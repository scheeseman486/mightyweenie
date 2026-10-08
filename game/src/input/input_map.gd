class_name MwInputMap
extends RefCounted
## Default bindings (docs/re/input.md), installed into the InputMap at
## start-up from one table. Each player has the original's eight buttons on
## a physical device; a context's verbs get the events of the buttons the
## original used for them (MwVerbs.PAD_TO_VERB), so the defaults put every
## verb where the original had it. Menu verbs get every player's buttons.
## Godot's own events on the `ui_*` actions we use are replaced.
##
## Rebinding (plan 21): a player's button rebound in the options menu
## ([member MwSettings.bindings]) holds that one input instead of its
## defaults. The menus' permanent keys ([constant MENU_KEYS]: arrows, Enter,
## Esc) always drive the shared menu verbs and player 1's, whatever is bound;
## no action gets the same input twice.

const DEADZONE := 0.5

## TEMPORARY (owner, 2026-10-07): only player 1 has inputs - the arrow keys,
## Z / X / C for A / B / C, Enter for Start (P1_ONLY_KEYS) and the first
## gamepad; players 2-4 get none, keyboard or gamepad. False restores the
## layouts below (KEYS, a gamepad per player). Read by [method install].
static var p1_only := true
## Player 1's keyboard while [member p1_only] is on (Genesis button -> key).
const P1_ONLY_KEYS := {"UP": KEY_UP, "DOWN": KEY_DOWN, "LEFT": KEY_LEFT, "RIGHT": KEY_RIGHT,
	"A": KEY_Z, "B": KEY_X, "C": KEY_C, "START": KEY_ENTER}

## Keyboard layouts for players 1 and 2 (Genesis button -> key).
const KEYS := {
	1: {"UP": KEY_W, "DOWN": KEY_S, "LEFT": KEY_A, "RIGHT": KEY_D,
		"B": KEY_J, "C": KEY_K, "A": KEY_L, "START": KEY_ENTER},
	2: {"UP": KEY_UP, "DOWN": KEY_DOWN, "LEFT": KEY_LEFT, "RIGHT": KEY_RIGHT,
		"B": KEY_KP_1, "C": KEY_KP_2, "A": KEY_KP_3, "START": KEY_KP_ENTER},
}
## Gamepads (SDL layout): Genesis A B C on the west, south, east face buttons.
const PAD_BUTTONS := {
	"UP": JOY_BUTTON_DPAD_UP, "DOWN": JOY_BUTTON_DPAD_DOWN, "LEFT": JOY_BUTTON_DPAD_LEFT,
	"RIGHT": JOY_BUTTON_DPAD_RIGHT, "B": JOY_BUTTON_A, "C": JOY_BUTTON_B, "A": JOY_BUTTON_X,
	"START": JOY_BUTTON_START,
}
## Menu Back (plan 21; owner: Esc and the gamepad's east face button - the
## Genesis C button's too): player 1's keyboard key; every player's gamepad.
const BACK_KEY := KEY_ESCAPE
const BACK_PAD := JOY_BUTTON_B
## The permanent menu keys (owner, plan 21): menu verb -> key.
const MENU_KEYS := {"ui_up": KEY_UP, "ui_down": KEY_DOWN, "ui_left": KEY_LEFT,
	"ui_right": KEY_RIGHT, "ui_accept": KEY_ENTER, "ui_back": KEY_ESCAPE}
## The rink's views (plan 20, MwRinkViews): F1-F8 pick one, any gamepad's
## Back button steps to the next. Not gameplay verbs - no player's, never in
## an MwInputFrame.
const VIEW_NEXT := "view_next"
const VIEW_SELECT: Array[String] = ["view_1", "view_2", "view_3", "view_4", "view_5", "view_6", "view_7", "view_8"]
const VIEW_KEYS: Array[Key] = [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8]
## Player 1's 2D / 3D switch (owner): the rebindable VIEW button
## ([constant MwSettings.P1_BUTTONS]); by default V (after Z X C) and the
## first gamepad's north face button, the one the Genesis layout leaves free.
## Not a gameplay verb either.
const VIEW_TOGGLE := "view_toggle"
const VIEW_KEY := KEY_V
const VIEW_PAD := JOY_BUTTON_Y
## Left stick as the D-pad: [axis, direction].
const PAD_AXES := {
	"UP": [JOY_AXIS_LEFT_Y, -1.0], "DOWN": [JOY_AXIS_LEFT_Y, 1.0],
	"LEFT": [JOY_AXIS_LEFT_X, -1.0], "RIGHT": [JOY_AXIS_LEFT_X, 1.0],
}


