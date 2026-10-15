extends "res://test/rom/rom_test_base.gd"
## The rink scene (screens 4-6): set-up and camera at a faceoff, the layers
## following the camera, live play (the simulation on the players' verbs,
## the AI, the match flow: the period start, the pause menu, the exits),
## and recorded passes of the original shown through the sprite layers
## (compare/fixtures/rink_draw.json).

var host: Node
var _passes: Array


var _layouts := {}


func before_all() -> void:
	super.before_all()
	_layouts = MwSettings.layouts


func after_all() -> void:
	MwSettings.layouts = _layouts
	MwInputMap.install()


func before_each() -> void:
	MwSettings.layouts = {}
	MwInputMap.install()
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
	var session := MwSession.new(1, 1)
	session.setup.team_a = 9
	session.setup.stadium = 9
	var rk := _rink(_router(session), 4)
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
	var session := MwSession.new(1, 1)
	session.setup.team_a = 3
	session.setup.team_b = 7
	session.setup.stadium = 3
	var router := _router(session)
	var rk := _rink(router, 4, {"new_match": true})
	var state := rk.state
	assert_eq(state.phase, MwRinkState.PHASE_START, "a period starts (panel, coach, FACE OFF!)")
	assert_true(state.rng == session.rng, "the session's main stream")
	_until_play(rk)
	assert_eq(state.phase, MwRinkState.PHASE_PLAY, "the puck dropped")
	var me: MwRinkState.Player = null
	for p in state.teams[0].players:
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
	MwSettings.layouts = {1: "GENESIS", 2: "GENESIS"}      # the original's pause menu
	var router := _router(MwSession.new(1, 1))
	var rk := _rink(router, 4, {"new_match": true})
	var state := rk.state
	_until_play(rk)
	assert_eq(state.phase, MwRinkState.PHASE_PLAY)
	var start := {"p1_pause": true}
	rk._screen_pass(2, MwInputFrame.make(start, {}))
	assert_true(rk.phases.paused, "the pause menu")
	assert_ne(state.clock_widget & 4, 0, "the clock paused")
	var puck := state.puck.motion.pos.duplicate()
	var tick := state.tick
	for i in 10:
		rk._screen_pass(2, MwInputFrame.make({"p1_move_down": true}, {}))
	assert_eq(state.puck.motion.pos, puck, "the game stands still")
	assert_eq(state.tick, tick + 20, "the tick counter runs")
	rk._screen_pass(2, MwInputFrame.make({"p2_ui_resume": true, "ui_resume": true}, {}))
	assert_true(rk.phases.paused, "only the pad that paused answers")
	var accept := {"p1_ui_resume": true, "ui_resume": true}
	rk._screen_pass(2, MwInputFrame.make(accept, {}))
	assert_false(rk.phases.paused, "Start (resume) resumes")
	assert_eq(state.clock_widget & 4, 0, "the clock goes on")
	assert_eq(state.pass_tick, state.tick, "the paused time is not elapsed")
	assert_false(router.busy())
	rk._screen_pass(2, MwInputFrame.make({}, {}))
	rk._screen_pass(2, MwInputFrame.make(start, {}))
	assert_true(rk.phases.paused, "paused again")
	rk._screen_pass(2, MwInputFrame.make({"p1_ui_back": true, "ui_back": true}, {}))
	assert_false(rk.phases.paused, "Menu Back resumes too")
	rk._screen_pass(2, MwInputFrame.make({}, {}))
	rk._screen_pass(2, MwInputFrame.make(start, {}))
	assert_true(rk.phases.paused, "paused a third time")
	rk._screen_pass(2, MwInputFrame.make({"p1_punch": true, "p1_dive": true}, {}))
	assert_true(rk.phases.paused, "gameplay verbs do nothing on the pause menu")
	rk._screen_pass(2, MwInputFrame.make({"p1_ui_pause_replay": true, "ui_pause_replay": true}, {}))
	assert_true(router.busy(), "Instant Replay: leaving for the replay")


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
	MwSettings.layouts = {1: "GENESIS"}                    # the original's pause menu
	var session := MwSession.new(1, 1)
	session.setup.team_a = 3
	session.setup.team_b = 7
	session.setup.stadium = 3
	var rk := _rink(_router(session), 4, {"new_match": true})
	var state := rk.state
	rk._screen_pass(2, MwInputFrame.make({}, {}))
	assert_gt(_cells(rk, 0, 8, 40, 12), 50, "the period / score panel")
	for i in 120:
		if state.phase == 9 and state.subphase == 1 and _cells(rk, 0, 0, 40, 8) > 0:
			break
		rk._screen_pass(2, MwInputFrame.make({}, {}))
	var b: PackedInt32Array = state.speech_box
	assert_ne(int(rk.window.cell(b[0] - 1, b[1] - 1)["key"]), 0, "the speech box's corner")
	assert_gt(_cells(rk, b[0], b[1], b[2], b[3]), 20, "the quote in it")
	_until_play(rk)
	assert_gt(_cells(rk, 2, 22, 9, 5), 30, "the clock widget")
	var start := {"p1_pause": true}
	rk._screen_pass(2, MwInputFrame.make(start, {}))
	assert_eq(_cells(rk, 2, 22, 9, 5), 0, "the window cleared for the menu")
	assert_gt(_cells(rk, 12, 0, 16, 5), 10, "PAUSE")
	assert_gt(_cells(rk, 7, 5, 26, 5), 10, "A - REPLAY")
	rk._screen_pass(2, MwInputFrame.make({"p1_ui_resume": true, "ui_resume": true}, {}))
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
	var sprite := layer.get_child(0) as Sprite2D
	var img := sprite.texture.get_image()
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
	var palette := RomPalette.make(4, PackedStringArray(MwScreenPalettes.RINK))
	var m := palette.material(true)
	assert_true(m.get_shader_parameter("shadow_highlight"))
	assert_false(palette.material().get_shader_parameter("shadow_highlight"))


