class_name MwKeyGate
extends RefCounted
## The keyboard's verbs held back while a text input types (owner,
## 2026-10-10: typing set off the keyboard's bindings).
##
## Player 1's keys drive verbs (Z / X / C, Enter, Esc, the arrows, A / S /
## Q ...: MwInputMap.KEYS and MENU_KEYS) and they are letters too. While a
## text input takes the keyboard's text ([method take], from
## MwTextField.begin to MwTextField.finish), [MwLiveInput] reads every
## action from the other inputs only - the gamepads still drive the screen
## (the keys on a text input screen) - and the keyboard goes to the text
## input alone (its own keys: Enter, Esc, Backspace, the arrows inside the
## text, paste). When it ends ([method give_back]), the keys held then stay
## held back until they are let go, so the key that ended it (Enter, Esc)
## is no press on the screen underneath; then every binding is live again.
##
## Godot keeps one state per action, whatever pressed it, so the gate reads
## the inputs themselves ([method held]): a key by its code, a gamepad
## button or axis on its device.

## The text input that has the keyboard (null: none).
static var _taker: WeakRef = null
## The keys held when the keyboard was given back: "p<physical code>" or
## "k<key code>" -> true, until they are let go.
static var _latched := {}


## [param taker] (a text input) types: the keys drive no verbs.
static func take(taker: Object) -> void:
	_taker = weakref(taker)


## [param taker] is done typing: the keys drive verbs again, those held now
## once they are let go.
static func give_back(taker: Object) -> void:
	if _taker == null or _taker.get_ref() != taker:
		return
	_taker = null
	for a in InputMap.get_actions():
		for event in InputMap.action_get_events(a):
			if event is InputEventKey and down(event, 0.5):
				_latched[_name(event as InputEventKey)] = true


## True while a text input has the keyboard (a freed one has not).
static func taking() -> bool:
	return _taker != null and _taker.get_ref() != null


## True when some key drives no verb now: a text input types, or a key
## held when it ended is still down.
static func active() -> bool:
	return taking() or not _latched.is_empty()


## Each tick ([method MwLiveInput.tick]): the held-back keys let go are
## live again.
static func update() -> void:
	for k: String in _latched.keys():
		var code := int(k.substr(1))
		var still := Input.is_physical_key_pressed(code) if k[0] == "p" else Input.is_key_pressed(code)
		if not still:
			_latched.erase(k)


## True when input [param event] (an action's event) may drive verbs now (a
## held-back key found let go is live again).
static func passes(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return true
	if taking():
		return false
	var n := _name(event as InputEventKey)
	if _latched.has(n) and not down(event, 0.5):
		_latched.erase(n)
	return not _latched.has(n)


## True when [param action] is held by an input the gate lets through.
static func held(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	var dz := InputMap.action_get_deadzone(action)
	for event in InputMap.action_get_events(action):
		if passes(event) and down(event, dz):
			return true
	return false


## True while input [param event] is down: a key, a gamepad button, an axis
## past [param deadzone] its way (device -1: any gamepad).
static func down(event: InputEvent, deadzone: float) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.physical_keycode != KEY_NONE:
			return Input.is_physical_key_pressed(k.physical_keycode)
		return k.keycode != KEY_NONE and Input.is_key_pressed(k.keycode)
	var devices: Array = [event.device] if event.device >= 0 else Input.get_connected_joypads()
	for d in devices:
		if event is InputEventJoypadButton and Input.is_joy_button_pressed(d,
				(event as InputEventJoypadButton).button_index):
			return true
		if event is InputEventJoypadMotion:
			var m := event as InputEventJoypadMotion
			if Input.get_joy_axis(d, m.axis) * signf(m.axis_value) >= deadzone:
				return true
	return false


## Nobody typing, nothing held back (tests; a fresh game).
static func reset() -> void:
	_taker = null
	_latched = {}


static func _name(k: InputEventKey) -> String:
	return "p%d" % k.physical_keycode if k.physical_keycode != KEY_NONE else "k%d" % k.keycode
