class_name MwRinkShot3D
extends RefCounted
## What the game's 3D views look at in one pass (plan 20, docs/rink3d.md,
## Views): the play's points, taken from the state and the pass's 3D
## placements (MwRinkDraw3D items), blended between passes like the frames
## ([method blend]). Rink px. Presentation only: read from the state, never
## written.

## The ice under the 2D screen's centre (the sim camera's look point).
var look := Vector3.ZERO
## The puck (its point as drawn: on its carrier's stick while carried).
var puck := Vector3.ZERO
## The skaters and goalies on the ice.
var players := PackedVector3Array()
## The player the first-person camera rides with (MwRinkDraw3D subject, e.g.
## "t0.p3.1A"; "" none): player 1's (pad 1's; plan 34, an extended set-up:
## the lowest-numbered player's, [method rider_pad]), else the puck carrier,
## else the player nearest the puck.
var rider := ""
## His point, where he faces (radians clockwise from north) and whether he
## is player 1's.
var rider_at := Vector3.ZERO
var rider_heading := 0.0
var rider_is_p1 := false
## The puck carrier's subject ("" loose).
var carrier := ""
## The characters players drive right now ([method drivers_of]: plan 34's 3D
## EXTENDED frames them with the puck): their subjects and points, in the
## same order. Empty in a 3D frame recorded before plan 34 (the camera then
## takes player 1's rider, [member rider_is_p1]).
var driver_keys := PackedStringArray()
var drivers := PackedVector3Array()
## Each driver's match pad (MwHumanControl.pad_index's numbering: an
## extended set-up's player number - 1, else the original's pad 0-3), in
## the same order - which machine's player drives it, online ([method
## of_pads]). Empty in a frame recorded before it.
var driver_pads := PackedInt32Array()
## The phase (MwRinkState.PHASE_*) and the teams' scores (the cinematic
## camera's cues).
var phase := 0
var score := Vector2i.ZERO

## Plan 40 (S3): the fields, in the order a frame's data keeps them
## ([method to_data]: MwFullReplay.side_to_data, the saved replays); every
## field is one (test_replay_3d).
const FIELDS := ["look", "puck", "players", "rider", "rider_at", "rider_heading", "rider_is_p1", "carrier",
		"phase", "score", "driver_keys", "drivers", "driver_pads"]


## The shot as plain data ([constant FIELDS]).
func to_data() -> Dictionary:
	var d := {}
	for k: String in FIELDS:
		d[k] = get(k)
	return d


## A shot from [method to_data]'s data (a key it does not know is skipped,
## one it lacks keeps its default: a frame recorded before it).
static func from_data(d: Dictionary) -> MwRinkShot3D:
	var shot := MwRinkShot3D.new()
	for k in d:
		if k in FIELDS:
			shot.set(k, d[k])
	return shot


## The shot of [param state] drawn as [param items] (its pass's
## MwRinkDraw3D items), the sim camera at [param shown].
static func make(state: MwRinkState, items: Array, shown: Vector2) -> MwRinkShot3D:
	var shot := MwRinkShot3D.new()
	shot.look = MwRinkCamera3D.look_point(shown)
	var bodies := {}
	for it: Dictionary in items:
		var key: String = it.get("key", "")
		if key.ends_with("/body"):
			bodies[key.trim_suffix("/body")] = it["at"]
	shot.puck = bodies.get("puck", Vector3(shot.look.x, shot.look.y, 0))
	shot.phase = state.phase
	shot.score = Vector2i(state.teams[0].score, state.teams[1].score)
	var carried := state.puck.carried_by()
	var nearest := ""
	var nearest_d := INF
	var p1 := ""
	var first := rider_pad(state)
	var headings := {}
	for ti in state.teams.size():
		var team: MwRinkState.Team = state.teams[ti]
		for pi in team.players.size():
			var p: MwRinkState.Player = team.players[pi]
			var subject := MwRinkDraw3D.subject_key(ti, pi, p.record)
			if not p.present or not bodies.has(subject):
				continue
			var at: Vector3 = bodies[subject]
			shot.players.append(at)
			headings[subject] = heading_of(p.angle)
			if p == carried:
				shot.carrier = subject
			if is_driven(p):
				shot.driver_keys.append(subject)
				shot.drivers.append(at)
				shot.driver_pads.append(pad_of(state, team, p))
			if p.flags & MwRinkState.Player.HUMAN:
				if state.extended:
					if p.pad == first:
						p1 = subject
				else:
					var k := 1 if p.flags & MwRinkState.Player.SECOND_PAD else 0
					if int(team.pads[k]) == 0:
						p1 = subject
			var d := Vector2(at.x - shot.puck.x, at.y - shot.puck.y).length()
			if not p.is_goalie() and d < nearest_d:
				nearest_d = d
				nearest = subject
	shot.rider = p1 if p1 != "" else (shot.carrier if shot.carrier != "" else nearest)
	shot.rider_is_p1 = p1 != ""
	if shot.rider != "":
		shot.rider_at = bodies[shot.rider]
		shot.rider_heading = headings[shot.rider]
	return shot


## The pad whose player the first-person camera rides with: pad 1 (0),
## the original's player 1; plan 34, an extended set-up: the lowest match
## pad playing (its lowest-numbered player; 0 with nobody).
static func rider_pad(state: MwRinkState) -> int:
	if not state.extended:
		return 0
	var low := -1
	for team: MwRinkState.Team in state.teams:
		for pad in team.port_pads:
			if low < 0 or pad < low:
				low = pad
	return maxi(low, 0)


