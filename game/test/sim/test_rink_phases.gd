extends "res://test/rom/rom_test_base.gd"
## The match flow (MwRinkPhases: the puck rules `$C84A` and the phase
## handler `$FC58`) against the original (compare/fixtures/rink_phases.json
## from `tools/bin/pass-check --phase-fixture`; decoded fields only): each
## case starts from the state at the end of a recorded segment, runs the
## rest of the pass (update, puck rules, phase handler, draws) and the next
## pass's start with the ticks the original read, the sound driver's
## answers about the coach's voice and the pause menu's answer, and must
## end with every field the original had at the next segment's start - or
## leave for the screen the original left for. Cases cover the faceoff
## sequence, the period start (speech, FACE OFF! drop), goals, the period
## end and the game over, the pause, icing and the goalie hold, the FACE
## OFF banner, Waste the Goalie and the exits. Then the parts checked
## without the original: the drop's settle bug, the clock, the pause menu.

var fx: Dictionary
var paths: Array


## What the original read from outside the CPU in a case.
class Recorded extends RefCounted:
	var ticks: Array = []
	var voices: Array = []
	var handle := 0
	var pause := 0
	var _t := 0
	var _v := 0

	func tick_at(up: MwRinkUpdate, _tag: int) -> void:
		if _t < ticks.size():
			up.s.tick = int(ticks[_t][1])
			_t += 1

	func voice_poll(_ph: MwRinkPhases, _handle: int) -> int:
		var v := int(voices[_v]) if _v < voices.size() else 0
		_v += 1
		return v

	func voice_handle(_ph: MwRinkPhases, _id: int) -> int:
		return handle

	func pause_result(_ph: MwRinkPhases) -> int:
		return pause


func before_all() -> void:
	super.before_all()
	fx = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_phases.json")))
	paths = fx["paths"]


func _state(values: Array) -> MwRinkState:
	var d := MwSimDict.to_dict(MwRinkState.new())
	var changes := {}
	for i in paths.size():
		changes[paths[i]] = values[i]
	MwSimDict.patch_dict(d, changes)
	return MwSimDict.from_dict(d)


func test_fixture_covers_the_match_flow() -> void:
	var feats := {}
	for c in fx["cases"]:
		for f in c["features"]:
			feats[f] = true
	var want := ["goalie hold", "pause 1", "voice", "expression", "voices pause", "drop thud", "drop shake", "clock",
			"0:00", "phase 9/1 -> 9/2", "phase 9/2 -> 1/0", "phase 1/0 -> 0/0", "phase 3/0 -> 3/1", "phase 3/0 -> 5/1",
			"phase 5/1 -> 10/1", "phase 11/1 -> 11/2", "phase 14/0 -> 14/1", "rule 0 -> 1 (phase 0 -> 0)",
			"rule 1 -> 0 (phase 0 -> 0)", "rule 1 -> 2 (phase 8 -> 8)", "goal 5 -> 65535"]
	for s in 9:
		want.append("faceoff %d -> %d" % [s, s + 1 if s < 8 else 255])
	for x in [1, 5, 7, 10, 12, 14, 15, 18]:
		want.append("exit %d" % x)
	for f in want:
		assert_true(feats.has(f), "a case with %s" % f)


func test_cases_end_as_the_original() -> void:
	if not need_rom():
		return
	var failed := 0
	var cur: Array = []
	for c in fx["cases"]:
		if c.has("start"):
			cur = (c["start"] as Array).duplicate()
		else:
			for ch in c["start_diff"]:
				cur[int(ch[0])] = ch[1]
		var s := _state(cur)
		var po: Array = c["playoffs"]
		s.playoffs.rng.state = int(po[0])
		s.playoffs.dead = PackedInt32Array([int(po[1]), int(po[2])])
		s.playoffs.seed = int(po[3])
		s.playoffs.pair = int(po[4])
		s.playoffs.conference = int(po[5])
		s.playoffs.best_of_3 = int(po[6])
		s.playoffs.flag_11 = int(po[7])
		s.playoffs.series = int(po[8])
		s.playoffs.round = int(po[9])
		s.playoffs.flags = int(po[10])
		for h in c["ring"]:
			s.replay.ring_bytes[int(h[0])] = (int(h[1]) >> 8) & 0xFF
			s.replay.ring_bytes[int(h[0]) + 1] = int(h[1]) & 0xFF
		var sim := MwRinkSim.new(rom, s)
		var up := MwRinkUpdate.new(sim)
		var ph := MwRinkPhases.new(up)
		var rec := Recorded.new()
		rec.ticks = c["ticks"]
		rec.voices = c["voices"]
		rec.handle = int(c["handle"])
		rec.pause = int(c["pause"])
		up.hooks = rec
		ph.hooks = rec
		up.after_segment(int(c["e"]))
		var to := ph.pass_end(int(c["e"]))
		var name := "%s pass %d (%s)" % [c["run"], c["pass"], ", ".join(c["features"])]
		if c.has("exit"):
			if to != int(c["exit"]):
				failed += 1
				fail_test("%s: left for %d" % [name, to])
			continue
		up.draws([], MwRinkPhases.RULES_DRAWN, ph.overlays)
		s.tick = int(c["pass_tick"])
		up.pass_start(int(c["e_next"]))
		var pads: Array = c["pads"]
		for p in 4:
			s.pads_held[p] = int(pads[2 * p])
			s.pads_new[p] = int(pads[2 * p + 1])
		var want := {}
		for i in paths.size():
			want[paths[i]] = cur[i]
		for ch in c["end"]:
			want[paths[int(ch[0])]] = ch[1]
		var got := MwSimDict.leaves(MwSimDict.to_dict(s))
		var out := []
		for p in want:
			if p == "tick":
				continue
			var w: Variant = want[p]
			var g: Variant = got.get(p)
			var same: bool = (int(w) == int(g)) if (w is float or w is int) and (g is float or g is int) else w == g
			if not same:
				out.append("%s %s/%s" % [p, str(w), str(g)])
		if not out.is_empty():
			failed += 1
			fail_test("%s: %d fields differ: %s" % [name, out.size(), ", ".join(out.slice(0, 6))])
	assert_eq(failed, 0, "%d cases as the original" % ((fx["cases"] as Array).size() - failed))


