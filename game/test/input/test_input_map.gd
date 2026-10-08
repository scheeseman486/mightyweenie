extends GutTest
## Default bindings: every verb for p1-p4, on the original's buttons. The
## tests below check the full layout (MwInputMap.p1_only off); the temporary
## player-1-only layout has its own test.

var _p1_only: bool
var _bindings: Dictionary


func before_all() -> void:
	_p1_only = MwInputMap.p1_only
	_bindings = MwSettings.bindings
	MwSettings.bindings = {}
	MwInputMap.p1_only = false
	MwInputMap.install()


func after_all() -> void:
	MwInputMap.p1_only = _p1_only
	MwSettings.bindings = _bindings
	MwInputMap.install()


func _has_key(action: String, key: Key) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and e.physical_keycode == key:
			return true
	return false


func _has_pad(action: String, device: int, button: JoyButton) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.device == device and e.button_index == button:
			return true
	return false


func test_every_action_exists() -> void:
	for a in MwVerbs.all_actions():
		assert_true(InputMap.has_action(a), a)
	assert_eq(MwVerbs.all_actions().size(), 9 + 4 * (21 + 9), "21 per-player verbs (14 gameplay) and 9 menu ones")


func test_player_one_keyboard_and_pad() -> void:
	assert_true(_has_key("p1_pass", KEY_J), "J = B = pass")
	for v in ["p1_wrist_shot", "p1_slap_shot", "p1_check"]:
		assert_true(_has_key(v, KEY_K), "K = C = %s" % v)
	assert_true(_has_key("p1_punch", KEY_L), "L = A = punch")
	assert_true(_has_key("p1_pause", KEY_ENTER))
	assert_true(_has_key("p1_move_left", KEY_A))
	assert_true(_has_pad("p1_pass", 0, JOY_BUTTON_A), "south = B")
	assert_true(_has_pad("p1_punch", 0, JOY_BUTTON_X), "west = A")
	assert_false(_has_pad("p1_pass", 1, JOY_BUTTON_A), "pad 2 is player 2")


func test_other_contexts_use_the_same_buttons() -> void:
	assert_true(_has_key("p1_fight_punch", KEY_J) and _has_key("p1_fight_punch", KEY_K), "B or C punch")
	assert_true(_has_key("p1_fight_block", KEY_L))
	assert_true(_has_key("p1_move_left", KEY_A), "fighters move left/right (manual)")
	assert_true(_has_key("p2_replay_exit", KEY_KP_ENTER))
	assert_true(_has_pad("p4_replay_rewind", 3, JOY_BUTTON_X))
	assert_true(_has_pad("p3_zamboni_whip", 2, JOY_BUTTON_DPAD_UP))


func test_menus_take_every_players_buttons() -> void:
	assert_true(_has_key("ui_accept", KEY_ENTER) and _has_key("ui_accept", KEY_KP_ENTER))
	for d in 4:
		assert_true(_has_pad("ui_accept", d, JOY_BUTTON_START), "start on pad %d" % (d + 1))
		assert_true(_has_pad("ui_option_b", d, JOY_BUTTON_A), "B on pad %d" % (d + 1))
	assert_false(_has_key("ui_accept", KEY_SPACE), "Godot's own events replaced")
	assert_false(_has_pad("ui_accept", 0, JOY_BUTTON_A), "south is B, not Start")


func test_per_player_menu_verbs() -> void:
	assert_true(_has_key("p1_ui_left", KEY_A) and not _has_key("p1_ui_option_b", KEY_KP_1), "only P1's buttons")
	assert_true(_has_key("p1_ui_left", KEY_LEFT), "and the permanent menu keys (plan 21)")
	assert_true(_has_key("p2_ui_left", KEY_LEFT))
	assert_true(_has_pad("p3_ui_right", 2, JOY_BUTTON_DPAD_RIGHT))
	assert_false(_has_pad("p3_ui_right", 0, JOY_BUTTON_DPAD_RIGHT))
	assert_true(_has_key("ui_left", KEY_A) and _has_key("ui_left", KEY_LEFT), "the shared verb stays")


