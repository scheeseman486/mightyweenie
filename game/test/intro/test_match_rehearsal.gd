extends "res://test/rom/rom_test_base.gd"
## The rink's entry rehearsed for the 3D intro (plan 33, MwMatchRehearsal):
## the same as the rink's real entry, and the session untouched.


func _router(seed_ := 1) -> MwRouter:
	var host := Node.new()
	add_child_autofree(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(seed_, 1)
	return router


func test_the_rinks_entry_is_the_rehearsals() -> void:
	if not need_rom():
		return
	for seed_value in [1, 77]:
		var router := _router(seed_value)
		var session: MwSession = router.session
		session.setup.team_a = 3
		session.setup.team_b = 7
		session.setup.stadium = 5
		var before := session.rng.state
		var rehearsal := MwMatchRehearsal.run(rom, session.setup, session.rng.state, session.playoffs)
		assert_eq(session.rng.state, before, "the session's random numbers untouched")
		router.go(4, {"new_match": true}, false)
		router.step()
		var rk := router.current() as MwRink
		assert_not_null(rk)
		var real := MwSimDict.to_dict(rk.state)
		var rehearsed := MwSimDict.to_dict(rehearsal.state)
		assert_eq(MwSimDict.diff(real, rehearsed), {}, "the same state (seed %d)" % seed_value)
		assert_eq(rk.state.rng.state, rehearsal.state.rng.state, "and the same random numbers after it")
		var real_bench: Dictionary = rk.state.bench_life.snapshot()
		assert_eq(real_bench["figs"].size(), rehearsal.bench["figs"].size())
		# places: team, slot, place of each figure
		var places := func(f: PackedFloat32Array) -> Array:
			var out := []
			for i in range(0, f.size(), MwBenchLife.FIG):
				out.append([int(f[i]), int(f[i + 1]), int(f[i + 3])])
			return out
		assert_eq(places.call(real_bench["figs"]), places.call(rehearsal.bench["figs"]), "the benches as rehearsed")


func test_what_it_tells_the_intro() -> void:
	if not need_rom():
		return
	var session := MwSession.new(5, 1)
	session.setup.team_a = 2
	session.setup.team_b = 9
	var rehearsal := MwMatchRehearsal.run(rom, session.setup, session.rng.state)
	var starters := rehearsal.starters()
	assert_eq(starters.size(), 12, "six a team on the ice")
	for st: Dictionary in starters:
		var at: Vector2 = st["at"]
		assert_lt(absf(at.x), 185.0, "on the ice")
		assert_lt(absf(at.y), 372.0)
	assert_eq(rehearsal.roster(0).size() + rehearsal.roster(1).size(), 48, "everyone alive")
	var keys := {}
	for it: Dictionary in rehearsal.scenery():
		keys[String(it["key"]).get_slice("/", 0)] = true
	assert_true(keys.has("net0") and keys.has("net1"), "the nets")
	var figs: PackedFloat32Array = rehearsal.bench["figs"]
	assert_eq(figs.size() / MwBenchLife.FIG, 36, "18 reserves a bench")
