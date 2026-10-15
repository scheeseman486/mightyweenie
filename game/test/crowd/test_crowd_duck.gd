extends "res://test/rom/rom_test_base.gd"
## The crowd makes way (owner, 2026-10-09; MwCrowdDuck, rink3d_crowd's
## duck_px): only fans who hide the rink move (the line of sight over their
## heads comes down on the ice); such a fan in front of a thing on the ice
## that he hides sinks until his head is just below its lowest pixel, those
## near it side to side less, out to a reach - wider and gentler during a
## goal; fans behind it or below it stay up. The things' tracks fade in and
## out and leave a wake, at any frame rate; their boxes ease from frame to
## frame and stop at the ice, a carried puck goes with its carrier, a fan's
## feet passing a thing's top ease him in - nothing jumps or snaps (owner);
## the 3D view hands them over each frame - the main 3D camera's (follow)
## only, with the switch on.

const PX := MwCrowdDuck.PX
const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")

## A skater-sized drawing standing on its point: 24 x 40 px, centred.
const RECT := Vector4(-12, -40, 24, 40)
const AT := Vector3(0, 0, -20)          # view space: 400 px ahead


## A fan [param px_lower] px (at the thing's distance) below the thing's
## point on the screen, [param aside] px to the side, at depth [param z]
## (view space; the thing's is -20).
func _fan(px_lower: float, aside := 0.0, z := -10.0) -> Vector3:
	var k := AT.z / z
	return Vector3(aside * PX / k, -px_lower * PX / k, z)


func test_a_fan_in_front_sinks_till_its_feet_show() -> void:
	# his feet 20 px below its point at its distance, 28 px tall at half its
	# distance: 56 px there, his head 36 above its lowest pixel
	var fan := _fan(20)
	var d := MwCrowdDuck.sink(fan, 16, 28, AT, RECT, 1.0)
	assert_almost_eq(d, (36.0 + MwCrowdDuck.CLEAR) / 2.0, 1e-4, "his own px: half what it is at its distance")
	var head := -20.0 + (28.0 - d) * 2.0
	assert_almost_eq(head, -MwCrowdDuck.CLEAR, 1e-4, "his head just below its lowest pixel")


func test_fans_behind_it_or_below_it_stay_up() -> void:
	assert_eq(MwCrowdDuck.sink(_fan(20, 0, -30), 16, 28, AT, RECT, 1.0), 0.0, "behind it")
	assert_eq(MwCrowdDuck.sink(_fan(60), 16, 28, AT, RECT, 1.0), 0.0, "his head well below it on the screen")
	assert_eq(MwCrowdDuck.sink(_fan(-45), 16, 28, AT, RECT, 1.0), 0.0, "all of him above it on the screen")
	assert_eq(MwCrowdDuck.sink(Vector3(0, -0.5, 1), 16, 28, AT, RECT, 1.0), 0.0, "behind the camera")


func test_feet_passing_its_top_ease_him_in() -> void:
	# owner: no jumps or sudden snaps - a fan whose feet are just above a
	# thing's top on the screen covers none of it; just below, he must sink
	# most of his height: eased over TOP_SOFT px instead of a jump
	var last := 0.0
	for above in [2.0, 0.0, -2.0, -4.0, -6.0, -8.0]:      # his feet above its top (40 px), px
		var d := MwCrowdDuck.sink(_fan(-40.0 - above), 16, 28, AT, RECT, 1.0)
		if above >= 0.0:
			assert_eq(d, 0.0, "feet %d px above its top: none" % above)
		else:
			assert_gt(d, last, "feet %d px below its top: more" % -above)
			assert_lt(d - last, 0.5 * (28.0 + MwCrowdDuck.CLEAR), "no jump")
		last = d
	assert_almost_eq(MwCrowdDuck.sink(_fan(-40.0 + MwCrowdDuck.TOP_SOFT), 16, 28, AT, RECT, 1.0),
			28.0 + MwCrowdDuck.CLEAR, 1e-4,
			"all the way from TOP_SOFT px below it")


