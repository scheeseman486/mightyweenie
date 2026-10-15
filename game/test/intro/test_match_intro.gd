extends "res://test/rom/rom_test_base.gd"
## The matchup in 3D (plan 33, MwMatchup + MwMatchIntro3D): the opening
## goes on until a press; a press lines the players up and the rink takes
## over without a fade; a second press skips to it with the fade; 2D is the
## original's; the game is the same either way.


func _router(view: int, seed_ := 1) -> MwRouter:
	var host := Node.new()
	add_child_autofree(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(seed_, 1)
	router.session.setup.team_a = 3
	router.session.setup.team_b = 7
	_saved_view = MwSettings.start_view
	MwSettings.start_view = view
	router.go(3, {}, false)
	router.step()
	MwSettings.start_view = _saved_view
	return router


var _saved_view := -1


func _press() -> MwInputFrame:
	var a := MwVerbs.pad_actions(1, MwVerbs.BITS["START"], [MwVerbs.Context.MATCHUP])
	return MwInputFrame.make(a, {})


func _none() -> MwInputFrame:
	return MwInputFrame.make({}, {})


## The router's ticks until its screen is [param id] (at most [param n]);
## returns the ticks run.
func _until(router: MwRouter, id: int, n: int) -> int:
	for i in n:
		if router.current_id() == id:
			return i
		router.step()
	return n


func test_the_opening_goes_on_until_a_press_then_the_rink_without_a_fade() -> void:
	if not need_rom():
		return
	var router := _router(MwRinkViews.FOLLOW)
	var mu := router.current() as MwMatchup
	assert_not_null(mu.intro, "the 3D opening")
	assert_false(mu.get_node("Rink").visible, "the 2D rink hidden")
	_until(router, -99, 1500)
	assert_eq(router.current_id(), 3, "no 300-tick timeout: it goes on")
	assert_gt(mu.intro.cast.items().size(), 20, "the players are out")
	var rng_before := router.session.rng.state
	var life_seed := mu.intro.life.crowd_seed
	assert_not_null(mu.plane.lower, "the text in two halves")
	mu._screen_pass(1, _press())
	assert_true(mu.intro.cast.lining_up, "a press lines them up")
	_until(router, -99, MwMatchup.SWING_TICKS / 4)
	assert_gt(mu.plane.position.y, 0.0, "a little swing back first")
	_until(router, -99, MwMatchup.SWING_TICKS / 2)
	assert_lt(mu.plane.position.y, 0.0, "the top half swings out to the top")
	assert_gt(mu.plane.lower.position.y, 0.0, "the bottom half to the bottom")
	_until(router, -99, MwMatchup.SWING_TICKS / 4 + 1)
	assert_false(mu.plane.visible or mu.plane.lower.visible, "both out")
	var k := 0
	while not mu.intro.cast.lined_up() and k < 1200:
		router.step()
		k += 1
	var shown := {}
	for it: Dictionary in mu.intro.cast.items():
		shown[it["key"]] = true
	for st: Dictionary in mu.intro.rehearsal.starters():
		assert_true(shown.has(st["key"]), "in place, a starter is drawn as the rink will draw him")
	for key: String in shown:
		assert_false(key.begins_with("cast."), "everyone as the rink will draw him: " + key)
	var n := _until(router, 4, 1200)
	assert_eq(router.current_id(), 4, "the rink after %d ticks" % n)
	assert_eq(router.fader.coverage(), 0.0, "no fade")
	var rk := router.current() as MwRink
	var rehearsal := MwMatchRehearsal.run(rom, router.session.setup, rng_before, router.session.playoffs)
	assert_eq(MwSimDict.diff(MwSimDict.to_dict(rk.state), MwSimDict.to_dict(rehearsal.state)), {},
			"the match as rehearsed")
	assert_eq(rk.state.crowd_life.crowd_seed, life_seed, "the crowd goes on")


func test_a_second_press_skips_with_the_fade() -> void:
	if not need_rom():
		return
	var router := _router(MwRinkViews.CINEMATIC, 4)
	var mu := router.current() as MwMatchup
	_until(router, -99, 30)
	mu._screen_pass(1, _press())
	_until(router, -99, 10)
	mu._screen_pass(1, _press())
	assert_gt(router.fader.coverage() + (1.0 if router.fader.busy() else 0.0), 0.0, "fading out")
	_until(router, 4, 200)
	assert_eq(router.current_id(), 4)


func test_2d_is_the_originals() -> void:
	if not need_rom():
		return
	var router := _router(MwRinkViews.FLAT)
	var mu := router.current() as MwMatchup
	assert_null(mu.intro, "no 3D opening in 2D")
	assert_null(mu.plane.lower, "the text in one plane")
	var n := _until(router, 4, 600)
	assert_eq(router.current_id(), 4, "300 ticks, then the rink")
	assert_lt(n, 400)


## Plan 35: the opening's flow is a match rule (online the host's camera);
## a machine that draws 2D runs the 3D flow's model alone - the rink comes
## at the same tick with the same match as on a machine drawing it.
func test_the_flow_is_the_matchs_rule_whatever_this_machine_draws() -> void:
	if not need_rom():
		return
	var runs := []
	for drawn in [true, false]:
		if not drawn:
			MwSettings.use_match_rules({"opening_view": MwRinkViews.FOLLOW})
		var router := _router(MwRinkViews.FOLLOW if drawn else MwRinkViews.FLAT, 9)
		var mu := router.current() as MwMatchup
		assert_not_null(mu.intro, "the 3D flow (drawn: %s)" % drawn)
		assert_eq(mu.intro.view == null, not drawn, "a view only where it is drawn")
		assert_eq(mu.get_node("Rink").visible, not drawn, "the 2D picture where it isn't")
		_until(router, -99, 200)
		mu._screen_pass(1, _press())
		var n := _until(router, 4, 2000)
		assert_eq(router.current_id(), 4)
		var rk := router.current() as MwRink
		runs.append([router.tick, MwSimDict.to_dict(rk.state), rk.state.crowd_life.crowd_seed, n])
		MwSettings.own_match_rules()
	assert_eq(runs[1][0], runs[0][0], "the rink at the same tick")
	assert_eq(runs[1][2], runs[0][2], "the same crowd")
	assert_eq(MwSimDict.diff(runs[0][1], runs[1][1]), {}, "the same match")
