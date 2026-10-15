extends "res://test/rom/rom_test_base.gd"
## The stands' layout (plan 15, MwStands): seats round the rink, mirrored
## left to right, out of the pens, each showing a character with both views
## dealt at random (owner, 2026-10-09: MwStands.deal).

var seats: Array = []
var data: Dictionary


func before_all() -> void:
	super.before_all()
	data = MwCrowd.load_data()
	seats = MwStands.seats(data)


func test_rows_and_regions() -> void:
	assert_gt(seats.size(), 400, "seats")
	var regions := {}
	var rows := {}
	for seat: Dictionary in seats:
		regions[seat["region"]] = true
		rows[seat["row"]] = true
	assert_eq(regions.size(), 4, "far end, both halves of the sides, near end")
	assert_eq(rows.size(), MwStands.ROWS)


func test_complete_characters_only() -> void:
	var figures := {}
	for f: Dictionary in data["figures"]:
		figures[f["name"]] = true
	for seat: Dictionary in seats:
		assert_true(figures.has(seat["front"]) and figures.has(seat["back"]), "%s / %s" % [seat["front"], seat["back"]])
		assert_true(String(seat["front"]).begins_with("front_") and String(seat["back"]).begins_with("back_"))


func test_mirrored_halves() -> void:
	var at := {}
	for entry: Dictionary in seats:
		var pos: Vector3 = entry["pos"]
		at[Vector3i(roundi(pos.x * 10), roundi(pos.y * 10), entry["row"])] = entry
	for seat: Dictionary in seats:
		var point: Vector3 = seat["pos"]
		var m: Dictionary = at.get(Vector3i(roundi(-point.x * 10), roundi(point.y * 10), seat["row"]), {})
		assert_false(m.is_empty(), "mirror of %s" % point)
		if not m.is_empty():
			assert_almost_eq((m["facing"] as Vector2).x, -(seat["facing"] as Vector2).x, 1e-4)


## Who sits where: random, the same for the same seed; every character with
## both views, its swaps and both skins turn up; nothing the atlas lacks.
func test_the_crowd_is_dealt_at_random() -> void:
	var again := MwStands.seats(data)
	var other := MwStands.seats(data, 12345)
	var same := 0
	for i in seats.size():
		assert_eq([again[i]["front"], again[i]["swap"], again[i]["team"]],
				[seats[i]["front"], seats[i]["swap"], seats[i]["team"]])
		if other[i]["front"] == seats[i]["front"]:
			same += 1
	var fans := MwStands.fans(data)
	assert_eq(fans.size(), 12, "the twelve characters with both views")
	assert_lt(same, seats.size() / 4, "another seed, another crowd (about 1 in 12 alike)")
	var counts := {}
	var team := 0
	var swapped := 0
	for seat: Dictionary in seats:
		counts[seat["front"]] = int(counts.get(seat["front"], 0)) + 1
		team += 1 if seat["team"] else 0
		swapped += 1 if not (seat["swap"] as Array).is_empty() else 0
	assert_eq(counts.size(), fans.size(), "every character")
	var mean := float(seats.size()) / fans.size()
	for k: String in counts:
		assert_between(float(counts[k]), mean * 0.6, mean * 1.4, "%s: about its share" % k)
	assert_almost_eq(float(team) / seats.size(), MwStands.team_share(data), 0.05, "the skin as often as in the picture")
	assert_gt(swapped, 0, "colour swaps")
	var keys := {}
	for v: Array in MwStands.variants(data):
		keys[str(v)] = true
	for other_seat: Dictionary in other:
		for side in ["front", "back"]:
			assert_true(keys.has(str([other_seat[side], other_seat["team"], other_seat["swap"]])),
					"in the atlas: %s" % str([other_seat[side], other_seat["team"], other_seat["swap"]]))


## How far a point is outside the boards (their straight lines and the
## corners' arcs, as MwStands rounds them).
func _outside(x: float, y: float) -> float:
	var r := MwStands.CORNER_FAR if y < 0 else MwStands.CORNER_NEAR
	var cx := MwStands.BOARD.x - r
	var cy := MwStands.BOARD.y - r
	var ax := absf(x)
	var ay := absf(y)
	if ax > cx and ay > cy:
		return Vector2(ax - cx, ay - cy).length() - r
	return maxf(ax - MwStands.BOARD.x, ay - MwStands.BOARD.y)


