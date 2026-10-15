class_name MwIntroCast
extends RefCounted
## The players at the match's opening (plan 33, docs/rink3d.md, The match's
## opening; owner: the players come on one after another, dance and show off
## to the crowd, then take their positions - the reserves leaving through the
## rink's right side, the rest to their start positions). Every player of
## both rosters still alive, drawn as the benches' figures are
## (MwBench3D.figure_item: their team's colours, their species' animations,
## turning with the camera, fading in the arches' dark), moved by a model of
## its own (its own seeded random numbers, never the game's), stepped in
## ticks.
##
## * Entrances: from [constant ENTER_AT] one every [constant ENTER_EVERY]
##   ticks, teams alternating in roster order, out of the original's bench
##   door in the east arch's dark ([constant DOOR]) at the game's pace until
##   inside the boards, as the game brings its players on.
## * Showing off: each then picks moves of his own - a lap to somewhere on
##   the ice (a hockey stop at its end), a skate to the boards to face a part
##   of the crowd and celebrate (MwBench3D.celebration: the game's
##   celebrations, arms up, a goalie's stick, hops), a spin, a cheer.
## * The ice in front of the door is kept clear (owner's request): a newcomer
##   skates quickly out of it (fanning out), nobody stops, spins or shows off
##   in it, and the laps go round it ([method in_clear]).
## * Line-up ([method line_up], a press): the starters skate to their spots
##   and turn to their facings, the rink's first frame (MwMatchRehearsal);
##   the reserves skate off through the east passage into its dark and come
##   out of the west arch to their places on the benches (as MwBenchLife
##   will place them). [method lined_up] when all are there.

enum { WAITING, SKATING, SHOWING, OUT, SET }
enum Move { NONE, LAP, SHOW, SPIN, CHEER, STOP }

## The original's bench door (`$A8EE`: motion_init(265, 10)): the players
## come on from here; and where the game's player is on the ice (state 20
## ends at x 178), at its pace (vx -$180: 1.5 px a tick).
const DOOR := Vector2(265, 10)
const IN_X := 178.0
const ENTER_SPEED := 1.5
## The first comes out this many ticks into the intro (owner: a 4 s shot of
## the rink, 6 s of the crowd), the rest one every ENTER_EVERY ticks.
const ENTER_AT := 600
const ENTER_EVERY := 18
## Where they skate (|x|, |y|): the ice, and where they show off at the
## boards (the sides; the ends beside the nets).
const ICE := Vector2(150.0, 300.0)
const SIDE_X := 165.0
const END_Y := 345.0
## Skating speeds (px a tick): showing off; at the line-up at least (all
## there within LINEUP_TICKS); onto the benches.
const SPEED := Vector2(1.6, 2.6)
const LINEUP_SPEED := 2.0
const LINEUP_TICKS := 240
const BENCH_SPEED := 1.5
## Ticks in the dark between the east passage and the west arch.
const DARK_WAIT := 20
## The east passage's way out (|y| at most) and its dark.
const PASSAGE_Y := 24.0
const PASSAGE_IN := Vector2(175.0, 0.0)
const HOCKEY_STOP := 31            ## the skaters' hockey stop (a loop)
## The ice in front of the door kept clear: east of x CLEAR_X, within
## CLEAR_Y of the door's y.
const CLEAR_X := 90.0
const CLEAR_Y := 70.0

## Ticks since the intro began.
var tick := 0
## Each player: {team, slot, rec, starter, spot (Vector2), spot_v (variant),
## place (his bench place, reserves), enter_at, state, way, p, rate, since,
## then (what he does at the way's end: "clear", "move", "show", "stop", "set",
## "out", "bench"), move, until, look, pick, whole, at (standing)}.
var figs: Array[Dictionary] = []
var lining_up := false
## What each player looks like once in his place, as the rink's first frame
## will show him (Vector2i(team, slot) -> its MwRinkDraw3D items: a starter's
## frames - body, shadow, markers - or a reserve's bench figure); empty: his
## own standing frame. MwMatchIntro3D fills it from the rehearsal, so the
## rink takes over a picture it would draw itself.
var settled := {}
## The match's seed for the figures' own moments (MwBench3D.rand).
var seed_ := 0

var _rom: PackedByteArray
var _rng := RandomNumberGenerator.new()


func _init(rom: PackedByteArray, rehearsal: MwMatchRehearsal, seed_value: int) -> void:
	_rom = rom
	seed_ = seed_value
	_rng.seed = seed_value
	var spots := {}
	for st: Dictionary in rehearsal.starters():
		spots[Vector2i(st["team"], st["slot"])] = st
	var places := {}
	var f: PackedFloat32Array = rehearsal.bench.get("figs", PackedFloat32Array())
	for i in range(0, f.size() - MwBenchLife.FIG + 1, MwBenchLife.FIG):
		places[Vector2i(int(f[i]), int(f[i + 1]))] = int(f[i + 3])
	var rosters := [rehearsal.roster(0), rehearsal.roster(1)]
	var n := 0
	for k in maxi(rosters[0].size(), rosters[1].size()):
		for t in 2:
			if k >= rosters[t].size():
				continue
			var r: Dictionary = rosters[t][k]
			var key := Vector2i(t, r["slot"])
			var st: Dictionary = spots.get(key, {})
			figs.append({"team": t, "slot": r["slot"], "rec": r["record"], "starter": not st.is_empty(),
					"spot": st.get("at", Vector2.ZERO), "spot_v": int(st.get("variant", 0)),
					"place": int(places.get(key, -1)), "enter_at": ENTER_AT + n * ENTER_EVERY,
					"state": WAITING, "way": PackedVector2Array(), "p": 0.0, "rate": 0.0, "since": 0,
					"then": "", "move": Move.NONE, "until": 0, "look": 6, "pick": 0.0, "whole": 0.0,
					"at": DOOR})
			n += 1


