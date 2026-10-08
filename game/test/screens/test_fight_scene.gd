extends "res://test/rom/rom_test_base.gd"
## The scenes of the fight (18, game/scenes/fight) and the referee
## cutscene (19, game/scenes/ref_wasted) run on their own (the demo match):
## what each pass paints and shows, the players' verbs reaching the sim
## (FIGHT + MENU contexts), the fade before the fight card with no passes
## run, the card over the fighters, the exits to 17.


## A screen scene entered on its own, its exit requests collected in [param exits].
func _scene(id: int, exits: Array) -> MwBetweenPlays:
	var node: MwBetweenPlays = (load(MwScreens.scene_path(id)) as PackedScene).instantiate()
	node.screen_id = id
	node.previous = 5
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


static func _cells(node: Node, name: String) -> int:
	return (node.get_node(name) as TileMapLayer).get_used_cells().size()


## Whether the window shows cells of the fight's tile bank (the card's rows).
static func _card_cells(node: MwBetweenPlays) -> int:
	var n := 0
	for plane in [node.window, node.window.high_cells]:
		for at in (plane as TileMapLayer).get_used_cells():
			var k := int((plane as RomPlane).cell(at.x, at.y)["key"])
			if k >= 1000 and k < 1085:
				n += 1
	return n


func test_fight_scene() -> void:
	if not need_rom():
		return
	var exits := []
	var node := _scene(18, exits)
	var sim := node.sim as MwFightSim
	assert_not_null(sim)
	assert_true(_cells(node, "PlaneB") + _cells(node, "PlaneBHigh") > 600, "the scoreboard on plane B")
	assert_true(_cells(node, "Window") + _cells(node, "WindowHigh") > 300, "the panel picture, names and bars")
	assert_eq(node.window.tiles.banks, PackedStringArray(["picture_03f460", "picture_03c264", "tilebank_02155a"]))
	for i in 60:
		node._screen_pass(2, MwInputFrame.new())
	assert_eq(sim.state, MwFightSim.FIGHTING, "walked in")
	assert_true(_shown(node.sprites_high) >= 2, "the fighters (priority sprites)")
	node._screen_pass(1, _frame(["p1_fight_punch"]))
	assert_eq(sim.fighters[0].state, MwFightSim.PUNCH, "B / C: fight_punch on pad 1")
	for i in 60:
		node._screen_pass(1, MwInputFrame.new())
	node._screen_pass(1, _frame(["p1_ui_accept"]))
	assert_eq(sim.state, MwFightSim.PAUSING, "Start: the menu context's accept")
	for i in 30:
		node._screen_pass(1, MwInputFrame.new())
	node._screen_pass(1, _frame(["p1_ui_accept"]))
	assert_eq(sim.state, MwFightSim.FIGHTING, "resumed")
	sim.fight_time = 1199
	sim.fighters[0].landed = 2
	var n := 0
	var pieces := 0
	while not sim.card and n < 400:
		pieces = _shown(node.sprites_high)
		node._screen_pass(1, MwInputFrame.new())
		n += 1
	assert_true(sim.card, "the result, then the card")
	assert_true(_card_cells(node) > 500, "the card's rows from the fight's tile bank (no fader: at once)")
	assert_true(pieces > 2)
	assert_eq(_shown(node.sprites_high), pieces, "the fighters stay over the card")
	assert_eq(int(node.palette.steps.size()), 3, "the card's colours: the screen palette, $39, colour 0")
	for i in 70:
		node._screen_pass(2, _frame(["p2_ui_option_b"]))
		if not exits.is_empty():
			break
	assert_eq(exits, [17], "B on pad 2 ends the card after 120 ticks")
	assert_eq(_shown(node.sprites_high), pieces)


func test_fade_before_the_card_runs_no_passes() -> void:
	if not need_rom():
		return
	var exits := []
	var node := _scene(18, exits)
	var fader := MwScreenFader.new()
	add_child_autofree(fader)
	node.fader = fader
	var sim := node.sim as MwFightSim
	for i in 60:
		node._screen_pass(2, MwInputFrame.new())
	sim.fight_time = 1199
	var n := 0
	while not sim.card and n < 400:
		node._screen_pass(1, MwInputFrame.new())
		n += 1
	assert_true(fader.busy(), "the 16-tick fade-out")
	assert_eq(_card_cells(node), 0, "the card waits for the cover")
	var tick := node.state.tick
	for i in 16:
		node._screen_pass(1, MwInputFrame.new())
		fader.step()
	assert_eq(sim.card_left, MwFightSim.CARD_TICKS, "no card pass during the fade")
	assert_eq(node.state.tick, tick + 16, "the game's tick goes on")
	node._screen_pass(1, MwInputFrame.new())
	assert_true(_card_cells(node) > 500, "covered: the card painted")
	assert_eq(fader.direction, -1, "and fading in")
	assert_eq(sim.card_left, MwFightSim.CARD_TICKS)
	node._screen_pass(3, MwInputFrame.new())
	assert_eq(sim.card_left, MwFightSim.CARD_TICKS - 3, "then the card's passes")


func test_ref_wasted_scene() -> void:
	if not need_rom():
		return
	var exits := []
	var node := _scene(19, exits)
	var sim := node.sim as MwRefereeSim
	assert_not_null(sim)
	assert_eq(node.state.phase, 12, "the demo match in Waste the Ref")
	assert_true(_cells(node, "PlaneB") + _cells(node, "PlaneBHigh") > 600, "the scoreboard")
	assert_true(_cells(node, "Window") + _cells(node, "WindowHigh") >= 320, "the message panel's picture")
	node._screen_pass(2, _frame(["p1_ui_accept"]))
	assert_true(exits.is_empty(), "nothing skips it")
	var most := 0
	var n := 0
	while exits.is_empty() and n < 1500:
		node._screen_pass(2, MwInputFrame.new())
		most = maxi(most, _shown(node.sprites_low) + _shown(node.sprites_high))
		n += 1
	assert_true(most > 10, "the referee and the players coming for him (side view)")
	assert_eq(exits, [17], "to the message scoreboard")
	assert_eq(node.state.ref_flag, 0, "the referee down")
	assert_eq(node.state.teams[0].flags5 & 1, 0)
