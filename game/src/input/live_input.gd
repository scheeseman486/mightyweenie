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
##
## Analogue control (plan 22; MwSettings.analogue, on by default): in the
## gameplay context a stick bound to a player's move verbs steers at its own
## angle and sets the pace ([method sticks]; the simulation's readers:
## MwHumanControl.stick). Past [constant STICK_DEADZONE] the stick also
## holds the move verbs of its eighth instead of whatever the axes' own
## thresholds pressed, so everything that reads the D-pad (a hazard's
## auto-jump, the faceoff, the fight) sees one direction held, as from a
## D-pad. Keys and D-pad buttons are untouched: without a stick the game
## plays exactly as the original.
##
## Shot heights (MwSettings.shot_heights, off by default): in the gameplay
## context each STANDARD-layout player's HIGH SHOT / LOW SHOT held ([method
## heights]; the simulation's reader: MwHumanControl.height). They are not
## directions, so the turned views leave them be.
##
## Plan 35: a stick is quantised here, before the game sees it - an angle
## and a travel, a byte each ([MwStick]: its code, [method stick_codes]) -
## and the game reads the code decoded, so a recorded or networked stream
## carries exactly what the game saw. The shot heights too are taken here,
## by this machine's settings and its players' layouts, and travel as they
## are (MwTickInput.heights).
##
## While a text input types ([MwKeyGate]) the keys drive no actions: each
## action is read from the inputs the gate lets through (the gamepads; the
## keys again once let go after it ends).

## Eighths of a turn clockwise for each player's directions, player 1
## first (0: as pressed; a player past its end: 0). Set by the screen that
## shows the turned view (the rink), cleared when it leaves or pauses.
static var turns := PackedInt32Array()

## The eight directions clockwise from up: (x right, y down).
const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
## A stick's radial dead zone (of its full travel).
const STICK_DEADZONE := 0.2

var _actions := MwVerbs.every_action()   # plan 38's local verbs too (the stream drops them)
var _presses := {}
var _turning := false        # the latest sample was in the gameplay context
var _sticks: Array = []      # the latest sample's sticks (empty: none)
var _codes := PackedInt32Array()   # their codes (MwStick)
var _heights: Array = []     # the latest sample's shot heights (empty: the D-pad's)


## Called once per physics tick: remember every action pressed since the
## previous physics frame, however briefly.
func tick() -> void:
	MwKeyGate.update()
	var gated := MwKeyGate.active()
	for a in _actions:
		if InputMap.has_action(a) and Input.is_action_just_pressed(a) and (not gated or MwKeyGate.held(a)):
			_presses[a] = true


## The actions pressed since the last read ([method tick] notes them every physics tick),
## cleared by reading; turned as the sample's are in the gameplay context.
func taps() -> Dictionary:
	var out := _presses
	_presses = {}
	return turned(out) if _turning else out


## The actions held now (action -> true) that [MwKeyGate] lets through; with the gameplay
## context in [param contexts] also the shot heights, the move directions turned
## ([member turns]) and the sticks quantised, each past its dead zone holding its eighth.
func sample(contexts: Array) -> Dictionary:
	var out := {}
	var gated := MwKeyGate.active()             # a text input types: its keys aren't verbs
	for a in _actions:
		if InputMap.has_action(a) and Input.is_action_pressed(a) and (not gated or MwKeyGate.held(a)):
			out[a] = true
	_turning = contexts.has(MwVerbs.Context.GAMEPLAY)
	_sticks = []
	_codes = PackedInt32Array()
	_heights = []
	if not _turning:
		return out
	if MwSettings.shot_heights:
		for p in range(1, MwVerbs.PLAYERS + 1):
			_heights.append(height_of(out, p) if MwSettings.layout(p) == "STANDARD" else -1)
	out = turned(out)
	if MwSettings.analogue:
		for p in range(1, MwVerbs.PLAYERS + 1):
			# plan 35: quantised (MwStick), turned by whole angle steps
			var code := MwStick.turned(MwStick.encode(stick_of(raw_stick(p))), turn(p))
			_codes.append(code)
			_sticks.append(MwStick.decode(code))
			if code != MwStick.NONE:
				out = with_eighth(out, p, MwStick.eighth(code))
	return out


