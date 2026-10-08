class_name MwPlanePainter
extends RefCounted
## The original's plane-drawing routines, ported to paint a [RomPlane]
## (docs/re/menus.md, Drawing). Coordinates are cells. `attr` is the
## original's D3 byte, the high byte of a name-table word: bit 7 priority
## (kept only by a plane with [member RomPlane.high_cells]), bits 6-5 palette line, bit 4 vertical flip, bit 3 horizontal.

const FONT_SMALL := 0x1F958     ## dark menu font; also the frame glyphs
const FONT_MENU := 0x447F4      ## light menu font
## Frame glyphs of $1F958 (`$BA98`): corners, horizontal and vertical edges.
const CH_CORNER := 0x40
const CH_EDGE_H := 0x7E
const CH_EDGE_TOP := 0x7B
const CH_EDGE_MID := 0x7C
const CH_EDGE_ONE := 0x7D
## The light font's `=`: a blank cell (erased frames, the roster's padding).
const CH_BLANK := 0x3D
## Fill of a selected frame: tile $DD (`$15926` with $E0DD) - the last tile
## of the menu backdrop picture, a solid colour.
const FILL_WORD := 0xE0DD


static func _line(attr: int) -> int:
	return (attr >> 5) & 3


## `$146EA`: a rectangle of the same name-table word.
static func fill(plane: RomPlane, x: int, y: int, w: int, h: int, word: int) -> void:
	for yy in h:
		for xx in w:
			plane.put_word(x + xx, y + yy, word)


## `$BD82`: erases a frame and its border (fills (x-1, y-1, w+2, h+2) with
## the blank tile).
static func erase_frame(plane: RomPlane, x: int, y: int, w: int, h: int) -> void:
	fill(plane, x - 1, y - 1, w + 2, h + 2, 0x8000)


## `$14C3E`: glyph of character [param ch] at (x, y) - bottom on the font's
## baseline, tiles column-major. Returns the cells advanced.
static func glyph(plane: RomPlane, rom: PackedByteArray, font: int, ch: int, x: int, y: int, attr: int) -> int:
	if ch == 0x20:
		return MwGfx.u16(rom, font + 2)
	var g := MwGfx.font_glyph(rom, font, ch)
	if g < 0:
		return 0
	var p := MwGfx.piece(rom, font + 8 + 6 * g)
	var w: int = p["w"]
	var h: int = p["h"]
	var top := y + MwGfx.s16(rom, font) - h
	var tile: int = p["tile"]
	plane.priority = (attr & 0x80) != 0
	for cy in h:
		for cx in w:
			plane.put(x + cx, top + cy, tile + cx * h + cy, _line(attr), (attr & 0x08) != 0, (attr & 0x10) != 0)
	return w


## `draw_text` ($14CAE): a string from cell (x, y). Returns the x after it.
static func text(plane: RomPlane, rom: PackedByteArray, font: int, s: PackedByteArray, x: int, y: int, attr: int) -> int:
	for c in s:
		x += glyph(plane, rom, font, c, x, y, attr)
	return x


## `$BA98`: a frame around the cells (x, y, w, h) drawn with the frame glyphs
## of $1F958 (`$BA98`, `$B9F2`, `$BA08`, `$BA40`), filled with tile $DD when
## [param filled] (`$C3B4`). [param erase] (`$C3BC`, `$B9CA`): every glyph
## is the light font's blank `=` instead - the frame rubbed out.
static func frame(plane: RomPlane, rom: PackedByteArray, x: int, y: int, w: int, h: int, filled: bool, erase := false) -> void:
	var g := func(ch: int, gx: int, gy: int, a: int) -> void:
		if erase:
			glyph(plane, rom, FONT_MENU, CH_BLANK, gx, gy, a)
		else:
			glyph(plane, rom, FONT_SMALL, ch, gx, gy, a)
	for i in w:                                     # top and bottom edges
		g.call(CH_EDGE_H, x + i, y - 1, 0xE0)
		g.call(CH_EDGE_H, x + i, y + h, 0xF0)
	for side in [[x - 1, 0xE0], [x + w, 0xE8]]:      # left and right edges
		var sx: int = side[0]
		var a: int = side[1]
		if h == 1:
			g.call(CH_EDGE_ONE, sx, y, a)
		else:
			g.call(CH_EDGE_TOP, sx, y, a)
			for i in range(1, h - 1):
				g.call(CH_EDGE_MID, sx, y + i, a)
			g.call(CH_EDGE_TOP, sx, y + h - 1, a | 0x10)
	g.call(CH_CORNER, x - 1, y - 1, 0xE0)       # corners
	g.call(CH_CORNER, x - 1, y + h, 0xF0)
	g.call(CH_CORNER, x + w, y - 1, 0xE8)
	g.call(CH_CORNER, x + w, y + h, 0xF8)
	if filled:
		fill(plane, x, y, w, h, FILL_WORD)


## `map_copy` ($1449C) of a picture's map rows: [param rows] rows from map
## row [param src_row] to plane row [param dst_row] (all columns).
static func map_rows(plane: RomPlane, rom: PackedByteArray, picture: int, src_row: int, rows: int, dst_row: int, dst_x := 0) -> void:
	var pic := MwGfx.picture(rom, picture)
	var w: int = pic["width"]
	var base: int = pic["map"]
	for r in rows:
		for c in w:
			plane.put_word(dst_x + c, dst_row + r, MwGfx.u16(rom, base + 2 * ((src_row + r) * w + c)))


## `map_copy` ($1449C) of a rectangle: [param w] x [param h] name-table
## words from the map at [param map] (rows [param stride] words apart) to
## the plane's cell ([param x], [param y]).
static func map_rect(plane: RomPlane, rom: PackedByteArray, map: int, stride: int, w: int, h: int, x: int, y: int) -> void:
	for r in h:
		for c in w:
			plane.put_word(x + c, y + r, MwGfx.u16(rom, map + 2 * (r * stride + c)))
