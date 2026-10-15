extends "res://test/rom/rom_test_base.gd"
## The 3D benches and penalty boxes (plan 32, MwBenchLife, MwBench3D): who
## stands where, the game's pick seen walking out in time, the box's
## players and their way out, the figures drawn from the snapshot alone,
## repeatable from the seed.

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")

var sim: MwRinkSim
var update: MwRinkUpdate
var phases: MwRinkPhases


## The match and its passes (plan 40: test/support/rink_rig.gd).
const RinkRig := preload("res://test/support/rink_rig.gd")

var rig: RinkRig


func _match(seed_ := 5) -> MwRinkState:
	rig = RinkRig.new()
	var s := rig.make(rom, 3, 3, 7, 0, false, null, true)
	sim = rig.sim
	update = rig.update
	phases = rig.phases
	s.crowd_life = MwCrowdLife.new(seed_)
	s.bench_life = MwBenchLife.new(seed_)
	phases.enter(5)
	return s


func _run(passes: int) -> void:
	rig.run(passes)


func _until_play() -> void:
	for i in 400:
		if sim.s.phase == MwRinkState.PHASE_PLAY:
			return
		_run(1)


## Team [param t]'s roster slots on the bench by the game: alive, not on
## the ice, not in the box.
func _bench(s: MwRinkState, t: int) -> Array:
	var team := s.teams[t]
	var on := {}
	for p in team.players:
		if p.present:
			on[p.slot] = true
	var out := []
	for i in 24:
		var boxed := false
		for k in 3:
			var at := MwRinkPenalties.entry(k)
			if MwRinkPenalties.byte(team, at + 0x10) != 0 and MwRinkPenalties.byte(team, at + 0xE) == i:
				boxed = true
		if team.health[i] & 0x7FFFFFFF != 0 and not on.has(i) and not boxed:
			out.append(i)
	return out


func test_places() -> void:
	for t in 2:
		var sy := 1.0 if t == 0 else -1.0
		var seen := {}
		for k in MwBench3D.PEN_PLACES:
			var place := MwBench3D.place_at(t, MwBench3D.PEN + k)
			assert_true(place.x < -185.0 and place.x > -216.0 and place.y * sy > 40.0 and place.y * sy < 160.0,
					"pen place %d in the pen" % k)
			seen[place] = true
		for k in MwBench3D.RECESS_PLACES:
			var place := MwBench3D.place_at(t, MwBench3D.RECESS + k)
			assert_true(place.x < -185.0 and place.x > -256.0 and place.y * sy > 0.0 and place.y * sy < 40.0,
					"recess place %d" % k)
			seen[place] = true
		assert_eq(seen.size(), MwBench3D.PEN_PLACES + MwBench3D.RECESS_PLACES, "all different")
		for k in 3:
			var point := MwBench3D.place_at(t, MwBench3D.BOX + k)
			assert_true(point.x > 185.0 and point.x < 216.0 and point.y * sy > 40.0 and point.y * sy < 160.0,
					"box seat %d" % k)
	assert_eq(MwBench3D.place_at(0, MwBench3D.PEN).y, 46.0, "team A's bench on the south half")
	assert_almost_eq(MwBench3D.place_at(0, MwBench3D.PEN + 14).y, 156.0, 1e-4, "to its far end")
	assert_lt(MwBench3D.place_at(1, MwBench3D.PEN).y, 0.0, "team B's on the north half")