## A pass with the actions [param a] newly pressed.
func _tap(rk: MwRink, a: Dictionary) -> void:
	rk._screen_pass(2, MwInputFrame.make(a, {}))
	rk._screen_pass(2, MwInputFrame.make({}, {}))


func _verb(v: String, p := 1) -> Dictionary:
	return {MwVerbs.menu_action(p, v): true, v: true}


## Per pause menu item drawn: "primary" (the big font's own tiles, the
## team line's colours 2-3) or "secondary" (MwGlyphs' recoloured tiles,
## colours 5-6).
func _item_colours(rk: MwRink) -> Array:
	var out := []
	var layers: Array = rk.pause_menu.get("_layers")
	for plane: RomPlane in layers.slice(2):
		var cells := plane.get_used_cells()
		if cells.is_empty():
			continue
		var remapped := cells.all(func(c: Vector2i) -> bool: return int(plane.cell(c.x, \
				c.y)["key"]) >= MwGlyphs.REMAP_BASE)
		out.append("secondary" if remapped else "primary")
	return out


static func _expected_colours(sel: int, n: int) -> Array:
	var out := []
	for i in n:
		out.append("primary" if i == sel else "secondary")
	return out


## The score panel's operations (MwRinkPhases `_panel`: both teams' names
## and scores in the big font, all on attr $A0) painted on a fresh plane
## with [param rk]'s state: per team (0 A, 1 B) the palette lines of its
## name's cells and whether its score's cells are recoloured (MwGlyphs "grey").
func _panel_cells(rk: MwRink) -> Array:
	var big := MwRinkPhases.BIG_FONT
	var out := []
	for t in 2:
		var plane := RomPlane.new()
		plane.tiles = rk.window.tiles
		add_child_autofree(plane)
		var row := 0x13 if t == 0 else 0x17
		MwWindowPainter.new(plane, rom).paint([["text", big, 1, row, 0xA0,
				MwGfx.u32(rom, rk.state.teams[t].record + 4)],
				["glyph", big, 0x24, row, 0xA0, 0x30 + t]], rk.state)
		var lines := {}
		var grey := true
		for at in plane.get_used_cells():
			var c := plane.cell(at.x, at.y)
			if at.x < 0x20:
				lines[int(c["line"])] = true
			elif int(c["key"]) < MwGlyphs.REMAP_BASE:
				grey = false
		out.append([lines.keys(), grey])
	return out


