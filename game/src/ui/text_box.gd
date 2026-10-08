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


## `$15860`: draw [param s] from the cursor with [param attr].
func write(rom: PackedByteArray, s: PackedByteArray, attr: int) -> void:
	var line_h := MwGfx.u16(rom, font) + spacing
	var cx := cursor_x
	var i := 0
	while i < s.size() and s[i] != 0:
		var c := s[i]
		if c < 0x21 or c > 0x7E:
			if c == 0x20:
				cx += MwGfx.u16(rom, font + 2)
			elif c == 0x0A:
				cursor_y += line_h
				cx = 0
			i += 1
			continue
		var j := i
		var width := 0
		while j < s.size() and s[j] >= 0x21 and s[j] <= 0x7E:
			width += MwGfx.char_width(rom, font, s[j])
			j += 1
		if cx + width > w and cx != 0:
			cursor_y += line_h
			cx = 0
		if cursor_y >= h:
			cursor_x = cx
			return
		var px := cx + x
		var py := cursor_y + y
		while i < j:
			px += MwPlanePainter.glyph(plane, rom, font, s[i], px, py, attr)
			i += 1
		cx = px - x
	cursor_x = cx
