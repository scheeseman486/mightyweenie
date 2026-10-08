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
## "t0.p3.1A"; "" none): player 1's, else the puck carrier, else the player
## nearest the puck.
var rider := ""
## His point, where he faces (radians clockwise from north) and whether he
## is player 1's.
var rider_at := Vector3.ZERO
var rider_heading := 0.0
var rider_is_p1 := false
## The puck carrier's subject ("" loose).
var carrier := ""
## The phase (MwRinkState.PHASE_*) and the teams' scores (the cinematic
## camera's cues).
var phase := 0
var score := Vector2i.ZERO


## The shot of [param state] drawn as [param items] (its pass's
## MwRinkDraw3D items), the sim camera at [param shown].
static func make(state: MwRinkState, items: Array, shown: Vector2) -> MwRinkShot3D:
	var s := MwRinkShot3D.new()
	s.look = MwRinkCamera3D.look_point(shown)
	var bodies := {}
	for it: Dictionary in items:
		var key: String = it.get("key", "")
		if key.ends_with("/body"):
			bodies[key.trim_suffix("/body")] = it["at"]
	s.puck = bodies.get("puck", Vector3(s.look.x, s.look.y, 0))
	s.phase = state.phase
	s.score = Vector2i(state.teams[0].score, state.teams[1].score)
	var carried := state.puck.carried_by()
	var nearest := ""
	var nearest_d := INF
	var p1 := ""
	var headings := {}
	for ti in state.teams.size():
		var team: MwRinkState.Team = state.teams[ti]
		for pi in team.players.size():
			var p: MwRinkState.Player = team.players[pi]
			var subject := "t%d.p%d.%X" % [ti, pi, p.record]
			if not p.present or not bodies.has(subject):
				continue
			var at: Vector3 = bodies[subject]
			s.players.append(at)
			headings[subject] = heading_of(p.angle)
			if p == carried:
				s.carrier = subject
			if p.flags & MwRinkState.Player.HUMAN:
				var k := 1 if p.flags & MwRinkState.Player.SECOND_PAD else 0
				if int(team.pads[k]) == 0:
					p1 = subject
			var d := Vector2(at.x - s.puck.x, at.y - s.puck.y).length()
			if not p.is_goalie() and d < nearest_d:
				nearest_d = d
				nearest = subject
	s.rider = p1 if p1 != "" else (s.carrier if s.carrier != "" else nearest)
	s.rider_is_p1 = p1 != ""
	if s.rider != "":
		s.rider_at = bodies[s.rider]
		s.rider_heading = headings[s.rider]
	return s


## A player's facing (the byte angle +$73: 0 right, $40 down) as radians
## clockwise from north.
static func heading_of(angle: int) -> float:
	return wrapf(PI / 2.0 + (angle & 0xFF) * TAU / 256.0, -PI, PI)


## The way from [param a] to [param b] at [param t] (0 a, 1 b): points and
## headings move, the rest is [param b]'s; a rider who changed snaps.
static func blend(a: MwRinkShot3D, b: MwRinkShot3D, t: float) -> MwRinkShot3D:
	if a == null or t >= 1.0:
		return b
	var s := MwRinkShot3D.new()
	s.look = a.look.lerp(b.look, t)
	s.puck = a.puck.lerp(b.puck, t)
	s.players = b.players
	if a.players.size() == b.players.size():
		s.players = PackedVector3Array()
		for i in b.players.size():
			s.players.append(a.players[i].lerp(b.players[i], t))
	s.rider = b.rider
	s.rider_is_p1 = b.rider_is_p1
	s.rider_at = b.rider_at
	s.rider_heading = b.rider_heading
	if a.rider == b.rider:
		s.rider_at = a.rider_at.lerp(b.rider_at, t)
		s.rider_heading = lerp_angle(a.rider_heading, b.rider_heading, t)
	s.carrier = b.carrier
	s.phase = b.phase
	s.score = b.score
	return s


## The [param n] players nearest the puck.
func nearest_to_puck(n: int) -> PackedVector3Array:
	var sorted := Array(players)
	sorted.sort_custom(func(p: Vector3, q: Vector3) -> bool:
		return Vector2(p.x - puck.x, p.y - puck.y).length_squared() < Vector2(q.x - puck.x, q.y - puck.y).length_squared())
	return PackedVector3Array(sorted.slice(0, n))
