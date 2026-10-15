class_name MwRinkShape
extends RefCounted
## Plan 40 (R1): the rink's outline in one place - the boards (the physics
## boundary) as three named curves, each one chosen where it is used:
##
## * [method half_width], the ROM's boards, exact: the half width the sim's
##   corner tables give a row (`$1C77E` far from |y| 298, `$1C81E` near from
##   y 324; MwSimCollide.corner reads the same tables its own way, the
##   original's). The ice mask, the reflections' ice, CREATE-A-TEAM's
##   hazards, the calibration check.
## * [method rounded_sd], a rounded rectangle whose corners' radii are the
##   rows the tables cover: the crowd's duck, the stands' rows, the
##   billboards' depth and the benches' barriers (the shaders' `rink_sd` in
##   rink3d_geom.gdshaderinc, the same literals: test_rink_shape).
## * [method mesh_half_width], the paint mesh's outline (a superellipse
##   fitted to the tables in Blender, assets/rink3d/rink_paint.json,
##   [MwSplatterAtlas]): the paint, its splotches and streaks.

## The straight boards' half sizes (rink px; MwSimCollide.BOARD_X / BOARD_Y).
const BOARD := Vector2(MwSimCollide.BOARD_X, MwSimCollide.BOARD_Y)
## The rounded corners' radii: the rows the far and the near corner tables
## cover.
const CORNER_FAR := 74.0
const CORNER_NEAR := 48.0
## The boards' top: the far glass's (rink px).
const BOARDS_TOP := 48.0


## The ice's half width at rink row [param y] (the ROM's boards): points
## with |x| below it are inside the boards; 0 beyond the end boards.
static func half_width(rom: PackedByteArray, y: int) -> int:
	var ay := absi(y)
	if ay >= MwSimCollide.BOARD_Y:
		return 0
	var lo := MwSimCollide.CORNER_BOTTOM_FROM if y >= 0 else MwSimCollide.CORNER_TOP_FROM
	if ay < lo:
		return MwSimCollide.BOARD_X
	var tab := MwSimCollide.CORNER_BOTTOM if y >= 0 else MwSimCollide.CORNER_TOP
	return maxi(MwGfx.s16(rom, tab + 2 * (ay - lo) + 2), MwSimCollide.CORNER_MIN_X)


## Signed distance (rink px) from the boards' inside line, < 0 on the ice:
## the rounded rectangle ([constant BOARD]'s half sizes, corners
## [constant CORNER_FAR] north and [constant CORNER_NEAR] south).
static func rounded_sd(point: Vector2) -> float:
	var r := CORNER_FAR if point.y < 0.0 else CORNER_NEAR
	var point_2 := Vector2(absf(point.x), absf(point.y)) - (BOARD - Vector2(r, r))
	return Vector2(maxf(point_2.x, 0.0), maxf(point_2.y, 0.0)).length() + minf(maxf(point_2.x, point_2.y), 0.0) - r


## The paint mesh's boards' |x| at rink row [param y] (0 beyond the ends).
static func mesh_half_width(y: float) -> float:
	var board_layout := MwSplatterAtlas.layout()
	var row := int(floor(y)) + int(BOARD.y)
	if row < 0 or row >= 2 * int(BOARD.y) + 1:
		return 0.0
	return float(board_layout["xlim"][row])
