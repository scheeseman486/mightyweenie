class_name MwTextEntry
extends MwTextInputScreen
## CREATE-A-TEAM's text entry (plan 38, screen 131): its text input screen
## ([MwTextInputScreen]: the keyboard types and the pads pick, both at
## once), pushed over the screen that asks for any name or text of a custom
## team with the field to edit ([method MwCreateTeam.team_text]; the rink
## editor's rink name too). Its look: the field's title on the plate, the
## text in big letters (a short one) or in a box (a long one) with the
## port's blinking cursor under where the next character goes (the online
## fields' underline, MwGlyphs.field_cursor), its length, the field's gentle note
## tinted (the team name's: names should end in S, Z or 5 - owner: a note,
## never a stop) or a refused paste's reason in red, the grid of the
## field's keys (a team text: the characters every font the game draws
## names in has, [constant MwCustomTeam.CHARSET]'s capitals and signs,
## 12 a row), SPACE / DELETE / DONE under it, the prompts. The verbs are
## the password entry's (PICK LETTER, ERASE, CANCEL, DONE;
## [constant MwVerbs.Context.PASSWORD]). The editor's music goes on under
## it ([method MwEditorMusic.keep_up]).
##
## The text shows as the game will hold it (owner, 2026-10-11: the boxes
## confined to the limits; the title clear of them):
## * a short one (up to [constant BIG_LIMIT]) in big letters;
## * a longer one in a one-line box as wide as its limit;
## * a text the team description shows in a box (the bio, the coach's
##   quote: [member MwTextField.lines] and [member MwTextField.width]) word-
##   wrapped as that box wraps it, the field taking no more than its lines
##   ([member MwTextField.fits]), in a window of [constant LINES_SHOWN]
##   lines that follows the cursor and scrolls (TEXT UP / DOWN: Page Up /
##   Down, the right stick; [constant MwVerbs.Context.TEXT_ENTRY]), marks
##   beside it where lines are out of sight; the keyboard's Up / Down move
##   the text's cursor a line up or down, to the place in it nearest the
##   one it was at (owner, 2026-10-12; [method line_move]).
## An empty text may show an example ([member MwTextField.example]),
## dimmed: gone once anything is typed (owner).
##
## Data in: the field ("field"). Out: the field, and in the session's
## screens[131] {key, text, done} (done false: cancelled).

const GRID_X := 3
const GRID_Y := 13
const COLUMNS := 12
const ROWS := 4
const ITEMS_Y := 22
const BIG_LIMIT := 10                ## texts this long or shorter: big letters
## Rows: the title (a short or one-line text's, a wrapped text's), a
## one-line box's text, the length's, the wrapped box's first line and its
## lines' count; the wrapped box's window.
const TITLE_Y := MwPortMenu.BINDINGS_TITLE_Y
const WRAP_TITLE_Y := 1
const LINE_Y := 6
const COUNT_Y := 9
const WRAP_Y := 4
const WRAP_COUNT_Y := 11
const LINES_SHOWN := 5
const NOTE_TINT := Color(1.0, 0.82, 0.45)
const EXAMPLE_TINT := MwUiInk.DIM
const RED := MwUiInk.RED
const SOUND_KEY := MwSoundIds.KEY
const SOUND_MOVE := MwSoundIds.MOVE
## The big letters' advance and a space's (MwSpriteText.fixed's).
const BIG_ADVANCE := 0x18
const BIG_SPACE := 8
const LIGHT := MwEditorDraw.LIGHT
const DARK := MwEditorDraw.DARK
const MENU := MwEditorDraw.MENU

## The page's own layers, as one picture (the cuts' fades, [MwMenuCut]).
@onready var page_layers: CanvasGroup = $Page
@onready var plane: RomPlane = $Page/Plane
@onready var starfield: RomStarfield = $Starfield
@onready var palette: RomPalette = $Page/Plane.palette
@onready var typed: RomPieces = $Page/Typed
## Plan 40 (M5): pushed by a cut (from CREATE-A-TEAM: the stars going on),
## it is popped by one too; from the rink editor (no starfield) both fade.
var cut: MwMenuCut
var _by_cut := false

