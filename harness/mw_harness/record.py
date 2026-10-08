"""Pass records of the original (format mw-pass/1, docs/compare.md).

:func:`record_original` plays an input script on the original in BlastEm
(EA 4-Way Play attached) and writes one line per completed pass, with exact
pass boundaries: a breakpoint at every loop wait exit. Script presses are
applied at VBlank (tick start), screen entries and boundaries, following
:class:`~mw_harness.script.ScriptPlayer`.

:func:`screen_entries_gpgx` plays the same script on Genesis Plus GX at frame
resolution (two pads, no 4-Way Play) for cross-checking the screen flow.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from .blastem_live import LiveBlastEm
from .probes import BUILTIN, ProbeSet
from .rom import Rom, default_rom_path
from .script import PAD_BITS, PLAYERS, Script, ScriptPlayer

VBLANK = 0x13F96            # IRQ6_VBlank: tick_counter is incremented inside
SCREEN_CALL = 0x20AC        # run_screens: jsr (a0) with $FFB05E = new screen, D7 = previous
PLAYER_STATS = 0xD168       # screen 9 handler, called by screen 8 ...
PLAYER_STATS_RETURN = 0xCD2A  # ... and returning here
#: Loop wait exits (docs/re/timing.md). True: D0 holds the pass's elapsed ticks.
WAIT_EXITS = {0x00DA6: True, 0x0103E: False, 0x0108E: True, 0x08D7C: True, 0x0B1F4: False,
              0x0D1F0: True, 0x0D8E6: True, 0x0E43C: True, 0x0E6CE: True, 0x0F96E: True,
              0x11B9C: True, 0x121EC: True, 0x1295C: True, 0x13AD0: True, 0x09E70: True,
              # loops that sync to the VBlank-drained DMA queue ($148A8) instead of the tick counter
              0x13830: False,   # main menu (1)
              0x0C340: False,   # team description (2)
              0x0CC02: False,   # game stats (8)
              0x1098E: False}   # special plays (10)
RINK_SCREENS = (4, 5, 6)
SAFETY_TICKS = 100_000      # ~28 minutes of game time
TICKS, SCREEN_ID, PADS_12, PADS_34, PHASE = "[0xffca56].l", "[0xffb05e].w", "[0xffca5a].l", "[0xffca5e].l", "[0xffc60a].w"


def _names(mask: int) -> list[str]:
    return [n for n, b in PAD_BITS.items() if mask & b]


def _line(d: dict) -> str:
    return json.dumps(d, separators=(", ", ": "))


def record_original(script: Script, probes: list[ProbeSet], out: Path | None = None, rom: Path | None = None,
                    m68k_divider: int = 7, max_ticks: int | None = None, name: str = "") -> list[dict]:
    """Play ``script`` on the original; return (and write to ``out``) the records."""
    rom = Path(rom) if rom else default_rom_path()
    extra = [f for ps in probes for f in ps.fields if f.original != BUILTIN]
    player = ScriptPlayer(script)
    header = {"format": "mw-pass/1", "side": "original", "rom_sha1": Rom.load(rom).sha1,
              "script": name or script.name, "probes": [p.name for p in probes],
              "tool": f"blastem ea_multitap divider {m68k_divider}"}
    records: list[dict] = [header]
    bound = [0] * (PLAYERS + 1)          # what BlastEm currently has pressed
    stack: list[tuple[int, int]] = []    # logical screens (screen, visit); 9 sits on top of 8
    visits: dict[int, int] = {}
    passes: dict[tuple[int, int], int] = {}
    last_tick: dict[tuple[int, int], int] = {}

    def sync(bl: LiveBlastEm) -> None:
        for p in range(1, PLAYERS + 1):
            want = player.held(p)
            if want != bound[p]:
                bl.press(p, *_names(want & ~bound[p]))
                bl.release(p, *_names(bound[p] & ~want))
                bound[p] = want

    def enter(screen: int, tick: int, prev: int, push: bool) -> None:
        visit = visits[screen] = visits.get(screen, 0) + 1
        if push:
            stack.append((screen, visit))
        else:
            stack[:] = [(screen, visit)]
        last_tick[(screen, visit)] = tick
        records.append({"event": "screen", "screen": screen, "visit": visit, "tick": tick, "prev": prev})
        player.screen_entered(screen, tick)

    with LiveBlastEm(rom, m68k_divider) as bl:
        for a in (VBLANK, SCREEN_CALL, PLAYER_STATS, PLAYER_STATS_RETURN, *WAIT_EXITS):
            bl.breakpoint(a)
        tick = 0
        while True:
            a = bl.cont()
            if a == VBLANK:
                tick = bl.read(TICKS)[0] + 1
                player.tick_start(tick)
                if player.ended or (max_ticks is not None and tick >= max_ticks):
                    break
                if max_ticks is None and tick >= SAFETY_TICKS:
                    raise RuntimeError(f"script did not reach END by tick {tick}; add END or pass max_ticks")
            elif a == SCREEN_CALL:
                screen, prev, tick = bl.read(SCREEN_ID, "d7", TICKS)
                enter(screen, tick, prev & 0xFFFF, push=False)
            elif a == PLAYER_STATS:
                tick = bl.read(TICKS)[0]
                enter(9, tick, stack[-1][0] if stack else -1, push=True)
            elif a == PLAYER_STATS_RETURN:
                if len(stack) > 1:
                    stack.pop()
                    records.append({"event": "resume", "screen": stack[-1][0], "visit": stack[-1][1],
                                    "tick": bl.read(TICKS)[0]})
                    player.resume(*stack[-1])
            else:
                if not stack:            # a wait before the first screen (not expected)
                    continue
                vals = bl.read(TICKS, "d0", PADS_12, PADS_34, PHASE, *[f.original for f in extra])
                tick, d0, p12, p34, phase = vals[:5]
                key = stack[-1]
                n = passes.get(key, 0)
                passes[key] = n + 1
                elapsed = (d0 & 0xFFFF) if WAIT_EXITS[a] else tick - last_tick[key]
                last_tick[key] = tick
                rec = {"screen": key[0], "visit": key[1], "pass": n, "tick": tick, "elapsed": elapsed,
                       "pads": [p12 >> 16, p12 & 0xFFFF, p34 >> 16, p34 & 0xFFFF], "site": a}
                if key[0] in RINK_SCREENS:
                    rec["phase"] = phase
                for f, v in zip(extra, vals[5:]):
                    if f.applies(key[0]):
                        rec[f.name] = v
                records.append(rec)
                player.boundary(key[0], key[1], n, tick)
            sync(bl)
        records.append({"event": "end", "tick": tick})
    if out is not None:
        write(records, out)
    return records


def write(records: list[dict], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("".join(_line(r) + "\n" for r in records))


def read(path: Path) -> list[dict]:
    return [json.loads(l) for l in Path(path).read_text().splitlines() if l.strip()]


def cache_key(script_text: str, probes: list[str], rom_sha1: str, settings: str) -> str:
    h = hashlib.sha1()
    for part in (script_text, ",".join(probes), rom_sha1, settings, Path(__file__).read_text()):
        h.update(part.encode())
    return h.hexdigest()[:16]


def screen_entries_gpgx(script: Script, frames: int, rom: Path | None = None) -> list[tuple[int, int, int]]:
    """(screen, visit, tick) entries when ``script`` runs on Genesis Plus GX.

    Frame resolution: the screen ID is sampled after each frame, and every frame
    counts as one pass for the script player, which is right for menus (one pass
    per tick) and approximate elsewhere. Two pads only.
    """
    from .emulator import ReferenceEmulator

    player = ScriptPlayer(script)
    entries, visits, cur, n = [], {}, None, 0
    with ReferenceEmulator(rom) as emu:
        while emu.frame < frames and not player.ended:
            emu.step_players([_names(player.held(1)), _names(player.held(2))])
            s = emu.state(with_cpu=False)
            tick, sid = s.ram_u32(0xFFCA56), s.ram_u16(0xFFB05E)
            if emu.frame > 300 and tick > 0 and (cur is None or sid != cur[0]):
                visits[sid] = visits.get(sid, 0) + 1
                cur, n = (sid, visits[sid]), 0
                entries.append((sid, visits[sid], tick))
                player.screen_entered(sid, tick)
            player.tick_start(tick + 1)
            if cur is not None:
                player.boundary(cur[0], cur[1], n, tick + 1)
                n += 1
    return entries
