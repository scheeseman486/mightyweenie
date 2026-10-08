"""The rink's drawing state decoded from a recording (plan 07).

:func:`decode` turns the RAM of one pass (:mod:`rink_record` regions) into
the fields ``MwRinkState.from_dict`` reads (docs/re/rink.md, Objects): the
camera, both teams with their on-ice players, arrows and markers, the puck,
nets, in-ice hazards, rink objects, goal lamps and overlays. Only game
state: positions, ROM addresses of animations and frames, flags. The info
plates' tiles (pixels from the ROM's font) are read back into the values
they show (:func:`plates`): plate slots are shared, so a plate can show
another marker's last values.
"""
from __future__ import annotations

import struct

OBJECTS = 0xFFB0B2
PLANE_B = 0xFFB0B2
RINK = 0xFFB0E8
PUCK = 0xFFB3C2
TEAMS = (0xFFB402, 0xFFB8AC)
TEAM_SIZE = 0x4AA
PLAYERS = 0x6C
PLAYER_SIZE = 0x76
FACEOFF = 0xFFBD56
IMPALE = 0xFFBD82
REF = 0xFFBD92
PROJECTION = 0xFFBDBA


class Ram:
    """Big-endian reads over the recorded regions."""

    def __init__(self, regions: dict[str, tuple[int, int]], ram: dict[str, bytes]):
        self.parts = [(regions[k][0], ram[k]) for k in ram]

    def _at(self, a: int, n: int) -> bytes:
        for base, data in self.parts:
            if base <= a and a + n <= base + len(data):
                return data[a - base:a - base + n]
        raise KeyError(f"{a:#x} not recorded")

    def u8(self, a: int) -> int:
        return self._at(a, 1)[0]

    def s8(self, a: int) -> int:
        return struct.unpack(">b", self._at(a, 1))[0]

    def u16(self, a: int) -> int:
        return struct.unpack(">H", self._at(a, 2))[0]

    def s16(self, a: int) -> int:
        return struct.unpack(">h", self._at(a, 2))[0]

    def u32(self, a: int) -> int:
        return struct.unpack(">I", self._at(a, 4))[0]

    def s32(self, a: int) -> int:
        return struct.unpack(">i", self._at(a, 4))[0]


def motion(r: Ram, a: int) -> list[int]:
    """x, y, z (24.8), vx, vy, vz (1/256 px per tick), ax, ay, az."""
    return [r.s32(a), r.s32(a + 8), r.s32(a + 0x10), r.s16(a + 4), r.s16(a + 0xC), r.s16(a + 0x14),
            r.s16(a + 6), r.s16(a + 0xE), r.s16(a + 0x16)]


def anim(r: Ram, a: int) -> list[int]:
    """Animation object: record address, speed, flags, variant, position, frame."""
    return [r.u32(a), r.u16(a + 4), r.u8(a + 6), r.u8(a + 7), r.u16(a + 8), r.u8(a + 0xA)]