var _plate: RomPlane
var _half: RomPlane
var _under: RomPlane                 # the boxes' black, under the letters
var _dim: RomPlane                   # an example, dimmed
var _marks: Node2D                   # the wrapped box's arrows (lines out of sight)
var _soft: RomPlane
var _red: RomPlane
var _cursor_layer: RomPlane
var _cursor_cells := Rect2i()      # where the text's cursor goes: its cells (a row of them)
var _cursor_font := LIGHT
var _big_ink := Rect2i()           # a big letter's ink (its "M"), from its origin
## The wrapped box's first line shown, and whether it follows the cursor
## (typing and moving it do; a scroll leaves it where it was put).
var top := 0
var _follow := true
## The prompts were drawn for a gamepad (its CURSOR LEFT / RIGHT on the
## triggers), not the keyboard: drawn again when that changes.
var _pad_prompts := false


## The coach's quote's example for [param team] (port text; the editor's
## coach page shows it too while he has none).
static func coach_quote_example(team: MwCustomTeam) -> String:
	return ("WIN OR LOSE, MY BOYS LEAVE SOMETHING ON THE ICE. USUALLY TEETH. "
			+ "ANYONE WHO WANTS TO BEAT THE %s HAD BETTER BRING SPARE PARTS.") % team.name.to_upper()


## The bio's example for [param team] (port text).
static func bio_example(team: MwCustomTeam) -> String:
	return ("NOBODY KNOWS WHERE THE %s CAME FROM, BUT %s HASN'T BEEN THE SAME SINCE. "
			+ "THEY PLAY DIRTY, HIT HARD AND NEVER SAY SORRY. THEIR FANS BRING THEIR OWN STRETCHERS.") % [
			team.name.to_upper(), team.city.to_upper()]


func _set_up(data: Dictionary) -> void:
	if session:
		starfield.start(session.rng_aux)
		palette.team_a = session.setup.team_a
	cut = MwMenuCut.new(page_layers, starfield, session)
	_by_cut = bool(data.get("menu_cut", false)) and session != null
	if _by_cut:
		cut.restore_stars()                    # the stars of the screen under going on
	cut.enter(_by_cut, data, false)
	_under = plane.duplicate() as RomPlane
	_under.name = "Under"
	page_layers.add_child(_under)
	page_layers.move_child(_under, plane.get_index())
	_plate = plane.duplicate() as RomPlane
	_plate.palette = MwGlyphs.plate_palette(palette)
	page_layers.add_child(_plate)
	_half = plane.duplicate() as RomPlane       # plan 40 (M1): items centred to the half cell
	_half.name = "Half"
	_half.position = plane.position + Vector2(4, 0)
	page_layers.add_child(_half)
	_dim = plane.duplicate() as RomPlane
	_dim.name = "Example"
	_dim.modulate = EXAMPLE_TINT
	page_layers.add_child(_dim)
	_marks = Node2D.new()
	_marks.name = "Marks"
	page_layers.add_child(_marks)
	_soft = plane.duplicate() as RomPlane       # the gentle note, tinted (owner: a note, not a stop)
	_soft.modulate = NOTE_TINT
	page_layers.add_child(_soft)
	_red = plane.duplicate() as RomPlane        # a refused paste's reason
	_red.modulate = RED
	page_layers.add_child(_red)
	_cursor_layer = plane.duplicate() as RomPlane
	_cursor_layer.name = "Cursor"
	page_layers.add_child(_cursor_layer)


func _page_size() -> int:
	return COLUMNS * ROWS


func _columns() -> int:
	return COLUMNS


func _offered() -> Array:
	return [WORD_PAGE, WORD_SPACE, WORD_DELETE, WORD_DONE]


func _look_pass(elapsed: int) -> void:
	for i in elapsed:
		starfield.step()
	blink_step(elapsed)                      # plan 40 (M7): MwTextInputScreen's
	MwEditorMusic.keep_up()
	if (MwGlyphs.last_device >= 0) != _pad_prompts and not _done:
		_redraw()                            # the prompts for the device used now


func _redraw_text() -> void:
	_blink = 0                               # typing shows the cursor
	_follow = true                           # and the window goes where it is
	_redraw()