func test_the_ways_and_the_dark() -> void:
	var way := MwBench3D.route(0, MwBench3D.place_at(0, MwBench3D.PEN + 6), MwBench3D.place_at(0, MwBench3D.WEST_EXIT))
	assert_eq(way.size(), 3, "round the pen's corner into the recess")
	assert_almost_eq(absf(way[1].y), MwBench3D.TURN_Y, 0.01)
	assert_eq(MwBench3D.along(way, 0.0)[0], way[0])
	assert_eq(MwBench3D.along(way, 1.0)[0], way[2])
	assert_eq(MwBench3D.shade_at(-200.0), 1.0)
	assert_eq(MwBench3D.shade_at(MwBench3D.WEST_OUT.x), 0.0, "the west exit is dark")
	assert_eq(MwBench3D.shade_at(265.0), 0.0, "the original's bench door is in the east arch's dark")
	assert_eq(MwBench3D.shade_at(178.0), 1.0, "inside the boards: lit")
	var mid := MwBench3D.shade_at(250.0)
	assert_true(mid > 0.0 and mid < 1.0, "coming out of it")
	var items := MwBench3D.arch_shade([{"key": "t0.p2.1234/body", "place": MwRinkDraw3D.UPRIGHT,
			"at": Vector3(250, 10, 0)},
			{"key": "puck/body", "place": MwRinkDraw3D.UPRIGHT, "at": Vector3(250, 10, 0)}])
	assert_almost_eq(float(items[0]["shade"]), mid, 1e-6, "a player at the door: shaded")
	assert_false(items[1].has("shade"), "players only")


func test_a_match_fills_the_benches() -> void:
	if not need_rom():
		return
	var s := _match()
	_run(1)
	var life := s.bench_life
	for t in 2:
		var want := _bench(s, t)
		assert_eq(want.size(), 18, "18 reserves at the start")
		var places := {}
		for slot: int in want:
			var key := MwBenchLife.fig_key(t, slot)
			assert_true(life.figs.has(key), "reserve %s on the bench" % key)
			var fg: Dictionary = life.figs[key]
			assert_eq(fg["kind"], MwBenchLife.SIT, "standing at once (under the fade)")
			places[fg["place"]] = true
		assert_eq(places.size(), 18, "each in his own place")
		var ys := []
		for p: int in places:
			if p < MwBench3D.PEN_PLACES:
				ys.append(absf(MwBench3D.place_at(t, p).y))
		assert_lt(ys.min(), 50.0, "the pen filled from end...")
		assert_gt(ys.max(), 150.0, "...to end (owner)")
		for pos in 6:
			# the game's own pick for a skater; for the goalie its pick were he to die
			var pick := sim.players.best_substitute(s.teams[t], pos).x if pos < 5 else life.next_goalie(sim, s.teams[t])
			var place: int = life.figs[MwBenchLife.fig_key(t, pick)]["place"]
			assert_true(place >= MwBench3D.RECESS and place < MwBench3D.RECESS + MwBench3D.RECESS_PLACES,
					"next up for position %d waits by the way out" % pos)
	assert_eq(life.figs.size(), 36)


func test_a_death_sends_the_games_pick_out_in_time() -> void:
	if not need_rom():
		return
	var s := _match()
	_until_play()
	var life := s.bench_life
	var team := s.teams[0]
	var p := team.players[1]
	var pick := sim.players.best_substitute(team, p.position)
	var key := "0.%d" % pick.x
	assert_true(life.figs.has(key))
	# killed, as MwSimPlayers.damage does it
	team.health[p.slot] = 0
	sim.players.enter(p, 0x12)
	_run(1)
	var fg: Dictionary = life.figs[key]
	assert_eq(fg["kind"], MwBenchLife.OUT, "the game's pick is on his way")
	assert_eq(fg["place"], MwBench3D.WEST_EXIT, "into the west arch")
	assert_eq(life.kill_at[1], life.ticks, "the other bench cheers")
	var n := 0
	while p.slot != pick.x and n < 300:
		_run(1)
		n += 1
	assert_eq(p.slot, pick.x, "the game sent him on")
	assert_eq(p.state, 0x14, "from the bench door")
	assert_true(life.figs.has(key), "still walking")
	var at := MwBench3D.along(MwBench3D.route(0, fg["from"], MwBench3D.place_at(0, fg["place"])), fg["p"])[0] as Vector2
	assert_gt(float(fg["p"]), 0.6, "nearly there")
	assert_lt(MwBench3D.shade_at(at.x), 1.0, "already in the arch's dark")
	_run(MwBenchLife.OUT_LAG / 2 + 2)
	assert_false(life.figs.has(key), "gone into the dark")
	assert_false(_bench(s, 0).has(pick.x))
	assert_eq(_bench(s, 0).size(), 17, "the bench one thinner")
	var figs_a := 0
	for k: String in life.figs:
		if k.begins_with("0."):
			figs_a += 1
	assert_eq(figs_a, 17)


