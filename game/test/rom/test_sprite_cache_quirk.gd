extends "res://test/rom/rom_test_base.gd"
## The original's sprite tile cache bug, faked (MwSpriteCacheQuirk): the
## three pieces and their tiles, the animations that make them break, and
## the sprite layer building them.

## [first tile, size byte, the frame of the smaller piece drawn first, the
## frame of the bigger one, the animation playing both].
const CASES := [
	[0xDF29, 0xD, 0x4CDFA, 0x4CE08, 0x4CEB2],
	[0x89AF, 0xC, 0x3E026, 0x3E040, 0x3E110],
	[0x9EDD, 0xE, 0x43CF6, 0x43D1E, 0x43D2E],
]


func test_other_pieces_show_their_own_tiles() -> void:
	assert_eq(MwSpriteCacheQuirk.tile(0xDEBB, 0xB, 5), 0xDEBB + 5)
	assert_eq(MwSpriteCacheQuirk.tile(0xDF29, 0x5, 3), 0xDF2C, "the whip's 2x2 piece (frame 0) is fine")
	assert_eq(MwSpriteCacheQuirk.tile(0x89AF, 0x0, 0), 0x89AF, "the 1x1 corner is fine")


func test_the_broken_pieces_keep_the_slots_tiles_then_others() -> void:
	# the whip's 4x2: its left half (4 tiles: the 2x2's slot), then another sprite's
	assert_eq(MwSpriteCacheQuirk.tile(0xDF29, 0xD, 3), 0xDF2C)
	assert_eq(MwSpriteCacheQuirk.tile(0xDF29, 0xD, 4), 0xDBA3)
	assert_eq(MwSpriteCacheQuirk.tile(0xDF29, 0xD, 7), 0xDBA6)
	# the portrait's bottom row: its first tile, then nothing, then others'
	assert_eq(MwSpriteCacheQuirk.tile(0x89AF, 0xC, 0), 0x89AF)
	assert_eq(MwSpriteCacheQuirk.tile(0x89AF, 0xC, 1), 0)
	assert_eq(MwSpriteCacheQuirk.tile(0x89AF, 0xC, 2), 0x8927)
	# the fall's 4x3: one tile of its own
	assert_eq(MwSpriteCacheQuirk.tile(0x9EDD, 0xE, 0), 0x9EDD)
	assert_ne(MwSpriteCacheQuirk.tile(0x9EDD, 0xE, 1), 0x9EDE)
	for q in MwSpriteCacheQuirk.PIECES:
		var size: int = q.y
		var n := (((size >> 2) & 3) + 1) * ((size & 3) + 1)
		var e: Array = MwSpriteCacheQuirk.PIECES[q]
		assert_eq(int(e[0]) + (e[1] as Array).size(), n, "every tile of $%04X's piece accounted for" % q.x)


## The table's pieces are what the ROM's animations draw: the smaller piece
## in a frame shown before the bigger one's, with the same first tile.
func test_the_rom_breaks_these_pieces() -> void:
	if not need_rom():
		return
	for c in CASES:
		var small := _piece(int(c[2]), int(c[0]))
		var big := _piece(int(c[3]), int(c[0]), int(c[1]))
		assert_true(small >= 0, "frame $%05X has a piece at $%04X" % [c[2], c[0]])
		assert_true(big >= 0, "frame $%05X has the %X piece at $%04X" % [c[3], c[1], c[0]])
		var cached: int = MwSpriteCacheQuirk.PIECES[Vector2i(int(c[0]), int(c[1]))][0]
		assert_eq((((small >> 2) & 3) + 1) * ((small & 3) + 1), cached, "the slot is the smaller piece's")
		var order := _frames(int(c[4]))
		assert_true(order.find(int(c[2])) >= 0 and order.find(int(c[2])) < order.find(int(c[3])),
				"the smaller piece's frame plays first in $%05X" % c[4])


## The sprite layer builds the whip's broken piece from those tiles.
func test_the_sprite_layer_builds_the_broken_piece() -> void:
	if not need_rom():
		return
	var layer := MwSpriteLayer.new()
	add_child_autofree(layer)
	layer._texture(0xDF29, 0xD, 0)
	var px: PackedByteArray = layer._pixel_cache[Vector3i(0xDF29, 0xD, 0)]
	# column 2, row 0 (8 px wide tiles in a 32 x 16 texture): tile $DBA3
	var want := MwGfx.tile_indices(rom, 0xDBA3 << 5)
	var ok := true
	for y in 8:
		for x in 8:
			if px[y * 32 + 16 + x] != want[y * 8 + x]:
				ok = false
	assert_true(ok, "the piece's third column shows tile $DBA3")


## The size byte of the piece at [param first] in frame [param frame] (the
## given size if any), -1 if none.
func _piece(frame: int, first: int, size := -1) -> int:
	for i in MwGfx.u16(rom, frame):
		var a := frame + 2 + 6 * i
		if MwGfx.u16(rom, a + 4) == first and (size < 0 or rom[a + 2] == size):
			return rom[a + 2]
	return -1


## The frame addresses of every variant of animation [param anim] in order.
func _frames(anim: int) -> Array:
	var count := rom[anim + 3]
	var frames := MwGfx.u32(rom, anim + 4)
	var out := []
	var w := MwGfx.u16(rom, anim + 8)
	var end := anim + (w >> 2)
	var v := anim + 8
	while v < end:
		var lst := anim + (MwGfx.u16(rom, v) >> 2)
		for i in count:
			out.append(frames + MwGfx.u16(rom, lst + 2 * i))
		v += 2
	return out
