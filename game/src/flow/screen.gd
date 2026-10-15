class_name MwScreen
extends Node2D
## Base class of every screen scene's root (docs/scenes.md).
##
## The router creates the scene, fills in who it is and where it came from,
## calls [method _enter_screen] once and then [method _screen_pass] whenever
## the screen's pass length has elapsed on the 60 Hz tick, with the elapsed
## ticks and the input of that pass - like the original's screen loops.
## A screen leaves with [method exit_to] (or [method push] / [method pop]);
## those only ask - the router listening to the signals decides when.

## The original's screen ID this scene shows (set by the router; when the
## scene is run on its own from the editor, this is the ID it pretends to be).
@export var screen_id := -1
## Entry variant from the screen table ("period_start", "goal", ...).
var entry := ""
## Screen ID shown before this one (the original's D7), -1 at boot.
var previous := -1
## How many times this screen ID has been entered.
var visit := 0
## Set when the screen fades itself in after entering (the title's parts):
## the router then leaves the screen covered.
@export var fades_in_itself := false
## The game session (setup, random streams, attract flag), set by the router.
var session: MwSession
## The router's full-screen fader, set by the router (screens that fade
## parts of themselves use it for the full-screen steps).
var fader: MwScreenFader
## Plan 40 (I6): the screen this one asked to leave for ([method exit_to];
## [constant POPPED] by [method pop]; -1: not leaving).
var leaving_to := -1
const POPPED := -2
## Plan 40 (S12): after a screen pushed over this one pops, the next pass
## counts from the pop (the port's screens: the time away is not caught up -
## CREATE-A-TEAM's talking portrait, the online pages' starfield, the rink
## editor). False, the original's: the visit's passes go on from its last
## one, so the first pass carries every tick spent away, as theirs did.
var resume_fresh := false
## The ticks the last screen pushed over this one stayed (set as it pops,
## before [method _resume_screen]).
var away := 0
var pushed_at := 0  ## the tick a screen was last pushed over this one (set by MwRouter; [member away] counts from it)

## Asks the router to leave for [param id] (fade length [param ticks], -1 =
## the router's default).
signal exit_requested(id: int, data: Dictionary, fade: bool, ticks: int)
## Asks the router to show [param id] (an ID or an MwScreens.EXTRA key) over
## this screen ([param fade] false: at once - plan 40, M5's cuts).
signal push_requested(id: Variant, data: Dictionary, fade: bool)
## Asks the router to close this screen and resume the one underneath with
## [param result] (its [method _resume_screen]'s; [param fade] as above).
signal pop_requested(result: Dictionary, fade: bool)


## Called once after the scene is in the tree; [param data] comes from the
## screen that asked for this one.
func _enter_screen(_data: Dictionary) -> void:
	pass


## One pass of the screen's loop: [param elapsed] ticks since the previous
## pass, [param input] what the players hold / newly pressed.
func _screen_pass(_elapsed: int, _input: MwInputFrame) -> void:
	pass


## Plan 41 (online feel; a client's match calls it after each frame's
## ticks): this machine's players' menu presses its game hasn't run yet
## ([param presses]: player number -> verb names, in the order pressed),
## shown at once. A screen with per-player menus runs them through its own
## per-player handlers on its model - nothing else: no screen or stage
## change, no sound (MwLocalEcho.run) -, draws, and puts its model back; with
## none ([param presses] empty) a screen that showed some draws its own model
## again. The game's state is never changed here. Default: nothing.
func predict_local(_presses: Dictionary) -> void:
	pass


## Called when a screen is pushed over this one: its fade-out is over (the
## picture is covered) and this one is hidden; what it shows outside itself
## (the 3D view, the wide picture) goes now, never during the fade-out.
func _cover_screen() -> void:
	pass


## Called when a screen pushed over this one is popped, with what it handed
## back ([param _result]: its [method pop]'s; plan 40, I6 - the text entry's
## text, the password screen's stars).
func _resume_screen(_result := {}) -> void:
	pass


## Leave for screen [param id] (fades out and in unless [param fade] is
## false; the fade-out takes [param ticks], -1 = the default). The router
## keeps the first request; [member leaving_to] says it.
func exit_to(id: int, data := {}, fade := true, ticks := -1) -> void:
	if leaving_to == -1:
		leaving_to = id
	exit_requested.emit(id, data, fade, ticks)


## Plan 40 (I6): this screen asked to leave ([method exit_to], [method
## pop]): it takes no more input (screens with a phase of their own before
## leaving keep a flag for that phase).
func leaving() -> bool:
	return leaving_to != -1


## Show screen [param id] over this one; this one waits (no passes).
## [param fade] false: no fade (a cut between starfield screens, MwMenuCut).
func push(id: Variant, data := {}, fade := true) -> void:
	push_requested.emit(id, data, fade)


## The screen this one was pushed over and leaves in sight (MwRouter: a
## push with "over"), from [param data] (null: none).
static func under_of(data: Dictionary) -> MwScreen:
	var u: Variant = data.get(MwRouter.UNDER)
	return u as MwScreen if u is MwScreen and is_instance_valid(u) else null


## What a screen pushed over this one (in sight: MwRouter's "over") fades
## out while it covers it, and back in as it leaves: its title (none here).
func covered_fades() -> Array[CanvasItem]:
	return []


## Close this screen and return to the one underneath, handing it
## [param result] (its [method _resume_screen]'s).
func pop(result := {}, fade := true) -> void:
	if leaving_to == -1:
		leaving_to = POPPED
	pop_requested.emit(result, fade)
