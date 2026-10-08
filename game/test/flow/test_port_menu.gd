extends "res://test/rom/rom_test_base.gd"
## The port's own menus (plan 21): the front menu after the title, options,
## controller bindings, Menu Back through the setup screens, the credits
## from the menu, the attract demo from its idle; settings saved to a test
## file (never the player's).

## Test input: the actions held now (the router turns them into presses).
class Pad extends MwInputSource:
	var held := {}
	func sample(_contexts: Array) -> Dictionary:
		return held.duplicate()

var host: Node
var router: MwRouter
var pad: Pad
var _saved := []


func before_all() -> void:
	super.before_all()
	_saved = [MwSettings.path, MwSettings.camera, MwSettings.enhance_audio, MwSettings.bindings,
			MwSettings.front_menu, MwAudio.free_music_samples, MwAudio.free_effects,
			MwSettings.fullscreen]
	MwSettings.path = "user://test_port_menu_%d.cfg" % Time.get_ticks_usec()
	MwSettings.front_menu = true


func after_all() -> void:
	if FileAccess.file_exists(MwSettings.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.path = _saved[0]
	MwSettings.camera = _saved[1]
	MwSettings.enhance_audio = _saved[2]
	MwSettings.bindings = _saved[3]
	MwSettings.front_menu = _saved[4]
	MwAudio.free_music_samples = _saved[5]
	MwAudio.free_effects = _saved[6]
	MwSettings.fullscreen = _saved[7]
	MwInputMap.install()


func before_each() -> void:
	MwSettings.camera = 0
	MwSettings.enhance_audio = true
	MwSettings.fullscreen = false
	MwSettings.bindings = {}
	MwInputMap.install()


func after_each() -> void:
	if host:
		host.free()
		host = null


## A router with screen [param id] adopted (uncovered).
func _start(id: int, data := {}) -> void:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	router = MwRouter.new(host, fader)
	router.session = MwSession.new(1, 1)
	pad = Pad.new()
	router.input = pad
	var scene := (load(MwScreens.scene_path(id)) as PackedScene).instantiate() as MwScreen
	scene.screen_id = id
	if id == 0:
		fader.cover()
	router.adopt(scene, data)
	if id != 0:
		fader.uncover()


func _run(ticks: int) -> void:
	for i in ticks:
		router.step()


## Press [param action] for 3 ticks, then let go and wait [param after] ticks.
func _press(action: String, after := 10) -> void:
	pad.held = {action: true}
	_run(3)
	pad.held = {}
	_run(after)


## Run until screen [param id] is on (and settled: 80 ticks past its entry).
func _until(id: int, limit := 3000) -> bool:
	for i in limit:
		router.step()
		if router.current_id() == id and not router.busy():
			_run(40)
			return true
	return false


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
	assert_true(_until(1), "START GAME -> the game setup")
	_press("ui_back")
	assert_true(_until(MwScreens.FRONT_MENU), "Menu Back -> the front menu")
	_press("ui_down")
	assert_eq(_menu().row, 1)
	_press("ui_accept")
	assert_true(_until(MwScreens.OPTIONS), "OPTIONS")
	_press("ui_back")
	assert_true(_until(MwScreens.FRONT_MENU))
	assert_eq(_menu().row, 1, "the row it left from")
	_press("ui_up")
	_press("ui_up")
	assert_eq(_menu().row, 3, "wraps to QUIT GAME")
	_press("ui_up")
	assert_eq(_menu().rows[_menu().row].label, "CREDITS")
	_press("ui_accept")
	assert_true(_until(0), "CREDITS -> the credits roll")
	assert_true((router.current() as MwTitleScreen).part >= MwTitleScreen.Part.CREDITS_LOAD)
	_run(200)
	_press("ui_accept")
	assert_true(_until(MwScreens.FRONT_MENU), "a press: back to the front menu")


func test_the_pads_south_button_selects_too() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(20)
	_press("ui_down")
	_press("ui_option_b")                     # Genesis B: the pad's south button (Xbox A)
	assert_true(_until(MwScreens.OPTIONS), "OPTIONS")
	_press("ui_option_b")                     # CAMERA is a choice: nothing happens
	assert_eq(MwSettings.camera, 0)
	assert_eq(router.current_id(), MwScreens.OPTIONS)


func test_quit_game_fades_out_then_closes() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(20)
	var m := _menu()
	assert_eq(m.rows.map(func(r): return r.label), ["START GAME", "OPTIONS", "CREDITS", "QUIT GAME"])
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
	assert_eq(m.row, 3)
	assert_eq(router.current_id(), MwScreens.FRONT_MENU)
	assert_almost_eq(router.fader.coverage(), 1.0, 0.001, "black")


func test_options_change_and_are_saved() -> void:
	if not need_rom():
		return
	_start(MwScreens.OPTIONS)
	_run(10)
	_press("ui_right")
	assert_eq(MwSettings.camera_name(), "3D")
	_press("ui_right")
	assert_eq(MwSettings.camera_name(), "2D", "wraps")
	_press("ui_left")
	assert_eq(MwSettings.camera_name(), "3D")
	_press("ui_down")
	_press("ui_left")
	assert_false(MwSettings.enhance_audio)
	assert_false(MwAudio.free_music_samples or MwAudio.free_effects, "the audio switches follow")
	_press("ui_down")
	assert_eq(_menu().rows[_menu().row].label, "DISPLAY")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "WINDOWED")
	_press("ui_right")
	assert_true(MwSettings.fullscreen, "full screen (the window itself only with a display)")
	assert_eq(_menu()._value(_menu().rows[_menu().row]), "FULLSCREEN")
	MwSettings.camera = 0
	MwSettings.enhance_audio = true
	MwSettings.fullscreen = false
	MwSettings.load_file()
	assert_eq([MwSettings.camera_name(), MwSettings.enhance_audio, MwSettings.fullscreen], ["3D", false, true], "saved")
	_press("ui_down")
	_press("ui_accept")
	assert_true(_until(MwScreens.BINDINGS), "CONTROLLER BINDINGS")
	_press("ui_back")
	assert_true(_until(MwScreens.OPTIONS), "Menu Back -> options")


