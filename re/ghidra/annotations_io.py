"""Text <-> Ghidra annotations for the Mutant League Hockey database.

The CSV files in ``re/labels/`` are the source of truth (versioned in git);
the Ghidra database is a rebuildable cache. Two directions:

* :func:`apply` writes every CSV row into an open program (idempotent).
* :func:`export` reads user annotations back out of a program into the CSVs,
  so work done in the Ghidra GUI can be committed.

Files (all sorted by address, hex without ``$``):

* ``hardware.csv`` / ``ram.csv`` / ``rom.csv`` - data labels:
  ``address,size,name,comment,source,verified``.
  RAM addresses are written in the ``$FFxxxx`` form; :func:`apply` also
  labels the ``$FFFFxxxx`` mirror used by absolute-short addressing.
* ``functions.csv`` - ``address,name,comment,source,verified``. The comment
  becomes the function's plate comment.
* ``comments.csv`` - free comments in code: ``address,kind,text``
  (kind = ``pre``, ``post`` or ``eol``).

``source`` says where a fact came from; ``verified`` says how it was
confirmed (empty = unverified). Unverified external labels keep a
``ra_``/``gg_``/``forum_`` prefix (see re/README.md).
"""
from __future__ import annotations

import csv
from dataclasses import dataclass, field
from pathlib import Path

LABEL_FIELDS = ["address", "size", "name", "comment", "source", "verified"]
FUNCTION_FIELDS = ["address", "name", "comment", "source", "verified"]
COMMENT_FIELDS = ["address", "kind", "text"]
LABEL_FILES = ("hardware.csv", "ram.csv", "rom.csv")
COMMENT_KINDS = ("pre", "post", "eol")


# --------------------------------------------------------------------------
# Pure-Python CSV model (no Ghidra needed)
# --------------------------------------------------------------------------
@dataclass
class Annotations:
    labels: dict[str, dict[int, dict]] = field(default_factory=dict)  # file -> addr -> row
    functions: dict[int, dict] = field(default_factory=dict)
    comments: dict[tuple[int, str], str] = field(default_factory=dict)

    @classmethod
    def load(cls, folder: Path) -> "Annotations":
        a = cls()
        for name in LABEL_FILES:
            a.labels[name] = {int(r["address"], 16): _fill(r, LABEL_FIELDS)
                              for r in _read(folder / name)}
        a.functions = {int(r["address"], 16): _fill(r, FUNCTION_FIELDS)
                       for r in _read(folder / "functions.csv")}
        a.comments = {(int(r["address"], 16), r["kind"]): r["text"]
                      for r in _read(folder / "comments.csv")}
        return a

    def save(self, folder: Path) -> None:
        folder.mkdir(parents=True, exist_ok=True)
        for name in LABEL_FILES:
            _write(folder / name, LABEL_FIELDS, self.labels.get(name, {}))
        _write(folder / "functions.csv", FUNCTION_FIELDS, self.functions)
        with (folder / "comments.csv").open("w", newline="") as f:
            w = csv.DictWriter(f, COMMENT_FIELDS, lineterminator="\n")
            w.writeheader()
            for (addr, kind) in sorted(self.comments, key=lambda k: (k[0], COMMENT_KINDS.index(k[1]))):
                w.writerow({"address": f"{addr:06X}", "kind": kind, "text": self.comments[(addr, kind)]})


def label_file_for(addr: int) -> str:
    """Which label CSV an address belongs in."""
    if addr >= 0xFF0000:
        return "ram.csv"
    if addr >= 0x400000:
        return "hardware.csv"
    return "rom.csv"


def canonical(addr: int) -> int:
    """Fold the $FFFFxxxx absolute-short mirror onto $FFxxxx."""
    return 0xFF0000 | (addr & 0xFFFF) if addr >= 0xFFFF0000 else addr


