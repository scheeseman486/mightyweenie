extends "res://test/rom/rom_test_base.gd"
## Penalties on (MwRinkPenalties, plan 10; docs/re/penalties.md) on a set-up
## match: the referee's ruling, stopping play, the box's seconds, order and
## releases, the power play and its clock, a power-play goal freeing a
## player, and the penalty scoreboard sending called players to the box.
## The original's behaviour pass for pass: `tools/bin/visit-check` on the
## soak recordings (docs/compare.md).

var sim: MwRinkSim
var pen: MwRinkPenalties


class Idle:
	func think(_sim: MwRinkSim, _p: MwRinkState.Player, _team: MwRinkState.Team, _other: MwRinkState.Team) -> void:
		pass


func before_each() -> void:
	var s := MwRinkState.new()
	s.rng = MlhRng.new(99)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = Idle.new()
	MwRinkMatch.start(sim, 4, 9, 4, 0, false, 2)
	s.period_minutes = 3
	s.clock = 150
	var phases := MwRinkPhases.new(MwRinkUpdate.new(sim))
	assert_eq(phases.enter(5), -1, "a faceoff: everyone lined up")
	s.penalties = 1
	s.period_row = 0
	s.clock = 150
	s.phase = 0
	pen = sim.penalties


func _skater(t: int, i: int) -> MwRinkState.Player:
	return sim.s.teams[t].players[i]


func test_seconds_from_the_rom_table() -> void:
	# minor 60 / 60 / 120, major 120 / 180 / 300 by the period length row
	assert_eq([MwRinkPenalties.seconds_for(rom, -3, 0), MwRinkPenalties.seconds_for(rom, -3, 1),
			MwRinkPenalties.seconds_for(rom, -3, 2)], [60, 60, 120])
	assert_eq([MwRinkPenalties.seconds_for(rom, 2, 0), MwRinkPenalties.seconds_for(rom, 2, 1),
			MwRinkPenalties.seconds_for(rom, 2, 2)], [120, 180, 300])
	assert_eq(MwRinkPenalties.seconds_for(rom, 0, 1), 0)


func test_ruling() -> void:
	var p := _skater(0, 1)
	var team := sim.s.teams[0]
	assert_true(pen.rule(1, p), "code 1 counts in any phase")
	assert_eq(MwRinkPenalties.byte(team, MwRinkPenalties.PENDING), 1)
	assert_true(p.flags & MwRinkState.Player.IN_BOX != 0)
	assert_eq(MwRinkSim.s8(p.penalty), 1)
	assert_false(pen.rule(1, p), "already called")
	assert_false(pen.rule(1, _skater(0, 5)), "not the goalie")
	sim.s.phase = 3
	assert_false(pen.rule(3, _skater(0, 2)), "3 only in open play")
	sim.s.phase = 0
	assert_true(pen.rule(3, _skater(0, 2)), "3 stops play")
	assert_true(MwRinkPenalties.flags(team) & MwRinkPenalties.NOW != 0)
	assert_true(sim.s.penalty.shown(), "the penalty icon")
	sim.s.penalties = 0
	assert_false(pen.rule(-7, _skater(0, 3)), "penalties off")


func test_a_call_that_stops_play_cancels_waiting_minors() -> void:
	var a := sim.s.teams[0]
	var b := sim.s.teams[1]
	# a waiting minor of team B (as the ruling leaves it: on the screen)
	MwRinkPenalties.set_flags(b, MwRinkPenalties.DELAYED)
	_skater(1, 2).flags |= MwRinkState.Player.IN_BOX
	_skater(1, 2).penalty = (-3) & 0xFF
	MwRinkPenalties.set_byte(b, MwRinkPenalties.PENDING, 1)
	assert_true(pen.rule(3, _skater(0, 1)))
	pen.pass_start()
	assert_eq(sim.s.phase, 2, "phase 2")
	assert_eq(MwRinkPenalties.flags(a) & MwRinkPenalties.STOP, MwRinkPenalties.STOP)
	assert_eq(MwRinkPenalties.byte(b, MwRinkPenalties.PENDING), 0, "team B's minor cancelled")
	assert_eq(_skater(1, 2).flags & MwRinkState.Player.IN_BOX, 0)


