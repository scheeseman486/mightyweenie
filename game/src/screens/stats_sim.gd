class_name MwStatsSim
extends MwScreenSim
## Screen 8, the game stats (`$CB56`), with screen 9, the player stats
## (`$D168`), inside it (plan 11; docs/re/stats.md). 9 is a subroutine of
## 8: the dispatcher's `$FFB05E` stays 8 while it runs, and its return sets
## 8 up again from scratch (`$CD2A`: `bra $CB56`, D7 kept).
##
## 8: one page of team statistics - the title and the team names on the
## window (its top 9 rows), 12 stats rows and the footer (A: player stats) on
## plane A (the table `$1CFFC`: a label and a team offset, 0 for the next
## formatter of `$1D050`, -1 at the end), plane A scrolled 16 pixels per
## D-pad press (held; 2 px a pass, the pads not read until the step ends),
## the team logos and the scroll arrows as sprites, the starfield on plane
## B. A pass is one loop of `$CB9E` (its boundary `$CC02`, after the
## `dma_queue_wait`: one tick). Start (newly pressed, any pad) returns to
## the screen it came from (D7: the scoreboard) after the music's and the
## screen's 32-tick fades; A opens 9 (the screen fades, the music plays on);
## B stops / restarts the starfield, C re-aims it while it runs.
##
## 9: 5 pages per team (the 4 lines' 5 skaters, the 4 goalies) drawn into
## two text boxes in turn (plane A's `$FFC406`, the window's `$FFC41C`; the
## window then covers the whole screen or none of it, so a page shows only
## once drawn); Down / Up the next / previous page (5 wraps), A the other
## team (same page; the starfield re-aimed), B / C as in 8, Start back to
## 8. A pass is one tick wait (`$D1F0`; 3-5 ticks when it redraws).
##
## Random numbers: none from the main stream; the starfield's directions
## come from the second stream ([member aux], `$FFCA18`): 8's set-up, B
## turning it on, C while on, 9's A. Nothing is left for the rink: the
## screens write their scratch (`$FFC3EE`-`$FFC475`, read by no other
## code), plane A's scroll, the starfield's objects (`$FFC7F8`, `$FFC810`)
## and plane B's scroll, the music state.
##
## Draws: [member window_ops] (the window, `$FFB0CA`) and [member
## plane_a_ops] (plane A, `$FFB09A`, 40 x 32 cells, scrolled vertically by
## [member scroll_a]) are [MwWindowPainter] operations ("fill" and "text";
## a text box's print is one "text" per word where `$15860` placed it).
## [member MwScreenSim.plane_ops] stays empty: plane B shows the starfield
## (picture `$4546C` repeated, as [RomStarfield]) at [member
## MwRinkState.scroll_b] (the pixels of [member star], which the VBlank
## task `$134E2` moves every tick). [member window_rows]: the screen rows
## the window covers from the top (8: 9; 9: 28 or 0). [member sprite_ops]:
## ["piece", piece, x, y, attr, depth] in screen pixels (`add_sprite_piece`
## `$156C6`; a team logo is its frame's pieces, `draw_frame` `$A07E`); 8
## builds its list every pass, 9 only when it redraws (the list stays up,
## so each 9 pass reports it). Events: ["sound", $25, handle] and
## ["voice_stop", handle] (`$CB3C`: a button's sound, the previous one
## stopped), ["music_track", address, handle] and ["music_stop", handle]
## (`$13C6E`), ["music_fade", 32] (`$13CAC`), ["fade_in", 32] (a set-up's
## palette: `screen_palette` `$215E`, the team lines `$23B0`) and
## ["fade_out", 32] (`$149CC`).
##
## The checks (`tools/bin/screen-check --only 8`) compare the scratch, the
## scrolls, the starfield, the aux stream and the music state after every
## pass; [method enter_ram] gives the sim what the decoded [MwRinkState]
## does not hold (the aux stream, the scratch a visit does not rewrite).

# --- the original's tables and constants -------------------------------------------------------

const TITLE := 0x1CF96               ## "GAME STATS": x, y, attr (words), text, plane, font (longs)
const NAME_PLANE := 0x1CFA0          ## the team names' plane (a long: the window)
const NAME_FONT := 0x22BEC           ## the team names' font (`$CD60`), 9's jersey numbers
const LABEL_A := 0x1CFD8             ## team A's column: x, y, attr (words)
const LABEL_A_TEXT := 0x1CFDE        ## ... then its text, plane, font (longs)
const LABEL_B := 0x1CFEA
const LABEL_B_TEXT := 0x1CFF0
const ROWS := 0x1CFFC                ## the rows: label (long), team offset (word; 0 formatter, -1 end)
const FORMATTERS := 0x1D050          ## the special rows' routines (code addresses)
const FORMAT_POWER_PLAYS := 0xCF78
const FORMAT_PENALTIES := 0xCF9A
const FORMAT_PASSING := 0xCFDC
const FORMAT_NONE := 0xD04E
const LAYOUT_8 := 0x1D060            ## `$4BE6`'s plane layouts (+2 / +3 plane A's size, +$B window rows)
const LAYOUT_9 := 0x1D0E2
const ARROW := 0x1D072               ## the arrow piece
const ARROW_UP := 0x1CFB0            ## 8's arrows: x, y, depth, attr (sprite coordinates)
const ARROW_DOWN := 0x1CFA8
const ARROWS_9 := [0x1CFC0, 0x1CFB8] ## 9's two arrows (`$D840`)
const LOGO_A := 0x1CFC8              ## 8's team logos: x, y, depth, attr
const LOGO_B := 0x1CFD0
const STAR_VX := 0x13470             ## the starfield's velocities by direction (words)
const STAR_VY := 0x1346C
const MUSIC := 0x1CE2D0              ## the track `$13C6E` plays
const BUTTON := 0x25                 ## the sound of an accepted button
const FADE_IN := 32                  ## a set-up's palette fade (`$1498C` per line)
const SPRITE_ORIGIN := 0x80          ## sprite coordinates of the screen's corner
const SCROLL_TOP := -80              ## plane A's vscroll at the first row (`$FFB0`)
const SCROLL_BOTTOM := -16           ## ... at the last (`$FFF0`)
const SCROLL_STEP := 2               ## px per pass
const SCROLL_ROWS := 16              ## px per press
const WINDOW_SIZE := Vector2i(40, 28)   ## the window object's cells (`$FFB0D2`)
# 9
const BOX_FONT := 0x447F4            ## the text boxes' font (`$D572`)
const HEADER_AT := 0x1D078           ## the team name: cursor x, y
const HEADER_FONT := 0x246FA
const TITLE_9 := 0x50B9B             ## "PLAYER STATS"
const TITLE_9_AT := 0x1D07E          ## x, y, attr
const TITLE_9_FONT := 0x22EE0
const NUMBER_HEAD := 0x50BB6         ## "NO"
const NUMBER_HEAD_AT := 0x1D084      ## x, y, attr (the page name at x 4 on the same row)
const PAGE_NAMES := 0x1D09C          ## by page (longs)
const COLUMN_HEADS := 0x1D0B0        ## by page (longs)
const COLUMN_X := 0x1D0C4            ## by page (words)
const PAGE_ROUTINES := 0x1D0CE       ## `$D5A6`'s stats routine by page (all `$D5BA`)
const PLAYER_STATS := 0xD5BA
const FOOTER := 0x50C93              ## 9's footer (A: the other team), at (8, 24) attr $60
const PAGES := 5
const FIRST_ROW := 9
const ROW_STEP := 3
# RAM
const WINDOW := 0xFFFFB0CA           ## the window's plane object
const PLANE_A := 0xFFFFB09A          ## plane A's
const BOX_A := 0xFFFFC406            ## 9's text box on plane A
const BOX_W := 0xFFFFC41C            ## ... on the window
const TEXTS := 0xFFC432              ## the value strings: team A's at +0, team B's at +14
const TEXTS_SIZE := 28
const TEXT_B := 14
const LABELS := 0xFFC44E             ## the two column descriptors ($12 bytes each)
const HANDLE := 0xFFC472
const AUX := 0xFFCA18
const STAR := 0xFFC7F8               ## the starfield's motion object
const STAR_PARAMS := 0xFFC810        ## its motion parameters
const SCROLL_A := 0xFFB0DA           ## plane A's vscroll buffer
const HSCROLL_A := 0xFFB0D6          ## plane A's hscroll buffer
const MUSIC_HANDLE := 0xFFCA2C
const MUSIC_TRACK := 0xFFCA30
const MUSIC_ON := 0xFFCA34
const MUSIC_FADE := 0xFFCA36
## [V] all recordings: the VBlank task runs 9 times between 8's set-up
## installing the starfield and the first pass boundary.
const STAR_SETUP_TICKS := 9


