"""Ghidra annotation round-trip: CSV -> fresh database -> CSV must not change.

Slow (~20 s: imports and analyses the ROM). Run with tools/bin/re-test.
"""
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
ROM = ROOT / "rom" / "Mutant League Hockey (USA, Europe).md"
GHIDRA = ROOT / "re" / "ghidra"


@pytest.mark.skipif(not ROM.exists(), reason="ROM not installed")
def test_rebuild_then_export_is_lossless(tmp_path):
    labels = tmp_path / "labels"
    shutil.copytree(ROOT / "re" / "labels", labels)
    before = {p.name: p.read_text() for p in labels.glob("*.csv")}
    project = tmp_path / "project"
    py = sys.executable
    subprocess.run([py, GHIDRA / "mlh_import.py", "--rebuild", "--rom", ROM,
                    "--project-dir", project, "--labels-dir", labels], check=True)
    subprocess.run([py, GHIDRA / "sync.py", "export",
                    "--project-dir", project, "--labels-dir", labels], check=True)
    after = {p.name: p.read_text() for p in labels.glob("*.csv")}
    for name in before:
        assert after[name] == before[name], f"{name} changed in the round trip"
