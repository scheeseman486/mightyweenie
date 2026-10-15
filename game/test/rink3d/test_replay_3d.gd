extends "res://test/rom/rom_test_base.gd"
## The instant replay in 3D (plan 20, MwReplay3D): a 3D frame kept beside
## every frame of the replay ring, in step with it (closed, dropped,
## abandoned, reset), outside the comparisons; screen 7 playing them
## through the 3D view with the rink's cameras, the 2D replay unchanged.
## Short names: r the MwRinkState.ReplayRing under test.

const SCRIPT := "res://scenes/instant_replay/instant_replay.gd"
const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")


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


func _scene(state: MwRinkState, view: int) -> MwBetweenPlays:
	var node: MwBetweenPlays = (load(MwScreens.scene_path(7)) as PackedScene).instantiate()
	node.screen_id = 7
	node.previous = 5
	node.session = MwSession.new(1234, 5678)
	node.session.screens["rink"] = state
	node.session.view = view
	add_child_autofree(node)
	node._enter_screen({})
	return node


static func _press(actions: Array, held_only := false) -> MwInputFrame:
	var input := MwInputFrame.new()
	for a in actions:
		input.held[a] = true
		if not held_only:
			input.pressed[a] = true
	return input


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
	var state := _recorded_state()
	var node := _scene(state, MwRinkViews.TV)
	var rs := node.sim as MwReplaySim
	var host := MwRink3DHost.of(get_tree())
	assert_true(host.shown_for(node), "the 3D view shows the replay")
	var view := host.view()
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.TV)
	var f := MwReplay3D.at(state.replay, int(rs.replay.shown["at"]))
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
	f = MwReplay3D.at(state.replay, int(rs.replay.shown["at"]))
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
	var state := _recorded_state()
	state.replay.side.clear()
	var node := _scene(state, MwRinkViews.FOLLOW)
	assert_false(MwRink3DHost.of(get_tree()).shown_for(node))
	assert_true(node.plane_b.visible, "the 2D replay")
	node.free()


## Plan 40 (S3): the shot's data is every field of it, and comes back the
## same; the live view's frame and the replay's are one builder's (the
## replay's has more, the live one never takes the paint's inputs).
func test_one_frame_builder_and_the_shots_data() -> void:
	var names := []
	for property in MwRinkShot3D.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	names.sort()
	var fields := MwRinkShot3D.FIELDS.duplicate()
	fields.sort()
	assert_eq(names, fields, "every field kept")
	if not need_rom():
		return
	var s := _recorded_state()
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(s)
	var shot := MwRinkShot3D.make(s, drawer.items, Vector2(s.camera.shown))
	assert_eq(MwRinkShot3D.from_data(shot.to_data()).to_data(), shot.to_data(), "the data comes back")
	assert_eq(MwFullReplay.side_from_data(MwFullReplay.side_to_data({"shot": shot}))["shot"].to_data(),
			shot.to_data(), "through a saved replay's side record")
	s.crowd_life = MwCrowdLife.new(3)
	s.bench_life = MwBenchLife.new(3)
	s.splatter = MwSplatter.new(3)
	var live := MwReplay3D.frame(s, drawer, false)
	var replay := MwReplay3D.frame(s, drawer)
	for k in live:
		assert_true(replay.has(k), k)
	assert_eq(live.keys(), ["items", "shot", "shown", "crowd", "bench", "splat"])
	assert_false((live["splat"] as Dictionary).has("in"), "the live frame leaves the paint's inputs")
	assert_true((replay["splat"] as Dictionary).has("in"), "the replay's takes them")
	for k in ["screen", "screen_no_arrows", "arrows", "pieces"]:
		assert_true(replay.has(k) and not live.has(k), k)