func test_its_lowest_pixel_is_at_the_ice() -> void:
	assert_eq(MwCrowdDuck.ice_up(Vector4(-12, -40, 24, 48)), Vector4(-12, -40, 24, 40),
			"the rows below its feet (a stick blade, skates) do not count")
	assert_eq(MwCrowdDuck.ice_up(Vector4(-4, -30, 8, 8)), Vector4(-4, -30, 8, 8), "a puck in the air as it is")
	assert_lte(MwCrowdDuck.ice_up(Vector4(-4, 2, 8, 8)).w, 0.0, "all below the ice: nothing")


func test_a_head_just_below_it_dips_a_little() -> void:
	# his head 2 px below its lowest pixel: within the clearance
	var d := MwCrowdDuck.sink(_fan(58), 16, 28, AT, RECT, 1.0)
	assert_almost_eq(d, (MwCrowdDuck.CLEAR - 2.0) / 2.0, 1e-4)


func test_never_more_than_his_height() -> void:
	# a quarter of its distance, his feet 20 px above its point: his head far above it
	var d := MwCrowdDuck.sink(_fan(-20, 0, -5), 16, 28, AT, RECT, 1.0)
	assert_almost_eq(d, 28.0 + MwCrowdDuck.CLEAR, 1e-4, "behind his seat, all of him")


func test_less_and_less_to_the_side() -> void:
	var full := MwCrowdDuck.sink(_fan(20), 16, 28, AT, RECT, 1.0)
	var edge := 12.0 + 16.0     # its half width + his (16 px at half its distance: 32 there)
	var last := full
	assert_almost_eq(MwCrowdDuck.sink(_fan(20, edge + MwCrowdDuck.CORE), 16, 28, AT, RECT, 1.0), full, 1e-4,
			"all the way within CORE px of it")
	for gap in [10.0, 16.0, 22.0, 28.0, 34.0]:
		var d := MwCrowdDuck.sink(_fan(20, edge + gap), 16, 28, AT, RECT, 1.0)
		assert_lt(d, last, "%d px aside: less" % gap)
		assert_gt(d, 0.0, "%d px aside: still some" % gap)
		last = d
	assert_eq(MwCrowdDuck.sink(_fan(20, edge + MwCrowdDuck.REACH), 16, 28, AT, RECT, 1.0), 0.0, "none from REACH")
	assert_eq(MwCrowdDuck.sink(_fan(20, -edge - MwCrowdDuck.REACH), 16, 28, AT, RECT, 1.0), 0.0, "either side")


func test_level_with_it_hardly_at_all() -> void:
	var full := MwCrowdDuck.sink(_fan(20), 16, 28, AT, RECT, 1.0)
	var near := MwCrowdDuck.sink(_fan(20, 0, AT.z + 0.5 * MwCrowdDuck.FRONT * PX), 16, 28, AT, RECT, 1.0)
	assert_gt(near, 0.0)
	assert_lt(near, full, "half FRONT nearer: some of it")
	assert_eq(MwCrowdDuck.sink(_fan(20, 0, AT.z), 16, 28, AT, RECT, 1.0), 0.0, "level: none")
	assert_almost_eq(MwCrowdDuck.sink(_fan(20), 16, 28, AT, RECT, 0.5), full * 0.5, 1e-4, "a weaker point less")


