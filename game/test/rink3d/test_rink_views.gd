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
	assert_eq(MwRinkViews.COUNT, 10)
	assert_eq(MwRinkViews.NAMES.size(), MwRinkViews.COUNT)
	assert_eq(MwRinkViews.NAMES[MwRinkViews.FLAT], "2D")
	assert_eq(MwRinkViews.NAMES[MwRinkViews.FOLLOW], "Follow 3D", "today's 3D view on F8")
	assert_eq(MwRinkViews.EXTENDED, 8, "plan 34's 3D EXTENDED after the F keys' eight")
	assert_eq(MwRinkViews.EXTENDED_2D, 9, "plan 44's 2D EXTENDED after it")
	assert_eq(MwRinkViews.NAMES[MwRinkViews.EXTENDED_2D], "2D Extended")
	assert_false(MwRinkViews.is_3d(MwRinkViews.FLAT))
	for v in range(1, MwRinkViews.COUNT):
		assert_true(MwRinkViews.is_3d(v), "drawn by the 3D view (2D EXTENDED too)")
	assert_false(MwRinkViews.opens_3d(MwRinkViews.EXTENDED_2D), "2D EXTENDED opens as 2D")
	assert_true(MwRinkViews.opens_3d(MwRinkViews.EXTENDED))
	var seen := []
	var view := MwRinkViews.FLAT
	for i in 8:
		seen.append(view)
		view = MwRinkViews.next(view)
	assert_eq(seen, range(8), "Back steps through the F keys' eight (2D and 3D's group)")
	assert_eq(view, MwRinkViews.FLAT, "and round to 2D: the EXTENDED two skipped")
	seen = []
	view = MwRinkViews.EXTENDED_2D
	for i in 8:
		seen.append(view)
		view = MwRinkViews.next(view, true)
	assert_eq(seen, [9, 1, 2, 3, 4, 5, 6, 8], "an EXTENDED match: its two in the round, 2D and the follow camera not")
	assert_eq(view, MwRinkViews.EXTENDED_2D, "round to 2D EXTENDED")


func test_each_3d_view_has_its_camera() -> void:
	var modes := {}
	for v in range(1, MwRinkViews.COUNT):
		modes[MwRinkViews.camera_mode(v)] = true
	modes[MwRinkViews.camera_mode(MwRinkViews.BIRDS_EYE, true)] = true
	assert_eq(modes.size(), 10, "nine views, two birds-eye layouts")
	assert_eq(MwRinkViews.camera_mode(MwRinkViews.FOLLOW), MwRinkCamera3D.Mode.FOLLOW)
	assert_eq(MwRinkViews.camera_mode(MwRinkViews.EXTENDED), MwRinkCamera3D.Mode.EXTENDED)
	assert_eq(MwRinkViews.camera_mode(MwRinkViews.EXTENDED_2D), MwRinkCamera3D.Mode.EXTENDED_ORTHO)
	assert_false(modes.has(MwRinkCamera3D.Mode.CALIBRATION), "the calibration camera stays a check")


func test_which_views_turn_the_controls() -> void:
	assert_eq(MwRinkViews.turn(MwRinkViews.TV), 2, "a quarter turn: up = east, where the camera looks")
	assert_eq(MwRinkViews.turn(MwRinkViews.DOLLY), 2)
	assert_eq(MwRinkViews.turn(MwRinkViews.BIRDS_EYE, true), 2)
	for v in [MwRinkViews.FLAT, MwRinkViews.ORTHO, MwRinkViews.FOLLOW, MwRinkViews.CINEMATIC, MwRinkViews.EXTENDED,
			MwRinkViews.EXTENDED_2D]:
		assert_eq(MwRinkViews.turn(v), 0, MwRinkViews.NAMES[v])
	assert_eq(MwRinkViews.turn(MwRinkViews.BIRDS_EYE, false), 0, "goals top and bottom: as the 2D")


func test_arrows_only_where_the_2d_camera_frames() -> void:
	for v in [MwRinkViews.FLAT, MwRinkViews.ORTHO, MwRinkViews.FOLLOW]:
		assert_true(MwRinkViews.shows_arrows(v), MwRinkViews.NAMES[v])
	for v in [MwRinkViews.TV, MwRinkViews.DOLLY, MwRinkViews.BIRDS_EYE, MwRinkViews.FIRST_PERSON, MwRinkViews.CINEMATIC,
			MwRinkViews.EXTENDED, MwRinkViews.EXTENDED_2D]:
		assert_false(MwRinkViews.shows_arrows(v), MwRinkViews.NAMES[v])


