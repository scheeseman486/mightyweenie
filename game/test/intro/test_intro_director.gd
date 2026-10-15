extends "res://test/rom/rom_test_base.gd"
## The match's opening's camera (plan 33, MwIntroDirector3D): a steady TV
## shot of the rink first, then the crowd's shots, then shots picked from
## its own seed by what the players do; the line-up's glide ends on the
## match's view.
## Short names: d the MwIntroDirector3D under test.

const STEP := 1.0 / 60.0
const CROWD_SHOTS := [MwIntroDirector3D.STANDS_DOLLY, MwIntroDirector3D.DRONE,
		MwIntroDirector3D.CROWD_CRANE, MwIntroDirector3D.END_SWEEP]

var rehearsal: MwMatchRehearsal


func before_all() -> void:
	super.before_all()
	if not rom.is_empty():
		var session := MwSession.new(5, 1)
		session.setup.team_a = 2
		session.setup.team_b = 9
		rehearsal = MwMatchRehearsal.run(rom, session.setup, session.rng.state)


func _camera() -> MwRinkCamera3D:
	var cam := MwRinkCamera3D.new()
	add_child_autofree(cam)
	return cam


## [param seconds] of the intro at 60 ticks a second: the players (if any)
## and the camera; returns each shot taken in order.
func _run(d: MwIntroDirector3D, cam: MwRinkCamera3D, seconds: float) -> Array:
	var shots := []
	for i in int(round(seconds * 60.0)):
		if d.cast != null:
			d.cast.step(1)
		d.clock += STEP
		d.place(cam, Vector3.ZERO, false, STEP)
		if shots.is_empty() or shots[-1] != int(d.shot):
			shots.append(int(d.shot))
	return shots


func test_the_steady_shot_then_the_crowd() -> void:
	var d := MwIntroDirector3D.new(9)
	var cam := _camera()
	_run(d, cam, 0.2)
	var steady := cam.transform
	assert_eq(int(d.shot), MwIntroDirector3D.TV_STEADY)
	var eye := MwIntroDirector3D.TV_EYE
	assert_almost_eq(cam.transform.origin, MwRink3D.world(eye.x, eye.y, eye.z), Vector3.ONE * 0.01,
			"from where the TV camera stands")
	_run(d, cam, 3.7)
	assert_eq(int(d.shot), MwIntroDirector3D.TV_STEADY, "4 s")
	assert_true(cam.transform.is_equal_approx(steady), "still")
	var shots := _run(d, cam, 6.0)
	shots.pop_front()
	assert_between(shots.size(), 2, 3, "two or three of the crowd's shots: %s" % str(shots))
	for shot_id: int in shots:
		assert_has(CROWD_SHOTS, shot_id, "the crowd's")


func test_then_the_players_from_its_own_seed() -> void:
	if not need_rom():
		return
	var runs := []
	for seed_value in [3, 3, 4]:
		var d := MwIntroDirector3D.new(seed_value)
		d.cast = MwIntroCast.new(rom, rehearsal, 7)
		var cam := _camera()
		_run(d, cam, MwIntroDirector3D.STEADY_S + MwIntroDirector3D.CROWD_S)
		var run_shots := _run(d, cam, 40.0)
		runs.append(run_shots)
	var shots: Array = runs[0].duplicate()
	if shots[0] in CROWD_SHOTS:
		shots.pop_front()                 # (the crowd's last shot, a tick over)
	assert_eq(shots[0], MwIntroDirector3D.DOOR, "the door as the first come out")
	var players := 0
	for shot_id: int in shots:
		assert_ne(shot_id, MwIntroDirector3D.TV_STEADY)
		if shot_id in [MwIntroDirector3D.DANCER, MwIntroDirector3D.TRACK]:
			players += 1
	assert_gt(players, 0, "the players' shots: %s" % str(shots))
	assert_gt(shots.size(), 8, "shots of 2.6-4.5 s")
	assert_eq(runs[0], runs[1], "the same seed the same shots")
	assert_ne(runs[0], runs[2], "another seed, others")