## A column descriptor (`$FFC44E` team A, `$FFC460` team B; `$CD4E`):
## where `draw_text` puts the column's value.
class Column:
	var x := 0                       ## +0 .w (team B's: right edge, less the text's width)
	var y := 0                       ## +2 .w
	var attr := 0                    ## +4 .w
	var text := 0                    ## +6 .l: the string (a team name, then `$FFFFC432` / `$FFFFC440`)
	var plane := 0                   ## +$A .l
	var font := 0                    ## +$E .l


## The screen shown: 8, or 9 inside it.
var shown := 8
## The second random stream (`$FFCA18`): the starfield's directions. Live
## play hands in [member MwSession.rng_aux]; the checks load it from the
## RAM ([method enter_ram]).
var aux := MlhRng.new()
## 9's team (the original's A4, not in RAM): 0 team A, 1 team B.
var team_shown := 0

# the scratch (`$FFC3EE`-`$FFC475`)
## `$FFC3EE` .l: the tick last seen (8: the loop's top, 9: the tick wait);
## -1 after a set-up of 8, whose first loop top reads it 1-2 ticks before
## the first pass boundary by CPU time (not modelled, not compared).
var tick_seen := 0
var saved_font := 0                  ## `$FFC3F2` .l: 9's box font while it prints in another
var box_at := 0                      ## `$FFC3F6` .l: the box 9 draws into next (`$FFFFC406` / `$FFFFC41C`)
var formatter := 0                   ## `$FFC3FA` .w: the special rows formatted (4 after the set-up)
var scroll_left := 0                 ## `$FFC3FC` .w: px of the step to go (0: no step)
var scroll_step := 0                 ## `$FFC3FE` .w: px per pass (+2 down, -2 up)
var page := 0                        ## `$FFC400` .w: 9's page (0-3 lines, 4 goalies)
var row := 0                         ## `$FFC402` .w: 9's row being printed
var redraw := 0                      ## `$FFC404` .b: 1, bit 7 a redraw wanted
var stars_on := 0                    ## `$FFC405` .b: $FF the starfield runs, 0 held
var boxes: Array[MwRinkState.TextBox] = [MwRinkState.TextBox.new(), MwRinkState.TextBox.new()]   ## `$FFC406`, `$FFC41C`
var texts := PackedByteArray()       ## `$FFC432`-`$FFC44D`
var labels: Array[Column] = [Column.new(), Column.new()]   ## `$FFC44E`, `$FFC460`
var handle := 0                      ## `$FFC472` .l: the button sound's handle (0: none)

# outside the scratch
## `$FFB0DA`: plane A's vscroll (VDP: screen line y shows plane line y +
## vscroll; 8: -80 shows row 0 at screen row 10, -16 the last rows; 9: 0).
var scroll_a := 0
var hscroll_a := 0                   ## `$FFB0D6`: plane A's hscroll (9 sets 0; 8 leaves it)
var window_rows := 0                 ## the window's height from the top (VDP window register)
## This pass's plane A operations ([MwWindowPainter]).
var plane_a_ops: Array = []
## The starfield's motion object (`$FFC7F8`; [MwMotion]: 24.8 positions,
## the direction's velocity), its parameters (`$FFC810`: none) and its
## VBlank task being installed (`starfield_draw` `$12B3E` .. `starfield_free`
## `$12BC4`).
var star := MwMotion.new()
var star_params := MwMotion.Params.new()
var star_task := false
## The music state (`$FFCA2C` handle, `$FFCA30` track, `$FFCA34`, `$FFCA36` fade).
var music_handle := -1
var music_track := 0
var music_on := 0
var music_fade := 0
var _sprites_9: Array = []           ## 9's sprite list as last uploaded
var _digits := 0                     ## the digits the last number had (the original's d2)


func _init(rom_: PackedByteArray) -> void:
	super._init(rom_)
	texts.resize(TEXTS_SIZE)


func ported() -> bool:
	return true


