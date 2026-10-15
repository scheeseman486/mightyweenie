class_name MwTextField
extends RefCounted
## One text input (the port's): a text, its cursor and its rules. Every
## screen that asks for a text makes one and pushes a text input screen
## with it ([MwTextInputScreen]: the keyboard types, the pads pick from the
## keys on the screen, both at once): the online pages' fields (plan 35:
## HOST GAME's PORT and PASSWORD, JOIN GAME's IP ADDRESS and PASSWORD, on
## the on-screen keyboard 123) and CREATE-A-TEAM's names and texts (plan
## 38, on the text entry 131). Node-free: the screen draws it ([method
## shown], [method window]), hands it the keyboard's events ([method key])
## and the pads' keys ([method type_char], [method erase], [method paste]).
##
## Its options, set before [method set_text] (the kinds, [enum Kind], are
## presets of them):
## * [member allowed]: the characters it takes ("" any printable ASCII);
##   [member spaces]: the space too, between words (none first, none twice);
##   [member upper]: letters typed or pasted go in as capitals (the menu
##   fonts' texts).
## * [member limit]: characters at most. [member masked]: drawn as
##   asterisks (a password).
## * [member paste_ok] and [member check]: pastes taken, and a pasted text's
##   own test beyond the characters and the length ([member refusal] says
##   why one failed).
## * [member pages]: the pads' keys, in pages ([method keyboard_pages]).
## * [member advice]: a gentle note on the text as it is, never a stop (the
##   team name's S / Z / 5, owner).
## * [member fits]: the text's own limit beyond the characters and the
##   length, typing and pasting (CREATE-A-TEAM: a player's words of 10, a
##   wrapped text's lines). [member lines], [member width] and [member
##   example]: how the look shows it - a text wrapped in a box of so many
##   lines and cells, an example (dimmed) while it is empty.
## * [member id] and [member title]: what the text is for (the asker reads
##   it back) and the text input screen's header.
##
## Typing ([method begin] to [method finish]) the keyboard is the field's
## alone: the keys bound to verbs drive none ([MwKeyGate]). Printable
## characters type at the cursor (filtered, capped), Enter confirms, Esc
## cancels (the text as it was), Backspace, Delete, Left, Right, Home and
## End edit and move; Ctrl+V and Shift+Insert paste.
##
## * **Paste sanity** ([method clean_paste]; the OS clipboard,
##   [member clipboard_get]): trimmed, one line, printable ASCII only,
##   capped (an address 253 characters - a host name's limit - plus a port;
##   a password 32; a port 5 digits), only the field's characters, and an
##   address must read as one ([MwNetAddress]: an IPv4 dotted quad, an IPv6
##   address without a zone ID, or a host name, with an optional port), a
##   port as 1-65535. A paste replaces the field's text whole (an address
##   or a password is pasted whole: COPY ADDRESS on the host, then paste
##   here); a refused one leaves the field as it was and says why
##   ([member message]: NOT AN ADDRESS ...; the screen shows it in red with
##   its refusal sound).
## * The password shows as asterisks (the port's "*", MwGlyphs.field_text).
##   Passwords ignore case where they are used (MwNetService): the menu
##   fonts have no lower case and the field shows asterisks, so a case
##   typed by mistake could never be seen.

## Presets: TEXT any text (CREATE-A-TEAM's set its own characters), and the
## online pages' fields.
enum Kind { ADDRESS, PORT, PASSWORD, TEXT }
## What [method key] did with an event.
enum Result { NONE, EDITED, MOVED, CONFIRMED, CANCELLED, REFUSED, PASTED }

## Characters at most, by kind.
const CAPS := {Kind.ADDRESS: MwNetAddress.MAX_TEXT, Kind.PORT: 5, Kind.PASSWORD: 32, Kind.TEXT: 32}
## What a refused paste (or a value that isn't one) says.
const NOT_TEXT := {Kind.ADDRESS: "NOT AN ADDRESS", Kind.PORT: "NOT A PORT", Kind.PASSWORD: "NOT A PASSWORD",
		Kind.TEXT: "CAN'T PASTE THAT"}
const TOO_LONG := "TOO LONG"
const EMPTY_CLIPBOARD := "NOTHING TO PASTE"
## The online fields' headers on the on-screen keyboard (a password's is
## the password screen's own, from the ROM: the title left empty).
const TITLES := {Kind.ADDRESS: "ENTER ADDRESS", Kind.PORT: "ENTER PORT"}
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const DIGITS := "0123456789"
## The pads' keys by kind: [name, keys] pages; each key one the big font
## draws (MwKeyboardScreen.key_piece: its own signs that read as
## themselves, and the brackets it composes). Typed on the keyboard, a
## password takes any printable character.
const PAGES := {
	Kind.ADDRESS: [["ABC", "ABCDEFGHIJKLMNOPQRSTUVWXYZ.-"], ["123", "1234567890.:-[]"]],
	Kind.PORT: [["123", "1234567890"]],
	Kind.PASSWORD: [["ABC", "ABCDEFGHIJKLMNOPQRSTUVWXYZ.-"], ["123", "1234567890!?#%:'"]],
}

