#!/usr/bin/env python3
"""Read-only command-line queries against the Ghidra database (agent-friendly).

    tools/bin/py re/ghidra/gh.py decompile Reset
    tools/bin/py re/ghidra/gh.py disasm 0x200 20
    tools/bin/py re/ghidra/gh.py xrefs ra_game_clock
    tools/bin/py re/ghidra/gh.py funcs [substring]

Targets are a symbol name or a hex address. Each call starts a JVM (~4 s);
batch several targets in one call where possible. The project must not be
open for writing elsewhere (e.g. in the Ghidra GUI) at the same time.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT_DIR = ROOT / "re" / "ghidra" / "project"


def resolve_all(flat, program, target: str) -> list:
    """All addresses for a hex address or symbol name.

    RAM labels exist twice (at $FFxxxx and its abs.w mirror $FFFFxxxx), so
    a name can resolve to more than one address.
    """
    try:
        return [flat.toAddr(f"{int(target, 16):08x}")]
    except ValueError:
        syms = list(program.getSymbolTable().getSymbols(target))
        if not syms:
            sys.exit(f"unknown symbol {target}")
        return [s.getAddress() for s in syms]


def resolve(flat, program, target: str):
    return resolve_all(flat, program, target)[0]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["decompile", "disasm", "xrefs", "funcs"])
    ap.add_argument("args", nargs="*")
    a = ap.parse_args()

    import pyghidra
    pyghidra.start()
    from ghidra.app.decompiler import DecompInterface
    from ghidra.program.flatapi import FlatProgramAPI
    from ghidra.util.task import ConsoleTaskMonitor

    project = pyghidra.open_project(PROJECT_DIR, "MLH")
    try:
        with pyghidra.program_context(project, "/MLH") as program:
            flat = FlatProgramAPI(program)
            listing = program.getListing()
            if a.cmd == "funcs":
                needle = (a.args[0] if a.args else "").lower()
                for f in program.getFunctionManager().getFunctions(True):
                    if needle in f.getName().lower():
                        print(f"{f.getEntryPoint()}  {f.getName()}  ({f.getBody().getNumAddresses()} bytes)")
                return
            for target in a.args[:1] if a.cmd == "disasm" else a.args:
                addr = resolve(flat, program, target)
                if a.cmd == "decompile":
                    func = flat.getFunctionContaining(addr)
                    if func is None:
                        print(f"// no function at {addr}"); continue
                    di = DecompInterface(); di.openProgram(program)
                    res = di.decompileFunction(func, 60, ConsoleTaskMonitor())
                    print(f"// {func.getName()} @ {func.getEntryPoint()}")
                    df = res.getDecompiledFunction() if res.decompileCompleted() else None
                    print(df.getC() if df else f"// decompile failed: {res.getErrorMessage()}")
                elif a.cmd == "disasm":
                    n = int(a.args[1]) if len(a.args) > 1 else 30
                    ins = listing.getInstructionAt(addr)
                    for _ in range(n):
                        if ins is None:
                            break
                        label = flat.getSymbolAt(ins.getAddress())
                        if label:
                            print(f"{label}:")
                        print(f"  {ins.getAddress()}  {ins}")
                        ins = ins.getNext()
                elif a.cmd == "xrefs":
                    for ta in resolve_all(flat, program, target):
                        for ref in flat.getReferencesTo(ta):
                            frm = ref.getFromAddress()
                            f = flat.getFunctionContaining(frm)
                            print(f"{frm}  {ref.getReferenceType()}  -> {ta}  in {f.getName() if f else '?'}")
    finally:
        project.close()


if __name__ == "__main__":
    main()
