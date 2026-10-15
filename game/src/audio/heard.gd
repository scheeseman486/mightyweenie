class_name MwHeard
extends RefCounted
## Plan 41 (online feel), work item 3 - what an online client hears, apart
## from what its game asks (docs/net.md "Sound: asked and heard").
##
## The game waits on its sound driver (a voice's handle still playing, the
## goal song carried over the scoreboard, the crowd's level, the driver's
## work in the pass pacer), so on every machine the driver's answers must be
## the host's: on a client the game's calls and questions go to the
## driver's model alone ([member MwSound.driver], [member MwRouter.model]),
## fed only the confirmed game's calls. What is heard is [member audio] -
## the driver with the chips - fed the same calls (this): its handles are
## its own ([method heard_handle] maps the model's), and a prediction's
## sounds (a client's own menu moves, the run-ahead's shots and hits) play
## on it at once ([method predicted]); when the confirmed game makes the
## same call later, it isn't played again ([method confirmed]).
##
## A prediction runs again picture after picture (the menus' each frame, the
## run-ahead's after a rollback): each of its calls has a key - the press it
## ran ("echo:..."), the pass it ran in ("ahead:...") - and a call already
## heard under its key is not played again. Each also has the router tick
## the game is expected to make it at (its due: the pass's end; the tick the
## host merges the press, MwNetMatch.ahead_tick): the game's own call of
## the same sound within [member slack] ticks of it is the predicted one. A
## predicted sound the game never makes (another player did something
## else) was heard anyway; one the game makes that was never predicted is
## heard when it comes. Only sound effects
## are predicted (sampled sounds - [method MwSound.play] of a PCM id, a
## voice, a rink object's sound): music, the crowd, stops and fades are the
## confirmed game's alone.
##
## What is heard keeps its own clock (owner, 2026-10-13: music dropouts
## after scoring): [member audio] is pumped by the wall clock on a thread of
## its own ([method MwAudio.start_pump]), never held with the game's ticks
## (a late stream, a screen's entry); every call here takes its lock.

## The first PCM sound id (`$12`; below: sequences - music, jingles, the
## goal song - never predicted).
const FIRST_PCM := 0x12

## The switch: an online client's game asks a model of its own and hears
## the audible driver apart (MwRouter.split_audio); off, one driver as
## before, predictions unheard. `--no-sound-split` on the command line.
static var split_online := true

## The audible driver.
var audio: MwAudio = null
## How far from its due tick the game's own call of a predicted sound may
## come (router ticks: the round trip's estimate off by jitter).
var slack := 8
## The router whose ticks the due ticks are (null: [member audio]'s own
## count, tests).
var router: MwRouter = null
## Calls heard as the game made them, predicted and heard, the game's
## skipped (heard before as predicted), predictions that never came.
var stats := {"heard": 0, "predicted": 0, "skipped": 0, "expired": 0}
## The last [constant LOG_MAX] calls (tests, debugging): [tick, "game" /
## "predicted" / "skipped", the call, its arguments, the heard handle].
@warning_ignore("shadowed_global_identifier")   # a frozen name (docs/style.md N9): read by name elsewhere
var log: Array = []
const LOG_MAX := 128
## How long a prediction's key is remembered (ticks): longer than any
## prediction runs again.
const KEY_TICKS := 600
var _map := {}           # the model's handle -> the heard one
var _waiting: Array = [] # predicted, not yet made by the game: [match key, heard handle, due tick]
var _keys := {}          # prediction key + call + occurrence -> tick heard
var _counts := {}        # this prediction run's: key + call -> occurrences


static func _static_init() -> void:
	if "--no-sound-split" in OS.get_cmdline_user_args():
		split_online = false


func _init(audio_: MwAudio = null, router_: MwRouter = null) -> void:
	audio = audio_
	router = router_


## The router's tick ([member audio]'s count without one).
func now() -> int:
	if router != null:
		return router.tick
	return audio.tick_count() if audio != null else 0


## A prediction run starts ([member MwSound.predicting]): its calls counted
## afresh, the stale bookkeeping let go.
func begin_run() -> void:
	_counts.clear()
	_expire()


## Whether the call [param fn] ([param args]) is one a prediction plays.
static func predictable(fn: String, args: Array) -> bool:
	match fn:
		"play":
			return (int(args[0]) & 0xFFFF) >= FIRST_PCM
		"play_voice", "positional":
			return true
	return false