## Reads the OS clipboard (tests put their own here).
static var clipboard_get: Callable = func() -> String: return DisplayServer.clipboard_get()
## Writes it (COPY ADDRESS; tests put their own here).
static var clipboard_set: Callable = func(copied: String) -> void: DisplayServer.clipboard_set(copied)

var kind := Kind.TEXT
## What the text is for (the asker's name for it: "port", "name" ...).
var id := ""
## The text input screen's header ("" its own).
var title := ""
## The characters it takes ("" any printable ASCII but the space).
var allowed := ""
## Spaces between words.
var spaces := false
## Letters go in as capitals.
var upper := false
var limit := 32
## Drawn as asterisks.
var masked := false
## Pastes taken.
var paste_ok := true
## A pasted text's own test (beyond characters and length): (String) -> bool.
var check := Callable()
## What a refused paste says.
var refusal := ""
## The pads' keys: [name, keys] pages (empty: from [member allowed]).
var pages: Array = []
## A gentle note on the text: (String) -> String ("" none).
var advice := Callable()
## The text's own limit (typing, pasting): (String) -> bool, true when it fits.
var fits := Callable()
## A text the look wraps in a box: its lines at most (0: one line) and its width (cells).
var lines := 0
var width := 36
## Shown (dimmed) while the text is empty.
var example := ""

var text := ""
## The cursor: the character index it stands before (0 - text length).
var cursor := 0
## Typing goes to the field.
var editing := false
## Why the last paste was refused ("" none).
var message := ""
var _before := ""


## A field of [param field_kind] (its preset) holding [param initial].
func _init(field_kind := Kind.TEXT, initial := "") -> void:
	kind = field_kind
	limit = CAPS[kind]
	refusal = NOT_TEXT[kind]
	title = TITLES.get(kind, "")
	match kind:
		Kind.ADDRESS:
			allowed = LETTERS + LETTERS.to_lower() + DIGITS + ".:-[]"
			check = func(t: String) -> bool: return not MwNetAddress.parse(t).is_empty()
		Kind.PORT:
			allowed = DIGITS
			check = func(t: String) -> bool: return MwNetAddress.port_of(t) != 0
		Kind.PASSWORD:
			masked = true
		Kind.TEXT:
			spaces = true
	pages = PAGES.get(kind, [])
	set_text(initial)


## The field's length limit in characters ([member limit]).
func cap() -> int:
	return limit


## The text set (cut to the limit), the cursor after it.
func set_text(text_: String) -> void:
	text = text_.left(limit)
	cursor = text.length()


## True when [param ch] (a character code) may be typed into this field
## (a letter as it goes in: [method folded]).
func allows(ch: int) -> bool:
	ch = folded(ch)
	if ch == 0x20:
		return spaces
	if ch <= 0x20 or ch >= 0x7F:
		return false
	return allowed == "" or allowed.contains(char(ch))


## [param ch] as it goes in: a capital when [member upper].
func folded(ch: int) -> int:
	return ch - 0x20 if upper and ch >= 0x61 and ch <= 0x7A else ch


## Starts editing (the text kept to go back to on Esc): the keyboard is the
## field's ([MwKeyGate]).
func begin() -> void:
	editing = true
	_before = text
	cursor = text.length()
	message = ""
	MwKeyGate.take(self)


## Stops editing: [param keep] keeps the text (trimmed), else it goes back.
## The keyboard drives verbs again (the keys held now once let go).
func finish(keep: bool) -> void:
	text = text.strip_edges() if keep else _before
	editing = false
	cursor = text.length()
	MwKeyGate.give_back(self)


