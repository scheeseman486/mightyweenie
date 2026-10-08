extends "res://test/rom/rom_test_base.gd"
## MwRinkFacing3D (plan 16): each sprite shows the side the camera sees
## (Doom's rule), the calibration camera keeps the original's variants, nets
## show front or back by side.

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")


func _camera_at(from: Vector3, to: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	var a := MwRink3D.world(from.x, from.y, from.z)
	cam.transform = Transform3D(Basis.looking_at(MwRink3D.world(to.x, to.y, to.z) - a, Vector3.UP), a)
	return cam


func test_a_sprite_seen_from_eight_sides() -> void:
	# a player facing north (variant 0) at the centre, the camera 300 px away
	# on the ice's 8 compass points, 200 px up, looking at him
	# (seen from the west, looking east, his north is on the left: variant 6)
	var cases := [["south", Vector3(0, 300, 200), 0], ["south-west", Vector3(-212, 212, 200), 7],
			["west", Vector3(-300, 0, 200), 6], ["north-west", Vector3(-212, -212, 200), 5],
			["north", Vector3(0, -300, 200), 4], ["north-east", Vector3(212, -212, 200), 3],
			["east", Vector3(300, 0, 200), 2], ["south-east", Vector3(212, 212, 200), 1]]
	for c: Array in cases:
		var cam := _camera_at(c[1], Vector3.ZERO)
		var v := MwRinkFacing3D.shown_variant(0, MwRinkFacing3D.view_angle(cam, Vector3.ZERO))
		assert_eq(v, c[2], "seen from the %s" % c[0])
		cam.free()
	# facing east (2), seen from the east: his front (4, facing the camera)
	var east := _camera_at(Vector3(300, 0, 200), Vector3.ZERO)
	assert_eq(MwRinkFacing3D.shown_variant(2, MwRinkFacing3D.view_angle(east, Vector3.ZERO)), 4)
	east.free()


func test_per_sprite_not_per_camera() -> void:
	# one camera looking north from the south: a sprite straight ahead keeps
	# its variant, one far off to the right is seen a little from its left
	var cam := _camera_at(Vector3(0, 300, 240), Vector3(0, 0, 0))
	assert_eq(MwRinkFacing3D.shown_variant(0, MwRinkFacing3D.view_angle(cam, Vector3(0, 0, 0))), 0)
	assert_eq(MwRinkFacing3D.shown_variant(0, MwRinkFacing3D.view_angle(cam, Vector3(200, 0, 0))), 7)
	cam.free()


func test_calibration_camera_keeps_the_originals_variants() -> void:
	if not need_rom():
		return
	var passes: Array = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_draw.json")))["passes"]
	var vp := SubViewport.new()
	vp.size = MwRink3D.SCREEN
	vp.own_world_3d = true
	add_child_autofree(vp)
	var cam := MwRinkCamera3D.new()
	cam.mode = MwRinkCamera3D.Mode.CALIBRATION
	vp.add_child(cam)
	var n := 0
	for p in passes:
		var d := MwRinkDraw3D.new(rom)
		d.build(MwRinkState.from_dict(rom, p["state"]), p["phase_adds"])
		cam.follow(Vector2(MwRinkState.from_dict(rom, p["state"]).camera.shown))
		var shown := MwRinkFacing3D.apply(d.items, cam, rom)
		for i in shown.size():
			var a: Dictionary = d.items[i]
			var b: Dictionary = shown[i]
			if a.has("carrier"):
				continue      # re-anchored on the carrier, same spot on screen
			assert_eq([b["frame"], b["attr"], b["offset"]], [a["frame"], a["attr"], a["offset"]],
					"%s: %s as in 2D" % [p["name"], a["key"]])
			n += 1
	assert_gt(n, 100)


func test_nets_front_and_back() -> void:
	var from_south := _camera_at(Vector3(0, 500, 200), Vector3(0, -300, 0))
	var from_north := _camera_at(Vector3(0, -500, 200), Vector3(0, 300, 0))
	var far := Vector3(0, -330, 0)      # mouth facing south
	var near := Vector3(0, 330, 0)      # mouth facing north
	assert_true(MwRinkFacing3D.net_front(1, MwRinkFacing3D.view_angle(from_south, far)), "far net from the south: front")
	assert_false(MwRinkFacing3D.net_front(-1, MwRinkFacing3D.view_angle(from_south, near)), "near net from the south: back")
	assert_false(MwRinkFacing3D.net_front(1, MwRinkFacing3D.view_angle(from_north, far)), "far net from behind: back")
	assert_true(MwRinkFacing3D.net_front(-1, MwRinkFacing3D.view_angle(from_north, near)), "near net from the north: front")
	from_south.free()
	from_north.free()


func test_turned_items_are_copies() -> void:
	if not need_rom():
		return
	var passes: Array = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_draw.json")))["passes"]
	var p: Dictionary = passes[0]
	var d := MwRinkDraw3D.new(rom)
	d.build(MwRinkState.from_dict(rom, p["state"]), p["phase_adds"])
	var before := str(d.items)
	var cam := _camera_at(Vector3(0, -600, 300), Vector3(0, 0, 0))
	var shown := MwRinkFacing3D.apply(d.items, cam, rom)
	cam.free()
	assert_eq(str(d.items), before, "the pass's items are untouched")
	var differ := 0
	for i in shown.size():
		if shown[i]["frame"] != d.items[i]["frame"]:
			differ += 1
	assert_gt(differ, 0, "seen from the north, the players turn")
