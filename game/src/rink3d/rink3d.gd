class_name MwRink3D
extends RefCounted
## Shared numbers and conversions of the 3D rink view (plan 14,
## docs/rink3d.md). Presentation only: nothing here feeds the simulation.
##
## Rink coordinates are the simulation's: x right, y down the screen (south,
## towards the viewer), z up, in px. Godot's: X = x, Y = z (up), Z = y, in
## metres, 1 px = [constant METRES_PER_PX].

## 1 rink px in metres (rink 18.5 x 37.2 m, far boards 2.4 m).
const METRES_PER_PX := 0.05

## The original's projection (`$5AC2`): map = (x + 256, y + 461 - z).
const MAP_ORIGIN := Vector2i(0x100, 0x1CD)
## The 2D screen (and the 3D view's viewport) in px.
const SCREEN := Vector2i(320, 224)

## ROM pictures the rink model is textured from (UV0 = their pixels / size):
## the rink picture (plane B), the side boards with signs, the penalty-box side.
const PICTURE_RINK := 0x24CFC
const PICTURE_SIGNS := 0x4A066
const PICTURE_FENCE := 0x3C264

## The ice as a mirror (plan 37, owner: on-ice sprites reflected at 25 % at
## their base, fading to 0 over 12 px, the rink's geometry the same; then
## both doubled: 50 % over 24): pixel row n above the ice (0 = the row
## standing on it) reflected at [constant REFLECT_ALPHA] * (1 - n /
## [constant REFLECT_FADE]), none from row [constant REFLECT_FADE] up
## (rink3d_reflect.gdshaderinc, [method reflect_alpha]).
const REFLECT_ALPHA := 0.5
const REFLECT_FADE := 24


## How opaque the reflection of pixel row [param n] above the ice is (0 =
## the row standing on it; none below the ice or from [constant
## REFLECT_FADE] up) - the shaders' rule (rink3d_reflect.gdshaderinc).
static func reflect_alpha(n: float) -> float:
	if n < 0.0 or n >= REFLECT_FADE:
		return 0.0
	return REFLECT_ALPHA * (1.0 - n / REFLECT_FADE)


## Godot position (metres) of a rink point (px).
static func world(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, y) * METRES_PER_PX


## Rink point (px) of a Godot position.
static func rink(point: Vector3) -> Vector3:
	return Vector3(point.x, point.z, point.y) / METRES_PER_PX


## The map point (the original's projection) of a rink point.
static func map_point(x: float, y: float, z: float) -> Vector2:
	return Vector2(x + MAP_ORIGIN.x, y + MAP_ORIGIN.y - z)


## The rink point on the ice under a map point (z = 0).
static func ice_under_map(m: Vector2) -> Vector3:
	return Vector3(m.x - MAP_ORIGIN.x, m.y - MAP_ORIGIN.y, 0)
