"""Fixtures for the rink's draw pass and camera (plan 07) from recordings.

:func:`passes` decodes a recording (:mod:`rink_record`) pass by pass into
what the GDScript side needs: the state (:mod:`rink_state`), the
original's ``draw_frame`` and ``add_sprite_piece`` calls (the phase
handler's pieces apart: they are an input until plan 09), the finished
sprite list and a hash of each info plate's RAM tiles.

:func:`draw_fixture` samples passes that together show every kind of
sprite the recordings have; :func:`camera_fixture` keeps runs of
consecutive passes with what the camera reads. Both write fields,
addresses and hashes only.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from .rink_record import REC_DIR, STANDARD_RUNS, load
from .rink_state import decode, sprite_list
from .rom import Rom, default_rom_path

FIXTURES = Path(__file__).resolve().parents[2] / "compare" / "fixtures"
RUNS = list(STANDARD_RUNS)
WORD = 0xFFFF


def _call(c: list[int]) -> list[int]:
    """[ret, d0, d1, d2, d3, a5] -> [x, y, depth, attr, address] (words)."""
    s16 = lambda v: ((v & WORD) ^ 0x8000) - 0x8000
    return [s16(c[1]), s16(c[2]), c[3] & WORD, c[4] & WORD, c[5] & 0xFFFFFF]


def _split(entries: list) -> tuple[list, list]:
    """Calls outside / inside the phase handler's markers."""
    outside, inside, inph = [], [], False
    for e in entries:
        if e[0] == "phase":
            inph = e[1] == 0
            continue
        if e[0] == "tick":
            continue
        (inside if inph else outside).append(_call(e))
    return outside, inside


def passes(name: str, folder: Path = REC_DIR, every: int = 1):
    header, recs, calls = load(folder / f"{name}.jsonl.gz")
    regions = {k: tuple(v) for k, v in header["regions"].items()}
    rom = Rom.load(default_rom_path()).data
    for r in recs[::every]:
        n = r["pass"]
        drw, drw_phase = _split(calls["drw"].get(n, []))
        pcs, pcs_phase = _split(calls["pcs"].get(n, []))
        ticks = [e[1] for e in calls["drw"].get(n, []) if e[0] == "tick"]
        state = decode(regions, r["ram"], rom)
        if ticks:
            state["tick"] = ticks[0]      # the tick while the arrows were drawn
        plates = [hashlib.sha1(r["ram"]["plates"][256 * i:256 * (i + 1)]).hexdigest()[:16] for i in range(4)]
        yield {"name": f"{name}#{n}", "pass": n, "screen": r["screen"], "visit": r["visit"], "e": r["e"],
               "state": state, "calls": drw, "phase_calls": drw_phase,
               "adds": pcs, "phase_adds": pcs_phase, "sprites": sprite_list(r["ram"]), "plates": plates}


def features(p: dict) -> set[str]:
    """What a pass shows (for picking a varied sample)."""
    s = p["state"]
    f = {f"phase{s['phase']}", f"stadium{s['stadium']}", f"net{s['nets'][0]['style']}"}
    frames = {c[4] for c in p["calls"]}
    f |= {f"frame{a:x}" for a in frames & {0x3C8A4, 0x3C8CC, 0x3C25C, 0x20370, 0x3C88A, 0x3DC6C}}
    for t in s["teams"]:
        for pl in t["players"]:
            if pl["present"]:
                if pl["state"] in (4, 0x11, 0x12, 0x13):
                    f.add(f"state{pl['state']}")
                if pl["motion"][2]:
                    f.add("airborne")
    f |= {f"obj{o['kind']}" for o in s["objects"] if o["kind"]}
    f |= {f"haz{h[2]}" for h in s["hazards"] if h[2]}
    if any(c[2] == 0x7FFF for c in p["calls"]):
        f.add("arrow")
    if any(c[2] == 0xFFFF for c in p["calls"]):
        f.add("top")
    if p["phase_adds"]:
        f.add("phase_sprites")
    if len(p["adds"]) - len(p["phase_adds"]) > 79 or len(p["sprites"]) >= 79:
        f.add("full")
    if s["camera"]["shake"]:
        f.add("shake")
    if s["reserves"]:
        f.add("reserves")
    if s["puck"]["anim"][0] != 0x3C8D4:
        f.add("puck_drop")
    return f


def _slim(p: dict) -> dict:
    out = {k: p[k] for k in ("name", "visit", "e", "state", "phase_adds", "calls", "adds", "sprites", "plates")}
    return out


