class_name MwSpriteText
extends RefCounted
## Strings drawn as sprites, one font piece per character (for [RomPieces]):
## `draw_text_sprites` ($F3CC: each character advances by its width in
## cells, spaces by the font's) and `$B772` (big letters a fixed 24 pixels
## apart, spaces 8). Pieces are relative to (0, 0) = the string's start on
## the font's baseline row; [param attr] (the original's D3) XORs their
## palette line.


## `$F3CC`: [pieces, x after the string].
static func pieces(rom: PackedByteArray, font: int, s: PackedByteArray, attr: int, x := 0) -> Array:
	var out := []
	for c in s:
		if c != 0x20:
			var g := MwGfx.font_glyph(rom, font, c)
			if g >= 0:
				out.append(_piece(rom, font, g, x, attr))
		x += 8 * MwGfx.char_width(rom, font, c)
	return [out, x]


## `$B772`: [pieces, x after the string] with a fixed [param advance].
static func fixed(rom: PackedByteArray, font: int, s: PackedByteArray, attr: int, advance := 0x18, space := 8) -> Array:
	var out := []
	var x := 0
	for c in s:
		if c == 0x20:
			x += space
			continue
		var g := MwGfx.font_glyph(rom, font, c)
		if g >= 0:
			out.append(_piece(rom, font, g, x, attr))
		x += advance
	return [out, x]


static func _piece(rom: PackedByteArray, font: int, g: int, x: int, attr: int) -> Dictionary:
	var p := MwGfx.piece(rom, font + 8 + 6 * g)
	p["x"] = int(p["x"]) + x
	p["attr"] = int(p["attr"]) ^ (attr & 0x60)
	return p
