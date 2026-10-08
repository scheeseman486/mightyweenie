class_name MwPortMenu
extends MwScreen
## The port's own menus (plan 21; owner, 2026-10-08: "a true options menu
## that looks original"), one scene for three screens ([constant MwScreens.PORT]):
##
## * 100, the front menu after the title (the owner's "Main Menu"): START
##   GAME (the game setup, the original's main menu 1), OPTIONS, CREDITS (the
##   title screen's credits roll), QUIT GAME (the screen and the music fade
##   out, then the game closes); 1800 ticks without a press start the
##   attract demo; Menu Back goes back to the title.
## * 101, options: CAMERA (the view every match starts in: 2D, or 3D - the
##   follow camera), ENHANCE AUDIO (plan 12's switches), DISPLAY (windowed or
##   full screen), CONTROLLER BINDINGS.
## * 102, controller bindings: Left / Right picks the player, Up / Down the
##   button (player 1 also has 2D / 3D, the view switch), Start waits for
##   the next input - any key but the function keys (the views'), gamepad
##   button or stick of any device - and binds it ([MwSettings]). The menu
##   then waits for that input to be let go, so the press that was bound
##   doesn't also move the menu (owner).
##
## Selecting: Start, or B (owner: the gamepad's south button, A on an Xbox
## pad, selects too). Only here: in the original's screens B has meanings
## of its own next to Start (team description pages, the champion's
## screen, the password), so it isn't added to `ui_accept`.
##
## The look and feel are the original menus': the main menu's scrolling
## starfield and palette, the logo cut from its backdrop, the menu fonts,
## the highlight frame (filled when the selection moves) with the dark font
## on the selected row, sound `$25` on every move and change, full-screen
## fades between screens. The labels are the port's own text.

const BACKDROP := 0x41BF2            ## the game setup's backdrop (main_menu.gd)
## The logo inside the backdrop's stone frame (cells) and where it goes.
const LOGO := Rect2i(15, 3, 10, 8)
const LOGO_AT := Vector2i(15, 2)
const SOUND_MOVE := 0x25             ## `$13CEE` sound: row moved / value changed
const FONT_LIGHT := MwPlanePainter.FONT_MENU
const FONT_DARK := MwPlanePainter.FONT_SMALL
const TEXT_ATTR := MwMenuRows.TEXT_ATTR
## Menu rows like the original's (a frame 34 cells wide), centred on the
## screen: inside cells 3-36, edges in 2 and 37 (the game setup's start at 4).
const ROW_X := 3
const ROW_W := 0x22
## The front menu's centred items and their frame.
const ITEM_W := 14
## Waiting for an input to bind: given up after this many ticks.
const CAPTURE_TICKS := 300
## QUIT GAME: the fade-out (screen and music) before the game closes.
const QUIT_TICKS := 32
const OFF_ON := ["OFF", "ON"]
const DISPLAY := ["WINDOWED", "FULLSCREEN"]
const BUTTON_LABELS := {"UP": "UP", "DOWN": "DOWN", "LEFT": "LEFT", "RIGHT": "RIGHT", "A": "A",
		"B": "B", "C": "C", "START": "START", "BACK": "MENU BACK", "VIEW": "2D / 3D"}

enum Kind { ITEM, CHOICE, BINDING }

@onready var plane: RomPlane = $Plane
## Text centred on half a cell: the same tiles 4 pixels to the right.
@onready var half_plane: RomPlane = $HalfPlane
@onready var starfield: RomStarfield = $Starfield
@onready var palette: RomPalette = $Plane.palette

var rom: PackedByteArray
## The page: "main", "options" or "bindings" (the entry variant).
var page := "main"
## Rows of the page: {kind, label, y, action / button}.
var rows: Array[Dictionary] = []
var row := 0
## Bindings: the player (1-4) and the button waiting for its input ("" none).
var player := 1
var capturing := ""
var idle := 0
## What QUIT GAME does once the fade-out is over (tests put their own here).
var quit_game := func() -> void: get_tree().quit()

var _fill := true                    # the highlight is filled on its next drawing
var _capture_left := 0
var _settle := false                 # ignore the pads until everything is released
var _bound: InputEvent = null        # ... and the input just bound
var _quit_left := -1                 # QUIT GAME: ticks of fade-out left (-1: not quitting)


func _enter_screen(_data: Dictionary) -> void:
	page = entry if entry != "" else "main"
	if not MwRom.available():
		return
	rom = MwRom.data()
	if session:
		palette.team_a = session.setup.team_a
		starfield.start(session.rng_aux)
	palette.screen = 1
	# line 1: the logo's colours as on the game setup screen; its black panel
	# (colour 15) see-through, so the starfield shows around the letters (owner)
	palette.steps = PackedStringArray(["screen_palette", "black 0", "panel_line a 1", "clear 31"])
	if page == "main":
		MwSound.music_title()            # the title's music goes on (it did into the credits)
	var st: Dictionary = session.screens.get(screen_id, {}) if session else {}
	player = int(st.get("player", 1))
	_build_rows()
	row = clampi(int(st.get("row", 0)), 0, rows.size() - 1)
	_draw()


