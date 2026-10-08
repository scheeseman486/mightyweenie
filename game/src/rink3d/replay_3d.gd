class_name MwReplay3D
extends RefCounted
## The instant replay in 3D (plan 20, docs/rink3d.md, Replays): the
## original's replay ring keeps each recorded pass as screen points only
## (and drops sprites outside the 2D window), so the 3D view keeps its own
## frame beside each one (MwRinkState.ReplayRing.side, by the frame's start
## offset, in step with the ring): the pass's placements (MwRinkDraw3D
## items), its play (MwRinkShot3D), the sim camera's point and its
## screen-space pieces. Screen 7 plays them through the same view and
## cameras as the rink. Presentation only.


## A rink pass's update ([param update]) drawing in 3D and keeping the
## replay's 3D frames: its drawer an MwRinkDraw3D (the original's sprite
## list unchanged), its replay frames' side-store [method frame].
static func use(update: MwRinkUpdate) -> void:
	if not update.drawer is MwRinkDraw3D:
		var d3 := MwRinkDraw3D.new(update.rom)
		d3.on_tick = update.drawer.on_tick
		update.drawer = d3
	update.replay_side = frame


## The 3D frame of the pass [param s] drawn with [param draw] (empty when it
## did not draw in 3D): {items, shot, shown, screen, screen_no_arrows}.
static func frame(s: MwRinkState, draw: MwRinkDraw) -> Dictionary:
	var d := draw as MwRinkDraw3D
	if d == null:
		return {}
	var shown := Vector2(s.camera.shown)
	return {"items": d.items, "shot": MwRinkShot3D.make(s, d.items, shown), "shown": shown,
			"screen": d.screen_sprites(), "screen_no_arrows": d.screen_sprites(true)}


## The 3D frame kept for the ring frame starting at [param at] (empty: none).
static func at(ring: MwRinkState.ReplayRing, offset: int) -> Dictionary:
	return ring.side.get(offset, {})
