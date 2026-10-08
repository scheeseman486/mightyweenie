extends "res://test/rom/rom_test_base.gd"
## The 3D view's pieces (plan 14): conversions, variants, the cameras'
## projections, frame composition and the ROM-backed model. Rendering itself
## is checked on the desktop (test/rink3d/calibration_render.gd).

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")


func test_world_and_rink_round_trip() -> void:
	var p := Vector3(-120, 345, 17)
	var w := MwRink3D.world(p.x, p.y, p.z)
	assert_almost_eq(w, Vector3(-6.0, 0.85, 17.25), Vector3.ONE * 1e-5)
	assert_almost_eq(MwRink3D.rink(w), p, Vector3.ONE * 1e-4)
	assert_eq(MwRink3D.map_point(0, 0, 0), Vector2(256, 461))
	assert_eq(MwRink3D.map_point(-58, -105, 10), Vector2(198, 346))


func _camera(mode: int) -> MwRinkCamera3D:
	var vp := SubViewport.new()
	vp.size = MwRink3D.SCREEN
	vp.own_world_3d = true
	add_child_autofree(vp)
	var cam := MwRinkCamera3D.new()
	cam.mode = mode as MwRinkCamera3D.Mode
	vp.add_child(cam)
	cam.current = true
	return cam


func test_calibration_camera_is_the_originals_projection() -> void:
	var cam := _camera(MwRinkCamera3D.Mode.CALIBRATION)
	var shown := Vector2i(96, 293)
	cam.follow(Vector2(shown))
	var ws := cam.world_scale()
	for p in [Vector3(0, 0, 0), Vector3(-185, -372, 0), Vector3(185, 300, 48), Vector3(-60, 120, 33), Vector3(40, -350, 112)]:
		var screen := cam.unproject_position(MwRink3D.world(p.x, p.y, p.z) * ws)
		var want := MwRink3D.map_point(p.x, p.y, p.z) - Vector2(shown)
		assert_almost_eq(screen, want, Vector2.ONE * 0.05, "rink point %s" % p)


func test_follow_camera_frames_the_2d_window() -> void:
	var cam := _camera(MwRinkCamera3D.Mode.FOLLOW)
	var shown := Vector2(96, 400)
	cam.follow(shown)
	var look := MwRinkCamera3D.look_point(shown)
	var centre := cam.unproject_position(MwRink3D.world(look.x, look.y, 0))
	assert_almost_eq(centre, Vector2(160, 112), Vector2.ONE * 0.5)
	var left := cam.unproject_position(MwRink3D.world(look.x - 160, look.y, 0))
	var right := cam.unproject_position(MwRink3D.world(look.x + 160, look.y, 0))
	assert_almost_eq(left.x, 0.0, 1.0)
	assert_almost_eq(right.x, 320.0, 1.0)
	assert_lt(cam.unproject_position(MwRink3D.world(look.x, look.y - 100, 0)).y, centre.y, "north is up the screen")


func test_free_camera_stays_where_it_is_placed() -> void:
	var cam := _camera(MwRinkCamera3D.Mode.FREE)
	var at := Transform3D(Basis.looking_at(Vector3(1, -0.5, 0), Vector3.UP), Vector3(-3, 4, 1))
	cam.transform = at
	cam.follow(Vector2(96, 400))
	assert_eq(cam.transform, at, "follow leaves a free camera alone")
	assert_almost_eq(cam.heading(), PI / 2.0, 1e-5, "looking east")


