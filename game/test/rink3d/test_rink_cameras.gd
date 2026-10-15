extends "res://test/rom/rom_test_base.gd"
## The game's 3D views' cameras (plan 20, MwRinkCamera3D, MwRinkShot3D,
## MwRinkDirector3D): where each one stands and looks, its smoothing at any
## frame rate, what the first-person camera hides.

var host: Node


func after_each() -> void:
	MwLiveInput.turns = PackedInt32Array([0, 0, 0, 0])
	if host != null and is_instance_valid(host):
		host.free()
	host = null


func _camera(mode: int, size := MwRink3D.SCREEN) -> MwRinkCamera3D:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	add_child_autofree(vp)
	var cam := MwRinkCamera3D.new()
	cam.view = Vector2(size)
	cam.mode = mode as MwRinkCamera3D.Mode
	vp.add_child(cam)
	cam.current = true
	return cam


func _shot(puck: Vector3, players: Array = []) -> MwRinkShot3D:
	var shot := MwRinkShot3D.new()
	shot.puck = puck
	shot.look = Vector3(puck.x, puck.y, 0)
	shot.players = PackedVector3Array(players)
	return shot


## The sim camera's shown point that looks at rink point [param point].
func _shown(point: Vector3) -> Vector2:
	return MwRink3D.map_point(point.x, point.y, 0) - Vector2(MwRink3D.SCREEN) / 2.0


func _eye(cam: MwRinkCamera3D) -> Vector3:
	return MwRink3D.rink(cam.global_position)


func _screen(cam: MwRinkCamera3D, point: Vector3) -> Vector2:
	return cam.unproject_position(MwRink3D.world(point.x, point.y, point.z) * cam.world_scale())


func test_damping_is_the_same_at_any_frame_rate() -> void:
	for target: float in [100.0, -40.0]:
		var ends := []
		for fps in [30, 60, 144, 240]:
			var x := 0.0
			var v := 0.0
			for i in fps:                      # one second
				var r := MwRinkCamera3D.damp(x, v, target, 5.0, 1.0 / fps)
				x = r[0]
				v = r[1]
			ends.append(x)
		for reached: float in ends:
			assert_almost_eq(reached, ends[0], absf(target) * 0.03, "1 s at any frame rate")
		assert_almost_eq(ends[0], target, absf(target) * 0.06, "settled after 1 s at omega 5")
	var a := MwRinkCamera3D.damp(Vector3.ZERO, Vector3.ZERO, Vector3(10, 0, 0), 5.0, 0.0)
	assert_eq(a[0], Vector3.ZERO, "no time, no move")


func test_ortho_is_the_2d_view_through_a_long_lens() -> void:
	var cam := _camera(MwRinkCamera3D.Mode.ORTHO)
	assert_eq(cam.world_scale(), Vector3(1, sqrt(2.0), sqrt(2.0)), "the original's projection")
	var look := Vector3(60, 100, 0)
	var shown := _shown(look)
	cam.follow(shown)
	for p in [look, look + Vector3(-100, -80, 0), look + Vector3(90, 70, 0), look + Vector3(40, 30, 40)]:
		var want := MwRink3D.map_point(p.x, p.y, p.z) - shown
		assert_almost_eq(_screen(cam, p), want, Vector2.ONE * 5.0, "rink point %s as in 2D" % p)
	# the east boards, 125 px right of the camera: their face shows some width
	var bottom := _screen(cam, Vector3(185, 100, 0))
	var top := _screen(cam, Vector3(185, 100, 48))
	assert_gt(top.x - bottom.x, 1.0, "the side boards' face is seen")
	assert_eq(cam.cut_boards(), MwStands.BOARD.y, "it looks over the near stands")