## Team names in the big font in their own team's colours, the scores grey
## (owner, 2026-10-09, MwSettings.team_name_colours); off: the original's
## panel, both names and scores on team A's line.
func test_the_score_panel_in_the_teams_colours() -> void:
	if not need_rom():
		return
	var was := MwSettings.team_name_colours
	var session := MwSession.new(1, 1)
	session.setup.team_a = 1
	session.setup.team_b = 5
	var rk := _rink(_router(session), 4, {"new_match": true})
	MwSettings.team_name_colours = true
	assert_eq(_panel_cells(rk), [[[1], true], [[2], true]],
			"team A's name on its line 1, team B's on line 2, the scores grey")
	MwSettings.team_name_colours = false
	assert_eq(_panel_cells(rk), [[[1], false], [[1], false]], "the original's: both on team A's line")
	MwSettings.team_name_colours = was


func test_the_standard_pause_menu() -> void:
	if not need_rom():
		return
	var router := _router(MwSession.new(1, 1))
	var rk := _rink(router, 4, {"new_match": true})
	_until_play(rk)
	rk._screen_pass(2, MwInputFrame.make({"p1_pause": true}, {}))
	assert_true(rk.phases.paused)
	var m := rk.phases.menu
	assert_eq(m["player"], 1)
	assert_eq(m["items"][0], "REPLAY")
	assert_eq(m["items"][-1], "FORFEIT")
	assert_eq(_cells(rk, 0, 0, 40, 20), 0, "the window holds none of the original's letters")
	assert_true(rk.pause_menu.visible, "the port's menu drawn")
	var line: RomPlane = rk.pause_menu.get("_layers")[1]
	var rows := {}
	for c in line.get_used_cells():
		rows[c.y] = true
	assert_eq(rows.keys().size(), 3,
			"PLAYER 1 on its black plate (MwGlyphs.black_label): the frame's rows above and below")
	assert_true(rows.has(MwPauseMenu.PLAYER_Y - 1) and rows.has(MwPauseMenu.PLAYER_Y + 1))
	var n: int = m["items"].size()
	assert_eq(_item_colours(rk), _expected_colours(0, n),
			"the selected item in the team's primary colour, the others in its secondary (owner)")
	_tap(rk, _verb("ui_up"))
	assert_eq(rk.phases.menu["sel"], n - 1, "up from the first item wraps to FORFEIT")
	assert_eq(_item_colours(rk), _expected_colours(n - 1, n), "the colours follow the selection")
	_tap(rk, _verb("ui_down"))
	assert_eq(rk.phases.menu["sel"], 0)
	_tap(rk, _verb("ui_down", 2))
	assert_eq(rk.phases.menu["sel"], 0, "only the player who paused answers")
	_tap(rk, _verb("ui_up"))
	_tap(rk, _verb("ui_accept"))
	assert_true(rk.phases.menu["confirm"], "FORFEIT asks first")
	assert_eq(rk.phases.menu["sure"], 1, "NO selected")
	_tap(rk, _verb("ui_resume").merged(_verb("ui_accept")))
	assert_false(rk.phases.menu["confirm"], "Start on ARE YOU SURE? goes back, never forfeits")
	assert_true(rk.phases.paused)
	_tap(rk, _verb("ui_back"))
	assert_false(rk.phases.paused, "Menu Back resumes")
	assert_false(rk.pause_menu.visible, "the menu goes")
	assert_eq(rk.state.phase, MwRinkState.PHASE_PLAY)
	rk._screen_pass(2, MwInputFrame.make({"p1_pause": true}, {}))
	_tap(rk, _verb("ui_resume"))
	assert_false(rk.phases.paused, "Start resumes")
	rk._screen_pass(2, MwInputFrame.make({"p1_pause": true}, {}))
	_tap(rk, _verb("ui_down"))
	for v in ["ui_pause_replay", "ui_pause_timeout"]:
		_tap(rk, _verb(v))
		assert_true(rk.phases.paused, "%s: no shortcut on the port's menu (owner)" % v)
		assert_false(router.busy())
		assert_eq(rk.phases.menu["sel"], 1, "the selection as it was")
	_tap(rk, _verb("ui_up"))
	_tap(rk, _verb("ui_accept"))
	assert_true(router.busy(), "Menu Accept on REPLAY: off to the instant replay")


