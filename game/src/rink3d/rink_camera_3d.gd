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
## * EXTENDED (plan 34, "3D EXTENDED"; owner: zooming in and out to keep the
##   puck and every character a player drives in frame; then never nearer
##   than the regular 3D camera, with as much ice round the puck as it
##   shows): FOLLOW's heading, tilt and field of view, and at least
##   FOLLOW's picture - it shows all FOLLOW shows (FOLLOW's eye,
##   [method follow_eye], is inside its view) and widens
##   from there only to keep the puck and the characters players drive
##   ([method MwRinkShot3D.targets]) in the picture, each with a margin
##   ([member extended_margin_px]) and a skater's height
##   ([member skater_height_px]): the least such picture
##   ([method extended_goal], [method fit]). With every target in FOLLOW's
##   picture it is FOLLOW's, so the puck has FOLLOW's room round it. What
##   it adds to FOLLOW - the point looked at moved and the distance grown -
##   follows critically damped springs ([method spring]), zooming out
##   faster ([member extended_out_s]) than in ([member extended_in_s]), with
##   small changes ignored ([member extended_dead_px],
##   [member extended_dead]) and a nearer picture only after it has been
##   asked for a moment ([member extended_hold_s]); FOLLOW's own motion (the
##   sim camera's) is not smoothed again. Whatever the springs say, the
##   distance is never less than what shows FOLLOW's picture and every
##   target from where the point is ([method extended_keep],
##   [constant EXTENDED_KEEP_PX]): never nearer than FOLLOW, and a breakaway
##   never leaves the picture; the spring keeps clear of that floor
##   ([constant EXTENDED_EASE_PX], [constant EXTENDED_URGE]), which follows
##   the play raw and so judders. Cuts (a new rink entry: the faceoff line-up,
##   the opening's hand-over; a replay) jump: [method snap].
## * EXTENDED_ORTHO (plan 44, "2D EXTENDED"; owner: the unused orthographic
##   view, zooming to fit all human players like 3D EXTENDED, built on its
##   code so the two behave alike): EXTENDED with ORTHO's lens - its 45 deg,
##   its long lens and its world scale (the original's projection) - in
##   place of FOLLOW's: the same fit, springs, dead zones, hold, floor and
##   far limit, worked in ORTHO's scaled space ([method ext_space]); never
##   nearer than ORTHO's picture, and zooming by moving back along the line
##   of sight, so the picture keeps ORTHO's look.
## * OVERVIEW: the whole rink from above the near end (debug, warm-up).
## * REVERSE: FOLLOW from the north end looking south (debug).
## * FREE: placed by its owner (scripted shots, test/rink3d/crowd_cinema.gd);
##   [method follow] leaves it where it is.
##
## Widescreen (plan 25): [member view] is the picture's shape. The modes
## that frame the original's screen keep its 224 px high (KEEP_HEIGHT: a
## wider picture shows more beside it), and a picture taller than 224 (a
## window narrower than the original's) grows them to keep its 320 across;
## the fitting modes (TV, birds-eye) fit to the whole picture.
##
## Smoothing is a critically damped spring stepped by the rendered frame's
## time ([member dt]): the same motion at any frame rate. [method snap]
## (a new mode, a jump in the play) puts the camera on its targets at once.
## Whatever the mode, each sprite shows the side the camera sees
## (MwRinkFacing3D).

enum Mode { FOLLOW, CALIBRATION, OVERVIEW, REVERSE, FREE, ORTHO, TV, DOLLY, BIRDS_EYE, BIRDS_EYE_ACROSS,
		FIRST_PERSON, CINEMATIC, EXTENDED, EXTENDED_ORTHO }

