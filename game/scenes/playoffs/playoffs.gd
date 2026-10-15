class_name MwPlayoffsScreen
extends MwScreen
## Screen 11, the playoffs (`screen_11_playoffs` $11AE4; docs/re/menus.md,
## Playoffs): the bracket of the run in [MwPlayoffs] - A's conference on
## the left, the other on the right, a view per round (Left / Right between
## the rounds played so far), Start to the next game (the matchup). A new
## run can be re-drawn with A. Before the bracket: the password screen
## (pushed: Continue Playoffs, or the new password after a game); a
## champion sees the Monster Cup; an eliminated team goes back to the menu.
##
## The port's playoffs (plan 34, MwFlow.port_playoffs): after a game the
## bracket's Start goes back to the game options (SAVE GAME, then the next
## game), the run as it stood when the bracket opened is kept
## ([member MwSession.run_checkpoint]) and written to the autosave; a loaded
## run ([code]loaded[/code] in the entry data) opens its bracket without
## the password screen; champion and eliminated go to LOCAL PLAY.

const FONT_TITLE := MwFonts.TITLE
const FONT_LIGHT := MwFonts.LIGHT
const FONT_DARK := MwFonts.DARK
const FONT_BIG := MwFonts.BIG
const ATTR := 0xE0
## Map rows of the playoffs picture (`$36CA4`, 28 cells wide), 12 cells each.
const MAP_STRIDE := 28
const CONFERENCE_MAPS := [0x370A0, 0x36CB0]   ## 12 x 9 headers: conference 0, 1
const LOGO_MAP := 0x36CC8          ## 16 x 7 at (12, 2)
const CUP_MAP := 0x36E50           ## 16 x 21 at (12, 7)
const FILLER_MAP := 0x37030        ## 1 row
const BOX3_MAP := 0x36EA8          ## a match box of the later rounds, 3 rows
const BOX4_MAP := 0x36F50          ## a first-round box, 4 rows
const END_MAP := 0x37068           ## the column's last row
const SIDE_X := [0, 28]
const FIRST_ROW := 9
const LAST_ROW := 27
## `$1F1A0`: per view, the byte offsets (row * 128) of its boxes; a smaller
## value ends the list.
const BOX_LISTS := [0x1F15E, 0x1F15A, 0x1F158, 0x1F166]
## `$1F170` + `$120DC[view]`: the view's two team lists and name rows.
const NAME_TABLE := 0x1F170
const NAME_VIEWS := 0x120DC
const NAME_CLEAR := 0x66C60        ## 10 x `_`
const NAME_X := [1, 0x1D]
const NAME_WIDTH := 10
const PLAYOFFS := [0x66C4B, 12, 15]
const PRESS := [0x66C54, 17, 0x19]
const START := [0x66C5A, 17, 0x1A]
const BRACKET_LINE := 0x399B0      ## line 2 of the bracket
## The champion: the trophy, "THE <name>", "WIN THE MONSTER CUP".
const CUP_ANIM := "22bc6"
const CUP_AT := Vector2(160, 70)
const CUP_ATTR := 0x40
const THE := 0x66C6B
const WIN := 0x66C6F
const CHAMP_Y := 14
## The champion's "THE <name>": the original's line 2 (the bracket's line);
## with MwSettings.team_name_colours (owner) team A's line, its own colours.
const CHAMP_ATTR := 0xC0
const CHAMP_TEAM_ATTR := 0xA0
const WIN_AT := Vector2(0x12, 14 + 0x1A)

@onready var plane: RomPlane = $Window
@onready var palette: RomPalette = $Window.palette
@onready var starfield: RomStarfield = $Starfield
@onready var cup: RomSprite = $Cup
@onready var champion_text: RomPieces = $ChampionText

enum Phase { NONE, BRACKET, CHAMPION, LEAVING }

