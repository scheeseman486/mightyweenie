extends "res://test/rom/rom_test_base.gd"
## Plan 34's 3D EXTENDED (owner: a camera zooming in and out to keep every
## human-controlled player in frame as well as the puck; then never zoomed in
## closer than the regular 3D camera, and as much of the field round the puck
## covered as that one covers; MwRinkCamera3D.Mode.EXTENDED,
## MwRinkShot3D.targets): its framing - the follow camera's picture at the
## least, widened for the targets -, its springs at any frame rate, its
## cuts; every target and all the follow camera shows inside the picture
## over simulated matches with players driving (bots on the pads) and on
## their replays, without pumping or the floor holding the zoom (it
## juddered), and the follow camera's picture exactly
## while the players are in it; the CAMERA setting; and the simulation the
## same match whether it is drawn in 2D or 3D EXTENDED.

## Passes a simulated match runs (2 ticks each: 30 s of play).
const PASSES := 900

var host: Node
var _saved_path := ""
var _saved_camera := 0


func before_each() -> void:
	_saved_path = MwSettings.path
	_saved_camera = MwSettings.camera


func after_each() -> void:
	MwSettings.path = _saved_path
	MwSettings.camera = _saved_camera
	MwLiveInput.turns = PackedInt32Array([0, 0, 0, 0])
	if host != null and is_instance_valid(host):
		host.free()
	host = null


## The pads of players 1-4 held as bots do: a direction (or none) for a
## while, now and then with B or C, from a generator of their own (never
## the game's random numbers).
class Bots:
	const DIRS := [0x01, 0x02, 0x04, 0x08, 0x05, 0x09, 0x06, 0x0A, 0x00]
	var rng := RandomNumberGenerator.new()
	var held := PackedInt32Array([0, 0, 0, 0])
	var left := PackedInt32Array([0, 0, 0, 0])

	func _init(seed_: int) -> void:
		rng.seed = seed_

	## The next pass's pads: [held, newly pressed] per pad.
	func next() -> Array:
		var out := []
		for pad in 4:
			var was := held[pad]
			left[pad] -= 1
			if left[pad] <= 0:
				left[pad] = rng.randi_range(6, 45)
				held[pad] = DIRS[rng.randi() % DIRS.size()]
				if rng.randf() < 0.3:
					held[pad] |= 0x10 if rng.randf() < 0.5 else 0x20
			out.append([held[pad], held[pad] & ~was])
		return out


## [Bots] as an input source for the router (players 1-4's gameplay verbs).
class BotInput extends MwInputSource:
	var bots: Bots
	var ticks := 0
	var held := {}

	func _init(seed_: int) -> void:
		bots = Bots.new(seed_)

	func tick() -> void:
		ticks += 1
		if ticks % 2 == 0:
			held = {}
			var pads := bots.next()
			for pad in 4:
				var bits: int = pads[pad][0]
				var names := {0x01: "move_up", 0x02: "move_down", 0x04: "move_left", 0x08: "move_right",
						0x10: "pass", 0x20: "wrist_shot"}
				for b: int in names:
					if bits & b:
						held["p%d_%s" % [pad + 1, names[b]]] = true

	func sample(_contexts: Array) -> Dictionary:
		return held.duplicate()


func _camera(size := MwRink3D.SCREEN) -> MwRinkCamera3D:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	add_child_autofree(vp)
	var cam := MwRinkCamera3D.new()
	cam.view = Vector2(size)
	cam.mode = MwRinkCamera3D.Mode.EXTENDED
	vp.add_child(cam)
	cam.current = true
	return cam


## The follow camera (the regular 3D) in a picture of [param size].
func _follow_camera(size := MwRink3D.SCREEN) -> MwRinkCamera3D:
	var cam := _camera(size)
	cam.mode = MwRinkCamera3D.Mode.FOLLOW
	return cam


## A shot of [param puck] and [param drivers], the 2D camera looking at
## [param look] (default: the puck).
func _shot(puck: Vector3, drivers: Array = [], look: Variant = null) -> MwRinkShot3D:
	var shot := MwRinkShot3D.new()
	shot.puck = puck
	shot.look = Vector3(puck.x, puck.y, 0) if look == null else look
	shot.drivers = PackedVector3Array(drivers)
	for i in drivers.size():
		shot.driver_keys.append("t0.p%d.0" % i)
	return shot


## The sim camera's point (the 2D screen's top-left map point) whose screen
## centre is over rink point [param look].
static func _shown(look: Vector3) -> Vector2:
	return MwRink3D.map_point(look.x, look.y, 0.0) - Vector2(MwRink3D.SCREEN) / 2.0


## Places [param cam] for [param shot] (the sim camera over its look point)
## over [param dt] s.
static func _place(cam: MwRinkCamera3D, shot: MwRinkShot3D, dt: float) -> void:
	cam.shot = shot
	cam.dt = dt
	cam.follow(_shown(shot.look))


