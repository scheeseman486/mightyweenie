extends "res://test/rom/rom_test_base.gd"
## Plan 40 (R1): the rink's outline in one place (MwRinkShape) - its three
## curves, and the shaders' copy of the rounded one (rink3d_geom) the same.


func test_the_rom_s_boards() -> void:
	if not need_rom():
		return
	assert_eq(MwRinkShape.half_width(rom, 0), 185, "the straight boards")
	assert_eq(MwRinkShape.half_width(rom, 297), 185)
	assert_eq(MwRinkShape.half_width(rom, -297), 185)
	assert_eq(MwRinkShape.half_width(rom, 372), 0, "beyond the end boards")
	assert_eq(MwRinkShape.half_width(rom, -372), 0)
	for y in range(298, 372):
		var lo := 0x144 if y >= 324 else 0
		var far := maxi(MwGfx.s16(rom, MwSimCollide.CORNER_TOP + 2 * (y - 0x12A) + 2), 0x6C)
		assert_eq(MwRinkShape.half_width(rom, -y), far, "far row %d" % y)
		if lo != 0:
			var near := maxi(MwGfx.s16(rom, MwSimCollide.CORNER_BOTTOM + 2 * (y - 0x144) + 2), 0x6C)
			assert_eq(MwRinkShape.half_width(rom, y), near, "near row %d" % y)
	for y in range(-371, 372, 7):
		assert_gte(MwRinkShape.half_width(rom, y), 0x6C, "never below the corners' narrowest")


func test_the_rounded_boards() -> void:
	assert_almost_eq(MwRinkShape.rounded_sd(Vector2(0, 372)), 0.0, 1e-4, "the boards' line")
	assert_almost_eq(MwRinkShape.rounded_sd(Vector2(0, 0)), -185.0, 1e-4)
	assert_almost_eq(MwRinkShape.rounded_sd(Vector2(185, 0)), 0.0, 1e-4)
	assert_gt(MwRinkShape.rounded_sd(Vector2(184, 371)), 0.0, "outside the rounded corner")
	var c := MwRinkShape.BOARD - Vector2(MwRinkShape.CORNER_NEAR, MwRinkShape.CORNER_NEAR)
	assert_almost_eq(MwRinkShape.rounded_sd(c + Vector2(1, 1).normalized() * MwRinkShape.CORNER_NEAR), 0.0, 1e-3,
			"the near corner's arc")


func test_the_paint_mesh_s_boards() -> void:
	var board_layout := MwSplatterAtlas.layout()
	if board_layout.is_empty():
		pending("no paint layout")
		return
	assert_eq(MwRinkShape.mesh_half_width(0.0), float(board_layout["xlim"][372]))
	assert_eq(MwRinkShape.mesh_half_width(-372.0), float(board_layout["xlim"][0]))
	assert_eq(MwRinkShape.mesh_half_width(372.5), float(board_layout["xlim"][744]))
	assert_eq(MwRinkShape.mesh_half_width(373.0), 0.0, "beyond the ends")
	assert_eq(MwRinkShape.mesh_half_width(-373.0), 0.0)
	assert_eq(MwSplatterAtlas.on_ice(10.0, 0.0), true)
	assert_eq(MwSplatterAtlas.on_ice(0.0, 400.0), false)


func test_the_shaders_have_the_same_boards() -> void:
	var code := FileAccess.get_file_as_string("res://src/rink3d/rink3d_geom.gdshaderinc")
	assert_true(code.contains("const vec2 RINK_BOARD = vec2(%.1f, %.1f);" % [MwRinkShape.BOARD.x, MwRinkShape.BOARD.y]))
	assert_true(code.contains("const float RINK_CORNER_FAR = %.1f;" % MwRinkShape.CORNER_FAR))
	assert_true(code.contains("const float RINK_CORNER_NEAR = %.1f;" % MwRinkShape.CORNER_NEAR))
	assert_true(code.contains("const float RINK_BOARDS_TOP = %.1f;" % MwRinkShape.BOARDS_TOP))
	assert_true(FileAccess.get_file_as_string("res://src/rink3d/rink3d_common.gdshaderinc").contains(
			'#include "res://src/rink3d/rink3d_geom.gdshaderinc"'), "every rink shader has it")
	for f in ["rink3d_billboard.gdshaderinc", "rink3d_crowd.gdshader"]:
		var c := FileAccess.get_file_as_string("res://src/rink3d/" + f)
		assert_false(c.contains("vec2(185.0, 372.0)") or c.contains("? 74.0 : 48.0"), "%s: no copy of the boards" % f)


## Plan 40 (R4): the shaders' helpers once - the rink's pixel, the ray meeting
## a plane, the level basis - in rink3d_geom, no copy left.
func test_the_shaders_helpers_once() -> void:
	var geom := FileAccess.get_file_as_string("res://src/rink3d/rink3d_geom.gdshaderinc")
	assert_true(geom.contains("const float RINK_PX = %s;" % str(MwRink3D.METRES_PER_PX)), "METRES_PER_PX")
	assert_true(geom.contains("vec3 ray_plane("))
	assert_true(geom.contains("vec3 level_toward_camera("))
	var d := DirAccess.open("res://src/rink3d")
	for f in d.get_files():
		if not (f.ends_with(".gdshader") or f.ends_with(".gdshaderinc")) or f == "rink3d_geom.gdshaderinc":
			continue
		var c := FileAccess.get_file_as_string("res://src/rink3d/" + f)
		assert_false(c.contains("0.0, 0.0, dot(n, v - q)"), "%s: no ray-plane copy" % f)
		assert_false(c.contains("normalize(vec3(back.x, 0.0, back.z)"), "%s: no level-basis copy" % f)
		assert_false(c.contains(" = 0.05;"), "%s: the rink's pixel from rink3d_geom" % f)
