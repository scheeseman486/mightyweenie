extends "res://test/rom/rom_test_base.gd"
## The matchup's timing and exits against the original (GPGX: screen 3 ->
## 4 in 339 ticks without input), the attract demo's pass-through, and the
## stadium of playoff games.

var host: Node


func after_each() -> void:
	if host:
		host.free()
		host = null
		await wait_process_frames(1)


## Runs the matchup from its entry; returns [ticks until screen 4, router].
func _run(session: MwSession, press_at := -1) -> Array:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = session
	var entered := [-1]
	router.screen_entered.connect(func(id: int, _v: int, tick: int, _p: int) -> void:
		if id == 4:
			entered[0] = tick)
	var mu := (load(MwScreens.scene_path(3)) as PackedScene).instantiate() as MwScreen
	mu.screen_id = 3
	router.adopt(mu)
	var start := router.tick
	var n := 0
	while entered[0] < 0 and n < 1000:
		if n == press_at:
			mu._screen_pass(0, MwInputFrame.make({"p2_ui_option_c": true}, {}))
		router.step()
		n += 1
	return [entered[0] - start, router]


func test_shows_300_ticks_then_the_rink() -> void:
	if not need_rom():
		return
	var r := _run(MwSession.new(1, 1))
	assert_eq(r[0], 339, "screen 3 -> 4 like the original (7 loading + 300 + 32 fade)")


func test_any_pad_skips_it() -> void:
	if not need_rom():
		return
	var r := _run(MwSession.new(1, 1), 100)
	assert_lt(int(r[0]), 140, "C on pad 2 leaves at once")


func test_attract_demo_goes_straight_to_the_rink() -> void:
	if not need_rom():
		return
	var s := MwSession.new(1, 1)
	s.attract = true
	var r := _run(s)
	assert_lt(int(r[0]), 3, "no display, no fade")
	assert_eq(s.setup.pads, MwMatchSetup.PADS_DEMO, "demo setup loaded")


func test_playoff_games_alternate_the_stadium() -> void:
	if not need_rom():
		return
	var s := MwSession.new(1, 1)
	s.setup.play_mode = 1
	s.setup.team_a = 3
	s.setup.team_b = 7
	s.playoffs.series = 0
	_run(s, 10)
	assert_eq(s.setup.stadium, 7, "game 1 at team B's")
	host.free()
	host = null
	s.playoffs.series = 1
	_run(s, 10)
	assert_eq(s.setup.stadium, 3, "series bit 0: team A's")