func test_the_box() -> void:
	if not need_rom():
		return
	var s := _match()
	_until_play()
	var life := s.bench_life
	var team := s.teams[1]
	var p := team.players[2]
	var slot := p.slot
	p.penalty = 0xFD                               # a minor call
	var i := sim.penalties.put_in_box(p)
	MwRinkPenalties.set_word(team, MwRinkPenalties.entry(i) + 0xC, 6)    # 6 clock seconds left
	_run(1)
	var key := "1.%d" % slot
	assert_true(life.figs.has(key), "in the box")
	var fg: Dictionary = life.figs[key]
	assert_eq(fg["place"], MwBench3D.BOX + i, "in its seat")
	assert_true(fg["box"])
	assert_lt(MwBench3D.place_at(1, fg["place"]).y, 0.0, "team B's box on the north half")
	var n := 0
	while fg["kind"] != MwBenchLife.OUT and n < 300:
		_run(1)
		n += 1
	assert_eq(fg["kind"], MwBenchLife.OUT, "up and out before his time is up")
	assert_ne(MwRinkPenalties.byte(team, MwRinkPenalties.entry(i) + 0x10), 0, "still in the box by the game")
	n = 0
	while MwRinkPenalties.byte(team, MwRinkPenalties.entry(i) + 0x10) != 0 and n < 300:
		_run(1)
		n += 1
	assert_eq(MwRinkPenalties.byte(team, MwRinkPenalties.entry(i) + 0x10), 0, "let out")
	assert_eq(team.players[2].state, 0x14, "from the door")
	assert_gt(float(fg["p"]), 0.6, "nearly in the dark as the game lets him out")
	_run(MwBenchLife.OUT_LAG / 2 + 2)
	assert_false(life.figs.has(key), "gone")


func test_the_same_seed_gives_the_same_benches() -> void:
	if not need_rom():
		return
	var runs := []
	for k in 2:
		var s := _match(9)
		_until_play()
		var team := s.teams[1]
		team.health[team.players[3].slot] = 0
		sim.players.enter(team.players[3], 0x12)
		s.teams[0].score += 1                        # a goal for A
		var snaps := []
		for i in 80:
			_run(1)
			snaps.append(var_to_bytes(s.bench_life.snapshot()))
		runs.append(snaps)
	assert_eq(runs[0], runs[1])


func test_figures_drawn_from_the_snapshot() -> void:
	if not need_rom():
		return
	var s := _match()
	_run(1)
	var snap := s.bench_life.snapshot()
	var items := MwBench3D.items(snap, rom)
	assert_eq(items.size(), 36, "one frame a figure")
	var keys := {}
	for it: Dictionary in items:
		keys[it["key"]] = true
		assert_eq(it["place"], MwRinkDraw3D.UPRIGHT)
		assert_true(it.has("dir"), "turning with the camera")
		var at: Vector3 = it["at"]
		var team := 0 if String(it["key"]).begins_with("bench.t0") else 1
		assert_eq(int(it["dir"]["attr0"]), MwBench3D.TEAM_ATTR[team], "in his team's colours")
		assert_lt(at.x, -185.0, "on the west side")
		assert_eq(signf(at.y), 1.0 if team == 0 else -1.0)
	assert_eq(keys.size(), 36)
	var biases := {}
	for it: Dictionary in items:
		biases[[String(it["key"]).substr(0, 8), it["bias"]]] = true
	assert_eq(biases.size(), 36, "a depth bias of his own in each team (no z-fighting)")
	assert_eq(MwBench3D.items(snap, rom), items, "the snapshot alone says it")
	# team A scores: A's bench celebrates, B's stands still facing the ice
	snap["ticks"] = 1000
	snap["goal_at"] = [940, -1]
	items = MwBench3D.items(snap, rom)
	snap["goal_at"] = [-1, -1]
	var before := MwBench3D.items(snap, rom)
	snap["goal_at"] = [940, -1]
	var goal := items
	items = before
	var moved := 0
	for k in items.size():
		var a: Dictionary = items[k]
		var b: Dictionary = goal[k]
		if String(a["key"]).begins_with("bench.t1"):
			assert_eq(int(b["dir"]["variant"]), 2, "B's bench looks at the ice")
			assert_eq(float((b["at"] as Vector3).z), 0.0, "and does not hop")
		elif a["frame"] != b["frame"] or (b["at"] as Vector3).z > 0.0:
			moved += 1
	assert_gt(moved, 9, "A's bench celebrates")