func test_tv_pans_and_zooms_from_one_pivot() -> void:
	var cam := _camera(MwRinkCamera3D.Mode.TV)
	cam.shot = _shot(Vector3(0, 0, 0), [Vector3(20, 10, 0), Vector3(-20, -10, 0), Vector3(10, 30, 0)])
	cam.follow(_shown(Vector3.ZERO))
	var pivot := Vector3(-cam.side_out_px, 0, cam.side_height_px)
	assert_almost_eq(_eye(cam), pivot, Vector3.ONE * 0.01)
	assert_almost_eq(cam.heading(), PI / 2.0, 0.01, "looking east across the rink")
	assert_almost_eq(_screen(cam, Vector3.ZERO), Vector2(160, 112), Vector2.ONE * 1.0, "the play in the middle")
	var tight := cam.fov
	# the play moves north and spreads out: the camera turns and widens, smoothly
	cam.shot = _shot(Vector3(0, -250, 0), [Vector3(100, -250, 0), Vector3(-90, -150, 0), Vector3(0, -330, 0)])
	cam.dt = 1.0 / 60.0
	cam.follow(_shown(Vector3(0, -250, 0)))
	assert_almost_eq(_eye(cam), pivot, Vector3.ONE * 0.01, "the pivot stays")
	var first := cam.heading()
	assert_lt(first, PI / 2.0, "turning north")
	assert_gt(first, PI / 2.0 - 0.1, "not at once")
	for i in 120:
		cam.follow(_shown(Vector3(0, -250, 0)))
	assert_almost_eq(_screen(cam, Vector3(0, -250, 0)).x, 160.0, 12.0, "the play framed after 2 s")
	assert_gt(cam.fov, tight, "zoomed out for the spread play")
	assert_between(cam.fov, cam.tv_fov_min, cam.tv_fov_max)


func test_dolly_tracks_along_its_rail() -> void:
	var cam := _camera(MwRinkCamera3D.Mode.DOLLY)
	cam.shot = _shot(Vector3(50, 200, 0))
	cam.follow(_shown(Vector3(50, 200, 0)))
	var eye := _eye(cam)
	assert_almost_eq(eye.x, -cam.side_out_px, 0.01)
	assert_almost_eq(eye.z, cam.side_height_px, 0.01)
	assert_almost_eq(eye.y, 200.0, 1.0, "level with the play")
	assert_almost_eq(cam.heading(), PI / 2.0, 0.01, "straight across")
	var fov := cam.fov
	cam.shot = _shot(Vector3(0, -360, 0))
	cam.dt = 1.0 / 30.0
	for i in 90:
		cam.follow(_shown(Vector3(0, -360, 0)))
	assert_almost_eq(_eye(cam).y, -cam.dolly_range_px, 2.0, "to the rail's end")
	assert_eq(cam.fov, fov, "no zoom")


func test_birds_eye_shows_the_whole_rink() -> void:
	for mode in [MwRinkCamera3D.Mode.BIRDS_EYE, MwRinkCamera3D.Mode.BIRDS_EYE_ACROSS]:
		var cam := _camera(mode)
		cam.follow(_shown(Vector3(80, 300, 0)))
		for x in [-185.0, 185.0]:
			for y in [-372.0, 372.0]:
				var corner := _screen(cam, Vector3(x, y, 0))
				assert_between(corner.x, 0.0, 320.0, "corner (%d, %d) on screen" % [x, y])
				assert_between(corner.y, 0.0, 224.0, "corner (%d, %d) on screen" % [x, y])
		var north := _screen(cam, Vector3(0, -372, 0))
		var south := _screen(cam, Vector3(0, 372, 0))
		if mode == MwRinkCamera3D.Mode.BIRDS_EYE:
			assert_lt(north.y, south.y, "goals top and bottom: north up")
		else:
			assert_lt(north.x, south.x, "goals left and right: north left")
			assert_gt(absf(north.x - south.x), 224.0, "the long way across: bigger")


