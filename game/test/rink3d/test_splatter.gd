extends "res://test/rom/rom_test_base.gd"
## The arena's paint (plan 37, MwSplatter): hits throw particles that paint
## the ice or the boards, deaths burst and leave a growing pool under the
## corpse, skates carry paint out of a patch, robots leave oil, skeletons
## nothing; repeatable from the seed, never touching the game.

var sim: MwRinkSim
var update: MwRinkUpdate
var phases: MwRinkPhases


## The match and its passes (plan 40: test/support/rink_rig.gd).
const RinkRig := preload("res://test/support/rink_rig.gd")

var rig: RinkRig


## A match (stadium 3) between teams [param a] and [param b] (1: robots, 18:
## trolls, 11: skeletons), in play.
func _match(a := 18, b := 1, seed_ := 5) -> MwRinkState:
	rig = RinkRig.new()
	var s := rig.make(rom, 3, a, b, 7, false, null, true)
	sim = rig.sim
	update = rig.update
	phases = rig.phases
	s.crowd_life = MwCrowdLife.new(seed_)
	s.splatter = MwSplatter.new(seed_)
	phases.enter(5)
	for i in 400:
		if s.phase == MwRinkState.PHASE_PLAY:
			break
		_run(1)
	return s


func _run(passes: int) -> void:
	rig.run(passes)                       # (the draw steps the paint: MwRinkUpdate.crowd_sound)


func _skater(s: MwRinkState, t: int) -> MwRinkState.Player:
	for p in s.teams[t].players:
		if p.present and not p.is_goalie():
			return p
	return null


## Painted ice texels within [param r] of [param c].
func _near(at: MwSplatterAtlas, c: Vector2, r: float) -> int:
	var cells := MwSplatterAtlas.ice_cells(c - Vector2(r, r), c + Vector2(r, r))
	var n := 0
	for i in (cells[0] as PackedInt32Array).size():
		if at.data[cells[0][i]] & MwSplatterAtlas.PAINT_BITS != 0 and (cells[1][i] as Vector2).distance_to(c) <= r:
			n += 1
	return n


## Texels with paint ([param kind], or any) - the ice's detail aside.
func _painted(at: MwSplatterAtlas, kind := -1) -> int:
	var n := 0
	for v in at.data:
		var k := v & MwSplatterAtlas.PAINT_BITS
		if k != 0 and (kind < 0 or k == kind):
			n += 1
	return n


## Texels with the ice's detail [param d].
func _detail(at: MwSplatterAtlas, d: int) -> int:
	var n := 0
	for v in at.data:
		if (v >> 2) & 3 == d:
			n += 1
	return n


func test_a_hit_paints_where_its_particles_land() -> void:
	if not need_rom():
		return
	var s := _match()
	var p := _skater(s, 0)
	_run(2)
	assert_eq(_painted(s.splatter.atlas), 0, "no paint in quiet play")
	sim.players.damage(p, 0x158000)
	_run(1)
	assert_gt((s.splatter.snapshot()["parts"] as Array).size(), 0, "particles in flight")
	var items := MwSplatter.items(s.splatter.snapshot())
	assert_eq(int(items[0]["place"]), MwRinkDraw3D.UPRIGHT)
	_run(60)
	assert_eq((s.splatter.snapshot()["parts"] as Array).size(), 0, "all landed")
	assert_gt(s.splatter.atlas.count(), 0, "painted")
	assert_gt(_painted(s.splatter.atlas, MwSplatterAtlas.BLOOD), 30, "a troll's blood")
	for it: Dictionary in items:
		assert_false(it.has("darker"), "blood in flight in the art's own colours")


func test_robots_leave_oil_skeletons_nothing() -> void:
	if not need_rom():
		return
	var s := _match(18, 1)
	sim.players.damage(_skater(s, 1), 0x158000)
	_run(1)
	var items := MwSplatter.items(s.splatter.snapshot())
	assert_gt(items.size(), 0, "oil in flight")
	for it: Dictionary in items:
		assert_eq(int(it.get("darker", 0)), MwSplatter.OIL_DARKER, "a shade darker in flight (owner)")
	_run(59)
	assert_gt(_painted(s.splatter.atlas, MwSplatterAtlas.OIL), 30, "a robot's oil")
	assert_eq(_painted(s.splatter.atlas, MwSplatterAtlas.BLOOD), 0)
	s = _match(11, 11)
	sim.players.damage(_skater(s, 0), 0x158000)
	_run(60)
	assert_eq(_painted(s.splatter.atlas), 0, "skeletons don't bleed (as the original)")


