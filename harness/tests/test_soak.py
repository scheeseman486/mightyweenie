"""Soak runs (`mw_harness.soak`, plan 10): run configurations, visits,
coverage totals and the greedy picks, on synthetic run summaries. No
BlastEm needed."""
import inspect

from mw_harness import sim_record as sr
from mw_harness import soak


def test_config_is_deterministic_and_valid():
    for seed in range(1, 200):
        c = soak.config(seed)
        assert c == soak.config(seed)
        s = c["setup"]
        assert s[0xFFB0DE] != s[0xFFB0DF] and 0 <= s[0xFFB0DE] < 23 and 0 <= s[0xFFB0DF] < 23
        assert s[0xFFB0E0] in (0, 1, 2, 4, 5)
        assert (s[0xFFB0E2], c["late"][0xFFB0E3]) in ((0, 3), (1, 5), (2, 8))
        assert 0 < c["rng_poke"] < 1 << 32
        if s[0xFFB0E1]:                       # playoffs: human pads, the home stadium, end at screen 16
            assert s[0xFFB0E0] != 5 and 0xFFB0E4 not in s and c["stop_screens"] == (16,)
        else:
            assert c["stop_screens"] == (1,)
        soak.describe(c)
    modes = [soak.config(seed)["setup"][0xFFB0E0] for seed in range(1, 400)]
    assert 0.45 < modes.count(5) / len(modes) < 0.75


def test_record_args_fit_record():
    params = inspect.signature(sr.record).parameters
    for k in soak.record_args(soak.config(7)):
        assert k in params, k
    for k in ("coverage", "lean_until_visit", "rng_poke"):
        assert k in params


def test_instrumented_holds_the_recorders_own_stops():
    own = sr.instrumented()
    assert {sr.SCREEN_CALL, sr.VBLANK, sr.SEG_START, sr.PAUSE_OPEN} <= own
    assert set(sr.TICK_SITES) <= own and sr.RINK_EXIT in own
    assert sr.RINK_EXIT not in sr.instrumented(draws=False)
    assert sr.SCREEN_CALL in own and 0xA4AA in own        # the "pen" log


SCREENS = [[3, 100], [4, 200], [12, 900], [5, 1000], [14, 2000], [4, 2100], [15, 3000], [1, 3100]]


def test_visit_of():
    assert soak.visit_of(SCREENS, 150) == 0       # matchup
    assert soak.visit_of(SCREENS, 200) == 1
    assert soak.visit_of(SCREENS, 950) == 0       # goal scoreboard
    assert soak.visit_of(SCREENS, 1500) == 2
    assert soak.visit_of(SCREENS, 2500) == 3
    assert soak.visit_of(SCREENS, 3050) == 0


def _run(seed, hits):
    return {"seed": seed, "screens": SCREENS, "hits": {f"{a:06X}": v for a, v in hits.items()}}


def test_coverage_and_pick():
    runs = [_run(1, {0x100: [250, 4], 0x200: [1500, 5], 0x300: [150, 3]}),
            _run(2, {0x100: [300, 4], 0x400: [2500, 4], 0x500: [2600, 4], 0x600: [2700, 4]})]
    cov = soak.coverage(runs)
    assert cov[0x100] == {"runs": 2, "first": [1, 250, 4, 1]}
    assert cov[0x400]["first"] == [2, 2500, 4, 3]
    picks = soak.pick(runs, 5)
    # visit 3 of seed 2 adds the most (3), then seed 1's visit 1 ($100; ties go to the lower seed), then visit 2
    assert [(s, v, len(n)) for s, v, n in picks] == [(2, 3, 3), (1, 1, 1), (1, 2, 1)]
    assert soak.pick(runs, 5, have={0x100, 0x200, 0x400, 0x500, 0x600}) == []


def test_seed_lists():
    assert soak._seeds("1-3,7") == [1, 2, 3, 7]


def test_soak_runs_are_named_by_seed_and_visit():
    for name, (seed, visit, visits) in sr.SOAK_RUNS.items():
        assert name == sr.soak_name(seed, visit) and visit >= 1 and visits >= 1


def test_frozen_targets():
    t = soak.targets()
    assert len(t) == 856 and all(0x200 <= a < 0x1FFD60 and a % 2 == 0 for a in t)
    assert t[0xA4AA] == "penalty_call"          # a labelled name wins
