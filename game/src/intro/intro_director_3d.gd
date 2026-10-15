class_name MwIntroDirector3D
extends MwRinkDirector3D
## The match's opening's camera (plan 33, docs/rink3d.md, The match's
## opening; owner: a steady TV-style shot of the rink for about 4 s, then
## sweeping cinematic shots - dollies, drone shots - for about 6 s, more on
## the crowd, with some randomness). The cinematic camera's director
## (MwRinkDirector3D: its shots, its smooth moves and cuts) with shots of
## its own, filmed from what the intro shows (MwIntroCast) instead of the
## play, from its own seeded random numbers:
##
## * TV_STEADY: the first [constant STEADY_S] s, still, from above the west
##   stands where the TV camera stands, the whole rink in the picture.
## * Then [constant CROWD_S] s of the crowd, two or three of: STANDS_DOLLY
##   (along a full section of the stands just above the boards, looking out
##   at the fans), DRONE (above the stands along a side, over them to the
##   ice), CROWD_CRANE (from the ice up and back from a section, still
##   facing it, to the ice before it), END_SWEEP
##   (across an end's stands, behind the net). The sections are the full
##   ones: the ends, and the sides beyond the arches ([constant SECTION_Y]).
## * Then DOOR (at the east door: the first players come out), and until
##   the line-up the crowd's shots, DOOR while they come out, DANCER (one of
##   them showing off, from the ice's side, swinging slowly round him), TRACK
##   (beside one skating), CROWD_CUT (a
##   section of the stands from the ice).
## * The line-up: a glide to the match's own view at the rink's first frame
##   ([member final]), so the rink takes over without a cut.
##
## Changes of shot cut, or now and then glide ([method _glide_frame]): the
## camera's place and its heading and tilt move on together, unhurried,
## and the tilt only between the two shots' (owner, 2026-10-09: the sweeps
## tilted down too much and swung round too fast - the eye and the focus
## used to move on separately, so the camera could pass over what it looked
## at: straight down and spinning). The shots themselves look down at most
## about 40 degrees, the hand-over too.

enum { TV_STEADY = 100, STANDS_DOLLY, DRONE, CROWD_CRANE, END_SWEEP, DOOR, DANCER, TRACK, CROWD_CUT, HAND_OVER }

const STEADY_S := 4.0
const CROWD_S := 6.0
## Shots after the steady one last this long (s).
const SHOT_S := Vector2(2.6, 4.5)
## The rink's corners and the stands' top (rink px): the steady shot shows
## them all.
const RINK_POINTS := [Vector3(-MwRinkShape.BOARD.x, -MwRinkShape.BOARD.y, 0),
		Vector3(MwRinkShape.BOARD.x, -MwRinkShape.BOARD.y, 0),
		Vector3(-MwRinkShape.BOARD.x, MwRinkShape.BOARD.y, 0), Vector3(MwRinkShape.BOARD.x, MwRinkShape.BOARD.y, 0),
		Vector3(-MwRinkShape.BOARD.x, 0, MwRinkShape.BOARDS_TOP),
		Vector3(MwRinkShape.BOARD.x, 0, MwRinkShape.BOARDS_TOP)]
## Where the TV camera stands (MwRinkCamera3D's side_out_px, side_height_px).
const TV_EYE := Vector3(-430.0, 0.0, 320.0)
## The sides' full stands (|y|): beyond the arches (MwStands.PEN_Y) to the
## corners.
const SECTION_Y := Vector2(190.0, 320.0)

## Seconds since the intro began.
var intro_time := 0.0
## The players (their places, for the shots that follow them).
var cast: MwIntroCast
## The match's view at the rink's first frame: {transform, fov, near, far,
## ortho, scale} (empty: none yet); the line-up glides there.
var final := {}
## The picture's shape (width / height).
var aspect := float(MwRink3D.SCREEN.x) / MwRink3D.SCREEN.y

## The intro's clock (s, MwMatchIntro3D's ticks): the hand-over's pace, so
## it ends with the players' line-up whether frames are drawn or not (drawn
## frames glide by their own clock, MwRinkCamera3D.clock, a pass behind).
var clock := 0.0