func test_the_replay_keeps_the_benches_and_the_view_shows_them() -> void:
	if not need_rom():
		return
	var s := _match()
	_run(1)
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(s)
	var f := MwReplay3D.frame(s, drawer)
	assert_eq(f["bench"], s.bench_life.snapshot(), "the replay's frame keeps them")
	var view := VIEW.instantiate() as MwRinkView3D
	add_child_autofree(view)
	view.present(s, drawer, {})
	var with_benches := view.sprites._shown
	view.benches = false
	view.blend_to(1.0)
	assert_eq(view.sprites._shown, with_benches - 36, "36 figures more")
	view.set_camera_mode(MwRinkCamera3D.Mode.CALIBRATION)
	view.blend_to(1.0)
	var without := view.sprites._shown
	view.benches = true
	view.blend_to(1.0)
	assert_eq(view.sprites._shown, without, "not from the original's angle")


func test_clipped_at_the_walls_but_not_over_them() -> void:
	# owner: clipped at the barrier, not where they hang over it
	var end := MwBench3D.place_at(0, MwBench3D.PEN + 14)          # the pen's far end (y 156)
	assert_true(MwBench3D.past_barrier(end, Vector3(end.x, 166, 10)), "through the end wall: clipped")
	assert_true(MwBench3D.past_barrier(end, Vector3(end.x, 163, 42)), "behind its tall glass (to 49): clipped")
	assert_false(MwBench3D.past_barrier(end, Vector3(end.x, 163, 52)), "over it: drawn")
	assert_true(MwBench3D.past_barrier(end, Vector3(end.x, 170, 52)), "but not far over it (owner: robots)")
	assert_false(MwBench3D.past_barrier(end, Vector3(end.x, 150, 10)), "inside: drawn")
	var pen := MwBench3D.place_at(0, MwBench3D.PEN + 4)
	assert_true(MwBench3D.past_barrier(pen, Vector3(-180, pen.y, 10)), "through the low boards into the rink")
	assert_false(MwBench3D.past_barrier(pen, Vector3(-182, pen.y, 25)), "over them (19 high)")
	assert_true(MwBench3D.past_barrier(pen, Vector3(-176, pen.y, 25)), "not far over them")
	assert_false(MwBench3D.past_barrier(pen, Vector3(pen.x, 30, 10)), "the pen opens into the recess")
	var recess := MwBench3D.place_at(0, MwBench3D.RECESS + 1)      # x -230, y 28
	assert_true(MwBench3D.past_barrier(recess, Vector3(recess.x, 44, 20)), "through the recess's wall")
	assert_true(MwBench3D.past_barrier(MwBench3D.place_at(0, MwBench3D.RECESS), Vector3(-230, -4, 10)),
			"through the bar into the other bench")
	assert_false(MwBench3D.past_barrier(MwBench3D.place_at(0, MwBench3D.RECESS), Vector3(-230, -3, 20)),
			"over the bar (16 high)")
	assert_false(MwBench3D.past_barrier(Vector2(-250, 20), Vector3(-266, 20, 10)), "the way out west is open")
	assert_true(MwBench3D.past_barrier(Vector2(-266, 20), Vector3(-266, 44, 10)),
			"the hallway's walls run on under the stands (owner, 2026-10-11)")
	var seat := MwBench3D.place_at(1, MwBench3D.BOX + 0)
	assert_false(MwBench3D.past_barrier(seat, Vector3(180, seat.y, 30)), "the box's fence is see-through: not cut")
	var far_seat := MwBench3D.place_at(1, MwBench3D.BOX + 2)    # beyond the fence: the boards' pad
	assert_true(MwBench3D.past_barrier(far_seat, Vector3(180, far_seat.y, 10)), "through the pad")
	assert_false(MwBench3D.past_barrier(Vector2(250, 10), Vector3(240, 22, 10)), "the door's way is open")
	# the shader's list is this one
	var text := FileAccess.get_file_as_string("res://src/rink3d/rink3d_billboard.gdshaderinc")
	var block := text.substr(text.find("const vec4 BARRIER["))
	block = block.substr(0, block.find("};"))
	var re := RegEx.create_from_string("vec4\\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\\)")
	var segs := []
	for m in re.search_all(block):
		segs.append(Vector4(float(m.strings[1]), float(m.strings[2]), float(m.strings[3]), float(m.strings[4])))
	var tops_text := text.substr(text.find("const float BARRIER_TOP["))
	tops_text = tops_text.substr(tops_text.find("{") + 1)
	tops_text = tops_text.substr(0, tops_text.find("}"))
	var tops := Array(tops_text.split(",")).map(func(t: String) -> float: return float(t.strip_edges()))
	assert_eq(segs.size(), MwBench3D.BARRIERS.size())
	assert_eq(tops.size(), MwBench3D.BARRIERS.size())
	for k in mini(segs.size(), MwBench3D.BARRIERS.size()):
		assert_eq(segs[k], MwBench3D.BARRIERS[k][0], "barrier %d" % k)
		assert_eq(tops[k], MwBench3D.BARRIERS[k][1], "barrier %d's top" % k)


