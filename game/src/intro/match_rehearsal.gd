class_name MwMatchRehearsal
extends RefCounted
## The rink's entry for a new match, rehearsed (plan 33, docs/rink3d.md,
## The match's opening): what MwRink._live_entry will make of the session
## (its own MwRink.enter_match, on a state of its own) -
## the matchup's set-up (`$B2B0`: the clock, the stadium, both teams and
## their first six on the ice), the period start's faceoff (`$AB2C`: both
## teams lined up at centre ice, `$3A28`), the camera there - run on a copy
## of the session's main random stream, without sound, nothing kept. The
## 3D intro (MwMatchIntro3D) reads it to know who starts, where each one
## will stand and face, where the camera will be, the stadium's nets, lamps
## and hazards, and each reserve's place on the benches (MwBenchLife), so
## its end is the rink's first frame. Presentation only: the session (its
## random numbers above all) is never touched; test_match_rehearsal checks
## the rink's real entry is this one.

## The entered state (a new match's period start), its sim, the first
## frame's draw (MwRinkDraw3D: the items MwRink presents first) and the
## benches as the rink's entry places them (MwBenchLife.snapshot).
var state: MwRinkState
var sim: MwRinkSim
var draw: MwRinkDraw3D
var bench := {}


## Plan 45: the rehearsal's sim disposed as the rehearsal goes (its cycle
## would keep the rehearsed state).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and sim != null:
		sim.dispose()


## The rehearsal of a new match for setup [param su] (the session's; a copy
## is used), from random stream state [param rng_state] (the session's
## main stream now) and the session's playoff run [param playoffs].
static func run(rom: PackedByteArray, su: MwMatchSetup, rng_state: int,
		playoffs: MwPlayoffs = null) -> MwMatchRehearsal:
	var rehearsal := MwMatchRehearsal.new()
	var s := MwRinkState.new()
	s.rng = MlhRng.new(rng_state)
	var rehearsal_sim := MwRinkSim.new(rom, s)
	rehearsal_sim.cpu = MwRinkAI.new()
	var up := MwRinkUpdate.new(rehearsal_sim)
	var phases := MwRinkPhases.new(up)
	MwRinkMatch.boot_icons(rehearsal_sim)              # (the icons draw nothing here)
	s.bench_life = MwBenchLife.new(0)
	var setup_copy := su.copy()
	setup_copy.take_extended_rules()                   # (plan 44: as the rink's entry will)
	MwRink.enter_match(rehearsal_sim, phases, setup_copy, true, playoffs, false, 4)
	rehearsal.state = s
	rehearsal.sim = rehearsal_sim
	rehearsal.draw = MwRinkDraw3D.new(rom)
	rehearsal.draw.build(s)
	rehearsal.bench = s.bench_life.snapshot()
	return rehearsal


## The players on the ice at the period start: [{team, index, slot,
## record, at: Vector2 (rink px), variant, key}] (key: the first frame's
## body item's).
func starters() -> Array:
	var out := []
	for t in 2:
		var team := state.teams[t]
		for p in team.players:
			if not p.present:
				continue
			var px := p.motion.pixels()
			out.append({"team": t, "index": p.index, "slot": p.slot, "record": p.record,
					"at": Vector2(px.x, px.y), "variant": p.anim.variant,
					"key": MwRinkDraw3D.subject_key(t, team.players.find(p), p.record) + "/body"})
	return out


## Every roster player alive of team [param t]: [{slot, record}] in roster
## order (the dead of a playoff run are not).
func roster(t: int) -> Array:
	var out := []
	var team := state.teams[t]
	for i in 24:
		var rec := MwTeams.roster_record(sim.rom, team.record, i)
		if rec != 0 and team.health[i] & 0x7FFFFFFF != 0:
			out.append({"slot": i, "record": rec})
	return out


## The first frame's items that are not players' (nets, lamps, the
## stadium's objects, the referee, the puck...): what stands on the rink
## before anyone skates out, and at the end.
func scenery() -> Array:
	var out := []
	for it: Dictionary in draw.items:
		var key: String = it.get("key", "")
		if key.begins_with("t") or int(it["place"]) == MwRinkDraw3D.SCREEN:
			continue
		out.append(it)
	return out
