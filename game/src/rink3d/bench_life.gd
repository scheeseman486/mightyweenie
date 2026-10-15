class_name MwBenchLife
extends RefCounted
## The benches' life (plan 32, docs/rink3d.md, Benches; owner: the benches
## filled with each team's reserves, animated, watching and getting excited):
## who stands on each team's bench and in its penalty box, where, who is on
## his way out, and what has just happened to cheer or sulk about. A small
## model stepped with the game's passes ([method step], MwRinkUpdate: live
## play only, beside the crowd's life) that reads the game's state and never
## writes it; what it is at a pass ([method snapshot]: plain data, a few
## hundred bytes) is all MwBench3D needs to draw every figure, so a replay
## keeps it with each frame (MwReplay3D) and shows the benches as they were.
## Repeatable: the same seed and the same passes give the same benches.
##
## * On the bench: a team's roster players alive, not on the ice and not in
##   the box (18 at a match's start). Each keeps his place; newcomers take
##   the free place farthest from the others (the bench filled evenly to
##   its ends); the dead leave gaps, so the bench
##   thins out as the team's players die and their reserves go on.
## * Next up: the players the game would send on if a player of each
##   position died now (its own pick, `$F72C`, read: MwSimPlayers
##   .best_substitute) wait in the recess by the way out, the rest in the
##   pen; they change places on foot as the picks change.
## * Called: when a player starts dying (state 18, killed, or 19, fallen
##   through the ice) the game's pick for his position walks into the west
##   arch, timed to be in its dark as the death animation ends and the game
##   sends him on from the original's bench door, in the east arch (where
##   MwBench3D lets him come out of the dark). If the game picks someone else
##   after all, that one goes, quickly, and the first walks back.
## * The box: each team's penalised players sit in its box's seats (its
##   entries, MwRinkPenalties); a few clock seconds before his time is up
##   he gets up and walks into the east arch, reaching its dark as the game
##   lets him out at the door. A power-play goal's early release is not
##   foreseen: he goes quickly then.
## * Anyone who leaves the bench or the box any other way goes into the
##   arch quickly; under a fade (a rink entry: the Reserves line changes,
##   the period's) changes are made at once.
## * Cues: each team's last goal and its last kill of the other's players;
##   the crowd's liveliness (MwCrowdLife); the puck, which each figure
##   watches (his [code]look[/code], turning with a little hysteresis).
## Presentation only: nothing of the game's state or random numbers.

## A figure's state ([member figs]).
enum { SIT, MOVE, OUT }
## Snapshot figures: [team, slot, record, place, from x, from y, progress,
## look, since, kind] (a PackedFloat32Array, this stride).
const FIG := 10
## Walking speeds (px a tick): changing places on the bench; walking back
## in; going out unforeseen (quickly).
const MOVE_SPEED := 1.0
const IN_SPEED := 1.5
const QUICK_SPEED := 3.0
## The fastest a called player goes out (px a tick).
const OUT_SPEED := 3.0
## Ticks after the game takes him that a called player reaches the dark (the
## game's player takes about as long to come out of the east arch's).
const OUT_LAG := 14
## A figure in an arch who is still on the bench by the game after this
## long (ticks) walks back in (the game picked someone else).
const OUT_GRACE := 90
## The box: he gets up when his release is this near (ticks, at this pace).
const BOX_SPEED := 1.5
## A look turns once the puck is this far (radians) past the half-way to
## the next direction.
const LOOK_HYSTERESIS := 0.17
const STATE_KILLED := 0x12
const STATE_FELL := 0x13

## The match's seed (the crowd's: each figure's own moments in MwBench3D).
var bench_seed := 0
## The model's clock (ticks).
var ticks := 0
## Figures by "team.slot": {team, slot, record, place, from: Vector2,
## p (0..1 along the way from [code]from[/code] to the place), rate (p a
## tick), len (the way's length, px), look, since (tick the walk began),
## kind, out_at (tick he reached an arch), box (in the box, not on the
## bench)}.
var figs := {}
## Each team's last goal and last kill of the other's players (ticks; -1 none).
var goal_at := PackedInt32Array([-1, -1])
var kill_at := PackedInt32Array([-1, -1])
## The crowd's liveliness (MwCrowdLife.life) at the last pass.
var life := 0.0
var _score := Vector2i.ZERO
var _dying := {}                 # "team.index" -> record of a player seen dying
var _started := false


func _init(seed_ := 0) -> void:
	bench_seed = seed_