## The prediction's call [param fn] ([param args]) under key [param key],
## the game expected to make it at tick [param due] (-1: now): heard now
## unless heard before under the same key.
func predicted(key: String, fn: String, args: Array, due := -1) -> void:
	if audio == null or not predictable(fn, args):
		return
	var base := "%s|%s%s" % [key, fn, str(args)]
	var n := int(_counts.get(base, 0))
	_counts[base] = n + 1
	var full := "%s#%d" % [base, n]
	if _keys.has(full):
		return
	var t := now()
	_keys[full] = t
	audio.lock()                     # (pumped on a thread of its own: MwAudio.start_pump)
	var h: Variant = MwSound.call_on(audio, fn, args)
	audio.unlock()
	_waiting.append([_match_key(fn, args), h, due if due >= 0 else t])
	stats["predicted"] += 1
	_log("predicted", fn, args, h)


## The game's call [param fn] ([param args]; [param result] the model's
## answer, [param game] the model): heard, unless a prediction played it -
## then its heard handle is the model's.
func confirmed(fn: String, args: Array, result: Variant, game: MwAudio) -> void:
	if audio == null:
		return
	var heard_h: Variant = null
	var found := false
	if predictable(fn, args):
		var k := _match_key(fn, args)
		var t := now()
		var best := -1
		for i in _waiting.size():
			var w: Array = _waiting[i]
			if w[0] == k and absi(int(w[2]) - t) <= slack \
					and (best < 0 or absi(int(w[2]) - t) < absi(int(_waiting[best][2]) - t)):
				best = i
		if best >= 0:
			heard_h = _waiting[best][1]
			_waiting.remove_at(best)
			found = true
			stats["skipped"] += 1
			_log("skipped", fn, args, heard_h)
	if not found:
		audio.lock()
		heard_h = _hear(fn, args, game)
		audio.unlock()
		stats["heard"] += 1
		_log("game", fn, args, heard_h)
	if fn in ["play", "play_voice", "random_sound"] and result is int and heard_h is int:
		_map[int(result) & 0xFFFFFFFF] = int(heard_h) & 0xFFFFFFFF
		if _map.size() > 512:
			_map.erase(_map.keys()[0])


## The heard driver's handle for the model's [param h] (the same where the
## two never parted: a match's start, a resync).
func heard_handle(h: int) -> int:
	return int(_map.get(h & 0xFFFFFFFF, h & 0xFFFFFFFF))


## After the model was taken from a snapshot and the heard driver with it:
## their handles one again, nothing waiting.
func synced() -> void:
	_map.clear()
	_waiting.clear()
	_keys.clear()


## The game's call on the heard driver: handles mapped; the organ pool's
## tune the model picked (the pick is the game's: its stream, its length).
func _hear(fn: String, args: Array, game: MwAudio) -> Variant:
	var a := args
	match fn:
		"stop", "carry_over":
			a = [heard_handle(int(args[0]))]
		"fade_out":
			a = [heard_handle(int(args[0])), args[1], args[2]]
		"fade_in":
			a = [heard_handle(int(args[0])), args[1]]
		"play", "random_sound":
			if game != null and MwAudio.organ_pool and (fn == "random_sound"
					or (int(args[0]) & 0xFFFF) in MwOrganPool.ORIGINALS):
				return audio.play_pool_tune(game.organ_last)
	return MwSound.call_on(audio, fn, a)


## What a predicted call and the game's are matched on: the call and its
## sound (a rink object's sound whether on screen or not).
static func _match_key(fn: String, args: Array) -> String:
	if fn == "positional":
		return "%s %d" % [fn, int(args[0])]
	return "%s %s" % [fn, str(args)]


func _log(why: String, fn: String, args: Array, h: Variant) -> void:
	log.append([now(), why, fn, args, h])
	if log.size() > LOG_MAX:
		log = log.slice(log.size() - LOG_MAX)


func _expire() -> void:
	var t := now()
	var kept: Array = []
	for w: Array in _waiting:
		if int(w[2]) >= t - slack:
			kept.append(w)
		else:
			stats["expired"] += 1
	_waiting = kept
	if _keys.size() > 64:
		for k: String in _keys.keys():
			if int(_keys[k]) < t - KEY_TICKS:
				_keys.erase(k)
