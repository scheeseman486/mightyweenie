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
