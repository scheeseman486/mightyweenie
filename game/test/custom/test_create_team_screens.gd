extends "res://test/rom/rom_test_base.gd"
## CREATE-A-TEAM's screens (plan 38): the front menu's entry, the team
## list, the editor's pages, the text entry, saving, copying and deleting -
## walked through the router with the menu verbs, the bank in a test folder.

const TEST_DIR := "user://test_create_team_screens"

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad


var _dir := ""


func before_all() -> void:
	super.before_all()
	_dir = MwCustomTeams.dir                      # (the run's test folder, pre_run.gd: put back after)


func before_each() -> void:
	MwCustomTeams.clear()
	MwCustomTeams.dir = TEST_DIR
	MwSettings.bindings = {}
	MwSettings.layouts = {}
	MwInputMap.install()


func after_each() -> void:
	MwSound.trace = Callable()
	MwSound.driver = null
	MwEditorMusic.on = false
	if host:
		rig.free_host()
		host = null
	MwCustomTeams.clear()
	MwCustomTeams.dir = _dir
	var d := DirAccess.open(TEST_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(TEST_DIR)


func _start(id: int) -> void:
	router = rig.make(self, MwSession.new(1, 1))
	host = rig.host
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(id)
	scene.screen_id = id
	router.adopt(scene, {})
	router.fader.uncover()


func _run(ticks: int) -> void:
	rig.run(ticks)


func _press(action: String, after := 6) -> void:
	rig.hold({action: true}, 2, after)


func _until(id: int, limit := 1500) -> bool:
	return rig.until(id, limit, 4)


func _screen() -> Node:
	return router.current()


## Goes to the row whose action is [param action] on the screen's page.
func _go(action: String) -> void:
	var screen: Variant = _screen()
	for k in 30:
		if screen.rows[screen.row]["action"] == action:
			return
		_press("ui_down", 2)
	fail_test("no row %s on %s" % [action, screen.page])


## Types [param text] on the text entry: the old text taken back with the
## pads' ERASE LETTER, the new one on the keyboard (its key events), DONE.
func _type(text: String) -> void:
	assert_eq(router.current_id(), MwScreens.TEXT_ENTRY)
	var te: MwTextEntry = _screen()
	while te.field.text != "":
		_press("ui_erase_letter", 2)
	for c in text:
		var event := InputEventKey.new()
		event.unicode = c.unicode_at(0)
		event.pressed = true
		te.key(event)
	_press("ui_password_done")
	_run(30)


func test_copy_an_original_rename_it_and_save() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(10)
	_press("ui_down")
	_press("ui_accept")
	assert_true(_until(MwScreens.CREATE_A_TEAM), "the front menu's CREATE-A-TEAM")
	var screen: Variant = _screen()
	assert_eq(screen.rows.map(func(r): return r.action), ["new", "copy_original"])
	_press("ui_down")
	_press("ui_right")
	var from: int = screen.copy_from
	assert_ne(from, 0, "COPY A TEAM: another original")
	_press("ui_accept")
	assert_true(_until(MwScreens.EDIT_TEAM), "the editor")
	assert_not_null(MwCustomTeams.editing)
	screen = _screen()
	assert_eq(screen.page, "edit")
	assert_eq(screen.id, MwCustomTeams.editing_id())
	assert_eq(MwCustomTeams.editing.name, MwCustomTeam.from_original(MwRom.archive().bytes(), from).name)
	_go("info")
	_press("ui_accept")
	assert_eq(screen.page, "info")
	_go("name")
	_press("ui_accept")
	assert_true(_until(MwScreens.TEXT_ENTRY))
	_type("TESTERS")
	assert_eq(router.current_id(), MwScreens.EDIT_TEAM)
	assert_eq(MwCustomTeams.editing.name, "TESTERS")
	assert_eq(MwGfx.rom_string(MwRom.data(), MwTeams.name(MwRom.data(), screen.id)).get_string_from_ascii(), "TESTERS",
			"the game reads the working copy")
	_go("skulls")
	var sk: int = MwCustomTeams.editing.skulls
	_press("ui_left")
	assert_eq(MwCustomTeams.editing.skulls, maxi(sk - 1, 0))
	_press("ui_back")
	assert_eq(screen.page, "edit")
	_go("save")
	_press("ui_accept")
	assert_true(_until(MwScreens.CREATE_A_TEAM), "saved: the list")
	assert_eq(MwCustomTeams.count(), 1)
	assert_null(MwCustomTeams.editing)
	assert_true(FileAccess.file_exists(TEST_DIR.path_join(MwCustomTeams.teams[0].id + ".json")))
	assert_eq(MwCustomTeams.teams[0].name, "TESTERS")
	screen = _screen()
	assert_eq(screen.rows.size(), 3)


func test_new_team_roster_players_plays_and_delete() -> void:
	if not need_rom():
		return
	_start(MwScreens.CREATE_A_TEAM)
	_run(20)
	_press("ui_accept")                       # NEW TEAM: its city, then its name
	assert_true(_until(MwScreens.TEXT_ENTRY))
	_type("NOWHERE")
	assert_true(_until(MwScreens.TEXT_ENTRY), "then the name")
	_type("NOBODIES")
	assert_true(_until(MwScreens.EDIT_TEAM))
	var screen: Variant = _screen()
	var team: MwCustomTeam = MwCustomTeams.editing
	assert_eq([team.city, team.name], ["NOWHERE", "NOBODIES"])
	# the roster: a new goalie in line 1's G slot, then a skater picked from an original
	_go("roster")
	_press("ui_accept")
	assert_eq(screen.page, "roster")
	for i in 5:
		_press("ui_down", 2)
	assert_eq(screen.cursor, 5)
	_press("ui_editor_delete")               # NEW
	assert_eq(screen.page, "player")
	assert_true(screen._player().is_goalie(), "a new player in the G column is a goalie")
	var actions: Array = screen.rows.map(func(r): return r.action)
	assert_false("p_species" in actions, "a goalie has one species: no row")
	assert_false("p_enforcer" in actions, "and is never an enforcer")
	_press("ui_editor_next")                 # his ratings
	assert_eq(screen.page, "ratings")
	var speed: int = screen._player().ratings["speed"]
	_go("rating")
	_press("ui_down", 2)                       # SPEED
	_press("ui_right")
	assert_eq(screen._player().ratings["speed"], mini(speed + 1, 10))
	_press("ui_back")
	assert_eq(screen.page, "roster")
	assert_true(team.roster[5].has("player"))
	_press("ui_up", 2)                         # RD
	_press("ui_editor_copy")                 # PICK A PLAYER
	assert_eq(screen.page, "pick")
	_press("ui_editor_next")
	assert_eq(screen.pick_team, 1)
	_press("ui_accept")
	assert_eq(screen.page, "roster")
	assert_eq(team.roster[4], {"team": 1, "slot": 4}, "team 1's line 1 RD")
	_press("ui_back")
	# the plays: no play twice, special 2 kept
	_go("plays")
	_press("ui_accept")
	assert_eq(screen.page, "plays")
	for i in 6:
		_press("ui_right", 2)
		_press("ui_down", 2)
	var plays := Array(team.nasty) + Array(team.specials)
	for v in plays:
		assert_eq(plays.count(v), 1)
	assert_eq(team.specials[1], 10)
	_press("ui_back")
	_go("save")
	_press("ui_accept")
	assert_true(_until(MwScreens.CREATE_A_TEAM))
	assert_eq(MwCustomTeams.count(), 1)
	# delete it: ARE YOU SURE? NO first, then YES
	screen = _screen()
	_go("team")
	_press("ui_editor_delete")
	assert_true(screen.confirm.active, "ARE YOU SURE? (plan 40, M4a: the box every screen asks in)")
	assert_eq(screen.confirm.sure, 1, "NO first")
	_press("ui_accept")
	assert_false(screen.confirm.active)
	assert_eq(screen.page, "list")
	assert_eq(MwCustomTeams.count(), 1, "NO kept it")
	_press("ui_editor_delete")
	_press("ui_up")
	_press("ui_accept")
	assert_eq(MwCustomTeams.count(), 0, "YES deleted it")
	assert_eq(DirAccess.get_files_at(TEST_DIR).size(), 0)


func test_leaving_without_saving_asks() -> void:
	if not need_rom():
		return
	_start(MwScreens.CREATE_A_TEAM)
	_run(10)
	_press("ui_down")
	_press("ui_accept")
	assert_true(_until(MwScreens.EDIT_TEAM))
	_press("ui_back")
	var screen: Variant = _screen()
	assert_true(screen.confirm.active, "a new team isn't saved yet: ARE YOU SURE?")
	_press("ui_up")
	_press("ui_accept")
	assert_true(_until(MwScreens.CREATE_A_TEAM))
	assert_null(MwCustomTeams.editing)
	assert_eq(MwCustomTeams.count(), 0)
	_press("ui_back")
	assert_true(_until(MwScreens.FRONT_MENU))


func test_list_scrolls_with_arrows_past_three_teams() -> void:
	if not need_rom():
		return
	var plain := MwRom.archive().bytes()
	for t in 5:
		MwCustomTeams.save(MwCustomTeam.from_original(plain, t))
	_start(MwScreens.CREATE_A_TEAM)
	_run(10)
	var screen: Variant = _screen()
	var up: RomSprite = screen._arrows[0]
	var down: RomSprite = screen._arrows[1]
	assert_eq(MwCreateTeam.list_shown(3), 3, "three teams all show")
	assert_eq(MwCreateTeam.list_shown(5), 2, "more: two and the arrows")
	assert_false(up.visible, "nothing above")
	assert_true(down.visible, "teams below")
	assert_eq(down.position.x, 160.0, "alone: centred")
	_go("team")
	assert_eq(screen.list_top, 0)
	for k in 4:
		_press("ui_down", 2)
	assert_eq(screen.rows[screen.row]["team"], 4, "the last team")
	assert_eq(screen.list_top, 3, "scrolled to it")
	assert_true(up.visible, "teams above")
	assert_false(down.visible, "none below")
	assert_eq(screen.rows[screen.row]["y"], MwCreateTeam.LIST_FIRST + 2, "the second row shown")
	_press("ui_up", 2)
	_press("ui_up", 2)
	assert_eq(screen.list_top, 2)
	assert_true(up.visible and down.visible, "both")
	assert_eq(up.position.y, float(MwCreateTeam.LIST_ARROW_TOP), "the up arrow hangs from the top")
	assert_eq(down.position.y, float(MwCreateTeam.LIST_ARROW_TOP + MwPortMenu.ARROW_W), "the down one stands under it")
	assert_lt(up.position.x, down.position.x, "side by side")
	_press("ui_accept")
	assert_true(_until(MwScreens.EDIT_TEAM), "the editor")
	var editor: Variant = _screen()
	assert_false(editor._arrows[0].visible or editor._arrows[1].visible, "no arrows off the list")


func test_list_switches_teams_on_and_off() -> void:
	if not need_rom():
		return
	var plain := MwRom.archive().bytes()
	for t in 2:
		MwCustomTeams.save(MwCustomTeam.from_original(plain, t))
	_start(MwScreens.CREATE_A_TEAM)
	_run(10)
	var screen: Variant = _screen()
	_go("team")
	var team: MwCustomTeam = screen.listed[int(screen.rows[screen.row]["team"])]
	assert_true(screen._label(screen.rows[screen.row]).begins_with("ON  "), "the indicator before the team")
	_press("ui_right", 2)
	assert_false(team.enabled, "owner: switched off in the list")
	assert_true(screen._label(screen.rows[screen.row]).begins_with("OFF "))
	assert_eq(MwCustomTeams.count(), 1, "out of the game")
	assert_eq(screen.listed.size(), 2, "still in the list")
	assert_eq(screen.rows[screen.row]["action"], "team", "the selection stays on it")
	var file: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_DIR.path_join(team.id + ".json")))
	assert_eq(file.get("enabled"), false, "kept in its file")
	_press("ui_left", 2)
	assert_true(team.enabled, "on again")
	assert_eq(MwCustomTeams.count(), 2)
	_press("ui_right", 2)
	_press("ui_accept")
	assert_true(_until(MwScreens.EDIT_TEAM), "an off team edits")
	assert_eq(_screen().id, MwTeams.COUNT + 1, "read past the bank's one team on")
	_go("save")
	_press("ui_accept")
	assert_true(_until(MwScreens.CREATE_A_TEAM), "saved: the list")
	screen = _screen()
	assert_eq(MwCustomTeams.count(), 1, "saved, still off")
	assert_eq(screen.listed.size(), 2)
	assert_eq(screen.rows[screen.row]["action"], "team", "back on its row")
	assert_false(screen.listed[int(screen.rows[screen.row]["team"])].enabled)


