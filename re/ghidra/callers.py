#!/usr/bin/env python3
"""Which screen handlers (or other named roots) reach a function? (read-only)

    tools/bin/py re/ghidra/callers.py 122d6 1291a [--roots screen_]

Walks the call graph upwards (BFS) from each target and prints the shortest
caller chain to every function whose name starts with a root prefix.
"""
from __future__ import annotations

import argparse
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("targets", nargs="+")
    ap.add_argument("--roots", default="screen_")
    a = ap.parse_args()
    import pyghidra
    pyghidra.start()
    from ghidra.program.flatapi import FlatProgramAPI
    project = pyghidra.open_project(ROOT / "re" / "ghidra" / "project", "MLH")
    try:
        with pyghidra.program_context(project, "/MLH") as program:
            flat = FlatProgramAPI(program)
            fm = program.getFunctionManager()
            for t in a.targets:
                start = fm.getFunctionContaining(flat.toAddr(f"{int(t, 16):08x}"))
                if start is None:
                    print(f"{t}: no function"); continue
                seen = {start.getEntryPoint(): None}
                q = deque([start]); hits = []
                while q:
                    f = q.popleft()
                    if f.getName().startswith(a.roots):
                        chain, g = [], f
                        while g is not None:
                            chain.append(g.getName()); prev = seen[g.getEntryPoint()]; g = prev
                        hits.append(" <- ".join(reversed(chain)) if False else " -> ".join(chain))
                        continue
                    for c in f.getCallingFunctions(None):
                        if c.getEntryPoint() not in seen:
                            seen[c.getEntryPoint()] = f; q.append(c)
                print(f"{start.getName()}:")
                for h in hits or ["(no root reached)"]:
                    print("   ", h)
    finally:
        project.close()


if __name__ == "__main__":
    main()
