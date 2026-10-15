extends "res://test/rom/rom_test_base.gd"
## Plan 40 (D2): `$15860`'s layout in one place (MwTextBox.layout) - the
## text boxes, the stats screens' words, the speeches' and scoreboards'
## quotes lay text out with it. Words wrap when they don't fit and the line
## isn't empty; the terminator ends a word of its own (trailing spaces past
## the width take the next line, as the original's loop does); nothing from
## the box's bottom on; the cursor words are 16-bit.

const FONT := MwPlanePainter.FONT_SMALL


func _w(ch: String) -> int:
	return MwGfx.char_width(rom, FONT, ch.unicode_at(0))


func _line() -> int:
	return MwGfx.u16(rom, FONT)


func test_a_word_that_does_not_fit_wraps() -> void:
	if not need_rom():
		return
	var a := _w("A")
	var l := MwTextBox.layout(rom, FONT, "AA AA".to_ascii_buffer(), 3 * a, 99, _line())
	assert_eq(l["words"], [[0, 2, 0, 0], [3, 5, 0, _line()]], "the second word on the next line")
	assert_eq(l["cursor_x"], 2 * a)
	assert_eq(l["cursor_y"], _line())
	assert_false(l["cut"])
	var wide := MwTextBox.layout(rom, FONT, "AAAA".to_ascii_buffer(), a, 99, _line())
	assert_eq(wide["words"], [[0, 4, 0, 0]], "a word on an empty line stays, however wide")


func test_trailing_spaces_past_the_width_take_the_next_line() -> void:
	if not need_rom():
		return
	var a := _w("A")
	var l := MwTextBox.layout(rom, FONT, "AA ".to_ascii_buffer(), 2 * a, 99, _line())
	assert_eq(l["cursor_x"], 0, "the terminator's empty word wraps")
	assert_eq(l["cursor_y"], _line())
	var fits := MwTextBox.layout(rom, FONT, "AA".to_ascii_buffer(), 2 * a, 99, _line())
	assert_eq(fits["cursor_x"], 2 * a, "no trailing space: the cursor stays on the line")
	assert_eq(fits["cursor_y"], 0)


func test_nothing_from_the_bottom_on() -> void:
	if not need_rom():
		return
	var a := _w("A")
	var l := MwTextBox.layout(rom, FONT, "AA AA AA".to_ascii_buffer(), 2 * a, _line(), _line())
	assert_eq(l["words"], [[0, 2, 0, 0]], "one line's room: the first word only")
	assert_true(l["cut"])
	assert_eq(l["cursor_x"], 0)
	assert_eq(l["cursor_y"], _line())
	var nl := MwTextBox.layout(rom, FONT, "A\nA".to_ascii_buffer(), 99, 99, _line())
	assert_eq(nl["words"], [[0, 1, 0, 0], [2, 3, 0, _line()]], "$0A starts a line")


func test_the_cursor_words_are_16_bit() -> void:
	if not need_rom():
		return
	var a := _w("A")
	var l := MwTextBox.layout(rom, FONT, "A".to_ascii_buffer(), 99, 99, _line(), 0xFFFE, 0)
	assert_eq(l["words"], [[0, 1, -2, 0]], "x is signed")
	assert_eq(l["cursor_x"], (a - 2) & 0xFFFF)


func test_the_mark() -> void:
	if not need_rom():
		return
	var a := _w("A")
	var b := _w("B")
	var sp := _w(" ")
	var bytes := "AB CD".to_ascii_buffer()
	assert_eq(MwTextBox.layout(rom, FONT, bytes, 99, 99, _line(), 0, 0, 1)["mark"], Vector2i(a, 0), "a letter")
	assert_eq(MwTextBox.layout(rom, FONT, bytes, 99, 99, _line(), 0, 0, 2)["mark"], Vector2i(a + b, 0), "a space")
	assert_eq(MwTextBox.layout(rom, FONT, bytes, 99, 99, _line(), 0, 0, 3)["mark"], Vector2i(a + b + sp, 0),
			"the next word")
	var end: Dictionary = MwTextBox.layout(rom, FONT, bytes, 99, 99, _line(), 0, 0, 5)
	assert_eq(end["mark"], Vector2i(end["cursor_x"], 0), "the text's length: the cursor after it")
	var wrapped := MwTextBox.layout(rom, FONT, bytes, a + b, 99, _line(), 0, 0, 3)
	assert_eq(wrapped["mark"], Vector2i(0, _line()), "a wrapped word's letter")
	var cut := MwTextBox.layout(rom, FONT, bytes, a + b, _line(), _line(), 0, 0, 3)
	assert_eq(cut["mark"], Vector2i(-1, -1), "below the box: not reached")
