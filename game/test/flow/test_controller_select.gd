extends "res://test/rom/rom_test_base.gd"
## Plan 34: the controller selection (110) and the players in a match
## (MwHumans) - the original's pad modes derived from the players, each pad
## handed its player's inputs, the page's moves and rules, the flow through
## it, saves keeping the players.
## Short names: h the MwHumans under test, m the MwMainMenu under test.

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


# --- MwHumans --------------------------------------------------------------------------------------

func test_the_original_pad_modes_come_back() -> void:
	if not need_rom():
		return
	var counts := {0: Vector2i(1, 0), 1: Vector2i(1, 1), 2: Vector2i(2, 0), 3: Vector2i(2, 1), 4: Vector2i(2, 2),
			5: Vector2i(0, 0)}
	for mode in counts:
		var h := MwHumans.from_pad_mode(rom, mode)
		assert_eq(Vector2i(h.count(0), h.count(1)), counts[mode], "mode %d's players" % mode)
		assert_eq(h.pad_mode(), mode, "mode %d derived back" % mode)
		assert_true(MwHumans.identity(h.pad_players(rom)), "mode %d: pads 1-4 are players 1-4" % mode)


func test_players_fill_the_original_slots_in_number_order() -> void:
	if not need_rom():
		return
	var h := MwHumans.new()
	h.set_team(7, 0)
	h.set_team(3, 0)
	h.set_team(5, 1)
	assert_eq(h.teams[0], [3, 7], "number order")
	assert_eq(h.pad_mode(), 3, "2 v 1")
	var map := h.pad_players(rom)
	var slots := []
	for t in 2:
		for i in 2:
			slots.append(rom[MwRinkMatch.PAD_MODES + 4 * 3 + 2 * t + i])
	assert_eq(map[slots[0] & 3], 3, "team A's first slot: its lowest number")
	assert_eq(map[slots[1] & 3], 7)
	assert_eq(map[slots[2] & 3], 5, "team B's first slot")
	assert_false(1 in map, "player 1, not playing, drives no pad")


func test_extended_set_ups_have_no_original_mode() -> void:
	var h := MwHumans.new()
	for p in [1, 2, 3]:
		h.set_team(p, 0)
	assert_eq(h.pad_mode(), -1, "three on a team")
	h = MwHumans.new()
	h.set_team(2, 1)
	assert_eq(h.pad_mode(), -1, "team B only")
	h.set_team(1, 0)
	h.set_team(3, 1)
	assert_eq(h.pad_mode(), -1, "1 v 2")


func test_moves_and_the_team_limit() -> void:
	var h := MwHumans.new()
	assert_true(h.move(4, -1))
	assert_eq(h.team_of(4), 0, "left: team A")
	assert_false(h.move(4, -1), "no further left")
	assert_true(h.move(4, 1))
	assert_eq(h.team_of(4), MwHumans.MIDDLE, "right: back to the middle")
	for p in range(1, 7):
		assert_true(h.move(p, 1))
	assert_false(h.move(9, 1), "a team holds six")
	assert_eq(h.count(1), MwHumans.TEAM_MAX)
	var back := MwHumans.from_record(h.to_record())
	assert_eq(back.teams, h.teams, "the record round trip")


func test_each_pad_gets_its_players_inputs() -> void:
	var map := PackedInt32Array([3, 7, 0, 4])
	var got := MwHumans.remap({"p3_pass": true, "p7_move_up": true, "p1_pass": true, "ui_accept": true,
			"p7_ui_left": true, "p12_check": true, "view_toggle": true}, map)
	assert_eq(got, {"p1_pass": true, "p2_move_up": true, "ui_accept": true, "p2_ui_left": true,
			"view_toggle": true}, "pad 1 = player 3, pad 2 = player 7; the others dropped; shared verbs kept")
	assert_true(MwHumans.identity(PackedInt32Array([1, 2, 3, 4])))


# --- the page and the flow -------------------------------------------------------------------------

func _start(id: int, mode := "exhibition", prepare := Callable()) -> MwScreen:
	router = rig.make(self, MwSession.new(1, 1))
	host = rig.host
	router.session.local_mode = mode
	if prepare.is_valid():
		prepare.call(router.session)
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(id)
	scene.screen_id = id
	router.adopt(scene)
	router.fader.uncover()
	_run(20)
	return scene


func _run(ticks: int) -> void:
	rig.run(ticks)


func _press(action: String, player := 1, after := 6) -> void:
	rig.hold({action: true, "p%d_%s" % [player, action]: true}, 3, after)


func _until(id: int, limit := 600) -> bool:
	return rig.until(id, limit, 0)


