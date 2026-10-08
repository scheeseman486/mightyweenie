"""Reference decoders (mw_harness.gfx, palettes) and the ROM catalogue.

Fast checks: formats on synthetic data, catalogue entries consistent with the
ROM, the catalogue and fixtures carrying no ROM content, and the GDScript
hash fixture being current. The checks against the original's VRAM/CRAM are
in test_gfx_original.py.
"""
import json
import struct
from pathlib import Path

import pytest

from mw_harness import gfx, palettes
from mw_harness.__main__ import gfx_hashes
from mw_harness.assets import Poke, parse_pokes
from mw_harness.rom import Rom

ROOT = Path(__file__).resolve().parents[2]
CATALOGUE = ROOT / "game/data/rom_catalogue.json"
HASHES = ROOT / "compare/fixtures/gfx_hashes.json"
CHECKPOINTS = ROOT / "compare/fixtures/gfx_checkpoints.json"


@pytest.fixture(scope="module")
def cat():
    return json.loads(CATALOGUE.read_text())


@pytest.fixture(scope="module")
def rom(mlh_rom_path):
    return Rom.load(mlh_rom_path)


# --- formats (synthetic) -----------------------------------------------------
def test_tile_high_nibble_is_left_pixel():
    data = bytes([0x12, 0x34]) + bytes(30)
    assert gfx.tile_indices(data)[:4] == bytes([1, 2, 3, 4])


def test_colour_words():
    assert gfx.color_rgb8(0x0000) == (0, 0, 0)
    assert gfx.color_rgb8(0x0EEE) == (255, 255, 255)
    assert gfx.color_rgb8(0x000E) == (255, 0, 0)       # red is the low nibble
    assert gfx.color_rgb8(0x0E00) == (0, 0, 255)


def test_name_table_word():
    c = gfx.Cell.from_word(0xF9FF)
    assert (c.priority, c.line, c.vflip, c.hflip, c.tile) == (True, 3, True, True, 0x1FF)


def test_piece_layout():
    # x, y, size (w-1 << 2 | h-1), attr (hflip bit 3, vflip bit 4, line 5-6), tile word
    raw = struct.pack(">bbBBH", -8, 5, (1 << 2) | 2, 0x08 | 0x10 | (2 << 5), 0x1234)
    p = gfx.Piece.parse(raw, 0)
    assert (p.x, p.y, p.width, p.height, p.hflip, p.vflip, p.line) == (-8, 5, 2, 3, True, True, 2)
    assert p.rom_address == 0x1234 << 5
    assert gfx.Piece.parse(struct.pack(">bbBBH", 0, 0, 0, 0, 0x7FF), 0).rom_address is None


def test_frame_tiles_are_column_major():
    # one 2x1-cell piece whose two ROM tiles are solid colours 1 and 2
    rom = bytearray(0x10000 + 64)
    rom[0x10000:0x10020] = bytes([0x11] * 32)
    rom[0x10020:0x10040] = bytes([0x22] * 32)
    frame = struct.pack(">H", 1) + struct.pack(">bbBBH", 0, 0, (1 << 2) | 0, 0, 0x10000 >> 5)
    rom[:len(frame)] = frame
    ox, oy, w, h, px = gfx.frame_image(bytes(rom), gfx.frame_pieces(bytes(rom), 0))
    assert (ox, oy, w, h) == (0, 0, 16, 8)
    assert px[0] == 1 and px[8] == 2


