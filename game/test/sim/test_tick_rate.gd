extends "res://test/rom/rom_test_base.gd"
## Plan 36, TICK RATE fast-forwarded: CPU against CPU on the rink, each pass
## as long as MwPassPacer says the original's 68000 would take, the pass
## lengths fed back into the game as live play does - ORIGINAL (MwPassLoad's
## features, MwPassCost; no sound driver here: its mean) and APPROXIMATED
## (MwPassApprox: integers). BlastEm's CPU-against-CPU load recordings
## (cpu_s0, cpu_s10, cpu_s16) average 3.65-3.68 ticks a pass: 2 ticks 5 %,
## 3 45 %, 4 35-38 %, 5 9-10 %, 6 4 %, 7+ 1 %; all sixteen runs 3.53-4.02.
## The models' check against those recordings pass by pass: `tools/bin/
## pass-check --tick-model` (docs/re/timing.md "Pass load").

const PASSES := 1500


## [param passes] passes of a CPU match paced by [param mode]; with
## [param both] the other model runs beside it on the same passes. Returns
## {"e": elapsed per pass, "gap": the largest |APPROXIMATED - ORIGINAL| a
## pass (master clocks), "total": ORIGINAL's work then (both: else 0),
## "state": the rink's state at the end}. [param teams]: the stadium and the
## two teams (plan 38: a custom team's ids read [method MwRom.data] as it is
## now, with the custom teams' view).
func _match(mode: String, passes: int, both := false, teams := Vector3i(3, 3, 7)) -> Dictionary:
	var bytes := MwRom.data() if teams.x >= MwTeams.COUNT or teams.y >= MwTeams.COUNT else rom
	var s := MwRinkState.new()
	s.rng = MlhRng.new(36)
	var sim := MwRinkSim.new(bytes, s)
	var pass_load := MwPassLoad.new(bytes) if mode == "ORIGINAL" or both else null
	var approx := MwPassApprox.new(bytes) if mode == "APPROXIMATED" or both else null
	var cpu: Object = MwRinkAI.new()
	if pass_load != null:
		pass_load.live = true
		cpu = pass_load.wrap(cpu)
	if approx != null:
		cpu = approx.wrap(cpu)
	sim.cpu = cpu
	var update := MwRinkUpdate.new(sim)
	var phases := MwRinkPhases.new(update)
	MwRinkMatch.start(sim, teams.x, teams.y, teams.z, 5, false, 2)
	s.period_minutes = 3
	s.clock = 180
	assert_eq(phases.enter(5), -1, "a faceoff at centre ice")
	var pacer := MwPassPacer.new()
	var es := PackedInt32Array()
	var e := 2
	var first := true
	var gap := 0
	var gap_total := 0
	for i in passes:
		s.tick += e
		update.pass_start(e)
		if pass_load != null:
			pass_load.clock_now(update.window_ops)
			pass_load.begin(sim, e)
		if approx != null:
			approx.clock_now(update.window_ops)
			approx.begin(sim, e)
		sim.run(e)
		update.after_segment(e)
		var left := phases.pass_end(e)
		if left >= 0:
			# a goal or a stoppage: back to a faceoff (the screens between not run)
			MwRinkMatch.rink_exit(sim, left)
			for m in [pass_load, approx]:
				if m != null:
					m.reset_visit()
			pacer.reset()
			phases.enter(5)
			first = true
			e = 2
			continue
		update.draws([], MwRinkPhases.RULES_DRAWN, phases.overlays, phases.sprite_ops)
		var wo := {}
		var wa := {}
		if pass_load != null:
			var f := pass_load.features(update, phases)
			wo = MwPassCost.work_mclk(f, f["clock"])
		if approx != null:
			wa = approx.work(update, phases)
		if both:
			var d := 0
			var t := 0
			for k in ["before", "rink_update", "after"]:
				d += absi(int(wa[k]) - int(wo[k]))
				t += int(wo[k])
			if d > gap:
				gap = d
				gap_total = t
			assert_eq([wa["rows_words"], wa["words"]], [wo["rows_words"], wo["words"]], "pass %d: the same words" % i)
		pacer.begin(wa if mode == "APPROXIMATED" else wo, first)
		first = false
		while not pacer.vblank():
			pass
		e = pacer.last_elapsed
		es.append(e)
	return {"e": es, "gap": gap, "total": gap_total, "state": MwSimDict.to_dict(s)}