## A team whose two colours are alike (the yellow team's are the same):
## the pause items' secondary drawn darker (owner), on a copy of the
## window's palette; a team with two distinct colours keeps the window's.
func test_the_pause_items_secondary_darker_when_alike() -> void:
	if not need_rom():
		return
	for team: int in [1, 0]:
		var session := MwSession.new(1, 1)
		session.setup.team_a = team
		var router := _router(session)
		var rk := _rink(router, 4, {"new_match": true})
		_until_play(rk)
		rk._screen_pass(2, MwInputFrame.make({"p1_pause": true}, {}))
		var window: RomPalette = rk.window.palette
		var items: RomPalette = (rk.pause_menu.get("_layers")[2] as RomPlane).palette
		var c := window.colours()
		if team == 1:
			assert_true(MwPauseMenu.alike(c[16 + 2], c[16 + 5]), "the yellow team's two colours alike")
			assert_ne(items, window, "the items on their own copy")
			assert_eq(items.colours()[16 + 5], RomPalette.darker(c[16 + 5], MwPauseMenu.DARKER_LEVELS),
					"its secondary darker")
			assert_eq(items.colours()[16 + 6], RomPalette.darker(c[16 + 6], MwPauseMenu.DARKER_LEVELS))
			assert_eq(items.colours()[16 + 2], c[16 + 2], "its primary as it is")
		else:
			assert_false(MwPauseMenu.alike(c[16 + 2], c[16 + 5]))
			assert_eq(items, window, "two distinct colours: the window's palette")
		host.free()
		host = null


func test_forfeit_from_the_pause_menu() -> void:
	if not need_rom():
		return
	var router := _router(MwSession.new(1, 1))
	var rk := _rink(router, 4, {"new_match": true})
	_until_play(rk)
	rk._screen_pass(2, MwInputFrame.make({"p1_pause": true}, {}))
	_tap(rk, _verb("ui_up"))                             # FORFEIT
	_tap(rk, _verb("ui_accept"))
	_tap(rk, _verb("ui_down"))                           # YES
	assert_eq(rk.phases.menu["sure"], 0)
	_tap(rk, _verb("ui_accept"))
	assert_false(rk.phases.paused)
	assert_eq(rk.state.phase, MwRinkMatch.PHASE_FORFEIT, "the original's forfeit")
	assert_eq(rk.state.scoring & 0xFFFF, MwRinkRam.TEAMS[0] & 0xFFFF, "player 1's team forfeits")
	assert_true(rk.state.forfeit_manual, "marked as a manual forfeit (plan 26: the port's lines on 17)")
	for i in 400:
		if router.busy():
			break
		rk._screen_pass(2, MwInputFrame.make({}, {}))
	assert_true(router.busy(), "then the forfeit scoreboard")
	assert_gt(_cells(rk, 0, 0, 40, 10), 10, "FORFEIT! shown")


## A team too short at a faceoff's line-up (owner's bug, 2026-10-10: a team
## running out of players as a faceoff came, then a freeze): the rink entry
## forfeits at once (`$F7C8` in `$F8A4`'s line-up: `rink_exit` to 17) - the
## exit asked for while the router is still entering the rink is the next
## change, never lost (the rink no longer passes once it has asked).
func test_a_forfeit_at_the_faceoff_line_up_leaves_for_the_message() -> void:
	if not need_rom():
		return
	var router := _router(MwSession.new(1, 1))
	var rk := _rink(router, 4, {"new_match": true})
	_until_play(rk)
	var team: MwRinkState.Team = rk.state.teams[1]
	var skaters := 0
	for q in team.players:
		if q.present and q.position != 5:
			skaters += 1
			if skaters > 1:
				team.health[q.slot] = 0          # dead, no substitute left (`$C1E` without `$F6A8`)
				rk.sim.players.off_ice(q)
	assert_true(rk.sim.players.forfeits(team), "one skater: the team forfeits")
	router.go(5, {}, false)                    # the next faceoff
	var seen := []
	for i in 600:
		router.step()
		if seen.is_empty() or seen.back() != router.current_id():
			seen.append(router.current_id())
		if router.current_id() == 17:
			break
	assert_eq(router.current_id(), 17, "the forfeit's message (screens %s)" % str(seen))
	assert_eq(router.session.screens["rink"].phase, MwRinkMatch.PHASE_FORFEIT)