func test_view_actions_are_the_f_keys_and_back() -> void:
	assert_eq(MwInputMap.VIEW_SELECT.size(), 8, "F1-F8 as plan 20 put them (3D EXTENDED on VIEW and Back)")
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
	assert_eq(MwRinkViews.picked(v, MwRinkViews.EXTENDED_2D, true, true), MwRinkViews.EXTENDED,
			"an EXTENDED match: 2D EXTENDED -> 3D EXTENDED")
	assert_eq(MwRinkViews.picked(v, MwRinkViews.EXTENDED, true, true), MwRinkViews.EXTENDED_2D,
			"3D EXTENDED -> 2D EXTENDED (owner: never 2D / 3D)")
	assert_eq(MwRinkViews.picked(v, MwRinkViews.TV, true, true), MwRinkViews.EXTENDED_2D, "a debug view -> its 2D")
	assert_eq(MwRinkViews.picked(v, MwRinkViews.EXTENDED, false, true), MwRinkViews.EXTENDED_2D, "online too")
	var y := InputEventJoypadButton.new()
	y.device = 0
	y.button_index = JOY_BUTTON_Y
	y.pressed = true
	assert_eq(MwRinkViews.picked(y, MwRinkViews.FLAT), MwRinkViews.FOLLOW, "the first pad's north button")
	y.device = 1
	assert_eq(MwRinkViews.picked(y, MwRinkViews.FLAT), -1, "player 1's only")


## Plan 44 (owner: no switching between 2D and 2D EXTENDED, or between 3D
## and 3D EXTENDED): the F keys' 2D and follow camera are the match's
## group's; the options' four cameras and the match they make.
func test_the_views_stay_in_the_matchs_group() -> void:
	MwInputMap.install()
	var f1 := InputEventKey.new()
	f1.physical_keycode = KEY_F1
	f1.pressed = true
	var f8 := InputEventKey.new()
	f8.physical_keycode = KEY_F8
	f8.pressed = true
	assert_eq(MwRinkViews.picked(f1, MwRinkViews.TV), MwRinkViews.FLAT)
	assert_eq(MwRinkViews.picked(f1, MwRinkViews.TV, true, true), MwRinkViews.EXTENDED_2D, "F1: the group's 2D")
	assert_eq(MwRinkViews.picked(f8, MwRinkViews.FLAT, true, true), MwRinkViews.EXTENDED, "F8: the group's 3D")
	assert_eq(MwRinkViews.picked(f1, MwRinkViews.FLAT, false, true), -1, "online: no F keys")
	assert_eq(MwRinkViews.grouped(MwRinkViews.FLAT, true), MwRinkViews.EXTENDED_2D)
	assert_eq(MwRinkViews.grouped(MwRinkViews.EXTENDED, false), MwRinkViews.FOLLOW)
	assert_eq(MwRinkViews.grouped(MwRinkViews.TV, true), MwRinkViews.TV, "a debug view as it is")
	var saved := [MwSettings.camera, MwSettings.start_view]
	MwSettings.start_view = -1
	assert_eq(MwSettings.CAMERAS, ["2D", "3D", "2D EXTENDED", "3D EXTENDED"] as Array[String], "the owner's four")
	var want := [[MwRinkViews.FLAT, false], [MwRinkViews.FOLLOW, false], [MwRinkViews.EXTENDED_2D, true],
			[MwRinkViews.EXTENDED, true]]
	for c in 4:
		MwSettings.camera = c
		assert_eq([MwSettings.view(), MwSettings.extended_play()], want[c], MwSettings.camera_name())
		assert_eq(MwSettings.match_rules()["extended_play"], want[c][1], "a match rule")
	for c in 4:
		MwSettings.camera = c
		MwSettings.use_match_rules({"extended_play": true})
		assert_true(MwSettings.extended_play(), "a match's rule (online: always)")
		assert_eq(MwSettings.view(), MwRinkViews.grouped(want[c][0], true), "this machine's 2D or 3D in its group")
		MwSettings.own_match_rules()
		assert_eq(MwSettings.extended_play(), want[c][1], "its own again")
	MwSettings.camera = saved[0]
	MwSettings.start_view = saved[1]


