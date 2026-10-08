"""The Python RNG model must reproduce the original exactly."""
import json
from pathlib import Path

from mw_harness import ReferenceEmulator
from mw_harness.rng import RNG_STATE_ADDR, rng_next, rng_range, steps_between

FIXTURE = json.loads((Path(__file__).parent / "fixtures" / "rng_trace.json").read_text())


def test_next_matches_traced_sequence():
    s = FIXTURE["start_state"]
    for want in FIXTURE["next_states"]:
        s = rng_next(s)
        assert s == want


def test_range_matches_traced_calls():
    for call in FIXTURE["range_calls"]:
        _, value = rng_range(call["state_before"], call["lo"], call["hi"])
        assert value == call["value"], call


def test_every_frame_of_the_original_is_explained(mlh_rom_path):
    """Frame to frame, $FFB096 only ever moves by whole rng_next steps."""
    with ReferenceEmulator(mlh_rom_path) as emu:
        prev = None
        for frame in range(1, 3000):
            emu.step("START" if 2400 <= frame <= 2404 else None)
            s = emu.state(with_cpu=False).ram_u32(RNG_STATE_ADDR)
            if prev:
                assert steps_between(prev, s, limit=64) is not None, f"frame {frame}"
            prev = s
