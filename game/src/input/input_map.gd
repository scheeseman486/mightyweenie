class_name MwInputMap
extends RefCounted
## The bindings, per player and per verb (plan 22; docs/re/input.md),
## installed into the InputMap from one table.
##
## A verb's inputs are the ones the player bound to it ([member
## MwSettings.bindings], one input each), else its layout's defaults
## ([constant LAYOUTS], [method MwSettings.layout]); a direction verb also
## has a stick ([method stick_events]: the left stick unless rebound):
##
## * **STANDARD** (owner's default): the menus answer the usual gamepad
##   conventions - accept on the south face button (Xbox A) and Start, back
##   on east (Xbox B) - and a screen's other choices go on west / north / the
##   right shoulder in the original's A / B / C order ([constant
##   STANDARD_PAD]); gameplay, fights and the keyboard are the GENESIS
##   layout's. The original's lettered pause menu's A / B (REPLAY /
##   TIMEOUT) have no inputs and no bindings rows ([constant
##   STANDARD_UNUSED]): the port's pause menu has them as items. With
##   [member MwSettings.shot_heights] on, the shot heights
##   (MwVerbs.SHOT_HEIGHTS) are on the triggers: HIGH SHOT the right one,
##   LOW SHOT the left (player 1's keyboard: A above Left Shift, [constant
##   KEYS]); off, they have no inputs and no rows.
## * **GENESIS**: every verb on the original's button (MwVerbs.PAD_TO_VERB):
##   A / B / C on the gamepad's west / south / east, Start; Menu Back on the
##   gamepad's Select (and Esc), so it shares an input with nothing. No
##   shot heights (a 3-button pad has no spare button).
##
## Menu verbs (`ui_*`) get every player's inputs on their shared action (any
## player drives menus) and each player's on the per-player one. The menus'
## permanent keys ([constant MENU_KEYS]: arrows, Enter, Esc) always drive
## the shared menu verbs and player 1's, whatever is bound; no action gets
## the same input twice. Two verbs live on one screen on one input are a
## collision ([method collisions]; the bindings menu shows them red) unless
## they are one of the original's tap / hold groups (MwVerbs.GROUPS).

const DEADZONE := 0.5
## [method collisions]' mark of a direction verb whose stick collides.
const STICK_MARK := "#stick"
const LAYOUTS: Array[String] = ["STANDARD", "GENESIS"]

## Each player's default devices (plan 34: twelve players; the owner's
## player-1-only layout of 2026-10-07 retired - the controller selection
## decides who plays): player n's gamepad is device n - 1; the keyboard is
## player 1's (as it was: the arrow keys, Z / X / C for A / B / C, Enter for
## Start; Q for RECLAIM in the STANDARD layout; with the shot heights on, the
## STANDARD layout's HIGH SHOT and LOW SHOT under the left little finger, A
## above Left Shift, while Z / X / C stay under the other fingers). Shared
## menu verbs take every player's inputs. CREATE-A-TEAM's extra verbs (plan
## 38): A / S for the editors' X / Y, W / E to turn the rink editor's view,
## R / F to zoom (A is HIGH SHOT's too: the editors and the rink never meet),
## Page Up / Down to scroll the text entry's box.
const KEYS := {
	1: {"UP": KEY_UP, "DOWN": KEY_DOWN, "LEFT": KEY_LEFT, "RIGHT": KEY_RIGHT,
		"A": KEY_Z, "B": KEY_X, "C": KEY_C, "START": KEY_ENTER, "RECLAIM": KEY_Q,
		"SHOT_HIGH": KEY_A, "SHOT_LOW": KEY_SHIFT,
		"X": KEY_A, "Y": KEY_S, "VIEW_LEFT": KEY_W, "VIEW_RIGHT": KEY_E, "VIEW_IN": KEY_R, "VIEW_OUT": KEY_F,
		"SCROLL_UP": KEY_PAGEUP, "SCROLL_DOWN": KEY_PAGEDOWN},
}
## The gamepad's buttons by place (SDL layout; Xbox names in brackets).
const PAD := {"SOUTH": JOY_BUTTON_A, "EAST": JOY_BUTTON_B, "WEST": JOY_BUTTON_X,
	"NORTH": JOY_BUTTON_Y, "START": JOY_BUTTON_START, "SELECT": JOY_BUTTON_BACK,
	"LB": JOY_BUTTON_LEFT_SHOULDER, "RB": JOY_BUTTON_RIGHT_SHOULDER,
	"UP": JOY_BUTTON_DPAD_UP, "DOWN": JOY_BUTTON_DPAD_DOWN, "LEFT": JOY_BUTTON_DPAD_LEFT,
	"RIGHT": JOY_BUTTON_DPAD_RIGHT}
