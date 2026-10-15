extends "res://test/rom/rom_test_base.gd"
## Plan 44's 2D EXTENDED (owner: the unused orthographic 3D view, zooming to
## fit every human player on screen as the 3D EXTENDED view does, built on its
## code so the two behave the same; MwRinkCamera3D.Mode.EXTENDED_ORTHO):
## 3D EXTENDED's framing with ORTHO's lens in ORTHO's world - ORTHO's own
## picture while the targets are in it, widened for them, the whole rink at
## the far limit, ORTHO's look kept (its pitch and lens, only further back),
## and over a simulated match with players driving every target in the
## picture.

const PASSES := 600
const ROOT2 := 1.4142135623730951


func _camera(mode := MwRinkCamera3D.Mode.EXTENDED_ORTHO, size := MwRink3D.SCREEN) -> MwRinkCamera3D:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	add_child_autofree(vp)
	var cam := MwRinkCamera3D.new()
	cam.view = Vector2(size)
	cam.mode = mode
	vp.add_child(cam)
	cam.current = true
	return cam


func _shot(puck: Vector3, drivers: Array = [], look: Variant = null) -> MwRinkShot3D:
	var shot := MwRinkShot3D.new()
	shot.puck = puck
	shot.look = Vector3(puck.x, puck.y, 0) if look == null else look
	shot.drivers = PackedVector3Array(drivers)
	for i in drivers.size():
		shot.driver_keys.append("t0.p%d.0" % i)
	return shot


static func _shown(look: Vector3) -> Vector2:
	return MwRink3D.map_point(look.x, look.y, 0.0) - Vector2(MwRink3D.SCREEN) / 2.0


static func _place(cam: MwRinkCamera3D, shot: MwRinkShot3D, dt: float) -> void:
	cam.shot = shot
	cam.dt = dt
	cam.follow(_shown(shot.look))


## Where rink point [param point] shows in [param cam]'s picture (px), the world
## scaled as the view scales it for the camera's mode (ORTHO's: sqrt 2).
static func _screen(cam: MwRinkCamera3D, point: Vector3) -> Vector2:
	var w := MwRink3D.world(point.x, point.y, point.z) * cam.world_scale()
	if cam.is_position_behind(w):
		return Vector2(-1e6, -1e6)
	return cam.unproject_position(w)


static func _outside(cam: MwRinkCamera3D, tol := 0.5) -> Array:
	var out := []
	var targets := cam.shot.targets()
	for i in targets.size():
		var t := targets[i]
		var pts := [Vector3(t.x, t.y, 0.0)] if i == 0 else [t, t + Vector3(0, 0, cam.skater_height_px)]
		for point: Vector3 in pts:
			var screen_point := _screen(cam, point)
			if screen_point.x < -tol or screen_point.y < -tol or screen_point.x > cam.view.x + tol \
					or screen_point.y > cam.view.y + tol:
				out.append([point, screen_point])
	return out


## Where ORTHO's own picture of the ice at [param look] (its corners on the
## ice) shows in [param cam]'s (px).
func _ortho_picture(cam: MwRinkCamera3D, look: Vector3) -> Rect2:
	var o := _camera(MwRinkCamera3D.Mode.ORTHO, Vector2i(cam.view))
	o.follow(_shown(look))
	var r := Rect2()
	for i in 4:
		var px := Vector2(0.0 if i % 2 == 0 else cam.view.x, 0.0 if i < 2 else cam.view.y)
		var from := o.project_ray_origin(px)
		var dir := o.project_ray_normal(px)
		var hit := from + dir * (-from.y / dir.y)
		var screen_point := cam.unproject_position(hit)
		r = Rect2(screen_point, Vector2.ZERO) if i == 0 else r.expand(screen_point)
	return r


func test_the_lens_is_orthos() -> void:
	var cam := _camera()
	assert_eq(cam.world_scale(), Vector3(1, ROOT2, ROOT2), "ORTHO's world: the original's projection")
	assert_eq(cam.ext_space(), Vector3(1, ROOT2, ROOT2))
	assert_almost_eq(cam.ext_pitch(), deg_to_rad(45.0), 1e-6)
	assert_almost_eq(cam.ext_fov(), cam.ortho_fov(), 1e-6)
	assert_eq(cam.ext_base_px(), cam.ortho_distance_px)
	assert_eq(cam.cut_boards(), MwRinkShape.BOARD.y, "the stands cut away as ORTHO's")
	var three := _camera(MwRinkCamera3D.Mode.EXTENDED)
	assert_eq(three.ext_space(), Vector3.ONE, "3D EXTENDED: the rink's own space, FOLLOW's lens")
	assert_eq(three.ext_base_px(), three.distance_px)


