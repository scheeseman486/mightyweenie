extends "res://test/rom/rom_test_base.gd"
## Owner, 2026-10-13: the music dropped out after goals - an online client
## heard nothing while its game held a tick (the host's stream late through a
## goal's screen changes) or its main thread was busy (a screen's entry),
## past the sound card's 70 ms (MwAudio.BUFFER_TARGET). What is heard now
## keeps its own clock (MwAudio.start_pump): the ticks the wall clock says
## are due, on a thread of its own (MwAudioPump); its router no longer steps
## it; the game's calls reach it under its lock (MwHeard).
## Short names: a the MwAudio under test, r the MwRouter under test.

const MOVE := MwSoundIds.MOVE
const GOAL_SONG := 0x09

## A driver the test treats as heard (MwAudio.audible: a Godot player and
## chips, which a headless test has not).
class Heard extends MwAudio:
	func audible() -> bool:
		return true

var _made: Array[MwAudio] = []
var _was := []
var _host: Node


func before_each() -> void:
	_was = [MwSound.driver, MwSound.heard, MwSound.quiet, MwSound.predicting, MwAudio.organ_pool,
			MwAudioPump.threaded]
	MwAudio.organ_pool = false


func after_each() -> void:
	for a in _made:
		a.stop_pump()
	MwSound.driver = _was[0]
	MwSound.heard = _was[1]
	MwSound.quiet = _was[2]
	MwSound.predicting = _was[3]
	MwAudio.organ_pool = _was[4]
	MwAudioPump.threaded = _was[5]
	for a in _made:
		if is_instance_valid(a) and not a.is_inside_tree():
			a.free()
	_made.clear()
	if _host != null:
		_host.free()
		_host = null


func _driver(heard := false) -> MwAudio:
	var a: MwAudio = Heard.new() if heard else MwAudio.new()
	a.setup(rom, false, false)
	_made.append(a)
	return a


## A router on a host under the test, [param audio] its driver.
func _router(audio: MwAudio) -> MwRouter:
	_host = Node.new()
	add_child(_host)
	var fader := MwScreenFader.new()
	_host.add_child(fader)
	var r := MwRouter.new(_host, fader)
	r.audio = audio
	return r


func test_the_pump_runs_the_ticks_the_clock_says() -> void:
	if not need_rom():
		return
	var a := _driver()
	a.start_pump(false)
	var pump := a.pump_clock()
	var t0 := pump.started_at()
	assert_true(a.pumping())
	assert_false(pump.on_thread(), "on the main thread (--no-audio-thread)")
	assert_eq(pump.pump(t0 + 100000), 6, "100 ms: six ticks")
	assert_eq(a.tick_count(), 6)
	assert_eq(pump.pump(t0 + 100000), 0, "none more due")
	assert_eq(pump.pump(t0 + 116667), 1, "the next at 116.7 ms")
	assert_eq(pump.pump(t0 + 2000000), MwAudioPump.MAX_TICKS, "a long wait: the most a look runs")
	assert_eq(pump.pump(t0 + 2016667), 1, "the clock goes on from there, the rest let go")
	assert_eq(a.tick_count(), 7 + MwAudioPump.MAX_TICKS + 1)
	a.stop_pump()
	assert_false(a.pumping())


func test_a_pumped_driver_is_not_stepped_by_its_router() -> void:
	if not need_rom():
		return
	var a := _driver()
	var r := _router(a)
	r.step()
	assert_eq(a.tick_count(), 1, "stepped by the router's ticks")
	a.start_pump(false)
	var before := a.tick_count()
	for i in 10:
		r.step()
	assert_eq(a.tick_count(), before, "its own clock: the router's ticks don't step it")
	a.stop_pump()
	r.step()
	assert_eq(a.tick_count(), before + 1, "stepped by the ticks again")


func test_a_split_client_hears_through_a_busy_main_thread() -> void:
	if not need_rom():
		return
	MwAudioPump.threaded = true
	var heard := _driver(true)
	var r := _router(heard)
	r.split_audio(true)
	assert_not_null(r.model, "split: the game's own driver")
	assert_true(heard.pumping(), "what is heard runs on its own clock")
	assert_eq(MwSound.heard.audio, heard)
	MwSound.play(GOAL_SONG)                       # the confirmed game's call, heard under the lock
	var t0 := heard.tick_count()
	OS.delay_msec(250)                            # the main thread held (a screen's entry; no router step)
	var ran := heard.tick_count() - t0
	assert_between(ran, 10, 18, "~15 ticks heard while the main thread was held: %d" % ran)
	assert_eq(r.model.tick_count(), 0, "the game's driver waits for its ticks")
	r.split_audio(false)
	assert_false(heard.pumping(), "one driver again, stepped by the ticks")
	var t1 := heard.tick_count()
	OS.delay_msec(50)
	assert_eq(heard.tick_count(), t1, "the thread is gone")


func test_the_games_calls_meet_the_pump_under_its_lock() -> void:
	if not need_rom():
		return
	MwAudioPump.threaded = true
	var heard := _driver(true)
	var r := _router(heard)
	r.split_audio(true)
	var hh: MwHeard = MwSound.heard
	var start := Time.get_ticks_msec()
	var calls := 0
	while Time.get_ticks_msec() - start < 300:   # the game's calls while the pump ticks
		var h: int = MwSound.play(MOVE)
		MwSound.stop(h)
		calls += 2
		if calls % 50 == 0:
			r.step()                                  # (the game's own ticks: the model)
	r.split_audio(false)
	assert_eq(int(hh.stats["heard"]), calls, "every call heard")
	assert_gt(heard.tick_count(), 10, "the pump ran meanwhile")
	assert_gt(calls, 100)


func test_with_the_chips_and_a_player_it_renders_on_its_thread() -> void:
	if not need_rom() or not ClassDB.class_exists("MwChips"):
		pending("MwChips extension not built")
		return
	MwAudioPump.threaded = true
	var heard := MwAudio.new()
	heard.name = "HeardAudio"
	add_child(heard)                                   # (as the router service's: its player plays)
	heard.setup(rom)
	_made.append(heard)
	assert_true(heard.audible(), "a player and chips")
	var r := _router(heard)
	r.split_audio(true)
	assert_true(heard.pumping())
	MwSound.play(GOAL_SONG)
	var t0 := heard.tick_count()
	OS.delay_msec(200)
	assert_between(heard.tick_count() - t0, 8, 15, "rendered while the main thread was held")
	r.split_audio(false)
	assert_false(heard.pumping())
	r.step()
	heard.queue_free()