## Plan 40 (B6): the next goalie up is the game's own pick (`$F72C`) - a
## backup goalie in the penalty box is not next up.
func test_next_goalie_is_the_games_pick() -> void:
	if not need_rom():
		return
	var s := _match()
	_until_play()
	var team := s.teams[0]
	var on := team.players[5].slot
	var first := s.bench_life.next_goalie(sim, team)
	assert_ne(first, -1, "a backup goalie")
	assert_ne(first, on, "not the one on the ice")
	assert_eq(first, sim.players.best_substitute(team, 5, on).x)
	var at := MwRinkPenalties.entry(0)
	MwRinkPenalties.set_byte(team, at + 0xE, first)
	MwRinkPenalties.set_byte(team, at + 0x10, 1)
	assert_ne(s.bench_life.next_goalie(sim, team), first, "boxed: not next up")


## Plan 42 (speed, second round): the benches' six picks from one sweep of
## the roster (MwSimPlayers.best_substitutes) are the game's picks asked one
## by one - through a played match with health knocked down, players killed
## and boxed at random.
func test_the_six_picks_at_once_are_the_games_picks() -> void:
	if not need_rom():
		return
	var s := _match()
	_until_play()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var asked := 0
	for i in 300:
		_run(1)
		var team := s.teams[rng.randi() % 2]
		if rng.randf() < 0.1:
			team.health[rng.randi() % 24] = 0 if rng.randf() < 0.3 else rng.randi_range(1, 0x7FFFFFFF)
		if rng.randf() < 0.05:
			var at := MwRinkPenalties.entry(rng.randi() % 3)
			MwRinkPenalties.set_byte(team, at + 0xE, rng.randi() % 24)
			MwRinkPenalties.set_byte(team, at + 0x10, rng.randi() % 2)
		for checked_team in s.teams:
			var on := checked_team.players[5].slot if checked_team.players[5].present else -1
			var exclude := on if rng.randf() < 0.7 else rng.randi_range(-1, 23)
			var picks := sim.players.best_substitutes(checked_team, exclude)
			for pos in 6:
				var want := sim.players.best_substitute(checked_team, pos, exclude if pos == 5 else -1)
				if picks[pos] != want:
					assert_eq(picks[pos], want, "pass %d, position %d" % [i, pos])
					return
				asked += 1
	assert_eq(asked, 300 * 2 * 6)
