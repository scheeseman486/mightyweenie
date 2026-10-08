extends "res://test/rom/rom_test_base.gd"
## The stands' layout (plan 15, MwStands): seats round the rink, mirrored
## left to right, out of the pens, each showing a character with both views
## (stand-ins for the rest, owner).

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
	for s: Dictionary in seats:
		regions[s["region"]] = true
		rows[s["row"]] = true
	assert_eq(regions.size(), 4, "far end, both halves of the sides, near end")
	assert_eq(rows.size(), MwStands.ROWS)


func test_complete_characters_only() -> void:
	var figures := {}
	for f: Dictionary in data["figures"]:
		figures[f["name"]] = true
	for s: Dictionary in seats:
		assert_true(figures.has(s["front"]) and figures.has(s["back"]), "%s / %s" % [s["front"], s["back"]])
		assert_true(String(s["front"]).begins_with("front_") and String(s["back"]).begins_with("back_"))


func test_mirrored_halves() -> void:
	var at := {}
	for s: Dictionary in seats:
		var p: Vector3 = s["pos"]
		at[Vector3i(roundi(p.x * 10), roundi(p.y * 10), s["row"])] = s
	for s: Dictionary in seats:
		var p: Vector3 = s["pos"]
		var m: Dictionary = at.get(Vector3i(roundi(-p.x * 10), roundi(p.y * 10), s["row"]), {})
		assert_false(m.is_empty(), "mirror of %s" % p)
		if not m.is_empty():
			assert_eq(m["front"], s["front"])
			assert_ne(m["mirrored"], s["mirrored"])


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


func test_outside_the_boards_and_pens() -> void:
	for s: Dictionary in seats:
		var p: Vector3 = s["pos"]
		assert_gt(_outside(p.x, p.y), MwStands.D0, "outside: %s" % p)
		if absf(p.y) < MwStands.PEN_Y and absf(p.x) > MwStands.BOARD.x:
			assert_gt(absf(p.x), MwStands.BOARD.x + MwStands.PEN_CLEAR, "behind the pens: %s" % p)


func test_facing_the_rink() -> void:
	for s: Dictionary in seats:
		var p: Vector3 = s["pos"]
		var f: Vector2 = s["facing"]
		assert_lt(f.dot(Vector2(p.x, p.y)), 0.0, "faces in: %s" % p)


func test_path_rows_line_up() -> void:
	# the same u is the same place at any offset: normals agree
	for u in MwStands.path_us(8.0):
		var a := MwStands.point_at_u(MwStands.offset(0), u)
		var b := MwStands.point_at_u(MwStands.offset(MwStands.ROWS - 1), u)
		assert_almost_eq((a["n"] as Vector2).dot(b["n"]), 1.0, 1e-3)


func test_top_rows_fade_to_black() -> void:
	assert_eq(MwStands3D.fade(0.0), 1.0, "the ice")
	assert_eq(MwStands3D.fade(MwStands.height(5) + 34.0), 1.0, "row 6's fans: full colour")
	assert_gt(MwStands3D.fade(MwStands.height(6) + 34.0), 0.9, "row 7's heads: barely")
	assert_lt(MwStands3D.fade(MwStands.height(8) + 17.0), 0.8, "row 9 darker")
	assert_lt(MwStands3D.fade(MwStands.height(9) + 34.0), 0.2, "the top row's heads nearly black")
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


func test_the_referee_mirrors_towards_the_play() -> void:
	if not MwRom.available():
		pending("no ROM")
		return
	var stands := MwStands3D.new()
	add_child_autofree(stands)
	var cam := Camera3D.new()
	add_child_autofree(cam)
	var at := MwRink3D.world(0, 400, 240)
	cam.transform = Transform3D(Basis.looking_at(MwRink3D.world(0, 0, 0) - at, Vector3.UP), at)
	assert_false(stands.ref_looks_right(), "looks left (at the rink) to start with")
	stands.watch(Vector3(300, 0, 0), cam)
	assert_true(stands.ref_looks_right(), "the puck to his right: mirrored")
	stands.watch(Vector3(225, 0, 0), cam)
	assert_true(stands.ref_looks_right(), "a little to his left: no flicker")
	stands.watch(Vector3(100, 0, 0), cam)
	assert_false(stands.ref_looks_right(), "well to his left: back")


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