func _check_pace(es: PackedInt32Array, label: String) -> void:
	var counts := {}
	var ticks := 0
	for e in es:
		counts[e] = int(counts.get(e, 0)) + 1
		ticks += e
	var n := es.size()
	var mean := float(ticks) / n
	gut.p("%s: %d passes, mean %.3f ticks, %s" % [label, n, mean, str(counts)])
	assert_between(mean, 3.4, 4.1, "the original's 3.5-4.0 ticks a pass")
	var share := func(k: int) -> float: return float(counts.get(k, 0)) / n
	assert_between(share.call(3), 0.3, 0.55, "3 ticks: the original's commonest")
	assert_between(share.call(4), 0.25, 0.5)
	assert_lt(share.call(2), 0.12)
	assert_lt(share.call(1), 0.01, "a pass shorter than a frame is rare")


func test_cpu_match_runs_at_the_originals_pace() -> void:
	if not need_rom():
		return
	_check_pace(_match("ORIGINAL", PASSES)["e"], "ORIGINAL")


func test_approximated_runs_at_the_same_pace() -> void:
	if not need_rom():
		return
	var r := _match("APPROXIMATED", PASSES, true)
	_check_pace(r["e"], "APPROXIMATED")
	gut.p("largest gap to ORIGINAL's model: %d master clocks of %d" % [r["gap"], r["total"]])
	assert_lt(r["gap"], 400, "integer weights in 1/16 cycles: within a few dozen cycles of ORIGINAL's model")


## Online (plan 35) every machine paces the passes itself: APPROXIMATED is a
## function of the game alone - the same passes, the same ticks.
func test_approximated_is_deterministic() -> void:
	if not need_rom():
		return
	var a := _match("APPROXIMATED", 600)
	var b := _match("APPROXIMATED", 600)
	assert_eq(a["e"], b["e"], "the same pass lengths")
	assert_eq(var_to_bytes(a["state"]), var_to_bytes(b["state"]), "the same game")


func test_online_forces_approximated_for_original() -> void:
	var was := MwSettings.tick_rate
	MwSettings.tick_rate = "ORIGINAL"
	assert_eq(MwSettings.rink_tick_rate(false), "ORIGINAL")
	assert_eq(MwSettings.rink_tick_rate(true), "APPROXIMATED", "online: the deterministic model")
	for r in ["OVERCLOCKED", "APPROXIMATED"]:
		MwSettings.tick_rate = r
		assert_eq(MwSettings.rink_tick_rate(true), r)
	MwSettings.tick_rate = was
	var offline := MwSession.new()
	assert_false(MwPassPacer.online_session(offline), "a session without plan 35's player table")
	assert_false(MwPassPacer.online_session(null))


## Plan 38 with plan 36: a custom team at its own rink - more hazards and
## rink objects than the original's slots, its own gravity - paced by both
## models: they read the rink's slots whatever their number, so the pass
## lengths stay the original's kind of pace and the two agree.
func test_a_custom_rink_is_paced_alike() -> void:
	if not need_rom():
		return
	var team := MwCustomTeam.from_original(MwRom.archive().bytes(), 9)
	team.rink.gravity = -16
	team.rink.hazards.clear()
	for x in [-150, -90, 90, 150]:
		team.rink.hazards.append({"kind": "pit", "x": x, "y": 180, "mirror": false})
		team.rink.hazards.append({"kind": "mine", "x": x, "y": -180, "mirror": false})
	team.rink.hazards.append({"kind": "shark", "x": 0, "y": 200, "mirror": false})
	team.validate(MwRom.archive().bytes())
	MwCustomTeams.teams.append(team)
	MwCustomTeams.rebuild()
	var r := _match("APPROXIMATED", 600, true, Vector3i(23, 23, 4))
	var st: Dictionary = r["state"]
	MwCustomTeams.clear()
	assert_gt((st["hazards"] as Array).size(), MwRinkState.HAZARD_SLOTS, "the custom rink's extra slots")
	var ticks := 0
	for e in r["e"]:
		ticks += e
		assert_between(e, 1, 12, "a pass of a frame to a few")
	var mean := float(ticks) / (r["e"] as PackedInt32Array).size()
	gut.p("custom rink: mean %.3f ticks a pass, largest gap to ORIGINAL's model %d of %d"
			% [mean, r["gap"], r["total"]])
	assert_between(mean, 3.0, 4.5, "the original's kind of pace")
	assert_lt(r["gap"], 400, "the two models agree")