func test_ratings_run_down_each_column_with_an_enforcer() -> void:
	if not need_rom():
		return
	var plain := MwRom.archive().bytes()
	MwCustomTeams.save(MwCustomTeam.from_original(plain, 0))
	_start(MwScreens.CREATE_A_TEAM)
	_run(10)
	_go("team")
	_press("ui_accept")
	assert_true(_until(MwScreens.EDIT_TEAM))
	var screen: Variant = _screen()
	_go("roster")
	_press("ui_accept")
	_press("ui_accept")                       # line 1's centre: a copy of his own
	assert_eq(screen.page, "player")
	_go("p_enforcer")
	if not screen._player().enforcer:
		_press("ui_right")
	assert_true(screen._player().enforcer)
	_press("ui_editor_next")
	assert_eq(screen.page, "ratings")
	var order: Array = screen.rows.map(func(r): return [r.action, r.x])
	var left := order.filter(func(o): return o[1] == 1).map(func(o): return o[0])
	assert_eq(left, ["rating", "rating", "rating", "rating", "rating", "p_aggression", "p_weapon", "p_overall"],
			"the left column top to bottom, OVERALL last")
	var first_right := order.find(order.filter(func(o): return o[1] == 21)[0])
	assert_eq(order.slice(first_right, first_right + 7).map(func(o): return o[0]),
			["rating", "rating", "rating", "rating", "rating", "p_instinct", "p_bonus"], "then the right column")
	assert_eq(first_right, 7, "after the whole left column")


