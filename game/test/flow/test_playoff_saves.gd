extends "res://test/rom/rom_test_base.gd"
## Plan 34: the playoffs' saves (MwPlayoffSave), the saved games' page, and
## the port's routes through the playoffs screen - after a game back to the
## game options (and the autosave), a loaded run's bracket, the password's
## cancel back to its page.

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad
var _dir := ""
var _front := true


func before_all() -> void:
	super.before_all()
	_dir = MwPlayoffSave.dir
	_front = MwSettings.front_menu
	MwSettings.front_menu = true


func after_all() -> void:
	MwPlayoffSave.dir = _dir
	MwSettings.front_menu = _front


func before_each() -> void:
	MwPlayoffSave.dir = "user://test_saves_%d" % Time.get_ticks_usec()


func after_each() -> void:
	if host:
		rig.free_host()
		host = null
	for slot in MwPlayoffSave.slots():
		MwPlayoffSave.delete(slot)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwPlayoffSave.dir))


func _router(session: MwSession) -> void:
	router = rig.make(self, session)
	host = rig.host
	pad = rig.pad


func _adopt(id: int, data := {}) -> void:
	var scene := MwRouter.instantiate_scene(id)
	scene.screen_id = id
	router.adopt(scene, data)
	router.fader.uncover()


func _run(ticks: int) -> void:
	rig.run(ticks)


func _press(action: String, after := 10) -> void:
	rig.hold({action: true, "p1_" + action: true}, 3, after)


func _until(id: int, limit := 900) -> bool:
	return rig.until(id, limit, 20)


## A session with a run of teams 3 and 7 after its first game (won): the
## screens' own calls, in their order.
func _after_a_game() -> MwSession:
	var rom_bytes := MwRom.data()
	var session := MwSession.new(1, 1)
	session.local_mode = "playoffs"
	session.setup.team_a = 3
	session.setup.team_b = 7
	session.setup.play_mode = MwPlayoffs.MODE_PLAYOFFS
	session.playoffs.start(session.setup, session.rng)                  # PLAY GAME: the new run
	session.run_started = true
	session.playoffs.build_bracket(rom_bytes, session.setup.team_a, session.setup.team_b)   # its bracket
	var g := session.playoffs.game_teams()
	session.setup.team_a = g.x
	session.setup.team_b = g.y
	session.playoffs.flags &= ~MwPlayoffs.NEW               # the bracket's Start (`$11C6A`)
	session.playoffs.game_over(true)                        # the game, won
	var d := session.playoffs.dead
	session.run_password = session.playoffs.make_password(rom_bytes, d[0], d[1],
			session.setup.pads).get_string_from_ascii()
	session.run_checkpoint = session.setup.to_bytes() + session.playoffs.to_bytes()   # the bracket opens
	session.run_games = 1
	return session


func test_the_run_round_trips_its_21_bytes() -> void:
	var original := MwPlayoffs.new()
	original.rng.state = 0x12345678
	original.dead = PackedInt32Array([0x2ABCD, 0x15555])
	original.seed = 0xABC
	original.pair = 37
	original.conference = 1
	original.best_of_3 = 1
	original.flag_11 = 1
	original.series = 2
	original.round = 0
	original.flags = MwPlayoffs.SHOW_PASSWORD | MwPlayoffs.RANDOM_DEAD
	var playoffs := MwPlayoffs.new()
	assert_true(playoffs.from_bytes(original.to_bytes()))
	assert_eq(playoffs.to_bytes(), original.to_bytes())
	assert_eq([playoffs.rng.state, playoffs.dead[0], playoffs.dead[1], playoffs.seed, playoffs.pair, playoffs.flags],
			[0x12345678, 0x2ABCD, 0x15555, 0xABC, 37, original.flags])
	assert_false(playoffs.from_bytes(PackedByteArray([1, 2, 3])), "not 21 bytes")


func test_a_loaded_run_goes_on_as_if_never_saved() -> void:
	if not need_rom():
		return
	var rom_bytes := MwRom.data()
	var uninterrupted := _after_a_game()
	assert_true(MwPlayoffSave.save(uninterrupted, 3))
	# uninterrupted: the bracket opens, the next game's teams
	uninterrupted.playoffs.build_bracket(rom_bytes, uninterrupted.setup.team_a, uninterrupted.setup.team_b)
	var want := [uninterrupted.playoffs.sides[0], uninterrupted.playoffs.sides[1], uninterrupted.playoffs.game_teams(),
			uninterrupted.playoffs.rng.state]
	# loaded into a fresh session: the same bracket opens
	var session := MwSession.new(99, 99)
	assert_true(MwPlayoffSave.load_into(session, 3))
	assert_eq(session.local_mode, "playoffs")
	assert_true(session.run_started)
	assert_eq(session.run_games, 0, "no game since the load: no SAVE GAME yet")
	assert_eq(session.run_password, uninterrupted.run_password)
	session.playoffs.build_bracket(rom_bytes, session.setup.team_a, session.setup.team_b)
	assert_eq([session.playoffs.sides[0], session.playoffs.sides[1], session.playoffs.game_teams(),
			session.playoffs.rng.state], want,
			"the same bracket, the same next game, the same stream")


