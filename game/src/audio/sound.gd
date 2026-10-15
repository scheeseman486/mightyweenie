class_name MwSound
extends RefCounted
## The original's sound calls for game code (plan 12): the API of the 68000
## side of the sound driver (`$13BE0-$13FFF`, docs/re/sound.md), answered by
## the running [MwAudio] service ([member driver]).
##
## One answer to "still playing?" (plan 40, D6, owner: the answers merged): the
## driver's - the running service's, or its model's (MwRouter.use_driver_model:
## every router without a service of its own has it, headless games,
## recordings, replays and the tests alike) - so the answers the game waits
## on (a voice playing, the goal song carried, the chant heard) are the same
## with sound or without, on every machine and in every test. With no driver
## at all (no ROM) nothing starts ([constant NONE]) and nothing is busy.
## The original's checks answer from its recordings instead (their hooks,
## MwScreenSim / MwRinkPhases), never through here.
##
## Handles are the original's d0: unsigned 32-bit, `$FFFFFFFF` = nothing
## started, bit 31 set = a sequence.

const NONE := 0xFFFFFFFF
## Port only ([member MwSettings.goal_song_carries]): a second's fade-in of
## the scoreboard's crowd or music after the carried goal song.
const FADE_IN_TICKS := 60

## The audio service, or null.
static var driver: MwAudio = null
## Debug hook: when valid, called after every call of this API (with or
## without a driver) as `trace.call(name, args, result)` - [param name] the
## method's, [param args] its arguments (an Array), [param result] what it
## returns (null for none). Live logs (`test/screens/live_sound.gd`) and tests.
static var trace := Callable()
## Plan 41 (online feel): while true every call that would start, stop or
## change a sound does nothing (a sound returns [constant NONE], untraced) -
## a client's prediction runs the game's own handlers on a copy, and what it
## plays must not reach the driver, whose answers the game waits on (the
## questions still answer as the driver does). MwLocalEcho.run sets it.
static var quiet := false
## Plan 41 work item 3: an online client's audible driver, apart from
## [member driver] (then the driver's model: the game's calls and
## questions) - every game's call is heard on it too ([MwHeard]); null
## (offline, the host): [member driver] is heard.
static var heard: MwHeard = null
## Plan 41 work item 3: while true the calls are a prediction's (the menus'
## local echo, the run-ahead's passes): heard at once on [member heard]
## under [member predict_key] (once per key), never traced; with [member
## quiet] they reach no driver of the game's (the run-ahead's own model
## takes them: it is [member driver] while it runs).
static var predicting := false
## The prediction's key: the press or the pass the calls are made for.
static var predict_key := ""
## The router tick the game is expected to make the prediction's calls at
## (MwHeard: its own call then isn't heard again); -1 now.
static var predict_due := -1
## Port only ([member MwSettings.goal_song_carries]): the goal song carried
## over from the rink ([method carry_over]) while it plays; [constant NONE]:
## none.
static var carried := NONE
static var _fade_pending := false


## Plan 35: the port's own bookkeeping back to power-on (a fresh game in
## the same process: recordings and replays): no carried song, no fade-in
## pending.
static func reset() -> void:
	carried = NONE
	_fade_pending = false
	if heard != null:
		heard.synced()


## Plan 45 (docs/style.md D8): the globals a prediction swaps (the client's
## run-ahead: its own driver model, heard as predictions), saved by
## [method begin_swap] and put back by [method end_swap]; empty when nothing
## is swapped.
static var _swap := {}


## Saves the globals a prediction is about to swap ([member quiet],
## [member predicting], [member predict_key], [member predict_due]; with
## [param whole] [member driver] and the API's bookkeeping too - the
## run-ahead's own model; a local echo keeps the game's), to be put back by
## [method end_swap].
static func begin_swap(whole := true) -> void:
	reset_swaps()                            # (one left open: its saved globals are the true ones)
	_swap = {"quiet": quiet, "predicting": predicting, "key": predict_key, "due": predict_due}
	if whole:
		_swap["driver"] = driver
		_swap["state"] = snapshot_state()


## Puts back what [method begin_swap] saved (nothing when nothing is swapped).
static func end_swap() -> void:
	if _swap.is_empty():
		return
	quiet = _swap["quiet"]
	predicting = _swap["predicting"]
	predict_key = _swap["key"]
	predict_due = _swap["due"]
	if _swap.has("driver"):
		driver = _swap["driver"]
		restore_state(_swap["state"])
	_swap = {}


## A swap no [method end_swap] closed - the prediction stopped by a script
## error - put back; the online match calls it before the game's own ticks,
## so the game's sound calls and "still playing?" questions never reach the
## prediction's model. True when something was left.
static func reset_swaps() -> bool:
	if _swap.is_empty():
		return false
	push_error("MwSound: a prediction's swap was left open - put back")
	end_swap()
	return true