## Players 1-12's sticks at the latest sample, decoded from their codes; empty outside the
## gameplay context or with analogue control off.
func sticks() -> Array:
	return _sticks


## Players 1-12's sticks at the latest sample as [MwStick] codes (empty: as [method sticks]).
func stick_codes() -> PackedInt32Array:
	return _codes


## Players 1-12's shot heights at the latest sample (-1 a player not on the STANDARD
## layout); empty outside the gameplay context or with the option off.
func heights() -> Array:
	return _heights


## Player [param player]'s shot height in [param actions] (MwInputSource.heights):
## 1 HIGH SHOT held, 2 LOW SHOT, 0 neither or both (the middle height).
static func height_of(actions: Dictionary, player: int) -> int:
	var high := actions.has(MwVerbs.action(player, MwVerbs.SHOT_HIGH))
	var low := actions.has(MwVerbs.action(player, MwVerbs.SHOT_LOW))
	if high == low:
		return 0
	return 1 if high else 2


## Player [param player]'s stick as it is: the gamepad axes bound to their
## move verbs (x right, y down; each direction the furthest of its axes).
static func raw_stick(player: int) -> Vector2:
	var v := [0.0, 0.0, 0.0, 0.0]            # up, down, left, right
	for i in 4:
		var a := MwVerbs.action(player, MwVerbs.MOVE[i])
		if not InputMap.has_action(a):
			continue
		for event in InputMap.action_get_events(a):
			if event is InputEventJoypadMotion:
				var m := event as InputEventJoypadMotion
				v[i] = maxf(v[i], _axis(m.device, m.axis) * signf(m.axis_value))
	return Vector2(v[3] - v[2], v[1] - v[0])


## Axis [param axis] of gamepad [param device] (-1: whichever gamepad has
## it furthest from the centre).
static func _axis(device: int, axis: int) -> float:
	if device >= 0:
		return Input.get_joy_axis(device, axis as JoyAxis)
	var best := 0.0
	for d in Input.get_connected_joypads():
		var x := Input.get_joy_axis(d, axis as JoyAxis)
		if absf(x) > absf(best):
			best = x
	return best


## The stick the simulation sees from [param raw] (x right, y down; full
## travel 1): nothing inside [constant STICK_DEADZONE], else its direction
## with the travel past the dead zone as the length (to 1), each axis in
## 256ths. The turned views turn its quantised code (MwStick.turned).
static func stick_of(raw: Vector2) -> Vector2i:
	var m := raw.length()
	if m <= STICK_DEADZONE:
		return Vector2i.ZERO
	var v := raw / m * minf((m - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.0)
	return Vector2i(roundi(v.x * 256.0), roundi(v.y * 256.0))


## [param actions] with player [param player]'s move verbs those of eighth
## [param i] (0 right, 2 down ...: MwStick.eighth), as a D-pad would hold
## them.
static func with_eighth(actions: Dictionary, player: int, i: int) -> Dictionary:
	var out := actions.duplicate()
	var names: Array[String] = []
	for v in MwVerbs.MOVE:
		names.append(MwVerbs.action(player, v))
		out.erase(names[-1])
	if i in [5, 6, 7]:
		out[names[0]] = true
	elif i in [1, 2, 3]:
		out[names[1]] = true
	if i in [3, 4, 5]:
		out[names[2]] = true
	elif i in [7, 0, 1]:
		out[names[3]] = true
	return out


## [param actions] with each player's move directions turned by [member
## turns]; the other actions as they are.
static func turned(actions: Dictionary) -> Dictionary:
	var out := actions
	for p in mini(turns.size(), MwVerbs.PLAYERS):
		if turns[p] % 8 != 0:
			out = turn_player(out, p + 1, turns[p])
	return out


## Player [param player]'s turn ([member turns]; 0 past its end).
static func turn(player: int) -> int:
	return turns[player - 1] if player >= 1 and player <= turns.size() else 0


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
