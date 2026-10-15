class_name MwFullReplayPlayback
extends MwInstantReplay
## Screen 7's playback of the whole match (plan 28; REPLAY LENGTH: FULL
## GAME): [MwInstantReplay]'s controls over [MwFullReplay]'s frames instead
## of the ring's. It starts where the original does (the ring's oldest
## frame: the last play), and rewinds back to the match's first frame and
## plays on to its last. A frame drawn changes the rink state as the
## original's do (plane B's scroll, the markers and plates). The ring is
## not touched, so nothing is put back on leaving.
##
## For the longer reach (owner's request; the original's ring is short):
## A held for more than [constant FAST_AFTER] ticks rewinds faster - twice
## the frames per tick, then four times, ... up to [constant FAST_MAX] -
## and so does C held while playing.

const FAST_AFTER := 120
## Ticks each doubling of the speed takes.
const FAST_STEP := 60
const FAST_MAX := 32

var store: MwFullReplay
## The arena's paint on its 3D frames (plan 37, MwSplatterReplay: the match's
## own, or made again from the store's seed and inputs; null: the paint off).
var paint: MwSplatterReplay
## The frame at the read position (the original's read offset): the next
## one forward; frames before it = [member MwInstantReplay.cursor].
var pos := 0
var _hold_a := 0
var _hold_c := 0


func _init(state: MwRinkState, rom_: PackedByteArray, store_: MwFullReplay) -> void:
	super(state, rom_)
	store = store_
	paint = MwSplatterReplay.of(state, store_)


## Whether screen 7 plays the whole match for [param state].
static func wanted(state: MwRinkState) -> bool:
	return MwSettings.full_replays() and state.full_replay != null and state.full_replay.size() > 0


## The set-up as the original's (`$9DD0`), from the ring's oldest frame
## (the last frame kept when the ring is empty).
func start(control: int) -> void:
	pad = control
	ring.pan = Vector2i.ZERO
	pos = clampi(store.size() - ring.frames, 0, store.size() - 1)
	_peek()
	draw_frame()
	cursor = pos
	play = false
	_peek()


## A saved replay's set-up (plan 34, [MwReplayFile]): from the match's
## first frame, playing (C, as on screen 7, would start it).
func start_first(control: int) -> void:
	pad = control
	ring.pan = Vector2i.ZERO
	pos = 0
	_peek()
	draw_frame()
	cursor = pos
	play = true
	_peek()


## One tick of the loop ([method MwInstantReplay.step]) and, with A held (or C held while
## playing) past [constant FAST_AFTER] ticks, [method extra_frames] more frames at once. True
## when Start leaves.
func step(elapsed: int, held: int, new: int) -> bool:
	_hold_a = _hold_a + elapsed if held & HELD_A else 0
	_hold_c = _hold_c + elapsed if held & NEW_C and play else 0
	if super.step(elapsed, held, new):
		return true
	var hold := _hold_a if _hold_a > 0 else _hold_c
	for i in extra_frames(hold):
		super.step(16, held & HELD_A, 0)          # the next frame at once, no new presses
	return false


## Frames drawn on top of the one a tick draws after A or C was held for
## [param ticks].
static func extra_frames(ticks: int) -> int:
	if ticks <= FAST_AFTER:
		return 0
	var doublings := mini(1 + (ticks - FAST_AFTER) / FAST_STEP, 5)     # 2^5 = FAST_MAX
	return mini((1 << doublings) - 1, FAST_MAX - 1)


## The frames there are to play: the whole match's ([member store]).
func frame_count() -> int:
	return store.size()


## The frame on screen's 3D frame ({} none), with the arena's paint as it
## was then (plan 37; none with the paint off).
func frame_3d() -> Dictionary:
	var i := int(shown.get("at", -1))
	var f := store.side(i)
	if f.is_empty():
		return f
	if paint == null:
		f.erase("splat")
		return f
	return paint.dress(f, i)


## Nothing to put back: the ring was not read.
func leave() -> void:
	pass


func _peek() -> void:
	if pos >= 0 and pos < store.size():
		wait = store.words(pos)[0] & 0xF


func _back() -> void:
	pos = maxi(pos - 1, 0)


## [method MwInstantReplay.draw_frame] (`$9F82`) from the store: the frame at [member pos], which
## then moves on to the next (nothing drawn outside the store).
func draw_frame() -> void:
	if pos < 0 or pos >= store.size():
		return
	var w := store.words(pos)
	var k := [0]
	var next := func() -> int:
		var v: int = w[k[0]] if k[0] < w.size() else 0
		k[0] += 1
		return v
	var more := func() -> bool: return k[0] < w.size() - 1      # sprite records up to the trailer
	_decode(next, more)
	shown["at"] = pos
	_port_side()
	pos += 1
	drawn += 1
