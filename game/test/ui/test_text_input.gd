extends "res://test/rom/rom_test_base.gd"
## One text input for CREATE-A-TEAM and the online pages (owner,
## 2026-10-10): the field's options (MwTextField), its text input screens
## (MwTextInputScreen: CREATE-A-TEAM's text entry 131 and the online pages'
## keyboard 123), and the bindings gated while it types - real key, button
## and stick events through Godot's Input, the router reading them with
## MwLiveInput as the game does: player 1's bound letters type and drive
## nothing, the pads still pick, Enter and Esc end it with no press left
## over for the screen underneath.

const TEST_DIR := "user://test_text_input"

var host: Node
var router: MwRouter
var _down := {}                     # the keys held: let go after each test
var _kept := {}
var _clip := ""


func before_all() -> void:
	super.before_all()
	_kept = {"path": MwSettings.path, "port": MwSettings.net_port, "address": MwSettings.net_address,
			"get": MwTextField.clipboard_get, "teams": MwCustomTeams.dir}
	MwSettings.path = "user://test_text_input_%d.cfg" % Time.get_ticks_usec()


func after_all() -> void:
	if FileAccess.file_exists(MwSettings.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.path = _kept["path"]
	MwSettings.net_port = _kept["port"]
	MwSettings.net_address = _kept["address"]
	MwTextField.clipboard_get = _kept["get"]


func before_each() -> void:
	MwCustomTeams.clear()
	MwCustomTeams.dir = TEST_DIR
	MwSettings.bindings = {}
	MwSettings.layouts = {}
	MwSettings.net_address = ""
	MwInputMap.install()
	MwKeyGate.reset()
	MwTextField.clipboard_get = func() -> String: return _clip


func after_each() -> void:
	for code: Key in _down.keys():
		_key(code, false)
	_button(JOY_BUTTON_A, false)
	_button(JOY_BUTTON_DPAD_RIGHT, false)
	if host:
		host.free()
		host = null
	MwKeyGate.reset()
	MwEditorMusic.on = false
	MwCustomTeams.clear()
	MwCustomTeams.dir = _kept["teams"]            # (the run's test folder, pre_run.gd)
	var d := DirAccess.open(TEST_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(TEST_DIR)


## Screen [param id] adopted, read through the live input (the game's).
func _start(id: int) -> void:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	router = MwRouter.new(host, fader)
	router.session = MwSession.new(1, 1)
	router.input = MwLiveInput.new()
	var scene := (load(MwScreens.scene_path(id)) as PackedScene).instantiate() as MwScreen
	scene.screen_id = id
	router.adopt(scene, {})
	fader.uncover()


## Screen [param id] adopted with [param data], read through the live input.
func _start_with(id: int, data: Dictionary) -> void:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	router = MwRouter.new(host, fader)
	router.session = MwSession.new(1, 1)
	router.input = MwLiveInput.new()
	var scene := (load(MwScreens.scene_path(id)) as PackedScene).instantiate() as MwScreen
	scene.screen_id = id
	router.adopt(scene, data)
	fader.uncover()


func _run(ticks: int) -> void:
	for i in ticks:
		router.step()


## Steps until a screen other than [param was] is on top, settled.
func _until_new(was: Node, limit := 600) -> bool:
	for i in limit:
		router.step()
		if router.current() != was and not router.busy():
			_run(4)
			return true
	return false


func _until(id: int, limit := 600) -> bool:
	for i in limit:
		router.step()
		if router.current_id() == id and not router.busy():
			_run(4)
			return true
	return false


## Key [param code] as the OS sends it ([param ch] its character): Godot's
## Input, then every node's _input.
func _key(code: Key, down: bool, ch := 0, mods := "") -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.unicode = ch if down else 0
	event.pressed = down
	event.ctrl_pressed = "ctrl" in mods
	event.shift_pressed = "shift" in mods
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


## A tap: down for a tick, a frame (Godot's "just pressed" lasts one), let
## go, [param after] ticks.
func _tap(code: Key, ch := 0, mods := "", after := 4) -> void:
	_key(code, true, ch, mods)
	_run(1)
	await get_tree().process_frame
	_key(code, false)
	_run(after)


func _press_button(b: JoyButton) -> void:
	_button(b, true)
	_run(1)
	await get_tree().process_frame
	_button(b, false)
	_run(4)


## Types [param text] on the keyboard, a key a character (letters by their
## keys, capitals with Shift).
func _type(text: String) -> void:
	for c in text:
		var ch := c.unicode_at(0)
		var code: Key = KEY_SPACE
		if c.to_upper() >= "A" and c.to_upper() <= "Z":
			code = KEY_A + (c.to_upper().unicode_at(0) - 0x41) as Key
		elif c >= "0" and c <= "9":
			code = KEY_0 + (ch - 0x30) as Key
		await _tap(code, ch, "shift" if c >= "A" and c <= "Z" else "")


# --- the field and the screens -----------------------------------------------------------------------

func test_a_team_text_field() -> void:
	var field := MwCreateTeam.team_text("name", "TEAM NAME", "", MwCustomTeam.NAME_MAX)
	assert_eq([field.id, field.title, field.limit, field.masked], ["name", "TEAM NAME", 10, false])
	field.begin()
	for c in " ab":
		field.type_char(c.unicode_at(0))
	assert_eq(field.text, "AB", "capitals; no space first")
	assert_eq(field.note(), MwCreateTeam.NAME_NOTE, "the gentle note")
	assert_true(field.type_char(0x20))
	assert_false(field.type_char(0x20), "words one space apart")
	assert_false(field.type_char(0x40), "@: not a character the fonts share")
	field.type_char(0x73)
	assert_eq(field.text, "AB S")
	assert_eq(field.note(), "", "ends in S")
	_clip = "  new  york "
	assert_false(field.paste(), "two spaces: refused")
	assert_eq(field.message, "CAN'T PASTE THAT")
	_clip = "  new york "
	assert_true(field.paste())
	assert_eq(field.text, "NEW YORK", "trimmed, in capitals")
	_clip = "metropolis!"
	assert_false(field.paste())
	assert_eq(field.message, MwTextField.TOO_LONG)
	field.type_char(0x20)
	field.finish(true)
	assert_eq(field.text, "NEW YORK", "kept trimmed")
	assert_eq(field.keyboard_pages(), [["ABC", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\"#%',-.:?_"]],
			"the pads' keys: the capitals and signs")
	var cut := MwTextInputScreen.cut_pages(field.keyboard_pages(), 28)
	assert_eq(cut.map(func(p: Array) -> String: return p[0]), ["ABC", "234"], "cut to a look's grid")
	assert_eq(str(cut[1][1]), "23456789!\"#%',-.:?_")
	var pw := MwTextField.new(MwTextField.Kind.PASSWORD, "secret")
	assert_eq([pw.shown(), pw.title], ["******", ""], "masked; the ROM's header")


func test_both_screens_are_one_text_input() -> void:
	for id in [MwScreens.TEXT_ENTRY, MwScreens.KEYBOARD]:
		var node := (load(MwScreens.scene_path(id)) as PackedScene).instantiate()
		assert_true(node is MwTextInputScreen, "%d: a text input screen" % id)
		var ctx: Array = MwScreens.contexts(id)
		assert_eq(ctx[0], MwVerbs.Context.PASSWORD, "the password screen's verbs")
		# plan 38's text entry adds its wrapped box's scroll (a local context), nothing else
		assert_eq(ctx.slice(1), [MwVerbs.Context.TEXT_ENTRY] if id == MwScreens.TEXT_ENTRY else [],
				"%d: no other verbs" % id)
		node.free()


# --- CREATE-A-TEAM --------------------------------------------------------------------------------

func test_create_a_team_types_bound_letters_and_they_drive_nothing() -> void:
	if not need_rom():
		return
	_start(MwScreens.CREATE_A_TEAM)
	_run(20)
	await _tap(KEY_ENTER)                     # NEW TEAM: its city first
	assert_true(_until(MwScreens.TEXT_ENTRY), "the text entry")
	var te := router.current() as MwTextEntry
	assert_true(MwKeyGate.taking(), "the keyboard is the field's")
	await _type("zxc asq")                    # A B C, the editors' X / Y, RECLAIM
	assert_eq(te.field.text, "ZXC ASQ", "typed, in capitals")
	assert_eq(te.cursor, 0, "the grid's cursor stayed: no PICK LETTER, no direction")
	assert_eq(router.current_id(), MwScreens.TEXT_ENTRY, "C (CANCEL) cancelled nothing")
	await _tap(KEY_LEFT)
	await _tap(KEY_BACKSPACE)
	assert_eq(te.field.text, "ZXC AQ", "the arrows and Backspace inside the text")
	assert_eq(te.cursor, 0)
	await _press_button(JOY_BUTTON_DPAD_RIGHT)
	await _press_button(JOY_BUTTON_A)         # the pads still pick (STANDARD: south)
	assert_eq(te.field.text, "ZXC ABQ", "B, at the text's cursor")
	await _type("12345")
	assert_eq(te.field.text, "ZXC AB123Q", "ten at most")
	await _tap(KEY_ENTER)
	assert_true(_until_new(te), "then the name")       # (plan 40, M5: by a cut, the stars going on)
	assert_eq(router.current_id(), MwScreens.TEXT_ENTRY)
	assert_ne(router.current(), te)
	te = router.current() as MwTextEntry
	assert_eq(te.field.title, "TEAM NAME")
	await _type("testers")                     # W / E / R / F: the rink editor's view keys
	await _tap(KEY_ENTER)
	assert_true(_until(MwScreens.EDIT_TEAM), "the editor")
	var screen: Variant = router.current()
	assert_eq([MwCustomTeams.editing.city, MwCustomTeams.editing.name], ["ZXC AB123Q", "TESTERS"])
	assert_eq([screen.page, screen.row], ["edit", 0], "the Enter that ended it accepted nothing here")
	assert_false(MwKeyGate.active(), "every key live again")
	await _tap(KEY_DOWN)
	assert_ne(screen.row, 0, "the bindings drive the editor again")


func test_create_a_team_esc_drops_the_text_and_goes_no_further() -> void:
	if not need_rom():
		return
	_start(MwScreens.CREATE_A_TEAM)
	_run(20)
	await _tap(KEY_ENTER)
	assert_true(_until(MwScreens.TEXT_ENTRY))
	await _type("x")
	await _tap(KEY_ESCAPE)
	assert_true(_until(MwScreens.CREATE_A_TEAM), "dropped")
	_run(30)
	assert_eq(router.current_id(), MwScreens.CREATE_A_TEAM, "Esc wasn't also Back: still on the list")
	assert_eq(router.current().page, "list")
	assert_null(MwCustomTeams.editing, "no team made")


## Owner, 2026-10-12: the bio's text entry - the keyboard's Up / Down move
## the text's cursor a line, the gamepad's LT / RT move it left / right, and
## held, ERASE (and the keyboard's Backspace as the system repeats it)
## repeat.
func test_the_bio_moves_by_lines_and_held_keys_repeat() -> void:
	if not need_rom():
		return
	var field := MwCreateTeam.team_text("bio", "BIO", "", MwCustomTeam.TEXT_MAX)
	field.lines = 7
	field.width = 36
	_start_with(MwScreens.TEXT_ENTRY, {"field": field})
	_run(10)
	var te := router.current() as MwTextEntry
	# three lines of 36: "AAAA ... " words of 8 and a space
	var t := ""
	for i in 12:
		t += "ABCDEFGH "
	field.set_text(t.strip_edges())
	te._redraw()
	var lines := te._wrapped()
	assert_gt(lines.size(), 2, "wrapped over several lines")
	field.cursor = lines[0].size() + 4                 # line 2, its 5th place
	await _tap(KEY_UP)
	assert_eq(field.cursor, 4, "Up: the line above, the same place")
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	assert_eq(field.cursor, lines[0].size() + lines[1].size() + 4, "Down twice: two lines down")
	await _tap(KEY_UP)
	await _tap(KEY_UP)
	await _tap(KEY_UP)
	assert_eq(field.cursor, 0, "up from the first line: the text's start")
	await _tap(KEY_DOWN)
	assert_eq(field.cursor, lines[0].size(), "the next line's start")
	# the triggers: the text's cursor left and right
	_trigger(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_run(1)
	await get_tree().process_frame
	_trigger(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_run(4)
	assert_eq(field.cursor, lines[0].size() + 1, "RT: a character right")
	_trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
	_run(MwHoldRepeat.DELAY + 20)
	_trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_run(4)
	assert_eq(field.cursor, 0, "LT held: on to the start")
	assert_eq(te.cursor, 0, "the keys' cursor stayed")
	# ERASE held (STANDARD: north) repeats
	field.cursor = field.text.length()
	var n := field.text.length()
	_button(JOY_BUTTON_Y, true)
	_run(MwHoldRepeat.DELAY + 30)
	_button(JOY_BUTTON_Y, false)
	_run(4)
	assert_lt(field.text.length(), n - 5, "ERASE held: on erasing (%d of %d left)" % [field.text.length(), n])
	# the keyboard's own repeat (the system's echoes) erases too
	n = field.text.length()
	_key(KEY_BACKSPACE, true)
	_run(1)
	for i in 3:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_BACKSPACE
		event.keycode = KEY_BACKSPACE
		event.pressed = true
		event.echo = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		_run(1)
	_key(KEY_BACKSPACE, false)
	_run(2)
	assert_eq(field.text.length(), n - 4, "Backspace held: the press and its three echoes")


func _trigger(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# --- the online pages -----------------------------------------------------------------------------

func test_join_game_password_typed_with_bound_letters() -> void:
	if not need_rom():
		return
	_start(MwScreens.JOIN_GAME)
	_run(10)
	await _tap(KEY_DOWN)
	var menu := router.current() as MwOnlineMenu
	assert_eq(menu.rows[menu.row].action, "password")
	await _tap(KEY_ENTER)
	assert_true(_until(MwScreens.KEYBOARD), "its text input screen (123)")
	var kb := router.current() as MwKeyboardScreen
	assert_same(kb.field, menu.password_field)
	await _type("zxcZ")
	assert_eq(kb.field.text, "zxcZ", "as typed (MwNetService folds the case)")
	assert_eq(kb.field.shown(), "****", "masked")
	assert_eq(kb.cursor, 0, "the keys' cursor stayed")
	assert_eq(router.current_id(), MwScreens.KEYBOARD, "C (CANCEL) cancelled nothing")
	await _tap(KEY_ESCAPE)
	assert_true(_until(MwScreens.JOIN_GAME))
	_run(30)
	assert_eq(router.current_id(), MwScreens.JOIN_GAME, "Esc dropped the text, no Back on the page")
	assert_eq([menu.password_field.text, menu.row], ["", 1])
	await _tap(KEY_ENTER)
	assert_true(_until(MwScreens.KEYBOARD))
	kb = router.current() as MwKeyboardScreen
	await _press_button(JOY_BUTTON_A)         # a pad picks meanwhile: A
	await _type("hunter2")
	await _tap(KEY_ENTER)
	assert_true(_until(MwScreens.JOIN_GAME))
	_run(30)
	assert_eq(router.current_id(), MwScreens.JOIN_GAME, "Enter kept it and opened nothing again")
	assert_eq([menu.password_field.text, menu.row], ["Ahunter2", 1])
	# paste sanity on the keyboard's field
	await _tap(KEY_UP)
	await _tap(KEY_ENTER)
	assert_true(_until(MwScreens.KEYBOARD))
	kb = router.current() as MwKeyboardScreen
	_clip = "10.0.0.9\nrm -rf"
	await _tap(KEY_V, 0, "ctrl")
	assert_eq([kb.field.text, kb.note], ["", "NOT AN ADDRESS"], "refused: why, in red")
	_clip = " 10.0.0.9 "
	await _tap(KEY_V, 0, "ctrl")
	assert_eq([kb.field.text, kb.note], ["10.0.0.9", ""])
	assert_eq(router.current_id(), MwScreens.KEYBOARD, "V: no view switch either")
	await _tap(KEY_ENTER)
	assert_true(_until(MwScreens.JOIN_GAME))
	assert_eq(menu.address_field.text, "10.0.0.9")
