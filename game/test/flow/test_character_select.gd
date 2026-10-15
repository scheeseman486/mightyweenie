extends "res://test/rom/rom_test_base.gd"
## Plan 34 work items 9-10, the selection screens (MwCharacterSelect: 111
## character selection, 112 the captain vote, 113 the line-up panels)
## walked through the router: picks, refusals, locks, READY, the vote on
## 111 and on its own screen, the panels' crash (two meeting in the middle,
## or one from above alone), no title under them, DONE by the drivers'
## confirm (its glyph beside it), browsing a card's candidates (nobody else
## moves; a duplicate in red; accept or Left / Right commits with the swap,
## Back reverts, READY commits), Back to the controller selection and on
## again, and the way on to the matchup.

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

## An online game's service, for its lobby alone.
class FakeNet extends MwNetService:
	var fake := MwNetLobby.new()
	func lobby() -> MwNetLobby:
		return fake

const DEMON_NET := MwSpecialPlaysSim.DEMON_NET

var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad
var _settings := []
## The sounds started ([id, handle]; MwSound.trace - plan 40, D6: the
## driver's model answers, every start is logged here).
var _plays: Array = []


func before_each() -> void:
	_plays = []
	MwSound.trace = func(call_name: String, args: Array, result: Variant) -> void:
		if call_name in ["play", "play_voice"]:
			_plays.append([int(args[0]), result])
	_settings = [MwSettings.character_select, MwSettings.captain_mode, MwSettings.lineup_select, MwSettings.front_menu]
	MwSettings.front_menu = true
	MwSettings.character_select = MwSettings.CHARACTER_SELECTS[0]
	MwSettings.captain_mode = MwSettings.CAPTAIN_MODES[0]
	MwSettings.lineup_select = true


func after_each() -> void:
	MwSound.trace = Callable()
	MwSettings.character_select = _settings[0]
	MwSettings.captain_mode = _settings[1]
	MwSettings.lineup_select = _settings[2]
	MwSettings.front_menu = _settings[3]
	if host:
		rig.free_host()
		host = null


func _start(id: int, a: Array, b: Array, mode := "exhibition", reserves := 0, prepare := Callable()) -> MwScreen:
	var session := MwSession.new(1, 1)
	router = rig.make(self, session)
	host = rig.host
	session.local_mode = mode
	session.humans = MwHumans.new()
	for p in a:
		session.humans.set_team(p, 0)
	for p in b:
		session.humans.set_team(p, 1)
	session.setup.reserves = reserves
	if prepare.is_valid():
		prepare.call(session)
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(id)
	scene.screen_id = id
	router.adopt(scene)
	router.fader.uncover()
	_run(4)
	return scene


func _run(ticks: int) -> void:
	rig.run(ticks)


func _press(action: String, player := 1, after := 3) -> void:
	rig.hold({action: true, "p%d_%s" % [player, action]: true}, 2, after)


func _until(id: int, limit := 600) -> bool:
	return rig.until(id, limit, 0)


## Player 1's accept on the controller selection (110) until it goes on
## (its wall lifts first).
func _go_on_from_the_controller_selection() -> void:
	for i in 40:
		_press("ui_accept", 1, 6)
		if router.current_id() != MwScreens.CONTROLLER_SELECT or router.busy():
			gut.p("110 went on after %d presses" % (i + 1))
			return


func _refused_since(n: int) -> bool:
	for c in _plays.slice(n):
		if int(c[0]) == MwLineup.SOUND_REFUSED:
			return true
	return false


# --- character selection (111) ---------------------------------------------------------------------

func test_the_cards_show_the_rinks_starters() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.CHARACTER_SELECT, [1, 2, 3], [4, 5]) as MwCharacterSelect
	assert_eq(cs.stage, MwCharacterSelect.Stage.PICK)
	for t in 2:
		assert_eq(cs.cards[t].size(), 6, "six cards a side")
		var starters := MwLineup.starters_of(cs.rehearsal, t)
		for card: MwCharacterCard in cs.cards[t]:
			assert_eq(card.slot, starters[card.pos], "the rink entry's starter")
			assert_eq(card.record, (cs.lineups[t] as MwLineup).record(starters[card.pos]))
	assert_eq([cs.cursor[1], cs.cursor[2], cs.cursor[3], cs.cursor[4], cs.cursor[5]], [0, 1, 2, 0, 1],
			"the cursors spread over their team's positions")
	var c0: Vector2i = cs.card_cell(0, 0)
	var c5: Vector2i = cs.card_cell(1, 5)
	assert_lt(c0.x, 20, "team A on the left")
	assert_gte(c5.x, 20, "team B on the right")
	assert_gt(c5.y, c0.y, "LD, RD, G under C, LW, RW")


func test_picks_refusals_and_ready_without_line_ups() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.CHARACTER_SELECT, [1, 2, 3], [4, 5]) as MwCharacterSelect
	assert_eq(cs.title, "PICK YOUR POSITION", "the title says what to do (owner, 2026-10-13)")
	_press("ui_accept", 1)
	assert_eq(cs.picks[1], MwCharacterSelect.Pick.LOCKED, "line-ups off: taken and locked at once")
	_press("ui_left", 2)
	assert_eq(cs.cursor[2], 0, "LW, Left: C")
	var n := _plays.size()
	_press("ui_accept", 2)
	assert_true(_refused_since(n), "player 1's position refuses")
	assert_eq(cs.picks[2], MwCharacterSelect.Pick.MOVING)
	_press("ui_down", 2)
	_press("ui_accept", 2)
	assert_eq(cs.taken[0][3], 2, "LD")
	_press("ui_accept", 3)
	_press("ui_accept", 4)
	assert_eq(cs.stage, MwCharacterSelect.Stage.PICK, "player 5 still picking")
	_press("ui_right", 5)
	_press("ui_accept", 5)
	assert_eq(cs.stage, MwCharacterSelect.Stage.READY, "everyone locked: READY")
	assert_eq(cs.title, "READY")
	_press("ui_back", 4)
	assert_eq(cs.stage, MwCharacterSelect.Stage.PICK, "a Back takes it back")
	assert_eq(cs.title, "PICK YOUR POSITION")
	assert_eq(cs.picks[4], MwCharacterSelect.Pick.MOVING, "line-ups off: Back gives the position back")
	_press("ui_accept", 4)
	assert_eq(cs.stage, MwCharacterSelect.Stage.READY)
	assert_true(_until(3), "no vote, no panels: on to the matchup")
	var h := router.session.humans
	assert_eq(h.positions, {1: 0, 2: 3, 3: 2, 4: 0, 5: 2}, "each player's own position")
	assert_true(h.owners())
	assert_eq(h.lineups, [PackedInt32Array(), PackedInt32Array()], "the starters")