## Check hook (before [method enter]): the RAM at the screen's call - the
## aux stream, the scratch (9's boxes, the strings' tails: what this visit
## may not rewrite), plane A's hscroll and the music state.
func enter_ram(ram: PackedByteArray) -> void:
	aux.state = MwRinkRam.u32(ram, AUX)
	tick_seen = MwRinkRam.u32(ram, 0xFFC3EE)
	saved_font = MwRinkRam.u32(ram, 0xFFC3F2)
	box_at = MwRinkRam.u32(ram, 0xFFC3F6)
	formatter = MwRinkRam.u16(ram, 0xFFC3FA)
	scroll_left = MwRinkRam.s16(ram, 0xFFC3FC)
	scroll_step = MwRinkRam.s16(ram, 0xFFC3FE)
	page = MwRinkRam.u16(ram, 0xFFC400)
	row = MwRinkRam.u16(ram, 0xFFC402)
	redraw = MwRinkRam.u8(ram, 0xFFC404)
	stars_on = MwRinkRam.u8(ram, 0xFFC405)
	for i in 2:
		_box_from(ram, (BOX_A if i == 0 else BOX_W) & 0xFFFFFF, boxes[i])
		_label_from(ram, LABELS + 0x12 * i, labels[i])
	texts = ram.slice(TEXTS - MwRinkRam.BASE, TEXTS - MwRinkRam.BASE + TEXTS_SIZE)
	handle = MwRinkRam.u32(ram, HANDLE)
	hscroll_a = MwRinkRam.s16(ram, HSCROLL_A)
	music_handle = MwRinkRam.s32(ram, MUSIC_HANDLE)
	music_track = MwRinkRam.u32(ram, MUSIC_TRACK)
	music_on = MwRinkRam.u8(ram, MUSIC_ON)
	music_fade = MwRinkRam.u16(ram, MUSIC_FADE)


static func _box_from(ram: PackedByteArray, a: int, b: MwRinkState.TextBox) -> void:
	b.plane = MwRinkRam.u32(ram, a)
	b.font = MwRinkRam.u32(ram, a + 4)
	b.x = MwRinkRam.s16(ram, a + 8)
	b.y = MwRinkRam.s16(ram, a + 0xA)
	b.w = MwRinkRam.s16(ram, a + 0xC)
	b.h = MwRinkRam.s16(ram, a + 0xE)
	b.spacing = MwRinkRam.s16(ram, a + 0x10)
	b.cursor_x = MwRinkRam.s16(ram, a + 0x12)
	b.cursor_y = MwRinkRam.s16(ram, a + 0x14)


static func _label_from(ram: PackedByteArray, a: int, l: Column) -> void:
	l.x = MwRinkRam.s16(ram, a)
	l.y = MwRinkRam.s16(ram, a + 2)
	l.attr = MwRinkRam.u16(ram, a + 4)
	l.text = MwRinkRam.u32(ram, a + 6)
	l.plane = MwRinkRam.u32(ram, a + 0xA)
	l.font = MwRinkRam.u32(ram, a + 0xE)


func begin_pass() -> void:
	super.begin_pass()
	plane_a_ops.clear()


# --- 8: set-up -----------------------------------------------------------------------------------

## `$CB56`: 8's set-up and its loop's first pass up to the boundary.
func enter(state: MwRinkState, screen_id: int, from_screen: int) -> void:
	super.enter(state, screen_id, from_screen)
	begin_pass()
	_setup_8()


## `$CB56`..`$CB9A`, then the first loop pass's top: the music (`$13C6E`),
## the tick noted (`$FFC3EE`; the loop's top overwrites it), the starfield started, the sound handle cleared, the planes
## (`$D06A`), no scroll step, the starfield running, the title (`$CD34`),
## the team names and the rows (`$CD4E`); the loop's top and sprites.
func _setup_8() -> void:
	shown = 8
	_music_8()
	_stars_start()
	handle = 0
	_layout_8()
	scroll_left = 0
	scroll_step = 0
	stars_on = 0xFF
	_title()
	_team_names()
	# the first loop pass's top reads the tick 1-2 ticks before its boundary
	tick_seen = -1
	_sprites_8()
	_stars_run(_setup_vblanks())


## `$13C6E` (`$CB6E`; live: [method MwSound.music_game]): the stats music,
## unless it is the track playing; music on, no fade (the driver's state as
## the comparison models it).
func _music_8() -> void:
	sound_call(func() -> void: MwSound.music_game())
	if music_track != MUSIC:
		if music_track != 0:
			events.append(["music_stop", music_handle])
		music_track = MUSIC
		_serial = (_serial + 1) & 0x3FFFFFFF
		music_handle = _serial | 0x40000000
		events.append(["music_track", MUSIC, music_handle])
	music_on = 0xFF
	music_fade = 0


## `$D06A`: the planes' layout `$1D060` (the window over the top rows), the
## window and plane A cleared, the starfield drawn on plane B (its VBlank
## task on), plane A's vscroll at the first row, the palette fading in.
func _layout_8() -> void:
	window_rows = rom[LAYOUT_8 + 0xB]
	_clear_planes(LAYOUT_8)
	star_task = true
	scroll_a = SCROLL_TOP
	events.append(["fade_in", FADE_IN])


## `$146D6` on the window and plane A: every cell 0.
func _clear_planes(layout: int) -> void:
	window_ops.append(["fill", 0, 0, WINDOW_SIZE.x, WINDOW_SIZE.y, 0])
	plane_a_ops.append(["fill", 0, 0, rom[layout + 2], rom[layout + 3], 0])


## `$CD34`: "GAME STATS" (`draw_text` with `$1CF96`'s place, plane, font).
func _title() -> void:
	var x := MwGfx.s16(rom, TITLE)
	var y := MwGfx.s16(rom, TITLE + 2)
	var attr := MwGfx.u16(rom, TITLE + 4)
	var text := MwGfx.u32(rom, TITLE + 6)
	_ops_for(MwGfx.u32(rom, TITLE + 0xA)).append(["text", MwGfx.u32(rom, TITLE + 0xE), x, y, attr, text])


## `$CD4E`: the team names on the window's row 7 (team A from column 2,
## team B up to column 38), then the descriptors pointed at the value
## strings and plane A, and the rows.
func _team_names() -> void:
	var la := labels[0]
	var lb := labels[1]
	lb.text = MwGfx.u32(rom, s.teams[1].record + 4)
	lb.plane = MwGfx.u32(rom, NAME_PLANE)
	lb.font = NAME_FONT
	_label_place(lb, LABEL_B)
	lb.x = MwRinkSim.s16(lb.x - _width(lb.font, _label_text(lb)))
	la.text = MwGfx.u32(rom, s.teams[0].record + 4)
	la.plane = MwGfx.u32(rom, NAME_PLANE)
	la.font = NAME_FONT
	_label_place(la, LABEL_A)
	_draw_label(la)
	_draw_label(lb)
	_label_target(la, LABEL_A_TEXT)
	_label_target(lb, LABEL_B_TEXT)
	la.y = 0
	lb.y = 0
	_rows()


