extends "res://test/rom/rom_test_base.gd"
## Plan 12's wiring of the game's sound calls ([MwSound], traced through
## [member MwSound.trace]; no driver): the rink's positional sounds and
## `$5C3C`, live play only ([member MwRinkSim.live], a screen sim without
## comparison hooks), a screen's calls held after its fade-out until the
## scene's fade is over, the driver's handles as signed longs, the rink
## exit's `$13C04` with its screen and the rink pass's crowd noise
## (`$B052`). Whole runs: test/screens/live_sound.gd.

var calls: Array = []


func before_each() -> void:
	calls = []
	MwSound.trace = func(what: String, args: Array, _result: Variant) -> void: calls.append([what, args])


func after_each() -> void:
	MwSound.trace = Callable()


func _names() -> Array:
	return calls.map(func(c: Array) -> String: return c[0])


## `$5C3C`: the point (x + $100, y + $1CD - z) minus the camera's whole
## pixels within 320 x 240.
func test_on_screen() -> void:
	var s := MwRinkState.new()
	var a := MwRinkState.Actor.new()
	a.motion.init(-0x100, -0x1CD)
	assert_true(MwRinkSim.on_screen(s, a), "the camera's corner")
	a.motion.init(-0x100 + 0x13F, -0x1CD + 0xEF)
	assert_true(MwRinkSim.on_screen(s, a), "the opposite corner")
	a.motion.init(-0x100 + 0x140, -0x1CD)
	assert_false(MwRinkSim.on_screen(s, a), "x 320")
	a.motion.init(-0x100, -0x1CD + 0xF0)
	assert_false(MwRinkSim.on_screen(s, a), "y 240")
	a.motion.init(-0x100, -0x1CD, 1)
	assert_false(MwRinkSim.on_screen(s, a), "1 px up: above the screen")
	s.camera.x = 0x10 << 8
	a.motion.init(-0x100 + 0x10, -0x1CD)
	assert_true(MwRinkSim.on_screen(s, a), "the camera moved")
	a.motion.init(-0x100, -0x1CD)
	assert_false(MwRinkSim.on_screen(s, a))


## The segment's sounds: always the events; the driver's API only live.
func test_rink_sounds_live_only() -> void:
	var s := MwRinkState.new()
	var sim := MwRinkSim.new(rom, s)
	var a := MwRinkState.Actor.new()
	a.motion.init(-0x100, -0x1CD)
	sim.positional(0x27, a)
	sim.sound(0x1A, "music")
	assert_eq(sim.events, [["sound", 0x27], ["music", 0x1A]])
	assert_eq(calls, [], "not live: no call")
	sim.live = true
	sim.positional(0x27, a)
	a.motion.init(0x200, 0)
	sim.positional(0x23, a)
	sim.sound(2)
	assert_eq(calls, [["positional", [0x27, true]], ["positional", [0x23, false]], ["play", [2]]])


## Without hooks a screen calls the driver; after its fade-out started the
## calls wait for the scene's fade ([method MwScreenSim.fade_over]).
func test_screen_calls_wait_for_the_fade() -> void:
	var sim := MwScreenSim.new(rom)
	sim.crowd_level(50)
	sim.fade_out(32)
	sim.crowd_off()
	sim.voice_stop(5)
	sim.sound_call(func() -> void: MwSound.enter_match(0xFFFF))
	assert_eq(_names(), ["crowd_level"])
	assert_eq(sim.events, [["crowd", 50], ["fade_out", 32], ["crowd_off"], ["voice_stop", 5]])
	sim.fade_over()
	assert_eq(_names(), ["crowd_level", "crowd_off", "stop", "enter_match"])
	sim.crowd_off()
	assert_eq(_names().size(), 5, "after the fade: at once again")


## With comparison hooks nothing reaches the driver and the handles are
## the sim's own, as before.
func test_screen_calls_not_under_hooks() -> void:
	var sim := MwScreenSim.new(rom)
	sim.hooks = RefCounted.new()
	sim.crowd_level(50)
	sim.fade_music(32)
	sim.fade_out(32)
	sim.voice_stop(1)
	sim.fade_over()
	var h := sim.sound(0x25)
	assert_eq(calls, [])
	assert_eq(h, 0x40000001)
	assert_eq(sim.events.back(), ["sound", 0x25, h])


func test_handle_of() -> void:
	assert_eq(MwScreenSim.handle_of(0xFFFFFFFF), -1, "none: negative, as `bmi` sees it")
	assert_eq(MwScreenSim.handle_of(0x80000002), -0x7FFFFFFE, "a sequence")
	assert_eq(MwScreenSim.handle_of(5), 5)


## `rink_exit` (`$FBB4`): `$13C04` with the screen in d0; the draw pass's
## crowd noise capped at 1000, none while a coach speaks (`$FFC644`).
func test_rink_exit_and_crowd() -> void:
	if not need_rom():
		return
	var s := MwRinkState.new()
	var sim := MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 0, 0, 5, 0, false, 2)
	var up := MwRinkUpdate.new(sim)
	var ph := MwRinkPhases.new(up)
	up.crowd_sound()
	assert_eq(calls, [], "not live")
	sim.live = true
	s.crowd = 1200
	up.crowd_sound()
	s.crowd_quiet = 1
	up.crowd_sound()
	s.crowd_quiet = 0
	assert_eq(ph.exit(12), 12)
	assert_eq(calls, [["crowd_level", [1000]], ["enter_match", [12]]])
	assert_has(sim.events, ["sounds_off"])