func test_wider_and_gentler_during_a_goal() -> void:
	var edge := 12.0 + 16.0
	for gap in [MwCrowdDuck.REACH, 60.0, 100.0]:
		assert_eq(MwCrowdDuck.sink(_fan(20, edge + gap), 16, 28, AT, RECT, 1.0), 0.0, "%d px aside: none in play" % gap)
		assert_gt(MwCrowdDuck.sink(_fan(20, edge + gap), 16, 28, AT, RECT, 1.0, false, 1.0), 0.0,
				"%d px aside: some in a goal" % gap)
	var full := MwCrowdDuck.sink(_fan(20), 16, 28, AT, RECT, 1.0)
	assert_almost_eq(MwCrowdDuck.sink(_fan(20, edge + MwCrowdDuck.GOAL_CORE), 16, 28, AT, RECT, 1.0, false, 1.0), full,
			1e-4,
			"all the way out to GOAL_CORE")
	assert_eq(MwCrowdDuck.sink(_fan(20, edge + MwCrowdDuck.GOAL_REACH), 16, 28, AT, RECT, 1.0, false, 1.0), 0.0,
			"none from GOAL_REACH")
	var half := MwCrowdDuck.sink(_fan(20, edge + 40), 16, 28, AT, RECT, 1.0, false, 0.5)
	assert_gt(half, MwCrowdDuck.sink(_fan(20, edge + 40), 16, 28, AT, RECT, 1.0))
	assert_lt(half, MwCrowdDuck.sink(_fan(20, edge + 40), 16, 28, AT, RECT, 1.0, false, 1.0), "half way in: between")


## The follow camera at the bottom of the rink (the 2D camera's lowest).
func _bottom_camera() -> Transform3D:
	var vp := SubViewport.new()
	vp.size = MwRink3D.SCREEN
	vp.own_world_3d = true
	add_child_autofree(vp)
	var cam := MwRinkCamera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.follow(Vector2(96, 680))
	return cam.global_transform


## Where the head of a fan [param h] px tall standing at rink point
## [param at] is, seen from [param cam] (a screen billboard: up the screen).
func _head(cam: Transform3D, at: Vector3, h := 28.0) -> Vector3:
	var v := cam.affine_inverse() * MwRink3D.world(at.x, at.y, at.z)
	return cam * (v + Vector3(0, h * PX, 0))


func test_only_fans_who_hide_the_rink() -> void:
	var cam := _bottom_camera()
	var row := func(k: int) -> float: return MwStands.offset(k) + MwStands.FIGURE_AT * MwStands.DEPTH
	var near := Vector3(0, MwStands.BOARD.y + row.call(3), MwStands.height(3))
	assert_eq(MwCrowdDuck.occludes(_head(cam, near), cam), 1.0, "the near end's fourth row hides the ice")
	var side := Vector3(-MwStands.BOARD.x - row.call(3), 100, MwStands.height(3))
	assert_eq(MwCrowdDuck.occludes(_head(cam, side), cam), 0.0, "the side stands do not (owner)")
	var low := Vector3(0, MwStands.BOARD.y + row.call(0), MwStands.height(0))
	assert_eq(MwCrowdDuck.occludes(_head(cam, low, 0.5), cam), 0.0, "a head below the line of sight to the ice")
	var tv := MwRinkCamera3D.looking(Vector3(-430, 0, 320), Vector3(0, 0, 0))
	assert_eq(MwCrowdDuck.occludes(_head(tv, side), tv), 1.0, "the side stands from a side camera do")
	var level := MwRinkCamera3D.looking(Vector3(0, 600, 0.5), Vector3(0, 0, 40))
	assert_eq(MwCrowdDuck.occludes(_head(level, near), level), 0.0, "a line of sight that never comes down")
	assert_almost_eq(MwRinkShape.rounded_sd(Vector2(0, 372)), 0.0, 1e-4, "the boards' line")
	assert_almost_eq(MwRinkShape.rounded_sd(Vector2(0, 0)), -185.0, 1e-4)
	assert_gt(MwRinkShape.rounded_sd(Vector2(184, 371)), 0.0, "outside the rounded corner")