func test_frames_compose_like_the_rom_frames() -> void:
	if not need_rom():
		return
	var sp := MwSprites3D.new()
	var cases := [[MwRinkDraw.SHADOW, 0x60], [MwRinkDraw.STAND_FRAME, 0x00], [MwRinkDraw.STAND_FRAME, 0x08],
			[MwRinkDraw.STAND_FRAME, 0x10], [MwRinkDraw.POSSESSION, 0x60]]
	for c in cases:
		var f := sp.frame_texture(rom, c[0], c[1])
		var ref := MwGfx.frame_image(rom, MwGfx.frame_pieces(rom, c[0]), (c[1] >> 3) & 3)
		assert_eq([f["w"], f["h"], -int(f["x0"]), -int(f["y0"])], [ref["w"], ref["h"], ref["ox"], ref["oy"]], "frame %X attr %X box" % c)
		var got: PackedByteArray = (f["tex"] as ImageTexture).get_image().get_data()
		var want: PackedByteArray = ref["px"]
		var same := got.size() == want.size()
		for i in mini(got.size(), want.size()):
			if got[i] % 16 != want[i] % 16:
				same = false
				break
		assert_true(same, "frame %X attr %X pixels" % c)
	sp.free()


func test_far_lamp_frames_hang_from_their_pin() -> void:
	if not need_rom():
		return
	var sp := MwSprites3D.new()
	add_child_autofree(sp)
	var pin := MwRinkDraw3D.FAR_PIN_Z
	var stand := {"frame": MwRinkDraw.STAND_FRAME, "attr": 0, "depth": 88, "place": MwRinkDraw3D.UPRIGHT,
			"at": Vector3(0, -371, 49), "offset": Vector2i.ZERO, "order": 0, "pin": pin}
	var player := {"frame": MwRinkDraw.STAND_FRAME, "attr": 0, "depth": 88, "place": MwRinkDraw3D.UPRIGHT,
			"at": Vector3(30, -300, 12), "offset": Vector2i.ZERO, "order": 1}
	var lamp := stand.duplicate()
	lamp["at"] = Vector3(0, -371, 47)
	lamp["order"] = 2
	sp.show_items([stand, player, lamp])
	var quads := sp.get_children().filter(func(n: Node) -> bool: return (n as MeshInstance3D).visible)
	assert_eq(quads.size(), 3)
	var f := sp.frame_texture(rom, MwRinkDraw.STAND_FRAME, 0)
	var want := [[stand, Vector2(pin, 0.0), 49 - pin, 0.0], [player, Vector2.ZERO, 12, 12 * MwRink3D.METRES_PER_PX],
			[lamp, Vector2(pin, MwSprites3D.SAME_POINT_BIAS), 47 - pin, MwSprites3D.SAME_POINT_BIAS]]
	for i in 3:
		var mi := quads[i] as MeshInstance3D
		var at: Vector3 = want[i][0]["at"]
		assert_eq(mi.position, MwRink3D.world(at.x, at.y, 0), "sorted at the ice point under it")
		assert_eq(mi.get_instance_shader_parameter("pin"), want[i][1], "pin %d" % i)
		var r: Vector4 = mi.get_instance_shader_parameter("px_rect")
		assert_eq(r.y, float(f["y0"]) - want[i][2], "raised above its anchor %d" % i)
		assert_almost_eq(mi.sorting_offset, want[i][3], 1e-6, "sort %d" % i)


func test_model_gets_rom_materials() -> void:
	if not need_rom():
		return
	var vp := SubViewport.new()
	vp.size = MwRink3D.SCREEN
	vp.own_world_3d = true
	add_child_autofree(vp)
	var view: MwRinkView3D = VIEW.instantiate()
	view.palette = RomPalette.make(4, PackedStringArray(["screen_palette", "rom 1BD8A 3"]), 3, 9)
	vp.add_child(view)
	var meshes := view.model.meshes()
	assert_eq(meshes.keys().size(), 9, "floor, wall, near_wall, glass, signs, signs_glass, fence, bench, bench_glass")
	var sizes := {"floor": Vector2i(512, 904), "signs": Vector2i(320, 72), "fence": Vector2i(320, 64)}
	for name in meshes:
		var m := (meshes[name] as MeshInstance3D).material_override as ShaderMaterial
		assert_not_null(m, name)
		var pic := m.get_shader_parameter("picture") as Texture2D
		assert_not_null(pic, name + " picture")
		assert_not_null(m.get_shader_parameter("palette"), name + " palette")
		if sizes.has(name):
			assert_eq(Vector2i(pic.get_size()), sizes[name], name)
