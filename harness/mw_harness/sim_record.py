"""Simulation recordings of the original (plan 08, docs/compare.md,
Simulation recordings).

Plays a match on the original in BlastEm and keeps, for every pass of the
rink loop (screens 4-6), what a pass-for-pass test of the simulation
segment needs (``$F98A`` ``jsr $95C8`` .. ``$F9C8``, after the puck update):

* ``start``: RAM ``$FFB050``-``$FFCA61`` at ``$F98A`` (pads read, nothing
  simulated yet): hold timers, game clock, RNG, the setup bytes, the rink
  state, puck, both teams, overlays, plates, rules, phase, tick, pads;
* ``mid``: RAM ``$FFB050``-``$FFBDC1`` at ``$F9C2`` (both teams updated,
  the puck not yet);
* ``end``: the ``start`` RAM at ``$F9C8``;
* ``ai``: for every CPU think, RAM ``$FFB050``-``$FFBDC1`` before the AI
  (``jsr $3BFE`` at ``$8A0`` / ``$8C8``) and after it and the avoidance
  (``jsr $2050`` at ``$8AC`` / ``$8DC``): what the AI changed;
* call logs (debugger arrays, no round trip): every ``$86A`` entry (player,
  motion, animation position, state, RNG), ``rng_next`` / ``rng_range``
  callers, ``$63D8`` callers and D0.

Recorder v3 (plan 09) adds what the rest of the pass (outside the segment)
needs to be checked pass by pass: the tick at every place the rink pass
reads it (``TICK_SITES`` tags 9+: pass start, clock, penalty timers,
faceoff, goal, stoppages, every phase handler's "now - stamp", coach
speeches, the sharks' oscillators, the goalie arrow), the phase handler's
entry (``ph``), the direct sound calls ``$13CEE`` (``sd``) and every
"still playing?" poll of the sound driver (``vc``: the coach voice), plus
the runs of ``RUNS3`` (whole matches with short periods, overtime, a
playoff game, the pause menu, goalie holds and icing, the attract demo),
driven by :class:`PauseDriver` / :class:`GoalieDriver` and the recorder's
handling of the pause menu (``PAUSE_OPEN`` .. ``PAUSE_DONE``) and of the
attract demo.

Recorder v4 (plan 09, presentation; runs with ``"draws": True``, the
``_d`` runs of ``RUNS3``) adds what the original draws outside the
segment, as fixed-width records in two debugger arrays (``DRAW_LOGS``):
``win`` every window-plane write routine the phase code uses (``draw_text``
``$14CAE``, a glyph ``$14C26``, ``$146EA`` fill, ``$14B30`` VRAM fill,
``$1449C`` map copy, the frame ``$BA98``, the text box print ``$15860``,
the clock widget ``$25AA``) with its arguments and the name-table writes
they make (``$14656`` a glyph's cells, ``$14B30`` / ``$1449C``), and ``spr`` every
``draw_frame`` ``$A07E`` / ``add_sprite_piece`` ``$156C6`` call made while
the pass's "phase share" runs (``$FA86``: the penalty timers ``$A5EC``, the
puck rules ``$C84A``, the phase handler ``$FC58``, up to its return
``$FAA0`` or a rink exit ``$FB38``); marker records (kind 0 / 9) bound the
share in both arrays.

Pads are driven by :class:`PadDriver`, a seeded reactive player (skates to
the puck, carries it to the net, taps and holds A/B/C). Recordings are local
(``out/sim/NAME/``: RAM); fixtures made from them hold decoded fields only.
"""
from __future__ import annotations

import gzip
import json
import math
import random
import struct
import tempfile
import time
from collections.abc import Iterable
from pathlib import Path

from .blastem_live import BlastEmError, LiveBlastEm
from .rom import Rom, default_rom_path

VBLANK = 0x13F96
SCREEN_CALL = 0x20AC
SEG_START = 0xF98A           # jsr $95C8; (a7).w = elapsed ticks
SEG_MID = 0xF9C2             # jsr $5E74 (puck update)
SEG_END = 0xF9C8
AI_PRE = (0x8A0, 0x8C8)      # jsr $3BFE: gated CPU skater / last carrier or goalie
AI_POST = (0x8AC, 0x8DC)     # jsr $2050 after the AI (and $8820)
SNAP = (0xFFB050, 0xCA62 - 0xB050)
AI_SNAP = (0xFFB050, 0xBDC2 - 0xB050)
MARK = 0xFFFFFFFF            # + pass number: the pass starts (entries never start with $FFFFFFFF)
MARK_END = 0xFFFFFFFE        # + pass number: the segment ended (later entries: rest of the pass)
#: Debugger arrays: name -> (address, expressions appended per hit[,
#: condition: a BlastEm expression, other hits are not logged]).
LOGS = {
    "ent": (0x86A, ["a5", "d0", "[a5].l", "[a5+4].l", "[a5+8].l", "[a5+12].l", "[a5+16].l", "[a5+20].l",
                    "[a5+32].l", "[a5+112].l", "[0xffb096].l", "[0xffca56].l"]),
    "col": (0x6D02, ["a5", "[a5].l", "[a5+4].l", "[a5+8].l", "[a5+12].l", "[a5+16].l", "[a5+20].l",
                     "[0xffb096].l"]),
    "pk": (0x5E74, ["[a7].l", "[0xffca56].l"]),
    "pen": (0xA4AA, ["[a7].l", "d0", "a5"]),
    "snd": (0x13D58, ["[a7].l", "d0", "a5"]),
    # change player: the "puck" it reads is a6 (the collision code's frame when called from there)
    "chg": (0x1856, ["[a7].l", "a5", "a6", "[a6].l", "[a6+4].l", "[a6+8].l", "[a6+12].l", "[a6+36].l", "[a6+60].l"]),
    "rn": (0x4BC6, ["[a7].l", "[0xffb096].l"]),
    "rr": (0x4BD6, ["[a7].l", "d0", "d1", "[0xffb096].l"]),
    "sk": (0x63D8, ["[a7].l", "a5", "d0"]),
    # --- recorder v3 ---
    # phase handler $FC58 entry: tick, phase, subphase, d0 = the pass's elapsed
    "ph": (0xFC58, ["[0xffca56].l", "[0xffc60a].w", "[0xffc60c].w", "d0"]),
    # direct sound calls $13CEE: return address, sound id; the call $13D58
    # makes (return $13D7A) is in "snd" already
    "sd": (0x13CEE, ["[a7].l", "d0"], "[a7].l != 0x13d7a"),
    # sound driver polls $13D9C ("still playing?"), at its exit $13DB8:
    # caller's return address (above the 6 saved registers), d0 = the result
    # (0: done), a5 (the caller's; for the portraits' voices, polled by
    # $B572 at return $B5CA: the portrait, $FFC618 the coach, +$18 = the
    # handle), tick
    "vc": (0x13DB8, ["[a7+24].l", "d0", "a5", "[0xffca56].l"]),
}
#: Where the rink pass reads the tick counter (the VBlank interrupt moves it
#: at any time, also between two reads a few instructions apart): address ->
#: tag; logged as [tag, tick] with the long at $FFCA56 when the instruction
#: is reached (= what it reads). Tags 1-8: the simulation segment (v2);
#: 9+: the rest of the pass and the rink entries (v3, plan 09). Not logged:
#: the pass-start wait loop `$F966` (its last read = the previous `$C5FE` +
#: the pass's elapsed ticks) and the VBlank's own `addq`. Found by reading
#: the code reachable from the loop (`$F962`-`$FB2A` without the segment, the
#: phase table `$FC84`, the rink object hooks `$67B2`, the entries) and
#: checked with a census run (every tick read of the ROM logged): in the v3
#: runs every read the rink loop and its entries made is one of these.
TICK_SITES = {
    0x6136: 1,    # take: puck +$26
    0x51F4: 2,    # poke: puck +$26
    0x1BF0: 3,    # B-hold release: puck +$26
    0x747A: 4,    # white bone: +$2E
    0x749C: 5,    # black bone: +$2E
    0x5E6A: 6,    # faceoff drop set-up: puck +$26
    0x922: 7,     # the bones' 900-tick timer
    0x5F16: 8,    # the pick-up lock's 30 ticks
    # --- v3: pass loop and rink entry ---
    0xF95E: 9,    # rink entry (`$F884`/`$F8A4`/`$F8F0` common part): $C5FE = now
    0xF970: 10,   # pass start: $C5FE = now (after the elapsed wait `$F966`)
    0xAA5E: 57,   # rink entry (`$F936` -> `$AA58`): $C2D8 = now
    # --- game clock `$FFB066` ($16B0.. timer object, `$261C` widget) ---
    0x16F4: 11,   # $16E6 timer_start: stamp = now (faceoff state 8, every pass)
    0x1702: 12,   # $16FA timer_update: now - stamp - rate
    0x1714: 13,   # $16FA: stamp = now - d (second read: +1 when a VBlank fell between)
    0x257E: 14,   # $2562 unpause: stamp = now (rink entry, pause resume)
    0x26B2: 15,   # $261C: now - stamp >= 60 -> resync
    0x26BE: 16,   # $261C: resync stamp = now
    # --- penalties `$A5EC` (step h) / `$A66A` (penalties on) ---
    0xA79E: 17,   # $A782 (phase 0), icon shown: now - $C2D8 >= 240
    0xA7B8: 18,   # $A782 (phase 0): $C2D8 = now
    0xAA0E: 19,   # $AA02 "power play" banner: now - $C2F4 >= 120
    0xA728: 20,   # $A6C2 penalty (phase 2) state 0: $C2D8 = now
    0xA75C: 21,   # $A6C2 state 1: now - $C2D8 >= 240
    # --- faceoff sequence `$AC1C` (phases 1, 9), stamp $C2FA ---
    0xAC74: 22,   # state 0: stamp
    0xACC2: 23,   # state 1 (panel): now - stamp >= 90
    0xAE14: 24,   # state 2 (`$AE10`, widget drawn): stamp
    0xAE3A: 25,   # now - stamp >= 60 (portrait)
    0xAE90: 26,   # stamp
    0xAE9C: 27,   # now - stamp >= 30
    # --- goal `$928C` (phase 3), stamp $C2B0 ---
    0x9312: 28,   # state 0 (clock stopped): stamp
    0x935E: 29,   # blink: now - stamp >= 6
    0x936A: 30,   # blink: stamp = now
    0x9466: 31,   # stamp
    0x9494: 32,   # panel: now - stamp >= 150
    # --- puck rules: phase 8 `$CA12`, stamp $C3DC ---
    0xCA4A: 33,   # state 0 (whistle): stamp
    0xCAC4: 34,   # state 1: now - stamp >= 180
    # --- phase handlers (`$FC58`, table `$FC84`), stamp $C602 ---
    0xFD0E: 35,   # phase 0, pause resumed with Start: $C5FE = now
    0xFD1A: 36,   # phase 0 (every pass): $C602 = now
    0xFE74: 37,   # phase 4 (fight): now - $C602 >= 180
    0xFEA8: 38,   # phase 5 sub 0 (period end): now - $C602 >= 180
    0xFF1C: 39,   # phase 5, game over (winner): $C602 = now
    0xFF3E: 40,   # phase 5 sub 1 (winner panel): now - $C602 >= 180
    0xFF78: 41,   # phase 5 -> 10: $C602 = now
    0x1003C: 42,  # phase 9 sub 0: $C602 = now after the speech set-up
    0x10122: 43,  # phase 11 (Waste the Goalie): now - $C602 >= 480
    0x1017A: 44,  # phase 11 end: $C602 = now
    0x101B6: 45,  # phase 12 (Waste the Ref): now - $C602 >= 180
    0x101F6: 46,  # phase 13 (forfeit): now - $C602 >= 300
    0x1028A: 47,  # phase 14 (FACE OFF banner): now - $C602 > 180
    # --- coach speeches ---
    0x10396: 48,  # $102A6 (every speech pass): now - $C602 >= 600 (cap)
    0x10546: 49,  # $10474 period-start set-up: $C602 = now
    0x1060A: 50,  # $1054C game-over set-up: $C602 = now
    0x10726: 51,  # $10610 goal set-up: $C602 = now
    0x107C4: 52,  # $10732 penalty set-up: $C602 = now
    # --- rink objects (`$56EA` -> `$6734` hooks) ---
    0x1522C: 53,  # oscillator `$1522C` (shark update `$68AE`: x, then y)
    0x6890: 54,   # shark spawn `$686C` (rink set-up): x oscillator start = now
    0x68A4: 55,   # shark spawn: y oscillator start = now
    # --- draws ---
    0x4B5C: 56,   # `$4B14` arrow of a human goalie: tick bit 4 ($CA59)
}
TICK_LOG = "tk"
#: Recorder v4: the share of the pass between the segment's rest and the
#: draw pass - `$A5EC` (penalty timers, the penalty icon), `$C84A` (puck
#: rules, the stoppage icon), `$FC58` (phase handler, pause menu) - starts at
#: SHARE_START and ends at SHARE_END, or at a rink exit (`$FB38`, the
#: handler never returns).
SHARE_START = 0xFA86
SHARE_END = 0xFAA0
RINK_EXIT = 0xFB38
def _bytes_long(reg: str, at: int) -> str:
    """The long at ``reg + at`` read byte by byte (a string may start at an
    odd address, where a long read fails in the debugger and the record
    would lose a value)."""
    b = [f"[{reg}+{at + i}].b" for i in range(4)]
    return f"({b[0]} * 16777216 + {b[1]} * 65536 + {b[2]} * 256 + {b[3]})"


