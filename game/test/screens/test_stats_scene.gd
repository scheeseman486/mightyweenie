extends "res://test/rom/rom_test_base.gd"
## The game stats scene (8 with 9 inside it, game/scenes/game_stats) run
## on its own (the demo match): the starfield, plane A's rows below the
## window, the logos and arrows, the scroll, the switch to 9 and back
## behind a 32-tick fade with no passes run, the session's aux stream, the
## exit to the screen it came from.


## The scene entered from the scoreboard 14 with a session and a fader,
## its exit requests collected in [param exits].
func _scene(exits: Array, session: MwSession, fader: MwScreenFader) -> MwBetweenPlays:
	var node: MwBetweenPlays = (load(MwScreens.scene_path(8)) as PackedScene).instantiate()
	node.screen_id = 8
	node.previous = 14
	node.session = session
	node.fader = fader
	add_child_autofree(node)
	node.exit_requested.connect(func(to: int, _d: Dictionary, _f: bool, _t: int) -> void: exits.append(to))
	node._enter_screen({})
	return node


static func _frame(actions: Array) -> MwInputFrame:
	var f := MwInputFrame.new()
	for a in actions:
		f.held[a] = true
		f.pressed[a] = true
	return f


static func _shown(layer: Node) -> int:
	var n := 0
	for c in layer.get_children():
		if (c as Sprite2D).visible:
			n += 1
	return n


static func _cells(plane: TileMapLayer) -> int:
	return plane.get_used_cells().size()


## A pass of one tick (the fader stepped as the router does).
static func _tick(node: MwBetweenPlays, fader: MwScreenFader, input := MwInputFrame.new()) -> void:
	fader.step()
	node._screen_pass(1, input)


func test_stats_scene() -> void:
	if not need_rom():
		return
	var exits := []
	var session := MwSession.new(77, 0x1234567)
	var fader := MwScreenFader.new()
	add_child_autofree(fader)
	var aux := session.rng_aux.state
	var node := _scene(exits, session, fader)
	var sim := node.sim as MwStatsSim
	var plane_a := node.get_node("PlaneAClip/PlaneA") as RomPlane
	var clip := node.get_node("PlaneAClip") as Control
	var stars := node.get_node("Starfield") as RomStarfield
	assert_not_null(sim)
	assert_ne(session.rng_aux.state, aux, "the session's aux stream picked the starfield's direction")
	assert_eq(sim.aux, session.rng_aux)
	assert_true(_cells(node.window) > 20, "the title and team names")
	assert_true(_cells(plane_a) > 100, "the stats rows")
	assert_eq(_cells(node.plane_b), 0, "plane B is the starfield")
	assert_eq(clip.position.y, 72.0, "plane A below the window's 9 rows")
	assert_eq(plane_a.position.y, 80.0 - 72.0, "row 0 at screen line 80")
	assert_true(node.window.visible)
	assert_true(_shown(node.sprites_low) + _shown(node.sprites_high) >= 2, "logos and an arrow")
	var x := stars.x
	for i in 10:
		_tick(node, fader)
	assert_eq([stars.x, stars.y], [sim.star.pos[0], sim.star.pos[1]], "the starfield where the sim's VBlanks left it")
	assert_true(stars.x != x or stars.y != sim.star.pos[1] - 10 * sim.star.vel[1], "it moves")
	# a scroll step: 8 passes of 2 px
	_tick(node, fader, _frame(["p1_ui_down"]))
	for i in 8:
		_tick(node, fader)
	assert_eq(sim.scroll_a, -64)
	assert_eq(plane_a.position.y, 64.0 - 72.0, "plane A scrolled up 16 px")
	# A: 9 behind the fade, no passes while it covers
	_tick(node, fader, _frame(["p2_ui_option_a"]))
	assert_eq(sim.shown, 9, "any pad")
	assert_true(fader.busy(), "the fade out")
	var drawn := _cells(plane_a)
	var passes := 0
	var still := true
	while fader.direction > 0 and passes < 40:
		still = still and _cells(plane_a) == drawn and sim.page == 0
		_tick(node, fader, _frame(["p1_ui_down"]))
		passes += 1
	assert_eq(passes, 32, "32 ticks")
	assert_true(still, "8 shown under the cover, no pass run (Down ignored)")
	assert_eq(sim.page, 0)
	assert_eq(fader.direction, -1, "9 shown, fading in")
	assert_eq(node.window.visible, false, "9's first page is on plane A: no window rows")
	assert_eq(clip.position.y, 0.0)
	assert_eq(plane_a.position.y, 0.0)
	assert_true(_cells(plane_a) > 50, "a page of player stats")
	_tick(node, fader, _frame(["p1_ui_down"]))
	assert_eq(sim.page, 1)
	assert_true(node.window.visible, "the next page drawn on the window, which covers the screen")
	assert_false(clip.visible)
	assert_true(_cells(node.window) > 50)
	# Start: back to 8, set up again
	_tick(node, fader, _frame(["p1_ui_accept"]))
	assert_eq(sim.shown, 8)
	assert_true(exits.is_empty(), "9's Start stays in the scene")
	while fader.busy():
		_tick(node, fader)
	_tick(node, fader)
	assert_true(node.window.visible)
	assert_eq(clip.position.y, 72.0)
	assert_eq(plane_a.position.y, 8.0, "the first row again")
	assert_true(_cells(plane_a) > 100)
	# Start: back to the scoreboard
	var shown := _shown(node.sprites_low) + _shown(node.sprites_high)
	while fader.busy():
		_tick(node, fader)
	_tick(node, fader, _frame(["p1_ui_accept"]))
	assert_eq(exits, [14], "back where it came from")
	assert_eq(_shown(node.sprites_low) + _shown(node.sprites_high), shown, "the sprites stay up for the fade")
