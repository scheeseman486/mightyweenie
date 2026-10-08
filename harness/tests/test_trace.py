"""BlastEm event tracer (needs the ROM and tools/blastem)."""
from mw_harness.emulator import InputScript
from mw_harness.trace import BLASTEM, Probe, build_script, run_trace
import pytest

pytestmark = pytest.mark.skipif(not BLASTEM.exists(), reason="BlastEm not fetched")
VBLANK = 0x13F96          # IRQ6_VBlank
READ_JOYPADS = 0x1407E    # joypad read routine
TICKS = "[0xffca56].l"


def test_script_quotes_bindings():
    s = build_script([], 10, InputScript.parse("2-3:START"))
    assert 'binddown "gamepads.1.start"' in s and 'bindup "gamepads.1.start"' in s


def test_trace_is_deterministic(mlh_rom_path):
    a = run_trace([Probe(VBLANK, "vb", [TICKS])], frames=600)
    b = run_trace([Probe(VBLANK, "vb", [TICKS])], frames=600)
    assert a and [(e.cycle, e.values) for e in a] == [(e.cycle, e.values) for e in b]


def test_ticks_advance_one_per_vblank_on_ntsc(mlh_rom_path):
    ev = run_trace([Probe(VBLANK, "vb", [TICKS])], frames=900)
    ticks = [e.values[0] for e in ev]
    assert ticks == list(range(ticks[0], ticks[0] + len(ticks)))


def test_scripted_input_reaches_the_game(mlh_rom_path):
    ev = run_trace([Probe(READ_JOYPADS, "pad", ["[0xffca5a].w"])], frames=760,
                   inputs=InputScript.parse("750-753:START"))
    # $FFCA5A = P1 held (high byte) | P1 newly pressed (low byte); Start = $80
    words = [e.values[0] for e in ev if e.frame >= 750]
    assert 0x8080 in words and 0x8000 in words
