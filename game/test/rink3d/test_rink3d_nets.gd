extends "res://test/rom/rom_test_base.gd"
## The nets as 3D models (plan 17, MwNet3D / MwNets3D): the standard net's
## and the Battle Net's parts and material names, their size against the
## original's numbers, one closed frame and outline, continuous stipple, the
## ground shadow's rule, and the view standing models in place of the nets'
## drawings (not the Demon Net's; not for the calibration camera).

const S := MwRink3D.METRES_PER_PX
const BAR_Z := 20.0      # the roof's height (tools/blender/net_build.py)
const STANDARD := 1
const BATTLE := 2


## The model's mesh instances by part (frame, outline, netting, shadow: the
## object's name after its style).
func _parts(style: int) -> Dictionary:
	var out := {}
	var model: Node3D = MwNet3D.MODELS[style].instantiate()
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		out[String(mi.name).get_slice("_", 1)] = mi.mesh
	model.free()
	return out


## Rink px of a model point: (x, d behind the goal line, height).
func _px(v: Vector3) -> Vector3:
	return Vector3(v.x / S, -v.z / S, v.y / S)


func _points_of(mesh: Mesh) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for s in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			pts.append(_px(v))
	return pts


func _bounds(pts: PackedVector3Array) -> AABB:
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


func test_parts_and_materials() -> void:
	for style: int in MwNet3D.MODELS:
		var parts := _parts(style)
		assert_eq_deep(parts.keys().map(func(k): return k).filter(func(k): return k in ["frame", "outline", "netting", "shadow"]).size(), 4)
		for part: String in parts:
			var mesh: Mesh = parts[part]
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s)
				assert_not_null(MwNet3D.material_for(mat.resource_name), "%d %s: %s" % [style, part, mat.resource_name])


func test_material_names_carry_indices() -> void:
	var bar := MwNet3D.material_for("bar_0_11")
	assert_eq(bar.shader, MwNet3D.FLAT)
	assert_eq(bar.get_shader_parameter("index"), 11)
	var spike := MwNet3D.material_for("spike_0_7")
	assert_eq(spike.shader, MwNet3D.FLAT)
	assert_eq(spike.get_shader_parameter("index"), 7)
	var net := MwNet3D.material_for("net_0_1_8")
	assert_eq(net.shader, MwNet3D.NETTING)
	assert_eq([net.get_shader_parameter("outer"), net.get_shader_parameter("inner")], [1, 8])
	assert_eq(MwNet3D.material_for("shadow_0_6").get_shader_parameter("fill"), 6)
	assert_eq(MwNet3D.material_for("outline_1_9").get_shader_parameter("index"), 25, "line 1")
	assert_eq(MwNet3D.material_for("hidden").shader, MwNet3D.HIDDEN)
	assert_null(MwNet3D.material_for("Material"))


func test_size_against_the_original() -> void:
	var parts := _parts(STANDARD)
	var all := PackedVector3Array()
	for part: String in parts:
		all.append_array(_points_of(parts[part]))
	var box := _bounds(all)
	var frame := _bounds(_points_of(parts["frame"]))
	# inside where the puck's centre stops ($1C74A: half width 28, 16 behind)
	assert_between(box.end.x, 24.0, 28.0, "as wide as the footprint, inside the physics")
	assert_almost_eq(box.position.x, -box.end.x, 0.01, "symmetric")
	assert_between(box.end.y, 14.0, 16.0, "as deep as the footprint")
	assert_between(box.end.z, 20.0, 22.5, "the crossbar's top (the drawings: 20-22)")
	assert_almost_eq(frame.position.z, 0.0, 0.01, "the frame stands on the ice")
	assert_gt(box.position.z, -0.5, "only the outline shell's underside below it")
	var post := 0
	for p in _points_of(parts["frame"]):
		if absf(p.y) < 1.0 and p.z > 10.0 and absf(absf(p.x) - 21.0) <= 0.81:
			post += 1
	assert_gt(post, 0, "posts at x +-21")


