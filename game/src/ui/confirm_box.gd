class_name MwConfirmBox
extends Node2D
## A YES / NO question over a screen (plan 34: leaving a playoff run,
## overwriting or deleting a save, keeping a replay), in the pause menu's
## look - it is the pause menu's confirm page ([MwPauseMenu], plan 23: the
## big font's title in greys, a line on the black plate, YES and NO with the
## title screen's eyes on the selected one) over the screen dimmed (true
## translucency, as the port uses instead of shadow / highlight).
## [method handle] takes the menu verbs while it is open; [signal answered]
## says what was chosen (Menu Back: NO).

## The question was answered, the box closed: [param yes] true for YES, false for NO or Menu Back.
signal answered(yes: bool)

const SOUND_MOVE := MwSoundIds.MOVE
const SHADE := Color(0, 0, 0, 0.6)

var menu := MwPauseMenu.new()
var shade := ColorRect.new()
var active := false
## 0 YES, 1 NO (the pause menu's FORFEIT question starts on NO).
var sure := 1
## Who answers: 0 anyone (the shared menu verbs), else that player alone
## (their own: the end of a match's SAVE REPLAY?, player 1's).
var player := 0
var _title := ""
var _line := ""
var _attr := 0x20


## Uses [param window]'s tiles and palette (as the pause menu does).
func setup(window: RomPlane, rom: PackedByteArray) -> void:
	z_index = 30
	shade.color = SHADE
	shade.size = Vector2(320, 224)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	menu.setup(window, rom, MwPauseMenu.with_fonts(window.tiles))
	add_child(menu)
	visible = false


## Asks [param line] (on the plate) under [param title]; the items in
## palette attr [param attr]; NO selected unless [param yes_first].
func open(line: String, title := "ARE YOU SURE?", attr := 0x20, yes_first := false) -> void:
	_title = title
	_line = line
	_attr = attr
	sure = 0 if yes_first else 1
	active = true
	visible = true
	_draw()


## Hides the box without an answer (no [signal answered]).
func close() -> void:
	active = false
	visible = false
	menu.close()


## One pass: true while open (the screen's own input waits).
func handle(input: MwInputFrame) -> bool:
	if not active:
		return false
	if input == null:
		return true
	if _pressed(input, "ui_up") or _pressed(input, "ui_down") or _pressed(input, "ui_left") \
			or _pressed(input, "ui_right"):
		sure ^= 1
		MwSound.play(SOUND_MOVE)
		_draw()
	elif _pressed(input, "ui_accept"):
		var yes := sure == 0
		close()
		answered.emit(yes)
	elif _pressed(input, "ui_back"):
		close()
		answered.emit(false)
	return true


func _pressed(input: MwInputFrame, verb: String) -> bool:
	return input.menu_pressed(player, verb) if player > 0 else input.is_pressed(verb)


func _draw() -> void:
	menu.show_menu({"confirm": true, "sure": sure, "title": _title, "line": _line}, _attr)