## The GENESIS layout on a gamepad: A B C on the west, south, east face
## buttons (left to right, as on the Genesis pad), Menu Back on Select,
## player 1's 2D / 3D on north.
const GENESIS_PAD := {"UP": "UP", "DOWN": "DOWN", "LEFT": "LEFT", "RIGHT": "RIGHT",
	"A": "WEST", "B": "SOUTH", "C": "EAST", "START": "START", "BACK": "SELECT", "VIEW": "NORTH",
	"X": "LB", "Y": "RB", "VIEW_LEFT": "RS_LEFT", "VIEW_RIGHT": "RS_RIGHT", "VIEW_IN": "RS_UP",
	"VIEW_OUT": "RS_DOWN", "SCROLL_UP": "RS_UP", "SCROLL_DOWN": "RS_DOWN", "CURSOR_LEFT": "LT",
	"CURSOR_RIGHT": "RT"}
## The STANDARD layout's gamepad buttons for the verbs it moves (the rest
## as GENESIS): accept south + Start, back east; a screen's A / B / C
## choices on west / north / RB; the screens whose first choice is not
## "leave" put it on south too (the password's letters, the special plays'
## play, the team description's pages).
const STANDARD_PAD := {
	"ui_accept": ["START", "SOUTH"], "ui_back": ["EAST"],
	"ui_delete": ["WEST"], "ui_keep": ["NORTH"],
	"ui_skip": ["WEST", "NORTH", "RB"],
	"ui_next_page": ["SOUTH", "WEST", "NORTH", "RB"], "ui_info_return": ["START"],
	"ui_new_playoffs": ["WEST"], "ui_starfield_stop": ["NORTH"], "ui_starfield_turn": ["RB"],
	"ui_password_done": ["START"], "ui_pick_letter": ["SOUTH", "WEST"], "ui_erase_letter": ["NORTH"],
	"ui_cancel": ["RB"],
	"ui_resume": ["START"],
	"ui_view_stats": ["WEST"], "ui_view_special_plays": ["NORTH"], "ui_view_replay": ["RB"],
	"ui_stats_switch": ["WEST"],
	"ui_plays_done": ["START"], "ui_nasty_play": ["WEST"], "ui_choose_play": ["SOUTH", "NORTH"],
	"ui_phony_play": ["RB"],
	"replay_exit": ["START", "SOUTH"], "replay_rewind": ["WEST"], "replay_slow": ["NORTH"],
	"replay_play": ["RB"],
	"reclaim": ["LB"],
	"shot_high": ["RT"], "shot_low": ["LT"],
	"ui_editor_copy": ["WEST"], "ui_editor_delete": ["NORTH"], "ui_editor_next": ["RB"],
	"ui_editor_previous": ["LB"],
	"rink_done": ["START"], "rink_place": ["SOUTH"], "rink_remove": ["NORTH"], "rink_mirror": ["WEST"],
	"rink_kind_next": ["RB"], "rink_kind_previous": ["LB"],
}
## The gamepad's triggers by place: axes, pressed past [constant DEADZONE].
const PAD_TRIGGERS := {"LT": JOY_AXIS_TRIGGER_LEFT, "RT": JOY_AXIS_TRIGGER_RIGHT}
## Verbs the STANDARD layout leaves off the keyboard: Start's resume on the
## port's pause menu (plan 23: Enter picks the selected item, Esc resumes).
const STANDARD_PAD_ONLY: Array[String] = ["ui_resume"]
## Verbs the STANDARD layout has no use for: no inputs (bound ones
## ignored) and no row on the bindings page ([method unused]). The
## original's lettered pause menu's A / B: the port's pause menu (plan 23)
## has REPLAY and TIMEOUT as items, and as shortcuts beside them they
## picked REPLAY / TIMEOUT whatever was selected (owner, 2026-10-09: gone).
const STANDARD_UNUSED: Array[String] = ["ui_pause_replay", "ui_pause_timeout"]
## Verbs the GENESIS layout has no input for: RECLAIM (B tapped twice
## reclaims there; MwVerbs.RECLAIM) and the shot heights (MwVerbs.SHOT_HEIGHTS;
## the D-pad's Up / Down lift shots there).
const GENESIS_UNUSED: Array[String] = [MwVerbs.RECLAIM, MwVerbs.SHOT_HIGH, MwVerbs.SHOT_LOW]
## Menu Back's key and player 1's 2D / 3D key (after Z X C).
const BACK_KEY := KEY_ESCAPE
const VIEW_KEY := KEY_V
## The permanent menu keys (owner, plan 21): key -> the menu verbs it drives
## (Enter: every verb that means the original's Start in a menu).
const MENU_KEYS := {KEY_UP: ["ui_up"], KEY_DOWN: ["ui_down"], KEY_LEFT: ["ui_left"],
	KEY_RIGHT: ["ui_right"], KEY_ENTER: ["ui_accept", "ui_info_return", "ui_password_done", "ui_plays_done"],
	KEY_ESCAPE: ["ui_back"]}
