extends "res://test/rom/rom_test_base.gd"
## Plan 34: the game setup's port variants, EXHIBITION and PLAYOFFS - no
## pads or play mode rows, the rows moved up, SERIES in the playoffs'
## stadium slot, PLAY GAME / SAVE GAME, a run keeping its teams, the
## question before leaving a run, and the top graphic's slam.
## Short names: m the MwMainMenu under test.

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad
var _front := true


func before_all() -> void:
	super.before_all()
	_front = MwSettings.front_menu
	MwSettings.front_menu = true


func after_all() -> void:
	MwSettings.front_menu = _front


func after_each() -> void:
	if host:
		rig.free_host()
		host = null


func _start(mode: String, prepare := Callable()) -> MwMainMenu:
	router = rig.make(self, MwSession.new(1, 1))
	host = rig.host
	router.session.local_mode = mode
	if prepare.is_valid():
		prepare.call(router.session)
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(1)
	scene.screen_id = 1
	router.adopt(scene)
	router.fader.uncover()
	return scene as MwMainMenu


func _run(ticks: int) -> void:
	rig.run(ticks)


func _press(action: String, after := 10) -> void:
	rig.hold({action: true, "p1_" + action: true}, 3, after)


func _until(id: int, limit := 600) -> bool:
	return rig.until(id, limit, 0)


func test_exhibition_rows() -> void:
	if not need_rom():
		return
	var m := _start("exhibition")
	_run(30)
	assert_eq(m.variant, "exhibition")
	assert_eq(router.session.setup.play_mode, MwPlayoffs.MODE_REGULAR)
	assert_false(m._shown(MwMenuRows.PADS_ROW), "no pads row (owner)")
	assert_false(m._shown(MwMenuRows.PLAY_MODE_ROW), "no play mode row")
	assert_eq(m.rows.item(MwMenuRows.PERIOD_ROW, 0)["y"], 16, "the period length in the play mode's slot")
	assert_eq(m.rows.item(9, 0)["y"], 24, "the death index a slot up")
	var seen := [m.row]
	for i in 7:
		_press("ui_down", 4)
		seen.append(m.row)
	assert_eq(seen, [0, 4, 6, 7, 8, 9, MwMainMenu.ACTION_ROW, MwMainMenu.ACTION_ROW],
			"down through the rows to PLAY GAME")
	_press("ui_up", 4)
	assert_eq(m.row, 9)
	var labels := MwPlanePainter.FONT_SMALL
	assert_ne(labels, 0)


func test_play_game_starts_an_exhibition() -> void:
	if not need_rom():
		return
	var m := _start("exhibition")
	_run(30)
	while m.row != MwMainMenu.ACTION_ROW:
		_press("ui_down", 2)
	_press("ui_accept", 0)
	assert_true(_until(MwScreens.CONTROLLER_SELECT), "PLAY GAME -> the controller selection (plan 34)")
	_run(4)
	_press("ui_accept", 0)
	assert_true(_until(3), "then the matchup")
	assert_eq(router.session.playoffs.flags & MwPlayoffs.NEW, 0, "no run")


## Plan 34: any other player's Left / Right edits team B (the original's
## P3 / P4) - in an extended set-up players 5-12 too; in the original's
## set-ups a player on none of pads 1-4 edits nothing.
func test_players_5_to_12_edit_team_b_in_an_extended_set_up() -> void:
	if not need_rom():
		return
	for extended in [false, true]:
		_start("exhibition", func(session: MwSession) -> void:
			session.humans = MwHumans.new()
			session.humans.set_team(1, 0)
			session.humans.set_team(2, 1)
			if extended:
				session.humans.set_team(9, 1)
				session.humans.set_team(10, 1)
			session.pad_map = session.humans.pad_players(rom))
		_run(30)
		var b := router.session.setup.team_b
		pad.held = {"p9_ui_right": true}
		_run(3)
		pad.held = {}
		_run(10)
		if extended:
			assert_ne(router.session.setup.team_b, b, "1 v 3: player 9's Right edits team B")
		else:
			assert_eq(router.session.setup.team_b, b, "1 v 1: player 9 (not playing) on no pad")
		host.free()
		host = null


