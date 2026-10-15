extends "res://test/rom/rom_test_base.gd"
## The port's own menus (plan 21): the front menu after the title, options,
## controller bindings, Menu Back through the setup screens, the credits
## from the menu, the attract demo from its idle; settings saved to a test
## file (never the player's).
## Short names: m the MwPortMenu under test.

## Test input: the actions held now (the router turns them into presses).
const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad
var _saved := []


func before_all() -> void:
	super.before_all()
	_saved = [MwSettings.path, MwSettings.camera, MwSettings.enhance_audio, MwSettings.bindings,
			MwSettings.front_menu, MwAudio.free_music_samples, MwAudio.free_effects,
			MwSettings.fullscreen, MwSettings.layouts, MwSettings.analogue, MwSettings.sticks, MwSettings.aspect,
			MwSettings.character_select, MwSettings.captain_mode, MwSettings.lineup_select, MwSettings.replay_length,
			MwSettings.shot_heights, MwSettings.tick_rate, MwSettings.blood, MwSettings.ice_detail,
			MwSettings.reflections]
	MwSettings.path = "user://test_port_menu_%d.cfg" % Time.get_ticks_usec()
	MwSettings.front_menu = true


func after_all() -> void:
	if FileAccess.file_exists(MwSettings.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.path = _saved[0]
	MwSettings.camera = _saved[1]
	MwSettings.enhance_audio = _saved[2]
	MwSettings.apply_audio()                 # the switches it drives, as they were
	MwSettings.bindings = _saved[3]
	MwSettings.front_menu = _saved[4]
	MwAudio.free_music_samples = _saved[5]
	MwAudio.free_effects = _saved[6]
	MwSettings.fullscreen = _saved[7]
	MwSettings.layouts = _saved[8]
	MwSettings.analogue = _saved[9]
	MwSettings.sticks = _saved[10]
	MwSettings.aspect = _saved[11]
	MwSettings.character_select = _saved[12]
	MwSettings.captain_mode = _saved[13]
	MwSettings.lineup_select = _saved[14]
	MwSettings.replay_length = _saved[15]
	MwSettings.shot_heights = _saved[16]
	MwSettings.tick_rate = _saved[17]
	MwSettings.blood = _saved[18]
	MwSettings.ice_detail = _saved[19]
	MwSettings.reflections = _saved[20]
	MwInputMap.install()


func before_each() -> void:
	MwSettings.camera = 0
	MwSettings.enhance_audio = true
	MwSettings.fullscreen = false
	MwSettings.aspect = "ORIGINAL"
	MwSettings.analogue = true
	MwSettings.shot_heights = false
	MwSettings.tick_rate = "OVERCLOCKED"
	MwSettings.blood = true
	MwSettings.ice_detail = true
	MwSettings.reflections = true
	MwSettings.bindings = {}
	MwSettings.layouts = {}
	MwSettings.sticks = {}
	MwInputMap.install()


func after_each() -> void:
	if host:
		rig.free_host()
		host = null


## A router with screen [param id] adopted (uncovered).
func _start(id: int, data := {}) -> void:
	router = rig.make(self, MwSession.new(1, 1))
	host = rig.host
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(id)
	scene.screen_id = id
	if id == 0:
		router.fader.cover()
	router.adopt(scene, data)
	if id != 0:
		router.fader.uncover()


func _run(ticks: int) -> void:
	rig.run(ticks)


## Press [param action] for 3 ticks, then let go and wait [param after] ticks.
func _press(action: String, after := 10) -> void:
	rig.hold({action: true}, 3, after)


## Run until screen [param id] is on (and settled: 80 ticks past its entry).
func _until(id: int, limit := 3000) -> bool:
	return rig.until(id, limit, 40)


func _menu() -> MwPortMenu:
	return router.current() as MwPortMenu


func test_the_title_leads_to_the_front_menu_and_back() -> void:
	if not need_rom():
		return
	_start(0)
	_run(60)
	_press("ui_accept", 60)                   # the developer logo
	assert_true(_until(0), "the title")
	_press("ui_accept")
	assert_true(_until(MwScreens.FRONT_MENU), "the title's fade-out -> the front menu, not the credits")
	assert_eq(router.history.slice(-2), [0, MwScreens.FRONT_MENU])
	assert_eq(_menu().row, 0, "START GAME selected")
	_press("ui_back")
	assert_true(_until(0), "Menu Back -> the title")
	var title := router.current() as MwTitleScreen
	assert_ne(title.part, MwTitleScreen.Part.LOGO, "without the developer logo")
	_press("ui_accept", 40)
	assert_true(_until(MwScreens.FRONT_MENU))


func test_front_menu_items_and_back_from_the_setup_screens() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(20)
	_press("ui_accept")
	assert_true(_until(MwScreens.PLAY_MODE), "START GAME -> PLAY MODE (plan 34)")
	_press("ui_accept")
	assert_true(_until(MwScreens.LOCAL_PLAY), "LOCAL PLAY")
	_press("ui_accept")
	assert_true(_until(1), "EXHIBITION -> the game setup")
	assert_eq(router.session.local_mode, "exhibition")
	_press("ui_back")
	assert_true(_until(MwScreens.LOCAL_PLAY), "Menu Back -> LOCAL PLAY")
	_press("ui_back")
	assert_true(_until(MwScreens.PLAY_MODE))
	_press("ui_back")
	assert_true(_until(MwScreens.FRONT_MENU), "-> the front menu")
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "CREATE-A-TEAM")
	_press("ui_accept")
	assert_true(_until(MwScreens.CREATE_A_TEAM), "CREATE-A-TEAM (plan 38)")
	_press("ui_back")
	assert_true(_until(MwScreens.FRONT_MENU))
	_press("ui_down")
	_press("ui_down")                         # (owner: the team descriptions third, OPTIONS fourth)
	assert_eq(_menu().row, 3)
	assert_eq(_menu().rows[_menu().row].label, "OPTIONS")
	_press("ui_accept")
	assert_true(_until(MwScreens.OPTIONS), "OPTIONS")
	_press("ui_back")
	assert_true(_until(MwScreens.FRONT_MENU))
	assert_eq(_menu().row, 3, "the row it left from")
	for i in 4:
		_press("ui_up")
	assert_eq(_menu().row, 6, "wraps to QUIT GAME")
	_press("ui_up")
	assert_eq(_menu().rows[_menu().row].label, "CREDITS")
	_press("ui_accept")
	assert_true(_until(0), "CREDITS -> the credits roll")
	assert_true((router.current() as MwTitleScreen).part >= MwTitleScreen.Part.CREDITS_LOAD)
	_run(200)
	_press("ui_accept")
	assert_true(_until(MwScreens.FRONT_MENU), "a press: back to the front menu")


func test_only_accept_selects() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(20)
	_press("ui_down")
	_press("ui_down")
	_press("ui_down")
	_press("ui_skip")                         # another screen's verb: nothing here
	assert_eq(router.current_id(), MwScreens.FRONT_MENU)
	_press("ui_accept")                       # Enter, Start or the pad's south button
	assert_true(_until(MwScreens.OPTIONS), "OPTIONS")
	_press("ui_accept")
	assert_true(_until(MwScreens.VISUALS), "VISUALS")
	_press("ui_accept")                       # CAMERA is a choice: nothing happens
	assert_eq(MwSettings.camera, 0)
	assert_eq(router.current_id(), MwScreens.VISUALS)


func test_quit_game_fades_out_then_closes() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(20)
	var m := _menu()
	assert_eq(m.rows.map(func(r): return r.action), ["start", "create", "teams", "options", "replays", "credits", \
			"quit"],
			"owner: the team descriptions before OPTIONS")
	assert_eq(m.rows[1].label, "CREATE-A-TEAM", "plan 38")
	assert_eq(m.rows[2].label, MwPortMenu.label_text(m.rom, "@mode:4+S"), "the original's words, plural")
	assert_eq(m.rows[3].label, "OPTIONS")
	var quits := [0]
	m.quit_game = func() -> void: quits[0] += 1
	_press("ui_up", 0)                        # wraps to the last item
	assert_eq(m.rows[m.row].label, "QUIT GAME")
	_press("ui_accept", 10)
	assert_eq(quits[0], 0, "fading out first")
	assert_true(router.fader.busy() or router.fader.coverage() > 0.0, "the screen fades")
	pad.held = {"ui_down": true}             # no menu while it goes
	_run(40)
	pad.held = {}
	_run(10)
	assert_eq(quits[0], 1, "then the game closes, once")
	assert_eq(m.row, 6)
	assert_eq(router.current_id(), MwScreens.FRONT_MENU)
	assert_almost_eq(router.fader.coverage(), 1.0, 0.001, "black")