## The wrapped box's window scrolls with TEXT UP / DOWN (the pads': the
## right stick); the keyboard's Page Up / Down come through [method key].
func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if cut != null and cut.step(elapsed):
		return                                   # popping by a cut: the page fading out, the stars on
	if input != null and field != null and field.lines > 0 and not _done:
		if input.is_pressed("ui_text_up"):
			_scroll(-1)
		elif input.is_pressed("ui_text_down"):
			_scroll(1)
	super._screen_pass(elapsed, input)


## Page Up / Down scroll the wrapped box, Up / Down move the text's cursor
## a line (the field takes the other keys).
func key(event: InputEventKey) -> void:
	var code := event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	if field != null and field.lines > 0 and event.pressed and code in [KEY_PAGEUP, KEY_PAGEDOWN]:
		_scroll(-1 if code == KEY_PAGEUP else 1)
		return
	if field != null and field.lines > 0 and field.editing and event.pressed and not event.alt_pressed \
			and code in [KEY_UP, KEY_DOWN]:
		if line_move(-1 if code == KEY_UP else 1):
			_sound("move")
			_redraw_text()
		return
	super.key(event)


## The text's cursor [param d] lines up (-1) or down (+1) in the wrapped
## box, to the place on that line nearest (in cells) the one it is at; up
## from the first line to the text's start, down from the last to its end.
## False when it stays where it is.
func line_move(d: int) -> bool:
	var lines := _wrapped()
	var starts: Array[int] = []
	var at := 0
	for l in lines:
		starts.append(at)
		at += l.size()
	var line := lines.size() - 1
	for i in lines.size():
		if field.cursor < starts[i] + lines[i].size() or i == lines.size() - 1:
			line = i
			break
	var was := field.cursor
	var to := line + d
	if lines.is_empty() or to < 0:
		field.cursor = 0
	elif to >= lines.size():
		field.cursor = field.text.length()
	else:
		var x := MwGfx.text_width(rom, LIGHT, lines[line].slice(0, field.cursor - starts[line]))
		# a line holds the spaces after its last word too: its last place is
		# the next line's first, but on the last line the text's end
		var last := lines[to].size() - (1 if to < lines.size() - 1 else 0)
		var best := 0
		var best_d := 1 << 30
		for j in range(0, maxi(last, 0) + 1):
			var dd := absi(MwGfx.text_width(rom, LIGHT, lines[to].slice(0, j)) - x)
			if dd < best_d:
				best = j
				best_d = dd
		field.cursor = starts[to] + best
	return field.cursor != was


## The wrapped box's window [param d] lines up or down.
func _scroll(d: int) -> void:
	var t := clampi(top + d, 0, maxi(_wrapped().size() - LINES_SHOWN, 0))
	if t == top:
		return
	top = t
	_follow = false
	_sound("move")
	_redraw()


## The field's text wrapped as its box wraps it.
func _wrapped() -> Array[PackedByteArray]:
	return MwEditorDraw.wrap(rom, LIGHT, MwEditorDraw.ascii(field.shown()), field.width)


## Back to the screen under: by a cut when pushed by one (plan 40, M5).
func _close_with(result: Dictionary) -> void:
	if _by_cut and cut != null:
		cut.leave(func(c: Dictionary) -> void: pop(result.merged(c), false))
	else:
		pop(result)


func _closing() -> void:
	_cursor_layer.clear()


func _sound(what: String) -> void:
	match what:
		"key":
			MwSound.play(SOUND_KEY)
		"refused":
			MwSound.play(MwCreateTeam.SOUND_REFUSED)
		_:
			MwSound.play(SOUND_MOVE)


