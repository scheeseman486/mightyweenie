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

## Asks the router to leave for [param id] (fade length [param ticks], -1 =
## the router's default).
signal exit_requested(id: int, data: Dictionary, fade: bool, ticks: int)
## Asks the router to show [param id] (an ID or an MwScreens.EXTRA key) over this screen.
signal push_requested(id: Variant, data: Dictionary)
## Asks the router to close this screen and resume the one underneath.
signal pop_requested


## Called once after the scene is in the tree; [param data] comes from the
## screen that asked for this one.
func _enter_screen(_data: Dictionary) -> void:
	pass


## One pass of the screen's loop: [param elapsed] ticks since the previous
## pass, [param input] what the players hold / newly pressed.
func _screen_pass(_elapsed: int, _input: MwInputFrame) -> void:
	pass


## Called when a screen pushed over this one is popped.
func _resume_screen() -> void:
	pass


## Leave for screen [param id] (fades out and in unless [param fade] is
## false; the fade-out takes [param ticks], -1 = the default).
func exit_to(id: int, data := {}, fade := true, ticks := -1) -> void:
	exit_requested.emit(id, data, fade, ticks)


## Show screen [param id] over this one; this one waits (no passes).
func push(id: Variant, data := {}) -> void:
	push_requested.emit(id, data)


## Close this screen and return to the one underneath.
func pop() -> void:
	pop_requested.emit()
