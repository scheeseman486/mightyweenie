extends "res://test/rom/rom_test_base.gd"
## Live play without the original to compare against: a match set up and
## lined up (MwRinkMatch), the match flow (MwRinkPhases: faceoff sequence,
## goal, the puck rules' goalie hold), human control through the pad bytes
## and the separate verbs (MwHumanControl), and what leaving the rink does
## (`rink_exit`).

const DOWN := 0x02
const LEFT := 0x04
const C := 0x20

var sim: MwRinkSim
var update: MwRinkUpdate
var phases: MwRinkPhases
## The screen the phase handler left for in the last [method _run] (-1 none).
var left := -1


## CPU players that stay put (these tests are about human control and the
## rules; the AI has its own checks: `tools/bin/sim-check --think`, `--ai`).
class Idle:
	func think(_sim: MwRinkSim, _p: MwRinkState.Player, _team: MwRinkState.Team, _other: MwRinkState.Team) -> void:
		pass


func _match(pads := 0) -> MwRinkState:
	var s := MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = Idle.new()
	update = MwRinkUpdate.new(sim)
	phases = MwRinkPhases.new(update)
	MwRinkMatch.start(sim, 3, 3, 7, pads, false, 2)
	s.period_minutes = 3
	s.clock = 180
	assert_eq(phases.enter(5), -1, "a faceoff at centre ice")
	return s


## Passes of 2 ticks with pad 0 held [param held] (newly pressed on the
## first); stops when the phase handler leaves the rink ([member left]).
func _run(passes: int, held := 0, new := -1) -> void:
	left = -1
	for i in passes:
		sim.s.tick += 2
		update.pass_start(2)
		sim.s.pads_held[0] = held
		sim.s.pads_new[0] = (held if new < 0 else new) if i == 0 else 0
		sim.run(2)
		update.after_segment(2)
		left = phases.pass_end(2)
		if left >= 0:
			return
		update.draws([], MwRinkPhases.RULES_DRAWN, phases.overlays)


func _until_play() -> void:
	for i in 400:
		if sim.s.phase == MwRinkState.PHASE_PLAY:
			return
		_run(1)


func _human(s: MwRinkState) -> MwRinkState.Player:
	for p in s.teams[0].players:
		if p.flags & MwRinkState.Player.HUMAN:
			return p
	return null


## [param p] alone in the near end, standing; the puck loose far away.
func _alone(p: MwRinkState.Player) -> void:
	p.motion.init(-80, 220, 0)
	p.target_x = -80
	p.target_y = 220
	var pk := sim.s.puck
	pk.flags &= ~MwRinkState.Puck.CARRIED
	pk.motion.init(100, -250, 0)


func _give(p: MwRinkState.Player) -> void:
	var pk := sim.s.puck
	pk.flags &= ~(MwRinkState.Puck.BY_TEAM_B | MwRinkState.Puck.SHOT | MwRinkState.Puck.PASS)
	if p.team == 1:
		pk.flags |= MwRinkState.Puck.BY_TEAM_B
	var at := p.motion.pixels()
	pk.motion.init(at.x, at.y, 0)
	sim.puck.possess(p)


func test_a_match_lines_up_and_the_faceoff_drops() -> void:
	if not need_rom():
		return
	var s := _match()
	var n := 0
	for t in s.teams:
		for p in t.players:
			n += int(p.present)
	assert_eq(n, 12, "six a side")
	assert_eq(s.teams[0].pads, [0, 0xFF], "P1 controls team A")
	assert_not_null(_human(s), "a human skater on team A")
	assert_eq(s.phase, MwRinkState.PHASE_FACEOFF)
	assert_ne(s.puck.flags & MwRinkState.Puck.HIDDEN, 0, "puck up above the circle")
	assert_eq(s.puck.motion.pixels(), Vector3i(0, 0, 112))
	_run(45)
	assert_eq(s.faceoff_step, 1, "the period panel for 90 ticks")
	assert_ne(s.puck.flags & MwRinkState.Puck.HIDDEN, 0)
	_run(1)
	assert_eq(s.faceoff_step, 2, "the panel goes")
	_run(1)
	assert_eq(s.faceoff_step, 3, "the referee shown, the clock widget up")
	assert_ne(s.clock_widget & 2, 0)
	for i in 100:
		if s.puck.flags & MwRinkState.Puck.HIDDEN == 0:
			break
		_run(1)
	assert_eq(s.faceoff_step, 5, "dropped when the referee's arm is down")
	_until_play()
	assert_eq(s.phase, MwRinkState.PHASE_PLAY, "play starts when it lands")
	assert_eq(s.puck.motion.pos[2], 0)
	assert_eq(s.faceoff_step, 0xFF)
	assert_eq(s.clock_flags & 1, 1, "the clock runs")


