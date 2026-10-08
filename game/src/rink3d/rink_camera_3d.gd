class_name MwRinkCamera3D
extends Camera3D
## The 3D view's camera (plans 14 and 20). It follows the simulation's camera
## (MwRinkCamera: the 2D view's top-left map point, shakes included), which
## keeps running in all views - the original's on-screen test (`$5C3C`)
## makes it part of the gameplay - and, in the game's views, the play itself
## ([member shot], MwRinkShot3D). Presentation only: it looks, it changes
## nothing.
##
## Modes:
## * FOLLOW (F8, "Follow 3D"): looks at the ice under the 2D screen's centre
##   from the south, pitched [member pitch_deg] down, in perspective, framed
##   so about [member width_px] of the rink fit across at that point
##   (default: the 2D window's 320). At 45 deg heights and ice depth shrink
##   alike, as in the original's projection.
## * CALIBRATION: orthographic, 45 deg; with the world scaled sqrt 2 on its
##   up and north-south axes ([method world_scale]) this is exactly the
##   original's projection, pixel for pixel: the 3D scene must then draw
##   what the 2D one does (checks).
## * ORTHO (F2): the 2D view in 3D: the calibration camera's framing and
##   world scale through a long lens far away instead of a parallel
##   projection ([member ortho_distance_px]), so the side boards and glass
##   show some width, as the original's art fudges them.
## * TV (F3): one fixed pivot high in the west stands at centre ice
##   ([member side_out_px], [member side_height_px]), looking east across the
##   rink; it pans to the play (the puck and the 2D camera's look point,
##   smoothed) and zooms with how spread out the play is (the puck and the
##   players nearest it).
## * DOLLY (F4): the same height and side on a rail along the boards,
##   tracking the play's y, looking straight across; fixed focal length.
## * BIRDS_EYE / BIRDS_EYE_ACROSS (F5): the whole rink from high above,
##   tilted [member birds_eye_tilt_deg] from straight down; the goals top and
##   bottom (as the 2D) or left and right (looking east, bigger). Still.
## * FIRST_PERSON (F6): player 1's player's eyes (MwRinkShot3D.rider; else
##   the puck carrier, else the player nearest the puck): his point, looking
##   along his facing, the turn smoothed (critically damped, never a snap);
##   the view hides his own frames and any too close to the lens
##   ([method hidden_subject], [member lens_clear_px]).
## * CINEMATIC (F7): MwRinkDirector3D's shots, for footage.
## * OVERVIEW: the whole rink from above the near end (debug, warm-up).
## * REVERSE: FOLLOW from the north end looking south (debug).
## * FREE: placed by its owner (scripted shots, test/rink3d/crowd_cinema.gd);
##   [method follow] leaves it where it is.
##
## Smoothing is a critically damped spring stepped by the rendered frame's
## time ([member dt]): the same motion at any frame rate. [method snap]
## (a new mode, a jump in the play) puts the camera on its targets at once.
## Whatever the mode, each sprite shows the side the camera sees
## (MwRinkFacing3D).

enum Mode { FOLLOW, CALIBRATION, OVERVIEW, REVERSE, FREE, ORTHO, TV, DOLLY, BIRDS_EYE, BIRDS_EYE_ACROSS,
		FIRST_PERSON, CINEMATIC }

const S := MwRink3D.METRES_PER_PX
## The area the birds-eye views show: the ice and this much around it (px).
const BIRDS_EYE_MARGIN := 40.0

@export var mode := Mode.FOLLOW:
	set(v):
		if v != mode:
			_snap = true
		mode = v
@export_range(10.0, 90.0) var pitch_deg := 45.0
@export var distance_px := 340.0
@export var width_px := 320.0
## ORTHO: how far away the long lens is (px).
@export var ortho_distance_px := 2400.0
## TV / dolly: the camera's place west of the rink's centre line and its
## height (px; the west stands' top row is 381 px out, 212 px high).
@export var side_out_px := 430.0
@export var side_height_px := 320.0
## TV: the zoom's limits (vertical field of view, deg) and how much room
## the play gets around it (px).
@export var tv_fov_min := 9.0
@export var tv_fov_max := 34.0
@export var tv_margin_px := 70.0
## TV / dolly: how far ahead of the puck they aim (s at its speed).
@export var lead_s := 0.35
## Dolly: the field of view (vertical, deg) and how far along the rail it
## goes (|y|, px).
@export var dolly_fov := 30.0
@export var dolly_range_px := 250.0
## Birds-eye: the tilt from straight down (deg).
@export var birds_eye_tilt_deg := 18.0
## First person: the eye's height above the ice (px), the look down (deg),
## the field of view (vertical, deg), how near to the lens other frames
## may come before they are hidden (px).
@export var eye_height_px := 30.0
@export var first_pitch_deg := 7.0
@export var first_fov := 62.0
@export var lens_clear_px := 52.0

