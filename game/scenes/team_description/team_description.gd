class_name MwTeamDescription
extends MwScreen
## Screen 2, the team description (`screen_02_team_description` $C75A;
## docs/re/menus.md, Team description). One tall plane (64 x 48 cells) holds
## the pages: the header plate at rows 20-27, the coach's or a player's page
## above it (rows 0-19), the bio or the roster below (rows 28-47). The plane
## scrolls between showing rows 20-47 (vscroll 160) and rows 0-27
## (vscroll 0) with the original's motion object: pages above drop in and
## bounce, pages below rise. Sprites (logo, big letters, portraits) sit on
## the plane and move with it.
##
## Any pad drives the screen. Bio: D-pad switches team, A/B/C the coach.
## Coach: D-pad switches team, A/B/C the roster. Roster: D-pad moves the
## cursor (Up/Down player, Left/Right line), A/B/C the player. Player: D-pad
## the next player, A/B/C back to the roster. Start: back to the bio, and
## from the bio back to the main menu.
##
## Ported routine by routine; strings, tables and positions are read from the
## ROM at run time.

enum Page { BIO, COACH, ROSTER, PLAYER }

const SCROLL_PARAMS := 0x1CE26     ## gravity, restitution, frictions (`motion_params`)
const SCROLL_START := 0x1CE2E      ## the motion's x, y, z at entry
const UPPER := 0xA0                ## vscroll of the bio / roster (plane rows 20-47)
const RISE_SPEED := 0x708          ## upward speed of a rise (1/256 px per tick)
const DROP_SPEED := -200           ## starting speed of a drop ($FF38)
const SETTLED_SPEED := 0x20        ## on the bottom slower than this: arrived
const LANDING_SPEED := 0x3E8       ## the landing sound plays at or below this speed
## The original takes this long to draw a page before it starts moving
## (measured on the original: press -> motion start, ticks); the roster
## coming back from a player redraws the plate and header first (+1).
const DRAW_TICKS := {Page.BIO: 4, Page.COACH: 5, Page.ROSTER: 6, Page.PLAYER: 5}

const PLATE := 0x48738             ## header plate picture (40 x 8 cells)
const PLATE_ROW := 20
const SIDE_ATTRS := 0xC224         ## $20, $40: palette line of the sprites by side
const TEXT_COLOUR := 0xC20C        ## the `move.w #$EE` of `$C1E6`: colour 9 of the text line
const TEXT_LINE := 0x1BD6A         ## the text line's colours

const FONT_BIG := 0x246FA          ## sprite letters (24 px per letter, space 8)
const FONT_HEADING := 0x22BEC
const FONT_LIGHT := MwPlanePainter.FONT_MENU
const FONT_DARK := MwPlanePainter.FONT_SMALL

const HEADINGS := 0x1CE3C          ## "HOME TEAM", "VISITING TEAM" by side
const ROSTER_HEADING := 0x1CE44
const HEADING_X := 0x1CE48         ## word: column of the headings
const NASTY_HEADING := 0x1CE4A
const NASTY_NAMES := 0x1CE4E       ## nasty play names by play ID
const NASTY_X := 0x1CE72           ## word: their column
const CITY_GAP := 0x1CE74          ## " " after the city in a player's quote
const DASH := 0x1CE78              ## " - "
const NO_HEADING := 0x1CE7C
const POSITION_HEADING := 0x1CE80
const LINE_HEADINGS := 0x1CE84     ## "STARTERS" ... by line
const LINE_WORDS := 0x1CE94        ## "STARTING " ... by line (quotes)
const QUOTE_PARTS := 0x1CEA4       ## "I'M ", " AND I PLAY ", " FOR THE "
const VERDICT_VERBS := 0x1CEB0     ## by overall rating (+8 low nibble)
const VERDICT_MIDDLE := 0x1CEDC
const VERDICT_WORDS := 0x1CEE0
const POSITIONS := 0x1CF0C         ## "CENTER" ... "GOALIE" by roster position
const LABELS := [0x1CF24, 0x1CF3C]          ## skater ratings, left / right column
const GOALIE_LABELS := [0x1CF54, 0x1CF68]
## Ratings shown in each column: [record offset, high nibble]; the sixth row
## only for players with an extra rating (+$D high nibble), never goalies.
const RATINGS := [
	[[0x9, false], [0xA, false], [0x8, true], [0xC, true], [0xC, false], [0xE, true]],
	[[0xB, true], [0xB, false], [0xA, true], [0xD, false], [0x9, true], [0xF, true]]]