func test_with_the_players_in_orthos_picture_it_is_ortho() -> void:
	var cam := _camera()
	var o := _camera(MwRinkCamera3D.Mode.ORTHO)
	var look := Vector3(-20, 60, 0)
	var near := _shot(Vector3(20, 40, 0), [Vector3(30, 50, 0)], look)
	_place(cam, near, 0.0)
	o.follow(_shown(look))
	assert_almost_eq(cam.extended_distance(), cam.ortho_distance_px, 0.01, "ORTHO's distance")
	assert_almost_eq(cam.transform.origin, o.transform.origin, Vector3.ONE * 0.001, "ORTHO's picture")
	assert_almost_eq(cam.transform.basis.z, o.transform.basis.z, Vector3.ONE * 0.0001, "its 45 deg")
	assert_almost_eq(cam.fov, o.fov, 0.0001, "its long lens")
	assert_almost_eq(_screen(cam, near.puck), _screen(o, near.puck), Vector2.ONE * 0.01,
			"the puck where the 2D has it")
	assert_eq(_outside(cam), [])
	for i in 60:
		_place(cam, _shot(Vector3(20, 40, 0), [Vector3(-150, -250, 0)], look), 1.0 / 30.0)
	assert_gt(cam.extended_distance(), cam.ortho_distance_px * 1.2, "apart: further back")
	assert_eq(_outside(cam), [], "everyone in the picture")
	assert_almost_eq(cam.fov, o.fov, 0.0001, "the same lens: only further back (ORTHO's look kept)")
	var r := _ortho_picture(cam, look)
	assert_true(r.position.x >= -0.5 and r.position.y >= -0.5 and r.end.x <= 320.5 and r.end.y <= 224.5,
			"and all ORTHO shows: %s" % r)
	for i in 150:
		_place(cam, near, 1.0 / 30.0)
	assert_almost_eq(cam.extended_distance(), cam.ortho_distance_px, 0.01, "together again: ORTHO's distance")
	o.follow(_shown(look))
	assert_almost_eq(cam.transform.origin, o.transform.origin, Vector3.ONE * 0.001, "and ORTHO's picture")


func test_the_far_limit_shows_the_whole_rink() -> void:
	var cam := _camera()
	var far := cam.extended_far()
	var b := MwStands.BOARD
	_place(cam, _shot(Vector3(-b.x, -b.y, 0), [Vector3(b.x, b.y, 0)], Vector3.ZERO), 0.0)
	assert_lte(cam.extended_distance(), far + 0.01, "corner to corner: within the far limit")
	assert_gt(cam.extended_distance(), 0.7 * far)
	for x in [-b.x, b.x]:
		for y in [-b.y, b.y]:
			for z in [0.0, cam.skater_height_px]:
				var screen_point := _screen(cam, Vector3(x, y, z))
				assert_between(screen_point.x, -0.5, 320.5, "corner (%d, %d, %d)" % [x, y, z])
				assert_between(screen_point.y, -0.5, 224.5, "corner (%d, %d, %d)" % [x, y, z])
	assert_lt(cam.near, cam.transform.origin.length(), "the near plane short of the rink")
	assert_gt(cam.far, (cam.transform.origin - MwRink3D.world(0, -b.y, 0) * cam.world_scale()).length(),
			"and the far one past it")


func test_a_skater_shows_as_in_ortho() -> void:
	var cam := _camera()
	var o := _camera(MwRinkCamera3D.Mode.ORTHO)
	_place(cam, _shot(Vector3.ZERO), 0.0)
	o.follow(_shown(Vector3.ZERO))
	for point: Vector3 in [Vector3.ZERO, Vector3(0, 0, 48), Vector3(0, 48, 0), Vector3(100, -60, 20)]:
		assert_almost_eq(_screen(cam, point), _screen(o, point), Vector2.ONE * 0.05, "%s where ORTHO has it" % point)
	var foot := _screen(cam, Vector3(0, 0, 0))
	assert_almost_eq(foot.y - _screen(cam, Vector3(0, 0, 48)).y, 48.0, 1.5,
			"48 px up: about 48 px on screen (the long lens's 2 %)")
	assert_almost_eq(_screen(cam, Vector3(0, 48, 0)).y - foot.y, 48.0, 1.5,
			"48 px south: about 48 px down - the original's projection")


# --- a simulated match -----------------------------------------------------------------------------