func _label_place(l: Column, a: int) -> void:
	l.x = MwGfx.s16(rom, a)
	l.y = MwGfx.s16(rom, a + 2)
	l.attr = MwGfx.u16(rom, a + 4)


func _label_target(l: Column, a: int) -> void:
	l.text = MwGfx.u32(rom, a)
	l.plane = MwGfx.u32(rom, a + 4)
	l.font = MwGfx.u32(rom, a + 8)


## `$CDEA`: the rows of `$1CFFC` from plane A's row 0, two rows apart: the
## values (a team offset's word, `$CF38`; or the next special formatter),
## then `$CEF0` (team B's value right-aligned to column 38, both values,
## the label centred).
func _rows() -> void:
	var la := labels[0]
	var lb := labels[1]
	formatter = 0
	var a := ROWS
	while true:
		lb.x = MwGfx.s16(rom, LABEL_B)
		var label := MwGfx.u32(rom, a)
		var off := MwGfx.s16(rom, a + 4)
		a += 6
		if off < 0:
			return
		if off == 0:
			_format_special(MwGfx.u32(rom, FORMATTERS + 4 * formatter))
			formatter = (formatter + 1) & 0xFFFF
		else:
			_number(team_word(s.teams[0], off), _text_offset(la.text))
			_number(team_word(s.teams[1], off), _text_offset(lb.text))
		_row(label)
		la.y = MwRinkSim.s16(la.y + 2)
		lb.y = MwRinkSim.s16(lb.y + 2)


## `$CEF0`: team B's value right-aligned, both values drawn, the label
## centred in 40 columns (measured and drawn in team B's font).
func _row(label: int) -> void:
	var la := labels[0]
	var lb := labels[1]
	lb.x = MwRinkSim.s16(lb.x - _width(lb.font, _label_text(lb)))
	_draw_label(la)
	_draw_label(lb)
	var w := MwGfx.text_width(rom, lb.font, MwGfx.rom_string(rom, label))
	var x := MwRinkSim.asr(MwRinkSim.s16(0x28 - w), 1)
	_ops_for(lb.plane).append(["text", lb.font, x, lb.y, lb.attr, label])


## `draw_text` of a descriptor's string at its place.
func _draw_label(l: Column) -> void:
	_ops_for(l.plane).append(["text", l.font, l.x, l.y, l.attr, _label_text(l)])


## The special rows (`$1D050`'s routines): power plays `$CF78` ("a/b" of
## +$486 / +$488), penalties `$CF9A` ("a/b:00", +$48A / +$48C), passing
## `$CFDC` ("a/b (p%)" of +$496 / +$498, p = a * 100 / b; "a/b" when b is
## 0), `$D04E` (no values).
func _format_special(routine: int) -> void:
	for t in 2:
		var team := s.teams[t]
		var at := 0 if t == 0 else TEXT_B
		match routine:
			FORMAT_POWER_PLAYS:
				_fraction(team_word(team, 0x486), team_word(team, 0x488), at)
			FORMAT_PENALTIES:
				var e := _fraction(team_word(team, 0x48A), team_word(team, 0x48C), at)
				e = _put_bytes(e, [0x3A, 0x30, 0x30])
				_put(e, 0)
			FORMAT_PASSING:
				var made := team_word(team, 0x496)
				var tried := team_word(team, 0x498)
				var e := _fraction(made, tried, at)
				if tried != 0:
					e = _put_bytes(e, [0x20, 0x28])
					e = _number(_divu(made * 100, tried) & 0xFFFF, e)
					e = _put_bytes(e, [0x25, 0x29])
				_put(e, 0)
			FORMAT_NONE:
				_put(at, 0)
			_:
				push_warning("MwStatsSim: unknown stats formatter $%X" % routine)
				_put(at, 0)


## `$D058`: "a/b" at [param at]; returns the offset of its 0.
func _fraction(a: int, b: int, at: int) -> int:
	var e := _number(a, at)
	_put(e, 0x2F)
	return _number(b, e + 1)


## A team's word at RAM offset [param off] (`$4A2` the score, else its
## statistics block).
static func team_word(team: MwRinkState.Team, off: int) -> int:
	if off == 0x4A2:
		return team.score & 0xFFFF
	var lo := MwRinkState.Team.STATS_AT
	if off >= lo and off + 2 <= lo + team.stats.size():
		return team.stat(off)
	push_warning("MwStatsSim: no team word at +$%X" % off)
	return 0


# --- numbers and the strings ---------------------------------------------------------------------

## `stats_number` `$CF38`: [param v] (a word) in decimal at [param at] in
## the strings, a 0 after it, no leading zeros (1000+ gives wrong
## characters, as the original: `divu` of a sign-extended word).
## [param entry] 100 (`$CF38`), 10 (`$CF52`: at most two digits) or 2
## (`$CF5A`: always two). Returns the offset of the 0; [member _digits] the
## digits written (the original's d2).
func _number(v: int, at: int, entry := 100) -> int:
	var d0 := v & 0xFFFF
	_digits = 0
	var tens := entry == 2
	if entry == 100 and d0 >= 100:
		_digits += 1
		d0 = _divu(_ext_l(d0), 100)
		_put(at, d0 + 0x30)
		at += 1
		d0 = _swap(d0)
		tens = true
	if tens or (d0 & 0xFFFF) >= 10:
		_digits += 1
		d0 = _divu(_ext_l(d0 & 0xFFFF), 10)
		_put(at, d0 + 0x30)
		at += 1
		d0 = _swap(d0)
	_digits += 1
	_put(at, d0 + 0x30)
	_put(at + 1, 0)
	return at + 1



## 68000 `divu.w`: [param d0] (32 bits) / [param divisor]: remainder in
## the high word, quotient in the low; on overflow (a quotient over $FFFF)
## d0 unchanged.
static func _divu(d0: int, divisor: int) -> int:
	d0 &= 0xFFFFFFFF
	divisor &= 0xFFFF
	if divisor == 0:
		return d0
	var q := d0 / divisor
	if q > 0xFFFF:
		return d0
	return ((d0 % divisor) << 16) | q


static func _ext_l(w: int) -> int:
	return (w | 0xFFFF0000) if w & 0x8000 else w & 0xFFFF


static func _swap(d0: int) -> int:
	return ((d0 << 16) | (d0 >> 16)) & 0xFFFFFFFF