const S := MwRink3D.METRES_PER_PX
## The area the birds-eye views show: the ice and this much around it (px).
const BIRDS_EYE_MARGIN := 40.0
## EXTENDED: how far round each target's point the picture must always
## reach, whatever its springs are doing (px; a quarter of a skater's
## width - was 8: the floor follows the play raw, 30 passes a second, and
## as the zoom it judders, so it is for a burst the spring cannot follow
## - owner, 2026-10-12), up to a skater's height above it.
const EXTENDED_KEEP_PX := 4.0
## EXTENDED: the room round each target's point (px) the distance's spring
## heads for at the least, from where its point is (the point's spring
## trailing the goal's, the goal's distance can be too near from there):
## the spring, not the floor, keeps the targets in (less than
## [member extended_margin_px], so the dead zone still holds).
const EXTENDED_EASE_PX := 12.0
## EXTENDED: zooming out, the spring quickens near the floor, up to this
## many times more ([constant EXTENDED_URGE_PX] px over it: not at all; on
## it: all of it), so a quick spreading of the play is followed by the
## spring rather than by the floor.
const EXTENDED_URGE := 1.5
const EXTENDED_URGE_PX := 32.0
## EXTENDED: how far the distance may go past the far limit (the whole rink,
## [method extended_far]) to keep the targets in the picture while its point
## catches up (a share of the limit).
const EXTENDED_OVER := 1.25
## EXTENDED's longest step (s): a longer frame is stepped in parts this
## long, the targets moving evenly from the frame before's, so a slow frame
## rate goes through the same steps as a fast one (and at most
## [constant EXTENDED_STEPS] of them: a hitch).
const EXTENDED_STEP := 1.0 / 240.0
const EXTENDED_STEPS := 60

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
## EXTENDED (plan 34): the room round each target on the ice (px) and the
## height it reaches (px: a skater's - the tallest characters' frames, so
## heads stay in the picture); the springs' settling times (s): zooming
## out, zooming in, the point; the dead zones: the point (px) and the
## distance (a share of it); how long the targets must ask for a nearer
## picture before it zooms in (s: a player switching to a nearer character,
## then the play spreading again, would otherwise pump in and out).
@export var extended_margin_px := 16.0
@export var skater_height_px := 48.0
@export var extended_out_s := 0.25
@export var extended_in_s := 1.0
@export var extended_point_s := 0.6
@export var extended_dead_px := 4.0
@export var extended_dead := 0.03
@export var extended_hold_s := 0.5

## The play this frame (the view's, blended between passes); null: only
## the sim camera's point is known.
var shot: MwRinkShot3D
## The picture's shape in the original's pixels (MwRink3DHost.view_size):
## the 320 x 224 screen, or wider or taller (plan 25).
var view := Vector2(MwRink3D.SCREEN)
## The rendered frame's time (s) the smoothing steps by; 0: no time passes.
var dt := 0.0
## The shown frame's own clock (s, blended between passes; < 0 none): the
## match's opening's (plan 33), for its director's glide.
var clock := -1.0
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
var _ext_live := false          # EXTENDED has placed itself from a shot since the last snap
var _ext_at := Vector3.ZERO     # its point looked at (rink px, on the ice) and distance (px) as placed
var _ext_d := 0.0
var _ext_off := Vector3.ZERO    # the springs: what it adds to FOLLOW - the point moved from FOLLOW's
var _ext_off_v := Vector3.ZERO  # look point, the distance past FOLLOW's - and their speeds
var _ext_dd := 0.0
var _ext_dd_v := 0.0
var _ext_goal_off := Vector3.ZERO  # what the springs head for (the dead zones' held goals)
var _ext_goal_dd := 0.0
var _ext_aim_dd := 0.0          # what the distance's spring heads for (the goal, or held while it waits)
var _ext_keep := 0.0            # the floor as last placed (px), and whether it held the distance
var _ext_on := false
var _ext_wait := 0.0            # how long the goal has been nearer than the distance (s)
var _ext_look := Vector3.ZERO   # FOLLOW's look point, the targets and the drivers' subjects of the frame before
var _ext_targets := PackedVector3Array()
var _ext_keys := PackedStringArray()


## The world root's scale for this mode (CALIBRATION, ORTHO and 2D
## EXTENDED: sqrt 2 up and north-south, the original's projection;
## CINEMATIC: its director's).
func world_scale() -> Vector3:
	if mode == Mode.CINEMATIC:
		return director.world_scale()
	if mode == Mode.CALIBRATION or mode == Mode.ORTHO or mode == Mode.EXTENDED_ORTHO:
		return Vector3(1, sqrt(2.0), sqrt(2.0))
	return Vector3.ONE


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
		Mode.FOLLOW, Mode.ORTHO, Mode.EXTENDED, Mode.EXTENDED_ORTHO:
			return MwRinkShape.BOARD.y
		Mode.REVERSE:
			return -MwRinkShape.BOARD.y
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


