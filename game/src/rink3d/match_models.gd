class_name MwMatchModels
extends RefCounted
## Plan 40 (S3): the match's models - the port's own presentation the
## rink's state carries beside the original's RAM: the crowd's life (plan
## 31, [member MwRinkState.crowd_life]), the benches' and boxes' figures
## (plan 32, [member MwRinkState.bench_life]) and the arena's paint (plan
## 37, [member MwRinkState.splatter]). The one place that knows them
## together:
## * [method make]: a match's, as the rink makes them (one seed; the 3D
##   opening's crowd and paint handed over, going on);
## * [method step]: a pass's step of each, in order - the benches read the
##   crowd's life - from the draw pass (MwRinkUpdate.crowd_sound), whatever
##   runs the pass;
## * [method frame_parts]: their part of a 3D frame (the live view's,
##   the replays' - MwReplay3D.frame -, the opening's).
## What the online hash and the resync snapshot do with each is
## MwRinkState.PORT_FIELDS's. A new model: a field there and a line in each
## of these.

## Their keys in a 3D frame (MwRinkView3D.present_frame; the saved
## replays' side records keep them: never renamed).
const CROWD := "crowd"
const BENCH := "bench"
const SPLAT := "splat"


## The models of [param s] that are not there yet, as the rink's entry makes
## them: the crowd from [param session]'s crowd stream (the same on every
## machine; 1 without a session), the benches from the crowd's seed, the
## paint (MwSettings.splatter) from it too - the attract demo's its own,
## the same every time (MwSplatter.seed_for). [param handed]: the 3D
## opening's ("crowd_life", "splatter": the matchup's exit data) go on.
static func make(s: MwRinkState, session: MwSession, handed := {}) -> void:
	if s.crowd_life == null:
		var life: Variant = handed.get("crowd_life")
		s.crowd_life = life if life is MwCrowdLife else MwCrowdLife.new(
				session.port_seed(MwSession.STREAM_CROWD) if session else 1)
	if s.bench_life == null:
		s.bench_life = MwBenchLife.new(s.crowd_life.crowd_seed)
	if s.splatter == null and MwSettings.splatter:
		var splat: Variant = handed.get("splatter")
		s.splatter = splat if splat is MwSplatter else MwSplatter.new(
				MwSplatter.seed_for(session != null and session.attract, s.crowd_life.crowd_seed))


## A pass of [param e] ticks for each model of [param sim]'s state: the
## crowd at the game's crowd level, the score and whether play is on, then
## the benches, then the paint.
static func step(sim: MwRinkSim, e: int) -> void:
	var s := sim.s
	if s.crowd_life != null:
		s.crowd_life.step(e, s.crowd & 0xFFFF, Vector2i(s.teams[0].score, s.teams[1].score),
				s.phase == MwRinkState.PHASE_PLAY)
	if s.bench_life != null:
		s.bench_life.step(e, sim)
	if s.splatter != null:
		s.splatter.step(e, sim)


## The models' part of a 3D frame (any of them null: left out): their
## snapshots; for a replay's frame ([param for_replay]) the paint's inputs
## since the frame before as well ("in": MwSplatter.take_inputs - taken,
## so only the replay's frame takes them).
static func frame_parts(crowd: MwCrowdLife, bench: MwBenchLife, splat: MwSplatter, for_replay: bool) -> Dictionary:
	var f := {}
	if crowd != null:
		f[CROWD] = crowd.snapshot()
	if bench != null:
		f[BENCH] = bench.snapshot()
	if splat != null:
		var sp := splat.snapshot()
		if for_replay:
			sp["in"] = splat.take_inputs()
		f[SPLAT] = sp
	return f
