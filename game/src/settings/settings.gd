class_name MwSettings
extends RefCounted
## The port's options (plan 21; owner, 2026-10-08), kept in
## `user://settings.cfg` and saved whenever the options menus change one:
##
## * [member camera]: the view every match starts in ([constant CAMERAS]: 2D or
##   3D, the follow camera; the matchup sets [member MwSession.view] from it).
##   Plan 20's other views stay on the F keys, debug views for now (owner).
## * [member enhance_audio]: plan 12's enhancement switches
##   ([member MwAudio.free_music_samples], [member MwAudio.free_effects]).
## * [member fullscreen]: the window full screen or windowed.
## * [member bindings]: the buttons a player rebound, one input each
##   ([MwInputMap] builds every action from them). The function keys are
##   never bound: they stay the rink's views (plan 20, debug views - owner).
## * [member front_menu]: the port's own main menu after the title (screens
##   100-102, `scenes/port_menu/`); off: the original's title -> credits ->
##   game setup. Not in the menus (tests and comparisons turn it off).
##
## Everything is static: one set of settings per run of the game.

const PATH := "user://settings.cfg"
## The views a match can start in: the original's 2D, or 3D (owner: plan 20's
## follow camera; its other views are reached with the F keys only).
const CAMERAS: Array[String] = ["2D", "3D"]
const CAMERA_VIEWS: Array[int] = [MwRinkViews.FLAT, MwRinkViews.FOLLOW]
## The buttons a player has (the original's eight, then Menu Back).
const BUTTONS: Array[String] = ["UP", "DOWN", "LEFT", "RIGHT", "A", "B", "C", "START", "BACK"]
## Player 1's extra button: the 2D / 3D switch (owner; [constant
## MwInputMap.VIEW_TOGGLE]), not one of the original's.
const P1_BUTTONS: Array[String] = ["VIEW"]

## Where [method load_file] / [method save] read and write (tests use another).
static var path := PATH
## Index into [constant CAMERAS].
static var camera := 0
## A view (MwRinkViews) every match starts in instead of [member camera]; -1
## none. Not saved: tests and `live_match.gd --view`.
static var start_view := -1
static var enhance_audio := true
static var fullscreen := false
static var front_menu := true
## Rebound buttons: "p<player>_<button>" (button of [constant BUTTONS]) ->
## the input (an [InputEventKey], [InputEventJoypadButton] or
## [InputEventJoypadMotion]).
static var bindings := {}


## Reads [member path] (missing file or keys: the defaults).
static func load_file() -> void:
	var cfg := ConfigFile.new()
	camera = 0
	enhance_audio = true
	fullscreen = false
	bindings = {}
	if not FileAccess.file_exists(path) or cfg.load(path) != OK:
		return
	var c := str(cfg.get_value("game", "camera", CAMERAS[0]))
	camera = maxi(CAMERAS.find(c), 0)
	enhance_audio = bool(cfg.get_value("audio", "enhance", true))
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	if cfg.has_section("bindings"):
		for key in cfg.get_section_keys("bindings"):
			var e := decode_event(str(cfg.get_value("bindings", key, "")))
			if e != null and bindable(e):
				bindings[key] = e


## Writes [member path].
static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "camera", CAMERAS[camera])
	cfg.set_value("audio", "enhance", enhance_audio)
	cfg.set_value("display", "fullscreen", fullscreen)
	for key in bindings:
		cfg.set_value("bindings", key, encode_event(bindings[key]))
	cfg.save(path)


## Puts the settings into effect: the audio switches, the window and the
## input map.
static func apply() -> void:
	apply_audio()
	apply_display()
	MwInputMap.install()


## [member enhance_audio] -> plan 12's two switches.
static func apply_audio() -> void:
	MwAudio.free_music_samples = enhance_audio
	MwAudio.free_effects = enhance_audio


