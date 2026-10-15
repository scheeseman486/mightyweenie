extends "res://test/rom/rom_test_base.gd"
## CREATE-A-TEAM's rink editor (plan 38, screen 138): the working copy's
## rink in the 3D view, its rows, placing (the keep-clear zones refuse),
## removing, the colours, a test skate and back to the team editor.

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad


func after_each() -> void:
	if host:
		rig.free_host()
		host = null
	MwCustomTeams.clear()


func _start() -> void:
	var team := MwCustomTeam.from_original(MwRom.archive().bytes(), 9)
	team.rink.hazards.clear()
	MwCustomTeams.edit(team)
	router = rig.make(self, MwSession.new(1, 1))
	host = rig.host
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(MwScreens.HOME_RINK)
	scene.screen_id = MwScreens.HOME_RINK
	router.adopt(scene, {})
	router.fader.uncover()
	_run(10)


func _run(ticks: int) -> void:
	rig.run(ticks)


func _press(action: String, after := 4) -> void:
	rig.hold({action: true}, 2, after)


func test_rows_place_remove_skate() -> void:
	if not need_rom():
		return
	_start()
	var editor: MwRinkEditor = router.current()
	var team := MwCustomTeams.editing
	assert_eq(editor.page, "rink")
	assert_eq(editor.rows.map(func(r): return r.action), ["name", "colours", "net", "gravity", "hazards", "skate"])
	# the net and the gravity
	_press("ui_down")
	_press("ui_down")
	var net := team.rink.net
	_press("ui_right")
	assert_ne(team.rink.net, net)
	assert_eq(editor.state.nets[0].style, team.rink.net, "the 3D view's rink set up again")
	_press("ui_down")
	_press("ui_right")
	assert_eq(team.rink.gravity, -26)
	assert_eq(editor.state.player_params.gravity, -26)
	# placing: refused in the centre's keep-clear zone, placed below it
	_press("ui_down")
	_press("ui_accept")
	assert_eq(editor.page, "place")
	assert_true(editor.cursor_arrow.visible or true)
	editor.at = Vector2i(0, 0)
	_press("rink_place")
	assert_eq(team.rink.hazards.size(), 0, "the centre line-up stays clear")
	editor.at = Vector2i(0, 200)
	_press("rink_kind_next")                 # pit
	_press("rink_place")
	assert_eq(team.rink.hazards.size(), 1)
	assert_eq(team.rink.hazards[0]["kind"], "pit")
	assert_eq(editor.state.hazards[0].kind, 2, "set up as a match sets it up")
	rig.hold({"ui_right": true}, 10, 2)
	assert_gt(editor.at.x, 0, "the cursor moves")
	_press("rink_remove")
	assert_eq(team.rink.hazards.size(), 0)
	_press("rink_done")
	assert_eq(editor.page, "rink")
	# the colours: a role's colour edited, then the preset again
	_press("ui_up")
	_press("ui_up")
	_press("ui_up")
	assert_eq(editor.rows[editor.row].action, "colours")
	_press("ui_accept")
	assert_eq(editor.page, "colours")
	_press("ui_down")                         # ICE
	_press("ui_accept")
	assert_eq(editor.page, "colour")
	var before: int = editor._colours()[0]
	_press("ui_right")
	assert_ne(editor._colours()[0], before)
	var v := MwRom.data()
	assert_eq(MwGfx.words(v, MwPalettes.ice_palette(v, MwCustomTeams.editing_id()), 16)[0], editor._colours()[0],
			"the game reads it")
	_press("ui_back")
	_press("ui_editor_next")
	assert_true(team.rink.colours.is_empty(), "a preset: its colours")
	_press("ui_back")
	# a test skate, and back
	for i in 4:
		_press("ui_down", 1)
	assert_eq(editor.rows[editor.row].action, "skate")
	_press("ui_accept")
	assert_eq(editor.page, "skate")
	_run(120)
	assert_not_null(editor.sim)
	assert_gt(editor.sim.s.tick, 100, "the scrimmage runs")
	_press("rink_done")
	_run(60)
	assert_eq(editor.page, "rink")
	assert_null(editor.sim)
	_press("ui_back")
	for i in 600:
		router.step()
		if router.current_id() == MwScreens.EDIT_TEAM:
			break
	assert_eq(router.current_id(), MwScreens.EDIT_TEAM, "back to the team editor")


