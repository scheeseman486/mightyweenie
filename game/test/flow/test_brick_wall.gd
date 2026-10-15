extends "res://test/rom/rom_test_base.gd"
## Plan 34 (owner): the controller selection's opening ([MwBrickWall]) -
## the panels hold their logos, the logo backgrounds fade, the top rises
## off the screen in front of the logos, names and title left in place
## (layers under the window, holes in it), the gate's clinks - and its
## mirror on the way back to the game setup (the slam, the backgrounds
## fading back in, everything back in the window); the black strip above
## the arch's skull see-through; input during it; the torchlight across the
## cuts.

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad
var calls: Array = []
var _front := true


func before_all() -> void:
	super.before_all()
	_front = MwSettings.front_menu
	MwSettings.front_menu = true


func after_all() -> void:
	MwSettings.front_menu = _front


func before_each() -> void:
	calls = []
	MwSound.trace = func(what: String, args: Array, _result: Variant) -> void: calls.append([what, args])


func after_each() -> void:
	MwSound.trace = Callable()
	if host:
		rig.free_host()
		host = null


## Screen [param id] adopted (the fader uncovered unless [param fade_in]),
## player 1 in the middle (Back goes back from 110).
func _start(id: int, fade_in := false) -> MwMainMenu:
	router = rig.make(self, MwSession.new(1, 1))
	host = rig.host
	router.session.local_mode = "exhibition"
	router.session.humans = MwHumans.new()
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(id)
	scene.screen_id = id
	router.adopt(scene)
	if fade_in:
		router.fader.cover()
		router.fader.fade_in(32)
	else:
		router.fader.uncover()
	return scene as MwMainMenu


func _run(ticks: int) -> void:
	rig.run(ticks)


## Two ticks: the input sampled after the first one's pass, the second's
## pass sees the press.
func _press(action: String, player := 1) -> void:
	rig.hold({action: true, "p%d_%s" % [player, action]: true}, 2, 0)


func _menu() -> MwMainMenu:
	return router.current() as MwMainMenu


func _names() -> Array:
	return calls.map(func(c: Array) -> String: return c[0])


func test_the_panels_hold_their_logos() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT)
	_run(400)                                     # longer than a logo phase (180 ticks)
	for panel in m.panels:
		assert_true(panel.held, "held (owner: the animation stops first)")
		assert_true(panel.logo.visible and panel.ring.visible, "the team's logo")
		assert_false(panel.skater.visible, "no skater")
		assert_false(panel.portrait.visible, "no portrait")
		assert_false(panel.team_colours, "the panel colours")


func test_the_opening_fades_then_rises() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT)
	var w := m.wall
	assert_not_null(w)
	var logo_at := m.panels[0].logo.global_position
	var title_at := w.title.global_position
	var alphas: Array[float] = []
	var heights: Array[int] = []
	var rise_tick := -1
	for t in 70:
		router.step()
		alphas.append(w.backs.modulate.a)
		heights.append(w.height)
		if rise_tick < 0 and "fm_effect" in _names():
			rise_tick = t
		assert_eq(m.plane.position.y, -float(w.height), "tick %d: the window at the wall's height" % t)
		assert_eq(m.torches[0].position.y - w._group_y[3], -float(w.height), "the torches with it")
		assert_eq(m.panels[1].position.y, -float(w.height), "the panels (their skulls) with it")
	var fade := MwBrickWall.FADE_TICKS
	assert_almost_eq(alphas[fade / 2 - 1], 0.5, 0.06, "half faded at 1/6 s")
	assert_eq(heights[fade - 2], 0, "no rise while the backgrounds fade")
	assert_eq(alphas[fade - 1], 0.0, "faded out after %d ticks" % fade)
	assert_eq(rise_tick, fade - 1, "the gate's clinks start with the rise")
	assert_eq(calls[_names().find("fm_effect")], ["fm_effect", ["gate"]])
	for t in range(fade, fade + MwBrickWall.RISE_TICKS):
		assert_lte(heights[t - 1], heights[t], "rising")
	var d1 := heights[fade + 5] - heights[fade + 4]
	var d2 := heights[fade + 25] - heights[fade + 24]
	assert_gt(d2, d1, "faster and faster")
	assert_eq(heights[fade + MwBrickWall.RISE_TICKS - 1], MwBrickWall.HEIGHT, "off the top after 1/2 s")
	assert_eq(w.phase, MwBrickWall.Phase.UP)
	assert_eq(m.panels[0].logo.global_position, logo_at, "the team logos stay")
	assert_eq(w.title.global_position, title_at, "the title plate stays (owner)")
	assert_eq(m.logo_plane.position, Vector2.ZERO, "the logo stays")


