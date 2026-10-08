"""Probe sets (compare/probes/*.json): named per-pass fields, how each side
provides them and how the diff compares them. See docs/compare.md."""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from .rom import REPO_ROOT

PROBE_DIR = REPO_ROOT / "compare" / "probes"
BUILTIN = "builtin"     # recorded by every pass line (time, input, screen sets)
ALWAYS = ("time", "input", "screen")


@dataclass(frozen=True)
class Field:
    name: str
    original: str              # BlastEm expression, or "builtin"
    godot: str                 # observe() key, or "builtin"
    compare: object            # "exact" | "relative" | "ignore" | {"tolerance": n}
    screens: tuple[int, ...] | None = None

    def applies(self, screen: int) -> bool:
        return self.screens is None or screen in self.screens


@dataclass(frozen=True)
class ProbeSet:
    name: str
    fields: tuple[Field, ...]


def load(name: str, folder: Path = PROBE_DIR) -> ProbeSet:
    d = json.loads((folder / f"{name}.json").read_text())
    fields = tuple(Field(f["name"], f["original"], f["godot"], f.get("compare", "exact"),
                         tuple(f["screens"]) if "screens" in f else None) for f in d["fields"])
    return ProbeSet(d["name"], fields)


def load_many(names) -> list[ProbeSet]:
    if isinstance(names, str):
        names = [n for n in names.split(",") if n]
    return [load(n) for n in names]


def available(folder: Path = PROBE_DIR) -> list[str]:
    return sorted(p.stem for p in folder.glob("*.json"))