func _put(at: int, v: int) -> void:
	if at < 0 or at >= TEXTS_SIZE:
		push_warning("MwStatsSim: a string runs past $FFC44D")
		return
	texts[at] = v & 0xFF


func _put_bytes(at: int, bytes: Array) -> int:
	for b in bytes:
		_put(at, int(b))
		at += 1
	return at


## The offset in the strings of a RAM string's address, -1 for a ROM one.
static func _text_offset(addr: int) -> int:
	var o := (addr & 0xFFFFFF) - TEXTS
	return o if o >= 0 and o < TEXTS_SIZE else -1


## A descriptor's string: the strings' bytes up to their 0, or the ROM's.
func _label_text(l: Column) -> PackedByteArray:
	return _string_at(l.text)


func _string_at(addr: int) -> PackedByteArray:
	var o := _text_offset(addr)
	if o < 0:
		return MwGfx.rom_string(rom, addr & 0xFFFFFF)
	var e := o
	while e < TEXTS_SIZE and texts[e] != 0:
		e += 1
	return texts.slice(o, e)


## `$14C14`: a string's width in cells.
func _width(font: int, text: PackedByteArray) -> int:
	return MwGfx.text_width(rom, font, text)


## The operation list of the plane object at [param plane].
func _ops_for(plane: int) -> Array:
	match plane & 0xFFFFFF:
		0xFFB0CA:
			return window_ops
		0xFFB09A:
			return plane_a_ops
	push_warning("MwStatsSim: drawing on plane object $%X" % plane)
	return plane_a_ops


# --- sprites -------------------------------------------------------------------------------------

## `$CB9E`..`$CBEA`: the list reset, the arrows (up while plane A is not
## at its first row, down while not at its last), the team logos.
func _sprites_8() -> void:
	sprite_ops.clear()
	if scroll_a != SCROLL_TOP:
		_piece(ARROW, ARROW_UP, sprite_ops)
	if scroll_a != SCROLL_BOTTOM:
		_piece(ARROW, ARROW_DOWN, sprite_ops)
	_logo(s.teams[0], LOGO_A, 0, 0, -1, sprite_ops)
	_logo(s.teams[1], LOGO_B, 0, 0, -1, sprite_ops)


## `add_sprite_piece` with x, y, depth, attr at [param at].
func _piece(piece: int, at: int, out: Array) -> void:
	out.append(["piece", piece, MwGfx.s16(rom, at) - SPRITE_ORIGIN, MwGfx.s16(rom, at + 2) - SPRITE_ORIGIN,
			MwGfx.u16(rom, at + 6), MwGfx.u16(rom, at + 4)])


## `draw_frame` of a team's logo (record +$78) with the place at [param
## at] moved by ([param dx], [param dy]), [param attr] (-1: the place's).
func _logo(team: MwRinkState.Team, at: int, dx: int, dy: int, attr: int, out: Array) -> void:
	if s.replay.open != 0:
		push_warning("MwStatsSim: draw_frame with the replay recording ($FFC2D2)")
	var frame := MwGfx.u32(rom, team.record + 0x78)
	var x := MwGfx.s16(rom, at) + dx - SPRITE_ORIGIN
	var y := MwGfx.s16(rom, at + 2) + dy - SPRITE_ORIGIN
	var depth := MwGfx.u16(rom, at + 4)
	var a := MwGfx.u16(rom, at + 6) if attr < 0 else attr
	for i in MwGfx.u16(rom, frame):
		out.append(["piece", frame + 2 + 6 * i, x, y, a, depth])


# --- the starfield -------------------------------------------------------------------------------

## `starfield_scroll_start` `$13480`: the motion object at rest at 0
## (`motion_init`), no friction (`motion_params` 0), then a direction (it
## falls into `$134A4`).
func _stars_start() -> void:
	star.init(0, 0, 0)
	star_params = MwMotion.Params.new(0, 0, 0, 0)
	_stars_redirect()


## `starfield_redirect` `$134A4`: a direction from the aux stream (`& $E`
## indexes the velocity tables), the position's fractions dropped.
func _stars_redirect() -> void:
	var k := aux.next_state() & 0xE
	star.vel[0] = MwGfx.s16(rom, STAR_VX + k)
	star.vel[1] = MwGfx.s16(rom, STAR_VY + k)
	star.pos[0] = star.pos[0] & ~0xFF
	star.pos[1] = star.pos[1] & ~0xFF


## `starfield_hold` `$134D0`: velocity 0.
func _stars_hold() -> void:
	star.vel[0] = 0
	star.vel[1] = 0


## The VBlanks between the set-up installing the starfield and the first
## pass boundary: [constant STAR_SETUP_TICKS] (the set-up's drawing takes
## 8 in one recording: its length is the CPU's, not a count the code
## keeps). Under a check ([member MwScreenSim.hooks] answering
## `stored_long` from the RAM at the boundary): the count that brings the
## starfield where the original's stood.
func _setup_vblanks() -> int:
	if hooks == null or not hooks.has_method("stored_long"):
		return STAR_SETUP_TICKS
	var at: Variant = hooks.get("next_ram")
	if not at is PackedByteArray or (at as PackedByteArray).is_empty():
		return STAR_SETUP_TICKS
	for k in 2:
		var v := MwRinkSim.s16(star.vel[k])
		if v == 0:
			continue
		var d: int = _signed32(int(hooks.call("stored_long", self, STAR + 8 * k))) - _signed32(star.pos[k])
		if d % v == 0 and absi(d / v - STAR_SETUP_TICKS) <= 3:
			return d / v
		break
	return STAR_SETUP_TICKS


static func _signed32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v & 0x80000000 else v


## The VBlank task `$134E2` [param ticks] times (while installed): a tick
## of motion each, plane B's scroll buffers (`$FFB0D8` hscroll, `$FFB0DC`
## vscroll) = the position in pixels.
func _stars_run(ticks: int) -> void:
	if not star_task or ticks <= 0:
		return
	star.step(star_params, ticks)
	var p := star.pixels()
	s.scroll_b = Vector2i(MwRinkSim.s16(p.x), MwRinkSim.s16(p.y))


## B (newly pressed): the starfield stopped, or started again in a new
## direction (the tick noted); C while it runs: a new direction.
func _stars_buttons(w: int) -> void:
	if w & 0x10:
		_button()
		stars_on ^= 0xFF
		if stars_on == 0:
			_stars_hold()
			return
	elif stars_on != 0 and w & 0x20:
		_button()
	else:
		return
	tick_seen = _tick_early()
	_stars_redirect()