func test_team_info_from_the_pause_menu_and_back() -> void:
	if not need_rom():
		return
	var session := MwSession.new(1, 1)
	session.setup.team_a = 3
	session.setup.team_b = 7
	var aspect := MwSettings.aspect
	MwSettings.aspect = "WIDE"
	var router := _router(session)
	var rk := _rink(router, 4, {"new_match": true})
	var host_3d := MwRink3DHost.of(rk.get_tree())
	_until_play(rk)
	rk._screen_pass(2, MwInputFrame.make({"p1_pause": true}, {}))
	var items: Array = rk.phases.menu["items"]
	assert_eq(items.slice(-2), ["TEAM INFO", "FORFEIT"], "before FORFEIT (plan 29)")
	assert_false(MwRinkPhases.QUIT in items, "no QUIT GAME: a spectated match's alone (owner, 2026-10-10)")
	var drawn: Array = rk.pause_menu.get("_layers").filter( \
			func(l: RomPlane) -> bool: return not l.get_used_cells().is_empty())
	assert_eq(drawn.size(), 2 + items.size(), "the title, the player and every item drawn")
	_tap(rk, _verb("ui_up"))                             # FORFEIT
	_tap(rk, _verb("ui_up"))                             # TEAM INFO
	_tap(rk, _verb("ui_accept"))
	assert_true(router.busy(), "the team description asked for")
	assert_eq(host_3d.wide_user, rk, "the game keeps its wide picture through the fade-out (owner)")
	var before := MwSimDict.to_dict(rk.state)
	var rng := [session.rng.state, session.rng_aux.state]
	var td: Node = null
	for i in 200:
		router.step()
		if router.current_id() == 2 and router.current() != rk:
			td = router.current()
			break
	assert_not_null(td, "pushed over the rink")
	assert_null(host_3d.wide_user, "given back under the cover: the description is pillarboxed")
	assert_eq(router.stack.size(), 2, "the rink waits underneath")
	assert_false(rk.visible)
	assert_eq(td.get("team"), 7, "player 1 paused: the opponent's team first")
	for i in 600:
		router.step()
		if td.get("page") == 0 and not td.get("scrolling") and int(td.get("_open_at")) < 0 and i > 60:
			break
	var start := MwVerbs.pad_actions(1, 0x80, [MwVerbs.Context.TEAM_INFO])
	td._screen_pass(1, MwInputFrame.make(start, {}))
	for i in 200:
		router.step()
		if router.current() == rk:
			break
	assert_eq(router.current(), rk, "Start: back to the game")
	var after := MwSimDict.to_dict(rk.state)
	var changed := []
	for k in before:
		# (the tick counter runs while paused, as in the original's pause loop)
		if k != "tick" and str(after.get(k)) != str(before[k]):
			changed.append(k)
	assert_eq(changed, [], "the game as it was paused")
	assert_eq([session.rng.state, session.rng_aux.state], rng, "the random streams untouched")
	assert_true(rk.phases.paused and rk.pause_menu.visible, "on its pause menu")
	assert_true(rk.visible)
	assert_eq(host_3d.wide_user, rk, "the wide picture taken again")
	MwSettings.aspect = aspect


# --- a spectated match (the port's CPU v CPU exhibition) ---------------------------------------------

