class_name MwEditorDraw
extends RefCounted
## CREATE-A-TEAM's drawing (plan 38): the port menus' look (MwPortMenu) -
## rows with a label and a value, the highlight frame filled and the dark
## font on the selected row, centred items - and the prompts as the glyphs
## of the verbs they name (plan 23, [MwGlyphs] live cells: the keyboard's
## or the gamepad's, whichever was used last).

const LIGHT := MwPlanePainter.FONT_MENU
const DARK := MwPlanePainter.FONT_SMALL
const HEADING := MwFonts.HEADING
const BIG := MwFonts.BIG
## Text attrs: the port menus' (line 3, priority) and the team look's
## white (line 3) and yellow (line 2, the team description's text line).
const MENU := 0xE0
const WHITE := 0x60
const YELLOW := 0x40
## The colour squares: their size and pitch (pixels), the selection box's grey.
const SWATCH := 7
const SWATCH_PITCH := 10
const MARK_GREY := Color(0.53, 0.53, 0.53)


## A line of text as the bytes the glyph drawers take (ASCII).
static func ascii(line: String) -> PackedByteArray:
	return line.to_ascii_buffer()


## The cells a line of text takes in [param font] ([method MwGlyphs.text_width]).
static func width(rom: PackedByteArray, font: int, line: String) -> int:
	return MwGlyphs.text_width(rom, font, ascii(line))


## A line of text drawn on [param plane] in [param font] from cell ([param x], [param y])
## with [param attr] ([method MwGlyphs.text]); returns the x after it.
static func text(plane: RomPlane, rom: PackedByteArray, font: int, line: String, x: int, y: int, attr: int) -> int:
	return MwGlyphs.text(plane, rom, font, ascii(line), x, y, attr)


## [param line] centred on the screen to the half cell, as the port menus'
## items and titles (plan 40, M2, owner: the tidied centring): an
## odd leftover goes on [param half] (its layer 4 px right) - or, with
## [param half] null, [param plane] holds this line alone and moves 4 px.
static func centred(plane: RomPlane, half: RomPlane, rom: PackedByteArray, font: int, line: String, y: int,
		attr: int) -> void:
	var b := ascii(line)
	var c := MwMenuRow.centred_x(rom, font, b, 40)
	if half == null:
		if not plane.has_meta(&"centred_x0"):
			plane.set_meta(&"centred_x0", plane.position.x)
		plane.position.x = float(plane.get_meta(&"centred_x0")) + 4 * c.y
	MwGlyphs.text(half if c.y != 0 and half != null else plane, rom, font, b, c.x, y, attr)


## A row (MwMenuRow.row, the port menus' - plan 40, M1): [param label]
## from cell [param x], [param value] right-aligned to [param x] +
## [param w] (cut to its room), framed and dark when [param selected];
## [param dim_on]: a dimmed row's grey layer (MwMenuRow.layers), else null.
static func row(plane: RomPlane, rom: PackedByteArray, label: String, value: String, x: int, y: int, w: int,
		selected: bool, attr: int, dim_on: RomPlane = null, line_count := 1) -> void:
	MwMenuRow.row(plane, rom, ascii(label), ascii(value), x, y, w, selected, attr, dim_on, line_count)


## An item centred in its frame's [param w] cells to the half cell
## (MwMenuRow.item; [param half]: the layer 4 px right).
static func item(plane: RomPlane, half: RomPlane, rom: PackedByteArray, label: String, x: int, y: int, w: int,
		selected: bool, attr: int) -> void:
	MwMenuRow.item(plane, half, rom, ascii(label), x, y, w, selected, attr)


