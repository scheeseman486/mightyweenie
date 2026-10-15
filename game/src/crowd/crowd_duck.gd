class_name MwCrowdDuck
extends RefCounted
## The crowd makes way (owner, 2026-10-09: in 3D, looking at the bottom of
## the rink, the crowd covered too much of it - the fans within some radius
## of a player, AI or human, the puck or another thing down there sink, with
## a falloff, not all of them; then only those hiding the rink, a wider,
## gentler curve for the skull that spins after a goal, and only on the main
## 3D camera: the follow camera, MwRinkView3D; then no jumps or snaps where
## two occlusion masks overlap; and 2026-10-11, the same in 3D EXTENDED:
## MwRinkView3D.ducks; docs/rink3d.md, Crowd).
##
## Only fans that hide the rink move: the camera's line of sight over a
## fan's head must come down on the ice inside the boards ([method
## occludes]; the side stands seen from the end never do). Among them, each
## thing standing on the ice - the players, the puck, the referee, the nets,
## the hazards that stand up, during a goal the lamp's skull - clears a space
## round its drawing as the camera sees it: a fan nearer the camera whose
## drawing comes within [constant REACH] px of it, side to side (px at the
## thing's distance), and whose head is higher on the screen than its lowest
## pixel, sinks until his head is [constant CLEAR] px below that pixel - all
## the way within [constant CORE] px of it, less and less out to
## [constant REACH]; a fan whose feet are already above its top on the screen
## does not cover it, less and less so over [constant TOP_SOFT] px. Its
## lowest pixel counts from its ice point up (the rows a frame draws below
## its feet - stick blades, skates - lie on the ice in 3D), and its drawing
## eases from frame to frame ([constant RECT_LAG_S]): animation frames and
## facings change a figure's box every few passes, which moved the fans in
## jumps (owner). A carried puck is its carrier's: he makes way for both (it
## hops round his stick with every frame). During a goal the curve widens and softens
## ([constant GOAL_CORE], [constant GOAL_REACH]), eased in and out over
## [constant GOAL_FADE_S]. A fan sinks behind his tread and the seats in
## front of him (rink3d_crowd: his depth stays that of a figure standing at
## his feet), so the crowd's skyline dips under the thing and no further.
##
## Smooth in time: each thing leaves a wake of [constant SAMPLES] - 1 points,
## each following the one before ([constant LAG_S] s), weaker and weaker
## ([constant WAKE]), so the fans it has passed rise again over about half a
## second; a thing that comes on fades in ([constant FADE_IN_S]), one that
## goes - or jumps ([constant JUMP_PX]: a faceoff reset) - fades out where it
## was ([constant FADE_OUT_S]). Stepped by the rendered frame's time, solved
## exactly, so the same at any frame rate.
##
## This class keeps those tracks and the goal's share (node-free) and picks
## the things out of a frame ([method things]); MwStands3D hands them to the
## crowd shader, which does the sinking. [method sink] and [method occludes]
## are the shader's rule, for the tests. Presentation only, behind
## [member MwSettings.crowd_duck].

## Fans within this many px of a thing's drawing (side to side, at its
## distance) sink all the way; out to [constant REACH] less and less.
const CORE := 6.0
const REACH := 36.0
## During a goal: wider, gentler.
const GOAL_CORE := 16.0
const GOAL_REACH := 128.0
## The goal's curve comes in (and goes) over this (s).
const GOAL_FADE_S := 0.6
## How far below a thing's lowest pixel a sunk fan's head goes (px).
const CLEAR := 4.0
## A fan's feet this far (px) below a thing's top on the screen: he covers it
## fully; at its top, not at all (no jump as its top rises past them).
const TOP_SOFT := 8.0
## A thing's drawing (its box) eases to each new frame's with this time
## constant (s), solved exactly.
const RECT_LAG_S := 0.12
## A fan sinks all the way only when he stands this much nearer the camera
## than the thing (px; less: less, level with it: not at all).
const FRONT := 8.0
## A fan hides the rink fully once the line of sight over his head comes
## down this far inside the boards (px; at the boards: not at all).
const RINK_SOFT := 8.0
## The wake: points each following the one before with this time constant
## (s), and their weights.
const SAMPLES := 4
const LAG_S := 0.1
const WAKE: Array[float] = [1.0, 0.8, 0.55, 0.3]
## A thing coming on fades in over this (s); one going fades out.
const FADE_IN_S := 0.25
const FADE_OUT_S := 0.5
## A move longer than this in one frame (rink px) is a jump: the old place
## fades out, the new one fades in (MwRinkBlend3D.SNAP_PX).
const JUMP_PX := MwRinkBlend3D.SNAP_PX
## The crowd shader's arrays (points: tracks x [constant SAMPLES]).
const MAX_TRACKS := 32
const MAX_POINTS := MAX_TRACKS * SAMPLES
## One frame pixel in view units (MwRink3D.METRES_PER_PX).
const PX := MwRink3D.METRES_PER_PX