## A pass of [param e] ticks of [param sim]'s match (its state read only).
func step(e: int, sim: MwRinkSim) -> void:
	var s := sim.s
	ticks += e
	life = s.crowd_life.life if s.crowd_life != null else 0.0
	var at_once := s.first_pass != 0 or not _started   # under the fade: no walking
	_started = true
	var score := Vector2i(s.teams[0].score, s.teams[1].score)
	for t in 2:
		if score[t] > _score[t]:
			goal_at[t] = ticks
	_score = score
	var puck := s.puck.motion.pixels()
	for t in 2:
		_team(t, sim, at_once)
	for key: String in figs.keys():
		var fg: Dictionary = figs[key]
		if fg["p"] < 1.0:
			fg["p"] = minf(1.0, fg["p"] + fg["rate"] * e)
			if fg["p"] >= 1.0:
				if fg["kind"] == OUT:
					fg["out_at"] = ticks
				else:
					fg["kind"] = SIT
		if fg["kind"] == SIT:
			fg["look"] = _look(fg, Vector2(puck.x, puck.y))


func _team(t: int, sim: MwRinkSim, at_once: bool) -> void:
	var s := sim.s
	var team := s.teams[t]
	var roster := PackedInt32Array()
	for i in 24:
		roster.append(MwTeams.roster_record(sim.rom, team.record, i) if team.record != 0 else 0)
	var on_ice := {}
	for p in team.players:
		if p.present:
			on_ice[p.slot] = true
	var boxed := {}                  # slot -> entry
	for i in 3:
		var at := MwRinkPenalties.entry(i)
		if MwRinkPenalties.byte(team, at + 0x10) != 0:
			boxed[MwRinkPenalties.byte(team, at + 0xE)] = i
	var bench := {}
	for i in 24:
		if roster[i] != 0 and team.health[i] & 0x7FFFFFFF != 0 and not on_ice.has(i) and not boxed.has(i):
			bench[i] = true
	# deaths: the game's pick walks out
	var dying_now := {}
	for p in team.players:
		if not p.present or (p.state != STATE_KILLED and p.state != STATE_FELL):
			continue
		var dk := "%d.%d" % [t, p.index]
		dying_now[dk] = p.record
		if _dying.get(dk, 0) == p.record:
			continue
		kill_at[1 - t] = ticks
		var pick := sim.players.best_substitute(team, p.position)
		var fk := fig_key(t, pick.x)
		if pick.y != 0 and bench.has(pick.x) and figs.has(fk) and figs[fk]["kind"] != OUT:
			_go_out(figs[fk], MwBench3D.WEST_EXIT, _death_left(sim, p) + OUT_LAG, OUT_SPEED)
	for dk: String in _dying.keys():
		if dk.begins_with("%d." % t) and not dying_now.has(dk):
			_dying.erase(dk)
	for dk: String in dying_now:
		_dying[dk] = dying_now[dk]
	# who left: out through the arch (at once under a fade)
	for key: String in figs.keys():
		var fg: Dictionary = figs[key]
		if fg["team"] != t:
			continue
		var slot: int = fg["slot"]
		var in_box: bool = fg["box"]
		var still := boxed.has(slot) if in_box else bench.has(slot)
		if fg["kind"] == OUT:
			if not still and (fg["p"] >= 1.0 or at_once):
				figs.erase(key)
			elif not still:
				fg["rate"] = maxf(fg["rate"], QUICK_SPEED / maxf(fg["len"], 1.0))   # gone on: hurry
			elif fg["p"] >= 1.0 and not in_box and ticks - int(fg["out_at"]) >= OUT_GRACE:
				_move(fg, _free_place(t, slot, false, fg), IN_SPEED)      # still on the bench: back in
		elif not still:
			if at_once:
				figs.erase(key)
			else:
				_go_out(fg, MwBench3D.EAST_EXIT if in_box else MwBench3D.WEST_EXIT, 0, QUICK_SPEED)
	# the box: its seats; up and out as his time runs out
	for slot: int in boxed:
		var i: int = boxed[slot]
		var key := fig_key(t, slot)
		if not figs.has(key) or not figs[key]["box"] or (at_once and figs[key]["kind"] == OUT):
			figs[key] = _new_fig(t, slot, roster[slot], MwBench3D.BOX + i)
		var fg: Dictionary = figs[key]
		var left := _box_left(s, team, i)
		if left < 0:
			if fg["kind"] == OUT:
				fg["rate"] = 0.0                  # the clock stopped: he waits
			continue
		var way := MwBench3D.length(MwBench3D.route(t, _now(fg), MwBench3D.place_at(t, MwBench3D.EAST_EXIT)))
		if fg["kind"] != OUT and left <= way / BOX_SPEED:
			_go_out(fg, MwBench3D.EAST_EXIT, left + OUT_LAG, OUT_SPEED)
		elif fg["kind"] == OUT and fg["p"] < 1.0:
			fg["rate"] = (1.0 - fg["p"]) / maxf(left + OUT_LAG, 1.0)
	# the bench: newcomers to free places; next up by the way out
	var next := {}
	# (plan 42, second round: the six picks from one sweep of the roster -
	# MwSimPlayers.best_substitutes: positions 0-4 and the next goalie up)
	var picks := sim.players.best_substitutes(team, _goalie_on(team))
	for pos in 5:
		var pick := picks[pos]
		if pick.y != 0 and bench.has(pick.x):
			next[pick.x] = true
	var g := picks[5].x if picks[5].y != 0 else -1
	if bench.has(g):
		next[g] = true
	for slot: int in bench:
		var key := fig_key(t, slot)
		if not figs.has(key):
			figs[key] = _new_fig(t, slot, roster[slot], _free_place(t, slot, next.has(slot), null))
			continue
		var fg: Dictionary = figs[key]
		if fg["kind"] == OUT or fg["box"]:
			continue
		var in_recess: bool = fg["place"] >= MwBench3D.RECESS \
				and fg["place"] < MwBench3D.RECESS + MwBench3D.RECESS_PLACES
		if in_recess != next.has(slot):
			var to := _free_place(t, slot, next.has(slot), fg)
			var to_recess := to >= MwBench3D.RECESS and to < MwBench3D.RECESS + MwBench3D.RECESS_PLACES
			if to_recess != in_recess:
				if at_once:
					fg["place"] = to
					fg["kind"] = SIT
					fg["p"] = 1.0
				else:
					_move(fg, to, MOVE_SPEED)


