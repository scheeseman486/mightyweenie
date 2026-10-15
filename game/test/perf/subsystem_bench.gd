extends SceneTree
## Plan 45's subsystem bench (tools/bin/frame-profile's offline partner, no
## display): what each part of a frame costs on its own, in microseconds a
## call, best of three runs - a CPU v CPU rink pass (the sim alone, with the
## 2D draw pass, with the 3D drawer's), the match models (crowd life,
## benches, paint), the online pass's extras (the rink hash, the run-ahead's
## copy), and the sound driver's tick (the model alone, and with the chips
## rendering a tick of audio). Built on plan 42's bench.
##   tools/bin/godot-headless -s res://test/perf/subsystem_bench.gd [-- --passes N]

const PADS := [0x01, 0x02, 0x04, 0x08, 0x05, 0x0A, 0]


func _initialize() -> void:
	_run.call_deferred()


## A CPU v CPU match at its first faceoff: [state, sim, update, phases].
func _game(seed_value: int, models: bool) -> Array:
	var rom := MwRom.data()
	var s := MwRinkState.new()
	s.rng = MlhRng.new(seed_value)
	var sim := MwRinkSim.new(rom, s)
	sim.cpu = MwRinkAI.new()
	var update := MwRinkUpdate.new(sim)
	var phases := MwRinkPhases.new(update)
	MwRinkMatch.start(sim, 3, 3, 7, 4, false, 2)
	s.period = 1
	s.period_minutes = 5
	s.clock = 300
	phases.enter(5)
	if models:
		MwMatchModels.make(s, MwSession.new(seed_value, 1))
	return [s, sim, update, phases]


## [param count] passes of [param game] with random pads: microseconds a pass.
## [param what]: 0 the pass alone (no draw), 1 the pass with its draw pass
## (the game's drawer: 2D, or the 3D drawer), 2 the match models' step
## alone, 3 the rink hash alone (2 and 3 after a pass without its draw).
func _passes(game: Array, count: int, what: int, rng: RandomNumberGenerator) -> float:
	var s: MwRinkState = game[0]
	var sim: MwRinkSim = game[1]
	var update: MwRinkUpdate = game[2]
	var phases: MwRinkPhases = game[3]
	var spent := 0
	for i in count:
		for pad in 4:
			if rng.randf() < 0.15:
				s.pads_held[pad] = PADS[rng.randi() % PADS.size()] | (0x10 if rng.randf() < 0.1 else 0)
		var started := Time.get_ticks_usec()
		var to := update.run_pass(2, phases, Callable(), Callable(), what == 1)
		if what <= 1:
			spent += Time.get_ticks_usec() - started
		if to >= 0:
			MwRinkMatch.rink_exit(sim, to)
			phases.enter(5)
			continue
		started = Time.get_ticks_usec()
		match what:
			2:
				MwMatchModels.step(sim, 2)
			3:
				MwNetHash.rink(s)
		if what >= 2:
			spent += Time.get_ticks_usec() - started
	return spent / float(count)


func _run() -> void:
	var count := int(preload("res://test/support/cli.gd").args().get("passes", "400"))
	var best := {}
	for rep in 3:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var results := {}
		var game := _game(7, true)
		_passes(game, 300, 0, rng)                        # into play
		results["rink pass (sim)"] = _passes(game, count, 0, rng)
		results["rink pass + 2D draw"] = _passes(game, count, 1, rng)
		results["match models step"] = _passes(game, count, 2, rng)
		results["rink hash (online)"] = _passes(game, count, 3, rng)
		var game_3d := _game(7, false)
		(game_3d[2] as MwRinkUpdate).drawer = MwRinkDraw3D.new(MwRom.data())
		_passes(game_3d, 300, 0, rng)
		results["rink pass + 3D drawer's draw"] = _passes(game_3d, count, 1, rng)
		var copier := MwRinkCopy.new()
		var shadow := MwRinkState.new()
		copier.copy_into(shadow, game[0])
		var started := Time.get_ticks_usec()
		for i in 40:
			copier.copy_into(shadow, game[0])
		results["rink copy (run-ahead)"] = (Time.get_ticks_usec() - started) / 40.0
		for chips in [false, true]:
			var audio := MwAudio.new()
			audio.setup(MwRom.data(), false, chips)
			audio.s68k.music_game()
			audio.s68k.crowd_level(600)
			started = Time.get_ticks_usec()
			for i in 600:
				if i % 30 == 0:
					audio.play_sound(0x25)
				audio.tick()
			results["sound tick (%s)" % ("driver + chips" if chips else "driver model")] = \
					(Time.get_ticks_usec() - started) / 600.0
			audio.free()
		for key: String in results:
			best[key] = minf(float(best.get(key, 1e12)), float(results[key]))
	for key: String in best:
		print("BENCH %-26s %8.1f us" % [key, best[key]])
	quit()