#: Debugger arrays of fixed-width records [kind, values...] (missing values
#: are 0): name -> (width, {kind: (address, expressions, condition or None)}).
#: Kind 0 marks the share's start, 9 its end (value 1: at a rink exit).
#: ``spr`` calls are logged only inside the share (debugger variable
#: ``inph``); ``win`` calls everywhere (the clock's texts are drawn at the
#: pass start, `$261C`).
DRAW_LOGS = {
    "win": (12, {
        # draw_text: return, string, font, plane object, x, baseline y, attr, the string's first 8 bytes
        1: (0x14CAE, ["[a7].l", "a0", "a5", "a1", "d1", "d2", "d3", _bytes_long("a0", 0), _bytes_long("a0", 4)], None),
        # one glyph (not draw_text's own calls `$14CBA`, nor the text box's `$15854`): char, font, plane, x, y, attr
        2: (0x14C26, ["[a7].l", "d0", "a5", "a1", "d1", "d2", "d3"],
            "([a7].l != 0x14cba) & ([a7].l != 0x15854)"),
        # fill (not the text box's `$15926` inside a filled frame): word, plane, x, y, w, h
        3: (0x146EA, ["[a7].l", "d0", "a5", "d1", "d2", "d3", "d4"], "[a7].l != 0x15938"),
        # VRAM rectangle fill (all: `$146EA`'s too, return `$14710`): row bytes, VRAM address, stride, word, rows
        4: (0x14B30, ["[a7].l", "d0", "d1", "d2", "d3", "d4"], None),
        # map copy: source, row bytes, VRAM address, dest stride, source stride, rows
        5: (0x1449C, ["[a7].l", "a0", "d0", "d1", "d2", "d3", "d4"], None),
        # frame: rect, plane, x, y, w, h, filled ($C3B4), rubbed out ($C3BC)
        6: (0xBA98, ["[a7].l", "a0", "a5", "[a0].w", "[a0+2].w", "[a0+4].w", "[a0+6].w", "[0xffc3b4].w",
                     "[0xffc3bc].w"], None),
        # text box print: string, box, attr, font, x, y, w, h, the string's first 4 bytes
        7: (0x15860, ["[a7].l", "a0", "a5", "d3", "[a5+4].l", "[a5+8].w", "[a5+10].w", "[a5+12].w",
                      "[a5+14].w", _bytes_long("a0", 0)], None),
        # the clock widget drawn: the clock flags $B077 (bit 0: the power-play form)
        8: (0x25AA, ["[a7].l", "[0xffb077].b"], None),
        # a glyph's cells written (`$14656`, the name-table words go straight to the VDP): plane, piece,
        # VRAM tile (the sprite cache's slot for the piece's ROM tiles), x, top y, attr
        10: (0x14656, ["[a7].l", "a5", "a0", "d0", "d1", "d2", "d3"], None),
    }),
    "spr": (8, {
        # draw_frame: x, y, depth, attr, frame (sprite coordinates)
        1: (0xA07E, ["[a7].l", "d0", "d1", "d2", "d3", "a5"], "inph"),
        # add_sprite_piece: x, y, depth, attr, piece
        2: (0x156C6, ["[a7].l", "d0", "d1", "d2", "d3", "a5"], "inph"),
    }),
}
#: Recorder v5 (plan 11): the screens between plays recorded pass by pass.
#: Their pass boundaries - the instruction after each tick wait (d0 = the
#: ticks since the last pass where a wait is) or after the pass's DMA wait -
#: and the screens they belong to; the RAM there is SNAP and STACK (the
#: handlers' locals sit in the stack page: a6 = $FFFFF8 for 12-19,
#: $FFFFF4 for 7).
SCREEN_SITES = {
    0x8D7C: (12, 13, 14, 15, 16),   # scoreboards `$8CF4` (after the tick wait)
    0xE6CE: (17,),                  # message scoreboard `$E612`
    0xCC02: (8,),                   # game stats (after the DMA wait; no tick wait)
    0xD1F0: (9,),                   # player stats (inside 8)
    0x1098E: (10,),                 # special plays (after the DMA wait)
    0xD8E6: (18,),                  # fight
    0xE43C: (18,),                  # the fight card (d4: ticks left)
    0x13AD0: (19,),                 # referee cutscene
    0x9E70: (7,),                   # instant replay (once per tick)
}
STACK = (0xFFFE00, 0x200)
MARK_SCREEN = 0xFFFFFFFD     # + screen pass index: a screen pass (or entry) starts
RNG_MAIN = 0xFFB096          # the main random stream (long)
RING = (0xFF0000, 0x8000)     # the replay ring's data (MwRinkState.ReplayRing)
TEAMS = (0xFFB402, 0xFFB8AC)
PUCK = 0xFFB3C2
PHASE = 0xFFC60A             # game_phase .w
GOALS = (0xFFB8A4, 0xFFBD4E)  # team +$4A2 .w: the score
CLOCK = 0xFFB06A             # game clock seconds .w
PERIOD = 0xFFB076            # .b, 4+ = overtime
PAUSE_OPEN = 0x492A          # $48FC: a pad's Start opened the pause menu (d2 = 2 * pad); a busy loop follows
PAUSE_DONE = 0x4A6E          # $48FC leaves: d0 = 1 Start (resume), 2 A (replay: screen 7), 3 B (timeout: screen 10)
PAUSE_OFFER = 0xFFB094       # .w 1: "B - TIMEOUT" offered
#: $1C258[pad mode]: pads below it pause for team A, the others for team B.
PAUSE_SPLIT = {0: 9, 1: 1, 2: 9, 3: 2, 4: 2, 5: 9}
#: Ticks between the recorder's Start pulses outside the rink, per screen
#: (default 40): the instant replay plays a while before it is left.
PULSE = {7: 150}
REC_DIR = Path(__file__).resolve().parents[2] / "out" / "sim"

