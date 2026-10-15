"""Load recordings (plan 36): what each part of the original's rink pass
costs the 68000, pass by pass.

A plan 08 simulation recording (:mod:`sim_record`, the same runs and pad
drivers, so the port's pass-for-pass tools read it) plus one debugger
array, ``ld``, filled in the order the 68000 reaches the probes below:
[tag, cycle, value] per hit, ``cycle`` being BlastEm's master clock (896 040
a frame on NTSC, 7 per 68000 cycle; 32 bits, so differences are taken
modulo 2^32). The probes sit on instructions the recorder does not stop or
log at already (a second breakpoint at one address would replace the
first): the rink loop's top-level calls (docs/re/rink-pass.md 1) and the
VBlank handler `$13F96` (entry after its `movem`, each callback of the
list at `$FFCA4E`, its `rte`). A pass's elapsed ticks are the VBlanks
between two pass starts (``PASS_START``); the costs follow from the stamps:
A (pass start -> the DMA wait ``DMA_WAIT``), the VBlank handlers, B (after
the wait -> the next pass start), each minus the handlers inside. The DMA
queue's pushes (``QUEUE_PROBES``) say when the wait has something to wait
for, and how many words the next VBlank drains.

    tools/bin/py -m mw_harness load-record cpu_s0 [NAME ...] [--passes N]

Recordings go to ``out/load/NAME/`` (local, like ``out/sim``).
"""
from __future__ import annotations

import json
from pathlib import Path

from . import sim_record as sr
from .trace import REPO_ROOT

REC_DIR = REPO_ROOT / "out" / "load"
#: Master clocks per NTSC frame (3420 x 262) and per 68000 cycle.
MCLK_FRAME = 896040
MCLK_68K = 7
#: tag -> (address, name, value expression): the rink loop `$F962`.
PASS_PROBES = {
    1: (0xF96E, "pass_start", "d0"),          # the tick wait's exit; d0 = elapsed
    2: (0xF978, "penalties", "0"),            # jsr $A66A
    3: (0xF97E, "clock", "0"),                # jsr $261C
    4: (0xF984, "pads", "0"),                 # jsr $1407E
    5: (0xF990, "after_control", "0"),        # $95C8 done (team control)
    6: (0xF9AA, "team_1", "0"),               # first team's $3836 (after the order roll)
    7: (0xF9B2, "team_2", "0"),               # first done
    8: (0xF9C0, "puck", "0"),                 # second done; jsr $5E74 next
    9: (0xF9CC, "portrait", "0"),             # puck done; $AFAC next
    10: (0xF9D4, "objects", "0"),             # jsr $7868
    11: (0xF9DA, "camera_target", "0"),
    12: (0xFA42, "rink_update", "0"),         # jsr $56EA next
    13: (0xFA4E, "dma_wait", "[0xffd898].w"),   # jsr $148A8: waits while the queue holds entries (count)
    14: (0xFA54, "after_wait", "0"),          # sprite list reset next
    15: (0xFA5A, "replay_rec", "0"),
    16: (0xFA88, "penalty_timers", "0"),      # jsr $A5EC (`$FA86` is the draw logs' share start)
    17: (0xFA8E, "puck_rules", "0"),          # jsr $C84A
    18: (0xFA9A, "phase", "0"),               # bsr $FC58
    19: (0xFAA4, "draw_team_a", "0"),         # jsr $38E0 (`$FAA0` is the share end)
    20: (0xFAAA, "draw_team_b", "0"),
    21: (0xFAB4, "draw_puck", "0"),
    22: (0xFABE, "draw_rink", "0"),           # $591E: nets, hazards, objects, lamps, ...
    23: (0xFAC8, "draw_portrait", "0"),
    24: (0xFAE2, "replay_close", "0"),        # jsr $9D64
    25: (0xFAE8, "first_pass", "0"),
    26: (0xFB16, "queue_sprites", "0"),       # jsr $157B0
    27: (0xFB1C, "hscroll", "0"),
    28: (0xFB22, "vsram", "0"),
    29: (0xFB28, "pass_end", "[0xffd898].w"),   # the queue's entries for the next VBlank
}
#: The DMA queue's push (`$1483C`, from `dma_queue_vram` `$14806` and the
#: other entries): one entry, d0 = its length in words.
QUEUE_PROBES = {
    50: (0x14886, "queue_push", "d0"),
}
#: The VBlank handler `$13F96`.
VBLANK_PROBES = {
    40: (0x13F9A, "vblank_in", "[0xffca56].l"),   # after the movem; value: tick (before its +1)
    41: (0x13FA4, "callback", "a0"),              # jsr (a0): one callback of `$FFCA4E`
    42: (0x13FA6, "callback_done", "0"),
    43: (0x13FD0, "vblank_out", "[0xffca56].l"),  # rte
}
#: Work counted per pass (where the cost scales with a count).
WORK_PROBES = {
    51: (0x156CA, "sprite_piece", "0"),       # add_sprite_piece `$156C6` (after its pushes)
    52: (0x150D4, "sprite_cache", "d0"),      # sprite_cache(_now) `$150CE` / `$150C6`: d0 = the key (first tile word)
    54: (0x150D8, "sprite_cache_n", "d1"),    # its d1 = tiles - 1 + 16 x (rows - 1) (the size byte's form)
    53: (0xA082, "draw_frame", "0"),          # draw_frame `$A07E`
}
#: Inside a team's update `$3836`: its formation `$3E7A`, then per player
#: slot `$86A` (control or the AI, the state handler, motion, collisions).
PLAYER_PROBES = {
    60: (0x3842, "players", "a5"),            # formation done; a5 = the team
    61: (0x3854, "player", "a5"),             # a present player's `$86A` next
    62: (0x385C, "player_done", "a5"),
    63: (0x3C00, "ai", "a5"),                 # ai_think `$3BFE`
    64: (0x8A6, "ai_done", "0"),              # its returns in `$86A`
    65: (0x8CE, "ai_done", "0"),
    66: (0x6D06, "collide", "a5"),            # collide_player `$6D02`
}
PROBES = {**PASS_PROBES, **VBLANK_PROBES, **QUEUE_PROBES, **WORK_PROBES, **PLAYER_PROBES}
#: The sound driver's VBlank work (`$13DE8`, `$17B20`; docs/re/sound.md 4):
#: what it did, counted per VBlank (``--sound``), for its cost model.
SOUND_PROBES = {
    70: (0x17176, "snd_channel", "0"),        # `$1715E`: a channel in use (state 0)
    71: (0x18CDE, "snd_noteoff_entry", "0"),  # `$18CD0`: one queued note-off looked at
    72: (0x189E0, "snd_track_clock", "0"),    # one MIDI clock of a track
    73: (0x17356, "snd_midi_byte", "0"),
    74: (0x173EA, "snd_note_off", "0"),
    75: (0x174D2, "snd_note_on", "0"),
    76: (0x17556, "snd_pcm_note_on", "0"),
    77: (0x17656, "snd_fm_note_on", "0"),
    78: (0x1715E, "snd_channels", "0"),       # the channel pass (not when the sequencer is locked)
    79: (0x16F28, "snd_env_pitch", "0"),
    80: (0x16FB4, "snd_env_volume", "0"),
    81: (0x17040, "snd_arpeggio", "0"),
    82: (0x170C6, "snd_vibrato", "0"),
    83: (0x16DAC, "snd_fm_pitch", "0"),
    84: (0x16D32, "snd_pcm_pitch", "0"),
    85: (0x17E62, "snd_voice_rate", "0"),
    86: (0x17EA2, "snd_voice_volume", "0"),
    87: (0x17B68, "snd_copy", "0"),           # the 133-byte batch copy to the Z80
    88: (0x13F1C, "snd_crowd", "0"),
    89: (0x18D54, "snd_track_slot", "0"),     # `$18CD0`'s track loop (32 slots while any is active)
    90: (0x17B48, "snd_driver", "0"),         # `$17B20` past the Z80 / lock checks
}
PASS_START = 1
DMA_WAIT = 13
AFTER_WAIT = 14