## True when [param cam] (3D EXTENDED) shows all the follow camera shows
## for its shot's look point: FOLLOW's eye inside its view - a camera of the
## same heading and lens that sees it sees everything FOLLOW sees.
static func _sees_follow(cam: MwRinkCamera3D, tol := 0.0005) -> bool:
	var eye := cam.follow_eye(cam.shot.look)
	var c := cam.transform.affine_inverse() * MwRink3D.world(eye.x, eye.y, eye.z)
	var depth := -c.z
	var t := cam.half_tans()
	return depth >= -tol and absf(c.x) <= t.x * depth + tol and absf(c.y) <= t.y * depth + tol


## Where the follow camera's picture of the ice at [param look] shows in
## [param cam]'s (px): the box round its corners on the ice.
func _follow_picture(cam: MwRinkCamera3D, look: Vector3) -> Rect2:
	var fol := _follow_camera(Vector2i(cam.view))
	fol.follow(_shown(look))
	var r := Rect2()
	for i in 4:
		var px := Vector2(0.0 if i % 2 == 0 else cam.view.x, 0.0 if i < 2 else cam.view.y)
		var from := fol.project_ray_origin(px)
		var dir := fol.project_ray_normal(px)
		var hit := from + dir * (-from.y / dir.y)
		var screen_point := cam.unproject_position(hit)
		r = Rect2(screen_point, Vector2.ZERO) if i == 0 else r.expand(screen_point)
	return r


## Where rink point [param point] shows in [param cam]'s picture (px); a point
## behind the camera far outside.
static func _screen(cam: MwRinkCamera3D, point: Vector3) -> Vector2:
	var w := MwRink3D.world(point.x, point.y, point.z)
	if cam.is_position_behind(w):
		return Vector2(-1e6, -1e6)
	return cam.unproject_position(w)


## The targets of [param cam]'s shot that are not inside its picture (their
## point on the ice and a skater's height above a driver; [param tol] px).
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


## The times a series turns back ([param zone]: it must go that far the
## other way first, so jitter is not counted).
static func _reversals(series: Array, zone: float) -> int:
	var n := 0
	var dir := 0
	var hi: float = series[0] if not series.is_empty() else 0.0
	var lo := hi
	for x: float in series:
		hi = maxf(hi, x)
		lo = minf(lo, x)
		if dir != -1 and x < hi - zone:
			n += 1 if dir == 1 else 0
			dir = -1
			lo = x
		elif dir != 1 and x > lo + zone:
			n += 1 if dir == -1 else 0
			dir = 1
			hi = x
	return n


func test_turns_are_counted_past_their_zone() -> void:
	assert_eq(_reversals([0.0, 10.0, 20.0, 18.0, 25.0, 5.0, 6.0, 30.0], 4.0), 2, "down at 5, up at 30")
	assert_eq(_reversals([0.0, 1.0, 0.0, 1.0, 0.0], 4.0), 0, "jitter")


# --- a simulated match ---------------------------------------------------------------------------

## A match on the rink with [param pads] (the original's pad mode) and bots
## on them for up to [param passes] passes, drawn in 3D as the rink scene
## draws it: each pass's shot (MwRinkShot3D.make over its MwRinkDraw3D
## items) and whether a cut came before it (a rink entry: the faceoff line-up
## after a goal). Stops early when the match leaves the rink for good.
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
	var bots := Bots.new(seed_)
	var out := []
	var cut := true
	if ph.enter(5) >= 0:
		return out
	for i in passes:
		var pp := bots.next()
		s.tick += 2
		up.pass_start(2)
		for pad in 4:
			s.pads_held[pad] = pp[pad][0]
			s.pads_new[pad] = pp[pad][1]
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


## [param passes] (from [method _simulate]) through [param cam] at
## [param fps] rendered frames a second, blending between passes as the
## view does (MwRinkView3D.auto_blend: pass k shown, the way from pass k - 1
## to it by the share of its time gone by); [param each] is called after
## every frame with the frame's time (s).
static func _film(cam: MwRinkCamera3D, passes: Array, fps: int, each: Callable) -> void:
	var frames := int(passes.size() * fps / 30.0)
	var prev: MwRinkShot3D = null
	var at := -1
	for j in range(1, frames + 1):
		var time := float(j) / fps
		var k := mini(int(floor(time * 30.0 + 1e-6)), passes.size() - 1)
		var t := time * 30.0 - k
		if k != at:
			if passes[k]["cut"]:
				cam.snap()
				prev = null
			else:
				prev = passes[at]["shot"] if at >= 0 else null
			at = k
		var shot: MwRinkShot3D = passes[k]["shot"]
		_place(cam, MwRinkShot3D.blend(prev, shot, maxf(t, 0.0)), 1.0 / fps)
		each.call(time)


# --- the framing --------------------------------------------------------------------------------

