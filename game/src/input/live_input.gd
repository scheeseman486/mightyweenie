class_name MwLiveInput
extends MwInputSource
## Input from the player's devices through the InputMap.
##
## Controls that turn with the camera (plan 20, owner): in the rink's views
## that look another way than the original's (MwRinkViews.turn), each
## player's move directions are turned as they are sampled, so up on the pad
## is up on the screen. Only in the gameplay context (menus, the pause menu,
## fights and replays read them as they are); the simulation, recordings and
## playback see the turned pads like any others.

## Eighths of a turn clockwise for players 1-4's directions (0: as pressed).
## Set by the screen that shows the turned view (the rink), cleared when it
## leaves or pauses.
static var turns := PackedInt32Array([0, 0, 0, 0])

## The eight directions clockwise from up: (x right, y down).
const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

var _actions := MwVerbs.all_actions()
var _presses := {}
var _turning := false        # the latest sample was in the gameplay context


## Called once per physics tick: remember every action pressed since the
## previous physics frame, however briefly.
func tick() -> void:
	for a in _actions:
		if InputMap.has_action(a) and Input.is_action_just_pressed(a):
			_presses[a] = true


func taps() -> Dictionary:
	var out := _presses
	_presses = {}
	return turned(out) if _turning else out


func sample(contexts: Array) -> Dictionary:
	var out := {}
	for a in _actions:
		if InputMap.has_action(a) and Input.is_action_pressed(a):
			out[a] = true
	_turning = contexts.has(MwVerbs.Context.GAMEPLAY)
	return turned(out) if _turning else out


## [param actions] with each player's move directions turned by [member
## turns]; the other actions as they are.
static func turned(actions: Dictionary) -> Dictionary:
	var out := actions
	for p in MwVerbs.PLAYERS:
		if turns[p] % 8 != 0:
			out = turn_player(out, p + 1, turns[p])
	return out


## [param actions] with player [param player]'s directions turned [param
## eighths] of a turn clockwise (a direction and its opposite together
## cancel).
static func turn_player(actions: Dictionary, player: int, eighths: int) -> Dictionary:
	var names: Array[String] = []
	for v in MwVerbs.MOVE:
		names.append(MwVerbs.action(player, v))
	var d := Vector2i(int(actions.has(names[3])) - int(actions.has(names[2])),
			int(actions.has(names[1])) - int(actions.has(names[0])))
	var out := actions.duplicate()
	for n in names:
		out.erase(n)
	var i := DIRECTIONS.find(d)
	if i < 0:
		return out
	var t: Vector2i = DIRECTIONS[posmod(i + eighths, 8)]
	if t.y < 0:
		out[names[0]] = true
	elif t.y > 0:
		out[names[1]] = true
	if t.x < 0:
		out[names[2]] = true
	elif t.x > 0:
		out[names[3]] = true
	return out