func test_the_page_moves_each_players_line() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT) as MwMainMenu
	var sel := m.select
	assert_not_null(sel, "the controller selection")
	assert_true(1 in sel.shown, "player 1 (the keyboard) has a line")
	var h := router.session.humans
	assert_eq(h.team_of(1), 0, "the boot set-up: player 1 on team A")
	_press("ui_right")
	assert_eq(h.team_of(1), MwHumans.MIDDLE, "Right: the middle")
	_press("ui_right")
	assert_eq(h.team_of(1), 1, "team B")
	_press("ui_back")
	assert_eq(h.team_of(1), MwHumans.MIDDLE, "Back on a team: the middle")
	_press("ui_left", 3)
	assert_eq(h.team_of(3), 0 if 3 in sel.shown else MwHumans.MIDDLE, "player 3 moves only with a line")
	h.set_team(3, MwHumans.MIDDLE)
	_press("ui_accept")
	assert_true(_until(3), "nobody on a team: CPU v CPU, on to the matchup")
	assert_eq(router.session.setup.pads, 5, "pad mode 5")


func test_going_on_derives_the_pad_mode() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT, "exhibition", func(router_session: MwSession) -> void:
		router_session.humans = MwHumans.new()
		router_session.humans.set_team(2, 0)
		router_session.humans.set_team(1, 1)) as MwMainMenu
	assert_true(2 in m.select.shown, "a player on a team has a line")
	_press("ui_accept")
	assert_true(_until(3))
	assert_eq(router.session.setup.pads, 1, "1 v 1")
	var slots := [rom[MwRinkMatch.PAD_MODES + 4], rom[MwRinkMatch.PAD_MODES + 6]]
	assert_eq(router.session.pad_map[slots[0] & 3], 2, "team A's pad: player 2")
	assert_eq(router.session.pad_map[slots[1] & 3], 1, "team B's: player 1")
	assert_eq(router.session.player_on_pad((slots[0] & 3) + 1), 2)


func test_the_matchs_screens_read_the_mapped_pads() -> void:
	if not need_rom():
		return
	_start(MwScreens.CONTROLLER_SELECT, "exhibition", func(router_session: MwSession) -> void:
		router_session.humans = MwHumans.new()
		router_session.humans.set_team(5, 0))
	_press("ui_accept")
	assert_true(_until(3))
	var p0 := router.session.pad_map.find(5)
	assert_gte(p0, 0, "player 5 drives a pad")
	pad.held = {"p5_pass": true}
	_run(2)
	assert_true(router._frame.held.has("p%d_pass" % (p0 + 1)), "the matchup sees player 5's input on that pad")
	assert_false(router._frame.held.has("p5_pass"))


func test_playoffs_need_a_player_on_team_a() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT, "playoffs", func(router_session: MwSession) -> void:
		router_session.humans = MwHumans.new()
		router_session.humans.set_team(1, 1)) as MwMainMenu
	assert_ne(m.select.refusal(), "")
	_press("ui_accept", 1, 20)
	assert_eq(router.current_id(), MwScreens.CONTROLLER_SELECT, "refused")
	_press("ui_left")
	_press("ui_left")
	assert_eq(router.session.humans.team_of(1), 0)
	assert_eq(m.select.refusal(), "")


## CPU v CPU (everyone in the middle) is a local exhibition's alone (owner,
## 2026-10-10: exhibition only): the playoffs and online refuse
## it as their other refusals - the sound, player 1's line shaking and the
## reason on the title plate for a while; the session calls only a local
## exhibition's spectated (MwSession.spectated).
func test_cpu_v_cpu_is_an_exhibitions_alone() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT, "playoffs", func(router_session: MwSession) -> void:
		router_session.humans = MwHumans.new()) as MwMainMenu
	var sel := m.select
	assert_eq(sel.refusal(), MwControllerSelect.EXHIBITION_ONLY, "the playoffs: nobody on a team refused")
	var title: RomPlane = sel.get("_title")
	var cells := title.get_used_cells().size()
	_press("ui_accept", 1, 20)
	assert_eq(router.current_id(), MwScreens.CONTROLLER_SELECT, "refused")
	assert_false(router.busy())
	assert_eq(sel.message, MwControllerSelect.EXHIBITION_ONLY, "the reason on the title plate")
	assert_ne(title.get_used_cells().size(), cells, "the plate redrawn with it")
	_run(MwControllerSelect.MESSAGE_TICKS)
	assert_eq(sel.message, "", "then the title again")
	assert_eq(title.get_used_cells().size(), cells)
	_press("ui_right")
	assert_eq(sel.refusal(), MwControllerSelect.TEAM_A_NEEDS, "team B alone: team A still needs a player")
	assert_false(router.session.spectated(), "never a spectated playoff game")
	var online := MwControllerSelect.new()
	online.humans = MwHumans.new()
	online.online = [1, 2]
	assert_eq(online.refusal(), MwControllerSelect.LOCAL_ONLY, "online: CPU v CPU is local only")
	online.humans.set_team(2, 1)
	assert_eq(online.refusal(), "", "a player on a team plays online")
	online.free()
	var session := MwSession.new(1, 1)
	session.local_mode = "exhibition"
	session.humans = MwHumans.new()
	assert_true(session.spectated(), "a local exhibition with everyone in the middle")
	assert_eq(session.screen_pads(), MwVerbs.PLAYERS, "every player's pad counts on its screens")
	session.online = {"players": [1, 2], "machines": {"1": 0, "2": 1}}
	assert_false(session.spectated(), "never online")
	session.online = {}
	session.attract = true
	assert_false(session.spectated(), "the attract demo is the original's CPU v CPU")
	assert_eq(session.screen_pads(), 4)
	session.attract = false
	session.humans.set_team(1, 0)
	assert_false(session.spectated(), "someone plays")


