"""Soak runs (plan 10): seeded matches of the original, back to back in
BlastEm faster than real time, with code coverage.

A run is a seed. :func:`config` turns it into the recorder's arguments - the
setup bytes (teams, stadium, pad mode, period length, penalties, reserves,
Death Index), the period minutes poked at the matchup, a poke of the main
random stream at the matchup (BlastEm's boot seed is fixed by its timing,
so without it equal setups play equal matches) and, in modes with human
pads, the recorder's seeded pad driver. :func:`run` plays it lean
(:func:`sim_record.record` with nothing recorded and a breakpoint on every
coverage target, deleted at its first hit) and writes
``out/soak/runs/<seed>.json``: the config, the screens with their ticks and
the tick and screen each target was first reached at. ``sim-record --soak
SEED --from-visit K`` records the run in full from its K-th rink visit,
with coverage of the recorded part: other breakpoints can change BlastEm's
timing slightly, so the recording may part from the soak run, and its own coverage map is what counts.

    tools/bin/py -m mw_harness soak targets [--refresh]
    python3 -m mw_harness.soak run ...      (PYTHONPATH=harness: stdlib only,
                                            e.g. on the desktop's own Python)
    tools/bin/py -m mw_harness soak run 1-40 [--budget 165] [--worker K/N] [--redo]
    tools/bin/py -m mw_harness soak report [--missing] [--all]
    tools/bin/py -m mw_harness soak pick [--count 10]

Targets: every function entry of the Ghidra database (addresses only,
cached in ``out/soak/targets.json``) and every labelled function
(``re/labels/functions.csv``).

Plan 11 (seeds from :data:`GEN2` on): the run is set up through the main
menu's rows by a :class:`tours.Tour`, which also plays every screen between
plays from its navigation model (:mod:`screen_models`) - the scoreboards'
stats, special plays and instant replays, the fight, passwords, the team
description - inputs no run has taken yet first (``bias``: the counts of
the runs so far, stored with the run). ``soak report --edges`` lists the
models' inputs never taken.
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import subprocess
import time
from pathlib import Path

from . import screen_models as sm
from . import sim_record as sr
from . import tours
from .playoffs import RANDOM_DEAD, State, decode_bits, pack
from .rom import REPO_ROOT

SOAK_DIR = REPO_ROOT / "out" / "soak"
RUN_DIR = SOAK_DIR / "runs"
TARGETS = SOAK_DIR / "targets.json"           # names (Ghidra's), local
FROZEN = REPO_ROOT / "compare" / "fixtures" / "soak_targets.json"
FROZEN2 = REPO_ROOT / "compare" / "fixtures" / "soak_targets_2.json"   # plan 11's runs (more labels)
#: Seeds from here are plan 11's: menus and tours.
GEN2 = 1000
#: Plan 11's seeds from here: fight styles (idle / forward fighters, for
#: knockouts) and more runs with people (fights need one).
GEN2_FIGHTS = 1300
#: Plan 11's seeds from here: the Monster Cup final played CPU vs CPU (pad
#: mode 5 poked) from a password, for the champion's screen (a person's
#: side seldom wins with the recorder's pad drivers).
GEN2_FINAL = 1400
#: Plan 11's seeds from here: special plays with both pages played in either
#: order (two-page pad modes only: P1 + P2, P3, P4).
GEN2_PAGES = 1500
MODES_PAGES = ((1, 0.5), (3, 0.25), (4, 0.25))
MODES_FIGHTS = ((5, 0.2), (0, 0.3), (1, 0.25), (2, 0.15), (4, 0.1))
#: Play modes `$FFB0E1` of plan 11's runs with people: regular, playoffs,
#: playoffs 2 of 3, Continue Playoffs (a password).
PLAYS = ((0, 0.78), (1, 0.08), (2, 0.06), (3, 0.08))
STOP = SOAK_DIR / "stop"              # its presence ends `soak run` between two runs
LABELS = REPO_ROOT / "re" / "labels" / "functions.csv"

#: Pad modes and their weights: 5 CPU vs CPU (fast: no stop per pass), the
#: others with the recorder's pad drivers on the human pads.
MODES = ((5, 0.6), (0, 0.15), (1, 0.1), (2, 0.1), (4, 0.05))
#: Period length rows: `$FFB0E2` index -> `$FFB0E3` minutes.
LENGTHS = ((0, 3, 0.45), (1, 5, 0.4), (2, 8, 0.15))
RINK_SCREENS = (4, 5, 6)


def config(seed: int, bias: dict[str, int] | None = None) -> dict:
    """The recorder's arguments for soak run ``seed`` (deterministic; plan
    11's seeds also take the tour's ``bias``)."""
    if seed >= GEN2:
        return config2(seed, bias)
    r = random.Random(seed * 7919 + 17)
    mode = r.choices([m for m, _ in MODES], [w for _, w in MODES])[0]
    a = r.randrange(23)
    b = r.randrange(22)
    b += b >= a
    index, minutes, _ = r.choices(LENGTHS, [w for *_, w in LENGTHS])[0]
    playoffs = mode != 5 and r.random() < 0.1
    setup = {0xFFB0E0: mode, 0xFFB0E1: 1 if playoffs else 0, 0xFFB0DE: a, 0xFFB0DF: b,
             0xFFB0E2: index, 0xFFB0E5: int(r.random() < 0.65), 0xFFB0E6: int(r.random() < 0.3),
             0xFFB0E7: r.randrange(5)}
    if not playoffs:                       # the playoffs use the home team's stadium
        setup[0xFFB0E4] = r.randrange(23)
    return {"seed": seed, "setup": setup, "late": {0xFFB0E3: minutes},
            "rng_poke": r.randrange(1, 1 << 32),
            "driver": r.choice(["match", "match", "pause", "goalie"]) if mode != 5 else "chase",
            "driver_seed": r.randrange(1 << 16),
            # a regular game ends back at the main menu; a playoff game at screen 16
            "stop_screens": (16,) if playoffs else (1,)}


def _password_ok(digits: list[int]) -> bool:
    n = 0
    for d in reversed(digits):
        n = n * 28 + d
    return len(digits) == sm.PASSWORD_LEN and decode_bits(n >> 32, n & 0xFFFFFFFF) is not None


def valid_password(r: random.Random, round_: int | None = None) -> list[int]:
    """A password the original takes (alphabet indices): a playoff run in
    one conference, any round (or ``round_``: 2 the Monster Cup), single
    games or best of 3."""
    while True:
        a = r.randrange(10)
        b = r.randrange(9)
        b += b >= a
        bo3 = int(r.random() < 0.4)
        st = State(seed=r.randrange(1, 4096), pair=a * 10 + b, conference=r.randrange(2), best_of_3=bo3,
                   round=r.randrange(4 if bo3 else 3) if round_ is None else round_, flags=RANDOM_DEAD,
                   dead_a=r.getrandbits(18) if r.random() < 0.3 else 0)
        try:
            d0, d1, _ = pack(st)
        except ValueError:
            continue
        digits = tours.password_digits(d0, d1)
        if _password_ok(digits):
            return digits


def _wrong_password(r: random.Random, n: int) -> list[int]:
    while True:
        d = [r.randrange(28) for _ in range(n)]
        if not _password_ok(d):
            return d


def config2(seed: int, bias: dict[str, int] | None = None) -> dict:
    """Plan 11's runs: the setup through the main menu's rows (pad mode 5
    poked: the menu cannot set it), excursions first, password plans, the
    tour's seed and detours per gap."""
    r = random.Random(seed * 104729 + 3)
    fights = seed >= GEN2_FIGHTS
    final = seed >= GEN2_FINAL
    modes = MODES_FIGHTS if fights else MODES
    mode = r.choices([m for m, _ in modes], [w for _, w in modes])[0]
    if final:
        mode = 5
    pages = seed >= GEN2_PAGES
    if pages:
        mode = r.choices([m for m, _ in MODES_PAGES], [w for _, w in MODES_PAGES])[0]
    human = mode != 5
    play = r.choices([p for p, _ in PLAYS], [w for _, w in PLAYS])[0] if human else 0
    if final and not pages:
        play = 3
    index, _, _ = r.choices(LENGTHS, [w for *_, w in LENGTHS])[0]
    menu = {3: play, 4: index, 7: int(r.random() < 0.65), 8: int(r.random() < 0.3), 9: r.randrange(5)}
    if human:
        menu[2] = mode
    if play == 0:
        a = r.randrange(23)
        b = r.randrange(22)
        b += b >= a
        menu[0], menu[1] = a, b
        if r.random() < 0.5:                 # else the stadium follows team A
            menu[6] = r.randrange(23)
    elif play in (1, 2):                     # one conference's teams
        a = r.randrange(20)
        b = r.randrange(9)
        b += b >= a % 10
        menu[0], menu[1] = a, a - a % 10 + b
    excursions, passwords = [], []
    if r.random() < 0.3:
        excursions.append("browse")
    if r.random() < 0.15:
        excursions.append("team_description")
    if human and r.random() < 0.06:
        excursions.append("password_cancel")
        passwords.append({"attempts": [{"digits": [r.randrange(28) for _ in range(r.randrange(1, 9))],
                                        "cancel": True}]})
    if play == 3:
        attempts = []
        if r.random() < 0.5:
            attempts.append({"digits": _wrong_password(r, 13), "valid": False})
        if r.random() < 0.3:
            attempts.append({"digits": [r.randrange(28) for _ in range(r.randrange(1, 13))], "valid": False})
        good = {"digits": valid_password(r, 2 if final and not pages else None), "valid": True}
        if r.random() < 0.4:
            good["mistake"] = r.randrange(13)
        attempts.append(good)
        passwords.append({"attempts": attempts})
    return {"seed": seed, "gen": 2, "setup": {0xFFB0E0: 5} if not human else {}, "late": {},
            "menu": menu, "excursions": excursions, "browse": r.randrange(4, 16), "passwords": passwords,
            "rng_poke": r.randrange(1, 1 << 32),
            "driver": r.choice(["match", "match", "pause", "pause", "goalie"]) if human else "chase",
            "driver_seed": r.randrange(1 << 16), "tour_seed": r.randrange(1 << 16),
            "detours": (0, r.choice([1, 2, 3])), "bias": dict(bias or {}), "fight_styles": fights,
            "pages_both": pages,
            # a regular game ends back at the main menu; a playoff game at the next matchup
            # (after the new password and the bracket) or the main menu (eliminated, champion)
            "stop_screens": (1,) if play == 0 else (3, 1)}


