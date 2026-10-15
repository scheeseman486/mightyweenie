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
## Plan 34: the players' number tags (extended set-ups, MwRinkDraw's
## markers) take the plate slots from here on, player n slot 15 + n - past
## the fourteen plates (MwRinkState.PLATES_EXTENDED).
const TAG_SLOT := 16
## Plan 34 (section 7): the owners' hollow mark (MwRinkDraw: an owned player
## driven by someone else or the CPU) and the captain's C beside the player's
## number, each in four variants - the face index of pads 1-4's crossbones
## (players 1-4 on line 3; players 5-12 take pad 1's on their own line) -
## from these plate slots on (past the tags).
const RING_SLOT := 28
const CAPTAIN_SLOT := 32
## The hollow mark (port art): a ring on the ice 32 x 12 pixels round the
## feet, in the owner's colour ("F") with the crossbones' outline ("o") on
## both sides, in a plate's 32 x 16.
const RING := [
	".........oooooooooooooo.........",
	".....ooooFFFFFFFFFFFFFFoooo.....",
	"...ooFFFFFooooooooooooFFFFFoo...",
	"..oFFFFooo............oooFFFFo..",
	".oFFFoo..................ooFFFo.",
	"oFFFo......................oFFFo",
	"oFFFo......................oFFFo",
	".oFFFoo..................ooFFFo.",
	"..oFFFFooo............oooFFFFo..",
	"...ooFFFFFooooooooooooFFFFFoo...",
	".....ooooFFFFFFFFFFFFFFoooo.....",
	".........oooooooooooooo.........",
]

static var _tags := {}             # player -> the tag's 256 bytes (made once)
static var _marks := {}            # Vector2i(slot, variant) -> a ring's / a C's 256 bytes
static var _made := {}             # Vector3i(number, position, health) -> a plate's 256 bytes


## The plates' VRAM tiles (`$FFBE80` + 256 * slot -> VRAM tile `$5F4` + 8 *
## slot) for the values [param plates] (MwRinkState.plates: [number,
## position, health] a slot; plan 34's extended set-ups have fourteen, the
## ones past the original's four in tiles further on, MwRinkDraw.PORT_BANK):
## tile index -> 32 bytes. Plan 34: with the extended set-ups' plates (or
## [param marks]: captains in the original's set-ups) the players' number
## tags, the owners' hollow marks and the captains' C too.
static func ram_tiles(rom: PackedByteArray, plates: Array, marks := false) -> Dictionary:
	var out := {}
	for slot in plates.size():
		var v: Array = plates[slot]
		var key := Vector3i(v[0], v[1], v[2])
		if not _made.has(key):
			if _made.size() > 4096:
				_made.clear()
			_made[key] = tiles(rom, v[0], v[1], v[2])
		var b: PackedByteArray = _made[key]
		for n in 8:
			out[MwRinkDraw.PLATE_TILES + 8 * slot + n] = b.slice(32 * n, 32 * n + 32)
	if plates.size() > 4:
		for player in range(1, MwPlayerColours.PLAYERS + 1):
			var b := tag_tiles(rom, player)
			for n in 8:
				out[MwRinkDraw.PLATE_TILES + 8 * (TAG_SLOT + player - 1) + n] = b.slice(32 * n, 32 * n + 32)
	if plates.size() <= 4 and not marks:
		return out
	for k in range(1, 5):
		for slot: int in [RING_SLOT, CAPTAIN_SLOT]:
			var b := ring_tiles(rom, k) if slot == RING_SLOT else captain_tiles(rom, k)
			for n in 8:
				out[MwRinkDraw.PLATE_TILES + 8 * (slot + k - 1) + n] = b.slice(32 * n, 32 * n + 32)
	return out


## Plan 34: the owners' hollow mark ([constant RING]) for crossbones
## variant [param k] (1-4: the face index of pad k's), a plate's 8 tiles.
static func ring_tiles(rom: PackedByteArray, k: int) -> PackedByteArray:
	var key := Vector2i(RING_SLOT, k)
	if _marks.has(key):
		return _marks[key]
	var face := MwPlayerColours.face_index(rom, k)
	var line := MwPlayerColours.outline_index(rom)
	var b := PackedByteArray()
	b.resize(256)
	for y in RING.size():
		var row: String = RING[y]
		for x in row.length():
			var v := face if row[x] == "F" else (line if row[x] == "o" else 0)
			if v <= 0:
				continue
			var tile := 2 * (x / 8) + y / 8             # column-major, two rows
			var at := 32 * tile + 4 * (y % 8) + (x % 8) / 2
			b[at] = (b[at] & 0x0F) | (v << 4) if x % 2 == 0 else (b[at] & 0xF0) | v
	_marks[key] = b
	return b


## Plan 34: the captain's C (the plates' letter C, font [constant FONT])
## beside their number tag, its outline in crossbones variant [param k]'s
## face index (as [method tag_tiles] colours the digits').
static func captain_tiles(rom: PackedByteArray, k: int) -> PackedByteArray:
	var key := Vector2i(CAPTAIN_SLOT, k)
	if not _marks.has(key):
		_marks[key] = _label(rom, PackedByteArray([rom[LETTERS]]), k)
	return _marks[key]


## Plan 34: player [param player]'s number tag (1-12), a plate's 8 tiles
## (32 x 16, column-major) with the number in the plate's digits (font
## [constant FONT]) in its top row, their outline (the digits' commonest
## colour) in the player's colour: the face index of their crossbones
## (MwPlayerColours.face_index) - pad 1's for players 5-12, whose palette
## line puts their colour there (MwRinkDraw.player_attr).
static func tag_tiles(rom: PackedByteArray, player: int) -> PackedByteArray:
	if not _tags.has(player):
		_tags[player] = _label(rom, str(player).to_ascii_buffer(), player if player <= 4 else 1)
	return _tags[player]


## [param text]'s characters in the plates' font along the top row of a
## plate's 8 tiles, their outline (the commonest colour) in crossbones
## variant [param k]'s face index (MwPlayerColours.face_index).
static func _label(rom: PackedByteArray, text: PackedByteArray, k: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(256)
	for i in text.size():
		_glyph(rom, b, 2 * i, text[i])                   # column i, top row
	var counts := {}
	for v in b:
		for n in [v >> 4, v & 15]:
			if n != 0:
				counts[n] = int(counts.get(n, 0)) + 1
	var outline := 0
	for n: int in counts:
		if outline == 0 or int(counts[n]) > int(counts[outline]):
			outline = n
	var face := MwPlayerColours.face_index(rom, k)
	if outline != 0 and face > 0:
		for i in b.size():
			var hi := b[i] >> 4
			var lo := b[i] & 15
			b[i] = ((face if hi == outline else hi) << 4) | (face if lo == outline else lo)
	return b


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


## [method values]' glyph lookup: a digit's tile bytes -> the digit (made at its first call).
static var _digits := {}
static var _letters := {}


## What plate tiles [param data] (256 bytes) show: [number, position, health], [constant NONE]
## for a part never drawn - [method tiles] backwards, its glyphs read from [param rom] (the
## comparisons read the original's RAM plates with it).
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