## The play this frame (the view's, blended between passes); null: only
## the sim camera's point is known.
var shot: MwRinkShot3D
## The rendered frame's time (s) the smoothing steps by; 0: no time passes.
var dt := 0.0
## The cinematic camera's director.
var director := MwRinkDirector3D.new()

var _turn := 0
var _snap := true
var _aim := Vector3.ZERO
var _aim_v := Vector3.ZERO
var _zoom := 20.0
var _zoom_v := 0.0
var _rail := 0.0
var _rail_v := 0.0
var _eye := Vector3.ZERO
var _eye_v := Vector3.ZERO
var _yaw := 0.0
var _yaw_v := 0.0
var _rider := ""
var _puck_last := Vector3.ZERO
var _vel := Vector3.ZERO
var _vel_v := Vector3.ZERO


## The world root's scale for this mode (CALIBRATION and ORTHO: sqrt 2 up
## and north-south, the original's projection).
func world_scale() -> Vector3:
	return Vector3(1, sqrt(2.0), sqrt(2.0)) if mode == Mode.CALIBRATION or mode == Mode.ORTHO else Vector3.ONE


## The camera's yaw (radians, 0 = looking north) in FOLLOW / REVERSE.
func yaw() -> float:
	return PI if mode == Mode.REVERSE else 0.0


## Where the camera looks, seen from above: radians clockwise from north
## (east PI / 2).
func heading() -> float:
	return MwRinkFacing3D.heading(self)


## The camera's heading in eighths of a turn clockwise from north, kept until
## the camera looks more than 30 deg away from it (not the 22.5 deg half
## step, so a heading near the boundary does not flip back and forth):
## player 1's pad turns by it in first person (plan 20, MwLiveInput).
func turn_eighths() -> int:
	var h := heading()
	if absf(angle_difference(h, _turn * PI / 4.0)) > deg_to_rad(30.0):
		_turn = posmod(roundi(h / (PI / 4.0)), 8)
	return _turn


## The next [method follow] puts the camera on its targets at once (a jump
## in the play, a new mode).
func snap() -> void:
	_snap = true


## The end boards (rink y) the camera looks over from beyond them, for the
## stands' cutaway (MwStands3D.cutaway); 0: none.
func cut_boards() -> float:
	match mode:
		Mode.FOLLOW, Mode.ORTHO:
			return MwStands.BOARD.y
		Mode.REVERSE:
			return -MwStands.BOARD.y
		Mode.CINEMATIC:
			return director.cut_boards
	return 0.0


## The subject (MwRinkDraw3D key prefix) whose frames the view hides: the
## first-person camera's rider. "" none.
func hidden_subject() -> String:
	return _rider if mode == Mode.FIRST_PERSON else ""


## The rink point (px) under the 2D screen's centre for the sim camera's
## [param shown] (top-left map point; fractional between passes).
static func look_point(shown: Vector2) -> Vector3:
	return MwRink3D.ice_under_map(shown + Vector2(MwRink3D.SCREEN) / 2.0)


## A critically damped spring's step towards [param target] over
## [param step] s ([param omega]: its stiffness, rad/s; it settles in about
## 4 / omega s): [position, velocity]. Implicit, so stable at any frame time
## (float or Vector3).
static func damp(x: Variant, v: Variant, target: Variant, omega: float, step: float) -> Array:
	var f := 1.0 + 2.0 * step * omega
	var oo := omega * omega
	var det := 1.0 / (f + step * step * oo)
	return [(x * f + v * step + target * (step * step * oo)) * det, (v + (target - x) * (step * oo)) * det]


## The camera at rink point [param eye] looking at rink point [param at] (px).
static func looking(eye: Vector3, at: Vector3) -> Transform3D:
	var e := MwRink3D.world(eye.x, eye.y, eye.z)
	var a := MwRink3D.world(at.x, at.y, at.z)
	return Transform3D(Basis.looking_at(a - e, Vector3.UP), e)