const RATING_ROW := 8
const LABEL_X := [9, 0x19]
const VALUE_X := [0x15, 0x25]

const BIO_BOX := 0x1CDFE           ## x, y, w, h (cells)
const COACH_BOX := 0x1CE06
const BAR := 0x1CE0E               ## the roster cursor's bar (+2 rows per position)
const BAR_ERASE := 0x1CE1E
const PLAYER_BOX := 0x1CE16
const TEXT_ATTR := 0xE0            ## the boxes' text (line 3)
const PLAIN_ATTR := 0x60

const LOGO_AT := Vector2(0x10, 0xB0)
const CITY_AT := Vector2(0x40, 0xA8)
const NAME_AT := Vector2(0x40, 0xC0)
const NUMBER_AT := Vector2(0x10, 0xB4)
const PLAYER_NAME_X := 0x48
const PLAYER_NAME_SPLIT := 0x1E    ## wider than this (cells): two lines
const COACH_AT := Vector2(0x44, 0x58)
const COACH_TAIL_AT := Vector2(0x7C, 0x49)
const PLAYER_AT := Vector2(0x10, 0x54)
const PLAYER_TAIL_AT := Vector2(0x24, 0x39)
const BADGE_AT := Vector2(0x10, 0x80)
const TAIL := 0x1FB02              ## speech bubble tail (a sprite piece)
const TAIL_ATTR := 0xE0
const BADGE := 0x214CE             ## frame drawn beside players with an extra rating
const PLAYER_PORTRAIT_SIZE := 1
const STAR_QUOTES := 12            ## `$F420` category

const SOUND_CROWD := 0x10
const SOUND_MOVE := 0x25
const SOUND_LAND := 0x15

@onready var plane: RomPlane = $Plane
@onready var starfield: RomStarfield = $Starfield
@onready var palette: RomPalette = $Plane.palette
@onready var sprites: Node2D = $Sprites
@onready var logo: RomSprite = $Sprites/Logo
@onready var city: RomPieces = $Sprites/City
@onready var team_name: RomPieces = $Sprites/Name
@onready var number: RomPieces = $Sprites/Number
@onready var player_names: Array[RomPieces] = [$Sprites/PlayerName1, $Sprites/PlayerName2]
@onready var tail: RomPieces = $Sprites/Tail
@onready var badge: RomSprite = $Sprites/Badge
@onready var portrait: MwPortrait = $Sprites/Portrait

var rom: PackedByteArray
var setup: MwMatchSetup
var page := Page.BIO
var side := 0             ## `$C322`: 0 team A (home), 1 team B (visiting)
var team := 0             ## `$C32C`
var cursor := 0           ## `$C324`: roster position 0-5 (C, LW, RW, LD, RD, G)
var line := 0             ## `$C326`: line 0-3
var bar_moved := false    ## `$C320`: the bar waits to be drawn at the cursor
var motion := MwMotion.new()  ## `$C372`: z = vscroll
var params: MwMotion.Params   ## `$C38A`
var target := 0           ## `$C3B2`
var land_sound := false   ## `$C3BE`
var scrolling := false    ## in a page's move loop
## `$C3B8`: the last page's portrait is drawn while the next page rises.
var hook := false
var box: MwTextBox        ## `$C336`
var vscroll := 0

var _now := 0             ## ticks since entering (the original's tick counter)
var _mark := 0            ## `$C36E`: last motion step / portrait advance
var _open_at := -1        ## tick the requested page opens (-1: none)
var _opening := Page.BIO
var _from_player := false
var _crowd := 0           ## `$C3C0`
var _effect := 0          ## `$C3C4`
var _team_lines := false  ## lines 1-2 are the teams' lines (after a switch)
var _portrait_player := false  ## the portrait is a player's (tail, badge)
var _drawn_roster := []   ## what the roster rows show (redrawn on change)
var _leaving := false


func _ready() -> void:
	fades_in_itself = false