def eol_text(row: dict) -> str:
    """The EOL comment :func:`apply` writes for a data label row."""
    tags = []
    if row.get("source"):
        tags.append(f"src: {row['source']}")
    if row.get("verified"):
        tags.append(f"verified: {row['verified']}")
    return (row.get("comment", "") + (f" [{'; '.join(tags)}]" if tags else "")).strip()


def plate_text(row: dict) -> str:
    """The plate comment :func:`apply` writes for a function row."""
    tags = "; ".join(x for x in (f"src: {row['source']}" if row.get("source") else "",
                                 f"verified: {row['verified']}" if row.get("verified") else "") if x)
    return (row.get("comment", "") + (f"\n[{tags}]" if tags else "")).strip()


def _read(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def _fill(row: dict, fields: list[str]) -> dict:
    return {k: (row.get(k) or "").strip() for k in fields}


def _write(path: Path, fields: list[str], rows: dict[int, dict]) -> None:
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fields, lineterminator="\n")
        w.writeheader()
        for addr in sorted(rows):
            r = {k: rows[addr].get(k, "") for k in fields}
            r["address"] = f"{addr:06X}"
            w.writerow(r)


# --------------------------------------------------------------------------
# Ghidra side (needs a started pyghidra and an open program)
# --------------------------------------------------------------------------
def _addr(program, offset: int):
    return program.getAddressFactory().getDefaultAddressSpace().getAddress(offset)


def apply(program, folder: Path, log=print) -> None:
    """Write every annotation in ``folder`` into ``program`` (call inside a transaction)."""
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.program.model.data import ByteDataType, DWordDataType, WordDataType
    from ghidra.program.model.listing import CodeUnit
    from ghidra.program.model.symbol import SourceType
    from ghidra.util.task import TaskMonitor

    ann = Annotations.load(folder)
    st = program.getSymbolTable()
    listing = program.getListing()
    mem = program.getMemory()
    fm = program.getFunctionManager()
    types = {1: ByteDataType(), 2: WordDataType(), 4: DWordDataType()}

    for fname, rows in ann.labels.items():
        for off, row in rows.items():
            targets = [off]
            if 0xFF8000 <= off <= 0xFFFFFF:  # reachable via (xxxx).w too
                targets.append(0xFFFF0000 | (off & 0xFFFF))
            for t in targets:
                a = _addr(program, t)
                prim = st.getPrimarySymbol(a)
                if prim is None or prim.getName() != row["name"]:
                    st.createLabel(a, row["name"], SourceType.USER_DEFINED).setPrimary()
                listing.setComment(a, CodeUnit.EOL_COMMENT, eol_text(row) or None)
                size = int(row["size"] or 0)
                block = mem.getBlock(a)
                if size in types and block is not None and not block.isVolatile() \
                        and listing.getInstructionContaining(a) is None:
                    try:
                        listing.clearCodeUnits(a, a.add(size - 1), False)
                        listing.createData(a, types[size])
                    except Exception:  # noqa: BLE001 - overlaps other data; label still applies
                        pass
        log(f"[annotations] {fname}: {len(rows)} labels")

    for off, row in ann.functions.items():
        a = _addr(program, off)
        func = fm.getFunctionAt(a)
        if func is None:
            if listing.getInstructionAt(a) is None:
                DisassembleCommand(a, None, True).applyTo(program, TaskMonitor.DUMMY)
            CreateFunctionCmd(a).applyTo(program, TaskMonitor.DUMMY)
            func = fm.getFunctionAt(a)
        if func is None:
            log(f"[annotations] WARNING: no function at {off:06X} ({row['name']})")
            continue
        if func.getName() != row["name"] or func.getSymbol().getSource() != SourceType.USER_DEFINED:
            func.setName(row["name"], SourceType.USER_DEFINED)
        func.setComment(plate_text(row) or None)
    log(f"[annotations] functions.csv: {len(ann.functions)} functions")

    kinds = {"pre": CodeUnit.PRE_COMMENT, "post": CodeUnit.POST_COMMENT, "eol": CodeUnit.EOL_COMMENT}
    for (off, kind), text in ann.comments.items():
        listing.setComment(_addr(program, off), kinds[kind], text)
    log(f"[annotations] comments.csv: {len(ann.comments)} comments")


