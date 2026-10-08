class_name MwScreenSim
extends RefCounted
## The node-free part of a screen between plays (plan 11): its state and
## its passes as the original's handler runs them, shared by the screen's
## scene (which draws what a pass asks for) and the checks
## (`test/sim/screen_check.gd`: pass for pass against recorder v5's
## recordings). A screen works on the game's state ([member s], the rink's
## [MwRinkState]: teams, players, the RNG, the penalty boxes, the text box)
## plus its own locals.
##
## A pass: [method step] with the ticks since the last pass (the original's
## tick wait) and the pads as `read_joypads` leaves them in that pass
## (held / newly pressed bytes of pads 1-4); it returns the screen to leave
## for (the exit's fade and teardown included), or -1. What a pass draws is
## left in [member window_ops] / [member plane_ops] (MwWindowPainter's
## operations, on the window and plane B) and [member sprite_ops]; sounds and
## the like in [member events].
##
## Sound (plan 12): in live play ([method live]: no comparison hooks) the
## helpers below also make the original's calls of the sound driver's API
## ([MwSound]) right where the original does, with the driver's handles; the
## checks see the events only. The calls a pass makes after its fade-out
## started ([method fade_out]: the original waits for the fade there) wait
## for the scene's fade ([method fade_over]).

## Leaving: the fade-out's ticks (`fade_out_start(32)`).
const FADE_OUT := 32

var rom: PackedByteArray
var s: MwRinkState
## The screen (`$FFB05E`) and the one it came from (the original's D7).
var screen := -1
var from := -1
## Comparison hooks (optional): voice_poll(sim, handle) -> 0 / 1,
## voice_handle(sim, sound) -> handle, tick(sim) -> the tick a read sees.
var hooks: Object = null
## This pass's window plane operations ([MwWindowPainter]).
var window_ops: Array = []
## This pass's plane B operations ([MwWindowPainter]).
var plane_ops: Array = []
## This pass's sprites, in the original's order: ["anim", record, variant,
## frame, x, y, depth, attr] (an animation object's frame, screen pixels),
## ["piece", piece, x, y, attr, depth], ["portrait", ...] (as
## [member MwRinkPhases.sprite_ops]).
var sprite_ops: Array = []
## Sounds and music: ["sound", id], ["music", id, handle], ["music_stop",
## handle], ["crowd", level], ["crowd_off"], ["voice_stop", handle].
var events: Array = []
## Live sound calls held until the scene's fade-out is over ([method fade_out]).
var _after_fade: Array[Callable] = []
var _fading := false
## Comparison aid: every main-stream draw as [state before, caller].
var rng_log: Array = []
var log_rng := false
var _serial := 0


func _init(rom_: PackedByteArray) -> void:
	rom = rom_


## The screen's set-up (the dispatcher called it with [param from_screen] in
## D7). Virtual.
func enter(state: MwRinkState, screen_id: int, from_screen: int) -> void:
	s = state
	screen = screen_id
	from = from_screen


## One pass of [param elapsed] ticks; [param held] / [param new]: the 4
## pads' bytes as read in this pass. Returns the next screen or -1. Virtual.
func step(_elapsed: int, _held: Array, _new: Array) -> int:
	return -1


## The fields this screen models that differ from the original's RAM
## ([param ram]: an [MwRinkRam] image, [param stack]: the stack page
## `$FFFE00`-`$FFFFFF`) after the same pass: ["what", ours, theirs]. Virtual.
func compare(_ram: PackedByteArray, _stack: PackedByteArray) -> Array:
	return []


## Clears the per-pass outputs (a pass's draws and events).
func begin_pass() -> void:
	window_ops.clear()
	plane_ops.clear()
	sprite_ops.clear()
	events.clear()


## The tick counter (`$FFCA56`) as a read in this pass sees it.
func now() -> int:
	if hooks != null and hooks.has_method("tick"):
		return int(hooks.call("tick", self))
	return s.tick & 0xFFFFFFFF


## `$4BC6`: the next main-stream value.
func rng_next() -> int:
	if log_rng:
		var st := get_stack()
		rng_log.append([s.rng.state, "%s:%d" % [st[1]["function"], st[1]["line"]] if st.size() > 1 else "?"])
	return s.rng.next_state()