## The vertical field of view (deg) that just shows every rink point of
## [param points] from [param xf] (a camera transform, world).
static func fit_fov(xf: Transform3D, points: Array) -> float:
	var aspect := float(MwRink3D.SCREEN.x) / MwRink3D.SCREEN.y
	var t := 0.0
	var inv := xf.affine_inverse()
	for p: Vector3 in points:
		var c := inv * MwRink3D.world(p.x, p.y, p.z)
		var d := -c.z
		if d <= 0.001:
			continue
		t = maxf(t, maxf(absf(c.y) / d, absf(c.x) / d / aspect))
	return rad_to_deg(2.0 * atan(t))


## Places the camera for the sim camera's [param shown] (fractional between
## passes) and [member shot].
func follow(shown: Vector2) -> void:
	if mode == Mode.FREE:
		return
	var look := look_point(shown)
	var w := MwRink3D.world(look.x, look.y, look.z)
	var snapping := _snap
	_snap = false
	var step := 0.0 if snapping else dt
	projection = PROJECTION_PERSPECTIVE
	keep_aspect = KEEP_HEIGHT
	near = 0.1
	far = 400.0
	match mode:
		Mode.CALIBRATION:
			projection = PROJECTION_ORTHOGONAL
			size = MwRink3D.SCREEN.y * S
			var target := w * world_scale()
			var back := Vector3(0, sin(deg_to_rad(45.0)), cos(deg_to_rad(45.0)))
			transform = Transform3D(Basis.from_euler(Vector3(-deg_to_rad(45.0), 0, 0)), target + back * 100.0)
			near = 1.0
		Mode.OVERVIEW:
			fov = 50.0
			var centre := MwRink3D.world(0, 40, 0)
			transform = Transform3D(Basis.from_euler(Vector3(-deg_to_rad(55.0), 0, 0)),
					centre + Vector3(0, sin(deg_to_rad(55.0)), cos(deg_to_rad(55.0))) * 52.0)
		Mode.ORTHO:
			_ortho(w)
		Mode.TV:
			_tv(look, snapping, step)
		Mode.DOLLY:
			_dolly(look, snapping, step)
		Mode.BIRDS_EYE:
			_birds_eye(false)
		Mode.BIRDS_EYE_ACROSS:
			_birds_eye(true)
		Mode.FIRST_PERSON:
			if not _first_person(snapping, step):
				_follow_south(w)
		Mode.CINEMATIC:
			if not director.place(self, look, snapping, step):
				_follow_south(w)
		_:
			_follow_south(w)


## FOLLOW (and REVERSE).
func _follow_south(w: Vector3) -> void:
	var p := deg_to_rad(pitch_deg)
	var d := distance_px * S
	var half_w := atan((width_px / 2.0) / distance_px)
	fov = rad_to_deg(2.0 * atan(tan(half_w) * MwRink3D.SCREEN.y / MwRink3D.SCREEN.x))
	var y := yaw()
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))     # -forward of the basis below
	transform = Transform3D(Basis.from_euler(Vector3(-p, y, 0)), w + back * d)


## ORTHO: the calibration camera's framing (the world scaled as for it)
## through a long lens: 224 px of the original's screen fill the height at
## the look point.
func _ortho(w: Vector3) -> void:
	var target := w * world_scale()
	var back := Vector3(0, sin(deg_to_rad(45.0)), cos(deg_to_rad(45.0)))
	var d := ortho_distance_px * S
	fov = rad_to_deg(2.0 * atan(MwRink3D.SCREEN.y * S / 2.0 / d))
	transform = Transform3D(Basis.from_euler(Vector3(-deg_to_rad(45.0), 0, 0)), target + back * d)
	near = maxf(d - 60.0, 1.0)
	far = d + 120.0


## Where the side cameras aim: between the 2D camera's look point and
## where the puck is going ([member lead_s] ahead at its smoothed speed,
## as a camera operator leads the play), on the ice, kept off the boards.
func _play_aim(look: Vector3, snapping: bool, step: float) -> Vector3:
	var puck := shot.puck if shot != null else look
	if snapping:
		_vel = Vector3.ZERO
		_vel_v = Vector3.ZERO
		_puck_last = puck
	elif step > 0.0:
		var r := damp(_vel, _vel_v, (puck - _puck_last) / step, 6.0, step)
		_vel = r[0]
		_vel_v = r[1]
		_puck_last = puck
	var lead := _vel * lead_s
	lead.z = 0.0
	var a := look.lerp(puck + lead.limit_length(120.0), 0.6)
	return Vector3(clampf(a.x, -150.0, 150.0), clampf(a.y, -330.0, 330.0), 0.0)


