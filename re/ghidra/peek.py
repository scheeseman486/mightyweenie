#!/usr/bin/env python3
"""Disassemble a range without saving (for code Ghidra hasn't discovered yet).

    tools/bin/py re/ghidra/peek.py 10100 [count]

Clears and disassembles in a throwaway transaction, prints, discards.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    start = int(sys.argv[1], 16)
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    import pyghidra
    pyghidra.start()
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.util.task import TaskMonitor
    project = pyghidra.open_project(ROOT / "re" / "ghidra" / "project", "MLH")
    try:
        with pyghidra.program_context(project, "/MLH") as program:
            listing = program.getListing()
            fm = program.getFunctionManager()
            st = program.getSymbolTable()
            space = program.getAddressFactory().getDefaultAddressSpace()
            tx = program.startTransaction("peek")
            try:
                a = space.getAddress(start)
                if listing.getInstructionAt(a) is None:
                    listing.clearCodeUnits(a, a.add(count * 6), False)
                    DisassembleCommand(a, None, True).applyTo(program, TaskMonitor.DUMMY)
                ins = listing.getInstructionAt(a)
                for _ in range(count):
                    if ins is None:
                        break
                    sym = st.getPrimarySymbol(ins.getAddress())
                    f = fm.getFunctionAt(ins.getAddress())
                    if sym is not None or f is not None:
                        print(f"{(f or sym).getName()}:")
                    print(f"  {ins.getAddress()}  {ins}")
                    ins = ins.getNext()
            finally:
                program.endTransaction(tx, False)
    finally:
        project.close()


if __name__ == "__main__":
    main()
