class_name MwTextInputScreen
extends MwScreen
## A text input screen (the port's; owner, 2026-10-10: one text input for
## CREATE-A-TEAM and the online pages, general enough for other uses later).
## Pushed over the screen that asks for a text, with the [MwTextField] to
## edit in the data's "field" (its options: the characters, the length,
## masking, paste, the pads' keys). The keyboard types and the pads pick from
## the keys on the screen, both at once, whichever comes. The look is the
## scene's:
## [MwTextEntry] (131, CREATE-A-TEAM's: big letters or a box over a grid of
## characters) and [MwKeyboardScreen] (123, the password screen's, for the
## online fields). What they share is here:
##
## * **Typing:** the field is edited from entering ([method
##   MwTextField.begin]), so the keyboard is the field's - the keys bound
##   to verbs drive none ([MwKeyGate]) - and [method key] hands it each
##   key: characters type at its cursor, Enter keeps the text, Esc (or
##   another key bound to Menu Back that types nothing here) drops it,
##   Backspace, Delete, the arrows, Home and End edit and move inside it,
##   Ctrl+V and Shift+Insert paste. Alt+Enter stays the window's.
## * **The keys:** the field's pages ([method MwTextField.keyboard_pages])
##   cut to what the look holds ([method _page_size] keys in [method
##   _columns]), and the words under them ([method words]: the next page,
##   SPACE, DELETE, PASTE, DONE - those the look offers and the field
##   takes). The cursor moves over both: within a row it wraps, up from the
##   top row and down from the bottom one it goes to the words, and back.
## * **The pads:** the password screen's verbs ([constant
##   MwVerbs.Context.PASSWORD], any local player): PICK LETTER types the
##   key under the cursor or does its word, ERASE LETTER takes back the
##   character before the text's cursor, CANCEL and Menu Back drop the
##   text, DONE keeps it, the directions move the cursor; CURSOR LEFT /
##   RIGHT ([constant MwVerbs.Context.TEXT_ENTRY]: the triggers) move the
##   text's cursor (owner, 2026-10-12). Held, the directions, the text's
##   cursor, ERASE LETTER and PICK LETTER on DELETE repeat ([MwHoldRepeat]:
##   owner, 2026-10-12, the erasing ones too; the keyboard's keys repeat as
##   the system repeats them).
## * **The result:** the field itself, edited in place (as it was when
##   dropped), and in the session's screens[screen_id] {key (the field's
##   [member MwTextField.id]), text, done}; then the screen pops.

## The words under the keys ([method words]).
const WORD_PAGE := "page"
const WORD_SPACE := "space"
const WORD_DELETE := "delete"
const WORD_PASTE := "paste"
const WORD_DONE := "done"

var rom: PackedByteArray
var field: MwTextField
## The keys' pages: [name, keys], each at most [method _page_size] keys.
var pages: Array = []
var page := 0
## Under the cursor: a key (0 to [method _page_size] - 1), or a word (from
## [method _page_size] on, in [method words]' order).
var cursor := 0
## Why the last paste was refused ("" none).
var note := ""
var _done := false
## Held verbs repeating ([MwHoldRepeat]): the directions on the keys, the
## text's cursor, ERASE LETTER, PICK LETTER (on DELETE).
var _rep_x := MwHoldRepeat.new()
var _rep_y := MwHoldRepeat.new("ui_up", "ui_down")
var _rep_text := MwHoldRepeat.new("ui_text_left", "ui_text_right")
var _rep_erase := MwHoldRepeat.new("", "ui_erase_letter")
var _rep_pick := MwHoldRepeat.new("", "ui_pick_letter")


func _enter_screen(data: Dictionary) -> void:
	if not MwRom.available():
		return
	rom = MwRom.data()
	field = data.get("field") as MwTextField
	if field == null:
		field = MwTextField.new()
	pages = cut_pages(field.keyboard_pages(), _page_size())
	_set_up(data)
	field.begin()                            # the keyboard is the field's
	_redraw()


## [param from]'s pages cut into pages of [param size] keys at most (a
## page cut off another is named by its first keys).
static func cut_pages(from: Array, size: int) -> Array:
	var out := []
	for source_page: Array in from:
		var page_keys := str(source_page[1])
		var i := 0
		while i < page_keys.length():
			var part := page_keys.substr(i, size)
			out.append([str(source_page[0]) if i == 0 else part.left(3), part])
			i += size
	return out


## The keys of the page shown.
func keys() -> String:
	return str(pages[page][1]) if not pages.is_empty() else ""