## The rink's views (plan 20, MwRinkViews): F1-F8 pick one, any gamepad's
## Select steps to the next. Debug views (owner); not verbs, never bound.
const VIEW_NEXT := "view_next"
const VIEW_SELECT: Array[String] = ["view_1", "view_2", "view_3", "view_4", "view_5", "view_6", "view_7", "view_8"]
const VIEW_KEYS: Array[Key] = [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8]
## Player 1's 2D / 3D switch (owner; MwVerbs.VIEW_TOGGLE).
const VIEW_TOGGLE := MwVerbs.VIEW_TOGGLE
## Left stick as the D-pad: [axis, direction].
const PAD_AXES := {
	"UP": [JOY_AXIS_LEFT_Y, -1.0], "DOWN": [JOY_AXIS_LEFT_Y, 1.0],
	"LEFT": [JOY_AXIS_LEFT_X, -1.0], "RIGHT": [JOY_AXIS_LEFT_X, 1.0],
	"RS_UP": [JOY_AXIS_RIGHT_Y, -1.0], "RS_DOWN": [JOY_AXIS_RIGHT_Y, 1.0],
	"RS_LEFT": [JOY_AXIS_RIGHT_X, -1.0], "RS_RIGHT": [JOY_AXIS_RIGHT_X, 1.0],
}


## Bumped whenever a gamepad is connected or unplugged (plan 34: pages
## that show the players' devices redraw when it changes).
static var devices_changed := 0


## The keyboard layout of [param player] (Genesis button -> key; empty: none).
static func keys(player: int) -> Dictionary:
	return KEYS.get(player, {})


## Plan 34: the gamepad [param player] plays on - the device of a gamepad
## input they bound, else their default one (device player - 1).
static func pad_device(player: int) -> int:
	for v in MwVerbs.all_verbs():
		var b := MwSettings.binding(player, v)
		if b != null and not b is InputEventKey and b.device >= 0:
			return b.device
	return player - 1


## True when [param player] has keyboard inputs (player 1's keyboard, or a
## key they bound).
static func uses_keyboard(player: int) -> bool:
	if not keys(player).is_empty():
		return true
	for v in MwVerbs.all_verbs():
		if MwSettings.binding(player, v) is InputEventKey:
			return true
	return false


## True when [param player] can play now: their gamepad is connected, or
## they have the keyboard.
static func connected(player: int) -> bool:
	return pad_device(player) in Input.get_connected_joypads() or uses_keyboard(player)


