"""Build a tiny Genesis ROM that writes known values to every memory we parse.

Used to verify the savestate offsets in mw_harness.gpgx_state against the
actual core shipped with stable-retro. The 68000 code is hand-assembled; each
helper documents its encoding.
"""
from __future__ import annotations

import struct

VDP_DATA = 0xC00000
VDP_CTRL = 0xC00004

# Known values the tests check for.
WORK_RAM = {0xFF0000: 0xABCD, 0xFF1234: 0x5A5A, 0xFFFFF0: 0x1357}
VRAM = [0x1234, 0x5678]          # written at VRAM $0000
CRAM = [0x0EEE, 0x0222, 0x0A42]  # written at CRAM $00
VSRAM = [0x0123]                 # written at VSRAM $00
Z80_RAM = {0x0000: 0x5A, 0x1FFF: 0xA5}
VDP_REG_WRITES = {0x01: 0x04, 0x0F: 0x02, 0x07: 0x3C}  # reg -> value
DREGS = [0x11111111 * (i + 1) & 0xFFFFFFFF for i in range(8)]
AREGS = [0x00FF8000 + 0x10 * i for i in range(7)]  # A0-A6 (A7 is the stack)
LOOP_PC = None  # set by build()


def _move_w_abs(value: int, addr: int) -> bytes:
    """move.w #value,(addr).l  -> 33FC vvvv aaaaaaaa"""
    return struct.pack(">HHI", 0x33FC, value, addr)


def _move_l_abs(value: int, addr: int) -> bytes:
    """move.l #value,(addr).l  -> 23FC vvvvvvvv aaaaaaaa"""
    return struct.pack(">HII", 0x23FC, value, addr)


def _move_b_abs(value: int, addr: int) -> bytes:
    """move.b #value,(addr).l  -> 13FC 00vv aaaaaaaa"""
    return struct.pack(">HHI", 0x13FC, value, addr)


def _move_l_imm_dn(value: int, n: int) -> bytes:
    """move.l #value,Dn  -> 0x203C | n<<9"""
    return struct.pack(">HI", 0x203C | (n << 9), value)


def _movea_l_imm_an(value: int, n: int) -> bytes:
    """movea.l #value,An -> 0x207C | n<<9"""
    return struct.pack(">HI", 0x207C | (n << 9), value)


def build() -> bytes:
    global LOOP_PC
    rom = bytearray(0x20000)
    struct.pack_into(">II", rom, 0, 0x00FFFE00, 0x200)  # SSP, reset PC
    rom[0x100:0x110] = b"SEGA GENESIS    "
    rom[0x180:0x18E] = b"GM 00000000-00"
    rom[0x1F0:0x1F3] = b"JUE"
    code = bytearray()
    for reg, val in VDP_REG_WRITES.items():           # VDP register writes
        code += _move_w_abs(0x8000 | (reg << 8) | val, VDP_CTRL)
    code += _move_l_abs(0xC0000000, VDP_CTRL)          # CRAM write @ 0
    for c in CRAM:
        code += _move_w_abs(c, VDP_DATA)
    code += _move_l_abs(0x40000000, VDP_CTRL)          # VRAM write @ 0
    for v in VRAM:
        code += _move_w_abs(v, VDP_DATA)
    code += _move_l_abs(0x40000010, VDP_CTRL)          # VSRAM write @ 0
    for v in VSRAM:
        code += _move_w_abs(v, VDP_DATA)
    for addr, val in WORK_RAM.items():
        code += _move_w_abs(val, addr)
    # Z80 RAM: release Z80 reset, request its bus, wait for the grant.
    code += _move_w_abs(0x0100, 0xA11200)              # Z80 reset off
    code += _move_w_abs(0x0100, 0xA11100)              # bus request
    loop = len(code)
    code += struct.pack(">HHI", 0x0839, 0, 0xA11100)   # btst #0,($A11100).l
    code += struct.pack(">Hb", 0x6600, 0)[:1] + bytes([(loop - (len(code) + 2)) & 0xFF])  # bne.s loop
    for addr, val in Z80_RAM.items():
        code += _move_b_abs(val, 0xA00000 + addr)
    for i, v in enumerate(DREGS):
        code += _move_l_imm_dn(v, i)
    for i, v in enumerate(AREGS):
        code += _movea_l_imm_an(v, i)
    LOOP_PC = 0x200 + len(code)
    code += struct.pack(">H", 0x60FE)                  # bra.s * (spin)
    rom[0x200:0x200 + len(code)] = code
    return bytes(rom)