func test_characters_swaps_and_locks() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.CHARACTER_SELECT, [1, 2, 3, 4, 5], [], "exhibition", 1) as MwCharacterSelect
	var lineup: MwLineup = cs.lineups[0]
	_press("ui_accept", 1)
	assert_eq(cs.picks[1], MwCharacterSelect.Pick.PICKED, "line-ups on: the position first")
	_press("ui_accept", 1)
	assert_eq(cs.picks[1], MwCharacterSelect.Pick.LOCKED, "then the character")
	_press("ui_accept", 2)
	var c := lineup.candidates(1)
	var n := _plays.size()
	# stepping LW backwards reaches centre's starter, locked by player 1: refused and passed over
	var back := c[posmod(c.find(lineup.slots[1]) - 1, c.size())]
	_press("ui_left", 2)
	if back == lineup.original[0]:
		assert_true(_refused_since(n))
	assert_ne(lineup.slots[1], lineup.original[0], "never the locked centre")
	assert_eq(lineup.slots[0], lineup.original[0], "the centre stays")
	# RW's starter on LW: they swap
	lineup.slots = lineup.original.duplicate()
	assert_true(lineup.place(1, lineup.original[2], cs.locked(0)))
	assert_eq(lineup.slots[2], lineup.original[1], "swapped")
	for p in [3, 4, 5]:
		_press("ui_accept", p)
		_press("ui_accept", p)
	_press("ui_accept", 2)
	assert_eq(cs.stage, MwCharacterSelect.Stage.READY)
	_run(MwCharacterSelect.READY_TICKS + 2)
	assert_eq(cs.stage, MwCharacterSelect.Stage.PANELS, "an exhibition: no vote; Reserves on: the panel")
	assert_eq(cs.panels.size(), 1, "the team with players")
	assert_eq(cs.panels[0].drivers, [1, 2, 3, 4, 5] as Array[int], "no captain: all its players")
	assert_eq(cs.panels[0].owners.size(), 5, "the picks' P<n> on the cards")
	assert_eq(cs.panels[0].tags().size(), 5, "each on the card picked, none riding the highlight")
	_run(150)
	_press("ui_accept", 4)
	assert_true(_until(3))


func test_the_locked_faces_pull_one_at_a_time() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.CHARACTER_SELECT, [1, 2, 3, 4, 5, 6], []) as MwCharacterSelect
	for p in [1, 2, 3, 4, 5, 6]:
		pad.held["p%d_ui_accept" % p] = true
	pad.held["ui_accept"] = true
	_run(2)
	pad.held = {}
	assert_eq(cs.stage, MwCharacterSelect.Stage.READY, "six locked at once")
	var pulled := {}
	for i in 400:
		router.step()
		var n := 0
		for card: MwCharacterCard in cs.cards[0]:
			if card.pulling():
				n += 1
				pulled[card.pos] = true
		assert_lte(n, 1, "one face at a time")
		if router.current_id() != MwScreens.CHARACTER_SELECT:
			break
	assert_gt(pulled.size(), 0, "the locks' faces")


func test_back_with_nothing_taken_returns_to_the_controller_selection() -> void:
	if not need_rom():
		return
	_start(MwScreens.CHARACTER_SELECT, [1, 2, 3], [4, 5])
	_press("ui_back", 1)
	assert_true(_until(MwScreens.CONTROLLER_SELECT), "player 1's Back")


func test_the_demon_net_is_never_offered() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.CHARACTER_SELECT, [1, 2, 3, 4, 5], [6], "playoffs", 1) as MwCharacterSelect
	_press("ui_down", 1)
	_press("ui_right", 1)
	_press("ui_right", 1)
	assert_eq(cs.cursor[1], 5, "C, down, right twice: G")
	_press("ui_accept", 1)
	var seen := {}
	for i in 6:
		_press("ui_right", 1)
		var card: MwCharacterCard = cs.cards[0][5]
		seen[card.record] = true
		assert_ne(card.record, DEMON_NET, "never the Demon Net")
		assert_true(MwLineup.is_goalie_slot(card.slot), "a goalie")
	assert_eq(seen.size(), 4, "the four goalies go round")


# --- the vote ----------------------------------------------------------------------------------------