def extra_logs(sound: bool = False) -> dict:
    """The ``ld`` array for :func:`sim_record.record` (with [SOUND_PROBES])."""
    table = {**PROBES, **SOUND_PROBES} if sound else PROBES
    probes = [(addr, [str(tag), "cycle", value]) for tag, (addr, _, value) in table.items()]
    clash = {addr for addr, _ in probes} & sr.instrumented(draws=True, screens=True)
    assert not clash, f"probes on addresses the recorder uses: {sorted(map(hex, clash))}"
    return {"ld": (3, probes)}


def record_run(name: str, folder: Path = REC_DIR, passes: int | None = None, budget: float = 165.0,
               sound: bool = False) -> Path:
    """Run ``name`` of ``sim_record.RUNS`` / ``RUNS3`` with the load probes
    (same seed and driver as its plan 08-10 recording)."""
    seed = sum(sr.RUNS3.get(name, {}).get("base", name).encode()) & 0xFFFF
    if name in sr.RUNS3:
        spec = dict(sr.RUNS3[name])
        spec.pop("base", None)
        spec.pop("draws", None)                    # the draw logs' addresses overlap the probes
        setup, n = spec.pop("setup"), spec.pop("passes")
    else:
        setup, n = sr.RUNS[name]
        spec = {}
    out = sr.record(name, setup, passes or n, folder / name, seed=seed, budget=budget,
                    extra_logs=extra_logs(sound), **spec)
    meta = json.loads((out / "meta.json").read_text())
    table = {**PROBES, **SOUND_PROBES} if sound else PROBES
    meta["load"] = {"format": "mw-load/1", "probes": {str(t): [a, nm] for t, (a, nm, _) in table.items()},
                    "mclk_frame": MCLK_FRAME, "mclk_68k": MCLK_68K}
    (out / "meta.json").write_text(json.dumps(meta))
    return out


def main(args) -> None:
    folder = Path(args.out) if getattr(args, "out", None) else REC_DIR
    for name in args.names:
        p = record_run(name, folder, passes=args.passes, budget=getattr(args, "budget", None) or 165.0,
                       sound=getattr(args, "sound", False))
        m = json.loads((p / "meta.json").read_text())
        print(name, m["count"], "passes", m["seconds"], "s")