func test_with_the_players_in_follows_picture_it_is_follow() -> void:
	var cam := _camera()
	var fol := _follow_camera()
	var look := Vector3(-20, 60, 0)                  # the 2D camera leading the puck a little
	var near := _shot(Vector3(20, 40, 0), [Vector3(30, 50, 0)], look)
	_place(cam, near, 0.0)
	_place(fol, near, 0.0)
	assert_almost_eq(cam.extended_distance(), cam.distance_px, 0.001, "FOLLOW's distance")
	assert_almost_eq(cam.extended_at(), look, Vector3.ONE * 0.001, "and its point (owner: no nearer than 3D)")
	assert_almost_eq(cam.transform.origin, fol.transform.origin, Vector3.ONE * 0.0001, "FOLLOW's picture")
	assert_almost_eq(cam.transform.basis.z, fol.transform.basis.z, Vector3.ONE * 0.0001)
	assert_almost_eq(cam.fov, fol.fov, 0.0001, "the follow camera's lens")
	assert_almost_eq(_screen(cam, near.puck), _screen(fol, near.puck), Vector2.ONE * 0.01,
			"the puck where FOLLOW has it: the same room round it (owner)")
	assert_eq(_outside(cam), [])
	for i in 60:
		_place(cam, _shot(Vector3(20, 40, 0), [Vector3(-150, -200, 0)], look), 1.0 / 30.0)
	assert_gt(cam.extended_distance(), cam.distance_px + 50.0, "apart: further")
	assert_true(_sees_follow(cam), "and still all FOLLOW shows")
	for i in 150:
		_place(cam, near, 1.0 / 30.0)
	assert_almost_eq(cam.extended_distance(), cam.distance_px, 0.01, "together again: FOLLOW's distance")
	assert_almost_eq(cam.extended_at(), look, Vector3.ONE * 0.01, "and point")


func test_the_least_picture_that_shows_follows_and_every_target() -> void:
	var cam := _camera()
	var look := Vector3(0, 0, 0)
	var targets := PackedVector3Array([Vector3(-60, 0, 0), Vector3(60, -190, 0), Vector3(30, 60, 0)])
	var goal := cam.extended_goal(targets, look)
	_place(cam, _shot(targets[0], [targets[1], targets[2]], look), 0.0)
	assert_almost_eq(cam.extended_at(), goal[0], Vector3.ONE * 0.001)
	assert_eq(_outside(cam), [], "everyone in the picture")
	assert_true(_sees_follow(cam), "and all FOLLOW shows")
	assert_gt(cam.extended_distance(), cam.distance_px + 20.0, "further than FOLLOW")
	# the least: a target's margin or FOLLOW's picture on an edge of the picture each way
	var pts := PackedVector3Array()
	for t in targets:
		pts.append_array(MwRinkCamera3D.box(PackedVector3Array([t]), cam.extended_margin_px, cam.skater_height_px))
	var edges := Vector4(INF, INF, INF, INF)            # px inside the left, right, top, bottom edges
	for c in pts:
		var screen_point := _screen(cam, c)
		edges = Vector4(minf(edges.x, screen_point.x), minf(edges.y, 320.0 - screen_point.x),
				minf(edges.z, screen_point.y), minf(edges.w, 224.0 - screen_point.y))
	var fs := _follow_picture(cam, look)
	edges = Vector4(minf(edges.x, fs.position.x), minf(edges.y, 320.0 - fs.end.x), minf(edges.z, fs.position.y),
			minf(edges.w, 224.0 - fs.end.y))
	gut.p("room inside the edges (left, right, top, bottom): %s" % edges)
	for i in 4:
		assert_gte(edges[i], -0.05, "inside edge %d" % i)
	assert_true(absf(edges.z) < 0.05 and absf(edges.w) < 0.05 or absf(edges.x) < 0.05 and absf(edges.y) < 0.05,
			"touching top and bottom, or left and right")
	# the point a little off and the same picture needs more distance
	var tans := cam.half_tans()
	var musts := pts.duplicate()
	musts.append(cam.follow_eye(look))
	var d: float = goal[1]
	assert_almost_eq(MwRinkCamera3D.reach(musts, goal[0], tans, deg_to_rad(cam.pitch_deg)), d, 0.01, "reach agrees")
	for off: Vector3 in [Vector3(8, 0, 0), Vector3(-8, 0, 0), Vector3(0, 8, 0), Vector3(0, -8, 0)]:
		assert_gt(MwRinkCamera3D.reach(musts, goal[0] + off, tans, deg_to_rad(cam.pitch_deg)), d - 0.01,
				"no nearer from %s" % off)


