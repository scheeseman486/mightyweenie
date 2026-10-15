extends RefCounted
## Plan 40 (T4 with S2): a match on the rink's own code for the tests - the
## set-up they share (a seeded state, the CPU standing still unless given
## one, the match started, a short period), its passes run by the rink's own
## pass (MwRinkUpdate.run_pass: the game's order, its draws with the phase
## handler's overlays and sprites, none while paused) and the waits.
##
##   var rig := RinkRig.new()
##   rig.make(rom)                       # stadium 3, teams 3 v 7, pad mode 0
##   rig.enter()                         # a faceoff at centre ice
##   rig.until_play()
##   rig.run(10, RinkRig.held(rig.s, 0, B))

const Idle := preload("res://test/support/idle_cpu.gd")

var s: MwRinkState
var sim: MwRinkSim
var update: MwRinkUpdate
var phases: MwRinkPhases
## The phase handler's exit of the last pass run (-1: play goes on; PAUSED,
## TEAM_INFO; a screen: it left the rink).
var left := -1


## A match at [param stadium], team [param team_a] v [param team_b], pad
## mode [param pads], [param reserves] (MwRinkMatch.start), a
## [param minutes]-minute period, its random stream from [param seed_];
## [param cpu] the CPU players' thinking (null: they stand still),
## [param live] the sound (MwRinkSim.live). The phase handler's entry is
## the test's ([method enter]).
func make(rom: PackedByteArray, stadium := 3, team_a := 3, team_b := 7, pads := 0, reserves := false,
		cpu: Object = null, live := false, minutes := 3, seed_ := 1234) -> MwRinkState:
	s = MwRinkState.new()
	s.rng = MlhRng.new(seed_)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = cpu if cpu != null else Idle.new()
	sim.live = live
	update = MwRinkUpdate.new(sim)
	phases = MwRinkPhases.new(update)
	MwRinkMatch.start(sim, stadium, team_a, team_b, pads, reserves, 2)
	s.period_minutes = minutes
	s.clock = minutes * 60
	return s


## The phase handler's entry [param screen] (5: a faceoff at centre ice);
## its exit (-1: none).
func enter(screen := 5) -> int:
	return phases.enter(screen)


## One pass of [param e] ticks (MwRinkUpdate.run_pass), [param pads] called
## after its start; the handler's exit ([member left]).
func step(pads := Callable(), e := 2) -> int:
	left = update.run_pass(e, phases, pads)
	return left


## [param passes] passes ([method step]), [param pads] called with the
## pass's number (0 the first) after each start; stops when the handler
## leaves the rink. Returns [member left].
func run(passes: int, pads := Callable(), e := 2) -> int:
	left = -1
	for i in passes:
		step(pads.bind(i) if pads.is_valid() else Callable(), e)
		if left >= 0:
			break
	return left


## Passes until the puck is in play (at most [param limit]; stops if the
## handler leaves the rink). Whether it is.
func until_play(limit := 400) -> bool:
	for i in limit:
		if s.phase == MwRinkState.PHASE_PLAY:
			return true
		if step() >= 0:
			break
	return s.phase == MwRinkState.PHASE_PLAY


## A [method run]'s pads: pad [param pad] of [param state] holding [param bits],
## newly pressed on the first pass ([param new] >= 0: those instead), its
## stick [param stick] (null: left as it is).
static func held(state: MwRinkState, pad: int, bits: int, new := -1, stick: Variant = null) -> Callable:
	return func(i: int) -> void:
		state.pads_held[pad] = bits
		state.pads_new[pad] = (bits if new < 0 else new) if i == 0 else 0
		if stick != null:
			state.pad_sticks[pad] = stick