func test_hold_repeats_a_number_faster_and_faster() -> void:
	var repeat := MwHoldRepeat.new()
	var held := MwInputFrame.make({"ui_right": true}, {})
	assert_eq(repeat.step(held, 1, true), 0, "the press: the screen's own step")
	var total := 0
	var first := -1
	for t in 400:
		var n := repeat.step(MwInputFrame.make({"ui_right": true}, {"ui_right": true}), 1, true)
		total += n
		if n != 0 and first < 0:
			first = t
	assert_eq(first, MwHoldRepeat.DELAY - 1, "repeats after the delay")
	assert_gt(total, 150, "and speeds up to a step a tick")
	assert_eq(repeat.step(MwInputFrame.make({}, {"ui_right": true}), 1, true), 0, "let go: none")
	assert_eq(repeat.step(held, 1, false), 0, "not a number: none")


func test_name_colours_row() -> void:
	if not need_rom():
		return
	MwCustomTeams.save(MwCustomTeam.from_original(MwRom.archive().bytes(), 2))
	_start(MwScreens.CREATE_A_TEAM)
	_run(10)
	_go("team")
	_press("ui_accept")
	assert_true(_until(MwScreens.EDIT_TEAM))
	var screen: Variant = _screen()
	var team := MwCustomTeams.editing
	_go("colours")
	_press("ui_accept")
	_go("name_colours")
	assert_eq(screen._value(screen.rows[screen.row]), "STANDARD")
	_press("ui_accept")
	assert_eq(team.name_colours, team.kit.slice(0, 2), "its own, from the shirt's")
	assert_eq(screen.name_text.palette.colours()[18], team.kit[0])
	_press("ui_right")
	_press("ui_accept")
	assert_eq(screen.page, "colour")
	_press("ui_right")
	assert_ne(team.name_colours[1], team.kit[1], "edited apart from the shirt")
	assert_eq(screen.name_text.palette.colours()[19], team.name_colours[1], "the header's letters take it")
	assert_eq(screen.palette.colours()[19], team.kit[1], "the page's line keeps the shirt")
	_press("ui_accept")
	_press("ui_editor_delete")
	assert_true(team.name_colours.is_empty(), "back to the game's")