var _subject := -1            # the player a shot follows (index into cast.figs)
var _dance_heading := 0.0     # DANCER: from him towards the rink's middle when the shot began
var _doored := false          # the door's first shot taken
var _hand_from := {}          # the hand-over's start: {eye, focus, fov}
var _hand_at := -1.0          # the clock the hand-over began at (< 0: not yet)
var _scale := Vector3.ONE     # the world's scale now
## The hand-over's glide (s).
const HAND_S := 2.5
## A glide between shots turns at most about this fast (deg/s), and lasts
## this long (s) at least and at most; a change that would turn further or
## move further (rink px) than a glide can at that pace cuts instead.
const GLIDE_TURN := 30.0
const GLIDE_S := Vector2(2.0, 4.0)
const GLIDE_MOST_PX := 280.0
var _glide := {}              # a glide on: {from: Transform3D, fov, t, s} (s < 0: not sized yet)


func _init(seed_ := 0x4D57) -> void:
	_rng.seed = seed_
	@warning_ignore("int_as_enum_without_match")   # the opening's own shots, past the director's
	shot = TV_STEADY as Shot
	_length = STEADY_S
	_cut = true


## Places [param cam] for this frame ([param step] s on).
func place(cam: MwRinkCamera3D, _look: Vector3, _snapping: bool, step: float) -> bool:
	intro_time += step
	time += step
	cut_boards = 0.0
	if _hand_at >= 0.0:
		return _hand_over(cam)
	if time >= _length:
		var from := cam.transform
		var fov := cam.fov
		_next_intro()
		if _gentle:
			_glide = {"from": from, "fov": fov, "t": 0.0, "s": -1.0}
			_gentle = false
	if not _glide.is_empty():
		_glide_frame(cam, step)
		return true
	_frame(cam, _shot_focus(), step)
	return true


## A glide into the new shot: its frame now (as a cut would place it) and
## the frame the glide began at, blended - the place along a line, the
## heading the shorter way round and the tilt between the two
## (MwRinkCamera3D.blend_view) - over a time that keeps the turn at about
## [constant GLIDE_TURN] deg/s ([constant GLIDE_S]). Then the shot goes on
## from where its frame is, without a jolt.
func _glide_frame(cam: MwRinkCamera3D, step: float) -> void:
	_cut = true
	_frame(cam, _shot_focus(), step)
	var to := cam.transform
	var to_fov := cam.fov
	var from: Transform3D = _glide["from"]
	if float(_glide["s"]) < 0.0:
		var a := MwRinkCamera3D.heading_tilt(from.basis)
		var b := MwRinkCamera3D.heading_tilt(to.basis)
		var turn := rad_to_deg(Vector2(wrapf(b.x - a.x, -PI, PI), b.y - a.y).length())
		var most := maxf(GLIDE_S.x, minf(GLIDE_S.y, _length - 0.5))
		var duration := maxf(turn * 1.5 / GLIDE_TURN, GLIDE_S.x)
		if duration > most or from.origin.distance_to(to.origin) / MwRink3D.METRES_PER_PX > GLIDE_MOST_PX:
			_glide = {}                      # too far for an unhurried glide: a cut (placed above)
			return
		_glide["s"] = duration
	_glide["t"] = float(_glide["t"]) + step
	var u := clampf(float(_glide["t"]) / float(_glide["s"]), 0.0, 1.0)
	var eased := u * u * (3.0 - 2.0 * u)
	cam.transform = MwRinkCamera3D.blend_view(from, to, eased)
	cam.fov = lerpf(float(_glide["fov"]), to_fov, eased)
	if u >= 1.0:
		_glide = {}


## The line-up began: the camera glides from where it is to the match's
## view ([member final]) over [constant HAND_S] s of the intro's clock.
func begin_hand_over() -> void:
	if _hand_at >= 0.0 or final.is_empty():
		return
	_hand_at = clock
	_hand_from = {"eye": _eye, "focus": _focus, "fov": _fov}
	@warning_ignore("int_as_enum_without_match")   # the opening's own shots, past the director's
	shot = HAND_OVER as Shot


## True once the hand-over's glide has ended (the camera is the match's).
func handed_over() -> bool:
	return _hand_at >= 0.0 and clock - _hand_at >= HAND_S


