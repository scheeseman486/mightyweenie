extends "res://test/rom/rom_test_base.gd"
## ROM-backed resources and nodes: they fill themselves from the ROM, and a
## saved scene keeps only their references (no tiles, cells, colours or
## frames).


func _rink_layer() -> RomTileMapLayer:
	var layer := RomTileMapLayer.new()
	var ts := RomTileSet.new()
	ts.banks = PackedStringArray(["picture_024cfc"])
	layer.tiles = ts
	layer.palette = MwScreenPalettes.palette(4, "", 22, 5, 22)
	layer.map = "picture_024cfc"
	return layer


func test_palette_texture_maps_indices() -> void:
	if not need_rom():
		return
	var pal := MwScreenPalettes.palette(4)
	var words := pal.colours()
	assert_eq(words.size(), 64)
	var img := pal.texture().get_image()
	assert_eq(img.get_size(), Vector2i(64, 1))
	for i in 64:
		var c := img.get_pixel(i, 0)
		if i % 16 == 0:
			assert_eq(c.a, 0.0, "colour 0 of line %d transparent" % (i / 16))
		else:
			assert_eq(c.to_rgba32(), MwGfx.color(words[i]).to_rgba32(), "colour %d" % i)


## Owner, 2026-10-13 (music dropouts after scoring): the rink sets its
## palette's recipe at once - its users told once, and not at all when the
## match's rink comes again with the same one.
func test_a_recipe_set_at_once_tells_once_and_not_when_unchanged() -> void:
	if not need_rom():
		return
	var pal := MwScreenPalettes.palette(4)
	var told := [0]
	pal.changed.connect(func() -> void: told[0] += 1)
	var steps := pal.steps
	assert_true(pal.set_recipe(5, 3, 7, 3, steps), "changed")
	assert_eq(told[0], 1, "told once for five fields")
	assert_eq([pal.screen, pal.team_a, pal.team_b, pal.stadium], [5, 3, 7, 3])
	var words := pal.colours()
	assert_eq(words, RomPalette.make(5, steps, 3, 3, 7).colours(), "built as the fields one by one would")
	assert_false(pal.set_recipe(5, 3, 7, 3, steps.duplicate()), "the same recipe")
	assert_eq(told[0], 1, "not told again")
	assert_eq(pal.colours(), words, "nor built again")
	assert_true(pal.set_recipe(5, 3, 8, 3, steps))
	assert_eq(told[0], 2)


func test_the_darker_step() -> void:
	assert_eq(RomPalette.darker(0x0CE, 2), 0x08A, "yellow (r7 g6 b0) two levels darker: r5 g4 b0")
	assert_eq(RomPalette.darker(0x222, 2), 0x000, "never below black")
	assert_eq(RomPalette.darker(0xEEE, 0), 0xEEE)
	if not need_rom():
		return
	var pal := MwScreenPalettes.palette(4)
	var dark := pal.duplicate() as RomPalette
	dark.steps = pal.steps + PackedStringArray(["darker 21 2"])
	var a := pal.colours()
	var b := dark.colours()
	for i in 64:
		assert_eq(b[i], RomPalette.darker(a[i], 2) if i == 21 else a[i], "colour %d" % i)


func test_tile_set_has_a_copy_per_line() -> void:
	if not need_rom():
		return
	var ts := RomTileSet.new()
	ts.banks = PackedStringArray(["picture_024cfc"])
	var tile_set := ts.build()
	var src := tile_set.get_source(0) as TileSetAtlasSource
	var n := 990 + MwGlyphs.tiles().size()
	var atlas := src.texture.get_image()
	assert_eq(atlas.get_height(), ceili(4.0 * n / RomTileSet.COLUMNS) * 8,
			"room for the bank's and the glyphs' (plan 23) in 4 lines")
	assert_eq(atlas.get_format(), Image.FORMAT_R8)
	# VRAM tile 1 = the bank's first tile; line 2 copy has values 32-47 or 0
	var made := src.get_tiles_count()
	var c := ts.atlas_coords(1, 2)
	assert_true(src.has_tile(c), "its tile made when asked for (plan 27)")
	assert_lte(src.get_tiles_count(), made + 1, "only that one")
	assert_lt(src.get_tiles_count(), 4 * n, "not all of them")
	var seen := {}
	for y in 8:
		for x in 8:
			seen[atlas.get_pixel(c.x * 8 + x, c.y * 8 + y).r8] = true
	for v in seen:
		assert_true(v == 0 or (v >= 33 and v <= 47), "value %d" % v)
	assert_eq(ts.atlas_coords(5000, 0), Vector2i(-1, -1))