func test_the_human_skates_where_the_pad_points() -> void:
	if not need_rom():
		return
	var s := _match()
	_until_play()
	var p := _human(s)
	var y0 := p.motion.pixels().y
	_run(20, DOWN)
	assert_gt(p.motion.pixels().y, y0 + 10, "down the ice")
	var x0 := p.motion.pixels().x
	_run(20, LEFT)
	assert_lt(p.motion.pixels().x, x0 - 10, "to the left")


func test_c_tapped_shoots_a_wrist_shot_held_a_slap_shot() -> void:
	if not need_rom():
		return
	var s := _match()
	_until_play()
	var p := _human(s)
	_alone(p)
	_give(p)
	_run(1, C)
	assert_ne(s.hold_left[0], 0, "the hold timer runs")
	assert_eq(p.state, 0, "nothing yet")
	_run(1, 0)
	assert_eq(p.state, 6, "released early: wrist shot")
	s = _match()
	_until_play()
	p = _human(s)
	_alone(p)
	_give(p)
	var ticks := 0
	_run(1, C)
	while p.state == 0 and ticks < 120:
		_run(1, C, 0)
		ticks += 2
	assert_eq(p.state, 5, "held: slap shot")
	assert_gt(ticks, 4, "when the hold time is up")


func test_a_verb_bound_alone_acts_on_its_press() -> void:
	if not need_rom():
		return
	var s := _match()
	_until_play()
	var p := _human(s)
	_alone(p)
	_give(p)
	sim.human.direct[0] = ["slap_shot"]
	_run(1)
	sim.human.direct[0] = []
	assert_eq(p.state, 5, "slap shot at once")
	assert_eq(s.hold_left[0], 0, "no timer")
	s = _match()
	_until_play()
	p = _human(s)
	_alone(p)
	sim.human.direct[0] = ["change_player"]
	_run(1)
	sim.human.direct[0] = []
	assert_eq(p.flags & MwRinkState.Player.HUMAN, 0, "control left him")
	assert_not_null(_human(s), "for a team-mate")


func test_a_goal_leaves_for_the_scoreboard_with_the_faceoff_at_centre() -> void:
	if not need_rom():
		return
	var s := _match()
	_until_play()
	s.phase = 3
	s.scoring = 0xFFFFB8AC                       # team B (CPU): no coach speech
	s.puck.motion.pos[1] = -0x15100              # in the top net
	_run(400)
	assert_eq(left, 12, "the goal scoreboard")
	assert_eq(s.goal_message, 0xFFFF, "the goal sequence ran")
	assert_eq(s.faceoff_spot, 0, "the next faceoff at centre ice")
	assert_eq(s.clock_flags & 1, 0, "the clock stopped")
	assert_eq(phases.enter(5), -1)
	assert_eq(s.phase, MwRinkState.PHASE_FACEOFF, "lined up at centre ice")


func test_a_goalie_holding_the_puck_15_clock_seconds_stops_play() -> void:
	if not need_rom():
		return
	var s := _match()
	_until_play()
	var g := s.teams[1].players[5]
	_give(g)
	var clock := s.clock
	_run(200)
	assert_eq(s.phase, 8, "a stoppage")
	assert_eq(s.rule_hold, 0xFFFF, "the goalie hold (FACE OFF)")
	assert_eq(clock - s.clock, 15, "15 clock seconds")
	_run(200)
	assert_eq(left, 5, "a faceoff")
	var at := s.rule_spot                       # where the puck was held
	var want: int = [[1, 3], [6, 8]][1 if at.y >= 0 else 0][1 if at.x >= 0 else 0]
	assert_eq(s.faceoff_spot, want, "at the deep circle of the goalie's end, on the puck's side")


func test_leaving_the_rink_takes_weapons_back() -> void:
	if not need_rom():
		return
	var s := _match()
	var p := s.teams[0].players[1]
	p.flags &= ~MwRinkState.Player.ENFORCER
	p.weapon = 2
	s.teams[0].flags4 |= 0x80
	MwRinkMatch.rink_exit(sim, 7)
	assert_eq(p.weapon, 2, "not for the instant replay")
	MwRinkMatch.rink_exit(sim, 12)
	assert_eq(p.weapon, -1)
	assert_eq(s.teams[0].flags4 & 0x80, 0, "armed force over")


func test_a_period_change_switches_ends() -> void:
	if not need_rom():
		return
	var s := _match()
	var a := s.teams[0].flags4 & 2
	var b := s.teams[1].flags4 & 2
	s.teams[0].health[3] = 0x123456
	MwRinkMatch.period_end(sim)
	assert_ne(s.teams[0].flags4 & 2, a)
	assert_ne(s.teams[1].flags4 & 2, b)
	assert_eq(s.teams[0].health[3] >> 16, 0x80, "rested")
