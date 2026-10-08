"""Decode a Genesis Plus GX savestate into Genesis-native data.

stable-retro only exposes 68k work RAM through its memory API, but its
``get_state()`` returns GPGX's full savestate (``state_save()`` in
core/state.c), whose layout is fixed for a given core build:

    offset   size     field
    0x00000  0x10     version string "GENPLUS-GX 1.7.5"
    0x00010  0x10000  68k work RAM ($FF0000-$FFFFFF)   16-bit words, host LE
    0x10010  0x2000   Z80 RAM ($A00000-$A01FFF)        bytes
    0x12010  1        zstate (Z80 bus/reset state)
    0x12011  4        zbank (Z80 68k-bank register)
    0x12015  0x10     io_reg (I/O ports $A10001-$A1001F)
    -- vdp_context_save() --
    0x12025  0x400    sat   (VDP internal sprite attribute cache)  words LE
    0x12425  0x10000  vram                                         words LE
    0x22425  0x80     cram  (GPGX packed 9-bit colour, see below)  words LE
    0x224A5  0x80     vsram                                        words LE
    0x22525  0x20     VDP registers 0-31                           bytes
    ...      sound context (size depends on the core's build options)
    M68K_REGS_OFFSET  D0-D7, A0-A7, PC (u32 LE each), SR (u16), USP, ISP

Every offset here is verified by harness/tests/test_state_layout.py, which
runs a synthetic ROM that writes known values everywhere. If a stable-retro
upgrade changes the core, that test fails instead of the harness silently
reading garbage.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass

STATE_VERSION = b"GENPLUS-GX 1.7.5"

OFF_WORK_RAM = 0x10
OFF_ZRAM = 0x10010
OFF_ZSTATE = 0x12010
OFF_ZBANK = 0x12011
OFF_IO_REG = 0x12015
OFF_SAT = 0x12025
OFF_VRAM = 0x12425
OFF_CRAM = 0x22425
OFF_VSRAM = 0x224A5
OFF_VDP_REGS = 0x22525
#: Follows the variable-size sound context, so it is calibrated rather than
#: derived: the synthetic ROM loads D0-D7 with known values and the test
#: locates them (stable-retro 1.0.1 / GPGX 1.7.5 -> 0x23433).
M68K_REGS_OFFSET = 0x23433

_M68K_REG_NAMES = [f"D{i}" for i in range(8)] + [f"A{i}" for i in range(8)]


def _swap16(buf: bytes) -> bytes:
    """GPGX keeps 16-bit memories in host (little-endian) word order.

    Swap each byte pair to get the 68000's big-endian view.
    """
    b = bytearray(buf)
    b[0::2], b[1::2] = buf[1::2], buf[0::2]
    return bytes(b)


def gpgx_cram_to_genesis(packed: int) -> int:
    """GPGX stores CRAM as 9-bit BBBGGGRRR; return Genesis 0000BBB0GGG0RRR0."""
    r = packed & 7
    g = (packed >> 3) & 7
    b = (packed >> 6) & 7
    return (b << 9) | (g << 5) | (r << 1)


def genesis_color_to_rgb8(c: int) -> tuple[int, int, int]:
    """Genesis 9-bit colour to 8-bit RGB using the linear 0..7 -> 0..252 ramp.

    (Real hardware's DAC is non-linear; pick the mapping in one place so the
    Godot side and the tests agree. 36 * level is the common convention.)
    """
    return (((c >> 1) & 7) * 36, ((c >> 5) & 7) * 36, ((c >> 9) & 7) * 36)


@dataclass(frozen=True)
class MDState:
    """One frame's worth of Genesis state, in native (big-endian) layout."""

    work_ram: bytes        # 64 KiB, index 0 == $FF0000
    z80_ram: bytes         # 8 KiB
    vram: bytes            # 64 KiB
    cram: tuple[int, ...]  # 64 Genesis colour words (0000BBB0GGG0RRR0)
    vsram: tuple[int, ...] # 40 used entries (64 stored)
    vdp_regs: bytes        # 32 registers
    sat_cache: bytes       # VDP internal sprite table cache (big-endian words)
    io_regs: bytes
    m68k: dict[str, int]   # D0-D7, A0-A7, PC, SR, USP, ISP
    raw: bytes             # the untouched savestate (for set_state)

    def fingerprint(self) -> tuple:
        """Every decoded field - use this, not ``raw``, to compare states.

        stable-retro hands out a fixed 1,036,288-byte buffer but GPGX only
        fills the first part; the tail is uninitialised memory that can differ
        between otherwise identical states.
        """
        return (self.work_ram, self.z80_ram, self.vram, self.cram, self.vsram,
                self.vdp_regs, self.sat_cache, self.io_regs,
                tuple(sorted(self.m68k.items())))

    def ram_u8(self, addr: int) -> int:
        return self.work_ram[addr & 0xFFFF]

    def ram_u16(self, addr: int) -> int:
        return struct.unpack_from(">H", self.work_ram, addr & 0xFFFF)[0]

    def ram_u32(self, addr: int) -> int:
        return struct.unpack_from(">I", self.work_ram, addr & 0xFFFF)[0]

    def vram_u16(self, addr: int) -> int:
        return struct.unpack_from(">H", self.vram, addr & 0xFFFE)[0]

    def palette_rgb8(self) -> list[tuple[int, int, int]]:
        return [genesis_color_to_rgb8(c) for c in self.cram]


def _find_m68k_regs(raw: bytes) -> int:
    if M68K_REGS_OFFSET is None:
        raise RuntimeError("M68K_REGS_OFFSET not calibrated")
    return M68K_REGS_OFFSET


def parse_state(raw: bytes, with_cpu: bool = True) -> MDState:
    if raw[:16] != STATE_VERSION:
        raise ValueError(f"unexpected savestate version {raw[:16]!r}; "
                         "re-run harness/tests/test_state_layout.py and update offsets")
    cram_words = struct.unpack_from("<64H", raw, OFF_CRAM)
    vsram_words = struct.unpack_from("<64H", raw, OFF_VSRAM)
    m68k: dict[str, int] = {}
    if with_cpu and M68K_REGS_OFFSET is not None:
        o = _find_m68k_regs(raw)
        vals = struct.unpack_from("<16I", raw, o)
        m68k = dict(zip(_M68K_REG_NAMES, vals))
        m68k["PC"], = struct.unpack_from("<I", raw, o + 64)
        m68k["SR"], = struct.unpack_from("<H", raw, o + 68)
        m68k["USP"], m68k["ISP"] = struct.unpack_from("<II", raw, o + 70)
    return MDState(
        work_ram=_swap16(raw[OFF_WORK_RAM:OFF_WORK_RAM + 0x10000]),
        z80_ram=bytes(raw[OFF_ZRAM:OFF_ZRAM + 0x2000]),
        vram=_swap16(raw[OFF_VRAM:OFF_VRAM + 0x10000]),
        cram=tuple(gpgx_cram_to_genesis(w) for w in cram_words),
        vsram=tuple(vsram_words),
        vdp_regs=bytes(raw[OFF_VDP_REGS:OFF_VDP_REGS + 0x20]),
        sat_cache=_swap16(raw[OFF_SAT:OFF_SAT + 0x400]),
        io_regs=bytes(raw[OFF_IO_REG:OFF_IO_REG + 0x10]),
        m68k=m68k,
        raw=bytes(raw),
    )