## How far each seat's fan sinks (the shader's rule: [method
## MwCrowdDuck.occludes] x [method MwCrowdDuck.sink]) for a skater at rink
## point [param thing], from [param cam]; each fan his back view's size.
func _sinks(stands: MwStands3D, cam: Transform3D, thing: Vector3) -> PackedFloat32Array:
	var view := cam.affine_inverse()
	var at := view * MwRink3D.world(thing.x, thing.y, 0)
	var out := PackedFloat32Array()
	for seat: Dictionary in stands.seats:
		var size: Vector2i = stands.rects[stands._key(seat["back"], seat["team"], seat["swap"])].size
		var pos: Vector3 = seat["stand"]          # (where the figure stands: the shader's anchor)
		var fan := view * MwRink3D.world(pos.x, pos.y, pos.z)
		var head := cam * (fan + Vector3(0, size.y * PX, 0))
		out.append(MwCrowdDuck.occludes(head, cam) * MwCrowdDuck.sink(fan, size.x, size.y, at, RECT, 1.0))
	return out


func test_sparse_crowds_from_a_tenth_to_a_full_house() -> void:
	# owner: sparser crowds tested, from 10 percent full in steps of
	# 10 percent up to a full stadium
	if not need_rom():
		return
	var stands := MwStands3D.new()
	add_child_autofree(stands)
	var cam := _bottom_camera()
	var sinks := _sinks(stands, cam, Vector3(10, 366, 0))       # a skater against the near boards
	var sinking := {}
	for i in sinks.size():
		if sinks[i] > 0.0:
			sinking[i] = true
			var pos: Vector3 = stands.seats[i]["pos"]
			assert_gt(pos.y, MwStands.BOARD.y, "seat %d: the near end's fans only, not the side stands" % i)
	assert_gt(sinking.size(), 10, "a full house: a dip in the near end's crowd")
	var was := -1
	var counts := []
	for p in range(1, 11):
		stands.occupancy = p / 10.0
		var shown := stands.shown_seats()
		assert_eq(shown.size(), roundi(p / 10.0 * stands.seats.size()), "%d%%: that share of the seats" % (p * 10))
		var n := 0
		for i in shown:
			if sinking.has(i):
				n += 1
		assert_gte(n, was, "%d%%: the same fans sink, and those who came since" % (p * 10))
		was = n
		counts.append(n)
	assert_eq(was, sinking.size(), "a full house: all of them")
	assert_gt(counts[0], 0, "a tenth of a house: still someone in the way, still sinking")
	gut.p("fans sinking from 10%% to 100%%: %s of %d" % [str(counts), sinking.size()])
	# the shader's input does not depend on who is there
	var things := [_thing("t0.p1.1A/body", 10, 366)]
	var params := []
	for p in [1, 5, 10]:
		stands.occupancy = p / 10.0
		stands.clear_way()
		stands.make_way(things, 1.0)
		params.append([stands._crowd_material.get_shader_parameter("duck_count"),
				stands._crowd_material.get_shader_parameter("duck_at")])
	assert_eq(params[0], params[1])
	assert_eq(params[0], params[2])


func test_a_parallel_projection() -> void:
	var fan := Vector3(0, -20 * PX, -10)
	assert_almost_eq(MwCrowdDuck.sink(fan, 16, 28, AT, RECT, 1.0, true), 28.0 - 20.0 + MwCrowdDuck.CLEAR, 1e-4,
			"no perspective: px are px")