## The key of team [param t]'s roster slot [param slot]'s figure in
## [member figs] ("1.7").
static func fig_key(t: int, slot: int) -> String:
	if t >= 0 and t < 2 and slot >= 0 and slot < 24:
		if _fig_keys.is_empty():
			for tt in 2:
				for ss in 24:
					_fig_keys.append("%d.%d" % [tt, ss])
		return _fig_keys[t * 24 + slot]           # (plan 42: spelled once)
	return "%d.%d" % [t, slot]


static var _fig_keys := PackedStringArray()


## The goalie the game would send on were [param team]'s goalie to die
## now (-1 none): its pick (`$F72C`, MwSimPlayers.best_substitute) leaving
## out the goalie on the ice, whom the pick itself only leaves out once he
## is dead.
func next_goalie(sim: MwRinkSim, team: MwRinkState.Team) -> int:
	var pick := sim.players.best_substitute(team, 5, _goalie_on(team))
	return pick.x if pick.y != 0 else -1


## The roster slot of [param team]'s goalie on the ice (-1: none).
static func _goalie_on(team: MwRinkState.Team) -> int:
	if team.players.size() > 5 and team.players[5].present:
		return team.players[5].slot
	return -1


## Ticks until the dying [param p]'s animation ends and the game sends his
## substitute on (state 18: the death animation, then the corpse; 19: the
## fall, then one more pass).
func _death_left(_sim: MwRinkSim, p: MwRinkState.Player) -> int:
	var anim := p.anim
	var full := anim.count << 8
	var left := ceili(float(maxi(full - anim.position, 0)) / maxi(anim.speed, 1))
	return left + (6 if p.state == STATE_FELL else 2)


## Ticks until box entry [param i] of [param team] frees its player at the
## clock's pace (-1: the clock is stopped).
func _box_left(s: MwRinkState, team: MwRinkState.Team, i: int) -> int:
	if not s.clock_flags & 1:
		return -1
	var secs := MwRinkSim.s16(MwRinkPenalties.word(team, MwRinkPenalties.entry(i) + 0xC))
	var into := clampi(MwRinkSim.s16((s.tick - s.clock_ref) & 0xFFFF), 0, s.clock_rate)
	return maxi((secs - 1) * s.clock_rate + (s.clock_rate - into), 0)


func _new_fig(t: int, slot: int, record: int, place: int) -> Dictionary:
	return {"team": t, "slot": slot, "record": record, "place": place,
			"from": MwBench3D.place_at(t, place), "p": 1.0, "rate": 0.0,
			"look": 6 if place >= MwBench3D.BOX else 2, "since": ticks, "kind": SIT, "out_at": 0,
			"box": place >= MwBench3D.BOX, "len": 0.0}


