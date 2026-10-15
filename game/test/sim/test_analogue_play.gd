extends "res://test/rom/rom_test_base.gd"
## Analogue control in play (plan 22; MwSettings.analogue): a human's stick
## steers at its own angle, sets the pace, aims passes at its angle and shots
## between the D-pad's corners; with no stick (the option off, a key or the
## D-pad) every reader is the original's.

const RIGHT := 0x08

var sim: MwRinkSim
var update: MwRinkUpdate
var phases: MwRinkPhases


## The match and its passes (plan 40: test/support/rink_rig.gd).
const RinkRig := preload("res://test/support/rink_rig.gd")

var rig: RinkRig


func _match() -> MwRinkState:
	rig = RinkRig.new()
	var s := rig.make(rom)
	sim = rig.sim
	update = rig.update
	phases = rig.phases
	rig.enter(5)
	return s


## Passes of 2 ticks with pad 0 held [param held] and its stick [param st].
func _run(passes: int, held := 0, st := Vector2i.ZERO) -> void:
	rig.run(passes, RinkRig.held(sim.s, 0, held, -1, st))


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


## A match in play with its human skater alone in the near end, standing.
func _alone() -> MwRinkState.Player:
	var s := _match()
	_until_play()
	var p := _human(s)
	p.motion.init(-80, 220, 0)
	p.target_x = -80
	p.target_y = 220
	s.puck.flags &= ~MwRinkState.Puck.CARRIED
	s.puck.motion.init(100, -250, 0)
	return p


func test_shot_aim_without_a_stick_is_the_tables() -> void:
	if not need_rom():
		return
	_match()
	for k in 16:
		assert_eq(sim.puck.shot_aim(k, Vector2i.ZERO),
				Vector2i(MwGfx.s16(rom, MwSimPuck.AIM_X + 2 * k), MwGfx.s16(rom, MwSimPuck.AIM_LIFT + 2 * k)))


func test_shot_aim_between_the_corners() -> void:
	if not need_rom():
		return
	_match()
	var aim := func(k: int) -> Vector2i: return sim.puck.shot_aim(k, Vector2i.ZERO)
	assert_eq(sim.puck.shot_aim(0, Vector2i(-256, 0)), aim.call(4), "full left: the D-pad's left")
	assert_eq(sim.puck.shot_aim(0, Vector2i(-181, -181)), aim.call(5), "full up-left: its top corner")
	assert_eq(sim.puck.shot_aim(0, Vector2i(181, 181)), aim.call(10), "down-right")
	var mid: Vector2i = aim.call(0)
	var right: Vector2i = aim.call(8)
	var up: Vector2i = aim.call(1)
	assert_eq(sim.puck.shot_aim(0, Vector2i(128, 0)), Vector2i((mid.x + right.x) / 2, mid.y), "half right: half way")
	assert_eq(sim.puck.shot_aim(0, Vector2i(0, -128)), Vector2i(mid.x, (mid.y + up.y) / 2), "half up: half the lift")


func test_the_stick_steers_at_its_angle() -> void:
	if not need_rom():
		return
	var p := _alone()
	var s := sim.s
	var at := p.motion.pixels()
	sim.human.target(p, RIGHT)
	assert_eq(Vector2i(p.target_x - at.x, p.target_y - at.y), sim.polar(0, 0x64), "the D-pad: right")
	var st := Vector2i(222, 128)                    # 30 degrees below right
	s.pad_sticks[0] = st
	sim.human.target(p, RIGHT)
	var a := sim.human.stick_angle(st)
	assert_between(a, 0x13, 0x17, "about 30 degrees")
	assert_eq(Vector2i(p.target_x - at.x, p.target_y - at.y), sim.polar(a, 0x64), "the stick's angle")
	p.flags &= ~MwRinkState.Player.HUMAN
	assert_eq(sim.human.stick(p, s.teams[0]), Vector2i.ZERO, "a CPU player has none")


func test_full_travel_plays_as_the_d_pad_less_goes_slower() -> void:
	if not need_rom():
		return
	var runs := []
	for st in [Vector2i.ZERO, Vector2i(256, 0), Vector2i(48, 0)]:
		var p := _alone()
		_run(30, RIGHT, st)
		runs.append([p.motion.pixels(), sim.velocity(p).x])
	assert_eq(runs[1], runs[0], "full travel to the right: exactly the D-pad's right")
	assert_lt(runs[2][0].x, runs[0][0].x - 10, "a little travel: not as far")
	assert_lt(runs[2][1], runs[0][1], "and slower")
	assert_gt(runs[2][0].x, -80 + 10, "but on the way")


func test_a_pass_aims_at_the_stick() -> void:
	if not need_rom():
		return
	var p := _alone()
	var s := sim.s
	s.pads_held[0] = 0x02                          # the D-pad's down
	assert_eq(sim.puck.aim_pass(p), 0x40, "the D-pad")
	s.pad_sticks[0] = Vector2i(128, -222)
	assert_eq(sim.puck.aim_pass(p), sim.human.stick_angle(Vector2i(128, -222)), "the stick's angle")
	var player: MwRinkState.Player = s.teams[0].goalie()
	player.flags |= MwRinkState.Player.HUMAN
	player.motion.init(0, -250, 0)                      # his net at the top
	s.pads_held[0] = 0
	s.pad_sticks[0] = Vector2i(-181, -181)
	assert_eq(sim.puck.aim_pass(player), 0x80, "a goalie: not towards his own end - across")
	s.pad_sticks[0] = Vector2i(20, -250)
	player.angle = 0x55
	assert_eq(sim.puck.aim_pass(player), 0x55, "nearly straight at his end: his facing, as the D-pad")