## [param player]'s device as the menus tag it (plan 23's tags: "XB3",
## "PAD5"): their gamepad's when it is connected, else "KEYS" for a
## keyboard player, else their gamepad's (shown greyed: not there).
static func device_tag(player: int) -> String:
	var d := pad_device(player)
	if d in Input.get_connected_joypads() or not uses_keyboard(player):
		return MwGlyphs.tag(d)
	return "KEYS"


static func _joy_changed(_device: int, _connected: bool) -> void:
	devices_changed += 1


## [param player]'s inputs for [param verb]: the one bound to it, else
## the layout's defaults ([method default_events]); a direction verb also
## its stick ([method stick_events]); none when the player's layout has no
## use for it ([method unused]).
static func verb_events(player: int, verb: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if unused(player, verb):
		return out
	var bound := MwSettings.binding(player, verb)
	if bound != null:
		out.append(bound)
	else:
		out = default_events(player, verb)
	for event in stick_events(player, verb):
		_add(out, event)
	return out


## The stick axis driving direction verb [param verb] for [param player]
## (MwVerbs.STICKS): the bound one, else the layout's ([method
## default_stick]); empty for other verbs.
static func stick_events(player: int, verb: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not MwVerbs.is_direction(verb):
		return out
	var bound := MwSettings.stick_binding(player, verb)
	if bound != null:
		out.append(bound)
		return out
	return default_stick(player, verb)


## The layouts' stick for direction verb [param verb]: the left stick of
## the player's gamepad (device player - 1), as their D-pad (owner: mapped
## sensibly by default); none for a player without defaults.
static func default_stick(player: int, verb: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not MwVerbs.is_direction(verb):
		return out
	var place: String = ["UP", "DOWN", "LEFT", "RIGHT"][maxi(MwVerbs.MOVE.find(verb), MwVerbs.NAV.find(verb))]
	var m := InputEventJoypadMotion.new()
	m.device = player - 1
	m.axis = PAD_AXES[place][0]
	m.axis_value = PAD_AXES[place][1]
	out.append(m)
	return out


## The default inputs of [param verb] for [param player] in [param layout]
## (empty: the player's): the keyboard keys of the Genesis buttons it was
## on (player 1's keyboard), Esc for Menu Back and V for the view switch
## (player 1), and the gamepad (device player - 1) by the layout.
static func default_events(player: int, verb: String, layout := "") -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if verb == VIEW_TOGGLE and player != 1:
		return out
	if layout == "":
		layout = MwSettings.layout(player)
	if unused(player, verb, layout):
		return out
	var buttons := MwVerbs.genesis_buttons(verb)
	var layout_keys := keys(player) if not (layout == "STANDARD" and verb in STANDARD_PAD_ONLY) else {}
	for b in buttons:
		match b:
			"BACK":
				if player == 1:
					_add(out, _key(BACK_KEY))
			"VIEW":
				_add(out, _key(VIEW_KEY))
			_:
				if layout_keys.has(b):
					_add(out, _key(layout_keys[b]))
	var places: Array = []
	if layout == "STANDARD" and STANDARD_PAD.has(verb):
		places = STANDARD_PAD[verb]
	else:
		for b in buttons:
			places.append(GENESIS_PAD[b])
	for place in places:
		if PAD_TRIGGERS.has(place):
			var t := InputEventJoypadMotion.new()
			t.device = player - 1
			t.axis = PAD_TRIGGERS[place]
			t.axis_value = 1.0
			_add(out, t)
			continue
		if PAD.has(place):
			_add(out, _pad(player - 1, PAD[place]))
		if PAD_AXES.has(place) and not MwVerbs.is_direction(verb):     # directions: their stick
			var m := InputEventJoypadMotion.new()
			m.device = player - 1
			m.axis = PAD_AXES[place][0]
			m.axis_value = PAD_AXES[place][1]
			_add(out, m)
	return out


## [param verb] has no use in [param player]'s layout ([param layout]
## instead when given): the STANDARD layout's [constant STANDARD_UNUSED],
## the GENESIS layout's [constant GENESIS_UNUSED]; the shot heights in the
## STANDARD layout too while [member MwSettings.shot_heights] is off.
static func unused(player: int, verb: String, layout := "") -> bool:
	if layout == "":
		layout = MwSettings.layout(player)
	if layout == "STANDARD":
		return verb in STANDARD_UNUSED or (verb in MwVerbs.SHOT_HEIGHTS and not MwSettings.shot_heights)
	return verb in GENESIS_UNUSED


static func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	return k


static func _pad(device: int, button: JoyButton) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.device = device
	b.button_index = button
	return b


## Every action's events: action name -> events.
static func defaults() -> Dictionary:
	var out := {}
	for a in MwVerbs.every_action():
		out[a] = [] as Array[InputEvent]
	out[VIEW_TOGGLE] = [] as Array[InputEvent]
	for p in range(1, MwVerbs.PLAYERS + 1):
		for v in MwVerbs.all_verbs():
			var names: Array[String] = []
			if v == VIEW_TOGGLE:
				if p != 1:
					continue
				names.append(VIEW_TOGGLE)
			elif MwVerbs.is_local(v):
				names.append(v)                 # plan 38: the editor's own, shared (not in the stream)
			elif v.begins_with("ui_"):
				names.append_array([v, MwVerbs.menu_action(p, v)])
			else:
				names.append(MwVerbs.action(p, v))
			var events := verb_events(p, v)
			for n in names:
				for event in events:
					_add(out[n], event)
	for code in MENU_KEYS:
		for v in MENU_KEYS[code]:
			_add(out[v], _key(code))
			_add(out[MwVerbs.menu_action(1, v)], _key(code))
	return out


## Appends [param event] to [param events] unless the same input is there.
static func _add(events: Array, event: InputEvent) -> void:
	if not events.any(func(x: InputEvent) -> bool: return _same(x, event)):
		events.append(event)


## Same physical input on the same device (InputEvent.is_match ignores the
## gamepad device).
static func _same(a: InputEvent, b: InputEvent) -> bool:
	return a.get_class() == b.get_class() and a.device == b.device and a.as_text() == b.as_text()


static func _input_key(event: InputEvent) -> String:
	return "%s|%d|%s" % [event.get_class(), event.device, event.as_text()]


## The views' actions and their events ([constant VIEW_SELECT]: the F
## keys, [constant VIEW_NEXT]: any gamepad's Select).
static func view_events() -> Dictionary:
	var table := {}
	for i in VIEW_SELECT.size():
		var view_keys: Array[InputEvent] = [_key(VIEW_KEYS[i])]
		table[VIEW_SELECT[i]] = view_keys
	var back: Array[InputEvent] = [_pad(-1, JOY_BUTTON_BACK)]
	table[VIEW_NEXT] = back
	return table


## Installs every action (replacing existing events of these actions), and
## follows the gamepads coming and going ([member devices_changed]).
static func install() -> void:
	var joy := Callable(MwInputMap, "_joy_changed")
	if not Input.joy_connection_changed.is_connected(joy):
		Input.joy_connection_changed.connect(joy)
	var table := defaults()
	table.merge(view_events())
	for a in table:
		if not InputMap.has_action(a):
			InputMap.add_action(a, DEADZONE)
		else:
			InputMap.action_erase_events(a)
			InputMap.action_set_deadzone(a, DEADZONE)
		for e in table[a]:
			InputMap.action_add_event(a, e)
	MwGlyphs.refresh_live()                  # the prompts show the new bindings (plan 23)


## The verbs sharing an input with another verb live at the same time
## ([method screen_contexts]): "p<player>_<verb>" -> true, or with
## [constant STICK_MARK] after it when the shared input is the verb's stick. Fine, and not
## listed: one verb's inputs for several players (menu verbs are shared)
## and the verbs of one tap / hold group (MwVerbs.GROUPS). The permanent
## menu keys count as player 1's.
##
## Worked out once per state of the bindings ([method bindings_state]) and
## handed out as a copy: the bindings page asks at every move (owner,
## 2026-10-12: the stutter moving between its rows - twelve players' inputs
## for every verb, ~70 ms on the VM a move).
static func collisions() -> Dictionary:
	var state := bindings_state()
	if _collisions_state != state:
		_collisions = _work_out_collisions()
		_collisions_state = state
	return _collisions.duplicate()


static var _collisions := {}
static var _collisions_state := ""


## What the players' inputs follow from, as a key: their bindings, sticks
## and layouts, and the shot heights' switch (MwSettings) - the rest is this
## class's constants.
static func bindings_state() -> String:
	return "%d|%d|%d|%s" % [MwSettings.bindings.hash(), MwSettings.sticks.hash(), MwSettings.layouts.hash(),
			MwSettings.shot_heights]


static func _work_out_collisions() -> Dictionary:
	var events := {}
	var sticks := {}                                    # "p1_move_up|<input>": the verb's stick
	for p in range(1, MwVerbs.PLAYERS + 1):
		for v in MwVerbs.all_verbs():
			var list := verb_events(p, v)
			for event in stick_events(p, v):
				sticks["%s|%s" % [MwVerbs.player_key(p, v), _input_key(event)]] = true
			if p == 1:
				for code in MENU_KEYS:
					if v in MENU_KEYS[code]:
						_add(list, _key(code))
			events[MwVerbs.player_key(p, v)] = list
	var out := {}
	for ctxs in screen_contexts():
		var live := []
		for ctx in ctxs:
			for v in MwVerbs.context_verbs(ctx):
				if not v in live:
					live.append(v)
		if MwVerbs.Context.GAMEPLAY in ctxs:
			live.append(VIEW_TOGGLE)
			live.append(MwVerbs.RECLAIM)
			live.append_array(MwVerbs.SHOT_HEIGHTS)
		var by_input := {}
		for p in range(1, MwVerbs.PLAYERS + 1):
			for v in live:
				var key := MwVerbs.player_key(p, v)
				var meaning := MwVerbs.meaning(v)
				if not v.begins_with("ui_") and not MwVerbs.is_local(v):
					meaning = "p%d:%s" % [p, meaning]
				for e in events[key]:
					var k := _input_key(e)
					if not by_input.has(k):
						by_input[k] = {}
					by_input[k][key] = meaning
		for k in by_input:
			var users: Dictionary = by_input[k]
			var meanings := {}
			for key in users:
				meanings[users[key]] = true
			if meanings.size() > 1:
				for key in users:
					out[key + STICK_MARK if sticks.has(key + "|" + k) else key] = true
	return out


## The sets of contexts whose verbs are live together: each context alone
## (a screen with two reads one at a time: the rink's play or its pause
## menu), and the period-end scoreboard with its Zamboni whip.
static func screen_contexts() -> Array:
	var out := []
	for ctx in MwVerbs.PAD_TO_VERB:
		out.append([ctx])
	out.append([MwVerbs.Context.SCOREBOARD, MwVerbs.Context.ZAMBONI])
	return out


# --- plan 40 (I3): the bindings' input helpers (were MwSettings', which keeps the storage) ------

## The (x, y) axes of the stick [param event] moved: a gamepad's left or right
## stick; empty for anything else (a trigger, a key, a button, null).
static func stick_axes(event: InputEvent) -> Array[JoyAxis]:
	var out: Array[JoyAxis] = []
	if event is InputEventJoypadMotion and absf(event.axis_value) >= DEADZONE:
		if event.axis == JOY_AXIS_LEFT_X or event.axis == JOY_AXIS_LEFT_Y:
			out.assign([JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y])
		elif event.axis == JOY_AXIS_RIGHT_X or event.axis == JOY_AXIS_RIGHT_Y:
			out.assign([JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y])
	return out


## A clean copy of [param event] as a binding: the physical key (no echo,
## no modifiers), the gamepad button, or the gamepad axis and its direction.
## Null for anything else (mouse, touch, a stick barely moved) and for what
## can't be bound ([method bindable]).
static func normalized(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		if not bindable(event):
			return null
		var k := InputEventKey.new()
		k.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return k
	if event is InputEventJoypadButton:
		var b := InputEventJoypadButton.new()
		b.device = event.device
		b.button_index = event.button_index
		return b
	if event is InputEventJoypadMotion and absf(event.axis_value) >= DEADZONE:
		var m := InputEventJoypadMotion.new()
		m.device = event.device
		m.axis = event.axis
		m.axis_value = signf(event.axis_value)
		return m
	return null


## False for the inputs no button may take: the function keys (owner: they
## stay the rink's views, plan 20).
static func bindable(event: InputEvent) -> bool:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return code < KEY_F1 or code > KEY_F35
	return true


## "key:<physical keycode>", "button:<device>:<index>", "axis:<device>:<axis>:<+1|-1>".
static func encode_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key:%d" % event.physical_keycode
	if event is InputEventJoypadButton:
		return "button:%d:%d" % [event.device, event.button_index]
	if event is InputEventJoypadMotion:
		return "axis:%d:%d:%d" % [event.device, event.axis, 1 if event.axis_value > 0 else -1]
	return ""


## The input [method encode_event] wrote as [param text], or null for a text not
## of its forms.
static func decode_event(text: String) -> InputEvent:
	var parts := text.split(":")
	match parts[0]:
		"key":
			if parts.size() == 2:
				var k := InputEventKey.new()
				k.physical_keycode = int(parts[1]) as Key
				return k
		"button":
			if parts.size() == 3:
				var b := InputEventJoypadButton.new()
				b.device = int(parts[1])
				b.button_index = int(parts[2]) as JoyButton
				return b
		"axis":
			if parts.size() == 4:
				var m := InputEventJoypadMotion.new()
				m.device = int(parts[1])
				m.axis = int(parts[2]) as JoyAxis
				m.axis_value = 1.0 if int(parts[3]) > 0 else -1.0
				return m
	return null


const _PAD_BUTTONS := ["A", "B", "X", "Y", "BACK", "GUIDE", "START", "LS", "RS", "LB", "RB",
		"DPAD UP", "DPAD DOWN", "DPAD LEFT", "DPAD RIGHT", "MISC", "PADDLE 1", "PADDLE 2",
		"PADDLE 3", "PADDLE 4", "TOUCHPAD"]
const _AXES := [["LS LEFT", "LS RIGHT"], ["LS UP", "LS DOWN"], ["RS LEFT", "RS RIGHT"],
		["RS UP", "RS DOWN"], ["LT", "LT"], ["RT", "RT"]]
## Key names whose characters the menu fonts lack (both fonts have
## ! " # % ' ( ) , - . / : = ? _ ` and the letters and digits).
const _SYMBOLS := {";": "SEMICOLON", "\\": "BACKSLASH", "+": "PLUS", "*": "ASTERISK",
		"<": "LESS", ">": "GREATER", "&": "AMPERSAND", "$": "DOLLAR", "^": "CARET",
		"~": "TILDE", "@": "AT", "[": "BRACKET L", "]": "BRACKET R"}


## What the menus show for an input: "Z", "ENTER", "PAD1 X", "PAD2 LS UP".
static func event_name(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var shown := code
		if DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_keycode_from_physical(code as Key)
		var text := OS.get_keycode_string(shown as Key).to_upper()
		if text.is_empty():
			text = "KEY %d" % code
		return _SYMBOLS.get(text, text)
	if event is InputEventJoypadButton:
		var i: int = event.button_index
		var n: String = _PAD_BUTTONS[i] if i >= 0 and i < _PAD_BUTTONS.size() else "BUTTON %d" % i
		return "PAD%d %s" % [event.device + 1, n]
	if event is InputEventJoypadMotion:
		var a: int = event.axis
		var n: String = _AXES[a][1 if event.axis_value > 0 else 0] if a >= 0 and a < _AXES.size() else "AXIS %d" % a
		return "PAD%d %s" % [event.device + 1, n]
	return "?"