func _build_rows() -> void:
	rows.clear()
	match page:
		"main":
			for i in 4:
				rows.append({"kind": Kind.ITEM, "label": ["START GAME", "OPTIONS", "CREDITS", "QUIT GAME"][i],
						"action": ["start", "options", "credits", "quit"][i], "y": 14 + 3 * i})
		"options":
			rows.append({"kind": Kind.CHOICE, "label": "CAMERA", "action": "camera", "y": 14})
			rows.append({"kind": Kind.CHOICE, "label": "ENHANCE AUDIO", "action": "audio", "y": 17})
			rows.append({"kind": Kind.CHOICE, "label": "DISPLAY", "action": "display", "y": 20})
			rows.append({"kind": Kind.ITEM, "label": "CONTROLLER BINDINGS", "action": "bindings", "y": 23})
		"bindings":
			var buttons := MwSettings.buttons(player)
			for i in buttons.size():
				var b: String = buttons[i]
				rows.append({"kind": Kind.BINDING, "label": BUTTON_LABELS[b], "button": b, "y": 8 + 2 * i})


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty():
		return
	for i in elapsed:
		starfield.step()                 # VBlank task
	if _quit_left >= 0:
		_quit_left = maxi(_quit_left - elapsed, 0)
		if _quit_left == 0 and (fader == null or not fader.busy()):
			_quit_left = -2              # once
			quit_game.call()
		return
	if _quit_left == -2:
		return
	if capturing != "":
		_capture_left -= elapsed
		if _capture_left <= 0:
			capturing = ""               # nothing came: the binding stays
			_settle = true
			_draw()
		return
	if _settle:
		if (input != null and not input.held.is_empty()) or held_down(_bound):
			return
		_settle = false
		_bound = null
	idle += elapsed
	if input == null:
		return
	if not input.pressed.is_empty():
		idle = 0
	elif page == "main" and idle >= MwAttract.IDLE_TICKS:
		_attract()
		return
	if input.is_pressed("ui_back"):
		_back()
	elif input.is_pressed("ui_up"):
		_move(-1)
	elif input.is_pressed("ui_down"):
		_move(1)
	elif input.is_pressed("ui_left"):
		_change(-1)
	elif input.is_pressed("ui_right"):
		_change(1)
	elif input.is_pressed("ui_accept") or input.is_pressed("ui_option_b"):
		_accept()


# --- actions -------------------------------------------------------------------------------------
func _move(d: int) -> void:
	row = posmod(row + d, rows.size())
	_fill = true
	MwSound.play(SOUND_MOVE)
	_draw()


func _change(d: int) -> void:
	if page == "bindings":
		player = posmod(player - 1 + d, MwVerbs.PLAYERS) + 1
		_build_rows()                    # player 1 has one more button
		row = mini(row, rows.size() - 1)
	else:
		match rows[row].get("action", ""):
			"camera":
				MwSettings.camera = posmod(MwSettings.camera + d, MwSettings.CAMERAS.size())
			"audio":
				MwSettings.enhance_audio = not MwSettings.enhance_audio
				MwSettings.apply_audio()
			"display":
				MwSettings.fullscreen = not MwSettings.fullscreen
				MwSettings.apply_display()
			_:
				return
		MwSettings.save()
	_fill = true
	MwSound.play(SOUND_MOVE)
	_draw()


func _accept() -> void:
	_remember()
	match page:
		"main":
			match rows[row].action:
				"start":
					MwSound.music_fade_out(32)
					exit_to(1)
				"options":
					exit_to(MwScreens.OPTIONS)
				"credits":
					exit_to(0, {"credits": true})
				"quit":
					_quit()
		"options":
			if rows[row].action == "bindings":
				exit_to(MwScreens.BINDINGS)
		"bindings":
			capturing = rows[row].button
			_capture_left = CAPTURE_TICKS
			_draw()


## QUIT GAME: the screen and the music fade out, then [member quit_game].
func _quit() -> void:
	_quit_left = QUIT_TICKS
	MwSound.music_fade_out(QUIT_TICKS)
	if fader:
		fader.fade_out(QUIT_TICKS)


## Menu Back: one screen up.
func _back() -> void:
	_remember()
	match page:
		"main":
			exit_to(0, {"title": true})
		"options":
			exit_to(MwScreens.FRONT_MENU)
		"bindings":
			exit_to(MwScreens.OPTIONS)


## Idle on the front menu: the attract demo, as the game setup's idle does
## (`$138BE`: as if Start was pressed, then the matchup with the demo setup);
## the demo comes back here.
func _attract() -> void:
	session.attract = true
	session.attract_return = MwScreens.FRONT_MENU
	session.playoffs.start(session.setup, session.rng)     # `$11D8E`, as the game setup's Start
	MwSound.music_fade_out(32)
	exit_to(3)


func _remember() -> void:
	if session:
		session.screens[screen_id] = {"row": row, "player": player}