## [method damp]'s spring solved exactly over [param step] s: [position,
## velocity]. The target moves evenly from [param from] (null: it is held at
## [param target]) to [param target] over the step, as the play does between
## two passes, so any number of frames over the same time end in the same
## place: the motion is no frame rate's own (plan 34's 3D EXTENDED; float or
## Vector3).
static func spring(x: Variant, v: Variant, target: Variant, omega: float, step: float, from: Variant = null) -> Array:
	if step <= 0.0:
		return [x, v]
	var rate: Variant = target * 0.0 if typeof(from) == TYPE_NIL else (target - from) / step
	var lag: Variant = rate * (2.0 / omega)              # how far a steady chase stays behind
	var a: Variant = x - (target - rate * step) + lag
	var b: Variant = v - rate + a * omega
	var decay := exp(-omega * step)
	return [target - lag + (a + b * step) * decay, rate + (b - (a + b * step) * omega) * decay]


## [param from] moved towards [param to] until it is at most [param zone]
## away (a dead zone: what moves inside it is ignored; float or Vector3).
static func trail(from: Variant, to: Variant, zone: float) -> Variant:
	var gap: Variant = to - from
	var n: float = absf(gap) if gap is float else (gap as Vector3).length()
	if n <= zone:
		return from
	return from + gap * (1.0 - zone / n)


## Plan 40 (R7): the camera glides' view blend - the match's opening's and
## the rink editor's (moved from MwIntroDirector3D).

## A camera basis's heading (rad, round the vertical; the shorter way is
## the caller's) and tilt (rad, + up).
static func heading_tilt(b: Basis) -> Vector2:
	var f := -b.z
	var tilt := asin(clampf(f.y, -1.0, 1.0))
	var view_heading := atan2(f.x, f.z)
	return Vector2(view_heading, tilt)


## [param from] blended into [param to] by [param weight] (0..1): the place
## along the line between them, the heading the shorter way round, the tilt
## between the two (never past either: a blend of headings half a turn
## apart doesn't swing over the top, as a slerp of the two would); no roll.
## [param to] itself at 1.
static func blend_view(from: Transform3D, to: Transform3D, weight: float) -> Transform3D:
	if weight >= 1.0:
		return to
	var a := heading_tilt(from.basis)
	var b := heading_tilt(to.basis)
	var view_heading := a.x + wrapf(b.x - a.x, -PI, PI) * weight
	var tilt := lerpf(a.y, b.y, weight)
	var dir := Vector3(cos(tilt) * sin(view_heading), sin(tilt), cos(tilt) * cos(view_heading))
	return Transform3D(Basis.looking_at(dir, Vector3.UP), from.origin.lerp(to.origin, weight))


## The camera at rink point [param eye] looking at rink point [param at] (px).
static func looking(eye: Vector3, at: Vector3) -> Transform3D:
	var origin := MwRink3D.world(eye.x, eye.y, eye.z)
	var a := MwRink3D.world(at.x, at.y, at.z)
	return Transform3D(Basis.looking_at(a - origin, Vector3.UP), origin)


## The picture's width over its height ([member view]).
func aspect() -> float:
	return view.x / view.y


## The vertical field of view (deg) that just shows every rink point of
## [param points] from [param xf] (a camera transform, world) in a picture
## of [param ratio] (width / height; default: the original's).
static func fit_fov(xf: Transform3D, points: Array, ratio := float(MwRink3D.SCREEN.x) / MwRink3D.SCREEN.y) -> float:
	var t := 0.0
	var inv := xf.affine_inverse()
	for point: Vector3 in points:
		var c := inv * MwRink3D.world(point.x, point.y, point.z)
		var d := -c.z
		if d <= 0.001:
			continue
		t = maxf(t, maxf(absf(c.y) / d, absf(c.x) / d / ratio))
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
		Mode.EXTENDED, Mode.EXTENDED_ORTHO:
			_extended(look, w, snapping, step)
		_:
			_follow_south(w)
	if not mode in [Mode.TV, Mode.BIRDS_EYE, Mode.BIRDS_EYE_ACROSS]:
		_taller()