func test_battle_net_is_the_standard_with_spikes() -> void:
	var standard := _parts(STANDARD)
	var battle := _parts(BATTLE)
	for part in ["netting", "shadow"]:
		var a := _bounds(_points_of(standard[part]))
		var b := _bounds(_points_of(battle[part]))
		assert_almost_eq(b.position, a.position, Vector3.ONE * 0.01, part)
		assert_almost_eq(b.end, a.end, Vector3.ONE * 0.01, part)
	var frame := _bounds(_points_of(battle["frame"]))
	assert_gt(frame.end.x, 30.0, "spikes out of the sides")
	assert_gt(frame.end.z, 23.0, "and over the roof")
	# the spikes in their own greys, lit and shaded (owner: distinct at low
	# res), the feet of those on the netting hidden (the netting is
	# see-through), in the frame and its outline - the standard net has none
	var greys := []
	for s in battle["frame"].get_surface_count():
		var name: String = battle["frame"].surface_get_material(s).resource_name
		if name.begins_with("spike_"):
			greys.append(int(name.get_slice("_", 2)))
	greys.sort()
	assert_eq(greys, [1, 7, 8], "up, sideways, down")
	for part in ["frame", "outline"]:
		assert_true(_materials(battle[part]).has("hidden"), "battle %s: hidden feet" % part)
		assert_false(_materials(standard[part]).has("hidden"), "standard %s" % part)


func _materials(mesh: Mesh) -> Array:
	return range(mesh.get_surface_count()).map(func(s): return mesh.surface_get_material(s).resource_name)


## Every surface of [param mesh] as triangles of rink px points (and UVs).
func _triangles(mesh: Mesh) -> Array:
	var out := []
	for sf in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(sf)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in range(0, idx.size(), 3):
			var t := [idx[i], idx[i + 1], idx[i + 2]]
			out.append([t.map(func(j): return _px(v[j])), t.map(func(j): return uv[j] if not uv.is_empty() else Vector2.ZERO)])
	return out


var _points: Array[Vector3] = []


## A point's index among the points seen, the same for points within
## 0.02 px (the import compresses each surface's positions on its own).
func _key(p: Vector3) -> int:
	for i in _points.size():
		if _points[i].distance_to(p) < 0.02:
			return i
	_points.append(p)
	return _points.size() - 1


## [param mesh]'s edges used by other than two triangles, and its pieces.
func _closed_pieces(mesh: Mesh) -> Array:
	_points.clear()
	var edges := {}
	var links := {}
	for t: Array in _triangles(mesh):
		for k in 3:
			var a := _key(t[0][k])
			var b := _key(t[0][(k + 1) % 3])
			edges[Vector2i(mini(a, b), maxi(a, b))] = edges.get(Vector2i(mini(a, b), maxi(a, b)), 0) + 1
			links.get_or_add(a, []).append(b)
	var open := edges.keys().filter(func(e): return edges[e] != 2)
	var pieces := 0
	var seen := {}
	for start: int in links:
		if seen.has(start):
			continue
		pieces += 1
		var todo: Array = [start]
		while not todo.is_empty():
			var p: int = todo.pop_back()
			if seen.has(p):
				continue
			seen[p] = true
			todo.append_array(links.get(p, []))
	return [open, pieces]


func test_frame_is_one_closed_mesh() -> void:
	# owner: one continuous mesh (the outline unbroken at the joins): every
	# edge between exactly two triangles; the standard frame in one piece
	# (the Battle Net's netting spikes stand apart from it)
	for style: int in MwNet3D.MODELS:
		var parts := _parts(style)
		for part in ["frame", "outline"]:
			var r := _closed_pieces(parts[part])
			assert_eq(r[0].size(), 0, "%d %s: edges not between two faces: %s" % [style, part, r[0].slice(0, 4)])
			if style == STANDARD:
				assert_eq(r[1], 1, "%s: one piece" % part)


