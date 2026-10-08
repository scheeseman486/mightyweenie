"""Rink recordings of the original (plan 07, docs/re/rink.md).

Plays a match on the original in BlastEm and keeps, for every pass of the
rink loop (screens 4-6):

* the pass's elapsed ticks (``$F96E``: D0 after the tick wait);
* the RAM the drawing reads, dumped at ``$FB16`` (all drawing done, just
  before the sprite list is queued): the plane B object, the rink state,
  puck, both teams, overlays, the info-plate tiles, the finished sprite
  list and a few globals;
* every ``draw_frame`` call (``$A07E``: return address, D0 x, D1 y, D2
  depth, D3 attr, A5 frame) and every ``add_sprite_piece`` call (``$156C6``:
  the same with A5 = the piece) of the pass, in order, with markers around
  the phase handler's share (``$FA9C``-``$FAA0``, ``bsr $FC58``).

The recording is local (``out/``): it holds RAM, and the plate tiles are
pixels made from the ROM's font. Fixtures are built from it by
:mod:`rink_fixtures` (fields, addresses and hashes only).

Setups poke the main menu's bytes (``$FFB0DE``-``$FFB0E7``) before Start;
pad 1 can be driven by a seeded random walk (``human=True``).
"""
from __future__ import annotations

import gzip
import json
import random
from pathlib import Path

from .blastem_live import LiveBlastEm
from .rom import Rom, default_rom_path

VBLANK = 0x13F96
SCREEN_CALL = 0x20AC
PASS_START = 0xF96E          # after the tick wait; D0 = elapsed ticks
PASS_END = 0xFB16            # jsr $157B0 (queue the sprite list)
DRAW_FRAME = 0xA07E
ADD_PIECE = 0x156C6
PHASE_CALL = 0xFA9C          # bsr $FC58 (phase handler)
PHASE_DONE = 0xFAA0
MARK = 0xFFFFFFFF            # + pass number: a pass starts
MARK_PHASE = 0xFFFFFFFE      # + 0: phase handler starts, + 1: it returned
MARK_TICK = 0xFFFFFFFD       # + tick counter: an off-screen arrow is drawn ($4B14; a goalie's blinks)
ARROW = 0x4B14
ENTRY = 6                    # values per logged call

#: RAM dumped at every pass end: name -> (address, bytes).
REGIONS = {
    "objects": (0xFFB0B2, 0xD10),      # plane B obj, window obj, rink state, puck, teams, overlays
    "setup": (0xFFB0DC, 0x0C),
    "clock": (0xFFB060, 0x20),         # game clock $B066 (+4 seconds, +$10 period), $B077 flags, power play $B078
    "icons": (0xFFC2DC, 0x100),        # $C2DC .. ($C3C8 overlay is in "icons2")
    "icons2": (0xFFC3C8, 0x14),
    "faceoff": (0xFFC2F0, 0x30),       # $C2F2 clock .. $C31D faceoff spot
    "rules": (0xFFC3E0, 0x10),         # $C3E2 puck-rule state (the stoppage icon)
    "plates": (0xFFBE80, 0x400),
    "sprites": (0xFFE164, 0x280),
    "depths": (0xFFE3E4, 0x140),
    "count": (0xFFE524, 4),
    "phase": (0xFFC604, 0x0C),         # $C606 fade, $C608 replay, $C60A phase, $C60C subphase
    "proj": (0xFFBDB8, 4),             # $FFBDBA projection mode
    "tick": (0xFFCA56, 4),
    "snap": (0xFFC5FE, 4),
}
#: The recordings the rink fixtures come from (rink_fixtures.RUNS): name ->
#: (setup bytes poked on the main menu, pad 1 random walk, passes). Team A
#: picks the stadium (it follows team A); pads mode 5 = CPU vs CPU.
STANDARD_RUNS = {
    "demo_s4": ({0xFFB0E0: 5, 0xFFB0DE: 4, 0xFFB0DF: 1, 0xFFB0E4: 4, 0xFFB0E6: 1}, False, 3000),
    "human_s9": ({0xFFB0DE: 9, 0xFFB0DF: 3, 0xFFB0E4: 9, 0xFFB0E6: 1}, True, 3000),
    "demo_s10": ({0xFFB0E0: 5, 0xFFB0DE: 10, 0xFFB0DF: 16, 0xFFB0E4: 10, 0xFFB0E6: 0}, False, 3000),
    "human_s14": ({0xFFB0DE: 14, 0xFFB0DF: 2, 0xFFB0E4: 14, 0xFFB0E6: 1}, True, 4000),
    "demo_s3": ({0xFFB0E0: 5, 0xFFB0DE: 3, 0xFFB0DF: 12, 0xFFB0E4: 3}, False, 4000),
    "demo_s22": ({0xFFB0E0: 5, 0xFFB0DE: 22, 0xFFB0DF: 20, 0xFFB0E4: 22, 0xFFB0E6: 1}, False, 4000),
}
REC_DIR = Path(__file__).resolve().parents[2] / "out" / "rink"


