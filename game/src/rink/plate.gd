class_name MwPlate
extends RefCounted
## A player's info plate (docs/re/rink.md, Markers): 8 tiles the original
## keeps in RAM (`$FFBE80` + 256 * plate slot, VRAM tile `$5F4` + 8 * slot)
## under the crossbones marker, a 32x16 sprite piece (tiles column-major).
## `$6146` clears them, `$62D8`/`$6166` redraw what changed:
##
## * tile 0 and tile 2 (top row, columns 0-1): the jersey number's two
##   decimal digits (`$6362`), tile 6 (top row, column 3): the position letter
##   `"CLRDDG"[position]` (`$6388`), glyph tiles copied from font `$4CACC`;
## * with Reserves on, rows 1-5 of tiles 1, 3, 5, 7 (the bottom row): a 32
##   px health bar (`$630A`), `health` pixels of colour 1, the rest colour 7.
##
## A value of `$FF` was never drawn (the marker's initial state): blank.

const FONT := 0x4CACC
const LETTERS := 0x1C5BC
const NONE := 0xFF


## The plate's 256 bytes (8 tiles, 4 bits per pixel, as in VRAM).
static func tiles(rom: PackedByteArray, number: int, position: int, health: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(256)
	if number != NONE:
		_glyph(rom, out, 0, 0x30 + number / 10)
		_glyph(rom, out, 2, 0x30 + number % 10)
	if position != NONE:
		_glyph(rom, out, 6, rom[LETTERS + position])
	if health != NONE:
		var v := health
		for t in 4:
			var row: int
			if v < 0:
				row = 0x77777777
			elif v >= 8:
				row = 0x11111111
			else:
				var yellow := (0x11111111 << (32 - 4 * v)) & 0xFFFFFFFF if v > 0 else 0
				row = yellow | (0x77777777 >> (4 * v))
			for r in range(1, 6):
				var a := 32 * (2 * t + 1) + 4 * r
				out[a] = (row >> 24) & 0xFF
				out[a + 1] = (row >> 16) & 0xFF
				out[a + 2] = (row >> 8) & 0xFF
				out[a + 3] = row & 0xFF
			v -= 8
	return out


## `$63A2`: the glyph tile of [param ch] into tile [param t]. A character
## the font lacks (an unused marker's number 127 - tens "<" - or position
## 7 - char 3 -, which only the instant replay writes) leaves the glyph
## lookup `$14BA0` with a null piece: its tile word is read from ROM address
## 4 (the reset vector's low word) and that "tile" copied.
static func _glyph(rom: PackedByteArray, out: PackedByteArray, t: int, ch: int) -> void:
	var g := MwGfx.font_glyph(rom, FONT, ch)
	var piece := FONT + 8 + 6 * g if g >= 0 else 0
	var src := MwGfx.u16(rom, piece + 4) << 5
	for i in 32:
		out[32 * t + i] = rom[src + i]


## What a plate's 256 bytes show: [number, position, health], [constant
## NONE] for a part never drawn (the inverse of [method tiles]; the
## comparisons read the original's RAM plates with it).
static var _digits := {}
static var _letters := {}


static func values(rom: PackedByteArray, data: PackedByteArray) -> Array:
	var blank := PackedByteArray()
	blank.resize(32)
	if data == PackedByteArray() or data.slice(0, 256).count(0) == 256:
		return [NONE, NONE, NONE]
	var t: Array[PackedByteArray] = []
	for i in 8:
		t.append(data.slice(32 * i, 32 * i + 32))
	if _digits.is_empty():
		for d in 10:
			var g := PackedByteArray()
			g.resize(256)
			_glyph(rom, g, 0, 0x30 + d)
			_digits[g.slice(0, 32)] = d
		for i in 6:
			var g := PackedByteArray()
			g.resize(256)
			_glyph(rom, g, 0, rom[LETTERS + i])
			if not _letters.has(g.slice(0, 32)):
				_letters[g.slice(0, 32)] = i
	var digits := _digits
	var letters := _letters
	var number := NONE
	if t[0] != blank or t[2] != blank:
		number = 10 * int(digits.get(t[0], 0)) + int(digits.get(t[2], 0))
	var position := NONE
	if t[6] != blank:
		position = int(letters.get(t[6], NONE))
	var health := NONE
	var row1 := PackedByteArray()
	for i in 4:
		row1.append_array(t[2 * i + 1].slice(4, 8))
	var zero := PackedByteArray()
	zero.resize(16)
	if row1 != zero:
		health = 0
		for b in row1:
			if b >> 4 == 1:
				health += 1
			if b & 15 == 1:
				health += 1
	return [number, position, health]