func test_options_change_and_are_saved() -> void:
	if not need_rom():
		return
	_start(MwScreens.VISUALS)
	_run(10)
	assert_eq(_menu().rows.map(func(r): return r.label),
			["CAMERA", "DISPLAY", "ASPECT RATIO", "ABACABB MODE", "DETAILED ICE", "REFLECTIONS"], "the owner's words")
	_press("ui_right")
	assert_eq(MwSettings.camera_name(), "3D")
	_press("ui_right")
	assert_eq(MwSettings.camera_name(), "2D EXTENDED", "plan 44: the third camera")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "2D EXTENDED")
	_press("ui_right")
	assert_eq(MwSettings.camera_name(), "3D EXTENDED", "plan 34's the fourth")
	_press("ui_right")
	assert_eq(MwSettings.camera_name(), "2D", "wraps")
	_press("ui_left")
	assert_eq(MwSettings.camera_name(), "3D EXTENDED", "and back")
	_press("ui_left")
	_press("ui_left")
	assert_eq(MwSettings.camera_name(), "3D")
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "DISPLAY")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "WINDOWED")
	_press("ui_right")
	assert_true(MwSettings.fullscreen, "full screen (the window itself only with a display)")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "FULLSCREEN")
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "ASPECT RATIO")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "ORIGINAL", "the original's by default")
	_press("ui_right")
	assert_eq(MwSettings.aspect, "WIDE")
	assert_true(MwSettings.wide())
	_press("ui_right")
	assert_eq(MwSettings.aspect, "ORIGINAL", "wraps")
	_press("ui_left")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "WIDE")
	# the 3D view's (owner, 2026-10-10): on by default, Left / Right flip them
	for spec: Array in [["ABACABB MODE", "blood"], ["DETAILED ICE", "ice_detail"], ["REFLECTIONS", "reflections"]]:
		_press("ui_down")
		assert_eq(_menu().rows[_menu().row].label, spec[0])
		assert_eq(_menu()._value(_menu().rows[_menu().row]), "ON", spec[0] + ": on by default")
		_press("ui_right")
		assert_false(_switch(spec[1]), spec[0] + ": off")
		assert_eq(_menu()._value(_menu().rows[_menu().row]), "OFF")
		_press("ui_left")
		assert_true(_switch(spec[1]), spec[0] + ": on again")
		_press("ui_left")
		assert_false(_switch(spec[1]))
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "CAMERA", "round to the first row")
	_press("ui_back")
	assert_true(_until(MwScreens.OPTIONS), "Menu Back -> OPTIONS")
	_press("ui_down")
	_press("ui_accept")
	assert_true(_until(MwScreens.MODIFIERS), "GAMEPLAY MODIFIERS")
	assert_eq(_menu().rows.map(func(r): return r.label),
			["ENHANCE AUDIO", "REPLAY LENGTH", "REPLAY BLOOD", "TICK RATE", "CHARACTER SELECT", "CAPTAIN MODE",
			"LINE-UP SELECT", "EXTENDED PENALTIES", "EXTENDED CPU"], "plan 44's two after them; REPLAY BLOOD")
	_press("ui_left")
	assert_false(MwSettings.enhance_audio)
	assert_false(MwAudio.free_music_samples or MwAudio.free_effects, "the audio switches follow")
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "REPLAY LENGTH")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "FULL GAME", "the whole match by default (plan 28)")
	_press("ui_right")
	assert_eq(MwSettings.replay_length, "ORIGINAL")
	assert_false(MwSettings.full_replays())
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "REPLAY BLOOD")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "OFF", "off by default (owner, 2026-10-15)")
	var replay_paint := MwSettings.replay_paint
	_press("ui_right")
	assert_true(MwSettings.replay_paint, "on")
	_press("ui_left")
	assert_false(MwSettings.replay_paint, "off again")
	MwSettings.replay_paint = replay_paint
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "TICK RATE")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "OVERCLOCKED", "a pass every 2 ticks by default (plan 36)")
	_press("ui_right")
	assert_eq(MwSettings.tick_rate, "APPROXIMATED")
	_press("ui_right")
	assert_eq(MwSettings.tick_rate, "ORIGINAL")
	assert_eq(MwSettings.rink_tick_rate(false), "ORIGINAL")
	_press("ui_down")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "5+ PLAYERS", "the brief's gate by default")
	_press("ui_right")
	assert_eq(MwSettings.character_select, "3+ ON A TEAM")
	_press("ui_down")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "5+ PLAYERS")
	_press("ui_right")
	assert_eq(MwSettings.captain_mode, "2+ PLAYERS")
	_press("ui_down")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "ON")
	_press("ui_right")
	assert_false(MwSettings.lineup_select)
	_press("ui_back")
	assert_true(_until(MwScreens.OPTIONS))
	_press("ui_down")
	_press("ui_accept")
	assert_true(_until(MwScreens.CONTROLS), "CONTROLS")
	assert_eq(_menu().rows.map(func(r): return r.label), ["ANALOG CONTROL", "SHOT HEIGHT BUTTONS", \
			"CONTROLLER BINDINGS"],
			"the owner's spelling")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "ON", "on by default")
	_press("ui_right")
	assert_false(MwSettings.analogue)
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "OFF")
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "SHOT HEIGHT BUTTONS")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "OFF", "the original's by default")
	assert_true(InputMap.action_get_events("p1_shot_high").is_empty(), "off: HIGH SHOT has no inputs")
	_press("ui_right")
	assert_true(MwSettings.shot_heights)
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "ON")
	assert_false(InputMap.action_get_events("p1_shot_high").is_empty(), "on: the input map gives it its inputs")
	MwSettings.camera = 0
	MwSettings.enhance_audio = true
	MwSettings.fullscreen = false
	MwSettings.aspect = "ORIGINAL"
	MwSettings.analogue = true
	MwSettings.shot_heights = false
	MwSettings.replay_length = "FULL GAME"
	MwSettings.character_select = "5+ PLAYERS"
	MwSettings.captain_mode = "5+ PLAYERS"
	MwSettings.lineup_select = true
	MwSettings.tick_rate = "OVERCLOCKED"
	MwSettings.blood = true
	MwSettings.ice_detail = true
	MwSettings.reflections = true
	MwSettings.load_file()
	assert_eq([MwSettings.camera_name(), MwSettings.enhance_audio, MwSettings.fullscreen, MwSettings.aspect,
			MwSettings.analogue, MwSettings.shot_heights, MwSettings.replay_length, MwSettings.character_select,
			MwSettings.captain_mode, MwSettings.lineup_select, MwSettings.tick_rate],
			["3D", false, true, "WIDE", false, true, "ORIGINAL", "3+ ON A TEAM", "2+ PLAYERS", false, "ORIGINAL"],
			"saved")
	assert_eq([MwSettings.blood, MwSettings.ice_detail, MwSettings.reflections], [false, false, false],
			"ABACABB MODE, DETAILED ICE, REFLECTIONS saved")
	MwSettings.blood = true
	MwSettings.ice_detail = true
	MwSettings.reflections = true
	MwSettings.replay_length = "FULL GAME"
	MwSettings.shot_heights = false
	MwSettings.character_select = "5+ PLAYERS"
	MwSettings.captain_mode = "5+ PLAYERS"
	MwSettings.lineup_select = true
	MwSettings.tick_rate = "OVERCLOCKED"
	_press("ui_down")
	_press("ui_accept")
	assert_true(_until(MwScreens.BINDINGS), "CONTROLLER BINDINGS")
	_press("ui_back")
	assert_true(_until(MwScreens.CONTROLS), "Menu Back -> CONTROLS")


## The VISUALS page's 3D switches (owner, 2026-10-11: ABACABB MODE,
## DETAILED ICE, REFLECTIONS) by their action.
func _switch(action: String) -> bool:
	match action:
		"blood":
			return MwSettings.blood
		"ice_detail":
			return MwSettings.ice_detail
	return MwSettings.reflections


