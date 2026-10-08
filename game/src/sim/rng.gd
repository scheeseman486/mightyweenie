class_name MlhRng
extends RefCounted
## The original game's pseudo-random number generator, bit for bit.
##
## Reverse engineered in plan 01 (docs/re/rng.md). The original keeps one
## 32-bit state word (main stream at $FFB096; a second stream at $FFCA18 uses
## the same algorithm) and advances it with [method next_state]. Game code
## consumes it through [method range_value]. Calls happen every main-loop pass
## and every tick of a wait, so to stay in sync with the original the
## simulation must make the same calls in the same order.

const _M32 := 0xFFFFFFFF

## Current 32-bit state.
var state: int = 0


func _init(seed_value: int = 0) -> void:
	state = seed_value & _M32


## One step of the generator; returns the new state.
## 68000: add.l D0,D0 / lsr.w #1,D0 / swap D0 / lsr.l #8,D1 / eor.w D1,D0
func next_state() -> int:
	var d0 := (state << 1) & _M32
	d0 = (d0 & 0xFFFF0000) | ((d0 & 0xFFFF) >> 1)
	d0 = ((d0 << 16) | (d0 >> 16)) & _M32
	var d1 := state >> 8
	state = (d0 & 0xFFFF0000) | ((d0 ^ d1) & 0xFFFF)
	return state


## Uniform value in [lo, hi] (inclusive), from one [method next_state].
## The original scales the low 16 bits: ((state & $FFFF) * span) >> 16.
func range_value(lo: int, hi: int) -> int:
	var span := (hi - lo + 1) & 0xFFFF
	next_state()
	return ((((state & 0xFFFF) * span) >> 16) + lo) & 0xFFFF


## The hardware-seed path: the fresh state is advanced 32 times.
func warm_up(steps: int = 32) -> void:
	for i in steps:
		next_state()