## A picture taller than the original's (plan 25: a window narrower than
## 320 x 224): the framing made for 224 px high grows with it, so the 320
## across still show (a wider one gets its sides from KEEP_HEIGHT).
func _taller() -> void:
	var k := view.y / MwRink3D.SCREEN.y
	if k <= 1.0:
		return
	if projection == PROJECTION_ORTHOGONAL:
		size *= k
	else:
		fov = taller_fov(fov)


## The field of view [param f] (vertical, deg) framed for the original's 224
## px high, in this picture (taller: wider; [method _taller]); [param back]:
## the other way, the framing a field of view of this picture came from.
func taller_fov(f: float, back := false) -> float:
	var k := view.y / MwRink3D.SCREEN.y
	if k <= 1.0:
		return f
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(f) / 2.0) * (1.0 / k if back else k)))


## FOLLOW's field of view (vertical, deg, for the original's 224 px high):
## [member width_px] across at [member distance_px].
func follow_fov() -> float:
	var half_w := atan((width_px / 2.0) / distance_px)
	return rad_to_deg(2.0 * atan(tan(half_w) * MwRink3D.SCREEN.y / MwRink3D.SCREEN.x))


## FOLLOW (and REVERSE).
func _follow_south(w: Vector3) -> void:
	var pitch := deg_to_rad(pitch_deg)
	var d := distance_px * S
	fov = follow_fov()
	var y := yaw()
	var back := Vector3(sin(y) * cos(pitch), sin(pitch), cos(y) * cos(pitch))     # -forward of the basis below
	transform = Transform3D(Basis.from_euler(Vector3(-pitch, y, 0)), w + back * d)


## ORTHO's field of view (vertical, deg, for the original's 224 px high):
## the 224 px fill the height at [member ortho_distance_px].
func ortho_fov() -> float:
	return rad_to_deg(2.0 * atan(MwRink3D.SCREEN.y / 2.0 / ortho_distance_px))


## ORTHO: the calibration camera's framing (the world scaled as for it)
## through a long lens: 224 px of the original's screen fill the height at
## the look point.
func _ortho(w: Vector3) -> void:
	var target := w * world_scale()
	var back := Vector3(0, sin(deg_to_rad(45.0)), cos(deg_to_rad(45.0)))
	var d := ortho_distance_px * S
	fov = ortho_fov()
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
	for point: Vector3 in pts:
		r = maxf(r, Vector2(point.x - aim.x, point.y - aim.y).length())
	var dist := (pivot - aim).length()
	var want := clampf(rad_to_deg(2.0 * atan(((r + tv_margin_px) / dist) / aspect())), tv_fov_min, tv_fov_max)
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
	var origin := MwRink3D.world(eye.x, eye.y, eye.z)
	var up := Vector3.RIGHT if across else Vector3.FORWARD     # the screen's up: east (across) or north
	transform = Transform3D(Basis.looking_at(MwRink3D.world(at.x, at.y, at.z) - origin, up), origin)
	var bx := MwRinkShape.BOARD.x + BIRDS_EYE_MARGIN
	var by := MwRinkShape.BOARD.y + BIRDS_EYE_MARGIN
	var corners := []
	for x in [-bx, bx]:
		for y in [-by, by]:
			corners.append(Vector3(x, y, 0))
			corners.append(Vector3(x, y, 48))
	fov = fit_fov(transform, corners, aspect())
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
	var pitch := deg_to_rad(first_pitch_deg)
	var dir := Vector3(sin(_yaw) * cos(pitch), -sin(pitch), -cos(_yaw) * cos(pitch))
	var origin := MwRink3D.world(_eye.x, _eye.y, _eye.z)
	transform = Transform3D(Basis.looking_at(dir, Vector3.UP), origin)
	fov = first_fov
	near = 0.05
	return true


# --- 3D EXTENDED (plan 34) and 2D EXTENDED (plan 44) ----------------------------------------------