## Where [param fg] is now (rink px).
func _now(fg: Dictionary) -> Vector2:
	var to := MwBench3D.place_at(fg["team"], fg["place"])
	if fg["p"] >= 1.0:
		return to
	return MwBench3D.along(MwBench3D.route(fg["team"], fg["from"], to), fg["p"])[0]


## [param fg] walks to [param place] at [param speed] (px a tick).
func _move(fg: Dictionary, place: int, speed: float) -> void:
	var from := _now(fg)
	fg["from"] = from
	fg["place"] = place
	fg["p"] = 0.0
	fg["since"] = ticks
	fg["kind"] = MOVE
	var d := MwBench3D.length(MwBench3D.route(fg["team"], from, MwBench3D.place_at(fg["team"], place)))
	fg["len"] = d
	fg["rate"] = speed / maxf(d, 1.0)
	if d < 0.5:
		fg["p"] = 1.0
		fg["kind"] = SIT


## [param fg] walks out to [param exit], reaching it [param in_ticks] from
## now (0: at [param fastest]), never faster than [param fastest] (px a tick).
func _go_out(fg: Dictionary, exit: int, in_ticks: int, fastest: float) -> void:
	_move(fg, exit, fastest)
	fg["kind"] = OUT
	fg["out_at"] = 0
	fg["rate"] = 1.0 / maxf(maxf(float(in_ticks), fg["len"] / fastest), 1.0)


## The free place for [param slot] of team [param t] (in the recess if
## [param recess], else the pen; the other if that is full): the one
## farthest from the places taken (the first such nearest the way out), or
## for a figure [param fg] already on the bench the nearest to him.
func _free_place(t: int, slot: int, recess: bool, fg: Variant) -> int:
	var taken := {}
	for key: String in figs:
		var o: Dictionary = figs[key]
		if o["team"] == t and o["slot"] != slot and o["kind"] != OUT and not o["box"]:
			taken[o["place"]] = true
	var kinds := [MwBench3D.RECESS, MwBench3D.PEN] if recess else [MwBench3D.PEN, MwBench3D.RECESS]
	for base: int in kinds:
		var n: int = MwBench3D.RECESS_PLACES if base == MwBench3D.RECESS else MwBench3D.PEN_PLACES
		var best := -1
		var best_d := INF
		for k in n:
			var place := base + k
			if taken.has(place):
				continue
			var at := MwBench3D.place_at(t, place)
			var d := 0.0
			if fg != null:
				d = _now(fg).distance_to(at)
			else:
				var room := 1e6                      # to the nearest taken place
				for o: int in taken:
					room = minf(room, at.distance_to(MwBench3D.place_at(t, o)))
				d = -room
			if d < best_d:
				best_d = d
				best = place
		if best >= 0:
			return best
	return MwBench3D.PEN + MwBench3D.PEN_PLACES - 1     # (never: 21 places for 18 players)


## [param fg]'s look at the puck at [param puck] (rink px): the variant
## towards it, changed only once the puck is well past the half-way to the
## next one.
func _look(fg: Dictionary, puck: Vector2) -> int:
	var d := puck - MwBench3D.place_at(fg["team"], fg["place"])
	if d.length() < 1.0:
		return fg["look"]
	var ang := atan2(d.x, -d.y)
	var cur: int = fg["look"]
	var off := angle_difference(cur * PI / 4.0, ang)
	if absf(off) < PI / 8.0 + LOOK_HYSTERESIS:
		return cur
	return MwBench3D.variant_of(d)


## What the benches are now (plain data: a replay keeps it with each
## frame): {seed, ticks, goal_at, kill_at, life, figs (PackedFloat32Array,
## [constant FIG] numbers a figure, in key order)}.
func snapshot() -> Dictionary:
	var f := PackedFloat32Array()
	var keys := figs.keys()
	keys.sort()
	for key: String in keys:
		var fg: Dictionary = figs[key]
		var from: Vector2 = fg["from"]
		f.append_array(PackedFloat32Array([fg["team"], fg["slot"], fg["record"], fg["place"], from.x, from.y,
				fg["p"], fg["look"], fg["since"], fg["kind"]]))
	return {"seed": bench_seed, "ticks": ticks, "goal_at": [goal_at[0], goal_at[1]],
			"kill_at": [kill_at[0], kill_at[1]], "life": life, "figs": f}