## The controller selection left with everyone in the middle (owner,
## 2026-10-10: a CPU vs CPU match could be neither paused nor left): a local
## exhibition, pad mode 5, nobody on a team.
func _spectated_session() -> MwSession:
	var session := MwSession.new(1, 1)
	session.local_mode = "exhibition"
	session.humans = MwHumans.new()
	session.humans.apply_to(session.setup)
	session.pad_map = session.humans.pad_players(rom)
	return session


## Every player's pad skips a speech and pauses - whoever's device it is,
## nobody being on a team - into the spectators' menu, which only the
## player who paused answers; no pad reaches a skater.
func test_a_spectated_match_any_player_skips_and_pauses() -> void:
	if not need_rom():
		return
	var session := _spectated_session()
	assert_true(session.spectated(), "everyone in the middle of a local exhibition")
	var rk := _rink(_router(session), 4, {"new_match": true})
	var state := rk.state
	assert_true(state.spectated, "the match knows it")
	assert_eq(state.pad_mode, 5, "the original's CPU v CPU")
	assert_eq(state.fight_block, 0, "not the attract demo")
	for i in 300:
		if state.phase == MwRinkState.PHASE_START and state.subphase == 1:
			break
		rk._screen_pass(2, MwInputFrame.make({}, {}))
	assert_eq(state.subphase, 1, "team A's coach speaks (a CPU team: nobody's to skip in the original)")
	for i in 5:
		rk._screen_pass(2, MwInputFrame.make({}, {}))
	assert_eq(state.subphase, 1, "it goes on without a press")
	rk._screen_pass(2, MwInputFrame.make({"p9_pass": true, "p9_release_puck": true, "p9_change_player": true}, {}))
	assert_ne(state.subphase, 1, "player 9's B skipped it")
	_until_play(rk)
	assert_eq(state.phase, MwRinkState.PHASE_PLAY)
	for p in state.teams[0].players + state.teams[1].players:
		assert_eq(p.flags & MwRinkState.Player.HUMAN, 0, "nobody drives a skater")
	rk._screen_pass(2, MwInputFrame.make({"p7_pause": true}, {}))
	assert_true(rk.phases.paused, "player 7's Start pauses")
	assert_eq(rk.phases.menu["player"], 7)
	assert_eq(rk.phases.menu["items"], Array(MwRinkPhases.SPECTATED_ITEMS),
			"REPLAY, TEAM INFO, QUIT GAME: no TIMEOUT or FORFEIT")
	assert_eq(rk.phases.menu["items"], ["REPLAY", "TEAM INFO", "QUIT GAME"])
	assert_eq(rk.state.pause_offer, 0, "no timeout")
	assert_true(rk.pause_menu.visible, "the port's menu")
	var drawn: Array = rk.pause_menu.get("_layers").filter( \
			func(l: RomPlane) -> bool: return not l.get_used_cells().is_empty())
	assert_eq(drawn.size(), 2 + 3, "PAUSE, PLAYER 7 and the three items drawn")
	_tap(rk, _verb("ui_resume", 1))
	assert_true(rk.phases.paused, "only the player who paused answers")
	_tap(rk, _verb("ui_resume", 7))
	assert_false(rk.phases.paused, "Start resumes")
	assert_eq(state.phase, MwRinkState.PHASE_PLAY)
	rk._screen_pass(2, MwInputFrame.make({"p12_pause": true}, {}))
	assert_true(rk.phases.paused, "player 12 pauses too")
	assert_eq(rk.phases.menu["player"], 12)
	_tap(rk, _verb("ui_back", 12))
	assert_false(rk.phases.paused, "Menu Back resumes")