# --- 8: the pass ---------------------------------------------------------------------------------

## One pass: 8's loop (`$CC02` on) or 9's (`$D1F0` on). Returns the screen
## to leave for (8's Start: the one it came from), else -1.
func step(elapsed: int, held: Array, new: Array) -> int:
	if shown == 9:
		return _pass_9(elapsed, held, new)
	return _pass_8(elapsed, held, new)


## `$CC02`..: a scroll step in progress moves plane A 2 px (none past the
## ends) and the pass ends without reading the pads until the 16 px are
## done; else the pads (any pad): Start leaves, the D-pad (held) starts a
## step, A opens 9, B / C the starfield. Then the loop's top: the tick, the
## sprites.
func _pass_8(elapsed: int, held: Array, new: Array) -> int:
	var n := _pass_ticks(elapsed)
	if scroll_left != 0:
		var at_end := scroll_a == (SCROLL_TOP if scroll_step < 0 else SCROLL_BOTTOM)
		if not at_end:
			scroll_a = MwRinkSim.s16(scroll_a + scroll_step)
			scroll_left = MwRinkSim.s16(scroll_left + scroll_step)
			if scroll_left != 0:
				return _loop_top_8(n)
		scroll_left = 0
		scroll_step = 0
	MwScoreboardSim.read_pads(s, held, new)
	var w := pads_word(held, new)
	if w & 0x80:
		return _leave_8()
	if w & 0x0200 or (not w & 0x0100 and w & 0x0800):
		scroll_step = SCROLL_STEP
		scroll_left = -SCROLL_ROWS
	elif w & 0x0500:
		scroll_step = -SCROLL_STEP
		scroll_left = SCROLL_ROWS
	elif w & 0x40:
		return _open_9(n)
	else:
		_stars_buttons(w)
	return _loop_top_8(n)


## `$CB9E`: the tick noted, the sprites; the pass's VBlanks move the starfield.
func _loop_top_8(n: int) -> int:
	tick_seen = _tick_early()
	_sprites_8()
	_stars_run(n)
	return -1


## Start: the sound, the music's and the screen's fades, `$D126` (the
## starfield freed, the layout restored); back to D7.
func _leave_8() -> int:
	_button()
	if music_track != 0:
		music_fade = FADE_OUT
		events.append(["music_fade", FADE_OUT])
	if from != 9:                               # `$CCF0`: D7 = 9 skips it
		sound_call(func() -> void: MwSound.music_fade_out(FADE_OUT))   # `$CCF8`
	fade_out(FADE_OUT)
	star_task = false
	return from


## `$CB3C`: the button sound (the previous one stopped, `$CB42`; the
## event only when there was one).
func _button() -> void:
	if handle != 0:
		events.append(["voice_stop", handle])
	var h := handle
	sound_call(func() -> void: MwSound.stop(h))
	handle = sound(BUTTON)                      # `$CB4A`


## The tick a read right after this pass's boundary sees.
func _tick_early() -> int:
	return MwScoreboardSim.tick_early(self)


## The VBlanks from this pass's boundary to the next (the starfield's
## ticks): the checks know the next boundary (hooks' `pass_end`); live play
## runs a pass per tick and gives the pass's ticks.
func _pass_ticks(elapsed: int) -> int:
	if hooks != null and hooks.has_method("pass_end") and hooks.has_method("pass_start"):
		return (MwScoreboardSim.tick_late(self) - MwScoreboardSim.tick_early(self)) & 0xFFFF
	return elapsed & 0xFFFF


# --- 9 -------------------------------------------------------------------------------------------

## 8's A: the sound, the fade (the music plays on), `$D126`, then 9
## (`$D168`) up to its first boundary. The starfield misses one VBlank
## between 8's teardown and 9's set-up [V].
func _open_9(n: int) -> int:
	_button()
	fade_out(FADE_OUT)
	star_task = false
	_setup_9()
	sprite_ops.append_array(_sprites_9)
	_stars_run(n - 1)
	return -1


## `$D168`: `$D736` (the layout `$1D0E2`: the window over the whole screen;
## the starfield drawn again; plane A's scrolls 0; the palette; the window
## and plane A cleared), page 0, the starfield on, team A, the two text
## boxes (`$D55C`), plane A's box first, the first page drawn.
func _setup_9() -> void:
	shown = 9
	window_rows = rom[LAYOUT_9 + 0xB]
	star_task = true
	scroll_a = 0
	hscroll_a = 0
	events.append(["fade_in", FADE_IN])
	_clear_planes(LAYOUT_9)
	page = 0
	stars_on = 0xFF
	redraw = 1
	team_shown = 0
	_boxes_init()
	box_at = BOX_A
	_redraw_9()


## `$D55C`: the boxes (0, 0, 40, 28) on plane A and on the window, font `$447F4`.
func _boxes_init() -> void:
	for i in 2:
		var b := boxes[i]
		b.x = 0
		b.y = 0
		b.w = 0x28
		b.h = 0x1C
		b.spacing = 0
		b.plane = PLANE_A if i == 0 else WINDOW
		b.font = BOX_FONT
		b.cursor_x = 0
		b.cursor_y = 0


## `$D1E4`..: the tick wait's end (the tick noted), the pads (newly
## pressed, any pad): Start back to 8, A the other team (the starfield
## re-aimed), Down / Up the page, B / C the starfield; a redraw if one was
## asked for.
func _pass_9(elapsed: int, held: Array, new: Array) -> int:
	var n := _pass_ticks(elapsed)
	tick_seen = _tick_early()
	MwScoreboardSim.read_pads(s, held, new)
	var w := pads_word(held, new) & 0xFF
	if w & 0x80:
		return _back_to_8()
	if w & 0x40:
		_button()
		team_shown ^= 1
		redraw |= 0x80
		tick_seen = _tick_early()
		_stars_redirect()
	elif w & 0x02:
		if page >= 4:
			page = 0xFFFF
		_button()
		page = (page + 1) & 0xFFFF
		redraw |= 0x80
	elif w & 0x01:
		if page == 0:
			page = PAGES
		_button()
		page = (page - 1) & 0xFFFF
		redraw |= 0x80
	else:
		_stars_buttons(w)
	if redraw & 0x80:
		redraw &= 0x7F
		_redraw_9()
	sprite_ops.append_array(_sprites_9)
	_stars_run(n)
	return -1


## 9's Start: the sound, the fade (the music plays on), `$D7FE` (the
## starfield freed), back in 8 (`bra $CB56`): 8 set up again.
func _back_to_8() -> int:
	_button()
	fade_out(FADE_OUT)
	star_task = false
	_setup_8()
	return -1