## ABACABB MODE, DETAILED ICE and REFLECTIONS (owner, 2026-10-11: each on
## by default): on with no settings file and with one from before them;
## the page holds its six rows as GAMEPLAY MODIFIERS does - two rows apart
## from CHOICE_Y, the last one's highlight frame on the screen, every label
## and value in the frame in either font.
func test_the_visuals_switches_default_on_and_the_page_fits() -> void:
	if not need_rom():
		return
	var path := MwSettings.path
	MwSettings.path = "user://test_port_menu_none_%d.cfg" % Time.get_ticks_usec()
	MwSettings.blood = false
	MwSettings.ice_detail = false
	MwSettings.reflections = false
	MwSettings.load_file()
	assert_eq([MwSettings.blood, MwSettings.ice_detail, MwSettings.reflections], [true, true, true],
			"no settings file: on")
	var old := ConfigFile.new()
	old.set_value("display", "aspect", "WIDE")
	old.save(MwSettings.path)
	MwSettings.blood = false
	MwSettings.ice_detail = false
	MwSettings.reflections = false
	MwSettings.load_file()
	assert_eq([MwSettings.blood, MwSettings.ice_detail, MwSettings.reflections, MwSettings.aspect],
			[true, true, true, "WIDE"], "a file from before them: on")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.path = path
	MwSettings.aspect = "ORIGINAL"
	_start(MwScreens.MODIFIERS)
	_run(10)
	var modifiers := _menu().rows.slice(0, MwPortMenu.CHOICES_SHOWN).map(func(r): return r.y)
	host.free()
	host = null
	_start(MwScreens.VISUALS)
	_run(10)
	var m := _menu()
	assert_eq(m.rows.size(), 6)
	assert_eq(m.rows.slice(0, MwPortMenu.CHOICES_SHOWN).map(func(r): return r.y), modifiers,
			"spaced as GAMEPLAY MODIFIERS")
	for i in m.rows.size():
		assert_eq(int(m.rows[i].y), MwPortMenu.CHOICE_Y + 2 * i)
	for i in 5:
		_press("ui_down")
	assert_eq(m.row, 5, "REFLECTIONS selected")
	var y: int = m.rows[5].y
	assert_lt(y + 1, 28, "its frame's bottom edge on the screen (28 rows)")
	assert_ne(int(m.plane.cell(MwPortMenu.ROW_X - 1, y + 1)["key"]), 0, "the frame drawn there")
	assert_ne(int(m.plane.cell(MwPortMenu.ROW_X + MwPortMenu.ROW_W, y + 1)["key"]), 0, "to its right corner")
	for r: Dictionary in m.rows.slice(3):
		for font: int in [MwPortMenu.FONT_LIGHT, MwPortMenu.FONT_DARK]:
			for v: String in MwPortMenu.OFF_ON:
				var room: int = MwPortMenu.ROW_W - m._width(font, (r.label as String).to_ascii_buffer()) - 2
				assert_true(m._width(font, v.to_ascii_buffer()) <= room, "%s %s: in the frame" % [r.label, v])


## Rows: PLAYER, LAYOUT, CONTROLS (the page), then the page's verbs.
## The pages' titles on the pause menu's plate (owner: the player line's
## widget re-used, in its grey): the same cells MwGlyphs.black_label draws,
## on the title's layer, centred to half a cell, line 3's black there the
## rink window's $222.
func test_the_pages_titles_sit_on_the_pause_menus_plate() -> void:
	if not need_rom():
		return
	var bytes := MwRom.data()
	for page: Array in [[MwScreens.OPTIONS, "options", MwPortMenu.OPTIONS_TITLE_Y],
			[MwScreens.VISUALS, "visuals", MwPortMenu.OPTIONS_TITLE_Y],
			[MwScreens.MODIFIERS, "modifiers", MwPortMenu.OPTIONS_TITLE_Y],
			[MwScreens.CONTROLS, "controls", MwPortMenu.OPTIONS_TITLE_Y],
			[MwScreens.PLAY_MODE, "play_mode", MwPortMenu.OPTIONS_TITLE_Y],
			[MwScreens.LOCAL_PLAY, "local_play", MwPortMenu.OPTIONS_TITLE_Y],
			[MwScreens.CONTINUE, "continue", MwPortMenu.OPTIONS_TITLE_Y],
			[MwScreens.BINDINGS, "bindings", MwPortMenu.BINDINGS_TITLE_Y]]:
		page[1] = MwPortMenu.label_text(bytes, MwPortMenu.TITLES[page[1]])
		_start(page[0])
		_run(10)
		var m := _menu()
		var y: int = page[2]
		var b := (page[1] as String).to_ascii_buffer()
		var twice_x := 40 - MwGlyphs.text_width(m.rom, MwPortMenu.FONT_LIGHT, b)
		var on: RomPlane = m.get("_plate")
		assert_eq(on.position.x, 4.0 * (twice_x % 2), "centred to half a cell")
		assert_eq((on.palette as RomPalette).build(m.rom)[53], 0x222, "the plate's grey, as the pause menu's")
		assert_eq(m.palette.build(m.rom)[53], 0, "the screen's own black unchanged")
		var want := RomPlane.new()
		want.tiles = on.tiles
		want.palette = on.palette
		add_child_autofree(want)
		@warning_ignore("integer_division")
		var x := (twice_x - twice_x % 2) / 2
		var end := MwGlyphs.black_label(want, m.rom, MwPortMenu.FONT_LIGHT, b, x, y, MwPortMenu.TEXT_ATTR)
		for cy in range(y - 1, y + 2):
			for cx in range(x - 1, end + 1):
				assert_eq(on.cell(cx, cy), want.cell(cx, cy), "%s: cell (%d, %d) as the plate's" % [page[1], cx, cy])
		assert_ne(int(on.cell(x - 1, y)["key"]), 0, "%s: the plate's rounded end" % page[1])
		host.free()
		host = null


func _verb_row(m: MwPortMenu, verb: String) -> int:
	for i in m.rows.size():
		if m.rows[i].get("verb", "") == verb:
			return i
	return -1


## Moves the selection to row [param to].
func _go(m: MwPortMenu, to: int) -> void:
	while m.row != to:
		_press("ui_down" if m.row < to else "ui_up", 2)


## Turns the CONTROLS row to page [param title].
func _page(m: MwPortMenu, title: String) -> void:
	_go(m, 2)
	for i in MwVerbs.PAGES.size():
		if MwVerbs.PAGES[m.bind_page][0] == title:
			return
		_press("ui_right", 2)
	fail_test("no page " + title)


func _key_event(code: Key, down := true) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = down
	return k


## Cells in use on [param plane] along row [param y].
func _cells_on(plane: RomPlane, y: int) -> int:
	var n := 0
	for x in 40:
		if int(plane.cell(x, y)["key"]) != 0:
			n += 1
	return n


## The game setup's top hangs above the pages, only its arch in view
## (owner); not on the bindings page, whose title is up there.
func test_the_game_setups_top_hangs_above_the_pages() -> void:
	if not need_rom():
		return
	for id: int in [MwScreens.FRONT_MENU, MwScreens.PLAY_MODE, MwScreens.LOCAL_PLAY, MwScreens.OPTIONS,
			MwScreens.BINDINGS]:
		_start(id)
		_run(4)
		var m := router.current() as MwPortMenu
		assert_eq(m.top.modulate.a, 0.0 if id == MwScreens.BINDINGS else 1.0, "page %d" % id)
		assert_eq(m.logo_plane.modulate.a, 0.0 if id == MwScreens.BINDINGS else 1.0, "the logo too")
		assert_eq(m.top.position.y, -float(MwPortMenu.TOP_HANG))
		assert_gt(m.top.get_used_cells().size(), 0)
		for c in m.top.get_used_cells():
			assert_false(MwPortMenu.LOGO.has_point(c), "the logo's hole kept")
			if MwPortMenu.LOGO.has_point(c):
				break
		host.queue_free()
		host = null


func test_the_bindings_pages_list_the_verbs() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	assert_eq(m.rows.slice(0, 3).map(func(r): return r.label), ["PLAYER", "LAYOUT", "CONTROLS"])
	assert_eq([m._value(m.rows[0]), m._value(m.rows[1]), m._value(m.rows[2])],
			["1  " + MwInputMap.device_tag(1), "STANDARD", "MENUS"], "the player with their device's tag (plan 34)")
	assert_eq(m.rows.slice(3).map(func(r): return r.verb), MwVerbs.PAGES[0][1], "the menus' verbs")
	assert_eq(MwPortMenu.binding_text(1, "ui_accept"), "ENTER / PAD1 START", "the defaults shown")
	assert_eq(MwPortMenu.binding_text(1, "ui_back"), "ESCAPE / PAD1 B")
	assert_eq(MwPortMenu.binding_text(1, "ui_skip"), "Z / PAD1 X")
	_page(m, "GAMEPLAY")
	var gameplay: Array = MwVerbs.PAGES[1][1].filter(func(v: String) -> bool: return not v in MwVerbs.SHOT_HEIGHTS)
	assert_eq(m.rows.slice(3).map(func(r): return r.verb), gameplay, "no shot heights while their option is off")
	assert_eq(MwPortMenu.binding_text(1, "pass"), "X / PAD1 A")
	MwSettings.shot_heights = true
	MwInputMap.install()
	m._build_rows()
	assert_eq(m.rows.slice(3).map(func(r): return r.verb), MwVerbs.PAGES[1][1], "on: HIGH / LOW SHOT listed")
	assert_eq(MwPortMenu.binding_text(1, "shot_high"), "A / PAD1 RT", "the right trigger (A: player 1's key)")
	assert_eq(MwPortMenu.binding_text(1, "shot_low"), "SHIFT / PAD1 LT", "the left trigger")
	MwSettings.shot_heights = false
	MwInputMap.install()
	m._build_rows()
	_press("ui_left", 2)
	assert_eq(m._value(m.rows[2]), "MENUS", "Left: the page before")
	_press("ui_left", 2)
	assert_eq(m.bind_page, MwVerbs.PAGES.size() - 1, "wraps")
	_press("ui_back")
	assert_true(_until(MwScreens.CONTROLS))
	_go(_menu(), _menu().rows.size() - 1)     # CONTROLLER BINDINGS
	_press("ui_accept")
	assert_true(_until(MwScreens.BINDINGS))
	assert_eq(_menu().bind_page, MwVerbs.PAGES.size() - 1, "the page remembered")