## The editor's music (owner, 2026-10-10: CREATE-A-TEAM's menus play the
## team information music): the team description's - the menus'
## music stopped (`$C768`), its crowd sequence `$10` - from the front menu's
## CREATE-A-TEAM through the list, the text entry and the editor, kept going
## (never restarted from the start, never stopped); back on the front menu
## it stops and the front menu's own comes back. The sound driver's model
## answers whether the crowd still plays.
func test_the_editor_plays_the_team_descriptions_music() -> void:
	if not need_rom():
		return
	var calls := []
	_start(MwScreens.FRONT_MENU)
	assert_eq(MwSound.driver, router.audio, "the router's own driver model (plan 40, D6)")
	MwSound.trace = func(what: String, args: Array, result: Variant) -> void: calls.append([what, args, result])
	_run(10)
	_press("ui_down")
	_press("ui_accept")
	assert_true(_until(MwScreens.CREATE_A_TEAM), "the front menu's CREATE-A-TEAM")
	var names := calls.map(func(c: Array) -> String: return c[0])
	var fade := calls.find(["music_fade_out", [1], null])
	assert_gt(fade, -1, "the menus' music stops, as the team description's does")
	var crowd := calls.filter(func(c: Array) -> bool: return c[0] == "play" and c[1] == [MwEditorMusic.MUSIC])
	assert_eq(crowd.size(), 1, "then the team description's crowd sequence")
	if crowd.is_empty():
		return
	assert_gt(calls.find(crowd[0]), fade)
	var handle: int = crowd[0][2]
	assert_true(MwSound.busy(handle), "playing")
	calls.clear()
	_press("ui_accept")                       # NEW TEAM: the text entry, then the editor
	assert_true(_until(MwScreens.TEXT_ENTRY))
	_run(60)
	assert_true(MwSound.busy(handle), "on under the text entry")
	_type("MUSIC")
	assert_true(_until(MwScreens.TEXT_ENTRY))
	_type("TOWNS")
	assert_true(_until(MwScreens.EDIT_TEAM))
	_run(120)
	names = calls.map(func(c: Array) -> String: return c[0])
	for n in ["music_fade_out", "music_title", "music_game", "stop"]:
		assert_false(n in names, "nothing stops or replaces it in the editor: no " + n)
	assert_eq(calls.filter(func(c: Array) -> bool: return c[0] == "play" and c[1] == [MwEditorMusic.MUSIC]).size(), 0,
			"kept, not started again")
	assert_true(MwSound.busy(handle), "still the same")
	calls.clear()
	_press("ui_back")                        # LEAVE WITHOUT SAVING? YES, then the front menu
	_press("ui_up")
	_press("ui_accept")
	assert_true(_until(MwScreens.CREATE_A_TEAM))
	assert_true(MwSound.busy(handle), "the list: still on")
	_press("ui_back")
	assert_true(_until(MwScreens.FRONT_MENU))
	var stop := calls.find(["stop", [handle], null])
	var title := calls.find(["music_title", [], null])
	assert_gt(stop, -1, "the front menu: the crowd stops")
	assert_gt(title, stop, "and the front menu's own music comes back")
	assert_false(MwEditorMusic.on)