def draw_fixture(runs=RUNS, per_run: int = 4, folder: Path = REC_DIR) -> dict:
    picked, setups = [], []
    for name in runs:
        seen: set[str] = set()
        allp = list(passes(name, folder))
        # passes whose phase changed during the pass are left out: the
        # recording only has the phase after it, the drawing saw the one before
        cands = [p for q, p in zip(allp, allp[1:]) if p["state"]["phase"] == q["state"]["phase"]]
        chosen = []
        while len(chosen) < per_run:
            best = max(cands, key=lambda c: len(features(c) - seen))
            gain = features(best) - seen
            if not gain:
                break
            seen |= gain
            chosen.append(best)
        picked += [_slim(c) for c in chosen]
        first = allp[0]["state"]
        setups.append({"name": name, "stadium": first["stadium"], "nets": first["nets"], "hazards": first["hazards"],
                       "objects": first["objects"], "lamps": first["lamps"], "impale": first["impale"]})
    return {"description": "Rink draw pass (plan 07): recorded passes of the original (BlastEm) - the "
                           "drawing state, the phase handler's pieces, and what the original drew: draw_frame "
                           "and add_sprite_piece calls [x, y, depth, attr, ROM address], the sprite list in link "
                           "order [x, y, size, attr, depth] and a hash of each RAM info plate; and per recording the "
                           "rink objects of its first pass (the stadium set-up). "
                           "harness: python -m mw_harness rink-fixtures", "passes": picked, "setups": setups}


def _camera_pass(before: dict, p: dict) -> dict:
    s, b = p["state"], before["state"]
    tgt = s["camera"]["target"]
    tm = None
    if tgt:
        if tgt["kind"] == "puck":
            tm = s["puck"]["motion"]
        elif tgt["kind"] == "player":
            tm = s["teams"][tgt["team"]]["players"][tgt["slot"]]["motion"]
        elif tgt["kind"] == "ref":
            tm = s["ref"]["motion"]
    keys = ("x", "y", "speed", "lead", "shake", "amp", "shake_16", "shown")
    return {"e": p["e"], "phase_before": b["phase"], "phase": s["phase"], "subphase": s["subphase"],
            "before": {k: b["camera"][k] for k in keys}, "after": {k: s["camera"][k] for k in keys},
            "target": tgt, "previous_target": b["camera"]["target"], "target_motion": tm,
            "puck_flags": s["puck"]["flags"], "carrier": s["puck"]["carrier"],
            "flags4": [t["flags4"] for t in s["teams"]], "flags5": [t["flags5"] for t in s["teams"]],
            "fighting": [pl["flags"] & 0x10 for pl in s["teams"][0]["players"]]}


def camera_fixture(runs=RUNS, length: int = 40, folder: Path = REC_DIR) -> dict:
    """Per run: the first passes of play after the first faceoff, and the
    passes around the first camera shake (if any)."""
    seqs = []
    for name in runs:
        ps = list(passes(name, folder))
        pairs = [(ps[i - 1], ps[i]) for i in range(1, len(ps)) if ps[i]["visit"] == ps[i - 1]["visit"]]
        start = next(i for i, (b, p) in enumerate(pairs) if p["state"]["phase"] == 0)
        windows = [(start - 5, start - 5 + length)]
        shake = next((i for i, (b, p) in enumerate(pairs) if p["state"]["camera"]["shake"] > b["state"]["camera"]["shake"]), None)
        if shake is not None:
            windows.append((shake - 3, shake + 12))
        for a, z in windows:
            seqs.append({"name": f"{name}#{pairs[a][1]['pass']}", "passes": [_camera_pass(b, p) for b, p in pairs[a:z]]})
    return {"description": "Rink camera (plan 07): runs of consecutive passes recorded from the original "
                           "(BlastEm): elapsed ticks, the phase before and after the pass, the camera before and "
                           "after, what it followed (and its motion), and the puck and team flags the choice reads. "
                           "harness: python -m mw_harness rink-fixtures", "sequences": seqs}


def write_all(folder: Path = REC_DIR, out: Path = FIXTURES) -> None:
    (out / "rink_draw.json").write_text(json.dumps(draw_fixture(folder=folder), separators=(",", ":")) + "\n")
    (out / "rink_camera.json").write_text(json.dumps(camera_fixture(folder=folder), separators=(",", ":")) + "\n")


def dump(name: str, out: Path, every: int = 1) -> int:
    """All passes of a recording as JSON (local checks and the rink scene's
    playback, ``out/rink/dec/``)."""
    ps = [_slim(p) for p in passes(name, every=every)]
    out.write_text(json.dumps({"passes": ps}, separators=(",", ":")))
    return len(ps)


def main(args) -> None:
    """``rink-record`` / ``rink-fixtures`` / ``rink-dump`` (docs/compare.md, Rink)."""
    from .rink_record import record_standard
    if args.cmd == "rink-record":
        for name in args.names or RUNS:
            print(record_standard(name))
    elif args.cmd == "rink-dump":
        (REC_DIR / "dec").mkdir(parents=True, exist_ok=True)
        for name in args.names or RUNS:
            print(name, dump(name, REC_DIR / "dec" / f"{name}.json", args.every))
    else:
        write_all()
        print(FIXTURES / "rink_draw.json", FIXTURES / "rink_camera.json")