func test_binding_a_verb() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	_page(m, "GAMEPLAY")
	_go(m, _verb_row(m, "move_down"))
	_press("ui_accept")
	assert_eq(m.capturing, "move_down", "waiting for an input")
	_press("ui_back")
	assert_eq(router.current_id(), MwScreens.BINDINGS, "Menu Back while waiting does not leave")
	var event := InputEventJoypadButton.new()
	event.device = 2
	event.button_index = JOY_BUTTON_Y
	event.pressed = true
	m._input(event)
	assert_eq(m.capturing, "")
	assert_true(MwInputMap._same(MwSettings.binding(1, "move_down"), MwInputMap.normalized(event)),
			"player 1's SKATE DOWN = pad 3's Y")
	var ev := InputMap.action_get_events("p1_move_down")
	assert_eq(ev.size(), 2, "one input per verb, and the stick")
	assert_true(ev[1] is InputEventJoypadMotion and ev[1].axis == JOY_AXIS_LEFT_Y, "the left stick stays")
	assert_eq(MwPortMenu.binding_text(1, "move_down"), "PAD3 Y")
	_run(10)
	_go(m, 0)
	_press("ui_right")
	assert_eq(m.player, 2, "Right on PLAYER: the next player")
	assert_eq(m.bind_page, 1, "the same page")
	_go(m, _verb_row(m, "move_down"))
	_press("ui_accept")
	assert_eq(m.capturing, "move_down")
	m._input(_key_event(KEY_K))
	assert_true(MwInputMap._same(MwSettings.binding(2, "move_down"), MwInputMap.normalized(_key_event(KEY_K))),
			"any device for any player")
	_run(10)
	_press("ui_accept")
	_run(MwPortMenu.CAPTURE_TICKS + 5)
	assert_eq(m.capturing, "", "nothing pressed: given up")
	_press("ui_back")
	assert_true(_until(MwScreens.CONTROLS))


func test_the_layout_row_starts_a_player_afresh() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	MwSettings.set_binding(1, "ui_skip", _key_event(KEY_Q))
	assert_eq(MwPortMenu.binding_text(1, "ui_skip"), "Q")
	_go(m, 1)
	_press("ui_right")
	assert_eq(m._value(m.rows[1]), "GENESIS")
	assert_eq(MwSettings.layout(1), "GENESIS")
	assert_eq(MwPortMenu.binding_text(1, "ui_skip"), "Z / PAD1 X", "the player's bindings gone")
	assert_eq(MwPortMenu.binding_text(1, "ui_back"), "ESCAPE / PAD1 BACK", "Genesis: Back on Select")
	assert_eq(MwSettings.layout(2), "STANDARD", "the other players keep theirs")
	MwSettings.layouts = {}
	MwSettings.load_file()
	assert_eq(MwSettings.layout(1), "GENESIS", "saved")
	_press("ui_left")
	assert_eq(MwSettings.layout(1), "STANDARD")


func test_a_collision_is_shown_red() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	_page(m, "GAMEPLAY")
	var pass_row := _verb_row(m, "pass")
	var shot_row := _verb_row(m, "wrist_shot")
	var slap_row := _verb_row(m, "slap_shot")
	var check_row := _verb_row(m, "check")
	var change_row := _verb_row(m, "change_player")
	assert_eq(_cells_on(m._red, m.rows[pass_row].y), 0, "no collisions by default")
	_go(m, pass_row)
	_press("ui_accept")
	m._input(_key_event(KEY_C))              # wrist shot's key
	_run(10)
	assert_eq(MwPortMenu.binding_text(1, "pass"), "C", "bound to both")
	_go(m, check_row)                         # PASS to CHECK all shown
	assert_eq(m.scroll, pass_row - 3, "PASS the first shown")
	assert_gt(_cells_on(m._red, m.rows[pass_row].y), 0, "PASS's input in red")
	assert_gt(_cells_on(m._red, m.rows[shot_row].y), 0, "WRIST SHOT's too")
	assert_gt(_cells_on(m._red, m.rows[slap_row].y), 0, "and SLAP SHOT's (C's hold)")
	assert_eq(_cells_on(m._red, m.rows[change_row].y), 0, "CHANGE PLAYER's not")
	assert_true(InputMap.action_has_event("p1_pass", _key_event(KEY_C)))
	assert_true(InputMap.action_has_event("p1_wrist_shot", _key_event(KEY_C)), "both keep the input")


func test_a_stick_row_binds_a_whole_stick() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	var at := _verb_row(m, "ui_stick")
	assert_eq(m.rows[at].label, "STICK", "the menus' page has a stick row")
	assert_eq(MwPortMenu.stick_text(1, "ui_stick"), "PAD1 LS", "the left stick by default")
	_page(m, "GAMEPLAY")
	at = _verb_row(m, "move_stick")
	assert_eq(at, _verb_row(m, "move_right") + 1, "after the four directions")
	_go(m, at)
	_press("ui_accept")
	assert_eq(m.capturing, "move_stick")
	assert_eq(m._value(m.rows[at]), "MOVE A STICK")
	var trig := InputEventJoypadMotion.new()
	trig.device = 0
	trig.axis = JOY_AXIS_TRIGGER_RIGHT
	trig.axis_value = 1.0
	m.take_binding(trig)
	assert_eq(m.capturing, "move_stick", "a trigger: still waiting")
	var rs := InputEventJoypadMotion.new()
	rs.device = 1
	rs.axis = JOY_AXIS_RIGHT_Y
	rs.axis_value = 1.0
	m.take_binding(rs)
	assert_eq(m.capturing, "")
	assert_eq(MwPortMenu.stick_text(1, "move_stick"), "PAD2 RS")
	assert_eq(MwPortMenu.binding_text(1, "move_up"), "UP / PAD1 DPAD UP", "the D-pad as it was")
	_run(10)
	_press("ui_accept")
	m.take_binding(_key_event(KEY_K))
	assert_eq(m.capturing, "", "a key on a stick row gives up")
	assert_eq(MwPortMenu.stick_text(1, "move_stick"), "PAD2 RS", "nothing bound")


## The PAUSE + REPLAY page: the original's pause menu's A / B (REPLAY,
## TIMEOUT) for a GENESIS player only - the STANDARD layout's port menu
## has no use for them (MwInputMap.STANDARD_UNUSED).
func test_the_pause_shortcuts_are_genesis_only() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	_page(m, "PAUSE + REPLAY")
	var verbs: Array = m.rows.slice(3).map(func(r): return r.verb)
	for v in MwInputMap.STANDARD_UNUSED:
		assert_false(v in verbs, "STANDARD: no %s row" % v)
	assert_true("ui_resume" in verbs and "replay_rewind" in verbs, "the page's other verbs")
	_go(m, 1)
	_press("ui_right")
	assert_eq(MwSettings.layout(1), "GENESIS")
	verbs = m.rows.slice(3).map(func(r): return r.verb)
	for v in MwInputMap.STANDARD_UNUSED:
		assert_true(v in verbs, "GENESIS: the %s row" % v)
	assert_eq(MwPortMenu.binding_text(1, "ui_pause_replay"), "Z / PAD1 X", "the lettered menu's A")
	_press("ui_left")
	assert_eq(MwSettings.layout(1), "STANDARD")


