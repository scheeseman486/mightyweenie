extends "res://test/rom/rom_test_base.gd"
## Plan 27: the start's background loading (MwPreloader) - the screens'
## scenes in reach order, kept, and their tile sets' atlases prepared.


func after_each() -> void:
	RomTileSet.forget()


func test_the_title_comes_first_and_every_screen_is_there_once() -> void:
	var order := MwPreloader.screen_order(0)
	assert_eq(order[0], MwScreens.scene_path(0))
	var seen := {}
	for path in order:
		assert_false(seen.has(path), "%s once" % path)
		seen[path] = true
		assert_true(ResourceLoader.exists(path), path)
	for text in MwScreens.scenes():
		if text == "boot":
			continue
		assert_true(seen.has("res://scenes/%s/%s.tscn" % [text, text]), text)
	assert_lt(order.find(MwScreens.scene_path(MwScreens.FRONT_MENU)), order.find(MwScreens.scene_path(4)),
			"the front menu before the rink: it's nearer the title")


func test_a_scenes_tile_sets_are_found() -> void:
	var sets := MwPreloader.tile_sets_of(load(MwScreens.scene_path(0)) as PackedScene)
	assert_gt(sets.size(), 0)
	for ts in sets:
		assert_gt(ts.banks.size() + ts.fonts.size(), 0, "a tile set with tiles")


func test_scenes_load_and_their_atlases_are_prepared() -> void:
	if not need_rom():
		return
	var preloader := MwPreloader.new()
	add_child_autofree(preloader)
	var first := MwScreens.scene_path(0)
	var rest := MwScreens.scene_path(1)
	preloader.start(PackedStringArray([first]), PackedStringArray([rest]))
	await wait_for_signal(preloader.finished, 20)
	assert_true(preloader.done(), "finished")
	assert_true(preloader.scenes.has(first) and preloader.scenes.has(rest), "both scenes kept")
	assert_eq(RomTileSet.preparing(), 0)
	for ts in MwPreloader.tile_sets_of(preloader.scenes[first]):
		assert_true(RomTileSet._prepared.has(RomTileSet.key_of(ts.banks, ts.fonts)),
				"prepared: %s" % ",".join(ts.banks))