func test_playoffs_series_and_a_new_run() -> void:
	if not need_rom():
		return
	var m := _start("playoffs")
	_run(30)
	assert_eq(router.session.setup.play_mode, MwPlayoffs.MODE_PLAYOFFS)
	assert_false(m._shown(MwMainMenu.STADIUM_ROW), "the series picks the stadium (owner)")
	assert_lt(router.session.setup.team_a, 20, "conference teams only, as the original's playoffs")
	_press("ui_down", 4)
	_press("ui_down", 4)
	assert_eq(m.row, MwMainMenu.SERIES_ROW, "SERIES after the period length")
	_press("ui_right", 4)
	assert_eq(router.session.setup.play_mode, MwPlayoffs.MODE_BEST_OF_3, "best of 3")
	_press("ui_left", 4)
	assert_eq(router.session.setup.play_mode, MwPlayoffs.MODE_PLAYOFFS)
	_press("ui_right", 4)
	assert_false(m.can_save(), "no SAVE GAME before a game")
	_press("ui_accept", 0)                       # Start on any row plays
	assert_true(_until(11), "a new run: its bracket")
	assert_true(router.session.run_started)
	assert_eq(router.session.playoffs.best_of_3, 1)
	assert_ne(router.session.playoffs.flags & MwPlayoffs.NEW, 0)


func test_a_run_in_progress_keeps_its_teams_and_offers_save() -> void:
	if not need_rom():
		return
	var m := _start("playoffs", func(session: MwSession) -> void:
		session.setup.team_a = 3
		session.setup.team_b = 7
		session.setup.play_mode = MwPlayoffs.MODE_PLAYOFFS
		session.playoffs.start(session.setup, session.rng)
		session.run_started = true
		session.run_games = 1)
	_run(30)
	assert_true(m.locked())
	assert_true(m.can_save())
	assert_eq(m.row, MwMainMenu.ACTION_ROW, "back from a game: on PLAY GAME")
	assert_eq([router.session.setup.team_a, router.session.setup.team_b], [3, 7], "the teams kept")
	for i in 8:
		_press("ui_up", 2)
	assert_eq(m.row, MwMenuRows.PERIOD_ROW, "the teams can't be reached")
	_press("ui_down", 2)
	_press("ui_right", 4)
	assert_eq(router.session.setup.play_mode, MwPlayoffs.MODE_PLAYOFFS, "the series kept")
	while m.row != MwMainMenu.ACTION_ROW:
		_press("ui_down", 2)
	assert_eq(m.action, 0, "PLAY GAME")
	_press("ui_left", 4)
	assert_eq(m.action, 1, "SAVE GAME")
	_press("ui_accept", 0)
	assert_true(_until(MwScreens.SAVED_GAMES), "SAVE GAME -> the saved games")


func test_leaving_a_run_asks_first() -> void:
	if not need_rom():
		return
	var m := _start("playoffs", func(session: MwSession) -> void:
		session.setup.play_mode = MwPlayoffs.MODE_PLAYOFFS
		session.run_started = true)
	_run(30)
	_press("ui_back", 4)
	assert_true(m.confirm.active, "ARE YOU SURE?")
	assert_eq(m.confirm.sure, 1, "NO first")
	_press("ui_accept", 20)
	assert_false(m.confirm.active)
	assert_eq(router.current_id(), 1, "NO: stays")
	assert_true(router.session.run_started)
	_press("ui_back", 4)
	_press("ui_up", 4)
	assert_eq(m.confirm.sure, 0)
	_press("ui_accept", 0)
	assert_true(_until(MwScreens.LOCAL_PLAY), "YES: LOCAL PLAY")
	assert_false(router.session.run_started, "the run let go")