def describe(cfg: dict) -> str:
    if cfg.get("gen") == 2:
        m = cfg["menu"]
        mode = {5: "cpu", 0: "p1", 1: "p1p2", 2: "coop", 3: "p3", 4: "p4"}[m.get(2, 5)]
        play = {0: "", 1: " playoffs", 2: " playoffs 2/3", 3: " continue", 4: " td"}[m[3]]
        return (f"seed {cfg['seed']}: {mode}{play} teams {m.get(0, '-')}-{m.get(1, '-')} stadium {m.get(6, '-')}"
                f" length {m[4]} penalties {'on' if m[7] else 'off'} reserves {m[8]} death {m[9]}"
                f" {'+'.join(cfg['excursions']) or 'no excursions'} driver {cfg['driver'] if 2 in m else '-'}")
    s = cfg["setup"]
    mode = {5: "cpu", 0: "p1", 1: "p1p2", 2: "coop", 4: "p4"}[s[0xFFB0E0]]
    return (f"seed {cfg['seed']}: {mode}{' playoffs' if s[0xFFB0E1] else ''} teams {s[0xFFB0DE]}-{s[0xFFB0DF]}"
            f" stadium {s.get(0xFFB0E4, '-')} {cfg['late'][0xFFB0E3]} min"
            f" penalties {'on' if s[0xFFB0E5] else 'off'} reserves {s[0xFFB0E6]} death {s[0xFFB0E7]}"
            f" driver {cfg['driver'] if s[0xFFB0E0] != 5 else '-'}")