def synthetic_font() -> bytes:
    """Font at 0: baseline 2, space 3, char map at +$20 ('A' -> glyph 0 1x1
    tile at $10000, 'B' -> glyph 1 2x2 tiles at $10040), 2 glyphs."""
    rom = bytearray(0x10000 + 6 * 32)
    struct.pack_into(">hHHH", rom, 0, 2, 3, 0x20, 2)
    struct.pack_into(">bbBBH", rom, 8, 0, 0, 0, 0x60, 0x10000 >> 5)                 # attr ignored
    struct.pack_into(">bbBBH", rom, 14, 0, 0, (1 << 2) | 1, 0, 0x10040 >> 5)
    rom[0x20 - 0x21 + 0x21:0x20 - 0x21 + 0x7F] = bytes([0xFF]) * 0x5E
    rom[0x20 - 0x21 + ord("A")] = 0
    rom[0x20 - 0x21 + ord("B")] = 1
    rom[0x10000:0x10020] = bytes([0x11] * 32)
    for i in range(4):     # B's tiles: colours 2, 3, 4, 5 (column-major)
        rom[0x10040 + 32 * i:0x10060 + 32 * i] = bytes([0x22 + 0x11 * i] * 32)
    rom[0x100:0x108] = b"AB A?B\0\0"
    return bytes(rom)


def test_text_layout_on_the_baseline():
    rom = synthetic_font()
    text = gfx.rom_string(rom, 0x100)
    assert text == b"AB A?B"
    assert gfx.char_width(rom, 0, ord(" ")) == 3 and gfx.char_width(rom, 0, ord("?")) == 0
    assert gfx.text_width(rom, 0, text) == 1 + 2 + 3 + 1 + 0 + 2
    assert gfx.text_glyphs(rom, 0, text, 10, 7) == [
        (10, 8, 1, 1, 0x10000), (11, 7, 2, 2, 0x10040), (16, 8, 1, 1, 0x10000), (17, 7, 2, 2, 0x10040)]
    top, w, h, px = gfx.text_image(rom, 0, b"AB", line=1)
    assert (top, w, h) == (0, 24, 16)
    assert px[8 * 24] == 16 + 1            # 'A' in the bottom row, line 1
    assert px[0] == 0                      # above 'A': empty
    assert px[8] == 16 + 2 and px[8 * 24 + 8] == 16 + 3 and px[16] == 16 + 4   # column-major


def test_credit_page_strings():
    rom = bytearray(b"head\0line 1\0\0") + bytes(4)
    assert gfx.string_list(bytes(rom), 0) == [0, 5]
    assert gfx.string_list(b"\0one\0\0", 0) == [0, 1]


def test_colour_zero_is_transparent_in_pictures():
    img = bytearray(64)
    tile = bytes([0x10] * 32)                     # pixels alternate 1, 0
    gfx.blit_tile(img, 8, 0, 0, gfx.tile_indices(tile), 2, False, False)
    assert img[0] == 2 * 16 + 1 and img[1] == 0


def test_animation_variants():
    # 2 frames; variant 0 list at +12, variant 1 = same list mirrored (flips 1)
    rom = struct.pack(">HBBI", 0x20, 1, 2, 0x100) + struct.pack(">HH", (12 << 2) | 0, (12 << 2) | 1) \
        + struct.pack(">HH", 0, 8)
    an = gfx.Animation.parse(rom, 0)
    assert an.variants == ((12, 0), (12, 1)) and an.offsets_of(rom, 1) == (0, 8)
    assert an.frame_addresses(rom) == [0x100, 0x108]


def test_whole_frame_flip():
    p = gfx.Piece(-8, 4, 2, 1, 0, 0x800)
    (f,) = gfx.flip_pieces([p], 1)
    assert (f.x, f.y, f.hflip) == (-8, 4, True)            # -(-8 + 16) = -8
    (f,) = gfx.flip_pieces([gfx.Piece(0, 0, 1, 1, 0, 0x800)], 3)
    assert (f.x, f.y, f.hflip, f.vflip) == (-8, -8, True, True)


def test_poke_directive():
    text = "@screen 1 +200 P1 START\n#poke @screen 5 #2 +600 FFC60A.w=3\n#poke @screen 6 +1 B076.b=$1F\n"
    assert parse_pokes(text) == [Poke(5, 2, 600, 0xFFC60A, "w", 3), Poke(6, 1, 1, 0xB076, "b", 0x1F)]


# --- catalogue vs ROM ------------------------------------------------------------
def test_catalogue_is_for_this_rom(cat, rom):
    assert cat["format"] == "mw-rom-catalogue/1" and cat["rom_sha1"] == rom.sha1