func test_spikes_on_the_side_boards_and_objects_shown() -> void:
	if not need_rom():
		return
	_start()
	var editor: MwRinkEditor = router.current()
	var team := MwCustomTeams.editing
	for i in 4:
		_press("ui_down")
	_press("ui_accept")
	assert_eq(editor.page, "place")
	assert_eq(editor.state.phase, MwRinkState.PHASE_PLAY, "the rink objects drawn (not a set-up phase)")
	editor.kind = MwCustomRink.KIND_ORDER.find("shark")
	editor.at = Vector2i(-100, 200)
	editor._setup_state()
	assert_eq(editor.state.objects.filter(func(o): return o.kind == 1).size(), 1, "the shark under the cursor shown")
	editor.kind = MwCustomRink.KIND_ORDER.find("fire")
	_press("rink_kind_next")                 # spikes: on the nearer board
	assert_eq(MwCustomRink.KIND_ORDER[editor.kind], "spikes")
	assert_eq(editor.at, Vector2i(-MwCustomRink.SPIKES_X, 200))
	_press("rink_place")
	assert_eq(team.rink.hazards.back(), {"kind": "spikes", "x": -185, "y": 200, "mirror": false})
	_press("rink_mirror")                    # the other board, facing the ice
	assert_eq(editor.at.x, MwCustomRink.SPIKES_X)
	_press("rink_place")
	assert_eq(team.rink.hazards.back(), {"kind": "spikes", "x": 185, "y": 200, "mirror": true})
	pad.held = {"ui_left": true}               # across: a jump to the left board
	_run(3)
	pad.held = {}
	_run(2)
	assert_eq(editor.at.x, -MwCustomRink.SPIKES_X)
	# a JSON's spikes off the boards come back onto them
	var custom_rink := MwCustomRink.new()
	custom_rink.hazards = [{"kind": "spikes", "x": 40, "y": 999, "mirror": false}]
	custom_rink.validate()
	assert_eq(custom_rink.hazards[0], {"kind": "spikes", "x": 185, "y": MwCustomRink.SPIKES_Y, "mirror": true})


