class_name MwTextBox
extends RefCounted
## The original's word-wrapping text box (`$15800`-`$15926`; docs/re/menus.md,
## Drawing): a rectangle of a plane, a font and a cursor. Words (runs of
## `!`-`~`) wrap to the next line when they do not fit and the line is not
## empty; spaces advance by the font's space width; byte $0A starts a new
## line; drawing stops below the box. A line is the font's +0 word (its
## height) plus [member spacing] rows.

var plane: RomPlane
var font := 0
var x := 0
var y := 0
var w := 0
var h := 0
var spacing := 0
var cursor_x := 0
var cursor_y := 0
## The cell the character [method write] was asked to mark went to (or
## the cursor after the text, when the mark is the text's length); (-1, -1)
## when not reached. The port's: a text cursor's place (MwTextEntry).
var mark := Vector2i(-1, -1)


## `$15800`: the box (x, y, w, h) on [param plane_] in [param font_].
func _init(plane_: RomPlane, font_: int, rect: Rect2i, spacing_ := 0) -> void:
	plane = plane_
	font = font_
	x = rect.position.x
	y = rect.position.y
	w = rect.size.x
	h = rect.size.y
	spacing = spacing_


## `$1580A`: cursor back to the top left.
func home() -> void:
	cursor_x = 0
	cursor_y = 0


## `$15926`: fill the box with one name-table word.
func fill(word: int) -> void:
	MwPlanePainter.fill(plane, x, y, w, h, word)


## `$15860`: draw [param bytes] from the cursor with [param attr] (and note
## where character [param mark_at] goes: [member mark]). The words' places
## are [method layout]'s.
func write(rom: PackedByteArray, bytes: PackedByteArray, attr: int, mark_at := -1) -> void:
	var l := layout(rom, font, bytes, w, h, MwGfx.u16(rom, font) + spacing, cursor_x, cursor_y, mark_at)
	for wd: Array in l["words"]:
		var px: int = x + int(wd[2])
		var py: int = y + MwRinkSim.s16(wd[3])
		for i in range(int(wd[0]), int(wd[1])):
			px += MwPlanePainter.glyph(plane, rom, font, bytes[i], px, py, attr)
	cursor_x = MwRinkSim.s16(l["cursor_x"])
	cursor_y = MwRinkSim.s16(l["cursor_y"])
	var m: Vector2i = l["mark"]
	mark = Vector2i(-1, -1) if m.x == -1 and m.y == -1 else m + Vector2i(x, y)


## Plan 40 (D2): `$15860`'s layout alone, as the 68000 runs it (16-bit
## cursor words, signed compares) - [method write], the simulations' text
## boxes (the stats screens' words, the speeches' and the scoreboards'
## quotes) and the tests lay text out with it: [param bytes] (up to a 0) in
## [param text_font] from the cursor ([param start_x], [param start_y]) in a
## box [param columns] x [param rows] cells, a line [param line] rows. Words (runs of
## `!`-`~`) wrap when they don't fit and the line isn't empty, spaces
## advance by the font's space width, $0A starts a line, nothing from the
## box's bottom on. The terminator ends a word of its own: after trailing
## spaces past the width the cursor takes the next line, as the original's.
## {words: [[from, to, x, y]] (x signed, y the cursor word), cursor_x,
## cursor_y (words), cut: it stopped at the bottom, mark: where character
## [param mark_at] went, box-relative - the cursor after the text when it is
## the text's length; (-1, -1) not reached}. (MwEditorDraw.wrap keeps a
## line's spaces for the editors' pages: the port's own rule.)
static func layout(rom: PackedByteArray, text_font: int, bytes: PackedByteArray, columns: int, rows: int, line: int,
		start_x := 0, start_y := 0, mark_at := -1) -> Dictionary:
	var space := MwGfx.u16(rom, text_font + 2)
	var words := []
	var marked := Vector2i(-1, -1)
	var pen_x := MwRinkSim.s16(start_x)
	var pen_y := start_y & 0xFFFF
	var i := 0
	var ch := _at(bytes, i)
	while ch != 0:
		while ch < 0x21 or ch > 0x7E:
			if i == mark_at:
				marked = Vector2i(pen_x, MwRinkSim.s16(pen_y))
			if ch == 0x20:
				pen_x = MwRinkSim.s16(pen_x + space)
			elif ch == 0x0A:
				pen_y = (pen_y + line) & 0xFFFF
				pen_x = 0
			i += 1
			ch = _at(bytes, i)
			if ch == 0:
				break
		var j := i
		var width := 0
		while ch >= 0x21 and ch <= 0x7E:
			if j == mark_at:
				marked = Vector2i(width, -1)                 # the word's place is known below
			width += MwGfx.char_width(rom, text_font, ch)
			j += 1
			ch = _at(bytes, j)
		if MwRinkSim.s16(pen_x + width) > MwRinkSim.s16(columns) and pen_x != 0:
			pen_y = (pen_y + line) & 0xFFFF
			pen_x = 0
		if pen_y >= (rows & 0xFFFF):
			if mark_at >= i and mark_at < j:
				marked = Vector2i(-1, -1)
			return {"words": words, "cursor_x": pen_x & 0xFFFF, "cursor_y": pen_y, "cut": true, "mark": marked}
		if j > i:
			words.append([i, j, pen_x, pen_y])
			if mark_at >= i and mark_at < j:
				marked = Vector2i(pen_x + marked.x, MwRinkSim.s16(pen_y))
		pen_x = MwRinkSim.s16(pen_x + width)
		i = j
		ch = _at(bytes, i)
	if mark_at >= i and MwRinkSim.s16(pen_y) < rows:
		marked = Vector2i(pen_x, MwRinkSim.s16(pen_y))
	return {"words": words, "cursor_x": pen_x & 0xFFFF, "cursor_y": pen_y, "cut": false, "mark": marked}


static func _at(bytes: PackedByteArray, i: int) -> int:
	return bytes[i] if i < bytes.size() else 0