func test_exhibition_back_goes_to_local_play() -> void:
	if not need_rom():
		return
	var m := _start("exhibition")
	_run(30)
	_press("ui_skip", 4)                         # landed at once
	assert_null(m.slam)
	var text: CanvasItem = m.plane.lower.get_parent()
	var sounds: Array = []
	MwSound.trace = func(what: String, args: Array, _r: Variant) -> void: sounds.append([what, args])
	pad.held = {"ui_back": true, "p1_ui_back": true}
	router.step()                                 # sampled: the next pass sees it
	pad.held = {}
	router.step()
	assert_eq(router.current_id(), 1, "the top rises first (owner)")
	assert_has(sounds, ["fm_effect", [MwBrickWall.SOUND]], "to the gate's clinks, as 110's wall (owner)")
	var covered := 0.0
	var highest := 0.0
	var heights: Array[float] = []
	for i in MwMainMenu.LIFT_TICKS - 1:
		router.step()
		covered = maxf(covered, router.fader.coverage())
		highest = maxf(highest, -m.plane.position.y)
		heights.append(-m.plane.position.y)
	MwSound.trace = Callable()
	assert_eq(router.current_id(), 1)
	assert_almost_eq(highest, float(MwPortMenu.TOP_HANG), 8.0, "up to where the pages hang it")
	assert_lt(heights[2] - heights[0], heights[-1] - heights[-3], "faster and faster")
	assert_does_not_have(sounds, ["fm_effect_stop", []], "the clinks ring on")
	assert_eq(text.modulate.a, 0.0, "the menu's text faded out")
	assert_eq(m.logo_plane.position, Vector2.ZERO, "the logo stays (the window rises in front of it)")
	assert_true(_until(MwScreens.LOCAL_PLAY, 20))
	assert_eq(covered, 0.0, "a cut, no fade")
	var lp := router.current() as MwPortMenu
	assert_true(lp.top.visible, "LOCAL PLAY: the top hanging there")
	assert_eq(lp.top.position.y, -float(MwPortMenu.TOP_HANG))


## Owner, 2026-10-12: a star's voice on the game setup played on after
## backing out - now faded out quickly: Menu Back fades the panels'
## voices (MwPortrait.quiet: the driver stops them, the mix fades them over
## VOICE_FADE_TICKS) and the panels start no more while the top rises.
func test_back_fades_a_stars_voice() -> void:
	if not need_rom():
		return
	var m := _start("exhibition")
	_run(30)
	_press("ui_skip", 4)
	var star := m.panels[0].portrait
	star.set_player(MwRom.data(), MwTeams.player(MwRom.data(), m.panels[0].team, 0), 2)
	star.start(0)
	var voice := -1
	for i in 120:
		router.step()
		star.advance(1)                           # (talking now, whatever the panel's cycle shows)
		if MwSound.busy(star.voice):
			voice = star.voice
			break
	assert_ne(voice, -1, "talking: its voice playing")
	var sounds: Array = []
	MwSound.trace = func(what: String, args: Array, r: Variant) -> void: sounds.append([what, args, r])
	pad.held = {"ui_back": true, "p1_ui_back": true}
	router.step()
	pad.held = {}
	router.step()
	var faded := false
	for c: Array in sounds:
		faded = faded or (c[0] == "fade_out" and int(c[1][0]) == voice and int(c[1][1]) == MwMainMenu.VOICE_FADE_TICKS)
	assert_true(faded, "its voice faded out")
	assert_false(MwSound.busy(voice), "stopped in the driver")
	for panel in m.panels:
		assert_true(panel.portrait.muted, "the panels start no more")
	sounds.clear()
	for i in 40:
		router.step()
	MwSound.trace = Callable()
	var again := false
	var id := MwGfx.u16(MwRom.data(), star.data + 8)
	for c: Array in sounds:
		again = again or (c[0] == "play" and int(c[1][0]) == id)
	assert_false(again, "no voice again while leaving")