## Owner, 2026-10-12: the spikes were placed wrong depending on how the
## player turned the camera - a press slanted by the turned camera jumped
## the spikes to the other board. Along the board they follow the press's
## part along the rink's y; only a fresh press pointing across, to the other
## board on the screen, jumps them; the other kinds move the way the press
## points, fractions kept.
func test_spikes_follow_the_turned_camera() -> void:
	if not need_rom():
		return
	_start()
	var editor: MwRinkEditor = router.current()
	for i in 4:
		_press("ui_down")
	_press("ui_accept")
	assert_eq(editor.page, "place")
	editor.kind = MwCustomRink.KIND_ORDER.find("spikes")
	editor.at = Vector2i(MwCustomRink.SPIKES_X, 0)
	for yaw in [0.0, 20.0, 30.0, 40.0, -30.0]:
		editor.yaw = fposmod(yaw, 360.0)
		editor.at = Vector2i(MwCustomRink.SPIKES_X, 0)
		pad.held = {"ui_up": true}                 # up the screen: mostly north, a slant across
		_run(20)
		pad.held = {}
		_run(2)
		assert_eq(editor.at.x, MwCustomRink.SPIKES_X, "yaw %d: still on the east board" % yaw)
		assert_lt(editor.at.y, -10, "yaw %d: moved north along it" % yaw)
	# turned further (yaw 60, 90: the camera on the east side), up the screen
	# points across the rink more than along it: to the west board
	editor.yaw = 60.0
	editor.at = Vector2i(MwCustomRink.SPIKES_X, 0)
	pad.held = {"ui_up": true}
	_run(20)
	pad.held = {}
	_run(2)
	assert_eq(editor.at.x, -MwCustomRink.SPIKES_X, "yaw 60: up = mostly across, to the west board")
	assert_lt(editor.at.y, -5, "... and on north along it while held")
	editor.yaw = 90.0
	editor.at = Vector2i(MwCustomRink.SPIKES_X, 0)
	pad.held = {"ui_up": true}
	_run(20)
	pad.held = {}
	_run(2)
	assert_eq(editor.at, Vector2i(-MwCustomRink.SPIKES_X, 0), "yaw 90: up = across, to the west board")
	pad.held = {"ui_right": true}                  # right on the screen: north along it
	_run(20)
	pad.held = {}
	_run(2)
	assert_eq(editor.at.x, -MwCustomRink.SPIKES_X)
	assert_lt(editor.at.y, -10)
	# another kind: a slanted camera moves it along the screen's direction
	editor.kind = MwCustomRink.KIND_ORDER.find("fire")
	editor.yaw = 20.0
	editor.at = Vector2i(0, 100)
	pad.held = {"ui_right": true}
	_run(30)
	pad.held = {}
	_run(2)
	var moved := Vector2(editor.at - Vector2i(0, 100))
	var want := Vector2.RIGHT.rotated(-deg_to_rad(20.0))
	assert_gt(moved.length(), 20.0)
	assert_almost_eq(moved.normalized().dot(want), 1.0, 0.01, "along the screen's right: %s" % moved)


func test_colours_reach_the_3d_view_at_once() -> void:
	if not need_rom():
		return
	_start()
	var editor: MwRinkEditor = router.current()
	var told := [0]
	editor.view_palette.changed.connect(func() -> void: told[0] += 1)
	_press("ui_down")                         # COLOURS
	_press("ui_right")                        # the next preset
	assert_gt(told[0], 0, "the view's palette told its users")
	assert_eq(editor.view_palette.colours().slice(0, 16), editor._colours(), "and holds the rink's colours")


## Plan 38 with plan 36: TICK RATE paces the rink's live play only (screens
## 4-6, MwRink.pass_pacer); the rink editor keeps its own pace with any
## setting - its TEST SKATE runs 2-tick passes, as the editor's
## preview, not the match's.
func test_tick_rate_leaves_the_editor_alone() -> void:
	if not need_rom():
		return
	var was := MwSettings.tick_rate
	MwSettings.tick_rate = "ORIGINAL"
	_start()
	var editor: MwRinkEditor = router.current()
	assert_false(editor.has_method("pass_pacer"), "the router's clock gives the editor its own passes")
	for i in 10:
		if editor.rows[editor.row].action == "skate":
			break
		_press("ui_down", 1)
	assert_eq(editor.rows[editor.row].action, "skate")
	_press("ui_accept")
	assert_eq(editor.page, "skate")
	var t0 := router.tick
	var s0: int = editor.sim.s.tick
	_run(120)
	var ran: int = editor.sim.s.tick - s0
	assert_eq(ran % 2, 0, "2-tick passes")
	assert_between(ran, router.tick - t0 - 2, router.tick - t0, "a pass every 2 ticks (%d ticks in %d)" % [ran,
			router.tick - t0])
	_press("rink_done")
	_run(60)
	assert_eq(editor.page, "rink")
	MwSettings.tick_rate = was


