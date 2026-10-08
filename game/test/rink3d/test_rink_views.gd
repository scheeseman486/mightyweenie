extends "res://test/rom/rom_test_base.gd"
## The rink's views (plan 20, MwRinkViews): F1-F8 and Back, the session
## setting, the camera modes, the controls turning with the camera
## (MwLiveInput), only in play.

var host: Node


func after_each() -> void:
	MwLiveInput.turns = PackedInt32Array([0, 0, 0, 0])
	if host != null and is_instance_valid(host):
		host.free()
	host = null


func test_views_in_the_owners_order() -> void:
	assert_eq(MwRinkViews.COUNT, 8)
	assert_eq(MwRinkViews.NAMES[MwRinkViews.FLAT], "2D")
	assert_eq(MwRinkViews.NAMES[MwRinkViews.FOLLOW], "Follow 3D", "today's 3D view on F8")
	assert_false(MwRinkViews.is_3d(MwRinkViews.FLAT))
	for v in range(1, MwRinkViews.COUNT):
		assert_true(MwRinkViews.is_3d(v))
	var seen := []
	var v := MwRinkViews.FLAT
	for i in MwRinkViews.COUNT:
		seen.append(v)
		v = MwRinkViews.next(v)
	assert_eq(seen, range(MwRinkViews.COUNT), "Back steps through them all")
	assert_eq(v, MwRinkViews.FLAT, "and round to 2D")


func test_each_3d_view_has_its_camera() -> void:
	var modes := {}
	for v in range(1, MwRinkViews.COUNT):
		modes[MwRinkViews.camera_mode(v)] = true
	modes[MwRinkViews.camera_mode(MwRinkViews.BIRDS_EYE, true)] = true
	assert_eq(modes.size(), 8, "seven views, two birds-eye layouts")
	assert_eq(MwRinkViews.camera_mode(MwRinkViews.FOLLOW), MwRinkCamera3D.Mode.FOLLOW)
	assert_false(modes.has(MwRinkCamera3D.Mode.CALIBRATION), "the calibration camera stays a check")


func test_which_views_turn_the_controls() -> void:
	assert_eq(MwRinkViews.turn(MwRinkViews.TV), 2, "a quarter turn: up = east, where the camera looks")
	assert_eq(MwRinkViews.turn(MwRinkViews.DOLLY), 2)
	assert_eq(MwRinkViews.turn(MwRinkViews.BIRDS_EYE, true), 2)
	for v in [MwRinkViews.FLAT, MwRinkViews.ORTHO, MwRinkViews.FOLLOW, MwRinkViews.CINEMATIC]:
		assert_eq(MwRinkViews.turn(v), 0, MwRinkViews.NAMES[v])
	assert_eq(MwRinkViews.turn(MwRinkViews.BIRDS_EYE, false), 0, "goals top and bottom: as the 2D")


func test_arrows_only_where_the_2d_camera_frames() -> void:
	for v in [MwRinkViews.FLAT, MwRinkViews.ORTHO, MwRinkViews.FOLLOW]:
		assert_true(MwRinkViews.shows_arrows(v), MwRinkViews.NAMES[v])
	for v in [MwRinkViews.TV, MwRinkViews.DOLLY, MwRinkViews.BIRDS_EYE, MwRinkViews.FIRST_PERSON, MwRinkViews.CINEMATIC]:
		assert_false(MwRinkViews.shows_arrows(v), MwRinkViews.NAMES[v])


func test_view_actions_are_the_f_keys_and_back() -> void:
	assert_eq(MwInputMap.VIEW_SELECT.size(), MwRinkViews.COUNT)
	for i in MwInputMap.VIEW_SELECT.size():
		var a := MwInputMap.VIEW_SELECT[i]
		assert_true(InputMap.has_action(a), a)
		var keys := InputMap.action_get_events(a).filter(func(e): return e is InputEventKey)
		assert_eq(keys.size(), 1, a)
		assert_eq((keys[0] as InputEventKey).physical_keycode, KEY_F1 + i, a)
	var back := InputMap.action_get_events(MwInputMap.VIEW_NEXT)
	assert_eq(back.size(), 1)
	assert_eq((back[0] as InputEventJoypadButton).button_index, JOY_BUTTON_BACK)
	assert_eq((back[0] as InputEventJoypadButton).device, -1, "any gamepad")
	for a in MwInputMap.VIEW_SELECT + [MwInputMap.VIEW_NEXT]:
		assert_false(a in MwVerbs.all_actions(), "%s is no gameplay verb" % a)


func test_player_ones_2d_3d_switch() -> void:
	MwInputMap.install()
	var v := InputEventKey.new()
	v.physical_keycode = KEY_V
	v.pressed = true
	assert_eq(MwRinkViews.picked(v, MwRinkViews.FLAT), MwRinkViews.FOLLOW, "2D -> 3D: the follow camera")
	assert_eq(MwRinkViews.picked(v, MwRinkViews.FOLLOW), MwRinkViews.FLAT, "3D -> 2D")
	assert_eq(MwRinkViews.picked(v, MwRinkViews.TV), MwRinkViews.FLAT, "a debug view -> 2D")
	var y := InputEventJoypadButton.new()
	y.device = 0
	y.button_index = JOY_BUTTON_Y
	y.pressed = true
	assert_eq(MwRinkViews.picked(y, MwRinkViews.FLAT), MwRinkViews.FOLLOW, "the first pad's north button")
	y.device = 1
	assert_eq(MwRinkViews.picked(y, MwRinkViews.FLAT), -1, "player 1's only")