func test_a_death_bursts_and_a_pool_grows_under_the_corpse() -> void:
	if not need_rom():
		return
	var s := _match()
	var p := _skater(s, 0)
	sim.players.damage(p, 0x7FFFFFFF)
	_run(1)
	assert_gt(_painted(s.splatter.atlas), 1000, "a 1:1 splat under him at once")
	var corpse: MwRinkState.RinkObject = null
	for i in 200:
		_run(1)
		for rink_object in s.objects:
			if rink_object.kind == MwRinkState.KIND_CORPSE:
				corpse = rink_object
		if corpse != null:
			break
	assert_not_null(corpse, "the corpse")
	var before := _painted(s.splatter.atlas)
	_run(200)
	var grown := _painted(s.splatter.atlas)
	assert_gt(grown, before, "the pool grew")
	var c := Vector2(corpse.motion.pos[0] / 256.0, corpse.motion.pos[1] / 256.0)
	var near := _near(s.splatter.atlas, c, MwSplatter.POOL_MAX * 1.3)
	_run(150)
	assert_eq(_near(s.splatter.atlas, c, MwSplatter.POOL_MAX * 1.3), near, "and stopped at its size")
	assert_eq(s.splatter.atlas.data[MwSplatterAtlas.ice_texel(c.x + 0.5, c.y + 0.5)] & MwSplatterAtlas.PAINT_BITS,
			MwSplatterAtlas.BLOOD, "under the corpse")


func test_skates_carry_paint_out_of_a_pool() -> void:
	if not need_rom():
		return
	var s := _match()
	var p := _skater(s, 0)
	_run(1)
	var at := Vector2(p.motion.pos[0] / 256.0, p.motion.pos[1] / 256.0)
	s.splatter.atlas.pool(MwSplatterAtlas.BLOOD, at.x, at.y, 6, 1)
	var before := _painted(s.splatter.atlas)
	# skate him east out of it: 3 px a pass, facing east
	for i in 20:
		p.angle = 0
		p.motion.pos[0] += 3 * 256
		s.splatter.step(2, sim)
	assert_gt(_painted(s.splatter.atlas) - before, 30, "two feet's tracks out of the pool")


## The ice's detail (owner: the arena's ice splattered beforehand with dark
## and light splotches, from a random seed kept for replays): from the seed,
## the same for the same seed, different for another, over a good part of
## the ice, the first operations (so replays have it).
func test_the_ice_is_splotched_from_the_seed() -> void:
	if not need_rom():
		return
	var first := MwSplatter.new(11)
	var again := MwSplatter.new(11)
	var splatter := MwSplatter.new(12)
	assert_eq(first.atlas.digest(), again.atlas.digest(), "the same seed, the same ice")
	assert_ne(first.atlas.digest(), splatter.atlas.digest(), "another seed, another")
	assert_eq(first.atlas.count(), MwSplatter.SPLOTCHES, "laid as operations")
	var dark := _detail(first.atlas, MwSplatterAtlas.DARK)
	var light := _detail(first.atlas, MwSplatterAtlas.LIGHT)
	gut.p("dark %d, light %d texels" % [dark, light])
	assert_gt(dark, 25000, "a good part of the ice (~270 000 texels)")
	assert_gt(light, 25000)
	assert_eq(_painted(first.atlas), 0, "no paint")


## Skates scratch the ice light, mostly in turns (owner).
func test_skates_scratch_mostly_in_turns() -> void:
	if not need_rom():
		return
	var s := _match()
	var p := _skater(s, 0)
	_run(1)
	var before := _detail(s.splatter.atlas, MwSplatterAtlas.LIGHT)
	for i in 20:                           # straight east, 3 px a pass
		p.angle = 0
		p.motion.pos[0] += 3 * 256
		s.splatter.step(2, sim)
	var straight := _detail(s.splatter.atlas, MwSplatterAtlas.LIGHT) - before
	before = _detail(s.splatter.atlas, MwSplatterAtlas.LIGHT)
	var a := 0.0
	for i in 20:                           # a tight turn, 3 px a pass
		a += 0.5
		p.angle = int(a * 256.0 / TAU) & 0xFF
		p.motion.pos[0] += int(cos(a) * 3 * 256)
		p.motion.pos[1] += int(sin(a) * 3 * 256)
		s.splatter.step(2, sim)
	var turning := _detail(s.splatter.atlas, MwSplatterAtlas.LIGHT) - before
	gut.p("straight %d, turning %d" % [straight, turning])
	assert_gt(turning, straight * 3, "mostly in turns")