## True when a player drives [param p] right now: the human flag (+$74 bit
## 2, which the original's pads put on the player each controls and move on
## a switch - `$3A28` at a line-up). A character left to the CPU drops out.
## Plan 34's extended set-ups (up to six players a team) flag their players
## the same way, so they just add drivers.
static func is_driven(p: MwRinkState.Player) -> bool:
	return p.present and p.flags & MwRinkState.Player.HUMAN != 0


## The match pad driving [param p] of [param team] in [param state]
## (MwHumanControl.pad_index): an extended set-up's own (+ the player's
## number - 1), else the team's slot's - the original's pad 0-3; -1 none.
static func pad_of(state: MwRinkState, team: MwRinkState.Team, p: MwRinkState.Player) -> int:
	if state.extended:
		return p.pad
	var pad := int(team.pads[1 if p.flags & MwRinkState.Player.SECOND_PAD else 0])
	return pad & 3 if pad != 0xFF else -1


## Online (owner, 2026-10-13: 3D EXTENDED extends for the local players
## only): the match pads of the players on this machine of [param session]
## (its own numbers in the match's online table, pad_of's numbering for a
## set-up [param extended] or not); null offline, where every player is
## local.
static func local_pads(session: MwSession, extended: bool) -> Variant:
	if session == null or session.online.is_empty():
		return null
	var out := PackedInt32Array()
	var machines: Dictionary = session.online.get("machines", {})
	for k in machines:
		if int(machines[k]) != session.machine:
			continue
		var n := int(k)
		var pad := session.humans.pad_index(n) if extended else Array(session.pad_map).find(n)
		if pad >= 0:
			out.append(pad)
	out.sort()
	return out


## This shot with only the drivers on [param pads] (pad_of's numbering) -
## what 3D EXTENDED frames online (MwRinkView3D.local_pads): the others
## aren't this machine's to keep in the picture. With none of them driving,
## the puck alone (no fallback to player 1's rider). A frame recorded
## before [member driver_pads] keeps its drivers.
func of_pads(pads: PackedInt32Array) -> MwRinkShot3D:
	if driver_pads.size() != drivers.size():
		return self
	var shot := from_data(to_data())
	shot.driver_keys = PackedStringArray()
	shot.drivers = PackedVector3Array()
	shot.driver_pads = PackedInt32Array()
	for i in drivers.size():
		if driver_pads[i] in pads:
			shot.driver_keys.append(driver_keys[i])
			shot.drivers.append(drivers[i])
			shot.driver_pads.append(driver_pads[i])
	shot.rider_is_p1 = false
	return shot


## The characters players drive right now in [param state] ([method
## is_driven]), team A's first, each team's in slot order. In single
## player: one skater.
static func drivers_of(state: MwRinkState) -> Array[MwRinkState.Player]:
	var out: Array[MwRinkState.Player] = []
	for team: MwRinkState.Team in state.teams:
		for p in team.players:
			if is_driven(p):
				out.append(p)
	return out


## A player's facing (the byte angle +$73: 0 right, $40 down) as radians
## clockwise from north.
static func heading_of(angle: int) -> float:
	return wrapf(PI / 2.0 + (angle & 0xFF) * TAU / 256.0, -PI, PI)


## The way from [param before] to [param after] at [param t] (0 a, 1 b): points and
## headings move, the rest is [param after]'s; a rider who changed snaps, and so
## do the drivers when they changed (and one who jumped, MwRinkBlend3D).
static func blend(before: MwRinkShot3D, after: MwRinkShot3D, t: float) -> MwRinkShot3D:
	if before == null or t >= 1.0:
		return after
	var shot := from_data(after.to_data())          # b's, then the points that move
	shot.look = before.look.lerp(after.look, t)
	shot.puck = before.puck.lerp(after.puck, t)
	if before.players.size() == after.players.size():
		shot.players = PackedVector3Array()
		for i in after.players.size():
			shot.players.append(before.players[i].lerp(after.players[i], t))
	if before.rider == after.rider:
		shot.rider_at = before.rider_at.lerp(after.rider_at, t)
		shot.rider_heading = lerp_angle(before.rider_heading, after.rider_heading, t)
	if before.driver_keys == after.driver_keys:
		shot.drivers = PackedVector3Array()
		for i in after.drivers.size():
			var from := before.drivers[i]
			var to := after.drivers[i]
			shot.drivers.append(to if from.distance_to(to) > MwRinkBlend3D.SNAP_PX else from.lerp(to, t))
	return shot


## The points 3D EXTENDED frames (plan 34): the puck - on the ice under it:
## its height comes and goes too quickly to frame (the faceoff drops it from
## 112 px) - and the characters players drive ([member drivers]; in a 3D
## frame recorded before them, player 1's rider).
func targets() -> PackedVector3Array:
	var out := PackedVector3Array([Vector3(puck.x, puck.y, 0.0)])
	if not drivers.is_empty():
		out.append_array(drivers)
	elif rider_is_p1:
		out.append(rider_at)
	return out


## The [param n] players nearest the puck.
func nearest_to_puck(n: int) -> PackedVector3Array:
	var sorted := Array(players)
	sorted.sort_custom(func(p: Vector3, q: Vector3) -> bool:
		return Vector2(p.x - puck.x, p.y - puck.y).length_squared() < Vector2(q.x - puck.x, \
				q.y - puck.y).length_squared())
	return PackedVector3Array(sorted.slice(0, n))
