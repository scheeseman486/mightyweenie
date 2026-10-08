class_name MwScoreboardBackdrop
extends RefCounted
## What the scoreboards' common set-up (`$9034`, screens 12-19) and score
## panel (`$8EF4`) draw, as MwWindowPainter operations (plan 11,
## docs/re/scoreboards.md): plane B holds the scoreboard (map `$3F46C` of the
## picture `$3F460` from row 1) and its numbers, the window the panel's
## picture (the menu panel `$4A066` for 12-16, the message panel `$3C264`
## for 17-19, from row 18) and the texts. The scene loads the pictures
## ([method pictures]) and paints the operations.

const SCOREBOARD := 0x3F460          ## picture_load
const PLANE_FILLS := 0x1C8F8         ## 3 x (word, x, y, w, h) on plane B
const SCOREBOARD_MAP := 0x1C916      ## (map.l, row bytes, VRAM, dest stride, src stride, rows)
const PANELS := 0x1C948              ## by screen - 12: -> (picture.l, map.l, row bytes, VRAM, strides, rows)
const NAME_X := 0x1C982              ## per team: centre (doubled) of the name, x of the score
const MENU_TEXTS := 0x1C98A          ## 12-14, 17: 5 x (x, y, attr .w, string .l)
const MENU_TEXTS_OVER := 0x1C9BC     ## 15, 16: 3 entries
const FONT := 0x447F4                ## names, numbers, times, menu texts
const FONT_SCORE := 0x22D66          ## the scores
const ATTR := 0x60
const PLANE_B_VRAM := 0xE000         ## 64 cells a row
const WINDOW_VRAM := 0xF000
const ROW_BYTES := 0x80


## The pictures the screen loads (`picture_load`): the scoreboard, then
## its panel.
static func pictures(rom: PackedByteArray, screen: int) -> PackedInt32Array:
	var entry := MwGfx.u32(rom, PANELS + 4 * (screen - 12))
	return PackedInt32Array([SCOREBOARD, MwGfx.u32(rom, entry)])


## `$9034`'s drawing: {"window": ops, "plane": ops} - the window cleared
## (`$146D6`, `$8000`) with the panel's map rows (`map_copy` to VRAM
## `$F900`: row 18), plane B's fills (`$1C8F8`) and the scoreboard's map
## (VRAM `$E080`: row 1, 17 rows), then the score panel ([method numbers]).
static func setup_ops(rom: PackedByteArray, s: MwRinkState, screen: int) -> Dictionary:
	var window := [["fill", 0, 0, 64, 32, 0x8000]]
	var plane := []
	for i in 3:
		var a := PLANE_FILLS + 10 * i
		plane.append(["fill", MwGfx.u16(rom, a + 2), MwGfx.u16(rom, a + 4), MwGfx.u16(rom, a + 6),
				MwGfx.u16(rom, a + 8), MwGfx.u16(rom, a)])
	var entry := MwGfx.u32(rom, PANELS + 4 * (screen - 12))
	window.append(_map(rom, entry + 4, WINDOW_VRAM))
	plane.append(_map(rom, SCOREBOARD_MAP, PLANE_B_VRAM))
	plane.append_array(numbers(rom, s))
	return {"window": window, "plane": plane}


## A `map_copy` record (map.l, row bytes, VRAM, dest stride, src stride,
## rows) as ["map", map, stride (words), w, h, x, y] on the plane at [param base].
static func _map(rom: PackedByteArray, a: int, base: int) -> Array:
	var vram := MwGfx.u16(rom, a + 6)
	var at := vram - base
	return ["map", MwGfx.u32(rom, a), MwGfx.u16(rom, a + 10) / 2, MwGfx.u16(rom, a + 4) / 2,
			MwGfx.u16(rom, a + 12), (at % ROW_BYTES) / 2, at / ROW_BYTES]


## `$8EF4`: the score panel on plane B - per team its name (centred on
## column 13 / 27, row 6), its score (two digits, row 7) and its penalty
## box (each entry's number at column 9 / 24, row 11 + its rank, then its
## time as m:ss), then the game clock at (17, 14) unless after a fight
## (phase 4).
static func numbers(rom: PackedByteArray, s: MwRinkState) -> Array:
	var ops := []
	for t in 2:
		var team := s.teams[t]
		var name := MwGfx.u32(rom, team.record + 4)
		var w := MwRinkPhases.text_width(rom, FONT, name)
		ops.append(["text", FONT, ((MwGfx.u16(rom, NAME_X + 4 * t) - w) & 0xFFFF) >> 1, 6, ATTR, name])
		_two_digits(ops, FONT_SCORE, team.score & 0xFFFF, MwGfx.u16(rom, NAME_X + 4 * t + 2), 7)
		for i in 3:
			var e := MwRinkPenalties.entry(i)
			if team.stat(e + 0x10, 1) == 0:
				continue
			var x := 0x18 if team.flags4 & 1 else 9
			_two_digits(ops, FONT, team.stat(e + 0x12, 1), x, 0xB + team.stat(e + 0x13, 1))
			_mss(ops, team.stat(e + 0xC), -1, 0xB + team.stat(e + 0x13, 1))   # right after the number, its row
	if s.phase != 4:
		_mss(ops, s.clock & 0xFFFF, 0x11, 0xE)
	return ops


## `$F3B0`: two digits (tens, ones) as glyphs, at ([param x], [param y])
## or (x < 0) right after the last glyph.
static func _two_digits(ops: Array, font: int, v: int, x: int, y: int) -> void:
	_glyph(ops, font, 0x30 + (v / 10) % 256, x, y)
	_glyph(ops, font, 0x30 + v % 10, -1, y)


## `$F37A`: m:ss (minutes space-padded below 10) in [constant FONT].
static func _mss(ops: Array, seconds: int, x: int, y: int) -> void:
	var m := seconds / 60
	var sec := seconds % 60
	if m < 10:
		_glyph(ops, FONT, 0x20, x, y)
		_glyph(ops, FONT, 0x30 + m, -1, y)
	else:
		_two_digits(ops, FONT, m, x, y)
	_glyph(ops, FONT, 0x3A, -1, y)
	_two_digits(ops, FONT, sec, -1, y)


static func _glyph(ops: Array, font: int, ch: int, x: int, y: int) -> void:
	if x < 0:
		ops.append(["glyph_after", font, y, ATTR, ch])
	else:
		ops.append(["glyph", font, x, y, ATTR, ch])


## `$8FD8`: the scoreboard menu's texts on the window: 12-14 and 17 "A",
## the B line ("Reserves and Plays" with Reserves on), "C", Start; 15 / 16
## without B.
static func menu_texts(rom: PackedByteArray, screen: int, reserves: bool) -> Array:
	var ops := []
	var rows: Array = []
	if screen >= 0x11 or screen < 0xF:
		rows = [0, 1, 3, 4] if reserves else [0, 2, 3, 4]
		for i in rows:
			ops.append(_menu_text(rom, MENU_TEXTS + 10 * i))
	else:
		for i in 3:
			ops.append(_menu_text(rom, MENU_TEXTS_OVER + 10 * i))
	return ops


static func _menu_text(rom: PackedByteArray, a: int) -> Array:
	return ["text", FONT, MwGfx.u16(rom, a), MwGfx.u16(rom, a + 2), MwGfx.u16(rom, a + 4), MwGfx.u32(rom, a + 6)]