# --- without the original ------------------------------------------------------------------------

func _flow() -> MwRinkPhases:
	var s := MwRinkState.new()
	s.rng = MlhRng.new(99)
	var sim := MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 3, 3, 7, 0, false, 2)
	s.period_minutes = 3
	s.clock = 180
	return MwRinkPhases.new(MwRinkUpdate.new(sim))


func test_the_face_off_drop_ends_on_its_first_settled_pass() -> void:
	if not need_rom():
		return
	var ph := _flow()
	var s := ph.s
	s.phase = MwRinkState.PHASE_START
	s.subphase = 2
	s.fight_block = 0
	s.drop.init(0, 0, 0xB4)
	s.drop.vel[2] = -1
	s.faceoff_text = 0
	s.camera.shown = Vector2i(96, 293)
	s.drop_plane = s.camera.shown
	var passes := 0
	var thuds := 0
	var shook := false
	while s.phase == MwRinkState.PHASE_START and passes < 100:
		ph.sim.events.clear()
		s.camera.shown = s.drop_plane            # (the camera pass puts plane B back every pass)
		ph.pass_end(3)
		for e in ph.sim.events:
			if e == ["sound", 0x15]:
				thuds += 1
		shook = shook or s.camera.shown.x != s.drop_plane.x
		passes += 1
	assert_eq(s.phase, MwRinkState.PHASE_FACEOFF, "the faceoff goes on")
	assert_eq(thuds, 1, "one thud, at the first bounce")
	assert_true(shook, "plane B shook while bouncing")
	assert_eq(s.faceoff_text, 0xC304, "the settle counter took the pointer's low word: no 40-pass hold")
	assert_between(passes, 20, 40, "about 80 ticks")


func test_the_clock_counts_a_second_per_20_ticks_and_0_00_ends_the_period() -> void:
	if not need_rom():
		return
	var ph := _flow()
	var s := ph.s
	var up := ph.up
	s.phase = 0
	s.clock = 3
	s.clock_widget = 2
	s.clock_flags = 1
	s.clock_ref = 0
	s.tick = 0
	var seconds := []
	for i in 40:
		s.tick += 2
		up.pass_start(2)
		ph.pass_end(2)
		seconds.append(s.clock)
		if s.phase != 0:
			break
	assert_eq(seconds.slice(0, 12), [3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2], "a second after 20 ticks")
	assert_eq(s.clock, 0)
	assert_eq(s.phase, 5, "0:00: the period ends")
	assert_has(ph.sim.events, ["sound", 0x1D], "the horn")
	assert_eq(s.clock_flags & 3, 2, "expired, stopped")


func test_the_pause_offers_the_timeout_to_the_team_with_the_puck() -> void:
	if not need_rom():
		return
	var ph := _flow()
	var s := ph.s
	s.phase = 0
	var p := s.teams[0].players[1]
	p.motion.init(-120, 200, 0)
	s.puck.motion.init(-120, 200, 0)
	s.puck.flags = MwRinkState.Puck.CARRIED
	s.puck.carrier = p
	s.pads_new[0] = 0x80
	assert_eq(ph.pass_end(2), MwRinkPhases.PAUSED, "Start opens the pause menu")
	assert_eq(s.pause_offer, 1, "team A carries the puck and has its timeout")
	assert_eq(s.pause_team, 0xB402)
	assert_eq(ph.pause_press(0x20), MwRinkPhases.PAUSED, "C does nothing")
	s.teams[0].health[2] = 0x123456
	assert_eq(ph.pause_press(0x10), 10, "B: the timeout (special plays screen)")
	assert_eq(s.teams[0].flags4 & 0x10, 0, "the timeout is used")
	assert_eq(s.teams[0].health[2], 0x800000, "rested")
	assert_eq(s.faceoff_spot, 6, "the next faceoff at the circle nearest the puck")
	assert_eq(s.clock_flags & 1, 0, "the clock stopped")
	# without the puck: no timeout offered; B does nothing
	ph = _flow()
	s = ph.s
	s.phase = 0
	s.pads_new[0] = 0x80
	assert_eq(ph.pass_end(2), MwRinkPhases.PAUSED)
	assert_eq(s.pause_offer, 0)
	assert_eq(ph.pause_press(0x10), MwRinkPhases.PAUSED, "no timeout to take")
	assert_eq(ph.pause_press(0x40), 7, "A: the instant replay")


func test_faceoff_circles_by_quadrant() -> void:
	if not need_rom():
		return
	assert_eq(MwRinkPhases.nearest_spot(rom, -50, -300), 1, "top left, deep")
	assert_eq(MwRinkPhases.nearest_spot(rom, -50, -100), 2, "top left, near centre")
	assert_eq(MwRinkPhases.nearest_spot(rom, 60, -372), 3)
	assert_eq(MwRinkPhases.nearest_spot(rom, -1, 372), 6)
	assert_eq(MwRinkPhases.nearest_spot(rom, 0, 372), 8)
	assert_eq(MwRinkPhases.nearest_spot(rom, 10, 80), 7)