## One key event while editing: what it did ([enum Result]).
func key(event: InputEventKey) -> int:
	if not editing or not event.pressed:
		return Result.NONE
	var code := event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	var command := event.ctrl_pressed or event.meta_pressed
	if is_paste(event):
		if event.echo:
			return Result.NONE
		return Result.PASTED if paste() else Result.REFUSED
	if event.echo and code in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		return Result.NONE                   # a held Enter or Esc: once
	if event.alt_pressed:
		return Result.NONE                   # Alt+Enter is the window's (MwSettings.is_display_toggle)
	match code:
		KEY_ENTER, KEY_KP_ENTER:
			finish(true)
			return Result.CONFIRMED
		KEY_ESCAPE:
			finish(false)
			return Result.CANCELLED
		KEY_BACKSPACE:
			return Result.EDITED if erase() else Result.NONE
		KEY_DELETE:
			if cursor >= text.length():
				return Result.NONE
			text = text.erase(cursor, 1)
			return Result.EDITED
		KEY_LEFT:
			cursor = maxi(cursor - 1, 0)
			return Result.MOVED
		KEY_RIGHT:
			cursor = mini(cursor + 1, text.length())
			return Result.MOVED
		KEY_HOME:
			cursor = 0
			return Result.MOVED
		KEY_END:
			cursor = text.length()
			return Result.MOVED
	if command or event.unicode <= 0:
		return Result.NONE
	return Result.EDITED if type_char(event.unicode) else Result.REFUSED


## True for a paste key: Ctrl+V (Cmd+V) or Shift+Insert.
static func is_paste(event: InputEventKey) -> bool:
	var code := event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	return ((event.ctrl_pressed or event.meta_pressed) and code == KEY_V) \
			or (event.shift_pressed and code == KEY_INSERT)


## Types character [param ch] at the cursor; false when the field doesn't
## take it (a space first or next to another) or is full.
func type_char(ch: int) -> bool:
	ch = folded(ch)
	if not allows(ch) or text.length() >= limit:
		return false
	if ch == 0x20 and (cursor == 0 or text[cursor - 1] == " " or (cursor < text.length() and text[cursor] == " ")):
		return false
	if fits.is_valid() and not fits.call(text.insert(cursor, char(ch))):
		return false
	text = text.insert(cursor, char(ch))
	cursor += 1
	message = ""
	return true


## Takes back the character before the cursor; false when there is none.
func erase() -> bool:
	if cursor <= 0:
		return false
	text = text.erase(cursor - 1, 1)
	cursor -= 1
	message = ""
	return true


## Pastes the OS clipboard ([method paste_text]).
func paste() -> bool:
	return paste_text(str(clipboard_get.call()))


## Replaces the text with [param pasted] if it passes the sanity checks
## ([method clean_paste]); else the field stays and [member message] says why.
func paste_text(pasted: String) -> bool:
	var r := clean_paste(pasted)
	if not r["ok"]:
		message = r["why"]
		return false
	text = r["text"]
	cursor = text.length()
	message = ""
	return true


## The sanity checks of a paste of [param pasted]: {ok, text, why}.
func clean_paste(pasted: String) -> Dictionary:
	var t := pasted.strip_edges()
	var no := {"ok": false, "text": "", "why": refusal}
	if not paste_ok:
		return no
	if t == "":
		no["why"] = EMPTY_CLIPBOARD
		return no
	if "\n" in t or "\r" in t:
		return no
	var out := ""
	for i in t.length():
		var c := t.unicode_at(i)
		if c < 0x20 or c > 0x7E or not allows(c):
			return no
		if c == 0x20 and out.ends_with(" "):
			return no                         # words one space apart
		out += char(folded(c))
	if out.length() > limit or (fits.is_valid() and not fits.call(out)):
		no["why"] = TOO_LONG
		return no
	if check.is_valid() and not check.call(out):
		return no
	return {"ok": true, "text": out, "why": ""}


## The text as drawn: a password's as asterisks.
func shown() -> String:
	return "*".repeat(text.length()) if masked else text


## The gentle note on the text as it is ("" none).
func note() -> String:
	return str(advice.call(text)) if advice.is_valid() else ""


## What fits [param cells] cells: {text, cursor (the cursor's cell in it,
## -1 when not editing)}. Editing, the window follows the cursor (the text
## scrolls); otherwise a text too long shows its start and "..".
func window(cells: int) -> Dictionary:
	var drawn := shown()
	cells = maxi(cells, 3)
	if not editing:
		return {"text": drawn if drawn.length() <= cells else drawn.left(cells - 2) + "..", "cursor": -1}
	var room := cells - 1                  # the cursor's cell past the end
	var first := clampi(cursor - room, 0, maxi(drawn.length() - room, 0))
	if drawn.length() <= room:
		first = 0
	return {"text": drawn.substr(first, cells), "cursor": cursor - first}


## The pads' keys: [member pages], else one page of [member allowed] (the
## capitals alone when letters go in as capitals), else the password's.
func keyboard_pages() -> Array:
	if not pages.is_empty():
		return pages
	if allowed == "":
		return PAGES[Kind.PASSWORD]
	var keys := ""
	for c in allowed:
		if not (upper and c.unicode_at(0) >= 0x61 and c.unicode_at(0) <= 0x7A):
			keys += c
	return [["ABC", keys]]