func test_repeatable_from_the_seed() -> void:
	if not need_rom():
		return
	var digests := []
	for k in 2:
		var s := _match(18, 1, 9)
		sim.players.damage(_skater(s, 0), 0x158000)
		sim.players.damage(_skater(s, 1), 0x158000)
		_run(80)
		digests.append(s.splatter.atlas.digest())
	assert_eq(digests[0], digests[1], "the same paint")


func test_switch_off_no_model() -> void:
	MwSettings.splatter = false
	assert_false(MwSettings.splatter)
	MwSettings.splatter = true


const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")


## The replay keeps the paint as it was (its operations' count) and the
## particles; the view shows the paint on the model and the particles as
## standing frames, neither from the original's angle (the calibration camera).
func test_the_view_and_the_replay() -> void:
	if not need_rom():
		return
	var s := _match()
	sim.players.damage(_skater(s, 0), 0x158000)
	_run(2)
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(s)
	var early := MwReplay3D.frame(s, drawer)
	assert_true(early.has("splat"), "the replay frame keeps it")
	var parts: int = (early["splat"]["parts"] as Array).size()
	assert_gt(parts, 0)
	_run(60)
	var late_ops := s.splatter.atlas.count()
	assert_gt(late_ops, int(early["splat"]["ops"]), "painted since")
	var late_digest := s.splatter.atlas.digest()
	var view := VIEW.instantiate() as MwRinkView3D
	add_child_autofree(view)
	var mirror := MwSettings.reflections
	MwSettings.reflections = false      # (counting the quads: no reflections, test_reflections)
	drawer.build(s)
	view.present(s, drawer, {})
	var floor_m := view.model._materials["floor"] as ShaderMaterial
	assert_true(bool(floor_m.get_shader_parameter("paint_on")), "the paint on the ice")
	assert_almost_eq(float(floor_m.get_shader_parameter("paint_marks_alpha")), 0.75, 1e-6,
			"75 % over the ice's markings (owner)")
	assert_eq(floor_m.get_shader_parameter("paint"), s.splatter.atlas.texture())
	# the early frame: fewer operations shown, its particles drawn
	var without := early.duplicate()
	without.erase("splat")
	view.present_frame(without, {}, false)
	var plain := view.sprites._shown
	view.present_frame(early, {}, false)
	assert_eq(s.splatter.atlas._applied, int(early["splat"]["ops"]), "the paint as it was")
	assert_eq(view.sprites._shown, plain + parts, "its particles")
	view.set_camera_mode(MwRinkCamera3D.Mode.CALIBRATION)
	view.blend_to(1.0)
	assert_false(bool(floor_m.get_shader_parameter("paint_on")), "not from the original's angle")
	# back to live: the latest paint again
	view.set_camera_mode(MwRinkCamera3D.Mode.FOLLOW)
	drawer.build(s)
	view.present(s, drawer, {})
	assert_eq(s.splatter.atlas.digest(), late_digest, "live again")
	assert_true(bool(floor_m.get_shader_parameter("paint_on")))
	MwSettings.reflections = mirror


## The oil in flight a shade darker (owner): the sprites' instance carries
## the levels, which darker_by takes off each channel as RomPalette.darker.
func test_oil_in_flight_is_drawn_a_shade_darker() -> void:
	if not need_rom():
		return
	var sp := MwSprites3D.new()
	add_child_autofree(sp)
	sp.reflections = false          # (its reflection: test_reflections)
	sp.palette = RomPalette.make(4, PackedStringArray(["screen_palette"]), 18, 3)
	var it := {"frame": MwSplatter.new(1)._frames_of(MwSplatter.DROPS_OIL)[0], "attr": 0x20, "depth": 0,
			"place": MwRinkDraw3D.UPRIGHT, "at": Vector3(0, 40, 20), "offset": Vector2i.ZERO, "order": 0,
			"key": "splat/1", "darker": MwSplatter.OIL_DARKER}
	sp.show_items([it])
	var shown: Array = sp.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and n.visible)
	assert_eq(shown.size(), 1)
	assert_eq(float((shown[0] as MeshInstance3D).get_instance_shader_parameter("darker")), 1.0)
	assert_eq(RomPalette.darker(0x888, MwSplatter.OIL_DARKER), 0x666, "$888 -> $666")


