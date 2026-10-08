extends "res://test/rom/rom_test_base.gd"
## The referee cutscene after Waste the Ref (MwRefereeSim, screen 19) on a
## set-up match in phase 12 (plan 11; docs/re/referee.md): the playing
## team, the players' updates going on (the phase-12 AI sends the playing
## team after the referee), his hits and fall, the forced fall after 900
## ticks, the crowd fading, the exit to 17. The original pass for pass:
## `tools/bin/screen-check scr_1009_v8 --only 19`.

const NONE := [0, 0, 0, 0]

var sim: MwRinkSim
var s: MwRinkState


class Idle:
	func think(_sim: MwRinkSim, _p: MwRinkState.Player, _team: MwRinkState.Team, _other: MwRinkState.Team) -> void:
		pass


## A match in phase 12 with the referee on the ice as `$10182` leaves him
## ((165, 0), 5 hits, attr `$A0`, standing), played by team [param t].
func _cutscene(t := 0) -> MwRefereeSim:
	s = MwRinkState.new()
	s.rng = MlhRng.new(4321)
	sim = MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 4, 9, 4, 0, false, 2)
	s.period_minutes = 3
	s.clock = 150
	MwRinkPhases.new(MwRinkUpdate.new(sim)).enter(5)
	s.phase = 12
	s.tick = 2000
	s.teams[t].flags5 |= 1
	s.ref_flag = 5
	s.ref_attr = 0xA0
	s.referee.motion.init(0xA5, 0, 0)
	s.referee.anim = MwAnimState.from_record(rom, MwRefereeSim.REF_STANDS)
	var r := MwRefereeSim.new(rom)
	r.enter(s, 19, 5)
	return r


func _run(r: MwRefereeSim, e: int) -> int:
	s.tick += e
	r.begin_pass()
	return r.step(e, NONE, NONE)


func test_setup() -> void:
	if not need_rom():
		return
	var r := _cutscene(1)
	assert_eq(r.playing_team, s.teams[1], "the team with +5 bit 0")
	assert_eq(r.other, s.teams[0])
	assert_eq(r.crowd, 1000)
	assert_eq(r.stamp, 2000)
	assert_eq(s.projection, 1, "the side view")
	r = _cutscene(0)
	assert_eq(r.playing_team, s.teams[0])


func test_forced_fall_after_900_ticks() -> void:
	if not need_rom():
		return
	var r := _cutscene()
	r.rink.cpu = Idle.new()                  # nobody goes for him
	var t0 := s.tick
	while s.ref_flag != 0 and s.tick - t0 < 2000:
		assert_eq(_run(r, 3), -1)
	assert_eq(s.tick - t0, 900, "900 ticks")
	assert_eq(s.referee.anim.address, MwSimPlayers.REF_DOWN, "knocked down")
	assert_true(s.referee.anim.playing())
	assert_has(r.events, ["sound", 0x2A])
	assert_has(r.events, ["sound", 9])
	assert_eq(s.teams[0].flags5 & 1, 1, "cleared on the next pass")
	_run(r, 3)
	assert_eq(s.teams[0].flags5 & 1, 0)
	var t1 := s.tick
	var to := -1
	while to < 0 and s.tick - t1 < 2000:
		to = _run(r, 3)
		if s.referee.anim.playing():
			assert_eq(r.stamp, s.tick, "stamped while he falls")
			assert_eq(r.crowd, 1000)
	assert_eq(to, 17, "to the message scoreboard")
	assert_eq(s.tick - r.stamp, 120, "120 ticks after the fall")
	assert_eq(r.crowd, 1000 - 950 * 120 / 120)
	assert_has(r.events, ["fade_out", MwScreenSim.FADE_OUT])
	assert_eq(s.projection, 0)
	assert_eq(s.phase, 12, "the phase stays")


func test_stands_again_between_hits() -> void:
	if not need_rom():
		return
	var r := _cutscene()
	r.rink.cpu = Idle.new()
	r.rink.players._referee_hit(1)
	assert_eq(s.ref_flag, 4, "one hit less")
	assert_true(s.referee.anim.playing(), "a hurt animation")
	assert_ne(s.referee.anim.address, MwRefereeSim.REF_STANDS)
	for i in 200:
		_run(r, 2)
		if s.referee.anim.address == MwRefereeSim.REF_STANDS:
			break
	assert_eq(s.referee.anim.address, MwRefereeSim.REF_STANDS, "standing again (`$EF84`)")
	assert_false(s.referee.anim.playing())
	assert_eq(s.ref_flag, 4)


func test_the_players_waste_the_ref() -> void:
	if not need_rom():
		return
	var r := _cutscene()
	var to := -1
	var hits := [s.ref_flag]
	var t0 := s.tick
	while to < 0 and s.tick - t0 < 3000:
		to = _run(r, 3)
		if s.ref_flag != hits[hits.size() - 1]:
			hits.append(s.ref_flag)
	assert_eq(to, 17)
	assert_eq(hits, [5, 4, 3, 2, 1, 0], "five hits")
	assert_true(s.tick - t0 < 900 + 400, "before the forced fall's time")
	var punchers := 0
	for p in s.teams[0].players:
		if p.position != 5 and p.present:
			punchers += 1
	assert_true(punchers > 0)


func test_box_occupants_animate() -> void:
	if not need_rom():
		return
	var r := _cutscene()
	r.rink.cpu = Idle.new()
	var p := s.teams[1].players[2]
	s.penalties = 1
	sim.penalties.rule(1, p)
	sim.penalties.serve_calls()
	_run(r, 2)
	# the side view: x 189 -> y' 377 - 189, the box's y -> x' y + 160
	var box := r.sprite_ops.filter(func(o: Array) -> bool: return o[0] == "anim" and int(o[5]) == 377 - 189)
	assert_eq(box.size(), 1, "the box entry")
	assert_eq(int(box[0][4]), 160 + 52, "team B's box, its first place")
	var ref := r.sprite_ops.filter(func(o: Array) -> bool: return o[0] == "anim" and int(o[1]) == MwRefereeSim.REF_STANDS)
	assert_eq([int(ref[0][4]), int(ref[0][5]), int(ref[0][7])], [160, 377 - 165, 0xA0], "the referee at (165, 0)")