## [param e] ticks on.
func step(e: int) -> void:
	tick += e
	for f in figs:
		_step(f, e)


func _step(f: Dictionary, e: int) -> void:
	match int(f["state"]):
		WAITING:
			if tick >= int(f["enter_at"]):
				var y := DOOR.y
				var way := PackedVector2Array([DOOR, Vector2(IN_X, y)])
				if lining_up:
					way.append(f["spot"])
					_skate(f, way, maxf(LINEUP_SPEED, MwBench3D.length(way) / LINEUP_TICKS), "set")
				else:
					_skate(f, way, ENTER_SPEED, "clear")
		SKATING:
			f["p"] = minf(1.0, float(f["p"]) + float(f["rate"]) * e)
			if f["p"] >= 1.0:
				var way: PackedVector2Array = f["way"]
				f["at"] = way[-1]
				_arrive(f)
		SHOWING:
			if tick >= int(f["until"]) and not lining_up:
				_next_move(f)
		OUT:
			if tick >= int(f["until"]):
				var t: int = f["team"]
				var from := MwBench3D.place_at(t, MwBench3D.WEST_EXIT)
				_skate(f, MwBench3D.route(t, from, MwBench3D.place_at(t, int(f["place"]))), BENCH_SPEED, "bench")


func _arrive(f: Dictionary) -> void:
	match String(f["then"]):
		"clear":                             # on the ice: quickly out of the door's way, fanning out
			var at: Vector2 = f["at"]
			var to := Vector2(CLEAR_X - 12.0, DOOR.y + _rng.randf_range(-CLEAR_Y + 15.0, CLEAR_Y - 15.0))
			_skate(f, PackedVector2Array([at, to]), SPEED.y, "move")
		"move":
			_next_move(f)
		"stop":
			_show(f, Move.STOP, 16)
		"show":
			_show(f, Move.SHOW, _rng.randi_range(150, 260))
		"set":
			f["state"] = SET
			f["look"] = f["spot_v"]
		"bench":
			f["state"] = SET
			f["look"] = 2                    # the benches look at the ice (east)
		"out":
			f["state"] = OUT
			f["until"] = tick + DARK_WAIT


## The next move of a player showing off (out of the door's clear ice
## first: a lap or the boards, never a move on the spot).
func _next_move(f: Dictionary) -> void:
	var from: Vector2 = f["at"]
	var r := _rng.randf() * (0.75 if in_clear(from) else 1.0)
	if r < 0.4:
		var to := Vector2(_rng.randf_range(-ICE.x, ICE.x), _rng.randf_range(-ICE.y, ICE.y))
		while in_clear(to):
			to = Vector2(_rng.randf_range(-ICE.x, ICE.x), _rng.randf_range(-ICE.y, ICE.y))
		_skate(f, _curve(from, to), _rng.randf_range(SPEED.x, SPEED.y), "stop")
	elif r < 0.75:
		var to: Vector2
		var look: int
		if _rng.randf() < 0.7:
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			to = Vector2(side * SIDE_X, _rng.randf_range(-280.0, 280.0))
			while in_clear(to):
				to.y = _rng.randf_range(-280.0, 280.0)
			look = 2 if side > 0.0 else 6
		else:
			var end := 1.0 if _rng.randf() < 0.5 else -1.0
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			to = Vector2(side * _rng.randf_range(60.0, 140.0), end * END_Y)
			look = 4 if end > 0.0 else 0
		_skate(f, _curve(from, to), _rng.randf_range(SPEED.x, SPEED.y), "show")
		f["show_look"] = look
	elif r < 0.85:
		_show(f, Move.SPIN, 48)
	else:
		_show(f, Move.CHEER, _rng.randi_range(90, 150))


func _show(f: Dictionary, move: int, length: int) -> void:
	f["state"] = SHOWING
	f["move"] = move
	f["since"] = tick
	f["until"] = tick + length
	f["pick"] = _rng.randf()
	f["whole"] = _rng.randf()
	if move == Move.SHOW:
		f["look"] = int(f.get("show_look", f["look"]))
	elif move == Move.CHEER:
		f["whole"] = 1.0                     # hops and cheers (no whole celebration)


func _skate(f: Dictionary, way: PackedVector2Array, speed: float, then: String) -> void:
	f["state"] = SKATING
	f["way"] = way
	f["p"] = 0.0
	f["rate"] = speed / maxf(MwBench3D.length(way), 1.0)
	f["since"] = tick
	f["then"] = then