func test_first_person_rides_with_his_player() -> void:
	var cam := _camera(MwRinkCamera3D.Mode.FIRST_PERSON)
	var shot := _shot(Vector3(40, 40, 0))
	shot.rider = "t0.p2.1A"
	shot.rider_at = Vector3(30, 60, 0)
	shot.rider_heading = PI / 2.0
	cam.shot = shot
	cam.follow(_shown(Vector3.ZERO))
	assert_almost_eq(_eye(cam), Vector3(30, 60, cam.eye_height_px), Vector3.ONE * 0.01, "his eyes")
	assert_almost_eq(cam.heading(), PI / 2.0, 0.01, "looking his way")
	assert_eq(cam.hidden_subject(), "t0.p2.1A")
	assert_eq(cam.turn_eighths(), 2, "player 1's pad: up = where he looks")
	# he turns round: the camera follows smoothly, never in one frame
	shot.rider_heading = -PI / 2.0
	cam.dt = 1.0 / 60.0
	cam.follow(_shown(Vector3.ZERO))
	assert_gt(absf(angle_difference(cam.heading(), -PI / 2.0)), 2.5, "no snap")
	for i in 120:
		cam.follow(_shown(Vector3.ZERO))
	assert_almost_eq(angle_difference(cam.heading(), -PI / 2.0), 0.0, 0.05, "turned after 2 s")
	# nobody to ride with: it falls back to the follow framing
	cam.shot = _shot(Vector3.ZERO)
	cam.follow(_shown(Vector3.ZERO))
	assert_eq(cam.hidden_subject(), "")