## The pens' back walls (rink px, |x|: tools/blender/rink_build.py BENCH_BACK_X).
const PENS_BACK := 216.0


func test_outside_the_boards_and_pens() -> void:
	for seat: Dictionary in seats:
		for where: String in ["pos", "stand"]:       # the seat's place and where its figure stands
			var point: Vector3 = seat[where]
			assert_gt(_outside(point.x, point.y), MwStands.D0, "outside: %s" % point)
			if absf(point.y) < MwStands.PEN_Y and absf(point.x) > MwStands.BOARD.x:
				assert_gt(absf(point.x), MwStands.BOARD.x + MwStands.PEN_CLEAR, "behind the pens: %s" % point)
				assert_gt(absf(point.x), PENS_BACK + 1.0, "behind the pens' back walls: %s" % point)
			if absf(point.y) < MwStands.HALL_Y and absf(point.x) > MwStands.BOARD.x:
				assert_gt(absf(point.x), MwStands.BOARD.x + MwStands.HALL_CLEAR, "over the hallways: %s" % point)


## Owner, 2026-10-14: z-fighting in the stands, worst at the bottom, where
## neighbouring fans' depths were close. A figure's depth is an upright plane
## at his feet facing the camera's heading (rink3d_crowd:
## level_toward_camera), and the game's cameras look straight along the rink
## (north, south; the TV side views east, west) - so the depth is the stand
## point's y (or x). Two figures that can overlap on the screen (this near
## side to side, rows this close in height: the widest and tallest views)
## never stand at one depth from any of those headings; on the row's line
## alone (the seats' places) the end rows' neighbours all did.
func test_neighbours_never_stand_in_one_plane() -> void:
	const MIN_PX := MwStands.STAGGER_MIN
	for axis in 2:                                     # 0: depth along y (north / south), 1: along x
		var on_line := _planes_shared("pos", axis, MIN_PX)
		var stood := _planes_shared("stand", axis, MIN_PX)
		assert_gt(on_line.size(), 20, "the rows' line: neighbours in one plane (axis %d)" % axis)
		assert_eq(stood, [] as Array[String], "where they stand: none (axis %d)" % axis)
	for seat: Dictionary in seats:
		var step := (seat["stand"] as Vector3).distance_to(seat["pos"])
		assert_lte(step, MwStands.STAGGER * 3.21, "a small step")
		assert_lt(MwStands.FIGURE_AT * MwStands.DEPTH + step, MwStands.SEAT_AT * MwStands.DEPTH
				- MwStands.SEAT_T / 2.0, "in front of the seat")


## The pairs of figures, placed at [param where], whose drawings can overlap
## (within 44 px side to side, 70 px in height) at depths along [param axis]
## (0: y, 1: x) less than [param min_px] apart.
func _planes_shared(where: String, axis: int, min_px: float) -> Array[String]:
	var order := range(seats.size())
	var depth := func(i: int) -> float:
		var point: Vector3 = seats[i][where]
		return point.y if axis == 0 else point.x
	order.sort_custom(func(a: int, b: int) -> bool: return depth.call(a) < depth.call(b))
	var out: Array[String] = []
	for n in order.size():
		var a: Vector3 = seats[order[n]][where]
		for m in range(n + 1, order.size()):
			var b: Vector3 = seats[order[m]][where]
			if depth.call(order[m]) - depth.call(order[n]) >= min_px:
				break
			var across := absf(a.x - b.x) if axis == 0 else absf(a.y - b.y)
			if across < MwStands.STAGGER_REACH and absf(a.z - b.z) < 70.0:
				out.append("%s / %s" % [a, b])
	return out


## Owner, 2026-10-11: the seating comes in right behind the pens (every row
## but the first, which the pens stand on), and the hallways between them
## stay clear under row 4, which roofs them.
func test_the_middle_filled_round_the_hallways() -> void:
	var behind := {}
	var over := {}
	for seat: Dictionary in seats:
		var point: Vector3 = seat["pos"]
		if absf(point.x) <= MwStands.BOARD.x:
			continue
		if absf(point.y) < MwStands.HALL_Y:
			over[seat["row"]] = true
		elif absf(point.y) < MwStands.PEN_Y:
			behind[seat["row"]] = true
	for k in MwStands.ROWS:
		assert_eq(behind.has(k), k >= 1, "row %d behind the pens" % k)
		assert_eq(over.has(k), k >= 4, "row %d over the hallways" % k)
	assert_eq(MwStands.cut(0, MwStands.Seg.SIDE, Vector2(-201, 100)), MwStands.Cut.PEN)
	assert_eq(MwStands.cut(3, MwStands.Seg.SIDE, Vector2(-255, 20)), MwStands.Cut.HALL)
	assert_eq(MwStands.cut(1, MwStands.Seg.SIDE, Vector2(-219, 100)), MwStands.Cut.NONE)
	assert_eq(MwStands.cut(0, MwStands.Seg.FAR_CORNER, Vector2(-201, -320)), MwStands.Cut.NONE)