func test_the_shader_has_the_same_rule() -> void:
	var code := MwStands3D.CROWD_SHADER.code
	for c in [["DUCK_CORE", MwCrowdDuck.CORE], ["DUCK_REACH", MwCrowdDuck.REACH],
			["DUCK_GOAL_CORE", MwCrowdDuck.GOAL_CORE], ["DUCK_GOAL_REACH", MwCrowdDuck.GOAL_REACH],
			["DUCK_CLEAR", MwCrowdDuck.CLEAR], ["DUCK_FRONT", MwCrowdDuck.FRONT],
			["DUCK_RINK_SOFT", MwCrowdDuck.RINK_SOFT]]:
		assert_true(code.contains("const float %s = %.1f;" % c), "%s = %s" % c)
	assert_true(code.contains("rink_sd("), "the boards' signed distance (rink3d_geom: test_rink_shape)")
	assert_true(code.contains("const float DUCK_TOP_SOFT = %.1f;" % MwCrowdDuck.TOP_SOFT), "TOP_SOFT")
	assert_true(code.contains("duck_at[%d]" % MwCrowdDuck.MAX_POINTS), "room for every point")
	assert_true(code.contains("duck_rect[%d]" % MwCrowdDuck.MAX_POINTS))


# --- the tracks -------------------------------------------------------------------

func _thing(key: String, x: float, y: float) -> Dictionary:
	return {"key": key, "at": Vector2(x, y), "rect": RECT}


func _step(duck: MwCrowdDuck, things: Array, seconds: float, fps: float, scoring := false) -> void:
	for i in roundi(seconds * fps):
		duck.update(things, 1.0 / fps, scoring)


func test_a_thing_fades_in_and_out() -> void:
	var duck := MwCrowdDuck.new()
	duck.update([_thing("puck/body", 0, 300)], 0.0)
	assert_eq(duck.points(), [], "just come on: nothing yet")
	_step(duck, [_thing("puck/body", 0, 300)], MwCrowdDuck.FADE_IN_S * 0.5, 60)
	var half: Array = duck.points()
	assert_eq(half.size(), MwCrowdDuck.SAMPLES)
	var life: float = duck.tracks["puck/body"].life
	assert_almost_eq(life, 0.5, 0.05, "half faded in")
	assert_almost_eq(float(half[0][2]), smoothstep(0.0, 1.0, life), 1e-5)
	_step(duck, [_thing("puck/body", 0, 300)], 1.0, 60)
	var pts: Array = duck.points()
	for i in MwCrowdDuck.SAMPLES:
		assert_eq(pts[i][0], Vector2(0, 300), "the wake on it")
		assert_almost_eq(float(pts[i][2]), MwCrowdDuck.WAKE[i], 1e-4)
		assert_eq(pts[i][1], RECT)
	_step(duck, [], MwCrowdDuck.FADE_OUT_S * 0.5, 60)
	assert_true(duck.tracks.is_empty(), "gone")
	assert_eq(duck.ghosts.size(), 1, "fading out where it was")
	assert_almost_eq(duck.ghosts[0].life, 0.5, 0.05)
	assert_eq(duck.points()[0][0], Vector2(0, 300))
	_step(duck, [], MwCrowdDuck.FADE_OUT_S, 60)
	assert_eq(duck.points(), [], "faded out")
	assert_true(duck.ghosts.is_empty())


func test_the_wake_follows_and_catches_up() -> void:
	var duck := MwCrowdDuck.new()
	_step(duck, [_thing("t0.p1.1A/body", 0, 300)], 1.0, 60)
	for i in 30:        # 200 px/s east for half a second
		duck.update([_thing("t0.p1.1A/body", 100.0 * (i + 1) / 30.0, 300)], 1.0 / 60.0)
	var pts: Array = duck.points()
	assert_eq(pts[0][0], Vector2(100, 300))
	for i in range(1, MwCrowdDuck.SAMPLES):
		assert_lt((pts[i][0] as Vector2).x, (pts[i - 1][0] as Vector2).x, "each behind the one before")
	assert_gt((pts[MwCrowdDuck.SAMPLES - 1][0] as Vector2).x, 0.0, "all on their way")
	_step(duck, [_thing("t0.p1.1A/body", 100, 300)], 2.0, 60)
	for point: Array in duck.points():
		assert_almost_eq((point[0] as Vector2).x, 100.0, 0.5, "caught up once it stops")


