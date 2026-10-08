extends GutTest
## Per-pass input: newly pressed once, then held; scripted pads -> verbs.


func test_pressed_only_on_the_first_pass() -> void:
	var f1 := MwInputFrame.make({"p1_pass": true}, {})
	assert_true(f1.is_pressed("p1_pass") and f1.is_held("p1_pass"))
	assert_true(f1.player_pressed(1, "pass"))
	var f2 := MwInputFrame.make({"p1_pass": true}, f1.held)
	assert_false(f2.is_pressed("p1_pass"))
	assert_true(f2.player_held(1, "pass"))
	var f3 := MwInputFrame.make({}, f2.held)
	assert_false(f3.is_held("p1_pass"))


func _scripted(text: String) -> MwScriptPlayer:
	var p := MwScriptPlayer.new(MwInputScript.parse(text, "t"))
	p.screen_entered(1, 0)
	p.tick_start(1)
	return p


func test_scripted_pads_become_verbs_per_context() -> void:
	var src := MwScriptedInput.new(_scripted("@screen 1 +1 P1 A+START\n@screen 1 +1 P3 C+UP\n@screen 1 +50 END"))
	var menu := src.sample([MwVerbs.Context.MENU])
	assert_eq(menu.keys().size(), 8, "shared and per-player menu verbs")
	for a in ["ui_option_a", "ui_accept", "ui_option_c", "ui_up", "p1_ui_option_a", "p1_ui_accept",
			"p3_ui_option_c", "p3_ui_up"]:
		assert_true(menu.has(a), a)
	var game := src.sample([MwVerbs.Context.GAMEPLAY])
	for a in ["p1_punch", "p1_dive", "p1_special_play", "p1_pause", "p3_wrist_shot", "p3_slap_shot",
			"p3_check", "p3_move_up"]:
		assert_true(game.has(a), a)
	var fight := src.sample([MwVerbs.Context.FIGHT])
	assert_eq(fight.keys(), ["p1_fight_block", "p3_fight_punch"], "up does nothing in a fight")
	var both := src.sample([MwVerbs.Context.MENU, MwVerbs.Context.ZAMBONI])
	assert_true(both.has("p3_zamboni_whip") and both.has("ui_up"))
