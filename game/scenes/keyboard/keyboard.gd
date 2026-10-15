class_name MwKeyboardScreen
extends MwTextInputScreen
## The on-screen keyboard (screen 123, plan 35 section 2: "Gamepads get 123
## in the password screen's style"): the online pages' text input screen
## ([MwTextInputScreen]: the keyboard types and the pads pick, both at
## once), pushed over HOST GAME / JOIN GAME with the field to edit
## ([MwOnlineMenu]; a [MwTextField] in the data's "field"). The password
## screen's look (MwPasswordScreen): the starfield, the header between its
## decorations (the field's title; a password's is the password screen's
## own), the big font's bars, the 7 x 4 grid of big letters at the
## original's places with the cursor's in yellow, the hints with the
## player's glyphs; here the field's keys in pages of 28 (ABC, 123), and
## the words - the next page, DEL, PASTE, OK - on the bottom line, where
## the password screen's last line asks for Start.
##
## Its verbs are the password screen's (Context.PASSWORD), any local
## player's: A types the key under the cursor (or does the word), B takes
## the last character back, C or Menu Back cancel (the field as it was),
## Start is OK; on the keyboard the field's own keys (MwTextField). The
## text shows above the top bar in the light menu font (a password as
## asterisks) with a blinking cursor where the next character goes,
## scrolled when long. A refused PASTE says why under it (NOT AN ADDRESS
## in red, sound $2E). The big font has no brackets (an IPv6 address
## before its port): they are made from its "L" ([method bracket]: the
## letter and itself upside down within its own height, one over the
## other - "]" mirrored); the pages hold nothing else it lacks.

## Keys a page (the password screen's grid) and its columns.
const KEYS := 28
const COLUMNS := 7
## Rows: the text, a refusal under it, the words.
const TYPED_Y := 5
const NOTE_Y := 6
const WORD_Y := 25
const WORD_GAP := 4
## The text's cells (a long one scrolls).
const TEXT_CELLS := 34
## The words as they read here (the next page's: its name).
const LABELS := {MwTextInputScreen.WORD_DELETE: "DEL", MwTextInputScreen.WORD_PASTE: "PASTE",
		MwTextInputScreen.WORD_DONE: "OK"}
## The brackets the big font lacks, made from its "L" ([method bracket]).
const BRACKETS := [0x5B, 0x5D]
const BRACKET_FROM := 0x4C
## The password screen's constants (its look: MwPasswordScreen).
const P := preload("res://scenes/password/password.gd")
const RED := MwUiInk.RED

@onready var plane: RomPlane = $Window
@onready var palette: RomPalette = $Window.palette
@onready var starfield: RomStarfield = $Starfield
@onready var grid: RomPieces = $Grid

var _brackets: Array[RomPieces] = [] # the bracket keys' sprites
var _text: RomPlane                  # the text and the words
var _red: RomPlane                   # the refusal
var _cursor_layer: RomPlane
var _typed_x := 0                    # the text's cursor cell
var _starfield: Array = []
var _effect := 0


func _ready() -> void:
	fades_in_itself = false


func _set_up(data: Dictionary) -> void:
	_starfield = data.get("starfield", [])
	if _starfield.size() == 4:
		starfield.restore(_starfield)
	elif session:
		starfield.start(session.rng_aux)
	palette.screen = 11                      # the password screen's colours
	if session:
		palette.team_a = session.setup.team_a
		palette.stadium = session.setup.stadium
	palette.steps = P.palette_steps()              # plan 40 (M7): the password screen's
	_text = _layer("Text")
	_red = _layer("Note")
	_red.modulate = RED
	_cursor_layer = _layer("Cursor")
	_draw_page()


func _layer(n: String) -> RomPlane:
	var layer := plane.duplicate() as RomPlane
	layer.name = n
	add_child(layer)
	return layer


func _page_size() -> int:
	return KEYS


func _columns() -> int:
	return COLUMNS


func _offered() -> Array:
	return [WORD_PAGE, WORD_DELETE, WORD_PASTE, WORD_DONE]


func _label(w: String) -> String:
	return LABELS.get(w, w.to_upper())


func _look_pass(elapsed: int) -> void:
	for i in elapsed:
		starfield.step()
	blink_step(elapsed)                      # plan 40 (M7): MwTextInputScreen's


func _redraw() -> void:
	_draw_keys()


func _redraw_text() -> void:
	_blink = 0                               # typing shows the cursor
	_draw_text()


## The sounds: `$12AB2`'s - the last effect stopped, the next started.
func _sound(what: String) -> void:
	match what:
		"key", "done":
			_effect_sound(P.SOUND_KEY)
		"refused":
			_effect_sound(P.SOUND_REFUSED)
		_:
			_effect_sound(P.SOUND_MOVE)


## Back to the page: the starfield where it is.
func _closing() -> void:
	if _starfield.size() == 4:
		_starfield[0] = starfield.x
		_starfield[1] = starfield.y
		_starfield[2] = starfield.vx
		_starfield[3] = starfield.vy
	_cursor_layer.clear()


## `$12AB2`: the last effect stopped, [param id] started.
func _effect_sound(id: int) -> void:
	MwSound.stop(_effect)
	_effect = MwSound.play(id)



# --- drawing ----------------------------------------------------------------------------------------

## The page: the header (the field's title, or the password screen's own
## from the ROM) between the decorations, the bars, the hints.
func _draw_page() -> void:
	plane.wipe()
	if field.title == "":
		MwPlanePainter.text(plane, rom, P.FONT_HEADER, MwGfx.rom_string(rom, P.HEADER_ENTER), 13, 2, P.ATTR_TEXT)
	else:
		var h := field.title.to_ascii_buffer()
		@warning_ignore("integer_division")
		var x := (40 - MwGfx.text_width(rom, P.FONT_HEADER, h)) / 2
		MwPlanePainter.text(plane, rom, P.FONT_HEADER, h, x, 2, P.ATTR_TEXT)
	P.decorations(plane, rom)
	P.hints(plane, rom)


