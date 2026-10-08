extends "res://test/rom/rom_test_base.gd"
## The rink scene (screens 4-6): set-up and camera at a faceoff, the layers
## following the camera, live play (the simulation on the players' verbs,
## the AI, the match flow: the period start, the pause menu, the exits),
## and recorded passes of the original shown through the sprite layers
## (compare/fixtures/rink_draw.json).

var host: Node
var _passes: Array


func before_all() -> void:
	super.before_all()
	_passes = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_draw.json")))["passes"]


func after_each() -> void:
	if host:
		host.free()
		host = null
		await wait_process_frames(1)


func _router(session: MwSession) -> MwRouter:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = session
	return router


func _rink(router: MwRouter, id: int, data := {}) -> MwRink:
	router.go(id, data, false)
	for i in 3:
		router.step()
	return router.current() as MwRink


func test_period_start_sets_up_the_stadium_and_holds_the_faceoff_view() -> void:
	if not need_rom():
		return
	var s := MwSession.new(1, 1)
	s.setup.team_a = 9
	s.setup.stadium = 9
	var rk := _rink(_router(s), 4)
	assert_not_null(rk)
	assert_eq(rk.state.stadium, 9)
	assert_eq(rk.state.nets[0].style, 2, "Rink War Arena: Battle Nets")
	assert_eq(rk.palette.stadium, 9)
	var cam := rk.state.camera.shown
	assert_almost_eq(cam.y, 293, 40, "near the centre faceoff view (96, 293), drifting to the puck")
	assert_eq(rk.plane_low.position, Vector2(-cam), "plane B low cells at the camera")
	assert_eq(rk.plane_high.position, Vector2(-cam), "plane B high cells at the camera")
	assert_true(rk.window.get_used_cells().size() > 40, "clock widget drawn")


func test_live_play_runs_the_simulation_on_the_verbs() -> void:
	if not need_rom():
		return
	var s := MwSession.new(1, 1)
	s.setup.team_a = 3
	s.setup.team_b = 7
	s.setup.stadium = 3
	var router := _router(s)
	var rk := _rink(router, 4, {"new_match": true})
	var st := rk.state
	assert_eq(st.phase, MwRinkState.PHASE_START, "a period starts (panel, coach, FACE OFF!)")
	assert_true(st.rng == s.rng, "the session's main stream")
	_until_play(rk)
	assert_eq(st.phase, MwRinkState.PHASE_PLAY, "the puck dropped")
	var me: MwRinkState.Player = null
	for p in st.teams[0].players:
		if p.flags & MwRinkState.Player.HUMAN:
			me = p
	var y0 := me.motion.pixels().y
	var down := {"p1_move_down": true}
	rk._screen_pass(2, MwInputFrame.make(down, {}))
	for i in 30:
		rk._screen_pass(2, MwInputFrame.make(down, down))
	assert_gt(me.motion.pixels().y, y0 + 20, "P1 skated down the ice")
	assert_eq(rk.sprites_low.get_child_count() + rk.sprites_high.get_child_count() > 12, true, "players drawn")


## Passes with nothing pressed until open play (the period start's panel,
## team A's coach - 600 ticks unless skipped -, the drop, the faceoff).
func _until_play(rk: MwRink) -> void:
	for i in 900:
		if rk.state.phase == MwRinkState.PHASE_PLAY:
			return
		rk._screen_pass(2, MwInputFrame.make({}, {}))


func test_start_pauses_and_the_pad_that_paused_answers() -> void:
	if not need_rom():
		return
	var router := _router(MwSession.new(1, 1))
	var rk := _rink(router, 4, {"new_match": true})
	var st := rk.state
	_until_play(rk)
	assert_eq(st.phase, MwRinkState.PHASE_PLAY)
	var start := {"p1_pause": true}
	rk._screen_pass(2, MwInputFrame.make(start, {}))
	assert_true(rk.phases.paused, "the pause menu")
	assert_ne(st.clock_widget & 4, 0, "the clock paused")
	var puck := st.puck.motion.pos.duplicate()
	var tick := st.tick
	for i in 10:
		rk._screen_pass(2, MwInputFrame.make({"p1_move_down": true}, {}))
	assert_eq(st.puck.motion.pos, puck, "the game stands still")
	assert_eq(st.tick, tick + 20, "the tick counter runs")
	rk._screen_pass(2, MwInputFrame.make(start, {}))
	assert_false(rk.phases.paused, "Start resumes")
	assert_eq(st.clock_widget & 4, 0, "the clock goes on")
	assert_eq(st.pass_tick, st.tick, "the paused time is not elapsed")
	assert_false(router.busy())
	rk._screen_pass(2, MwInputFrame.make({}, {}))
	rk._screen_pass(2, MwInputFrame.make(start, {}))
	assert_true(rk.phases.paused, "paused again")
	var a := {"p1_punch": true, "p1_dive": true, "p1_special_play": true}
	rk._screen_pass(2, MwInputFrame.make(a, {}))
	assert_true(router.busy(), "A: leaving for the instant replay")