## Coloured squares (Genesis colour words) in [param layer]: one
## [constant SWATCH] x [constant SWATCH] each, [constant SWATCH_PITCH]
## pixels apart, the last in the cell before [param right_x] on row
## [param y]; [param mark]: the index boxed (owner: the selected colour
## shown) - a 1-pixel box a pixel out from its square, grey, or black where
## the square itself is greyish ([method mark_colour]).
static func swatches(layer: Node2D, words: PackedInt32Array, right_x: int, y: int, mark := -1) -> void:
	var last := 8 * (right_x - 1)
	for i in words.size():
		var at := Vector2(last - SWATCH_PITCH * (words.size() - 1 - i), 8 * y)
		var c := MwGfx.color(words[i])
		if i == mark:
			var box := Rect2(at - Vector2(2, 2), Vector2(SWATCH + 4, SWATCH + 4))
			var m := mark_colour(c)
			for edge in [Rect2(box.position, Vector2(box.size.x, 1)),
					Rect2(box.position + Vector2(0, box.size.y - 1), Vector2(box.size.x, 1)),
					Rect2(box.position, Vector2(1, box.size.y)),
					Rect2(box.position + Vector2(box.size.x - 1, 0), Vector2(1, box.size.y))]:
				var edge_rect := ColorRect.new()
				edge_rect.color = m
				edge_rect.position = edge.position
				edge_rect.size = edge.size
				layer.add_child(edge_rect)
		var sq := ColorRect.new()
		sq.color = c
		sq.size = Vector2(SWATCH, SWATCH)
		sq.position = at
		layer.add_child(sq)


## The selection box's colour around a square of [param c]: grey, or black
## when [param c] is a grey itself (little colour, middling light) and grey
## would not stand out from it.
static func mark_colour(c: Color) -> Color:
	var spread := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	var light := c.get_luminance()
	return Color.BLACK if spread < 0.25 and light > 0.25 and light < 0.8 else MARK_GREY


## [param bytes] word-wrapped as the original's text box wraps it in
## [param font] to [param w] cells (MwTextBox.write, `$15860`: a word that
## doesn't fit goes to the next line unless the line is empty; spaces
## advance by the font's space width; $0A starts a line): the lines, each
## drawable on its own in a one-line box with the same result.
static func wrap(rom: PackedByteArray, font: int, bytes: PackedByteArray, w: int) -> Array[PackedByteArray]:
	var text_lines: Array[PackedByteArray] = []
	var cur := PackedByteArray()
	var cx := 0
	var space := MwGfx.u16(rom, font + 2)
	var i := 0
	while i < bytes.size() and bytes[i] != 0:
		var c := bytes[i]
		if c < 0x21 or c > 0x7E:
			if c == 0x20:
				cx += space
				cur.append(c)
			elif c == 0x0A:
				text_lines.append(cur)
				cur = PackedByteArray()
				cx = 0
			i += 1
			continue
		var j := i
		var word_width := 0
		while j < bytes.size() and bytes[j] >= 0x21 and bytes[j] <= 0x7E:
			word_width += MwGfx.char_width(rom, font, bytes[j])
			j += 1
		if cx + word_width > w and cx != 0:
			text_lines.append(cur)
			cur = PackedByteArray()
			cx = 0
		cur.append_array(bytes.slice(i, j))
		cx += word_width
		i = j
	text_lines.append(cur)
	return text_lines


## A text's lines [param text_lines] (from [method wrap]) from [param first], at most
## [param shown] of them, in a box at cell ([param x], [param y]),
## [param w] cells wide - a line a row ([param font]'s height).
static func lines(plane: RomPlane, rom: PackedByteArray, font: int, text_lines: Array[PackedByteArray], first: int,
		shown: int, x: int, y: int, w: int, attr: int) -> void:
	var h := maxi(MwGfx.u16(rom, font), 1)
	for k in shown:
		var i := first + k
		if i < 0 or i >= text_lines.size():
			continue
		MwTextBox.new(plane, font, Rect2i(x, y + h * k, w + 1, h)).write(rom, text_lines[i], attr)


## A Genesis colour word's levels (red, green, blue: 0-7) and back.
static func levels(colour_word: int) -> Array:
	return [(colour_word >> 1) & 7, (colour_word >> 5) & 7, (colour_word >> 9) & 7]


## The Genesis colour word of the levels [param lv] (red, green, blue: 0-7): [method levels]
## back.
static func word(lv: Array) -> int:
	return ((int(lv[2]) & 7) << 9) | ((int(lv[1]) & 7) << 5) | ((int(lv[0]) & 7) << 1)
