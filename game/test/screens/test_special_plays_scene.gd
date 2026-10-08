extends "res://test/rom/rom_test_base.gd"
## The special plays scene (screen 10, game/scenes/special_plays) on a
## match state: the backdrop by pad mode on plane B, the pages' texts on
## the window (page B's from row 13 with a second pad), the buttons, the
## idle page's players and the substitution list's portrait as sprites, the
## menus' tune, the choices reaching the sim and the exits (back to the
## scoreboard; 5 after a timeout).


## The scene entered from [param from], on [param state] (null: the demo
## match), its exit requests collected in [param exits].
func _scene(exits: Array, from: int, state: MwRinkState) -> MwBetweenPlays:
	var node: MwBetweenPlays = (load(MwScreens.scene_path(10)) as PackedScene).instantiate()
	node.screen_id = 10
	node.previous = from
	if state != null:
		var session := MwSession.new(77, 0x1234567)
		session.screens["rink"] = state
		node.session = session
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


static func _shown(node: MwBetweenPlays) -> int:
	var n := 0
	for layer in [node.sprites_low, node.sprites_high]:
		for c in (layer as Node).get_children():
			if (c as Sprite2D).visible:
				n += 1
	return n


## The rows of [param plane] (and its high-priority cells) holding cells.
static func _rows(plane: RomPlane) -> Array:
	var out := []
	var cells := plane.get_used_cells()
	if plane.high_cells:
		cells.append_array(plane.high_cells.get_used_cells())
	for c in cells:
		if not c.y in out:
			out.append(c.y)
	out.sort()
	return out


func test_one_pad_team_with_the_idle_page() -> void:
	if not need_rom():
		return
	var exits := []
	var calls := []
	MwSound.trace = func(what: String, _args: Array, _result: Variant) -> void: calls.append(what)
	var node := _scene(exits, 14, null)
	MwSound.trace = Callable()
	var sim := node.sim as MwSpecialPlaysSim
	assert_not_null(sim)
	assert_eq(node.state.pad_mode, 0, "the demo match: team B has no pad")
	assert_has(calls, "music_game", "the menus' tune (`$13C6E`)")
	var rows := _rows(node.plane_b)
	assert_eq([rows.front(), rows.back()], [0, 23], "the picture and the line-up display")
	assert_true(node.plane_b.high_cells.get_used_cells().size() > 100, "the display's front rows above the sprites")
	node._screen_pass(2, MwInputFrame.new())
	assert_true(node.window.get_used_cells().size() > 60, "the plays page's texts")
	assert_true(_rows(node.window).back() <= 12, "page A's rows only")
	assert_true(_shown(node) >= 9, "the buttons and team A's players")
	assert_eq(sim.sprite_ops.filter(func(x: Array) -> bool: return x[0] == "anim").size(), 6)
	node._screen_pass(2, _frame(["p1_ui_down"]))
	assert_eq(sim.pages[0].cursor, 3)
	node._screen_pass(2, _frame(["p1_ui_option_b"]))
	assert_eq(node.state.teams[0].special, 10, "B: the highlighted play armed")
	assert_true(exits.is_empty())
	node._screen_pass(2, MwInputFrame.new())
	assert_eq(exits, [14], "back to the scoreboard")


func test_two_pads_with_reserves() -> void:
	if not need_rom():
		return
	var s := MwRinkState.new()
	var rs := MwRinkSim.new(rom, s)
	MwRinkMatch.start(rs, 0, 0, 5, 1, true, 2)
	s.period = 1
	var exits := []
	var node := _scene(exits, 4, s)
	var sim := node.sim as MwSpecialPlaysSim
	assert_eq(node.state, s, "the session's match")
	assert_eq(_rows(node.plane_b).back(), 27, "the picture in 28 rows")
	node._screen_pass(2, MwInputFrame.new())
	var rows := _rows(node.window)
	assert_true(rows.front() < 13 and rows.back() >= 13 + 5, "both pages' positions")
	# page A: the left wing's substitution list
	node._screen_pass(2, _frame(["p1_ui_down"]))
	node._screen_pass(2, _frame(["p1_ui_option_a"]))
	assert_eq(sim.pages[0].handler, MwSpecialPlaysSim.SUBST_PASS)
	node._screen_pass(2, MwInputFrame.new())
	assert_true(sim.sprite_ops.any(func(x: Array) -> bool: return x[0] == "portrait"), "the coach")
	assert_true(_shown(node) > 0)
	node._screen_pass(2, _frame(["p1_ui_down"]))
	node._screen_pass(2, _frame(["p1_ui_option_a"]))
	assert_eq(s.teams[0].players[1].record, MwGfx.u32(rom, s.teams[0].record + 0x18 + 4 * 7), "a line change")
	# both pages done: a faceoff after the timeout
	node._screen_pass(2, _frame(["p1_ui_accept"]))
	node._screen_pass(2, _frame(["p1_ui_accept", "p2_ui_accept"]))
	assert_eq([sim.pages[0].done, sim.pages[1].done], [1, 1])
	node._screen_pass(2, MwInputFrame.new())
	assert_eq(exits, [5])
