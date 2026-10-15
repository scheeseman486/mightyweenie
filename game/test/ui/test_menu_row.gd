extends "res://test/rom/rom_test_base.gd"
## Plan 40 (M1): the port menus' row drawn one way (MwMenuRow) - the port
## menus, the online pages and (owner, 2026-10-11) the editors: a value
## keeps two cells from its label, an item centres to the half cell.


func _w(f: int, text: String) -> int:
	return MwGlyphs.text_width(rom, f, text.to_ascii_buffer())


func test_a_value_keeps_two_cells_from_its_label() -> void:
	if not need_rom():
		return
	var f := MwMenuRow.LIGHT
	var label := "LABEL".to_ascii_buffer()
	assert_eq(MwMenuRow.room(rom, f, label, 30), 30 - _w(f, "LABEL") - 2)
	var long := "A VERY LONG VALUE INDEED".to_ascii_buffer()
	var cut := MwMenuRow.cut(rom, f, long, 10)
	assert_lte(MwGlyphs.text_width(rom, f, cut), 10, "cut to its room")
	assert_eq(MwGlyphs.text_width(rom, f, MwMenuRow.cut(rom, f, cut + "X".to_ascii_buffer(), 10)) <= 10, true)
	assert_eq(MwMenuRow.cut(rom, f, "LONGER".to_ascii_buffer(), 0).size(), 1, "one character at least")


func test_an_item_centres_to_the_half_cell() -> void:
	if not need_rom():
		return
	var f := MwMenuRow.LIGHT
	for text: String in ["A", "AB", "NEW TEAM", "EDIT"]:
		var b := text.to_ascii_buffer()
		var c := MwMenuRow.centred_x(rom, f, b, 2 * 10 + 20)
		var w := _w(f, text)
		assert_eq(2 * c.x + c.y + w, 40, "%s: centred on cell 20 to the half cell" % text)
		assert_eq(c.y, (40 - w) % 2, "%s: half a cell right when odd" % text)


func test_the_editors_draw_through_it() -> void:
	for f in ["res://src/custom/editor_draw.gd", "res://scenes/online/online.gd",
			"res://scenes/port_menu/port_menu.gd"]:
		var code := FileAccess.get_file_as_string(f)
		assert_true(code.contains("MwMenuRow."), f)
		assert_false(code.contains("- 1\n\twhile value.length() > 1"), "%s: no room of its own" % f)
