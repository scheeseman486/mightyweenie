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
## did not draw in 3D) - the one builder (plan 40, S3): the live view's
## (MwRinkView3D.present: [param for_replay] false) and the replay's.
## {items, shot, shown, crowd (the crowd's life, MwCrowdLife.snapshot: its
## look and noise, plan 31), bench (the benches' and boxes' figures,
## MwBenchLife.snapshot, plan 32), splat (the arena's paint and particles,
## MwSplatter.snapshot, plan 37)}: MwMatchModels.frame_parts. A replay's
## frame also: screen, screen_no_arrows, arrows (MwRinkDraw.arrow_marks:
## the arrows again for a wide picture), pieces (MwRinkDraw3D.pieces: the
## wide 2D picture's list) and in splat "in" (the paint's inputs since the
## frame before, MwSplatter.take_inputs - a replay makes the paint again
## from them and the seed, MwSplatterReplay).
static func frame(s: MwRinkState, draw: MwRinkDraw, for_replay := true) -> Dictionary:
	var drawer := draw as MwRinkDraw3D
	if drawer == null:
		return {}
	var shown := Vector2(s.camera.shown)
	var f := {"items": drawer.items, "shot": MwRinkShot3D.make(s, drawer.items, shown), "shown": shown}
	if for_replay:
		f["screen"] = drawer.screen_sprites()
		f["screen_no_arrows"] = drawer.screen_sprites(true)
		f["arrows"] = MwRinkDraw.arrow_marks(s)
		f["pieces"] = drawer.pieces
	f.merge(MwMatchModels.frame_parts(s.crowd_life, s.bench_life, s.splatter, for_replay))
	return f


## The 3D frame kept for the ring frame starting at [param offset] of [param ring] (empty: none).
static func at(ring: MwRinkState.ReplayRing, offset: int) -> Dictionary:
	return ring.side.get(offset, {})
