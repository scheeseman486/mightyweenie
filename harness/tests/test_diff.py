"""The diff tool on synthetic records (docs/compare.md)."""
import copy

from mw_harness.diff import diff
from mw_harness.probes import Field, ProbeSet, load_many

SETS = load_many("time,input,screen")


def record(start_tick=100, screens=((1, 5), (4, 6)), first=None):
    recs = [{"format": "mw-pass/1", "side": "x"}]
    t = start_tick
    visits = {}
    for screen, n in ([first] if first else []) + list(screens):
        visits[screen] = visits.get(screen, 0) + 1
        recs.append({"event": "screen", "screen": screen, "visit": visits[screen], "tick": t})
        for i in range(n):
            t += 3
            r = {"screen": screen, "visit": visits[screen], "pass": i, "tick": t, "elapsed": 3,
                 "pads": [0x4040 if i == 2 else 0, 0, 0, 0]}
            if screen in (4, 5, 6):
                r["phase"] = 0
            recs.append(r)
        t += 10
    recs.append({"event": "end", "tick": t})
    return recs


def test_identical_records_match():
    a = record()
    assert diff(a, copy.deepcopy(a), SETS).ok


def test_ticks_compare_relative_to_the_visit():
    a, b = record(start_tick=100), record(start_tick=5000)
    assert diff(a, b, SETS).ok


def test_finds_a_changed_field():
    a = record()
    b = copy.deepcopy(a)
    rec = [r for r in b if r.get("screen") == 4 and r.get("pass") == 3][0]
    rec["phase"] = 2
    res = diff(a, b, SETS)
    assert not res.ok and (res.kind, res.screen, res.pass_index) == ("field", 4, 3)
    assert res.fields == [("phase", 0, 2)]
    assert len(res.context) == 3


def test_held_byte_only():
    a = record()
    b = copy.deepcopy(a)
    rec = [r for r in b if r.get("pass") == 2][0]
    rec["pads"][0] = 0x4000                  # newly-pressed byte consumed by the game
    assert diff(a, b, SETS).ok
    rec["pads"][0] = 0x2000
    assert not diff(a, b, SETS).ok


def test_finds_a_flow_difference():
    res = diff(record(screens=((1, 5), (4, 6), (5, 3))), record(screens=((1, 5), (4, 6), (12, 3))), SETS)
    assert not res.ok and res.kind == "flow" and res.fields == [("screen", 5, 12)]


def test_finds_a_pass_count_difference():
    res = diff(record(screens=((1, 5), (4, 6))), record(screens=((1, 4), (4, 6))), SETS)
    assert not res.ok and res.kind == "passes" and res.screen == 1


def test_last_visit_may_be_cut_short():
    assert diff(record(screens=((1, 5), (4, 6))), record(screens=((1, 5), (4, 4))), SETS).ok


def test_rebases_on_the_later_start():
    original = record(first=(0, 50))          # boots through the title first
    ours = record()                           # starts at the main menu
    assert diff(original, ours, SETS).ok


def test_tolerance_and_ignore():
    tol = ProbeSet("t", (Field("x", "-", "-", {"tolerance": 2}),))
    a, b = record(), record()
    for r in a:
        if "pass" in r and "event" not in r:
            r["x"] = 10
    for r in b:
        if "pass" in r and "event" not in r:
            r["x"] = 12
    assert diff(a, b, [tol]).ok
    for r in b:
        if "pass" in r and "event" not in r:
            r["x"] = 13
    assert not diff(a, b, [tol]).ok
    assert diff(a, b, [ProbeSet("i", (Field("x", "-", "-", "ignore"),))]).ok