## Plan 35 work item 6: the port's bookkeeping a resync snapshot carries -
## the carried goal song, its fade-in pending.
static func snapshot_state() -> Dictionary:
	return {"carried": carried, "fade": _fade_pending}


## [method snapshot_state]'s [param d] back.
static func restore_state(d: Dictionary) -> void:
	carried = int(d.get("carried", NONE)) & 0xFFFFFFFF
	_fade_pending = bool(d.get("fade", false))


## `sound_play` `$13CEE`: sound [param id] (`$00-$11` sequences, `$12-$3A`
## PCM voices); stops the last positional sound first. Returns the handle.
## The goal song (`$09`) may play another tune of the organ pool ([member
## MwAudio.organ_pool], plan 39).
static func play(id: int) -> int:
	return int(_send("play", [id], NONE))


## Port only: sound [param id] (a sampled effect) at [param rate] (8.8,
## `$100` as recorded) and [param volume] (`$100` as recorded) - the game
## setup's second crash, lower and softer ([method
## MwSound68k.sound_play_voice]). Returns the handle.
static func play_voice(id: int, rate: int, volume: int) -> int:
	return int(_send("play_voice", [id, rate, volume], NONE))


## `sound_busy` `$13D9C`: is [param handle] still playing?
static func busy(handle: int) -> bool:
	if driver != null and driver.owed > 0:
		driver.settle()
	var b := driver.s68k.sound_busy(handle) if driver else false
	_trace("busy", [handle], b)
	return b


## `sound_stop` `$13DC2`.
static func stop(handle: int) -> void:
	_send("stop", [handle])


## `$13D58`: a sound tied to a rink object - played only when [param
## on_screen] (`$5C3C`), replacing the previous one (60 ticks at most).
static func positional(id: int, on_screen: bool) -> void:
	_send("positional", [id, on_screen])


## `$13CE2`: one of the four phase-start jingles (ids 5-8) from [param
## rng_value] (`rng_next`'s result); with [member MwAudio.organ_pool] a tune
## of the organ pool (plan 39).
static func random_sound(rng_value: int) -> void:
	_send("random_sound", [rng_value])


## Port only (plan 34, owner): FM effect [param name] ([constant
## MwFmSfx.EFFECTS], e.g. "gate": a chain-link gate lifting) on the FM
## channel the music leaves free (FM6), from the next tick.
static func fm_effect(name: String) -> void:
	_send("fm_effect", [name])


## Port only (plan 34): the FM effect playing ends (keyed off; FM6 back to
## the driver).
static func fm_effect_stop() -> void:
	_send("fm_effect_stop", [])


## `$13C66`: the title music (also the playoffs champion's), repeating.
static func music_title() -> void:
	_send("music_title", [])


## `$13C6E`: the menus' music, repeating (kept if already playing).
static func music_game() -> void:
	_send("music_game", [])


## `music_fade_out` `$13CAC`: the music stops [param ticks] ticks from now.
static func music_fade_out(ticks: int) -> void:
	_send("music_fade_out", [ticks])


## `$13C04`: the music faded over [param ticks], the crowd off, the driver
## reset (entering or leaving a match).
static func enter_match(ticks: int) -> void:
	if quiet:
		return
	_send("enter_match", [ticks], null, false)
	carried = NONE
	_fade_pending = false
	_trace("enter_match", [ticks])


## Port only ([member MwSettings.goal_song_carries]): the rink left while
## sequence [param keep] (the goal song) plays - instead of [method
## enter_match], every other sound stopped and [param keep] playing on
## ([method MwAudio.carry_over]); [member carried] until it ends.
static func carry_over(keep: int) -> void:
	if quiet:
		return
	carried = NONE
	_fade_pending = false
	_send("carry_over", [keep], null, false)
	if driver:
		carried = keep & 0xFFFFFFFF
	_trace("carry_over", [keep])


## Port only: the carried goal song still plays. When it has ended, the
## next [method take_fade_in] answers [constant FADE_IN_TICKS] (once).
static func carrying() -> bool:
	if carried == NONE:
		return false
	if driver != null and driver.owed > 0:
		driver.settle()
	if driver and driver.s68k.sound_busy(carried):
		return true
	carried = NONE
	_fade_pending = true
	return false


## Port only: the fade-in for the scoreboard's first crowd or music after
## the carried song ([constant FADE_IN_TICKS] once, then 0).
static func take_fade_in() -> int:
	if quiet:
		return 0
	if not _fade_pending:
		return 0
	_fade_pending = false
	return FADE_IN_TICKS


## Port only: the scoreboard left - the carried song (if it still plays)
## stopped, no fade-in pending.
static func end_carry() -> void:
	if quiet:
		return
	if carried != NONE:
		stop(carried)
	carried = NONE
	_fade_pending = false


## Port only: sound [param handle] (played as sound [param id]) stops now
## and, still sounding, fades out in the mix over [param ticks] ticks
## (MwAudio.fade_out_sound) - a star's voice when the game setup is left.
static func fade_out(handle: int, ticks: int, id := -1) -> void:
	_send("fade_out", [handle, ticks, id])