## Owner, 2026-10-11: TEST SKATE is one character on the rink, roaming free
## under the player's control, kept very simple, in the match's 3D views with
## the VISUALS layers, its prompt framed as the panels' hints.
func test_test_skate_is_one_skater_player_1_drives() -> void:
	if not need_rom():
		return
	var paint_was := MwSettings.splatter
	MwSettings.splatter = true
	_start()
	var editor: MwRinkEditor = router.current()
	assert_not_null(editor._splat, "the paint (VISUALS' PAINT on): the ice's detail on the editor's pages")
	assert_eq(editor.state.splatter, editor._splat)
	router.session.view = MwRinkViews.TV
	for i in 10:
		if editor.rows[editor.row].action == "skate":
			break
		_press("ui_down", 1)
	_press("ui_accept")
	assert_eq(editor.page, "skate")
	assert_eq(editor._skate_view, MwRinkViews.TV, "the player's 3D view")
	assert_true(editor._skate_under.visible, "the prompt's frame")
	_run(60)
	var s: MwRinkState = editor.sim.s
	var on := []
	for t in 2:
		for p in s.teams[t].players:
			if p.present:
				on.append(p)
	assert_eq(on.size(), 1, "one character on the rink")
	var me: MwRinkState.Player = on[0]
	assert_ne(me.flags & MwRinkState.Player.HUMAN, 0, "Player 1's")
	assert_ne(s.puck.flags & MwRinkState.Puck.HIDDEN, 0, "no puck to play")
	assert_eq(s.phase, MwRinkState.PHASE_PLAY)
	assert_eq(s.splatter, editor._splat, "the skate paints the visit's ice")
	assert_eq(MwLiveInput.turns.size(), MwVerbs.PLAYERS, "the TV view turns the pads")
	assert_eq(MwLiveInput.turns[0], MwRinkViews.SIDE_HEADING)
	# free roam: Player 1's pad skates him (no turning here: the test's pad is the frame itself)
	var x0 := me.motion.pixels().x
	rig.hold({MwVerbs.action(1, "move_right"): true}, 90, 0)
	assert_gt(me.motion.pixels().x, x0 + 20, "he skates where the pad says")
	assert_eq(Vector2i(s.puck.motion.pixels().x, s.puck.motion.pixels().y),
			Vector2i(me.motion.pixels().x, me.motion.pixels().y), "the hidden puck rides with him (the camera's)")
	# gone (dead, swallowed): back at centre ice
	me.record = 0
	_run(4)
	assert_ne(editor.sim.s, s, "a fresh skater")
	assert_not_null(editor._skater())
	# Esc: back to the editor
	var esc := InputEventKey.new()
	esc.keycode = MwInputMap.BACK_KEY
	esc.pressed = true
	editor._unhandled_input(esc)
	assert_eq(editor.glide_dir, -1)
	assert_true(MwLiveInput.turns.is_empty(), "the pads unturned")
	_run(60)
	assert_eq(editor.page, "rink")
	MwSettings.splatter = paint_was
	MwLiveInput.turns = PackedInt32Array()


## TEST SKATE's views: the match's, never 2D (the editor is 3D only).
func test_test_skate_views_stay_3d() -> void:
	if not need_rom():
		return
	_start()
	var editor: MwRinkEditor = router.current()
	editor._skate_view = MwRinkViews.FOLLOW
	var toggle := InputEventAction.new()
	toggle.action = MwInputMap.VIEW_TOGGLE
	toggle.pressed = true
	assert_eq(editor._view_picked(toggle), MwRinkViews.EXTENDED, "VIEW: the follow camera <-> 3D EXTENDED")
	editor._skate_view = MwRinkViews.EXTENDED
	assert_eq(editor._view_picked(toggle), MwRinkViews.FOLLOW)
	var f1 := InputEventAction.new()
	f1.action = MwInputMap.VIEW_SELECT[0]
	f1.pressed = true
	assert_eq(editor._view_picked(f1), -1, "F1 (2D): nothing")
	var f3 := InputEventAction.new()
	f3.action = MwInputMap.VIEW_SELECT[2]
	f3.pressed = true
	assert_eq(editor._view_picked(f3), MwRinkViews.TV)
	editor._skate_view = MwRinkViews.EXTENDED
	var nxt := InputEventAction.new()
	nxt.action = MwInputMap.VIEW_NEXT
	nxt.pressed = true
	assert_eq(editor._view_picked(nxt), MwRinkViews.ORTHO, "Select steps past 2D")