var rom: PackedByteArray
var setup: MwMatchSetup
var playoffs: MwPlayoffs
var phase := Phase.NONE
var view := 0                ## -6(a6): the round the bracket shows
var redraw := false          ## -8(a6)
var _held := false           ## the champion's starfield stopped (-$10(a6))
var _first := true
var _loaded := false         ## plan 34: a loaded run's bracket, no password screen
var _autosaved := false


func _ready() -> void:
	fades_in_itself = false


func _enter_screen(data: Dictionary) -> void:
	if not MwRom.available() or session == null:
		return
	rom = MwRom.data()
	_loaded = bool(data.get("loaded", false))
	if MwFlow.port_playoffs(session) and previous == 16:
		session.run_game_played()
	setup = session.setup
	playoffs = session.playoffs
	starfield.start(session.rng_aux)          # $11CBA: a moving starfield
	plane.wipe()
	_palette(false)
	if playoffs.flags & MwPlayoffs.CHAMPION:
		_champion()


## `$215E` (screen 11), colour 0 black; the bracket's line 2 (`$11CA8`).
func _palette(bracket: bool) -> void:
	palette.screen = 11
	palette.team_a = setup.team_a
	palette.stadium = setup.stadium
	var steps := PackedStringArray(["screen_palette", "black 0"])
	if bracket:
		steps.append("rom %x 2" % BRACKET_LINE)
	palette.steps = steps


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty() or phase == Phase.LEAVING:
		return
	for i in elapsed:
		starfield.step()
	if _first:
		_first = false
		if phase == Phase.CHAMPION:
			pass
		elif playoffs.flags & MwPlayoffs.ELIMINATED:
			_leave(MwFlow.end_run(session) if MwFlow.port_playoffs(session) else 1)
			return
		elif _loaded:
			MwSound.music_game()
			_bracket_start()
		elif playoffs.flags & MwPlayoffs.NEW == 0:
			push("password", {"show": playoffs.flags & MwPlayoffs.SHOW_PASSWORD != 0,
					"starfield": starfield.state()})
			return
		else:
			MwSound.music_game()              # `$11B3C`
			_bracket_start()
	if input != null and input.is_pressed("ui_back") and phase == Phase.BRACKET:
		_leave(1)                             # Menu Back (plan 21): back to the game setup
		return
	var pads := _pads(input)
	if phase == Phase.CHAMPION and input != null and input.is_pressed("ui_back"):
		pads |= 0x80                          # Menu Back as Start: leave (plan 22)
	match phase:
		Phase.BRACKET:
			_bracket_pass(pads)
		Phase.CHAMPION:
			_champion_pass(elapsed, pads)


## The newly pressed bytes of every pad OR'd (the bracket and the champion
## read any pad): pads 1-4, or every player's in an extended set-up (plan
## 34: [method MwSession.screen_pads]) - and team A's captain's, wherever
## the router put them (between playoff games the run's screens answer
## the captain as well as P1).
func _pads(input: MwInputFrame) -> int:
	var pads := 0
	if input == null:
		return pads
	var n := session.screen_pads() if session else 4
	pads = input.any_pad_bits(n, [MwVerbs.Context.PLAYOFFS])
	var captain := MwRinkControl.captain_screen_pad(session.humans, session.pad_map) if session else 0
	if captain > n:
		pads |= input.pad_bits(captain, [MwVerbs.Context.PLAYOFFS])
	return pads


## Back from the password screen: the bracket of the run it gave (its
## stars going on: [param r], the pop's result).
func _resume_screen(r := {}) -> void:
	starfield.restore(r.get("starfield", []))
	plane.wipe()
	MwSound.music_game()                      # `$11B3C` (after the password's `$13C04`)
	_bracket_start()


