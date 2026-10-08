"""mw_harness.menu_cases: record summaries and the committed fixture."""
import json

from mw_harness.menu_cases import FIXTURE, SCRIPTS, summarise


def test_summary_keeps_the_last_pass_of_each_visit():
    recs = [{"event": "screen", "screen": 1, "visit": 1, "tick": 0},
            {"screen": 1, "visit": 1, "pass": 0, "setup_a": 0x16050000, "setup_b": 0x01051600, "setup_c": 0,
             "stadium_mode": 0},
            {"screen": 1, "visit": 1, "pass": 1, "setup_a": 0x16060000, "setup_b": 0x01051600, "setup_c": 4,
             "stadium_mode": 255},
            {"event": "screen", "screen": 3, "visit": 1, "tick": 50}]
    s = summarise(recs)
    assert s["history"] == [1, 3]
    assert s["visits"][0] == {"screen": 1, "visit": 1, "setup": "16060000010516000004", "stadium_mode": 255}
    assert s["visits"][1]["setup"] is None


def test_fixture_covers_every_menu_script():
    d = json.loads(FIXTURE.read_text())
    assert set(d["cases"]) == {p.stem for p in SCRIPTS.glob("menu_*.mwi")}
    for case in d["cases"].values():
        assert case["history"][0] == 0 and all(len(v["setup"]) == 20 for v in case["visits"])
