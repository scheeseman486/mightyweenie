class_name MwRinkDirector3D
extends RefCounted
## The cinematic camera's director (plan 20, F7; owner: "swoops and zooms
## that aren't necessarily good for gameplay but work well to capture
## footage"). It picks shots of the play and moves through them:
##
## * CRANE: from high behind the play down towards it.
## * ORBIT: round the puck above the glass, slowly.
## * LOW_TRACK: just above the ice beside the boards, level with the play.
## * CLOSE_UP: tight on the puck (its carrier), from a fixed side.
## * BEHIND_NET: from behind the goal the play is near, over the end boards
##   (the stands there cut away, MwStands3D.cutaway).
## * GOAL: a slow orbit round the puck after a goal.
##
## A shot lasts 4-8 s; a new one comes then, or at once on a cue (a goal, a
## faceoff, a jump in the play). Most changes cut; some, and the goal's,
## move there slowly. Its choices are its own seeded random numbers (the
## same footage for the same play), never the game's. Presentation only.

enum Shot { CRANE, ORBIT, LOW_TRACK, CLOSE_UP, BEHIND_NET, GOAL }

const NAMES := ["crane", "orbit", "low track", "close-up", "behind the net", "goal"]

## The end boards (rink y) the current shot looks over from beyond them
## (the stands' cutaway); 0 none.
var cut_boards := 0.0
## The shot on now and how far into it (s).
var shot := Shot.CRANE
var time := 0.0

var _length := 6.0
var _rng := RandomNumberGenerator.new()
var _phase := -1
var _score := Vector2i(-1, -1)
var _side := 1.0
var _angle := 0.0
var _focus := Vector3.ZERO
var _focus_v := Vector3.ZERO
var _eye := Vector3.ZERO
var _eye_v := Vector3.ZERO
var _fov := 36.0
var _fov_v := 0.0
var _gentle := false          # moving to this shot slowly (no cut)
var _cut := true


func _init() -> void:
	_rng.seed = 0x4D57


## Places [param cam] for this frame (its [member MwRinkCamera3D.shot],
## [param step] s after the last frame; [param snapping]: a jump, a new
## mode). False: nothing to film (no shot).
func place(cam: MwRinkCamera3D, look: Vector3, snapping: bool, step: float) -> bool:
	var sh := cam.shot
	if sh == null:
		return false
	var puck := Vector3(clampf(sh.puck.x, -175.0, 175.0), clampf(sh.puck.y, -360.0, 360.0), 8.0)
	_cue(sh, puck, snapping)
	time += step
	if time >= _length:
		_next(puck, _rng.randf() < 0.35)
	var focus := puck.lerp(Vector3(look.x, look.y, 8.0), 0.25)
	if _cut:
		_focus = focus
		_focus_v = Vector3.ZERO
	else:
		var f := MwRinkCamera3D.damp(_focus, _focus_v, focus, 4.0, step)
		_focus = f[0]
		_focus_v = f[1]
	var want := _shot_eye(_focus)
	var fov: float = want[1]
	if _cut:
		_eye = want[0]
		_eye_v = Vector3.ZERO
		_fov = fov
		_fov_v = 0.0
		_cut = false
	else:
		var omega := 1.3 if _gentle else 7.0
		var e := MwRinkCamera3D.damp(_eye, _eye_v, want[0], omega, step)
		_eye = e[0]
		_eye_v = e[1]
		var z := MwRinkCamera3D.damp(_fov, _fov_v, fov, 1.5 if _gentle else 6.0, step)
		_fov = z[0]
		_fov_v = z[1]
		if _gentle and _eye.distance_to(want[0]) < 6.0:
			_gentle = false
	cam.transform = MwRinkCamera3D.looking(_eye, _focus)
	cam.fov = _fov
	cam.near = 0.5
	cut_boards = signf(_eye.y) * MwStands.BOARD.y if absf(_eye.y) > MwStands.BOARD.y else 0.0
	return true


## New shots on the play's cues: a goal (the goal orbit), a faceoff or a
## period's start (a crane down to it), a jump.
func _cue(sh: MwRinkShot3D, puck: Vector3, snapping: bool) -> void:
	var scored := _score.x >= 0 and sh.score != _score
	var faceoff := sh.phase != _phase and (sh.phase == MwRinkState.PHASE_FACEOFF or sh.phase == MwRinkState.PHASE_START)
	_score = sh.score
	_phase = sh.phase
	if scored:
		_start(Shot.GOAL, 7.0, true, puck)
	elif snapping:
		_start(Shot.CRANE, 6.0, false, puck)
	elif faceoff and shot != Shot.CRANE:
		_start(Shot.CRANE, 5.0, false, puck)


## The next shot after this one's time, by where the play is.
func _next(puck: Vector3, gentle: bool) -> void:
	var weights := {Shot.CRANE: 1.0, Shot.ORBIT: 2.0, Shot.LOW_TRACK: 2.0, Shot.CLOSE_UP: 1.5,
			Shot.BEHIND_NET: 3.0 if absf(puck.y) > 220.0 else 0.0}
	weights.erase(shot)
	var total := 0.0
	for w: float in weights.values():
		total += w
	var r := _rng.randf() * total
	var pick: int = weights.keys()[0]
	for k: int in weights:
		r -= weights[k]
		if r <= 0.0:
			pick = k
			break
	_start(pick, _rng.randf_range(4.0, 8.0), gentle, puck)


func _start(s: int, length: float, gentle: bool, puck: Vector3) -> void:
	shot = s as Shot
	time = 0.0
	_length = length
	_gentle = gentle
	_cut = not gentle
	_side = -1.0 if puck.x > 0.0 else 1.0          # the far side from the play: a wider view
	_angle = _rng.randf_range(0.0, TAU)


## Where the shot's eye is for [param f] now, and its field of view
## (vertical, deg): [eye (rink px), fov].
func _shot_eye(f: Vector3) -> Array:
	var u := clampf(time / _length, 0.0, 1.0)
	match shot:
		Shot.CRANE:
			var e := u * u * (3.0 - 2.0 * u)
			var high := Vector3(f.x * 0.4, f.y + 300.0, 420.0)
			var low := Vector3(f.x * 0.7, f.y + 150.0, 110.0)
			return [_inside(high.lerp(low, e), 420.0), lerpf(44.0, 34.0, e)]
		Shot.ORBIT:
			var a := _angle + 0.22 * time
			return [_inside(f + Vector3(sin(a) * 210.0, cos(a) * 210.0, 120.0), 120.0), 36.0]
		Shot.LOW_TRACK:
			return [Vector3(_side * 170.0, clampf(f.y + 40.0 * _side, -350.0, 350.0), 22.0), 42.0]
		Shot.CLOSE_UP:
			var a := _angle + 0.05 * time
			return [_inside(f + Vector3(sin(a) * 105.0, cos(a) * 105.0, 42.0), 42.0), 26.0]
		Shot.BEHIND_NET:
			var end := signf(f.y) if f.y != 0.0 else -1.0
			return [Vector3(f.x * 0.25, end * 420.0, 150.0), lerpf(46.0, 38.0, u)]
		Shot.GOAL:
			var a := _angle + 0.32 * time
			return [_inside(f + Vector3(sin(a) * 150.0, cos(a) * 150.0, 70.0), 70.0), 34.0]
	return [f + Vector3(0, 200, 200), 40.0]


## [param e] kept over the ice (inside the boards), at height [param z].
static func _inside(e: Vector3, z: float) -> Vector3:
	return Vector3(clampf(e.x, -175.0, 175.0), clampf(e.y, -360.0, 360.0), z)