func test_the_top_graphic_slams_in() -> void:
	if not need_rom():
		return
	var m := _start("exhibition")
	router.fader.cover()
	router.fader.fade_in(32)
	_run(10)
	assert_not_null(m.slam, "falling")
	assert_eq(m.slam.height(), MwSlam.HEIGHT, "held up there while the screen fades in")
	assert_eq(m.plane.position.y, -float(MwSlam.HEIGHT), "the window's layer with it")
	assert_eq(m.panels[0].position.y, -float(MwSlam.HEIGHT), "and the panels")
	_run(40)
	assert_lt(m.slam.height() if m.slam else 0, MwSlam.HEIGHT, "falls once faded in")
	var shook := false
	var thuds := 0
	var still := true
	var over := false
	var bounces := 0
	var falling := true
	var last := -1
	var jump := 0
	for i in 300:
		router.step()
		if m.slam and m.slam.thud:
			thuds += 1
		if m.plane.position.x != 0:
			shook = true
		if m.position.x != 0 or m.starfield.position.x != 0 or m.plane.lower.get_parent().position.x != 0:
			still = false
		if m.logo_plane.position != Vector2.ZERO:
			still = false
		var h := -int(m.plane.position.y)
		if last >= 0:
			jump = maxi(jump, absi(h - last))
			if falling and h > last:
				bounces += 1                         # back up off the floor
			if h != last:
				falling = h < last
		last = h
		if m.logo_plane.get_index() > m.plane.get_index():
			over = true
		if m.slam == null:
			break
	assert_null(m.slam, "settled")
	assert_eq(thuds, 2, "a crash on each bounce (owner)")
	assert_true(shook, "the top shook while it bounced")
	assert_true(still, "the stars, the menu's text and the logo stay (owner)")
	assert_eq(bounces, 2, "it bounces twice, then lands (owner: no snap)")
	assert_lt(jump, 20, "never a snap: no more than a pass's fall between frames")
	assert_false(over, "the logo always under the window, never on top (owner)")
	assert_eq(m.plane.position, Vector2.ZERO, "in place")


func test_a_press_lands_the_graphic_at_once() -> void:
	if not need_rom():
		return
	var m := _start("exhibition")
	_run(20)                                      # past the original's 14 ticks of loading
	assert_not_null(m.slam)
	_press("ui_skip", 0)
	assert_null(m.slam)
	assert_eq(m.plane.position.y, 0.0)


func test_the_slam_matches_face_off() -> void:
	# FACE OFF!'s drop (docs/re/phases.md 4.4) at the port's 2-tick passes:
	# 180 px under -24/256 px per tick squared reach the floor in about 62
	# ticks (31 passes), the bounces settle about 20 ticks later
	var slam := MwSlam.new()
	var passes := 0
	var first_floor := -1
	while not slam.done and passes < 200:
		slam.advance(MwSlam.PASS_TICKS)
		passes += 1
		if first_floor < 0 and slam.thud:
			first_floor = passes
	assert_between(first_floor, 31, 33, "the first bounce")
	assert_between(passes, 38, 45, "settled")


## The game setup's top (owner: a clean bounce, no snap): from the top of
## a bounce it falls back and bounces again, each a quarter as high, until a
## bounce would be slower than 1 px a tick; then it is on the floor.
func test_the_game_setups_top_bounces_and_lands() -> void:
	var slam := MwSlam.new()
	slam.bounces = true
	var passes := 0
	var first_floor := -1
	var tops: Array[int] = []
	var last := slam.height()
	var rising := false
	var jump := 0
	while not slam.done and passes < 300:
		slam.advance(MwSlam.PASS_TICKS)
		passes += 1
		if first_floor < 0 and slam.thud:
			first_floor = passes
		var h := slam.height()
		jump = maxi(jump, absi(h - last))
		if rising and h < last:
			tops.append(last)
		rising = h > last if h != last else rising
		last = h
	assert_between(first_floor, 31, 33, "the first bounce as FACE OFF!'s")
	assert_eq(tops.size(), 2, "two bounces (%s)" % str(tops))
	assert_between(tops[0], 40, 50, "the first about a quarter of the drop")
	assert_between(tops[1], 9, 15, "the second a quarter of that")
	assert_lt(jump, 20, "no snap")
	assert_between(passes, 75, 85, "settled on the floor")