func _enter_screen(_data: Dictionary) -> void:
	if not MwRom.available() or session == null:
		return
	rom = MwRom.data()
	setup = session.setup
	MwSound.music_fade_out(1)                 # `$C768`: the menus' music stops
	hook = false
	starfield.start(session.rng_aux)          # $13480, then held ($134D0)
	starfield.hold()
	plane.wipe()                              # $BB94: plane A cleared
	portrait.set_palette(palette)
	portrait.rng = session.rng
	tail.set_pieces(_xor([MwGfx.piece(rom, TAIL)], TAIL_ATTR))
	badge.frame_addresses = PackedInt32Array([BADGE])
	logo.position = LOGO_AT
	city.position = CITY_AT
	team_name.position = NAME_AT
	number.position = NUMBER_AT
	_motion_start()                           # $C3B6
	side = 0
	_select_team()                            # $C226
	_text_palette()                           # $C1E6
	_show(false, false, false)
	_open(Page.BIO)


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty() or _leaving:
		return
	_now += elapsed
	for i in elapsed:
		starfield.step()                      # VBlank task
	if _open_at >= 0:                         # the original is still drawing
		if _now < _open_at:
			return
		_open_at = -1
		_open(_opening)
	if scrolling:
		_scroll_pass()
		return
	if input != null and input.is_pressed("ui_back"):
		_leaving = true                       # Menu Back (plan 21): as Start on the bio
		exit_to(1)
		return
	_crowd_sound()
	match page:
		Page.BIO:
			_bio_pass(input)
		Page.COACH:
			_coach_pass(input)
		Page.ROSTER:
			_roster_pass(input)
		Page.PLAYER:
			_player_pass(input)


# --- pages: opening ------------------------------------------------------------------------------
## Opens [param p] after the original's drawing time.
func _request(p: Page, from_player := false) -> void:
	_opening = p
	_from_player = from_player
	_open_at = _now + DRAW_TICKS[p] + (1 if from_player else 0)


## Draws page [param p] and starts its move (the first move pass is this one).
func _open(p: Page) -> void:
	page = p
	match p:
		Page.BIO:                               # $C4AA
			_erase_lower()
			box = MwTextBox.new(plane, FONT_LIGHT, _rect(BIO_BOX))
			_draw_plate()
			_bio_text()
		Page.COACH:                             # $C546
			_erase_upper()
			_framed_box(COACH_BOX)
			portrait.attr = _sprite_attr()
			portrait.set_data(rom, MwPortrait.coach_data(rom, MwTeams.coach(rom, team)), 0)
			portrait.start(0)
			_mark = _now
			_portrait_player = false
			_coach_text()
			_text_palette()
		Page.ROSTER:                            # $C5F4 ($C5EC from a player)
			if _from_player:
				_draw_plate()
			_erase_lower()
			MwPlanePainter.frame(plane, rom, _bar_x(), _bar_y(BAR), _rect(BAR).size.x, 1, true)
			bar_moved = false
			_roster_text()
		Page.PLAYER:                            # $C6C0
			_erase_upper()
			_framed_box(PLAYER_BOX)
			portrait.attr = _sprite_attr()
			portrait.set_player(rom, _player(), PLAYER_PORTRAIT_SIZE)
			portrait.start(0)
			_mark = _now
			_portrait_player = true
			_draw_plate()
			_player_text()
	scrolling = true
	_scroll_pass()


## The page's move loop: [method _scroll] towards its place, the sprites it
## draws meanwhile; when it has arrived, the next pass is the page's own loop.
func _scroll_pass() -> void:
	var down := page == Page.COACH or page == Page.PLAYER
	var moving := _scroll(0 if down else UPPER, DROP_SPEED if down else RISE_SPEED)
	_crowd_sound()
	match page:
		Page.BIO, Page.ROSTER:
			_show(true, false, hook)
		Page.COACH:
			_show(true, false, true)
		Page.PLAYER:
			_show(false, true, true)
	if moving:
		return
	scrolling = false
	hook = down                               # $C3B8 set after a drop, cleared after a rise


## `$C3FC`: one pass of the move towards vscroll [param to] (at [param speed]
## when the target changes). False once there: on the bottom and settled, or
## at the top.
func _scroll(to: int, speed: int) -> bool:
	if to != target:
		target = to
		motion.vel[2] = speed
		_mark = _now
		land_sound = true
	var z := motion.pixels().z
	if z <= 4:
		if z == 0 and motion.vel[2] < SETTLED_SPEED:
			return false
		if motion.vel[2] <= LANDING_SPEED and land_sound:
			_effect_sound(SOUND_LAND)
			land_sound = false
	if target != 0 and z >= target:
		return false
	var elapsed := _now - _mark
	_mark = _now
	motion.step(params, elapsed)
	z = motion.pixels().z
	if target != 0 and z > target:
		z = target
		motion.init(0, 0, target)
	_set_scroll(z)
	return true