def record_args(cfg: dict) -> dict:
    """``sim_record.record`` keyword arguments for ``cfg``."""
    if cfg.get("gen") == 2:
        return {"setup": cfg["setup"], "seed": cfg["driver_seed"], "late": {}, "rng_poke": cfg["rng_poke"],
                "driver": cfg["driver"], "stop_screens": tuple(cfg["stop_screens"]),
                "tour": {"seed": cfg["tour_seed"], "menu": cfg["menu"], "excursions": cfg["excursions"],
                         "browse": cfg["browse"], "passwords": cfg["passwords"], "bias": cfg["bias"],
                         "detours": list(cfg["detours"]), "fight_styles": bool(cfg.get("fight_styles")),
                         "pages_both": bool(cfg.get("pages_both"))}}
    return {"setup": cfg["setup"], "seed": cfg["driver_seed"], "late": cfg["late"],
            "rng_poke": cfg["rng_poke"], "driver": cfg["driver"],
            "stop_screens": tuple(cfg["stop_screens"])}


# --- targets ------------------------------------------------------------------------

def labels() -> dict[int, tuple[str, str]]:
    """Labelled functions: address -> (name, comment)."""
    with open(LABELS) as f:
        return {int(r["address"], 16): (r["name"], r["comment"]) for r in csv.DictReader(f)}