func test_temporary_player_one_only() -> void:
	MwInputMap.p1_only = true
	MwInputMap.install()
	assert_true(_has_key("p1_pass", KEY_X), "X = B = pass")
	for v in ["p1_wrist_shot", "p1_slap_shot", "p1_check"]:
		assert_true(_has_key(v, KEY_C), "C = C = %s" % v)
	assert_true(_has_key("p1_punch", KEY_Z), "Z = A = punch")
	assert_true(_has_key("p1_pause", KEY_ENTER))
	assert_true(_has_key("p1_move_left", KEY_LEFT) and _has_key("p1_move_up", KEY_UP))
	assert_false(_has_key("p1_move_left", KEY_A), "WASD off")
	assert_true(_has_pad("p1_pass", 0, JOY_BUTTON_A), "the first gamepad stays player 1's")
	for p in range(2, MwVerbs.PLAYERS + 1):
		for a in MwVerbs.all_actions():
			if a.begins_with("p%d_" % p):
				assert_eq(InputMap.action_get_events(a).size(), 0, a)
	assert_true(_has_key("ui_accept", KEY_ENTER) and not _has_key("ui_accept", KEY_KP_ENTER))
	assert_true(_has_pad("ui_accept", 0, JOY_BUTTON_START))
	assert_false(_has_pad("ui_accept", 1, JOY_BUTTON_START), "menus: player 1 only")
	MwInputMap.p1_only = false
	MwInputMap.install()


func test_live_input_sees_actions() -> void:
	var live := MwLiveInput.new()
	Input.action_press("p2_slap_shot")
	assert_true(live.sample([]).has("p2_slap_shot"))
	Input.action_release("p2_slap_shot")
	assert_false(live.sample([]).has("p2_slap_shot"))


func test_a_quick_tap_between_passes_is_not_lost() -> void:
	var live := MwLiveInput.new()
	live.sample([])
	live.taps()
	Input.action_press("p1_punch")
	live.tick()           # the physics tick sees it pressed...
	Input.action_release("p1_punch")
	var held := live.sample([])
	assert_false(held.has("p1_punch"), "...released before the pass samples")
	var frame := MwInputFrame.make(held, {})
	frame.pressed.merge(live.taps())
	assert_true(frame.is_pressed("p1_punch"), "the pass still sees the press")
	assert_true(live.taps().is_empty(), "taps are read once")


# --- plan 21: Menu Back, the permanent menu keys, rebinding ------------------------------------

func _count(action: String, e: InputEvent) -> int:
	return InputMap.action_get_events(action).filter(func(x: InputEvent) -> bool: return MwInputMap._same(x, e)).size()


func test_menu_back_defaults() -> void:
	assert_true(_has_key("ui_back", KEY_ESCAPE) and _has_key("p1_ui_back", KEY_ESCAPE), "Esc")
	for d in 4:
		assert_true(_has_pad("ui_back", d, JOY_BUTTON_B), "east on pad %d" % (d + 1))
	assert_true(_has_pad("p2_ui_back", 1, JOY_BUTTON_B) and not _has_pad("p2_ui_back", 0, JOY_BUTTON_B))
	assert_true(_has_pad("ui_option_c", 0, JOY_BUTTON_B), "east stays the Genesis C button too (owner)")
	assert_false(_has_pad("p1_wrist_shot", 0, JOY_BUTTON_A), "nothing else moves")


func test_permanent_menu_keys() -> void:
	for verb in MwInputMap.MENU_KEYS:
		var k: Key = MwInputMap.MENU_KEYS[verb]
		assert_true(_has_key(verb, k), "%s on its permanent key" % verb)
		assert_true(_has_key(MwVerbs.menu_action(1, verb), k), "and player 1's")
	assert_false(_has_key("p1_move_up", KEY_UP), "menus only: player 1 plays on WASD in this layout")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_UP
	assert_eq(_count("ui_up", up), 1, "player 2's Up arrow and the permanent one: once")


func test_a_rebound_button_holds_one_input() -> void:
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	MwSettings.bindings = {"p1_A": q}
	MwInputMap.install()
	for a in ["p1_punch", "p1_dive", "p1_special_play", "p1_fight_block", "p1_ui_option_a"]:
		assert_eq(InputMap.action_get_events(a).size(), 1, a)
		assert_true(_has_key(a, KEY_Q), a)
	assert_true(_has_key("ui_option_a", KEY_Q) and _has_pad("ui_option_a", 1, JOY_BUTTON_X), "the shared verb: every player's")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_UP
	MwSettings.bindings = {"p1_UP": up, "p1_START": up}
	MwInputMap.install()
	assert_eq(_count("p1_ui_up", up), 1, "bound to a permanent key of the same verb: no double input")
	assert_true(_has_key("p1_move_up", KEY_UP) and not _has_key("p1_move_up", KEY_W))
	assert_true(_has_key("p1_pause", KEY_UP), "one key on two buttons is allowed")
	var pad := InputEventJoypadMotion.new()
	pad.device = 2
	pad.axis = JOY_AXIS_RIGHT_X
	pad.axis_value = 1.0
	MwSettings.bindings = {"p1_C": pad}
	MwInputMap.install()
	assert_eq(InputMap.action_get_events("p1_wrist_shot"), [pad] as Array[InputEvent], "any device, any player (no gating)")
	MwSettings.bindings = {}
	MwInputMap.install()