func test_the_logo_stays_put_and_the_frame_has_a_hole() -> void:
	if not need_rom():
		return
	var m := _start("exhibition")
	_run(20)
	assert_not_null(m.logo_plane, "the logo on a layer of its own")
	var r := MwPortMenu.LOGO
	var filled := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if int(m.logo_plane.cell(x, y)["key"]) != 0:
				filled += 1
			assert_true(int(m.plane.cell(x, y)["key"]) in [0, m.plane.cell(0, 0).get("blank", -1)] \
					or (int(m.plane.cell(x, y)["key"]) & 0x7FF) == 0, "the window's hole at (%d, %d)" % [x, y])
	assert_gt(filled, 40, "the logo's cells")
	assert_eq(MwPortMenu.LOGO_AT, r.position, "where the port's menus draw it (owner: consistent)")
	assert_true(m.slam != null and m.slam.height() > 0)
	assert_eq(m.logo_plane.position.y, 0.0, "still while the frame falls")
	assert_lt(m.logo_plane.get_index(), m.plane.get_index(), "the frame falls in front of it")


func test_local_play_cuts_to_the_game_setup() -> void:
	if not need_rom():
		return
	router = rig.make(self, MwSession.new(1, 1))
	host = rig.host
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(MwScreens.LOCAL_PLAY)
	scene.screen_id = MwScreens.LOCAL_PLAY
	router.adopt(scene)
	router.fader.uncover()
	_run(40)
	var before := (router.current() as MwPortMenu).starfield
	var vel := Vector2i(before.vx, before.vy)
	var star_at := (before.get_child(0) as Node2D).position
	pad.held = {"ui_accept": true}
	var covered := 0.0
	var faded := false
	for i in MwMenuCut.FADE_TICKS + 6:
		var lp := router.current() as MwPortMenu
		if lp != null:
			star_at = (lp.starfield.get_child(0) as Node2D).position
			faded = faded or lp.page_layers.self_modulate.a == 0.0
		router.step()
		covered = maxf(covered, router.fader.coverage())
		if router.current_id() == 1:
			break
		if i == 3:
			pad.held = {}
	pad.held = {}
	assert_eq(router.current_id(), 1, "EXHIBITION: the game setup once LOCAL PLAY's text has faded")
	assert_true(faded, "LOCAL PLAY's text faded out first (owner)")
	assert_eq(covered, 0.0, "a cut, no fade (owner: the logo lines up)")
	var m := router.current() as MwMainMenu
	assert_eq(Vector2i(m.starfield.vx, m.starfield.vy), vel, "the starfield goes on the same way")
	var drawn := (m.starfield.get_child(0) as Node2D).position
	assert_almost_eq(drawn.x, star_at.x, 2.0, "drawn where LOCAL PLAY left it - no flash (owner)")
	assert_almost_eq(drawn.y, star_at.y, 2.0)
	assert_ne(m.starfield.palette, m.palette, "the stars in their own colours (owner)")
	assert_eq(Array(m.starfield.palette.steps), ["screen_palette", "black 0"], "not the torchlight's line 3")
	assert_not_null(m.slam)
	assert_between(m.slam.height(), MwPortMenu.TOP_HANG - 4, MwPortMenu.TOP_HANG,
			"the top falls from where LOCAL PLAY hung it (owner)")
	var text: CanvasItem = m.plane.lower.get_parent()
	assert_lt(text.modulate.a, 0.5, "the menu's text fading in")
	_run(MwMainMenu.TEXT_FADE_TICKS)
	assert_eq(text.modulate.a, 1.0)
