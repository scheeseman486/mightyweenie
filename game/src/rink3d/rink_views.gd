class_name MwRinkViews
extends RefCounted
## The rink's views (plan 20, docs/rink3d.md, Views): the original's 2D and
## seven 3D cameras, on F1-F8 in this order (owner), plan 34's 3D EXTENDED
## (the follow camera zooming to keep every player's character and the puck
## in the picture; owner) and plan 44's 2D EXTENDED (the orthographic view
## zooming so, with 3D EXTENDED's code) after them, on no F key of their
## own; a pad's Back button steps to the next. The view is a session
## setting ([member MwSession.view], 2D by default) and presentation only:
## the simulation never sees it. Some views turn the players' controls with
## the camera (owner: right on the pad is right on the screen; [method
## turn]).
##
## Plan 44 (owner): the views a match plays in come in two groups - 2D and
## 3D ([constant PLAIN]), 2D EXTENDED and 3D EXTENDED ([constant WIDE]) -
## and a match's group is fixed when it starts (an EXTENDED match's rule is
## the game's: MwRinkState.extended_play); player 1's VIEW switch goes between
## its 2D and its 3D, the F keys' 2D and follow camera are its group's, and
## Back's round skips the other group's two (no switching between the groups
## within a match).

enum { FLAT, ORTHO, TV, DOLLY, BIRDS_EYE, FIRST_PERSON, CINEMATIC, FOLLOW, EXTENDED, EXTENDED_2D }

const COUNT := 10
const NAMES := ["2D", "Ortho 3D", "TV", "Dolly", "Birds-eye", "First person", "Cinematic", "Follow 3D",
		"3D Extended", "2D Extended"]
## Plan 44: the groups' views, [its 2D, its 3D]: 2D and the follow camera,
## and the EXTENDED pair.
const PLAIN: Array[int] = [FLAT, FOLLOW]
const WIDE: Array[int] = [EXTENDED_2D, EXTENDED]

## The side-on cameras (TV, dolly, birds-eye across) look east from the
## west stands: north on the screen's left, south on its right, as the
## scoreboards' side view (owner's later scenes). In eighths of a turn
## clockwise from north.
const SIDE_HEADING := 2


## True for the 3D views (drawn by the 3D view: 2D EXTENDED too).
static func is_3d(v: int) -> bool:
	return v != FLAT


## Plan 44: true for the views whose match opening is the 3D one (plan 33's
## show): the 3D views but 2D EXTENDED, which opens as 2D does.
static func opens_3d(v: int) -> bool:
	return v != FLAT and v != EXTENDED_2D


## Plan 44: true for the EXTENDED group's views.
static func is_extended(v: int) -> bool:
	return v in WIDE


## Plan 44: the group of the EXTENDED views ([param extended]) or of 2D and
## 3D.
static func group(extended: bool) -> Array[int]:
	return WIDE if extended else PLAIN


## Plan 44: view [param v] in the terms of the EXTENDED group ([param
## extended]) or the other: 2D <-> 2D EXTENDED, the follow camera <-> 3D
## EXTENDED; any other view as it is.
static func grouped(v: int, extended: bool) -> int:
	var i := PLAIN.find(v)
	if i < 0:
		i = WIDE.find(v)
	return group(extended)[i] if i >= 0 else v


## The view after [param v] (Back), round to 2D after the last; plan 44:
## the other group's two ([param extended]: this match's group) skipped.
static func next(v: int, extended := false) -> int:
	var n := (v + 1) % COUNT
	while (PLAIN if extended else WIDE).has(n):
		n = (n + 1) % COUNT
	return n


## The view after [param v] on player 1's VIEW switch (plan 44): within the
## match's group ([param extended]), its 2D <-> its 3D; from any other view
## (the F keys' debug views) the group's 2D.
static func toggled(v: int, extended := false) -> int:
	var g := group(extended)
	return g[1] if v == g[0] else g[0]


## The view [param event] picks: player 1's VIEW switch ([method toggled]),
## F1-F8 (2D and the follow camera in the match's group: [param extended]),
## or Back (the one after [param current], [method next]); -1 none.
## Without [param debug] (plan 35: online, owner) only the VIEW switch.
static func picked(event: InputEvent, current: int, debug := true, extended := false) -> int:
	if event.is_action_pressed(MwInputMap.VIEW_TOGGLE, false, true):
		return toggled(current, extended)
	if not debug:
		return -1
	for i in MwInputMap.VIEW_SELECT.size():
		if event.is_action_pressed(MwInputMap.VIEW_SELECT[i], false, true):
			return grouped(i, extended)
	if event.is_action_pressed(MwInputMap.VIEW_NEXT, false, true):
		return next(current, extended)
	return -1


## Plan 40 (I6): the view and the birds-eye view's layout without a session
## (a rink or replay scene run on its own from the editor): [method
## view_of], [method across_of], [method select] read and write these then.
static var lone_view := FLAT
static var lone_across := false


## The view [param session] shows ([member lone_view] without one).
static func view_of(session: MwSession) -> int:
	return session.view if session else lone_view


## The birds-eye view's layout of [param session] (goals left and right).
static func across_of(session: MwSession) -> bool:
	return session.birds_eye_across if session else lone_across


## Sets [param session]'s view to [param v]; the birds-eye view picked
## again switches its layout.
static func select(session: MwSession, v: int) -> void:
	if session == null:
		v = posmod(v, COUNT)
		if v == BIRDS_EYE and lone_view == v:
			lone_across = not lone_across
		lone_view = v
		return
	v = posmod(v, COUNT)
	if v == BIRDS_EYE and session.view == v:
		session.birds_eye_across = not session.birds_eye_across
	session.view = v


## Plan 44: the group [param session]'s match plays in ([member
## MwSession.extended_views]; without a session: [member lone_view]'s).
static func extended_of(session: MwSession) -> bool:
	return session.extended_views if session else is_extended(lone_view)


## True for the views that frame the play as the 2D camera does: the arrows
## pointing at players off the 2D screen show there (the original's), and
## not in the others (plan 20) - 3D EXTENDED and 2D EXTENDED included: they
## keep every player's character in their picture, so an arrow at the 2D
## screen's edge would point at someone in sight (plans 34, 44).
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
		EXTENDED:
			return MwRinkCamera3D.Mode.EXTENDED
		EXTENDED_2D:
			return MwRinkCamera3D.Mode.EXTENDED_ORTHO
	return MwRinkCamera3D.Mode.FOLLOW


## How far every pad's directions turn in view [param v] (eighths of a turn
## clockwise): the side-on views a quarter (up on the pad = east, the way
## the camera looks); 0 in the views that look north and in the cinematic
## one (footage). First person turns player 1's pad by the camera's own
## heading instead (MwRinkCamera3D.turn_eighths). 3D EXTENDED and 2D
## EXTENDED look north as the follow camera and the 2D do: 0.
static func turn(v: int, across := false) -> int:
	match v:
		TV, DOLLY:
			return SIDE_HEADING
		BIRDS_EYE:
			return SIDE_HEADING if across else 0
	return 0
