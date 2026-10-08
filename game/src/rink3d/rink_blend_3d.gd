class_name MwRinkBlend3D
extends RefCounted
## The 3D view between passes (plan 14; owner: an unlocked frame rate that
## changes nothing in the game's behaviour or timing). The simulation keeps
## its fixed pass rate on the 60 Hz tick; the view is drawn as often as the
## display allows and shows the way from the previous pass to the latest one:
## each frame's point and the camera move by the share of the pass interval
## gone by ([param t], 0..1). The frames themselves (animation, flips,
## palette) are the latest pass's. A frame with no counterpart in the
## previous pass (same key and placement), or one that moved further than
## [constant SNAP_PX] (a faceoff reset, a line change), is shown where it is.
## Presentation only, at the cost of one pass of latency.

## A move longer than this (rink px in one pass) is a jump, not motion.
const SNAP_PX := 48.0


## [param items] (MwRinkDraw3D.items) by their keys.
static func by_key(items: Array) -> Dictionary:
	var out := {}
	for it: Dictionary in items:
		if it.has("key"):
			out[it["key"]] = it
	return out


## [param cur] with each frame's point taken back towards where it was in
## [param prev] (the previous pass's [method by_key]): there at [param t] 0,
## where it is now at 1.
static func items(prev: Dictionary, cur: Array, t: float) -> Array:
	t = clampf(t, 0.0, 1.0)
	if t >= 1.0 or prev.is_empty():
		return cur
	var out := []
	for it: Dictionary in cur:
		var was: Dictionary = prev.get(it.get("key", ""), {})
		if was.is_empty() or was["place"] != it["place"] or was.get("pin", 0) != it.get("pin", 0):
			out.append(it)
			continue
		var a: Vector3 = was["at"]
		var b: Vector3 = it["at"]
		if a.distance_to(b) > SNAP_PX:
			out.append(it)
			continue
		var moved := it.duplicate()
		moved["at"] = a.lerp(b, t)
		out.append(moved)
	return out


## The sim camera's shown point (map px) between passes; a jump snaps.
static func point(prev: Vector2, cur: Vector2, t: float) -> Vector2:
	if prev.distance_to(cur) > SNAP_PX:
		return cur
	return prev.lerp(cur, clampf(t, 0.0, 1.0))
