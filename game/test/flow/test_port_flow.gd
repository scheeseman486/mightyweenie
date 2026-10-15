extends "res://test/rom/rom_test_base.gd"
## Plan 34 work item 12: the port's flows end to end through the real
## scenes - the front menu's START GAME, PLAY MODE, LOCAL PLAY, the game
## setup's EXHIBITION and PLAYOFFS variants, the controller selection, the
## selection steps when they apply, to the matchup; the way back with Back.

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad
var _front := true


func before_all() -> void:
	super.before_all()
	_front = MwSettings.front_menu
	MwSettings.front_menu = true


func after_all() -> void:
	MwSettings.front_menu = _front


func after_each() -> void:
	if host:
		rig.free_host()
		host = null


func _start(prepare := Callable()) -> void:
	router = rig.make(self, MwSession.new(1, 1))
	host = rig.host
	if prepare.is_valid():
		prepare.call(router.session)
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(MwScreens.FRONT_MENU)
	scene.screen_id = MwScreens.FRONT_MENU
	router.adopt(scene)
	router.fader.uncover()
	_run(10)


func _run(ticks: int) -> void:
	rig.run(ticks)


func _press(action: String, player := 1, after := 8) -> void:
	rig.hold({action: true, "p%d_%s" % [player, action]: true}, 3, after)


## Waits for screen [param id] to be on and settled (its fade over, its
## opening done: a few more ticks).
func _until(id: int, limit := 900) -> bool:
	return rig.until(id, limit, 40)


## The front menu's row whose action is [param action], selected.
func _pick(action: String) -> void:
	var menu := router.current() as MwPortMenu
	var at := -1
	for i in menu.rows.size():
		if str(menu.rows[i].get("action", "")) == action:
			at = i
	assert_gte(at, 0, "a row for %s" % action)
	while menu.row != at:
		_press("ui_down", 1, 4)
	_press("ui_accept")


## The game setup's PLAY GAME.
func _play_game() -> void:
	var menu := router.current() as MwMainMenu
	while menu.row != MwMainMenu.ACTION_ROW:
		_press("ui_down", 1, 3)
	_press("ui_accept")


func test_an_exhibition_from_the_front_menu_to_the_matchup() -> void:
	if not need_rom():
		return
	_start()
	_pick("start")
	assert_true(_until(MwScreens.PLAY_MODE), "START GAME: PLAY MODE")
	_pick("local")
	assert_true(_until(MwScreens.LOCAL_PLAY), "LOCAL PLAY")
	_pick("exhibition")
	assert_true(_until(1), "EXHIBITION: the game setup")
	assert_eq(router.session.local_mode, "exhibition")
	assert_eq([router.session.setup.penalties, router.session.setup.reserves], [1, 1],
			"PENALTIES on, RESERVES enabled: the port's defaults (owner, 2026-10-15)")
	_run(120)                                   # the slam
	_play_game()
	assert_true(_until(MwScreens.CONTROLLER_SELECT), "PLAY GAME: the controller selection")
	_run(80)                                    # the brick wall's opening
	_press("ui_accept")
	assert_true(_until(MwScreens.LINEUPS), "player 1 alone on team A, Reserves on: his line-up panel")
	_run(150)                                   # the panel lands
	_press("ui_accept")                         # DONE: the line-up as it stands
	assert_true(_until(3), "on to the matchup")
	assert_eq(router.session.setup.pads, 0, "the original's 1 v CPU")
	assert_true(MwHumans.identity(router.session.pad_map), "pads 1-4 as they are")


func test_a_playoff_run_from_the_front_menu_to_the_matchup() -> void:
	if not need_rom():
		return
	_start()
	_pick("start")
	assert_true(_until(MwScreens.PLAY_MODE))
	_pick("local")
	assert_true(_until(MwScreens.LOCAL_PLAY))
	_pick("playoffs")
	assert_true(_until(1), "PLAYOFFS: the game setup")
	_run(120)
	_play_game()
	assert_true(_until(11), "a new run: its bracket")
	assert_true(router.session.run_started)
	_run(120)
	_press("ui_accept")
	assert_true(_until(MwScreens.CONTROLLER_SELECT), "the bracket's Start: the controller selection")
	_run(80)
	_press("ui_accept")
	assert_true(_until(MwScreens.LINEUPS), "Reserves on (the port's default): the line-up panel")
	_run(150)
	_press("ui_accept")
	assert_true(_until(3), "on to the matchup")


func test_five_players_go_through_character_selection() -> void:
	if not need_rom():
		return
	_start(func(router_session: MwSession) -> void:
		router_session.humans = MwHumans.new()
		for p in [1, 2, 3]:
			router_session.humans.set_team(p, 0)
		for p in [4, 5]:
			router_session.humans.set_team(p, 1))
	_pick("start")
	assert_true(_until(MwScreens.PLAY_MODE))
	_pick("local")
	assert_true(_until(MwScreens.LOCAL_PLAY))
	_pick("exhibition")
	assert_true(_until(1))
	_run(120)
	_play_game()
	assert_true(_until(MwScreens.CONTROLLER_SELECT))
	_run(80)
	_press("ui_accept")
	assert_true(_until(MwScreens.CHARACTER_SELECT), "more than four players: character selection")


func test_back_all_the_way_to_the_title() -> void:
	if not need_rom():
		return
	_start()
	_pick("start")
	assert_true(_until(MwScreens.PLAY_MODE))
	_pick("local")
	assert_true(_until(MwScreens.LOCAL_PLAY))
	_pick("exhibition")
	assert_true(_until(1))
	_run(120)
	_play_game()
	assert_true(_until(MwScreens.CONTROLLER_SELECT))
	_run(80)
	router.session.humans.set_team(1, MwHumans.MIDDLE)
	_press("ui_back")
	assert_true(_until(1), "110: Back in the middle - the game setup")
	_run(120)
	_press("ui_back")
	assert_true(_until(MwScreens.LOCAL_PLAY), "the game setup: LOCAL PLAY")
	_press("ui_back")
	assert_true(_until(MwScreens.PLAY_MODE))
	_press("ui_back")
	assert_true(_until(MwScreens.FRONT_MENU))
	_press("ui_back")
	assert_true(_until(0), "the front menu: the title")


## The port's game setup defaults (owner, 2026-10-15: penalties and reserves
## on by default): taken once a session, the first time the front menu shows -
## the player's own choice stays after; the original's boot defaults (both
## off) for a session that never sees it (the original's flow).
func test_penalties_and_reserves_on_by_default() -> void:
	if not need_rom():
		return
	var session := MwSession.new(1, 1)
	assert_eq([session.setup.penalties, session.setup.reserves], [0, 0], "the original's boot defaults")
	session.take_port_defaults()
	assert_eq([session.setup.penalties, session.setup.reserves], [1, 1])
	session.setup.penalties = 0
	session.take_port_defaults()
	assert_eq(session.setup.penalties, 0, "the player's own choice stays")
	_start()
	assert_eq([router.session.setup.penalties, router.session.setup.reserves], [1, 1], "the front menu takes them")
