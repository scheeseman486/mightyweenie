extends "res://test/rom/rom_test_base.gd"
## The instant replay in 3D (plan 20, MwReplay3D): a 3D frame kept beside
## every frame of the replay ring, in step with it (closed, dropped,
## abandoned, reset), outside the comparisons; screen 7 playing them
## through the 3D view with the rink's cameras, the 2D replay unchanged.

const SCRIPT := "res://scenes/instant_replay/instant_replay.gd"


func _recorded_state() -> MwRinkState:
	var s := MwRinkState.new()
	MwRinkMatch.start(MwRinkSim.new(rom, s), 0, 0, 5, 0, false, 2)
	s.period = 1
	s.clock = 180
	return load(SCRIPT).demo_replay_state(rom, s)


## The ring's frames' start offsets, oldest first.
static func _frame_starts(r: MwRinkState.ReplayRing) -> Array:
	var out := []
	var at := r.read
	for i in r.frames:
		out.append(at)
		var h := (r.ring_bytes[at] << 8) | r.ring_bytes[(at + 1) % MwRinkState.ReplayRing.SIZE]
		at = (at + ((h & 0xFFF0) >> 3) + 2) % MwRinkState.ReplayRing.SIZE
	return out


func _scene(st: MwRinkState, view: int) -> MwBetweenPlays:
	var node: MwBetweenPlays = (load(MwScreens.scene_path(7)) as PackedScene).instantiate()
	node.screen_id = 7
	node.previous = 5
	node.session = MwSession.new(1234, 5678)
	node.session.screens["rink"] = st
	node.session.view = view
	add_child_autofree(node)
	node._enter_screen({})
	return node


static func _press(actions: Array, held_only := false) -> MwInputFrame:
	var f := MwInputFrame.new()
	for a in actions:
		f.held[a] = true
		if not held_only:
			f.pressed[a] = true
	return f


func test_a_3d_frame_beside_every_ring_frame() -> void:
	if not need_rom():
		return
	var s := _recorded_state()
	var r := s.replay
	assert_gt(r.frames, 20, "the demo filled the ring")
	var starts := _frame_starts(r)
	for at: int in starts:
		var f := MwReplay3D.at(r, at)
		assert_false(f.is_empty(), "a 3D frame at %d" % at)
		if f.is_empty():
			break
		assert_gt((f["items"] as Array).size(), 10, "the pass's placements")
		assert_true(f["shot"] is MwRinkShot3D)
		assert_true(f.has("screen") and f.has("screen_no_arrows"))
	assert_eq(r.side.size(), starts.size(), "nothing kept for frames gone")
	assert_false(MwSimDict.to_dict(s).get("replay", {}).has("side"), "outside the comparisons")


func test_the_side_store_follows_the_ring() -> void:
	var r := MwRinkState.ReplayRing.new()
	r.reset()
	r.open_frame(2)
	r.put_word(0x1234)
	r.side[r.frame_start] = {"n": 0}
	r.close_frame()
	var first := 0
	assert_eq(r.side.keys(), [first])
	r.open_frame(2)
	var open_at := r.frame_start
	r.side[open_at] = {"n": 1}
	r.abandon_frame()
	assert_false(r.side.has(open_at), "an abandoned frame's goes with it")
	# fill the ring: the oldest frames are dropped with theirs
	var n := 1
	while r.frames < 3 or r.side.has(first):
		r.open_frame(2)
		r.side[r.frame_start] = {"n": n}
		for i in 500:
			r.put_word(i)
		r.close_frame()
		n += 1
		if n > 200:
			break
	assert_false(r.side.has(first), "the oldest frame dropped with its 3D frame")
	assert_eq(r.side.size(), r.frames, "one per frame held")
	var starts := _frame_starts(r)
	for k: int in r.side:
		assert_true(k in starts, "kept for a frame the ring holds (%d)" % k)
	r.reset()
	assert_true(r.side.is_empty(), "a reset clears it")


func test_the_replay_plays_in_3d() -> void:
	if not need_rom():
		return
	var st := _recorded_state()
	var node := _scene(st, MwRinkViews.TV)
	var rs := node.sim as MwReplaySim
	var host := MwRink3DHost.of(get_tree())
	assert_true(host.shown_for(node), "the 3D view shows the replay")
	var view := host.view()
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.TV)
	var f := MwReplay3D.at(st.replay, int(rs.replay.shown["at"]))
	assert_same(view._items, f["items"], "the oldest frame's placements")
	assert_false(node.plane_b.visible, "no 2D rink")
	assert_false(node.plane_b.high_cells.visible)
	assert_true(node.window.visible, "the widget stays")
	# play: each frame drawn is presented, blending from the one before
	node._screen_pass(1, _press(["p1_replay_play"]))
	var drawn := rs.replay.drawn
	for i in 60:
		node._screen_pass(1, MwInputFrame.new())
	assert_gt(rs.replay.drawn, drawn, "frames played")
	f = MwReplay3D.at(st.replay, int(rs.replay.shown["at"]))
	assert_same(view._items, f["items"], "the frame drawn last")
	assert_false(view._prev.is_empty(), "blending from the frame before")
	var before := rs.replay.drawn
	for i in 30:
		node._screen_pass(1, MwInputFrame.new())
		if rs.replay.drawn != before:
			break
	assert_eq(view.pass_ticks, maxi(rs.replay.wait, 1), "a frame just drawn blends in over the time to the next")
	assert_true(view.auto_blend)
	# F1: the 2D replay, as it was
	MwRinkViews.select(node.session, MwRinkViews.FLAT)
	node._present(false)
	assert_false(host.shown_for(node))
	assert_true(node.plane_b.visible)
	assert_gt(node.sprites_low.get_children().filter(func(c): return c.visible).size()
			+ node.sprites_high.get_children().filter(func(c): return c.visible).size(), 0, "the frame's sprites")
	node._screen_pass(1, _press(["p1_replay_exit"]))
	node.free()
	assert_false(host.visible, "released as it leaves")


func test_a_frame_without_its_3d_frame_shows_in_2d() -> void:
	if not need_rom():
		return
	var st := _recorded_state()
	st.replay.side.clear()
	var node := _scene(st, MwRinkViews.FOLLOW)
	assert_false(MwRink3DHost.of(get_tree()).shown_for(node))
	assert_true(node.plane_b.visible, "the 2D replay")
	node.free()