## `$C3B6`: the motion's parameters and start (vscroll 160).
func _motion_start() -> void:
	params = MwMotion.Params.new(MwGfx.s16(rom, SCROLL_PARAMS), MwGfx.s16(rom, SCROLL_PARAMS + 2),
			MwGfx.s16(rom, SCROLL_PARAMS + 4), MwGfx.s16(rom, SCROLL_PARAMS + 6))
	motion.init(MwGfx.s16(rom, SCROLL_START), MwGfx.s16(rom, SCROLL_START + 2), MwGfx.s16(rom, SCROLL_START + 4))
	target = UPPER
	_set_scroll(UPPER)


func _set_scroll(v: int) -> void:
	vscroll = v
	plane.scroll_to(v)
	sprites.position = Vector2(0, -v)


# --- pages: their loops --------------------------------------------------------------------------
## The original's pads: every player's newly pressed byte (`$C28E`).
func _pads(input: MwInputFrame) -> int:
	if input == null:
		return 0
	return input.pad_bits(1) | input.pad_bits(2) | input.pad_bits(3) | input.pad_bits(4)


## Start (`$C28E`): from a page back to the bio; from the bio, leave.
func _start_pressed(pads: int) -> bool:
	if pads & 0x80 == 0:
		return false
	if page == Page.BIO:
		_leaving = true                       # the crowd stops once the fade is over (_exit_tree)
		exit_to(1)
	else:
		_request(Page.BIO)
	return true


func _bio_pass(input: MwInputFrame) -> void:         # $C4FE
	_show(true, false, false)
	var pads := _pads(input)
	if _start_pressed(pads):
		return
	if pads & 0x0F:
		_effect_sound(SOUND_MOVE)
		side ^= 1
		_erase_lower()
		_select_team()
		_team_lines = true                    # $2268
		_text_palette()
		_bio_text()
	elif pads & 0x70:
		_request(Page.COACH)


func _coach_pass(input: MwInputFrame) -> void:       # $C592
	_show(true, false, true)
	_advance_portrait()                       # $B858
	var pads := _pads(input)
	if _start_pressed(pads):
		return
	if pads & 0x0F:
		portrait.stop()
		_effect_sound(SOUND_MOVE)
		side ^= 1
		_select_team()
		_team_lines = true
		_update_palette()
		_request(Page.COACH)
	elif pads & 0x70:
		portrait.stop()
		_request(Page.ROSTER)


## The original redraws the rows every pass, before the frame is shown;
## here they are redrawn at the end of the pass when something changed.
func _roster_pass(input: MwInputFrame) -> void:      # $C63E
	_show(true, false, false)
	var pads := _pads(input)
	if _start_pressed(pads):
		return
	if pads & 0x0F:
		_effect_sound(SOUND_MOVE)
		MwPlanePainter.frame(plane, rom, _bar_x(), _bar_y(BAR_ERASE), _rect(BAR_ERASE).size.x, 1, false, true)
		_move_cursor(pads)
	else:
		if bar_moved:
			MwPlanePainter.frame(plane, rom, _bar_x(), _bar_y(BAR), _rect(BAR).size.x, 1, true)
			bar_moved = false
			_drawn_roster = []
		if pads & 0x70:
			_request(Page.PLAYER)
	_roster_text()


func _player_pass(input: MwInputFrame) -> void:      # $C70A
	_show(false, true, true)
	_advance_portrait()                       # $B8C2
	var pads := _pads(input)
	if _start_pressed(pads):
		return
	if pads & 0x0F:
		portrait.stop()
		_effect_sound(SOUND_MOVE)
		_move_cursor(pads)
		_request(Page.PLAYER)
	elif pads & 0x70:
		portrait.stop()
		_request(Page.ROSTER, true)


## `$C348`: Down / Up the next / previous player, Right / Left the next /
## previous line, wrapping through the lines.
func _move_cursor(pads: int) -> void:
	if pads & 0x02:
		cursor += 1
	elif pads & 0x01:
		cursor -= 1
	elif pads & 0x08:
		line += 1
	elif pads & 0x04:
		line -= 1
	if cursor < 0:
		cursor = 5
		line -= 1
	if cursor >= 6:
		cursor = 0
		line += 1
	if line < 0:
		line = 3
	if line >= 4:
		line = 0
	bar_moved = true


