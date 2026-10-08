"""Stadium records (docs/re/rinks.md): the parser's layout, checked against the
ROM's own structure and against what the game copies into RAM."""
import pytest

from mw_harness import ReferenceEmulator, Rom
from mw_harness.stadiums import TEAM_COUNT, all_stadiums

RINK_STATE = 0xFFB0E8          # +0: pointer to the stadium record in use
CROWD_BYTE = 0xFFB360
SETUP_STADIUM = 0xFFB0E4


@pytest.fixture(scope="module")
def stadiums(mlh_rom_path):
    return all_stadiums(Rom.load(mlh_rom_path))


def test_records_are_contiguous(stadiums):
    """Variable-length records follow each other in team order, so the layout
    (header size, placement size and counts) must chain exactly."""
    assert len(stadiums) == TEAM_COUNT
    for a, b in zip(stadiums, stadiums[1:]):
        assert a.end == b.address


def test_ice_hazard_kinds_match_mask(stadiums):
    for s in stadiums:
        ice_bits = {p.kind - 1 for p in s.ice}
        assert ice_bits == {b for b in range(4) if s.hazard_mask >> b & 1}
        assert all(1 <= p.kind <= 4 for p in s.ice)
        assert bool(s.objects) == bool(s.hazard_mask & 0xF0)


def test_field_ranges(stadiums):
    assert {s.palette for s in stadiums} == set(range(6))
    assert {s.net_style for s in stadiums} == {1, 2}
    assert {s.object_offset for s in stadiums} == {-24}
    assert {s.crowd_byte for s in stadiums} == {0, 1}


@pytest.mark.parametrize("stadium", [0, 5, 19])
def test_game_uses_the_selected_record(mlh_rom_path, stadiums, stadium):
    with ReferenceEmulator(mlh_rom_path) as emu:
        while not (emu.frame > 6450 and emu.state(with_cpu=False).ram_u16(0xFFB05E) == 1):
            emu.step()
        emu.poke(SETUP_STADIUM, stadium)
        for _ in range(5):
            emu.step("START")
        while emu.state(with_cpu=False).ram_u16(0xFFB05E) != 4:
            emu.step()
        s = emu.state(with_cpu=False)
    assert s.ram_u32(RINK_STATE) == stadiums[stadium].address
    assert s.ram_u8(CROWD_BYTE) == stadiums[stadium].crowd_byte
