extends "res://test/rom/rom_test_base.gd"
## The rink sprites' shadows laid flat on the ice in 3D (owner, 2026-10-09;
## MwFlatShadows, MwSettings.flat_shadows): the shadow pixels, the flat made
## of them, the bench area, and the 3D sprites using them.

## A skater's frame (team A's attr): its shadow is a dither of colour 11
## under its skates, and a line along its raised stick.
const SKATER := 0x45252
const TEAM_A := 0x20

var _was := true


func before_each() -> void:
	_was = MwSettings.flat_shadows
	MwSettings.flat_shadows = true


func after_each() -> void:
	MwSettings.flat_shadows = _was


func test_shadow_pixels_are_colour_11_of_the_team_lines() -> void:
	assert_true(MwFlatShadows.is_shadow(16 + 11))
	assert_true(MwFlatShadows.is_shadow(32 + 11))
	assert_false(MwFlatShadows.is_shadow(11), "line 0's colour 11 is the ice's own")
	assert_false(MwFlatShadows.is_shadow(48 + 11))
	assert_false(MwFlatShadows.is_shadow(16 + 15), "black")
	var px := PackedByteArray([0, 27, 31, 43, 63, 18])
	assert_eq(MwFlatShadows.strip(px), PackedByteArray([0, 0, 31, 0, 63, 18]))
	assert_eq(px, PackedByteArray([0, 27, 31, 43, 63, 18]), "a copy")
	assert_false(MwFlatShadows.has_shadow(PackedByteArray([0, 31, 63])))


func test_the_flat_keeps_the_dither() -> void:
	# a checkerboard of shadow pixels, 6 x 3 (owner: the dither stays)
	var shadow := 27
	var px := PackedByteArray([
		shadow, 0, shadow, 0, shadow, 0,
		0, shadow, 0, shadow, 0, shadow,
		shadow, 0, shadow, 0, shadow, 0])
	var m := MwFlatShadows.mask(px, 6)
	assert_eq(m, PackedByteArray([
		255, 0, 255, 0, 255, 0,
		0, 255, 0, 255, 0, 255,
		255, 0, 255, 0, 255, 0]), "the shadow pixels as they are")
	assert_eq(MwFlatShadows.mask(PackedByteArray([0, 31, 0]), 3), PackedByteArray(), "no shadow: no flat")


func test_the_flat_runs_under_the_figure_standing_on_it() -> void:
	var shadow := 27
	var f := 31       # the figure's black
	var c := 18
	# a skate (5 px of the figure) between two shadow runs: dithered over; a
	# gap of two transparent pixels: not (the ice between two shadows)
	var px := PackedByteArray([shadow, shadow, f, c, c, c, f, shadow, 0, 0, shadow])
	var m := MwFlatShadows.mask(px, px.size())
	assert_eq(m, PackedByteArray([255, 255, 0, 255, 0, 255, 0, 255, 0, 0, 255]))
	# a figure wider than BODY_GAP between two shadow pixels: not filled
	var wide := PackedByteArray([shadow])
	for i in MwFlatShadows.BODY_GAP + 1:
		wide.append(c)
	wide.append(shadow)
	var mw := MwFlatShadows.mask(wide, wide.size())
	assert_eq(mw[2], 0, "too wide to be its feet")
	# one transparent pixel next to the figure is part of the gap
	var px2 := PackedByteArray([shadow, 0, f, f, shadow])
	assert_eq(MwFlatShadows.mask(px2, 5), PackedByteArray([255, 0, 255, 0, 255]))


## The stick's shadow stays on the billboard (owner's decision): pixels
## beside the stick, and a patch up in the air that touches it, to its end;
## on the ground only those beside the blade.
func test_the_sticks_shadow_stays_on_the_stick() -> void:
	var shadow := 27
	var k := 20        # colour 4 of line 1: the stick
	var b := 31
	var w := 8
	var px := PackedByteArray()
	px.resize(w * 11)            # rows -10..0 from the frame's point
	for x in range(2, 6):
		px[x] = k                # a raised stick (row -10)
		px[w + x] = shadow            # its shadow line below it
	px[2 * w + 6] = shadow            # the line going on, two and three pixels away
	px[3 * w + 7] = shadow
	px[9 * w + 0] = k            # the blade on the ice (row -1)
	px[9 * w + 3] = b            # a skate
	for x in [0, 1, 5, 6, 7]:
		px[10 * w + x] = shadow       # the shadow on the ice (row 0)
	var m := MwFlatShadows.mask(px, w, -10)
	var on := MwFlatShadows.ON_STICK
	var fl := MwFlatShadows.FLAT
	for x in range(2, 6):
		assert_eq(m[w + x], on, "beside the stick")
	assert_eq(m[2 * w + 6], on, "the line two pixels away")
	assert_eq(m[3 * w + 7], on, "and to its end: the patch is up in the air")
	assert_eq(m[10 * w + 0], on, "beside the blade on the ice")
	assert_eq(m[10 * w + 1], on)
	assert_eq(m[10 * w + 5], fl, "the rest of the shadow on the ice: flat")
	assert_eq(m[10 * w + 7], fl)
	assert_eq(m[9 * w + 0], 0, "the stick itself is no shadow")