func test_player_one_has_the_view_switch() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	_page(m, "GAMEPLAY")
	assert_eq(m.rows[-1].verb, MwVerbs.VIEW_TOGGLE)
	assert_eq(m.rows[-1].label, "2D / 3D")
	assert_eq(MwPortMenu.binding_text(1, MwVerbs.VIEW_TOGGLE), "V / PAD1 Y", "after Z X C; the pad's north button")
	var n := m.rows.size()
	_go(m, 0)
	_press("ui_right")
	assert_eq(m.player, 2)
	assert_eq(m.rows.size(), n - 1, "players 2-4 have no view switch")
	_press("ui_left")
	assert_eq([m.player, m.rows.size()], [1, n])


func test_long_pages_scroll() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	_page(m, "GAMEPLAY")
	assert_gt(m.rows.size() - 3, MwPortMenu.VERBS_SHOWN)
	_go(m, 0)
	assert_eq([m._arrows[0].visible, m._arrows[1].visible], [false, true], "the down arrow: verbs below")
	assert_eq(m._arrows[1].position.x, 160.0, "alone: centred")
	_press("ui_up")                           # wraps to the last verb
	assert_eq(m.row, m.rows.size() - 1)
	assert_eq(m.scroll, m.rows.size() - 3 - MwPortMenu.VERBS_SHOWN, "scrolled to it")
	assert_eq(m.rows[-1].y, MwPortMenu.VERB_Y + 2 * (MwPortMenu.VERBS_SHOWN - 1), "drawn on the last line")
	assert_eq([m._arrows[0].visible, m._arrows[1].visible], [true, false], "the up arrow: verbs above")
	assert_eq(m._arrows[0].position.x, 160.0, "alone: centred")
	assert_eq(m._arrows[0].anim, "%X" % MwGfx.u32(MwRom.data(), MwRinkMatch.ARROWS + 4 * MwPortMenu.ARROW_PAD))
	_press("ui_down")                         # wraps to PLAYER
	assert_eq([m.row, m.scroll], [0, 0])
	_go(m, 3 + MwPortMenu.VERBS_SHOWN)        # one verb past the first page: LET PUCK GO
	assert_eq(m.scroll, 2, "and CHANGE PLAYER, its partner, in view too (the pair hint)")
	assert_eq([m._arrows[0].visible, m._arrows[1].visible], [true, true], "verbs above and below")
	assert_eq(m._arrows[0].position.x + m._arrows[1].position.x, 320.0, "the pair centred")


func test_function_keys_are_not_bound() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	_go(m, _verb_row(m, "ui_up"))
	_press("ui_accept")
	assert_eq(m.capturing, "ui_up")
	for code in [KEY_F1, KEY_F3, KEY_F8, KEY_F12]:
		m._input(_key_event(code))
		assert_eq(m.capturing, "ui_up", "F%d: still waiting" % (code - KEY_F1 + 1))
	assert_null(MwSettings.binding(1, "ui_up"))
	m._input(_key_event(KEY_I))
	assert_eq(m.capturing, "")
	assert_eq(MwPortMenu.binding_text(1, "ui_up"), "I")


func test_the_bound_input_must_be_let_go_first() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	var at := _verb_row(m, "ui_down")
	_go(m, at)
	_press("ui_accept")
	assert_eq(m.capturing, "ui_down")
	var d := _key_event(KEY_D)
	Input.parse_input_event(d)
	Input.flush_buffered_events()
	m._input(d)
	assert_eq(m.capturing, "")
	# the key, held, repeats: its repeats press ui_down now, which would
	# move the selection on - the menu waits for the key itself
	rig.hold({"ui_down": true}, 3, 30)
	rig.hold({"ui_down": true}, 3, 10)
	assert_eq(m.row, at, "nothing while D is down")
	Input.parse_input_event(_key_event(KEY_D, false))
	Input.flush_buffered_events()
	_run(5)
	_press("ui_down")
	assert_eq(m.row, at + 1, "let go: the menu answers again")


func test_idle_starts_the_demo_which_comes_back() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(MwAttract.IDLE_TICKS + 10)
	assert_true(_until(4, 600), "idle: the demo's rink (through the matchup)")
	assert_true(router.session.attract)
	assert_eq(router.history.slice(-2), [3, 4])
	rig.hold({"p1_pause": true, "ui_accept": true}, 10, 0)
	assert_true(_until(MwScreens.FRONT_MENU, 600), "any input ends the demo: back to the front menu")
	assert_false(router.session.attract)


func test_a_new_match_starts_in_the_options_camera() -> void:
	if not need_rom():
		return
	MwSettings.camera = 1
	_start(1)
	_run(30)
	pad.held = {"ui_accept": true, "p1_ui_accept": true}   # the game setup reads each player's pad
	_run(3)
	pad.held = {}
	assert_true(_until(3, 400), "the matchup")
	assert_eq(router.session.view, MwRinkViews.FOLLOW, "3D from the options: the follow camera")


# --- plan 34: the menu overhaul ------------------------------------------------------------------
func test_every_page_goes_back_one_screen_up() -> void:
	if not need_rom():
		return
	for pair: Array in [[MwScreens.OPTIONS, MwScreens.FRONT_MENU], [MwScreens.VISUALS, MwScreens.OPTIONS],
			[MwScreens.MODIFIERS, MwScreens.OPTIONS], [MwScreens.CONTROLS, MwScreens.OPTIONS],
			[MwScreens.BINDINGS, MwScreens.CONTROLS], [MwScreens.PLAY_MODE, MwScreens.FRONT_MENU],
			[MwScreens.LOCAL_PLAY, MwScreens.PLAY_MODE], [MwScreens.CONTINUE, MwScreens.LOCAL_PLAY],
			[MwScreens.REPLAYS, MwScreens.FRONT_MENU]]:
		_start(pair[0])
		_run(10)
		_press("ui_back")
		assert_true(_until(pair[1]), "%d -> %d" % pair)
		assert_true(pair[1] in MwScreens.exits(pair[0]), "%d's exits list %d" % pair)
		host.free()
		host = null


func test_the_item_pages() -> void:
	if not need_rom():
		return
	for page: Array in [[MwScreens.PLAY_MODE, ["local", "online"]],
			[MwScreens.LOCAL_PLAY, ["exhibition", "playoffs", "continue"]],
			[MwScreens.CONTINUE, ["load", "password"]],
			[MwScreens.OPTIONS, ["visuals", "modifiers", "controls"]]]:
		_start(page[0])
		_run(10)
		var m := _menu()
		assert_eq(m.rows.map(func(r): return r.action), page[1])
		for i in m.rows.size():
			assert_eq(m.rows[i].label, MwPortMenu.label_text(m.rom, MwPortMenu.ITEMS[m.page][i][0]))
		var w: int = m.get("_item_w")
		for r in m.rows:
			assert_lt(MwGlyphs.text_width(m.rom, MwPortMenu.FONT_LIGHT, (r.label as String).to_ascii_buffer()), w - 1,
					"%s fits its frame" % r.label)
		host.free()
		host = null


func test_online_play_leads_to_the_online_pages() -> void:
	if not need_rom():
		return
	_start(MwScreens.PLAY_MODE)
	_run(10)
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "ONLINE MULTIPLAYER")
	assert_false(_menu().rows[_menu().row].disabled, "plan 35: there")
	_press("ui_accept")
	assert_true(_until(MwScreens.ONLINE), "-> 119 (test/net/test_online_pages.gd has the rest)")


func test_playoffs_and_the_password_from_local_play() -> void:
	if not need_rom():
		return
	_start(MwScreens.LOCAL_PLAY)
	_run(10)
	router.session.run_started = true
	_press("ui_down")
	_press("ui_accept")
	assert_true(_until(1), "PLAYOFFS -> the game setup")
	assert_eq(router.session.local_mode, "playoffs")
	assert_false(router.session.run_started, "a new run")
	host.free()
	host = null
	_start(MwScreens.CONTINUE)
	_run(10)
	_press("ui_down")
	_press("ui_accept")
	assert_true(_until(11), "PASSWORD -> the playoffs")
	assert_eq(router.session.setup.play_mode, MwPlayoffs.MODE_CONTINUE, "the original's CONTINUE")
	assert_eq(router.session.playoffs.flags & MwPlayoffs.NEW, 0, "no new run: the password is asked")
	_run(120)
	assert_true(router.current() is MwPasswordScreen, "the password screen over the playoffs")


