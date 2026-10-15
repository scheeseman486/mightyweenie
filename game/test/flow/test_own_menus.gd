extends "res://test/rom/rom_test_base.gd"
## Plan 34, work item 9, in the rink scene: everyone else's own menus
## (MwOwnMenus over the running game, MwRinkControl behind them), the
## captains' pause, QUIT GAME and REJOIN on the own menus (the pause menu
## has none: owner, 2026-10-10), the players who left kept in the session
## (MwHumans.out).
## Short names: h the MwHumans under test.

var host: Node
var _layouts := {}


func before_all() -> void:
	super.before_all()
	_layouts = MwSettings.layouts


func after_all() -> void:
	MwSettings.layouts = _layouts
	MwInputMap.install()


func before_each() -> void:
	MwSettings.layouts = {}
	MwInputMap.install()


func after_each() -> void:
	if host:
		host.free()
		host = null
		await wait_process_frames(1)


## A session with [param h]'s players (as the controller selection leaves it).
func _session(h: MwHumans) -> MwSession:
	var session := MwSession.new(1, 1)
	session.humans = h
	h.apply_to(session.setup)
	session.pad_map = h.pad_players(rom)
	return session


func _rink(session: MwSession) -> MwRink:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = session
	router.go(4, {"new_match": true}, false)
	for i in 3:
		router.step()
	var rk := router.current() as MwRink
	for i in 900:
		if rk.state.phase == MwRinkState.PHASE_PLAY:
			break
		rk._screen_pass(2, MwInputFrame.make({}, {}))
	return rk


static func _humans(a: Array, b: Array, captains := [0, 0]) -> MwHumans:
	var h := MwHumans.new()
	for p in a:
		h.set_team(p, 0)
	for p in b:
		h.set_team(p, 1)
	h.captains = captains.duplicate()
	return h


func _tap(rk: MwRink, a: Dictionary) -> void:
	rk._screen_pass(2, MwInputFrame.make(a, {}))
	rk._screen_pass(2, MwInputFrame.make({}, {}))


func _verb(v: String, p: int) -> Dictionary:
	return {MwVerbs.menu_action(p, v): true, v: true}


func test_own_menus_over_the_running_game() -> void:
	if not need_rom():
		return
	var rk := _rink(_session(_humans([1, 2, 3], [4, 5], [1, 4])))
	var control := rk.state.control
	assert_not_null(control, "the rink's control layer")
	assert_true(control.captain_mode)
	var seat := control.seat_of(2)
	assert_not_null(control.driven_by(seat))
	var tick := rk.state.tick
	_tap(rk, {"p2_pause": true})
	assert_false(rk.phases.paused, "player 2's Start never pauses ...")
	assert_eq(rk.own_menus.count(), 1, "... it opens their own menu")
	assert_true(rk.own_menus.visible)
	assert_null(control.driven_by(seat), "the CPU drives their skater")
	for i in 10:
		rk._screen_pass(2, MwInputFrame.make({}, {}))
	assert_eq(rk.state.tick, tick + 24, "the game runs on under it")
	_tap(rk, {"p5_pause": true})
	assert_eq(rk.own_menus.count(), 2, "one window a player")
	var w2: Node2D = rk.own_menus.get_node("Player2")
	var w5: Node2D = rk.own_menus.get_node("Player5")
	assert_lt(w2.position.x, 160.0, "team A's down the left")
	assert_gt(w5.position.x, 160.0, "team B's down the right")
	_tap(rk, _verb("ui_down", 2))
	assert_eq(seat.menu["sel"], 1, "QUIT GAME")
	_tap(rk, _verb("ui_accept", 2))
	assert_true(seat.menu["confirm"], "ARE YOU SURE?")
	assert_eq((w2.get_node("Title") as RomPlane).get_used_cells().size() > 0, true, "the question drawn")
	_tap(rk, _verb("ui_back", 2))
	assert_false(seat.menu["confirm"])
	_tap(rk, _verb("ui_resume", 2))
	assert_true(seat.menu.is_empty(), "Start resumes")
	assert_not_null(control.driven_by(seat), "player 2 drives again")
	assert_eq(rk.own_menus.count(), 1)
	_tap(rk, {"p1_pause": true})
	assert_true(rk.phases.paused, "the captain pauses")
	assert_false(rk.own_menus.visible, "the own menus hidden under the pause menu")
	assert_false(MwRinkPhases.QUIT in rk.phases.menu["items"], "no QUIT GAME on the captain's (owner, 2026-10-10)")
	_tap(rk, _verb("ui_resume", 1))
	assert_false(rk.phases.paused)
	assert_true(rk.own_menus.visible, "back over the game")


