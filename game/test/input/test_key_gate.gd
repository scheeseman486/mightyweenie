extends GutTest
## The keyboard's verbs held back while a text input types (MwKeyGate, read
## by MwLiveInput; owner, 2026-10-10: keyboard bindings fired while typing):
## real key, button and stick events through Godot's Input, the
## default bindings (player 1's keyboard, gamepad 0).
## Short names: f the MwTextField under test.

var live: MwLiveInput
var _down := {}                     # the keys this test holds: let go after it


func before_each() -> void:
	MwSettings.bindings = {}
	MwSettings.layouts = {}
	MwInputMap.install()
	MwKeyGate.reset()
	live = MwLiveInput.new()


func after_each() -> void:
	for code: Key in _down.keys():
		_key(code, false)
	_button(JOY_BUTTON_A, false)
	_stick(0.0)
	MwKeyGate.reset()


func _key(code: Key, down: bool, ch := 0) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.unicode = ch if down else 0
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	if down:
		_down[code] = true
	else:
		_down.erase(code)


func _button(b: JoyButton, down: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = b
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _stick(y: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_LEFT_Y
	event.axis_value = y
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## One tick of the live input: what it holds and what was pressed.
func _tick() -> Array:
	live.tick()
	return [live.sample([MwVerbs.Context.PASSWORD]), live.taps()]


func test_keys_drive_verbs_until_a_text_input_types() -> void:
	_key(KEY_Z, true, 0x7A)
	var got := _tick()
	assert_true(got[0].has("ui_pick_letter"), "Z: player 1's A, PICK LETTER")
	assert_true(got[1].has("ui_pick_letter"), "pressed")
	_key(KEY_Z, false)
	_tick()
	var f := MwTextField.new()
	f.begin()
	assert_true(MwKeyGate.taking(), "the field has the keyboard")
	for code: Key in [KEY_Z, KEY_X, KEY_C, KEY_A, KEY_S, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_F, KEY_V,
			KEY_ENTER, KEY_ESCAPE, KEY_UP, KEY_LEFT, KEY_SHIFT]:
		_key(code, true)
		got = _tick()
		assert_eq(got[0], {}, "%s held: no verb" % OS.get_keycode_string(code))
		assert_eq(got[1], {}, "%s pressed: no verb" % OS.get_keycode_string(code))
		_key(code, false)
	_button(JOY_BUTTON_A, true)
	got = _tick()
	assert_true(got[0].has("ui_pick_letter"), "the gamepad's south still picks (STANDARD)")
	assert_true(got[1].has("ui_pick_letter"))
	_button(JOY_BUTTON_A, false)
	_stick(-1.0)
	assert_true(_tick()[0].has("ui_up"), "and its stick moves")
	_stick(0.0)
	_tick()
	f.finish(true)
	assert_false(MwKeyGate.active())
	_key(KEY_X, true)
	assert_true(_tick()[0].has("ui_erase_letter"), "live again")


func test_the_key_that_ends_it_is_no_press_until_let_go() -> void:
	var f := MwTextField.new()
	f.begin()
	_key(KEY_ENTER, true)
	assert_eq(f.key(_event(KEY_ENTER)), MwTextField.Result.CONFIRMED)
	assert_false(MwKeyGate.taking(), "given back")
	assert_true(MwKeyGate.active(), "Enter still down: held back")
	for i in 3:
		var while_held := _tick()
		assert_false(while_held[0].has("ui_accept") or while_held[1].has("ui_accept"), "Enter, held on: nothing")
	_key(KEY_ENTER, false)
	_tick()
	assert_false(MwKeyGate.active(), "let go: every key live")
	_key(KEY_ENTER, true)
	var got := _tick()
	assert_true(got[0].has("ui_accept") and got[1].has("ui_accept"), "the next Enter accepts")


func test_a_text_input_gone_gives_the_keyboard_back() -> void:
	var f := MwTextField.new()
	f.begin()
	assert_true(MwKeyGate.taking())
	f = null
	assert_false(MwKeyGate.taking(), "a freed field types nothing")
	var typing := MwTextField.new()
	var field := MwTextField.new()
	typing.begin()
	field.finish(false)
	assert_true(MwKeyGate.taking(), "only the field typing gives it back")
	typing.finish(false)
	assert_false(MwKeyGate.taking())


func _event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event