## Online, 3D EXTENDED keeps only this machine's players in the picture
## (owner, 2026-10-13): each driver's match pad is in the shot
## (driver_pads), the view narrows the drivers to its machine's
## (MwRinkShot3D.of_pads: none of them - the puck alone, no fallback to
## player 1's rider); the machine's pads from the session's online table
## (local_pads: an extended set-up's number - 1, else the pad map's pad;
## offline, null: everyone). A frame from before driver_pads keeps its
## drivers.
func test_extended_frames_this_machines_players_online() -> void:
	if not need_rom():
		return
	var s := _recorded_state()
	s.extended = true
	for team: MwRinkState.Team in s.teams:
		for p: MwRinkState.Player in team.players:
			p.flags &= ~MwRinkState.Player.HUMAN      # (the recording's own driver let go)
	var drive := {0: [1, 0], 1: [3, 5]}           # team -> [slot, match pad]: players 1 and 6
	for t: int in drive:
		var p: MwRinkState.Player = s.teams[t].players[int(drive[t][0])]
		p.flags |= MwRinkState.Player.HUMAN
		p.pad = int(drive[t][1])
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(s)
	var shot := MwRinkShot3D.make(s, drawer.items, Vector2(s.camera.shown))
	assert_eq(shot.drivers.size(), 2, "two characters driven")
	assert_eq(shot.driver_pads, PackedInt32Array([0, 5]), "their match pads, in the drivers' order")
	assert_eq(shot.targets().size(), 3, "everyone's: the puck and both")
	var mine := shot.of_pads(PackedInt32Array([5]))
	assert_eq(mine.driver_pads, PackedInt32Array([5]))
	assert_eq(mine.targets(), PackedVector3Array([shot.targets()[0], shot.drivers[1]]), "the puck and ours")
	var none := shot.of_pads(PackedInt32Array())
	assert_eq(none.targets(), PackedVector3Array([shot.targets()[0]]), "nobody of ours driving: the puck alone")
	var old := MwRinkShot3D.from_data(shot.to_data())
	old.driver_pads = PackedInt32Array()
	assert_eq(old.of_pads(PackedInt32Array([5])).drivers.size(), 2, "a frame from before: its drivers kept")
	# this machine's pads from the session
	var session := MwSession.new(1, 1)
	assert_null(MwRinkShot3D.local_pads(session, true), "offline: everyone")
	for n in [1, 2, 3, 6]:
		session.humans.set_team(n, n % 2)
	session.online = {"players": [1, 2, 3, 6], "machines": {"1": 0, "2": 1, "3": 1, "6": 2}}
	session.machine = 1
	assert_eq(MwRinkShot3D.local_pads(session, true), PackedInt32Array([1, 2]), "an extended set-up: players 2 and 3")
	session.pad_map = PackedInt32Array([1, 3, 2, 6])
	assert_eq(MwRinkShot3D.local_pads(session, false), PackedInt32Array([1, 2]), "the original's: their pads")
	session.machine = 2
	assert_eq(MwRinkShot3D.local_pads(session, true), PackedInt32Array([5]), "player 6's machine")


## REPLAY BLOOD off (MwSettings.replay_paint, the default; owner, 2026-10-15):
## the ring's frames show without the arena's paint, the ring's own kept as
## recorded; on, with it.
func test_replay_blood_off_the_ring_s_frames_show_no_paint() -> void:
	if not need_rom():
		return
	var state := _recorded_state()
	var replay := MwInstantReplay.new(state, rom)
	replay.start(0)
	var at := int(replay.shown["at"])
	var stored := MwReplay3D.at(state.replay, at)
	assert_false(stored.is_empty())
	stored["splat"] = {"ops": 3, "parts": []}          # (as a match painting records it)
	var was := MwSettings.replay_paint
	MwSettings.replay_paint = false
	var f := replay.frame_3d()
	assert_false(f.has("splat"), "off: no paint shown")
	assert_same(f["items"], stored["items"], "the rest as recorded")
	assert_true(MwReplay3D.at(state.replay, at).has("splat"), "the ring's frame kept as recorded")
	MwSettings.replay_paint = true
	assert_true(replay.frame_3d().has("splat"), "on: shown")
	MwSettings.replay_paint = was


## The 3D view with auto_blend (the game's screens: fix 2026-10-15, "Replays
## are still extremely juddery and slow ... when rewinding"): a frame
## presented shows at the next rendered frame's blend, not at once - only
## that one is seen, however many passes ran before it; without auto_blend
## (the proof scene, the tests) at once.
func test_a_frame_presented_shows_at_the_rendered_frame_s_blend() -> void:
	if not need_rom():
		return
	var state := _recorded_state()
	var replay := MwInstantReplay.new(state, rom)
	replay.start(0)
	var f := replay.frame_3d()
	var view := VIEW.instantiate() as MwRinkView3D
	add_child_autofree(view)
	view.present_frame(f, {}, false)
	var all := view.sprites._shown
	assert_gt(all, 10, "shown at once")
	view.pass_shown(2)
	var fewer := f.duplicate()
	fewer["items"] = (f["items"] as Array).filter(func(it: Dictionary) -> bool:
			return int(it["place"]) == MwRinkDraw3D.SCREEN)
	view.present_frame(fewer, {}, false)
	assert_same(view._items, fewer["items"], "taken")
	assert_eq(view.sprites._shown, all, "auto_blend: not shown yet")
	view.blend_to(1.0)
	assert_lt(view.sprites._shown, all, "shown at the rendered frame's blend")
