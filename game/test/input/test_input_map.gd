extends GutTest
## The bindings per verb (plan 22): every verb for players 1-12 (plan 34)
## in the STANDARD layout (the default) and the GENESIS one, collisions,
## rebinding; RECLAIM; the players' devices.

var _bindings: Dictionary
var _layouts: Dictionary
var _sticks: Dictionary


func before_all() -> void:
	_bindings = MwSettings.bindings
	_layouts = MwSettings.layouts
	_sticks = MwSettings.sticks
	MwSettings.sticks = {}
	MwSettings.bindings = {}
	MwSettings.layouts = {}
	MwInputMap.install()


func after_all() -> void:
	MwSettings.bindings = _bindings
	MwSettings.layouts = _layouts
	MwSettings.sticks = _sticks
	MwInputMap.install()


func before_each() -> void:
	MwSettings.bindings = {}
	MwSettings.layouts = {}
	MwSettings.sticks = {}
	MwInputMap.install()


func _has_key(action: String, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == key:
			return true
	return false


func _has_pad(action: String, device: int, button: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.device == device and event.button_index == button:
			return true
	return false


func test_every_action_exists() -> void:
	for a in MwVerbs.all_actions():
		assert_true(InputMap.has_action(a), a)
	var menu := MwVerbs.menu_verbs().size()
	assert_eq(MwVerbs.all_actions().size(), menu + MwVerbs.PLAYERS * (MwVerbs.player_verbs().size() + menu))
	assert_eq(MwVerbs.PLAYERS, 12, "plan 34: twelve players")
	assert_true(InputMap.has_action(MwInputMap.VIEW_TOGGLE))
	for v in MwVerbs.all_verbs():
		assert_true(MwVerbs.LABELS.has(v), "%s has a label" % v)
		var paged := MwVerbs.PAGES.any(func(pg: Array) -> bool: return v in pg[1])
		assert_true(paged, "%s is on a bindings page" % v)


func test_player_one_keyboard_and_pad() -> void:
	assert_true(_has_key("p1_pass", KEY_X), "X = B = pass")
	for v in ["p1_wrist_shot", "p1_slap_shot", "p1_check"]:
		assert_true(_has_key(v, KEY_C), "C = C = %s" % v)
	assert_true(_has_key("p1_punch", KEY_Z), "Z = A = punch")
	assert_true(_has_key("p1_pause", KEY_ENTER))
	assert_true(_has_key("p1_move_left", KEY_LEFT) and _has_key("p1_move_up", KEY_UP))
	assert_false(_has_key("p1_move_left", KEY_A), "no WASD")
	assert_true(_has_pad("p1_pass", 0, JOY_BUTTON_A), "south = B")
	assert_true(_has_pad("p1_punch", 0, JOY_BUTTON_X), "west = A")
	assert_false(_has_pad("p1_pass", 1, JOY_BUTTON_A), "pad 2 is player 2")


## Plan 34: every player has a gamepad (device player - 1); the keyboard is
## player 1's alone.
func test_twelve_players_each_on_their_gamepad() -> void:
	for p in range(2, MwVerbs.PLAYERS + 1):
		assert_true(_has_pad("p%d_pass" % p, p - 1, JOY_BUTTON_A), "player %d: pad %d" % [p, p])
		assert_true(_has_pad("p%d_ui_accept" % p, p - 1, JOY_BUTTON_START))
		assert_true(_has_pad("ui_accept", p - 1, JOY_BUTTON_START), "every pad drives the menus")
		assert_false(InputMap.action_get_events("p%d_pass" \
				% p).any(func(e: InputEvent) -> bool: return e is InputEventKey),
				"player %d: no keys" % p)


func test_other_contexts_use_the_same_buttons() -> void:
	assert_true(_has_key("p1_fight_punch", KEY_X) and _has_key("p1_fight_punch", KEY_C), "B or C punch")
	assert_true(_has_key("p1_fight_block", KEY_Z))
	assert_true(_has_key("p1_move_left", KEY_LEFT), "fighters move left/right (manual)")
	assert_true(_has_key("p1_replay_exit", KEY_ENTER))
	assert_true(_has_pad("p4_replay_rewind", 3, JOY_BUTTON_X))
	assert_true(_has_pad("p12_replay_rewind", 11, JOY_BUTTON_X))
	assert_true(_has_pad("p3_zamboni_whip", 2, JOY_BUTTON_DPAD_UP))


func test_menus_take_every_players_buttons() -> void:
	assert_true(_has_key("ui_accept", KEY_ENTER))
	for d in MwVerbs.PLAYERS:
		assert_true(_has_pad("ui_accept", d, JOY_BUTTON_START), "start on pad %d" % (d + 1))
		assert_true(_has_pad("ui_accept", d, JOY_BUTTON_A), "STANDARD: south accepts on pad %d" % (d + 1))
		assert_true(_has_pad("ui_skip", d, JOY_BUTTON_X) and _has_pad("ui_skip", d, JOY_BUTTON_Y)
				and _has_pad("ui_skip", d, JOY_BUTTON_RIGHT_SHOULDER), "a screen's A / B / C: west, north, RB")
	assert_false(_has_key("ui_accept", KEY_SPACE), "Godot's own events replaced")
	assert_true(_has_pad("p1_pass", 0, JOY_BUTTON_A), "south is still pass in play (another context)")


func test_per_player_menu_verbs() -> void:
	assert_true(_has_key("p1_ui_left", KEY_LEFT), "player 1's keys and the permanent menu keys (plan 21)")
	assert_true(_has_key("p1_ui_skip", KEY_Z))
	assert_false(_has_key("p2_ui_left", KEY_LEFT), "player 2: no keyboard")
	assert_true(_has_pad("p3_ui_right", 2, JOY_BUTTON_DPAD_RIGHT))
	assert_false(_has_pad("p3_ui_right", 0, JOY_BUTTON_DPAD_RIGHT))
	assert_true(_has_key("ui_left", KEY_LEFT) and _has_pad("ui_left", 5, JOY_BUTTON_DPAD_LEFT),
			"the shared verb: everyone's")


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

func _count(action: String, event: InputEvent) -> int:
	return InputMap.action_get_events(action).filter(func(x: InputEvent) -> bool: return MwInputMap._same(x, \
			event)).size()


func test_menu_back_defaults() -> void:
	assert_true(_has_key("ui_back", KEY_ESCAPE) and _has_key("p1_ui_back", KEY_ESCAPE), "Esc")
	for d in MwVerbs.PLAYERS:
		assert_true(_has_pad("ui_back", d, JOY_BUTTON_B), "STANDARD: east on pad %d" % (d + 1))
	assert_true(_has_pad("p2_ui_back", 1, JOY_BUTTON_B) and not _has_pad("p2_ui_back", 0, JOY_BUTTON_B))
	assert_false(_has_pad("ui_view_replay", 0, JOY_BUTTON_B), "east is no screen's C in STANDARD (owner)")
	assert_true(_has_pad("p1_wrist_shot", 0, JOY_BUTTON_B), "but still the shot in play")
	MwSettings.layouts = _every("GENESIS")
	MwInputMap.install()
	for d in MwVerbs.PLAYERS:
		assert_true(_has_pad("ui_back", d, JOY_BUTTON_BACK), "GENESIS: Select on pad %d" % (d + 1))
		assert_false(_has_pad("ui_back", d, JOY_BUTTON_B))
	assert_true(_has_pad("ui_view_replay", 0, JOY_BUTTON_B), "GENESIS: the scoreboard's C is east")
	assert_true(_has_key("ui_back", KEY_ESCAPE))


func test_layouts_per_screen() -> void:
	# STANDARD: a screen's choices on west / north / RB; accept south; back east
	var std := {"ui_view_stats": JOY_BUTTON_X, "ui_view_special_plays": JOY_BUTTON_Y,
		"ui_view_replay": JOY_BUTTON_RIGHT_SHOULDER, "ui_stats_switch": JOY_BUTTON_X,
		"ui_starfield_stop": JOY_BUTTON_Y, "ui_starfield_turn": JOY_BUTTON_RIGHT_SHOULDER,
		"ui_pick_letter": JOY_BUTTON_A, "ui_choose_play": JOY_BUTTON_A, "ui_next_page": JOY_BUTTON_A}
	for v in std:
		assert_true(_has_pad(v, 0, std[v]), "STANDARD %s" % v)
	assert_true(_has_pad("p1_replay_exit", 0, JOY_BUTTON_A) and _has_pad("p1_replay_rewind", 0, JOY_BUTTON_X))
	for v in MwInputMap.STANDARD_UNUSED:
		assert_true(InputMap.action_get_events(v).is_empty(),
				"STANDARD: %s has no inputs (the port's pause menu's items)" % v)
		assert_true(MwInputMap.default_events(1, v, "STANDARD").is_empty())
	# GENESIS: the original's buttons
	MwSettings.layouts = {1: "GENESIS"}
	MwInputMap.install()
	var gen := {"ui_view_stats": JOY_BUTTON_X, "ui_view_special_plays": JOY_BUTTON_A,
		"ui_view_replay": JOY_BUTTON_B, "ui_pause_replay": JOY_BUTTON_X, "ui_pause_timeout": JOY_BUTTON_A,
		"ui_pick_letter": JOY_BUTTON_X,
		"ui_erase_letter": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B}
	for v in gen:
		assert_true(_has_pad(v, 0, gen[v]), "GENESIS %s" % v)
	assert_false(_has_pad("ui_accept", 0, JOY_BUTTON_A), "GENESIS: south is B, not Start")
	for v in MwVerbs.all_verbs():
		if v in MwInputMap.STANDARD_PAD_ONLY or v in MwInputMap.STANDARD_UNUSED or v in MwInputMap.GENESIS_UNUSED:
			continue
		assert_eq(_keys(v, "STANDARD"), _keys(v, "GENESIS"), "%s: the keyboard is the same in both" % v)
	assert_eq(_keys("ui_pause_replay", "STANDARD"), [], "STANDARD: no key for the pause menu's REPLAY shortcut")
	assert_eq(_keys("ui_pause_replay", "GENESIS"), [MwInputMap.KEYS[1]["A"]], "GENESIS: the lettered menu's A")
	assert_eq(_keys("ui_resume", "STANDARD"), [], "STANDARD: Start's resume is the gamepad's only (Enter picks)")
	assert_eq(_keys("ui_resume", "GENESIS"), [MwInputMap.KEYS[1]["START"]], "GENESIS: Enter resumes")
	assert_eq(_keys("ui_skip", "STANDARD"), [MwInputMap.KEYS[1]["A"], MwInputMap.KEYS[1]["B"], MwInputMap.KEYS[1]["C"]],
			"a screen's A / B / C keys")


## Player 1's default keys for [param verb] in [param layout].
func _keys(verb: String, layout: String) -> Array:
	var out := []
	for event in MwInputMap.default_events(1, verb, layout):
		if event is InputEventKey:
			out.append(event.physical_keycode)
	return out


func test_no_collisions_in_either_layout() -> void:
	for l in MwInputMap.LAYOUTS:
		MwSettings.layouts = _every(l)
		assert_eq(MwInputMap.collisions(), {}, l)
	MwSettings.layouts = {1: "STANDARD", 2: "GENESIS"}
	assert_eq(MwInputMap.collisions(), {}, "mixed")


## Every player in layout [param l].
static func _every(l: String) -> Dictionary:
	var out := {}
	for p in range(1, MwVerbs.PLAYERS + 1):
		out[p] = l
	return out


func test_a_collision_marks_both_verbs() -> void:
	var rb := InputEventJoypadButton.new()
	rb.device = 0
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	MwSettings.bindings = {"p1_ui_view_stats": rb}
	var c := MwInputMap.collisions()
	assert_true(c.has("p1_ui_view_stats") and c.has("p1_ui_view_replay"), "the scoreboard's stats and replay on RB")
	assert_false(c.has("p1_ui_starfield_turn"), "the stats screen's RB is fine: stats isn't live there")
	var j := InputEventKey.new()
	j.physical_keycode = KEY_X
	MwSettings.bindings = {"p1_slap_shot": j}
	c = MwInputMap.collisions()
	assert_true(c.has("p1_slap_shot") and c.has("p1_pass"), "X: pass's group and the shot's")
	assert_false(c.has("p1_wrist_shot"), "the shot's other verbs are on C")
	MwSettings.bindings = {"p2_pass": j}
	c = MwInputMap.collisions()
	assert_true(c.has("p2_pass") and c.has("p1_pass"), "two players' pass on one key")
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	MwSettings.bindings = {"p1_ui_skip": enter}
	c = MwInputMap.collisions()
	assert_true(c.has("p1_ui_skip") and c.has("p1_ui_accept"), "Enter is accept's permanent key")
	MwSettings.bindings = {}


func test_permanent_menu_keys() -> void:
	for k in MwInputMap.MENU_KEYS:
		for verb in MwInputMap.MENU_KEYS[k]:
			assert_true(_has_key(verb, k), "%s on its permanent key" % verb)
			assert_true(_has_key(MwVerbs.menu_action(1, verb), k), "and player 1's")
	assert_true(_has_key("p1_move_up", KEY_UP), "player 1 skates on the arrows too")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_UP
	assert_eq(_count("ui_up", up), 1, "player 1's Up arrow and the permanent one: once")


## The STANDARD layout's unused verbs (the original's pause menu's A / B)
## ignore a binding left from the GENESIS layout; GENESIS takes it.
func test_standard_ignores_its_unused_verbs_bindings() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	MwSettings.bindings = {"p1_ui_pause_replay": event}
	MwInputMap.install()
	assert_true(InputMap.action_get_events("p1_ui_pause_replay").is_empty(), "STANDARD: nothing")
	assert_true(MwInputMap.unused(1, "ui_pause_timeout"))
	assert_false(MwInputMap.unused(1, "ui_resume"))
	MwSettings.layouts = {1: "GENESIS"}
	MwInputMap.install()
	assert_eq(InputMap.action_get_events("p1_ui_pause_replay"), [event] as Array[InputEvent], "GENESIS: the bound key")
	assert_false(MwInputMap.unused(1, "ui_pause_timeout"))
	assert_eq(MwInputMap.collisions(), {})
	MwSettings.layouts = {}
	MwSettings.bindings = {}
	MwInputMap.install()


func test_a_rebound_verb_holds_one_input() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	MwSettings.bindings = {"p1_punch": event}
	MwInputMap.install()
	assert_eq(InputMap.action_get_events("p1_punch"), [event] as Array[InputEvent])
	assert_true(_has_key("p1_dive", KEY_Z) and not _has_key("p1_dive", KEY_W), "one verb at a time")
	assert_true(_has_key("p1_fight_block", KEY_Z), "another context's verb on A keeps its own")
	MwSettings.bindings = {"p1_ui_skip": event}
	MwInputMap.install()
	assert_true(_has_key("ui_skip", KEY_W) and _has_pad("ui_skip", 1, JOY_BUTTON_X), "the shared verb: every player's")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_UP
	MwSettings.bindings = {"p1_ui_up": up, "p1_pause": up}
	MwInputMap.install()
	assert_eq(_count("p1_ui_up", up), 1, "bound to a permanent key of the same verb: no double input")
	assert_true(_has_key("p1_pause", KEY_UP), "one key on two verbs is allowed")
	var pad := InputEventJoypadMotion.new()
	pad.device = 2
	pad.axis = JOY_AXIS_RIGHT_X
	pad.axis_value = 1.0
	MwSettings.bindings = {"p1_wrist_shot": pad}
	MwInputMap.install()
	assert_eq(InputMap.action_get_events("p1_wrist_shot"), [pad] as Array[InputEvent],
			"any device, any player (no gating)")
	MwSettings.bindings = {}
	MwInputMap.install()


func _motion(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var m := InputEventJoypadMotion.new()
	m.device = device
	m.axis = axis
	m.axis_value = value
	return m


func _has_axis(action: String, device: int, axis: JoyAxis, value: float) -> bool:
	return InputMap.action_get_events(action).any(func(e: InputEvent) -> bool:
		return e is InputEventJoypadMotion and e.device == device and e.axis == axis and e.axis_value == value)


func test_sticks_drive_the_direction_verbs() -> void:
	for p in range(1, MwVerbs.PLAYERS + 1):
		assert_true(_has_axis("p%d_move_up" % p, p - 1, JOY_AXIS_LEFT_Y, -1.0), "the left stick by default (%d)" % p)
		assert_true(_has_axis("p%d_move_right" % p, p - 1, JOY_AXIS_LEFT_X, 1.0))
		assert_true(_has_axis("p%d_ui_down" % p, p - 1, JOY_AXIS_LEFT_Y, 1.0), "the menus' too")
	assert_true(_has_axis("p1_zamboni_whip", 0, JOY_AXIS_LEFT_Y, -1.0), "the whip as before")
	assert_eq(MwInputMap.default_events(1, "move_up").filter(func(e): return e is InputEventJoypadMotion), [],
			"the D-pad binding holds no stick")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_I
	MwSettings.bindings = {"p1_move_up": k}
	MwInputMap.install()
	assert_true(_has_key("p1_move_up", KEY_I) and not _has_pad("p1_move_up", 0, JOY_BUTTON_DPAD_UP),
			"the D-pad rebound")
	assert_true(_has_axis("p1_move_up", 0, JOY_AXIS_LEFT_Y, -1.0), "the stick stays")
	var saved_path := MwSettings.path
	MwSettings.path = "user://test_sticks_%d.cfg" % Time.get_ticks_usec()
	MwSettings.set_stick(1, "move_stick", _motion(2, JOY_AXIS_RIGHT_X, -1.0))
	assert_true(_has_axis("p1_move_up", 2, JOY_AXIS_RIGHT_Y, -1.0)
			and _has_axis("p1_move_down", 2, JOY_AXIS_RIGHT_Y, 1.0)
			and _has_axis("p1_move_left", 2, JOY_AXIS_RIGHT_X, -1.0)
			and _has_axis("p1_move_right", 2, JOY_AXIS_RIGHT_X, 1.0),
			"the whole right stick of pad 3, whichever way it was moved")
	assert_false(_has_axis("p1_move_up", 0, JOY_AXIS_LEFT_Y, -1.0), "instead of the left")
	assert_true(_has_axis("p1_ui_up", 0, JOY_AXIS_LEFT_Y, -1.0), "the menus keep theirs")
	MwSettings.set_stick(1, "move_stick", _motion(2, JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_true(_has_axis("p1_move_up", 0, JOY_AXIS_LEFT_Y, -1.0), "not a stick: back to the layout's")
	MwSettings.set_stick(1, "ui_stick", _motion(0, JOY_AXIS_RIGHT_Y, 1.0))
	MwSettings.sticks = {}
	MwSettings.load_file()
	assert_true(MwInputMap._same(MwSettings.stick_binding(1, "ui_left"), _motion(0, JOY_AXIS_RIGHT_X, -1.0)), "saved")
	MwSettings.set_layout(1, "GENESIS")
	assert_true(MwSettings.sticks.is_empty(), "a new layout: the layout's sticks")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.path = saved_path


func test_a_stick_collision_marks_the_stick() -> void:
	MwSettings.bindings = {"p1_pass": _motion(0, JOY_AXIS_LEFT_Y, -1.0)}
	MwInputMap.install()
	var c := MwInputMap.collisions()
	assert_true(c.has("p1_pass"), "the pass")
	assert_true(c.has("p1_move_up" + MwInputMap.STICK_MARK), "the skating stick's up")
	assert_false(c.has("p1_move_up"), "not its D-pad")
	assert_false(c.has("p1_ui_up" + MwInputMap.STICK_MARK), "the menus' stick lives elsewhere")


func test_set_layout_starts_afresh() -> void:
	var saved_path := MwSettings.path
	MwSettings.path = "user://test_layout_%d.cfg" % Time.get_ticks_usec()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_Q
	MwSettings.bindings = {"p1_punch": event, "p2_punch": event}
	MwSettings.set_layout(1, "GENESIS")
	assert_eq(MwSettings.layout(1), "GENESIS")
	assert_false(MwSettings.bindings.has("p1_punch"), "player 1's own bindings go")
	assert_true(MwSettings.bindings.has("p2_punch"), "player 2's stay")
	assert_eq(MwSettings.layout(2), "STANDARD", "the default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.path = saved_path


func test_settings_round_trip() -> void:
	var saved := [MwSettings.path, MwSettings.camera, MwSettings.enhance_audio, MwSettings.bindings,
			MwSettings.fullscreen, MwSettings.aspect]
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
	MwSettings.aspect = "WIDE"
	MwSettings.bindings = {"p1_ui_up": k, "p4_ui_back": b, "p2_move_down": m, "p1_punch": f}
	MwSettings.layouts = {2: "GENESIS"}
	MwSettings.analogue = false
	MwSettings.save()
	MwSettings.camera = 0
	MwSettings.enhance_audio = true
	MwSettings.fullscreen = false
	MwSettings.aspect = "ORIGINAL"
	MwSettings.bindings = {}
	MwSettings.layouts = {}
	MwSettings.load_file()
	assert_eq(MwSettings.aspect, "WIDE")
	assert_eq([MwSettings.layout(1), MwSettings.layout(2)], ["STANDARD", "GENESIS"])
	assert_false(MwSettings.analogue)
	assert_eq(MwSettings.camera_name(), "3D")
	assert_eq(MwSettings.view(), MwRinkViews.FOLLOW, "3D: the follow camera")
	assert_false(MwSettings.enhance_audio)
	assert_true(MwSettings.fullscreen)
	assert_false(MwSettings.bindings.has("p1_punch"), "a function key in the file is dropped")
	assert_eq(MwSettings.bindings.size(), 3)
	var want := {"p1_ui_up": k, "p4_ui_back": b, "p2_move_down": m}
	for key in want:
		assert_true(MwInputMap._same(MwSettings.bindings[key], want[key]), key)
	# plan 21's per-button bindings: the verbs that were on the button
	var cfg := ConfigFile.new()
	cfg.set_value("bindings", "p1_A", MwInputMap.encode_event(k))
	cfg.set_value("bindings", "p1_BACK", MwInputMap.encode_event(b))
	cfg.save(MwSettings.path)
	MwSettings.load_file()
	for v in ["punch", "dive", "special_play", "fight_block", "replay_rewind", "ui_view_stats", "ui_skip"]:
		assert_true(MwSettings.binding(1, v) != null and MwInputMap._same(MwSettings.binding(1, v), k), "A -> %s" % v)
	assert_true(MwInputMap._same(MwSettings.binding(1, "ui_back"), b), "BACK -> Menu Back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.load_file()
	assert_eq([MwSettings.camera, MwSettings.enhance_audio, MwSettings.fullscreen, MwSettings.bindings,
			MwSettings.analogue, MwSettings.layouts, MwSettings.aspect], [0, true, false, {}, true, {}, "ORIGINAL"],
			"no file: the defaults")
	assert_eq(MwSettings.view(), MwRinkViews.FLAT)
	MwSettings.path = saved[0]
	MwSettings.camera = saved[1]
	MwSettings.enhance_audio = saved[2]
	MwSettings.apply_audio()                 # the switches it drives (the crowd's noise...) as they were
	MwSettings.bindings = saved[3]
	MwSettings.fullscreen = saved[4]
	MwSettings.aspect = saved[5]


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
		for v in MwVerbs.GAMEPLAY:
			for event in MwInputMap.default_events(p, v):
				assert_false(event is InputEventJoypadButton and event.button_index == JOY_BUTTON_Y,
						"Y is no gameplay button")
	assert_false(MwInputMap.VIEW_TOGGLE in MwVerbs.all_actions(), "no screen's verb")
	assert_eq(MwInputMap.default_events(2, MwInputMap.VIEW_TOGGLE).size(), 0, "player 1's only")
	var n := InputEventKey.new()
	n.physical_keycode = KEY_N
	MwSettings.bindings = {"p1_view_toggle": n}
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
		assert_false(MwInputMap.bindable(f))
		assert_null(MwInputMap.normalized(f))
	var k := InputEventKey.new()
	k.physical_keycode = KEY_ESCAPE
	assert_true(MwInputMap.bindable(k))


func test_event_names() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_ENTER
	assert_eq(MwInputMap.event_name(k), "ENTER")
	var b := InputEventJoypadButton.new()
	b.device = 1
	b.button_index = JOY_BUTTON_DPAD_UP
	assert_eq(MwInputMap.event_name(b), "PAD2 DPAD UP")
	var m := InputEventJoypadMotion.new()
	m.device = 0
	m.axis = JOY_AXIS_LEFT_Y
	m.axis_value = -0.8
	assert_eq(MwInputMap.event_name(MwInputMap.normalized(m)), "PAD1 LS UP")
	m.axis_value = 0.2
	assert_null(MwInputMap.normalized(m), "a stick barely moved is no input")


func test_alt_enter_is_the_display_switch_only() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	assert_false(MwSettings.is_display_toggle(event), "Enter alone is Start / select")
	event.alt_pressed = true
	assert_true(MwSettings.is_display_toggle(event))
	event.echo = true
	assert_false(MwSettings.is_display_toggle(event), "not its repeats")
	event.echo = false
	event.keycode = KEY_KP_ENTER
	event.physical_keycode = KEY_KP_ENTER
	assert_true(MwSettings.is_display_toggle(event), "the keypad's Enter too")
	var was := MwSettings.fullscreen
	MwSettings.toggle_fullscreen()            # headless: flipped, nothing saved or shown
	assert_ne(MwSettings.fullscreen, was)
	MwSettings.fullscreen = was


func test_alt_enter_presses_nothing() -> void:
	var was := MwSettings.fullscreen
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	event.alt_pressed = true
	var driven := []
	for a in InputMap.get_actions():
		if event.is_action(a):
			driven.append(a)
	assert_gt(driven.size(), 0, "Enter drives Start and the menus' select")
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	for a in driven:
		assert_false(Input.is_action_pressed(a), "%s not pressed" % a)
	assert_ne(MwSettings.fullscreen, was, "the Router switched the display")
	var up := event.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	MwSettings.fullscreen = was


# --- plan 34: RECLAIM, the players' devices --------------------------------------------------------

func test_reclaim() -> void:
	assert_true(_has_pad("p1_reclaim", 0, JOY_BUTTON_LEFT_SHOULDER), "STANDARD: the left shoulder")
	assert_true(_has_pad("p7_reclaim", 6, JOY_BUTTON_LEFT_SHOULDER))
	assert_true(_has_key("p1_reclaim", KEY_Q), "player 1's Q")
	assert_true(MwVerbs.RECLAIM in MwVerbs.player_verbs() and MwVerbs.LABELS.has(MwVerbs.RECLAIM))
	MwSettings.layouts = {1: "GENESIS"}
	MwInputMap.install()
	assert_true(InputMap.action_get_events("p1_reclaim").is_empty(), "GENESIS: none (B tapped twice)")
	assert_true(MwInputMap.unused(1, MwVerbs.RECLAIM))
	assert_true(_has_pad("p2_reclaim", 1, JOY_BUTTON_LEFT_SHOULDER), "player 2 still STANDARD")
	var lb := InputEventJoypadButton.new()
	lb.device = 0
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	MwSettings.layouts = {}
	MwSettings.bindings = {"p1_pass": lb}
	assert_true(MwInputMap.collisions().has("p1_reclaim"), "a gameplay verb on its input collides")
	MwSettings.bindings = {}
	MwInputMap.install()


func test_players_devices() -> void:
	assert_eq(MwInputMap.pad_device(5), 4, "player 5: the fifth gamepad")
	assert_true(MwInputMap.uses_keyboard(1))
	assert_false(MwInputMap.uses_keyboard(5))
	assert_true(MwInputMap.connected(1), "the keyboard is always there")
	assert_eq(MwInputMap.connected(12), 11 in Input.get_connected_joypads())
	assert_true(MwInputMap.device_tag(12).ends_with("12"), "a gamepad's tag, its number")
	var b := InputEventJoypadButton.new()
	b.device = 8
	b.button_index = JOY_BUTTON_A
	MwSettings.bindings = {"p5_pass": b}
	assert_eq(MwInputMap.pad_device(5), 8, "a bound gamepad")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_T
	MwSettings.bindings = {"p6_pass": k}
	assert_true(MwInputMap.uses_keyboard(6), "a bound key")
	assert_true(MwInputMap.connected(6))
	if not 5 in Input.get_connected_joypads():
		assert_eq(MwInputMap.device_tag(6), "KEYS", "its gamepad away: the keyboard")
	MwSettings.bindings = {}
	var before := MwInputMap.devices_changed
	MwInputMap._joy_changed(3, true)
	assert_eq(MwInputMap.devices_changed, before + 1, "a gamepad coming or going is noted")
