extends "res://test/rom/rom_test_base.gd"
## The 3D rink model (plan 14: game/assets/rink3d/rink.glb, made by
## tools/blender/rink_build.py and rink_export.py, tweakable in Blender): the
## boards must stand where the puck bounces (the physics boundary from the
## ROM's tables), and nothing ROM-derived may be in the file.

const GLB := "res://assets/rink3d/rink.glb"
const S := MwRink3D.METRES_PER_PX
const BOARD_X := 185
const BOARD_Y := 372
const OBJECTS := ["bench", "fence", "floor", "glass", "near_wall", "signs", "signs_glass", "wall"]


func _model() -> Node3D:
	var n := (load(GLB) as PackedScene).instantiate() as Node3D
	autofree(n)
	return n


func test_objects() -> void:
	var m := _model()
	for object_name in OBJECTS:
		assert_true(m.find_child(object_name, true, false) is MeshInstance3D, object_name)


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


static func _to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return (a + ab * t).distance_to(point)


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
	for object_name in ["wall", "near_wall", "glass", "signs", "signs_glass", "fence"]:
		var mesh := (m.find_child(object_name, true, false) as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var point := MwRink3D.rink(v)
				if point.z > 0.5:
					continue
				var d := _distance(point.x, point.y)
				count += 1
				if point.y > NEAR_FROM and d >= 1.5:     # the near end's outer wall and its glass
					assert_lt(d, NEAR_T + 1.5, "near wall at most %d px outside (%s)"
							% [NEAR_T, Vector2(point.x, point.y)])
					outside += 1
					continue
				if d > worst:
					worst = d
					where = Vector2(point.x, point.y)
	gut.p("%d base points (%d on the near end's outer wall), worst %.2f px at %s" % [count, outside, worst, where])
	assert_gt(count, 500)
	assert_gt(outside, 50, "the near end's outer wall stands outside the boundary")
	assert_lt(worst, 1.5, "boards within 1.5 px of where the puck bounces (worst at %s)" % where)


## Owner, 2026-10-11: the banners fill the boards in front of the benches
## (x -185, y -160..160) without a gap - no black filler column (u 0.5 px of
## the signs picture) - and 1:1: every face's columns as wide as it is long.
func test_the_banners_fill_the_bench_front() -> void:
	if not need_rom():
		return
	var mesh := (_model().find_child("signs", true, false) as MeshInstance3D).mesh
	var w := _picture_px("signs").x
	var lo := INF
	var hi := -INF
	var filler := 0
	var stretched := 0
	for sf in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(sf)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			var ps := []
			var us := []
			for k in 3:
				ps.append(MwRink3D.rink(verts[indices[t + k]]))
				us.append(uv[indices[t + k]].x * w)
			if absf(ps[0].x + BOARD_X) > 0.5:
				continue
			for p in ps:
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
			if absf(us[0] - 0.5) < 1e-3 and absf(us[1] - 0.5) < 1e-3 and absf(us[2] - 0.5) < 1e-3:
				filler += 1
			var dy := maxf(absf(ps[1].y - ps[0].y), maxf(absf(ps[2].y - ps[0].y), absf(ps[2].y - ps[1].y)))
			var du := maxf(absf(us[1] - us[0]), maxf(absf(us[2] - us[0]), absf(us[2] - us[1])))
			if absf(du - dy) > 1e-2:
				stretched += 1
	assert_almost_eq(lo, -160.0, 0.01, "from the north pen's end wall")
	assert_almost_eq(hi, 160.0, 0.01, "to the south pen's end wall")
	assert_eq(filler, 0, "no black filler: the banners fill it")
	assert_eq(stretched, 0, "the banners' columns 1:1, never stretched")


func test_uvs_stay_inside_their_pictures() -> void:
	var m := _model()
	for object_name in OBJECTS:
		var mesh := (m.find_child(object_name, true, false) as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var uvs: PackedVector2Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
			var bad := 0
			for uv in uvs:
				if uv.x < -1e-4 or uv.x > 1.0001 or uv.y < -1e-4 or uv.y > 1.0001:
					bad += 1
			assert_eq(bad, 0, object_name + " UVs in 0..1")


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
	var bytes := MwRom.data()
	for y in range(298, 372):
		var w := MwRinkShape.half_width(bytes, -y)
		assert_true(inside.call(w - 1, -y) and not inside.call(w, -y), "far corner row %d" % y)


# --- plan 37: the paint atlas's UV2 ----------------------------------------------------------

## Each object's picture size (px): UV0 is in its pixels.
func _picture_px(object_name: String) -> Vector2:
	var addr := MwRink3D.PICTURE_RINK
	if object_name.begins_with("signs"):
		addr = MwRink3D.PICTURE_SIGNS
	elif object_name == "fence":
		addr = MwRink3D.PICTURE_FENCE
	var pic := MwGfx.picture(rom, addr)
	return Vector2(int(pic["width"]) * 8, int(pic["height"]) * 8)


## Every face's UV2 is its UV0 shifted by whole texels into the paint atlas
## (so the paint has the picture's texel edges), or the dead texel; the ice
## takes the two blocks' shifts.
func test_paint_uv2_is_uv0_shifted_by_whole_texels() -> void:
	if not need_rom():
		return
	var m := _model()
	var size := float(MwSplatterAtlas.SIZE)
	var dead := Vector2(1023.5, 1023.5)
	var ice_shifts := {}
	for object_name in OBJECTS:
		var mesh := (m.find_child(object_name, true, false) as MeshInstance3D).mesh
		var pic := _picture_px(object_name)
		var painted := 0
		var bad := 0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			assert_eq(uv2.size(), uv.size(), object_name + " has UV2")
			for t in range(0, indices.size(), 3):
				var shifts := []
				for k in 3:
					var i := indices[t + k]
					var a := uv2[i] * size
					if a.distance_to(dead) < 1e-2:
						shifts.append(null)
						continue
					shifts.append(a - uv[i] * pic)
				if shifts[0] == null and shifts[1] == null and shifts[2] == null:
					continue
				painted += 1
				for sh in shifts:
					if sh == null or (sh as Vector2).distance_to(shifts[0]) > 1e-2 \
							or absf(sh.x - roundf(sh.x)) > 1e-2 or absf(sh.y - roundf(sh.y)) > 1e-2:
						bad += 1
						break
				if object_name == "floor" and bad == 0:
					ice_shifts[Vector2i(roundi(shifts[0].x), roundi(shifts[0].y))] = true
		assert_eq(bad, 0, object_name + ": UV2 = UV0 + whole texels")
		if object_name in ["floor", "wall", "glass", "signs", "fence"]:
			assert_gt(painted, 0, object_name + " takes paint")
		else:
			assert_eq(painted, 0, object_name + " takes none")
	assert_eq(ice_shifts.keys().size(), 2, "the ice's two blocks")
	assert_true(ice_shifts.has(Vector2i(-70, -88)) and ice_shifts.has(Vector2i(-70, 617)), str(ice_shifts.keys()))


## The boards' runs (rink_paint.json) fit the atlas without overlapping each
## other, the ice's blocks or the dead texel.
func test_paint_runs_do_not_overlap() -> void:
	var board_layout := MwSplatterAtlas.layout()
	var used := PackedByteArray()
	used.resize(MwSplatterAtlas.SIZE * MwSplatterAtlas.SIZE)
	var bad := 0
	for r: Array in board_layout["runs"]:
		for col in range(int(r[1]), int(r[1]) + int(r[3])):
			for row in range(int(r[2]), int(r[2]) + int(r[4])):
				if col >= MwSplatterAtlas.SIZE or row >= MwSplatterAtlas.SIZE:
					bad += 1
					continue
				if (col < 373 and row < 749) or (col == 1023 and row == 1023):
					bad += 1
				var i := row * MwSplatterAtlas.SIZE + col
				if used[i] != 0:
					bad += 1
				used[i] = 1
	assert_eq(bad, 0, "runs apart, clear of the ice and the dead texel")