#: Setup bytes: $B0DE team A (its stadium unless $B0E4 is poked after),
#: $B0DF team B, $B0E0 pads (0 P1 v CPU, 1 P1 v P2, 2 P1+P2 v CPU, 3 P1+P2 v
#: P3, 4 P1+P2 v P3+P4, 5 CPU v CPU), $B0E4 stadium, $B0E6 reserves, $B0E7
#: Death Index. name -> (setup, passes).
RUNS = {
    "cpu_s0": ({0xFFB0E0: 5, 0xFFB0DE: 0, 0xFFB0DF: 7, 0xFFB0E4: 0, 0xFFB0E7: 2}, 5000),
    "p1_s9": ({0xFFB0E0: 0, 0xFFB0DE: 9, 0xFFB0DF: 3, 0xFFB0E4: 9, 0xFFB0E7: 4}, 5000),
    "p1p2_s4": ({0xFFB0E0: 1, 0xFFB0DE: 4, 0xFFB0DF: 11, 0xFFB0E4: 4, 0xFFB0E6: 1, 0xFFB0E7: 1}, 5000),
    "cpu_s10": ({0xFFB0E0: 5, 0xFFB0DE: 10, 0xFFB0DF: 2, 0xFFB0E4: 10, 0xFFB0E7: 3}, 5000),
    "p1_s8": ({0xFFB0E0: 0, 0xFFB0DE: 8, 0xFFB0DF: 15, 0xFFB0E4: 8, 0xFFB0E7: 0}, 5000),
    "p1p2_s17": ({0xFFB0E0: 1, 0xFFB0DE: 17, 0xFFB0DF: 18, 0xFFB0E4: 17, 0xFFB0E7: 2}, 5000),
    "coop_s14": ({0xFFB0E0: 2, 0xFFB0DE: 14, 0xFFB0DF: 21, 0xFFB0E4: 14, 0xFFB0E6: 1, 0xFFB0E7: 3}, 5000),
    "p1_s2": ({0xFFB0E0: 0, 0xFFB0DE: 2, 0xFFB0DF: 12, 0xFFB0E4: 2, 0xFFB0E7: 1}, 5000),
    "cpu_s16": ({0xFFB0E0: 5, 0xFFB0DE: 16, 0xFFB0DF: 5, 0xFFB0E4: 16, 0xFFB0E7: 4}, 5000),
    "p1_s5": ({0xFFB0E0: 0, 0xFFB0DE: 5, 0xFFB0DF: 19, 0xFFB0E4: 5, 0xFFB0E6: 1, 0xFFB0E7: 2}, 5000),
    "p4_s22": ({0xFFB0E0: 4, 0xFFB0DE: 22, 0xFFB0DF: 13, 0xFFB0E4: 22, 0xFFB0E7: 2}, 5000),
}
#: Recorder v3 runs (plan 09): name -> record() arguments. Short periods
#: ($FFB0E3 minutes; $FFB0E2 = 0, the 3:00 index, for the penalty lengths)
#: so a match ends inside one recording; `stop_screens` ends the run at game
#: over. match_cpu_s13 enters period 3 with team B's score set to team A's
#: and 8 clock seconds (a tie: overtime, sudden death). In the playoffs the
#: stadium is team B's in a first game (`$B2B0`), so that run is named
#: after it.
RUNS3 = {
    "match_p1_s6": {"setup": {0xFFB0E0: 0, 0xFFB0DE: 6, 0xFFB0DF: 1, 0xFFB0E4: 6, 0xFFB0E7: 2,
                              0xFFB0E2: 0}, "late": {0xFFB0E3: 1},
                    "passes": 6000, "stop_screens": (15,), "driver": "match"},
    "match_cpu_s13": {"setup": {0xFFB0E0: 5, 0xFFB0DE: 13, 0xFFB0DF: 3, 0xFFB0E4: 13, 0xFFB0E7: 3,
                                0xFFB0E2: 0}, "late": {0xFFB0E3: 1},
                      "passes": 6000, "stop_screens": (15,),
                      "screen_pokes": ({"screen": 4, "period": 3, "clock": 8, "tie": True},)},
    "playoff_p1_s19": {"setup": {0xFFB0E0: 0, 0xFFB0E1: 1, 0xFFB0DE: 15, 0xFFB0DF: 19, 0xFFB0E7: 1,
                                 0xFFB0E2: 0}, "late": {0xFFB0E3: 1},
                       "passes": 6000, "stop_screens": (16,), "driver": "match"},
    "pause_p1_s7": {"setup": {0xFFB0E0: 0, 0xFFB0DE: 7, 0xFFB0DF: 11, 0xFFB0E4: 7, 0xFFB0E7: 1,
                              0xFFB0E2: 0}, "late": {0xFFB0E3: 2},
                    "passes": 6000, "driver": "pause"},
    "goalie_p1_s12": {"setup": {0xFFB0E0: 0, 0xFFB0DE: 12, 0xFFB0DF: 18, 0xFFB0E4: 12, 0xFFB0E7: 0,
                                0xFFB0E2: 0}, "late": {0xFFB0E3: 2},
                      "passes": 6000, "driver": "goalie"},
    "attract": {"setup": {}, "passes": 4000, "attract": True, "attract_press": (2500, 300)},
}
#: Recorder v4 runs: the v3 runs above again with the draw logs
#: (``DRAW_LOGS``), same seeds (named ``base``).
for _n in ("match_p1_s6", "pause_p1_s7", "goalie_p1_s12", "attract"):
    RUNS3[_n + "_d"] = {**RUNS3[_n], "draws": True, "base": _n}
#: Pads a mode uses (0-based), as `$1BFFE` assigns them.
PADS_IN_MODE = {0: [0], 1: [0, 1], 2: [0, 1], 3: [0, 1, 2], 4: [0, 1, 2, 3], 5: []}


class Snap:
    """Big-endian reads of a RAM snapshot starting at ``base``."""

    def __init__(self, data: bytes, base: int = SNAP[0]):
        self.data = data
        self.base = base

    def u8(self, a: int) -> int:
        return self.data[a - self.base]

    def u16(self, a: int) -> int:
        return struct.unpack_from(">H", self.data, a - self.base)[0]

    def s16(self, a: int) -> int:
        return struct.unpack_from(">h", self.data, a - self.base)[0]

    def s32(self, a: int) -> int:
        return struct.unpack_from(">i", self.data, a - self.base)[0]


DIRS = [{"RIGHT"}, {"RIGHT", "DOWN"}, {"DOWN"}, {"DOWN", "LEFT"}, {"LEFT"}, {"LEFT", "UP"}, {"UP"}, {"UP", "RIGHT"}]