## Plan 40 (M5, owner: the starfield fades or cuts only towards a screen
## without one, and the stars keep moving): the front menu,
## CREATE-A-TEAM's list, its editor and the text entry over them change by
## cuts - never a fade to black, the page's layers fading out and in, the
## stars going on where they were and the same way, the menus' logo staying
## put between the front menu and the list; the editor's stars move; the
## rink editor (no stars) still fades.
func test_cuts_between_the_starfield_screens() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(10)
	var menu: MwPortMenu = _screen()
	while menu.row != 1:
		_press("ui_down", 2)
	assert_eq(menu.rows[menu.row].action, "create")
	pad.held = {"ui_accept": true}
	var seen := _watch(MwScreens.CREATE_A_TEAM)
	_stars_go_on(seen, "front menu -> list")
	assert_true(seen.any(func(r: Array) -> bool: return r[3] > 0.0 and r[3] < 1.0), "the page fades")
	assert_true(seen.all(func(r: Array) -> bool: return r[4] == 1.0), "the logo stays put")
	# NEW TEAM: the text entry (city, name) by cuts, then the editor
	pad.held = {"ui_accept": true}
	seen = _watch(MwScreens.TEXT_ENTRY)
	_stars_go_on(seen, "list -> text entry")
	_type("TOWNS")
	seen = _watch(MwScreens.TEXT_ENTRY)
	_stars_go_on(seen, "the city -> the name")
	_type("TOWNIES")
	seen = _watch(MwScreens.EDIT_TEAM)
	_stars_go_on(seen, "the name -> the editor")
	assert_eq(seen[-1][4], 0.0, "the editor: the logo gone")
	var screen: Variant = _screen()
	var before: Array = screen.starfield.state()
	_run(20)
	assert_ne(screen.starfield.state(), before, "the editor's stars keep moving")
	# Back, LEAVE WITHOUT SAVING? YES: the list, then the front menu
	_press("ui_back")
	assert_true(screen.confirm.active)
	_press("ui_up")
	pad.held = {"ui_accept": true}
	seen = _watch(MwScreens.CREATE_A_TEAM)
	_stars_go_on(seen, "the editor -> the list")
	pad.held = {"ui_back": true}
	seen = _watch(MwScreens.FRONT_MENU)
	_stars_go_on(seen, "the list -> the front menu")
	assert_true(seen.all(func(r: Array) -> bool: return r[4] == 1.0), "the logo stays put")