func _hand_over(cam: MwRinkCamera3D) -> bool:
	var now := cam.clock if cam.clock >= 0.0 else clock      # the shown frame's, when drawn
	var u := clampf((now - _hand_at) / HAND_S, 0.0, 1.0)
	var eased := u * u * (3.0 - 2.0 * u)
	var to: Transform3D = final["transform"]
	var eye: Vector3 = _hand_from["eye"]
	var focus: Vector3 = _hand_from["focus"]
	if eye.distance_to(focus) < 1.0:
		eased = 1.0                              # (nothing filmed yet: straight there)
		focus = eye + Vector3(0, -1, 0)
	var from := MwRinkCamera3D.looking(eye, focus)
	cam.transform = MwRinkCamera3D.blend_view(from, to, eased)
	# the lens as the director sets it (the camera widens it for a taller
	# picture afterwards, MwRinkCamera3D.taller_fov), the clip planes and
	# the world's scale (ORTHO's) the match's at the end
	cam.fov = lerpf(float(_hand_from["fov"]), cam.taller_fov(float(final["fov"]), true), eased)
	cam.near = lerpf(0.5, float(final.get("near", 0.5)), eased * eased * eased)
	cam.far = lerpf(cam.far, float(final.get("far", cam.far)), eased)
	_scale = Vector3.ONE.lerp(final.get("scale", Vector3.ONE), eased)
	return true


## The world's scale while filming (MwRinkCamera3D.world_scale): the true
## one, gliding to the match's view's (ORTHO's) at the line-up.
func world_scale() -> Vector3:
	return _scale


## The next shot: the crowd's first, then by what the intro shows.
func _next_intro() -> void:
	var crowd := intro_time < STEADY_S + CROWD_S
	var weights := {STANDS_DOLLY: 2.0, DRONE: 1.5, CROWD_CRANE: 1.5, END_SWEEP: 1.0}
	if not crowd and cast != null:
		var entering := false
		var any := false
		for f in cast.figs:
			if int(f["state"]) == MwIntroCast.WAITING:
				entering = true
			elif int(f["state"]) != MwIntroCast.OUT:
				any = true
		weights[CROWD_CUT] = 1.0
		if entering:
			weights[DOOR] = 3.0
		if any:
			weights[DANCER] = 2.5
			weights[TRACK] = 1.5
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
	var length := _rng.randf_range(SHOT_S.x, SHOT_S.y)
	if crowd:
		length = minf(length, STEADY_S + CROWD_S - intro_time) if STEADY_S + CROWD_S - intro_time > 1.5 else length
	elif not _doored and cast != null:
		pick = DOOR                         # the first players come out
		length = 5.0
		_doored = true
	_start(pick, length, _rng.randf() < 0.3, Vector3(_rng.randf_range(-1.0, 1.0), 0, 0))
	_subject = _pick_subject(pick)
	if _subject >= 0:
		var point := cast.position(cast.figs[_subject])
		var toward := -Vector2(point.x, point.y)
		_dance_heading = atan2(toward.x, toward.y) if toward.length() > 1.0 else 0.0


## A player for a shot that follows one (-1 none): one showing off for
## DANCER, one skating for TRACK.
func _pick_subject(for_shot: int) -> int:
	if cast == null or not for_shot in [DANCER, TRACK]:
		return -1
	var want := MwIntroCast.SHOWING if for_shot == DANCER else MwIntroCast.SKATING
	var picks := []
	for i in cast.figs.size():
		var st := int(cast.figs[i]["state"])
		if st == want or (for_shot == DANCER and st == MwIntroCast.SKATING):
			picks.append(i)
	if picks.is_empty():
		return -1
	return picks[_rng.randi() % picks.size()]


## A full section's |y| on a side for this shot (from its random angle).
func _section_y() -> float:
	return signf(sin(_angle) + 1e-6) * lerpf(SECTION_Y.x, SECTION_Y.y, absf(cos(_angle)))