## QUIT GAME (owner, 2026-10-10: in CPU vs CPU matches only, stopping the
## game at once and going back to the exhibition's game options; ARE YOU
## SURE? as FORFEIT asks) ends the match where it stands and goes back to
## the game setup - no forfeit, no scoreboards, the sounds off; with the
## GENESIS layout the spectators' menu is the port's all the same, its A /
## B picking (Start resumes there).
func test_quit_game_goes_back_to_the_game_options() -> void:
	if not need_rom():
		return
	MwSettings.layouts = {3: "GENESIS"}
	MwInputMap.install()
	var router := _router(_spectated_session())
	var rk := _rink(router, 4, {"new_match": true})
	_until_play(rk)
	rk._screen_pass(2, MwInputFrame.make({"p3_pause": true}, {}))
	assert_true(rk.phases.paused)
	assert_false(rk.phases.menu.is_empty(), "the port's menu for a GENESIS player (the lettered one can't leave)")
	assert_true(rk.pause_menu.visible)
	_tap(rk, _verb("ui_down", 3))
	_tap(rk, _verb("ui_down", 3))
	assert_eq(rk.phases.menu["items"][rk.phases.menu["sel"]], MwRinkPhases.QUIT)
	_tap(rk, _verb("ui_pause_replay", 3))
	assert_true(rk.phases.menu["confirm"], "the lettered menu's A picks: ARE YOU SURE?")
	assert_eq(rk.phases.menu["sure"], 1, "NO selected")
	_tap(rk, _verb("ui_resume", 3).merged(_verb("ui_accept", 3)))
	assert_false(rk.phases.menu["confirm"], "Start goes back to the menu")
	assert_true(rk.phases.paused)
	_tap(rk, _verb("ui_pause_replay", 3))
	_tap(rk, _verb("ui_pause_replay", 3))
	assert_false(rk.phases.menu["confirm"], "NO: back to the menu")
	assert_false(router.busy())
	_tap(rk, _verb("ui_pause_timeout", 3))
	_tap(rk, _verb("ui_up", 3))
	assert_eq(rk.phases.menu["sure"], 0, "YES")
	rk._screen_pass(2, MwInputFrame.make(_verb("ui_pause_timeout", 3), {}))
	assert_false(rk.phases.paused, "the pause is over")
	assert_true(rk.phases.menu.is_empty())
	assert_false(rk.pause_menu.visible, "the menu gone")
	assert_true(["sounds_off"] in rk.sim.events, "every sound off (`$13C04`)")
	assert_true(router.busy(), "leaving")
	assert_eq(router.pending_id(), 1, "for the game setup")
	assert_eq(rk.state.phase, MwRinkState.PHASE_PLAY, "no forfeit")
	assert_false(rk.state.forfeit_manual)
	for i in 120:
		router.step()
		if router.current_id() == 1 and not router.busy():
			break
	assert_eq(router.current_id(), 1, "the game setup")
	assert_true(router.current() is MwMainMenu)
	assert_eq(router.history, [4, 1], "no scoreboard on the way")
	assert_eq(router.session.local_mode, "exhibition", "its exhibition variant")
	MwSettings.layouts = {}
	MwInputMap.install()


## The spectators' REPLAY: the instant replay of the paused match, which
## any player controls and leaves (nobody plays: every pad is everyone's,
## MwBetweenPlays.spectators); then play goes on.
func test_the_spectators_replay_answers_anyone() -> void:
	if not need_rom():
		return
	var router := _router(_spectated_session())
	var rk := _rink(router, 4, {"new_match": true})
	_until_play(rk)
	for i in 60:
		rk._screen_pass(2, MwInputFrame.make({}, {}))     # a few seconds in the replay ring
	rk._screen_pass(2, MwInputFrame.make({"p5_pause": true}, {}))
	assert_eq(rk.phases.menu["items"][rk.phases.menu["sel"]], "REPLAY")
	_tap(rk, _verb("ui_accept", 5))
	assert_true(router.busy(), "off to the instant replay")
	assert_eq(router.pending_id(), 7)
	for i in 200:
		router.step()
		if router.current_id() == 7 and not router.busy():
			break
	assert_eq(router.current_id(), 7)
	var keys := _Keys.new()
	router.input = keys
	var exit := MwVerbs.pad_actions(10, 0x80, MwScreens.contexts(7))
	var back := false
	for i in 600:
		keys.held = exit if i % 30 < 4 else {}
		router.step()
		if router.current_id() == 6:
			back = true
			break
	assert_true(back, "player 10's Start left the replay: play goes on")


const _Keys := preload("res://test/support/pad.gd")