def ghidra_functions() -> dict[int, str]:
    """Function entries of the Ghidra database (one JVM start, ~10 s)."""
    out = subprocess.run([str(REPO_ROOT / "tools" / "bin" / "py"), str(REPO_ROOT / "re" / "ghidra" / "gh.py"),
                          "funcs"], capture_output=True, text=True, check=True).stdout
    funcs = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            try:
                funcs[int(parts[0], 16)] = parts[1]
            except ValueError:
                continue
    return funcs


def targets(refresh: bool = False, gen: int = 1) -> dict[int, str]:
    """Coverage targets: address -> name (labels win over Ghidra's names).
    Only ROM code below the checksum area ($200-$1FFD5F). The address list is
    frozen in ``compare/fixtures/soak_targets.json`` (``--refresh``: Ghidra's
    functions and the labels again): the breakpoints a run sets are part of
    what it plays (see :func:`sim_record.record`), so the recordings of
    ``sim_record.SOAK_RUNS`` repeat only with the same list. Plan 11's runs
    (``gen`` 2) have their own list, ``soak_targets_2.json``, with the labels
    of plan 11's research."""
    frozen = FROZEN2 if gen == 2 else FROZEN
    if refresh or not frozen.exists():
        cache = {f"{a:06X}": n for a, n in sorted(ghidra_functions().items())}
        cache.update({f"{a:06X}": n for a, (n, _) in labels().items()})
        frozen.write_text(json.dumps({"format": "mw-soak-targets/1",
                                      "addresses": sorted(a for a in cache if 0x200 <= int(a, 16) < 0x1FFD60
                                                          and int(a, 16) % 2 == 0)}, indent=0) + "\n")
        SOAK_DIR.mkdir(parents=True, exist_ok=True)
        TARGETS.write_text(json.dumps(cache))
    names = json.loads(TARGETS.read_text()) if TARGETS.exists() else {}
    lab = labels()
    out = {}
    for a in json.loads(frozen.read_text())["addresses"]:
        x = int(a, 16)
        out[x] = lab[x][0] if x in lab else names.get(a, f"FUN_{a}")
    return out


# --- runs -----------------------------------------------------------------------------

def _stored(cfg: dict) -> dict:
    """``cfg`` as a run file keeps it (JSON: string keys)."""
    out = {**cfg, "setup": {f"{k:06X}": v for k, v in cfg["setup"].items()},
           "late": {f"{k:06X}": v for k, v in cfg["late"].items()}}
    if "menu" in cfg:
        out["menu"] = {str(k): v for k, v in cfg["menu"].items()}
    return out


def config_of(seed: int) -> dict:
    """The configuration a run was made with: plan 11's from its run file
    (the tour's bias was the runs' counts then), else :func:`config`."""
    f = RUN_DIR / f"{seed}.json"
    if seed < GEN2 or not f.exists():
        return config(seed)
    c = json.loads(f.read_text())["config"]
    c["setup"] = {int(k, 16): v for k, v in c["setup"].items()}
    c["late"] = {int(k, 16): v for k, v in c["late"].items()}
    c["menu"] = {int(k): v for k, v in c["menu"].items()}
    c["stop_screens"] = tuple(c["stop_screens"])
    c["detours"] = tuple(c["detours"])
    return c


