extends GutTest
## The screen table: every original screen ID has a scene, every scene's
## root is an MwScreen, and every transition seen on the original is allowed.

const SCENES := ["boot", "title", "main_menu", "team_description", "matchup", "rink", "instant_replay",
		"game_stats", "player_stats", "special_plays", "playoffs", "password", "scoreboard", "fight",
		"ref_wasted", "port_menu", "character_select", "online", "keyboard", "create_team", "text_entry",
		"rink_editor"]


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
	var menus := [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 118]
	for id in menus:
		assert_true(MwScreens.PORT.has(id), "port screen %d" % id)
		assert_eq(MwScreens.info(id).scene, "port_menu")
	assert_eq(menus.map(func(id: int) -> String: return MwScreens.entry(id)),
			["main", "options", "bindings", "visuals", "modifiers", "controls", "play_mode", "local_play",
			"continue", "saved_games", "replays"])


func test_the_selection_screens() -> void:
	for id in [MwScreens.CHARACTER_SELECT, MwScreens.CAPTAIN_VOTE, MwScreens.LINEUPS]:
		assert_eq(MwScreens.info(id).scene, "character_select", "plan 34: one scene for the selection steps")
		assert_true(id in MwScreens.exits(MwScreens.CONTROLLER_SELECT), "110 goes on to %d" % id)
		assert_true(3 in MwScreens.exits(id), "and on to the matchup")
		assert_true(MwScreens.CONTROLLER_SELECT in MwScreens.exits(id), "Back: 110")
	assert_eq([MwScreens.entry(111), MwScreens.entry(112), MwScreens.entry(113)], ["characters", "vote", "lineups"])


func test_transitions_seen_on_the_original_are_allowed() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(
			"../compare/fixtures/screen_transitions.json").simplify_path()
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var pairs: Array = doc["transitions"]
	assert_gt(pairs.size(), 20)
	for p in pairs:
		var a := int(p[0])
		var b := int(p[1])
		assert_true(b in MwScreens.exits(a), "%d -> %d seen on the original" % [a, b])


func test_contexts() -> void:
	assert_eq(MwScreens.contexts(4), [MwVerbs.Context.GAMEPLAY, MwVerbs.Context.PAUSE], "play, and its pause menu")
	assert_eq(MwScreens.contexts(14), [MwVerbs.Context.SCOREBOARD, MwVerbs.Context.ZAMBONI])
	assert_eq(MwScreens.contexts(18), [MwVerbs.Context.FIGHT], "the fight's Start and the card's buttons")
	assert_eq(MwScreens.contexts(7), [MwVerbs.Context.REPLAY])
	assert_eq(MwScreens.contexts(8), [MwVerbs.Context.STATS])
	assert_eq(MwScreens.contexts(100), [MwVerbs.Context.MENU])
	for t in [MwScreens.TABLE, MwScreens.PORT, MwScreens.EXTRA]:
		for id in t:
			for ctx in t[id]["contexts"]:
				assert_true(MwVerbs.PAD_TO_VERB.has(ctx), "screen %s: a known context" % str(id))


func test_project_boots_through_the_router() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), MwScreens.scene_path(MwScreens.BOOT))
	assert_eq(ProjectSettings.get_setting("autoload/Router"), "*res://src/flow/router_service.gd")


func test_create_a_team_screens() -> void:
	assert_eq([MwScreens.info(130).scene, MwScreens.info(131).scene, MwScreens.info(132).scene,
			MwScreens.info(138).scene], ["create_team", "text_entry", "create_team", "rink_editor"], "plan 38")
	assert_true(MwScreens.CREATE_A_TEAM in MwScreens.exits(MwScreens.FRONT_MENU))
	assert_eq([MwScreens.entry(130), MwScreens.entry(132)], ["list", "team"])
