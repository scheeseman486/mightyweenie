#!/usr/bin/env python3
"""Measure how many 60 Hz ticks each pass of the game's screen loops takes.

    tools/bin/py re/measure/loop_timing.py [--frames N] [--divider 7] [--input SCRIPT] [--json OUT]

Every screen loop ends in the same busy-wait: re-read tick_counter until it
changes; on exit D0 holds the ticks elapsed since the loop's snapshot. We put
a BlastEm breakpoint on the instruction after each of those waits (found in
plan 01 - see docs/re/timing.md) and log tick_counter, D0 and, for the
gameplay loop, the game phase word at $FFC60A.

--divider lowers the 68000 clock divider (7 = stock NTSC) to emulate an
overclocked CPU, which is how per-iteration (frame-tied) behaviour shows up.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "harness"))
from mw_harness.emulator import InputScript  # noqa: E402
from mw_harness.trace import Probe, run_trace  # noqa: E402

TICKS = "[0xffca56].l"
# exit address of each tick busy-wait -> (label, extra expressions)
WAIT_EXITS = {
    0x000DA6: ("wait_ticks", []),
    0x00103E: ("title", []),
    0x00108E: ("title_pages", []),
    0x008D7C: ("scoreboard", ["d6"]),          # screens 12-16
    0x009E70: ("fn_9dd0", []),
    0x00B1F4: ("matchup_intro", []),           # screen 3
    0x00D1F0: ("screen_09", []),
    0x00D8E6: ("fight", []),                   # screen 18
    0x00E43C: ("fn_e3a8", []),
    0x00E6CE: ("screen_17", []),
    0x00F96E: ("gameplay", ["[0xffc60a].w"]),  # screens 4-6
    0x011B9C: ("playoffs", []),                # screen 11
    0x0121EC: ("password", []),
    0x01295C: ("bracket", []),
    0x013AD0: ("screen_19", []),
}

# A regular game, P1 idle (CPU vs CPU-controlled teammates), pressing START
# on the main menu and at every scoreboard (frame numbers from a GPGX run;
# BlastEm boots ~4 frames later, so presses are held for a while).
DEFAULT_INPUT = ("6500-6505:START 16000-16005:START 24700-24705:START "
                 "33000-33005:START 44500-44505:START")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--frames", type=int, default=36000)
    ap.add_argument("--divider", type=int, default=7)
    ap.add_argument("--input", default=DEFAULT_INPUT)
    ap.add_argument("--json")
    a = ap.parse_args()

    probes = [Probe(addr, label, ["d0", TICKS, *extra]) for addr, (label, extra) in WAIT_EXITS.items()]
    events = run_trace(probes, a.frames, InputScript.parse(a.input), m68k_divider=a.divider, timeout=900)
    # For most loops D0 holds the elapsed ticks on exit. The title and matchup
    # loops compare against an absolute tick instead, so use the tick gap
    # between consecutive passes of the same loop for those.
    TICK_GAP = {"title", "matchup_intro"}
    per = defaultdict(Counter)
    phases = defaultdict(Counter)
    last_tick = {}
    for e in events:
        d0 = e.values[0] & 0xFFFF
        if e.label in TICK_GAP:
            prev, last_tick[e.label] = last_tick.get(e.label), e.values[1]
            if prev is None or not 0 < e.values[1] - prev < 30:
                continue
            d0 = e.values[1] - prev
        per[e.label][d0] += 1
        if e.label == "gameplay":
            phases[e.values[2] & 0xFFFF][d0] += 1
    print(f"68000 divider {a.divider}; {len(events)} loop passes in {a.frames} frames")
    print(f"{'loop':14s} {'passes':>7s} {'mean ticks':>10s} {'~fps':>6s}  histogram (ticks: passes)")
    out = {}
    for label, hist in sorted(per.items(), key=lambda kv: -sum(kv[1].values())):
        n = sum(hist.values()); mean = sum(k * v for k, v in hist.items()) / n
        top = ", ".join(f"{k}:{v}" for k, v in sorted(hist.items())[:8])
        print(f"{label:14s} {n:7d} {mean:10.2f} {60 / mean:6.1f}  {top}")
        out[label] = {str(k): v for k, v in sorted(hist.items())}
    if phases:
        print("gameplay by phase ($FFC60A):")
        for ph, hist in sorted(phases.items()):
            n = sum(hist.values()); mean = sum(k * v for k, v in hist.items()) / n
            print(f"   phase {ph:3d}: {n:6d} passes, mean {mean:.2f} ticks (~{60 / mean:.1f} fps): "
                  + ", ".join(f"{k}:{v}" for k, v in sorted(hist.items())[:8]))
        out["gameplay_by_phase"] = {str(p): {str(k): v for k, v in sorted(h.items())} for p, h in phases.items()}
    if a.json:
        Path(a.json).write_text(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