def edge_counts(runs: list[dict]) -> dict[str, int]:
    """Inputs taken by plan 11's runs: ``screen:state:input`` -> count."""
    out: dict[str, int] = {}
    for r in runs:
        for k, v in (r.get("tour") or {}).items():
            out[k] = out.get(k, 0) + v
    return out


def run(seed: int, budget: float = 160.0, cover: dict[int, str] | None = None,
        bias: dict[str, int] | None = None) -> dict:
    """Soak run ``seed`` (lean, with coverage); returns and writes its summary."""
    cfg = config(seed, bias)
    cover = cover if cover is not None else targets(gen=2 if seed >= GEN2 else 1)
    t0 = time.monotonic()
    folder = RUN_DIR / str(seed)
    sr.record(f"soak_{seed}", passes=10 ** 9, out_dir=folder, budget=budget, coverage=cover,
              lean_until_visit=10 ** 9, **record_args(cfg))
    meta = json.loads((folder / "meta.json").read_text())
    screens = [[scr, tick] for _, scr, tick in meta["screens"]]
    stop = tuple(cfg["stop_screens"])
    summary = {"seed": seed, "config": _stored(cfg),
               "describe": describe(cfg), "screens": screens,
               "finished": bool(screens) and screens[-1][0] in stop,
               "seconds": round(time.monotonic() - t0, 1),
               "end": meta.get("end"), "hits": meta["coverage"]}
    if "tour" in meta:
        summary["tour"] = meta["tour"]["counts"]
        summary["tour_log"] = meta["tour"]["log"]
        summary["menu_setup"] = meta["tour"].get("menu_setup")
    (RUN_DIR / f"{seed}.json").write_text(json.dumps(summary))
    return summary


def visit_of(screens: list, tick: int) -> int:
    """The rink visit (1-based) running at ``tick``, 0 outside the rink."""
    visit, inside = 0, False
    for scr, t in screens:
        if t > tick:
            break
        inside = scr in RINK_SCREENS
        visit += inside
    return visit if inside else 0


def load_runs() -> list[dict]:
    return [json.loads(p.read_text()) for p in sorted(RUN_DIR.glob("*.json"), key=lambda p: int(p.stem))]


def coverage(runs: list[dict]) -> dict[int, dict]:
    """Address -> {"runs": count, "first": [seed, tick, screen, visit]} over ``runs``."""
    out: dict[int, dict] = {}
    for r in runs:
        for a, (tick, scr) in r["hits"].items():
            e = out.setdefault(int(a, 16), {"runs": 0, "first": None})
            e["runs"] += 1
            if e["first"] is None:
                e["first"] = [r["seed"], tick, scr, visit_of(r["screens"], tick)]
    return out


def pick(runs: list[dict], count: int, have: set[int] = frozenset()) -> list[tuple[int, int, list[int]]]:
    """Greedy picks of (seed, rink visit) whose visit reaches the most rink
    targets not in ``have``: [(seed, visit, new addresses)]."""
    cands: dict[tuple[int, int], set[int]] = {}
    for r in runs:
        for a, (tick, scr) in r["hits"].items():
            v = visit_of(r["screens"], tick)
            if v:
                cands.setdefault((r["seed"], v), set()).add(int(a, 16))
    done = set(have)
    out = []
    for _ in range(count):
        best = max(cands.items(), key=lambda kv: (len(kv[1] - done), -kv[0][0]), default=None)
        if best is None or not best[1] - done:
            break
        new = sorted(best[1] - done)
        out.append((best[0][0], best[0][1], new))
        done |= best[1]
    return out


def _seeds(spec: str) -> list[int]:
    out = []
    for part in spec.split(","):
        lo, _, hi = part.partition("-")
        out += list(range(int(lo), int(hi or lo) + 1))
    return out