func test_binding_a_button() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	assert_eq(MwPortMenu.binding_text(1, "A"), "Z / PAD1 X", "the defaults shown")
	_press("ui_down")
	_press("ui_accept")
	var m := _menu()
	assert_eq(m.capturing, "DOWN", "waiting for an input")
	_press("ui_back")
	assert_eq(router.current_id(), MwScreens.BINDINGS, "Menu Back while waiting does not leave")
	var e := InputEventJoypadButton.new()
	e.device = 2
	e.button_index = JOY_BUTTON_Y
	e.pressed = true
	m._input(e)
	assert_eq(m.capturing, "")
	assert_true(MwInputMap._same(MwSettings.binding(1, "DOWN"), MwSettings.normalized(e)), "player 1's DOWN = pad 3's Y")
	assert_eq(InputMap.action_get_events("p1_move_down").size(), 1, "one input per button")
	assert_eq(MwPortMenu.binding_text(1, "DOWN"), "PAD3 Y")
	_run(10)
	_press("ui_right")
	assert_eq(m.player, 2, "Right: the next player")
	_press("ui_accept")
	assert_eq(m.capturing, "DOWN")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	k.pressed = true
	m._input(k)
	assert_true(MwInputMap._same(MwSettings.binding(2, "DOWN"), MwSettings.normalized(k)), "any device for any player")
	_run(10)
	_press("ui_accept")
	_run(MwPortMenu.CAPTURE_TICKS + 5)
	assert_eq(m.capturing, "", "nothing pressed: given up")
	_press("ui_back")
	assert_true(_until(MwScreens.OPTIONS))


func test_player_one_has_the_view_switch() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	assert_eq(m.rows.size(), MwSettings.BUTTONS.size() + 1, "player 1: one more button")
	assert_eq(m.rows[-1].button, "VIEW")
	assert_eq(m.rows[-1].label, "2D / 3D")
	assert_eq(MwPortMenu.binding_text(1, "VIEW"), "V / PAD1 Y", "after Z X C; the pad's free north button")
	_press("ui_up")                           # wraps to the last row: 2D / 3D
	assert_eq(m.rows[m.row].button, "VIEW")
	_press("ui_right")
	assert_eq(m.player, 2)
	assert_eq(m.rows.size(), MwSettings.BUTTONS.size(), "players 2-4 have no view switch")
	assert_eq(m.row, m.rows.size() - 1, "the row stays on the list")
	_press("ui_left")
	assert_eq([m.player, m.rows.size()], [1, MwSettings.BUTTONS.size() + 1])


func test_function_keys_are_not_bound() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	_press("ui_accept")
	var m := _menu()
	assert_eq(m.capturing, "UP")
	for code in [KEY_F1, KEY_F3, KEY_F8, KEY_F12]:
		var f := InputEventKey.new()
		f.physical_keycode = code
		f.pressed = true
		m._input(f)
		assert_eq(m.capturing, "UP", "F%d: still waiting" % (code - KEY_F1 + 1))
	assert_null(MwSettings.binding(1, "UP"))
	var k := InputEventKey.new()
	k.physical_keycode = KEY_I
	k.pressed = true
	m._input(k)
	assert_eq(m.capturing, "")
	assert_eq(MwPortMenu.binding_text(1, "UP"), "I")


func test_the_bound_input_must_be_let_go_first() -> void:
	if not need_rom():
		return
	_start(MwScreens.BINDINGS)
	_run(10)
	var m := _menu()
	for i in 3:
		_press("ui_down")                     # RIGHT
	_press("ui_accept")
	assert_eq(m.capturing, "RIGHT")
	var d := InputEventKey.new()
	d.physical_keycode = KEY_D
	d.pressed = true
	Input.parse_input_event(d)
	Input.flush_buffered_events()
	m._input(d)
	assert_eq(m.capturing, "")
	# the key, held, repeats: its repeats press ui_right now, which would
	# move the page on to player 2 - the menu waits for the key itself
	pad.held = {"ui_right": true}
	_run(3)
	pad.held = {}
	_run(30)
	pad.held = {"ui_right": true}
	_run(3)
	pad.held = {}
	_run(10)
	assert_eq(m.player, 1, "nothing while D is down")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_D
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	_run(5)
	_press("ui_right")
	assert_eq(m.player, 2, "let go: the menu answers again")


func test_idle_starts_the_demo_which_comes_back() -> void:
	if not need_rom():
		return
	_start(MwScreens.FRONT_MENU)
	_run(MwAttract.IDLE_TICKS + 10)
	assert_true(_until(4, 600), "idle: the demo's rink (through the matchup)")
	assert_true(router.session.attract)
	assert_eq(router.history.slice(-2), [3, 4])
	pad.held = {"p1_pause": true, "ui_accept": true}
	_run(10)
	pad.held = {}
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