func test_the_far_limit_shows_the_whole_rink() -> void:
	var cam := _camera()
	var far := cam.extended_far()
	var b := MwStands.BOARD
	_place(cam, _shot(Vector3(-b.x, -b.y, 0), [Vector3(b.x, b.y, 0)], Vector3.ZERO), 0.0)
	assert_lte(cam.extended_distance(), far + 0.01, "corner to corner: within the far limit (it looks from centre ice)")
	assert_gt(cam.extended_distance(), 0.7 * far, "but not much nearer")
	for x in [-b.x, b.x]:
		for y in [-b.y, b.y]:
			for z in [0.0, cam.skater_height_px]:
				var screen_point := _screen(cam, Vector3(x, y, z))
				assert_between(screen_point.x, -0.5, 320.5, "corner (%d, %d, %d)" % [x, y, z])
				assert_between(screen_point.y, -0.5, 224.5, "corner (%d, %d, %d)" % [x, y, z])
	# the puck at one end, the 2D camera there, players at the other corners
	var look := Vector3(0, b.y - 100, 0)
	_place(cam, _shot(Vector3(0, b.y - 10, 0), [Vector3(-b.x, -b.y, 0), Vector3(b.x, -b.y, 0)], look), 0.0)
	assert_lte(cam.extended_distance(), far * MwRinkCamera3D.EXTENDED_OVER)
	assert_eq(_outside(cam), [], "everyone in the picture")
	assert_true(_sees_follow(cam), "and FOLLOW's")


func test_a_wide_picture_needs_less_distance_for_players_side_by_side() -> void:
	var shot := _shot(Vector3(0, 0, 0), [Vector3(-180, 0, 0), Vector3(180, 0, 0)])
	var base := _camera()
	_place(base, shot, 0.0)
	var wide := _camera(Vector2i(398, 224))
	_place(wide, shot, 0.0)
	assert_lt(wide.extended_distance(), base.extended_distance() - 20.0, "WIDE: nearer for the same players")
	assert_eq(_outside(base), [])
	assert_eq(_outside(wide), [])
	assert_true(_sees_follow(wide), "and all FOLLOW shows in WIDE")
	var tall := _camera(Vector2i(320, 260))
	_place(tall, shot, 0.0)
	assert_eq(_outside(tall), [], "a picture taller than the original's too")
	assert_true(_sees_follow(tall))
	assert_almost_eq(tall.extended_distance(), base.extended_distance(), 0.5, "the same 320 across")


func test_without_drivers_the_puck_alone_and_an_old_frame_takes_player_ones_rider() -> void:
	var shot := _shot(Vector3(5, 6, 0))
	assert_eq(shot.targets(), PackedVector3Array([Vector3(5, 6, 0)]), "CPU v CPU: the puck")
	shot.puck = Vector3(5, 6, 112)
	assert_eq(shot.targets(), PackedVector3Array([Vector3(5, 6, 0)]), "on the ice under it (the faceoff's drop)")
	shot.rider_is_p1 = true
	shot.rider_at = Vector3(90, 10, 0)
	assert_eq(shot.targets(), PackedVector3Array([Vector3(5, 6, 0), Vector3(90, 10, 0)]),
			"a 3D frame recorded before plan 34: player 1's player")
	shot.drivers = PackedVector3Array([Vector3(1, 2, 0)])
	assert_eq(shot.targets(), PackedVector3Array([Vector3(5, 6, 0), Vector3(1, 2, 0)]), "the drivers when recorded")


# --- the springs --------------------------------------------------------------------------------

func test_zooming_out_is_quicker_than_zooming_in() -> void:
	var cam := _camera()
	cam.extended_margin_px = 100.0            # room enough that the springs alone move it
	var near := _shot(Vector3.ZERO, [Vector3(10, 0, 0)])
	var apart := _shot(Vector3.ZERO, [Vector3(-120, -150, 0), Vector3(120, 150, 0)])
	_place(cam, near, 0.0)
	var d0 := cam.extended_distance()
	var d1: float = cam.extended_goal(apart.targets(), apart.look)[1]
	assert_gt(d1 - d0, 150.0)
	var out_t := -1.0
	for i in 240:
		_place(cam, apart, 1.0 / 60.0)
		if out_t < 0.0 and cam.extended_distance() >= d0 + 0.9 * (d1 - d0):
			out_t = (i + 1) / 60.0
	var d2 := cam.extended_distance()
	assert_almost_eq(d2, d1, d1 * cam.extended_dead + 0.01, "out: within the dead zone of what is asked")
	var in_t := -1.0
	var held := 0.0
	for i in 360:
		_place(cam, near, 1.0 / 60.0)
		if cam.extended_distance() >= d2 - 0.5:
			held = (i + 1) / 60.0
		if in_t < 0.0 and cam.extended_distance() <= d2 - 0.9 * (d2 - d0):
			in_t = (i + 1) / 60.0
	assert_between(out_t, 0.15, 0.35, "out in about a quarter of a second")
	assert_between(held, 0.45, 0.6, "a nearer picture waits a moment")
	assert_between(in_t - held, 0.8, 1.2, "then in over about a second")
	assert_almost_eq(cam.extended_distance(), d0, d0 * cam.extended_dead + 0.01, "settled, within the dead zone")
	# players leaping apart (a cut aside): the floor keeps them in from the next frame on
	cam.extended_margin_px = 16.0
	_place(cam, near, 0.0)
	cam.snap()
	_place(cam, near, 0.0)
	_place(cam, _shot(Vector3.ZERO, [Vector3(-170, -40, 0), Vector3(170, 300, 0)]), 1.0 / 60.0)
	assert_eq(_outside(cam), [], "everyone in at once")