## `$B858` / `$B8C2`: the portrait's animation for the ticks since the last mark.
func _advance_portrait() -> void:
	var elapsed := _now - _mark
	_mark = _now
	portrait.advance(elapsed)


# --- team, palette, sounds -------------------------------------------------------------------------
## `$C226`: the side's team; the panel colours on line 0; cursor to the
## first player.
func _select_team() -> void:
	team = setup.team_a if side == 0 else setup.team_b
	cursor = 0
	line = 0
	_update_palette()
	_header()


## `$C1E6`: the text line (2 for team A's pages, 1 for team B's) takes the
## text colours, colour 9 = the code's constant.
func _text_palette() -> void:
	_update_palette()


## The palette as the original builds it (docs/re/menus.md, Team
## description): screen palette, colour 0 black, the team's panel colours
## on line 0, after a switch the teams' lines on 1-2 (`$2268`), the text
## line.
func _update_palette() -> void:
	palette.screen = 2
	palette.team_a = setup.team_a
	palette.team_b = setup.team_b
	palette.stadium = setup.stadium
	var steps := PackedStringArray(["screen_palette", "black 0", "panel_line %s 0" % ("a" if side == 0 else "b")])
	if _team_lines:
		steps.append_array(["team_line a 1 1", "team_line b 2 1"])
	var tl := 2 - side
	steps.append_array(["rom %x %d" % [TEXT_LINE, tl], "word %x %d" % [TEXT_COLOUR, 16 * tl + 9]])
	palette.steps = steps


## Palette bits of the side's sprites (`d6`): team A line 1, team B line 2.
func _sprite_attr() -> int:
	return rom[SIDE_ATTRS + side]


## Palette bits of the yellow text (`$C3B6`): the other line.
func _text_attr() -> int:
	return rom[SIDE_ATTRS + 1 - side]


## `$C7C2`: the crowd keeps going.
func _crowd_sound() -> void:
	if not MwSound.busy(_crowd):
		_crowd = MwSound.play(SOUND_CROWD)


## `$C7DE`: one effect at a time.
func _effect_sound(id: int) -> void:
	MwSound.stop(_effect)
	_effect = MwSound.play(id)


## Left after Start's fade (`td_leave` `$BC2C` waits for it): the crowd's
## sequence stopped (`$C7AA`).
func _exit_tree() -> void:
	if _leaving:
		MwSound.stop(_crowd)


# --- drawing ---------------------------------------------------------------------------------------
func _rect(a: int) -> Rect2i:
	return Rect2i(MwGfx.s16(rom, a), MwGfx.s16(rom, a + 2), MwGfx.s16(rom, a + 4), MwGfx.s16(rom, a + 6))


func _bar_x() -> int:
	return _rect(BAR).position.x


func _bar_y(a: int) -> int:
	return _rect(a).position.y + 2 * cursor


## `$C304`: clears rows 28-47 (bio / roster).
func _erase_lower() -> void:
	MwPlanePainter.fill(plane, 0, 0x1C, 0x28, 0x14, 0)
	_drawn_roster = []


## `$C2E0`: clears rows 0-19 (coach / player).
func _erase_upper() -> void:
	MwPlanePainter.fill(plane, 0, 0, 0x28, 0x14, 0)


## `$C2AE`: the header plate (rows 20-27).
func _draw_plate() -> void:
	MwPlanePainter.map_rows(plane, rom, PLATE, 0, 8, PLATE_ROW)


## `$BA8E`: a framed, filled speech box with the dark font.
func _framed_box(a: int) -> void:
	var r := _rect(a)
	MwPlanePainter.frame(plane, rom, r.position.x, r.position.y, r.size.x, r.size.y, true)
	box = MwTextBox.new(plane, FONT_DARK, r)


func _text(font: int, s: PackedByteArray, x: int, y: int, attr: int) -> void:
	MwPlanePainter.text(plane, rom, font, s, x, y, attr)


func _str(pointer_at: int) -> PackedByteArray:
	return MwGfx.rom_string(rom, MwGfx.u32(rom, pointer_at))