func test_the_vote_on_character_selection_then_the_panels() -> void:
	if not need_rom():
		return
	MwSettings.captain_mode = MwSettings.CAPTAIN_MODES[1]
	var cs := _start(MwScreens.CHARACTER_SELECT, [1, 2, 3], [4, 5], "playoffs", 1) as MwCharacterSelect
	assert_eq(cs.title, "PICK YOUR CHARACTER", "line-ups on: a position, then who plays it")
	for p in [1, 2, 3, 4, 5]:
		_press("ui_accept", p)
		_press("ui_accept", p)
	assert_eq(cs.stage, MwCharacterSelect.Stage.READY)
	_run(MwCharacterSelect.READY_TICKS + 2)
	assert_eq(cs.stage, MwCharacterSelect.Stage.VOTE, "the vote on the same screen")
	assert_eq(cs.title, "VOTE FOR CAPTAIN", "the owner's title")
	assert_eq(router.session.humans.positions.size(), 5)
	# team A votes for player 2 (cursors start on their own characters)
	_press("ui_right", 1)
	_press("ui_accept", 1)
	_press("ui_accept", 2)
	_press("ui_left", 3)
	_press("ui_accept", 3)
	assert_eq(router.session.humans.captains[0], 2, "the most votes")
	_press("ui_accept", 4)
	_press("ui_accept", 5)
	assert_eq(cs.votes[1].round, 2, "one each: the tied vote again")
	assert_eq(cs.title, "TIE - VOTE AGAIN")
	_press("ui_accept", 4)
	_press("ui_right", 5)
	_press("ui_accept", 5)
	assert_eq(router.session.humans.captains[1], 4)
	assert_eq(cs.stage, MwCharacterSelect.Stage.RESULT)
	assert_eq(cs.title, "CAPTAINS CHOSEN")
	for card: MwCharacterCard in cs.cards[0]:
		assert_eq(card.captain, card.pos == router.session.humans.positions[2], "the C on the captain's card")
	_run(MwCharacterSelect.RESULT_TICKS + 2)
	assert_eq(cs.stage, MwCharacterSelect.Stage.PANELS, "then the line-up panels")
	assert_eq(cs.title, "", "CAPTAINS CHOSEN gone under the panels")
	assert_eq(cs.panels.size(), 2)
	assert_eq(cs.panels[0].drivers, [2] as Array[int], "the captain drives")
	assert_eq(cs.panels[1].drivers, [4] as Array[int])
	assert_true(cs.cards[0][0].visible, "111 behind the falling panels")
	_run(200)
	assert_false(cs.cards[0][0].visible or cs.get_node("List").visible or cs.get_node("TeamNames").visible,
			"two panels landed: nothing of 111 through their edges")
	_press("ui_accept", 2)
	assert_false(cs.panels[1].is_ready, "only its captain answers a panel")
	_press("ui_accept", 5)
	assert_false(cs.panels[1].is_ready, "a player who isn't captain changes nothing")
	_press("ui_accept", 4)
	assert_true(_until(3), "every panel READY: the matchup")


func test_the_vote_screen_ties_twice_and_draws() -> void:
	if not need_rom():
		return
	MwSettings.captain_mode = MwSettings.CAPTAIN_MODES[1]
	var cs := _start(MwScreens.CAPTAIN_VOTE, [1, 2], [3], "playoffs") as MwCharacterSelect
	var session := router.session
	session.humans.captains = [0, 3]
	assert_eq(cs.stage, MwCharacterSelect.Stage.VOTE)
	assert_null(cs.votes[1], "a team of one doesn't vote")
	assert_eq(cs.title, "VOTE FOR CAPTAIN", "112 too")
	_press("ui_accept", 1)
	_press("ui_accept", 2)
	assert_eq(cs.votes[0].round, 2)
	_press("ui_accept", 1)
	_press("ui_right", 2)
	_press("ui_accept", 2)
	assert_true(cs.votes[0].drawn, "a second tie: the draw")
	assert_eq(cs.title, "CAPTAIN CHOSEN", "one team voted")
	assert_true(session.humans.captains[0] in [1, 2])
	assert_true(_until(3), "then on")


# --- the panels ----------------------------------------------------------------------------------------

func test_two_panels_crash_in_and_meet_in_the_middle() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1], [2], "exhibition", 1) as MwCharacterSelect
	assert_eq(cs.panels.size(), 2)
	var top := cs.panels[0]
	var panel := cs.panels[1]
	assert_eq([top.team, panel.team], [0, 1], "team A on top")
	assert_false(top.from_below)
	assert_true(panel.from_below, "team B from below")
	var n := _plays.size()
	var landed_at := -1
	var shook := false
	assert_almost_eq(top.position.y, -float(MwLineupPanel.HEIGHT), 2.0,
			"just off the screen at first (_start ran 4 ticks)")
	for i in 300:
		router.step()
		assert_eq(top.position.y, -(panel.position.y - MwLineupPanel.HEIGHT), "mirrored")
		assert_eq(cs.position.x, 0.0, "the screen never shakes (the stars stay still)")
		shook = shook or top.position.x != 0.0
		if landed_at < 0 and top.landed() and panel.landed():
			landed_at = i
	# owner, 2026-10-12: the game setup top's slam - it bounces and lands
	var ref := MwSlam.new(MwLineupPanel.HEIGHT)
	ref.bounces = true
	var ticks := 0
	while not ref.done:
		ref.advance(1)
		ticks += 1
	assert_almost_eq(landed_at + 4, ticks, 2, "landed when the game setup's bouncing slam lands")
	assert_true(shook, "each panel shakes itself")
	assert_eq([top.position, panel.position], [Vector2.ZERO, Vector2(0, MwLineupPanel.HEIGHT)], "meeting in the middle")
	var thuds := _plays.slice(n).filter(func(c: Array) -> bool: return int(c[0]) == MwSlam.THUD)
	assert_eq(thuds.size(), 2, "a crash on each of the first two bounces (one for both panels)")


func test_one_panel_comes_from_above_alone() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [], [3], "exhibition", 1) as MwCharacterSelect
	assert_eq(cs.panels.size(), 1)
	var pn := cs.panels[0]
	assert_eq(pn.team, 1, "team B's, whichever team it is")
	assert_false(pn.from_below, "from above")
	var shook := false
	for i in 200:
		router.step()
		assert_lte(pn.position.y, 0.0, "into the top half")
		shook = shook or pn.position.x != 0
		assert_eq(cs.position.x, 0.0, "the panel shakes, not the screen")
	assert_true(pn.landed())
	assert_eq(pn.position.y, 0.0)
	assert_true(shook, "the panel shook")