def test_pictures_match_their_descriptors(cat, rom):
    for key, e in cat["entries"].items():
        if e["kind"] in ("picture", "tilebank"):
            p = gfx.Picture.parse(rom.data, e["address"])
            assert (p.tiles, p.vram_base, p.count) == (e["tiles"], e["vram_base"], e["count"]), key
            if e["kind"] == "picture":
                assert (p.width, p.height, p.map_address) == (e["width"], e["height"], e["map"]), key


def test_rink_picture(cat):
    # the reference case from the research: rink at $24CFC (docs/re/graphics.md)
    e = cat["entries"]["picture_024cfc"]
    assert (e["tiles"], e["vram_base"], e["count"], e["width"], e["height"]) == (0x28588, 1, 990, 64, 113)


def test_animations_and_frames_parse(cat, rom):
    frames = [a for group in cat["frames"].values() for a in group]
    for key, e in cat["entries"].items():
        if e["kind"] == "anim":
            an = gfx.Animation.parse(rom.data, e["address"])
            assert (an.count, len(an.variants), an.frames_address) == (e["frames"], e["variants"], e["frame_data"]), key
            frames += an.frame_addresses(rom.data)
    for a in frames:
        n = struct.unpack_from(">H", rom.data, a)[0]
        assert a < 0x200000 and 1 <= n <= 32, hex(a)
    for g in cat["pieces"].values():                  # single pieces: ROM tiles
        assert all(gfx.Piece.parse(rom.data, a).rom_address for a in g["pieces"])


def test_catalogue_holds_no_rom_content(cat):
    """Only numbers, short names and lists of addresses: no byte strings,
    no pixel or map data (docs/architecture.md, Assets)."""
    def walk(v, path):
        if isinstance(v, dict):
            for k, x in v.items():
                walk(x, f"{path}.{k}")
        elif isinstance(v, list):
            for i, x in enumerate(v):
                walk(x, f"{path}[{i}]")
        elif isinstance(v, str):     # names, comments, a SHA-1 - never a hex dump
            assert len(v) <= 200 and (len(v) <= 40 or not all(c in "0123456789abcdefABCDEF" for c in v)), path
        else:
            assert isinstance(v, (int, float, bool)) or v is None, path
    walk(cat, "catalogue")
    for e in cat["entries"].values():           # any long int list must be addresses (frames/pieces)
        assert all(not isinstance(v, list) or len(v) < 300 for v in e.values())


def test_hash_fixture_is_current(cat, rom):
    """compare/fixtures/gfx_hashes.json (what the GDScript decoders must
    reproduce) matches the Python decoders on the catalogue."""
    assert json.loads(HASHES.read_text()) == gfx_hashes(rom, cat), \
        "regenerate: tools/bin/py -m mw_harness gfx-hashes"


# --- palette builders ------------------------------------------------------------------
def test_screen_palette_layout(rom):
    p = palettes.screen_palette(rom.data, 4, 22, 22)
    ice = struct.unpack_from(">16H", rom.data, palettes.ice_palette(rom.data, 22))
    assert p[0:8] == list(ice[:8]) and p[16 + 11] == p[32 + 11] == p[5]
    team = palettes.team_record(22) + 0x80
    assert p[16 + 2:16 + 4] == list(struct.unpack_from(">2H", rom.data, team))


def test_regional_pair_only_on_flagged_screens(rom):
    assert palettes.colour_pair(rom.data, 4, pal=True) != palettes.colour_pair(rom.data, 4, pal=False)
    assert palettes.colour_pair(rom.data, 1, pal=True) == palettes.colour_pair(rom.data, 1, pal=False)


def test_checkpoint_fixture_shape():
    cps = json.loads(CHECKPOINTS.read_text())
    names = [c["name"] for c in cps]
    assert len(names) == len(set(names)) >= 15
    for c in cps:
        assert set(c) >= {"name", "script", "at", "cram", "loaded", "tiles_min", "shown_min"}
        assert (ROOT / "compare/scripts" / f"{c['script']}.mwi").exists()