## `$BC9A`: the bio page.
func _bio_text() -> void:
	var x := MwGfx.s16(rom, HEADING_X)
	_text(FONT_HEADING, _str(HEADINGS + 4 * side), x - 1, 0x1C, PLAIN_ATTR)
	box.home()
	box.write(rom, MwGfx.rom_string(rom, MwTeams.bio(rom, team)), TEXT_ATTR)
	_text(FONT_HEADING, _str(NASTY_HEADING), x, 0x27, _text_attr())
	for i in 3:
		var play := MwTeams.nasty_play(rom, team, i)
		_text(FONT_LIGHT, _str(NASTY_NAMES + 4 * play), MwGfx.s16(rom, NASTY_X), 0x2A + 2 * i, _text_attr())


## `$BD4C`: the coach's page (the quote in the box, the coach's name).
func _coach_text() -> void:
	box.home()
	box.write(rom, MwGfx.rom_string(rom, MwTeams.coach_quote(rom, team)), TEXT_ATTR)
	var coach := MwTeams.coach(rom, team)
	_text(FONT_HEADING, MwGfx.rom_string(rom, MwGfx.u32(rom, coach)), 0x13, 0x0E, PLAIN_ATTR)


## `$BDE2`: the roster - headings and the line's six players; the cursor's
## row in the dark font on the bar (once the bar is drawn there).
func _roster_text() -> void:
	var key := [team, line, cursor, bar_moved]
	if key == _drawn_roster:
		return
	_drawn_roster = key
	_text(FONT_HEADING, _str(ROSTER_HEADING), MwGfx.s16(rom, HEADING_X), 0x1C, PLAIN_ATTR)
	_text(FONT_HEADING, _str(NO_HEADING), 2, 0x1F, _text_attr())
	_text(FONT_HEADING, _str(LINE_HEADINGS + 4 * line), 6, 0x1F, _text_attr())
	_text(FONT_HEADING, _str(POSITION_HEADING), 0x19, 0x1F, _text_attr())
	for i in 6:
		var rec := MwTeams.player(rom, team, line * 6 + i)
		var row := PackedByteArray()
		row.resize(36)
		row.fill(MwPlanePainter.CH_BLANK)
		_overlay(row, 0, _digits(rom[rec + 4], false))
		_overlay(row, 4, MwGfx.rom_string(rom, MwGfx.u32(rom, rec)))
		_overlay(row, 0x17, _str(POSITIONS + 4 * i))
		var font := FONT_DARK if not bar_moved and cursor == i else FONT_LIGHT
		_text(font, row, 2, 0x22 + 2 * i, PLAIN_ATTR)


## `$BDCE`: copies [param s] into [param row] from [param at]; spaces keep
## what is there; stops at the row's end.
static func _overlay(row: PackedByteArray, at: int, s: PackedByteArray) -> void:
	for c in s:
		if at >= row.size():
			return
		if c != 0x20:
			row[at] = c
		at += 1


## `$B812` / `$B7E8`: two digits; a leading zero kept or blanked.
static func _digits(v: int, blank_zero: bool) -> PackedByteArray:
	@warning_ignore("integer_division")
	var tens := 0x30 + v / 10
	if blank_zero and tens == 0x30:
		tens = 0x20
	return PackedByteArray([tens, 0x30 + v % 10])


## `$C278`: a player's page - number and name, the quote, the ratings.
func _player_text() -> void:
	_player_header()
	var rec := _player()
	box.home()
	var star := MwPortrait.star_entry(rom, rec)
	if star != 0:                             # $BEE2: a star's own quote
		var group := 0 if team < 20 else (1 if team < 22 else 2)
		var q := MwQuotes.pick(rom, STAR_QUOTES, group, MwGfx.u16(rom, star + 8), session.rng)
		box.write(rom, MwQuotes.expand(q["template"], {}), TEXT_ATTR)
	else:
		var quality := rom[rec + 8] & 0x0F
		var parts := [_str(QUOTE_PARTS), MwGfx.rom_string(rom, MwGfx.u32(rom, rec)),
				_str(QUOTE_PARTS + 4), _str(LINE_WORDS + 4 * line), _str(POSITIONS + 4 * cursor),
				_str(QUOTE_PARTS + 8)]
		var c := MwGfx.rom_string(rom, MwTeams.city(rom, team))
		if c != "The".to_ascii_buffer():
			parts.append_array([c, _str(CITY_GAP)])
		parts.append_array([MwGfx.rom_string(rom, MwTeams.name(rom, team)), _str(DASH),
				_str(VERDICT_VERBS + 4 * quality), _str(VERDICT_MIDDLE), _str(VERDICT_WORDS + 4 * quality)])
		for p in parts:
			box.write(rom, p, TEXT_ATTR)
	_ratings(rec)


