extends "res://test/rom/rom_test_base.gd"
## The attract loop (docs/re/title.md, Attract demo): main menu idle ->
## matchup (demo setup) -> rink demo -> any input -> main menu, setup
## restored.

var host: Node


func after_each() -> void:
	if host:
		host.free()
		host = null


func _router(script_text: String) -> Array:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(0x61F2415D, 0x1234567)
	var script := MwInputScript.parse(script_text, "attract")
	assert_eq(script.error, "")
	var player := MwScriptPlayer.new(script)
	var source := MwScriptedInput.new(player)
	source.attach(router)
	router.input = source
	var menu := (load(MwScreens.scene_path(1)) as PackedScene).instantiate() as MwScreen
	menu.screen_id = 1
	router.adopt(menu)
	return [router, player]


func test_session_attract_setup() -> void:
	if not need_rom():
		return
	var s := MwSession.new(12345, 1)
	var boot := s.setup.copy()
	assert_true(boot.equals(MwMatchSetup.from_rom(rom, MwMatchSetup.BOOT_DEFAULTS)))
	assert_eq([boot.team_a, boot.team_b, boot.period_minutes, boot.stadium], [22, 5, 5, 22])
	s.begin_attract()
	assert_true(s.attract)
	assert_eq(s.setup.pads, MwMatchSetup.PADS_DEMO)
	assert_eq(s.setup.period_minutes, 3)
	assert_ne(s.setup.team_a, s.setup.team_b)
	assert_eq(s.setup.stadium, s.setup.team_a)
	assert_between(s.setup.death_index, 0, 4)
	# the same picks as the original's code on the same random stream
	var r := MlhRng.new(12345)
	var a := r.range_value(0, 22)
	var b := r.range_value(0, 22)
	while b == a:
		b = r.range_value(0, 22)
	assert_eq([s.setup.team_a, s.setup.team_b, s.setup.death_index], [a, b, r.range_value(0, 4)])
	s.end_attract()
	assert_false(s.attract)
	assert_true(s.setup.equals(boot), "restored")


func test_idle_menu_runs_the_demo_and_input_ends_it() -> void:
	var r := _router("@screen 4 +300 P2 A\n@screen 1 #2 +10 END")
	var router: MwRouter = r[0]
	var player: MwScriptPlayer = r[1]
	var entered := {}
	router.screen_entered.connect(func(id: int, _v: int, tick: int, _p: int) -> void:
		if not entered.has(id):
			entered[id] = tick)
	var n := 0
	while not player.ended() and n < 3000:
		router.step()
		n += 1
	assert_true(player.ended())
	assert_eq(router.history, [1, 3, 4, 1])
	# 1800 idle ticks, then the menu's fade-out
	assert_eq(int(entered[3]), MwAttract.IDLE_TICKS + MwScreenFader.DEFAULT_TICKS)
	assert_lt(int(entered[4]) - int(entered[3]), 3, "the matchup passes straight through")
	assert_false(router.session.attract)
	assert_eq(router.session.setup.pads, 0, "setup restored")


func test_a_press_keeps_the_menu_awake() -> void:
	var r := _router("@screen 1 +1700 P1 DOWN\n@screen 1 +5000 END")
	var router: MwRouter = r[0]
	var player: MwScriptPlayer = r[1]
	var n := 0
	while not player.ended() and n < 4000 and router.history.size() == 1:
		router.step()
		n += 1
	# idle restarts at 1700: the demo starts 1800 ticks after that, not at 1800
	assert_eq(router.history.size(), 2)
	assert_eq(router.history[1], 3)
	assert_almost_eq(router.tick, 1700 + MwAttract.IDLE_TICKS + MwScreenFader.DEFAULT_TICKS, 2)


func test_demo_ends_by_itself() -> void:
	var r := _router("@screen 1 #2 +10 END")
	var router: MwRouter = r[0]
	var player: MwScriptPlayer = r[1]
	var n := 0
	while not player.ended() and n < 8000:
		router.step()
		n += 1
	assert_eq(router.history, [1, 3, 4, 1])
	assert_false(router.session.attract)