## Owner, 2026-10-12: the panels crash in over the controller selection -
## no screen fade - its CONTROLLER SELECT plate fading out; backing out
## they pull back off it with the brick wall's rise and its gate's clinks,
## the plate fading back in, and the controller selection goes on from where
## it was.
func test_over_the_controller_selection_and_pulled_back() -> void:
	if not need_rom():
		return
	var fm := []
	MwSound.trace = func(call_name: String, args: Array, result: Variant) -> void:
		if call_name in ["play", "play_voice"]:
			_plays.append([int(args[0]), result])
		elif call_name.begins_with("fm_effect"):
			fm.append([call_name, args])
	var session := MwSession.new(1, 1)
	router = rig.make(self, session)
	host = rig.host
	pad = rig.pad
	session.local_mode = "exhibition"
	session.humans = MwHumans.new()
	session.humans.set_team(1, 0)
	session.humans.set_team(2, 1)
	session.setup.reserves = 1
	rig.open(MwScreens.CONTROLLER_SELECT)
	_run(4)
	var sel := router.current()
	_go_on_from_the_controller_selection()
	_run(1)
	assert_eq(router.current_id(), MwScreens.LINEUPS)
	var cs := router.current() as MwCharacterSelect
	assert_eq(router.stack.size(), 2, "pushed over it")
	assert_eq(cs.under, sel)
	assert_true(sel.visible, "in sight under the panels")
	assert_eq(router.fader.coverage(), 0.0, "no fade")
	assert_false(sel.get_node("Starfield").visible, "its stars: the panels' screen's, under it")
	var plate: Array[CanvasItem] = sel.covered_fades()
	assert_eq(plate.size(), 1, "the CONTROLLER SELECT plate")
	var y0 := cs.panels[0].position.y
	_run(MwMenuCut.FADE_TICKS + 2)
	assert_gt(cs.panels[0].position.y, y0, "falling at once")
	assert_eq(plate[0].modulate.a, 0.0, "the plate faded out")
	_run(200)
	assert_true(cs.panels[0].landed() and cs.panels[1].landed())
	fm.clear()
	_press("ui_back", 1)
	assert_true(fm.has(["fm_effect", [MwBrickWall.SOUND]]), "the gate's clinks")
	_run(MwBrickWall.RISE_TICKS / 2)
	assert_lt(cs.panels[0].position.y, 0.0, "team A's going up")
	assert_gt(cs.panels[1].position.y, float(MwLineupPanel.HEIGHT), "team B's going down")
	assert_gt(plate[0].modulate.a, 0.0, "the plate fading back in")
	assert_true(_until(MwScreens.CONTROLLER_SELECT, 60))
	assert_eq(router.current(), sel, "the same controller selection, popped back to")
	assert_eq(router.stack.size(), 1)
	assert_eq(plate[0].modulate.a, 1.0)
	assert_true(sel.get_node("Starfield").visible, "its own stars again")
	assert_eq([session.humans.team_of(1), session.humans.team_of(2)], [0, 1], "everyone where they were")
	_press("ui_left", 2)
	assert_eq(session.humans.team_of(2), MwHumans.MIDDLE, "it answers again")
	_press("ui_right", 2)
	assert_eq(session.humans.team_of(2), 1)
	_go_on_from_the_controller_selection()
	assert_true(_until(MwScreens.LINEUPS), "on again")
	assert_eq((router.current() as MwCharacterSelect).under, sel)


func test_no_title_under_the_panels() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1], [], "exhibition", 1) as MwCharacterSelect
	assert_eq(cs.title, "", "no title: the panels cover it (owner)")
	assert_eq(cs.get_node("Title").get_used_cells().size(), 0, "nothing on the title's layer")
	_run(150)
	assert_eq(cs.get_node("Title").get_used_cells().size(), 0)


func test_done_by_the_confirm_button_on_any_card() -> void:
	if not need_rom():
		return
	var consts := (MwLineupPanel as Script).get_script_constant_map()
	assert_false(consts.has("SKIP"), "no SKIP (owner: redundant)")
	var cs := _start(MwScreens.LINEUPS, [1], [2], "exhibition", 1) as MwCharacterSelect
	_run(150)
	var top := cs.panels[0]
	var panel := cs.panels[1]
	var before := top.lineup.slots.duplicate()
	_press("ui_down", 1)
	assert_ne(top.shown(0), before[0], "Down: the card's next candidate, browsed")
	assert_eq(top.lineup.slots, before, "... not in the line-up yet")
	for i in MwLineup.POSITIONS:
		_press("ui_right", 1)
	assert_eq(top.cursor, 0, "Right goes round the six cards: DONE isn't an item")
	_press("ui_left", 1)
	assert_eq(top.cursor, MwLineup.POSITIONS - 1, "Left from C: G")
	var changed := top.lineup.slots.duplicate()
	assert_ne(changed, before, "Right committed the browsed one")
	_press("ui_accept", 1)
	assert_true(top.is_ready, "the confirm on a card: DONE")
	assert_false(panel.is_ready, "only its drivers'")
	_press("ui_accept", 2)
	assert_true(panel.is_ready)
	assert_true(_until(3))
	var session := router.session
	assert_eq(session.humans.lineups[0], changed, "team A's: changed")
	assert_eq(session.humans.lineups[1], PackedInt32Array(), "team B's: the original's")
	assert_eq(MwSelection.chosen_lineups(session), [changed, PackedInt32Array()], "for the rink's entry (plan 40, S13)")