## [member fullscreen] -> the window (Godot's borderless full screen); nothing
## without a display. A maximised window stays as it is when windowed.
static func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## The buttons [param player] can rebind ([constant BUTTONS], and player 1's
## [constant P1_BUTTONS]).
static func buttons(player: int) -> Array[String]:
	var out: Array[String] = []
	out.append_array(BUTTONS)
	if player == 1:
		out.append_array(P1_BUTTONS)
	return out


## The camera a new match starts in ([constant CAMERAS]).
static func camera_name() -> String:
	return CAMERAS[clampi(camera, 0, CAMERAS.size() - 1)]


## The view (MwRinkViews) a match starts in.
static func view() -> int:
	if start_view >= 0:
		return start_view
	return CAMERA_VIEWS[clampi(camera, 0, CAMERA_VIEWS.size() - 1)]


static func _key(player: int, button: String) -> String:
	return "p%d_%s" % [player, button]


## The input [param player] (1-4) rebound [param button] to, or null (the
## default).
static func binding(player: int, button: String) -> InputEvent:
	return bindings.get(_key(player, button))


## [param player]'s [param button] is [param event] from now on (null: back
## to the default); the input map is rebuilt and the file saved.
static func set_binding(player: int, button: String, event: InputEvent) -> void:
	if event == null:
		bindings.erase(_key(player, button))
	else:
		bindings[_key(player, button)] = normalized(event)
	MwInputMap.install()
	save()


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
	if event is InputEventJoypadMotion and absf(event.axis_value) >= MwInputMap.DEADZONE:
		var m := InputEventJoypadMotion.new()
		m.device = event.device
		m.axis = event.axis
		m.axis_value = signf(event.axis_value)
		return m
	return null


## False for the inputs no button may take: the function keys (owner: they
## stay the rink's views, plan 20).
static func bindable(e: InputEvent) -> bool:
	if e is InputEventKey:
		var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		return code < KEY_F1 or code > KEY_F35
	return true


## "key:<physical keycode>", "button:<device>:<index>", "axis:<device>:<axis>:<+1|-1>".
static func encode_event(e: InputEvent) -> String:
	if e is InputEventKey:
		return "key:%d" % e.physical_keycode
	if e is InputEventJoypadButton:
		return "button:%d:%d" % [e.device, e.button_index]
	if e is InputEventJoypadMotion:
		return "axis:%d:%d:%d" % [e.device, e.axis, 1 if e.axis_value > 0 else -1]
	return ""


static func decode_event(s: String) -> InputEvent:
	var p := s.split(":")
	match p[0]:
		"key":
			if p.size() == 2:
				var k := InputEventKey.new()
				k.physical_keycode = int(p[1]) as Key
				return k
		"button":
			if p.size() == 3:
				var b := InputEventJoypadButton.new()
				b.device = int(p[1])
				b.button_index = int(p[2]) as JoyButton
				return b
		"axis":
			if p.size() == 4:
				var m := InputEventJoypadMotion.new()
				m.device = int(p[1])
				m.axis = int(p[2]) as JoyAxis
				m.axis_value = 1.0 if int(p[3]) > 0 else -1.0
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
static func event_name(e: InputEvent) -> String:
	if e is InputEventKey:
		var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		var shown := code
		if DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_keycode_from_physical(code as Key)
		var s := OS.get_keycode_string(shown as Key).to_upper()
		if s.is_empty():
			s = "KEY %d" % code
		return _SYMBOLS.get(s, s)
	if e is InputEventJoypadButton:
		var i: int = e.button_index
		var n: String = _PAD_BUTTONS[i] if i >= 0 and i < _PAD_BUTTONS.size() else "BUTTON %d" % i
		return "PAD%d %s" % [e.device + 1, n]
	if e is InputEventJoypadMotion:
		var a: int = e.axis
		var n: String = _AXES[a][1 if e.axis_value > 0 else 0] if a >= 0 and a < _AXES.size() else "AXIS %d" % a
		return "PAD%d %s" % [e.device + 1, n]
	return "?"