func test_a_small_change_is_ignored() -> void:
	var cam := _camera()
	var shot := _shot(Vector3(0, 0, 0), [Vector3(-160, -150, 0), Vector3(160, 60, 0)])
	_place(cam, shot, 0.0)
	var at := cam.extended_at()
	var d := cam.extended_distance()
	assert_gt(d, cam.distance_px + 50.0, "wider than FOLLOW")
	for i in 120:
		var j := Vector3(2.0 if i % 2 else -2.0, 1.0 if i % 3 else -1.0, 0)
		_place(cam, _shot(j, [Vector3(-160, -150, 0) + j, Vector3(160, 60, 0) - j], Vector3.ZERO), 1.0 / 60.0)
	assert_almost_eq(cam.extended_at(), at, Vector3.ONE * 0.001, "jitter inside the dead zone: the point stays")
	assert_almost_eq(cam.extended_distance(), d, 1.0, "and nearly the distance (the box itself breathes a little)")


func test_the_springs_are_the_same_at_any_frame_rate() -> void:
	for target: Variant in [100.0, Vector3(-40, 20, 3)]:
		var ends := []
		for fps in [30, 60, 144, 240]:
			var x: Variant = target * 0.0
			var v: Variant = target * 0.0
			for i in fps:
				var r := MwRinkCamera3D.spring(x, v, target, 6.0, 1.0 / fps)
				x = r[0]
				v = r[1]
			ends.append(x)
		for end: Variant in ends:
			assert_almost_eq(end, ends[0], target * 0.0 + (Vector3.ONE * 1e-4 if target is Vector3 else 1e-4),
					"exact: one second at any frame rate")
	assert_eq(MwRinkCamera3D.spring(3.0, 1.0, 9.0, 4.0, 0.0), [3.0, 1.0], "no time, no move")


func test_a_snap_jumps_and_a_cut_frame_has_no_easing() -> void:
	var cam := _camera()
	var look := Vector3(0, -200, 0)
	_place(cam, _shot(Vector3(0, -200, 0), [Vector3(10, -200, 0)]), 0.0)
	var there := _shot(Vector3(0, -200, 0), [Vector3(170, -300, 0), Vector3(-160, 150, 0)], look)
	_place(cam, there, 1.0 / 60.0)
	var goal := cam.extended_goal(there.targets(), there.look)
	assert_gt(cam.extended_at().distance_to(goal[0]), 50.0, "eased: on its way")
	cam.snap()
	_place(cam, there, 1.0 / 60.0)
	assert_almost_eq(cam.extended_at(), goal[0], Vector3.ONE * 0.001, "a cut: there at once")
	assert_almost_eq(cam.extended_distance(), goal[1], 0.001)


# --- matches ------------------------------------------------------------------------------------

func test_every_target_stays_in_the_picture_over_simulated_matches() -> void:
	if not need_rom():
		return
	for setup: Array in [[4, 11, MwRink3D.SCREEN], [3, 23, Vector2i(398, 224)], [0, 37, MwRink3D.SCREEN]]:
		var passes := _simulate(setup[0], setup[1])
		assert_gt(passes.size(), PASSES / 2, "pad mode %d: a match played" % setup[0])
		var drivers := 0
		for simulated_pass: Dictionary in passes:
			drivers = maxi(drivers, (simulated_pass["shot"] as MwRinkShot3D).drivers.size())
		assert_eq(drivers, {4: 4, 3: 3, 0: 1}[setup[0]], "pad mode %d: its players' characters" % setup[0])
		var cam := _camera(setup[2])
		var bad := []
		var hidden := []
		var dist := []
		var goals := []
		var held := [0]
		_film(cam, passes, 60, func(time: float) -> void:
			var o := _outside(cam)
			if not o.is_empty() and bad.size() < 5:
				bad.append([time, o])
			if not _sees_follow(cam) and hidden.size() < 5:
				hidden.append(time)
			dist.append(cam.extended_distance())
			goals.append(cam.extended_goal(cam.shot.targets(), cam.shot.look)[1])
			var d := cam.extended_distance()
			if d > cam.distance_px + 0.01 and absf(d - cam.extended_keep(cam.shot.targets(), cam.shot.look,
					cam.extended_at())) < 0.01:
				held[0] += 1)
		assert_eq(bad, [], "pad mode %d: every target in every frame" % setup[0])
		assert_eq(hidden, [], "pad mode %d: and all the follow camera shows (owner: no nearer than 3D)" % setup[0])
		var nearest: float = dist.min()
		var furthest: float = dist.max()
		assert_gte(nearest, cam.distance_px - 0.01, "never nearer than the follow camera")
		assert_lte(furthest, cam.extended_far() * MwRinkCamera3D.EXTENDED_OVER, "nor much past the far limit")
		assert_gt(furthest - nearest, 150.0 if setup[0] != 0 else 20.0, "pad mode %d: it zooms" % setup[0])
		# no pumping: the distance turns back no more often than what it frames
		# asks for (it adds no swings of its own), and seldom - these bots
		# switch players far more often than people do
		var seconds := dist.size() / 60.0
		var turns := _reversals(dist, 4.0)
		var asked := _reversals(goals, 4.0)
		var big := _reversals(dist, 16.0)
		gut.p("pad mode %d: %.0f s, distance %.0f-%.0f px, %d turns (16 px: %d; the goal %d)" % [setup[0],
				seconds, nearest, furthest, turns, big, asked])
		assert_lte(turns, asked, "pad mode %d: no turns of its own" % setup[0])
		assert_lt(float(big), seconds / 1.5, "pad mode %d: no pumping (%d turns in %.0f s)" % [setup[0], big, seconds])
		# the floor follows the play raw (its speeds change with every pass):
		# while it holds the distance the zoom judders (owner, 2026-10-12; it
		# held it in 9-29 % of these frames) - the spring keeps clear of it
		gut.p("pad mode %d: the floor held the distance in %d of %d frames" % [setup[0], held[0], dist.size()])
		assert_lt(float(held[0]) / dist.size(), 0.05, "pad mode %d: the floor seldom holds the distance" % setup[0])