func test_done_shows_the_drivers_confirm_glyph() -> void:
	if not need_rom():
		return
	# the keyboard used last, whatever this machine has plugged in (a gamepad
	# connected at the start is the glyphs' device until a key is pressed:
	# MwGlyphs.joy_changed - with one, player 1's confirm showed its START)
	var device := [MwGlyphs.last_device, MwGlyphs._chosen]
	MwGlyphs.last_device = -1
	MwGlyphs._chosen = true
	var cs := _start(MwScreens.LINEUPS, [1], [2], "exhibition", 1) as MwCharacterSelect
	_run(150)
	for pn in cs.panels:
		var p: int = pn.drivers[0]
		var id := MwGlyphs.player_glyph(p, "ui_accept")
		assert_ne(id, "", "P%d's confirm has a glyph" % p)
		assert_eq(pn.glyphs, PackedStringArray([id]), "P%d's own confirm" % p)
		var cells := MwGlyphs.cells(id, MwGlyphs.Style.TEXT)
		if cells.is_empty():
			continue                                 # no glyph sheets: DONE alone
		var x := pn.done_x() + 1
		var row := MwPrompts.row(MwRom.data(), MwLineupPanel.FONT, MwLineupPanel.DONE_Y)
		var text: RomPlane = pn.get_node("Text")
		for i in cells.size():
			assert_eq(int(text.cell(x + i, row)["key"]), cells[i], "the glyph beside DONE")
		var after := x + cells.size() + 1 + MwGfx.text_width(MwRom.data(), MwLineupPanel.FONT, "DONE".to_ascii_buffer())
		assert_eq(after, MwLineupPanel.DONE_END, "DONE ends the tab, a blank after it")
	# player 1 on the keyboard (no gamepad here): Enter; player 2, a gamepad: its accept
	assert_eq(cs.panels[0].glyphs[0], "vk:13")
	assert_true(cs.panels[1].glyphs[0].begins_with("pad:"))
	_press("ui_accept", 1)
	var first_text: RomPlane = cs.panels[0].get_node("Text")
	var first_cells := MwGlyphs.cells(cs.panels[0].glyphs[0], MwGlyphs.Style.TEXT)
	if not first_cells.is_empty():
		var row := MwPrompts.row(MwRom.data(), MwLineupPanel.FONT, MwLineupPanel.DONE_Y)
		assert_ne(int(first_text.cell(cs.panels[0].done_x() + 1, row)["key"]), first_cells[0], "READY instead")
	MwGlyphs.last_device = device[0]
	MwGlyphs._chosen = device[1]


func test_the_glyphs_of_several_drivers_and_online() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1, 2, 3], [], "exhibition", 1) as MwCharacterSelect
	var pn := cs.panels[0]
	assert_eq(pn.drivers, [1, 2, 3] as Array[int], "no captain: all its players drive")
	var want := PackedStringArray()
	for p in [1, 2, 3]:
		var g := MwGlyphs.player_glyph(p, "ui_accept")
		if not g in want:
			want.append(g)
	assert_eq(pn.glyphs, want, "each distinct glyph once")
	# online: a driver on this machine is its local player; one elsewhere, their device's kind
	var session := router.session
	var net := FakeNet.new()
	net.fake.add_machine("", true)
	net.fake.add_machine("peer")
	net.fake.join(0, 1, MwNetService.Device.PAD)           # P1: this machine's local 1
	net.fake.join(1, 1, MwNetService.Device.PS)            # P2: another machine's, a PlayStation pad
	net.fake.join(1, 2, MwNetService.Device.KEYS)          # P3: another machine's keyboard
	session.online = {"players": [1, 2, 3], "machines": {"1": 0, "2": 1, "3": 1}}
	session.machine = 0
	session.net = net
	session.layouts = {2: "STANDARD", 3: "GENESIS"}
	assert_eq(cs.confirm_glyphs([1] as Array[int]), PackedStringArray([MwGlyphs.player_glyph(1, "ui_accept")]))
	assert_eq(cs.confirm_glyphs([2] as Array[int]), PackedStringArray(["pad:START"]), "Start accepts in the layouts")
	assert_eq(MwGlyphs.layout_glyph("ui_accept", "STANDARD", "NS"), "pad:+", "a Nintendo pad's Start")
	assert_eq(cs.confirm_glyphs([3] as Array[int]), PackedStringArray(["vk:13"]), "the keyboard's Enter")
	session.net = null
	session.online = {}


## Down on team A's C until the browsed candidate plays another card (a
## duplicate); false when none within its list.
func _browse_to_a_duplicate(pn: MwLineupPanel, player := 1) -> bool:
	for i in pn.lineup.candidates(pn.cursor).size():
		_press("ui_down", player)
		if pn.duplicate_shown():
			return true
	return false


func test_browsing_moves_nobody_else() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1], [], "exhibition", 1) as MwCharacterSelect
	_run(150)
	var pn := cs.panels[0]
	var before := pn.lineup.slots.duplicate()
	var list := pn.lineup.candidates(0)
	assert_gt(list.size(), 2, "C has candidates to browse")
	var i := list.find(before[0])
	var dupes := 0
	for n in list.size():
		_press("ui_down", 1)
		i = posmod(i + 1, list.size())
		assert_eq(pn.cards[0].slot, list[i], "Down: the next candidate on the card")
		assert_eq(pn.lineup.slots, before, "nobody in the line-up moves while browsing")
		for k in range(1, MwLineup.POSITIONS):
			assert_eq(pn.cards[k].slot, before[k], "the other cards as they were")
		var dupe := list[i] != before[0] and list[i] in before
		assert_false(pn.cards[0].red, "the highlighted card never red")
		for k in range(1, MwLineup.POSITIONS):
			assert_eq(pn.cards[k].red, dupe and before[k] == list[i],
					"red only on the card a duplicate (%d) would swap" % list[i])
		dupes += 1 if dupe else 0
	assert_eq(pn.preview, -1, "round the list: back at the card's own, nothing browsed")
	assert_gt(dupes, 0, "the list holds the line's other skaters")
	_press("ui_up", 1)
	assert_eq(pn.cards[0].slot, list[posmod(list.find(before[0]) - 1, list.size())], "Up: the other way")
	assert_eq(pn.lineup.slots, before)
	assert_false(pn.is_ready)


