"""Plan 07: the rink recordings' decoding and the committed rink fixtures."""
import json
import struct

import pytest

from mw_harness.rink_fixtures import FIXTURES
from mw_harness.rink_record import REGIONS, STANDARD_RUNS
from mw_harness.rink_state import NONE, decode, plate_tiles, plates, sprite_list
from mw_harness.rom import Rom, default_rom_path

DRAW = json.loads((FIXTURES / "rink_draw.json").read_text())
CAMERA = json.loads((FIXTURES / "rink_camera.json").read_text())


@pytest.fixture(scope="module")
def rom():
    try:
        return Rom.load(default_rom_path()).data
    except FileNotFoundError:
        pytest.skip("ROM not installed")


@pytest.mark.parametrize("values", [(13, 0, 32), (99, 5, 0), (7, 3, 12), (40, 1, NONE), (NONE, NONE, NONE)])
def test_plate_values_survive_the_round_trip(rom, values):
    data = b"".join(plate_tiles(rom, *values) if i == 2 else bytes(256) for i in range(4))
    got = plates(rom, data)
    assert got[2] == list(values)
    assert got[0] == [NONE, NONE, NONE]


def test_plate_layout(rom):
    p = plate_tiles(rom, 42, 5, 12)
    assert p[32 + 4:32 + 8] == bytes([0x11] * 4)          # bottom row, 12 yellow pixels...
    assert p[96 + 4:96 + 8] == bytes([0x11, 0x11, 0x77, 0x77])
    assert p[160 + 4:160 + 8] == bytes([0x77] * 4)        # ... then red
    assert p[128:160] == bytes(32)                        # column 2 of the top row stays empty


def test_sprite_list_follows_the_links():
    sprites = bytearray(0x280)
    depths = bytearray(0x140)
    # head -> 2 -> 1
    struct.pack_into(">HBBHH", sprites, 0, 0, 0, 2, 0, 0)
    struct.pack_into(">HBBHH", sprites, 8, 0x90, 0x05, 0, 0x6123, 0xA0)
    struct.pack_into(">HBBHH", sprites, 16, 0x91, 0x0F, 1, 0xE456, 0xB0)
    struct.pack_into(">HH", depths, 4, 3, 0)
    struct.pack_into(">HH", depths, 8, 9, 0)
    got = sprite_list({"sprites": bytes(sprites), "depths": bytes(depths)})
    assert got == [[0xB0, 0x91, 0x0F, 0xE0, 9], [0xA0, 0x90, 0x05, 0x60, 3]]


def test_decode_reads_the_regions():
    ram = {k: bytes(n) for k, (a, n) in REGIONS.items()}
    o = bytearray(ram["objects"])
    struct.pack_into(">hh", o, 4, 96, 293)                      # plane B camera
    struct.pack_into(">I", o, 0xB3C2 + 0x18 - 0xB0B2, 0x3C8D4)  # puck animation
    o[0xB3C2 + 0x3D - 0xB0B2] = 1
    struct.pack_into(">H", o, 0xB3C2 + 0x24 - 0xB0B2, 0xB46E + 2 * 0x76)
    ram["objects"] = bytes(o)
    s = decode({k: tuple(v) for k, v in REGIONS.items()}, ram)
    assert s["camera"]["shown"] == [96, 293]
    assert s["puck"]["anim"][0] == 0x3C8D4
    assert s["puck"]["carrier"] == {"kind": "player", "team": 0, "slot": 2}
    assert len(s["teams"]) == 2 and len(s["teams"][1]["players"]) == 6


def test_standard_runs_pick_their_stadium_by_team_a():
    for name, (setup, _human, _n) in STANDARD_RUNS.items():
        assert setup[0xFFB0DE] == setup[0xFFB0E4], name


def test_draw_fixture_shape():
    assert len(DRAW["passes"]) >= 20 and len(DRAW["setups"]) == len(STANDARD_RUNS)
    stadiums = {p["state"]["stadium"] for p in DRAW["passes"]}
    assert len(stadiums) >= 5
    for p in DRAW["passes"]:
        assert all(len(c) == 5 for c in p["calls"] + p["adds"])
        assert len(p["sprites"]) <= 79
        depths = [s[4] for s in p["sprites"]]
        assert depths == sorted(depths, reverse=True), p["name"]      # link order = depth order


def test_camera_fixture_is_consecutive():
    assert len(CAMERA["sequences"]) >= len(STANDARD_RUNS)
    for seq in CAMERA["sequences"]:
        ps = seq["passes"]
        for a, b in zip(ps, ps[1:]):
            assert b["before"] == a["after"], seq["name"]
