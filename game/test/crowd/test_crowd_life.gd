extends "res://test/rom/rom_test_base.gd"
## The crowd's life (plans 30-31, MwCrowdLife): stepped with the game's
## passes and repeatable from its seed; livelier with the game's crowd
## level, the leading team's fans more, a wave in a quiet spell that dies
## down when the play wakes the crowd; its snapshot draws the 3D crowd
## (MwStands3D.show_life) and, with ENHANCE AUDIO, makes its noise; the rink
## steps it only while its passes run (the pause stops it), and a replay
## frame keeps it, so the replay's crowd looks and sounds as it did.

const E := 2          ## ticks a pass


func _run(life: MwCrowdLife, seconds: float, level: int, live := true, score := Vector2i.ZERO) -> void:
	for i in int(seconds * 60.0 / E):
		life.step(E, level, score, live)


## A match's worth of crowd levels: calm, shots, a goal, calm again.
func _match(life: MwCrowdLife) -> Array:
	var out := []
	var levels := [50, 50, 300, 120, 1250, 900, 400, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50]
	for k in levels.size():
		for i in 120:
			life.step(E, levels[k], Vector2i(1 if k > 4 else 0, 0), true)
			out.append(life.snapshot())
	return out


func test_the_same_seed_gives_the_same_crowd() -> void:
	var a := _match(MwCrowdLife.new(1234))
	var b := _match(MwCrowdLife.new(1234))
	assert_eq(a, b, "pass for pass")
	var c := _match(MwCrowdLife.new(99))
	assert_ne(a, c, "another seed, another crowd")
	assert_eq(a[-1]["seed"], 1234, "the seed is in every snapshot")


func test_livelier_with_the_crowd_level_and_calm_again() -> void:
	var life := MwCrowdLife.new(1)
	_run(life, 2.0, MwCrowdLife.LEVEL_CALM)
	assert_almost_eq(life.life, MwCrowdLife.LIFE_CALM, 0.01, "calm")
	_run(life, 0.5, 1250)
	assert_gt(life.life, 0.95, "a goal: roaring at once")
	_run(life, 12.0, MwCrowdLife.LEVEL_CALM)
	assert_almost_eq(life.life, MwCrowdLife.LIFE_CALM, 0.05, "settled in a few seconds")


func test_the_leaders_fans_livelier() -> void:
	assert_eq(MwCrowdLife.lead_lift(0), 0.0)
	assert_eq(MwCrowdLife.lead_lift(1), MwCrowdLife.LEAD_LIFT)
	assert_gt(MwCrowdLife.lead_lift(3), MwCrowdLife.lead_lift(1), "more with a bigger lead")
	assert_eq(MwCrowdLife.lead_lift(20), MwCrowdLife.LEAD_LIFT_MAX)
	var life := MwCrowdLife.new(1)
	life.step(E, 50, Vector2i(0, 2), true)
	assert_eq([life.lead, life.lift], [-1, MwCrowdLife.lead_lift(2)], "team B leads by two")


func test_a_wave_in_a_quiet_spell() -> void:
	var life := MwCrowdLife.new(42)
	_run(life, MwCrowdLife.WAVE_AFTER - 0.5, MwCrowdLife.LEVEL_CALM)
	assert_lt(life.wave_t, 0.0, "not before the quiet has lasted")
	var waves := 0
	for i in 3600:
		var before := life.wave_t
		life.step(E, MwCrowdLife.LEVEL_CALM, Vector2i.ZERO, true)
		if before < 0.0 and life.wave_t >= 0.0:
			waves += 1
	assert_gt(waves, 0, "waves go round in two quiet minutes")
	life.start_wave()
	var from := life.wave_angle()
	_run(life, MwCrowdLife.WAVE_FADE + 0.1, MwCrowdLife.LEVEL_CALM)
	assert_eq(life.wave_amp(), 1.0, "up after its fade-in")
	assert_ne(life.wave_angle(), from, "going round")
	_run(life, 0.2, 400)
	assert_lt(life.wave_amp(), 1.0, "a shot: it dies down")
	_run(life, MwCrowdLife.WAVE_FADE, 400)
	assert_lt(life.wave_t, 0.0, "gone")


func test_no_new_wave_out_of_live_play() -> void:
	var life := MwCrowdLife.new(42)
	_run(life, 120.0, MwCrowdLife.LEVEL_CALM, false)
	assert_lt(life.wave_t, 0.0)


func test_its_noise() -> void:
	var calm := {"life": MwCrowdLife.LIFE_CALM, "wave_amp": 0.0}
	assert_eq(MwCrowdLife.sound_level(calm), MwCrowdLife.LEVEL_CALM, "calm: the original's calm level")
	assert_eq(MwCrowdLife.sound_level({"life": 1.0, "wave_amp": 0.0}), MwCrowdLife.LEVEL_FULL, "roaring")
	assert_eq(MwCrowdLife.sound_level({"life": MwCrowdLife.LIFE_CALM, "wave_amp": 1.0}),
			MwCrowdLife.LEVEL_CALM + MwCrowdLife.WAVE_CHEER, "a wave's cheer")
	assert_eq(MwCrowdLife.sound_level({"life": 1.0, "wave_amp": 1.0}),
			mini(MwCrowdLife.LEVEL_FULL + MwCrowdLife.WAVE_CHEER, 1000))