## Plan 44: the lens EXTENDED fits with - 3D EXTENDED FOLLOW's, 2D EXTENDED
## (EXTENDED_ORTHO) ORTHO's: its pitch (radians), field of view (deg, for
## the original's 224 px high), distance (px) and the space it is fitted in
## ([method ext_space]).
func ext_pitch() -> float:
	return deg_to_rad(45.0) if mode == Mode.EXTENDED_ORTHO else deg_to_rad(pitch_deg)


## EXTENDED's field of view (deg, for the original's 224 px high): ORTHO's in 2D EXTENDED
## (EXTENDED_ORTHO), FOLLOW's in 3D EXTENDED (plan 44).
func ext_fov() -> float:
	return ortho_fov() if mode == Mode.EXTENDED_ORTHO else follow_fov()


## The lens's distance (px) EXTENDED fits with: [member ortho_distance_px] in 2D EXTENDED
## (EXTENDED_ORTHO), FOLLOW's [member distance_px] in 3D EXTENDED (plan 44).
func ext_base_px() -> float:
	return ortho_distance_px if mode == Mode.EXTENDED_ORTHO else distance_px


## Plan 44: rink px (x east, y south, z up) as the space EXTENDED fits in:
## 3D EXTENDED's is the rink's own; 2D EXTENDED's ORTHO's world, sqrt 2
## north-south and up ([method world_scale] - the original's projection
## seen at 45 deg). EXTENDED's points looked at, its look points and its
## targets' boxes are in this space ([method extended_goal],
## [method extended_at]): a rink point times it.
func ext_space() -> Vector3:
	return Vector3(1, sqrt(2.0), sqrt(2.0)) if mode == Mode.EXTENDED_ORTHO else Vector3.ONE


## EXTENDED: the camera's half view across and up as tangents (x, y), for
## the picture's shape ([member view]; the lens's field of view, grown for
## a taller picture as [method _taller] grows it).
func half_tans() -> Vector2:
	var tv := tan(deg_to_rad(taller_fov(ext_fov())) / 2.0)
	return Vector2(tv * aspect(), tv)


## The least distance (px, along the line of sight) from which a camera
## looking north, pitched [param pitch] (radians) down at rink point
## [param at] on the ice, with half view tangents [param tans] (x across, y
## up), shows every rink point of [param points]: a point [i]ahead[/i] px
## nearer the camera than [param at] along the line of sight and [i]across[/i]
## / [i]up[/i] px off it needs ahead + across / tan x and ahead + up / tan y.
static func reach(points: PackedVector3Array, at: Vector3, tans: Vector2, pitch: float) -> float:
	var sp := sin(pitch)
	var cp := cos(pitch)
	var d := 0.0
	for point_2 in points:
		var dy := point_2.y - at.y
		var dz := point_2.z - at.z
		var ahead := dz * sp + dy * cp
		var up := dz * cp - dy * sp
		d = maxf(d, ahead + maxf(absf(point_2.x - at.x) / tans.x, absf(up) / tans.y))
	return d


## The box round [param targets] (rink px) on the ice, [param margin] px
## wider each way, as a solid [param height] px high above the highest of
## them: its eight corners.
static func box(targets: PackedVector3Array, margin: float, height: float) -> PackedVector3Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var top := 0.0
	for t in targets:
		lo = lo.min(Vector2(t.x, t.y))
		hi = hi.max(Vector2(t.x, t.y))
		top = maxf(top, t.z)
	var out := PackedVector3Array()
	for x in [lo.x - margin, hi.x + margin]:
		for y in [lo.y - margin, hi.y + margin]:
			out.append(Vector3(x, y, 0.0))
			out.append(Vector3(x, y, top + height))
	return out