func test_facing_the_rink() -> void:
	for seat: Dictionary in seats:
		var point: Vector3 = seat["pos"]
		var f: Vector2 = seat["facing"]
		assert_lt(f.dot(Vector2(point.x, point.y)), 0.0, "faces in: %s" % point)


func test_path_rows_line_up() -> void:
	# the same u is the same place at any offset: normals agree
	for u in MwStands.path_us(8.0):
		var a := MwStands.point_at_u(MwStands.offset(0), u)
		var b := MwStands.point_at_u(MwStands.offset(MwStands.ROWS - 1), u)
		assert_almost_eq((a["n"] as Vector2).dot(b["n"]), 1.0, 1e-3)


func test_top_rows_fade_to_black() -> void:
	# owner, 2026-10-11: twice the rows (5-10, were 8-10), a sharper ramp
	assert_eq(MwStands3D.fade(0.0), 1.0, "the ice")
	assert_eq(MwStands3D.fade(MwStands.height(3) + 18.0), 1.0, "row 4's fans: full colour")
	assert_gt(MwStands3D.fade(MwStands.height(3) + 34.0), 0.9, "row 4's heads: barely")
	assert_lt(MwStands3D.fade(MwStands.height(4) + 34.0), 0.85, "row 5's heads: fading")
	assert_almost_eq(MwStands3D.fade(MwStands.height(5) + 34.0), 0.5, 0.05, "row 6's heads: half")
	assert_lt(MwStands3D.fade(MwStands.height(7) + 18.0), 0.35, "row 8 dark")
	assert_lt(MwStands3D.fade(MwStands.height(8) + 18.0), 0.15, "row 9 nearly black")
	assert_lt(MwStands3D.fade(MwStands.height(9) + 18.0), 0.05, "the top row black")
	assert_eq(MwStands3D.fade(MwStands3D.FADE_TO), 0.0, "black at the top")
	var last := 1.0
	for z in range(0, 220, 4):
		assert_true(MwStands3D.fade(z) <= last, "never brighter going up")
		last = MwStands3D.fade(z)


func test_follow_camera_cuts_away_what_hides_the_play() -> void:
	# the follow camera near the near end: 240 px back and up from the ice point 330
	var cam := MwRink3D.world(0, 570, 240)
	var plane := MwStands3D.cut_plane(cam, MwStands.BOARD.y)
	assert_true(plane["on"])
	var w := func(x: float, y: float, z: float) -> Vector3: return MwRink3D.world(x, y, z)
	# the sight line from the camera over the near boards' top (z 48 at y 372)
	# is at z 48 + 192 * (y - 372) / 198 between them
	assert_true(MwStands3D.is_cut(plane, w.call(0, 450, 140)), "a fan above the sight line: cut")
	assert_false(MwStands3D.is_cut(plane, w.call(0, 450, 90)), "below it: kept (hides only the boards)")
	assert_false(MwStands3D.is_cut(plane, w.call(0, -450, 200)), "the far stands: kept")
	assert_false(MwStands3D.is_cut(plane, w.call(250, 0, 200)), "the side stands beside the rink: kept")
	# a camera over the ice (looking at the far end) cuts nothing
	assert_false(MwStands3D.cut_plane(MwRink3D.world(0, 100, 240), MwStands.BOARD.y)["on"])
	# reverse: over the far boards
	var rev := MwStands3D.cut_plane(MwRink3D.world(0, -570, 240), -MwStands.BOARD.y)
	assert_true(MwStands3D.is_cut(rev, w.call(0, -450, 140)))
	assert_false(MwStands3D.is_cut(rev, w.call(0, 450, 140)))