func test_an_extended_set_up_goes_on() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT, "exhibition", func(router_session: MwSession) -> void:
		router_session.humans = MwHumans.new()
		for p in [1, 2, 3]:
			router_session.humans.set_team(p, 0)
		router_session.humans.set_team(4, 1)) as MwMainMenu
	assert_eq(m.select.refusal(), "", "work item 8: extended set-ups play")
	_press("ui_accept")
	assert_true(_until(3), "on to the matchup")
	var su := router.session.setup
	assert_eq(su.pads, 3, "the nearest original mode (2 v 1)")
	assert_eq(su.extended, [], "the players hold them (plan 40, S13)")
	assert_eq(MwSelection.for_the_rink(router.session, su.copy()).extended,
			[PackedInt32Array([0, 1, 2]), PackedInt32Array([3])], "each team's match pads, at the rink's entry")
	assert_true(MwHumans.identity(router.session.pad_map), "nothing remapped: every player their own pad")
	pad.held = {"p3_pass": true}
	_run(2)
	assert_true(router._frame.held.has("p3_pass"), "player 3's input as it is")


func test_back_in_the_middle_returns_to_the_game_setup() -> void:
	if not need_rom():
		return
	_start(MwScreens.CONTROLLER_SELECT, "exhibition", func(router_session: MwSession) -> void:
		router_session.humans = MwHumans.new())
	_press("ui_back")
	assert_true(_until(1), "player 1's Back in the middle: the game setup")
	assert_null((router.current() as MwMainMenu).slam,
			"back before the wall rose: no slam (the mirror: test_brick_wall.gd)")


func test_every_match_comes_through_the_selection() -> void:
	var session := MwSession.new(1, 1)
	assert_eq(MwFlow.after_options(session, false), MwScreens.CONTROLLER_SELECT, "an exhibition, a run's next game")
	assert_eq(MwFlow.after_options(session, true), 11, "a new run: its bracket first")
	assert_eq(MwFlow.after_bracket(session, false), MwScreens.CONTROLLER_SELECT, "the bracket's Start")
	assert_eq(MwFlow.after_bracket(session, true), 1, "after a game: the game setup")
	assert_eq(MwFlow.after_controllers(session), 3)


func test_saves_keep_the_players() -> void:
	var saved := MwSession.new(1, 1)
	saved.humans = MwHumans.new()
	saved.humans.set_team(4, 0)
	saved.humans.set_team(9, 1)
	var session := MwSession.new(1, 1)
	session.load_humans(saved.humans_record())
	assert_eq(session.humans.teams, [[4], [9]])
	session.load_humans({})
	assert_eq(session.humans.teams, [[4], [9]], "a save without players changes nothing")


func test_owners_captains_and_line_ups_are_kept() -> void:
	var h := MwHumans.new()
	h.set_team(3, 0)
	h.set_team(8, 0)
	h.set_team(5, 1)
	h.positions = {3: 0, 8: MwHumans.GOALIE, 5: 2}
	h.captains = [8, 5]
	h.lineups[0] = PackedInt32Array([0, 1, 2, 3, 4, 20])
	assert_true(h.owners())
	assert_eq(h.owner_of(0, MwHumans.GOALIE), 8)
	assert_eq(h.owner_of(1, 0), 0, "nobody")
	var back := MwHumans.from_record(h.to_record())
	assert_eq([back.teams, back.positions, back.captains, back.lineups[0], back.lineups[1]],
			[h.teams, h.positions, h.captains, h.lineups[0], PackedInt32Array()], "the record round trip")
	h.set_team(8, MwHumans.MIDDLE)
	assert_false(h.positions.has(8), "leaving the team: the position goes")
	assert_eq(h.captain_of(0), 0, "and the captaincy")