## The splats cut straight (owner: a flat side goes against the ice's rim,
## or else where the arena's outside hides it entirely): the geyser's wall
## frames are cut at the bottom, nothing else is; every splotch of theirs
## has its cut on the rim or beyond it, never on the ice.
func test_straight_cut_splotches_lie_against_the_rim() -> void:
	if not need_rom():
		return
	var sp := MwSplatter.new(9)
	var geyser := sp._frames_of(MwSplatter.GEYSER)
	for i in geyser.size():
		var cut := MwSplatterAtlas.cut_side(geyser[i])
		if i in [0, 4, 5]:
			assert_eq(int(cut[0]) if not cut.is_empty() else -1, MwSplatterAtlas.CUT_BOTTOM,
					"geyser %d: cut at the bottom" % i)
		else:
			assert_true(cut.is_empty(), "geyser %d: no cut" % i)
	for anim in [MwSplatter.SPRAY, MwSplatter.DROPS]:
		for f in sp._frames_of(anim):
			assert_true(MwSplatterAtlas.cut_side(f).is_empty(), "%x: no cut (the drops' pool is round)" % anim)
	var at := sp.atlas
	var placed := 0
	for k in at._starts.size():
		var o: int = at._starts[k]
		if int(at._log[o]) != MwSplatterAtlas.OP_ICE:
			continue
		var frame := int(at._log[o + 2])
		var cut := MwSplatterAtlas.cut_side(frame)
		if cut.is_empty():
			continue
		placed += 1
		var m := MwSplatterAtlas.mask(frame)
		var c := Vector2(at._log[o + 3], at._log[o + 4])
		var up := Vector2(cos(at._log[o + 5]), sin(at._log[o + 5]))
		var right := Vector2(-up.y, up.x)
		var sc: float = at._log[o + 6]
		var fs := -1.0 if at._log[o + 7] > 0.5 else 1.0
		var mid: Vector2 = cut[1]
		var half: float = cut[2]
		var worst := -INF
		for t in range(-int(half), int(half) + 1):
			var edge := Vector2(mid.x + t, mid.y)        # (cut at the bottom: along x)
			var point := c + right * (edge.x - float(m["ox"])) * fs * sc - up * (edge.y - float(m["oy"])) * sc
			var d := MwSplatterAtlas.wall_s(point).y     # > 0 outside the boards
			worst = maxf(worst, -d)
		assert_lt(worst, 0.6, "the cut never on the ice (op %d: %.2f px in)" % [k, worst])
	assert_gt(placed, 10, "some splotches of the cut frames, along the rim")


## The puck drags paint out of a patch along its way (owner: oil and
## blood, but no ice trails): no scratches; nothing while it flies.
func test_the_puck_drags_paint_but_leaves_no_scratches() -> void:
	if not need_rom():
		return
	var s := _match()
	_run(1)
	var pk := s.puck
	pk.flags &= ~MwRinkState.Puck.HIDDEN
	pk.motion.pos[0] = -120 * 256
	pk.motion.pos[1] = 150 * 256
	pk.motion.pos[2] = 0
	s.splatter.step(2, sim)
	s.splatter.atlas.pool(MwSplatterAtlas.OIL, -120, 150, 6, 1)
	var before := _painted(s.splatter.atlas)
	var light := _detail(s.splatter.atlas, MwSplatterAtlas.LIGHT)
	for i in 20:                           # east, 4 px a pass
		pk.motion.pos[0] += 4 * 256
		s.splatter.step(2, sim)
	var dragged := _painted(s.splatter.atlas, MwSplatterAtlas.OIL) - before
	gut.p("dragged %d texels" % dragged)
	assert_gt(dragged, 15, "a line of oil out of the pool")
	assert_eq(_detail(s.splatter.atlas, MwSplatterAtlas.LIGHT), light, "no ice trails")
	# lifted: nothing
	s.splatter.atlas.pool(MwSplatterAtlas.BLOOD, -40, 200, 6, 1)
	pk.motion.pos[0] = -40 * 256
	pk.motion.pos[1] = 200 * 256
	s.splatter.step(2, sim)
	pk.motion.pos[2] = 6 * 256
	before = _painted(s.splatter.atlas)
	for i in 10:
		pk.motion.pos[0] += 4 * 256
		s.splatter.step(2, sim)
	assert_eq(_painted(s.splatter.atlas), before, "in the air: nothing")


