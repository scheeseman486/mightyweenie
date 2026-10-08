extends GutTest
## The screen table: every original screen ID has a scene, every scene's
## root is an MwScreen, and every transition seen on the original is allowed.

const SCENES := ["boot", "title", "main_menu", "team_description", "matchup", "rink", "instant_replay",
		"game_stats", "player_stats", "special_plays", "playoffs", "password", "scoreboard", "fight",
		"ref_wasted", "port_menu"]


func test_all_twenty_ids_and_boot() -> void:
	for id in range(-1, 20):
		assert_true(MwScreens.has(id), "screen %d in the table" % id)
	assert_eq(MwScreens.TABLE.size(), 21)


func test_scenes_are_the_approved_ones() -> void:
	var got := Array(MwScreens.scenes())
	got.sort()
	var want := SCENES.duplicate()
	want.sort()
	assert_eq(got, want)


func test_every_scene_instantiates_as_a_screen() -> void:
	for id in MwScreens.TABLE.keys() + MwScreens.PORT.keys() + MwScreens.EXTRA.keys():
		var path := MwScreens.scene_path(id)
		assert_true(ResourceLoader.exists(path), path)
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate()
		assert_true(node is MwScreen, "%s root is an MwScreen" % path)
		node.free()


func test_entry_variants() -> void:
	assert_eq([MwScreens.entry(4), MwScreens.entry(5), MwScreens.entry(6)], ["period_start", "faceoff", "continue"])
	for id in range(12, 18):
		assert_eq(MwScreens.info(id).scene, "scoreboard")
	assert_eq(MwScreens.scene_path(9), "res://scenes/player_stats/player_stats.tscn")


func test_exits_are_screen_ids() -> void:
	for id in MwScreens.TABLE.keys() + MwScreens.PORT.keys():
		for x in MwScreens.exits(id):
			assert_true((MwScreens.TABLE.has(x) or MwScreens.PORT.has(x)) and x >= 0, "exit %s of %d" % [str(x), id])


func test_the_ports_screens() -> void:
	assert_eq(MwScreens.PORT.keys(), [100, 101, 102])
	for id in MwScreens.PORT:
		assert_eq(MwScreens.info(id).scene, "port_menu")
	assert_eq([MwScreens.entry(100), MwScreens.entry(101), MwScreens.entry(102)], ["main", "options", "bindings"])


func test_transitions_seen_on_the_original_are_allowed() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../compare/fixtures/screen_transitions.json").simplify_path()
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var pairs: Array = doc["transitions"]
	assert_gt(pairs.size(), 20)
	for p in pairs:
		var a := int(p[0])
		var b := int(p[1])
		assert_true(b in MwScreens.exits(a), "%d -> %d seen on the original" % [a, b])


func test_contexts() -> void:
	assert_eq(MwScreens.contexts(4), [MwVerbs.Context.GAMEPLAY])
	assert_eq(MwScreens.contexts(14), [MwVerbs.Context.MENU, MwVerbs.Context.ZAMBONI])
	assert_eq(MwScreens.contexts(18), [MwVerbs.Context.FIGHT, MwVerbs.Context.MENU], "the fight's Start and the card's buttons")
	assert_eq(MwScreens.contexts(7), [MwVerbs.Context.REPLAY])


func test_project_boots_through_the_router() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), MwScreens.scene_path(MwScreens.BOOT))
	assert_eq(ProjectSettings.get_setting("autoload/Router"), "*res://src/flow/router_service.gd")