func test_the_rinks_switch_keeps_the_extended_group() -> void:
	if not need_rom():
		return
	MwInputMap.install()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = true
	var session := MwSession.new(0x61F2415D, 0x1234567)
	session.view = MwRinkViews.EXTENDED                 # the options' 3D EXTENDED (the matchup's)
	session.extended_views = true
	var was := MwSettings.start_view
	MwSettings.start_view = MwRinkViews.EXTENDED        # (the rink's entry takes the match's rules from it)
	var rink := _rink(session)
	var view := MwRink3DHost.of(get_tree()).view()
	var modes := []
	for i in 4:
		rink._unhandled_input(key)
		var shown := MwRink3DHost.of(get_tree()).shown_for(rink)
		modes.append([session.view, shown, view.camera.mode if shown else -1])
	var ext := MwRinkCamera3D.Mode.EXTENDED
	var ext_2d := MwRinkCamera3D.Mode.EXTENDED_ORTHO
	assert_eq(modes, [[MwRinkViews.EXTENDED_2D, true, ext_2d], [MwRinkViews.EXTENDED, true, ext],
			[MwRinkViews.EXTENDED_2D, true, ext_2d], [MwRinkViews.EXTENDED, true, ext]],
			"VIEW: 2D EXTENDED (the 3D view's orthographic camera) and back to 3D EXTENDED (owner)")
	MwSettings.start_view = was
	session.view = MwRinkViews.FLAT


func test_turning_a_players_directions() -> void:
	var up := {"p1_move_up": true, "p1_pass": true, "p2_move_up": true}
	var turned := MwLiveInput.turn_player(up, 1, 2)
	assert_eq(turned, {"p1_move_right": true, "p1_pass": true, "p2_move_up": true}, "a quarter turn: up -> right")
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


## Every player's turn [param t] (plan 34: twelve players).
static func _all(t: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(MwVerbs.PLAYERS)
	out.fill(t)
	return out


func test_the_rink_picks_views_and_turns_the_pads() -> void:
	if not need_rom():
		return
	var session := MwSession.new(0x61F2415D, 0x1234567)
	var rink := _rink(session)
	assert_eq(rink.view(), MwRinkViews.FLAT, "2D by default")
	assert_eq(MwLiveInput.turns, _all(0))
	rink.select_view(MwRinkViews.TV)
	assert_eq(session.view, MwRinkViews.TV, "the session keeps it")
	var view := MwRink3DHost.of(get_tree()).view()
	assert_true(MwRink3DHost.of(get_tree()).shown_for(rink))
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.TV)
	assert_eq(MwLiveInput.turns, _all(2), "every pad a quarter turn")
	rink.select_view(MwRinkViews.BIRDS_EYE)
	assert_false(session.birds_eye_across)
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.BIRDS_EYE)
	assert_eq(MwLiveInput.turns, _all(0), "goals top and bottom: no turn")
	rink.select_view(MwRinkViews.BIRDS_EYE)
	assert_true(session.birds_eye_across, "F5 again: the other layout")
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.BIRDS_EYE_ACROSS)
	assert_eq(MwLiveInput.turns, _all(2))
	rink.phases.paused = true
	rink._present(false)
	assert_eq(MwLiveInput.turns, _all(0), "the pause menu reads the pads as they are")
	rink.phases.paused = false
	rink.select_view(MwRinkViews.FLAT)
	assert_false(MwRink3DHost.of(get_tree()).shown_for(rink))
	assert_eq(MwLiveInput.turns, _all(0))
	rink.select_view(MwRinkViews.next(MwRinkViews.FOLLOW))
	assert_eq(session.view, MwRinkViews.FLAT, "Back after F8: 2D (plan 44: the EXTENDED two are another match's)")
	rink.select_view(MwRinkViews.next(MwRinkViews.CINEMATIC, true))
	assert_eq(session.view, MwRinkViews.EXTENDED, "an EXTENDED match's: 3D EXTENDED after the cinematic one")
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.EXTENDED)
	assert_eq(MwLiveInput.turns, _all(0), "looking north as the follow camera: no turn")
	rink.select_view(MwRinkViews.next(MwRinkViews.EXTENDED, true))
	assert_eq(session.view, MwRinkViews.EXTENDED_2D, "then 2D EXTENDED")
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.EXTENDED_ORTHO, "ORTHO's lens, zooming")
	assert_eq(view.world.scale, Vector3(1, sqrt(2.0), sqrt(2.0)), "in ORTHO's world (the original's projection)")
	assert_eq(MwLiveInput.turns, _all(0), "looking north as the 2D: no turn")
	assert_false(MwRinkViews.shows_arrows(rink.view()), "no off-screen arrows")
	rink.select_view(MwRinkViews.next(MwRinkViews.EXTENDED_2D, true))
	assert_eq(session.view, MwRinkViews.ORTHO, "and after it, round past 2D to the orthographic")
	rink.select_view(MwRinkViews.DOLLY)
	assert_eq(MwLiveInput.turns, _all(2))
	host.free()
	assert_eq(MwLiveInput.turns, PackedInt32Array(), "cleared as the rink leaves")
	assert_false(MwRink3DHost.of(get_tree()).visible, "and the view hidden")
	session.view = MwRinkViews.FLAT