## The frames that make way: the bodies of the players, the puck, the
## referee, the nets and the objects (MwRinkDraw3D keys); during a goal the
## lamps' skulls too, spinning on their stands or in flight.
static var _subjects := RegEx.create_from_string("^(t\\d+\\.p\\d+\\.[0-9A-F]+|puck|ref|net\\d+|obj\\d+)/body$")
static var _skulls := RegEx.create_from_string("^lamp\\d+/body$")


## A thing's track: its ice point now and its wake (rink px), its drawing
## (px from its point: left, top, width, height, y down - as MwSprites3D's
## px_rect) and how much it counts (0..1, fading in and out).
class Track:
	var points := PackedVector2Array()
	var rect := Vector4.ZERO
	var life := 0.0
	var going := false


## The things on the ice by key (MwRinkDraw3D's); those going, fading out.
var tracks := {}
var ghosts: Array[Track] = []
## How far the goal's curve has come in (0 none .. 1 a goal's; eased in
## [method goal_share]).
var goal := 0.0


## The things in [param items] (a frame's MwRinkDraw3D items, as the view
## shows them) that make way: {key, at (rink px, the ice point), rect}.
## [param rect_of] gives a frame's drawing (Vector4: left, top, width,
## height px from its ice point, y down; zero size: none). [param scoring]
## (a goal): the lamps' skulls count too, whether they spin on their stands
## (flat cards) or fly (owner: the skull's spin after a goal at the bottom).
static func things(items: Array, rect_of: Callable, scoring := false) -> Array:
	var out: Array = []
	for it: Dictionary in items:
		if int(it["place"]) != MwRinkDraw3D.UPRIGHT or float(it.get("pin", 0)) > 0.0:
			continue
		var key: String = it.get("key", "")
		var skull := scoring and _skulls.search(key) != null
		if not skull and (it.get("flat", false) or _subjects.search(key) == null):
			continue
		if it.has("carrier"):
			continue                # its carrier makes way for both
		var r := ice_up(rect_of.call(it))
		if r.z <= 0.0 or r.w <= 0.0:
			continue
		var at: Vector3 = it["at"]
		out.append({"key": key, "at": Vector2(at.x, at.y), "rect": r})
	return out


## [param rect] (left, top, width, height px from an ice point, y down) cut
## off at the ice point: the rows a frame draws below its feet (stick
## blades, skates, splashes lie on the ice in 3D) do not count, so its
## lowest pixel stays put while it skates. A frame all below it: empty.
static func ice_up(rect: Vector4) -> Vector4:
	return Vector4(rect.x, rect.y, rect.z, minf(rect.w, -rect.y))


## Steps the tracks to [param things_] ([method things]) over [param dt] s
## (the rendered frame's time; 0: places them, nothing moves or fades);
## [param scoring]: a goal is being celebrated (the goal phase), the curve
## widens.
func update(things_: Array, dt: float, scoring := false) -> void:
	dt = maxf(dt, 0.0)
	var seen := {}
	for o: Dictionary in things_:
		var key: String = o["key"]
		var at: Vector2 = o["at"]
		var track: Track = tracks.get(key)
		if track != null and track.points[0].distance_to(at) > JUMP_PX:
			_let_go(track)             # a jump: fades out where it was
			track = null
		var rect: Vector4 = o["rect"]
		if track == null:
			track = Track.new()
			for i in SAMPLES:
				track.points.append(at)
			track.rect = rect
			tracks[key] = track
		track.points[0] = at
		track.rect = rect + (track.rect - rect) * exp(-dt / RECT_LAG_S)
		seen[key] = true
	for key: String in tracks.keys():
		if not seen.has(key):
			_let_go(tracks[key])
	for live_track: Track in tracks.values():
		_wake(live_track, dt)
		live_track.life = minf(live_track.life + dt / FADE_IN_S, 1.0)
	var kept: Array[Track] = []
	for ghost: Track in ghosts:
		_wake(ghost, dt)
		ghost.life -= dt / FADE_OUT_S
		if ghost.life > 0.0:
			kept.append(ghost)
	ghosts = kept
	while tracks.size() + ghosts.size() > MAX_TRACKS and not ghosts.is_empty():
		var weakest := 0
		for i in ghosts.size():
			if ghosts[i].life < ghosts[weakest].life:
				weakest = i
		ghosts.remove_at(weakest)
	goal = clampf(goal + (dt if scoring else -dt) / GOAL_FADE_S, 0.0, 1.0)


