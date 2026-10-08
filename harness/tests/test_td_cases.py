"""mw_harness.td_cases: record summaries and the committed fixture."""
import json

from mw_harness.td_cases import FIXTURE, SCRIPTS, summarise


def test_summary_keeps_passes_that_change_something():
    recs = [{"event": "screen", "screen": 1, "visit": 1, "tick": 0},
            {"screen": 1, "visit": 1, "pass": 0},
            {"event": "screen", "screen": 2, "visit": 1, "tick": 100},
            {"screen": 2, "visit": 1, "pass": 0, "tick": 113, "vscroll": 160, "side": 0, "cursor": 0, "line": 0},
            {"screen": 2, "visit": 1, "pass": 1, "tick": 114, "vscroll": 160, "side": 0, "cursor": 0, "line": 0},
            {"screen": 2, "visit": 1, "pass": 2, "tick": 120, "vscroll": 158, "side": 0, "cursor": 0, "line": 0},
            {"screen": 2, "visit": 1, "pass": 3, "tick": 130, "vscroll": 158, "side": 1, "cursor": 0, "line": 0},
            {"event": "screen", "screen": 1, "visit": 2, "tick": 200}]
    s = summarise(recs)
    assert s["history"] == [1, 2, 1]
    assert s["visits"] == [{"visit": 1, "states": [[13, 160, 0, 0, 0], [20, 158, 0, 0, 0], [30, 158, 1, 0, 0]]}]


def test_fixture_covers_every_td_script():
    d = json.loads(FIXTURE.read_text())
    assert set(d["cases"]) == {p.stem for p in SCRIPTS.glob("td_*.mwi")}
    for case in d["cases"].values():
        assert case["history"][:3] == [0, 1, 2]
        assert all(len(s) == 5 for v in case["visits"] for s in v["states"])
