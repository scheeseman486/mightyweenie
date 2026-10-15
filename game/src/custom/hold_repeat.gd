class_name MwHoldRepeat
extends RefCounted
## Left / Right held on a number in the editors (plan 38 follow-up; owner:
## held, it repeats, speeding up gradually) - or any pair of verbs, or one
## ([method _init]; the text inputs' cursor, keys and erase: owner,
## 2026-10-12, backspace / delete repeating when held as well). The press
## itself makes the first step (the screen's own handling); held past
## [constant DELAY] ticks the value repeats, every [constant START_EVERY]
## ticks at first and a tick quicker for every [constant RAMP] ticks held,
## down to a step a tick. Counted in the passes' ticks (no wall clock).

const DELAY := 20
const START_EVERY := 6
const RAMP := 24
## A step's sound only every this many repeats (a tick's step would buzz).
const SOUND_EVERY := 3

var _dir := 0
var _held := 0
var _wait := 0
var _count := 0
## The verbs counted down (-1) and up (+1); "" none.
var minus := "ui_left"
var plus := "ui_right"


## Repeats [param minus_] (-1) and [param plus_] (+1) held; one of them ""
## for a verb alone.
func _init(minus_ := "ui_left", plus_ := "ui_right") -> void:
	minus = minus_
	plus = plus_


## The steps due this pass of [param elapsed] ticks: +n Right ([member
## plus]) held, -n Left ([member minus]) held, 0 none (nothing held, the
## other direction, or [param active] false: the selection isn't a number).
func step(input: MwInputFrame, elapsed: int, active: bool) -> int:
	var d := 0
	if input != null and active:
		var r := plus != "" and input.is_held(plus)
		var l := minus != "" and input.is_held(minus)
		d = 1 if r and not l else (-1 if l and not r else 0)
	if d == 0 or d != _dir:
		_dir = d
		_held = 0
		_wait = DELAY
		_count = 0
		return 0
	_held += elapsed
	_wait -= elapsed
	var n := 0
	while _wait <= 0:
		n += 1
		_wait += every()
	_count += n
	return n * d


## Ticks between repeats now.
func every() -> int:
	@warning_ignore("integer_division")
	return maxi(1, START_EVERY - maxi(_held - DELAY, 0) / RAMP)


## Whether this repeat makes its sound ([constant SOUND_EVERY]).
func sound_due() -> bool:
	return _count % SOUND_EVERY == 0
