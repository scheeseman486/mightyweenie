extends GutTest
## Plan 40 (M3): one "keep the selection in view" (MwScrollArrows.follow) -
## the port menus' lists and bindings, CREATE-A-TEAM's list, the text
## entry's box, the pause menu's PLAYERS.


func test_follow() -> void:
	assert_eq(MwScrollArrows.follow(0, 3, 5), 0, "in view: stays")
	assert_eq(MwScrollArrows.follow(0, 7, 5), 3, "below: the selection the last shown")
	assert_eq(MwScrollArrows.follow(6, 2, 5), 2, "above: the first shown")
	assert_eq(MwScrollArrows.follow(4, 4, 5), 4)
	assert_eq(MwScrollArrows.follow(9, 9, 5, 8), 3, "never past the list's end")
	assert_eq(MwScrollArrows.follow(0, 1, 5, 3), 0, "a short list from its top")
	for sel in 12:
		var off := MwScrollArrows.follow(0, sel, 4, 12)
		assert_eq(off, clampi(sel - 3, 0, 8), "the pause menu's rule (selection kept last)")