## Cells in use in the window plane's rectangle (x, y, w, h).
func _cells(rk: MwRink, x: int, y: int, w: int, h: int) -> int:
	var n := 0
	for cy in range(y, y + h):
		for cx in range(x, x + w):
			if int(rk.window.cell(cx, cy)["key"]) != 0:
				n += 1
	return n


func test_the_window_shows_the_panel_the_speech_the_clock_and_the_pause() -> void:
	if not need_rom():
		return
	var s := MwSession.new(1, 1)
	s.setup.team_a = 3
	s.setup.team_b = 7
	s.setup.stadium = 3
	var rk := _rink(_router(s), 4, {"new_match": true})
	var st := rk.state
	rk._screen_pass(2, MwInputFrame.make({}, {}))
	assert_gt(_cells(rk, 0, 8, 40, 12), 50, "the period / score panel")
	for i in 120:
		if st.phase == 9 and st.subphase == 1 and _cells(rk, 0, 0, 40, 8) > 0:
			break
		rk._screen_pass(2, MwInputFrame.make({}, {}))
	var b: PackedInt32Array = st.speech_box
	assert_ne(int(rk.window.cell(b[0] - 1, b[1] - 1)["key"]), 0, "the speech box's corner")
	assert_gt(_cells(rk, b[0], b[1], b[2], b[3]), 20, "the quote in it")
	_until_play(rk)
	assert_gt(_cells(rk, 2, 22, 9, 5), 30, "the clock widget")
	var start := {"p1_pause": true}
	rk._screen_pass(2, MwInputFrame.make(start, {}))
	assert_eq(_cells(rk, 2, 22, 9, 5), 0, "the window cleared for the menu")
	assert_gt(_cells(rk, 12, 0, 16, 5), 10, "PAUSE")
	assert_gt(_cells(rk, 7, 5, 26, 5), 10, "A - REPLAY")
	rk._screen_pass(2, MwInputFrame.make(start, {}))
	assert_gt(_cells(rk, 2, 22, 9, 5), 30, "the widget back when play resumes")


func test_recorded_passes_show_every_piece() -> void:
	if not need_rom():
		return
	var router := _router(MwSession.new(1, 1))
	var rk := _rink(router, 6)
	for p in _passes.slice(0, 8):
		rk.state = MwRinkState.from_dict(rom, p["state"])
		rk._phase_adds = p["phase_adds"]
		rk._present()
		var shown := 0
		for layer in [rk.sprites_low, rk.sprites_high]:
			for c in layer.get_children():
				if (c as Sprite2D).visible:
					shown += 1
		assert_eq(shown, (p["sprites"] as Array).size(), "%s: one sprite per piece" % p["name"])


func test_high_piece_behind_a_low_one_is_cut() -> void:
	if not need_rom():
		return
	var layer := MwSpriteLayer.new()
	layer.high = true
	add_child_autofree(layer)
	# the player shadow (one 24x16 piece... its first piece) twice, the low copy in front
	var piece := MwRinkDraw.SHADOW + 2
	var size := rom[piece + 2]
	var tile := MwGfx.u16(rom, piece + 4)
	var low := [0x100, 0x100, size, 0x60, tile, 9]
	var high := [0x100, 0x100, size, 0xE0, tile, 5]
	layer.show_list([low, high])
	var s := layer.get_child(0) as Sprite2D
	var img := s.texture.get_image()
	var opaque := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).r8 != 0:
				opaque += 1
	assert_eq(opaque, 0, "fully covered by the low piece in front")
	layer.show_list([high, low])
	img = (layer.get_child(0) as Sprite2D).texture.get_image()
	assert_true(img.get_data().count(0) < img.get_data().size(), "in front: drawn whole")


func test_shadow_highlight_is_translucency() -> void:
	if not need_rom():
		return
	var p := RomPalette.make(4, PackedStringArray(["screen_palette", "rom 1BD8A 3"]))
	var m := p.material(true)
	assert_true(m.get_shader_parameter("shadow_highlight"))
	assert_false(p.material().get_shader_parameter("shadow_highlight"))