## `$11B42`: the bracket from the seed, the round's teams into the setup
## (the music, `$11B3C`, is the callers': A's new draw comes back to
## `$11B46` without it).
func _bracket_start() -> void:
	if MwFlow.port_playoffs(session):
		session.checkpoint_run()
		if previous == 16 and not _autosaved:
			_autosaved = true
			MwPlayoffSave.save(session, MwPlayoffSave.AUTOSAVE)
	phase = Phase.BRACKET
	_palette(true)
	playoffs.build_bracket(rom, playoffs.run_place(setup.team_a), setup.team_b)
	var g := playoffs.game_teams()
	setup.team_a = playoffs.shown(g.x)          # plan 38: a custom team in its place's stead
	setup.team_b = g.y
	view = playoffs.round
	redraw = true
	_bracket_pass(0)


func _bracket_pass(pads: int) -> void:
	if redraw:
		_draw_bracket()
		_draw_names()
		redraw = false
	if pads & 0x40 and playoffs.flags & MwPlayoffs.NEW:
		playoffs.new_seed(session.rng)        # A: a new draw
		_bracket_start()
	elif pads & 0x04 and view != MwPlayoffs.FIRST_ROUND:
		view = (view - 1) & 3
		redraw = true
	elif pads & 0x08 and view != playoffs.round:
		view = (view + 1) & 3
		redraw = true
	elif pads & 0x80:
		_leave(MwFlow.after_bracket(session, previous == 16) if MwFlow.port_playoffs(session) else 3)


## `$11C6A`: fade out, then the matchup (3) or the main menu (1); the
## music's 1-tick fade once the screen's is over ([method _exit_tree]).
func _leave(to: int) -> void:
	phase = Phase.LEAVING
	playoffs.flags &= ~MwPlayoffs.NEW
	exit_to(to)


## Left after `$11C6A`'s fade: `$11C7C` (the music stops).
func _exit_tree() -> void:
	if phase == Phase.LEAVING:
		MwSound.music_fade_out(1)


# --- the bracket ------------------------------------------------------------------------------------
## `$11E0C`: conference headers (A's on the left), the logo and texts, then
## each side's column for the view: match boxes where its list says, filler
## rows between, the last row at 27.
func _draw_bracket() -> void:
	var own := playoffs.conference
	_map(CONFERENCE_MAPS[own], 12, 9, SIDE_X[0], 0)
	_map(CONFERENCE_MAPS[1 - own], 12, 9, SIDE_X[1], 0)
	_map(LOGO_MAP, 16, 7, 12, 2)               # $11F40
	MwPlanePainter.text(plane, rom, FONT_TITLE, MwGfx.rom_string(rom, PLAYOFFS[0]), PLAYOFFS[1], PLAYOFFS[2], ATTR)
	MwPlanePainter.text(plane, rom, FONT_LIGHT, MwGfx.rom_string(rom, PRESS[0]), PRESS[1], PRESS[2], ATTR)
	# "START" under "PRESS": the bound input's glyph, centred under it (plan 23)
	MwPrompts.draw(plane, rom, FONT_LIGHT, MwGfx.rom_string(rom, START[0]), START[1], START[2], ATTR,
			MwVerbs.Context.PLAYOFFS, true, true)
	var list: int = BOX_LISTS[view]
	var box_map := BOX4_MAP if view == MwPlayoffs.FIRST_ROUND else BOX3_MAP
	var box_rows := 4 if view == MwPlayoffs.FIRST_ROUND else 3
	for x in SIDE_X:
		var row := FIRST_ROW
		var k := 0
		while row != LAST_ROW:
			if row * 128 == MwGfx.u16(rom, list + 2 * k):
				_map(box_map, 12, box_rows, x, row)
				row += box_rows
				k += 1
			else:
				_map(FILLER_MAP, 12, 1, x, row)
				row += 1
		_map(END_MAP, 12, 1, x, LAST_ROW)