func test_settings_round_trip() -> void:
	var saved := [MwSettings.path, MwSettings.camera, MwSettings.enhance_audio, MwSettings.bindings,
			MwSettings.fullscreen]
	MwSettings.path = "user://test_settings_%d.cfg" % Time.get_ticks_usec()
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F
	var b := InputEventJoypadButton.new()
	b.device = 3
	b.button_index = JOY_BUTTON_Y
	var m := InputEventJoypadMotion.new()
	m.device = 1
	m.axis = JOY_AXIS_LEFT_Y
	m.axis_value = -1.0
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F5
	MwSettings.camera = 1
	MwSettings.enhance_audio = false
	MwSettings.fullscreen = true
	MwSettings.bindings = {"p1_UP": k, "p4_BACK": b, "p2_DOWN": m, "p1_A": f}
	MwSettings.save()
	MwSettings.camera = 0
	MwSettings.enhance_audio = true
	MwSettings.fullscreen = false
	MwSettings.bindings = {}
	MwSettings.load_file()
	assert_eq(MwSettings.camera_name(), "3D")
	assert_eq(MwSettings.view(), MwRinkViews.FOLLOW, "3D: the follow camera")
	assert_false(MwSettings.enhance_audio)
	assert_true(MwSettings.fullscreen)
	assert_false(MwSettings.bindings.has("p1_A"), "a function key in the file is dropped")
	assert_eq(MwSettings.bindings.size(), 3)
	for key in ["p1_UP", "p4_BACK", "p2_DOWN"]:
		assert_true(MwInputMap._same(MwSettings.bindings[key], {"p1_UP": k, "p4_BACK": b, "p2_DOWN": m}[key]), key)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.load_file()
	assert_eq([MwSettings.camera, MwSettings.enhance_audio, MwSettings.fullscreen, MwSettings.bindings],
			[0, true, false, {}], "no file: the defaults")
	assert_eq(MwSettings.view(), MwRinkViews.FLAT)
	MwSettings.path = saved[0]
	MwSettings.camera = saved[1]
	MwSettings.enhance_audio = saved[2]
	MwSettings.bindings = saved[3]
	MwSettings.fullscreen = saved[4]


func test_player_one_view_switch() -> void:
	var saved := MwSettings.bindings
	MwSettings.bindings = {}
	MwInputMap.install()
	var ev := InputMap.action_get_events(MwInputMap.VIEW_TOGGLE)
	assert_eq(ev.size(), 2)
	assert_eq((ev[0] as InputEventKey).physical_keycode, KEY_V)
	assert_eq([(ev[1] as InputEventJoypadButton).device, (ev[1] as InputEventJoypadButton).button_index],
			[0, JOY_BUTTON_Y], "the first pad's north button, free in the Genesis layout")
	for p in range(1, MwVerbs.PLAYERS + 1):
		for e in MwInputMap.default_events(p, "A") + MwInputMap.default_events(p, "B") + MwInputMap.default_events(p, "C"):
			assert_false(e is InputEventJoypadButton and e.button_index == JOY_BUTTON_Y, "Y is no Genesis button")
	assert_false(MwInputMap.VIEW_TOGGLE in MwVerbs.all_actions(), "no gameplay verb")
	assert_eq(MwInputMap.default_events(2, "VIEW").size(), 0, "player 1's only")
	var n := InputEventKey.new()
	n.physical_keycode = KEY_N
	MwSettings.bindings = {"p1_VIEW": n}
	MwInputMap.install()
	ev = InputMap.action_get_events(MwInputMap.VIEW_TOGGLE)
	assert_eq(ev.size(), 1, "rebound: one input")
	assert_eq((ev[0] as InputEventKey).physical_keycode, KEY_N)
	MwSettings.bindings = saved
	MwInputMap.install()


func test_function_keys_are_never_bindable() -> void:
	for code in [KEY_F1, KEY_F8, KEY_F12, KEY_F35]:
		var f := InputEventKey.new()
		f.physical_keycode = code
		f.pressed = true
		assert_false(MwSettings.bindable(f))
		assert_null(MwSettings.normalized(f))
	var k := InputEventKey.new()
	k.physical_keycode = KEY_ESCAPE
	assert_true(MwSettings.bindable(k))


func test_event_names() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_ENTER
	assert_eq(MwSettings.event_name(k), "ENTER")
	var b := InputEventJoypadButton.new()
	b.device = 1
	b.button_index = JOY_BUTTON_DPAD_UP
	assert_eq(MwSettings.event_name(b), "PAD2 DPAD UP")
	var m := InputEventJoypadMotion.new()
	m.device = 0
	m.axis = JOY_AXIS_LEFT_Y
	m.axis_value = -0.8
	assert_eq(MwSettings.event_name(MwSettings.normalized(m)), "PAD1 LS UP")
	m.axis_value = 0.2
	assert_null(MwSettings.normalized(m), "a stick barely moved is no input")
