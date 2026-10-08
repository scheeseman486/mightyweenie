class_name MwPasswordScreen
extends MwScreen
## The playoffs' password screen (`$12170`, inside screen 11; docs/re/
## menus.md, Playoffs), pushed over the playoffs: Continue Playoffs asks for
## a password; after a playoff game the new one is shown. 28 symbols in a
## 7 x 4 grid of big sprite letters; A adds the one under the cursor (13 at
## most), B takes the last back, C cancels (back to the main menu), Start
## with 13 symbols tries it - the original refuses bad ones with a sound.
## Taken: the run continues from it (pop: the playoffs show the bracket).
## Pad 1 drives it, pad 2 when pad 1 pressed nothing.

const GRID := 0x1F1C8              ## x, y of each symbol (window = screen pixels)
const HEADER_ENTER := 0x66C83      ## at (13, 2)
const HEADER_SHOW := 0x66C92       ## at (14, 2)
const HINTS := [[0x66C9F, 1, 0x18], [0x66CA8, 0x0E, 0x18], [0x66CB4, 0x1F, 0x18]]
const PRESS_START := [0x66CBD, 9, 0x19]
const BAR := 0x5075A               ## a row of the big font's `<`, `=`, `>`
const BAR_ROWS := [6, 0x15]
const DECO_MAP := 0x49138          ## 9 cells wide; 7 x 2 of it beside the header
const DECO_AT := [Vector2i(3, 2), Vector2i(30, 2)]
const TYPED_AT := Vector2(160, 36)
const FONT_BIG := 0x246FA
const FONT_HEADER := 0x22BEC
const FONT_LIGHT := 0x447F4
const ATTR_TEXT := 0xE0
const ATTR_GRID := 0xA0
const ATTR_CURSOR := 0xC0
## `$12170`: colours 2-3 of lines 1 and 2 (code constants), over 32 ticks.
const COLOURS := [[0x1218A, 18], [0x12196, 19], [0x121A2, 34], [0x121AE, 35]]
const SOUND_CROWD := 0x10
const SOUND_KEY := 0x30
const SOUND_MOVE := 0x25
const SOUND_REFUSED := 0x2E

@onready var plane: RomPlane = $Window
@onready var palette: RomPalette = $Window.palette
@onready var starfield: RomStarfield = $Starfield
@onready var grid: RomPieces = $Grid
@onready var typed: RomPieces = $Typed

var rom: PackedByteArray
var playoffs: MwPlayoffs
var show := false          ## a new password is shown
var cursor := 0            ## -$C(a6)
var buffer := PackedByteArray()   ## `$FFC7B8`
var _crowd := 0           ## -$14(a6): the crowd sequence's handle
var _effect := 0          ## -$18(a6): the last sound effect's (`$12AB2`)
var _done := false
## How the screen was left: 1 a password taken (pop), -1 cancelled (C).
var _result := 0


func _ready() -> void:
	fades_in_itself = false


func _enter_screen(data: Dictionary) -> void:
	if not MwRom.available() or session == null:
		return
	rom = MwRom.data()
	playoffs = session.playoffs
	show = bool(data.get("show", false))
	var sf: Array = data.get("starfield", [])
	if sf.size() == 4:
		starfield.x = int(sf[0])
		starfield.y = int(sf[1])
		starfield.vx = int(sf[2])
		starfield.vy = int(sf[3])
	MwSound.music_fade_out(1)                 # `$12176`
	palette.screen = 11
	palette.team_a = session.setup.team_a
	palette.stadium = session.setup.stadium
	var steps := PackedStringArray(["screen_palette", "black 0"])
	for c in COLOURS:
		steps.append("word %x %d" % [c[0], c[1]])
	palette.steps = steps
	if show:
		var d := playoffs.dead
		buffer = playoffs.make_password(rom, d[0], d[1], session.setup.pads)
	_draw_page()
	_draw_sprites()


## `$122D6`: the page (the original redraws it every pass).
func _draw_page() -> void:
	plane.wipe()
	var header := HEADER_SHOW if show else HEADER_ENTER
	MwPlanePainter.text(plane, rom, FONT_HEADER, MwGfx.rom_string(rom, header), 14 if show else 13, 2, ATTR_TEXT)
	for at in DECO_AT:
		MwPlanePainter.map_rect(plane, rom, DECO_MAP, 9, 7, 2, at.x, at.y)
	for row in BAR_ROWS:
		MwPlanePainter.text(plane, rom, FONT_BIG, MwGfx.rom_string(rom, BAR), 1, row, ATTR_GRID)
	if not show:
		for h in HINTS:
			MwPlanePainter.text(plane, rom, FONT_LIGHT, MwGfx.rom_string(rom, h[0]), h[1], h[2], ATTR_TEXT)
	MwPlanePainter.text(plane, rom, FONT_LIGHT, MwGfx.rom_string(rom, PRESS_START[0]), PRESS_START[1], PRESS_START[2], ATTR_TEXT)


