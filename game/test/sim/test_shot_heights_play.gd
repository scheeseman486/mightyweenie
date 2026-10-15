extends "res://test/rom/rom_test_base.gd"
## The shot heights in play (owner, 2026-10-09; MwSettings.shot_heights):
## the original lifts a human's shot by the D-pad's Up / Down in the
## screen's terms, so pushing towards the net lifts a shot at the top net
## and keeps one at the bottom net on the ice; with the pads' own heights
## (MwRinkState.pad_heights) HIGH / LOW SHOT pick the lift at either end, the
## D-pad (or the stick) only aims left / right, and CPU shots stay the
## original's.

const UP := 0x01
const DOWN := 0x02
const LEFT := 0x04

var sim: MwRinkSim


## The match and its passes (plan 40: test/support/rink_rig.gd).
const RinkRig := preload("res://test/support/rink_rig.gd")

var rig: RinkRig


## A match in play (seeded) and its human skater.
func _match() -> MwRinkState.Player:
	rig = RinkRig.new()
	var s := rig.make(rom)
	sim = rig.sim
	rig.enter(5)
	rig.until_play()
	for p in s.teams[0].players:
		if p.flags & MwRinkState.Player.HUMAN:
			return p
	return null


## [param p] (attacking down when [param down]) shoots a wrist shot with
## his pad holding [param held] and its height [param h]; the puck's
## (vx, vy, vz) just after.
func _shot(p: MwRinkState.Player, held: int, h: int, down := false) -> Vector3i:
	var s := sim.s
	var team := sim.team_of(p)
	team.flags4 = (team.flags4 & ~2) | (2 if down else 0)
	p.motion.init(-40, 0, 0)
	p.state = 6
	s.puck.flags |= MwRinkState.Puck.CARRIED
	s.puck.carrier = p
	var pad := sim.human.pad_of(p, team) & 3
	s.pads_held[pad] = held
	s.pad_heights[pad] = h
	sim.puck.shoot(p)
	return Vector3i(s.puck.motion.vel[0], s.puck.motion.vel[1], s.puck.motion.vel[2])


func test_the_aim_with_heights() -> void:
	if not need_rom():
		return
	_match()
	var table := func(k: int) -> Vector2i: return sim.puck.shot_aim(k, Vector2i.ZERO)
	for k in 16:
		for h in 3:
			var aim := sim.puck.shot_aim(k, Vector2i.ZERO, h)
			assert_eq(aim.x, table.call(k & 0xC).x, "k %d: the D-pad's left / right alone aim" % k)
			assert_eq(aim.y, table.call(h).y, "k %d h %d: the lift is the height's" % [k, h])
	assert_eq(sim.puck.shot_aim(5, Vector2i.ZERO, -1), table.call(5), "-1: the original's tables")
	var left: int = table.call(4).x
	var right: int = table.call(8).x
	assert_eq(sim.puck.shot_aim(0, Vector2i(-256, 0), 2), Vector2i(left, table.call(2).y),
			"the stick full left, low: the left corner along the ice")
	assert_eq(sim.puck.shot_aim(0, Vector2i(0, 256), 1), Vector2i(table.call(0).x, table.call(1).y),
			"the stick down, high: the middle, high (the stick's up / down no longer lift)")
	assert_eq(sim.puck.shot_aim(0, Vector2i(128, 0), 0).x, right / 2, "half right: half way to the corner")
	assert_eq(sim.puck.shot_aim(0, Vector2i(-181, -181), 0).x, left * 181 / 256,
			"up-left: by its sideways push (not the corner itself, as squared out)")
	var xs := []
	for deg in range(0, 91, 15):
		var a := deg_to_rad(deg)
		xs.append(sim.puck.shot_aim(0, Vector2i(roundi(256 * sin(a)), roundi(-256 * cos(a))), 0).x)
	for i in xs.size() - 1:
		assert_lt(xs[i], xs[i + 1], "from straight up to right, every 15 degrees aims further right: %s" % [xs])
	assert_eq(xs[-1], right, "sideways: the corner")


func test_the_original_lifts_by_the_screens_up_and_down() -> void:
	if not need_rom():
		return
	var p := _match()
	var up_net := _shot(p, UP, -1, false)
	p = _match()
	var down_net := _shot(p, DOWN, -1, true)
	assert_between(up_net.z, 0x200, 0x280, "towards the top net (Up): high")
	assert_between(down_net.z, 0, 0x80, "towards the bottom net (Down): along the ice")


func test_high_and_low_at_either_end() -> void:
	if not need_rom():
		return
	for down in [false, true]:
		var towards := DOWN if down else UP
		var away := UP if down else DOWN
		for held in [0, towards, away, towards | LEFT]:
			var p := _match()
			assert_between(_shot(p, held, 1, down).z, 0x200, 0x280, "HIGH SHOT, down %s, D-pad %d" % [down, held])
			p = _match()
			assert_between(_shot(p, held, 2, down).z, 0, 0x80, "LOW SHOT, down %s, D-pad %d" % [down, held])
			p = _match()
			assert_between(_shot(p, held, 0, down).z, 0x100, 0x180, "neither, down %s, D-pad %d" % [down, held])


func test_left_and_right_still_aim() -> void:
	if not need_rom():
		return
	var p := _match()
	var plain := _shot(p, UP, 1)
	p = _match()
	var left := _shot(p, UP | LEFT, 1)
	assert_ne(Vector2i(left.x, left.y), Vector2i(plain.x, plain.y), "Left: another corner")
	p = _match()
	var same := _shot(p, DOWN, 1)
	assert_eq(same, plain, "Up or Down held: the same shot (the height decides the lift)")


func test_cpu_shots_and_the_option_off_are_the_original() -> void:
	if not need_rom():
		return
	var p := _match()
	p.flags &= ~MwRinkState.Player.HUMAN
	var cpu := _shot(p, UP, -1)
	p = _match()
	p.flags &= ~MwRinkState.Player.HUMAN
	assert_eq(_shot(p, UP, 1), cpu, "a CPU shooter: heights ignored (same draws, same shot)")
	p = _match()
	var off := _shot(p, UP, -1)
	p = _match()
	assert_eq(sim.human.height(p, sim.team_of(p)), -1, "the default: the D-pad's")
	assert_eq(_shot(p, UP, sim.human.height(p, sim.team_of(p))), off)