def main(args) -> None:
    if args.what == "targets":
        t = targets(refresh=args.refresh, gen=args.gen or 1)
        print(len(t), "targets", f"({len(labels())} labelled)")
    elif args.what == "run":
        covers = {}
        bias = edge_counts([r for r in load_runs() if r["seed"] >= GEN2])
        t0 = time.monotonic()
        k, _, n = args.worker.partition("/")
        for seed in _seeds(args.seeds):
            if n and seed % int(n) != int(k):
                continue
            if not args.redo and (RUN_DIR / f"{seed}.json").exists():
                continue
            if STOP.exists():
                print("stop file", STOP)
                break
            left = args.budget - (time.monotonic() - t0)
            if left < 30:
                print("budget used up before seed", seed)
                break
            gen = 2 if seed >= GEN2 else 1
            if gen not in covers:
                covers[gen] = targets(gen=gen)
            s = run(seed, budget=min(left - 5, args.run_budget), cover=covers[gen], bias=bias)
            print(f"{s['describe']}: {len(s['hits'])} targets, {len(s['screens'])} screens,"
                  f" {'finished' if s['finished'] else 'cut'}, {s['seconds']} s", flush=True)
    elif args.what == "report":
        report(args)
    elif args.what == "pick":
        runs = load_runs()
        for seed, visit, new in pick(runs, args.count):
            names = targets()
            print(f"seed {seed} visit {visit}: +{len(new)}", ", ".join(names.get(a, f"{a:06X}") for a in new[:8]))


def report(args) -> None:
    runs = load_runs()
    if args.gen:
        runs = [r for r in runs if (r["seed"] >= GEN2) == (args.gen == 2)]
    if args.edges:
        edges = edge_counts(runs)
        keys = sm.edge_keys()
        print(f"{len(runs)} runs; inputs taken {len(edges)} ({sum(edges.values())} times);"
              f" model inputs never taken {len([k for k in keys if k not in edges])} / {len(keys)}")
        by: dict[str, list[str]] = {}
        for k in keys:
            if k not in edges:
                scr, state, label = k.split(":")
                by.setdefault(f"{scr}:{state}", []).append(label)
        for k, v in sorted(by.items(), key=lambda kv: (int(kv[0].split(":")[0]), kv[0])):
            print(f"  {k:24s} {', '.join(v)}")
        return
    names = targets(gen=args.gen or 1)
    lab = labels()
    cov = coverage(runs)
    hit = {a for a in names if a in cov}
    by_screen: dict[int, int] = {}
    for a in hit:
        by_screen[cov[a]["first"][2]] = by_screen.get(cov[a]["first"][2], 0) + 1
    print(f"{len(runs)} runs, {sum(r['seconds'] for r in runs):.0f} s;"
          f" {len(hit)} / {len(names)} targets reached ({len(hit & set(lab))} / {len(lab)} labelled)")
    print("first reached on screen:", ", ".join(f"{k}: {v}" for k, v in sorted(by_screen.items())))
    if args.missing:
        for a in sorted(set(names) - hit):
            if a in lab or args.all:
                n, c = lab.get(a, (names[a], ""))
                print(f"  {a:06X} {n:32s} {c[:80]}")


def add_arguments(sk: argparse.ArgumentParser) -> None:
    sk.add_argument("what", choices=["targets", "run", "report", "pick"])
    sk.add_argument("seeds", nargs="?", default="1", help="run: seeds, e.g. 1-20,25")
    sk.add_argument("--budget", type=float, default=165.0, help="run: seconds for all seeds")
    sk.add_argument("--run-budget", type=float, default=160.0, help="run: seconds at most per seed")
    sk.add_argument("--worker", default="", help="run: K/N - only the seeds with seed %% N == K")
    sk.add_argument("--redo", action="store_true", help="run: also seeds already run")
    sk.add_argument("--refresh", action="store_true", help="targets: re-read the Ghidra database")
    sk.add_argument("--missing", action="store_true", help="report: list the labelled targets never reached")
    sk.add_argument("--all", action="store_true", help="report --missing: Ghidra's unnamed ones too")
    sk.add_argument("--count", type=int, default=10, help="pick: how many (seed, visit) picks")
    sk.add_argument("--gen", type=int, default=0, help="report: only plan 10's (1) or plan 11's (2) runs")
    sk.add_argument("--edges", action="store_true", help="report: the screen models' inputs never taken")


if __name__ == "__main__":
    _p = argparse.ArgumentParser(description="soak runs with code coverage (plan 10)")
    add_arguments(_p)
    main(_p.parse_args())