## Port only: voice [param handle] (a [method play] of a sample) rises from
## silence over [param ticks] ticks (MwAudio.fade_in_voice).
static func fade_in(handle: int, ticks: int) -> void:
	_send("fade_in", [handle, ticks])


## `crowd_level` `$13E52`: the crowd noise for a crowd level 0-1000.
## Port only (plan 33): with [param fade_ticks] > 0, a crowd started now rises
## from silence over that many ticks - in the mix (MwAudio.fade_in_voice;
## plan 40, D7, owner: the driver as the original's, its own volume from $40
## at its own pace, the mix's ramp over it).
static func crowd_level(level: int, fade_ticks := 0) -> void:
	_send("crowd_level", [level] if fade_ticks <= 0 else [level, fade_ticks])


## Port only (plan 33): whether sound [param id]'s sample is sounding - on
## the driver's channel or, with ENHANCE AUDIO, on an extra voice (a sound
## the driver refused plays there; its handle says nothing). False without
## a driver.
static func sounding(id: int) -> bool:
	if driver != null and driver.owed > 0:
		driver.settle()
	return driver.sounding(id) if driver else false


## `$13EB6`: the crowd started again if it should be playing.
static func crowd_restart() -> void:
	_send("crowd_restart", [])


## `$13EEA`: the crowd fades out.
static func crowd_fade() -> void:
	_send("crowd_fade", [])


## `crowd_off` `$13EFC`: the crowd stops.
static func crowd_off() -> void:
	_send("crowd_off", [])


## The calls that answer (a handle): a model owing ticks settles before
## them; the others it makes among the owed ticks later (MwAudio.call_later).
const ANSWERS := {"play": true, "play_voice": true, "random_sound": true}


## A call that starts, stops or changes a sound: [param fn] ([param args])
## on the game's driver ([param none] without one), heard on [member heard]
## as the game's or as a prediction's ([member predicting]), traced (the
## game's own: [param traced]). Returns the driver's answer.
static func _send(fn: String, args: Array, none: Variant = null, traced := true) -> Variant:
	if quiet and not predicting:
		return none
	var r: Variant = none
	if not quiet and driver != null:
		if driver.owed > 0 and not ANSWERS.has(fn):
			driver.call_later(fn, args)            # (plan 42: made among the model's owed ticks later)
		else:
			if driver.owed > 0:
				driver.settle()                    # (plan 42: a model's ticks owed, run first)
			r = call_on(driver, fn, args)
	if heard != null and heard.audio != driver:
		if predicting:
			heard.predicted(predict_key, fn, args, predict_due)
		elif not quiet:
			heard.confirmed(fn, args, r, driver)
	if traced and not predicting:
		_trace(fn, args, r if fn == "play" or fn == "play_voice" else null)
	return r


## Call [param fn] ([param args]) of this API made on driver [param audio]
## (the game's or the heard one); its answer (a handle for a sound, else
## null).
static func call_on(audio: MwAudio, fn: String, args: Array) -> Variant:
	match fn:
		"play":
			return audio.play_sound(int(args[0]))
		"play_voice":
			return audio.s68k.sound_play_voice(int(args[0]), int(args[1]), int(args[2]))
		"stop":
			audio.s68k.sound_stop(int(args[0]))
		"positional":
			audio.s68k.positional(int(args[0]), bool(args[1]))
		"random_sound":
			return audio.random_sound(int(args[0]))
		"fm_effect":
			audio.fm_effect(str(args[0]))
		"fm_effect_stop":
			audio.fm_effect_stop()
		"music_title":
			audio.s68k.music_title()
		"music_game":
			audio.s68k.music_game()
		"music_fade_out":
			audio.s68k.music_fade_out(int(args[0]))
		"enter_match":
			audio.enter_match(int(args[0]))
		"carry_over":
			audio.carry_over(int(args[0]))
		"fade_out":
			audio.fade_out_sound(int(args[0]), int(args[1]), int(args[2]))
		"fade_in":
			if int(args[1]) > 0:
				audio.fade_in_voice(int(args[0]), int(args[1]))
		"crowd_level":
			var fade_ticks := int(args[1]) if args.size() > 1 else 0
			var starts := fade_ticks > 0 and not audio.s68k.crowd_sounding()
			audio.s68k.crowd_level(int(args[0]))
			var h := audio.s68k.r32(MwSound68k.CROWD_HANDLE)
			if starts and (h & 0x80000000) == 0:
				audio.fade_in_voice(h, fade_ticks)
		"crowd_restart":
			audio.s68k.crowd_restart()
		"crowd_fade":
			audio.s68k.crowd_fade()
		"crowd_off":
			audio.s68k.crowd_off()
		_:
			push_error("MwSound.call_on: no call %s" % fn)
	return null


static func _trace(what: String, args: Array, result: Variant = null) -> void:
	if trace.is_valid():
		trace.call(what, args, result)