## Owner, 2026-10-12: the roster's portraits carry the P1 / P2 ... tags too,
## for consistency - without character selection nobody has a position, so
## the drivers' tags ride the highlighted card, stacked as 111 stacks them
## (MwCharacterCard.tag_cell).
func test_without_character_selection_the_drivers_tags_ride_the_highlight() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1, 3], [2], "exhibition", 1) as MwCharacterSelect
	_run(150)
	var panel := cs.panels[0]
	assert_eq(panel.drivers, [1, 3] as Array[int], "no captain: both drive")
	assert_true(panel.owners.is_empty(), "nobody took a position")
	assert_eq(panel.tags(), {0: [1, 3]}, "both on the highlighted card, in their order")
	assert_eq(cs.panels[1].tags(), {0: [2]})
	for i in 2:
		var p: int = [1, 3][i]
		var at := MwCharacterCard.tag_cell(MwCharacterCard.Style.COMPACT, i, 2)
		assert_ne(panel._tags[p].cell(MwLineupPanel.CARD_X[0] + at.x, MwLineupPanel.CARD_Y + at.y)["key"], 0,
				"P%d drawn over the portrait, %s" % [p, "left" if i == 0 else "right"])
	_press("ui_right", 3)
	assert_eq(panel.cursor, 1)
	assert_eq(panel.tags(), {1: [1, 3]}, "they follow the highlight")
	assert_eq(panel._tags[1].cell(MwLineupPanel.CARD_X[0], MwLineupPanel.CARD_Y + MwCharacterCard.ROWS - 1)["key"], 0,
			"gone from the card left")


func test_a_duplicate_in_red_swaps_on_accept() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1], [], "exhibition", 1) as MwCharacterSelect
	_run(150)
	var pn := cs.panels[0]
	var before := pn.lineup.slots.duplicate()
	assert_true(_browse_to_a_duplicate(pn), "a duplicate among C's candidates")
	var dupe := pn.preview
	var was := before.find(dupe)
	# owner, 2026-10-12: the red shows the card accepting would swap
	assert_eq(pn.cards[was].text.modulate, MwCharacterCard.RED, "the card he plays now in red: it would swap")
	assert_eq(pn.cards[0].text.modulate, Color.WHITE, "the highlighted card in its colour")
	assert_eq(pn.cards[was].slot, dupe, "... still showing him")
	assert_eq(pn.swap_card(), was)
	assert_eq(pn.lineup.slots, before, "no swap yet")
	_press("ui_accept", 1)
	var want := before.duplicate()
	want[0] = dupe
	want[was] = before[0]
	assert_eq(pn.lineup.slots, want, "accept: committed, the two swapped")
	assert_eq([pn.cards[0].slot, pn.cards[was].slot], [dupe, before[0]], "both cards show it")
	assert_false(pn.cards[was].red, "the usual colour again")
	assert_eq(pn.cards[was].text.modulate, Color.WHITE)
	assert_eq(pn.swap_card(), -1)
	assert_eq(pn.preview, -1)
	assert_false(pn.is_ready, "committing isn't DONE")
	assert_eq(pn.cursor, 0, "still on the card")
	_press("ui_accept", 1)
	assert_true(pn.is_ready, "the next accept: DONE")
	assert_true(_until(3))
	assert_eq(router.session.humans.lineups[0], want, "the committed line-up kept")


func test_left_or_right_commits_the_browsed_one() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1], [], "exhibition", 1) as MwCharacterSelect
	_run(150)
	var pn := cs.panels[0]
	var before := pn.lineup.slots.duplicate()
	assert_true(_browse_to_a_duplicate(pn), "a duplicate among C's candidates")
	var dupe := pn.preview
	var was := before.find(dupe)
	_press("ui_right", 1)
	assert_eq(pn.cursor, 1, "Right: the next card")
	assert_eq(pn.lineup.slots[0], dupe, "and the browsed one in")
	assert_eq(pn.lineup.slots[was], before[0], "swapped as accept would")
	assert_false(pn.cards[was].red, "committed: no red")
	var now := pn.lineup.slots.duplicate()
	_press("ui_down", 1)
	var browsed := pn.preview
	assert_ne(browsed, -1)
	_press("ui_left", 1)
	assert_eq(pn.cursor, 0, "Left: the card before")
	assert_eq(pn.lineup.slots[1], browsed, "Left commits too")
	var j := now.find(browsed)
	if j >= 0:
		assert_eq(pn.lineup.slots[j], now[1], "with the swap")
	for k in MwLineup.POSITIONS:
		assert_eq(pn.lineup.slots.count(pn.lineup.slots[k]), 1, "six different characters")


func test_back_reverts_the_browsed_one_not_the_menu() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1], [], "exhibition", 1) as MwCharacterSelect
	_run(150)
	var pn := cs.panels[0]
	var before := pn.lineup.slots.duplicate()
	assert_true(_browse_to_a_duplicate(pn))
	_press("ui_back", 1)
	assert_eq(pn.preview, -1, "Back: the change backed out of")
	assert_eq(pn.cards[0].slot, before[0], "the card's own character back")
	for card in pn.cards:
		assert_false(card.red)
	assert_eq(pn.lineup.slots, before)
	_run(60)
	assert_eq(router.current_id(), MwScreens.LINEUPS, "not out of the menu")
	assert_false(pn.is_ready)
	_press("ui_back", 1)
	assert_true(_until(MwScreens.CONTROLLER_SELECT), "nothing browsed: Back leaves as before")


func test_ready_commits_the_browsed_one() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1], [2], "exhibition", 1) as MwCharacterSelect
	_run(150)
	var top := cs.panels[0]
	var panel := cs.panels[1]
	var before := top.lineup.slots.duplicate()
	assert_true(_browse_to_a_duplicate(top))
	var dupe := top.preview
	_press("ui_down", 2)
	assert_ne(panel.preview, -1, "team B browsing too")
	# online, a panel whose drivers' machines are all away is READY: its
	# browsed candidate is committed first, as DONE would leave it
	var input := MwInputFrame.new()
	input.away = {1: MwTickInput.LAGGING}
	cs._panels_pass(1, input)
	assert_true(top.is_ready, "its drivers away: READY")
	assert_eq(top.preview, -1)
	assert_eq(top.lineup.slots[0], dupe, "the browsed one committed")
	assert_eq(top.lineup.slots[before.find(dupe)], before[0], "with the swap")
	assert_false(panel.is_ready, "the other panel's driver is here")
	assert_ne(panel.preview, -1, "... still browsing")
	var bs := panel.lineup.slots.duplicate()
	_press("ui_accept", 2)
	_press("ui_accept", 2)
	assert_true(panel.is_ready)
	assert_ne(panel.lineup.slots, bs, "the browsed one in before DONE")
	assert_true(_until(3))
	assert_eq(router.session.humans.lineups, [top.lineup.slots, panel.lineup.slots], "the committed line-ups")