## The keyboard layout of [param player] (Genesis button -> key; empty: none).
static func keys(player: int) -> Dictionary:
	if p1_only:
		return P1_ONLY_KEYS if player == 1 else {}
	return KEYS.get(player, {})


## Physical events of [param button] ([method MwSettings.buttons]) for
## [param player] (1-4): the input the player rebound it to, else the
## defaults ([method default_events]).
static func button_events(player: int, button: String) -> Array[InputEvent]:
	var bound := MwSettings.binding(player, button)
	if bound != null:
		var one: Array[InputEvent] = [bound]
		return one
	return default_events(player, button)


## The default events of [param button] for [param player]: gamepad device
## player-1, plus the keyboard layout for players 1-2 (player 1 alone while
## [member p1_only] is on); Menu Back: Esc (player 1) and the pad's east
## button; player 1's VIEW: V and the first pad's north button.
static func default_events(player: int, button: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if p1_only and player != 1:
		return out
	if button == "VIEW":
		if player == 1:
			var v := InputEventKey.new()
			v.physical_keycode = VIEW_KEY
			var north := InputEventJoypadButton.new()
			north.device = 0
			north.button_index = VIEW_PAD
			out.append_array([v, north])
		return out
	if button == "BACK":
		if player == 1:
			var esc := InputEventKey.new()
			esc.physical_keycode = BACK_KEY
			out.append(esc)
		var east := InputEventJoypadButton.new()
		east.device = player - 1
		east.button_index = BACK_PAD
		out.append(east)
		return out
	var layout := keys(player)
	if layout.has(button):
		var k := InputEventKey.new()
		k.physical_keycode = layout[button]
		out.append(k)
	var b := InputEventJoypadButton.new()
	b.device = player - 1
	b.button_index = PAD_BUTTONS[button]
	out.append(b)
	if PAD_AXES.has(button):
		var m := InputEventJoypadMotion.new()
		m.device = player - 1
		m.axis = PAD_AXES[button][0]
		m.axis_value = PAD_AXES[button][1]
		out.append(m)
	return out


## The default events of every action: action name -> events.
static func defaults() -> Dictionary:
	var out := {}
	for a in MwVerbs.all_actions():
		out[a] = [] as Array[InputEvent]
	for ctx in MwVerbs.PAD_TO_VERB:
		var table: Dictionary = MwVerbs.PAD_TO_VERB[ctx]
		for button in table:
			for verb in MwVerbs.verbs_of(ctx, button):
				for p in range(1, MwVerbs.PLAYERS + 1):
					var names := [MwVerbs.action(p, verb)]
					if ctx == MwVerbs.Context.MENU:
						names.append(MwVerbs.menu_action(p, verb))
					for n in names:
						var events: Array = out[n]
						for e in button_events(p, button):
							_add(events, e)
	for verb in MENU_KEYS:
		var k := InputEventKey.new()
		k.physical_keycode = MENU_KEYS[verb]
		_add(out[verb], k)
		_add(out[MwVerbs.menu_action(1, verb)], k)
	return out


## Appends [param e] to [param events] unless the same input is there.
static func _add(events: Array, e: InputEvent) -> void:
	if not events.any(func(x: InputEvent) -> bool: return _same(x, e)):
		events.append(e)


## Same physical input on the same device (InputEvent.is_match ignores the
## gamepad device).
static func _same(a: InputEvent, b: InputEvent) -> bool:
	return a.get_class() == b.get_class() and a.device == b.device and a.as_text() == b.as_text()


## The views' actions and their events ([constant VIEW_SELECT]: the F
## keys, [constant VIEW_NEXT]: any gamepad's Back button).
static func view_events() -> Dictionary:
	var table := {}
	for i in VIEW_SELECT.size():
		var k := InputEventKey.new()
		k.physical_keycode = VIEW_KEYS[i]
		var keys: Array[InputEvent] = [k]
		table[VIEW_SELECT[i]] = keys
	var b := InputEventJoypadButton.new()
	b.device = -1
	b.button_index = JOY_BUTTON_BACK
	var back: Array[InputEvent] = [b]
	table[VIEW_NEXT] = back
	return table


## Installs the defaults (replacing existing events of these actions).
static func install() -> void:
	var table := defaults()
	table.merge(view_events())
	table[VIEW_TOGGLE] = button_events(1, "VIEW")
	for a in table:
		if not InputMap.has_action(a):
			InputMap.add_action(a, DEADZONE)
		else:
			InputMap.action_erase_events(a)
			InputMap.action_set_deadzone(a, DEADZONE)
		for e in table[a]:
			InputMap.action_add_event(a, e)