## Steps (the pad's held verbs let go after 3 ticks) until screen [param id]
## shows with its page all in: each tick [screen, the fader's coverage, the
## stars' state, the page's alpha, the logo's alpha].
func _watch(id: int, limit := 600) -> Array:
	var out := []
	for i in limit:
		router.step()
		if i == 3:
			pad.held = {}
		var screen: Variant = router.current()
		var stars: Array = screen.starfield.state() if screen != null and "starfield" in screen \
				and screen.starfield != null else []
		var a: float = screen.page_layers.self_modulate.a if screen != null and "page_layers" in screen else 1.0
		var logo: float = screen.logo_plane.modulate.a if screen != null and "logo_plane" in screen \
				and screen.logo_plane != null else 0.0
		out.append([router.current_id(), router.fader.coverage(), stars, a, logo])
		if router.current_id() == id and not router.busy() and a >= 1.0 and i > 3:
			break
	assert_eq(out[-1][0], id, "reached screen %d" % id)
	return out


## No fade to black, and every tick the stars a whole number of steps on
## from where they were, the same way.
func _stars_go_on(seen: Array, what: String) -> void:
	var prev: Array = []
	for r: Array in seen:
		assert_eq(r[1], 0.0, what + ": no fade to black")
		var st: Array = r[2]
		if not st.is_empty() and not prev.is_empty():
			assert_eq([st[2], st[3]], [prev[2], prev[3]], what + ": the stars the same way")
			var vx: int = st[2]
			var vy: int = st[3]
			var ok := false
			for k in 4:
				ok = ok or (st[0] - prev[0] == k * vx and st[1] - prev[1] == k * vy)
			assert_true(ok, what + ": the stars on from where they were")
		prev = st


## Plan 40 (M5): the rink editor has no stars - the editor fades to it.
func test_the_rink_editor_still_fades() -> void:
	if not need_rom():
		return
	_start(MwScreens.CREATE_A_TEAM)
	_run(10)
	_press("ui_down")                        # COPY A TEAM
	_press("ui_accept")
	assert_true(_until(MwScreens.EDIT_TEAM))
	_go("rink")
	pad.held = {"ui_accept": true}
	var covered := false
	for i in 200:
		router.step()
		if i == 3:
			pad.held = {}
		covered = covered or router.fader.coverage() > 0.0
		if router.current_id() == MwScreens.HOME_RINK:
			break
	assert_eq(router.current_id(), MwScreens.HOME_RINK)
	assert_true(covered, "a fade to black")


## Goes to row [param i] of the screen's page.
func _go_row(i: int) -> void:
	var screen: Variant = _screen()
	for k in 30:
		if screen.row == i:
			return
		_press("ui_down", 2)
	fail_test("no row %d on %s" % [i, screen.page])


## Types [param text] on the text entry in place of what it holds.
func _type_over(text: String) -> void:
	assert_eq(router.current_id(), MwScreens.TEXT_ENTRY)
	var te: MwTextEntry = _screen()
	te.field.set_text("")
	for c in text:
		var event := InputEventKey.new()
		event.unicode = c.unicode_at(0)
		event.pressed = true
		te.key(event)
	_press("ui_password_done")
	_run(30)


