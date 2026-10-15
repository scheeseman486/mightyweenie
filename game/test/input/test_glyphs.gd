extends "res://test/rom/rom_test_base.gd"
## The input glyphs (plan 23): the sheets as palette-index tiles (no sheet
## colour shown), the key and gamepad lookups, the gamepad families and
## tags, the live cells following the device used last, the prompts drawn
## into the screens' texts (STANDARD; GENESIS keeps the letters), the
## recoloured ROM glyphs of the pause menu.

var _layouts := {}
var _device := -1


func before_all() -> void:
	super.before_all()
	_layouts = MwSettings.layouts
	_device = MwGlyphs.last_device


func after_all() -> void:
	MwSettings.layouts = _layouts
	MwGlyphs.last_device = _device
	MwInputMap.install()


func before_each() -> void:
	MwSettings.layouts = {}
	MwSettings.bindings = {}
	MwGlyphs.last_device = -1
	MwInputMap.install()


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = true
	return k


func _button(device: int, b: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = b
	event.pressed = true
	return event


func test_the_tiles_are_palette_indices_only() -> void:
	var t := MwGlyphs.tiles()
	assert_gt(t.size(), 400, "both sheets cut into cells")
	var allowed := [0, MwGlyphs.BLACK, MwGlyphs.WHITE, MwGlyphs.GREY, MwGlyphs.DARK]
	var bad := 0
	for key in t:
		if key >= MwGlyphs.REMAP_BASE:
			continue                     # recoloured ROM glyphs: the ROM's own indices
		for v in (t[key] as PackedByteArray):
			if not v in allowed:
				bad += 1
	assert_eq(bad, 0, "no sheet colour: only the light font's line 3 indices")


func test_keys_from_the_key_code_sheet() -> void:
	assert_eq(MwGlyphs.glyph_of(_key(KEY_Z)), "vk:90")
	assert_eq(MwGlyphs.cells("vk:90").size(), 2, "a letter cap: 9 px, two cells")
	assert_eq(MwGlyphs.glyph_of(_key(KEY_ENTER)), "vk:13")
	assert_eq(MwGlyphs.cells("vk:13").size(), 3)
	assert_eq(MwGlyphs.glyph_of(_key(KEY_KP_ENTER)), "vk:13", "the keypad's Enter: Enter's cap")
	assert_eq(MwGlyphs.glyph_of(_key(KEY_ESCAPE)), "vk:27")
	assert_eq(MwGlyphs.glyph_of(_key(KEY_F3)), "vk:114")
	assert_eq(MwGlyphs.cells("vk:8").size(), 3, "Backspace (one of the sheet's early tiles): the wide cap")
	assert_eq(MwGlyphs.cells("vk:9").size(), 2, "Tab")
	assert_true(MwGlyphs.cells("vk:7").is_empty(), "no code 7")


func test_gamepad_glyphs_by_family() -> void:
	assert_eq(MwGlyphs.family_of_name("Xbox Series X Controller"), "XB")
	assert_eq(MwGlyphs.family_of_name("PS5 Controller"), "PS")
	assert_eq(MwGlyphs.family_of_name("Nintendo Switch Pro Controller"), "NS")
	assert_eq(MwGlyphs.family_of_name("8BitDo Something"), "PAD")
	assert_eq(MwGlyphs.button_name(JOY_BUTTON_A, "XB"), "A")
	assert_eq(MwGlyphs.button_name(JOY_BUTTON_A, "PS"), "CROSS")
	assert_eq(MwGlyphs.button_name(JOY_BUTTON_A, "NS"), "B", "Godot's buttons go by place")
	assert_eq(MwGlyphs.button_name(JOY_BUTTON_RIGHT_SHOULDER, "XB"), "RB")
	assert_eq(MwGlyphs.button_name(JOY_BUTTON_RIGHT_SHOULDER, "PS"), "R1")
	assert_eq(MwGlyphs.button_name(JOY_BUTTON_START, "NS"), "+")
	for button in ["A", "B", "X", "Y", "START", "BACK", "LB", "RB", "LT", "RT", "LS", "RS", "L1", "R2",
			"DPAD_UP", "STICK_LEFT", "CROSS", "+", "-"]:
		assert_false(MwGlyphs.cells("pad:" + button).is_empty(), button)
	assert_eq(MwGlyphs.cells("pad:A").size(), 1, "a face button: one cell")
	assert_eq(MwGlyphs.cells("pad:START").size(), 3)
	assert_eq(MwGlyphs.cells("pad:BACK").size(), 3, "Back composed like START")
	var m := InputEventJoypadMotion.new()
	m.device = 0
	m.axis = JOY_AXIS_RIGHT_X
	m.axis_value = -1.0
	assert_eq(MwGlyphs.stick_glyphs(m), PackedStringArray(["pad:RS", "pad:STICK_LEFT"]))
	assert_eq(MwGlyphs.tag(7), "PAD8", "a gamepad not connected")
	assert_eq(MwGlyphs.tag(-1), "", "no tag for the keyboard (owner)")


func test_the_live_cells_follow_the_device_used_last() -> void:
	assert_eq(MwGlyphs.verb_glyph(1, "ui_view_stats"), "vk:90", "the keyboard: Z (the original's A)")
	assert_eq(MwGlyphs.verb_glyph(1, "ui_view_stats", 0),
			"pad:" + MwGlyphs.button_name(JOY_BUTTON_X, MwGlyphs.family(0)),
			"a gamepad: STANDARD's west, in its family's marks")
	var cells := MwGlyphs.live_cells("ui_view_stats")
	assert_eq(cells.size(), 2, "as wide as the wider: the key cap")
	var before: PackedByteArray = MwGlyphs.tiles()[cells[0]].duplicate()
	var g := MwGlyphs.generation
	assert_true(MwGlyphs.note_input(_button(0, JOY_BUTTON_A)), "a gamepad pressed: the glyphs change")
	assert_false(MwGlyphs.note_input(_button(0, JOY_BUTTON_B)), "the same gamepad again: no change")
	assert_gt(MwGlyphs.generation, g)
	assert_ne(MwGlyphs.tiles()[cells[0]], before, "the cells redrawn in place")
	assert_true(MwGlyphs.note_input(_key(KEY_X)))
	assert_eq(MwGlyphs.tiles()[cells[0]], before, "and back")
	var m := InputEventJoypadMotion.new()
	m.device = 1
	m.axis = JOY_AXIS_LEFT_X
	m.axis_value = 0.2
	assert_false(MwGlyphs.note_input(m), "a stick inside its dead zone: nothing")


func test_prompts_in_texts() -> void:
	if not need_rom():
		return
	var font := MwPlanePainter.FONT_MENU
	var ctx := MwVerbs.Context.SCOREBOARD
	var w := func(prompt_text: String, context := ctx, all := false) -> int:
		return MwPrompts.width(rom, font, prompt_text.to_ascii_buffer(), context, all)
	var tw := func(text: String) -> int:
		return MwGfx.text_width(rom, font, text.to_ascii_buffer())
	assert_eq(w.call("A: Test line"), tw.call("A: Test line") + 1, "A's key cap is a cell wider than the letter")
	assert_eq(w.call("START: test"), tw.call("START: test") - 2, "START's: two cells narrower")
	assert_eq(w.call("PRESS A FOR A TEST", MwVerbs.Context.STATS), tw.call("PRESS A FOR A TEST") + 1, "after PRESS")
	assert_eq(w.call("A-SELECT", MwVerbs.Context.PASSWORD), 9)
	assert_eq(w.call("A FOR"), 5, "a letter that is no prompt stays")
	assert_eq(w.call("C. SLAYER"), 9, "an initial stays")
	assert_eq(w.call("A_B_C", MwVerbs.Context.REPLAY, true), 5 + 3, "every letter of the widget")
	assert_eq(MwPrompts.context_for([MwVerbs.Context.SCOREBOARD, MwVerbs.Context.ZAMBONI]), MwVerbs.Context.SCOREBOARD)
	assert_eq(MwPrompts.context_for([MwVerbs.Context.GAMEPLAY]), -1)
	assert_true(MwPrompts.active())
	MwSettings.layouts = {1: "GENESIS"}
	assert_false(MwPrompts.active(), "GENESIS: the original's letters")


func test_a_prompt_drawn_on_a_plane() -> void:
	if not need_rom():
		return
	var plane := RomPlane.new()
	var ts := RomTileSet.new()
	ts.fonts = PackedStringArray(["font_0447f4"])
	plane.tiles = ts
	plane.palette = RomPalette.make(12, PackedStringArray(["screen_palette"]))
	add_child_autofree(plane)
	var end := MwPrompts.text(plane, rom, MwPlanePainter.FONT_MENU, "A: View".to_ascii_buffer(), 4, 3, 0x60,
			MwVerbs.Context.SCOREBOARD)
	var cells := MwGlyphs.live_cells("ui_view_stats")
	var row := MwPrompts.row(rom, MwPlanePainter.FONT_MENU, 3)
	assert_eq(int(plane.cell(4, row)["key"]), cells[0], "the glyph's live cells where A was")
	MwPrompts.text(plane, rom, MwPlanePainter.FONT_MENU, "A: View".to_ascii_buffer(), 4, 5, 0x60,
			MwVerbs.Context.SCOREBOARD, false, false, MwGlyphs.Style.TEXT)
	var opaque := MwGlyphs.live_cells("ui_view_stats", MwGlyphs.Style.TEXT)
	assert_eq(int(plane.cell(4, MwPrompts.row(rom, MwPlanePainter.FONT_MENU, 5))["key"]), opaque[0],
			"TEXT: the scoreboards'")
	for k in opaque:
		assert_eq((MwGlyphs.tiles()[k] as PackedByteArray).count(0), 0, "on the font's black: no backdrop through it")
	assert_eq(int(plane.cell(5, row)["key"]), cells[1])
	assert_eq(int(plane.cell(4, row)["line"]), MwGlyphs.LINE)
	assert_eq(end, 4 + 2 + MwGfx.text_width(rom, MwPlanePainter.FONT_MENU, ": View".to_ascii_buffer()))


## Owner, 2026-10-12: SAVE REPLAY?'s V and L were in the team's colours -
## the greys covered only PAUSE / ARE YOU SURE?'s letters. Every title the
## pause menu's look draws (the confirm box's too) is greys, whatever it says.
func test_every_title_letter_has_its_greys() -> void:
	if not need_rom():
		return
	MwGlyphs.tiles()
	for title in ["PAUSE", "ARE YOU SURE?", "SAVE REPLAY?", "CONNECT?", "ABCDEFGHIJKLMNOPQRSTUVWXYZ?!0123456789"]:
		for ch in title.to_ascii_buffer():
			if ch == 0x20:
				continue
			assert_true(MwGlyphs._remapped.has("%d|%d|grey" % [MwPauseMenu.BIG, ch]),
					"%s: %s in greys" % [title, char(ch)])


func test_the_pause_menus_recoloured_glyphs() -> void:
	if not need_rom():
		return
	var plane := RomPlane.new()
	plane.tiles = RomTileSet.new()
	plane.palette = RomPalette.make(4, PackedStringArray(["screen_palette"]))
	add_child_autofree(plane)
	var x := MwGlyphs.rom_text(plane, rom, 0x246FA, "PAUSE".to_ascii_buffer(), 0, 4, 0xA0, "grey")
	assert_eq(x, MwGfx.text_width(rom, 0x246FA, "PAUSE".to_ascii_buffer()), "advances as the font")
	var seen := {}
	for key in MwGlyphs.tiles():
		if key >= MwGlyphs.REMAP_BASE:
			for v in (MwGlyphs.tiles()[key] as PackedByteArray):
				seen[v] = true
	assert_false(seen.has(2) and seen.has(3), "the big font's team colours replaced by greys")
	var second := {}
	for k in MwGlyphs._remapped.get("%d|%d|secondary" % [0x246FA, 0x52], {}).get("keys", []):
		for v in (MwGlyphs.tiles()[k] as PackedByteArray):
			second[v] = true
	assert_true(second.has(5) and not second.has(2) and not second.has(3),
			"the pause items' secondary: the face and shade on the team's colours 5-6 (owner)")
	MwGlyphs.black_frame(plane, rom, 5, 6, 8, 1)
	assert_eq(int(plane.cell(6, 6)["key"]), MwGlyphs.SOLID_BLACK, "filled black")
	assert_ne(int(plane.cell(4, 6)["key"]), 0, "its rounded end")


func test_the_bindings_menu_draws_glyphs_and_tags() -> void:
	var parts := MwPortMenu.binding_parts(1, "ui_accept")
	assert_eq(parts[0], {"glyph": "vk:13"}, "Enter's cap first")
	assert_eq(parts[1], {"text": " + "}, "a separator between the inputs (owner)")
	assert_eq(parts[2], {"text": MwGlyphs.tag(0) + " "}, "the gamepad's tag before its glyph (owner)")
	assert_eq(parts[3], {"glyph": "pad:" + MwGlyphs.button_name(JOY_BUTTON_START, MwGlyphs.family(0))})
	assert_eq(MwPortMenu.stick_parts(1, "move_stick"), [{"text": MwGlyphs.tag(0) + " "}, {"glyph": "pad:LS"}])
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F13
	assert_eq(MwPortMenu.event_parts(k)[0].get("glyph", ""), "vk:124", "any key with a cap")


func test_the_special_plays_buttons_become_glyphs() -> void:
	if not need_rom():
		return
	var scene := (load(MwScreens.scene_path(10)) as PackedScene).instantiate()
	var b := MwSpecialPlaysSim.BUTTONS
	var ops := [["piece", b + 6, 0xA0, 88, 0xE0, 0], ["piece", 0x12345, 0, 0, 0, 0]]
	var out: Array = scene._sprite_ops(ops)
	assert_eq(str(out[0][0]), "glyph", "B's button: its verb's glyph")
	assert_eq(out[0][6], MwGlyphs.live_cells("ui_choose_play"))
	assert_eq(out[1], ops[1], "other pieces as they are")
	MwSettings.layouts = {1: "GENESIS"}
	assert_eq(scene._sprite_ops(ops), ops, "GENESIS: the original's buttons")
	scene.free()


func test_the_replay_widget_letters_become_sprites() -> void:
	if not need_rom():
		return
	var plane := RomPlane.new()
	var ts := RomTileSet.new()
	ts.fonts = PackedStringArray(["font_0447f4"])
	plane.tiles = ts
	add_child_autofree(plane)
	var painter := MwWindowPainter.new(plane, rom)
	painter.prompt_ctx = MwVerbs.Context.REPLAY
	painter.paint([["text", MwPlanePainter.FONT_MENU, 4, 4, 0xE0, 0x5062B]], null)
	assert_eq(painter.overlays.size(), 3, "A, B and C over their symbols")
	assert_eq(painter.overlays[0][0], MwGlyphs.live_cells("replay_rewind"))
	assert_eq(int(painter.overlays[0][1]), 4 * 8 + 4, "centred on A's cell")
	var row := MwPrompts.row(rom, MwPlanePainter.FONT_MENU, 4)
	assert_eq(int(plane.cell(4, row)["key"]), 0, "the letter left out of the plane")


func test_glyphs_on_a_bar_or_in_text_are_opaque() -> void:
	for id in ["vk:13", "pad:A", "pad:START"]:
		var holes := [0, 0, 0]
		for style in MwGlyphs.Style.values():
			for k in MwGlyphs.cells(id, style):
				holes[style] += (MwGlyphs.tiles()[k] as PackedByteArray).count(0)
		assert_gt(holes[MwGlyphs.Style.NORMAL], 0, id + ": see-through around it")
		assert_eq(holes[MwGlyphs.Style.SELECTED], 0, id + ": on a selection bar, its white under it (owner)")
		assert_eq(holes[MwGlyphs.Style.TEXT], 0, id + ": in a text line, the font's black under it")


func test_a_plus_for_the_menu_fonts() -> void:
	if not need_rom():
		return
	var plane := RomPlane.new()
	plane.tiles = RomTileSet.new()
	plane.palette = RomPalette.make(1, PackedStringArray(["screen_palette"]))
	add_child_autofree(plane)
	for f in [MwPlanePainter.FONT_MENU, MwPlanePainter.FONT_SMALL]:
		assert_eq(MwGfx.font_glyph(rom, f, 0x2B), -1, "the font has no +")
		var bytes := "A+B".to_ascii_buffer()
		assert_eq(MwGlyphs.text_width(rom, f, bytes), MwGfx.text_width(rom, f, bytes) + 1, "the port's + a cell")
		var end := MwGlyphs.text(plane, rom, f, bytes, 2, 4, 0xE0)
		assert_eq(end, 2 + MwGlyphs.text_width(rom, f, bytes))
		var row := 4 + MwGfx.s16(rom, f) - 1
		assert_eq(int(plane.cell(2 + MwGfx.char_width(rom, f, 0x41), row)["key"]), MwGlyphs.PLUS_KEYS[f])
		var px: PackedByteArray = MwGlyphs.tiles()[MwGlyphs.PLUS_KEYS[f]]
		var minus := MwGfx.tile_indices(rom, int(MwGfx.piece(rom, f + 8 + 6 * MwGfx.font_glyph(rom, f, 0x2D))["tile"])
				* 32)
		assert_eq(px[2 * 8 + 1], minus[2 * 8 + 1], "the -'s ink")
		assert_eq(px[0], minus[0], "and background")


func test_a_gamepad_found_after_the_start_takes_the_glyphs_until_the_player_chooses() -> void:
	var chosen: bool = MwGlyphs._chosen
	MwGlyphs._chosen = false
	MwGlyphs.joy_changed(3, true)            # Godot finds a pad after the glyphs were drawn (plan 27)
	assert_eq(MwGlyphs.last_device, 3)
	MwGlyphs.joy_changed(3, false)           # unplugged: another pad's, or the keyboard
	var others := Input.get_connected_joypads().filter(func(d: int) -> bool: return d != 3)
	assert_eq(MwGlyphs.last_device, others[0] if not others.is_empty() else -1)
	MwGlyphs.note_input(_key(KEY_Z))          # the player chose the keyboard ...
	MwGlyphs.joy_changed(4, true)            # ... a pad plugged in later doesn't take over
	assert_eq(MwGlyphs.last_device, -1)
	MwGlyphs._chosen = chosen