func test_team_descriptions_browse_every_team() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(10)
	_press("ui_down")
	_press("ui_down")                         # (plan 38: CREATE-A-TEAM second; owner: then this)
	assert_eq(_menu().rows[_menu().row].action, "teams")
	_press("ui_accept")
	assert_true(_until(2), "the team description")
	var td := router.current() as MwTeamDescription
	assert_true(td.browse)
	_run(200)
	var bytes := MwRom.data()
	var first: int = td.team
	rig.hold({"p1_ui_right": true, "ui_right": true}, 3, 60)
	var pos: int = bytes[MwTeams.MENU_POSITION + first]
	assert_eq(td.team, bytes[MwTeams.MENU_ORDER + posmod(pos + 1, MwTeams.COUNT)], "the next team in the menu's order")
	assert_eq(td.side, 0, "the same side")
	rig.hold({"p1_ui_left": true, "ui_left": true}, 3, 60)
	assert_eq(td.team, first, "and back")
	rig.hold({"ui_back": true, "p1_ui_back": true, "ui_accept": true, "p1_ui_accept": true}, 3, 0)
	assert_true(_until(MwScreens.FRONT_MENU), "Start / Back from the bio: the front menu")


## The pair hint (owner, 2026-10-09): while a verb sharing its input with
## others by default is selected (MwVerbs.GROUPS), the others' labels are
## drawn as the highlight draws its own (frame, grey ground, dark font) on
## the dark PairPlane, round the label alone, and come into view.
func test_paired_verbs_are_hinted() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	_page(m, "GAMEPLAY")
	var at := func(v: String) -> int: return m.rows.map(func(r: Dictionary) -> String: return r.get("verb", "")).find(v)
	var shown := func(v: String) -> bool:
		var k: int = at.call(v) - 3 - m.scroll
		return k >= 0 and k < MwPortMenu.VERBS_SHOWN
	var hinted := func(v: String) -> bool:
		var r: Dictionary = m.rows[at.call(v)]
		return int(m._pair.cell(MwPortMenu.ROW_X, r.y)["key"]) != 0
	assert_eq(m._pair.modulate, MwPortMenu.PAIR_DARK)
	assert_lt(m._pair.get_index(), m.plane.get_index(), "under the plane: the highlight stays on top")
	assert_eq(m._pair.get_used_cells().size(), 0, "on CONTROLS: none")
	_go(m, at.call("move_stick"))
	assert_eq(m._pair.get_used_cells().size(), 0, "SKATE STICK shares nothing: none")
	_go(m, at.call("pass"))
	for v in ["release_puck", "change_player"]:
		assert_true(shown.call(v), "%s scrolled into view with PASS" % v)
		assert_true(hinted.call(v), "%s: hinted" % v)
		var r: Dictionary = m.rows[at.call(v)]
		var w := m._width(MwPortMenu.FONT_DARK, MwPortMenu._ascii(r.label))
		assert_eq(_cells_on(m._pair, r.y), w + 2, "%s: the label on its ground, the frame's sides either side" % v)
		assert_eq(int(m.plane.cell(MwPortMenu.ROW_X, r.y)["key"]), 0, "%s: not on the plane too" % v)
		assert_gt(_cells_on(m.plane, r.y), 0, "%s: its inputs stay on the plane (the verb only)" % v)
	var release: Dictionary = m.rows[at.call("release_puck")]
	var wr := m._width(MwPortMenu.FONT_DARK, MwPortMenu._ascii(release.label))
	assert_eq(_cells_on(m._pair, release.y - 1), wr + 2, "the frame's top round the label alone")
	assert_false(hinted.call("pass"), "the selected row has the highlight itself")
	assert_true(shown.call("move_stick"))
	assert_false(hinted.call("move_stick"), "a verb outside the group: not hinted")
	assert_gt(int(m.plane.cell(MwPortMenu.ROW_X, m.rows[at.call("move_stick")].y)["key"]), 0, "drawn as usual")
	_go(m, at.call("wrist_shot"))
	for v in ["slap_shot", "check"]:
		assert_true(shown.call(v))
		assert_true(hinted.call(v), "WRIST SHOT selected: %s hinted" % v)
	assert_false(shown.call("pass") and hinted.call("pass"), "PASS no longer")
	_go(m, at.call("dive"))
	for v in ["punch", "special_play"]:
		assert_true(hinted.call(v), "DIVE selected: %s hinted" % v)
	_go(m, at.call("pause"))
	assert_eq(m._pair.get_used_cells().size(), 0, "PAUSE: none")


# --- the project's logo on the main page (owner, 2026-10-11) ------------------------------------
## The logo's lowest visible pixel line on the pages, from the backdrop's own
## art: its cells' pixels but colour 0 and line 1's colour 15 (its black
## panel, see-through on the pages: palette step `clear 31`).
func _logo_foot() -> int:
	var img := MwGfx.picture_image(rom, MwGfx.picture(rom, MwPortMenu.BACKDROP))
	var r := MwPortMenu.LOGO
	var foot := -1
	for py in range(r.position.y * 8, r.end.y * 8):
		for px in range(r.position.x * 8, r.end.x * 8):
			var v: int = (img.px as PackedByteArray)[py * int(img.w) + px]
			if v != 0 and v != 31:
				foot = py
	return foot + 8 * (MwPortMenu.LOGO_AT.y - r.position.y)