func test_turning_a_players_directions() -> void:
	var up := {"p1_move_up": true, "p1_pass": true, "p2_move_up": true}
	var q := MwLiveInput.turn_player(up, 1, 2)
	assert_eq(q, {"p1_move_right": true, "p1_pass": true, "p2_move_up": true}, "a quarter turn: up -> right")
	assert_eq(MwLiveInput.turn_player({"p1_move_right": true}, 1, 2), {"p1_move_down": true})
	assert_eq(MwLiveInput.turn_player({"p1_move_left": true, "p1_move_down": true}, 1, 2),
			{"p1_move_left": true, "p1_move_up": true}, "down-left -> up-left")
	assert_eq(MwLiveInput.turn_player({"p1_move_up": true}, 1, 1),
			{"p1_move_up": true, "p1_move_right": true}, "an eighth: up -> up-right")
	assert_eq(MwLiveInput.turn_player({"p1_move_up": true}, 1, -1),
			{"p1_move_up": true, "p1_move_left": true})
	assert_eq(MwLiveInput.turn_player({"p1_move_up": true}, 1, 4), {"p1_move_down": true})
	assert_eq(MwLiveInput.turn_player({"p1_check": true}, 1, 2), {"p1_check": true}, "no direction, nothing to turn")


func test_live_input_turns_in_play_only() -> void:
	var live := MwLiveInput.new()
	MwLiveInput.turns = PackedInt32Array([2, 0, 0, 0])
	Input.action_press("p1_move_up")
	var play := live.sample([MwVerbs.Context.GAMEPLAY])
	assert_true(play.has("p1_move_right"), "turned in play")
	assert_false(play.has("p1_move_up"))
	var menu := live.sample([MwVerbs.Context.MENU])
	assert_true(menu.has("p1_move_up"), "menus see the pad as it is")
	var fight := live.sample([MwVerbs.Context.FIGHT])
	assert_true(fight.has("p1_move_up"), "fights too")
	Input.action_release("p1_move_up")
	MwLiveInput.turns = PackedInt32Array([0, 2, 0, 0])
	live.sample([MwVerbs.Context.GAMEPLAY])
	live.taps()
	Input.action_press("p2_move_left")
	live.tick()
	Input.action_release("p2_move_left")
	assert_false(live.sample([MwVerbs.Context.GAMEPLAY]).has("p2_move_up"))
	var taps := live.taps()
	assert_true(taps.has("p2_move_up"), "a quick tap turned too: left -> up")
	assert_false(taps.has("p2_move_left"))


func test_first_person_turn_keeps_its_eighth_near_a_boundary() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	add_child_autofree(vp)
	var cam := MwRinkCamera3D.new()
	cam.mode = MwRinkCamera3D.Mode.FREE
	vp.add_child(cam)
	for deg_want: Array in [[0.0, 0], [20.0, 0], [28.0, 0], [31.0, 1], [20.0, 1], [16.0, 1], [14.0, 0], [-10.0, 0],
			[90.0, 2], [-90.0, 6], [180.0, 4]]:
		cam.transform = Transform3D(Basis(Vector3.UP, -deg_to_rad(deg_want[0])), Vector3.ZERO)
		assert_eq(cam.turn_eighths(), deg_want[1], "heading %s deg" % deg_want[0])


func _rink(session: MwSession) -> MwRink:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = session
	router.input = MwLiveInput.new()
	var rink := (load(MwScreens.scene_path(4)) as PackedScene).instantiate() as MwRink
	rink.screen_id = 4
	router.adopt(rink, {"new_match": true})
	return rink


func test_the_rink_picks_views_and_turns_the_pads() -> void:
	if not need_rom():
		return
	var session := MwSession.new(0x61F2415D, 0x1234567)
	var rink := _rink(session)
	assert_eq(rink.view(), MwRinkViews.FLAT, "2D by default")
	assert_eq(MwLiveInput.turns, PackedInt32Array([0, 0, 0, 0]))
	rink.select_view(MwRinkViews.TV)
	assert_eq(session.view, MwRinkViews.TV, "the session keeps it")
	var view := MwRink3DHost.of(get_tree()).view()
	assert_true(MwRink3DHost.of(get_tree()).shown_for(rink))
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.TV)
	assert_eq(MwLiveInput.turns, PackedInt32Array([2, 2, 2, 2]), "every pad a quarter turn")
	rink.select_view(MwRinkViews.BIRDS_EYE)
	assert_false(session.birds_eye_across)
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.BIRDS_EYE)
	assert_eq(MwLiveInput.turns, PackedInt32Array([0, 0, 0, 0]), "goals top and bottom: no turn")
	rink.select_view(MwRinkViews.BIRDS_EYE)
	assert_true(session.birds_eye_across, "F5 again: the other layout")
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.BIRDS_EYE_ACROSS)
	assert_eq(MwLiveInput.turns, PackedInt32Array([2, 2, 2, 2]))
	rink.phases.paused = true
	rink._present(false)
	assert_eq(MwLiveInput.turns, PackedInt32Array([0, 0, 0, 0]), "the pause menu reads the pads as they are")
	rink.phases.paused = false
	rink.select_view(MwRinkViews.FLAT)
	assert_false(MwRink3DHost.of(get_tree()).shown_for(rink))
	assert_eq(MwLiveInput.turns, PackedInt32Array([0, 0, 0, 0]))
	rink.select_view(MwRinkViews.next(MwRinkViews.FOLLOW))
	assert_eq(session.view, MwRinkViews.FLAT, "Back after F8: 2D")
	rink.select_view(MwRinkViews.DOLLY)
	assert_eq(MwLiveInput.turns, PackedInt32Array([2, 2, 2, 2]))
	host.free()
	assert_eq(MwLiveInput.turns, PackedInt32Array([0, 0, 0, 0]), "cleared as the rink leaves")
	assert_false(MwRink3DHost.of(get_tree()).visible, "and the view hidden")
	session.view = MwRinkViews.FLAT
