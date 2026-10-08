extends "res://test/rom/rom_test_base.gd"
## The rink's draw pass (MwRinkDraw) against the original
## (compare/fixtures/rink_draw.json: passes recorded in BlastEm, picked to
## show every kind of sprite the recordings have; mw_harness rink-fixtures):
## the same draw_frame and add_sprite_piece calls, the same sprite list and
## the same info plates. Plus the list rules on their own.

var _passes: Array


func before_all() -> void:
	super.before_all()
	_passes = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_draw.json")))["passes"]


func test_recorded_passes_draw_the_same() -> void:
	if not need_rom():
		return
	assert_gt(_passes.size(), 20)
	for p in _passes:
		var m := MwRinkDrawCheck.compare(rom, p)
		assert_eq(m.size(), 0, "%s: %s" % [p["name"], "; ".join(m)])


func test_the_sample_covers_every_kind_of_sprite() -> void:
	if not need_rom():
		return
	var frames := {}
	for p in _passes:
		for c in p["calls"]:
			frames[int(c[4])] = true
	for f in [MwRinkDraw.SHADOW, MwRinkDraw.PUCK_SHADOW, MwRinkDraw.POSSESSION, MwRinkDraw.STAND_FRAME,
			MwRinkDraw.BORDER, MwRinkDraw.SMALL_BORDER, MwRinkDraw.PLATES + 24]:
		assert_true(frames.has(f), "frame %X drawn somewhere" % f)


## An empty draw pass to add pieces to.
func _draw() -> MwRinkDraw:
	var d := MwRinkDraw.new(rom)
	d.state = MwRinkState.new()
	d._entries = [[0, 0, 0, 0, 0, 0]]
	d._links = PackedInt32Array([0])
	return d


func test_equal_depths_put_the_later_piece_in_front() -> void:
	if not need_rom():
		return
	var d := _draw()
	var piece := MwRinkDraw.SHADOW + 2
	d.add_piece(0x100, 0x100, 5, 0, piece)
	d.add_piece(0x110, 0x100, 5, 0, piece)
	d.add_piece(0x120, 0x100, 9, 0, piece)
	d.add_piece(0x130, 0x100, 1, 0, piece)
	var xs := d.sprites().map(func(e: Array) -> int: return int(e[0]) - MwGfx.s8(rom, piece))
	assert_eq(xs, [0x120, 0x110, 0x100, 0x130])


func test_pieces_off_screen_are_dropped_and_79_kept() -> void:
	if not need_rom():
		return
	var d := _draw()
	var piece := MwRinkDraw.SHADOW + 2
	var px := MwGfx.s8(rom, piece)
	d.add_piece(0x60 - px - 1, 0x100, 1, 0, piece)     # corner 33 px off the left
	d.add_piece(0x60 - px, 0x100, 1, 0, piece)         # 32 px off: kept
	d.add_piece(0x1C0 - px, 0x100, 1, 0, piece)        # right edge: dropped
	assert_eq(d.sprites().size(), 1)
	for i in 100:
		d.add_piece(0x100, 0x100, i, 0, piece)
	assert_eq(d.sprites().size(), MwRinkDraw.MAX_COUNT - 1)


func test_projection() -> void:
	var d := MwRinkDraw.new(PackedByteArray())
	d.state = MwRinkState.new()
	assert_eq(d.project(0, 0, 0), Vector3i(256, 461, 461))
	assert_eq(d.project(-58, -105, 10), Vector3i(198, 346, 356))
	d.state.camera.shown = Vector2i(0, 274)
	assert_eq(d.to_sprite(d.project(-58, -105, 0)), Vector3i(326, 210, 356))


func test_plate_tiles() -> void:
	if not need_rom():
		return
	var blank := MwPlate.tiles(rom, 0xFF, 0xFF, 0xFF)
	assert_eq(blank, PackedByteArray(range(256).map(func(_i: int) -> int: return 0)))
	var p := MwPlate.tiles(rom, 42, 5, 12)
	# the bar: 12 yellow pixels then red on rows 1-5 of the bottom tiles
	assert_eq(p.slice(32 + 4, 32 + 8), PackedByteArray([0x11, 0x11, 0x11, 0x11]))
	assert_eq(p.slice(96 + 4, 96 + 8), PackedByteArray([0x11, 0x11, 0x77, 0x77]))
	assert_eq(p.slice(160 + 4, 160 + 8), PackedByteArray([0x77, 0x77, 0x77, 0x77]))
	assert_eq(p.slice(32, 36), PackedByteArray([0, 0, 0, 0]), "row 0 untouched")
	assert_ne(p.slice(0, 32), blank.slice(0, 32), "tens digit")
	assert_eq(p.slice(128, 160), blank.slice(0, 32), "column 2 of the top row stays empty")
