"""Golden behaviour of the original, recorded in plan 01 (docs/re/screens.md,
docs/re/timing.md). These pin our understanding: if one fails after a harness
change, the harness changed; if we're wrong about the game, fix the doc too.
"""
import pytest

from mw_harness import ReferenceEmulator
from mw_harness.emulator import InputScript
from mw_harness.fades import find_fades
from mw_harness.trace import BLASTEM, Probe, run_trace

START_GAME = InputScript.parse("6500-6505:START")
GAMEPLAY_WAIT_EXIT = 0xF96E  # D0 = elapsed ticks of the pass


@pytest.fixture(scope="module")
def start_game_run(mlh_rom_path):
    """GPGX: boot, title, menu, START, first faceoff (9,000 frames)."""
    samples, screens, last = [], [], None
    with ReferenceEmulator(mlh_rom_path) as emu:
        for _ in range(9000):
            emu.step(START_GAME.buttons_at(emu.frame))
            s = emu.state(with_cpu=False)
            sid = s.ram_u16(0xFFB05E)
            samples.append((emu.frame, s.ram_u32(0xFFCA56), sid, s.cram))
            if sid != last:
                screens.append((emu.frame, sid))
                last = sid
    return samples, screens


def test_screen_sequence(start_game_run):
    _, screens = start_game_run
    assert screens == [(1, 0), (6309, 1), (6535, 3), (6875, 4), (8930, 5)]


def test_fades_are_28_ticks(start_game_run):
    samples, _ = start_game_run
    fades = [(f.direction, f.start_frame, f.ticks, f.screen) for f in find_fades(samples)]
    assert fades == [
        ("in", 461, 28, 0), ("out", 642, 28, 0), ("in", 677, 28, 0),     # title
        ("out", 2775, 28, 0), ("in", 2808, 28, 0), ("out", 6252, 56, 0),  # credits
        ("in", 6313, 28, 1), ("out", 6507, 28, 1),                        # main menu
        ("in", 6541, 28, 3), ("out", 6847, 28, 3),                        # matchup
        ("in", 6886, 28, 4), ("out", 8902, 28, 4),                        # period start
        ("in", 8941, 28, 5),                                              # play
    ]


def _gameplay_elapsed(divider):
    ev = run_trace([Probe(GAMEPLAY_WAIT_EXIT, "pass", ["d0"])], frames=9500,
                   inputs=START_GAME, m68k_divider=divider)
    return [e.values[0] & 0xFFFF for e in ev]


@pytest.mark.skipif(not BLASTEM.exists(), reason="BlastEm not fetched")
def test_gameplay_pass_length_stock(mlh_rom_path):
    """Stock 68000: passes take 2-7 ticks, ~3.5 on average (~17 fps)."""
    el = _gameplay_elapsed(7)
    assert len(el) > 500 and set(el) <= set(range(1, 9))
    assert 3.0 <= sum(el) / len(el) <= 4.2


@pytest.mark.skipif(not BLASTEM.exists(), reason="BlastEm not fetched")
def test_gameplay_pass_length_overclocked(mlh_rom_path):
    """x2.33 68000 clock: passes drop to 1-2 ticks (~40+ fps), as on modded hardware."""
    el = _gameplay_elapsed(3)
    assert sum(el) / len(el) < 2.0
