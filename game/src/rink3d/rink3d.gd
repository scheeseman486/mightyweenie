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
## the rink picture (plane B), the side boards with signs, the referee side.
const PICTURE_RINK := 0x24CFC
const PICTURE_SIGNS := 0x4A066
const PICTURE_FENCE := 0x3C264


## Godot position (metres) of a rink point (px).
static func world(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, y) * METRES_PER_PX


## Rink point (px) of a Godot position.
static func rink(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, p.y) / METRES_PER_PX


## The map point (the original's projection) of a rink point.
static func map_point(x: float, y: float, z: float) -> Vector2:
	return Vector2(x + MAP_ORIGIN.x, y + MAP_ORIGIN.y - z)


## The rink point on the ice under a map point (z = 0).
static func ice_under_map(m: Vector2) -> Vector3:
	return Vector3(m.x - MAP_ORIGIN.x, m.y - MAP_ORIGIN.y, 0)