## `$120E0`: the teams' names centred in 10 cells on the view's rows, A's
## side at column 1, the other at 29; the very first name in the dark font
## on a bar of `_`.
func _draw_names() -> void:
	var e := NAME_TABLE + rom[NAME_VIEWS + view]
	var lists := [MwGfx.u16(rom, e) - 0xC770, MwGfx.u16(rom, e + 2) - 0xC770]
	var font := FONT_DARK
	var k := 0
	e += 4
	while MwGfx.s16(rom, e) >= 0:
		var row := MwGfx.u16(rom, e)
		MwPlanePainter.text(plane, rom, font, MwGfx.rom_string(rom, NAME_CLEAR), NAME_X[0], row, ATTR)
		for side in 2:
			var t := playoffs.shown(_bracket_word(lists[side] + 2 * k))
			var team_name := MwGfx.rom_string(rom, MwTeams.name(rom, t))
			var x: int = MwMotion.asr(NAME_WIDTH - MwGfx.text_width(rom, font, team_name), 1) + NAME_X[side]
			MwPlanePainter.text(plane, rom, font, team_name, x, row, ATTR)
			font = FONT_LIGHT
		k += 1
		e += 2


## The word at `$FFC770` + [param offset]: the bracket's teams and winners.
func _bracket_word(offset: int) -> int:
	@warning_ignore("integer_division")
	var i := offset / 2
	var side := 0 if i < 15 else 1
	var side_teams: PackedInt32Array = playoffs.sides[side]
	return side_teams[i - 15 * side]


func _map(map: int, w: int, h: int, x: int, y: int) -> void:
	MwPlanePainter.map_rect(plane, rom, map, MAP_STRIDE, w, h, x, y)


# --- the champion -----------------------------------------------------------------------------------
## `$1291A`: the Monster Cup - the trophy animation, the cup picture,
## "THE <team> WIN THE MONSTER CUP" in sprite letters; B stops / restarts
## the starfield, C sends it another way; Start: the main menu.
func _champion() -> void:
	phase = Phase.CHAMPION
	MwSound.music_title()                     # `$12934`
	_palette(true)
	_map(CUP_MAP, 16, 21, 12, 7)
	cup.anim = CUP_ANIM
	cup.attr_xor = CUP_ATTR
	cup.position = CUP_AT
	cup.rebuild()
	cup.restart()
	cup.visible = true
	var team_name := MwGfx.rom_string(rom, MwTeams.name(rom, setup.team_a))
	var x := (30 - MwGfx.text_width(rom, FONT_BIG, team_name)) * 4
	var line := CHAMP_TEAM_ATTR if MwSettings.team_name_colours else CHAMP_ATTR
	var a: Array = MwSpriteText.pieces(rom, FONT_BIG, MwGfx.rom_string(rom, THE), line, x)
	var b: Array = MwSpriteText.pieces(rom, FONT_BIG, team_name, line, int(a[1]) + 8)
	var c: Array = MwSpriteText.pieces(rom, FONT_TITLE, MwGfx.rom_string(rom, WIN), ATTR, int(WIN_AT.x))
	var all: Array = a[0] + b[0]
	for p in all:
		p["y"] = int(p["y"]) + CHAMP_Y
	for p in c[0]:
		p["y"] = int(p["y"]) + int(WIN_AT.y)
		all.append(p)
	# port only (plan 38): a custom champion's name in colours of its own
	# (its "THE <name>" on a palette of its own; the cup keeps the shared one)
	if line == CHAMP_TEAM_ATTR and champion_text.palette == palette:
		champion_text.palette = MwScreenPalettes.names(palette, 1)
	champion_text.set_pieces(all)


func _champion_pass(elapsed: int, pads: int) -> void:
	cup.advance(elapsed)
	if pads & 0x10:
		_held = not _held
		if not _held:
			starfield.redirect(session.rng_aux)
			pads &= ~0x20
		else:
			starfield.hold()
	if pads & 0x20 and not _held:
		starfield.redirect(session.rng_aux)
	if pads & 0x80:
		_leave(MwFlow.end_run(session) if MwFlow.port_playoffs(session) else 1)