## SPEECHES (owner, 2026-10-14: speeches could be viewed but not edited or
## made, and the item acted as a selection, which it is not): an editor -
## Left / Right change nothing; Accept opens the occasions, an occasion's
## situations (one of its own: straight to its lines), a situation's lines.
## Editing a line makes the situation his own (the original's lines copied
## first), NEW LINE adds one, deleting them all gives him the original's
## again, and ORIGINAL (asked first) puts an occasion back. The game reads
## his lines as he types them; the coach page's sample says one.
func test_speeches_are_edited_not_picked() -> void:
	if not need_rom():
		return
	MwCustomTeams.save(MwCustomTeam.from_original(MwRom.archive().bytes(), 2))
	_start(MwScreens.CREATE_A_TEAM)
	_run(10)
	_go("team")
	_press("ui_accept")
	assert_true(_until(MwScreens.EDIT_TEAM))
	var screen: Variant = _screen()
	var team := MwCustomTeams.editing
	var style := team.coach.style
	_go("coach")
	_press("ui_accept")
	assert_eq(screen.page, "coach")
	_go("coach_speeches")
	assert_eq(screen._value(screen.rows[screen.row]), "ORIGINAL")
	_press("ui_right")
	_press("ui_left")
	_press("ui_left")
	assert_eq(team.coach.style, style, "not a choice")
	_press("ui_accept")
	assert_eq(screen.page, "speeches")
	assert_eq(screen.rows.size(), MwCoachSpeeches.OCCASIONS.size())
	assert_true(screen.portrait.visible, "his portrait beside them")
	_go_row(7)
	_press("ui_accept")
	assert_eq(screen.page, "situations", "GOAL: its situations")
	_go_row(3)
	_press("ui_accept")
	assert_eq(screen.page, "lines", "HAT TRICK: its lines")
	var originals := MwCoachSpeeches.original_lines(MwRom.archive().bytes(), 7, 3, style)
	assert_gt(originals.size(), 0)
	assert_eq(screen.rows.size(), originals.size() + 1, "the original's lines and NEW LINE")
	_go_row(0)
	_press("ui_accept")
	assert_true(_until(MwScreens.TEXT_ENTRY))
	var te: MwTextEntry = _screen()
	assert_eq(te.field.lines, 6, "as many lines as the rink's speech box")
	assert_eq(te.field.width, 34)
	assert_eq(te.field.note(), MwCoachSpeeches.TOKENS_NOTE)
	assert_eq(te.field.text, MwCoachSpeeches.clean_line(originals[0]), "the line as it was")
	_type_over("#them can't stop us")
	assert_eq(router.current_id(), MwScreens.EDIT_TEAM)
	assert_eq(screen.page, "lines", "back on the lines")
	var own: PackedStringArray = team.coach.speeches.get("7.3", PackedStringArray())
	assert_eq(own.size(), originals.size())
	assert_eq(own[0], "#THEM CAN'T STOP US")
	assert_eq(own.slice(1), originals.slice(1), "the rest copied from the original")
	var v := MwRom.data()
	assert_ne(MwCustomOverlay.coach_speech_set(v, MwTeams.coach(v, screen.id), 7, 3), 0, "the game reads them")
	_go("speech_new")
	_press("ui_accept")
	assert_true(_until(MwScreens.TEXT_ENTRY))
	_type_over("One more for the #US")
	own = team.coach.speeches["7.3"]
	assert_eq(own.size(), originals.size() + 1)
	assert_eq(own[own.size() - 1], "ONE MORE FOR THE #US", "a new line, capitals as the editor's texts")
	# deleting them all: the original's again
	_go_row(0)
	for k in own.size():
		_press("ui_editor_delete")
	assert_false(team.coach.speeches.has("7.3"), "none left: the original's")
	assert_eq(screen.rows.size(), originals.size() + 1)
	_go_row(0)
	_press("ui_accept")
	assert_true(_until(MwScreens.TEXT_ENTRY))
	_type_over("#them can't stop us")
	_press("ui_back")
	assert_eq(screen.page, "situations")
	assert_eq(screen._value(screen.rows[screen.row]), "OWN")
	_press("ui_back")
	assert_eq(screen.page, "speeches")
	assert_eq(screen._value(screen.rows[screen.row]), "1 OF 6 OWN")
	_go_row(6)
	_press("ui_accept")
	assert_eq(screen.page, "lines", "PENALTY: one situation, its lines straight away")
	_press("ui_back")
	assert_eq(screen.page, "speeches")
	_go_row(0)
	_press("ui_back")
	assert_eq(screen.page, "coach")
	_go("coach_speeches")
	assert_eq(screen._value(screen.rows[screen.row]), "1 OF 32 OWN")
	assert_eq(screen._sample_speech(), MwCoachSpeeches.expanded("#THEM CAN'T STOP US", team.name, team.city,
			MwTeams.name_text(MwRom.data(), team.playoff_place)), "the sample: one of his own")
	_press("ui_accept")
	_go_row(7)
	_press("ui_editor_delete")
	assert_true(screen.confirm.active, "ORIGINAL asks first")
	_press("ui_up")
	_press("ui_accept")
	assert_true(team.coach.speeches.is_empty(), "the goal's original lines again")