## The words under the keys, in order: those of [method _offered] that do
## something here (the next page when there are pages, SPACE when the field
## takes spaces, PASTE when it takes pastes).
func words() -> Array:
	var out := []
	for w: String in _offered():
		if (w == WORD_PAGE and pages.size() < 2) or (w == WORD_SPACE and not field.spaces) \
				or (w == WORD_PASTE and not field.paste_ok):
			continue
		out.append(w)
	return out


## The words as the look reads them (the next page's word: that page's name).
func word_labels() -> Array:
	var out := []
	for w: String in words():
		out.append(str(pages[(page + 1) % pages.size()][0]) if w == WORD_PAGE else _label(w))
	return out


# --- passes -----------------------------------------------------------------------------------------

func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty() or _done:
		return
	_look_pass(elapsed)
	if input == null:
		return
	if input.is_pressed("ui_cancel") or input.is_pressed("ui_back"):
		close(false)
		return
	elif input.is_pressed("ui_password_done"):
		close(true)
		return
	elif input.is_pressed("ui_pick_letter"):
		pick()
	elif input.is_pressed("ui_erase_letter"):
		erase()
	elif input.is_pressed("ui_left"):
		move(-1, 0)
	elif input.is_pressed("ui_right"):
		move(1, 0)
	elif input.is_pressed("ui_up"):
		move(0, -1)
	elif input.is_pressed("ui_down"):
		move(0, 1)
	elif input.is_pressed("ui_text_left"):
		cursor_by(-1)
	elif input.is_pressed("ui_text_right"):
		cursor_by(1)
	if not _done:
		_repeats(input, elapsed)


## The held verbs' repeats this pass (the press made the first step).
func _repeats(input: MwInputFrame, elapsed: int) -> void:
	var n := _rep_x.step(input, elapsed, true)
	for i in absi(n):
		move(signi(n), 0, i == 0 and _rep_x.sound_due())
	n = _rep_y.step(input, elapsed, true)
	for i in absi(n):
		move(0, signi(n), i == 0 and _rep_y.sound_due())
	n = _rep_text.step(input, elapsed, true)
	if n != 0:
		cursor_by(n, _rep_text.sound_due())
	n = _rep_erase.step(input, elapsed, true)
	n += _rep_pick.step(input, elapsed, _on_word(WORD_DELETE))
	if n > 0:
		erase(n, _rep_erase.sound_due() and _rep_pick.sound_due())


## True while the cursor is on word [param w] (under the keys).
func _on_word(w: String) -> bool:
	var i := cursor - _page_size()
	var ws := words()
	return i >= 0 and i < ws.size() and str(ws[i]) == w


## The keyboard's keys go to the field (and nowhere else) while it types.
func _input(event: InputEvent) -> void:
	if _done or field == null or not field.editing or not visible:
		return
	if not event is InputEventKey or not event.is_pressed() or MwSettings.is_display_toggle(event):
		return
	get_viewport().set_input_as_handled()
	key(event as InputEventKey)


## One key while typing (the keyboard's events; tests call it).
func key(event: InputEventKey) -> void:
	if _done or not field.editing:
		return
	var r := field.key(event)
	match r:
		MwTextField.Result.CONFIRMED:
			close(true)
		MwTextField.Result.CANCELLED:
			close(false)
		MwTextField.Result.EDITED, MwTextField.Result.PASTED:
			_typed()
		MwTextField.Result.MOVED:
			_sound("move")
			_redraw_text()
		_:
			if not event.echo and event.is_action("ui_back"):
				close(false)                 # Menu Back bound to a key that types nothing here
			elif r == MwTextField.Result.REFUSED:
				_refused(field.message)


## PICK LETTER: the key under the cursor typed, or its word done.
func pick() -> void:
	var size := _page_size()
	if cursor < size:
		if cursor < keys().length() and field.type_char(keys().unicode_at(cursor)):
			_typed()
		else:
			_refused("")                     # the field is full (or takes no such character)
		return
	match str(words()[cursor - size]):
		WORD_PAGE:
			page = (page + 1) % pages.size()
			_sound("move")
			_redraw()
		WORD_SPACE:
			if field.type_char(0x20):
				_typed()
			else:
				_refused("")
		WORD_DELETE:
			erase()
		WORD_PASTE:
			if field.paste():
				_typed()
			else:
				_refused(field.message)
		WORD_DONE:
			close(true)