## What the shot looks at now (rink px).
func _shot_focus() -> Vector3:
	var u := clampf(time / _length, 0.0, 1.0)
	var sx := _side
	match shot:
		TV_STEADY:
			return Vector3(0, 0, 0)
		STANDS_DOLLY:
			if cos(_angle * 3.0) > 0.0:
				var end := signf(sin(_angle) + 1e-6)          # an end's stands
				var x := lerpf(-130.0, 130.0, u) * sx
				return Vector3(x * 0.8, end * 470.0, 125.0)
			var y := signf(sin(_angle) + 1e-6) * lerpf(SECTION_Y.x, SECTION_Y.y, u if sx > 0.0 else 1.0 - u)
			return Vector3(sx * 300.0, y + 30.0, 110.0)
		DRONE:
			var y := lerpf(-260.0, 260.0, u) * signf(_angle - PI)
			return Vector3(sx * 100.0, y + 140.0 * signf(_angle - PI), 20.0)
		CROWD_CRANE:
			var y := _section_y()
			var eased := u * u * (3.0 - 2.0 * u)
			return Vector3(sx * 320.0, y, 85.0).lerp(Vector3(sx * 140.0, y * 0.85, 10.0), eased)
		END_SWEEP:
			var end := signf(_angle - PI)
			return Vector3(lerpf(-140.0, 140.0, u) * sx * 0.6, end * 470.0, 150.0)
		DOOR:
			return Vector3(225.0, 10.0, 18.0)
		DANCER, TRACK:
			if _subject >= 0:
				var point := cast.position(cast.figs[_subject])
				return Vector3(point.x, point.y, 16.0)
			return Vector3.ZERO
		CROWD_CUT:
			var y := _section_y()
			return Vector3(sx * 330.0, y + 20.0, 140.0)
	return Vector3.ZERO


## Where the shot's eye is for focus [param f] now, and its lens.
func _shot_eye(f: Vector3) -> Array:
	var u := clampf(time / _length, 0.0, 1.0)
	var sx := _side
	match shot:
		TV_STEADY:
			var xf := MwRinkCamera3D.looking(TV_EYE, Vector3.ZERO)
			return [TV_EYE, MwRinkCamera3D.fit_fov(xf, RINK_POINTS, aspect) + 2.0]
		STANDS_DOLLY:
			if absf(f.y) > 400.0:
				return [Vector3(f.x / 0.8, signf(f.y) * 300.0, 70.0), 42.0]
			return [Vector3(sx * 150.0, f.y - 30.0 * signf(f.y), 60.0), 40.0]
		DRONE:
			return [Vector3(sx * 300.0, f.y - 140.0 * signf(_angle - PI), 190.0), 50.0]
		CROWD_CRANE:
			var y := _section_y()
			var eased := u * u * (3.0 - 2.0 * u)
			return [Vector3(sx * 120.0, y * 0.9, 45.0).lerp(Vector3(-sx * 40.0, y * 0.5, 165.0), eased),
					lerpf(42.0, 48.0, eased)]
		END_SWEEP:
			var end := signf(_angle - PI)
			return [Vector3(lerpf(-140.0, 140.0, u) * sx, end * 300.0, 110.0), 44.0]
		DOOR:
			return [Vector3(70.0, 55.0, 100.0), 36.0]
		DANCER:
			# from the ice's side of him (he shows off at the boards: an orbit
			# would put the eye over him), swinging slowly to and fro
			var a := _dance_heading + 0.5 * sin(0.3 * time + _angle)
			return [_inside(f + Vector3(sin(a) * 140.0, cos(a) * 140.0, 50.0), 50.0), 36.0]
		TRACK:
			return [_inside(f + Vector3(sx * 90.0, 90.0, 34.0), 34.0), 40.0]
		CROWD_CUT:
			return [Vector3(sx * 40.0, f.y - 40.0, 70.0), 40.0]
	return super._shot_eye(f)


## The match's view at the rink's first frame (the line-up's end): a
## camera of [param mode] (MwRinkCamera3D.Mode) placed for [param shown]
## (the sim camera's point) and [param shot] in a picture [param view]
## big, as the rink will place it: {transform, fov, near, far, ortho,
## scale}. A cinematic match starts with a fresh director (MwMatchIntro3D
## .detach), whose first shot this is.
static func match_view(mode: int, shown: Vector2, shot_: MwRinkShot3D, view: Vector2) -> Dictionary:
	var cam := MwRinkCamera3D.new()
	cam.mode = mode as MwRinkCamera3D.Mode
	cam.view = view
	cam.shot = shot_
	cam.snap()
	cam.follow(shown)
	var out := {"transform": cam.transform, "fov": cam.fov, "near": cam.near, "far": cam.far,
			"ortho": cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "scale": cam.world_scale()}
	cam.free()
	return out