## TV: pans from its pivot to the play, zooms with its spread.
func _tv(look: Vector3, snapping: bool, step: float) -> void:
	var pivot := Vector3(-side_out_px, 0, side_height_px)
	var aim := _play_aim(look, snapping, step)
	var r := 0.0
	var pts: Array = [aim]
	if shot != null:
		pts.append(shot.puck)
		pts.append_array(Array(shot.nearest_to_puck(3)))
	for p: Vector3 in pts:
		r = maxf(r, Vector2(p.x - aim.x, p.y - aim.y).length())
	var dist := (pivot - aim).length()
	var aspect := float(MwRink3D.SCREEN.x) / MwRink3D.SCREEN.y
	var want := clampf(rad_to_deg(2.0 * atan(((r + tv_margin_px) / dist) / aspect)), tv_fov_min, tv_fov_max)
	if snapping:
		_aim = aim
		_aim_v = Vector3.ZERO
		_zoom = want
		_zoom_v = 0.0
	else:
		# stiffer the further the play has got away (a fast pass or shot), and
		# quicker to zoom out than in: the play stays in the picture
		var away := clampf((Vector2(aim.x - _aim.x, aim.y - _aim.y).length() - 60.0) / 200.0, 0.0, 1.0)
		var a := damp(_aim, _aim_v, aim, lerpf(4.5, 10.0, away), step)
		_aim = a[0]
		_aim_v = a[1]
		var z := damp(_zoom, _zoom_v, want, 4.0 if want > _zoom else 1.5, step)
		_zoom = z[0]
		_zoom_v = z[1]
	fov = _zoom
	transform = looking(pivot, _aim)
	near = 1.0


## Dolly: along the rail with the play's y, looking straight across.
func _dolly(look: Vector3, snapping: bool, step: float) -> void:
	var want := clampf(_play_aim(look, snapping, step).y, -dolly_range_px, dolly_range_px)
	if snapping:
		_rail = want
		_rail_v = 0.0
	else:
		var away := clampf((absf(want - _rail) - 60.0) / 200.0, 0.0, 1.0)     # as the TV camera
		var a := damp(_rail, _rail_v, want, lerpf(3.5, 9.0, away), step)
		_rail = a[0]
		_rail_v = a[1]
	fov = dolly_fov
	transform = looking(Vector3(-side_out_px, _rail, side_height_px), Vector3(10.0, _rail, 0.0))
	near = 1.0


## Birds-eye: the whole area, still; [param across]: looking east, the
## goals left and right.
func _birds_eye(across: bool) -> void:
	var tilt := deg_to_rad(birds_eye_tilt_deg)
	var h := 1500.0
	var off := h * tan(tilt)
	var eye := Vector3(-off, 0, h) if across else Vector3(0, off, h)
	var at := Vector3.ZERO
	var e := MwRink3D.world(eye.x, eye.y, eye.z)
	var up := Vector3.RIGHT if across else Vector3.FORWARD     # the screen's up: east (across) or north
	transform = Transform3D(Basis.looking_at(MwRink3D.world(at.x, at.y, at.z) - e, up), e)
	var bx := MwStands.BOARD.x + BIRDS_EYE_MARGIN
	var by := MwStands.BOARD.y + BIRDS_EYE_MARGIN
	var corners := []
	for x in [-bx, bx]:
		for y in [-by, by]:
			corners.append(Vector3(x, y, 0))
			corners.append(Vector3(x, y, 48))
	fov = fit_fov(transform, corners)
	near = 10.0
	far = 200.0


## First person: [member shot]'s rider's eyes. False: nobody to ride with.
func _first_person(snapping: bool, step: float) -> bool:
	if shot == null or shot.rider == "":
		_rider = ""
		return false
	var b := shot.rider_at
	var eye := Vector3(b.x, b.y, maxf(b.z, 0.0) + eye_height_px)
	if snapping or _rider == "":
		_eye = eye
		_eye_v = Vector3.ZERO
		_yaw = shot.rider_heading
		_yaw_v = 0.0
	else:
		var a := damp(_eye, _eye_v, eye, 9.0, step)
		_eye = a[0]
		_eye_v = a[1]
		var target := _yaw + angle_difference(_yaw, shot.rider_heading)
		var y := damp(_yaw, _yaw_v, target, 5.0, step)
		_yaw = wrapf(y[0], -PI, PI)
		_yaw_v = y[1]
	_rider = shot.rider
	var p := deg_to_rad(first_pitch_deg)
	var dir := Vector3(sin(_yaw) * cos(p), -sin(p), -cos(_yaw) * cos(p))
	var e := MwRink3D.world(_eye.x, _eye.y, _eye.z)
	transform = Transform3D(Basis.looking_at(dir, Vector3.UP), e)
	fov = first_fov
	near = 0.05
	return true
