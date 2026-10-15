extends GutTest
## The shot heights' input side (owner, 2026-10-09; MwSettings.shot_heights,
## MwVerbs.SHOT_HEIGHTS): HIGH SHOT / LOW SHOT on the STANDARD layout's
## triggers (and player 1's keys) only while the option is on, none in the
## GENESIS layout; the height each STANDARD player holds, sampled in play
## only, carried by the frames and the pads to the simulation.

var _saved := []


func before_all() -> void:
	_saved = [null, MwSettings.shot_heights, MwSettings.bindings, MwSettings.layouts,
			MwSettings.sticks, MwSettings.path]


func after_all() -> void:
	MwSettings.shot_heights = _saved[1]
	MwSettings.bindings = _saved[2]
	MwSettings.layouts = _saved[3]
	MwSettings.sticks = _saved[4]
	MwSettings.path = _saved[5]
	MwInputMap.install()


func before_each() -> void:
	MwSettings.shot_heights = false
	MwSettings.bindings = {}
	MwSettings.layouts = {}
	MwSettings.sticks = {}
	MwInputMap.install()


func _trigger(action: String, device: int, axis: JoyAxis) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.device == device and event.axis == axis and event.axis_value > 0:
			return true
	return false


func _key(action: String, code: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == code:
			return true
	return false


func test_the_height_held() -> void:
	assert_eq(MwLiveInput.height_of({}, 1), 0, "neither: the middle height")
	assert_eq(MwLiveInput.height_of({"p1_shot_high": true}, 1), 1, "HIGH SHOT")
	assert_eq(MwLiveInput.height_of({"p1_shot_low": true}, 1), 2, "LOW SHOT")
	assert_eq(MwLiveInput.height_of({"p1_shot_high": true, "p1_shot_low": true}, 1), 0, "both: they cancel")
	assert_eq(MwLiveInput.height_of({"p2_shot_high": true}, 1), 0, "another player's")
	assert_eq(MwLiveInput.height_of({"p2_shot_high": true}, 2), 1)


func test_heights_only_in_play_with_the_option() -> void:
	var live := MwLiveInput.new()
	live.sample([MwVerbs.Context.GAMEPLAY])
	assert_eq(live.heights(), [], "off: the D-pad's for everyone (the original)")
	MwSettings.shot_heights = true
	live.sample([MwVerbs.Context.GAMEPLAY, MwVerbs.Context.PAUSE])
	var none := []
	none.resize(MwVerbs.PLAYERS)
	none.fill(0)
	assert_eq(live.heights(), none, "on: each STANDARD player's, all twelve (nothing held)")
	live.sample([MwVerbs.Context.MENU])
	assert_eq(live.heights(), [], "menus: none")
	MwSettings.layouts = {2: "GENESIS", 12: "GENESIS"}
	live.sample([MwVerbs.Context.GAMEPLAY])
	var want := none.duplicate()
	want[1] = -1
	want[11] = -1
	assert_eq(live.heights(), want, "a GENESIS player's D-pad lifts his shots")
	assert_eq(MwInputSource.new().heights(), [], "other sources (scripted input): none")


func test_frames_and_pads_carry_the_height() -> void:
	var input := MwInputFrame.make({"p2_move_up": true}, {})
	assert_eq(input.height(2), -1, "no heights: the D-pad's")
	input.heights = [1, 2, 0, -1, 0, 0, 0, 0, 0, 0, 0, 2]
	assert_eq([input.height(1), input.height(2), input.height(3), input.height(4), input.height(5)], [1, 2, 0, -1, 0])
	assert_eq([input.height(12), input.height(13)], [2, -1], "player 12's; none past the twelfth")
	var r := MwGameplayPads.read(input, 2)
	assert_eq(r["height"], 2)
	assert_eq(r["held"], 0x01, "the D-pad as before")
	assert_eq(MwGameplayPads.read(null, 1)["height"], -1)


func test_the_standard_layout_puts_them_on_the_triggers() -> void:
	MwSettings.shot_heights = true
	MwInputMap.install()
	for p in range(1, MwVerbs.PLAYERS + 1):
		assert_true(_trigger("p%d_shot_high" % p, p - 1, JOY_AXIS_TRIGGER_RIGHT), "player %d: HIGH SHOT on RT" % p)
		assert_true(_trigger("p%d_shot_low" % p, p - 1, JOY_AXIS_TRIGGER_LEFT), "player %d: LOW SHOT on LT" % p)
	assert_true(_key("p1_shot_high", KEY_A) and _key("p1_shot_low", KEY_SHIFT), "arrows / Z X C: A and Shift")
	for event in InputMap.action_get_events("p2_shot_high"):
		assert_false(event is InputEventKey, "plan 34: the keyboard is player 1's")


func test_none_while_off_or_in_the_genesis_layout() -> void:
	for v in MwVerbs.SHOT_HEIGHTS:
		assert_true(MwInputMap.unused(1, v), "off: %s unused" % v)
		assert_true(InputMap.action_get_events("p1_" + v).is_empty(), "off: no inputs")
	MwSettings.shot_heights = true
	MwSettings.layouts = {1: "GENESIS"}
	MwInputMap.install()
	for v in MwVerbs.SHOT_HEIGHTS:
		assert_true(MwInputMap.unused(1, v), "GENESIS: %s unused" % v)
		assert_true(InputMap.action_get_events("p1_" + v).is_empty(), "GENESIS: no inputs")
		assert_false(MwInputMap.unused(2, v), "player 2 (STANDARD) has them")
	var rt := InputEventJoypadMotion.new()
	rt.device = 0
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	MwSettings.bindings = {"p1_shot_high": rt}
	MwInputMap.install()
	assert_true(InputMap.action_get_events("p1_shot_high").is_empty(), "GENESIS ignores a binding of them")


func test_no_collisions_with_them_on() -> void:
	MwSettings.shot_heights = true
	for l in MwInputMap.LAYOUTS:
		var layouts := {}
		for p in range(1, MwVerbs.PLAYERS + 1):
			layouts[p] = l
		MwSettings.layouts = layouts
		assert_eq(MwInputMap.collisions(), {}, "%s, twelve players" % l)


func test_a_trigger_bound_to_another_gameplay_verb_collides() -> void:
	MwSettings.shot_heights = true
	var rt := InputEventJoypadMotion.new()
	rt.device = 0
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	MwSettings.bindings = {"p1_pass": rt}
	var c := MwInputMap.collisions()
	assert_true(c.has("p1_pass") and c.has("p1_shot_high"), "both shown red")


func test_the_option_is_saved() -> void:
	MwSettings.path = "user://test_shot_heights_%d.cfg" % Time.get_ticks_usec()
	MwSettings.shot_heights = true
	MwSettings.save()
	MwSettings.shot_heights = false
	MwSettings.load_file()
	assert_true(MwSettings.shot_heights, "saved and read back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.load_file()
	assert_false(MwSettings.shot_heights, "no file: off (the original's)")
	MwSettings.path = _saved[5]
