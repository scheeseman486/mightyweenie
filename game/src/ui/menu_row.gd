class_name MwMenuRow
extends RefCounted
## Plan 40 (M1): the port menus' row, drawn one way - the port menus
## (MwPortMenu), the online pages, CREATE-A-TEAM, its text entry and the
## rink editor (owner, 2026-10-11: the editors aligned to the port menus).
## The highlight frame filled and the dark font on the selected row; a
## label from the row's left and its value right-aligned, cut to keep
## [constant ROOM] cells between them (a two-line row: the value on the
## line under the label, the row's whole width); an item centred in its
## frame to the half cell (an odd leftover on a half layer, 4 px right); a
## dimmed row on a grey layer ([constant DIM]).

const LIGHT := MwPlanePainter.FONT_MENU
const DARK := MwPlanePainter.FONT_SMALL
## Cells kept between a row's label and its value.
const ROOM := 2
## A dimmed row's layer tint.
const DIM := MwUiInk.DIM


## The row's font: the dark one on the highlight.
static func font(selected: bool) -> int:
	return DARK if selected else LIGHT


## The highlight frame of a selected row ([param lines] rows high).
static func frame(on: RomPlane, rom: PackedByteArray, x: int, y: int, w: int, selected: bool, lines := 1) -> void:
	if selected:
		MwPlanePainter.frame(on, rom, x, y, w, lines, true)


## The room (cells) a row [param w] wide leaves its value beside
## [param label] in font [param f].
static func room(rom: PackedByteArray, f: int, label: PackedByteArray, w: int) -> int:
	return w - MwGlyphs.text_width(rom, f, label) - ROOM


## [param value] cut, a character at a time, until it fits [param room]
## cells (one character at least).
static func cut(rom: PackedByteArray, f: int, value: PackedByteArray, room_: int) -> PackedByteArray:
	while value.size() > 1 and MwGlyphs.text_width(rom, f, value) > room_:
		value = value.slice(0, value.size() - 1)
	return value


## A row on [param on]: framed when [param selected], [param label] from
## cell [param x], [param value] right-aligned to [param x] + [param w]
## (cut to its room); [param text_on]: the layer for its texts (a dimmed
## row's grey one; null: [param on]); [param lines] 2: the value on the
## line under the label.
static func row(on: RomPlane, rom: PackedByteArray, label: PackedByteArray, value: PackedByteArray, x: int, y: int,
		w: int, selected: bool, attr: int, text_on: RomPlane = null, lines := 1) -> void:
	frame(on, rom, x, y, w, selected, lines)
	var plane := text_on if text_on != null else on
	var f := font(selected)
	MwGlyphs.text(plane, rom, f, label, x, y, attr)
	var v := cut(rom, f, value, w if lines > 1 else room(rom, f, label, w))
	if not v.is_empty():
		MwGlyphs.text(plane, rom, f, v, x + w - MwGlyphs.text_width(rom, f, v), y + lines - 1, attr)


## Where text [param b] in font [param f] centred on [param twice_centre]
## half cells starts: (cell x, 1 when it sits half a cell right - on the
## half layer, 4 px - else 0).
static func centred_x(rom: PackedByteArray, f: int, b: PackedByteArray, twice_centre: int) -> Vector2i:
	var twice_x := twice_centre - MwGlyphs.text_width(rom, f, b)
	@warning_ignore("integer_division")
	return Vector2i((twice_x - twice_x % 2) / 2, twice_x % 2)


## An item: framed when [param selected], [param label] centred in its
## frame to the half cell ([param half]: the layer 4 px right).
static func item(on: RomPlane, half: RomPlane, rom: PackedByteArray, label: PackedByteArray, x: int, y: int, w: int,
		selected: bool, attr: int) -> void:
	frame(on, rom, x, y, w, selected)
	var f := font(selected)
	var c := centred_x(rom, f, label, 2 * x + w)
	MwGlyphs.text(half if c.y != 0 else on, rom, f, label, c.x, y, attr)