## A match with bots on the pads, drawn as the rink scene draws it (each
## pass's shot and whether a cut came before it).
func _simulate(pads: int, seed_: int, passes := PASSES) -> Array:
	var s := MwRinkState.new()
	s.rng = MlhRng.new(seed_)
	var sim := MwRinkSim.new(rom, s)
	sim.cpu = MwRinkAI.new()
	var up := MwRinkUpdate.new(sim)
	MwReplay3D.use(up)
	var ph := MwRinkPhases.new(up)
	MwRinkMatch.start(sim, 3, 3, 7, pads, false, 2)
	s.period = 1
	s.period_minutes = 5
	s.clock = 300
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var dirs := [0x01, 0x02, 0x04, 0x08, 0x05, 0x09, 0x06, 0x0A, 0x00]
	var held := PackedInt32Array([0, 0, 0, 0])
	var left := PackedInt32Array([0, 0, 0, 0])
	var out := []
	var cut := true
	if ph.enter(5) >= 0:
		return out
	for i in passes:
		s.tick += 2
		up.pass_start(2)
		for pad in 4:
			var was := held[pad]
			left[pad] -= 1
			if left[pad] <= 0:
				left[pad] = rng.randi_range(6, 45)
				held[pad] = dirs[rng.randi() % dirs.size()]
			s.pads_held[pad] = held[pad]
			s.pads_new[pad] = held[pad] & ~was
		sim.run(2)
		up.after_segment(2)
		var to := ph.pass_end(2)
		if to >= 0:
			MwRinkMatch.rink_exit(sim, to)
			if ph.enter(5) >= 0:
				break
			cut = true
			continue
		up.draws([], MwRinkPhases.RULES_DRAWN, ph.overlays, ph.sprite_ops)
		var drawer := up.drawer as MwRinkDraw3D
		out.append({"shot": MwRinkShot3D.make(s, drawer.items, Vector2(s.camera.shown)), "cut": cut})
		cut = false
	return out


func test_over_a_match_every_driver_stays_in_the_picture() -> void:
	if not need_rom():
		return
	var passes := _simulate(4, 0x2D2D)                  # four players driving
	assert_gt(passes.size(), 300)
	var cam := _camera()
	var o := _camera(MwRinkCamera3D.Mode.ORTHO)
	var prev: MwRinkShot3D = null
	var worst := []
	var nearer := 0
	for k in passes.size():
		var shot: MwRinkShot3D = passes[k]["shot"]
		if passes[k]["cut"]:
			cam.snap()
			prev = null
		for f in 2:                                     # 60 frames a second
			var sh := MwRinkShot3D.blend(prev, shot, 0.5 * (f + 1))
			_place(cam, sh, 1.0 / 60.0)
			var bad := _outside(cam, 1.0)
			if not bad.is_empty() and worst.size() < 5:
				worst.append([k, f, bad])
			o.follow(_shown(sh.look))
			if cam.extended_distance() < cam.ortho_distance_px - 0.01:
				nearer += 1
		prev = shot
	assert_eq(worst, [], "every target in the picture (pass, frame, points)")
	assert_eq(nearer, 0, "never nearer than ORTHO (owner: as 3D EXTENDED is never nearer than 3D)")


## VIEW between 2D EXTENDED and 3D EXTENDED (plan 44: the match's group):
## each takes up its own framing at once, the other's springs left behind.
func test_switching_between_the_extended_views_cuts_to_each_ones_framing() -> void:
	var cam := _camera()
	var look := Vector3(0, 40, 0)
	var apart := _shot(Vector3(0, 40, 0), [Vector3(-150, -250, 0), Vector3(160, 300, 0)], look)
	for i in 30:
		_place(cam, apart, 1.0 / 30.0)
	var d_2d := cam.extended_distance()
	cam.mode = MwRinkCamera3D.Mode.EXTENDED
	_place(cam, apart, 1.0 / 60.0)
	var three := _camera(MwRinkCamera3D.Mode.EXTENDED)
	_place(three, apart, 0.0)
	assert_almost_eq(cam.extended_distance(), three.extended_distance(), 0.01, "3D EXTENDED's own distance")
	assert_almost_eq(cam.transform.origin, three.transform.origin, Vector3.ONE * 0.001, "and picture")
	assert_eq(_outside(cam), [])
	cam.mode = MwRinkCamera3D.Mode.EXTENDED_ORTHO
	_place(cam, apart, 1.0 / 60.0)
	assert_almost_eq(cam.extended_distance(), d_2d, d_2d * 0.05, "back: 2D EXTENDED's")
	assert_eq(_outside(cam), [])
