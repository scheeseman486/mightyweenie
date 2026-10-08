@tool
class_name MwGfx
extends RefCounted
## Decoders for the original's graphics (docs/re/graphics.md), mirroring
## harness/mw_harness/gfx.py. They read the ROM bytes and return numbers,
## indexed pixels and dictionaries; nothing is stored. GUT checks them against
## the Python decoders by hash (compare/fixtures/gfx_hashes.json).
##
## Indexed pixels: value = palette line * 16 + colour index, and colour 0 of
## any line is transparent, so it stays 0.

# --- big-endian reads ------------------------------------------------------------
static func u8(rom: PackedByteArray, a: int) -> int:
	return rom[a]


static func s8(rom: PackedByteArray, a: int) -> int:
	var v := rom[a]
	return v - 256 if v >= 128 else v


static func u16(rom: PackedByteArray, a: int) -> int:
	return (rom[a] << 8) | rom[a + 1]


static func s16(rom: PackedByteArray, a: int) -> int:
	var v := u16(rom, a)
	return v - 0x10000 if v >= 0x8000 else v


static func u32(rom: PackedByteArray, a: int) -> int:
	return (rom[a] << 24) | (rom[a + 1] << 16) | (rom[a + 2] << 8) | rom[a + 3]


static func words(rom: PackedByteArray, a: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	for i in count:
		out[i] = u16(rom, a + 2 * i)
	return out


# --- tiles and colours -----------------------------------------------------------
## One 32-byte tile -> 64 colour indices, rows top to bottom, left pixel in the
## high nibble.
static func tile_indices(rom: PackedByteArray, a: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(64)
	for i in 32:
		var b := rom[a + i]
		out[i * 2] = b >> 4
		out[i * 2 + 1] = b & 15
	return out


## [param count] tiles from [param a], 64 indices each, concatenated.
static func tiles(rom: PackedByteArray, a: int, count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(64 * count)
	for i in 32 * count:
		var b := rom[a + i]
		out[i * 2] = b >> 4
		out[i * 2 + 1] = b & 15
	return out


## Genesis colour word 0000BBB0GGG0RRR0 -> 8-bit channels (x * 255 / 7).
static func color_rgb8(word: int) -> PackedByteArray:
	var r := (word >> 1) & 7
	var g := (word >> 5) & 7
	var b := (word >> 9) & 7
	return PackedByteArray([r * 255 / 7, g * 255 / 7, b * 255 / 7])


static func color(word: int) -> Color:
	var c := color_rgb8(word)
	return Color8(c[0], c[1], c[2])


static func palette_rgb(rom: PackedByteArray, a: int, count := 16) -> PackedByteArray:
	var out := PackedByteArray()
	for w in words(rom, a, count):
		out.append_array(color_rgb8(w))
	return out


# --- pictures (tile bank + map) ------------------------------------------------------
## `tiles.l, vram_base.w, count.w, width.w, height.w`, map words from +12.
static func picture(rom: PackedByteArray, a: int) -> Dictionary:
	return {"address": a, "tiles": u32(rom, a), "vram_base": u16(rom, a + 4), "count": u16(rom, a + 6),
			"width": u16(rom, a + 8), "height": u16(rom, a + 10), "map": a + 12}


## Name-table word -> {tile, hflip, vflip, line, priority}.
static func cell(word: int) -> Dictionary:
	return {"tile": word & 0x7FF, "hflip": (word & 0x800) != 0, "vflip": (word & 0x1000) != 0,
			"line": (word >> 13) & 3, "priority": (word & 0x8000) != 0}


## Draws a 64-index tile into [param img] (row stride [param stride]) at
## px/py: values become line * 16 + index; index 0 is skipped when
## [param transparent0].
static func blit_tile(img: PackedByteArray, stride: int, px: int, py: int, t: PackedByteArray,
		line: int, hflip: bool, vflip: bool, transparent0 := true) -> void:
	var base := line * 16
	for r in 8:
		var sr := 7 - r if vflip else r
		var row := (py + r) * stride + px
		for c in 8:
			var v := t[sr * 8 + (7 - c if hflip else c)]
			if v == 0:
				if transparent0:
					continue
				img[row + c] = 0
			else:
				img[row + c] = base + v


## The picture's whole map as indexed pixels: {w, h, px}. Cells whose tile is
## outside the picture's bank stay 0.
static func picture_image(rom: PackedByteArray, pic: Dictionary) -> Dictionary:
	var w: int = pic["width"] * 8
	var h: int = pic["height"] * 8
	var img := PackedByteArray()
	img.resize(w * h)
	var count: int = pic["count"]
	var bank := tiles(rom, pic["tiles"], count)
	var cache := {}
	for i in pic["width"] * pic["height"]:
		var word := u16(rom, pic["map"] + 2 * i)
		var k: int = (word & 0x7FF) - pic["vram_base"]
		if k < 0 or k >= count:
			continue
		if not cache.has(k):
			cache[k] = bank.slice(64 * k, 64 * k + 64)
		blit_tile(img, w, (i % pic["width"]) * 8, (i / pic["width"]) * 8, cache[k],
				(word >> 13) & 3, (word & 0x800) != 0, (word & 0x1000) != 0)
	return {"w": w, "h": h, "px": img}


# --- sprites ---------------------------------------------------------------------------
## Piece `x.b, y.b, size.b, attr.b, tile.w`: {x, y, w, h (cells), attr, tile}.
## Tiles >= $800 are ROM address / 32, column-major.
static func piece(rom: PackedByteArray, a: int) -> Dictionary:
	var size := rom[a + 2]
	return {"x": s8(rom, a), "y": s8(rom, a + 1), "w": ((size >> 2) & 3) + 1, "h": (size & 3) + 1,
			"attr": rom[a + 3], "tile": u16(rom, a + 4)}


static func frame_pieces(rom: PackedByteArray, a: int) -> Array:
	var out := []
	for i in u16(rom, a):
		out.append(piece(rom, a + 2 + 6 * i))
	return out


## Mirrors a whole frame ($156C6): x' = -(x + width), flip bit toggled.
static func flip_pieces(pieces: Array, flips: int) -> Array:
	var out := []
	for p in pieces:
		var q: Dictionary = p.duplicate()
		if flips & 1:
			q["x"] = -p["x"] - 8 * p["w"]
			q["attr"] = q["attr"] ^ 0x08
		if flips & 2:
			q["y"] = -p["y"] - 8 * p["h"]
			q["attr"] = q["attr"] ^ 0x10
		out.append(q)
	return out


## Bounds of pieces: [x0, y0, x1, y1].
static func frame_bounds(pieces: Array) -> Array:
	if pieces.is_empty():
		return [0, 0, 0, 0]
	var b := [999, 999, -999, -999]
	for p in pieces:
		b[0] = mini(b[0], p["x"])
		b[1] = mini(b[1], p["y"])
		b[2] = maxi(b[2], p["x"] + 8 * p["w"])
		b[3] = maxi(b[3], p["y"] + 8 * p["h"])
	return b


## Composes a frame: {ox, oy (origin inside the image), w, h, px}. Later
## pieces are drawn on top (`add_sprite_piece` puts a piece in front of the
## earlier ones of the same depth; docs/re/rink.md, Sprite list). [param bounds]
## ([x0, y0, x1, y1]) fixes the canvas, e.g. one box for a whole animation.
static func frame_image(rom: PackedByteArray, pieces: Array, flips := 0, bounds := []) -> Dictionary:
	if flips:
		pieces = flip_pieces(pieces, flips)
	var b: Array = bounds if not bounds.is_empty() else frame_bounds(pieces)
	var w: int = b[2] - b[0]
	var h: int = b[3] - b[1]
	var img := PackedByteArray()
	img.resize(w * h)
	for p: Dictionary in pieces:
		if p["tile"] < 0x800:
			continue
		var base: int = p["tile"] << 5
		if base + 32 * p["w"] * p["h"] > rom.size():
			continue                      # not a frame (bad data): draw nothing
		var hf: bool = (p["attr"] & 0x08) != 0
		var vf: bool = (p["attr"] & 0x10) != 0
		var line: int = (p["attr"] >> 5) & 3
		for cx in p["w"]:
			for cy in p["h"]:
				var t := tile_indices(rom, base + 32 * (cx * p["h"] + cy))
				var dx: int = p["w"] - 1 - cx if hf else cx
				var dy: int = p["h"] - 1 - cy if vf else cy
				blit_tile(img, w, p["x"] - b[0] + dx * 8, p["y"] - b[1] + dy * 8, t, line, hf, vf)
	return {"ox": -b[0], "oy": -b[1], "w": w, "h": h, "px": img}


## Animation `speed.w, flags.b, count.b, frames.l` + variant table (words
## `list_offset << 2 | flips`, ending where the first list starts):
## {address, speed, flags, count, frames, variants: [[list address, flips], ...]}.
static func animation(rom: PackedByteArray, a: int) -> Dictionary:
	var variants := []
	var end := -1
	var pos := a + 8
	while end < 0 or pos < end:
		var w := u16(rom, pos)
		var lst := a + (w >> 2)
		variants.append([lst, w & 3])
		end = lst if end < 0 else mini(end, lst)
		pos += 2
	return {"address": a, "speed": u16(rom, a), "flags": rom[a + 2], "count": rom[a + 3],
			"frames": u32(rom, a + 4), "variants": variants}


static func anim_offsets(rom: PackedByteArray, anim: Dictionary, variant := 0) -> PackedInt32Array:
	return words(rom, anim["variants"][variant][0], anim["count"])


## Every distinct frame address of an animation (all variants).
static func anim_frame_addresses(rom: PackedByteArray, anim: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in anim["variants"].size():
		for o in anim_offsets(rom, anim, v):
			var f: int = anim["frames"] + o
			if not f in out:
				out.append(f)
	return out


## Frames per second of an animation: position advances speed/256 frames per
## 60 Hz tick ($143CA).
static func anim_fps(anim: Dictionary) -> float:
	return 60.0 * anim["speed"] / 256.0


# --- fonts -----------------------------------------------------------------------------------
## Glyph piece addresses: `+6` count, glyphs (6-byte pieces) from `+8`.
static func font_glyphs(rom: PackedByteArray, a: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in u16(rom, a + 6):
		out.append(a + 8 + 6 * i)
	return out


## Character -> glyph index for `!`-`~` (map at `font + (+4) - $21 + char`).
static func font_char_map(rom: PackedByteArray, a: int) -> Dictionary:
	var offset := u16(rom, a + 4)
	var count := u16(rom, a + 6)
	var out := {}
	for c in range(0x21, 0x7F):
		var g := s8(rom, a + offset - 0x21 + c)
		if g >= 0 and g < count:
			out[char(c)] = g
	return out


# --- text (draw_text $14CAE, draw_glyph $14C26; docs/re/title.md) ------------------------------
## The 0-terminated string at [param a], without the 0.
static func rom_string(rom: PackedByteArray, a: int) -> PackedByteArray:
	var e := a
	while rom[e] != 0:
		e += 1
	return rom.slice(a, e)


## Glyph index of character code [param ch] (`!`-`~`), -1 when the font has none.
static func font_glyph(rom: PackedByteArray, font: int, ch: int) -> int:
	if ch < 0x21 or ch > 0x7E:
		return -1
	var g := s8(rom, font + u16(rom, font + 4) - 0x21 + ch)
	return g if g >= 0 and g < u16(rom, font + 6) else -1


## `$14BCE`: cells a character advances (space: font +2; no glyph: 0).
static func char_width(rom: PackedByteArray, font: int, ch: int) -> int:
	if ch == 0x20:
		return u16(rom, font + 2)
	var g := font_glyph(rom, font, ch)
	return 0 if g < 0 else ((rom[font + 8 + 6 * g + 2] >> 2) & 3) + 1


## `$14C14`: width of a string in cells.
static func text_width(rom: PackedByteArray, font: int, text: PackedByteArray) -> int:
	var w := 0
	for c in text:
		w += char_width(rom, font, c)
	return w


## Where `draw_text` puts each glyph of [param text] drawn at cell (x, y):
## [{x, y (top cell), w, h, tiles (ROM address of the first tile)}]. Glyphs
## sit on the baseline (top = y + font +0 - height); their tiles are
## column-major; the piece's attr is not used (the caller's line applies).
static func text_glyphs(rom: PackedByteArray, font: int, text: PackedByteArray, x := 0, y := 0) -> Array:
	var baseline := s16(rom, font)
	var space := u16(rom, font + 2)
	var out := []
	for c in text:
		if c == 0x20:
			x += space
			continue
		var g := font_glyph(rom, font, c)
		if g < 0:
			continue
		var p := piece(rom, font + 8 + 6 * g)
		out.append({"x": x, "y": y + baseline - int(p["h"]), "w": p["w"], "h": p["h"], "tiles": int(p["tile"]) * 32})
		x += int(p["w"])
	return out


## A string as indexed pixels: {top (row of the image's top relative to the
## text's row), w, h (pixels), px}. Width = the string's width in cells.
static func text_image(rom: PackedByteArray, font: int, text: PackedByteArray, line := 0) -> Dictionary:
	var glyphs := text_glyphs(rom, font, text)
	var w := 8 * text_width(rom, font, text)
	if glyphs.is_empty():
		return {"top": 0, "w": w, "h": 0, "px": PackedByteArray()}
	var top := 999
	var bottom := -999
	for g in glyphs:
		top = mini(top, g["y"])
		bottom = maxi(bottom, g["y"] + g["h"])
	var h := 8 * (bottom - top)
	var px := PackedByteArray()
	px.resize(w * h)
	for g in glyphs:
		for cx in int(g["w"]):
			for cy in int(g["h"]):
				var t := tile_indices(rom, int(g["tiles"]) + 32 * (cx * int(g["h"]) + cy))
				blit_tile(px, w, 8 * (int(g["x"]) + cx), 8 * (int(g["y"]) - top + cy), t, line, false, false)
	return {"top": top, "w": w, "h": h, "px": px}


## A credit page's strings (`$DD4`): the heading (may be empty), then body
## lines up to an empty string. Their addresses.
static func string_list(rom: PackedByteArray, a: int) -> PackedInt32Array:
	var out := PackedInt32Array([a])
	var p := a + rom_string(rom, a).size() + 1
	while rom[p] != 0:
		out.append(p)
		p += rom_string(rom, p).size() + 1
	return out


# --- hashes (compare/fixtures/gfx_hashes.json) ------------------------------------------------
static func sha1(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(data)
	return ctx.finish().hex_encode()


static func _be16(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 8) & 0xFF, v & 0xFF])


## A composed frame as hashed: origin x/y (signed), width, height (big-endian
## words), then the pixels.
static func frame_record(rom: PackedByteArray, pieces: Array, flips := 0) -> PackedByteArray:
	var f := frame_image(rom, pieces, flips)
	var out := _be16(f["ox"] & 0xFFFF) + _be16(f["oy"] & 0xFFFF) + _be16(f["w"]) + _be16(f["h"])
	out.append_array(f["px"])
	return out


## SHA-1 of what each catalogue entry decodes to (as gfx.catalogue_hashes).
static func catalogue_hashes(rom: PackedByteArray, cat: Dictionary) -> Dictionary:
	var out := {}
	var entries: Dictionary = cat["entries"]
	for key in entries:
		var e: Dictionary = entries[key]
		var a := int(e["address"])
		match e["kind"]:
			"picture", "tilebank":
				out[key + "/tiles"] = sha1(tiles(rom, int(e["tiles"]), int(e["count"])))
				if e["kind"] == "picture":
					var img := picture_image(rom, picture(rom, a))
					out[key + "/image"] = sha1(_be16(img["w"]) + _be16(img["h"]) + img["px"])
			"palette":
				out[key] = sha1(palette_rgb(rom, a))
			"anim":
				var an := animation(rom, a)
				var data := PackedByteArray()
				for v in an["variants"].size():
					for o in anim_offsets(rom, an, v):
						data.append_array(frame_record(rom, frame_pieces(rom, an["frames"] + o), an["variants"][v][1]))
				out[key] = sha1(data)
			"font":
				var data := PackedByteArray()
				for g in font_glyphs(rom, a):
					data.append_array(frame_record(rom, [piece(rom, g)]))
				var cmap := font_char_map(rom, a)
				var chars := cmap.keys()
				chars.sort()
				var s := ""
				for c in chars:
					s += "%s%02x" % [c, cmap[c]]
				data.append_array(s.to_utf8_buffer())
				out[key] = sha1(data)
			"map":
				var data := PackedByteArray()
				for r in int(e["rows"]):
					for c in int(e["cols"]):
						data.append_array(_be16(u16(rom, a + r * int(e["src_stride"]) + 2 * c)))
				out[key] = sha1(data)
	for group in cat.get("frames", {}):
		var data := PackedByteArray()
		for f in cat["frames"][group]:
			data.append_array(frame_record(rom, frame_pieces(rom, int(f))))
		out["frames/" + group] = sha1(data)
	for caller in cat.get("pieces", {}):
		var data := PackedByteArray()
		for p in cat["pieces"][caller]["pieces"]:
			data.append_array(frame_record(rom, [piece(rom, int(p))]))
		out["pieces/" + caller] = sha1(data)
	for key in entries:
		var e: Dictionary = entries[key]
		if e["kind"] == "font":
			for sa in e.get("strings", []):
				var img := text_image(rom, int(e["address"]), rom_string(rom, int(sa)))
				var rec := _be16(int(img["top"]) & 0xFFFF) + _be16(img["w"]) + _be16(img["h"])
				rec.append_array(img["px"])
				out["text/%s/%06x" % [key, int(sa)]] = sha1(rec)
	return out