func _redraw() -> void:
	plane.clear()
	_half.clear()
	_plate.clear()
	_under.clear()
	_dim.clear()
	for c in _marks.get_children():
		c.queue_free()
	MwGlyphs.plate_title(_plate, rom, LIGHT, MwEditorDraw.ascii(field.title),
			WRAP_TITLE_Y if field.lines > 0 else TITLE_Y,
			MENU)
	var shown := field.shown()
	var note_y := 11
	if field.lines > 0:
		typed.visible = false
		_draw_wrapped()
		note_y = 12
	elif field.limit <= BIG_LIMIT:
		var t: Array = MwSpriteText.fixed(rom, MwEditorDraw.BIG, MwEditorDraw.ascii(shown), 0x40,
				BIG_ADVANCE, BIG_SPACE)
		typed.set_pieces(t[0])
		typed.position = Vector2(int((320 - int(t[1]) - BIG_ADVANCE) / 2.0), 48)   # and the cursor's slot
		typed.visible = true
		_place_big_cursor(shown)
		MwEditorDraw.centred(plane, _half, rom, LIGHT, "%d OF %d" % [field.text.length(), field.limit], 9, MENU)
	else:
		# one line, as wide as its limit (and the cursor's cell)
		typed.visible = false
		@warning_ignore("integer_division")
		var x := 20 - (field.limit + 1) / 2
		_box(x, LINE_Y, field.limit + 1, 1)
		if field.text == "" and field.example != "":
			MwEditorDraw.text(_dim, rom, LIGHT, field.example.left(field.limit), x, LINE_Y, MENU)
		var box := MwTextBox.new(plane, LIGHT, Rect2i(x, LINE_Y, field.limit + 1, 1))
		box.write(rom, MwEditorDraw.ascii(shown), MENU, field.cursor)
		_cursor_layer.position = Vector2.ZERO
		_cursor_font = LIGHT
		_cursor_cells = Rect2i(box.mark, Vector2i(1, 1))
		MwEditorDraw.centred(plane, _half, rom, LIGHT, "%d OF %d" % [field.text.length(), field.limit], COUNT_Y, MENU)
	_soft.clear()
	_red.clear()
	var y := note_y
	if note != "":
		MwEditorDraw.centred(_red, null, rom, LIGHT, note, y, MENU)
	elif field.note() != "":
		MwEditorDraw.centred(_soft, null, rom, LIGHT, field.note(), y, MENU)
	var text := keys()
	for i in text.length():
		var sel := cursor == i
		var x := GRID_X + 3 * (i % COLUMNS)
		@warning_ignore("integer_division")
		var gy := GRID_Y + 2 * (i / COLUMNS)
		if sel:
			MwPlanePainter.frame(plane, rom, x, gy, 1, 1, true)
		MwEditorDraw.text(plane, rom, DARK if sel else LIGHT, text[i], x, gy, MENU)
	var labels := word_labels()
	var n := labels.size()
	@warning_ignore("integer_division")
	var w := mini(10, (38 - 2 * (n - 1)) / maxi(n, 1))
	@warning_ignore("integer_division")
	var x0 := (40 - (n * w + 2 * (n - 1))) / 2
	for i in n:
		MwEditorDraw.item(plane, _half, rom, labels[i], x0 + (w + 2) * i, ITEMS_Y, w, cursor == _page_size() + i, MENU)
	var parts := [["ui_pick_letter", "ADD"], ["ui_erase_letter", "DELETE"], ["ui_cancel", "CANCEL"]]
	if field.lines > 0 and _wrapped().size() > LINES_SHOWN:
		parts.append(["ui_text_down", "SCROLL"])
	MwPrompts.verbs(plane, rom, parts, 25, MENU)
	# a gamepad: its triggers move the text's cursor (owner, 2026-10-12);
	# the keyboard: it types, its arrows move it
	_pad_prompts = MwGlyphs.last_device >= 0
	if _pad_prompts and not MwGlyphs.verb_cells("ui_text_left").is_empty():
		MwPrompts.verbs(plane, rom, [["ui_password_done", "DONE"], ["ui_text_left", "CURSOR", "ui_text_right"]],
				27, MENU)
	else:
		MwPrompts.verbs(plane, rom, [["ui_password_done", "DONE   OR TYPE ON THE KEYBOARD"]], 27, MENU)
	_draw_cursor()