## `$4BD6`: uniform in [lo, hi] (a signed word).
func rng_range(lo: int, hi: int) -> int:
	if log_rng:
		var st := get_stack()
		rng_log.append([s.rng.state, "range %s:%d" % [st[1]["function"], st[1]["line"]] if st.size() > 1 else "range"])
	var span := (hi - lo + 1) & 0xFFFF
	var v := s.rng.next_state() & 0xFFFF
	return MwRinkSim.s16(((v * span) >> 16) + lo)


## The OR of the 4 pads' words (held byte << 8 | newly pressed byte), as
## the screens that take any pad test it.
static func pads_word(held: Array, new: Array) -> int:
	var w := 0
	for p in 4:
		w |= ((int(held[p]) & 0xFF) << 8) | (int(new[p]) & 0xFF)
	return w


## A sound effect (`sound_play` `$13CEE`); returns its handle: live, the
## driver's ([method MwSound.play], as a signed long: [method handle_of]); in
## the checks the hooks' or our own. The event ["sound", id, handle]. (Made
## at once even after [method fade_out]: the handle is needed now.)
func sound(id: int) -> int:
	var h: int
	if live():
		h = handle_of(MwSound.play(id & 0xFFFF))
	else:
		_serial = (_serial + 1) & 0x7FFFFFFF
		h = _serial | 0x40000000
		if hooks.has_method("voice_handle"):
			h = int(hooks.call("voice_handle", self, id))
	events.append(["sound", id & 0xFFFF, h])
	return h


## `$13D9C`: is the sound with [param handle] still playing? (Live play
## asks the driver, [method MwSound.busy]; the checks the recording's log.)
func playing(handle: int) -> bool:
	if hooks != null and hooks.has_method("voice_poll"):
		return int(hooks.call("voice_poll", self, handle)) != 0
	return MwSound.busy(handle)


# --- the sound driver's API (plan 12) -------------------------------------------------------------

## Live play: no comparison hooks - the sound calls reach the driver ([MwSound]).
func live() -> bool:
	return hooks == null


## The driver's handle (the original's d0, an unsigned long) as the signed
## long the original's `bpl` / `bmi` tests see (`$FFFFFFFF`: none, -1).
static func handle_of(d0: int) -> int:
	d0 &= 0xFFFFFFFF
	return d0 - 0x100000000 if d0 & 0x80000000 else d0


## A live call of the driver's API [param c] (no event): now, or after the
## fade-out this pass started. Nothing in the checks.
func sound_call(c: Callable) -> void:
	if not live():
		return
	if _fading:
		_after_fade.append(c)
	else:
		c.call()


## `sound_stop` `$13DC2` of [param handle]; the event ["voice_stop", handle].
func voice_stop(handle: int) -> void:
	events.append(["voice_stop", handle])
	sound_call(func() -> void: MwSound.stop(handle))


## `crowd_level` `$13E52` at [param level] (0-1000); the event ["crowd", level].
func crowd_level(level: int) -> void:
	events.append(["crowd", level])
	sound_call(func() -> void: MwSound.crowd_level(level))


## `crowd_off` `$13EFC`; the event ["crowd_off"].
func crowd_off() -> void:
	events.append(["crowd_off"])
	sound_call(func() -> void: MwSound.crowd_off())


## `music_fade_out` `$13CAC` over [param ticks]; the event ["music_fade", ticks].
func fade_music(ticks: int) -> void:
	events.append(["music_fade", ticks])
	sound_call(func() -> void: MwSound.music_fade_out(ticks))


## `fade_out_start` (`$149CC`) of [param ticks] and the original's wait for
## it: the event ["fade_out", ticks]; the live sound calls after it in this
## pass wait for the scene's fade ([method fade_over]).
func fade_out(ticks: int) -> void:
	events.append(["fade_out", ticks])
	if live():
		_fading = true


## The scene's fade-out is over (the screen left, or covered for a switch):
## the sound calls held since [method fade_out], in order.
func fade_over() -> void:
	_fading = false
	var calls := _after_fade
	_after_fade = []
	for c in calls:
		c.call()
