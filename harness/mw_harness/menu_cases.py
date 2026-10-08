"""Menu cases: scripted runs of the original's menus and the setup they leave.

Records each ``compare/scripts/menu_*.mwi`` on the original (BlastEm, EA 4-Way
Play, cached like ``record``) with the ``setup`` probes and keeps, per screen
visit, the setup bytes (`$FFB0DE`-`$FFB0E7`) and the main menu's stadium mode
at its last pass. ``compare/fixtures/menu_cases.json`` (no ROM content);
game/test/flow/test_main_menu.gd plays the same scripts on our screens.

    tools/bin/py -m mw_harness menu-cases [--update] [NAME ...]
"""
from __future__ import annotations

import json
from pathlib import Path

from .record import read
from .rom import REPO_ROOT

FIXTURE = REPO_ROOT / "compare" / "fixtures" / "menu_cases.json"
SCRIPTS = REPO_ROOT / "compare" / "scripts"
PROBES = "time,input,screen,setup"


def summarise(records: list[dict]) -> dict:
    visits: list[dict] = []
    history: list[int] = []
    for r in records:
        if r.get("event") == "screen":
            history.append(r["screen"])
            visits.append({"screen": r["screen"], "visit": r["visit"], "setup": None})
        elif "pass" in r and visits and "setup_a" in r:
            v = visits[-1]
            v["setup"] = f"{r['setup_a']:08x}{r['setup_b']:08x}{r['setup_c']:04x}"
            if "stadium_mode" in r:
                v["stadium_mode"] = r["stadium_mode"]
    return {"history": history, "visits": visits}


def measure(names=None) -> dict:
    from .__main__ import original_record

    cases = {}
    for path in sorted(SCRIPTS.glob("menu_*.mwi")):
        if names and path.stem not in names:
            continue
        cases[path.stem] = summarise(read(original_record(path, PROBES)))
    return cases


def main(update: bool = False, names=None) -> None:
    cases = measure(names)
    old = json.loads(FIXTURE.read_text())["cases"] if FIXTURE.exists() else {}
    old.update(cases)
    data = {"format": "mw-menu-cases/1",
            "comment": "Setup bytes ($FFB0DE-$FFB0E7, hex) and the main menu's stadium mode at the last "
                       "pass of each screen visit, from the original running compare/scripts/menu_*.mwi "
                       "(mw_harness menu-cases). No ROM content.",
            "cases": dict(sorted(old.items()))}
    text = "{\n" + ",\n".join(f" {json.dumps(k)}: {json.dumps(v)}" for k, v in data.items()) + "\n}\n"
    if update:
        FIXTURE.write_text(text)
        print(f"wrote {FIXTURE.relative_to(REPO_ROOT)}")
    else:
        print(text)