func test_a_waiting_minor_stops_play_when_the_offenders_carry_the_puck() -> void:
	var a := sim.s.teams[0]
	MwRinkPenalties.set_flags(a, MwRinkPenalties.DELAYED)
	var pk := sim.s.puck
	var ours := MwRinkState.Puck.BY_TEAM_B if a.flags4 & 1 else 0
	pk.flags = MwRinkState.Puck.CARRIED | (MwRinkState.Puck.BY_TEAM_B ^ ours)   # the other team has it
	pen.pass_start()
	assert_eq(sim.s.phase, 0, "play goes on")
	pk.flags = MwRinkState.Puck.CARRIED | ours
	pen.pass_start()
	assert_eq(sim.s.phase, 2, "the offenders have the puck")


func test_the_box_ranks_counts_down_and_releases() -> void:
	var a := sim.s.teams[0]
	var p1 := _skater(0, 1)
	var p2 := _skater(0, 2)
	for p in [p1, p2]:
		p.flags |= MwRinkState.Player.IN_BOX
		MwRinkPenalties.set_byte(a, MwRinkPenalties.PENDING, MwRinkPenalties.byte(a, MwRinkPenalties.PENDING) + 1)
	p1.penalty = 2                                   # major: 120 s at 3:00
	p2.penalty = (-3) & 0xFF                         # minor: 60 s
	sim.s.clock = 150
	assert_eq(pen.put_in_box(p1), 0)
	assert_eq(pen.put_in_box(p2), 1)
	assert_eq(MwRinkPenalties.count(a), 2)
	assert_eq(MwRinkPenalties.word(a, MwRinkPenalties.entry(0) + 0xC), 120)
	assert_eq(MwRinkPenalties.byte(a, MwRinkPenalties.entry(1) + 0x13), 0, "the minor goes out first")
	assert_eq(MwRinkPenalties.byte(a, MwRinkPenalties.entry(0) + 0x13), 1)
	assert_eq(MwRinkPenalties.byte(a, MwRinkPenalties.entry(2) + 0x13), 2, "a free entry ranks last")
	assert_eq(a.stat(MwRinkPenalties.MINUTES), 3, "penalty minutes")
	assert_eq(p1.record, 0, "off the ice")
	assert_eq(MwRinkPenalties.byte(a, MwRinkPenalties.PENDING), 0, "calls served")
	# the power play: team B has one, its clock shows when the boxes are even
	pen.power_play()
	assert_true(sim.s.clock_widget & 1 != 0)
	assert_eq(sim.s.pp_seconds, 120, "even again when both are out")
	assert_eq(sim.s.teams[1].stat(MwRinkPenalties.POWER_PLAYS), 1)
	pen.count_down(60)
	assert_eq(MwRinkPenalties.count(a), 1, "the minor served")
	assert_eq(_skater(0, 2).state, 0x14, "back on, from the bench")
	assert_eq(sim.s.pp_seconds, 60, "now the major's 60 left")
	pen.power_play_goal(a)
	assert_eq(MwRinkPenalties.count(a), 0, "a power-play goal frees the last one")
	assert_eq(sim.s.clock_widget & 1, 0, "no power play")
	assert_eq(sim.s.pp_seconds, 0)


func test_the_scoreboard_serves_team_a_first() -> void:
	var b := _skater(1, 3)
	var a := _skater(0, 4)
	for p in [b, a]:
		p.flags |= MwRinkState.Player.IN_BOX
		p.penalty = (-2) & 0xFF
		var t := sim.team_of(p)
		MwRinkPenalties.set_byte(t, MwRinkPenalties.PENDING, 1)
	pen.serve_calls()
	assert_eq(MwRinkPenalties.count(sim.s.teams[0]), 1)
	assert_eq(MwRinkPenalties.count(sim.s.teams[1]), 1)
	assert_eq(sim.s.teams[0].stat(MwRinkPenalties.PENALTIES), 1)
	# the box display's copy plays (+6 bit 7)
	assert_true(MwRinkPenalties.byte(sim.s.teams[0], MwRinkPenalties.entry(0) + 6) & 0x80 != 0)