## The camera looking north, pitched [param pitch] (radians) down, with half
## view tangents [param tans] (x across, y up), that shows every rink point
## of [param points] (px) from as near as it can: [the point it looks at (on
## the ice), its distance (px, along the line of sight)]. Each edge of the
## picture is a plane through the camera, and a point is in the picture on
## the inner side of all four; the heading and lens fixed, the planes keep
## their slopes, so the camera may stand on the outer side of four planes of
## the same slopes, each through the point that presses hardest on that
## edge. Across, it stands midway between the left and right ones; up and
## down, where the top and bottom ones meet - pulled straight back along its
## line of sight when the picture must be further off to be wide enough
## (the room that leaves shared above and below).
static func fit(points: PackedVector3Array, tans: Vector2, pitch: float) -> Array:
	var sp := sin(pitch)
	var cp := cos(pitch)
	var fwd := Vector3(0, -cp, -sp)                 # rink px: x east, y south, z up
	var up := Vector3(0, -sp, cp)
	var planes: Array[Vector3] = [fwd * tans.x - Vector3.RIGHT, fwd * tans.x + Vector3.RIGHT,   # right, left
			fwd * tans.y - up, fwd * tans.y + up]                                             # top, bottom
	var m: Array[float] = [INF, INF, INF, INF]      # (a point q is in the picture of a camera at e when
	for point_2 in points:                                #  every plane's n . (q - e) >= 0: e's n . e <= n . q)
		for i in 4:
			m[i] = minf(m[i], planes[i].dot(point_2))
	var back := maxf(-(m[2] + m[3]) / (2.0 * tans.y), -(m[0] + m[1]) / (2.0 * tans.x))
	var lift := (m[3] - m[2]) / 2.0
	var eye := Vector3((m[1] - m[0]) / 2.0, back * cp - lift * sp, back * sp + lift * cp)
	var d := eye.z / sp
	return [Vector3(eye.x, eye.y - d * cp, 0.0), d]


## FOLLOW's eye (rink px) when it looks at [param look] (the ice under the
## 2D screen's centre): [member distance_px] back along its line of sight -
## plan 44: the lens's ([method ext_base_px], [method ext_pitch]; 2D
## EXTENDED: ORTHO's, [param look] in its space, [method ext_space]).
func follow_eye(look: Vector3) -> Vector3:
	var pitch := ext_pitch()
	var d := ext_base_px()
	return Vector3(look.x, look.y + cos(pitch) * d, look.z + sin(pitch) * d)


## EXTENDED's far limit (px): the distance that shows the whole rink (the
## boards and the margin round them, a skater high) looked at from centre
## ice, at the picture's shape. Its distance never goes much past it
## ([constant EXTENDED_OVER]).
func extended_far() -> float:
	var b := MwRinkShape.BOARD + Vector2.ONE * extended_margin_px
	var corners := _spaced(box(PackedVector3Array([Vector3(-b.x, -b.y, 0), Vector3(b.x, b.y, 0)]), 0.0,
			skater_height_px))
	return reach(corners, Vector3.ZERO, half_tans(), ext_pitch())


## Rink points [param points] in EXTENDED's space ([method ext_space]).
func _spaced(points: PackedVector3Array) -> PackedVector3Array:
	var k := ext_space()
	if k == Vector3.ONE:
		return points
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i] * k
	return out


## The points EXTENDED must show for [param targets] (rink px) with FOLLOW
## looking at [param look] (in EXTENDED's space, [method ext_space]):
## FOLLOW's eye - a camera of the same heading and lens that sees it sees
## all FOLLOW sees (2D EXTENDED: ORTHO's) - and round each target
## [param margin] px on the ice and a skater's height above (made in rink
## px, then put in EXTENDED's space).
func _musts(targets: PackedVector3Array, look: Vector3, margin: float, with_follow := true) -> PackedVector3Array:
	var boxes := PackedVector3Array()
	for t in targets:
		boxes.append_array(box(PackedVector3Array([t]), margin, skater_height_px))
	var out := PackedVector3Array([follow_eye(look)] if with_follow else [])
	out.append_array(_spaced(boxes))
	return out


## Where EXTENDED wants to be for [param targets] (the puck first, then the
## drivers; rink px) with FOLLOW looking at [param look]: [the point looked
## at (on the ice), the distance (px)] - the least picture ([method fit])
## that shows FOLLOW's and each target with [member extended_margin_px]
## round it and [member skater_height_px] above. Every target in FOLLOW's
## picture: FOLLOW's own point and distance.
func extended_goal(targets: PackedVector3Array, look: Vector3) -> Array:
	return fit(_musts(targets, look, extended_margin_px), half_tans(), ext_pitch())


