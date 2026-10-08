extends "res://test/rom/rom_test_base.gd"
## Text in the original's fonts (draw_text $14CAE): widths, glyphs on the
## baseline, centring, RomText storing references only.


func test_widths_and_baseline_on_rom_fonts() -> void:
	if not need_rom():
		return
	var big := 0x447F4
	var body := 0x22EE0
	assert_eq(MwGfx.char_width(rom, body, 0x20), MwGfx.u16(rom, body + 2), "space = font +2")
	assert_eq(MwGfx.char_width(rom, body, 0x01), 0, "control characters draw nothing")
	var s := "MUTANT".to_ascii_buffer()
	var glyphs := MwGfx.text_glyphs(rom, body, s, 3, 11)
	assert_eq(glyphs.size(), 6)
	var x := 3
	for g in glyphs:
		assert_eq(g["x"], x)
		assert_eq(g["y"] + g["h"], 11 + MwGfx.s16(rom, body), "bottom on the baseline")
		x += int(g["w"])
	assert_eq(MwGfx.text_width(rom, body, s), x - 3)
	var img := MwGfx.text_image(rom, big, "All".to_ascii_buffer())
	assert_eq(img["w"], 8 * MwGfx.text_width(rom, big, "All".to_ascii_buffer()))


func test_credit_pages_are_19_string_lists() -> void:
	if not need_rom():
		return
	var count := 0
	for i in MwTitleScreen.PAGE_COUNT:
		var list := MwGfx.string_list(rom, MwGfx.u32(rom, MwTitleScreen.PAGES + 4 * i))
		assert_gt(list.size(), 1, "page %d has body lines" % i)
		count += list.size()
	assert_eq(MwGfx.rom_string(rom, MwGfx.u32(rom, MwTitleScreen.PAGES)).size(), 0, "page 1 has no heading")
	assert_gt(count, 50)


func test_rom_text_node() -> void:
	if not need_rom():
		return
	var t := RomText.new()
	t.font = "font_022ee0"
	t.string_address = MwGfx.u32(rom, MwTitleScreen.PAGES + 4) + 0   # a heading
	t.center_in = 40
	t.cell = Vector2i(0, 11)
	add_child_autofree(t)
	assert_gt(t.width, 0)
	assert_eq(t.start_cell(), Vector2i((40 - t.width) / 2, 11))
	assert_eq(t.offset, Vector2(8 * t.start_cell().x, 8 * 11))
	assert_not_null(t.texture)
	assert_eq(t.texture.get_width(), 8 * t.width)
	t.text = "AB"
	t.string_address = -1
	t.rebuild()
	assert_eq(t.bytes(), "AB".to_ascii_buffer())
	var packed := PackedScene.new()
	var root := Node2D.new()
	var copy := RomText.new()
	copy.font = "font_022ee0"
	copy.text = "AB"
	root.add_child(copy)
	copy.owner = root
	copy.rebuild()
	assert_eq(packed.pack(root), OK)
	var state := packed.get_state()
	var saved := []
	for i in state.get_node_property_count(1):
		saved.append(state.get_node_property_name(1, i))
	for p in RomText.GENERATED:
		assert_false(p in saved, "%s is not saved" % p)
	root.free()
