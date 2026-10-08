"""Stadium (rink) records: the reference parser for docs/re/rinks.md.

Each of the 23 teams has a home stadium. The team record (ROM $18D8A + team *
$9E) holds a pointer at +$10 to a variable-length stadium record:

    +$0  long  pointer to the stadium name (NUL-terminated)
    +$4  byte  ice palette index (table $1BE36; 0/1 and 3/5 share data)
    +$5  byte  goal net style (animation table $1B8F8; both nets)
    +$6  byte  unknown - no reader found, no effect seen
    +$7  byte  crowd byte - copied to $FFB360, no reader found
    +$8  byte  signed offset given to two rink objects (always -24)
    +$9  byte  n_ice: in-ice hazards that follow
    +$A  byte  n_obj: rink objects that follow those
    +$B  byte  hazard mask for the matchup text (bit n = hazard name n)
    +$C  n_ice x 6 bytes: x.w, y.w, kind.b, flags.b   (kind 1-4 = mask bit kind-1)
         n_obj x 6 bytes: x.w, y.w, kind.b, flags.b   (spawned like thrown objects)

Positions are rink coordinates (x right, y down, centre ice 0,0).
Nothing here is game content: it only reads the user's ROM.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass

from .rom import Rom

TEAM_TABLE = 0x18D8A
TEAM_RECORD_SIZE = 0x9E
TEAM_COUNT = 23
STADIUM_PTR = 0x10
HAZARD_BITS = ("thin_ice", "pits", "holes", "mines", "fires", "sharks", "worms", "spikes")


@dataclass(frozen=True)
class Placement:
    x: int
    y: int
    kind: int
    flags: int


@dataclass(frozen=True)
class Stadium:
    team: int            # home team index
    address: int         # ROM address of the record
    name_ptr: int
    palette: int
    net_style: int
    unknown_6: int
    crowd_byte: int
    object_offset: int
    hazard_mask: int
    ice: tuple[Placement, ...]
    objects: tuple[Placement, ...]
    end: int             # first byte after the record

    @property
    def hazards(self) -> tuple[str, ...]:
        return tuple(n for b, n in enumerate(HAZARD_BITS) if self.hazard_mask >> b & 1)


def _placements(rom: Rom, at: int, count: int) -> tuple[tuple[Placement, ...], int]:
    out = []
    for _ in range(count):
        x, y, kind, flags = struct.unpack_from(">hhBB", rom.data, at)
        out.append(Placement(x, y, kind, flags))
        at += 6
    return tuple(out), at


def stadium_address(rom: Rom, team: int) -> int:
    return rom.u32(TEAM_TABLE + team * TEAM_RECORD_SIZE + STADIUM_PTR)


def parse_stadium(rom: Rom, team: int) -> Stadium:
    a = stadium_address(rom, team)
    pal, net, unk, crowd, off, n_ice, n_obj, mask = struct.unpack_from(">BBBBbBBB", rom.data, a + 4)
    ice, p = _placements(rom, a + 12, n_ice)
    objs, p = _placements(rom, p, n_obj)
    return Stadium(team, a, rom.u32(a), pal, net, unk, crowd, off, mask, ice, objs, p)


def all_stadiums(rom: Rom) -> list[Stadium]:
    return [parse_stadium(rom, t) for t in range(TEAM_COUNT)]
