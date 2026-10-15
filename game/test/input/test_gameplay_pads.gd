extends GutTest
## Gameplay verbs into the original's pad bytes (MwGameplayPads): a
## button's verbs pressed together press the button; a verb on its own is
## a direct meaning; held verbs hold the button.

func _frame(held: Dictionary, before := {}) -> MwInputFrame:
	return MwInputFrame.make(held, before)


func test_all_of_a_buttons_verbs_press_the_button() -> void:
	var all := {"p1_wrist_shot": true, "p1_slap_shot": true, "p1_check": true, "p1_move_up": true}
	var r := MwGameplayPads.read(_frame(all), 1)
	assert_eq(r["held"], 0x21, "C + up held")
	assert_eq(r["new"], 0x21, "newly pressed")
	assert_eq(r["direct"], [], "no direct meaning")
	r = MwGameplayPads.read(_frame(all, all), 1)
	assert_eq(r["new"], 0, "still held: not new")
	assert_eq(r["held"], 0x21)


func test_a_verb_alone_is_a_direct_meaning() -> void:
	var r := MwGameplayPads.read(_frame({"p2_slap_shot": true}), 2)
	assert_eq(r["new"], 0, "the button is not pressed")
	assert_eq(r["held"], 0x20, "but held (one-timers, aims)")
	assert_eq(r["direct"], ["slap_shot"])
	r = MwGameplayPads.read(_frame({"p2_slap_shot": true}), 1)
	assert_eq(r["held"], 0, "another player's verb")


func test_pause_is_start() -> void:
	var r := MwGameplayPads.read(_frame({"p3_pause": true}), 3)
	assert_eq(r["new"], 0x80)


## Plan 42 (speed): every pad read in one go (MwGameplayPads.read_all, the
## frame's actions split by player once) is each pad read alone - random
## frames of every player's gameplay verbs, menu verbs, local verbs,
## RECLAIM, sticks and shot heights.
func test_reading_every_pad_at_once_is_reading_each() -> void:
	var verbs: Array = ["move_up", "move_down", "move_left", "move_right", "pause", MwVerbs.RECLAIM]
	for b in MwVerbs.BUTTON_VERBS:
		verbs.append_array(MwVerbs.BUTTON_VERBS[b])
	var actions := []
	for p in range(1, 13):
		for v in verbs:
			actions.append(MwVerbs.action(p, v))
		actions.append(MwVerbs.menu_action(p, "ui_left"))
	actions.append_array(["ui_accept", "ui_up"])
	actions.append_array(MwVerbs.local_verbs())
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 600:
		# (half the frames with presses rare: most pads read the quick way, plan 42)
		var press_rate := 0.5 if i % 2 == 0 else 0.03
		var input := MwInputFrame.new()
		for k in rng.randi_range(0, 40):
			var a: String = actions[rng.randi() % actions.size()]
			if rng.randf() < 0.6:
				input.held[a] = true
			if rng.randf() < press_rate:
				input.pressed[a] = true
		if rng.randf() < 0.3:
			input.sticks = []
			for p in 12:
				input.sticks.append(Vector2i(rng.randi_range(-256, 256), rng.randi_range(-256, 256)))
		if rng.randf() < 0.3:
			input.heights = []
			for p in 12:
				input.heights.append(rng.randi_range(-1, 2))
		var all := MwGameplayPads.read_all(input, 12)
		for p in 12:
			var one := MwGameplayPads.read(input, p + 1)
			if str(all[p]) != str(one):
				assert_eq(str(all[p]), str(one), "frame %d, pad %d" % [i, p + 1])
				return
	assert_eq(MwGameplayPads.read_all(null, 2), [MwGameplayPads.read(null, 1), MwGameplayPads.read(null, 2)])