## The least distance (px) that shows FOLLOW's picture (FOLLOW looking at
## [param look]) and every one of [param targets] (its point,
## [constant EXTENDED_KEEP_PX] round it and a skater's height above) from
## point [param at]: what EXTENDED never goes nearer than.
func extended_keep(targets: PackedVector3Array, look: Vector3, at: Vector3) -> float:
	return extended_reach(targets, look, at, EXTENDED_KEEP_PX)


## The least distance (px) that shows FOLLOW's picture (FOLLOW looking at
## [param look]) and every one of [param targets] ([param margin] px round
## its point and a skater's height above) from point [param at]: from
## [method extended_goal]'s point, its distance.
func extended_reach(targets: PackedVector3Array, look: Vector3, at: Vector3, margin := extended_margin_px) -> float:
	return reach(_musts(targets, look, margin), at, half_tans(), ext_pitch())


## EXTENDED's point looked at (rink px, on the ice) and distance (px) as last
## placed.
func extended_at() -> Vector3:
	return _ext_at


## EXTENDED's distance (px) as last placed (its point: [method extended_at]).
func extended_distance() -> float:
	return _ext_d


## EXTENDED: FOLLOW's placement for [param look] (the ice under the 2D
## screen's centre; [param w] in the world) plus what [member shot]'s
## targets ask for ([method extended_goal]), that eased by the springs and
## their dead zones, never nearer than [method extended_keep]; stepped in
## parts of at most [constant EXTENDED_STEP], the targets and FOLLOW's look
## point going evenly from the frame before's to these, as the view's blend
## moves them: a driver who jumped is where he is now, a jump of the 2D
## camera too, and drivers who changed (a player switching) change at the
## frame's end, where the blend changes them. A frame with no time: the
## springs stay, FOLLOW's point moves. FOLLOW's placement while there is no
## shot (the next one then snaps).
func _extended(look: Vector3, w: Vector3, snapping: bool, step: float) -> void:
	if shot == null:
		_ext_live = false
		if mode == Mode.EXTENDED_ORTHO:
			_ortho(w)
		else:
			_follow_south(w)
		return
	look *= ext_space()                        # (plan 44: 2D EXTENDED fits in ORTHO's space)
	var targets := shot.targets()
	if snapping or not _ext_live:
		var goal := extended_goal(targets, look)
		_ext_off = goal[0] - look
		_ext_off_v = Vector3.ZERO
		_ext_dd = goal[1] - ext_base_px()
		_ext_dd_v = 0.0
		_ext_goal_off = _ext_off
		_ext_goal_dd = _ext_dd
		_ext_aim_dd = _ext_dd
		_ext_wait = 0.0
		_ext_place(targets, look)
	elif step > 0.0:
		var same := _ext_targets.size() == targets.size() and _ext_keys == shot.driver_keys
		var jumped := _ext_look.distance_to(look) > MwRinkBlend3D.SNAP_PX
		var n := clampi(ceili(step / EXTENDED_STEP - 1e-6), 1, EXTENDED_STEPS)
		for i in n:
			var k := float(i + 1) / n
			var now := targets
			if same:
				now = PackedVector3Array()
				for j in targets.size():
					var a := _ext_targets[j]
					var b := targets[j]
					now.append(b if j > 0 and a.distance_to(b) > MwRinkBlend3D.SNAP_PX else a.lerp(b, k))
			elif i < n - 1 and not _ext_targets.is_empty():
				now = _ext_targets.duplicate()          # the drivers before, the puck going on
				now[0] = _ext_targets[0].lerp(targets[0], k)
			_extended_step(now, look if jumped else _ext_look.lerp(look, k), step / n)
	else:
		_ext_place(targets, look)
	_ext_targets = targets
	_ext_keys = shot.driver_keys
	_ext_look = look
	_ext_live = true
	var pitch := ext_pitch()
	fov = ext_fov()
	var back := Vector3(0, sin(pitch), cos(pitch))
	transform = Transform3D(Basis.from_euler(Vector3(-pitch, 0, 0)),
			MwRink3D.world(_ext_at.x, _ext_at.y, 0.0) + back * (_ext_d * S))
	if mode == Mode.EXTENDED_ORTHO:
		near = maxf(_ext_d * S - 60.0, 1.0)      # (ORTHO's: the long lens far away)
		far = _ext_d * S + 120.0


