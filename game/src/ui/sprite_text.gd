class_name MwSpriteText
extends RefCounted
## Strings drawn as sprites, one font piece per character (for [RomPieces]):
## `draw_text_sprites` ($F3CC: each character advances by its width in
## cells, spaces by the font's) and `$B772` (big letters a fixed 24 pixels
## apart, spaces 8). Pieces are relative to (0, 0) = the string's start on
## the font's baseline row; [param attr] (the original's D3) XORs their
## palette line.


## `$F3CC`: [pieces, x after the string].
static func pieces(rom: PackedByteArray, font: int, bytes: PackedByteArray, attr: int, x := 0) -> Array:
	var out := []
	for c in bytes:
		if c != 0x20:
			var g := MwGfx.font_glyph(rom, font, c)
			if g >= 0:
				out.append(_piece(rom, font, g, x, attr))
		x += 8 * MwGfx.char_width(rom, font, c)
	return [out, x]


## `$B772`: [pieces, x after the string] with a fixed [param advance].
static func fixed(rom: PackedByteArray, font: int, bytes: PackedByteArray, attr: int, advance := 0x18,
		space := 8) -> Array:
	var out := []
	var x := 0
	for c in bytes:
		if c == 0x20:
			x += space
			continue
		var g := MwGfx.font_glyph(rom, font, c)
		if g >= 0:
			out.append(_piece(rom, font, g, x, attr))
		x += advance
	return [out, x]


static func _piece(rom: PackedByteArray, font: int, g: int, x: int, attr: int) -> Dictionary:
	var glyph_piece := MwGfx.piece(rom, font + 8 + 6 * g)
	glyph_piece["x"] = int(glyph_piece["x"]) + x
	glyph_piece["attr"] = int(glyph_piece["attr"]) ^ (attr & 0x60)
	return glyph_piece