func test_slots_info_delete_and_refusals() -> void:
	if not need_rom():
		return
	var session := _after_a_game()
	assert_true(MwPlayoffSave.info(1).is_empty(), "empty")
	assert_false(MwPlayoffSave.save(MwSession.new(1, 1), 1), "nothing to save before a game")
	assert_true(MwPlayoffSave.save(session, 1))
	var i := MwPlayoffSave.info(1)
	assert_true(i.ok)
	assert_eq([i.team_a, i.round, i.password], [session.setup.team_a, session.playoffs.round, session.run_password])
	assert_eq(MwPlayoffSave.slots(), [0, 1, 2, 3, 4, 5, 6, 7, 8], "the autosave first, then 8 slots")
	var cfg := ConfigFile.new()
	cfg.load(MwPlayoffSave.path(1))
	cfg.set_value("save", "rom_sha1", "another rom")
	cfg.save(MwPlayoffSave.path(2))
	assert_false(MwPlayoffSave.info(2).ok, "another ROM's")
	assert_false(MwPlayoffSave.load_into(MwSession.new(1, 1), 2), "refused")
	MwPlayoffSave.delete(1)
	assert_false(MwPlayoffSave.exists(1))


func test_save_game_writes_a_slot_and_load_game_takes_it() -> void:
	if not need_rom():
		return
	var session := _after_a_game()
	_router(session)
	_adopt(MwScreens.SAVED_GAMES, {"mode": "save"})
	_run(10)
	var menu := router.current() as MwPortMenu
	assert_eq(menu.page_title(), "SAVE GAME")
	assert_eq(menu.rows.size(), 9)
	_press("ui_accept", 10)
	assert_eq(router.current_id(), MwScreens.SAVED_GAMES, "the autosave is the game's own: refused")
	_press("ui_down")
	_press("ui_accept", 0)
	assert_true(_until(1), "saved: back to the game setup")
	assert_true(MwPlayoffSave.exists(1))
	host.free()
	host = null
	_router(MwSession.new(5, 5))
	_adopt(MwScreens.SAVED_GAMES, {"mode": "load"})
	_run(10)
	menu = router.current() as MwPortMenu
	assert_eq(menu.page_title(), "LOAD GAME")
	assert_ne(menu._slot_value(menu.rows[1].info), "EMPTY")
	assert_eq(menu._slot_value(menu.rows[2].info), "EMPTY")
	_press("ui_accept", 10)
	assert_eq(router.current_id(), MwScreens.SAVED_GAMES, "the empty autosave: refused")
	_press("ui_down")
	_press("ui_accept", 0)
	assert_true(_until(11), "LOAD GAME -> the run's bracket")
	assert_true(router.session.run_started)
	assert_false(router.current() is MwPasswordScreen, "no password screen for a loaded run")
	assert_eq((router.current() as MwPlayoffsScreen).phase, MwPlayoffsScreen.Phase.BRACKET)


func test_overwrite_and_delete_ask_first() -> void:
	if not need_rom():
		return
	var session := _after_a_game()
	MwPlayoffSave.save(session, 1)
	_router(session)
	_adopt(MwScreens.SAVED_GAMES, {"mode": "save"})
	_run(10)
	var menu := router.current() as MwPortMenu
	_press("ui_down")
	_press("ui_accept")
	assert_true(menu.confirm.active, "OVERWRITE THIS SAVE?")
	_press("ui_back")
	assert_false(menu.confirm.active)
	assert_eq(router.current_id(), MwScreens.SAVED_GAMES, "NO: nothing")
	_press("ui_delete")
	assert_true(menu.confirm.active, "DELETE?")
	_press("ui_up")
	_press("ui_accept")
	assert_false(MwPlayoffSave.exists(1), "deleted")
	assert_eq(menu._slot_value(menu.rows[1].info), "EMPTY")
	_press("ui_back", 0)
	assert_true(_until(1), "Menu Back from SAVE GAME: the game setup")


func test_after_a_game_the_bracket_leads_back_to_the_options() -> void:
	if not need_rom():
		return
	var session := _after_a_game()
	session.run_games = 0                                    # the screen counts the game
	session.run_checkpoint = PackedByteArray()
	_router(session)
	var stand_in := MwScreen.new()
	stand_in.screen_id = 16                                # the playoff game's last scoreboard
	router.adopt(stand_in)
	router.fader.uncover()
	router.go(11)
	_run(200)
	assert_true(router.current() is MwPasswordScreen, "the new password, as the original")
	_press("ui_password_done", 0)                      # Start: on to the bracket
	_run(200)
	assert_eq(router.current_id(), 11)
	assert_eq(session.run_games, 1, "a game of the run")
	assert_eq(session.run_checkpoint.size(), 31, "the run as the bracket opened")
	assert_true(MwPlayoffSave.exists(MwPlayoffSave.AUTOSAVE), "autosaved")
	_press("ui_accept", 0)
	assert_true(_until(1), "the bracket's Start: the game options (SAVE GAME, then the next game)")
	assert_true((router.current() as MwMainMenu).can_save())


func test_the_passwords_cancel_goes_back_to_its_page() -> void:
	if not need_rom():
		return
	_router(MwSession.new(1, 1))
	_adopt(MwScreens.CONTINUE)
	_run(10)
	_press("ui_down")
	_press("ui_accept", 0)
	assert_true(_until(11))
	_run(100)
	assert_true(router.current() is MwPasswordScreen)
	_press("ui_back", 0)                               # as C: cancel
	assert_true(_until(MwScreens.CONTINUE), "cancelled: the continue page")


func test_an_eliminated_run_ends_at_local_play() -> void:
	if not need_rom():
		return
	var session := _after_a_game()
	session.playoffs.flags |= MwPlayoffs.ELIMINATED
	_router(session)
	var stand_in := MwScreen.new()
	stand_in.screen_id = 16
	router.adopt(stand_in)
	router.fader.uncover()
	router.go(11)
	assert_true(_until(MwScreens.LOCAL_PLAY), "eliminated: LOCAL PLAY")
	assert_false(session.run_started, "the run is over")
	assert_eq(session.run_checkpoint.size(), 0)