def export(program, folder: Path, log=print) -> Annotations:
    """Collect user annotations from ``program`` and merge them into ``folder``.

    Metadata (size/source/verified) of existing rows is kept, so a rename in
    the GUI only changes the name. Rows whose symbol was deleted in Ghidra are
    dropped. Labels the import script generates itself (vectors, header) are
    not exported.
    """
    from ghidra.program.model.listing import CodeUnit
    from ghidra.program.model.symbol import SourceType, SymbolType

    old = Annotations.load(folder)
    new = Annotations(labels={name: {} for name in LABEL_FILES})
    listing = program.getListing()
    fm = program.getFunctionManager()

    def label_row(off: int, name: str, size: str, eol: str) -> None:
        fname = label_file_for(off)
        prev = old.labels.get(fname, {}).get(off, {})
        comment = prev.get("comment", "") if eol == eol_text(prev) else eol
        # The CSV's size is authoritative (analysis may lay other data types
        # over a table); only new labels take their size from the listing.
        new.labels[fname][off] = {"size": prev["size"] if prev else size, "name": name,
                                  "comment": comment, "source": prev.get("source", ""),
                                  "verified": prev.get("verified", "")}

    for func in fm.getFunctions(True):
        if func.getSymbol().getSource() != SourceType.USER_DEFINED:
            continue
        off = func.getEntryPoint().getOffset()
        if off not in old.functions and off in old.labels.get(label_file_for(off), {}):
            # A data/code label from a label CSV that analysis turned into a
            # function (e.g. a JSR target): keep it where it was defined.
            eol = listing.getComment(CodeUnit.EOL_COMMENT, func.getEntryPoint()) or ""
            label_row(off, func.getName(), "", eol)
            continue
        prev = old.functions.get(off, {})
        plate = func.getComment() or ""
        if prev and plate == plate_text(prev):
            plate = prev["comment"]
        new.functions[off] = {"name": func.getName(), "comment": plate,
                              "source": prev.get("source", ""), "verified": prev.get("verified", "")}

    it = program.getSymbolTable().getAllSymbols(True)
    while it.hasNext():
        sym = it.next()
        if sym.getSource() != SourceType.USER_DEFINED or sym.getSymbolType() != SymbolType.LABEL:
            continue
        if not sym.isPrimary() or fm.getFunctionAt(sym.getAddress()) is not None:
            continue
        off = canonical(sym.getAddress().getOffset())
        fname = label_file_for(off)
        if off in new.labels[fname]:
            continue  # mirror of a RAM label already collected
        size = ""
        data = listing.getDataAt(sym.getAddress())
        if data is not None and data.isDefined() and data.getLength() in (1, 2, 4):
            size = str(data.getLength())
        eol = listing.getComment(CodeUnit.EOL_COMMENT, sym.getAddress()) or ""
        label_row(off, sym.getName(), size, eol)

    labelled = {off for rows in new.labels.values() for off in rows}
    kinds = {"pre": CodeUnit.PRE_COMMENT, "post": CodeUnit.POST_COMMENT, "eol": CodeUnit.EOL_COMMENT}
    from ghidra.program.model.address import AddressSet
    block = program.getMemory().getBlock("ROM")
    rom = AddressSet(block.getStart(), block.getEnd())
    for kind, code in kinds.items():
        ait = listing.getCommentAddressIterator(code, rom, True)
        while ait.hasNext():
            a = ait.next()
            off = a.getOffset()
            if kind == "eol" and off in labelled:
                continue
            new.comments[(off, kind)] = listing.getComment(code, a)
    new.save(folder)
    log(f"[annotations] exported {len(new.functions)} functions, "
        f"{sum(len(v) for v in new.labels.values())} labels, {len(new.comments)} comments")
    return new
