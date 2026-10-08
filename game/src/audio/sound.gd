class_name MwSound
extends RefCounted
## The original's sound calls for game code (plan 12): the API of the 68000
## side of the sound driver (`$13BE0-$13FFF`, docs/re/sound.md), answered by
## the running [MwAudio] service ([member driver]).
##
## Without a driver (headless runs: tests, checks, `live_match.gd`) the calls
## keep the silent stand-in's answers: [method play] hands out serial handles
## (recorded in [member cues]), nothing is ever busy.
##
## Handles are the original's d0: unsigned 32-bit, `$FFFFFFFF` = nothing
## started, bit 31 set = a sequence.

const NONE := 0xFFFFFFFF

## The audio service, or null.
static var driver: MwAudio = null
static var _next := 1
static var cues: Array = []     ## [id, handle] of every start without a driver (tests)
## Debug hook: when valid, called after every call of this API (with or
## without a driver) as `trace.call(name, args, result)` - [param name] the
## method's, [param args] its arguments (an Array), [param result] what it
## returns (null for none). Live logs (`test/screens/live_sound.gd`) and tests.
static var trace := Callable()


## `sound_play` `$13CEE`: sound [param id] (`$00-$11` sequences, `$12-$3A`
## PCM voices); stops the last positional sound first. Returns the handle.
static func play(id: int) -> int:
	var h: int
	if driver:
		h = driver.s68k.sound_play(id)
	else:
		h = _next
		_next += 1
		cues.append([id, h])
		if cues.size() > 256:
			cues.pop_front()
	_trace("play", [id], h)
	return h


## `sound_busy` `$13D9C`: is [param handle] still playing?
static func busy(handle: int) -> bool:
	var b := driver.s68k.sound_busy(handle) if driver else false
	_trace("busy", [handle], b)
	return b


## `sound_stop` `$13DC2`.
static func stop(handle: int) -> void:
	if driver:
		driver.s68k.sound_stop(handle)
	_trace("stop", [handle])


## `$13D58`: a sound tied to a rink object - played only when [param
## on_screen] (`$5C3C`), replacing the previous one (60 ticks at most).
static func positional(id: int, on_screen: bool) -> void:
	if driver:
		driver.s68k.positional(id, on_screen)
	_trace("positional", [id, on_screen])


## `$13CE2`: one of the four phase-start jingles (ids 5-8) from [param
## rng_value] (`rng_next`'s result).
static func random_sound(rng_value: int) -> void:
	if driver:
		driver.s68k.random_sound(rng_value)
	_trace("random_sound", [rng_value])


## `$13C66`: the title music (also the playoffs champion's), repeating.
static func music_title() -> void:
	if driver:
		driver.s68k.music_title()
	_trace("music_title", [])


## `$13C6E`: the menus' music, repeating (kept if already playing).
static func music_game() -> void:
	if driver:
		driver.s68k.music_game()
	_trace("music_game", [])


## `music_fade_out` `$13CAC`: the music stops [param ticks] ticks from now.
static func music_fade_out(ticks: int) -> void:
	if driver:
		driver.s68k.music_fade_out(ticks)
	_trace("music_fade_out", [ticks])


## `$13C04`: the music faded over [param ticks], the crowd off, the driver
## reset (entering or leaving a match).
static func enter_match(ticks: int) -> void:
	if driver:
		driver.enter_match(ticks)
	_trace("enter_match", [ticks])


## `crowd_level` `$13E52`: the crowd noise for a crowd level 0-1000.
static func crowd_level(level: int) -> void:
	if driver:
		driver.s68k.crowd_level(level)
	_trace("crowd_level", [level])


## `$13EB6`: the crowd started again if it should be playing.
static func crowd_restart() -> void:
	if driver:
		driver.s68k.crowd_restart()
	_trace("crowd_restart", [])


## `$13EEA`: the crowd fades out.
static func crowd_fade() -> void:
	if driver:
		driver.s68k.crowd_fade()
	_trace("crowd_fade", [])


## `crowd_off` `$13EFC`: the crowd stops.
static func crowd_off() -> void:
	if driver:
		driver.s68k.crowd_off()
	_trace("crowd_off", [])


static func _trace(what: String, args: Array, result: Variant = null) -> void:
	if trace.is_valid():
		trace.call(what, args, result)