## The grid (the big font's letters at the password screen's places), the
## cursor's in the cursor's colour, then the words and the text.
func _draw_keys() -> void:
	var text := keys()
	var pieces := []
	var made := 0
	for i in mini(text.length(), KEYS):
		var ch := text.unicode_at(i)
		var piece := key_piece(rom, ch if not ch in BRACKETS else BRACKET_FROM)
		if piece.is_empty():
			continue
		var at := Vector2i(MwGfx.s16(rom, P.GRID + 4 * i), MwGfx.s16(rom, P.GRID + 4 * i + 2))
		piece["x"] = int(piece["x"]) + at.x
		piece["y"] = int(piece["y"]) + at.y
		piece["attr"] = int(piece["attr"]) ^ ((P.ATTR_CURSOR if i == cursor else P.ATTR_GRID) & 0x60)
		if ch in BRACKETS:
			if made == _brackets.size():
				var bracket_pieces := RomPieces.new()
				bracket_pieces.name = "Bracket%d" % made
				bracket_pieces.palette = grid.palette
				add_child(bracket_pieces)
				move_child(bracket_pieces, grid.get_index() + 1)
				_brackets.append(bracket_pieces)
			_show(_brackets[made], bracket(rom, piece, ch == 0x5D))
			made += 1
		else:
			pieces.append(piece)
	for k in range(made, _brackets.size()):
		_brackets[k].texture = null
	grid.set_pieces(pieces)
	_draw_text()


## The big font's piece for [param ch] ({} when it has none).
static func key_piece(rom_bytes: PackedByteArray, ch: int) -> Dictionary:
	var g := MwGfx.font_glyph(rom_bytes, P.FONT_BIG, ch)
	return MwGfx.piece(rom_bytes, P.FONT_BIG + 8 + 6 * g) if g >= 0 else {}


## A bracket from the big font's "L" (its [param piece], placed): the
## letter, and over it the letter upside down within the rows it fills -
## the stem shared, a bar at the top and the bottom; [param closing]
## mirrors it within the columns it fills. MwGfx.frame_image's {ox, oy, w,
## h, px}.
static func bracket(rom_bytes: PackedByteArray, piece: Dictionary, closing: bool) -> Dictionary:
	var img := MwGfx.frame_image(rom_bytes, [piece])
	var w: int = img["w"]
	var h: int = img["h"]
	var px: PackedByteArray = img["px"]
	var top := h
	var bottom := -1
	var left := w
	var right := -1
	for y in h:
		for x in w:
			if px[y * w + x] != 0:
				top = mini(top, y)
				bottom = maxi(bottom, y)
				left = mini(left, x)
				right = maxi(right, x)
	if bottom < 0:
		return img
	var out := px.duplicate()
	for y in range(top, bottom + 1):
		for x in w:
			var v := px[(top + bottom - y) * w + x]
			if v != 0:
				out[y * w + x] = v
	if closing:
		var m := out.duplicate()
		for y in h:
			for x in range(left, right + 1):
				m[y * w + x] = out[y * w + left + right - x]
		out = m
	img["px"] = out
	return img


## [param sprite] shows [param img] (MwGfx.frame_image's) where its pieces
## were placed (as RomPieces.set_pieces does).
static func _show(sprite: RomPieces, img: Dictionary) -> void:
	sprite.texture = ImageTexture.create_from_image(Image.create_from_data(img["w"], img["h"], false,
			Image.FORMAT_R8, img["px"]))
	sprite.centered = false
	sprite.offset = Vector2(-int(img["ox"]), -int(img["oy"]))


## The words, the text (a window of it) and the refusal under it.
func _draw_text() -> void:
	_text.clear()
	var ws := word_labels()
	var total := WORD_GAP * (ws.size() - 1)
	for w in ws:
		total += MwGfx.text_width(rom, P.FONT_LIGHT, str(w).to_ascii_buffer())
	@warning_ignore("integer_division")
	var x := (40 - total) / 2
	for i in ws.size():
		var b := str(ws[i]).to_ascii_buffer()
		MwPlanePainter.text(_text, rom, P.FONT_LIGHT, b, x, WORD_Y,
				P.ATTR_CURSOR if cursor == KEYS + i else P.ATTR_TEXT)
		x += MwGfx.text_width(rom, P.FONT_LIGHT, b) + WORD_GAP
	var w := field.window(TEXT_CELLS)
	var t := str(w["text"]).to_ascii_buffer()
	@warning_ignore("integer_division")
	var tx := (40 - MwGlyphs.field_width(rom, P.FONT_LIGHT, t) - 1) / 2
	MwGlyphs.field_text(_text, rom, P.FONT_LIGHT, t, tx, TYPED_Y, P.ATTR_TEXT)
	_typed_x = tx + int(w["cursor"])
	_red.clear()
	if note != "":
		var n := note.to_ascii_buffer()
		@warning_ignore("integer_division")
		var nx := (40 - MwGlyphs.field_width(rom, P.FONT_LIGHT, n)) / 2
		MwGlyphs.field_text(_red, rom, P.FONT_LIGHT, n, nx, NOTE_Y, P.ATTR_TEXT)
	_draw_cursor()


func _draw_cursor() -> void:
	_cursor_layer.clear()
	if _blink_on() and not _done:
		MwGlyphs.field_cursor(_cursor_layer, rom, P.FONT_LIGHT, _typed_x, TYPED_Y, P.ATTR_TEXT)