def _exprs() -> list[tuple[str, int, int]]:
    out = []
    for name, (a, n) in REGIONS.items():
        for i in range(0, n, 4):
            out.append((name, i, a + i))
    return out


def record(name: str, setup: dict[int, int], passes: int, out: Path, human: bool = False, seed: int = 1,
           rom: Path | None = None, start_delay: int = 30) -> Path:
    """Record ``passes`` rink passes after Start on the main menu with
    ``setup`` (address -> byte) poked. Writes ``out`` (gzipped JSON lines)."""
    rom = Path(rom) if rom else default_rom_path()
    rng = random.Random(seed)
    exprs = _exprs()
    out.parent.mkdir(parents=True, exist_ok=True)
    header = {"format": "mw-rink/1", "name": name, "rom_sha1": Rom.load(rom).sha1, "setup": {hex(k): v for k, v in setup.items()},
              "human": human, "seed": seed, "regions": {k: [v[0], v[1]] for k, v in REGIONS.items()}}
    lines = [json.dumps(header)]
    with LiveBlastEm(rom) as bl:
        bl.breakpoint(SCREEN_CALL)
        vb_id = None
        screen = -1
        # 1. to the main menu, poke, Start
        while screen != 1:
            bl.cont()
            screen = bl.read("[0xffb05e].w")[0]
        for a, v in setup.items():
            bl.write(a, v, "b")
        bl.breakpoint(VBLANK)
        vb_id = max(k for k, v in bl.breakpoints.items() if v == VBLANK)
        for i in range(start_delay + 8):
            bl.cont()
            if i == start_delay:
                bl.press(1, "START")
            elif i == start_delay + 6:
                bl.release(1, "START")
        bl.command(f"delete {vb_id}")
        del bl.breakpoints[vb_id]
        # 2. the match
        bl.breakpoint(PASS_START)
        bl.breakpoint(PASS_END)
        logging = False
        held: set[str] = set()
        n = 0
        pending: dict | None = None
        vb = None            # VBlank breakpoint id while outside the rink
        ticks = 0
        start_down = False
        while n < passes:
            a = bl.cont()
            if a == SCREEN_CALL:
                scr, tick = bl.read("[0xffb05e].w", "[0xffca56].l")
                lines.append(json.dumps({"event": "screen", "screen": scr, "tick": tick}))
                if scr in (4, 5, 6):
                    if vb is not None:
                        bl.command(f"delete {vb}")
                        del bl.breakpoints[vb]
                        vb = None
                    if start_down:
                        bl.release(1, "START")
                        start_down = False
                elif vb is None:
                    if held:
                        bl.release(1, *sorted(held))
                        held = set()
                    bl.breakpoint(VBLANK)
                    vb = max(k for k, v in bl.breakpoints.items() if v == VBLANK)
                    ticks = 0
                continue
            if a == VBLANK:
                # scoreboards wait for Start: press it now and then
                ticks += 1
                if ticks % 40 == 0:
                    bl.press(1, "START")
                    start_down = True
                elif ticks % 40 == 6 and start_down:
                    bl.release(1, "START")
                    start_down = False
                continue
            if a == PASS_START:
                if not logging:
                    bl.log_at(DRAW_FRAME, "drw", "[a7].l", "d0", "d1", "d2", "d3", "a5")
                    bl.log_at(ADD_PIECE, "pcs", "[a7].l", "d0", "d1", "d2", "d3", "a5")
                    for at, k in ((PHASE_CALL, 0), (PHASE_DONE, 1)):
                        bl.on_hit(at, [f"append {arr} {v}" for arr in ("drw", "pcs") for v in (MARK_PHASE, k)])
                    bl.on_hit(ARROW, [f"append drw {MARK_TICK}", "append drw [0xffca56].l"])
                    logging = True
                e, scr = bl.read("d0", "[0xffb05e].w")
                for arr in ("drw", "pcs"):
                    bl.command(f"append {arr} {MARK}")
                    bl.command(f"append {arr} {n}")
                pending = {"pass": n, "screen": scr, "e": e & 0xFFFF}
                continue
            if a == PASS_END and pending is not None:
                vals: list[int] = []
                for i in range(0, len(exprs), 40):
                    vals += bl.read(*[f"[0x{x[2]:x}].l" for x in exprs[i:i + 40]])
                ram: dict[str, bytearray] = {k: bytearray() for k in REGIONS}
                for (rname, _, _), v in zip(exprs, vals):
                    ram[rname] += v.to_bytes(4, "big")
                pending["ram"] = {k: bytes(v[:REGIONS[k][1]]).hex() for k, v in ram.items()}
                lines.append(json.dumps(pending))
                pending = None
                n += 1
                if n % 250 == 0:
                    print("pass", n, flush=True)
                if human:
                    want = set(held)
                    if rng.random() < 0.15:
                        want = {rng.choice(["UP", "DOWN", "LEFT", "RIGHT", "UP", "DOWN"])}
                        if rng.random() < 0.5:
                            want.add(rng.choice(["LEFT", "RIGHT"]))
                    for b in ("A", "B", "C"):
                        want.discard(b)
                        if rng.random() < 0.06:
                            want.add(b)
                    down, up = want - held, held - want
                    if down:
                        bl.press(1, *sorted(down))
                    if up:
                        bl.release(1, *sorted(up))
                    held = want
        tmp = out.with_suffix(".arr")
        arrays = {k: bl.array(k, tmp) for k in ("drw", "pcs")}
        tmp.unlink(missing_ok=True)
    # split the call logs by pass; the phase handler's calls get a marker entry
    for k, arr in arrays.items():
        per: dict[int, list] = {}
        cur = None
        i = 0
        while i < len(arr):
            if arr[i] == MARK and i + 1 < len(arr):
                cur = arr[i + 1]
                per[cur] = []
                i += 2
                continue
            if arr[i] == MARK_PHASE and i + 1 < len(arr):
                if cur is not None:
                    per[cur].append(["phase", arr[i + 1]])
                i += 2
                continue
            if arr[i] == MARK_TICK and i + 1 < len(arr):
                if cur is not None:
                    per[cur].append(["tick", arr[i + 1]])
                i += 2
                continue
            if cur is not None and i + ENTRY <= len(arr):
                per[cur].append(arr[i:i + ENTRY])
            i += ENTRY
        lines.append(json.dumps({"event": "calls", "kind": k, "passes": {str(p): v for p, v in per.items()}}))
    with gzip.open(out, "wt") as f:
        f.write("\n".join(lines) + "\n")
    return out


def record_standard(name: str, folder: Path = REC_DIR) -> Path:
    """One of :data:`STANDARD_RUNS` into ``folder/NAME.jsonl.gz`` (about 90 s)."""
    setup, human, n = STANDARD_RUNS[name]
    seed = sum(name.encode()) & 0xFFFF
    return record(name, setup, n, folder / f"{name}.jsonl.gz", human=human, seed=seed)


def load(path: Path) -> tuple[dict, list[dict], dict[str, dict[int, list]]]:
    """Header, pass records (with ``ram`` as bytes per region and ``visit``,
    the number of the screen entry they belong to) and calls."""
    with gzip.open(path, "rt") as f:
        rows = [json.loads(l) for l in f if l.strip()]
    header, recs, calls = rows[0], [], {}
    visit = 0
    for r in rows[1:]:
        if r.get("event") == "calls":
            calls[r["kind"]] = {int(p): v for p, v in r["passes"].items()}
        elif r.get("event") == "screen":
            visit += 1
        elif "pass" in r:
            r["ram"] = {k: bytes.fromhex(v) for k, v in r["ram"].items()}
            r["visit"] = visit
            recs.append(r)
    return header, recs, calls
