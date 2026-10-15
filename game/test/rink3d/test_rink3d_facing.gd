extends "res://test/rom/rom_test_base.gd"
## MwRinkFacing3D (plan 16): each sprite shows the side the camera sees
## (Doom's rule), the calibration camera keeps the original's variants, nets
## show front or back by side.
## Short names: d the MwRinkDraw3D under test.

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
	var passes: Array = JSON.parse_string(FileAccess.get_file_as_string(
			repo_path("compare/fixtures/rink_draw.json")))["passes"]
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
	assert_true(MwRinkFacing3D.net_front(1, MwRinkFacing3D.view_angle(from_south, far)),
			"far net from the south: front")
	assert_false(MwRinkFacing3D.net_front(-1, MwRinkFacing3D.view_angle(from_south, near)),
			"near net from the south: back")
	assert_false(MwRinkFacing3D.net_front(1, MwRinkFacing3D.view_angle(from_north, far)), "far net from behind: back")
	assert_true(MwRinkFacing3D.net_front(-1, MwRinkFacing3D.view_angle(from_north, near)),
			"near net from the north: front")
	from_south.free()
	from_north.free()


func test_turned_items_are_copies() -> void:
	if not need_rom():
		return
	var passes: Array = JSON.parse_string(FileAccess.get_file_as_string(
			repo_path("compare/fixtures/rink_draw.json")))["passes"]
	var first_pass: Dictionary = passes[0]
	var d := MwRinkDraw3D.new(rom)
	d.build(MwRinkState.from_dict(rom, first_pass["state"]), first_pass["phase_adds"])
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


func test_a_carried_puck_goes_behind_a_player_seen_from_behind() -> void:
	if not need_rom():
		return
	assert_true(MwRinkFacing3D.blade_behind(0), "his back to the camera")
	assert_true(MwRinkFacing3D.blade_behind(7) and MwRinkFacing3D.blade_behind(1))
	assert_false(MwRinkFacing3D.blade_behind(4), "facing the camera")
	assert_false(MwRinkFacing3D.blade_behind(2) or MwRinkFacing3D.blade_behind(6), "side on")
	var passes: Array = JSON.parse_string(FileAccess.get_file_as_string(
			repo_path("compare/fixtures/rink_draw.json")))["passes"]
	var found := 0
	for p in passes:
		var d := MwRinkDraw3D.new(rom)
		d.build(MwRinkState.from_dict(rom, p["state"]), p["phase_adds"])
		var carried := d.items.filter(func(it: Dictionary) -> bool: return it.has("carrier"))
		if carried.is_empty():
			continue
		for from in [Vector3(0, 600, 300), Vector3(0, -600, 300)]:
			var cam := _camera_at(from, Vector3.ZERO)
			var shown := MwRinkFacing3D.apply(d.items, cam, rom)
			var body := {}
			for it: Dictionary in shown:
				if it.has("dir") and str(it["key"]).ends_with("/body"):
					body[it["key"]] = MwRinkFacing3D.shown_variant(int(it["dir"]["variant"]),
							MwRinkFacing3D.view_angle(cam, it["at"]))
			for it: Dictionary in shown:
				if it.has("carrier") and body.has(it["carrier"]):
					assert_eq(it.get("behind"), MwRinkFacing3D.blade_behind(body[it["carrier"]]), p["name"])
					found += 1
			cam.free()
	assert_gt(found, 0, "a carried puck in the fixtures")


func test_a_puck_behind_its_carrier_is_pushed_back() -> void:
	if not need_rom():
		return
	var sp := MwSprites3D.new()
	add_child_autofree(sp)
	sp.reflections = false          # (the reflections' quads: test_reflections)
	var frame := MwGfx.u32(rom, MwRinkDraw.PLATES)        # any drawable frame
	var it := {"place": MwRinkDraw3D.UPRIGHT, "frame": frame, "attr": 0, "at": Vector3(0, 0, 0),
			"offset": Vector2i.ZERO, "depth": 8}
	var puck := it.duplicate()
	puck["behind"] = true
	sp.show_items([it, puck])
	var quads := sp.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and n.visible)
	assert_eq(quads.size(), 2)
	assert_lt((quads[1] as MeshInstance3D).get_instance_shader_parameter("pin").y, 0.0, "pushed behind")
	assert_lt((quads[1] as MeshInstance3D).sorting_offset, (quads[0] as MeshInstance3D).sorting_offset,
			"and drawn before")


func test_spikes_point_into_the_ice_from_any_side() -> void:
	# spikes on the west board (x -185, drawn for the original's camera
	# looking north): a camera looking north keeps the picture, one looking
	# south mirrors it - on the screen east and west change sides, so the
	# blade still points into the ice from over its board (owner, 2026-10-12)
	var spike := {"place": MwRinkDraw3D.UPRIGHT, "at": Vector3(-185, 80, 0), "frame": 1, "attr": 0x20,
			"wall": true, "key": "obj0/body"}
	var cases := [["south", Vector3(-185, 400, 200), false], ["north", Vector3(-185, -300, 200), true],
			["south-east", Vector3(100, 300, 200), false], ["north-east", Vector3(100, -200, 200), true]]
	for c: Array in cases:
		var cam := _camera_at(c[1], Vector3(-185, 80, 0))
		var shown: Dictionary = MwRinkFacing3D.apply([spike], cam, PackedByteArray([0]))[0]
		assert_eq(int(shown["attr"]) & MwRinkFacing3D.MIRROR_BIT != 0, c[2], "seen from the %s" % c[0])
		assert_eq(int(shown["attr"]) & ~MwRinkFacing3D.MIRROR_BIT, 0x20, "only the mirror bit")
		cam.free()
	assert_eq(int(spike["attr"]), 0x20, "the item itself unchanged (a copy turned)")
	# the east board's spikes (mirrored by the original) lose the bit from the north
	var east := spike.duplicate()
	east["at"] = Vector3(185, 80, 0)
	east["attr"] = 0x20 | MwRinkFacing3D.MIRROR_BIT
	var north := _camera_at(Vector3(185, -300, 200), Vector3(185, 80, 0))
	assert_eq(int(MwRinkFacing3D.apply([east], north, PackedByteArray([0]))[0]["attr"]), 0x20)
	north.free()


func test_the_draw_marks_spikes_on_the_wall() -> void:
	if not need_rom():
		return
	var s := MwRinkState.new()
	s.rng = MlhRng.new(1)
	s.setup(rom, 0)
	s.phase = MwRinkState.PHASE_PLAY
	var spikes := MwRinkState.RinkObject.new()
	s.objects.append(spikes)
	s.spawn(rom, spikes, -185, 80, MwRinkState.KIND_SPIKES, 0)
	var rink_object := MwRinkState.RinkObject.new()
	s.objects.append(rink_object)
	s.spawn(rom, rink_object, 0, 0, MwRinkState.KIND_FIRE, 0)
	var d := MwRinkDraw3D.new(rom)
	d.build(s, [])
	var walls := d.items.filter(func(it: Dictionary) -> bool: return it.get("wall", false))
	assert_gt(walls.size(), 0, "the spikes' frame marked")
	for it: Dictionary in walls:
		assert_true(str(it["key"]).begins_with("obj%d/body" % s.objects.find(spikes)),
				"only the spikes': %s" % it["key"])