## The pause menu has no QUIT GAME (owner, 2026-10-10: a spectated CPU v
## CPU match's alone - plan 34 had it hand the pausing player's spot to the
## CPU); a captain's team-mate leaves with their own menu's QUIT GAME and
## comes back with REJOIN, the players who left kept in the session.
func test_quit_game_on_the_own_menu_and_rejoin() -> void:
	if not need_rom():
		return
	var plain := _rink(_session(_humans([1], [2])))
	assert_false(plain.state.control.captain_mode, "an exhibition: no captains")
	_tap(plain, {"p1_pause": true})
	assert_true(plain.phases.paused, "anyone pauses")
	assert_eq(plain.phases.menu["items"].size(), 4 if plain.state.pause_offer != 0 else 3)
	assert_false(MwRinkPhases.QUIT in plain.phases.menu["items"], "no QUIT GAME on the pause menu")
	host.free()
	host = null
	await wait_process_frames(1)
	var session := _session(_humans([1, 2], [3], [1, 3]))
	var rk := _rink(session)
	var control := rk.state.control
	assert_true(control.captain_mode)
	var seat := control.seat_of(2)
	_tap(rk, {"p2_pause": true})
	assert_false(rk.phases.paused, "player 2's Start: their own menu")
	_tap(rk, _verb("ui_down", 2))
	assert_eq(seat.menu["items"][seat.menu["sel"]], MwRinkControl.QUIT)
	_tap(rk, _verb("ui_accept", 2))
	assert_true(seat.menu["confirm"], "ARE YOU SURE?")
	_tap(rk, _verb("ui_down", 2))
	_tap(rk, _verb("ui_accept", 2))
	assert_true(seat.out, "YES: player 2 left")
	assert_eq(session.humans.out, {2: true}, "kept in the session (the next controller selection)")
	assert_null(control.driven_by(seat), "the CPU drives their skater")
	_tap(rk, {"p2_pause": true})
	assert_false(rk.phases.paused, "a player who left doesn't pause ...")
	assert_eq(seat.menu["items"][0], MwRinkControl.REJOIN, "... their Start offers REJOIN")
	assert_eq(rk.own_menus.count(), 1)
	_tap(rk, _verb("ui_accept", 2))
	assert_false(seat.out, "REJOIN")
	assert_eq(session.humans.out, {})
	assert_not_null(control.driven_by(seat), "player 2 plays again")
	assert_eq(rk.own_menus.count(), 0)


func test_players_still_out_start_the_next_selection_in_the_middle() -> void:
	if not need_rom():
		return
	var session := _session(_humans([1, 3], [2], [0, 0]))
	session.humans.out = {3: true}
	MwFlow.before_match(session)
	assert_eq(session.humans.team_of(3), MwHumans.MIDDLE, "player 3 left the last game: the middle")
	assert_eq(session.humans.out, {})
	assert_eq(session.humans.teams[0], [1])


func test_captain_screen_pads() -> void:
	if not need_rom():
		return
	var h := _humans([3, 7], [5], [7, 5])           # 2 v 1: the original's pads
	var pads := h.pad_players(rom)
	assert_eq(MwRinkControl.captain_screen_pad(h, pads), pads.find(7) + 1, "the pad the router gives the captain")
	assert_eq(MwRinkControl.captain_screen_pad(h, pads, 1), pads.find(5) + 1)
	var humans := _humans([1, 2, 9], [], [9, 0])
	assert_eq(MwRinkControl.captain_screen_pad(humans, humans.pad_players(rom)), 9,
			"an extended set-up: the player's own")
	assert_eq(MwRinkControl.captain_screen_pad(_humans([1], [2]), PackedInt32Array([1, 2, 3, 4])), 0, "no captains")


const Pad := preload("res://test/support/pad.gd")


## Between playoff games the game options answer team A's captain as well
## as P1 (the other players: team B's Left / Right as the original's P3 /
## P4 - nothing in a run, whose teams are kept).
func test_the_run_answers_team_as_captain() -> void:
	if not need_rom():
		return
	var front := MwSettings.front_menu
	MwSettings.front_menu = true
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	var session := _session(_humans([1, 2, 9], [], [9, 0]))
	router.session = session
	session.local_mode = "playoffs"
	session.setup.play_mode = MwPlayoffs.MODE_PLAYOFFS
	session.playoffs.start(session.setup, session.rng)
	session.run_started = true
	session.run_games = 1
	var pad := Pad.new()
	router.input = pad
	var scene := MwRouter.instantiate_scene(1)
	scene.screen_id = 1
	router.adopt(scene)
	fader.uncover()
	var menu := scene as MwMainMenu
	for i in 30:
		router.step()
	var row := menu.row
	for who in [2, 9]:
		pad.held = {"p%d_ui_up" % who: true}
		for i in 3:
			router.step()
		pad.held = {}
		for i in 4:
			router.step()
		if who == 2:
			assert_eq(menu.row, row, "player 2 (not the captain): nothing")
		else:
			assert_ne(menu.row, row, "the captain (player 9) moves the rows")
	MwSettings.front_menu = front


## Plan 40 (M8, owner): the own menus' items in the pause menu's colours -
## a secondary alike its primary two levels darker on the Genesis word, the
## same word the pause menu's item palette gives colour 5.
func test_items_in_the_pause_menus_colours() -> void:
	var c := PackedInt32Array()
	c.resize(64)
	c[16 + 2] = 0x0CE
	c[16 + 5] = 0x0CE
	c[32 + 2] = 0x22A
	c[32 + 5] = 0xCCC
	assert_eq(MwPauseMenu.item_words(c, 0x20), PackedInt32Array([0x0CE, 0x08A]), "alike: darker")
	assert_eq(MwPauseMenu.item_words(c, 0x40), PackedInt32Array([0x22A, 0xCCC]), "apart: as they are")
	assert_eq(MwPauseMenu.item_words(PackedInt32Array(), 0x20), PackedInt32Array(), "no palette")
	assert_eq(RomPalette.darker(0x0CE, MwPauseMenu.DARKER_LEVELS), 0x08A, "the palette step's darkening")
