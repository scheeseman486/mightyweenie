"""Screen paths and inputs found in plan 01 (docs/re/screens.md, docs/re/input.md).

Each test drives the original to a screen the way a player would (pokes only
where noted, to skip minutes of play) and checks the screen IDs it passes.
"""
import pytest

from mw_harness import ReferenceEmulator
from mw_harness.emulator import InputScript

SCREEN_ID = 0xFFB05E
GAME_PHASE = 0xFFC60A
PAD_MODE = 0xFFB0E0
TIMEOUT_OFFERED = 0xFFB094
TEAM_A = 0xFFB402
ARMED_SPECIAL_PLAY = 0x4A5      # team struct offset
WASTE_THE_REF = 10


def sid(emu):
    return emu.state(with_cpu=False).ram_u16(SCREEN_ID)


def phase(emu):
    return emu.state(with_cpu=False).ram_u16(GAME_PHASE)


def press(emu, button, frames=4, then=0):
    for _ in range(frames):
        emu.step(button)
    emu.run(then)


def step_until(emu, pred, limit, buttons=lambda emu: None):
    end = emu.frame + limit
    while emu.frame < end:
        emu.step(buttons(emu))
        if pred(emu):
            return True
    return False


def to_main_menu(emu):
    assert step_until(emu, lambda e: sid(e) == 1 and e.frame > 6400, 9000)
    emu.run(30)


def to_open_play(emu, settle=120):
    """Main menu -> Start -> first faceoff -> `settle` frames of open play (phase 0)."""
    to_main_menu(emu)
    press(emu, "START", 5)
    n = [0]

    def open_play(e):
        n[0] = n[0] + 1 if (sid(e) == 5 and phase(e) == 0) else 0
        return n[0] >= settle
    assert step_until(emu, open_play, 8000)


def test_pad_row_cycles_pad_modes_without_adapter(mlh_rom_path):
    with ReferenceEmulator(mlh_rom_path) as emu:
        to_main_menu(emu)
        press(emu, "DOWN", 4, 30)
        seen = []
        for _ in range(3):
            press(emu, "RIGHT", 4, 30)
            seen.append(emu.state(with_cpu=False).ram_u8(PAD_MODE))
    assert seen == [1, 2, 0]      # modes 3/4 need the 4-Way Play adapter


@pytest.fixture(scope="module")
def paused(mlh_rom_path):
    """Savestate with the pause menu open and B - TIMEOUT offered."""
    with ReferenceEmulator(mlh_rom_path) as emu:
        to_open_play(emu)
        for _ in range(40):
            press(emu, "START", 4, 40)
            if emu.state(with_cpu=False).ram_u16(TIMEOUT_OFFERED):
                return emu.save(), emu.frame
            press(emu, "START", 4, 30)                     # resume, try again later
            n = [0]

            def open_play(e):
                n[0] = n[0] + 1 if phase(e) == 0 else 0
                return n[0] >= 120
            step_until(emu, open_play, 3000)
    pytest.fail("timeout never offered")


def test_pause_replay_then_continue(mlh_rom_path, paused):
    blob, frame = paused
    with ReferenceEmulator(mlh_rom_path) as emu:
        emu.load(blob, frame)
        press(emu, "A")
        assert step_until(emu, lambda e: sid(e) == 7, 300)
        emu.run(300)
        press(emu, "START")
        assert step_until(emu, lambda e: sid(e) != 7, 600)
        assert sid(emu) == 6


def test_pause_timeout_opens_special_plays(mlh_rom_path, paused):
    blob, frame = paused
    with ReferenceEmulator(mlh_rom_path) as emu:
        emu.load(blob, frame)
        press(emu, "B")
        assert step_until(emu, lambda e: sid(e) == 10, 300)
        emu.run(60)
        press(emu, "START")
        assert step_until(emu, lambda e: sid(e) != 10, 600)
        assert sid(emu) == 5


def test_waste_the_ref_plays_19_then_17(mlh_rom_path):
    """Poke: arm 'Waste the Ref' for team A, then P1 holds A when it has the puck."""
    with ReferenceEmulator(mlh_rom_path) as emu:
        to_open_play(emu, settle=1)
        emu.poke(TEAM_A + ARMED_SPECIAL_PLAY, WASTE_THE_REF)
        hold_a = lambda e: "A" if e.frame % 34 < 30 else None   # noqa: E731
        assert step_until(emu, lambda e: phase(e) == 12, 3000, hold_a)
        screens = [sid(emu)]
        for _ in range(900):
            emu.step()
            if sid(emu) != screens[-1]:
                screens.append(sid(emu))
    assert screens == [5, 19, 17]