func test_what_stays_is_under_the_window() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT)
	_run(2)
	var w := m.wall
	var window := m.plane.get_index()
	for n: Node in [m.logo_plane, w.backs, w.logos, w.names, w.title]:
		assert_eq(n.get_parent(), m)
		assert_lt(n.get_index(), window, "%s under the window: it passes in front" % n.name)
	assert_lt(w.backs.get_index(), w.logos.get_index(), "the backgrounds under the logos")
	for panel in m.panels:
		assert_eq(panel.logo.get_parent(), w.logos, "the team's logo on the logos' layer")
		assert_eq(panel.ring.get_parent(), w.logos)
		assert_gt(panel.get_index(), window, "the panels (their skulls) rise with the window")
	assert_eq(m.select.get_node_or_null("Title"), null, "the plate is no longer the lines' layer")
	assert_eq(w.title.name, "Title")


func test_holes_where_the_layers_show() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT)
	_run(2)
	var w := m.wall
	for r: Rect2i in MwBrickWall.BACKS:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				assert_eq(int(m.plane.cell(x, y)["key"]), 0, "the window's hole at (%d, %d)" % [x, y])
				assert_ne(int(w.backs.cell(x, y)["key"]), 0, "the background's cell on its layer")
	var glyphs := 0
	for r: Rect2i in MwBrickWall.NAMES:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if int(w.names.cell(x, y)["key"]) != 0:
					glyphs += 1
					assert_eq(int(m.plane.cell(x, y)["key"]), 0, "a hole for the name's glyph at (%d, %d)" % [x, y])
				else:
					assert_lt(int(m.plane.cell(x, y)["key"]), MwBrickWall.GLYPH_KEYS, "no glyph left in the window")
	assert_gt(glyphs, 6, "both names' glyphs")
	assert_ne(int(m.plane.cell(5, 1)["key"]) + int(m.plane.cell(13, 11)["key"]), 0, "the other black areas stay")


func test_the_strip_above_the_skull_is_see_through() -> void:
	if not need_rom():
		return
	for id in [MwScreens.CONTROLLER_SELECT, 1]:
		var m := _start(id)
		_run(20)
		var k := MwMainMenu.SKULL_STRIP
		for x in range(k.position.x, k.end.x):
			assert_eq(int(m.plane.cell(x, k.position.y)["key"]), 0,
					"screen %d: a hole at (%d, %d)" % [id, x, k.position.y])
		assert_ne(int(m.plane.cell(k.position.x - 2, k.position.y)["key"]), 0,
				"screen %d: the strip under the panel stays" % id)
		assert_ne(int(m.plane.cell(k.position.x + 3, k.position.y + 2)["key"]), 0, "screen %d: the arch stays" % id)
		host.free()
		host = null


func test_from_the_bracket_it_waits_for_the_fade_in() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT, true)
	_run(10)
	assert_eq(m.wall.phase, MwBrickWall.Phase.WAIT, "still fading in")
	assert_eq(m.wall.backs.modulate.a, 1.0)
	_run(40)
	assert_ne(m.wall.phase, MwBrickWall.Phase.WAIT, "faded in: the opening")


