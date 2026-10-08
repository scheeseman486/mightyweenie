"""End to end (plan 02 acceptance): the original's record vs our side's record
for the same script. Until the scene framework exists our side replays the
original's screen flow and pass timing, so this proves the plumbing: script
timing in GDScript == what the original read from its pads, pass by pass."""
import subprocess
from pathlib import Path

import pytest

from mw_harness.__main__ import original_record
from mw_harness.diff import diff
from mw_harness.probes import load_many
from mw_harness.record import read
from mw_harness.rom import REPO_ROOT
from mw_harness.trace import BLASTEM

GODOT = REPO_ROOT / "tools" / "godot" / "godot"
SCRIPT = REPO_ROOT / "compare" / "scripts" / "coop_start.mwi"
pytestmark = pytest.mark.skipif(not (BLASTEM.exists() and GODOT.exists()), reason="BlastEm/Godot not fetched")


@pytest.fixture(scope="module")
def original(mlh_rom_path):
    return original_record(SCRIPT, "time,input,screen")


def ours(script: Path, original: Path, out: Path) -> list[dict]:
    subprocess.run([str(REPO_ROOT / "tools" / "bin" / "compare-godot"), str(script), "--replay", str(original),
                    "-o", str(out), "--from-screen", "1"], check=True, timeout=170, capture_output=True)
    return read(out)


def test_our_side_matches_the_original(original, tmp_path):
    res = diff(read(original), ours(SCRIPT, original, tmp_path / "godot.jsonl"), load_many("time,input"))
    assert res.ok, res.report()
    assert res.compared_visits == 3 and res.compared_passes > 900


def test_a_changed_press_is_found_at_its_pass(original, tmp_path):
    text = SCRIPT.read_text().replace("@screen 4 @pass 400      P2 B", "@screen 4 @pass 401      P2 B")
    assert text != SCRIPT.read_text()
    changed = tmp_path / "changed.mwi"
    changed.write_text(text)
    res = diff(read(original), ours(changed, original, tmp_path / "godot.jsonl"), load_many("time,input"))
    assert not res.ok
    # the record at boundary n shows what pass n-1 read: B pressed for pass 400 shows at 401
    assert (res.kind, res.screen, res.pass_index, res.fields[0][0]) == ("field", 4, 401, "pads")