## `$C008` (skaters) / `$C110` (goalies): labels and two-digit values.
func _ratings(rec: int) -> void:
	var goalie := cursor == 5
	var rows := 5
	if not goalie and rom[rec + 0x0D] >> 4 != 0:
		rows = 6
	for col in 2:
		var labels: int = (GOALIE_LABELS if goalie else LABELS)[col]
		for i in rows:
			_text(FONT_LIGHT, _str(labels + 4 * i), LABEL_X[col], RATING_ROW + 2 * i, PLAIN_ATTR)
		for i in rows:
			var r: Array = RATINGS[col][i]
			var b := rom[rec + int(r[0])]
			var v := b >> 4 if r[1] else b & 0x0F
			_text(FONT_LIGHT, _digits(v, true), VALUE_X[col], RATING_ROW + 2 * i, PLAIN_ATTR)


func _player() -> int:
	return MwTeams.player(rom, team, line * 6 + cursor)


# --- sprites ---------------------------------------------------------------------------------------
## Which sprites this pass draws: the team header (logo, city, name), the
## player header (number, name), the portrait (with its tail and badge).
func _show(team_header: bool, player_header: bool, portrait_shown: bool) -> void:
	logo.visible = team_header
	city.visible = team_header
	team_name.visible = team_header
	number.visible = player_header
	for n in player_names:
		n.visible = player_header and n.texture != null
	portrait.visible = portrait_shown
	tail.visible = portrait_shown
	tail.position = PLAYER_TAIL_AT if _portrait_player else COACH_TAIL_AT
	badge.visible = portrait_shown and _portrait_player and rom[_player() + 0x0D] >> 4 != 0
	if portrait_shown:
		portrait.place(PLAYER_AT if _portrait_player else COACH_AT)


## `$B7DE`: the team's logo (its own colours) and city and name in big letters.
func _header() -> void:
	logo.frame_addresses = PackedInt32Array([MwTeams.logo_frame(rom, team)])
	_big_text(city, MwGfx.rom_string(rom, MwTeams.city(rom, team)))
	_big_text(team_name, MwGfx.rom_string(rom, MwTeams.name(rom, team)))


## `$B9B2`: the player's number and name (`$B93A`: names wider than 30
## cells on two lines, split after the first word - at most 10 letters a line).
func _player_header() -> void:
	var rec := _player()
	badge.attr_xor = _sprite_attr()
	_big_text(number, _digits(rom[rec + 4], false))
	var name := MwGfx.rom_string(rom, MwGfx.u32(rom, rec))
	var first := PackedByteArray()
	var i := 0
	if MwGfx.text_width(rom, FONT_BIG, name) > PLAYER_NAME_SPLIT:
		while i < name.size() and first.size() < 10:
			var c := name[i]
			i += 1
			if c == 0x20:
				break
			first.append(c)
		if i < name.size() and name[i] == 0x20:
			i += 1
	var rest := name.slice(i, mini(i + 10, name.size()))
	if first.is_empty():
		_big_text(player_names[0], rest)
		player_names[0].position = Vector2(PLAYER_NAME_X, 0xB4)
		_big_text(player_names[1], PackedByteArray())
	else:
		_big_text(player_names[0], first)
		player_names[0].position = Vector2(PLAYER_NAME_X, 0xA8)
		_big_text(player_names[1], rest)
		player_names[1].position = Vector2(PLAYER_NAME_X, 0xC0)


## `$B772`: [param s] in the big sprite letters, one piece a letter, on the
## side's palette line.
func _big_text(node: RomPieces, s: PackedByteArray) -> void:
	node.set_pieces(MwSpriteText.fixed(rom, FONT_BIG, s, _sprite_attr())[0])


## The original's D3 on sprite pieces: palette line bits XORed.
static func _xor(pieces: Array, attr: int) -> Array:
	for p in pieces:
		p["attr"] = int(p["attr"]) ^ (attr & 0x60)
	return pieces