func test_the_bench_area_is_outside_the_side_boards() -> void:
	assert_false(MwFlatShadows.in_bench_area(Vector3(0, 0, 0)))
	assert_false(MwFlatShadows.in_bench_area(Vector3(-185, 300, 0)), "against the boards")
	assert_false(MwFlatShadows.in_bench_area(Vector3(120, -360, 20)), "behind a net, in the air")
	for x in MwBench3D.PEN_X:
		assert_true(MwFlatShadows.in_bench_area(Vector3(x, 100, 0)), "the pens")
	for x in MwBench3D.RECESS_X:
		assert_true(MwFlatShadows.in_bench_area(Vector3(x, 12, 0)), "the recess")
	assert_true(MwFlatShadows.in_bench_area(Vector3(MwBench3D.BOX_X, 60, 0)), "the box")
	assert_true(MwFlatShadows.in_bench_area(Vector3(MwBench3D.EAST_OUT.x, MwBench3D.EAST_OUT.y, 0)), "the arch")


## The skater's 3D frame keeps its pixels and carries its flat, which covers
## every shadow pixel.
func test_a_3d_frame_carries_its_flat() -> void:
	if not need_rom():
		return
	var spr := MwSprites3D.new()
	add_child_autofree(spr)
	var f := spr.frame_texture(rom, SKATER, TEAM_A)
	var px := (f["tex"] as ImageTexture).get_image().get_data()
	assert_true(MwFlatShadows.has_shadow(px), "the frame keeps its shadow pixels (the shaders leave them out)")
	assert_not_null(f["shadow"])
	var m := (f["shadow"] as ImageTexture).get_image().get_data()
	var covered := true
	var outside := 0
	for i in px.size():
		if MwFlatShadows.is_shadow(px[i]) and m[i] == 0:
			covered = false
		if m[i] != 0 and not MwFlatShadows.is_shadow(px[i]):
			outside += 1
			if px[i] == 0:
				covered = false        # never on the ice beside the shadow
	assert_true(covered, "every shadow pixel in the flat, nothing beside it")
	assert_gt(outside, 0, "the holes its feet leave dithered over")


## 3D: a skater on the ice gets his flat on the ice (two quads: the flat
## first, then him without his shadow pixels); in the bench area, or with
## the switch off, or for the calibration camera, one quad.
func test_3d_lays_the_flat_on_the_ice_but_not_in_the_bench_area() -> void:
	if not need_rom():
		return
	var spr := MwSprites3D.new()
	add_child_autofree(spr)
	spr.reflections = false        # (its reflection in the ice: test_reflections)
	var on_ice := _item(Vector3(40, 100, 0))
	spr.show_items([on_ice])
	assert_eq(_visible(spr).size(), 2)
	var shadow := _visible(spr)[0].material_override as ShaderMaterial
	assert_eq(shadow.shader, MwSprites3D.SPRITE_SHADOW)
	assert_eq(shadow.render_priority, MwSprites3D.SHADOW_PRIORITY)
	var body := _visible(spr)[1].material_override as ShaderMaterial
	assert_true(body.get_shader_parameter("strip_shadow"), "the depth pass leaves the shadow out")
	assert_true(body.next_pass.get_shader_parameter("strip_shadow"), "the colour pass too")
	assert_true(spr.frame_texture(rom, SKATER, TEAM_A)["stick"], "the skater's stick has a shadow")
	assert_eq(body.next_pass.next_pass.shader, MwSprites3D.SPRITE_STICK, "drawn on the billboard after the colours")
	assert_eq(body.next_pass.next_pass.get_shader_parameter("shadow_mask"), shadow.get_shader_parameter("mask"))
	spr.show_items([_item(Vector3(MwBench3D.PEN_X[0], 100, 0))])
	assert_eq(_visible(spr).size(), 1, "the bench: no flat")
	var benched := _visible(spr)[0].material_override as ShaderMaterial
	assert_true(benched.get_shader_parameter("strip_shadow"), "and no shadow in the frame either")
	assert_null(benched.next_pass.next_pass, "nor on the stick")
	spr.flat_shadows = false                  # (the view's layers: MwViewLayers)
	spr.show_items([on_ice])
	assert_eq(_visible(spr).size(), 1, "off: the original's frame")
	assert_false((_visible(spr)[0].material_override as ShaderMaterial).get_shader_parameter("strip_shadow"))
	spr.flat_shadows = true
	spr.original_order = true
	spr.show_items([on_ice])
	assert_eq(_visible(spr).size(), 1, "the calibration camera: the original's frame")