func test_the_puck_has_follows_room_while_the_players_are_in_its_picture() -> void:
	if not need_rom():
		return
	for pads in [0, 4]:
		var passes := _simulate(pads, 41, 600)
		var cam := _camera()
		var fol := _follow_camera()
		var n := {"frames": 0, "follow": 0, "calm": 0, "same": 0, "wider": 0}
		var worst := [0.0, 0.0]                     # the camera's place (px), the puck on the screen (px)
		var calm := [0.0]
		_film(cam, passes, 60, func(_time: float) -> void:
			n["frames"] += 1
			fol.shot = cam.shot
			fol.follow(_shown(cam.shot.look))
			var gap := MwRink3D.rink(cam.transform.origin).distance_to(MwRink3D.rink(fol.transform.origin))
			if gap < 0.05:
				n["follow"] += 1
			if cam.extended_distance() > cam.distance_px + 0.05:
				n["wider"] += 1
			var goal := cam.extended_goal(cam.shot.targets(), cam.shot.look)
			var asks: bool = goal[1] - cam.distance_px < 0.001 \
					and (goal[0] as Vector3).distance_to(cam.shot.look) < 0.001
			calm[0] = calm[0] + 1.0 / 60.0 if asks else 0.0
			if calm[0] >= 4.0:                      # FOLLOW's picture all it has asked for, a while
				n["calm"] += 1
				var puck := cam.shot.puck
				var off := _screen(cam, puck).distance_to(_screen(fol, puck))
				worst[0] = maxf(worst[0], gap)
				worst[1] = maxf(worst[1], off)
				if gap < 0.05:
					n["same"] += 1)
		gut.p(("pad mode %d: %d frames, FOLLOW's picture in %d (%.0f %%), wider in %d; %d settled on FOLLOW's: the "
				+ "camera within %.3f px, the puck within %.3f px") % [
				pads, n["frames"], n["follow"], 100.0 * n["follow"] / n["frames"], n["wider"], n["calm"], worst[0],
				worst[1]])
		assert_gt(n["calm"], n["frames"] / 20, "pad mode %d: the players often in FOLLOW's picture" % pads)
		assert_eq(n["same"], n["calm"], "pad mode %d: then FOLLOW's picture exactly" % pads)
		assert_lt(worst[1], 0.05, "pad mode %d: the puck where FOLLOW shows it (owner: the same room round it)" % pads)


func test_the_camera_is_the_same_at_any_frame_rate_over_a_match() -> void:
	if not need_rom():
		return
	var passes := _simulate(4, 5, 600)
	var samples := {}
	for fps in [30, 60, 144, 240]:
		var cam := _camera()
		var got := []
		_film(cam, passes, fps, func(time: float) -> void:
			if absf(time - roundf(time)) < 1e-6:
				got.append([cam.extended_at(), cam.extended_distance()]))
		samples[fps] = got
	var worst_at := 0.0
	var worst_d := 0.0
	for fps in [60, 144, 240]:
		assert_eq(samples[fps].size(), samples[30].size())
		for i in samples[30].size():
			worst_at = maxf(worst_at, (samples[fps][i][0] as Vector3).distance_to(samples[30][i][0]))
			worst_d = maxf(worst_d, absf(samples[fps][i][1] - samples[30][i][1]) / samples[30][i][1])
	gut.p("frame rates: the point within %.2f px, the distance within %.2f %%" % [worst_at, worst_d * 100.0])
	assert_lt(worst_at, 1.5, "the point at each second, whatever the frame rate")
	assert_lt(worst_d, 0.015, "the distance too")


