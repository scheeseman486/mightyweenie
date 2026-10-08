#!/usr/bin/env python3
"""Sync annotations between re/labels/*.csv and the Ghidra database.

    tools/bin/py re/ghidra/sync.py apply    # CSV -> DB (after editing CSVs)
    tools/bin/py re/ghidra/sync.py export   # DB -> CSV (after work in the GUI)

The CSVs are what we commit; see annotations_io.py for the format and
re/README.md for the workflow. Close the project in the Ghidra GUI first:
the database has a single writer.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import annotations_io  # noqa: E402

ROOT = HERE.parents[1]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("direction", choices=["apply", "export"])
    ap.add_argument("--project-dir", default=str(ROOT / "re" / "ghidra" / "project"))
    ap.add_argument("--labels-dir", default=str(ROOT / "re" / "labels"))
    a = ap.parse_args()

    import pyghidra
    pyghidra.start()
    project = pyghidra.open_project(Path(a.project_dir), "MLH")
    try:
        with pyghidra.program_context(project, "/MLH") as program:
            if a.direction == "apply":
                with pyghidra.transaction(program, "apply re/labels"):
                    annotations_io.apply(program, Path(a.labels_dir))
                program.save("apply re/labels", pyghidra.task_monitor())
            else:
                annotations_io.export(program, Path(a.labels_dir))
    finally:
        project.close()


if __name__ == "__main__":
    main()
