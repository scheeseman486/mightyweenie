class_name MwRinkFacing3D
extends RefCounted
## What each sprite shows from where the 3D camera is (plan 16): Doom's rule.
## A frame with a direction in the world (MwRinkDraw3D's [code]dir[/code]:
## players, their weapons, the shark, corpses; variant k = k x 45 deg
## clockwise from north, as the original draws them for its camera looking
## north) shows the variant for the angle between that direction and the
## line from the camera to it on the ice, per sprite and every rendered
## frame. From the original's angle (the calibration camera) that line points
## north for every sprite, so 3D shows the sim's own variants, as 2D does.
## A weapon follows its body's turned hotspot; a carried puck sits on the
## turned stick blade (hotspot 0, presentation only). A net shows its front
## (variant 1, the far net's drawing) from its mouth's side of its goal line
## and its back (variant 0) from the other.
## Presentation only: nothing here feeds the simulation.


## The direction (radians, clockwise from north) from the camera to the rink
## point [param at] (px) on the ice: per point for a perspective camera, the
## camera's heading for an orthographic one (and right above the point).
static func view_angle(cam: Camera3D, at: Vector3) -> float:
	var h := heading(cam)
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return h
	var c := MwRink3D.rink(cam.global_position if cam.is_inside_tree() else cam.position)
	var d := Vector2(at.x - c.x, at.y - c.y)
	if d.length() < 0.5:
		return h
	return atan2(d.x, -d.y)


## The camera's heading seen from above (radians clockwise from north).
static func heading(cam: Camera3D) -> float:
	var b := cam.global_transform.basis if cam.is_inside_tree() else cam.transform.basis
	var f := -b.z
	if Vector2(f.x, f.z).length() < 1e-6:     # straight down: its up says which way
		f = b.y
	return atan2(f.x, -f.z)


## The variant (0-7) a sprite facing [param variant] shows seen along
## [param angle] (view_angle).
static func shown_variant(variant: int, angle: float) -> int:
	return posmod(variant - roundi(angle / (PI / 4.0)), 8)


## Whether a net whose mouth faces [param mouth] (+1 south, -1 north) is
## seen from the front along [param angle].
static func net_front(mouth: int, angle: float) -> bool:
	return -cos(angle) * mouth < 0.0     # the line of sight's south part against the mouth


## [param items] (MwRinkDraw3D.items, between passes) as [param cam] sees
## them: turned frames, weapons and carried pucks moved with them, nets'
## views. Items are copied when changed.
static func apply(items: Array, cam: Camera3D, rom: PackedByteArray) -> Array:
	if rom.is_empty() or cam == null:
		return items
	var out := []
	var turned := {}     # body key -> [anim, variant shown, frame, at]
	for it: Dictionary in items:
		if it.has("dir") and it["place"] == MwRinkDraw3D.UPRIGHT:
			var d: Dictionary = it["dir"]
			var at: Vector3 = it["at"]
			var v := shown_variant(int(d["variant"]), view_angle(cam, at))
			var key: String = it["key"]
			if key.ends_with("/body"):
				turned[key] = [int(d["anim"]), v, int(d["aframe"]), at]
			if v != int(d["variant"]):
				var f := _frame(rom, int(d["anim"]), v, int(d["aframe"]))
				it = it.duplicate()
				it["frame"] = f.x
				it["attr"] = int(d["attr0"]) ^ (f.y << 3)
				if d.has("hot"):
					var h: Array = d["hot"]
					it["offset"] = hotspot(rom, int(h[0]), v, int(h[1]), int(h[2]))
		elif it.has("net"):
			var n: Dictionary = it["net"]
			var v := 1 if net_front(int(n["mouth"]), view_angle(cam, it["at"])) else 0
			var f := _frame(rom, int(n["anim"]), v, int(n["aframe"]))
			if f.x != int(it["frame"]):
				it = it.duplicate()
				it["frame"] = f.x
				it["attr"] = int(n["attr0"]) ^ (f.y << 3)
		elif it.has("carrier") and turned.has(it["carrier"]):
			var c: Array = turned[it["carrier"]]
			var at: Vector3 = it["at"]
			var stand: Vector3 = c[3]
			it = it.duplicate()
			it["at"] = Vector3(stand.x, stand.y, at.z)
			it["offset"] = hotspot(rom, int(c[0]), int(c[1]), int(c[2]), 0)
		out.append(it)
	return out


## The ROM address of frame [param frame] of [param variant] of animation
## [param anim], and the variant's flips (MwAnimState.frame_address).
static func _frame(rom: PackedByteArray, anim: int, variant: int, frame: int) -> Vector2i:
	var a := MwAnimState.new()
	a.address = anim
	a.variant = variant
	a.frame = frame
	return a.frame_address(rom)


## Hotspot [param n] of that frame, negated by the variant's flips
## (MwRinkDraw.hotspot).
static func hotspot(rom: PackedByteArray, anim: int, variant: int, frame: int, n: int) -> Vector2i:
	var f := _frame(rom, anim, variant, frame)
	var at := f.x + 2 + 6 * MwGfx.u16(rom, f.x) + 2 * n
	var hx := MwGfx.s8(rom, at)
	var hy := MwGfx.s8(rom, at + 1)
	return Vector2i(-hx if f.y & 1 else hx, -hy if f.y & 2 else hy)
