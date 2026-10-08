"""Team description cases: the original's page moves and selection, pass by pass.

Records each ``compare/scripts/td_*.mwi`` on the original (BlastEm, cached
like ``record``) with the ``team_description`` probes and keeps, per visit of
screen 2, the passes where the plane's vscroll, the side (team A / B), the
roster cursor or line changed: ``[tick from the visit's entry, vscroll, side,
cursor, line]``. ``compare/fixtures/team_description.json`` (numbers only, no
ROM content); game/test/flow/test_team_description.gd plays the same scripts
on our screen and checks it shows the same states at the same ticks.

    tools/bin/py -m mw_harness td-cases [--update] [NAME ...]
"""
from __future__ import annotations

import json

from .record import read
from .rom import REPO_ROOT

FIXTURE = REPO_ROOT / "compare" / "fixtures" / "team_description.json"
SCRIPTS = REPO_ROOT / "compare" / "scripts"
PROBES = "time,input,screen,team_description"
FIELDS = ("vscroll", "side", "cursor", "line")


def summarise(records: list[dict]) -> dict:
    history: list[int] = []
    visits: list[dict] = []
    entry = 0
    last = None
    for r in records:
        if r.get("event") == "screen":
            history.append(r["screen"])
            entry = r["tick"]
            last = None
            if r["screen"] == 2:
                visits.append({"visit": r["visit"], "states": []})
        elif "pass" in r and r.get("screen") == 2 and visits and "vscroll" in r:
            state = [r[f] for f in FIELDS]
            if state != last:
                visits[-1]["states"].append([r["tick"] - entry] + state)
                last = state
    return {"history": history, "visits": visits}


def measure(names=None) -> dict:
    from .__main__ import original_record

    cases = {}
    for path in sorted(SCRIPTS.glob("td_*.mwi")):
        if names and path.stem not in names:
            continue
        cases[path.stem] = summarise(read(original_record(path, PROBES)))
    return cases


def main(update: bool = False, names=None) -> None:
    cases = measure(names)
    old = json.loads(FIXTURE.read_text())["cases"] if FIXTURE.exists() else {}
    old.update(cases)
    data = {"format": "mw-td-cases/1",
            "comment": "Team description passes where vscroll, side, cursor or line changed: [tick from "
                       "the visit's entry, vscroll, side, cursor, line], from the original running "
                       "compare/scripts/td_*.mwi (mw_harness td-cases). No ROM content.",
            "cases": dict(sorted(old.items()))}
    text = "{\n" + ",\n".join(f" {json.dumps(k)}: {json.dumps(v)}" for k, v in data.items()) + "\n}\n"
    if update:
        FIXTURE.write_text(text)
        print(f"wrote {FIXTURE.relative_to(REPO_ROOT)}")
    else:
        print(text)
