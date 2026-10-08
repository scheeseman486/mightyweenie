"""Python model of the original's pseudo-random number generator.

Reverse engineered in plan 01 (docs/re/rng.md). State: one 32-bit word at
``$FFB096``. All routines take/return plain ints.

    rng_next  ($15616)  advance the state; the new state is the result
    rng_range ($15628)  uniform value in [lo, hi] from one rng_next
    rng_seed  ($155EE)  set the state; 0 = seed from VDP status + HV counter
                        (timing-dependent), then advance 32 times
"""
from __future__ import annotations

RNG_STATE_ADDR = 0xFFB096
M32 = 0xFFFFFFFF


def rng_next(state: int) -> int:
    """One step, exactly as the 68000 code does it:

        move.l (A5),D0 ; move.l D0,D1
        add.l D0,D0    ; lsr.w #1,D0   ; swap D0
        lsr.l #8,D1    ; eor.w D1,D0   ; move.l D0,(A5)
    """
    d0 = (state << 1) & M32
    d0 = (d0 & 0xFFFF0000) | ((d0 & 0xFFFF) >> 1)
    d0 = ((d0 << 16) | (d0 >> 16)) & M32
    d1 = state >> 8
    return (d0 & 0xFFFF0000) | ((d0 ^ d1) & 0xFFFF)


def rng_range(state: int, lo: int, hi: int) -> tuple[int, int]:
    """Returns (new_state, value in [lo, hi]); the scale uses the low word."""
    span = (hi - lo + 1) & 0xFFFF
    state = rng_next(state)
    value = (((state & 0xFFFF) * span) >> 16) + lo
    return state, value & 0xFFFF


def rng_seed(value: int) -> int:
    """Non-zero seeds are used as-is (no warm-up), as in the original."""
    if value == 0:
        raise ValueError("seed 0 means 'seed from hardware timing' - pass the captured value")
    return value & M32


def rng_warmup(state: int, steps: int = 32) -> int:
    """The hardware-seed path advances the fresh state 32 times."""
    for _ in range(steps):
        state = rng_next(state)
    return state


def steps_between(a: int, b: int, limit: int = 4096) -> int | None:
    """How many rng_next calls turn state a into state b (None if > limit)."""
    s = a
    for n in range(limit + 1):
        if s == b:
            return n
        s = rng_next(s)
    return None
