"""Input scripts v1 and the timing rules (docs/compare.md). The fixtures in
compare/fixtures/ are shared with the GDScript implementation's GUT tests."""
import json
from pathlib import Path

import pytest

from mw_harness.script import Script, ScriptError, ScriptPlayer

FIX = Path(__file__).resolve().parents[2] / "compare" / "fixtures"
SCRIPTS = Path(__file__).resolve().parents[2] / "compare" / "scripts"
PARSE = json.loads((FIX / "scripts_parse.json").read_text())
TIMELINE = json.loads((FIX / "player_timeline.json").read_text())


@pytest.mark.parametrize("case", PARSE["valid"], ids=lambda c: c["text"])
def test_parse_valid(case):
    (e,) = Script.parse(case["text"]).events
    want = case["event"]
    got = {k: getattr(e, k) for k in want}
    assert got == want
    assert e.to_text() == case["canonical"]
    (again,) = Script.parse(e.to_text()).events
    assert {k: getattr(again, k) for k in want} == want


@pytest.mark.parametrize("text", PARSE["invalid"])
def test_parse_invalid(text):
    with pytest.raises(ScriptError, match="line 1"):
        Script.parse(text)


def test_shipped_scripts_parse():
    for path in SCRIPTS.glob("*.mwi"):
        s = Script.parse(path.read_text())
        assert s.events, path
        assert Script.parse(s.to_text()).to_text() == s.to_text()


def play(case):
    player = ScriptPlayer(Script.parse(case["script"]))
    for step in case["timeline"]:
        kind, *args = step
        if kind == "screen":
            player.screen_entered(args[0], args[1])
        elif kind == "tick":
            player.tick_start(args[0])
        elif kind == "pass":
            player.boundary(*args)
        elif kind == "resume":
            player.resume(*args)
    return player


@pytest.mark.parametrize("case", TIMELINE["cases"], ids=lambda c: c["name"])
def test_timing_rules(case):
    assert [list(x) for x in play(case).log] == case["log"]


def test_tap_is_read_by_exactly_one_pass():
    """Whatever the pass length, exactly one boundary starts a pass with the tap down."""
    for length in range(1, 8):
        player = ScriptPlayer(Script.parse("@screen 5 +3 P1 A"))
        player.screen_entered(5, 0)
        reads, n = 0, 0
        for tick in range(1, 60):
            player.tick_start(tick)
            if tick % length == 0:
                player.boundary(5, 1, n, tick)
                n += 1
                reads += bool(player.held(1))
        assert reads == 1, length