func test_satan_mirrors_towards_the_play() -> void:
	if not MwRom.available():
		pending("no ROM")
		return
	var stands := MwStands3D.new()
	add_child_autofree(stands)
	var cam := Camera3D.new()
	add_child_autofree(cam)
	var at := MwRink3D.world(0, 400, 240)
	cam.transform = Transform3D(Basis.looking_at(MwRink3D.world(0, 0, 0) - at, Vector3.UP), at)
	assert_false(stands.satan_looks_right(), "looks left (at the rink) to start with")
	stands.watch(Vector3(300, 0, 0), cam)
	assert_true(stands.satan_looks_right(), "the puck to his right: mirrored")
	stands.watch(Vector3(225, 0, 0), cam)
	assert_true(stands.satan_looks_right(), "a little to his left: no flicker")
	stands.watch(Vector3(100, 0, 0), cam)
	assert_false(stands.satan_looks_right(), "well to his left: back")


## Owner, 2026-10-11: Satan stands on the picture's spot, in the
## lane the game's players come on along (from the bench door, 265, 10,
## straight west), and slides aside with little hops when they come by, back
## once they're gone. Aside he is out of that lane and his drawing - a
## billboard, turned to any camera - stays inside the hallway's walls (|y|
## 40, from x 216) and clear of the pens' corners.
func test_satan_makes_way_in_the_hallway() -> void:
	if not MwRom.available():
		pending("no ROM")
		return
	var stands := MwStands3D.new()
	add_child_autofree(stands)
	var r: Rect2i = stands.rects[stands._key("satan", false, [])]
	var lo := r.size.x
	var hi := -1
	for x in r.size.x:
		for y in r.size.y:
			if stands.atlas.get_pixel(r.position.x + x, r.position.y + y).r > 0.0:
				lo = mini(lo, x)
				hi = maxi(hi, x)
				break
	var half := maxf(r.size.x * 0.5 - lo, hi + 1 - r.size.x * 0.5)
	var aside := MwStands3D.SATAN_ASIDE
	assert_eq(MwStands3D.SATAN_AT, Vector2(235, 7), "home: the picture's spot")
	assert_gt(absf(aside.y - 10.0), 24.0, "aside: out of the door's lane")
	assert_lt(aside.y, 10.0, "on its far side from the follow camera")
	assert_lt(absf(aside.y) + half, 40.0, "inside the hallway's walls from any side (half width %.1f)" % half)
	assert_gt(aside.x - half, 185.0, "behind the boards")
	for corner in [Vector2(216, 40), Vector2(216, -40)]:
		assert_gt(aside.distance_to(corner), half, "clear of the pens' corner %s" % corner)
	# a player comes on from the door and skates west (1.5 px a tick, 60 ticks a second)
	var st: Dictionary = stands.satan
	assert_eq(st["at"], MwStands3D.SATAN_AT)
	var point := Vector2(265, 10)
	var dt := 1.0 / 60.0
	var hopped := false
	var aside_by := -1.0
	for i in 40:                    # to x 205, still within SATAN_CLEAR of his spot
		st = MwStands3D.satan_next(st, PackedVector2Array([point]), dt)
		hopped = hopped or float(st["hop"]) > 0.5
		if aside_by < 0.0 and (st["at"] as Vector2).distance_to(aside) < 0.01:
			aside_by = point.x
		if absf(point.x - 235.0) < 1.0:
			assert_lt((st["at"] as Vector2).y, -2.0, "out of the player's way when he passes")
		point.x -= 1.5
	assert_gt(aside_by, 235.0, "aside before the player reaches his spot")
	assert_true(hopped, "little hops on the way")
	assert_lt(float(st["hop"]), 0.01, "standing still: no hop")
	# the way clear: back home after a moment
	for i in 30:
		st = MwStands3D.satan_next(st, PackedVector2Array(), dt)
	assert_eq(st["goal"], aside, "waits a moment")
	for i in 60:
		st = MwStands3D.satan_next(st, PackedVector2Array(), dt)
	assert_eq(st["goal"], MwStands3D.SATAN_AT, "then goes back")
	for i in 60:
		st = MwStands3D.satan_next(st, PackedVector2Array(), dt)
	assert_eq(st["at"], MwStands3D.SATAN_AT, "home")
	# a box figure passing by the side, his spot clear: he stays
	st = MwStands3D.satan_next(st, PackedVector2Array([Vector2(236, -24)]), dt)
	assert_eq(st["goal"], MwStands3D.SATAN_AT, "the side's walker: he stays on his spot")
	# what he makes way for: bodies in the hallway (a player at the door
	# too), not those waiting at the exits in its dark, the puck or the ice's
	var items := [{"key": "t0.p3.1A/body", "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(265, 10, 0)},
			{"key": "bench.t1.s4/body", "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(250, 20, 0)},
			{"key": "bench.t0.s2/body", "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(270, 14, 0)},
			{"key": "puck/body", "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(240, 7, 0)},
			{"key": "t1.p2.0C/body", "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(100, 7, 0)}]
	assert_eq(MwStands3D.satan_figures(items), PackedVector2Array([Vector2(265, 10), Vector2(250, 20)]),
			"only what he could bump into")


func test_four_views_by_true_front() -> void:
	# the ROM's front drawings face front-right, its backs back-right
	# (owner); the camera at (0, 600) (the follow camera's side), a fan's
	# true front is his row's facing; sight: from the camera to him
	var cam := Vector2(0, 600)
	var sight := func(at: Vector2) -> Vector2: return at - cam
	# the left stands (facing east) seen from the south: front-right, at the
	# rink on the screen's right (owner: they looked left)
	assert_false(MwStands3D.shown_mirrored(Vector2(1, 0), sight.call(Vector2(-250, 0))))
	# the right stands (facing west): front-left, at the rink
	assert_true(MwStands3D.shown_mirrored(Vector2(-1, 0), sight.call(Vector2(250, 0))))
	# the far end (facing south, straight at the camera's side): left of
	# the camera a little to the screen's left (front-left), right of it to
	# the right (front-right)
	assert_true(MwStands3D.shown_mirrored(Vector2(0, 1), sight.call(Vector2(-100, -450))))
	assert_false(MwStands3D.shown_mirrored(Vector2(0, 1), sight.call(Vector2(100, -450))))
	# the near end (facing north) from behind: left of the camera back-right,
	# right of it back-left - the picture's halves
	assert_false(MwStands3D.shown_mirrored(Vector2(0, -1), sight.call(Vector2(-60, 450))))
	assert_true(MwStands3D.shown_mirrored(Vector2(0, -1), sight.call(Vector2(60, 450))))
	# the left stands from the north (camera at (0, -600)): the rink on the
	# screen's left, front-left
	assert_true(MwStands3D.shown_mirrored(Vector2(1, 0), Vector2(-250, 0) - Vector2(0, -600)))
	# from behind them (camera west and south): back-right, at the rink
	assert_false(MwStands3D.shown_mirrored(Vector2(1, 0), Vector2(-250, 0) - Vector2(-500, 200)))
	# ... west and north: back-left
	assert_true(MwStands3D.shown_mirrored(Vector2(1, 0), Vector2(-250, 0) - Vector2(-500, -200)))


func test_figures_are_screen_billboards() -> void:
	# plan 32 (owner: the crowd and the referee billboards too): on by
	# default, the crowd shader told; off, the upright cards of before
	if not MwRom.available():
		pending("no ROM")
		return
	var stands := MwStands3D.new()
	add_child_autofree(stands)
	assert_true(stands.billboards)
	var m: ShaderMaterial = stands.get_node("Figures").material_override
	assert_true(m.get_shader_parameter("screen_billboards"))
	stands.billboards = false
	assert_false(m.get_shader_parameter("screen_billboards"))
	stands.billboards = true
	assert_true(m.get_shader_parameter("screen_billboards"))


## The 3D stands deal from the crowd's seed (MwCrowdLife's, per match): a
## new seed, a new crowd (its views in the atlas); the same seed, nothing.
## (The figures' instance data reads back empty without a renderer.)
func test_the_stands_deal_by_the_crowds_seed() -> void:
	if not MwRom.available():
		pending("no ROM")
		return
	var stands := MwStands3D.new()
	add_child_autofree(stands)
	var fronts := func(l: Array) -> Array: return l.map(func(entry: Dictionary) -> String: return entry["front"])
	var before: Array = fronts.call(stands.seats)
	stands.show_life({"seed": 77})
	assert_eq(stands.dealt, 77)
	var after: Array = fronts.call(stands.seats)
	assert_ne(after, before, "another crowd")
	assert_eq(after, fronts.call(MwStands.seats(data, 77)), "the deal of that seed")
	for seat: Dictionary in stands.seats:
		assert_true(stands.rects.has(stands._key(seat["front"], seat["team"], seat["swap"])), "in the atlas")
	stands.show_life({"seed": 77})
	assert_eq(fronts.call(stands.seats), after, "the same seed: as it was")