## Replays (owner: made again procedurally from a seed): the passes' inputs
## taken as the replay frames take them, applied to a new model from the
## same seed, paint the same texels with the same operations and the same
## particles - at every frame, hits, a death, its pool, the streaks and
## scratches included.
func test_the_paint_made_again_from_the_seed_and_its_inputs() -> void:
	if not need_rom():
		return
	var s := _match(18, 1, 21)
	var again := MwSplatter.new(21)
	var frames := 0
	for k in 160:
		if k == 4:
			sim.players.damage(_skater(s, 0), 0x158000)
		if k == 30:
			sim.players.damage(_skater(s, 1), 0x158000)
		if k == 50:
			sim.players.damage(_skater(s, 0), 0x7FFFFFFF)
		_run(1)
		if k % 7 != 3:
			continue                       # (a frame now and then: the inputs pile up between)
		for rec in s.splatter.take_inputs():
			again.apply(rec)
		frames += 1
		assert_eq(again.atlas.count(), s.splatter.atlas.count(), "frame %d: the same operations" % frames)
		assert_eq(again.snapshot()["parts"], s.splatter.snapshot()["parts"], "frame %d: the same particles" % frames)
	for rec in s.splatter.take_inputs():
		again.apply(rec)                   # (the passes since the last frame)
	assert_gt(_painted(s.splatter.atlas), 1000, "painted")
	assert_eq(again.atlas.digest(), s.splatter.atlas.digest(), "the same texels")
	assert_eq(s.splatter.take_inputs().size(), 0, "taken")


## A recording's paint made on a worker thread (owner, 2026-10-15: replays
## still juddered and ran slow; the playbacks', MwSplatterReplay.of): at
## every frame the operations made here, the same texels forward and back
## (from the checkpoints it handed over); a frame shown before it got there
## has its own once made; stopped at once, it keeps what it made, and a frame
## past that shows the paint as far as it got.
func test_a_recording_s_paint_made_on_a_worker_thread() -> void:
	if not need_rom():
		return
	var s := _match(18, 1, 33)
	var drawer := MwRinkDraw3D.new(rom)
	var recorded := MwFullReplay.new()
	for k in 150:
		if k == 5:
			sim.players.damage(_skater(s, 0), 0x158000)
		if k == 40:
			sim.players.damage(_skater(s, 1), 0x7FFFFFFF)
		_run(1)
		if k % 3 == 2:
			drawer.build(s)
			recorded.add_frame(PackedByteArray([k & 0xFF, 2]), MwReplay3D.frame(s, drawer))
	recorded.seal()
	var store := MwFullReplay.from_data(bytes_to_var(var_to_bytes(recorded.to_data())))
	assert_eq(store.splat_seed, 33, "the seed recorded")
	var here := MwSplatterReplay.new(store)
	var there := MwSplatterReplay.new(store, null, true)
	assert_null(there.splat, "not made on this thread")
	var n := store.size()
	var last := there.dress(store.side(n - 1), n - 1)       # (likely before it got there)
	assert_lte(int(last["splat"]["ops"]), here.ops_at(n - 1), "as far as made")
	there.finish()
	assert_false(there.making(), "made")
	assert_eq(int((last["splat"]["ops_made"] as Callable).call()), here.ops_at(n - 1),
			"the frame shown: its own once made (the view asks each rendered frame)")
	assert_eq(there.made(), n, "every frame")
	for i in n:
		assert_eq(there.ops_at(i), here.ops_at(i), "frame %d: the same operations" % i)
	var a := there.atlas()
	assert_true(a.follows, "the frames' own atlas, fed by it")
	for i: int in [n - 1, n / 2, 3, n - 1]:
		a.seek(there.ops_at(i))
		here.atlas().seek(here.ops_at(i))
		assert_eq(a.digest(), here.atlas().digest(), "frame %d: the same texels" % i)
	assert_gt(_painted(a), 100, "blood painted")
	var stopped := MwSplatterReplay.new(store, null, true)
	stopped.stop()
	assert_false(stopped.making())
	stopped.run_to(n - 1)
	var made := stopped.made()
	assert_true(made >= 0 and made <= n, "what it made (%d frames)" % made)
	if made > 0:
		assert_eq(stopped.ops_at(n - 1), here.ops_at(made - 1), "a frame past it: the paint as far as it got")
	stopped.stop()                             # (again: nothing)