## The wrapped text's box: the field's width, a window of [constant
## LINES_SHOWN] lines from [member top] (following the cursor's line while
## [member _follow]), the cursor in its cell, marks where lines are out of
## sight, the lines used of the most; an example dimmed while empty.
func _draw_wrapped() -> void:
	var w := field.width
	@warning_ignore("integer_division")
	var x := 20 - w / 2
	_box(x, WRAP_Y, w, LINES_SHOWN)
	var lines := _wrapped()
	# the cursor's line and its place in it (a line holds its text's
	# characters in order, the spaces after its last word too)
	var at := 0
	var line := lines.size() - 1
	var rel := field.cursor
	for i in lines.size():
		if field.cursor < at + lines[i].size() or i == lines.size() - 1:
			line = i
			rel = field.cursor - at
			break
		at += lines[i].size()
	if _follow:
		top = MwScrollArrows.follow(top, line, LINES_SHOWN)       # plan 40 (M3)
	top = clampi(top, 0, maxi(lines.size() - LINES_SHOWN, 0))
	_cursor_layer.position = Vector2.ZERO
	_cursor_font = LIGHT
	_cursor_cells = Rect2i(-1, -1, 1, 1)
	if field.text == "" and field.example != "":
		var ex := MwEditorDraw.wrap(rom, LIGHT, MwEditorDraw.ascii(field.example), w)
		MwEditorDraw.lines(_dim, rom, LIGHT, ex, 0, LINES_SHOWN, x, WRAP_Y, w, MENU)
	for k in LINES_SHOWN:
		var i := top + k
		if i >= lines.size():
			break
		var box := MwTextBox.new(plane, LIGHT, Rect2i(x, WRAP_Y + k, w + 1, 1))
		box.write(rom, lines[i], MENU, rel if i == line else -1)
		if i == line:
			_cursor_cells = Rect2i(box.mark, Vector2i(1, 1))
	_arrow(x + w + 1, WRAP_Y, true, top > 0)
	_arrow(x + w + 1, WRAP_Y + LINES_SHOWN - 1, false, top + LINES_SHOWN < lines.size())
	var used := 0 if field.text == "" else lines.size()
	MwEditorDraw.centred(plane, _half, rom, LIGHT, "%d OF %d LINES" % [used, field.lines], WRAP_COUNT_Y, MENU)


## A box: black inside (under the letters), the menus' white frame round it.
func _box(x: int, y: int, w: int, h: int) -> void:
	MwGlyphs.black_frame(_under, rom, x, y, w, h)
	MwPlanePainter.frame(plane, rom, x, y, w, h, false)


## A small arrow in cell ([param x], [param y]) beside the box, up or down,
## when [param on]: more lines that way.
func _arrow(x: int, y: int, up: bool, on: bool) -> void:
	if not on:
		return
	for i in 3:
		var r := ColorRect.new()
		r.color = Color.WHITE
		r.size = Vector2(1 + 2 * i, 1)
		r.position = Vector2(8 * x + 3 - i, 8 * y + 2 + (i if up else 2 - i))
		_marks.add_child(r)


## The big letters' cursor: under the slot the next character takes, a
## letter's width of the port's underline cells along the letters' foot
## (their shadow's rows: a letter's, its "M", measured once), clear of the
## length's line under them.
func _place_big_cursor(shown: String) -> void:
	var x := 0
	for i in field.cursor:
		x += BIG_SPACE if shown[i] == " " else BIG_ADVANCE
	if _big_ink.size.x == 0:
		var m: Array = MwSpriteText.fixed(rom, MwEditorDraw.BIG, MwEditorDraw.ascii("M"), 0x40)
		var img := MwGfx.frame_image(rom, m[0])
		var w: int = img["w"]
		var px: PackedByteArray = img["px"]
		var lo := Vector2i(w, px.size())
		var hi := Vector2i(-1, -1)
		for i in px.size():
			if px[i] != 0:
				@warning_ignore("integer_division")
				var at := Vector2i(i % w, i / w)
				lo = lo.min(at)
				hi = hi.max(at)
		var origin := Vector2i(int(img["ox"]), int(img["oy"]))
		_big_ink = Rect2i(lo - origin, hi - lo + Vector2i.ONE)
	_cursor_font = LIGHT
	@warning_ignore("integer_division")
	_cursor_cells = Rect2i(0, 0, maxi((_big_ink.size.x + 4) / 8, 1), 1)
	# the underline is the cells' bottom row
	_cursor_layer.position = typed.position + Vector2(x + _big_ink.position.x,
			_big_ink.end.y - 2 - 7 - 8 * (MwGfx.s16(rom, LIGHT) - 1))


func _draw_cursor() -> void:
	_cursor_layer.clear()
	if _done or not _blink_on() or _cursor_cells.position.x < 0:
		return
	for i in _cursor_cells.size.x:
		MwGlyphs.field_cursor(_cursor_layer, rom, _cursor_font, _cursor_cells.position.x + i,
				_cursor_cells.position.y, MENU)


