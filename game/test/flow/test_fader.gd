extends GutTest
## Fades take exactly their length in ticks (32 for the original's $20) and
## start from where the screen is.


func test_fade_out_and_in_take_32_ticks() -> void:
	var f := MwScreenFader.new()
	f.fade_out()
	for i in 31:
		f.step()
		assert_true(f.busy())
	assert_almost_eq(f.coverage(), 31.0 / 32.0, 0.0001)
	f.step()
	assert_false(f.busy())
	assert_eq(f.coverage(), 1.0)
	f.fade_in()
	assert_eq(f.coverage(), 1.0)
	for i in 32:
		f.step()
	assert_false(f.busy())
	assert_eq(f.coverage(), 0.0)
	f.free()


func test_custom_length_and_colour() -> void:
	var f := MwScreenFader.new()
	f.fade_out(56, Color.WHITE)
	var n := 0
	while f.busy():
		f.step()
		n += 1
	assert_eq(n, 56)
	assert_eq(f.rect.color, Color.WHITE)
	f.free()


func test_cover_is_instant() -> void:
	var f := MwScreenFader.new()
	f.cover()
	assert_eq(f.coverage(), 1.0)
	assert_false(f.busy())
	f.uncover()
	assert_eq(f.coverage(), 0.0)
	f.free()


func test_a_fade_starts_from_the_current_coverage() -> void:
	var f := MwScreenFader.new()
	f.cover()
	f.fade_in(32)
	for i in 8:
		f.step()
	assert_almost_eq(f.coverage(), 0.75, 0.0001)
	f.fade_out(32)                  # e.g. a press during the logo's fade-in
	f.step()
	assert_almost_eq(f.coverage(), 0.75 + 0.25 / 32.0, 0.0001, "no jump back to 0")
	for i in 31:
		f.step()
	assert_eq(f.coverage(), 1.0)
	assert_false(f.busy())
	f.free()


func test_fade_lengths_follow_the_code() -> void:
	assert_eq(MwFade.ticks(0x20), 32)
	assert_eq(MwFade.ticks(0x1E), 30)
	assert_eq(MwFade.ticks(1), 1, "D1 < 2: one tick")
	assert_eq(MwFade.ticks(0), 1)
	assert_eq(MwScreenFader.DEFAULT_TICKS, MwFade.ticks(0x20))


func test_item_fades() -> void:
	var a := Node2D.new()
	var b := Node2D.new()
	var fade := MwFade.new([a] as Array[CanvasItem], 0.0)
	assert_eq(a.modulate, Color(0, 0, 0, 1))
	fade.add(b)
	assert_eq(b.modulate, Color(0, 0, 0, 1), "added items take the current level")
	fade.fade_in(30)
	var n := 0
	while fade.busy():
		fade.step()
		n += 1
	assert_eq(n, 30)
	assert_eq(a.modulate, Color.WHITE)
	assert_eq(b.modulate, Color.WHITE)
	fade.fade_out(30)
	for i in 15:
		fade.step()
	assert_almost_eq(fade.level, 0.5, 0.0001)
	fade.fade_in(10)               # from the current level
	fade.step()
	assert_almost_eq(fade.level, 0.55, 0.0001)
	a.free()
	b.free()


# --- the original's levels (`fade_vblank` $149F6; docs/re/title.md, Fade engine) ---

## Runs of [param f]'s shown level for a channel at [param screen] over a
## whole fade: [[level, ticks], ...] from the fade's first tick on.
func _runs(f: MwScreenFader, screen: int) -> Array:
	var runs := []
	while f.busy():
		f.step()
		var l := f.level_shown(screen)
		if runs.is_empty() or runs[-1][0] != l:
			runs.append([l, 0])
		runs[-1][1] += 1
	return runs


func test_progress_follows_the_code() -> void:
	assert_eq(MwScreenFader.progress_at(1, 32), 0x800)
	assert_eq(MwScreenFader.progress_at(31, 32), 31 * 0x800)
	assert_eq(MwScreenFader.progress_at(32, 32), MwScreenFader.DONE, "the carry after exactly D1 ticks")
	assert_eq(MwScreenFader.progress_at(0, 56), 0x10000 % 56, "the remainder is the start")
	assert_eq(MwScreenFader.progress_at(56, 56), MwScreenFader.DONE)
	assert_eq(MwScreenFader.progress_at(0, 1), MwScreenFader.DONE, "D1 < 2: one tick")


func test_a_full_colour_steps_down_as_on_the_original() -> void:
	var f := MwScreenFader.new()
	f.fade_out()
	# GPGX, CRAM frame by frame (plan 19 notes): 7 -> 6 -> ... -> 0 held 4, 5, 4, 5, 5, 4 ticks
	assert_eq(_runs(f, 7), [[7, 2], [6, 4], [5, 5], [4, 4], [3, 5], [2, 5], [1, 4], [0, 3]])
	f.fade_in()
	assert_eq(_runs(f, 7), [[0, 2], [1, 4], [2, 5], [3, 4], [4, 5], [5, 5], [6, 4], [7, 3]])
	f.free()


func test_dim_colours_reach_black_early() -> void:
	var f := MwScreenFader.new()
	f.fade_out()
	var black_at := {}
	for k in range(1, 33):
		f.step()
		for lv in [1, 2, 3, 7]:
			if not black_at.has(lv) and f.level_shown(lv) == 0:
				black_at[lv] = k
	assert_eq(black_at, {1: 16, 2: 24, 3: 27, 7: 30}, "the screen is black for the last 3 ticks, dim colours sooner")
	f.free()


func test_a_reversed_fade_starts_from_its_level() -> void:
	var f := MwScreenFader.new()
	f.cover()
	assert_eq(f.level_shown(7), 0)
	f.fade_in(32)
	for i in 16:
		f.step()
	var mid := f.level_shown(7)
	assert_eq(mid, MwScreenFader.faded_level(0, 7, 16 * 0x800))
	f.fade_out(32)
	assert_eq(f.level_shown(7), mid, "no jump")
	f.step()
	assert_eq(f.level_shown(7), MwScreenFader.faded_level(mid, 0, 0x800))
	while f.busy():
		f.step()
	assert_eq(f.level_shown(7), 0)
	f.free()


func test_the_cover_is_hidden_on_an_uncovered_screen() -> void:
	var f := MwScreenFader.new()
	assert_false(f.rect.visible, "no cover, no screen copy")
	f.fade_out()
	assert_true(f.rect.visible)
	while f.busy():
		f.step()
	f.fade_in()
	while f.busy():
		f.step()
	assert_false(f.rect.visible)
	f.free()


func test_smooth_fades_are_a_switch_off_by_default() -> void:
	assert_false(MwScreenFader.smooth_fades, "the original's 3-bit steps by default")
	var f := MwScreenFader.new()
	f.fade_out()
	assert_eq(f.rect.material.get_shader_parameter("smooth_fade"), false)
	MwScreenFader.smooth_fades = true
	f.step()
	assert_eq(f.rect.material.get_shader_parameter("smooth_fade"), true)
	MwScreenFader.smooth_fades = false
	var n := 1
	while f.busy():
		f.step()
		n += 1
	assert_eq(n, 32, "the same timing")
	f.free()