func test_back_during_the_crash_only_lands_them() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1], [2], "exhibition", 1) as MwCharacterSelect
	assert_false(cs.panels[0].landed())
	_press("ui_back", 1)
	assert_true(cs.panels[0].landed() and cs.panels[1].landed(), "a press lands them")
	_run(30)
	assert_eq(router.current_id(), MwScreens.LINEUPS, "and does nothing else")
	_press("ui_accept", 2)
	assert_true(cs.panels[1].is_ready)


func test_back_leaves_for_the_controller_selection_and_comes_again() -> void:
	if not need_rom():
		return
	var kept := PackedInt32Array([6, 1, 2, 3, 4, 5])
	var cs := _start(MwScreens.LINEUPS, [1], [2], "exhibition", 1, func(session: MwSession) -> void:
		session.humans.lineups[0] = kept
		session.lineup_teams = [session.setup.team_a, session.setup.team_b]) as MwCharacterSelect
	_run(150)
	assert_eq(cs.panels[0].lineup.slots, kept, "the last game's")
	_press("ui_down", 2)
	_press("ui_accept", 2)
	assert_false(cs.panels[1].is_ready, "accept on a browsed candidate: committed, not DONE")
	_press("ui_accept", 2)
	assert_true(cs.panels[1].is_ready)
	_press("ui_down", 1)
	_press("ui_back", 1)
	_run(30)
	assert_eq(router.current_id(), MwScreens.LINEUPS, "Back on a browsed candidate: only the change backed out of")
	assert_eq(cs.panels[0].lineup.slots, kept)
	_press("ui_back", 1)
	assert_true(_until(MwScreens.CONTROLLER_SELECT), "Back on a panel that isn't READY: the controller selection")
	var h := router.session.humans
	assert_eq(h.lineups, [kept, PackedInt32Array()], "the line-ups as before the screen opened")
	assert_eq([h.team_of(1), h.team_of(2)], [0, 1], "everyone where they were")
	_go_on_from_the_controller_selection()
	assert_true(_until(MwScreens.LINEUPS), "on again: the line-ups")
	cs = router.current() as MwCharacterSelect
	assert_eq(cs.panels.size(), 2)
	assert_eq(cs.panels[0].lineup.slots, kept, "as they were")
	assert_false(cs.panels[0].is_ready or cs.panels[1].is_ready, "nobody READY")


func test_back_from_the_panels_after_character_selection() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.CHARACTER_SELECT, [1, 2, 3, 4, 5], [], "exhibition", 1) as MwCharacterSelect
	for p in [1, 2, 3, 4, 5]:
		_press("ui_accept", p)
		_press("ui_accept", p)
	_run(MwCharacterSelect.READY_TICKS + 2)
	assert_eq(cs.stage, MwCharacterSelect.Stage.PANELS)
	assert_eq(router.session.humans.positions.size(), 5, "the picks made")
	_run(150)
	_press("ui_back", 3)
	assert_true(_until(MwScreens.CONTROLLER_SELECT), "any driver's Back")
	var h := router.session.humans
	assert_eq(h.positions, {}, "the positions as the screen found them")
	assert_eq(h.lineups, [PackedInt32Array(), PackedInt32Array()])
	_go_on_from_the_controller_selection()
	assert_true(_until(MwScreens.CHARACTER_SELECT), "on again: character selection first")


func test_a_ready_taken_back() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.LINEUPS, [1], [], "exhibition", 1) as MwCharacterSelect
	_run(150)
	_press("ui_accept", 1)
	assert_true(cs.panels[0].is_ready)
	_press("ui_back", 1)
	assert_false(cs.panels[0].is_ready, "Back takes READY back")
	_run(60)
	assert_eq(router.current_id(), MwScreens.LINEUPS, "still here")


# --- the flow ----------------------------------------------------------------------------------------------

func test_the_controller_selection_leads_to_character_selection() -> void:
	if not need_rom():
		return
	router = rig.make(self, MwSession.new(1, 1))
	host = rig.host
	router.session.local_mode = "exhibition"
	router.session.humans = MwHumans.new()
	for p in [1, 2, 3, 4, 5]:
		router.session.humans.set_team(p, 0 if p < 4 else 1)
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(MwScreens.CONTROLLER_SELECT)
	scene.screen_id = MwScreens.CONTROLLER_SELECT
	router.adopt(scene)
	router.fader.uncover()
	_run(20)
	_press("ui_accept", 1, 6)
	assert_true(_until(MwScreens.CHARACTER_SELECT), "five players: character selection")


func test_next_game_starts_from_the_last_picks() -> void:
	if not need_rom():
		return
	var cs := _start(MwScreens.CHARACTER_SELECT, [1, 2, 3], [4, 5], "exhibition", 1, func(session: MwSession) -> void:
		session.humans.positions = {1: 4, 2: 0, 4: 5}
		session.humans.lineups[0] = PackedInt32Array([6, 1, 2, 3, 4, 5])
		session.lineup_teams = [session.setup.team_a, session.setup.team_b]) as MwCharacterSelect
	assert_eq([cs.cursor[1], cs.cursor[2], cs.cursor[4]], [4, 0, 5], "the last positions")
	assert_eq(cs.picks[1], MwCharacterSelect.Pick.MOVING, "unlocked")
	assert_eq(cs.lineups[0].slots, PackedInt32Array([6, 1, 2, 3, 4, 5]), "the last characters")


