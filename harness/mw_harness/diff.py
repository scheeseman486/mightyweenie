"""Compare two pass records (mw-pass/1) and report the first difference.

Records are lined up by (screen, visit, pass), starting from the first visit
of the record that starts later; see docs/compare.md.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .probes import BUILTIN, ProbeSet


@dataclass
class Visit:
    screen: int
    visit: int
    entry_tick: int
    passes: list[dict] = field(default_factory=list)


@dataclass
class DiffResult:
    ok: bool
    kind: str = ""                 # "flow" | "passes" | "field"
    screen: int = -1
    visit: int = -1
    pass_index: int = -1
    fields: list[tuple[str, object, object]] = field(default_factory=list)
    context: list[tuple[dict | None, dict | None]] = field(default_factory=list)
    compared_visits: int = 0
    compared_passes: int = 0

    def summary(self) -> str:
        if self.ok:
            return f"match: {self.compared_visits} visits, {self.compared_passes} passes"
        where = f"screen {self.screen} visit {self.visit}"
        if self.kind == "flow":
            a, b = self.fields[0][1], self.fields[0][2]
            return f"first difference: screen flow at visit #{self.compared_visits + 1}: {a} vs {b}"
        if self.kind == "passes":
            return f"first difference: {where}: pass count {self.fields[0][1]} vs {self.fields[0][2]}"
        diffs = ", ".join(f"{n} {a} vs {b}" for n, a, b in self.fields)
        return f"first difference: {where} pass {self.pass_index}: {diffs}"

    def report(self, labels=("A", "B")) -> str:
        lines = [self.summary()]
        if self.context:
            lines.append(f"  previous passes ({labels[0]} | {labels[1]}):")
            for a, b in self.context:
                lines.append(f"    {_short(a)} | {_short(b)}")
        return "\n".join(lines)


def _short(r: dict | None) -> str:
    if r is None:
        return "-"
    keep = {k: v for k, v in r.items() if k not in ("screen", "visit", "site")}
    return " ".join(f"{k}={v}" for k, v in keep.items())


def visits(records: list[dict]) -> list[Visit]:
    out: list[Visit] = []
    by_key: dict[tuple[int, int], Visit] = {}
    for r in records:
        ev = r.get("event")
        if ev == "screen":
            v = Visit(r["screen"], r["visit"], r["tick"])
            out.append(v)
            by_key[(v.screen, v.visit)] = v
        elif ev is None and "pass" in r:
            v = by_key.get((r["screen"], r["visit"]))
            if v is not None:
                v.passes.append(r)
    return out


def _rebase(a: list[Visit], b: list[Visit]) -> tuple[list[Visit], list[Visit]]:
    if not a or not b or a[0].screen == b[0].screen:
        return a, b
    for i, v in enumerate(a):
        if v.screen == b[0].screen:
            return a[i:], b
    for i, v in enumerate(b):
        if v.screen == a[0].screen:
            return a, b[i:]
    return a, b


def _value(rule, name: str, rec: dict, visit: Visit):
    v = rec.get(name)
    if v is None:
        return None
    if rule == "relative":
        return v - visit.entry_tick
    if rule == "held":
        return [w >> 8 for w in v]
    return v


def _equal(rule, a, b) -> bool:
    if isinstance(rule, dict) and "tolerance" in rule:
        return a is not None and b is not None and abs(a - b) <= rule["tolerance"]
    return a == b


def diff(a_records: list[dict], b_records: list[dict], probes: list[ProbeSet], context: int = 3) -> DiffResult:
    fields = [f for ps in probes for f in ps.fields if f.compare != "ignore"]
    A, B = _rebase(visits(a_records), visits(b_records))
    res = DiffResult(ok=True)
    n = min(len(A), len(B))
    for k in range(n):
        va, vb = A[k], B[k]
        if va.screen != vb.screen:
            return DiffResult(False, "flow", va.screen, va.visit, -1,
                              [("screen", va.screen, vb.screen)], [], res.compared_visits, res.compared_passes)
        last = k == n - 1          # a run may stop in the middle of its last visit
        if len(va.passes) != len(vb.passes) and not last:
            m = min(len(va.passes), len(vb.passes))
            ctx = [(va.passes[i], vb.passes[i]) for i in range(max(0, m - context), m)]
            return DiffResult(False, "passes", va.screen, va.visit, m,
                              [("passes", len(va.passes), len(vb.passes))], ctx,
                              res.compared_visits, res.compared_passes)
        for i, (ra, rb) in enumerate(zip(va.passes, vb.passes)):
            bad = []
            for f in fields:
                if not f.applies(va.screen):
                    continue
                x, y = _value(f.compare, f.name, ra, va), _value(f.compare, f.name, rb, vb)
                if not _equal(f.compare, x, y):
                    bad.append((f.name, x, y))
            if bad:
                ctx = [(va.passes[j], vb.passes[j]) for j in range(max(0, i - context), i)]
                return DiffResult(False, "field", va.screen, va.visit, i, bad, ctx,
                                  res.compared_visits, res.compared_passes)
            res.compared_passes += 1
        res.compared_visits += 1
    return res