func test_netting_stipple_is_continuous() -> void:
	# owner: the stipple lines up across the back - the sides' and back's
	# netting share their UVs wherever their faces meet (the roof's own)
	for style: int in MwNet3D.MODELS:
		var uvs := {}
		_points.clear()
		for t: Array in _triangles(_parts(style)["netting"]):
			for k in 3:
				var p: Vector3 = t[0][k]
				if p.z < BAR_Z - 0.01:
					uvs.get_or_add(_key(p), []).append(t[1][k])
		assert_gt(uvs.size(), 20)
		for key: int in uvs:
			for uv: Vector2 in uvs[key]:
				assert_almost_eq(uv, uvs[key][0], Vector2(0.01, 0.01), "%d: UV at %s" % [style, _points[key]])


func test_ground_shadow_rule() -> void:
	if not need_rom():
		return
	var decal := MwNet3D.ground_decal(rom)
	assert_eq(decal.get_size(), Vector2i(38, 12))
	var used := {}
	for y in decal.get_height():
		for x in decal.get_width():
			used[decal.get_pixel(x, y).r8] = true
	assert_eq_deep(used.keys().filter(func(i): return i not in [0, 5, 6]), [])
	assert_true(used.has(0) and used.has(5) and used.has(6), "shadow (5, 6) and bare ice (0)")
	assert_eq(MwNet3D.shadow_index(decal, -23, 6), 6, "the side, hidden by the netting: filled")
	assert_eq(MwNet3D.shadow_index(decal, 22, 10), 6, "the other side")
	assert_eq(MwNet3D.shadow_index(decal, 0, 1), 0, "the mouth's front: ice")
	assert_eq(MwNet3D.shadow_index(decal, 0, 14), 6, "behind the back bar: filled")
	assert_eq(MwNet3D.shadow_index(decal, -19, 13), decal.get_pixel(0, 11).r8, "the drawing's own")
	# the Battle Net's drawing shows the same ground, a pixel lower
	assert_eq(MwNet3D.ground_decal(rom, BATTLE).get_data(), decal.get_data())
	assert_eq(MwNet3D.shadow_index(decal, 0, 1, 6, BATTLE), decal.get_pixel(19, 0).r8)


func test_models_in_place_of_the_nets() -> void:
	if not need_rom():
		return
	var anims := [0, 1, 2].map(func(s): return MwGfx.u32(rom, MwRinkState.NET_ANIMS + 4 * s))
	var nets := MwNets3D.new()
	add_child_autofree(nets)
	var items := [
		{"key": "net0/body", "at": Vector3(0, -329, 0), "net": {"anim": anims[STANDARD], "mouth": 1}},
		{"key": "net1/body", "at": Vector3(0, 329, 0), "net": {"anim": anims[STANDARD], "mouth": -1}},
		{"key": "puck/body", "at": Vector3(10, 20, 0)},
	]
	var rest := nets.take(items)
	assert_eq(rest.size(), 1, "the puck stays a sprite")
	var shown := nets.shown()
	assert_eq(shown.size(), 2)
	var far: MwNet3D = shown["net0/body"]
	var near: MwNet3D = shown["net1/body"]
	assert_eq([far.style, near.style], [STANDARD, STANDARD])
	assert_almost_eq(far.position, MwRink3D.world(0, -329, 0), Vector3.ONE * 1e-4)
	assert_almost_eq(far.basis.z, Vector3(0, 0, 1), Vector3.ONE * 1e-4, "far net: mouth south")
	assert_almost_eq(near.basis.z, Vector3(0, 0, -1), Vector3.ONE * 1e-4, "near net: turned round")
	# the calibration camera keeps the drawings
	assert_eq(nets.take(items, true).size(), 3)
	assert_eq(nets.shown().size(), 0)
	# Battle Nets: their own model
	items[0]["net"]["anim"] = anims[BATTLE]
	items[1]["net"]["anim"] = anims[BATTLE]
	assert_eq(nets.take(items).size(), 1)
	assert_eq(nets.shown().values().map(func(n): return n.style), [BATTLE, BATTLE])
	# the Demon Net (the top net only) keeps its drawings
	items[0]["net"]["anim"] = anims[0]
	assert_eq(nets.take(items).size(), 2)
	assert_eq(nets.shown().keys(), ["net1/body"])
