"""Palette builders: how the original composes CRAM from ROM pieces.

Most screens don't load a palette from the ROM as is. They build lines on
the stack from a default palette, the stadium's ice colours, the teams'
colour words and a per-screen colour pair, then hand them to the fade
(``$1498C``: fade line D2 towards 16 colours at A0). These functions mirror
those builders (docs/re/graphics.md, Palettes) and return Genesis colour
words; nothing here is stored.

Builders (ROM routine -> function):

* ``$215E`` :func:`screen_palette` - all four lines; every screen calls it.
* ``$22A6`` :func:`team_line` (entries ``$2272`` team A -> line 1,
  ``$2284`` team B -> line 2 plain, ``$2296`` team B -> line 2 in colours).
* ``$235E`` :func:`ice_line` - line 0 = the stadium's ice palette.
* ``$2398`` :func:`menu_line` - line 3 from the main menu's table.
* ``$23B0`` :func:`panel_line` - a team's colours on a panel line (stats).
"""
from __future__ import annotations

import struct

TEAM_TABLE = 0x18D8A        # 23 team records x $9E (docs/re/rinks.md)
TEAM_SIZE = 0x9E
DEFAULT_PALETTE = 0x1BD0A   # 4 lines
TEAM_LINE_BASES = {1: 0x1BD2A, 2: 0x1BD4A}   # by style (D3)
MENU_LINES = 0x1BE0A        # pointers to 16-colour lines
ICE_PALETTES = 0x1BE36      # 6 pointers (stadium record +4)
COLOUR_PAIRS = 0x1BE4E      # default pair; +4 NTSC, +8 PAL
PAIR_FLAGS = 0x1BE5A        # per screen ID: 1 = use the regional pair
PANEL_COLOURS = 0x1BE6E     # fixed colours of a panel line


def _w(rom: bytes, address: int, count: int = 1) -> list[int]:
    return list(struct.unpack_from(f">{count}H", rom, address))


def _l(rom: bytes, address: int) -> int:
    return struct.unpack_from(">I", rom, address)[0]


def team_record(team: int) -> int:
    return TEAM_TABLE + team * TEAM_SIZE


def ice_palette(rom: bytes, stadium: int) -> int:
    """Address of the ice palette of stadium ``stadium`` (the team index
    whose record points at the stadium, ``$FFB0E4``)."""
    record = _l(rom, team_record(stadium) + 0x10)
    return _l(rom, ICE_PALETTES + 4 * rom[record + 4])


def colour_pair(rom: bytes, screen: int, pal: bool = False) -> tuple[int, int]:
    """The two colours some screens swap per console region (``$21B0``)."""
    table = COLOUR_PAIRS
    if rom[PAIR_FLAGS + screen]:
        table += 8 if pal else 4
    a, b = _w(rom, table, 2)
    return a, b


def _team_colours(rom: bytes, team: int, line: list[int]) -> None:
    """Team record +$80: colours 2-3, 5-6, 7-8 and 9 of a team line."""
    c = team_record(team) + 0x80
    line[2:4] = _w(rom, c, 2)
    line[5:7] = _w(rom, c + 4, 2)
    line[7:9] = _w(rom, c + 0x10, 2)
    line[9] = _w(rom, c + 0x14)[0]


def screen_palette(rom: bytes, screen: int, team_a: int, stadium: int, pal: bool = False) -> list[int]:
    """``$215E``: 64 colours. Default palette; the stadium's 16 ice colours
    as line 0 (8 longs copied: plan 07 found colours 8-15 too);
    ice colour 5 also as colour 11 of lines 1-2; the colour pair as colours 1
    and 10 of lines 1-2; team A's colours on line 1. (The routine also looks
    up team B but never uses it.)"""
    p = _w(rom, DEFAULT_PALETTE, 64)
    p[0:16] = _w(rom, ice_palette(rom, stadium), 16)
    p[16 + 11] = p[32 + 11] = p[5]
    a, b = colour_pair(rom, screen, pal)
    p[16 + 1] = p[32 + 1] = a
    p[16 + 10] = p[32 + 10] = b
    line1 = p[16:32]
    _team_colours(rom, team_a, line1)
    p[16:32] = line1
    return p


def team_line(rom: bytes, screen: int, team: int, stadium: int, style: int, pal: bool = False) -> list[int]:
    """``$22A6``: 16 colours for a team's line. Style 1 (``$2272``,
    ``$2296``) starts from ``$1BD2A`` and adds the team's colours; style 2
    (``$2284``) starts from ``$1BD4A`` and keeps it (no team colours)."""
    line = _w(rom, TEAM_LINE_BASES[style], 16)
    line[1], line[10] = colour_pair(rom, screen, pal)
    if style != 2:
        _team_colours(rom, team, line)
    line[11] = _w(rom, ice_palette(rom, stadium) + 10)[0]
    return line


def ice_line(rom: bytes, stadium: int) -> list[int]:
    """``$235E`` + ``$149B2``: line 0 = the ice palette with colour 0 black."""
    line = _w(rom, ice_palette(rom, stadium), 16)
    line[0] = 0
    return line


def menu_line(rom: bytes, index: int) -> list[int]:
    """``$2398``: line 3 from the menu table (0-2)."""
    return _w(rom, _l(rom, MENU_LINES + 4 * index), 16)


def panel_line(rom: bytes, screen: int, colours: int, pal: bool = False) -> list[int]:
    """``$23B0``: fixed panel colours around seven team colours at
    ``colours`` (a team record's +$7C pointer)."""
    line = _w(rom, PANEL_COLOURS, 2) + _w(rom, colours, 7) + _w(rom, PANEL_COLOURS + 4, 7)
    line[1], line[10] = colour_pair(rom, screen, pal)
    return line


def builder_cases() -> list[tuple[str, tuple]]:
    """Builder calls whose results are hashed for the GDScript port
    (compare/fixtures/gfx_hashes.json)."""
    cases: list[tuple[str, tuple]] = []
    for screen in (1, 3, 4, 14, 18):
        for team, stadium in ((0, 0), (5, 12), (22, 22)):
            cases.append(("screen_palette", (screen, team, stadium)))
    for team, stadium in ((0, 0), (5, 12), (22, 22)):
        for style in (1, 2):
            cases.append(("team_line", (1, team, stadium, style)))
    cases += [("ice_line", (s,)) for s in range(23)]
    cases += [("menu_line", (i,)) for i in range(3)]
    cases += [("panel_line", (8, t)) for t in (0, 5, 22)]
    return cases


def run_case(rom: bytes, name: str, args: tuple) -> list[int]:
    if name == "panel_line":
        screen, team = args
        return panel_line(rom, screen, _l(rom, team_record(team) + 0x7C))
    return globals()[name](rom, *args)