func test_the_same_at_any_frame_rate() -> void:
	var runs := []
	for fps in [30.0, 60.0, 144.0]:
		var duck := MwCrowdDuck.new()
		_step(duck, [_thing("puck/body", 0, 300)], 0.5, fps)
		_step(duck, [_thing("puck/body", 40, 300)], 0.2, fps)
		_step(duck, [], 0.2, fps)
		runs.append(duck.points())
	for r in [1, 2]:
		assert_eq(runs[r].size(), runs[0].size())
		for i in runs[0].size():
			assert_almost_eq((runs[r][i][0] as Vector2).x, (runs[0][i][0] as Vector2).x, 0.2, "point %d" % i)
			assert_almost_eq(float(runs[r][i][2]), float(runs[0][i][2]), 0.04, "weight %d" % i)


func test_a_jump_fades_out_there_and_in_here() -> void:
	var duck := MwCrowdDuck.new()
	_step(duck, [_thing("puck/body", 0, 300)], 1.0, 60)
	duck.update([_thing("puck/body", 0, 0)], 1.0 / 60.0)        # a faceoff
	assert_eq(duck.ghosts.size(), 1, "the old place fades out")
	assert_eq(duck.ghosts[0].points[0], Vector2(0, 300))
	var track: MwCrowdDuck.Track = duck.tracks["puck/body"]
	assert_eq(track.points[MwCrowdDuck.SAMPLES - 1], Vector2(0, 0), "no wake across the rink")
	assert_lt(track.life, 0.1, "the new one fades in")
	duck.update([_thing("puck/body", 30, 0)], 1.0 / 60.0)
	assert_eq(duck.ghosts.size(), 1, "a move is not a jump")


func test_a_goal_widens_the_curve_gently() -> void:
	var duck := MwCrowdDuck.new()
	var things := [_thing("lamp0/body", 0, 372)]
	_step(duck, things, MwCrowdDuck.GOAL_FADE_S * 0.5, 60, true)
	assert_almost_eq(duck.goal, 0.5, 0.03, "coming in")
	assert_almost_eq(duck.goal_share(), smoothstep(0.0, 1.0, duck.goal), 1e-6, "eased")
	_step(duck, things, 2.0, 60, true)
	assert_eq(duck.goal_share(), 1.0, "a goal's")
	_step(duck, things, MwCrowdDuck.GOAL_FADE_S * 0.25, 60)
	assert_almost_eq(duck.goal, 0.75, 0.03, "going")
	_step(duck, things, 2.0, 60)
	assert_eq(duck.goal_share(), 0.0, "gone")
	_step(duck, things, 1.0, 60, true)
	duck.clear()
	assert_eq(duck.goal, 0.0, "a new match: none")


func test_a_new_frame_eases_in() -> void:
	# owner: no jumps or sudden snaps - a figure's box changes with every
	# animation frame and facing; the fans follow it eased, not at once
	var crowd_duck := MwCrowdDuck.new()
	var standing := Vector4(-12, -40, 24, 40)
	var lying := Vector4(-29, -20, 40, 20)
	_step(crowd_duck, [{"key": "t0.p1.1A/body", "at": Vector2(0, 300), "rect": standing}], 1.0, 60)
	assert_eq(crowd_duck.tracks["t0.p1.1A/body"].rect, standing, "its own box from the start")
	crowd_duck.update([{"key": "t0.p1.1A/body", "at": Vector2(0, 300), "rect": lying}], 1.0 / 60.0)
	var r: Vector4 = crowd_duck.tracks["t0.p1.1A/body"].rect
	assert_almost_eq(r, standing.lerp(lying, 1.0 - exp(-1.0 / 60.0 / MwCrowdDuck.RECT_LAG_S)), Vector4.ONE * 1e-3,
			"a frame later: a little way")
	var runs := []
	for fps in [30.0, 144.0]:
		var duck := MwCrowdDuck.new()
		_step(duck, [{"key": "t0.p1.1A/body", "at": Vector2(0, 300), "rect": standing}], 0.5, fps)
		# 5 and 24 frames
		_step(duck, [{"key": "t0.p1.1A/body", "at": Vector2(0, 300), "rect": lying}], 1.0 / 6.0, fps)
		runs.append(duck.tracks["t0.p1.1A/body"].rect)
	assert_almost_eq(runs[0], runs[1], Vector4.ONE * 1e-3, "the same at any frame rate")
	_step(crowd_duck, [{"key": "t0.p1.1A/body", "at": Vector2(0, 300), "rect": lying}], 1.5, 60)
	assert_almost_eq(crowd_duck.tracks["t0.p1.1A/body"].rect, lying, Vector4.ONE * 0.01, "there in the end")


