#!/usr/bin/env python3
"""Linear 68000 disassembly of a ROM range, without Ghidra (read-only).

    tools/bin/py re/lindis.py FE8C FFD6          # start end (hex, end exclusive)
    tools/bin/py re/lindis.py FE8C +40           # start, byte count

Useful for code Ghidra hasn't discovered (jump tables reached through
`move.l table(pc,d0.w),-(sp); rts`, inline data after calls). It decodes
straight through, so data in the range shows up as nonsense instructions;
read with care. Labels from re/labels/functions.csv are printed as headers.

capstone resolves `movem (d16,pc)` / `(d8,pc,Xn)` from the register-mask
word, 2 bytes too early; :func:`fix_movem_pc` corrects the printed target
(plan 05 - movem table addresses printed before that were off by 2).
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

import re

import capstone

ROOT = Path(__file__).resolve().parents[1]
ROM = ROOT / "rom" / "Mutant League Hockey (USA, Europe).md"


def fix_movem_pc(address: int, code: bytes, op_str: str) -> str:
    """Correct capstone's PC-relative movem target (base = the extension word
    after the register mask, i.e. address + 4)."""
    if len(code) < 6 or code[0] != 0x4C or code[1] not in (0xBA, 0xFA, 0xBB, 0xFB):
        return op_str
    if code[1] in (0xBA, 0xFA):
        disp = int.from_bytes(code[4:6], "big", signed=True)
    else:
        disp = int.from_bytes(code[5:6], "big", signed=True)
    target = address + 4 + disp
    return re.sub(r"\$[0-9a-f]+\(pc", f"${target:x}(pc", op_str, count=1)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    start = int(sys.argv[1], 16)
    end = start + int(sys.argv[2][1:], 16) if sys.argv[2].startswith("+") else int(sys.argv[2], 16)
    rom = ROM.read_bytes()
    names = {int(r["address"], 16): r["name"]
             for r in csv.DictReader(open(ROOT / "re" / "labels" / "functions.csv"))}
    md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_BIG_ENDIAN | capstone.CS_MODE_M68K_000)
    pc = start
    while pc < end:
        for ins in md.disasm(rom[pc:end + 16], pc):
            if ins.address >= end:
                break
            if ins.address in names:
                print(f"{names[ins.address]}:")
            op_str = fix_movem_pc(ins.address, bytes(ins.bytes), ins.op_str)
            print(f"  {ins.address:06x}  {ins.bytes.hex():<20} {ins.mnemonic} {op_str}")
            pc = ins.address + ins.size
        if pc < end:   # capstone stopped on bytes it can't decode
            print(f"  {pc:06x}  dc.w ${rom[pc:pc + 2].hex()}")
            pc += 2


if __name__ == "__main__":
    main()