## Binding capture: the next input pressed, from any device.
func _input(event: InputEvent) -> void:
	if capturing == "" or event.is_echo() or not event.is_pressed():
		return
	var e := MwSettings.normalized(event)
	if e == null:
		return
	get_viewport().set_input_as_handled()
	take_binding(e)


## Binds [param e] to the button waiting for one (also tests).
func take_binding(e: InputEvent) -> void:
	if capturing == "":
		return
	MwSettings.set_binding(player, capturing, e)
	capturing = ""
	_settle = true
	_bound = e
	_fill = true
	MwSound.play(SOUND_MOVE)
	_draw()


## True while [param e] (a binding: key, gamepad button or stick direction)
## is held down. A key held after it was bound repeats, and the repeats are
## presses of the actions it now drives (Godot counts echoes), so the menu
## waits for the input itself, not just for its actions.
static func held_down(e: InputEvent) -> bool:
	if e is InputEventKey:
		return Input.is_physical_key_pressed(e.physical_keycode)
	if e is InputEventJoypadButton:
		return Input.is_joy_button_pressed(e.device, e.button_index)
	if e is InputEventJoypadMotion:
		return Input.get_joy_axis(e.device, e.axis) * signf(e.axis_value) >= MwInputMap.DEADZONE / 2.0
	return false


# --- drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	plane.clear()
	half_plane.clear()
	match page:
		"main":
			_logo()
		"options":
			_logo()
			_centred("OPTIONS", 11, FONT_LIGHT)
		"bindings":
			_centred("CONTROLLER BINDINGS", 3, FONT_LIGHT)
			_centred("PLAYER %d" % player, 5, FONT_LIGHT)
	for i in rows.size():
		_draw_row(i, i == row)
	_fill = false


## The logo cut from the game setup's backdrop.
func _logo() -> void:
	var pic := MwGfx.picture(rom, BACKDROP)
	var w: int = pic["width"]
	var map: int = pic["map"] + 2 * (LOGO.position.y * w + LOGO.position.x)
	MwPlanePainter.map_rect(plane, rom, map, w, LOGO.size.x, LOGO.size.y, LOGO_AT.x, LOGO_AT.y)


func _draw_row(i: int, selected: bool) -> void:
	var r := rows[i]
	var y: int = r.y
	var centred_item: bool = r.kind == Kind.ITEM and page == "main"
	var x0 := _half(40 - ITEM_W) if centred_item else ROW_X
	var w := ITEM_W if centred_item else ROW_W
	if selected:
		MwPlanePainter.frame(plane, rom, x0, y, w, 1, true)
	var font := FONT_DARK if selected else FONT_LIGHT
	var label := _ascii(r.label)
	if r.kind == Kind.ITEM:
		_text_centred(label, 2 * x0 + w, y, font)
		return
	_text(label, x0, y, font)
	var value := _ascii(_value(r))
	var room := w - _width(font, label) - 2
	while value.size() > 1 and _width(font, value) > room:
		value = value.slice(0, value.size() - 1)
	_text(value, x0 + w - _width(font, value), y, font)


## What a row shows on its right.
func _value(r: Dictionary) -> String:
	match r.kind:
		Kind.CHOICE:
			match r.action:
				"camera":
					return MwSettings.camera_name()
				"display":
					return DISPLAY[1 if MwSettings.fullscreen else 0]
			return OFF_ON[1 if MwSettings.enhance_audio else 0]
		Kind.BINDING:
			if capturing == r.button:
				return "PRESS ANY INPUT"
			return binding_text(player, r.button)
	return ""


## The inputs of [param button] for [param player] as the menu shows them:
## the bound one, or the defaults (keyboard and the first gamepad input).
static func binding_text(p: int, button: String) -> String:
	var bound := MwSettings.binding(p, button)
	if bound != null:
		return MwSettings.event_name(bound)
	var names := PackedStringArray()
	var pad := false
	for e in MwInputMap.default_events(p, button):
		if e is InputEventKey:
			names.append(MwSettings.event_name(e))
		elif not pad:
			names.append(MwSettings.event_name(e))
			pad = true
	return " / ".join(names) if not names.is_empty() else "NONE"


func _centred(s: String, y: int, font: int) -> void:
	_text_centred(_ascii(s), 40, y, font)


## [param b] centred on [param twice_centre] / 2 cells, to half a cell: an odd
## leftover goes on the plane shifted 4 pixels right.
func _text_centred(b: PackedByteArray, twice_centre: int, y: int, font: int) -> void:
	var twice_x := twice_centre - _width(font, b)
	if twice_x % 2 == 0:
		_text(b, _half(twice_x), y, font)
	else:
		MwPlanePainter.text(half_plane, rom, font, b, _half(twice_x - 1), y, TEXT_ATTR)


func _text(b: PackedByteArray, x: int, y: int, font: int) -> void:
	MwPlanePainter.text(plane, rom, font, b, x, y, TEXT_ATTR)


func _width(font: int, b: PackedByteArray) -> int:
	return MwGfx.text_width(rom, font, b)


static func _half(v: int) -> int:
	@warning_ignore("integer_division")
	return v / 2


static func _ascii(s: String) -> PackedByteArray:
	return s.to_ascii_buffer()
