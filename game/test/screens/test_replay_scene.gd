extends "res://test/rom/rom_test_base.gd"
## The instant replay's scene (screen 7, game/scenes/instant_replay) on a
## demo match whose ring the CPU's AI filled (the scene run on its own) or
## on a state handed over in the session (live play): plane B the rink map
## at each drawn frame's camera point (its priority cells on PlaneBHigh),
## the widget in the window, the frames' sprites kept between drawn frames,
## the plates' RAM tiles, the replay verbs reaching the sim on the
## controlling pad, the exits (6 from the rink, the scoreboard it came
## from). The look is checked with screenshots, not here.

const SCRIPT := "res://scenes/instant_replay/instant_replay.gd"


## Screen 7 entered from [param from]; its exit requests go to [param
## exits]. [param st]: a state handed over in a session (null: run alone).
func _scene(from: int, exits: Array, st: MwRinkState = null) -> MwBetweenPlays:
	var node: MwBetweenPlays = (load(MwScreens.scene_path(7)) as PackedScene).instantiate()
	node.screen_id = 7
	node.previous = from
	if st != null:
		node.session = MwSession.new(1234, 5678)
		node.session.screens["rink"] = st
	add_child_autofree(node)
	node.exit_requested.connect(func(to: int, _d: Dictionary, _f: bool, _t: int) -> void: exits.append(to))
	node._enter_screen({})
	return node


## A demo match's state with a filled ring (as the scene makes it alone).
func _recorded_state() -> MwRinkState:
	var s := MwRinkState.new()
	MwRinkMatch.start(MwRinkSim.new(rom, s), 0, 0, 5, 0, false, 2)
	s.period = 1
	s.clock = 180
	return load(SCRIPT).demo_replay_state(rom, s)


static func _frame(actions: Array, held_only := false) -> MwInputFrame:
	var f := MwInputFrame.new()
	for a in actions:
		f.held[a] = true
		if not held_only:
			f.pressed[a] = true
	return f


static func _shown(layer: Node) -> int:
	var n := 0
	for c in layer.get_children():
		if (c as Sprite2D).visible:
			n += 1
	return n


static func _cells(node: Node, name: String) -> int:
	return (node.get_node(name) as TileMapLayer).get_used_cells().size()


func _camera(node: MwBetweenPlays) -> Vector2:
	var cam: Vector2i = (node.sim as MwReplaySim).replay.shown["camera"]
	return Vector2(-cam.x, -cam.y)


func test_scene_alone_shows_the_oldest_frame() -> void:
	if not need_rom():
		return
	var exits := []
	var node := _scene(5, exits)
	var rs := node.sim as MwReplaySim
	assert_not_null(rs)
	assert_true(rs.replay.ring.frames > 20, "the demo filled the ring")
	assert_eq(rs.replay.cursor, 1, "frozen on the oldest frame")
	var w := MwGfx.u16(rom, MwRinkUpdate.MAP + 8)
	var h := MwGfx.u16(rom, MwRinkUpdate.MAP + 0xA)
	assert_eq(_cells(node, "PlaneB") + _cells(node, "PlaneBHigh"), w * h, "the whole rink map")
	assert_true(_cells(node, "PlaneBHigh") > 0, "its near boards and crowd in front of the low sprites")
	assert_eq(node.plane_b.position, _camera(node), "plane B at the frame's camera point")
	assert_eq(node.plane_b.high_cells.position, node.plane_b.position)
	assert_eq(_cells(node, "WindowHigh"), 9 * 5, "the A/B/C widget (priority cells)")
	assert_eq(_cells(node, "Window"), 0)
	assert_true(_shown(node.sprites_low) + _shown(node.sprites_high) > 5, "the frame's sprites")
	assert_eq(node.sprites_low.ram_tiles.size(), 4 * 8, "the plates' RAM tiles")
	assert_eq(node.palette.screen, 7)
	assert_eq(node.palette.steps, PackedStringArray(["screen_palette", "rom 1BD8A 3"]), "the rink's palette")
	assert_eq(exits, [])


func test_play_rewind_and_exit_to_the_rink() -> void:
	if not need_rom():
		return
	var exits := []
	var node := _scene(5, exits)
	var rs := node.sim as MwReplaySim
	var sprites := _shown(node.sprites_low) + _shown(node.sprites_high)
	node._screen_pass(1, MwInputFrame.new())
	assert_eq(_shown(node.sprites_low) + _shown(node.sprites_high), sprites, "no frame drawn: the sprites stay")
	node._screen_pass(1, _frame(["p1_replay_play"]))
	assert_true(rs.replay.play, "C: replay_play on pad 1")
	for i in 60:
		node._screen_pass(1, MwInputFrame.new())
	assert_true(rs.replay.cursor > 5, "played on")
	assert_eq(node.plane_b.position, _camera(node), "plane B follows the frames")
	assert_true(_shown(node.sprites_low) + _shown(node.sprites_high) > 5)
	var at := rs.replay.cursor
	node._screen_pass(1, _frame(["p1_replay_rewind"]))
	for i in 20:
		node._screen_pass(1, _frame(["p1_replay_rewind"], true))
	assert_false(rs.replay.play)
	assert_true(rs.replay.cursor < at, "A held: rewinding")
	node._screen_pass(1, _frame(["p2_replay_exit"]))
	assert_eq(exits, [], "another pad's Start")
	node._screen_pass(1, _frame(["p1_replay_exit"]))
	assert_eq(exits, [6], "Start: back to the rink, play continues (entry 6)")
	var r := rs.replay.ring
	assert_eq([r.read, r.used], [rs.replay.saved_read, rs.replay.saved_used], "the ring put back")


func test_live_from_the_pause_menu_and_a_scoreboard() -> void:
	if not need_rom():
		return
	var st := _recorded_state()
	assert_true(st.replay.frames > 20, "frames recorded")
	st.pause_pad = 2                         # pad 2 paused and answered A
	var exits := []
	var node := _scene(6, exits, st)
	var rs := node.sim as MwReplaySim
	assert_eq(rs.s, st, "the rink's state from the session")
	assert_eq(rs.replay.pad, 1, "pad 2 controls")
	node._screen_pass(1, _frame(["p1_replay_exit"]))
	assert_eq(exits, [], "pad 1 is ignored")
	node._screen_pass(1, _frame(["p2_replay_exit"]))
	assert_eq(exits, [6])
	# from a scoreboard: the pad that pressed C there (its sim left the read in the state)
	for p in 4:
		st.pads_new[p] = 0
	st.pads_new[2] = MwInstantReplay.NEW_C
	exits.clear()
	var sb := _scene(14, exits, st)
	assert_eq((sb.sim as MwReplaySim).replay.pad, 2, "pad 3 pressed C")
	sb._screen_pass(1, _frame(["p3_replay_exit"]))
	assert_eq(exits, [14], "back to the scoreboard")
