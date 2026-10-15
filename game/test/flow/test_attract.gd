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
	var session := MwSession.new(12345, 1)
	var boot := session.setup.copy()
	assert_true(boot.equals(MwMatchSetup.from_rom(rom, MwMatchSetup.BOOT_DEFAULTS)))
	assert_eq([boot.team_a, boot.team_b, boot.period_minutes, boot.stadium], [22, 5, 5, 22])
	session.begin_attract()
	assert_true(session.attract)
	assert_eq(session.setup.pads, MwMatchSetup.PADS_DEMO)
	assert_eq(session.setup.period_minutes, 3)
	assert_ne(session.setup.team_a, session.setup.team_b)
	assert_eq(session.setup.stadium, session.setup.team_a)
	assert_between(session.setup.death_index, 0, 4)
	# the same picks as the original's code on the same random stream
	var rng := MlhRng.new(12345)
	var a := rng.range_value(0, 22)
	var b := rng.range_value(0, 22)
	while b == a:
		b = rng.range_value(0, 22)
	assert_eq([session.setup.team_a, session.setup.team_b, session.setup.death_index], [a, b, rng.range_value(0, 4)])
	session.end_attract()
	assert_false(session.attract)
	assert_true(session.setup.equals(boot), "restored")


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


## Plan 35: the idle timeout is a match rule - off online, where the menus
## wait for their players.
func test_no_idle_demo_with_the_timeout_off() -> void:
	var was := MwAttract.idle_attract
	MwAttract.idle_attract = false
	var r := _router("@screen 1 +5000 END")
	var router: MwRouter = r[0]
	for i in MwAttract.IDLE_TICKS * 2:
		router.step()
	MwAttract.idle_attract = was
	assert_eq(router.history, [1], "still on the menu")
	assert_false(router.session.attract)


## The attract demo is the original's CPU v CPU, not a spectated match
## (MwSession.spectated: the port's exhibition): any press - Start too -
## ends it as before, never pausing it into the spectators' menu.
func test_the_demo_is_no_spectated_match() -> void:
	if not need_rom():
		return
	var r := _router("@screen 4 +300 P3 START\n@screen 1 #2 +10 END")
	var router: MwRouter = r[0]
	var player: MwScriptPlayer = r[1]
	var spectated := false
	var paused := false
	var n := 0
	while not player.ended() and n < 3000:
		router.step()
		n += 1
		var rk := router.current() as MwRink
		if rk != null and rk.state != null:
			spectated = spectated or rk.state.spectated or router.session.spectated()
			paused = paused or (rk.phases != null and rk.phases.paused)
	assert_true(player.ended())
	assert_eq(router.history, [1, 3, 4, 1], "Start ended the demo")
	assert_false(spectated, "the demo is not a spectated match")
	assert_false(paused, "nothing paused it")
	assert_false(router.session.attract)