## net-mock's bots (owner, 2026-10-12: the person always ended up the goalie,
## a forward to be left free - the centre, 2026-10-13): told to leave a
## position free (NetBot.leave_free, net-mock's --position: the centre by
## default) they take every other one on their team first, across the rows
## too, and leave it to the person - who takes it; a team of bots alone still
## fills all six.
func test_net_mocks_bots_leave_the_centre_to_the_person() -> void:
	if not need_rom():
		return
	const Machines := preload("res://test/net/net_machines.gd")
	var session := MwSession.new(1, 1)
	var bot := Machines.NetBot.new()
	router = rig.make(self, session, bot)
	host = rig.host
	session.local_mode = "exhibition"
	session.humans = MwHumans.new()
	for p in range(1, 13):
		session.humans.set_team(p, 0 if p % 2 == 1 else 1)    # as net-mock's: odd numbers team A
	const YOU := 11                                    # (team A's last: the cursor starts on G)
	var bots: Array = range(1, 13).filter(func(p: int) -> bool: return p != YOU)
	bot.router = router
	bot.players.assign(bots)
	bot.leave_free = 0
	var cs := MwRouter.instantiate_scene(MwScreens.CHARACTER_SELECT) as MwCharacterSelect
	cs.screen_id = MwScreens.CHARACTER_SELECT
	router.adopt(cs)
	router.fader.uncover()
	bot.screen = MwScreens.CHARACTER_SELECT
	bot.entered = router.tick
	assert_eq(int(cs.cursor[YOU]), 5, "the person's cursor starts on the goalie")
	var bots_locked := func() -> bool:
		return bots.all(func(p: int) -> bool: return cs.picks.get(p) == MwCharacterSelect.Pick.LOCKED)
	for i in 1200:
		if bots_locked.call():
			break
		bot.tick()
		router.step()
	assert_true(bots_locked.call(), "every bot locked a position")
	assert_eq((cs.taken[0] as Dictionary).size(), 5, "five of the person's team's six taken")
	assert_false((cs.taken[0] as Dictionary).has(0), "the centre left to the person")
	assert_eq((cs.taken[1] as Dictionary).size(), 6, "the bots' own team: all six, the centre last")
	# the person goes to the centre and takes it
	for i in 12:
		var at := int(cs.cursor[YOU])
		if at == 0:
			break
		bot.pulse(MwVerbs.player_action(YOU, "ui_down" if at >= 3 else "ui_right"), 3)
		for k in 8:
			bot.tick()
			router.step()
	assert_eq(int(cs.cursor[YOU]), 0, "the person's cursor on the centre")
	for i in 2:
		bot.pulse(MwVerbs.player_action(YOU, "ui_accept"), 3)
		for k in 8:
			bot.tick()
			router.step()
	assert_eq((cs.taken[0] as Dictionary).get(0), YOU, "the centre the person's")


## ... and the person's cursor starts on it (owner, 2026-10-13: still only the
## goalie for the person, the centre wanted - the bots left the centre, but
## the person's cursor started on the goalie's card, their team's last
## player's): net-mock's host seats the person in the start record
## (NetBot.seat_person: their side by number, the centre as the position they
## last played), the bots join their sides on the controller selection as
## before - and the person, accepting twice at once, has the centre; the bots
## lock every other card.
func test_net_mocks_person_starts_on_the_centre() -> void:
	if not need_rom():
		return
	const Machines := preload("res://test/net/net_machines.gd")
	const YOU := 12                                    # (team B's last: the goalie's card unseated)
	var record := {"players": {"humans": MwHumans.new().to_record()}}
	Machines.NetBot.seat_person(record, YOU, 0)
	var session := MwSession.new(1, 1)
	var bot := Machines.NetBot.new()
	router = rig.make(self, session, bot)
	host = rig.host
	session.local_mode = "exhibition"
	session.humans = MwHumans.from_record((record["players"] as Dictionary)["humans"])
	assert_eq(session.humans.team_of(YOU), 1, "the person seated on team B, by number")
	assert_eq(session.humans.positions.get(YOU), 0, "with the centre as their last position")
	var bots: Array = range(1, 12)
	for p: int in bots:
		session.humans.set_team(p, 0 if p % 2 == 1 else 1)    # the bots, on the controller selection
	bot.router = router
	bot.players.assign(bots)
	bot.leave_free = 0
	var cs := MwRouter.instantiate_scene(MwScreens.CHARACTER_SELECT) as MwCharacterSelect
	cs.screen_id = MwScreens.CHARACTER_SELECT
	router.adopt(cs)
	router.fader.uncover()
	bot.screen = MwScreens.CHARACTER_SELECT
	bot.entered = router.tick
	assert_eq(int(cs.cursor[YOU]), 0, "the person's cursor starts on the centre")
	assert_true([2, 4, 6, 8, 10].all(func(p: int) -> bool: return int(cs.cursor[p]) != 0),
			"the person's team's bots on the other cards")
	for i in 2:
		bot.pulse(MwVerbs.player_action(YOU, "ui_accept"), 3)
		for k in 8:
			bot.tick()
			router.step()
	assert_eq((cs.taken[1] as Dictionary).get(0), YOU, "the centre the person's")
	assert_eq(cs.picks[YOU], MwCharacterSelect.Pick.LOCKED, "locked")
	var bots_locked := func() -> bool:
		return bots.all(func(p: int) -> bool: return cs.picks.get(p) == MwCharacterSelect.Pick.LOCKED)
	for i in 1200:
		if bots_locked.call():
			break
		bot.tick()
		router.step()
	assert_true(bots_locked.call(), "every bot locked a position")
	assert_eq([(cs.taken[0] as Dictionary).size(), (cs.taken[1] as Dictionary).size()], [6, 6], "every card taken")