## The typed symbols (centred) and the grid, the cursor's symbol in line 2.
func _draw_sprites() -> void:
	var w := MwGfx.text_width(rom, FONT_BIG, buffer)
	typed.position = Vector2(TYPED_AT.x - 4 * w, TYPED_AT.y)
	typed.set_pieces(MwSpriteText.pieces(rom, FONT_BIG, buffer, ATTR_CURSOR)[0])
	var pieces := []
	for i in 28:
		var at := Vector2i(MwGfx.s16(rom, GRID + 4 * i), MwGfx.s16(rom, GRID + 4 * i + 2))
		var g := MwGfx.font_glyph(rom, FONT_BIG, rom[MwPlayoffs.ALPHABET + i])
		if g < 0:
			continue
		var p := MwGfx.piece(rom, FONT_BIG + 8 + 6 * g)
		p["x"] = int(p["x"]) + at.x
		p["y"] = int(p["y"]) + at.y
		p["attr"] = int(p["attr"]) ^ ((ATTR_CURSOR if i == cursor else ATTR_GRID) & 0x60)
		pieces.append(p)
	grid.set_pieces(pieces)


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty() or _done:
		return
	for i in elapsed:
		starfield.step()
	if not MwSound.busy(_crowd):              # `$121F6`
		_crowd = MwSound.play(SOUND_CROWD)    # `$12202`
	var pads := 0
	if input:
		pads = input.pad_bits(1)
		if pads == 0:
			pads = input.pad_bits(2)
		if input.is_pressed("ui_back") and not show:
			pads = 0x20                       # Menu Back (plan 21): as C, cancel
	if _keys(pads):
		_try()


## `$12454`: one pass of the pads; true when Start finishes the entry.
func _keys(pads: int) -> bool:
	if show:
		return pads & 0x80 != 0
	var old_cursor := cursor
	var old_len := buffer.size()
	if pads & 0x40 and buffer.size() <= 12:
		buffer.append(rom[MwPlayoffs.ALPHABET + cursor])
		_effect_sound(SOUND_KEY)
	elif pads & 0x10:
		if buffer.size() > 0:
			buffer.resize(buffer.size() - 1)
			_effect_sound(SOUND_KEY)
	elif pads & 0x20:
		_done = true
		_result = -1
		MwSound.enter_match(0)                # `$122CA` at once (d0: no music plays)
		exit_to(1)                            # cancelled: the original leaves screen 11
		return false
	var moved := true
	if pads & 0x04:
		cursor += 6 if cursor % 7 == 0 else -1
	elif pads & 0x08:
		cursor += -6 if cursor % 7 == 6 else 1
	elif pads & 0x01:
		cursor += 21 if cursor < 7 else -7
	elif pads & 0x02:
		cursor += -21 if cursor > 20 else 7
	else:
		moved = false
	if moved:
		_effect_sound(SOUND_MOVE)
	if cursor != old_cursor or buffer.size() != old_len:
		_draw_sprites()
	if moved or pads & 0x80 == 0:
		return false
	if buffer.size() == MwPlayoffs.PASSWORD_LEN:
		return true
	_effect_sound(SOUND_REFUSED)
	return false


## `$1266C`: the run continues from the password, or it is refused.
func _try() -> void:
	if not playoffs.enter_password(rom, buffer):
		_effect_sound(SOUND_REFUSED)
		return
	var t := playoffs.teams()
	session.setup.team_a = t.x
	session.setup.team_b = t.y
	playoffs.reseed()
	_done = true
	var st: Dictionary = session.screens.get(11, {})
	st["starfield"] = [starfield.x, starfield.y, starfield.vx, starfield.vy]
	session.screens[11] = st
	_result = 1
	pop()


## `$12AB2`: the last effect stopped, [param id] started.
func _effect_sound(id: int) -> void:
	MwSound.stop(_effect)
	_effect = MwSound.play(id)


## Left after the fade: a password taken - `$122CA` (`$13C04`: the
## crowd's sequence and all else stopped, the driver reset; d0 is what
## `$2598` leaves, unread: no music plays here); cancelled - screen 11's
## `$11C7C` after its fade (the music's 1-tick fade).
func _exit_tree() -> void:
	if _result > 0:
		MwSound.enter_match(0)
	elif _result < 0:
		MwSound.music_fade_out(1)
