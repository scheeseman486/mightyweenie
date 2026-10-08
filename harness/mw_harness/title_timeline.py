"""Timeline of screen 0 (developer logo, title, credits) in the original.

Traces the original in BlastEm with breakpoints on screen 0's milestones
(docs/re/title.md) and reports their ticks relative to entering screen 0:
once without input, once with a press in each part (logo, title, credits).
The result is ``compare/fixtures/title_timeline.json`` (ticks only, no ROM
content); our title scene is tested against it (game/test/flow).

    tools/bin/py -m mw_harness title-timeline [--update]
"""
from __future__ import annotations

import json
from pathlib import Path

from .emulator import InputScript
from .rom import REPO_ROOT
from .trace import Probe, run_trace

FIXTURE = REPO_ROOT / "compare" / "fixtures" / "title_timeline.json"
TICK = "[0xffca56].l"

# milestone -> code address (the probe fires when the 68000 gets there)
MILESTONES = {
    "entry": 0x0FF0,          # screen_00_title
    "logo_start": 0x1014,     # logo loop starts timing (fade-in already running)
    "logo_end": 0x104E,       # 180 ticks or a press: dev_logo_hide
    "title_start": 0x105C,    # title loaded (title_band_init next)
    "title_fade_in": 0x10CE,  # first pass: lines 0/1 fade in
    "title_fade_out": 0x1122, # 2100 ticks or a press: full fade-out
    "credits": 0x0E5E,        # credits_run
    "page": 0x0EB6,           # a page starts (D4 = 18 .. 0)
    "page_fade_in": 0x0EDC,   # its lines fade in
    "page_fade_out": 0x0F40,  # its lines fade out
    "credits_end": 0x0F74,    # music fade + full fade-out
    "credits_done": 0x0F98,   # back to run_screens -> main menu
    "menu": 0x136DE,          # screen_01_main_menu
}

# presses for the skip run: (ticks after entry, button), one per part
SKIPS = [(100, "START"), (1000, "A"), (3000, "C")]


def _probes() -> list[Probe]:
    return [Probe(a, k, [TICK, "d4"] if k == "page" else [TICK]) for k, a in MILESTONES.items()]


def _timeline(events) -> dict:
    """Milestone ticks relative to the first entry; pages as a list of
    [start, fade_in, fade_out] (fewer when skipped)."""
    out: dict = {"pages": []}
    t0 = None
    for e in events:
        tick = e.values[0]
        if e.label == "entry":
            if t0 is not None:
                break             # a second visit (not traced here)
            t0 = tick
            out["entry_frame"] = e.frame
        if t0 is None:
            continue
        t = tick - t0
        if e.label == "page":
            assert 18 - e.values[1] == len(out["pages"]), "pages out of order"
            out["pages"].append([t])
        elif e.label in ("page_fade_in", "page_fade_out"):
            out["pages"][-1].append(t)
        elif e.label not in out:
            out[e.label] = t
    return out


def measure(rom=None) -> dict:
    plain = _timeline(run_trace(_probes(), 6500, InputScript(), rom=rom))
    f0 = plain.pop("entry_frame")
    # A press is held for 2 frames: the game samples "newly pressed" per pass.
    presses = InputScript([(f0 + t, f0 + t + 1, b) for t, b in SKIPS])
    skip = _timeline(run_trace(_probes(), f0 + SKIPS[-1][0] + 200, presses, rom=rom))
    skip.pop("entry_frame", None)
    return {
        "format": "mw-title-timeline/1",
        "comment": "Ticks after entering screen 0 in the original (BlastEm, stock NTSC), "
                   "from mw_harness title-timeline; docs/re/title.md. No ROM content.",
        "no_input": plain,
        "skips": {"presses": [{"tick": t, "button": b} for t, b in SKIPS], "events": skip},
    }


def dumps(data: dict) -> str:
    """JSON with one line per run (pages stay on one line each)."""
    lines = ["{"]
    keys = list(data)
    for i, k in enumerate(keys):
        comma = "," if i < len(keys) - 1 else ""
        lines.append(f" {json.dumps(k)}: {json.dumps(data[k])}{comma}")
    return "\n".join(lines) + "\n}\n"


def main(update: bool = False) -> None:
    data = measure()
    text = dumps(data)
    if update:
        FIXTURE.write_text(text)
        print(f"wrote {FIXTURE.relative_to(REPO_ROOT)}")
    else:
        print(text)
        if FIXTURE.exists() and json.loads(FIXTURE.read_text()) != data:
            print("differs from", FIXTURE.relative_to(REPO_ROOT))
