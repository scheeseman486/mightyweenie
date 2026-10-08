extends "res://test/rom/rom_test_base.gd"
## The 3D rink model (plan 14: game/assets/rink3d/rink.glb, made by
## tools/blender/rink_build.py and rink_export.py, tweakable in Blender): the
## boards must stand where the puck bounces (the physics boundary from the
## ROM's tables), and nothing ROM-derived may be in the file.

const GLB := "res://assets/rink3d/rink.glb"
const S := MwRink3D.METRES_PER_PX
const BOARD_X := 185
const BOARD_Y := 372
const OBJECTS := ["bench", "bench_glass", "fence", "floor", "glass", "near_wall", "signs", "signs_glass", "wall"]


func _model() -> Node3D:
	var n := (load(GLB) as PackedScene).instantiate() as Node3D
	autofree(n)
	return n


func test_objects() -> void:
	var m := _model()
	for name in OBJECTS:
		assert_true(m.find_child(name, true, false) is MeshInstance3D, name)


func test_no_images_in_the_glb() -> void:
	var f := FileAccess.open(GLB, FileAccess.READ)
	var data := f.get_buffer(f.get_length())
	var length := data.decode_u32(12)
	var json: Dictionary = JSON.parse_string(data.slice(20, 20 + length).get_string_from_utf8())
	assert_false(json.has("images"), "no images")
	assert_false(json.has("textures"), "no textures")


## x limit of the physics boundary at row |y| (the boards' surface).
func _xlim(y: float) -> float:
	var far := y < 0
	var a := absf(y)
	var table := 0x1C77E if far else 0x1C81E
	var first := 298 if far else 324
	var row := int(a)
	if row < first:
		return BOARD_X
	row = mini(row, BOARD_Y - 1)
	return mini(BOARD_X, MwGfx.u16(rom, table + 2 * (row - first + 1)))


## Distance (px) from a point to the physics boundary: per row r the
## boards' surface is at x = xlim(r) for r <= |y| < r + 1 (the tables'
## staircase: a vertical piece per row and a step to the next row), and the
## end boards at |y| = 372 out to the last row's limit.
func _distance(x: float, y: float) -> float:
	var best := INF
	var sy := signf(y) if y != 0 else 1.0
	var px := absf(x)
	var py := absf(y)
	for r in range(int(py) - 16, int(py) + 17):
		if r < 0 or r >= BOARD_Y:
			continue
		var bx := _xlim(sy * r)
		var nx := _xlim(sy * (r + 1)) if r + 1 < BOARD_Y else 0.0
		best = minf(best, _to_segment(Vector2(px, py), Vector2(bx, r), Vector2(bx, r + 1)))
		best = minf(best, _to_segment(Vector2(px, py), Vector2(bx, r + 1), Vector2(nx, r + 1)))
	return best


static func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return (a + ab * t).distance_to(p)


## The near end's outer wall stands this far outside the boundary, as the rink
## picture draws it (tools/blender/rink_build.py NEAR_T); its padding stays on it.
const NEAR_T := 11.0
const NEAR_FROM := 300.0


func test_boards_stand_on_the_physics_boundary() -> void:
	if not need_rom():
		return
	var m := _model()
	var worst := 0.0
	var where := Vector2.ZERO
	var count := 0
	var outside := 0
	for name in ["wall", "near_wall", "glass", "signs", "signs_glass", "fence"]:
		var mesh := (m.find_child(name, true, false) as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := MwRink3D.rink(v)
				if p.z > 0.5:
					continue
				var d := _distance(p.x, p.y)
				count += 1
				if p.y > NEAR_FROM and d >= 1.5:     # the near end's outer wall and its glass
					assert_lt(d, NEAR_T + 1.5, "near wall at most %d px outside (%s)" % [NEAR_T, Vector2(p.x, p.y)])
					outside += 1
					continue
				if d > worst:
					worst = d
					where = Vector2(p.x, p.y)
	gut.p("%d base points (%d on the near end's outer wall), worst %.2f px at %s" % [count, outside, worst, where])
	assert_gt(count, 500)
	assert_gt(outside, 50, "the near end's outer wall stands outside the boundary")
	assert_lt(worst, 1.5, "boards within 1.5 px of where the puck bounces (worst at %s)" % where)


func test_uvs_stay_inside_their_pictures() -> void:
	var m := _model()
	for name in OBJECTS:
		var mesh := (m.find_child(name, true, false) as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var uvs: PackedVector2Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]
			var bad := 0
			for uv in uvs:
				if uv.x < -1e-4 or uv.x > 1.0001 or uv.y < -1e-4 or uv.y > 1.0001:
					bad += 1
			assert_eq(bad, 0, name + " UVs in 0..1")


func test_the_floor_shows_only_the_ice() -> void:
	if not need_rom():
		return
	var img := MwRinkModel.ice_mask().get_image()
	var inside := func(x: int, y: int) -> bool:
		var m := MwRink3D.map_point(x, y, 0)
		return img.get_pixel(int(m.x), int(m.y)).r > 0.5
	for p in [Vector2i(0, 0), Vector2i(184, 0), Vector2i(-184, 200), Vector2i(0, 371), Vector2i(0, -371),
			Vector2i(100, 370), Vector2i(150, -320), Vector2i(-150, 330)]:
		assert_true(inside.call(p.x, p.y), "ice at %s" % p)
	for p in [Vector2i(185, 0), Vector2i(-186, 100), Vector2i(0, 372), Vector2i(0, -372), Vector2i(184, 370),
			Vector2i(-180, -365), Vector2i(230, 0), Vector2i(-240, 120), Vector2i(0, 420)]:
		assert_false(inside.call(p.x, p.y), "black at %s (boards, corners, pens, crowd)" % p)
	# the corners as the puck meets them
	var rom := MwRom.data()
	for y in range(298, 372):
		var w := MwRinkModel.ice_half_width(rom, -y)
		assert_true(inside.call(w - 1, -y) and not inside.call(w, -y), "far corner row %d" % y)
