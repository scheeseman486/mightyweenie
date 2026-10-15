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
	var script_player := MwScriptPlayer.new(MwInputScript.parse(text, "t"))
	script_player.screen_entered(1, 0)
	script_player.tick_start(1)
	return script_player


func test_scripted_pads_become_verbs_per_context() -> void:
	var src := MwScriptedInput.new(_scripted("@screen 1 +1 P1 A+START\n@screen 1 +1 P3 C+UP\n@screen 1 +50 END"))
	var menu := src.sample([MwVerbs.Context.SETUP])
	assert_eq(menu.keys().size(), 7, "shared and per-player menu verbs (A and C: skip)")
	for a in ["ui_skip", "ui_accept", "ui_up", "p1_ui_skip", "p1_ui_accept", "p3_ui_skip", "p3_ui_up"]:
		assert_true(menu.has(a), a)
	var board := src.sample([MwVerbs.Context.SCOREBOARD])
	for a in ["ui_view_stats", "ui_accept", "ui_view_replay", "p3_ui_view_replay"]:
		assert_true(board.has(a), a)
	assert_false(board.has("ui_up"), "the scoreboard reads no D-pad")
	var game := src.sample([MwVerbs.Context.GAMEPLAY])
	for a in ["p1_punch", "p1_dive", "p1_special_play", "p1_pause", "p3_wrist_shot", "p3_slap_shot",
			"p3_check", "p3_move_up"]:
		assert_true(game.has(a), a)
	var fight := src.sample([MwVerbs.Context.FIGHT])
	assert_eq(fight.keys(), ["p1_fight_block", "p1_fight_pause", "p3_fight_punch"], "up does nothing in a fight")
	var both := src.sample([MwVerbs.Context.SCOREBOARD, MwVerbs.Context.ZAMBONI])
	assert_true(both.has("p3_zamboni_whip") and both.has("ui_view_replay"))


func test_pad_bytes_from_verbs_and_back_as_start() -> void:
	var ctx := [MwVerbs.Context.STATS]
	var input := MwInputFrame.make({"p2_ui_stats_switch": true, "ui_stats_switch": true}, {})
	assert_eq(input.pad_bits(2, ctx), 0x40, "A")
	assert_eq(input.pad_bits(1, ctx), 0, "player 2's press")
	input = MwInputFrame.make({"p1_ui_back": true, "ui_back": true}, {})
	assert_eq(input.pad_bits(1, ctx), 0x80, "Menu Back is Start where Start leaves")
	assert_eq(input.pad_bits(1, [MwVerbs.Context.SETUP]), 0, "not in the game setup (Back goes up a menu)")
	assert_eq(input.pad_bits(1, [MwVerbs.Context.PLAYOFFS]), 0, "nor the playoffs (the bracket's Back)")
	input = MwInputFrame.make({"p1_ui_next_page": true}, {})
	assert_eq(input.pad_bits(1, [MwVerbs.Context.TEAM_INFO]), 0x70, "a verb on A / B / C sets all three")
	input = MwInputFrame.make({"p1_ui_skip": true}, {})
	assert_eq(input.pad_bits(1, [MwVerbs.Context.STATS]), 0, "another screen's verb means nothing here")


## Plan 40 (I2): player 0 is the shared menu verbs (an online game's
## options: the host's P1's) - each Genesis button of the game setup's
## context from its unprefixed action, as the main menu's own copy did; and
## any_pad_bits ORs players 1-n.
func test_the_shared_verbs_pad_byte_and_any_pad() -> void:
	var ctx := [MwVerbs.Context.SETUP]
	var table: Dictionary = MwVerbs.PAD_TO_VERB[MwVerbs.Context.SETUP]
	for button in table:
		if not MwVerbs.BITS.has(button):
			continue
		var frame := MwInputFrame.make({str(table[button]): true}, {})
		var want := 0                         # (every button the verb is on: A, B and C skip alike)
		for b in table:
			if MwVerbs.BITS.has(b) and table[b] == table[button]:
				want |= MwVerbs.BITS[b]
		assert_eq(frame.pad_bits(0, ctx), want, button)
		assert_eq(frame.pad_bits(1, ctx), 0, button + ": no player's")
	var input := MwInputFrame.make({"p1_ui_up": true, "p3_ui_accept": true}, {})
	assert_eq(input.any_pad_bits(4, ctx), MwVerbs.BITS["UP"] | MwVerbs.BITS["START"])
	assert_eq(input.any_pad_bits(2, ctx), MwVerbs.BITS["UP"], "players 1-2 only")


## Plan 40 (I3): one per-player name and its parse.
func test_player_names_round_trip() -> void:
	assert_eq(MwVerbs.player_key(3, "pass"), "p3_pass")
	assert_eq(MwVerbs.parse_action("p3_pass"), [3, "pass"])
	assert_eq(MwVerbs.parse_action("p12_ui_left"), [12, "ui_left"])
	assert_eq(MwVerbs.parse_action("ui_accept"), [-1, "ui_accept"], "shared")
	assert_eq(MwVerbs.parse_action("pause"), [-1, "pause"], "not a player's")
	assert_eq(MwVerbs.parse_action("px_pass"), [-1, "px_pass"])
	for p in [1, 7, 12]:
		for v in ["move_up", "ui_back", "slap_shot"]:
			assert_eq(MwVerbs.parse_action(MwVerbs.player_key(p, v)), [p, v])