## One step of EXTENDED's springs over [param step] s towards what
## [param targets] ask for with FOLLOW looking at [param look] (each goal
## reached evenly over the step; a nearer distance only once it has been
## asked for [member extended_hold_s]; no dead zone when FOLLOW's picture is
## all it asks for - it is then FOLLOW's exactly), then the floor. The point
## first: the distance's goal is never nearer than what shows the targets
## with [constant EXTENDED_EASE_PX] round them from where the point now is
## (its spring trails the goal's point), and zooming out the spring quickens
## near the floor ([constant EXTENDED_URGE]) - so the spring, not the floor,
## keeps the targets in: the floor follows the play raw, its 30 passes a
## second and all, and as the zoom it juddered (owner, 2026-10-12: it was
## the distance in a fifth of a match's frames, now hardly ever).
func _extended_step(targets: PackedVector3Array, look: Vector3, step: float) -> void:
	var goal := extended_goal(targets, look)
	var off: Vector3 = goal[0] - look
	var base := ext_base_px()
	var own: bool = goal[1] - base < 0.001 and off.length() < 0.001
	var off_was := _ext_goal_off
	_ext_goal_off = Vector3.ZERO if own else trail(_ext_goal_off, off, extended_dead_px)
	var a := spring(_ext_off, _ext_off_v, _ext_goal_off, 4.0 / extended_point_s, step, off_was)
	_ext_off = a[0]
	_ext_off_v = a[1]
	var at := Vector3(look.x + _ext_off.x, look.y + _ext_off.y, 0.0)
	var aim_was := _ext_aim_dd
	_ext_goal_dd = 0.0 if own else trail(_ext_goal_dd, goal[1] - base, goal[1] * extended_dead)
	var easing := reach(_musts(targets, look, EXTENDED_EASE_PX, false), at, half_tans(), ext_pitch())
	_ext_goal_dd = maxf(_ext_goal_dd, easing - base)
	if _ext_goal_dd < _ext_dd:
		if _ext_wait == 0.0:
			_ext_aim_dd = _ext_dd               # held where it is while it waits
			aim_was = _ext_aim_dd
		_ext_wait += step
		if _ext_wait > extended_hold_s:
			_ext_aim_dd = _ext_goal_dd
	else:
		_ext_wait = 0.0
		_ext_aim_dd = _ext_goal_dd
	var omega := 4.0 / extended_in_s
	if _ext_aim_dd > _ext_dd:                  # out: quicker, and quicker still near the floor
		var over := base + _ext_dd - extended_keep(targets, look, at)
		omega = 4.0 / extended_out_s * (1.0 + EXTENDED_URGE * clampf(1.0 - over / EXTENDED_URGE_PX, 0.0, 1.0))
	var z := spring(_ext_dd, _ext_dd_v, _ext_aim_dd, omega, step, aim_was)
	_ext_dd = z[0]
	_ext_dd_v = z[1]
	_ext_place(targets, look, step)


## EXTENDED's point and distance: FOLLOW's for [param look] and what the
## springs add, the distance raised to [method extended_keep] for
## [param targets] where it falls short (up to [constant EXTENDED_OVER] of
## the far limit) - the springs then go on from there, at the floor's
## speed over the [param step] s just gone at the least (it lets go
## without a jolt).
func _ext_place(targets: PackedVector3Array, look: Vector3, step := 0.0) -> void:
	_ext_at = Vector3(look.x + _ext_off.x, look.y + _ext_off.y, 0.0)
	_ext_d = ext_base_px() + _ext_dd
	var keep := minf(extended_keep(targets, look, _ext_at), extended_far() * EXTENDED_OVER)
	var was_on := _ext_on
	_ext_on = _ext_d < keep
	if _ext_on:
		_ext_d = keep
		_ext_dd = keep - ext_base_px()
		var carry := 0.0                    # (a floor that jumped - a target did - carries nothing)
		if was_on and step > 0.0:
			carry = minf((keep - _ext_keep) / step, extended_far() / extended_out_s)
		_ext_dd_v = maxf(_ext_dd_v, carry)
	_ext_keep = keep