def ref(word: int) -> dict | None:
    """A RAM address (low word) of an object -> what it is."""
    a = 0xFF0000 | word
    if word == 0:
        return None
    if a == PUCK:
        return {"kind": "puck"}
    if a == REF:
        return {"kind": "ref"}
    for t, base in enumerate(TEAMS):
        p0 = base + PLAYERS
        if p0 <= a < p0 + 6 * PLAYER_SIZE and (a - p0) % PLAYER_SIZE == 0:
            return {"kind": "player", "team": t, "slot": (a - p0) // PLAYER_SIZE}
    return {"kind": "address", "address": a}


def player(r: Ram, a: int) -> dict:
    return {"present": r.u32(a + 0x32) != 0, "motion": motion(r, a), "anim": anim(r, a + 0x18),
            "record": r.u32(a + 0x32), "slot": r.u8(a + 0x68), "position": r.u8(a + 0x69),
            "weapon": r.s8(a + 0x6D), "anim_id": r.u8(a + 0x6F), "state": r.u8(a + 0x70),
            "substate": r.u8(a + 0x71), "angle": r.u8(a + 0x73), "flags": r.u8(a + 0x74)}


def marker(r: Ram, a: int) -> list[int]:
    """x, y, plate slot, number, position, health (the values the plate shows)."""
    return [r.s16(a), r.s16(a + 2), r.u8(a + 4), r.u8(a + 5), r.u8(a + 6), r.u8(a + 7)]


def team(r: Ram, base: int) -> dict:
    return {"flags4": r.u8(base + 4), "flags5": r.u8(base + 5), "attr": r.u8(base + 0x4A4),
            "pads": [r.u8(base + 0x66), r.u8(base + 0x67)],
            "health": [r.u32(base + 6 + 4 * i) for i in range(24)],
            "players": [player(r, base + PLAYERS + i * PLAYER_SIZE) for i in range(6)],
            "arrows": [anim(r, base + 0x33A), anim(r, base + 0x34E)],
            "markers": [marker(r, base + 0x346), marker(r, base + 0x35A)]}


def overlay(r: Ram, a: int) -> dict:
    return {"anim": anim(r, a), "x": r.s16(a + 0xC), "y": r.s16(a + 0xE), "depth": r.u16(a + 0x10),
            "attr": r.u8(a + 0x12), "flags": r.u8(a + 0x13)}


PLATE_FONT = 0x4CACC
PLATE_LETTERS = b"CLRDDG"
NONE = 0xFF


def _glyph_tile(rom: bytes, ch: int) -> bytes:
    f = PLATE_FONT
    g = struct.unpack_from(">b", rom, f + struct.unpack_from(">H", rom, f + 4)[0] - 0x21 + ch)[0]
    tile = struct.unpack_from(">H", rom, f + 8 + 6 * g + 4)[0]
    return rom[tile << 5:(tile << 5) + 32]


def plate_tiles(rom: bytes, number: int, position: int, health: int) -> bytes:
    """The 256 RAM bytes of a plate showing these values (``$6362``,
    ``$6388``, ``$630A`` after ``$6146`` cleared it; GDScript MwPlate.tiles)."""
    out = bytearray(256)
    if number != NONE:
        out[0:32] = _glyph_tile(rom, 0x30 + number // 10)
        out[64:96] = _glyph_tile(rom, 0x30 + number % 10)
    if position != NONE:
        out[192:224] = _glyph_tile(rom, PLATE_LETTERS[position])
    if health != NONE:
        v = health
        for t in range(4):
            if v < 0:
                row = 0x77777777
            elif v >= 8:
                row = 0x11111111
            else:
                row = (((0x11111111 << (32 - 4 * v)) & 0xFFFFFFFF) if v else 0) | (0x77777777 >> (4 * v))
            for r in range(1, 6):
                a = 32 * (2 * t + 1) + 4 * r
                out[a:a + 4] = row.to_bytes(4, "big")
            v -= 8
    return bytes(out)


def plates(rom: bytes, data: bytes) -> list[list[int]]:
    """What each of the 4 RAM info plates shows: [number, position, health],
    $FF for a part never drawn (docs/re/rink.md, Markers; GDScript MwPlate)."""
    digits = {_glyph_tile(rom, 0x30 + d): d for d in range(10)}
    letters = {}
    for i, c in enumerate(PLATE_LETTERS):
        letters.setdefault(_glyph_tile(rom, c), i)
    out = []
    for k in range(4):
        t = [data[256 * k + 32 * i:256 * k + 32 * (i + 1)] for i in range(8)]
        blank = bytes(32)
        number = NONE
        if t[0] != blank or t[2] != blank:
            number = 10 * digits.get(t[0], 0) + digits.get(t[2], 0)
        position = letters.get(t[6], NONE) if t[6] != blank else NONE
        health = NONE
        row1 = b"".join(t[2 * i + 1][4:8] for i in range(4))
        if row1 != bytes(16):
            health = sum(1 for b in row1 for n in (b >> 4, b & 15) if n == 1)
        out.append([number, position, health])
    return out


def decode(regions: dict[str, tuple[int, int]], ram: dict[str, bytes], rom: bytes | None = None) -> dict:
    r = Ram(regions, ram)
    rk = RINK
    return {
        "plates": plates(rom, ram["plates"]) if rom is not None else None,
        "phase": r.u16(0xFFC60A), "subphase": r.u16(0xFFC60C), "tick": r.u32(0xFFCA56),
        "reserves": r.u8(0xFFB0E6), "stadium": r.u8(0xFFB0E4), "projection": r.u16(PROJECTION),
        "puck_rule": r.u16(0xFFC3E2) if "rules" in ram else None,
        "team_a": r.u8(0xFFB0DE), "team_b": r.u8(0xFFB0DF),
        "clock": {"seconds": r.u16(0xFFB06A), "period": r.u8(0xFFB076), "flags": r.u8(0xFFB077),
                  "powerplay": r.u16(0xFFB07C)} if "clock" in ram else None,
        "camera": {"target": ref(r.u16(rk + 4)), "speed": r.u16(rk + 6), "x": r.s32(rk + 8), "y": r.s32(rk + 0xC),
                   "lead": r.s16(rk + 0x10), "shake": r.s16(rk + 0x12), "amp": r.s16(rk + 0x14),
                   "shake_16": r.s16(rk + 0x16), "shown": [r.s16(PLANE_B + 4), r.s16(PLANE_B + 6)]},
        "teams": [team(r, b) for b in TEAMS],
        "puck": {"motion": motion(r, PUCK), "anim": anim(r, PUCK + 0x18), "carrier": ref(r.u16(PUCK + 0x24)),
                 "flags": r.u8(PUCK + 0x3D)},
        "nets": [{"motion": motion(r, rk + o), "anim": anim(r, rk + o + 0x18), "style": r.u8(rk + o + 0x24),
                  "bottom": r.u8(rk + o + 0x25)} for o in (0x18, 0x3E)],
        "lamps": [{"motion": motion(r, rk + o), "anim": anim(r, rk + o + 0x18)} for o in (0xB4, 0xD8)],
        "hazards": [[r.s16(rk + 0xFC + 10 * i), r.s16(rk + 0xFE + 10 * i), r.u8(rk + 0x104 + 10 * i),
                     r.u8(rk + 0x105 + 10 * i)] for i in range(4)],
        "objects": [{"motion": motion(r, a), "anim": anim(r, a + 0x18), "t24": r.u16(a + 0x24),
                     "t26": r.u16(a + 0x26), "kind": r.u8(a + 0x28), "flags": r.u8(a + 0x29)}
                    for a in (rk + 0x124 + 0x2A * i for i in range(8))],
        "crowd": r.s16(rk + 0x276),
        "overlays": {"faceoff": overlay(r, FACEOFF), "penalty": overlay(r, 0xFFC2DC), "stoppage": overlay(r, 0xFFC3C8)},
        "impale": anim(r, IMPALE),
        "ref": {"motion": motion(r, REF), "anim": anim(r, REF + 0x18)},
    }


def sprite_list(ram: dict[str, bytes]) -> list[list[int]]:
    """The finished sprite list in VDP link order (front to back), from the
    head entry: [x, y (sprite coordinates), size, attr byte, depth]. The attr
    byte is the SAT word's priority, palette and flip bits (the tile index,
    a slot of the sprite tile cache, is left out)."""
    sp, dp = ram["sprites"], ram["depths"]
    out = []
    i = sp[3]
    seen = 0
    while i and seen < 80:
        y, size, link, word, x = struct.unpack_from(">HBBHH", sp, 8 * i)
        out.append([x, y, size, (word >> 8) & 0xF8, struct.unpack_from(">H", dp, 4 * i)[0]])
        i = link
        seen += 1
    return out