func test_never_more_than_the_shader_holds() -> void:
	var duck := MwCrowdDuck.new()
	for round_number in 3:
		var things := []
		for i in 30:
			things.append(_thing("obj%d/body" % i, i * 10.0 + round_number * 100.0, 300))
		_step(duck, things, 0.1, 60)
	assert_lte(duck.tracks.size() + duck.ghosts.size(), MwCrowdDuck.MAX_TRACKS)
	assert_lte(duck.points().size(), MwCrowdDuck.MAX_POINTS)
	duck.clear()
	assert_eq(duck.points(), [])


func test_the_things_that_make_way() -> void:
	var rect := func(it: Dictionary) -> Vector4: return Vector4(-8, -30, 16, 30) if it["frame"] != 0 else Vector4.ZERO
	var items := []
	for key in ["t0.p3.1A/body", "t1.p0.2C/body", "puck/body", "ref/body", "net1/body", "obj4/body",
			"lamp0/body", "t0.p3.1A/shadow", "bench.t0.s2/body", "t0.arrow1/arrow", "t0.p3.1A/12345"]:
		items.append({"key": key, "frame": 1, "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(5, 310, 7)})
	items.append({"key": "lamp1/body", "frame": 1, "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(0, 372, 12),
			"flat": true})
	items.append({"key": "obj5/body", "frame": 1, "place": MwRinkDraw3D.UNDER_ICE, "at": Vector3(5, 310, 0)})
	items.append({"key": "obj6/body", "frame": 1, "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(5, -380, 0), "pin": 45})
	items.append({"key": "obj7/body", "frame": 0, "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(5, 310, 0)})
	var got := MwCrowdDuck.things(items, rect)
	var keys := got.map(func(o: Dictionary) -> String: return o["key"])
	assert_eq(keys, ["t0.p3.1A/body", "t1.p0.2C/body", "puck/body", "ref/body", "net1/body", "obj4/body"],
			"bodies on the ice; not shadows, the lamps' skulls, benches, in-ice hazards, pinned or empty frames")
	var carried := items.duplicate()
	carried[2] = carried[2].duplicate()
	carried[2]["carrier"] = "t0.p3.1A/body"
	assert_false(MwCrowdDuck.things(carried, rect).map(func(o: Dictionary) -> String: return o["key"]).has("puck/body"),
			"a carried puck is its carrier's (owner: two boxes overlapping, jumping)")
	keys = MwCrowdDuck.things(items, rect, true).map(func(o: Dictionary) -> String: return o["key"])
	assert_eq(keys, ["t0.p3.1A/body", "t1.p0.2C/body", "puck/body", "ref/body", "net1/body", "obj4/body", "lamp0/body",
			"lamp1/body"], "a goal: the skulls too, flying or spinning on their stands (owner)")
	assert_eq(got[0]["at"], Vector2(5, 310), "the ice point")
	assert_eq(got[0]["rect"], Vector4(-8, -30, 16, 30))


# --- the view ---------------------------------------------------------------------

func test_the_view_hands_them_over() -> void:
	if not need_rom():
		return
	var view := VIEW.instantiate() as MwRinkView3D
	add_child_autofree(view)
	var items := []
	for k in [["t0.p1.1A/body", Vector3(-20, 330, 0)], ["puck/body", Vector3(0, 340, 4)],
			["bench.t0.s1/body", Vector3(-230, 60, 0)]]:
		items.append({"frame": MwRinkDraw.STAND_FRAME, "attr": 0, "depth": 4, "place": MwRinkDraw3D.UPRIGHT,
				"at": k[1], "offset": Vector2i.ZERO, "order": 0, "key": k[0]})
	view.present_frame({"items": items, "shot": MwRinkShot3D.new(), "shown": Vector2(96, 400)}, {})
	var was := MwSettings.crowd_duck
	MwSettings.crowd_duck = true
	view.blend_to(1.0, 1.0)
	assert_eq(view.stands.duck.tracks.keys(), ["t0.p1.1A/body", "puck/body"], "the skater and the puck")
	var track: MwCrowdDuck.Track = view.stands.duck.tracks["puck/body"]
	var f := view.sprites.frame_texture(rom, MwRinkDraw.STAND_FRAME, 0)
	assert_eq(track.rect, MwCrowdDuck.ice_up(Vector4(f["x0"], float(f["y0"]) - 4.0, f["w"], f["h"])),
			"its drawing, raised by its height, from the ice up")
	var m: ShaderMaterial = view.stands._crowd_material
	assert_eq(int(m.get_shader_parameter("duck_count")), 2 * MwCrowdDuck.SAMPLES, "every point to the shader")
	MwSettings.crowd_duck = false
	view.blend_to(1.0, 1.0)
	assert_true(view.stands.duck.tracks.is_empty(), "off: none")
	assert_eq(int(m.get_shader_parameter("duck_count")), 0)
	MwSettings.crowd_duck = true
	for mode in [MwRinkCamera3D.Mode.CALIBRATION, MwRinkCamera3D.Mode.TV, MwRinkCamera3D.Mode.CINEMATIC]:
		view.set_camera_mode(mode)
		view.blend_to(1.0, 1.0)
		assert_true(view.stands.duck.tracks.is_empty(), "the main 3D camera only (owner): not %d" % mode)
	view.set_camera_mode(MwRinkCamera3D.Mode.EXTENDED)
	view.blend_to(1.0, 1.0)
	assert_eq(view.stands.duck.tracks.keys(), ["t0.p1.1A/body", "puck/body"],
			"3D EXTENDED too (owner, 2026-10-11: same behaviour)")
	assert_eq(int(m.get_shader_parameter("duck_count")), 2 * MwCrowdDuck.SAMPLES)
	assert_true(MwRinkView3D.ducks(MwRinkCamera3D.Mode.EXTENDED))
	for mode in MwRinkCamera3D.Mode.values():
		assert_eq(MwRinkView3D.ducks(mode), mode in [MwRinkCamera3D.Mode.FOLLOW, MwRinkCamera3D.Mode.EXTENDED],
				"the main 3D cameras only: %d" % mode)
	view.set_camera_mode(MwRinkCamera3D.Mode.TV)
	view.blend_to(1.0, 1.0)
	assert_true(view.stands.duck.tracks.is_empty(), "not the others")
	view.set_camera_mode(MwRinkCamera3D.Mode.FOLLOW)
	view.blend_to(1.0, 1.0)
	assert_eq(view.stands.duck.tracks.size(), 2, "back")
	assert_eq(float(m.get_shader_parameter("duck_goal")), 0.0, "in play: the narrow curve")
	var goal := MwRinkShot3D.new()
	goal.phase = MwRinkState.PHASE_GOAL
	view.present_frame({"items": items, "shot": goal, "shown": Vector2(96, 400)}, {}, true)
	view.blend_to(1.0, 1.0)
	assert_eq(float(m.get_shader_parameter("duck_goal")), 1.0, "a goal: the wide one")
	MwSettings.crowd_duck = was
