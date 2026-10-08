class_name MwRinkViews
extends RefCounted
## The rink's views (plan 20, docs/rink3d.md, Views): the original's 2D and
## seven 3D cameras, on F1-F8 in this order (owner); a pad's Back button
## steps to the next. The view is a session setting ([member
## MwSession.view], 2D by default) and presentation only: the simulation
## never sees it. Some views turn the players' controls with the camera
## (owner: right on the pad is right on the screen; [method turn]).

enum { FLAT, ORTHO, TV, DOLLY, BIRDS_EYE, FIRST_PERSON, CINEMATIC, FOLLOW }

const COUNT := 8
const NAMES := ["2D", "Ortho 3D", "TV", "Dolly", "Birds-eye", "First person", "Cinematic", "Follow 3D"]

## The side-on cameras (TV, dolly, birds-eye across) look east from the
## west stands: north on the screen's left, south on its right, as the
## scoreboards' side view (owner's later scenes). In eighths of a turn
## clockwise from north.
const SIDE_HEADING := 2


## True for the 3D views.
static func is_3d(v: int) -> bool:
	return v != FLAT


## The view after [param v] (Back), round to 2D after the last.
static func next(v: int) -> int:
	return (v + 1) % COUNT


## The view [param event] picks: player 1's 2D / 3D switch (2D <-> the
## follow camera; from another 3D view, 2D), F1-F8, or Back (the one after
## [param current]); -1 none.
static func picked(event: InputEvent, current: int) -> int:
	if event.is_action_pressed(MwInputMap.VIEW_TOGGLE, false, true):
		return FLAT if is_3d(current) else FOLLOW
	for i in MwInputMap.VIEW_SELECT.size():
		if event.is_action_pressed(MwInputMap.VIEW_SELECT[i], false, true):
			return i
	if event.is_action_pressed(MwInputMap.VIEW_NEXT, false, true):
		return next(current)
	return -1


## Sets [param session]'s view to [param v]; the birds-eye view picked
## again switches its layout.
static func select(session: MwSession, v: int) -> void:
	v = posmod(v, COUNT)
	if v == BIRDS_EYE and session.view == v:
		session.birds_eye_across = not session.birds_eye_across
	session.view = v


## True for the views that frame the play as the 2D camera does: the arrows
## pointing at players off the 2D screen show there (the original's), and
## not in the others (plan 20).
static func shows_arrows(v: int) -> bool:
	return v == FLAT or v == ORTHO or v == FOLLOW


## The 3D camera's mode for view [param v] ([param across]: birds-eye with
## the goals left and right).
static func camera_mode(v: int, across := false) -> MwRinkCamera3D.Mode:
	match v:
		ORTHO:
			return MwRinkCamera3D.Mode.ORTHO
		TV:
			return MwRinkCamera3D.Mode.TV
		DOLLY:
			return MwRinkCamera3D.Mode.DOLLY
		BIRDS_EYE:
			return MwRinkCamera3D.Mode.BIRDS_EYE_ACROSS if across else MwRinkCamera3D.Mode.BIRDS_EYE
		FIRST_PERSON:
			return MwRinkCamera3D.Mode.FIRST_PERSON
		CINEMATIC:
			return MwRinkCamera3D.Mode.CINEMATIC
	return MwRinkCamera3D.Mode.FOLLOW


## How far every pad's directions turn in view [param v] (eighths of a turn
## clockwise): the side-on views a quarter (up on the pad = east, the way
## the camera looks); 0 in the views that look north and in the cinematic
## one (footage). First person turns player 1's pad by the camera's own
## heading instead (MwRinkCamera3D.turn_eighths).
static func turn(v: int, across := false) -> int:
	match v:
		TV, DOLLY:
			return SIDE_HEADING
		BIRDS_EYE:
			return SIDE_HEADING if across else 0
	return 0