## `$D18E`: the sprites (the team's logo, the two arrows), the box filled
## with 0, the header (`$D366`), the rows (`$D446`), the boxes swapped
## (`$D334`).
func _redraw_9() -> void:
	var team := s.teams[team_shown]
	_sprites_9.clear()
	_logo(team, LOGO_A, 0x10, -8, 0x20 if team_shown == 0 else 0x40, _sprites_9)
	for at in ARROWS_9:
		_piece(ARROW, int(at), _sprites_9)
	var b := _box()
	_ops_for(b.plane).append(["fill", b.x, b.y, b.w, b.h, 0])
	_header_9(b, team)
	_rows_9(b, team)
	_swap_9()


func _box() -> MwRinkState.TextBox:
	return boxes[0] if box_at & 0xFFFFFF == BOX_A & 0xFFFFFF else boxes[1]


## `$D334`: plane A's box drawn - the window shows no rows, the window's
## box is next; else the window covers the screen, plane A's is next.
func _swap_9() -> void:
	if box_at & 0xFFFFFF == BOX_A & 0xFFFFFF:
		box_at = BOX_W
		window_rows = 0
	else:
		box_at = BOX_A
		window_rows = 0x1C


## `$D366`: the team name (font `$246FA`, attr $20 / $40), "PLAYER STATS"
## (font `$22EE0`), "NO", the page's name, its column header.
func _header_9(b: MwRinkState.TextBox, team: MwRinkState.Team) -> void:
	var attr := 0x20 if team_shown == 0 else 0x40
	saved_font = b.font
	b.font = HEADER_FONT
	_cursor(b, MwGfx.s16(rom, HEADER_AT), MwGfx.s16(rom, HEADER_AT + 2))
	_write(b, MwGfx.rom_string(rom, MwGfx.u32(rom, team.record + 4)), attr)
	b.font = saved_font
	saved_font = b.font
	b.font = TITLE_9_FONT
	_cursor(b, MwGfx.s16(rom, TITLE_9_AT), MwGfx.s16(rom, TITLE_9_AT + 2))
	_write(b, MwGfx.rom_string(rom, TITLE_9), MwGfx.u16(rom, TITLE_9_AT + 4))
	b.font = saved_font
	var y := MwGfx.s16(rom, NUMBER_HEAD_AT + 2)
	var a := MwGfx.u16(rom, NUMBER_HEAD_AT + 4)
	_cursor(b, MwGfx.s16(rom, NUMBER_HEAD_AT), y)
	_write(b, MwGfx.rom_string(rom, NUMBER_HEAD), a)
	_cursor(b, 4, y)
	_write(b, MwGfx.rom_string(rom, MwGfx.u32(rom, PAGE_NAMES + 4 * page)), a)
	_cursor(b, MwGfx.s16(rom, COLUMN_X + 2 * page), y)
	_write(b, MwGfx.rom_string(rom, MwGfx.u32(rom, COLUMN_HEADS + 4 * page)), a)


## `$D446`: from row 9, 3 rows apart: pages 0-3 the line's 5 roster slots
## (team record +$18 + 24 * page), page 4 the 4 goalies (slot 5 of each
## line); each player's line (`$D4BA`) and stats (`$D5A6`); the footer.
func _rows_9(b: MwRinkState.TextBox, team: MwRinkState.Team) -> void:
	var roster := team.record + 0x18
	var a := roster
	row = FIRST_ROW
	var count := 0
	var stride := 0
	if MwRinkSim.s16(page) <= 3:
		a += 0x18 * page
		count = 5
		stride = 4
	elif page == 4:
		a += 0x14
		count = 4
		stride = 0x18
	else:
		return
	for i in count:
		_player_line(b, a)
		_player_stats(b, team, (a - roster) >> 2)
		row = (row + ROW_STEP) & 0xFFFF
		a += stride
	_cursor(b, 8, 0x18)
	_write(b, MwGfx.rom_string(rom, FOOTER), 0x60)


## `$D4BA`: the jersey number (two digits, font `$22BEC`) at (1, row); the
## name split at its first space: the first word at (4, row) (copied into
## `$FFC432`), the rest at (4, row + 1) - a one-word name only there.
func _player_line(b: MwRinkState.TextBox, slot: int) -> void:
	var player := MwGfx.u32(rom, slot)
	_number(rom[player + 4], 0, 2)
	saved_font = b.font
	b.font = NAME_FONT
	_cursor(b, 1, row)
	_write(b, _string_at(TEXTS), 0x60)
	b.font = saved_font
	_cursor(b, 4, row)
	var name := MwGfx.u32(rom, player)
	var sp := name
	while rom[sp] != 0 and rom[sp] != 0x20:
		sp += 1
	var rest := name
	if rom[sp] != 0:
		var at := 0
		for k in range(name, sp):
			_put(at, rom[k])
			at += 1
		_put(at, 0)
		rest = sp + 1
		_write(b, _string_at(TEXTS), 0x60)
	_cursor(b, 4, row + 1)
	_write(b, MwGfx.rom_string(rom, rest), 0x60)


## `$D5BA` (every page's routine in `$1D0CE`): the roster slot's entry
## (team +$3A2 + 8 * slot) right-aligned on row + 1: skaters +4 (G, at
## most two digits) to column 24, +6 (PTS) 29, +2 (SOG) 34, +0 (PIM) 39;
## goalies +4, max(+2 - +4, 0) (SAV), +2.
func _player_stats(b: MwRinkState.TextBox, team: MwRinkState.Team, slot: int) -> void:
	if MwGfx.u32(rom, PAGE_ROUTINES + 4 * page) != PLAYER_STATS:
		push_warning("MwStatsSim: page %d's routine is not $D5BA" % page)
	var entry := 0x3A2 + 8 * slot
	var goals := team_word(team, entry + 4)
	_number(goals, 0, 10)
	_right_aligned(b, 0x18)
	var values: Array[int] = []
	if page != 4:
		values.append(team_word(team, entry + 6))
		values.append(team_word(team, entry + 2))
		values.append(team_word(team, entry))
	else:
		values.append(maxi(MwRinkSim.s16(team_word(team, entry + 2) - goals), 0))
		values.append(team_word(team, entry + 2))
	var right := 0x1D
	for v in values:
		_number(v, 0)
		_right_aligned(b, right)
		right += 5