## A fire's scorch mark (plan 37, owner: the players' shadow code extended
## to the fire's scorch marks): line 3's colour 11 in the fire's loop frames
## goes flat on the ice like a shadow, in its own colour; line 3's colour 11
## elsewhere stays.
func test_a_fires_scorch_lies_flat_like_a_shadow() -> void:
	if not need_rom():
		return
	var a := MwGfx.animation(rom, MwRinkUpdate.FIRE_LOOP)
	var fire: int = int(a["frames"]) + MwGfx.anim_offsets(rom, a, 0)[0]
	assert_eq(MwFlatShadows.scorch_index(fire, 0x60), MwFlatShadows.SCORCH_INDEX, "a fire on line 3")
	assert_eq(MwFlatShadows.scorch_index(fire, 0x20), -1, "not on another line")
	assert_eq(MwFlatShadows.scorch_index(MwRinkDraw.STAND_FRAME, 0x60), -1, "not another frame of line 3")
	var spr := MwSprites3D.new()
	add_child_autofree(spr)
	spr.reflections = false
	var f := spr.frame_texture(rom, fire, 0x60)
	assert_eq(int(f["scorch"]), MwFlatShadows.SCORCH_INDEX)
	assert_not_null(f["shadow"], "its scorch sorted as a flat")
	var px := (f["tex"] as ImageTexture).get_image().get_data()
	var m := (f["shadow"] as ImageTexture).get_image().get_data()
	var n := 0
	for i in px.size():
		if px[i] == MwFlatShadows.SCORCH_INDEX:
			n += 1
			assert_eq(m[i], MwFlatShadows.FLAT, "every scorch pixel in the flat")
	assert_gt(n, 40, "a ring of them")
	spr.show_items([{"frame": fire, "attr": 0x60, "depth": 0x100, "place": MwRinkDraw3D.UPRIGHT,
			"at": Vector3(104, -337, 0), "offset": Vector2i.ZERO, "order": 0, "key": "obj/0"}])
	var shown := _visible(spr)
	assert_eq(shown.size(), 2, "the flat, then the fire")
	var flat := shown[0].material_override as ShaderMaterial
	assert_eq(flat.shader, MwSprites3D.SPRITE_SHADOW)
	assert_eq(int(flat.get_shader_parameter("shade_index")), MwFlatShadows.SCORCH_INDEX, "in its own colour")
	var body := shown[1].material_override as ShaderMaterial
	assert_true(body.next_pass.get_shader_parameter("strip_shadow"))
	assert_eq(int(body.next_pass.get_shader_parameter("strip_also")), MwFlatShadows.SCORCH_INDEX,
			"left out of the standing fire")
	spr.show_items([_item(Vector3(40, 100, 0))])
	assert_eq(int((_visible(spr)[0].material_override as ShaderMaterial).get_shader_parameter("shade_index")),
			MwFlatShadows.SHADE_INDEX, "a skater's shadow in the shade colour")


func _item(at: Vector3) -> Dictionary:
	return {"frame": SKATER, "attr": TEAM_A, "depth": 0x100, "place": MwRinkDraw3D.UPRIGHT, "at": at,
			"offset": Vector2i.ZERO, "order": 0, "key": "t0.p0/body"}


func _visible(spr: MwSprites3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in spr.get_children():
		if c is MeshInstance3D and c.visible:
			out.append(c)
	return out