## REPLAY BLOOD (GAMEPLAY MODIFIERS; owner, 2026-10-15: the replays' blood
## optional, off by default): off, a recording's playback has no paint (none
## made); the match records its inputs all the same, so turned on the same
## recording shows it.
func test_replay_blood_off_by_default() -> void:
	assert_false(bool(MwSettings.SAVED["replay_paint"][2]), "off by default")
	if not need_rom():
		return
	var was := MwSettings.replay_paint
	var s := _match(18, 1, 34)
	sim.players.damage(_skater(s, 0), 0x158000)
	var drawer := MwRinkDraw3D.new(rom)
	var recorded := MwFullReplay.new()
	MwSettings.replay_paint = false
	for k in 12:
		_run(1)
		drawer.build(s)
		recorded.add_frame(PackedByteArray([k, 2]), MwReplay3D.frame(s, drawer))
	var last := recorded.side(recorded.size() - 1)
	assert_gt((last["splat"]["in"] as Array).size(), 0, "its inputs recorded all the same")
	assert_null(MwSplatterReplay.of(null, recorded), "off: no paint for the playback")
	var pb := MwFullReplayPlayback.new(MwRinkState.new(), rom, recorded)
	pb.shown["at"] = 5
	assert_false(pb.frame_3d().has("splat"), "its frames without it")
	MwSettings.replay_paint = true
	var on := MwSplatterReplay.of(null, recorded)
	assert_not_null(on, "on: made again")
	on.finish()
	assert_eq(on.ops_at(recorded.size() - 1), s.splatter.atlas.count(), "as the match painted")
	MwSettings.replay_paint = was


## A pass's inputs: its head, every player listed, the corpses, the puck.
func test_a_pass_s_inputs() -> void:
	if not need_rom():
		return
	var s := _match()
	_run(1)
	var rec := MwSplatter.inputs(2, s, rom)
	var n := s.teams[0].players.size() + s.teams[1].players.size()
	assert_eq(rec[0], 2, "its ticks")
	assert_eq(rec[2], n, "both teams' players")
	var p := _skater(s, 0)
	var o := MwSplatter.IN_HEAD + s.teams[0].players.find(p) * MwSplatter.IN_PLAYER
	assert_eq([rec[o], rec[o + 1], rec[o + 2], rec[o + 6], rec[o + 7], rec[o + 11]],
			[p.slot, 1, p.record, p.motion.pos[0], p.motion.pos[1], p.angle])
	var at := MwSplatter.IN_HEAD + n * MwSplatter.IN_PLAYER
	assert_eq(rec.size(), at + 1 + rec[at] * 3 + 4, "the corpses, then the puck")


## The replay's data keeps the inputs and no atlas (MwFullReplay.side_to_data:
## the atlas is the match's object - an older build wrote it as an object's
## id, which played no paint); the store keeps the seed.
func test_the_replay_data_keeps_the_inputs_and_the_seed_not_the_atlas() -> void:
	if not need_rom():
		return
	var s := _match(18, 1, 33)
	sim.players.damage(_skater(s, 0), 0x158000)
	_run(3)
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(s)
	var f := MwReplay3D.frame(s, drawer)
	assert_same(f["splat"]["atlas"], s.splatter.atlas, "the ring's frame: the match's atlas")
	assert_gt((f["splat"]["in"] as Array).size(), 0, "the passes' inputs")
	var store := MwFullReplay.new()
	store.add_frame(PackedByteArray([0, 2]), f)
	assert_eq(store.splat_seed, 33, "the seed")
	var back := MwFullReplay.from_data(store.to_data()).side(0)
	assert_false((back["splat"] as Dictionary).has("atlas"), "no atlas")
	assert_eq(back["splat"]["in"], f["splat"]["in"], "the inputs")
	assert_eq(int(back["splat"]["ops"]), int(f["splat"]["ops"]))
	assert_eq(MwFullReplay.from_data(store.to_data()).splat_seed, 33)