## The number just formatted (its [member _digits]) ending at column [param right].
func _right_aligned(b: MwRinkState.TextBox, right: int) -> void:
	_cursor(b, right - _digits, row + 1)
	_write(b, _string_at(TEXTS), 0x60)


## `$1580E`: the box's cursor.
static func _cursor(b: MwRinkState.TextBox, x: int, y: int) -> void:
	b.cursor_x = x & 0xFFFF
	b.cursor_y = y & 0xFFFF


## `text_box_write` `$15860`: [param text] from the box's cursor with
## [param attr]: words (runs of `!`-`~`) wrap to a new line when they do
## not fit and the line is not empty, spaces advance by the font's space,
## $0A starts a line, nothing is drawn from the box's bottom on (the cursor
## kept where it stopped). Each word is a "text" operation at its cells.
func _write(b: MwRinkState.TextBox, text: PackedByteArray, attr: int) -> void:
	var f := b.font & 0xFFFFFF
	var line := (MwGfx.u16(rom, f) + b.spacing) & 0xFFFF
	var space := MwGfx.u16(rom, f + 2)
	var ops := _ops_for(b.plane)
	var d1 := MwRinkSim.s16(b.cursor_x)
	var i := 0
	var ch := _at(text, i)
	while ch != 0:
		while ch < 0x21 or ch > 0x7E:
			if ch == 0x20:
				d1 = MwRinkSim.s16(d1 + space)
			elif ch == 0x0A:
				b.cursor_y = (b.cursor_y + line) & 0xFFFF
				d1 = 0
			i += 1
			ch = _at(text, i)
			if ch == 0:
				break
		var j := i
		var width := 0
		while ch >= 0x21 and ch <= 0x7E:
			width += MwGfx.char_width(rom, f, ch)
			j += 1
			ch = _at(text, j)
		if MwRinkSim.s16(d1 + width) > MwRinkSim.s16(b.w) and d1 != 0:
			b.cursor_y = (b.cursor_y + line) & 0xFFFF
			d1 = 0
		if (b.cursor_y & 0xFFFF) >= (b.h & 0xFFFF):
			b.cursor_x = d1 & 0xFFFF
			return
		if j > i:
			ops.append(["text", f, d1 + b.x, MwRinkSim.s16(b.cursor_y) + b.y, attr, text.slice(i, j)])
		d1 = MwRinkSim.s16(d1 + width)
		i = j
		ch = _at(text, i)
	b.cursor_x = d1 & 0xFFFF


static func _at(text: PackedByteArray, i: int) -> int:
	return text[i] if i < text.size() else 0


# --- comparison ----------------------------------------------------------------------------------

func compare(ram: PackedByteArray, stack: PackedByteArray) -> Array:
	var d := MwScoreboardSim.Diff.new(MwScoreboardSim.Mem.new(ram, stack))
	if tick_seen >= 0:
		d.long("tick $C3EE", 0xFFC3EE, tick_seen)
	d.long("saved font $C3F2", 0xFFC3F2, saved_font)
	d.long("box $C3F6", 0xFFC3F6, box_at)
	d.word("formatters $C3FA", 0xFFC3FA, formatter)
	d.word("scroll left $C3FC", 0xFFC3FC, scroll_left)
	d.word("scroll step $C3FE", 0xFFC3FE, scroll_step)
	d.word("page $C400", 0xFFC400, page)
	d.word("row $C402", 0xFFC402, row)
	d.byte("redraw $C404", 0xFFC404, redraw)
	d.byte("starfield on $C405", 0xFFC405, stars_on)
	for i in 2:
		_compare_box(d, (BOX_A if i == 0 else BOX_W) & 0xFFFFFF, boxes[i], "box %d" % i)
		_compare_label(d, LABELS + 0x12 * i, labels[i], "label %s" % ("A" if i == 0 else "B"))
	for i in TEXTS_SIZE:
		d.byte("strings $%X" % (TEXTS + i), TEXTS + i, texts[i])
	d.flag("sound $C472", HANDLE, handle != 0)
	d.word("plane A vscroll $B0DA", SCROLL_A, scroll_a)
	d.word("plane A hscroll $B0D6", HSCROLL_A, hscroll_a)
	d.word("plane B hscroll $B0D8", MwRinkRam.SCROLL_B, s.scroll_b.x)
	d.word("plane B vscroll $B0DC", MwRinkRam.SCROLL_B + 4, s.scroll_b.y)
	for k in 3:
		d.long("star pos %d" % k, STAR + 8 * k, star.pos[k])
		d.word("star vel %d" % k, STAR + 8 * k + 4, star.vel[k])
		d.word("star acc %d" % k, STAR + 8 * k + 6, star.acc[k])
	var params := [star_params.gravity, star_params.restitution, star_params.friction_ground, star_params.friction_air]
	params.append_array(Array(star_params.ground))
	params.append_array(Array(star_params.air))
	for i in params.size():
		d.word("star params +%d" % (2 * i), STAR_PARAMS + 2 * i, int(params[i]))
	d.long("aux rng $CA18", AUX, aux.state)
	d.handle("music handle $CA2C", MUSIC_HANDLE, music_handle >= 0)
	d.long("music track $CA30", MUSIC_TRACK, music_track)
	d.byte("music on $CA34", MUSIC_ON, music_on)
	d.word("music fade $CA36", MUSIC_FADE, music_fade)
	# nothing for the rink: the teams as they were
	d.ram_range(MwRinkRam.encode(s, ram), MwRinkRam.TEAMS[0], MwRinkRam.TEAMS[1] + 0x4AA)
	return d.out


static func _compare_box(d: MwScoreboardSim.Diff, a: int, b: MwRinkState.TextBox, what: String) -> void:
	d.long(what + " plane", a, b.plane)
	d.long(what + " font", a + 4, b.font)
	d.word(what + " x", a + 8, b.x)
	d.word(what + " y", a + 0xA, b.y)
	d.word(what + " w", a + 0xC, b.w)
	d.word(what + " h", a + 0xE, b.h)
	d.word(what + " spacing", a + 0x10, b.spacing)
	d.word(what + " cursor x", a + 0x12, b.cursor_x)
	d.word(what + " cursor y", a + 0x14, b.cursor_y)


static func _compare_label(d: MwScoreboardSim.Diff, a: int, l: Column, what: String) -> void:
	d.word(what + " x", a, l.x)
	d.word(what + " y", a + 2, l.y)
	d.word(what + " attr", a + 4, l.attr)
	d.long(what + " text", a + 6, l.text)
	d.long(what + " plane", a + 0xA, l.plane)
	d.long(what + " font", a + 0xE, l.font)