## ERASE LETTER: the character before the text's cursor taken back
## ([param times] of them: a held ERASE's repeats, its sound when
## [param sound]).
func erase(times := 1, sound := true) -> void:
	var any := false
	for i in times:
		any = field.erase() or any
	if any:
		_typed(sound)


## CURSOR LEFT / RIGHT: the text's cursor [param d] characters along (within
## the text), its sound when [param sound].
func cursor_by(d: int, sound := true) -> void:
	var to := clampi(field.cursor + d, 0, field.text.length())
	if to == field.cursor:
		return
	field.cursor = to
	if sound:
		_sound("move")
	_redraw_text()


## The cursor moves over the keys and the words (the password screen's
## wrap-around within a row; up from the top row and down from the bottom
## one go to the words, and back to the column above or below).
func move(dx: int, dy: int, sound := true) -> void:
	var n := keys().length()
	var cols := _columns()
	var size := _page_size()
	@warning_ignore("integer_division")
	var rows := (n + cols - 1) / cols
	var nw := words().size()
	if cursor < size and n > 0:
		@warning_ignore("integer_division")
		var r := cursor / cols
		var c := cursor % cols
		if dx != 0:
			cursor = r * cols + posmod(c + dx, mini(cols, n - r * cols))
		else:
			var to := r + dy
			if to < 0 or to >= rows:
				@warning_ignore("integer_division")
				cursor = size + mini(c * nw / cols, nw - 1)
			else:
				cursor = to * cols + mini(c, n - to * cols - 1)
	elif nw > 0:
		var w := clampi(cursor - size, 0, nw - 1)
		if dx != 0 or n == 0:
			cursor = size + posmod(w + dx, nw)
		else:
			@warning_ignore("integer_division")
			var c := (2 * w + 1) * cols / (2 * nw)
			var to := rows - 1 if dy < 0 else 0
			cursor = to * cols + mini(c, n - to * cols - 1)
	if sound:
		_sound("move")
	_redraw()


## Done (the text kept) or dropped: the result, back to the screen that asked.
func close(keep: bool) -> void:
	if _done:
		return
	_done = true
	if field.editing:
		field.finish(keep)
	_sound("done" if keep else "cancel")
	_closing()
	_close_with({"key": field.id, "text": field.text, "done": keep})     # (plan 40: the screen under's result)


## Left without an answer (the game left the screen): the text dropped,
## the keyboard given back.
func _exit_tree() -> void:
	if field != null and field.editing:
		field.finish(false)


func _typed(sound := true) -> void:
	note = ""
	if sound:
		_sound("key")
	_redraw_text()


func _refused(why: String) -> void:
	note = why
	_sound("refused")
	_redraw_text()


# --- the look's part --------------------------------------------------------------------------------

## Keys a page holds.
func _page_size() -> int:
	return 28


## Keys a row.
func _columns() -> int:
	return 7


## The words it offers, in order ([method words] keeps those that apply).
func _offered() -> Array:
	return [WORD_PAGE, WORD_SPACE, WORD_DELETE, WORD_PASTE, WORD_DONE]


## Word [param w] as it reads (not the next page's).
func _label(w: String) -> String:
	return w.to_upper()


## Its nodes and layers, before the first drawing ([param data]: the asker's).
func _set_up(_data: Dictionary) -> void:
	pass


## Back to the screen under with [param result] (its [method
## MwScreen._resume_screen]'s): popped (a screen of its own may cut).
func _close_with(result: Dictionary) -> void:
	pop(result)


## Every pass, first (its starfield, a blink).
func _look_pass(_elapsed: int) -> void:
	pass


## Plan 40 (M7): the text cursor's blink, both looks' - [constant
## BLINK_TICKS] on, as many off; typing shows it ([member _blink] back to 0
## in a look's _redraw_text).
const BLINK_TICKS := 16
var _blink := 0


## The blink [param elapsed] ticks on; the cursor drawn again when it turned.
func blink_step(elapsed: int) -> void:
	var was := _blink_on()
	_blink += elapsed
	if _blink_on() != was:
		_draw_cursor()


func _blink_on() -> bool:
	@warning_ignore("integer_division")
	return (_blink / BLINK_TICKS) % 2 == 0


## The text cursor drawn (or not: the blink, done).
func _draw_cursor() -> void:
	pass


## Everything drawn again.
func _redraw() -> void:
	pass


## The text (and the note) drawn again.
func _redraw_text() -> void:
	_redraw()


## Sound [param what]: "key", "move", "refused", "done" or "cancel".
func _sound(_what: String) -> void:
	pass


## Just before it pops.
func _closing() -> void:
	pass
