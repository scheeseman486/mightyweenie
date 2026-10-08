#!/usr/bin/env python3
"""Text strings referenced by a function and its callees (read-only).

    tools/bin/py re/ghidra/strings_used.py screen_19 [--depth 3]

Helps identify what a screen shows. Strings are the game's plain ASCII,
NUL-terminated text.
"""
from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("targets", nargs="+")
    ap.add_argument("--depth", type=int, default=3)
    a = ap.parse_args()
    import pyghidra
    pyghidra.start()
    from ghidra.program.flatapi import FlatProgramAPI
    rom = (ROOT / "rom" / "Mutant League Hockey (USA, Europe).md").read_bytes()

    def cstring(off: int) -> str | None:
        if not 0 <= off < len(rom):
            return None
        end = rom.find(b"\0", off, off + 80)
        s = rom[off:end] if end > off else b""
        if len(s) >= 3 and all(32 <= c < 127 for c in s):
            return s.decode()
        return None

    project = pyghidra.open_project(ROOT / "re" / "ghidra" / "project", "MLH")
    try:
        with pyghidra.program_context(project, "/MLH") as program:
            flat = FlatProgramAPI(program)
            fm = program.getFunctionManager()
            rm = program.getReferenceManager()
            for t in a.targets:
                syms = list(program.getSymbolTable().getSymbols(t))
                addr = syms[0].getAddress() if syms else flat.toAddr(f"{int(t, 16):08x}")
                start = fm.getFunctionContaining(addr)
                seen = {start.getEntryPoint()}
                q = deque([(start, 0)])
                print(f"== {start.getName()}")
                while q:
                    f, d = q.popleft()
                    it = rm.getReferenceSourceIterator(f.getBody(), True)
                    while it.hasNext():
                        src = it.next()
                        for ref in rm.getReferencesFrom(src):
                            off = ref.getToAddress().getOffset()
                            s = cstring(off) if off < 0x200000 else None
                            if s and ref.getReferenceType().isData():
                                print(f"   {'  ' * d}{f.getName()}: ${off:06X} {s!r}")
                    if d < a.depth:
                        for c in f.getCalledFunctions(None):
                            if c.getEntryPoint() not in seen:
                                seen.add(c.getEntryPoint()); q.append((c, d + 1))
    finally:
        project.close()


if __name__ == "__main__":
    main()
