#!/usr/bin/env python3
"""Build the Ghidra database for Mutant League Hockey from scratch.

    tools/bin/py re/ghidra/mlh_import.py [--rebuild] [--no-analyze]

Reproducible baseline: imports the ROM as a raw 68000 binary, lays out the
Genesis memory map, labels the vector table, cartridge header and hardware
registers, creates functions at the vector targets, applies every annotation
in re/labels/ (see annotations_io.py) and runs auto-analysis. Result: re/ghidra/project/MLH.gpr (gitignored;
the CSVs and later text exports are what we commit).

Why not ghidra_sega_ldr? Its last release targets Ghidra 11.0.1 and it needs a
Gradle rebuild for 12.x; this script does the same setup in ~100 readable
lines we control, and stays in step with the pinned Ghidra.
"""
from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import annotations_io  # noqa: E402  (re/ghidra/annotations_io.py)

ROOT = Path(__file__).resolve().parents[2]
PROJECT_DIR = ROOT / "re" / "ghidra" / "project"
PROJECT_NAME = "MLH"
PROGRAM_NAME = "MLH"
LABEL_DIR = ROOT / "re" / "labels"
# Ghidra has no plain-68000 variant; the 68020 one is the closest superset.
LANGUAGE = "68000:BE:32:MC68020"

VECTOR_NAMES = {
    0: "InitialSSP", 1: "Reset", 2: "BusError", 3: "AddressError",
    4: "IllegalInstruction", 5: "ZeroDivide", 6: "CHK", 7: "TRAPV",
    8: "PrivilegeViolation", 9: "Trace", 10: "LineA", 11: "LineF",
    24: "SpuriousInterrupt", 25: "IRQ1", 26: "IRQ2_External", 27: "IRQ3",
    28: "IRQ4_HBlank", 29: "IRQ5", 30: "IRQ6_VBlank", 31: "IRQ7",
    **{32 + i: f"TRAP{i}" for i in range(16)},
}

# name, start, length, rwx, volatile
HW_BLOCKS = [
    ("Z80_RAM", 0xA00000, 0x2000, "rw-", True),
    ("YM2612", 0xA04000, 0x4, "rw-", True),
    ("IO", 0xA10000, 0x20, "rw-", True),
    ("Z80_CTRL", 0xA11100, 0x200, "rw-", True),
    ("TMSS", 0xA14000, 0x4, "rw-", True),
    ("VDP", 0xC00000, 0x20, "rw-", True),
    ("WORK_RAM", 0xFF0000, 0x10000, "rwx", False),
]

# (offset, length, name) of the cartridge header strings at $100.
HEADER_FIELDS = [
    (0x100, 16, "hdr_system"), (0x110, 16, "hdr_copyright"),
    (0x120, 48, "hdr_name_domestic"), (0x150, 48, "hdr_name_overseas"),
    (0x180, 14, "hdr_serial"), (0x190, 16, "hdr_io_support"),
    (0x1C8, 40, "hdr_memo"), (0x1F0, 16, "hdr_region"),
]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rom", default=str(ROOT / "rom" / "Mutant League Hockey (USA, Europe).md"))
    ap.add_argument("--rebuild", action="store_true", help="delete and recreate the project")
    ap.add_argument("--no-analyze", action="store_true", help="skip auto-analysis")
    ap.add_argument("--project-dir", default=str(PROJECT_DIR), help=argparse.SUPPRESS)
    ap.add_argument("--labels-dir", default=str(LABEL_DIR), help=argparse.SUPPRESS)
    args = ap.parse_args()
    project_dir = Path(args.project_dir)
    labels_dir = Path(args.labels_dir)

    gpr = project_dir / f"{PROJECT_NAME}.gpr"
    if gpr.exists():
        if not args.rebuild:
            sys.exit(f"{gpr} exists; pass --rebuild to recreate it (close Ghidra first)")
        gpr.unlink()
        shutil.rmtree(project_dir / f"{PROJECT_NAME}.rep", ignore_errors=True)
    project_dir.mkdir(parents=True, exist_ok=True)

    import warnings

    import pyghidra
    # open_program() is deprecated in pyghidra 3 but remains the simplest
    # one-call import; revisit when moving to the ProgramLoader builder.
    warnings.filterwarnings("ignore", category=DeprecationWarning, module=__name__)
    pyghidra.start()
    t0 = time.time()
    with pyghidra.open_program(args.rom, project_location=project_dir, project_name=PROJECT_NAME,
                               program_name=PROGRAM_NAME, analyze=False, language=LANGUAGE,
                               loader="ghidra.app.util.opinion.BinaryLoader",
                               nested_project_location=False) as flat:
        program = flat.getCurrentProgram()
        with pyghidra.transaction(program, "Genesis setup"):
            setup_memory(program)
            entries = label_vectors(flat, program)
            label_header(flat)
            for addr in sorted(entries):
                flat.disassemble(A(flat, addr))
                flat.createFunction(A(flat, addr), None)
            annotations_io.apply(program, labels_dir)
        print(f"[mlh_import] setup done in {time.time() - t0:.1f}s")
        if not args.no_analyze:
            t1 = time.time()
            pyghidra.analyze(program)
            # EA code passes data inline after some JSRs; analysis disassembles
            # that data as code. Fix those call sites, then analyse again.
            with pyghidra.transaction(program, "inline call data"):
                n = fix_inline_calls(program, labels_dir / "inline_calls.csv")
            if n:
                pyghidra.analyze(program)
            print(f"[mlh_import] auto-analysis done in {time.time() - t1:.1f}s "
                  f"({n} inline-data call sites fixed)")
        fm = program.getFunctionManager()
        print(f"[mlh_import] {fm.getFunctionCount()} functions; saved to {gpr}")


