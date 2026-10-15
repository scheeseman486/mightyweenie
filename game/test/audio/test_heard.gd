extends "res://test/rom/rom_test_base.gd"
## Plan 41 work item 3 (MwHeard, MwSound.heard / predicting): an online
## client's game calls and asks a driver's model of its own; what is heard
## is another driver, fed the game's calls with their handles mapped, and a
## prediction's sound effects at once - once a key; the game's own call of
## a predicted sound isn't heard again; a prediction never made expires.
## Short names: h the MwHeard under test.

const MOVE := MwSoundIds.MOVE          # a PCM sound (predicted)
const THUD := MwSoundIds.THUD
const GOAL_SONG := 0x09                # a sequence (never predicted)

var _made: Array[MwAudio] = []
var _was := []


func before_each() -> void:
	_was = [MwSound.driver, MwSound.heard, MwSound.quiet, MwSound.predicting, MwSound.predict_key,
			MwAudio.organ_pool]
	MwAudio.organ_pool = false


func after_each() -> void:
	MwSound.driver = _was[0]
	MwSound.heard = _was[1]
	MwSound.quiet = _was[2]
	MwSound.predicting = _was[3]
	MwSound.predict_key = _was[4]
	MwAudio.organ_pool = _was[5]
	for audio in _made:
		audio.free()
	_made.clear()


func _driver() -> MwAudio:
	var audio := MwAudio.new()
	audio.setup(rom, false, false)
	_made.append(audio)
	return audio


## The game's driver and the heard one, split.
func _split() -> MwHeard:
	MwSound.driver = _driver()
	MwSound.heard = MwHeard.new(_driver())
	return MwSound.heard


## [param what] as a prediction's calls under [param key], due at tick
## [param due] (-1: now) - as MwLocalEcho.run.
static func _predict(key: String, what: Callable, due := -1) -> void:
	MwSound.quiet = true
	MwSound.predicting = true
	MwSound.predict_key = key
	MwSound.predict_due = due
	MwSound.heard.begin_run()
	what.call()
	MwSound.quiet = false
	MwSound.predicting = false
	MwSound.predict_due = -1


static func _ticks(n: int) -> void:
	for i in n:
		MwSound.driver.tick()
		MwSound.heard.audio.tick()


func _count(h: MwHeard, why: String, fn: String) -> int:
	return h.log.filter(func(e: Array) -> bool: return e[1] == why and e[2] == fn).size()


func test_a_prediction_is_heard_once_and_the_games_own_call_not_again() -> void:
	var h := _split()
	var game: MwAudio = MwSound.driver
	var alone := _driver()                       # the game's driver as it would be without predictions
	for i in 3:                                  # the same press predicted three frames running
		_predict("echo:2:ui_right:7", func() -> void: MwSound.play(MOVE), 14)
		_ticks(1)
		alone.tick()
	assert_eq(int(h.stats["predicted"]), 1, "heard once")
	assert_true(MwSound.sounding(MOVE) == false, "the game's driver asked: not sounding there")
	assert_true(h.audio.sounding(MOVE), "the heard driver plays it")
	assert_true(game.s68k.mem == alone.s68k.mem, "the game's driver had none of it")
	var predicted: int = h.log[0][4]
	_ticks(1)
	MwSound.play(MOVE)                           # someone else's move, long before the press is due
	assert_eq(int(h.stats["skipped"]), 0, "heard: not the prediction's")
	_ticks(10)
	var g := MwSound.play(MOVE)                  # the game runs the press (tick 14, as due)
	assert_ne(g, MwSound.NONE, "the game's driver plays it")
	assert_eq(int(h.stats["skipped"]), 1, "not heard again")
	assert_eq(int(h.stats["heard"]), 1, "(the other one)")
	assert_eq(h.heard_handle(g), predicted, "the game's handle is the predicted sound's")
	MwSound.stop(g)
	_ticks(2)
	assert_false(h.audio.s68k.sound_busy(predicted), "the game's stop reaches it")


func test_the_games_calls_are_heard_with_their_handles() -> void:
	var h := _split()
	var a := MwSound.play(THUD)
	_predict("ahead:100", func() -> void: MwSound.play(MOVE))   # the heard driver's channels diverge
	_ticks(1)
	var b := MwSound.play(GOAL_SONG)
	_ticks(2)
	assert_eq(int(h.stats["heard"]), 2, "the game's calls heard")
	assert_true(h.audio.s68k.sound_busy(h.heard_handle(b)), "its goal song plays on the heard driver")
	MwSound.stop(b)
	_ticks(2)
	assert_false(MwSound.busy(b), "stopped in the game")
	assert_false(h.audio.s68k.sound_busy(h.heard_handle(b)), "and heard stopped")
	assert_true(a != MwSound.NONE)


func test_only_sound_effects_are_predicted() -> void:
	var h := _split()
	_predict("ahead:10", func() -> void:
		MwSound.play(GOAL_SONG)
		MwSound.music_title()
		MwSound.crowd_level(500)
		MwSound.positional(THUD, true)
		MwSound.play(MOVE))
	assert_eq(int(h.stats["predicted"]), 2, "the rink object's sound and the PCM sound only")
	assert_eq(_count(h, "predicted", "positional"), 1)
	assert_eq(_count(h, "predicted", "play"), 1)


func test_a_prediction_never_made_expires() -> void:
	var h := _split()
	h.slack = 4
	_predict("ahead:10", func() -> void: MwSound.play(MOVE))
	_ticks(20)
	MwSound.play(MOVE)
	assert_eq(int(h.stats["skipped"]), 0, "too late to be the prediction's")
	assert_eq(int(h.stats["heard"]), 1, "heard as the game's")
	_predict("ahead:40", func() -> void: pass)
	assert_eq(int(h.stats["expired"]), 1, "the stale prediction let go")


func test_without_a_split_one_driver_as_before() -> void:
	MwSound.driver = _driver()
	MwSound.heard = null
	var calls := []
	MwSound.trace = func(fn: String, args: Array, r: Variant) -> void: calls.append([fn, args, r])
	var g := MwSound.play(MOVE)
	MwSound.stop(g)
	_predict_without_heard()
	MwSound.trace = Callable()
	assert_eq(calls, [["play", [MOVE], g], ["stop", [g], null]], "the calls traced as before")


func _predict_without_heard() -> void:
	MwSound.quiet = true
	MwSound.predicting = true
	MwSound.play(MOVE)                           # no heard driver: nothing anywhere, untraced
	MwSound.quiet = false
	MwSound.predicting = false
