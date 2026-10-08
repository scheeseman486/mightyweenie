"""Pass records of the original (docs/compare.md). Needs the ROM and BlastEm;
each recording boots the game (~5-10 s)."""
from pathlib import Path

import pytest

from mw_harness.diff import diff
from mw_harness.probes import Field, ProbeSet, load_many
from mw_harness.record import record_original, screen_entries_gpgx
from mw_harness.script import PAD_BITS, Script
from mw_harness.trace import BLASTEM

pytestmark = pytest.mark.skipif(not BLASTEM.exists(), reason="BlastEm not fetched")
SCRIPTS = Path(__file__).resolve().parents[2] / "compare" / "scripts"
PAD_MODE = ProbeSet("test", (Field("pad_mode", "[0xffb0e0].b", "-", "exact"),))


def script(name: str) -> Script:
    return Script.parse((SCRIPTS / f"{name}.mwi").read_text(), name)


@pytest.fixture(scope="module")
def coop(mlh_rom_path):
    return record_original(script("coop_start"), load_many("time,input,screen") + [PAD_MODE])


def passes(records, screen=None):
    return [r for r in records if "pass" in r and "event" not in r and (screen is None or r["screen"] == screen)]


def test_header_and_flow(coop):
    assert coop[0]["format"] == "mw-pass/1" and coop[0]["side"] == "original"
    flow = [(r["screen"], r["visit"]) for r in coop if r.get("event") == "screen"]
    assert flow == [(0, 1), (1, 1), (3, 1), (4, 1)]
    assert coop[-1]["event"] == "end"


def test_menu_input_reaches_the_game(coop):
    # two RIGHTs on the pad row: PAD 1 / SEGA -> PAD 1 / PAD 2 -> PAD 1-2 / SEGA
    assert passes(coop, 4)[0]["pad_mode"] == 2


def test_a_tap_is_read_by_exactly_one_pass(coop):
    held_a = [r for r in passes(coop, 4) if (r["pads"][0] >> 8) & PAD_BITS["A"]]
    assert len(held_a) == 1


def test_pass_hold_covers_its_passes(coop):
    # @screen 4 @pass 360..380 P1 UP+LEFT: the record at boundary n shows the read of pass n-1
    held = [r["pass"] - 1 for r in passes(coop, 4) if (r["pads"][0] >> 8) == PAD_BITS["UP"] | PAD_BITS["LEFT"]]
    assert held == list(range(360, 381))


def test_elapsed_matches_ticks(coop):
    rink = passes(coop, 4)
    for a, b in zip(rink, rink[1:]):
        assert b["elapsed"] == b["tick"] - a["tick"]
    assert all(r["phase"] in range(15) for r in rink)


def test_recording_is_deterministic(mlh_rom_path, coop):
    again = record_original(script("coop_start"), load_many("time,input,screen") + [PAD_MODE])
    assert again == coop
    assert diff(coop, again, load_many("time,input,screen")).ok


def test_four_pads(mlh_rom_path):
    rec = record_original(script("four_pads"), load_many("time,input"))
    seen = [0, 0, 0, 0]
    for r in passes(rec, 1):
        for i in range(4):
            seen[i] |= r["pads"][i] >> 8
    assert seen == [PAD_BITS["UP"], PAD_BITS["DOWN"], PAD_BITS["A"], PAD_BITS["B"]]


def test_gpgx_agrees_on_screen_flow(mlh_rom_path):
    s = Script.parse("@screen 1 +200 P1 START\n@screen 4 +60 END\n", "flow")
    blastem = [(r["screen"], r["visit"], r["tick"]) for r in record_original(s, load_many("time"))
               if r.get("event") == "screen"]
    gpgx = screen_entries_gpgx(s, frames=9000)
    assert [x[:2] for x in gpgx] == [x[:2] for x in blastem]
    for (_, _, tb), (_, _, tg) in zip(blastem, gpgx):
        assert abs(tb - tg) <= 2