def A(flat, offset: int):
    """Address from an int; via the string overload so values >= 2^31 work."""
    return flat.toAddr(f"{offset:08x}")


def setup_memory(program) -> None:
    mem = program.getMemory()
    space = program.getAddressFactory().getDefaultAddressSpace()
    rom = mem.getBlock(space.getAddress(0))
    rom.setName("ROM")
    rom.setPermissions(True, False, True)  # r-x: cartridge is read-only
    for name, start, length, rwx, volatile in HW_BLOCKS:
        b = mem.createUninitializedBlock(name, space.getAddress(start), length, False)
        b.setPermissions("r" in rwx, "w" in rwx, "x" in rwx)
        b.setVolatile(volatile)
    # 68000 absolute-short addressing sign-extends: `move.w ($B06A).w,d0`
    # reads $FFFFB06A, which the 24-bit bus maps to $FFB06A. Mirror work RAM
    # there so those references resolve to the same bytes.
    mem.createByteMappedBlock("WORK_RAM_SHORT", space.getAddress(0xFFFF0000),
                              space.getAddress(0xFF0000), 0x10000, False)


def label_vectors(flat, program) -> set[int]:
    """Make the 64 vector longs pointers, label slots and handler targets."""
    from ghidra.program.model.data import PointerDataType
    from ghidra.program.model.symbol import SourceType

    rom = program.getMemory()
    targets: dict[int, list[str]] = {}
    for i in range(64):
        slot = A(flat, i * 4)
        name = VECTOR_NAMES.get(i, f"Reserved{i}")
        flat.createLabel(slot, f"vec_{name}", True, SourceType.IMPORTED)
        flat.createData(slot, PointerDataType())
        if i == 0:
            continue
        target = rom.getInt(slot) & 0xFFFFFFFF
        targets.setdefault(target, []).append(name)
    for target, names in targets.items():
        # Several vectors usually share one catch-all handler.
        label = names[0] if len(names) == 1 else "DefaultException"
        flat.createLabel(A(flat, target), label, True, SourceType.IMPORTED)
        if len(names) > 1:
            flat.setPlateComment(A(flat, target), "Handler for vectors: " + ", ".join(names))
    return set(targets)


def label_header(flat) -> None:
    from ghidra.program.model.data import DWordDataType, WordDataType
    from ghidra.program.model.symbol import SourceType

    for off, length, name in HEADER_FIELDS:
        a = A(flat, off)
        flat.createLabel(a, name, True, SourceType.IMPORTED)
        flat.createAsciiString(a, length)
    flat.createLabel(A(flat, 0x18E), "hdr_checksum", True, SourceType.IMPORTED)
    flat.createData(A(flat, 0x18E), WordDataType())
    for off, name in ((0x1A0, "hdr_rom_start"), (0x1A4, "hdr_rom_end"),
                      (0x1A8, "hdr_ram_start"), (0x1AC, "hdr_ram_end")):
        flat.createLabel(A(flat, off), name, True, SourceType.IMPORTED)
        flat.createData(A(flat, off), DWordDataType())


INLINE_RULES = {
    # rule name -> function(memory, start_offset) -> data length in bytes
    "words_until_ffff": lambda read_u16, start: next(
        2 * (i + 1) for i in range(4096) if read_u16(start + 2 * i) == 0xFFFF),
}


def fix_inline_calls(program, csv_path: Path) -> int:
    """Turn the inline data after calls to known inline-data routines into data.

    For every call to a routine listed in ``re/labels/inline_calls.csv``: clear
    whatever analysis disassembled after the JSR, define the data (length
    from the routine's rule), make the call fall through past it and
    disassemble from there.
    """
    import csv as _csv

    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.program.model.data import ArrayDataType, ByteDataType
    from ghidra.util.task import TaskMonitor

    if not csv_path.exists():
        return 0
    listing = program.getListing()
    mem = program.getMemory()
    rm = program.getReferenceManager()
    space = program.getAddressFactory().getDefaultAddressSpace()
    read_u16 = lambda off: mem.getShort(space.getAddress(off)) & 0xFFFF  # noqa: E731
    fixed = 0
    for row in _csv.DictReader(csv_path.open()):
        rule = INLINE_RULES[row["rule"]]
        target = space.getAddress(int(row["address"], 16))
        for ref in rm.getReferencesTo(target):
            if not ref.getReferenceType().isCall():
                continue
            call = listing.getInstructionAt(ref.getFromAddress())
            if call is None:
                continue
            start = call.getMaxAddress().add(1)
            length = rule(read_u16, start.getOffset())
            end = start.add(length - 1)
            listing.clearCodeUnits(start, end, False)
            listing.createData(start, ArrayDataType(ByteDataType(), length, 1))
            call.setFallThrough(end.add(1))
            DisassembleCommand(end.add(1), None, True).applyTo(program, TaskMonitor.DUMMY)
            fixed += 1
    return fixed


if __name__ == "__main__":
    main()
