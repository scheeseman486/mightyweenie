extends "res://test/rom/rom_test_base.gd"
## The playoffs screen and its password screen, played with the pads:
## Continue Playoffs -> a password typed (as on the original: the fixture's
## symbols) -> the bracket -> Start -> the matchup, with the original's
## state and teams (compare/fixtures/playoffs.json); a new run; cancel;
## the champion and the eliminated.

var host: Node
var router: MwRouter
var _cases: Dictionary


func before_all() -> void:
	super.before_all()
	_cases = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/playoffs.json")))["cases"]


func after_each() -> void:
	if host:
		host.free()
		host = null
		await wait_process_frames(1)


func _start(session: MwSession) -> void:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	router = MwRouter.new(host, fader)
	router.session = session
	var po := (load(MwScreens.scene_path(11)) as PackedScene).instantiate() as MwScreen
	po.screen_id = 11
	router.adopt(po)
	_run(80)


func _run(ticks: int) -> void:
	for i in ticks:
		router.step()


## Presses [param verb] on pad [param p] in the current top screen's next pass.
func _press(verb: String, p := 1) -> void:
	var frame := MwInputFrame.make({MwVerbs.menu_action(p, verb): true}, {})
	router.current()._screen_pass(1, frame)
	_run(2)


func _type(symbols: Array) -> void:
	var cur := 0
	for t in symbols:
		var r0 := cur / 7
		var c0 := cur % 7
		while c0 != int(t) % 7:
			_press("ui_right")
			c0 = (c0 + 1) % 7
		while r0 != int(t) / 7:
			_press("ui_down")
			r0 = (r0 + 1) % 4
		cur = int(t)
		_press("ui_option_a")
	_press("ui_accept")


func test_continue_with_a_password_like_the_original() -> void:
	if not need_rom():
		return
	var case: Dictionary = _cases["typed_single"]
	var s := MwSession.new(1, 1)
	s.setup.play_mode = 3
	s.playoffs.start(s.setup, s.rng)
	_start(s)
	assert_true(router.current() is MwPasswordScreen, "Continue Playoffs asks for the password")
	_type(case["typed"])
	_run(80)
	assert_true(router.current() is MwPlayoffsScreen, "back on the bracket")
	assert_eq([s.setup.team_a, s.setup.team_b], case["teams"].map(func(x: Variant) -> int: return int(x)))
	assert_eq([s.playoffs.seed, s.playoffs.pair, s.playoffs.round], [0x3E7, 94, 2])
	_press("ui_accept")
	_run(40)
	assert_eq(router.current_id(), 3, "Start: the matchup")


func test_a_wrong_password_is_refused_and_c_cancels() -> void:
	if not need_rom():
		return
	var s := MwSession.new(1, 1)
	s.setup.play_mode = 3
	s.playoffs.start(s.setup, s.rng)
	_start(s)
	_type([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_true(router.current() is MwPasswordScreen, "refused: still asking")
	_press("ui_option_b")
	assert_eq((router.current() as MwPasswordScreen).buffer.size(), 12, "B takes one back")
	_press("ui_option_c")
	_run(40)
	assert_eq(router.current_id(), 1, "C: the main menu")


func test_a_new_run_and_its_redraw() -> void:
	if not need_rom():
		return
	var case: Dictionary = _cases["reroll"]
	var s := MwSession.new(1, 1)
	s.setup.play_mode = 1
	s.setup.team_a = 0
	s.setup.team_b = 5
	s.rng.state = 193114104                   # the original's main stream before Start (GPGX)
	s.playoffs.start(s.setup, s.rng)
	_start(s)
	assert_true(router.current() is MwPlayoffsScreen)
	_press("ui_option_a", 2)                  # any pad: a new draw from the main stream
	assert_eq(s.playoffs.seed, 0x764)
	var got := []
	for side in 2:
		got.append_array(Array(s.playoffs.sides[side]))
	assert_eq(got, case["bracket"].map(func(x: Variant) -> int: return int(x)))
	_press("ui_accept")
	_run(40)
	assert_eq(router.current_id(), 3)
	assert_eq(s.playoffs.flags & MwPlayoffs.NEW, 0, "the run has started")


func test_champion_and_eliminated_go_back_to_the_menu() -> void:
	if not need_rom():
		return
	var s := MwSession.new(1, 1)
	s.playoffs.flags = MwPlayoffs.CHAMPION
	_start(s)
	assert_eq((router.current() as MwPlayoffsScreen).phase, MwPlayoffsScreen.Phase.CHAMPION)
	_press("ui_accept")
	_run(40)
	assert_eq(router.current_id(), 1)
	host.free()
	host = null
	var e := MwSession.new(1, 1)
	e.playoffs.flags = MwPlayoffs.ELIMINATED
	_start(e)
	assert_eq(router.current_id(), 1)