## Where [param f] is now (rink px).
func position(f: Dictionary) -> Vector2:
	if int(f["state"]) == SKATING:
		return MwBench3D.along(f["way"], f["p"])[0]
	return f["at"]


## Whether [param point] is on the ice in front of the door, kept clear.
static func in_clear(point: Vector2) -> bool:
	return point.x > CLEAR_X and absf(point.y - DOOR.y) < CLEAR_Y


## A curved way from [param a] to [param b] (a quadratic arc bending a
## random way), kept on the ice and round the door's clear ice (its points
## there moved to its west edge: out of it straight, along it).
func _curve(a: Vector2, b: Vector2) -> PackedVector2Array:
	var d := b - a
	var c := (a + b) / 2.0 + Vector2(-d.y, d.x).normalized() * _rng.randf_range(-0.4, 0.4) * d.length()
	var out := PackedVector2Array()
	for i in 11:
		var u := i / 10.0
		var point_2 := a.lerp(c, u).lerp(c.lerp(b, u), u)
		if i == 0:
			point_2 = a
		elif i == 10:
			point_2 = b
		else:
			point_2 = Vector2(clampf(point_2.x, -170.0, 170.0), clampf(point_2.y, -350.0, 350.0))
			if in_clear(point_2):
				point_2.x = CLEAR_X - 15.0
		out.append(point_2)
	return out


## The press: everyone to his place for the match (see the class notes).
func line_up() -> void:
	if lining_up:
		return
	lining_up = true
	var late := 0
	for f in figs:
		var state: int = f["state"]
		if state == SET:
			continue
		var now := position(f)
		if state == WAITING:
			if f["starter"]:
				f["enter_at"] = tick + late * 6       # out of the door, straight to his spot
			else:
				f["state"] = OUT                     # straight to his bench, out of the west arch
				f["until"] = tick + late * 4
			late += 1
			continue
		var way: PackedVector2Array
		if f["starter"]:
			way = _curve(now, f["spot"]) if now.x <= IN_X \
					else PackedVector2Array([now, Vector2(IN_X, now.y), f["spot"]])
			_skate(f, way, maxf(LINEUP_SPEED, MwBench3D.length(way) / LINEUP_TICKS), "set")
		else:
			var y := clampf(now.y, -PASSAGE_Y, PASSAGE_Y)
			way = PackedVector2Array([now, Vector2(PASSAGE_IN.x, y), Vector2(MwBench3D.EAST_OUT.x, y * 0.6)])
			if now.x > PASSAGE_IN.x:
				way = PackedVector2Array([now, Vector2(MwBench3D.EAST_OUT.x, y * 0.6)])
			_skate(f, way, maxf(LINEUP_SPEED, MwBench3D.length(way) / LINEUP_TICKS), "out")


## Everyone in his place (the line-up done).
func lined_up() -> bool:
	if not lining_up:
		return false
	for f in figs:
		if int(f["state"]) != SET:
			return false
	return true


## The players' frames now (MwRinkDraw3D.items' form, keyed
## "cast.t<team>.s<slot>/body").
func items() -> Array:
	var out := []
	for f in figs:
		if int(f["state"]) == SET:
			var as_set: Array = settled.get(Vector2i(f["team"], f["slot"]), [])
			if not as_set.is_empty():
				out.append_array(as_set)
				continue
		var it := _item(f)
		if not it.is_empty():
			out.append(it)
	return out


func _item(f: Dictionary) -> Dictionary:
	var t: int = f["team"]
	var slot: int = f["slot"]
	var rec: int = f["rec"]
	var key := "cast.t%d.s%d/body" % [t, slot]
	var el := float(tick - int(f["since"]))
	match int(f["state"]):
		SKATING:
			return MwBench3D.walking_item(_rom, key, t, slot, rec, f["way"], f["p"], el, f["look"])
		SHOWING:
			var at: Vector2 = f["at"]
			var look: int = f["look"]
			match int(f["move"]):
				Move.SPIN:
					return MwBench3D.figure_item(_rom, key, t, slot, rec, Vector3(at.x, at.y, 0.0),
							MwBench3D.ANIM_SKATE, -1.0, posmod(look + int(el / 4.0), 8))
				Move.STOP:
					var anim := HOCKEY_STOP if not MwBench3D.goalie(_rom, rec) else MwBench3D.ANIM_SKATE
					return MwBench3D.figure_item(_rom, key, t, slot, rec, Vector3(at.x, at.y, 0.0), anim, el, look)
				_:
					var c := MwBench3D.celebration(_rom, rec, el, f["pick"], f["whole"])
					var z := MwBench3D.hop_height(seed_, t, slot, tick, c[2])
					return MwBench3D.figure_item(_rom, key, t, slot, rec, Vector3(at.x, at.y, z), c[0], c[1], look)
		SET:
			var at: Vector2 = f["at"]
			return MwBench3D.figure_item(_rom, key, t, slot, rec, Vector3(at.x, at.y, 0.0),
					MwBench3D.ANIM_SKATE, -1.0, f["look"])
	return {}