func test_layer_fills_cells_from_the_map() -> void:
	if not need_rom():
		return
	var layer := _rink_layer()
	layer.rebuild()
	assert_eq(layer.get_used_cells().size(), 64 * 113, "every cell of the rink map")
	assert_true(layer.material is ShaderMaterial)
	# cell (0, 0) shows the map's first word
	var word := MwGfx.u16(rom, int(MwRom.entry("picture_024cfc")["map"]))
	var want := layer.tiles.atlas_coords(word & 0x7FF, (word >> 13) & 3)
	assert_eq(layer.get_cell_atlas_coords(Vector2i.ZERO), want)
	layer.free()


func test_layer_region_and_priority() -> void:
	if not need_rom():
		return
	var layer := _rink_layer()
	layer.region = Rect2i(0, 41, 64, 23)
	layer.at = Vector2i(0, 9)
	layer.rebuild()
	assert_eq(layer.get_used_rect(), Rect2i(0, 9, 64, 23))
	layer.priority = 2
	layer.rebuild()
	var high := layer.get_used_cells().size()
	layer.priority = 1
	layer.rebuild()
	assert_eq(high + layer.get_used_cells().size(), 64 * 23)
	layer.free()


func test_sprite_builds_frames() -> void:
	if not need_rom():
		return
	var sprite := RomSprite.new()
	sprite.palette = MwScreenPalettes.palette(4)
	sprite.anim = "anim_04ceb2"
	sprite.rebuild()
	var an := MwGfx.animation(rom, 0x4CEB2)
	assert_eq(sprite.sprite_frames.get_animation_names().size(), an["variants"].size())
	assert_eq(sprite.sprite_frames.get_frame_count("v0"), an["count"])
	assert_almost_eq(sprite.sprite_frames.get_animation_speed("v0"), MwGfx.anim_fps(an), 0.001)
	var tex := sprite.sprite_frames.get_frame_texture("v0", 0)
	assert_eq(tex.get_image().get_format(), Image.FORMAT_R8)
	sprite.free()


func test_saved_scene_keeps_references_only() -> void:
	if not need_rom():
		return
	var root := Node2D.new()
	var bg := RomBackdrop.new()
	bg.palette = MwScreenPalettes.palette(4)
	root.add_child(bg)
	bg.owner = root
	var layer := _rink_layer()
	root.add_child(layer)
	layer.owner = root
	layer.rebuild()
	var sprite := RomSprite.new()
	sprite.palette = MwScreenPalettes.palette(4)
	sprite.anim = "anim_04ceb2"
	root.add_child(sprite)
	sprite.owner = root
	sprite.rebuild()
	assert_gt(layer.get_used_cells().size(), 0)
	var scene := PackedScene.new()
	assert_eq(scene.pack(root), OK)
	var path := "user://test_rom_nodes.tscn"
	assert_eq(ResourceSaver.save(scene, path), OK)
	var text := FileAccess.get_file_as_string(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	root.free()
	for forbidden in ["tile_map_data", "PackedByteArray", "Image", "SpriteFrames", "ImageTexture",
			"ShaderMaterial", "TileSet", "color ="]:
		assert_false(text.contains(forbidden), "saved scene contains '%s'" % forbidden)
	assert_string_contains(text, "picture_024cfc")
	assert_string_contains(text, "anim_04ceb2")
	assert_lt(text.length(), 4000)