func test_first_person_hides_his_frames_and_those_at_the_lens() -> void:
	var cam := _camera(MwRinkCamera3D.Mode.FIRST_PERSON)
	var shot := _shot(Vector3(40, 40, 0))
	shot.rider = "t0.p2.1A"
	shot.rider_at = Vector3(30, 60, 0)
	cam.shot = shot
	cam.follow(_shown(Vector3.ZERO))
	var items := [
		{"key": "t0.p2.1A/body", "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(30, 60, 0)},
		{"key": "t0.p2.1A/a1234", "place": MwRinkDraw3D.GROUND, "at": Vector3(30, 60, 0)},
		{"key": "t1.p0.22/body", "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(50, 70, 0)},
		{"key": "t1.p1.23/body", "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(30, -60, 0)},
		{"key": "t1.p0.22/shadow", "place": MwRinkDraw3D.GROUND, "at": Vector3(50, 70, 0)},
	]
	var kept := MwRinkView3D.lens_items(items, cam).map(func(it): return it["key"])
	assert_eq(kept, ["t1.p1.23/body", "t1.p0.22/shadow"], "his own frames and the one at the lens gone")
	cam.mode = MwRinkCamera3D.Mode.TV
	assert_eq(MwRinkView3D.lens_items(items, cam).size(), items.size(), "other cameras hide nothing")


func test_the_director_films_the_play() -> void:
	var cam := _camera(MwRinkCamera3D.Mode.CINEMATIC)
	var shot := _shot(Vector3(0, -300, 0), [Vector3(10, -290, 0)])
	cam.shot = shot
	cam.dt = 1.0 / 30.0
	cam.follow(_shown(Vector3(0, -300, 0)))
	assert_eq(cam.director.shot, MwRinkDirector3D.Shot.CRANE, "a new mode starts with a crane")
	var seen := {}
	for i in 30 * 60:                          # a minute of footage
		cam.follow(_shown(Vector3(0, -300, 0)))
		seen[cam.director.shot] = true
		var eye := _eye(cam)
		assert_true(absf(eye.x) <= 185.0 and eye.z > 0.0, "over the ice or the end boards")
		if absf(eye.y) > MwStands.BOARD.y:
			assert_eq(cam.cut_boards(), signf(eye.y) * MwStands.BOARD.y, "beyond the end boards: those stands cut away")
		else:
			assert_eq(cam.cut_boards(), 0.0)
	assert_gt(seen.size(), 3, "it changes shots")
	assert_true(seen.has(MwRinkDirector3D.Shot.BEHIND_NET), "near a goal: from behind the net")
	var goal := _shot(Vector3(0, -330, 0))
	goal.score = Vector2i(1, 0)
	cam.shot = goal
	cam.follow(_shown(Vector3(0, -300, 0)))
	assert_eq(cam.director.shot, MwRinkDirector3D.Shot.GOAL, "a goal: the goal orbit")


func test_shots_from_a_live_faceoff() -> void:
	if not need_rom():
		return
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(0x61F2415D, 0x1234567)
	router.session.setup.pads = 0                # P1 against the CPU
	router.input = MwLiveInput.new()
	var rink := (load(MwScreens.scene_path(4)) as PackedScene).instantiate() as MwRink
	rink.screen_id = 4
	router.adopt(rink, {"new_match": true})
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(rink.state)
	var shot := MwRinkShot3D.make(rink.state, drawer.items, Vector2(rink.state.camera.shown))
	assert_gte(shot.players.size(), 10, "the teams on the ice")
	assert_ne(shot.rider, "", "someone to ride with")
	assert_true(shot.rider.begins_with("t"), shot.rider)
	var keys := drawer.items.map(func(it): return it["key"])
	assert_true(keys.has(shot.rider + "/body"), "the rider's frames carry his subject")
	var half := MwRinkShot3D.blend(shot, shot, 0.5)
	assert_eq(half.rider, shot.rider)
	assert_almost_eq(half.puck, shot.puck, Vector3.ONE * 0.001)
	assert_almost_eq(MwRinkShot3D.heading_of(0), PI / 2.0, 1e-6, "angle 0: east")
	assert_almost_eq(absf(MwRinkShot3D.heading_of(0x40)), PI, 1e-6, "$40: south")
	assert_almost_eq(MwRinkShot3D.heading_of(0xC0), 0.0, 1e-6, "$C0: north")


## Plan 25: a wide picture shows the original's 224 px high and more beside
## it (the middle 320 as before); a tall one keeps the 320 across.
func test_wide_and_tall_pictures_keep_the_original_framing() -> void:
	var at := Vector3(40, 100, 0)
	var shown := _shown(at)
	var probe := [Vector3(at.x - 150, at.y, 0), Vector3(at.x + 150, at.y, 0), Vector3(at.x, at.y - 90, 0)]
	for mode in [MwRinkCamera3D.Mode.FOLLOW, MwRinkCamera3D.Mode.ORTHO]:
		var base := _camera(mode)
		base.follow(shown)
		var wide := _camera(mode, Vector2i(398, 224))
		wide.follow(shown)
		assert_almost_eq(wide.fov, base.fov, 0.0001, "%d: wide - the same height" % mode)
		var tall := _camera(mode, Vector2i(320, 240))
		tall.follow(shown)
		assert_gt(tall.fov, base.fov, "%d: tall - grown" % mode)
		for point: Vector3 in probe:
			var b := _screen(base, point)
			assert_almost_eq(_screen(wide, point), b + Vector2(39, 0), Vector2(0.6, 0.6),
					"%d: the middle 320 as before" % mode)
			assert_almost_eq(_screen(tall, point).x, b.x, 0.6, "%d: the 320 across kept" % mode)


func test_birds_eye_fits_the_wide_picture() -> void:
	for mode in [MwRinkCamera3D.Mode.BIRDS_EYE, MwRinkCamera3D.Mode.BIRDS_EYE_ACROSS]:
		var base := _camera(mode)
		base.follow(_shown(Vector3.ZERO))
		var cam := _camera(mode, Vector2i(530, 224))
		cam.follow(_shown(Vector3.ZERO))
		assert_lte(cam.fov, base.fov + 0.0001, "%d: no wider than needed" % mode)
		for x in [-185.0, 185.0]:
			for y in [-372.0, 372.0]:
				var corner := _screen(cam, Vector3(x, y, 0))
				assert_between(corner.x, 0.0, 530.0, "corner (%d, %d) in the picture" % [x, y])
				assert_between(corner.y, 0.0, 224.0, "corner (%d, %d) in the picture" % [x, y])
