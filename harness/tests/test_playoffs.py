"""mw_harness.playoffs (the Python reference) against the original's vectors."""
import json

import pytest

from mw_harness.playoffs import (State, alphabet, bracket, decode, encode, opponents, reseed, results)
from mw_harness.playoff_vectors import FIXTURE
from mw_harness.rom import Rom, default_rom_path

CASES = json.loads(FIXTURE.read_text())["cases"]


@pytest.fixture(scope="module")
def rom():
    try:
        return Rom.load(default_rom_path()).data
    except FileNotFoundError:
        pytest.skip("ROM not installed")


def _bracket_check(rom, case, st):
    a, b = st.teams()
    first, second, rng = bracket(reseed(st.seed), a, b)
    fr, sr, rng = results(rng, rom, first, second, st.flag_11)
    assert case["bracket"] == first + fr + second + sr
    assert rng == st.rng
    assert list(opponents(fr, sr, first, st.round)) == case["teams"]


@pytest.mark.parametrize("name", ["new_run", "reroll"])
def test_new_runs_draw_the_same_bracket(rom, name):
    case = CASES[name]
    _bracket_check(rom, case, State.from_ram(bytes.fromhex(case["state"])))


@pytest.mark.parametrize("name", ["typed_best_of_3", "typed_single"])
def test_typed_passwords_decode_like_the_original(rom, name):
    case = CASES[name]
    abc = alphabet(rom)
    pw = bytes(abc[i] for i in case["typed"])
    got = decode(pw, rom)
    want = State.from_ram(bytes.fromhex(case["state"]))
    assert got is not None
    for f in ("dead_a", "dead_b", "seed", "pair", "conference", "best_of_3", "flag_11", "series", "round"):
        assert getattr(got, f) == getattr(want, f), f
    _bracket_check(rom, case, want)


def test_shown_password_like_the_original(rom):
    case = CASES["shown"]
    poked = State.from_ram(bytes.fromhex(case["poke"]))
    poked.flags |= 0x10               # not mid-series: the opponent's dead players will be random
    pw, st = encode(poked, rom)
    abc = alphabet(rom)
    assert [abc.index(c) for c in pw] == case["password"]
    assert st.dead_b == State.from_ram(bytes.fromhex(case["state"])).dead_b


def test_passwords_round_trip_and_refusals(rom):
    st = State(seed=0x9F, pair=61, conference=1, best_of_3=1, series=1, round=0, dead_a=0x3FFFF, dead_b=0x12345)
    pw, _ = encode(st, rom)
    assert decode(pw, rom).dead_b == 0x12345
    st.series = 0
    st.flags = 0x10
    pw, _ = encode(st, rom)
    bad = pw[:3] + bytes([pw[3] ^ 1 if pw[3] ^ 1 in alphabet(rom) else pw[2]]) + pw[4:]
    assert decode(pw, rom) is not None
    assert decode(bad, rom) is None or bad == pw
    same = State(seed=0x9F, pair=66, round=0, flags=0x10)
    assert decode(encode(same, rom)[0], rom) is None, "A and B the same team"