func test_the_way_back_is_the_mirror() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT)
	_run(80)
	assert_eq(m.wall.phase, MwBrickWall.Phase.UP)
	var title_at := m.wall.title.global_position
	_press("ui_back")
	_run(1)
	var g := _menu()
	assert_eq(g.screen_id, 1, "player 1's Back in the middle: the game setup (a cut)")
	var w := g.wall
	assert_not_null(w, "the wall comes back")
	assert_not_null(g.slam, "with the slam")
	assert_gt(g.slam.height(), MwBrickWall.HEIGHT - 8, "from the top")
	assert_eq(w.phase, MwBrickWall.Phase.FALL)
	assert_eq(w.backs.modulate.a, 0.0, "the backgrounds still faded")
	assert_eq(w.title.global_position, title_at, "the title behind it, where it was")
	for n: Node in [w.backs, w.logos, w.names, w.title]:
		assert_lt(n.get_index(), g.plane.get_index(), "%s under the falling window" % n.name)
	for team_panel in g.panels:
		assert_true(team_panel.held, "the panels hold their logos")
	var landed := -1
	for t in 200:
		router.step()
		if landed < 0 and g.slam == null:
			landed = t
			assert_not_null(g.wall, "landed: the backgrounds fade back in")
			assert_lt(g.wall.backs.modulate.a, 1.0)
		if g.wall == null:
			break
	assert_eq(calls.count(["play", [MwSlam.THUD]]), 1, "the slam's thud")
	assert_null(g.wall, "done")
	assert_eq(g.position.x, 0.0)
	assert_eq(g.plane.position.y, 0.0)
	for panel in g.panels:
		assert_false(panel.held, "the panels take up their cycle")
		assert_eq(panel.logo.get_parent(), panel, "the logo back in its panel")
		assert_eq(panel.ring.get_index(), 0)
	for r: Rect2i in MwBrickWall.BACKS:
		assert_ne(int(g.plane.cell(r.position.x + 2, r.position.y + 4)["key"]), 0, "the background back in the window")
	assert_null(g.find_child("Title", true, false), "the title gone")
	assert_null(g.find_child("TeamNames", true, false))
	var glyphs := 0
	for y in range(0, 4):
		for x in range(4, 14):
			if int(g.plane.cell(x, y)["key"]) >= MwBrickWall.GLYPH_KEYS:
				glyphs += 1
	assert_gt(glyphs, 3, "team A's name back in the window")


func test_back_mid_rise_falls_from_there() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT)
	_run(MwBrickWall.FADE_TICKS + 20)
	assert_eq(m.wall.phase, MwBrickWall.Phase.RISE)
	_press("ui_back")
	var h := m.wall.height
	assert_eq(m.wall.phase, MwBrickWall.Phase.RISE, "Back mid-rise")
	assert_gt(h, 30)
	assert_has(_names(), "fm_effect_stop", "the clinks stop")
	_run(1)
	var g := _menu()
	assert_eq(g.screen_id, 1)
	assert_not_null(g.slam)
	assert_between(g.slam.height(), h - 2, h, "the fall from the rise's height")
	_press("ui_skip")
	assert_null(g.slam, "a press: in place at once")
	assert_null(g.wall, "the backgrounds in, merged")
	for panel in g.panels:
		assert_false(panel.held)


func test_back_during_the_fade_fades_back_in() -> void:
	if not need_rom():
		return
	_start(MwScreens.CONTROLLER_SELECT)
	_run(MwBrickWall.FADE_TICKS / 2)
	_press("ui_back")
	_run(1)
	var g := _menu()
	assert_eq(g.screen_id, 1)
	assert_null(g.slam, "the wall had not moved: no slam")
	assert_not_null(g.wall)
	assert_eq(g.wall.phase, MwBrickWall.Phase.FADE_IN)
	_run(MwBrickWall.FADE_TICKS + 2)
	assert_null(g.wall, "faded back in")


func test_the_lines_move_during_the_opening() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT)
	_run(MwBrickWall.FADE_TICKS + 5)
	assert_eq(m.wall.phase, MwBrickWall.Phase.RISE)
	_press("ui_left")
	assert_eq(router.session.humans.team_of(1), 0, "player 1's Left during the rise: team A")
	_run(3)
	assert_eq(m.wall.phase, MwBrickWall.Phase.RISE, "the rise goes on")


func test_other_entries_keep_the_slam() -> void:
	if not need_rom():
		return
	var m := _start(1)
	_run(20)
	assert_null(m.wall, "no wall from elsewhere")
	assert_not_null(m.slam, "the top falls in whole")
	assert_eq(m.panels[0].logo.get_parent(), m.panels[0])
	for panel in m.panels:
		assert_false(panel.held)


func test_the_torchlight_goes_on_across_the_cuts() -> void:
	if not need_rom():
		return
	var m := _start(MwScreens.CONTROLLER_SELECT)
	_run(400)
	var before := [m.flicker, m.torches[0].state.position, m.torches[1].state.position]
	assert_true(m._flickered, "the light has flickered by now")
	_press("ui_back")
	_run(1)
	var g := _menu()
	assert_eq(g.screen_id, 1)
	assert_eq(g.flicker, before[0], "line 3's palette kept")
	assert_true(g._flickered)
	assert_ne(g.torches[0].state.position, 0, "the torches' animation goes on")
	assert_lte(absi(g.torches[0].state.position - int(before[1])), 0x200, "where it was")
	assert_ne(g.torches[1].state.position, MwMainMenu.TORCH_SECOND_START)