## The attract demo's own seed (owner: a single seed of its own): fixed;
## any other match paints from the crowd's.
func test_the_demo_s_seed() -> void:
	assert_eq(MwSplatter.seed_for(true, 12345), MwSplatter.DEMO_SEED)
	assert_eq(MwSplatter.seed_for(true, 999), MwSplatter.DEMO_SEED, "whatever the crowd's")
	assert_eq(MwSplatter.seed_for(false, 12345), 12345, "a match: the crowd's")
	if not need_rom():
		return
	assert_eq(MwSplatter.new(MwSplatter.seed_for(true, 1)).atlas.digest(),
			MwSplatter.new(MwSplatter.seed_for(true, 2)).atlas.digest(), "the same ice every time")


## The VISUALS page's switches as [param on] (blood, ice_detail,
## reflections); returns them as they were.
func _switches(on: Array) -> Array:
	var was := [MwSettings.blood, MwSettings.ice_detail, MwSettings.reflections]
	MwSettings.blood = on[0]
	MwSettings.ice_detail = on[1]
	MwSettings.reflections = on[2]
	return was


## The model's materials that take the paint: the rink's and their reflections'.
func _paint_materials(view: MwRinkView3D) -> Array:
	return view.model._materials.values() + view.model._reflect_materials.values()


## The VISUALS page's switches (owner, 2026-10-11: ABACABB MODE, DETAILED
## ICE, REFLECTIONS) change what the 3D view draws, at its next frame, and
## never the paint: ABACABB MODE off hides the blood and oil on every
## painted surface and in the reflections, and the particles in flight;
## DETAILED ICE off the ice's own detail (the floor's layer); REFLECTIONS
## off the mirrored copies. The atlas keeps everything.
func test_the_visuals_switches_hide_what_is_drawn() -> void:
	if not need_rom():
		return
	var was := _switches([true, true, false])     # (counting the quads: no reflections, test_reflections)
	var s := _match()
	sim.players.damage(_skater(s, 0), 0x158000)
	_run(2)
	var parts: int = (s.splatter.snapshot()["parts"] as Array).size()
	assert_gt(parts, 0, "in flight")
	var ops := s.splatter.atlas.count()
	var digest := s.splatter.atlas.digest()
	var view := VIEW.instantiate() as MwRinkView3D
	add_child_autofree(view)
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(s)
	view.present(s, drawer, {})
	var floor_m := view.model._materials["floor"] as ShaderMaterial
	assert_true(bool(floor_m.get_shader_parameter("paint_on")))
	for m: ShaderMaterial in _paint_materials(view):
		assert_true(bool(m.get_shader_parameter("paint_blood")), "on: the blood")
		assert_true(bool(m.get_shader_parameter("ice_detail")), "on: the ice's detail")
	var shown := view.sprites._shown
	MwSettings.blood = false
	view.blend_to(1.0)
	for m: ShaderMaterial in _paint_materials(view):
		assert_false(bool(m.get_shader_parameter("paint_blood")), "ABACABB MODE off: no blood or oil")
		assert_true(bool(m.get_shader_parameter("ice_detail")), "the ice's detail kept")
	assert_true(bool(floor_m.get_shader_parameter("paint_on")), "the atlas still on the model")
	assert_eq(view.sprites._shown, shown - parts, "no particles in flight")
	MwSettings.ice_detail = false
	view.blend_to(1.0)
	assert_false(bool(floor_m.get_shader_parameter("ice_detail")), "DETAILED ICE off: the plain ice")
	MwSettings.blood = true
	view.blend_to(1.0)
	assert_true(bool(floor_m.get_shader_parameter("paint_blood")), "back at the next frame")
	assert_false(bool(floor_m.get_shader_parameter("ice_detail")))
	assert_eq(view.sprites._shown, shown, "the particles again")
	# a new atlas (another match, a replay) keeps the switches
	view.model.set_paint(s.splatter.atlas.texture(), true)
	assert_false(bool(floor_m.get_shader_parameter("ice_detail")), "kept by set_paint")
	MwSettings.ice_detail = true
	MwSettings.reflections = true
	view.blend_to(1.0)
	assert_true(bool(floor_m.get_shader_parameter("ice_detail")))
	assert_true((view.model.reflections()["wall"] as MeshInstance3D).visible, "REFLECTIONS on")
	assert_true(view.sprites.reflections)
	MwSettings.reflections = false
	view.blend_to(1.0)
	assert_false((view.model.reflections()["wall"] as MeshInstance3D).visible, "REFLECTIONS off")
	assert_false(view.sprites.reflections)
	assert_false(view.nets.reflections)
	assert_eq(s.splatter.atlas.count(), ops, "nothing painted by drawing")
	assert_eq(s.splatter.atlas.digest(), digest, "the same texels")
	_switches(was)