## Owner's request (the project's logo on the main menu): centred on the
## screen, a pixel's gap under the logo's lowest visible line, the PNG's own
## pixels at their own size on whole pixels; on no other page.
func test_the_projects_logo_sits_under_the_logo_on_the_main_page_alone() -> void:
	if not need_rom():
		return
	assert_eq(_logo_foot(), MwPortMenu.LOGO_FOOT, "the logo's feet, as the ROM's art has them")
	var png := Image.load_from_file(ProjectSettings.globalize_path("res://assets/logo/mightyweenie_logo.png"))
	png.convert(Image.FORMAT_RGBA8)
	for id: int in [MwScreens.FRONT_MENU, MwScreens.OPTIONS, MwScreens.VISUALS, MwScreens.MODIFIERS,
			MwScreens.CONTROLS, MwScreens.BINDINGS, MwScreens.PLAY_MODE, MwScreens.LOCAL_PLAY,
			MwScreens.CONTINUE, MwScreens.SAVED_GAMES, MwScreens.REPLAYS]:
		_start(id)
		_run(4)
		var m := _menu()
		var w := m.weenie
		assert_eq(w.visible, id == MwScreens.FRONT_MENU, "screen %d: the main page's alone" % id)
		if id == MwScreens.FRONT_MENU:
			var tex := w.texture
			assert_eq(Vector2i(tex.get_size()), png.get_size(), "its own size")
			var img := tex.get_image()
			img.convert(Image.FORMAT_RGBA8)
			assert_eq(img.get_data(), png.get_data(), "imported pixel for pixel (lossless, no filtering)")
			assert_eq(w.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
			assert_false(w.centered)
			assert_eq(w.scale, Vector2.ONE, "no scaling")
			assert_eq(w.global_transform, Transform2D(0.0, w.position), "unrotated, unscaled")
			assert_eq(w.position, w.position.round(), "on whole pixels")
			assert_eq(int(w.position.x) * 2 + png.get_width(), 320, "centred")
			assert_eq(int(w.position.y), MwPortMenu.LOGO_FOOT + 2, "its top a pixel's gap under the logo's feet")
			assert_eq(MwPortMenu.WEENIE_GAP, 1)
		host.free()
		host = null


## Owner: the menu's items a little closer to make room (off the tile grid,
## each gap about 1 px less): the main page's items evenly spaced a pixel
## closer than two rows, under the project's logo, inside the screen - drawn
## as every page's rows are (owner, 2026-10-10: no parallel structures): on
## the cell row their line falls in, on the page's layers' twins moved down
## by the pixels below it (MwPortMenu._on), the highlight frame with its row;
## the same pixel lines as before (text tops 116 + 15 i, frames a line above
## and two below).
func test_the_main_pages_items_are_a_pixel_closer_under_the_projects_logo() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(4)
	var m := _menu()
	assert_false("_main_layers" in m, "no layers of the main page's own")
	var offsets := []
	for i in m.rows.size():
		var top := MwPortMenu.main_item_top(i)
		var r: Dictionary = m.rows[i]
		assert_eq(top, 116 + 15 * i, "item %d's text top: as before" % i)
		assert_eq(MwPortMenu.item_top("main", i), top)
		assert_eq(8 * int(r.y) + int(r.dy), top, "item %d: its row and the pixels below it" % i)
		assert_between(int(r.dy), 0, 7)
		var on := m._on(m.plane, r.dy)
		var half := m._on(m.half_plane, r.dy)
		assert_eq(on.position, Vector2(0, r.dy), "item %d's cells: the plane, moved down %d" % [i, r.dy])
		assert_eq(half.position, Vector2(4, r.dy), "and the half-cell plane's")
		assert_eq(on.get_parent(), m.page_layers, "the page's own layers")
		assert_eq(on.tiles, m.plane.tiles)
		assert_eq(on.palette, m.plane.palette)
		assert_gt(_cells_on(on, r.y) + _cells_on(half, r.y), 0, "item %d's label there" % i)
		assert_gt(half.get_index(), on.get_index(),
				"the half-cell layer over the cells: a label there shows on the frame's fill")
		assert_false(r.dy in offsets, "one item a layer (the selected one's frame alone on it)")
		offsets.append(r.dy)
		if i > 0:
			assert_eq(top - MwPortMenu.main_item_top(i - 1), 2 * 8 - 1, "a pixel closer than two rows")
	# the selected item's frame: a pixel line above its text and two below its 7
	var logo_bottom := int(m.weenie.position.y) + m.weenie.texture.get_height() - 1
	assert_gt(MwPortMenu.main_item_top(0) - 1, logo_bottom + 1, "the first frame under the logo, a gap between")
	assert_eq(MwPortMenu.main_item_top(0) - 1 - (logo_bottom + 1), 6,
			"as much room as a frame leaves above the next item's text")
	assert_lt(MwPortMenu.main_item_top(m.rows.size() - 1) + 8, 224, "the last frame inside the screen")
	for want in m.rows.size() + 1:
		var framed := []
		for i in m.rows.size():
			var r: Dictionary = m.rows[i]
			var on := m._on(m.plane, r.dy)
			if _cells_on(on, r.y - 1) > 0 and _cells_on(on, r.y + 1) > 0:
				framed.append(i)
		assert_eq(framed, [want % m.rows.size()], "the frame on the selected item's row")
		_press("ui_down", 2)
	# the other item pages: on the tile rows, the page's planes themselves
	for id: int in [MwScreens.OPTIONS, MwScreens.PLAY_MODE]:
		host.free()
		_start(id)
		_run(4)
		for i in _menu().rows.size():
			var r: Dictionary = _menu().rows[i]
			assert_eq(r.dy, 0, "screen %d: on the tile rows" % id)
			assert_eq(r.y, MwPortMenu.ITEM_Y + MwPortMenu.ITEM_STEP * i)
			assert_eq(_menu()._on(_menu().plane, r.dy), _menu().plane)


## The page's own layers (MwPortMenu.page_layers) and the screen's others.
func _layers_of(m: MwPortMenu) -> Dictionary:
	var own := {}
	for c in m.page_layers.get_children():
		if c is CanvasItem:
			own[c] = (c as CanvasItem).modulate
	return own


## Owner, 2026-10-11: the items' fades were inconsistent (START GAME's fine,
## on OPTIONS the outline round the text faded differently) - made the same:
## on every page the page's own layers - planes, the tinted ones, the title's
## plate, the arrows, the question box, the project's logo, the online pages'
## own - are under one CanvasGroup, put together first and faded as one
## picture: in the cut into a page its alpha rises from 0 to 1 over
## MwMenuCut.FADE_TICKS, in the cut out of it falls to 0 before the next
## page comes - the one alpha on the group, every layer's own modulate (the
## red, dim and dark tints, the rest white) untouched; nothing but the
## backdrop, the stars, the logo and the hanging top outside it.
func test_every_page_fades_as_one_picture() -> void:
	if not need_rom():
		return
	for id: int in [MwScreens.FRONT_MENU, MwScreens.OPTIONS, MwScreens.VISUALS, MwScreens.MODIFIERS,
			MwScreens.CONTROLS, MwScreens.BINDINGS, MwScreens.PLAY_MODE, MwScreens.LOCAL_PLAY,
			MwScreens.CONTINUE, MwScreens.SAVED_GAMES, MwScreens.REPLAYS, MwScreens.ONLINE,
			MwScreens.HOST_GAME, MwScreens.JOIN_GAME]:
		_start(id, {"menu_cut": true, "logo": true, "top": true})
		var m := _menu()
		var g := m.page_layers
		assert_true(g is CanvasGroup, "screen %d: the page's layers under one CanvasGroup" % id)
		var outside := []
		for c in m.get_children():
			if c != g:
				outside.append(str(c.name))
		assert_eq(outside, ["Backdrop", "Starfield", "TopPlane", "LogoPlane"], "screen %d: the rest stays" % id)
		assert_lt(m.top.get_index(), g.get_index(), "under the page")
		assert_lt(m.logo_plane.get_index(), g.get_index())
		for c in [m.plane, m.half_plane, m._red, m._dim, m._pair, m._plate, m.confirm] + m._arrows:
			assert_eq((c as Node).get_parent(), g, "screen %d: %s the page's own" % [id, (c as Node).name])
		if m.weenie:
			assert_eq(m.weenie.get_parent(), g)
		assert_eq(m._red.modulate, MwPortMenu.RED, "the tints their own")
		assert_eq(m._dim.modulate, MwPortMenu.DIM)
		assert_eq(m._pair.modulate, MwPortMenu.PAIR_DARK)
		var own := _layers_of(m)
		# in by the cut: from 0 up to 1, the group alone
		var a := []
		for t in MwMenuCut.FADE_TICKS + 4:
			a.append(g.self_modulate.a)
			assert_eq(g.modulate, Color.WHITE, "screen %d: the alpha on the group's own drawing" % id)
			assert_eq(_layers_of(m), own, "screen %d: the layers' own modulates untouched" % id)
			router.step()
		assert_eq(a[0], 0.0, "screen %d: in by the cut, from nothing" % id)
		assert_true(a.any(func(v: float) -> bool: return v > 0.0 and v < 1.0), "screen %d: a fade" % id)
		for i in range(1, a.size()):
			assert_true(a[i] >= a[i - 1], "screen %d: fading in" % id)
		assert_eq(g.self_modulate.a, 1.0, "screen %d: in" % id)
		assert_eq(m.logo_plane.modulate.a, 0.0 if id == MwScreens.BINDINGS else 1.0, "the logo on its own")
		# out by a cut to another menu: down to 0, then the next page
		own = _layers_of(m)
		m.exit_to(MwScreens.OPTIONS if id == MwScreens.FRONT_MENU else MwScreens.FRONT_MENU)
		var out := []
		while router.current() == m and out.size() < 40:
			router.step()
			if router.current() != m:
				break
			out.append(g.self_modulate.a)
			assert_eq(_layers_of(m), own, "screen %d: the layers' own modulates untouched going out" % id)
			assert_eq(router.fader.coverage(), 0.0, "a cut, no fade")
		assert_eq(out[-1], 0.0, "screen %d: out before the cut" % id)
		assert_true(out.any(func(v: float) -> bool: return v > 0.0 and v < 1.0), "screen %d: a fade out" % id)
		for i in range(1, out.size()):
			assert_true(out[i] <= out[i - 1], "screen %d: fading out" % id)
		var next := _menu()
		assert_not_null(next)
		assert_lt(next.page_layers.self_modulate.a, 1.0, "screen %d: the next page fading in" % id)
		host.free()
		host = null


## Owner's request: the project's logo is one of the main page's own layers -
## it fades out with the page (as one picture: its own modulate untouched) in
## the cut to another menu and back in with it, the original's logo staying;
## with the whole screen in the fades to black (the screens with no
## starfield: the team descriptions, CREDITS, QUIT GAME, the attract demo,
## the title - plan 40, M5: CREATE-A-TEAM is a cut).
func test_the_projects_logo_fades_with_the_main_page() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(10)
	var m := _menu()
	_go(m, 3)
	assert_eq(m.rows[m.row].action, "options")
	assert_eq(m.weenie.get_parent(), m.page_layers, "one of the page's own layers")
	pad.held = {"ui_accept": true}
	var out := []
	for t in 40:
		router.step()
		if t == 3:
			pad.held = {}
		if not is_instance_valid(m) or router.current() != m:
			break
		assert_eq(m.weenie.modulate, Color.WHITE, "its own modulate untouched")
		assert_eq(m.logo_plane.modulate.a, 1.0, "the logo stays")
		out.append(m.page_layers.self_modulate.a)
	assert_eq(out[-1], 0.0, "out before the cut")
	assert_true(out.any(func(a: float) -> bool: return a > 0.0 and a < 1.0), "a fade, not a cut")
	for i in range(1, out.size()):
		assert_true(out[i] <= out[i - 1], "fading out")
	assert_true(_until(MwScreens.OPTIONS))
	assert_false(_menu().weenie.visible, "not on OPTIONS")
	pad.held = {"ui_back": true}
	var back := []
	for t in 60:
		router.step()
		if t == 3:
			pad.held = {}
		if router.current_id() == MwScreens.FRONT_MENU:
			m = _menu()
			back.append(m.page_layers.self_modulate.a)
			assert_eq(m.weenie.modulate, Color.WHITE, "its own modulate untouched")
			if m.page_layers.self_modulate.a >= 1.0:
				break
	assert_gt(back.size(), 2)
	assert_lt(back[0], 1.0, "back by the cut: fading in")
	assert_true(back.any(func(a: float) -> bool: return a > 0.0 and a < 1.0), "a fade")
	assert_eq(back[-1], 1.0, "in")
	assert_true(m.weenie.visible)
	# a fade to black (the team descriptions: no starfield): the whole screen goes, the logo with it
	_go(m, 2)
	pad.held = {"ui_accept": true}
	var covered := []
	for t in 60:
		router.step()
		if t == 3:
			pad.held = {}
		if router.current() != m:
			break
		covered.append(router.fader.coverage())
		assert_eq(m.page_layers.self_modulate.a, 1.0, "the fader covers it")
	assert_true(covered.any(func(c: float) -> bool: return c > 0.0 and c < 1.0),
			"the team descriptions: the screen fades out")
	assert_true(_until(2))


## ABACABB MODE's label red while it is on, white while off (owner's request,
## 2026-10-11).
func test_abacabb_mode_is_red_when_on() -> void:
	if not need_rom():
		return
	var was := MwSettings.blood
	MwSettings.blood = true
	_start(MwScreens.VISUALS)
	_run(4)
	var m := router.current() as MwPortMenu
	var i := -1
	for k in m.rows.size():
		if m.rows[k].get("action", "") == "blood":
			i = k
	assert_gt(i, -1, "the row")
	var y: int = m.rows[i].y
	var red := m.get("_red") as RomPlane
	var cells_on := func(layer: RomPlane) -> int:
		return layer.get_used_cells().filter(func(c: Vector2i) -> bool: return c.y == y and c.x < 20).size()
	var ink := m.get("_red_ink") as RomPlane
	assert_gt(cells_on.call(red), 0, "on: the label on the red layer")
	assert_eq(cells_on.call(ink), 0, "on, not selected: tinted, not screened")
	m.row = i
	m.call("_draw")
	assert_eq(cells_on.call(red), 0, "on, selected: not tinted (the bar would go red)")
	assert_gt(cells_on.call(ink), 0, "on, selected: the letters screened red")
	assert_true(ink.screen_tint, "the ink layer screens")
	assert_true((ink.material as ShaderMaterial).get_shader_parameter("screen_tint"), "... in its material")
	assert_false(red.screen_tint, "the red layer multiplies")
	MwSettings.blood = false
	m.call("_draw")
	assert_eq(cells_on.call(red) + cells_on.call(ink), 0, "off: no red")
	assert_gt(cells_on.call(m.plane), 0, "off: the label white")
	MwSettings.blood = was


## A binding's input that is another verb's too: its value red - tinted off
## the highlight, and on it red letters on the white bar like ABACABB MODE's
## label (owner, 2026-10-11, a follow-up: the value was a red block).
func test_collided_binding_is_red_on_the_bar_too() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(4)
	var m := router.current() as MwPortMenu
	var verbs := []
	for r in m.rows:
		if r.kind == MwPortMenu.Kind.BINDING and not r.get("stick", false) and verbs.size() < 2:
			verbs.append(r.verb)
	assert_eq(verbs.size(), 2, "two bindings on the first page")
	var theirs: InputEvent = null                    # the second verb's gamepad button, on the first's too
	for event in MwInputMap.verb_events(1, verbs[1]):
		if event is InputEventJoypadButton and theirs == null:
			theirs = event
	assert_not_null(theirs, "the second verb's button")
	MwSettings.bindings = {"p1_" + str(verbs[0]): theirs}
	MwInputMap.install()
	m.call("_draw")
	var i := -1
	for k in m.rows.size():
		if m.rows[k].kind == MwPortMenu.Kind.BINDING and m.call("_collided", m.rows[k]) and i < 0:
			i = k
	assert_gt(i, -1, "a collided row")
	var y: int = m.rows[i].y
	var red := m.get("_red") as RomPlane
	var ink := m.get("_red_ink") as RomPlane
	var value_cells := func(layer: RomPlane) -> int:
		return layer.get_used_cells().filter(func(c: Vector2i) -> bool: return c.y == y and c.x >= 20).size()
	m.row = 0 if i != 0 else 1
	m.call("_draw")
	assert_gt(value_cells.call(red), 0, "off the highlight: tinted")
	assert_eq(value_cells.call(ink), 0)
	m.row = i
	m.call("_draw")
	assert_eq(value_cells.call(red), 0, "on the highlight: not tinted (the bar would go red)")
	assert_gt(value_cells.call(ink), 0, "... screened: red letters, the bar white")


## The game's version in the main page's bottom right corner, on the page's
## own layers so it fades with the page like the project's logo, and on no
## other page (owner's request, 2026-10-11).
func test_version_bottom_right_on_the_main_page_alone() -> void:
	if not need_rom():
		return
	var v := MwPortMenu.version_text()
	assert_eq(v, "V" + str(ProjectSettings.get_setting("application/config/version")).to_upper(),
			"the project's version, the one the replays and the online HELLO carry")
	assert_ne(v, "DEV", "the project has one")
	var top := MwPortMenu.version_top()
	assert_eq(top, MwPortMenu.main_item_top(6), "QUIT GAME's line")
	for id: int in [MwScreens.FRONT_MENU, MwScreens.OPTIONS, MwScreens.VISUALS, MwScreens.CONTROLS,
			MwScreens.BINDINGS, MwScreens.PLAY_MODE, MwScreens.LOCAL_PLAY, MwScreens.REPLAYS]:
		_start(id)
		_run(4)
		var m := _menu()
		var dim := m.call("_on", m.get("_dim"), top & 7) as RomPlane
		var cells: Array = dim.get_used_cells().filter(
				func(c: Vector2i) -> bool: return c.y == top >> 3 and c.x > MwPortMenu.VERSION_RIGHT - v.length() - 2)
		if id != MwScreens.FRONT_MENU:
			assert_eq(cells.size(), 0, "screen %d: the main page's alone" % id)
		else:
			assert_eq(cells.size(), v.length(), "one cell a letter (the light font's)")
			assert_eq(cells.map(func(c: Vector2i) -> int: return c.x).max(), MwPortMenu.VERSION_RIGHT,
					"right-aligned, a cell in from the screen's edge")
			assert_true(m.page_layers.is_ancestor_of(dim), "a page layer: it fades with the page ...")
			assert_true(m.page_layers.is_ancestor_of(m.weenie), "... as the project's logo")
			assert_almost_eq(dim.modulate.r, MwPortMenu.DIM.r, 0.001, "dimmed")
		host.free()
		host = null


## Plan 44: GAMEPLAY MODIFIERS holds eight rows with EXTENDED PENALTIES and
## EXTENDED CPU (nine with 2026-10-15's REPLAY BLOOD) - more than a page of
## choices fits: five show and the page
## scrolls, the scroll arrows under them as the bindings' do.
func test_a_long_choice_page_scrolls() -> void:
	if not need_rom():
		return
	_start(MwScreens.MODIFIERS)
	_run(10)
	var m := _menu()
	assert_eq(m.rows.size(), 9)
	assert_eq([m._arrows[0].visible, m._arrows[1].visible], [false, true], "more below: the down arrow")
	assert_eq(m.rows.slice(0, 5).map(func(r): return r.y), [15, 17, 19, 21, 23], "five shown")
	for i in 8:
		_press("ui_down")
	assert_eq(m.rows[m.row].label, "EXTENDED CPU")
	assert_eq(m.scroll, 4, "scrolled to the last")
	assert_eq(int(m.rows[m.row].y), MwPortMenu.CHOICE_Y + 2 * (MwPortMenu.CHOICES_SHOWN - 1), "on the fifth line")
	assert_lt(int(m.rows[m.row].y) * 8 + 10, MwPortMenu.ARROW_TOP, "its frame above the arrows")
	assert_eq([m._arrows[0].visible, m._arrows[1].visible], [true, false], "more above: the up arrow")
	var was := MwSettings.extended_cpu
	_press("ui_right")
	assert_ne(MwSettings.extended_cpu, was, "EXTENDED CPU switches")
	_press("ui_left")
	assert_eq(MwSettings.extended_cpu, was)
	_press("ui_down")
	assert_eq([m.rows[m.row].label, m.scroll], ["ENHANCE AUDIO", 0], "round to the first row, the page back up")
	_start(MwScreens.VISUALS)
	_run(10)
	assert_false(_menu()._arrows[0].visible or _menu()._arrows[1].visible, "VISUALS' six fit: no arrows")