func test_the_drivers_are_the_characters_players_drive() -> void:
	if not need_rom():
		return
	for mode_n: Array in [[0, 1], [1, 2], [2, 2], [3, 3], [4, 4], [5, 0]]:
		var passes := _simulate(mode_n[0], 3, 30)
		var shot: MwRinkShot3D = passes[-1]["shot"]
		assert_eq(shot.drivers.size(), mode_n[1], "pad mode %d" % mode_n[0])
		assert_eq(shot.driver_keys.size(), shot.drivers.size())
		for k in shot.driver_keys:
			assert_true(k.begins_with("t"), k)
	var s := MwRinkState.new()
	var sim := MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 3, 3, 7, 4, false, 2)
	MwRinkPhases.new(MwRinkUpdate.new(sim)).enter(5)
	var driven := MwRinkShot3D.drivers_of(s)
	assert_eq(driven.size(), 4, "two a team")
	for p in driven:
		assert_true(p.flags & MwRinkState.Player.HUMAN != 0)
	driven[0].flags &= ~MwRinkState.Player.HUMAN
	assert_eq(MwRinkShot3D.drivers_of(s).size(), 3, "a character left to the CPU drops out")


## How a match is drawn never changes it - within its group of views: plan
## 44 made the group a match rule (EXTENDED: the humans' players count as on
## the original's screen wherever they are), so a 3D EXTENDED match is the
## same match as in 2D EXTENDED (the 3D view's orthographic camera), not as
## in 2D. (Written before the rink took the group from the match's rule,
## this test compared 3D EXTENDED with 2D and its run fell back to 3D;
## 2026-10-15.)
func test_a_match_drawn_in_3d_extended_is_the_same_match_as_in_2d_extended() -> void:
	if not need_rom():
		return
	var flat := _rink_run(MwRinkViews.EXTENDED_2D)
	var ext := _rink_run(MwRinkViews.EXTENDED)
	assert_gt(int(ext["placed"]), 100, "the 3D EXTENDED camera was placed every pass")
	assert_eq(int(flat["placed"]), 0, "2D EXTENDED: the orthographic camera")
	assert_eq(ext["screen"], flat["screen"], "the same screen at the end")
	assert_eq(ext["rng"], flat["rng"], "the same random numbers")
	assert_eq(MwSimDict.diff(ext["state"], flat["state"]), {}, "the same match")


## A live match on the rink scene with bots on players 1-4 (pad mode 4) in
## view [param view] for 30 s, a rendered frame between passes: the state,
## the random stream and the screen at the end; how often the 3D EXTENDED
## camera was placed. The options' camera is [param view] for it (the
## match's rules - an EXTENDED match or not - come from it at the rink's
## entry).
func _rink_run(view: int) -> Dictionary:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(0x61F2415D, 0x1234567)
	router.session.setup.pads = 4
	router.session.view = view
	var was := MwSettings.start_view
	MwSettings.start_view = view
	router.input = BotInput.new(77)
	var rink := (load(MwScreens.scene_path(4)) as PackedScene).instantiate() as MwRink
	rink.screen_id = 4
	router.adopt(rink, {"new_match": true})
	var placed := 0
	var rink_view := MwRink3DHost.of(get_tree()).view()
	for i in 1800:
		router.step()
		if router.current() == rink and MwRink3DHost.of(get_tree()).shown_for(rink):
			rink_view.blend_to(0.5, 1.0 / 60.0)
			if rink_view.camera.mode == MwRinkCamera3D.Mode.EXTENDED and rink_view.camera.shot != null:
				placed += 1
	var state: MwRinkState = router.session.screens["rink"]
	var out := {"state": MwSimDict.to_dict(state), "rng": router.session.rng.state, "screen": router.current_id(),
			"placed": placed}
	MwSettings.start_view = was
	host.free()
	host = null
	return out


func test_the_replay_frames_the_drivers_it_recorded() -> void:
	if not need_rom():
		return
	var s := MwRinkState.new()
	MwRinkMatch.start(MwRinkSim.new(rom, s), 0, 0, 5, 0, false, 2)
	s.period = 1
	s.clock = 180
	s = load("res://scenes/instant_replay/instant_replay.gd").demo_replay_state(rom, s)
	var side: Dictionary = s.replay.side.values()[0]
	var shot: MwRinkShot3D = side["shot"]
	assert_eq(shot.drivers.size(), 1, "player 1's character, recorded with the frame")
	var back := MwFullReplay.side_from_data(MwFullReplay.side_to_data(side))
	assert_eq((back["shot"] as MwRinkShot3D).drivers, shot.drivers, "kept in the whole match's store and the files")
	assert_eq((back["shot"] as MwRinkShot3D).driver_keys, shot.driver_keys)
	var old := MwFullReplay.side_to_data(side)
	old["shot"].erase("drivers")
	old["shot"].erase("driver_keys")
	var old_shot: MwRinkShot3D = MwFullReplay.side_from_data(old)["shot"]
	assert_true(old_shot.drivers.is_empty(), "a frame from before: no drivers")
	assert_eq(old_shot.targets().size(), 2, "the puck and player 1's player instead")
	# screen 7 in 3D EXTENDED: the recorded drivers and puck in the picture, frame by frame
	var node: MwBetweenPlays = (load(MwScreens.scene_path(7)) as PackedScene).instantiate()
	node.screen_id = 7
	node.previous = 5
	node.session = MwSession.new(1234, 5678)
	node.session.screens["rink"] = s
	node.session.view = MwRinkViews.EXTENDED
	add_child_autofree(node)
	node._enter_screen({})
	var view := MwRink3DHost.of(get_tree()).view()
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.EXTENDED)
	var bad := []
	var frames := 0
	for i in 400:
		node._screen_pass(1, MwInputFrame.make({}, {}))
		view.blend_to(0.5, 1.0 / 60.0)
		view.blend_to(1.0, 1.0 / 60.0)
		if view.camera.shot == null:
			continue
		frames += 1
		var o := _outside(view.camera)
		if not o.is_empty() and bad.size() < 5:
			bad.append([i, o])
	assert_gt(frames, 100)
	assert_eq(bad, [], "every recorded target in the picture")
	node.free()


