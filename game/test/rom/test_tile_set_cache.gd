extends "res://test/rom/rom_test_base.gd"
## Plan 27: the disk cache (MwCache) and the tile sets' atlases prepared on
## workers and kept between runs - a hit gives what drawing gives, a stale or
## broken file is drawn again, and the glyphs' live cells are brought up to
## date whatever the atlas held.

const ROOT := "user://test-cache"
const BANKS := ["picture_024cfc"]

var _was_enabled: bool
var _was_root: String


func before_each() -> void:
	_was_enabled = MwCache.enabled
	_was_root = MwCache.root
	MwCache.enabled = true
	MwCache.root = ROOT
	MwCache.clear()


func after_each() -> void:
	MwCache.clear()
	MwCache.enabled = _was_enabled
	MwCache.root = _was_root
	RomTileSet.forget()


func _files() -> PackedStringArray:
	var d := DirAccess.open(ROOT)
	return d.get_files() if d else PackedStringArray()


## The atlases' files (the glyphs' tiles have one of their own since the
## owner's polish round: MwGlyphs keeps them, written when first made).
func _atlases() -> Array:
	return Array(_files()).filter(func(f: String) -> bool: return f.begins_with("atlas-"))


func test_a_kept_value_reads_back() -> void:
	var v := {"order": PackedInt32Array([3, 1, 2]), "data": PackedByteArray([9, 8, 7]), "n": 5}
	MwCache.write("item", ["res://src/flow/cache.gd"], v)
	assert_eq(MwCache.read("item", ["res://src/flow/cache.gd"]), v)
	assert_eq(_files().size(), 1, "one file, no leftover part")


func test_other_sources_miss_and_a_new_value_replaces_the_old_file() -> void:
	MwCache.write("item", ["res://src/flow/cache.gd"], 1)
	assert_null(MwCache.read("item", ["res://src/rom/gfx.gd"]), "built from other files: stale")
	MwCache.write("item", ["res://src/rom/gfx.gd"], 2)
	assert_eq(MwCache.read("item", ["res://src/rom/gfx.gd"]), 2)
	assert_eq(_files().size(), 1, "the older file of the name is gone")


func test_off_reads_nothing_and_writes_nothing() -> void:
	MwCache.enabled = false
	MwCache.write("item", [], 1)
	assert_null(MwCache.read("item", []))
	assert_eq(_files().size(), 0)


func test_a_broken_file_reads_as_missing() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var f := FileAccess.open(MwCache.path_of("item", []), FileAccess.WRITE)
	f.store_string("not a cached value")
	f.close()
	assert_null(MwCache.read("item", []))


func test_a_cached_atlas_is_the_drawn_one() -> void:
	if not need_rom():
		return
	var glyphs := MwGlyphs.tiles()
	var drawn := RomTileSet.atlas_of(BANKS, [], glyphs)
	var first := RomTileSet.atlas_cached(BANKS, [], glyphs, MwGlyphs.fixed_hash())
	assert_eq(_atlases().size(), 1, "kept")
	var again := RomTileSet.atlas_cached(BANKS, [], glyphs, MwGlyphs.fixed_hash())
	for a in [first, again]:
		assert_eq(a["order"], drawn["order"])
		assert_eq(a["data"], drawn["data"])
		assert_eq(a["live"], drawn["live"])
	assert_ne(drawn["data"].count(0), drawn["data"].size(), "something drawn")


func test_other_glyph_art_draws_the_atlas_again() -> void:
	if not need_rom():
		return
	var glyphs := MwGlyphs.tiles()
	RomTileSet.atlas_cached(BANKS, [], glyphs, "old art")
	var a := RomTileSet.atlas_cached(BANKS, [], glyphs, MwGlyphs.fixed_hash())
	assert_eq(a["fixed"], MwGlyphs.fixed_hash())
	assert_eq(_atlases().size(), 1)


func test_a_prepared_tile_set_builds_what_drawing_builds() -> void:
	if not need_rom():
		return
	var direct := RomTileSet.new()
	direct.banks = PackedStringArray(BANKS)
	MwCache.enabled = false
	var want := (direct.build().get_source(0) as TileSetAtlasSource).texture.get_image().get_data()
	RomTileSet.forget()
	MwCache.enabled = true
	RomTileSet.prepare(PackedStringArray(BANKS), PackedStringArray())
	var waited := 0
	while RomTileSet.preparing() > 0 and waited < 5000:
		OS.delay_msec(5)
		waited += 5
	assert_eq(RomTileSet.preparing(), 0, "the worker finished")
	var ts := RomTileSet.new()
	ts.banks = PackedStringArray(BANKS)
	var src := ts.build().get_source(0) as TileSetAtlasSource
	assert_eq(src.texture.get_image().get_data(), want)
	assert_ne(ts.atlas_coords(1, 0), Vector2i(-1, -1), "its slots too")
	assert_eq(_atlases().size(), 1, "and the worker kept it on disk")


func test_live_cells_are_redrawn_into_an_older_atlas() -> void:
	if not need_rom():
		return
	var glyphs := MwGlyphs.tiles().duplicate()
	var a := RomTileSet.atlas_of(BANKS, [], glyphs)
	var order: PackedInt32Array = a["order"]
	var i := order.bsearch(MwGlyphs.LIVE_BASE)
	assert_true(MwGlyphs.is_live(order[i]), "the atlas has live cells")
	var tile := PackedByteArray()
	tile.resize(64)
	tile.fill(7)
	glyphs[order[i]] = tile
	var live := MwGlyphs.live_hash_of(glyphs)
	assert_ne(live, a["live"])
	RomTileSet._finish(a, glyphs, live)
	assert_eq(a["live"], live)
	var n := order.size()
	var data: PackedByteArray = a["data"]
	for line in 4:
		var slot := line * n + i
		var px: int = (slot / RomTileSet.COLUMNS) * 8 * int(a["w"]) + (slot % RomTileSet.COLUMNS) * 8
		assert_eq(data[px], line * 16 + 7, "line %d's copy redrawn" % line)


func test_the_fixed_hash_ignores_what_the_live_cells_show() -> void:
	var t := {MwGlyphs.KEY_BASE: PackedByteArray([1]), MwGlyphs.LIVE_BASE: PackedByteArray([2])}
	var other := t.duplicate()
	other[MwGlyphs.LIVE_BASE] = PackedByteArray([3])
	assert_eq(MwGlyphs._hash(t, false), MwGlyphs._hash(other, false))
	assert_ne(MwGlyphs.live_hash_of(t), MwGlyphs.live_hash_of(other))
	other[MwGlyphs.KEY_BASE] = PackedByteArray([4])
	assert_ne(MwGlyphs._hash(t, false), MwGlyphs._hash(other, false))
	assert_false(MwGlyphs.is_live(MwGlyphs.SOLID_BLACK))
	for k in MwGlyphs.PLUS_KEYS.values():
		assert_false(MwGlyphs.is_live(k))