## The goal's curve as the shader takes it: [member goal] eased (0..1).
func goal_share() -> float:
	return smoothstep(0.0, 1.0, goal)


## Forgets every thing at once (a new match).
func clear() -> void:
	tracks = {}
	ghosts = []
	goal = 0.0


func _let_go(track: Track) -> void:
	for key: String in tracks.keys():
		if tracks[key] == track:
			tracks.erase(key)
	track.going = true
	ghosts.append(track)


## Steps a track's wake by [param dt] s: each point follows the one before
## at the rate 1 / [constant LAG_S], the thing's own point held still over
## the step - solved exactly (a chain of lags), so any frame rate gives the
## same wake.
static func _wake(track: Track, dt: float) -> void:
	if dt <= 0.0:
		return
	var a := dt / LAG_S
	var decay := exp(-a)
	var x0 := track.points[0]
	var was := track.points.duplicate()
	for i in range(1, SAMPLES):
		var sum := Vector2.ZERO
		var term := 1.0           # a^(i - j) / (i - j)!
		for j in range(i, 0, -1):
			sum += (was[j] - x0) * term
			term *= a / float(i - j + 1)
		track.points[i] = x0 + sum * decay


## Every point the crowd makes way for: [at (rink px, an ice point), rect,
## weight (0..1)], the strongest tracks' first, at most [constant
## MAX_POINTS]; points too weak to matter left out.
func points() -> Array:
	var all: Array[Track] = []
	for live_track: Track in tracks.values():
		all.append(live_track)
	all.append_array(ghosts)
	all.sort_custom(func(a: Track, b: Track) -> bool: return a.life > b.life)
	var out: Array = []
	for track: Track in all.slice(0, MAX_TRACKS):
		var fade := smoothstep(0.0, 1.0, track.life)
		for i in SAMPLES:
			var w := WAKE[i] * fade
			if w >= 0.01:
				out.append([track.points[i], track.rect, w])
	return out


## How far (px, his own) the fan standing at [param fan] (view space, his
## feet), [param w] x [param h] px, sinks for the thing at [param at] (view
## space, its ice point) drawn as [param rect] (left, top, width, height px
## from it, y down), counting [param weight], with [param goal_] of the
## goal's curve - the crowd shader's rule for one thing (rink3d_crowd,
## duck_px), before [method occludes]. [param ortho]: a parallel projection.
static func sink(fan: Vector3, w: float, h: float, at: Vector3, rect: Vector4, weight: float, ortho := false,
		goal_ := 0.0) -> float:
	if not ortho and fan.z >= -1e-3:
		return 0.0
	var nearer := (fan.z - at.z) / PX       # view z: -forward
	if nearer <= 0.0:
		return 0.0
	var k := 1.0 if ortho else at.z / fan.z  # his px at the thing's distance
	var hx := (fan.x * k - at.x) / PX
	var feet := (fan.y * k - at.y) / PX
	var head := feet + h * k
	var bottom := -(rect.y + rect.w)
	var top := -rect.y
	var need := head - bottom + CLEAR
	var covers := smoothstep(0.0, TOP_SOFT, top - feet)
	if need <= 0.0 or covers <= 0.0:
		return 0.0
	var half := 0.5 * w * k
	var gap := maxf(0.0, maxf(rect.x - (hx + half), (hx - half) - (rect.x + rect.z)))
	var core := lerpf(CORE, GOAL_CORE, goal_)
	var reach := lerpf(REACH, GOAL_REACH, goal_)
	var f := (1.0 - smoothstep(core, reach, gap)) * smoothstep(0.0, FRONT, nearer) * covers * weight
	return f * minf(need / k, h + CLEAR)


## How much a fan whose head is at world point [param head] hides the rink
## from a camera placed at [param cam] (its global transform; [param ortho]:
## parallel) in a world scaled by [param scale] (the ortho camera's): the
## line of sight over his head comes down on the ice inside the boards
## (1 from [constant RINK_SOFT] px inside them, 0 at them and outside, or
## when it never comes down) - the crowd shader's rink_hidden.
static func occludes(head: Vector3, cam: Transform3D, ortho := false, scale := Vector3.ONE) -> float:
	var from := head if ortho else cam.origin
	var d := -cam.basis.z if ortho else head - cam.origin
	if d.y >= -1e-6:
		return 0.0
	var point := from + d * (-from.y / d.y)
	var r := Vector2(point.x / scale.x, point.z / scale.z) / PX
	return 1.0 - smoothstep(-RINK_SOFT, 0.0, MwRinkShape.rounded_sd(r))


## (The boards' signed distance: MwRinkShape.rounded_sd, plan 40.)