## A rendered frame's blend after a pass, at its end (the pass's frame shows
## there: MwRinkView3D.present_frame with auto_blend) - once [param view] has
## a frame.
static func _rendered(view: MwRinkView3D) -> void:
	if not view._items.is_empty():
		view.blend_to(1.0)


func test_the_opening_hands_over_to_3d_extended_without_a_cut() -> void:
	if not need_rom():
		return
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(1, 1)
	router.session.setup.team_a = 3
	router.session.setup.team_b = 7
	router.session.setup.pads = 2               # two players on team A
	var was := MwSettings.start_view
	MwSettings.start_view = MwRinkViews.EXTENDED
	router.go(3, {}, false)
	router.step()
	var mu := router.current() as MwMatchup
	assert_not_null(mu.intro, "the 3D opening (plan 33)")
	var final: Dictionary = mu.intro.director.final
	var view := MwRink3DHost.of(get_tree()).view()
	var cam := view.camera
	var rehearsed := MwRinkShot3D.make(mu.intro.rehearsal.state, mu.intro.rehearsal.draw.items,
			Vector2(mu.intro.rehearsal.state.camera.shown))
	assert_eq(rehearsed.drivers.size(), 2, "it frames the players' characters as the rink will")
	for i in MwMatchup.LOAD_TICKS + 30:
		router.step()
		_rendered(view)
	mu._screen_pass(1, MwInputFrame.make(MwVerbs.pad_actions(1, MwVerbs.BITS["START"], [MwVerbs.Context.MATCHUP]), {}))
	var at_hand := Transform3D()
	for i in 2400:
		if router.current_id() == 4:
			break
		router.step()
		_rendered(view)
		if router.current() == mu and mu.intro != null and mu.intro.director.handed_over():
			at_hand = cam.transform
	assert_eq(router.current_id(), 4, "the rink")
	assert_eq(cam.mode, MwRinkCamera3D.Mode.EXTENDED, "in 3D EXTENDED")
	var to: Transform3D = final["transform"]
	assert_almost_eq(at_hand.origin, to.origin, Vector3.ONE * 0.001, "the opening ends on 3D EXTENDED's framing")
	assert_almost_eq(cam.transform.origin, to.origin, Vector3.ONE * 0.01, "and the rink starts there: no cut")
	assert_almost_eq(cam.transform.basis.z, to.basis.z, Vector3.ONE * 0.0001)
	assert_almost_eq(cam.fov, float(final["fov"]), 0.001)
	MwSettings.start_view = was                 # (the rink's entry takes the match's rules from it: kept till then)
	if is_instance_valid(mu) and not mu.is_inside_tree():
		mu.free()                               # (the router frees the screen it left on an idle frame)


# --- the settings -------------------------------------------------------------------------------

func test_the_camera_setting_keeps_3d_extended() -> void:
	MwSettings.path = "user://test_extended_camera.cfg"
	MwSettings.camera = MwSettings.CAMERAS.find("3D EXTENDED")
	assert_eq(MwSettings.camera, 3, "the fourth CAMERA value (plan 44: 2D EXTENDED before it)")
	assert_eq(MwSettings.view(), MwRinkViews.EXTENDED, "a match starts in it")
	MwSettings.save()
	MwSettings.camera = 0
	MwSettings.load_file()
	assert_eq(MwSettings.camera_name(), "3D EXTENDED", "saved and read back")
	assert_eq(MwSettings.view(), MwRinkViews.EXTENDED)
	# a file from before plan 44 (three cameras, saved by name): 3D EXTENDED is still 3D EXTENDED
	var cfg := ConfigFile.new()
	cfg.load(MwSettings.path)
	assert_eq(cfg.get_value("game", "camera"), "3D EXTENDED", "the file keeps the text, not the index")
	MwSettings.camera = MwSettings.CAMERAS.find("2D EXTENDED")
	MwSettings.save()
	MwSettings.camera = 0
	MwSettings.load_file()
	assert_eq([MwSettings.camera_name(), MwSettings.view()], ["2D EXTENDED", MwRinkViews.EXTENDED_2D],
			"2D EXTENDED saved and read back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