## Presentation only (owner: replays and demos the same whatever the
## switches): a match drawn in 3D with ABACABB MODE, DETAILED ICE and
## REFLECTIONS off records what it does with them on - the same game, the
## same paint, the replay's data byte for byte - and its playback, made
## again from the seed, follows the switches it is shown with.
func test_the_switches_change_no_recording() -> void:
	if not need_rom():
		return
	var was := _switches([true, true, true])
	var runs := []
	for on: bool in [true, false]:
		_switches([on, on, on])
		var s := _match(18, 1, 41)
		var live_view := VIEW.instantiate() as MwRinkView3D
		add_child_autofree(live_view)
		var drawer := MwRinkDraw3D.new(rom)
		var live_store := MwFullReplay.new()
		for k in 90:
			if k == 3:
				sim.players.damage(_skater(s, 0), 0x158000)
			if k == 20:
				sim.players.damage(_skater(s, 1), 0x7FFFFFFF)
			_run(1)
			drawer.build(s)
			live_view.present(s, drawer, {}, k > 0)
			live_view.blend_to(0.5)
			live_view.blend_to(1.0)
			if k % 5 == 4:
				live_store.add_frame(PackedByteArray([k & 0xFF, 2]), MwReplay3D.frame(s, drawer))
		assert_eq(bool((live_view.model._materials["floor"] as ShaderMaterial).get_shader_parameter("paint_blood")), on)
		runs.append([MwNetHash.rink(s), s.splatter.atlas.digest(), s.splatter.atlas.count(),
				var_to_bytes(live_store.to_data()), _painted(s.splatter.atlas)])
	assert_gt(int(runs[0][4]), 100, "blood painted")
	assert_eq(runs[1][4], runs[0][4])
	assert_eq(runs[1][0], runs[0][0], "the same game")
	assert_eq(runs[1][1], runs[0][1], "the same texels")
	assert_eq(runs[1][2], runs[0][2], "the same operations")
	assert_eq(runs[1][3], runs[0][3], "the same replay data, byte for byte")
	# the recording played: the paint made again, drawn by the switches
	var store := MwFullReplay.from_data(bytes_to_var(runs[1][3]))
	var again := MwSplatterReplay.new(store)
	again.run_to(store.size() - 1)
	assert_eq(again.atlas().digest(), runs[0][1], "made again as it was")
	var f := again.dress(store.side(0), 0)
	var parts: int = (f["splat"]["parts"] as Array).size()
	assert_gt(parts, 0, "particles in the first frame")
	var view := VIEW.instantiate() as MwRinkView3D
	add_child_autofree(view)
	_switches([true, true, false])
	view.present_frame(f, {}, false)
	var shown := view.sprites._shown
	assert_true(bool((view.model._materials["floor"] as ShaderMaterial).get_shader_parameter("paint_blood")))
	MwSettings.blood = false
	MwSettings.ice_detail = false
	view.blend_to(1.0)
	var floor_m := view.model._materials["floor"] as ShaderMaterial
	assert_false(bool(floor_m.get_shader_parameter("paint_blood")), "the playback: no blood")
	assert_false(bool(floor_m.get_shader_parameter("ice_detail")), "the playback: the plain ice")
	assert_eq(view.sprites._shown, shown - parts, "the playback: no particles")
	_switches(was)