func test_blending_between_passes() -> void:
	var a := {"seed": 7, "ticks": 100, "life": 0.2, "lead": 0, "lift": 0.0, "wave_angle": 1.0, "wave_amp": 0.0}
	var b := {"seed": 7, "ticks": 102, "life": 0.4, "lead": 1, "lift": 0.25, "wave_angle": 1.2, "wave_amp": 0.5}
	var m := MwCrowdLife.blend(a, b, 0.5)
	assert_eq(m["ticks"], 101.0)
	assert_almost_eq(float(m["life"]), 0.3, 0.0001)
	assert_eq(m["lead"], 1)
	assert_eq(MwCrowdLife.blend({}, b, 0.5), b, "no previous pass: the latest")
	var wrapped := a.duplicate()
	wrapped["ticks"] = MwCrowdLife.WRAP - 1
	var after := b.duplicate()
	after["ticks"] = 1
	assert_eq(MwCrowdLife.blend(wrapped, after, 0.5)["ticks"], float(MwCrowdLife.WRAP), "over the wrap")


func test_the_shader_gets_the_snapshot() -> void:
	if not need_rom():
		return
	var st := MwStands3D.new()
	st.palette = MwScreenPalettes.palette(4, "", 22, 3, 7)
	add_child_autofree(st)          # builds (crowd, atlas, figures)
	var life := MwCrowdLife.new(5)
	_run(life, 0.5, 1250, true, Vector2i(2, 0))
	st.show_life(life.snapshot())
	var m: ShaderMaterial = st.get("_crowd_material")
	assert_almost_eq(float(m.get_shader_parameter("crowd_time")), 0.5, 0.001)
	assert_almost_eq(float(m.get_shader_parameter("liveliness")), life.life, 0.0001)
	assert_eq(int(m.get_shader_parameter("lead_team")), st.palette.team_a + 1, "team A leads")
	assert_eq(int(m.get_shader_parameter("trail_team")), st.palette.team_b + 1)
	assert_almost_eq(float(m.get_shader_parameter("lead_lift")), MwCrowdLife.lead_lift(2), 0.0001)
	assert_ne(float(m.get_shader_parameter("crowd_seed")), 0.0, "the match's seed")


func test_the_rink_steps_it_with_its_passes_and_a_replay_frame_keeps_it() -> void:
	if not need_rom():
		return
	var s := MwRinkState.new()
	var sim := MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 0, 0, 5, 0, false, 2)
	var up := MwRinkUpdate.new(sim)
	s.crowd_life = MwCrowdLife.new(3)
	var calls := []
	MwSound.trace = func(what: String, args: Array, _r: Variant) -> void: calls.append([what, args])
	up.pass_start(2)
	up.crowd_sound()
	assert_eq(s.crowd_life.ticks, 2, "not live: it steps all the same (plan 40: whatever runs the pass)...")
	assert_eq(calls, [], "...but no sound")
	sim.live = true
	s.crowd = 1250
	for i in 30:
		up.pass_start(2)
		up.crowd_sound()
	MwSound.trace = Callable()
	assert_eq(s.crowd_life.ticks, 62, "a pass's ticks a pass")
	assert_eq(calls[-1], ["crowd_level", [MwCrowdLife.sound_level(s.crowd_life.snapshot())]], "its noise")
	MwCrowdLife.drives_sound = false
	calls = []
	MwSound.trace = func(what: String, args: Array, _r: Variant) -> void: calls.append([what, args])
	up.crowd_sound()
	MwSound.trace = Callable()
	MwCrowdLife.drives_sound = true
	assert_eq(calls, [["crowd_level", [1000]]], "ENHANCE AUDIO off: the original's")
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(s)
	var f := MwReplay3D.frame(s, drawer)
	assert_eq(f["crowd"], s.crowd_life.snapshot(), "the frame keeps the crowd")
	var store := MwFullReplay.new()
	s.replay.reset()
	s.replay.open_frame(2)
	var start := s.replay.frame_start
	s.replay.close_frame()
	store.add(s.replay, start, f)
	assert_eq(store.side(0)["crowd"], f["crowd"], "and so does the whole match's replay")


func test_the_pause_stops_it() -> void:
	if not need_rom():
		return
	var host := Node.new()
	add_child_autofree(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(1, 1)
	router.go(4, {"new_match": true}, false)
	for i in 3:
		router.step()
	var rk := router.current() as MwRink
	assert_not_null(rk.state.crowd_life, "a match has its crowd")
	for i in 900:
		if rk.state.phase == MwRinkState.PHASE_PLAY:
			break
		rk._screen_pass(2, MwInputFrame.make({}, {}))
	var t0 := rk.state.crowd_life.ticks
	rk._screen_pass(2, MwInputFrame.make({}, {}))
	assert_gt(rk.state.crowd_life.ticks, t0, "it lives with the play")
	rk._screen_pass(2, MwInputFrame.make({"p1_pause": true}, {}))
	var t1 := rk.state.crowd_life.ticks
	for i in 30:
		rk._screen_pass(2, MwInputFrame.make({}, {}))
	assert_true(rk.phases.paused)
	assert_eq(rk.state.crowd_life.ticks, t1, "paused: the crowd stands still")