class PadDriver:
    """A seeded, reactive stand-in for a human on pad ``pad`` (0-3): picks a
    behaviour for a while (chase the puck, wander, stand still, mash), carries
    the puck towards the attacked net and shoots, taps and holds A/B/C for
    random lengths (1 pass = tap; 2-14 passes cross the 15/20-tick holds)."""

    def __init__(self, pad: int, rng: random.Random):
        self.pad = pad
        self.rng = rng
        self.mode = "chase"
        self.left = 0
        self.dpad: set[str] = set()
        self.buttons: dict[str, int] = {}   # held button -> passes left

    def _me(self, s: Snap):
        for t, base in enumerate(TEAMS):
            for k in (0, 1):
                if s.u8(base + 0x66 + k) != self.pad:
                    continue
                for i in range(6):
                    p = base + 0x6C + 0x76 * i
                    f = s.u8(p + 0x74)
                    if s.u16(p + 0x32) | s.u16(p + 0x34) and f & 4 and (f >> 3) & 1 == k:
                        return t, base, p
        return None

    def _toward(self, dx: int, dy: int) -> set[str]:
        if dx == 0 and dy == 0:
            return set()
        a = math.atan2(dy, dx)
        return set(DIRS[round(a / (math.pi / 4)) % 8])

    def _press(self, b: str, lo: int, hi: int) -> None:
        if b not in self.buttons and not any(x in self.buttons for x in "ABC" if x != b) or self.rng.random() < 0.2:
            self.buttons[b] = self.rng.randint(lo, hi)

    def step(self, s: Snap) -> set[str]:
        r = self.rng
        for b in list(self.buttons):
            self.buttons[b] -= 1
            if self.buttons[b] < 0:
                del self.buttons[b]
        me = self._me(s)
        self.left -= 1
        if self.left <= 0:
            self.mode = r.choices(["chase", "wander", "idle", "mash"], [0.6, 0.2, 0.08, 0.12])[0]
            self.left = r.randint(8, 60)
            self.dpad = set(r.choice(DIRS)) if self.mode == "wander" else set()
        if me is None:
            return set(self.dpad) | set(self.buttons)
        t, team, p = me
        px, py = s.s32(p) >> 8, s.s32(p + 8) >> 8
        kx, ky = s.s32(PUCK) >> 8, s.s32(PUCK + 8) >> 8
        carrying = s.u8(PUCK + 0x3D) & 1 and s.u16(PUCK + 0x24) == p & 0xFFFF
        down = s.u8(team + 4) & 2
        goalie = s.u8(p + 0x69) == 5
        if self.mode == "idle":
            self.dpad = set()
        elif carrying and self.mode != "mash":
            ny = 329 if down else -329
            self.dpad = self._toward(-px // 2 + r.randint(-40, 40), ny - py)
            near = abs(ny - py) < 170
            x = r.random()
            if near and x < 0.10:
                self._press("C", 0, 0) if r.random() < 0.5 else self._press("C", 5, 12)
            elif x < 0.025:
                self._press("B", 0, 0) if r.random() < 0.6 else self._press("B", 5, 12)
            elif x < 0.035:
                self._press("A", 0, 0) if r.random() < 0.5 else self._press("A", 4, 10)
            if goalie and x < 0.2:
                self._press("B", 0, 0)
        elif self.mode == "chase":
            self.dpad = self._toward(kx - px, ky - py) if r.random() < 0.95 else self.dpad
            d = abs(kx - px) + abs(ky - py)
            x = r.random()
            if d < 60 and x < 0.06:
                self._press("C", 0, 1)
            elif d < 90 and x < 0.10:
                self._press("A", 0, 0) if r.random() < 0.6 else self._press("A", 4, 12)
            elif x < 0.115:
                self._press("B", 0, 0)
            elif goalie and x < 0.2:
                self._press("A", 0, 6)
        elif self.mode == "mash":
            if r.random() < 0.2:
                self.dpad = set(r.choice(DIRS)) if r.random() < 0.8 else set()
            if r.random() < 0.15:
                self._press(r.choice("ABC"), 0, 14)
        return set(self.dpad) | set(self.buttons)


class MatchDriver(PadDriver):
    """The v3 runs' :class:`PadDriver`: it also lets most coach speeches
    run (no buttons while one is due or on, 60 % of them; the D-pad does not
    skip, `$102A6`), so the recordings hold whole speeches and their voices
    (the ``vc`` polls) as well as skipped ones."""

    def __init__(self, pad: int, rng: random.Random):
        super().__init__(pad, rng)
        self.listen: bool | None = None

    def step(self, s: Snap) -> set[str]:
        want = super().step(s)
        due = s.u16(PHASE) in (9, 10) or s.u16(0xFFC644) != 0
        if not due:
            self.listen = None
            return want
        if self.listen is None:
            self.listen = self.rng.random() < 0.6
        if self.listen:
            self.buttons.clear()
            return want - {"A", "B", "C", "START"}
        return want


class PauseDriver(MatchDriver):
    """A :class:`MatchDriver` that also opens the pause menu: in open play,
    every 150-450 passes, preferably while its team carries the puck (the
    only time ``B - TIMEOUT`` is offered), it taps Start alone and lets go
    of everything on the next pass (the menu's loop reads the pads at once:
    a button still held there would count as a new press). The recorder
    runs the menu (:meth:`choose`)."""

    def __init__(self, pad: int, rng: random.Random):
        super().__init__(pad, rng)
        self.wait = rng.randint(120, 250)
        self.quiet = 0
        self.picks = {"A": 0, "B": 0, "START": 0}

    def choose(self, offered: bool) -> str:
        """The menu button, keeping the three about even: B (timeout) when
        offered and not ahead, else the less used of A (instant replay) and
        Start (resume)."""
        other = min(("A", "START"), key=lambda k: (self.picks[k], k != "A"))
        b = "B" if offered and self.picks["B"] <= self.picks[other] else other
        self.picks[b] += 1
        return b

    def step(self, s: Snap) -> set[str]:
        want = super().step(s)
        if self.quiet:
            self.quiet -= 1
            self.buttons.clear()
            return set()
        if s.u16(PHASE) != 0:
            return want
        self.wait -= 1
        if self.wait > 0:
            return want
        flags = s.u8(PUCK + 0x3D)
        team = TEAMS[0] if self.pad < PAUSE_SPLIT.get(s.u8(0xFFB0E0), 9) else TEAMS[1]
        ours = flags & 1 and (flags >> 1 & 1) == (s.u8(team + 4) & 1)
        if ours or self.wait < -150:
            self.wait = self.rng.randint(150, 450)
            self.quiet = 1
            self.buttons.clear()
            return {"START"}
        return want


class GoalieDriver(MatchDriver):
    """A :class:`MatchDriver` for the puck rules (`$C84A`): carrying the
    puck with a skater in its own half it often passes back to its goalie
    (aimed at the goalie: the receiver is the team-mate within 45 degrees of
    the aim, `$4E94`; the goalie takes the pad with the puck, control.md
    change of player 3) or clears it down the ice (a B pass straight ahead,
    a wrist or a slap shot: icing when it crosses the far goal line
    untouched); holding the puck with its goalie it stands still, no
    buttons, for 60-220 passes (15 clock seconds = 300 ticks stop play: the
    goalie hold). A plan aims for 3 passes, presses, and keeps the aim 3
    passes more (taps act on the release, the aim is read then)."""

    def __init__(self, pad: int, rng: random.Random):
        super().__init__(pad, rng)
        self.hold = 0
        self.plan: list | None = None     # [button, hold passes, passes left, aim]

    def step(self, s: Snap) -> set[str]:
        r = self.rng
        me = self._me(s)
        if me is None:
            self.hold = 0
            self.plan = None
            return super().step(s)
        t, team, p = me
        carrying = s.u8(PUCK + 0x3D) & 1 and s.u16(PUCK + 0x24) == p & 0xFFFF
        goalie = s.u8(p + 0x69) == 5
        if goalie and carrying:
            self.plan = None
            if self.hold == 0:
                self.hold = r.randint(60, 220)
            if self.hold > 1:
                self.hold -= 1
                self.buttons.clear()
                self.dpad = set()
                return set()
            return super().step(s)              # let go: play on (pass / clear)
        self.hold = 0
        if self.plan is None and carrying and not goalie and s.u16(PHASE) == 0:
            px, py = s.s32(p) >> 8, s.s32(p + 8) >> 8
            ny = 329 if s.u8(team + 4) & 2 else -329    # the attacked goal line
            if py * ny <= 0 and r.random() < 0.15:
                g = team + 0x6C + 0x76 * 5
                x = r.random()
                if x < 0.5 and s.u16(g + 0x32) | s.u16(g + 0x34):
                    gx, gy = s.s32(g) >> 8, s.s32(g + 8) >> 8
                    self.plan = ["B", 1, 7, self._toward(gx - px, gy - py)]          # back to the goalie
                elif x < 0.8:                                                       # clear: pass to a far corner
                    self.plan = ["B", 1, 7, self._toward(r.choice((-200, 200)) - px, ny + (40 if ny > 0 else -40) - py)]
                elif x < 0.9:
                    self.plan = ["C", 1, 7, self._toward(-px // 2, ny - py)]          # wrist shot
                else:
                    self.plan = ["C", 8, 14, self._toward(-px // 2, ny - py)]         # slap shot
        if self.plan is not None:
            b, length, left, aim = self.plan
            self.plan[2] -= 1
            self.buttons.clear()
            self.dpad = set(aim)
            if self.plan[2] <= 0:
                self.plan = None
            # aim 3 passes, hold the button `length` passes, then the aim alone
            if left <= length + 3 and left > 3:
                return set(aim) | {b}
            return set(aim)
        return super().step(s)


DRIVERS = {"chase": PadDriver, "match": MatchDriver, "pause": PauseDriver, "goalie": GoalieDriver}


def instrumented(draws: bool = True, screens: bool = False) -> set[int]:
    """Every address the recorder stops or logs at (coverage leaves them out:
    two breakpoints at one address would confuse the stops)."""
    out = {SCREEN_CALL, VBLANK, SEG_START, SEG_MID, SEG_END, *AI_PRE, *AI_POST, PAUSE_OPEN, PAUSE_DONE,
           *TICK_SITES, *(v[0] for v in LOGS.values())}
    if screens:
        out |= set(SCREEN_SITES)
    if draws:
        out |= {SHARE_START, SHARE_END, RINK_EXIT}
        out |= {addr for _, calls in DRAW_LOGS.values() for addr, _, _ in calls.values()}
    return out


def _live(rom: Path, tries: int = 3) -> LiveBlastEm:
    """A LiveBlastEm; BlastEm's recompiler now and then fails while starting
    ("out of range for a 32-bit displacement"): start it again."""
    for i in range(tries):
        try:
            return LiveBlastEm(rom)
        except BlastEmError:
            if i == tries - 1:
                raise
            time.sleep(0.5)
    raise AssertionError


def record(name: str, setup: dict[int, int], passes: int, out_dir: Path, seed: int = 1,
           rom: Path | None = None, start_delay: int = 30, budget: float = 165.0, *,
           driver: str = "chase", stop_screens: tuple[int, ...] = (), screen_pokes: tuple = (),
           late: dict[int, int] | None = None, attract: bool = False,
           attract_press: tuple[int, ...] = (900, 250), draws: bool = False,
           coverage: Iterable[int] = (), lean_until_visit: int = 0, rng_poke: int | None = None,
           visits: int = 0, tour: dict | None = None, screens: bool = False) -> Path:
    """Record up to ``passes`` rink passes (stops early after ``budget``
    seconds, or at a screen of ``stop_screens``) into ``out_dir`` (meta.json
    + gzipped snapshots).

    ``driver``: the pad driver (``DRIVERS``). ``late``: setup bytes poked
    at every matchup (screen 3) entry, after the main menu (whose rows
    rewrite some, e.g. the period minutes `$FFB0E3` from `$FFB0E2`), before
    `$B2B0` sets up the match clock. ``screen_pokes``: dicts
    {"screen", "period", "clock" (seconds), "tie" (team B's goals = team
    A's)} applied when that screen is entered in that period (outside the
    rink loop; kept in ``meta["pokes"]``). ``attract``: no setup, no input:
    the main menu idles into the attract demo; in the n-th demo the recorder
    presses A on pad 1 after ``attract_press[n]`` passes (the last value for
    later demos; the demo ends on any input, or by itself at its first rink
    exit: then the menu idles into the next one), and the run ends back at
    the main menu after the press. ``draws``: recorder v4's draw logs
    (``DRAW_LOGS``).

    Plan 10 (the soak runner, :mod:`soak`): ``coverage``: code addresses
    with a breakpoint from power-on, each deleted at its first hit; the hits
    go to ``meta["coverage"]`` (address -> [tick, screen]). The addresses
    the recorder stops at itself are left out, and those it logs at
    (:func:`instrumented`) once it records (``coverage_dropped``).
    ``lean_until_visit``: record nothing before rink visit k (1-based; the
    pads still play), so a run can be recorded from a late visit within
    the budget; a large k = a lean run that only measures coverage.
    ``visits``: with ``lean_until_visit``, stop at the start of the rink
    visit after that many recorded ones (0: no limit).
    ``rng_poke``: the main random stream `$FFB096` (long) at the first
    matchup (screen 3) entry - varies CPU-vs-CPU games whose boot seed is
    fixed by the emulator's timing. A different set of breakpoints can
    change BlastEm's timing slightly (seen: matches parting by 1-2 ticks at
    a screen change), so a lean run and a full one of the same arguments
    usually, not always, play the same match: a recording's own coverage map
    (``meta["coverage"]``) says what it holds.

    Plan 11: ``tour``: the pads outside the rink follow a :class:`tours.Tour`
    (the screens' navigation models) instead of Start pulses, from the first
    main menu on: {"seed", "menu" (row -> value: the setup set through the
    main menu's rows; ``setup`` then holds only what the menu cannot set,
    pad mode 5), "excursions", "browse", "passwords", "bias", "detours"}.
    A screen of ``stop_screens`` stops the run only after a rink visit; what
    the tour took is in ``meta["tour"]``.

    ``screens`` (recorder v5, with ``draws``): the screens between plays
    recorded too - at each screen's entry (the dispatcher's call) and pass
    boundary (``SCREEN_SITES``) the RAM (SNAP, then STACK) into
    screens.bin.gz, ``meta["screen_passes"]`` [rink passes so far, screen,
    tick, site (SCREEN_CALL: the entry), d0], and the logs split per
    screen pass (``meta["screen_log_data"]``; sprite draws logged
    throughout the screens)."""
    t0 = time.monotonic()
    rom = Path(rom) if rom else default_rom_path()
    rng = random.Random(seed)
    out_dir.mkdir(parents=True, exist_ok=True)
    # scratch for debugger saves, outside the repository (files in connected
    # folders may not be deletable)
    tmp = Path(tempfile.mkdtemp(prefix="mw-rec-")) / "snap.tmp"
    menu = {int(k): v for k, v in dict((tour or {}).get("menu") or {}).items()}
    mode = setup.get(0xFFB0E0, menu.get(2, 0))      # gen 2 soak runs set the pad mode in the menu
    kind = DRIVERS[driver]
    drivers = [] if attract else [kind(p, random.Random(seed * 31 + p)) for p in PADS_IN_MODE[mode]]
    arrays = {**{k: len(v[1]) for k, v in LOGS.items()}, TICK_LOG: 2}
    if draws:
        arrays.update({k: w for k, (w, _) in DRAW_LOGS.items()})
    assert draws or not screens, "screen recordings need the draw logs"
    meta: dict = {"format": "mw-sim/1", "recorder": 5 if screens else 4 if draws else 3, "name": name, "rom_sha1": Rom.load(rom).sha1,
                  "setup": {hex(k): v for k, v in setup.items()}, "seed": seed,
                  "options": {"driver": driver, "stop_screens": list(stop_screens),
                              "screen_pokes": list(screen_pokes), "attract": attract, "draws": draws,
                              "late": {hex(k): v for k, v in (late or {}).items()}},
                  "snap": list(SNAP), "ai_snap": list(AI_SNAP),
                  "logs": {**{k: [v[0], len(v[1])] for k, v in LOGS.items()}, TICK_LOG: [0, 2],
                           **({k: [0, w] for k, (w, _) in DRAW_LOGS.items()} if draws else {})},
                  "tick_sites": {hex(a): t for a, t in TICK_SITES.items()},
                  "passes": [], "screens": [], "pauses": [], "pokes": [], "presses": []}
    start = gzip.open(out_dir / "start.bin.gz", "wb", compresslevel=3)
    mid = gzip.open(out_dir / "mid.bin.gz", "wb", compresslevel=3)
    end = gzip.open(out_dir / "end.bin.gz", "wb", compresslevel=3)
    ai = gzip.open(out_dir / "ai.bin.gz", "wb", compresslevel=3)
    scr_f = gzip.open(out_dir / "screens.bin.gz", "wb", compresslevel=6) if screens else None
    n_ai = 0
    meta["screen_passes"] = []
    meta["screen_snap"] = [list(SNAP), list(STACK)]

    def save(f, region) -> bytes:
        bl.command(f'save/b "{tmp}" [0x{region[0]:x}] {region[1]}')
        data = tmp.read_bytes()
        assert len(data) == region[1], (len(data), region)
        f.write(data)
        return data

    meta["coverage"] = {}
    where = [-1]                       # the screen now (coverage hits)
    tourer = None
    if tour is not None:
        from . import screen_models as sm
        from . import tours as tr
        goal = None
        if tour.get("menu") is not None:
            goal = tr.MenuGoal({int(k): v for k, v in dict(tour["menu"]).items()},
                               sm.MenuRows.from_rom(Rom.load(rom)), tour.get("excursions", ()),
                               tour.get("browse", 8))
        tourer = tr.Tour(random.Random(tour.get("seed", seed)), goal=goal, passwords=tour.get("passwords"),
                         bias=tour.get("bias"), detours=tuple(tour.get("detours", (0, 2))),
                         fight_styles=bool(tour.get("fight_styles", False)),
                         pages_both=bool(tour.get("pages_both", False)))
        meta["options"]["tour"] = {k: v for k, v in tour.items() if k != "bias"}
        meta["options"]["tour"]["bias_edges"] = len(tour.get("bias") or {})
    with _live(rom) as bl:
        cov_ids: dict[int, int] = {}   # coverage address -> breakpoint id until its first hit
        # the recorder's own stops are left out; a lean run measures its logs' addresses
        # until it starts recording (instrument() then drops their coverage breakpoints)
        own = {SCREEN_CALL, VBLANK, PAUSE_OPEN, PAUSE_DONE, *([SEG_START] if drivers else [])}
        if lean_until_visit <= 1:
            own |= instrumented(draws, screens)
        for ca in sorted(set(coverage) - own):
            bl.breakpoint(ca)
            cov_ids[ca] = max(k for k, v in bl.breakpoints.items() if v == ca)

        def cont() -> int:
            """The next stop that is not a coverage hit (those are noted
            and their breakpoints deleted on the way)."""
            while True:
                at = bl.cont()
                bp = cov_ids.pop(at, None)
                if bp is None:
                    return at
                tick_now, = bl.read("[0xffca56].l")
                meta["coverage"][f"{at:06X}"] = [tick_now, where[0]]
                bl.command(f"delete {bp}")
                del bl.breakpoints[bp]

        bl.breakpoint(SCREEN_CALL)
        screen = -1
        while screen != 1:
            cont()
            screen = where[0] = bl.read("[0xffb05e].w")[0]
        if not attract:
            for a, v in setup.items():
                bl.write(a, v, "b")
        if not attract and tourer is None:
            bl.breakpoint(VBLANK)
            vb_id = max(k for k, v in bl.breakpoints.items() if v == VBLANK)
            for i in range(start_delay + 8):
                while cont() != VBLANK:
                    pass
                if i == start_delay:
                    bl.press(1, "START")
                elif i == start_delay + 6:
                    bl.release(1, "START")
            bl.command(f"delete {vb_id}")
            del bl.breakpoints[vb_id]
        def instrument() -> None:
            """The logs and the segment / AI breakpoints (the recording).
            Coverage starts again with it: ``meta["coverage"]`` holds what
            the recorded part reached (the lean part's: ``coverage_lean``)."""
            for ca in instrumented(draws, screens) & set(cov_ids):
                bp = cov_ids.pop(ca)
                bl.command(f"delete {bp}")
                del bl.breakpoints[bp]
            if lean_until_visit > 1:
                # the replay ring's data so far (kept over faceoffs and the instant replay)
                bl.command(f'save/b "{tmp}" [0x{RING[0]:x}] {RING[1]}')
                with gzip.open(out_dir / "ring.bin.gz", "wb", compresslevel=6) as f:
                    f.write(tmp.read_bytes())
                meta["ring0"] = True
            if lean_until_visit > 1 and coverage:
                meta["coverage_lean"] = meta["coverage"]
                meta["coverage"] = {}
                for ca in sorted(set(coverage) - own - instrumented(draws, screens) - set(cov_ids)):
                    bl.breakpoint(ca)
                    cov_ids[ca] = max(k for k, v in bl.breakpoints.items() if v == ca)
            for k, (addr, ex, *cond) in LOGS.items():
                bl.log_at(addr, k, *ex, condition=cond[0] if cond else None)
            bl.command(f"array {TICK_LOG}")
            for addr, tag in TICK_SITES.items():
                bl.on_hit(addr, [f"append {TICK_LOG} {tag}", f"append {TICK_LOG} [0xffca56].l"])
            if draws:
                _draw_logs(bl)
            for a in (SEG_START, SEG_MID, SEG_END, *AI_PRE, *AI_POST):
                if a != SEG_START or not drivers:
                    bl.breakpoint(a)
            if screens:
                for a in SCREEN_SITES:
                    bl.breakpoint(a)

        def screen_record(at: int, scr: int, tick: int, d0: int) -> None:
            """Recorder v5: one screen entry / pass: its RAM and a log marker."""
            idx = len(meta["screen_passes"])
            for k in arrays:
                bl.command(f"append {k} {MARK_SCREEN}")
                bl.command(f"append {k} {idx}")
            save(scr_f, SNAP)
            save(scr_f, STACK)
            meta["screen_passes"].append([n, scr, tick, at, d0 & 0xFFFF])

        recording = lean_until_visit <= 1
        if drivers:                    # the pads play from the first pass
            bl.breakpoint(SEG_START)
        if recording:
            instrument()
        pausing = [d for d in drivers if isinstance(d, PauseDriver)]
        if pausing:
            bl.breakpoint(PAUSE_OPEN)
            bl.breakpoint(PAUSE_DONE)

        def vblank_on() -> int:
            bl.breakpoint(VBLANK)
            return max(k for k, v in bl.breakpoints.items() if v == VBLANK)

        def vblank_off(bp: int) -> None:
            bl.command(f"delete {bp}")
            del bl.breakpoints[bp]

        def release_all() -> None:
            for p in range(4):
                if held[p]:
                    bl.release(p + 1, *sorted(held[p]))
                    held[p] = set()

        held: list[set[str]] = [set() for _ in range(4)]
        n = 0
        cur: dict | None = None
        vb = None
        ticks = 0
        start_down = False
        visit = 0
        pulse = 40
        pause: dict | None = None      # the open pause menu: driver, ticks, button
        demo = 0                       # attract: demo visits seen
        demo_passes = 0
        pressed = False                # attract: A held to end the demo
        poked = rng_poke is None
        lean_passes = 0
        pulse_pad = 1                  # the pad of the START pulses outside the rink
        last_pause_pad: int | None = None
        if tourer is not None:         # the tour drives the first main menu
            tourer.enter(1, 0)
            vb = vblank_on()
        while n < passes and time.monotonic() - t0 < budget:
            a = cont()
            if a == SCREEN_CALL:
                scr, tick, period = bl.read("[0xffb05e].w", "[0xffca56].l", f"[0x{PERIOD:x}].b")
                where[0] = scr
                prev_scr = meta["screens"][-1][1] if meta["screens"] else -1
                meta["screens"].append([n, scr, tick])
                if scr in stop_screens and (tourer is None or visit > 0):
                    break
                if scr == 3 and not poked:
                    bl.write(RNG_MAIN, rng_poke & 0xFFFFFFFF, "l")
                    meta["pokes"].append([n, scr, hex(RNG_MAIN), rng_poke & 0xFFFFFFFF])
                    poked = True
                if recording and visits and scr in (4, 5, 6) and visit + 1 >= max(lean_until_visit, 1) + visits:
                    break
                if not recording and scr in (4, 5, 6) and visit + 1 >= lean_until_visit:
                    instrument()
                    recording = True
                    meta["recording_from"] = [visit + 1, tick]
                if scr == 3 and late:
                    for la, lv in late.items():
                        bl.write(la, lv, "b")
                        meta["pokes"].append([n, scr, hex(la), lv])
                for sp in screen_pokes:
                    if sp["screen"] == scr and sp.get("period", period) == period:
                        if "clock" in sp:
                            bl.write(CLOCK, sp["clock"], "w")
                            meta["pokes"].append([n, scr, hex(CLOCK), sp["clock"]])
                        if sp.get("tie"):
                            ga, = bl.read(f"[0x{GOALS[0]:x}].w")
                            bl.write(GOALS[1], ga, "w")
                            meta["pokes"].append([n, scr, hex(GOALS[1]), ga])
                if attract:
                    if scr == 4:
                        demo += 1
                        demo_passes = 0
                        visit += 1
                    elif scr == 1 and demo:
                        if pressed:
                            bl.release(1, "A")
                            break
                    continue
                if screens and recording:
                    bl.command(f"set inph {0 if scr in (4, 5, 6) else 1}")   # screens: every sprite logged
                    if scr not in (4, 5, 6):
                        screen_record(SCREEN_CALL, scr, tick, 0)
                if scr in (4, 5, 6):
                    visit += 1
                    if vb is not None:
                        vblank_off(vb)
                        vb = None
                    if start_down:
                        bl.release(pulse_pad, "START")
                        start_down = False
                    if tourer is not None:
                        release_all()
                        tourer.rink()
                    continue
                if tourer is not None:
                    release_all()
                    tourer.enter(scr, prev_scr)
                    if vb is None:
                        vb = vblank_on()
                    continue
                # the instant replay from the pause menu takes the pausing pad's buttons only
                new_pad = last_pause_pad + 1 if scr == 7 and last_pause_pad is not None else 1
                if new_pad != pulse_pad and start_down:
                    bl.release(pulse_pad, "START")
                    start_down = False
                pulse_pad = new_pad
                if vb is None:
                    release_all()
                    vb = vblank_on()
                    ticks = 0
                    pulse = PULSE.get(scr, 40)
                continue
            if a == VBLANK:
                ticks += 1
                if pause is not None:          # the pause menu's busy loop
                    if ticks == 20 or (ticks - 20) % 90 == 0 and ticks > 20:
                        offered, = bl.read(f"[0x{PAUSE_OFFER:x}].w")
                        b = pause["driver"].choose(bool(offered)) if ticks == 20 else "START"
                        pause.setdefault("buttons", []).append(b)
                        pause["offered"] = offered
                        bl.press(pause["driver"].pad + 1, b)
                        pause["down"] = b
                    elif pause.get("down") and (ticks - 20) % 90 == 6:
                        bl.release(pause["driver"].pad + 1, pause["down"])
                        pause["down"] = None
                    continue
                if tourer is not None:
                    want = tourer.tick(bl.read(*tourer.exprs()))
                    for p in range(4):
                        down, up = want[p] - held[p], held[p] - want[p]
                        if up:
                            bl.release(p + 1, *sorted(up))
                        if down:
                            bl.press(p + 1, *sorted(down))
                        held[p] = want[p]
                    continue
                if ticks % pulse == 0:
                    bl.press(pulse_pad, "START")
                    start_down = True
                elif ticks % pulse == 6 and start_down:
                    bl.release(pulse_pad, "START")
                    start_down = False
                continue
            if a in SCREEN_SITES and screens:
                if recording:
                    d0, tick, scr = bl.read("d0", "[0xffca56].l", "[0xffb05e].w")
                    screen_record(a, scr, tick, d0)
                continue
            if a == PAUSE_OPEN:
                d2, tick = bl.read("d2", "[0xffca56].l")
                release_all()
                d2 &= 0xFFFF               # the pad's offset is a word (the high word is stale)
                drv = next((d for d in pausing if 2 * d.pad == d2), None)
                if drv is None:           # another pad paused (not ours): resume
                    drv = pausing[0]
                pause = {"driver": drv, "pass": n, "tick": tick, "bp": vblank_on()}
                last_pause_pad = drv.pad
                ticks = 0
                continue
            if a == PAUSE_DONE:
                r, tick = bl.read("d0", "[0xffca56].l")
                if pause is not None:
                    if pause.get("down"):
                        bl.release(pause["driver"].pad + 1, pause["down"])
                    vblank_off(pause["bp"])
                    meta["pauses"].append([pause["pass"], pause["tick"], tick, r & 0xFFFF,
                                           pause.get("offered", 0), pause.get("buttons", [])])
                    pause = None
                continue
            if a == SEG_START and not recording:
                lean_passes += 1
                bl.command(f'save/b "{tmp}" [0x{SNAP[0]:x}] {SNAP[1]}')
                s = Snap(tmp.read_bytes())
                for d in drivers:
                    want = d.step(s)
                    p = d.pad
                    down, up = want - held[p], held[p] - want
                    if up:
                        bl.release(p + 1, *sorted(up))
                    if down:
                        bl.press(p + 1, *sorted(down))
                    held[p] = want
                continue
            if a == SEG_START:
                e, scr = bl.read("[a7].w", "[0xffb05e].w")
                for k in arrays:
                    bl.command(f"append {k} {MARK}")
                    bl.command(f"append {k} {n}")
                s = Snap(save(start, SNAP))
                cur = {"pass": n, "screen": scr, "e": e & 0xFFFF, "visit": visit, "ai": []}
                # the pads for the next pass (read by read_joypads after this one)
                for d in drivers:
                    want = d.step(s)
                    p = d.pad
                    down, up = want - held[p], held[p] - want
                    if up:
                        bl.release(p + 1, *sorted(up))
                    if down:
                        bl.press(p + 1, *sorted(down))
                    held[p] = want
                if attract and demo:
                    demo_passes += 1
                    limit = attract_press[min(demo, len(attract_press)) - 1]
                    if not pressed and demo_passes >= limit:
                        bl.press(1, "A")
                        pressed = True
                        meta["presses"].append([n, "A"])
                continue
            if cur is None:
                continue
            if a == SEG_MID:
                save(mid, AI_SNAP)
            elif a in AI_PRE or a in AI_POST:
                a5, = bl.read("a5")
                save(ai, AI_SNAP)
                cur["ai"].append([a, a5 & 0xFFFFFF, n_ai])
                n_ai += 1
            elif a == SEG_END:
                save(end, SNAP)
                for k in arrays:
                    bl.command(f"append {k} {MARK_END}")
                    bl.command(f"append {k} {n}")
                meta["passes"].append(cur)
                cur = None
                n += 1
                if n % 500 == 0:
                    print(name, "pass", n, f"{time.monotonic() - t0:.0f}s", flush=True)
        fin = bl.read("[0xffca56].l", "[0xffb05e].w", f"[0x{PHASE:x}].w", "pc")
        if tourer is not None:
            meta["tour"] = {"log": tourer.log, "counts": dict(tourer.counts), "menu_setup": tourer.menu_setup}
        meta["end"] = {"tick": fin[0], "screen": fin[1], "phase": fin[2], "pc": fin[3], "lean_passes": lean_passes,
                       "seconds": round(time.monotonic() - t0, 1)}
        widths = arrays if recording else {}
        arrays = {k: bl.array(k, tmp) for k in widths}
    for f in (start, mid, end, ai, *([scr_f] if scr_f else [])):
        f.close()
    if cur is not None:          # an unfinished pass: drop its start snapshot record
        pass
    tmp.unlink(missing_ok=True)
    logs: dict[str, dict[int, list]] = {}
    screen_logs: dict[str, dict[int, list]] = {}
    for k, arr in arrays.items():
        width = widths[k]
        per: dict[int, list] = {}    # pass -> [segment entries, entries after the segment]
        per_screen: dict[int, list] = {}    # screen pass -> entries (recorder v5)
        c = None
        sc = None
        part = 0
        i = 0
        while i < len(arr):
            if arr[i] in (MARK, MARK_END, MARK_SCREEN) and i + 1 < len(arr):
                if arr[i] == MARK:
                    c = arr[i + 1]
                    per[c] = [[], []]
                    part = 0
                    sc = None
                elif arr[i] == MARK_END:
                    part = 1
                    sc = None
                else:
                    sc = arr[i + 1]
                    per_screen[sc] = []
                i += 2
                continue
            if sc is not None:
                per_screen[sc].append(arr[i:i + width])
            elif c is not None:
                per[c][part].append(arr[i:i + width])
            i += width
        logs[k] = per
        screen_logs[k] = per_screen
    meta["log_data"] = {k: {str(p): v for p, v in per.items() if p < len(meta["passes"])} for k, per in logs.items()}
    if screens:
        meta["screen_log_data"] = {k: {str(p): v for p, v in per.items()} for k, per in screen_logs.items()}
    meta["count"] = len(meta["passes"])
    meta["seconds"] = round(time.monotonic() - t0, 1)
    (out_dir / "meta.json").write_text(json.dumps(meta))
    return out_dir


def _draw_logs(bl: LiveBlastEm) -> None:
    """Recorder v4: the ``DRAW_LOGS`` arrays, the share markers and the
    debugger variable ``inph`` (1 inside the share) that gates ``spr``."""
    bl.command("variable inph 0")
    for k, (width, calls) in DRAW_LOGS.items():
        bl.command(f"array {k}")
        for kind, (addr, exprs, cond) in calls.items():
            vals = [str(kind), *exprs] + ["0"] * (width - 1 - len(exprs))
            assert len(vals) == width, (k, kind)
            bl.on_hit(addr, [f"append {k} {v}" for v in vals], condition=cond)

    def marker(kind: int, value: int) -> list[str]:
        out = []
        for k, (width, _) in DRAW_LOGS.items():
            out += [f"append {k} {kind}", f"append {k} {value}"] + [f"append {k} 0"] * (width - 2)
        return out
    bl.on_hit(SHARE_START, ["set inph 1", *marker(0, 0)])
    bl.on_hit(SHARE_END, ["set inph 0", *marker(9, 0)])
    bl.on_hit(RINK_EXIT, ["set inph 0", *marker(9, 1)])


#: Recordings of soak runs (plan 10, `mw_harness.soak`): name -> (soak seed,
#: first rink visit recorded, visits recorded). Picked for what they
#: reach first (penalties, special plays, hazards, ...); see docs/compare.md.
SOAK_RUNS: dict[str, tuple[int, int, int]] = {
    "soak_22_v1": (22, 1, 3),      # penalty calls, waiting minors, phase 2, the box filled (screen 17)
    "soak_1_v5": (1, 5, 3),        # penalties: phase 2, a waiting minor cancelled, box releases, power play
    "soak_2_v11": (2, 11, 1),      # a power-play goal frees a player
    "soak_1_v10": (1, 10, 1),      # Waste the Goalie (phase 11)
    "soak_21_v4": (21, 4, 1),      # Waste the Ref (phase 12, screen 19)
    "soak_53_v7": (53, 7, 2),      # Jail Break
    "soak_5_v5": (5, 5, 1),        # a forfeit (phase 13)
    "soak_1_v4": (1, 4, 1),        # a fight called by the CPU (screen 18)
    "soak_2_v1": (2, 1, 1),        # a shark
    "soak_65_v1": (65, 1, 1),      # spikes: impaled, freed
    "soak_1_v1": (1, 1, 1),        # the Battle Net
    "soak_3_v2": (3, 2, 2),        # a timeout from the pause menu (co-op pads)
    "soak_3_v20": (3, 20, 1),      # Armed Force
    "soak_7_v6": (7, 6, 1),        # a stoppage (`$CA12`)
    "soak_2_v10": (2, 10, 1),      # the bribed referee frames an opponent (`$174E`)
    "soak_2_v4": (2, 4, 1),        # an exploding puck blows up (`$529A`)
    "soak_144_v15": (144, 15, 1),  # Jail Break with players in the box (`$A9F2`)
    "soak_3_v5": (3, 5, 2),        # play continues after an instant replay (screen 6, `$F8F0`)
}


#: Recorder v5 (plan 11): stretches of plan 11's soak runs recorded with the
#: screens between plays: name -> (seed, first rink visit, visits). A
#: recording plays its soak run exactly up to the first recorded rink visit;
#: from there it can take its own course (seen in most: the full recording's
#: stops inside the rink pass change what the soak's lean run did), so the
#: comments say what the recordings hold.
SCREEN_RUNS: dict[str, tuple[int, int, int]] = {
    "scr_1011_v19": (1011, 19, 2),  # special plays with Reserves, two pages (p1p2): positions, substitutions
    "scr_1033_v35": (1033, 35, 2),  # goal scoreboard's menu, the instant replay's controls
    "scr_1011_v12": (1011, 12, 2),  # substitution lists, both pages
    "scr_1001_v15": (1001, 15, 2),  # special plays (one page), period scoreboard -> game stats
    "scr_1001_v21": (1001, 21, 2),  # game over (15), player stats, slow replay
    "scr_1041_v10": (1041, 10, 2),  # a penalty walk watched, a human fight paused
    "scr_1009_v8": (1009, 8, 2),    # Waste the Ref: the referee cutscene (19), the new referee (17)
    "scr_1011_v7": (1011, 7, 2),    # the Zamboni's whip
    "scr_1019_v1": (1019, 1, 2),    # the replay played to its end
    "scr_1012_v7": (1012, 7, 2),    # message scoreboard's menu -> stats
    "scr_1122_v6": (1122, 6, 2),    # a knockout with penalties off, the replay from 17
    "scr_1125_v13": (1125, 13, 2),  # playoff game over (16) -> stats -> 16 -> the playoffs
    "scr_1112_v10": (1112, 10, 2),  # a forfeit: 17 -> game over (15)
    "scr_1500_v1": (1500, 1, 2),    # special plays with both pages (P1 + P2): done pages, back / stay
    "scr_1503_v12": (1503, 12, 2),  # special plays from 14 with 4 players, playoff game over (16)
    "scr_1501_v8": (1501, 8, 2),    # special plays from the pause menu (P3 mode, page B first), a knockout
    "scr_1309_v1": (1309, 1, 4),    # a playoff match from its start (P1): a knockout, penalties, Zamboni
    "scr_1317_v1": (1317, 1, 4),    # 4 players: a knockout, goals, special plays
    "scr_1334_v1": (1334, 1, 4),    # P1 from the menus: a knockout, special plays, stats, replay
    "scr_1347_v1": (1347, 1, 4),    # P1: a knockout and many detours
    "scr_1529_v1": (1529, 1, 4),    # P1 + P2: a knockout
    "scr_1315_v1": (1315, 1, 4),    # co-op playoffs 2 of 3: two knockouts, every detour
}


def soak_name(seed: int, visit: int) -> str:
    return f"soak_{seed}_v{visit}"


def record_soak(seed: int, visit: int, passes: int, folder: Path = REC_DIR, budget: float = 165.0,
                draws: bool = False, visits: int = 0, screens: bool = False, name: str | None = None) -> Path:
    """Soak run ``seed`` recorded in full from its rink visit ``visit`` (for
    ``visits`` rink visits; 0: up to ``passes``); ``screens``: with the
    screens between plays (recorder v5)."""
    from . import soak
    name = name or soak_name(seed, visit) + ("_d" if draws else "")
    return record(name, passes=passes, out_dir=folder / name, budget=budget, lean_until_visit=visit,
                  draws=draws or screens, visits=visits, screens=screens,
                  coverage=soak.targets(gen=2 if seed >= soak.GEN2 else 1),
                  **soak.record_args(soak.config_of(seed)))


def record_run(name: str, folder: Path = REC_DIR, passes: int | None = None, budget: float = 165.0) -> Path:
    """Record run ``name`` of ``RUNS``, ``RUNS3``, ``SOAK_RUNS`` or
    ``SCREEN_RUNS`` into ``folder / name`` (a v4 run takes its seed from the
    run it repeats)."""
    if name in SCREEN_RUNS:
        seed, visit, n = SCREEN_RUNS[name]
        return record_soak(seed, visit, passes or 10 ** 6, folder, budget, visits=n, screens=True, name=name)
    if name in SOAK_RUNS or name.endswith("_d") and name[:-2] in SOAK_RUNS:
        seed, visit, n = SOAK_RUNS[name.removesuffix("_d")]
        return record_soak(seed, visit, passes or 10 ** 6, folder, budget, draws=name.endswith("_d"), visits=n)
    seed = sum(RUNS3.get(name, {}).get("base", name).encode()) & 0xFFFF
    if name in RUNS3:
        spec = dict(RUNS3[name])
        spec.pop("base", None)
        setup, n = spec.pop("setup"), spec.pop("passes")
        return record(name, setup, passes or n, folder / name, seed=seed, budget=budget, **spec)
    setup, n = RUNS[name]
    return record(name, setup, passes or n, folder / name, seed=seed, budget=budget)


def load(path: Path) -> dict:
    """meta.json with the snapshots attached as bytes lists."""
    meta = json.loads((path / "meta.json").read_text())
    for k, size in (("start", SNAP[1]), ("mid", AI_SNAP[1]), ("end", SNAP[1]), ("ai", AI_SNAP[1])):
        data = gzip.open(path / f"{k}.bin.gz").read()
        meta[k] = [data[i:i + size] for i in range(0, len(data) - size + 1, size)]
    return meta


def main(args) -> None:
    folder = Path(args.out) if getattr(args, "out", None) else REC_DIR
    if getattr(args, "soak", None) is not None:
        p = record_soak(args.soak, args.from_visit, args.passes or 4000, folder,
                        budget=getattr(args, "budget", None) or 165.0)
        m = json.loads((p / "meta.json").read_text())
        print(p.name, m["count"], "passes", m["seconds"], "s", "from", m.get("recording_from"))
        return
    for name in args.names or RUNS:
        if name not in RUNS and name not in RUNS3 and name.removesuffix("_d") not in SOAK_RUNS \
                and name not in SCREEN_RUNS:
            raise SystemExit(f"unknown run {name!r}: {', '.join([*RUNS, *RUNS3, *SOAK_RUNS, *SCREEN_RUNS])}")
        p = record_run(name, folder, passes=args.passes, budget=getattr(args, "budget", None) or 165.0)
        m = json.loads((p / "meta.json").read_text())
        print(name, m["count"], "passes", m["seconds"], "s")
