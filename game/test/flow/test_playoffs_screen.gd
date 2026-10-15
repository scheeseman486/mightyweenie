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
		_press("ui_pick_letter")
	_press("ui_password_done")


func test_continue_with_a_password_like_the_original() -> void:
	if not need_rom():
		return
	var case: Dictionary = _cases["typed_single"]
	var session := MwSession.new(1, 1)
	session.setup.play_mode = 3
	session.playoffs.start(session.setup, session.rng)
	_start(session)
	assert_true(router.current() is MwPasswordScreen, "Continue Playoffs asks for the password")
	_type(case["typed"])
	_run(80)
	assert_true(router.current() is MwPlayoffsScreen, "back on the bracket")
	assert_eq([session.setup.team_a, session.setup.team_b], case["teams"].map(func(x: Variant) -> int: return int(x)))
	assert_eq([session.playoffs.seed, session.playoffs.pair, session.playoffs.round], [0x3E7, 94, 2])
	_press("ui_accept")
	_run(40)
	assert_eq(router.current_id(), 3, "Start: the matchup")


func test_a_wrong_password_is_refused_and_c_cancels() -> void:
	if not need_rom():
		return
	var session := MwSession.new(1, 1)
	session.setup.play_mode = 3
	session.playoffs.start(session.setup, session.rng)
	_start(session)
	_type([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_true(router.current() is MwPasswordScreen, "refused: still asking")
	_press("ui_erase_letter")
	assert_eq((router.current() as MwPasswordScreen).buffer.size(), 12, "B (erase) takes one back")
	_press("ui_cancel")
	_run(40)
	assert_eq(router.current_id(), 1, "C: the main menu")


func test_a_new_run_and_its_redraw() -> void:
	if not need_rom():
		return
	var case: Dictionary = _cases["reroll"]
	var session := MwSession.new(1, 1)
	session.setup.play_mode = 1
	session.setup.team_a = 0
	session.setup.team_b = 5
	session.rng.state = 193114104                   # the original's main stream before Start (GPGX)
	session.playoffs.start(session.setup, session.rng)
	_start(session)
	assert_true(router.current() is MwPlayoffsScreen)
	_press("ui_new_playoffs", 2)              # any pad: a new draw from the main stream
	assert_eq(session.playoffs.seed, 0x764)
	var got := []
	for side in 2:
		got.append_array(Array(session.playoffs.sides[side]))
	assert_eq(got, case["bracket"].map(func(x: Variant) -> int: return int(x)))
	_press("ui_accept")
	_run(40)
	assert_eq(router.current_id(), 3)
	assert_eq(session.playoffs.flags & MwPlayoffs.NEW, 0, "the run has started")


## Plan 34: the bracket reads every pad - in an extended set-up every
## player's (5-12 too); the password screen pad 1, else pad 2, and there
## then players 3-12 in number order.
func test_players_5_to_12_answer_in_an_extended_set_up() -> void:
	if not need_rom():
		return
	var session := MwSession.new(1, 1)
	session.setup.play_mode = 1
	session.playoffs.start(session.setup, session.rng)
	_start(session)
	var po := router.current() as MwPlayoffsScreen
	var start := MwInputFrame.make({MwVerbs.menu_action(9, "ui_accept"): true}, {})
	var pw := (load("res://scenes/password/password.tscn") as PackedScene).instantiate() as MwPasswordScreen
	pw.session = session
	var pick := MwInputFrame.make({MwVerbs.menu_action(3, "ui_pick_letter"): true}, {})
	assert_eq(po._pads(start), 0, "the original's set-up: player 9 on no pad")
	assert_eq(pw._pads(pick), 0, "the password: pads 1 and 2 only")
	session.humans = MwHumans.new()
	for p in [1, 2, 3]:
		session.humans.set_team(p, 0)
	session.humans.set_team(9, 1)
	session.pad_map = session.humans.pad_players(rom)
	assert_eq(po._pads(start), 0x80, "an extended set-up: player 9's Start")
	assert_eq(pw._pads(pick), 0x40, "the password: then player 3's A")
	var both := MwInputFrame.make({MwVerbs.menu_action(3, "ui_pick_letter"): true,
			MwVerbs.menu_action(2, "ui_erase_letter"): true}, {})
	assert_eq(pw._pads(both), 0x10, "pad 2 before them")
	pw.free()
	_press("ui_accept", 9)
	_run(40)
	assert_eq(router.current_id(), 3, "player 9's Start: the matchup")


## The palette lines the champion's banner draws on.
func _champion_lines() -> Array:
	var img := ((router.current() as MwPlayoffsScreen).champion_text.texture as ImageTexture).get_image()
	var lines := {}
	for v in img.get_data():
		if v % 16 != 0:
			lines[v / 16] = true
	var out := lines.keys()
	out.sort()
	return out


func test_champion_and_eliminated_go_back_to_the_menu() -> void:
	if not need_rom():
		return
	var champion_session := MwSession.new(1, 1)
	champion_session.playoffs.flags = MwPlayoffs.CHAMPION
	_start(champion_session)
	assert_eq((router.current() as MwPlayoffsScreen).phase, MwPlayoffsScreen.Phase.CHAMPION)
	assert_eq(_champion_lines(), [1, 3], "THE <name> on team A's line, in its colours (owner); WIN ... on line 3")
	var was := MwSettings.team_name_colours
	MwSettings.team_name_colours = false
	(router.current() as MwPlayoffsScreen)._champion()
	assert_eq(_champion_lines(), [2, 3], "off: the original's line 2")
	MwSettings.team_name_colours = was
	_press("ui_accept")
	_run(40)
	assert_eq(router.current_id(), 1)
	host.free()
	host = null
	var session := MwSession.new(1, 1)
	session.playoffs.flags = MwPlayoffs.ELIMINATED
	_start(session)
	assert_eq(router.current_id(), 1)