func test_the_glide_ends_on_the_matchs_view() -> void:
	var d := MwIntroDirector3D.new(5)
	d.final = {"transform": MwRinkCamera3D.looking(Vector3(-300, 0, 260), Vector3(0, 0, 0)), "fov": 44.0,
			"ortho": false, "scale": Vector3.ONE}
	var cam := _camera()
	_run(d, cam, 13.0)
	d.begin_hand_over()
	assert_eq(int(d.shot), MwIntroDirector3D.HAND_OVER)
	var from := cam.transform
	_run(d, cam, MwIntroDirector3D.HAND_S * 0.5)
	assert_false(d.handed_over(), "gliding")
	assert_false(cam.transform.is_equal_approx(from), "on its way")
	_run(d, cam, MwIntroDirector3D.HAND_S * 0.5 + STEP)
	assert_true(d.handed_over())
	var to: Transform3D = d.final["transform"]
	assert_almost_eq(cam.transform.origin, to.origin, Vector3.ONE * 0.01, "at the match's camera")
	assert_almost_eq(cam.transform.basis.z, to.basis.z, Vector3.ONE * 0.001, "looking its way")
	assert_almost_eq(cam.fov, 44.0, 0.01)


func test_the_glide_ends_on_each_views_first_frame() -> void:
	# owner: the entry scene's end into the game was far from seamless, the
	# camera cutting hard - the camera widens the director's lens in a taller
	# picture, and ORTHO's world is scaled: the glide ends on what the match's
	# camera shows, either way
	var shown := Vector2(MwMatchup.RINK_CAMERA)
	var modes := MwRinkCamera3D.Mode
	for size in [Vector2(320, 224), Vector2(480, 270)]:
		for mode in [modes.FOLLOW, modes.ORTHO, modes.TV, modes.DOLLY, modes.BIRDS_EYE]:
			var d := MwIntroDirector3D.new(5)
			d.final = MwIntroDirector3D.match_view(mode, shown, null, size)
			var cam := _camera()
			cam.view = size
			cam.director = d
			cam.mode = modes.CINEMATIC
			for i in 600 + int(MwIntroDirector3D.HAND_S * 60.0) + 2:
				if i == 600:
					d.begin_hand_over()
				d.clock += STEP
				cam.dt = STEP
				cam.follow(shown)
			var what := "mode %d in %s" % [mode, size]
			var to: Transform3D = d.final["transform"]
			assert_almost_eq(cam.transform.origin, to.origin, Vector3.ONE * 0.01, what)
			assert_almost_eq(cam.transform.basis.z, to.basis.z, Vector3.ONE * 0.001, what)
			assert_almost_eq(cam.fov, float(d.final["fov"]), 0.01, what + ": the lens as the match's")
			assert_eq(cam.world_scale(), d.final["scale"], what + ": the world's scale")


## Owner, 2026-10-09: the sweeps tilted down too far and swung round too
## fast. Never more than 40 degrees down (the steady TV shot's 37), never
## turning faster than 60 deg/s but at a cut - glides included (heading and
## tilt blended, MwRinkCamera3D.blend_view; too far for a glide: a cut).
func test_calm_sweeps() -> void:
	if not need_rom():
		return
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var d := MwIntroDirector3D.new(seed_value)
		d.cast = MwIntroCast.new(rom, rehearsal, 7)
		var cam := _camera()
		var last := Vector3.ZERO
		var shot := -1
		var steepest := 0.0
		var fastest := 0.0
		for i in 60 * 45:
			d.cast.step(1)
			d.clock += STEP
			d.place(cam, Vector3.ZERO, false, STEP)
			var f := -cam.transform.basis.z
			steepest = maxf(steepest, rad_to_deg(asin(clampf(-f.y, -1.0, 1.0))))
			if int(d.shot) == shot and d.time > 1.5 * STEP and last != Vector3.ZERO:
				fastest = maxf(fastest, rad_to_deg(last.angle_to(f)) / STEP)
			shot = int(d.shot)
			last = f
		assert_lt(steepest, 40.0, "seed %d: looks down at most 40 degrees" % seed_value)
		assert_lt(fastest, 60.0, "seed %d: turns at most 60 deg/s" % seed_value)


## A glide's heading goes the shorter way round and its tilt stays between
## the two ends' (a slerp of views half a turn apart looks straight down).
func test_blend_view() -> void:
	var a := MwRinkCamera3D.looking(Vector3(0, -200, 200), Vector3(0, 0, 0))    # facing +y, 45 down
	var b := MwRinkCamera3D.looking(Vector3(0, 200, 200), Vector3(0, 0, 0))     # facing -y, 45 down
	for e in [0.25, 0.5, 0.75]:
		var t := MwRinkCamera3D.blend_view(a, b, e)
		var tilt := rad_to_deg(MwRinkCamera3D.heading_tilt(t.basis).y)
		assert_almost_eq(tilt, -45.0, 0.5, "the tilt stays")
		assert_almost_eq(t.basis.x.y, 0.0, 1e-4, "no roll")
	assert_true(MwRinkCamera3D.blend_view(a, b, 1.0).is_equal_approx(b), "the end itself")
