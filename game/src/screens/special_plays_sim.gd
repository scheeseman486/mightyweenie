class_name MwSpecialPlaysSim
extends MwScreenSim
## Screen 10, special plays with the manual's Reserves page (`$11A18`; plan
## 11, docs/re/special-plays.md). Two page objects ([Page]; team A
## `$FFC64C`, team B `$FFC6DC`, `$90` bytes each) are little state machines
## run once per pass with their own pad's newly pressed buttons: the special
## plays (A the period's nasty play, B the highlighted special play, C the
## phony play - team +$4A5), the Reserves positions list (Reserves on), a
## position's substitution list (a line change: `player_create` `$7F8` in the
## on-ice slot, or the Demon Net in / out) and the done page. A team without
## a pad (team B in pad modes 0 / 2) gets the idle page instead, which shows
## team A's six on-ice players in side view playing rare random taunts (one
## `rng_next` per standing player per pass). When both pages are done the
## screen fades out and returns 5 (a faceoff) after a timeout (it was called
## from the rink: D7 <= 6), else the scoreboard it came from.
##
## Passes are the original's `$11A2E` loop, from one `dma_queue_wait`
## (`$1098E`) to the next: the exit test of the loop's tail first, then
## `read_joypads`, page A's handler, page B's handler, the sprites. [method
## enter] runs the set-up and the first pass (the handlers' set-ups). The
## original has no tick wait: a pass takes 3-8 ticks of CPU time, and the
## handlers that keep time (the idle page's animations, the substitution
## list's coach portrait) read the tick counter themselves ([method
## _read_tick]).
##
## Draws: [member window_ops] / [member plane_ops] as MwWindowPainter
## operations (the window holds every text: font `$447F4`, the highlighted
## item in `$1F958`, attr `$60`; plane B the backdrop pictures, [method
## pictures]); [member sprite_ops] in screen pixels (the window plane is the
## camera), in the original's order:
## * ["anim", record, variant, frame, x, y, depth, attr]: an animation
##   object's frame (`draw_anim_object` `$14444`: the idle page's players,
##   the substitution list's player figure);
## * ["portrait", x, y, depth, attr, animation, variant, frame, size]: the
##   coach portrait (`$B70C`, size 0: no border);
## * ["piece", piece, x, y, attr, depth]: one sprite piece (`$156C6`: the
##   A / B / C buttons of the plays page, the speech bubble's tail);
## * ["frame", frame, x, y, depth, attr]: a sprite frame (`draw_frame`
##   `$A07E`: the health bar, a dead player's figure, the Demon Net's, the
##   penalty box's bars);
## * ["sprite_text", font, x, y, attr, depth, string]: a jersey number as
##   sprites (`draw_text_sprites` `$F3CC`).
## Events: ["menu_music"] (`$13C6E`: the menus' tune unless it plays),
## ["fade_in", palette, line] (`fade_in_start` `$1498C`), ["sound", id,
## handle] (`$10968`: $25 cursor / choice / Start, $30 a line change, $2E
## refused; the coach's voices), ["voice_stop", handle] (`$13DC2`: the
## previous sound effect), ["music_fade", ticks] (`$13CAC`) and ["fade_out",
## ticks] at the exit.
##
## Quirks kept: a choice on the plays page empties and shows the sprite list
## at once (that pass's buttons never show); the plays are armed without
## any rule (a used play arms 0; Jail Break with nobody in the box); a dead
## candidate is refused but the list is made again (and the idle page told);
## `$10996` copies a text by its width in cells, not its characters.

const PAGES := [0xFFC64C, 0xFFC6DC]   ## the page objects
const MODE_RAM := 0xFFC646           ## 2 * the pad mode
const REFRESH_RAM := 0xFFC648        ## the idle page sets up its players again (after a line change)
const IDLE_E_RAM := 0xFFC64A         ## the idle page's elapsed ticks this pass
const SFX_RAM := 0xFFC76C            ## the last sound effect's handle
const NET_TOP := 0xFFB100            ## the top net object (rink state +$18)
const TEAM_WORDS := [0xB402, 0xB8AC]

## Plane B's backdrop (`$108EC` records: picture.l, then `map_copy`'s map.l,
## row bytes, VRAM, dest stride, src stride, rows): pad modes 0 / 2 (team B
## without a pad) the screen's picture in rows 0-13, its first row again in
## row 14, the line-up display's in rows 15-23; else the picture in 28 rows.
const BACKDROP_IDLE := [0x1F0D0, 0x1F0E2, 0x1F106]
const BACKDROP_FULL := [0x1F0F4]
const PLANE_B_VRAM := 0xE000
const ROW_BYTES := 0x80
const PALETTE := 0x1BE16             ## `fade_in_start` palette (line 3)
const FONT := 0x447F4
const FONT_CURSOR := 0x1F958         ## the highlighted item, the comment
const ATTR := 0x60
const BLANK := 0x5F                  ## `_`: the blank glyph `$10996` centres in
## Pseudo player records (name.l first): "Nobody" (an empty slot), "Demon Net".
const NOBODY := 0x1F000
const DEMON_NET := 0x1F00E
## The idle page's line-up stands behind the boards (attr $20: low priority
## under the advertising's high cells, last opaque row 178 - the
## scoreboards' backdrop 24 px higher, like the players). Frames reaching
## lower show a few stray pixels on the ice in the original (rows 179-182 in
## the recordings: stick blades, skates); ours cuts them from this row down,
## as the scoreboards' (owner: a non-behavioural cosmetic fix,
## docs/architecture.md Fidelity; [member MwScreenDraw.cut_rows]).
const BOARDS_BOTTOM := 179
## String pointers (longs) of the texts.
const T_ON_ICE := 0x1F01C
const T_PENALTY := 0x1F020
const T_PENALTY_BOX := 0x1F024
const T_UNDER_ICE := 0x1F028
const T_DECEASED := 0x1F02C
const T_NASTY := 0x1F030
const T_SPECIAL := 0x1F034
const T_HEALTH := 0x1F038
const T_PHONY := 0x1F03C
const T_PLAY := 0x1F040
const T_PEN := 0x1F044
const T_HURTIN := 0x1F048
const T_UNDER_THE_ICE := 0x1F04C
const T_DEAD := 0x1F050
const T_EVIL := 0x1F054
const T_ENFORCER := 0x1F058
const POSITIONS := 0x1F05C           ## 8 strings: C, LW, RW, LD, RD, G, none, SPECIAL PLAY
const PLAYS := 0x1F07C               ## play names by play number (0 "fake out")
const BUTTONS := 0x1F0AC             ## 3 sprite pieces (A, B, C), 6 bytes apart
const BUTTON_X := [0x34, 0xA0, 0x10C]
const FIGURES := 0x1143E             ## the substitution list's player figure animation by species
const FIGURE_DEAD := 0x3D5EC
const FIGURE_NET := 0x3D5D2
const BOX_BARS := 0x3D5B8
const HEALTH_BAR := 0x24516
const PORTRAIT_FRAME := 0x23BE6      ## the coach portrait's frame (a 7 x 8 window map)
const BUBBLE_TAIL := 0x1FB02
const COACHES := 0x1CD26             ## 20 x (coach record.l, portrait data.l, quote set.w)
const COACH_DEFAULT := 0x1CCA2
const QUOTES := 0x1D404
const PAD_A := 0x119FA               ## by 2 * pad mode: page A's second pad (byte offset in `$FFCA5A`)
const PAD_B := 0x11A04               ## page B's pads ($FFFF: none, the idle page)
const PAD_B2 := 0x11A0E
const SND_MOVE := 0x25
const SND_CHANGE := 0x30
const SND_REFUSED := 0x2E
const QUOTE_CATEGORY := 9            ## the coach's word on a player

## The page handlers (+$10): the set-ups store the per-pass handler.
const PLAYS_INIT := 0x117B4
const PLAYS_PASS := 0x1180C
const POSITIONS_INIT := 0x11896
const POSITIONS_PASS := 0x118CA
const SUBST_PASS := 0x1174A          ## set up by `$1161E` / `$11628`
const DONE_PASS := 0x1192C           ## set up by `$11914`
const IDLE_INIT := 0x1145A
const IDLE_PASS := 0x11520


## A page object (`$90` bytes; the handlers run with d6 / d7 / a3 / a4
## loaded from +0..+$F and saved back, a6 = the page).
class Page:
	var at := 0                      ## its RAM address
	var slot := 0                    ## +0 (d6): the on-ice slot being changed (= its position)
	var cursor := 0                  ## +4 (d7): the highlighted item (8: none, the done page)
	var player: MwRinkState.Player = null   ## +8 (a3): the slot's object (null: 0)
	var team_index := 0              ## +$C (a4): $FFFFB402 / $FFFFB8AC
	var team: MwRinkState.Team
	var handler := 0                 ## +$10
	var records := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])   ## +$14: the substitution list's records
	var items := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])     ## +$34: the items' strings (0: none, skipped)
	var comment := 0                 ## +$54: the comment's string (0: none yet)
	var quote_set := 0               ## +$58: the coach's quote set
	var row := 0                     ## +$5A: the page's rows on the window (A 0, B $D / $E)
	var new := 0                     ## +$5C: the pad's newly pressed buttons this pass
	var attr := 0                    ## +$5E: sprite attr (A $20, B $40)
	var done := 0                    ## +$60
	var portrait := MwScoreboardSim.Portrait.new()   ## +$62: the coach portrait
	var stamp := 0                   ## +$80: the tick of the last read (the portrait's / idle page's clock)
	var figure := MwAnimState.new()  ## +$84: the substitution list's player figure
	## What the original has written in this visit (the rest is a
	## previous visit's, not modelled).
	var known_items := false
	var known_comment := false
	var known_set := false
	var known_portrait := false
	var known_voice := false
	var known_stamp := false
	var known_figure := false

	func team_long() -> int:
		return 0xFFFF0000 | int(TEAM_WORDS[team_index])

	## Its fields against the original's (only what this visit wrote).
	func compare(d: MwScoreboardSim.Diff, name: String) -> void:
		d.long(name + " d6", at, slot)
		d.long(name + " d7", at + 4, cursor)
		d.long(name + " a3", at + 8, MwScoreboardSim.player_long(player))
		d.long(name + " team", at + 0xC, team_long())
		d.long(name + " handler", at + 0x10, handler)
		if known_items:
			for i in 8:
				d.long("%s record %d" % [name, i], at + 0x14 + 4 * i, records[i])
				d.long("%s item %d" % [name, i], at + 0x34 + 4 * i, items[i])
		if known_comment:
			d.long(name + " comment", at + 0x54, comment)
		if known_set:
			d.word(name + " quote set", at + 0x58, quote_set)
		d.word(name + " row", at + 0x5A, row)
		d.byte(name + " new", at + 0x5C, new)
		d.word(name + " attr", at + 0x5E, attr)
		d.word(name + " done", at + 0x60, done)
		if known_portrait:
			var p := at + 0x62
			d.anim(name + " portrait anim", p, portrait.anim, portrait.x0b)
			d.long(name + " portrait data", p + 0xC, portrait.data)
			d.word(name + " portrait +$10", p + 0x10, portrait.x10)
			d.word(name + " portrait mode", p + 0x12, portrait.mode)
			d.word(name + " portrait timer", p + 0x14, portrait.timer)
			d.word(name + " portrait size", p + 0x16, portrait.size)
			d.word(name + " portrait voices", p + 0x1C, portrait.voices)
			if known_voice:
				d.flag(name + " portrait voice", p + 0x18, portrait.handle != 0)
		if known_stamp:
			d.long(name + " stamp", at + 0x80, stamp)
		if known_figure:
			d.anim(name + " figure", at + 0x84, figure, 0)


var pages: Array[Page] = []
## `$FFC646`: 2 * the pad mode.
var mode2 := 0
## `$FFC648`: a line change was made (the idle page lines its players up again).
var refresh := 0
## `$FFC64A`: the idle page's ticks this pass.
var idle_e := 0
## `$FFC76C`: the last sound effect's handle (0: none).
var sfx := 0
## The rink's player code the screen calls ([MwSimPlayers]: `player_create`,
## `player_stop` / `player_play`, `player_in_box`, the position ratings).
var rink: MwRinkSim
var _known_refresh := false
var _known_idle_e := false
var _touched := {}                   ## players whose animation object was set (+$23 cleared)


func ported() -> bool:
	return true


## The pictures the set-up loads (`picture_load`) for pad mode [param mode].
static func pictures(rom_: PackedByteArray, mode: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for r in (BACKDROP_IDLE if mode == 0 or mode == 2 else BACKDROP_FULL):
		var pic := MwGfx.u32(rom_, r)
		if not pic in out:
			out.append(pic)
	return out


# --- set-up ------------------------------------------------------------------------------------

## `$11A18`'s set-up: `$10836` (the backdrop, the side view, the fade-in),
## the music, the pages (`$11966`), then the first pass (the handlers' own
## set-ups; they read no buttons).
func enter(state: MwRinkState, screen_id: int, from_screen: int) -> void:
	super.enter(state, screen_id, from_screen)
	begin_pass()
	rink = MwRinkSim.new(rom, s)
	rink.live = live()
	_touched.clear()
	_known_refresh = false
	_known_idle_e = false
	_backdrop()
	events.append(["menu_music"])
	sound_call(func() -> void: MwSound.music_game())   # `$11A20`
	_pages_setup()
	sfx = 0
	_pass([0, 0, 0, 0], [0, 0, 0, 0])


## `$10836`: the layout `$1F0BE` (plane B 64 x 32, the window 40 x 28, no
## plane A), both cleared (`$146D6`), the backdrop's maps on plane B, plane
## B's scroll 0, the fade-in (palette `$1BE16` on line 3), the side view on
## (`$FFBDBA`).
func _backdrop() -> void:
	plane_ops.append(["fill", 0, 0, 64, 32, 0])
	window_ops.append(["fill", 0, 0, 40, 28, 0])
	for r in (BACKDROP_IDLE if s.pad_mode == 0 or s.pad_mode == 2 else BACKDROP_FULL):
		var a: int = r + 4
		var at := MwGfx.u16(rom, a + 6) - PLANE_B_VRAM
		plane_ops.append(["map", MwGfx.u32(rom, a), MwGfx.u16(rom, a + 10) / 2, MwGfx.u16(rom, a + 4) / 2,
				MwGfx.u16(rom, a + 12), (at % ROW_BYTES) / 2, at / ROW_BYTES])
	s.scroll_b = Vector2i.ZERO
	events.append(["fade_in", PALETTE, 3])
	s.projection = 1


## `$11966`: page A for team A (attr $20, rows from 0): the special plays,
## or the positions with Reserves on; page B for team B (attr $40, rows
## from 14) idle and done, unless team B has a pad (pad modes 1, 3, 4: rows
## from 13, page A's set-up, not done).
func _pages_setup() -> void:
	pages.clear()
	for t in 2:
		var p := Page.new()
		p.at = PAGES[t]
		p.team_index = t
		p.team = s.teams[t]
		p.attr = 0x20 if t == 0 else 0x40
		p.row = 0 if t == 0 else 0xE
		pages.append(p)
	var a := pages[0]
	var b := pages[1]
	a.handler = POSITIONS_INIT if s.reserves else PLAYS_INIT
	b.done = 1
	b.handler = IDLE_INIT
	mode2 = 2 * (s.pad_mode & 0xFF)
	if s.pad_mode != 0 and s.pad_mode != 2:
		b.row = 0xD
		b.done = 0
		b.handler = a.handler


# --- the pass ----------------------------------------------------------------------------------

## A pass (see the class description): the loop's exit when both pages are
## done (the music and the screen faded out, the side view off: `$10902`),
## else `read_joypads` and both pages. Returns the screen to leave for: 5
## after a timeout (called from the rink, D7 <= 6), else the one it came
## from.
func step(_elapsed: int, held: Array, new: Array) -> int:
	if pages[0].done != 0 and pages[1].done != 0:
		fade_music(FADE_OUT)                    # `$11AB8`
		fade_out(FADE_OUT)
		s.projection = 0
		return 5 if from <= 6 else from     # (`bhi`: unsigned; D7 is never negative)
	_pass(held, new)
	return -1


## `$11A2E`..`$11A9C`: the pads read, page A's handler with its pads (P1, and
## the table `$119FA`'s), page B's (`$11A04` | `$11A0E`; none: 0), the
## sprites shown.
func _pass(held: Array, new: Array) -> void:
	MwScoreboardSim.read_pads(s, held, new)
	var a := pages[0]
	a.new = (int(new[0]) | _pad_byte(held, new, MwGfx.u16(rom, PAD_A + mode2), s.tick)) & 0xFF
	_run(a)
	var b := pages[1]
	b.new = 0
	var off := MwGfx.u16(rom, PAD_B + mode2)
	if off != 0xFFFF:
		b.new = (_pad_byte(held, new, off, s.tick) | _pad_byte(held, new, MwGfx.u16(rom, PAD_B2 + mode2), s.tick)) & 0xFF
	_run(b)


## The byte at `$FFCA5A` + [param off] (the tables hold odd offsets: a
## pad's newly pressed byte). Pad mode 5 (CPU vs CPU: the attract's, where
## this screen cannot be reached) reads past the tables' ends: page A's
## offset -1 is the tick counter's low byte (`$FFCA59`: page A sees random
## "presses"; page B gets none and never finishes, as on the original);
## any other offset outside the pads reads 0 here.
static func _pad_byte(held: Array, new: Array, off: int, tick := 0) -> int:
	var o := MwRinkSim.s16(off)
	if o == -1:
		return tick & 0xFF
	if o < 0 or o >= 8:
		return 0
	return (int(new[o >> 1]) if o & 1 else int(held[o >> 1])) & 0xFF


## A page's handler.
func _run(p: Page) -> void:
	match p.handler:
		PLAYS_INIT:
			_plays_init(p)
		PLAYS_PASS:
			_plays(p)
		POSITIONS_INIT:
			_positions_init(p)
		POSITIONS_PASS:
			_positions(p)
		SUBST_PASS:
			_subst(p)
		DONE_PASS:
			_done(p)
		IDLE_INIT:
			_idle_init(p)
		IDLE_PASS:
			_idle(p)
		_:
			push_warning("MwSpecialPlaysSim: unknown page handler $%X" % p.handler)


## `$10968`: the last sound effect stopped (`$13DC2`), [param id] started,
## its handle kept (`$FFC76C`).
func _sfx(id: int) -> void:
	voice_stop(sfx)                             # `$1096E`
	sfx = sound(id)                             # `$10976`


## The tick counter as a page handler's read sees it (`$FFCA56`). The
## passes are CPU-bound (no tick wait): the VBlank can fall anywhere in
## them, so the checks answer with what the original stored from that read
## (the hooks' `stored_long`: the page's +$80 at the next pass boundary);
## live play reads the counter ([method MwScreenSim.now]).
func _read_tick(p: Page) -> int:
	if hooks != null and hooks.has_method("stored_long"):
		return int(hooks.call("stored_long", self, p.at + 0x80)) & 0xFFFFFFFF
	return now() & 0xFFFFFFFF


# --- the special plays page ------------------------------------------------------------------------

## `$117B4`: the three special plays of the team (+$333..+$335: their names
## `$1F07C`, items 1, 3, 5; a used one is 0, "fake out"), the page's areas
## cleared, the cursor on the first.
func _plays_init(p: Page) -> void:
	p.new = 0
	p.handler = PLAYS_PASS
	_clear_items(p)
	for i in 3:
		p.items[1 + 2 * i] = MwGfx.u32(rom, PLAYS + 4 * p.team.x330[3 + i])
	_clear_heads(p)
	_clear_list(p)
	_side_panels(p, 0x6015)
	p.cursor = 1


## `$1180C`: the cursor, the page drawn (`$10E30`); then A arms the
## period's nasty play (team +$330 + period - 1; none in overtime), B the
## highlighted special play, C nothing (the phony play: one armed before is
## disarmed), Start leaves it - each to the positions (Reserves on, cursor
## on SPECIAL PLAY) or done. No rule is checked here (a used play arms 0).
func _plays(p: Page) -> void:
	_cursor(p)
	_draw_plays(p)
	var b := p.new
	if b & 0x70:
		var play := 0
		if b & 0x40:
			play = _nasty_play(p.team)
		elif b & 0x10:
			play = p.team.x330[3 + (p.cursor >> 1)]
		p.team.special = play & 0xFF
	elif not b & 0x80:
		return
	_sfx(SND_MOVE)
	sprite_ops.clear()               # `$1568E` / `$157B0` / `$148A8`: the sprites emptied and shown
	if not s.reserves:
		_done_init(p)
	else:
		p.cursor = 7
		_positions_init(p)


## The period's nasty play (team +$330 + `$FFB076` - 1; 0 from overtime on).
func _nasty_play(team: MwRinkState.Team) -> int:
	var d1 := MwRinkSim.s16((s.period & 0xFF) - 1)
	if d1 >= 3:
		return 0
	if d1 < 0:
		return team.players[5].flags2 & 0xFF      # +$32F (no period 0)
	return team.x330[d1]


## `$10E30`: the list, the team's city and name (Reserves on: "SPECIAL" /
## "PLAY"), "NASTY PLAY" and "PHONY PLAY" with the period's nasty play and
## "fake out" under them, the A / B / C buttons.
func _draw_plays(p: Page) -> void:
	var r := p.row
	_list(p)
	if not s.reserves:
		_centred(FONT, 13, 2 + r, 14, _rom_text(MwGfx.u32(rom, p.team.record)))
		_centred(FONT, 13, 3 + r, 14, _rom_text(MwGfx.u32(rom, p.team.record + 4)))
	else:
		_centred(FONT, 13, 2 + r, 14, _rom_text(MwGfx.u32(rom, T_SPECIAL)))
		_centred(FONT, 13, 3 + r, 14, _rom_text(MwGfx.u32(rom, T_PLAY)))
	_text(FONT, 3, 2 + r, MwGfx.u32(rom, T_NASTY))
	_text(FONT, 3, 3 + r, MwGfx.u32(rom, T_PLAY))
	_text(FONT, 30, 2 + r, MwGfx.u32(rom, T_PHONY))
	_text(FONT, 30, 3 + r, MwGfx.u32(rom, T_PLAY))
	_lines(FONT, 3, 7 + r, 7, 3, _rom_text(MwGfx.u32(rom, PLAYS + 4 * _nasty_play(p.team))))
	_lines(FONT, 30, 7 + r, 7, 3, _rom_text(MwGfx.u32(rom, PLAYS)))
	for k in 3:
		sprite_ops.append(["piece", BUTTONS + 6 * k, BUTTON_X[k], (11 + r) * 8, 0xE0, 0])


# --- the positions page (Reserves) ---------------------------------------------------------------

## `$11896`: the positions (`$1F05C`), the page's areas cleared; the cursor
## as the caller left it.
func _positions_init(p: Page) -> void:
	p.new = 0
	p.handler = POSITIONS_PASS
	for i in 8:
		p.items[i] = MwGfx.u32(rom, POSITIONS + 4 * i)
		p.records[i] = 0
	p.known_items = true
	_clear_heads(p)
	_clear_list(p)
	_side_panels(p, 0)


## `$118CA`: the cursor, the page drawn (`$10F8A`); Start: done; A / B / C:
## SPECIAL PLAY -> the special plays page, a position -> its substitution
## list (the slot's object in a3).
func _positions(p: Page) -> void:
	_cursor(p)
	_draw_positions(p)
	if p.new & 0x80:
		_sfx(SND_MOVE)
		_done_init(p)
		return
	p.new &= 0x70
	if p.new == 0:
		return
	_sfx(SND_MOVE)
	if p.cursor == 7:
		p.player = null
		p.slot = 0
		_plays_init(p)
		return
	p.slot = p.cursor
	p.player = p.team.players[p.slot]
	_subst_init(p)


## `$10F8A` (positions, done): the list, the team's city and name, "ON ICE:"
## with the players on the ice (`$3B6C`), "PENALTY" with the penalty box's
## count (`$A23A`).
func _draw_positions(p: Page) -> void:
	var r := p.row
	_list(p)
	_centred(FONT, 13, 2 + r, 14, _rom_text(MwGfx.u32(rom, p.team.record)))
	_centred(FONT, 13, 3 + r, 14, _rom_text(MwGfx.u32(rom, p.team.record + 4)))
	_text(FONT, 3, 2 + r, MwGfx.u32(rom, T_ON_ICE))
	var n := 0
	for q in p.team.players:
		if q.record != 0:
			n += 1
	_centred(FONT, 3, 3 + r, 7, _digits(n))
	_text(FONT, 30, 2 + r, MwGfx.u32(rom, T_PENALTY))
	_centred(FONT, 30, 3 + r, 7, _digits(MwRinkSim.s8(p.team.stat(0x39F, 1))))


# --- the substitution list ---------------------------------------------------------------------------

## `$1161E`: the page's areas cleared, the coach portrait's frame, then the
## list (`$11628`).
func _subst_init(p: Page) -> void:
	_clear_heads(p)
	_side_panels(p, 0x6015)
	var at := (p.row << 7) + 0x286
	window_ops.append(["map", PORTRAIT_FRAME, 7, 7, 8, (at % ROW_BYTES) / 2, at / ROW_BYTES])
	_subst_list(p)


## `$11628`: the list area cleared, the coach portrait (`$10C54`), the
## comment none; item 0 the slot's status ("ON ICE:", "PENALTY BOX:",
## "DECEASED:", "UNDER ICE:"), item 1 its player ("Nobody" / "Demon Net"
## for an empty slot), from item 3 the position's players of every line
## that are not on the ice, then (only when the slot's player plays his own
## position, or is no roster player) one more (`$11158`). The cursor on 1.
func _subst_list(p: Page) -> void:
	var team := p.team
	_clear_list(p)
	_coach(p)
	p.comment = 0
	p.known_comment = true
	p.new = 0
	p.handler = SUBST_PASS
	_clear_items(p)
	p.items[0] = MwGfx.u32(rom, T_ON_ICE)
	var a0 := p.player.original
	if a0 == 0:
		a0 = DEMON_NET if p.slot == 5 and _demon_net_in(team) else NOBODY
	else:
		var i := _roster_index(team, a0)
		if i >= 0:
			if team.health[i] & 0xFFFFFFFF == 0:
				p.items[0] = MwGfx.u32(rom, T_DECEASED)
				if _under_ice(team, i):
					p.items[0] = MwGfx.u32(rom, T_UNDER_ICE)
			elif rink.players._in_box(team, i):
				p.items[0] = MwGfx.u32(rom, T_PENALTY_BOX)
	p.records[1] = a0
	p.items[1] = MwGfx.u32(rom, a0)
	var n := 3
	for line in 4:
		var r := MwGfx.u32(rom, team.record + 0x18 + 0x18 * line + 4 * p.slot)
		var on := false
		for q in team.players:
			if q.original == r:
				on = true
		if not on:
			p.records[n] = r
			p.items[n] = MwGfx.u32(rom, r)
			n += 1
	var own := _roster_index(team, p.player.original)
	if own < 0 or own % 6 == p.slot:
		var extra := _best_other(p)
		if extra != 0:
			p.records[n] = extra
			p.items[n] = MwGfx.u32(rom, extra)
	p.cursor = 1


## `$11158`: the extra candidate. For the goalie the Demon Net, when the
## team attacks down (+4 bit 1), has it (+4 bit 3) and it is not in yet
## (`$7A6`); for a skater the best player of another skater position (the
## goalies and the slot's own position skipped): not in the box, not on the
## ice (skater slots), alive; score = his rating at the slot's position
## (`$1121E`) x min(health's high word, $40), the first maximum. 0: none.
func _best_other(p: Page) -> int:
	var team := p.team
	if p.slot == 5:
		if _demon_net_in(team) or team.flags4 & 2 == 0 or team.flags4 & 8 == 0:
			return 0
		return DEMON_NET
	var best := 0
	var pick := 0
	for i in 24:
		var pos := i % 6
		if pos == 5 or pos == p.slot or rink.players._in_box(team, i):
			continue
		var r := MwGfx.u32(rom, team.record + 0x18 + 4 * i)
		var on := false
		for k in 5:
			if team.players[k].original == r:
				on = true
		if on:
			continue
		var score := rink.players._position_rating(r, p.slot)
		var h := team.health[i] & 0xFFFFFFFF
		if h == 0:
			continue
		var hw := (h >> 16) & 0xFFFF
		if MwRinkSim.s16(hw) >= 0x40:
			hw = 0x40
		score = (score * hw) & 0xFFFF
		if MwRinkSim.s16(best) >= MwRinkSim.s16(score):
			continue
		best = score
		pick = r
	return pick


## `$1174A`: the cursor (again while it lands on the status, item 0);
## Start: back to the positions with the cursor on the slot; else the page
## drawn (`$10D74`), and A / B / C: refused (sound $2E) while the slot's
## player sits in the penalty box; on item 1 nothing; else the change
## (`$11242`), the list made again and the idle page told (`$FFC648`).
func _subst(p: Page) -> void:
	_cursor(p)
	while p.cursor == 0 and p.new & 0xF:
		_cursor(p)
	if p.new & 0x80:
		_draw_back(p)
		_sfx(SND_MOVE)
		p.cursor = p.slot
		_positions_init(p)
		return
	_draw_subst(p)
	p.new &= 0x70
	if p.new == 0:
		return
	var team := p.team
	var i := _roster_index(team, team.players[p.slot].original)
	if i >= 0 and rink.players._in_box(team, i):
		_sfx(SND_REFUSED)
		return
	if p.cursor == 1:
		_sfx(SND_MOVE)
		return
	_change(p)
	_subst_list(p)
	refresh = 1
	_known_refresh = true


## `$11242`: the highlighted candidate in. The Demon Net: the top net's
## style 0 (`$7C0`), the slot emptied (`player_create` of no record); a
## dead / under-the-ice player: refused (sound $2E); else `player_create`
## (`$7F8`: one `rng_next`) in the slot - position and slot the slot's, the
## player's roster slot - and a goalie put in takes the Demon Net out
## (`$7D2`: the stadium's style). Sound $30.
func _change(p: Page) -> void:
	var team := p.team
	var a0 := p.records[p.cursor]
	if a0 == DEMON_NET:
		MwRinkMatch.set_top_net(rink, 0)
		rink.players.create(p.player, team, 5, 0, 5, 0)
		_sfx(SND_CHANGE)
		return
	var i := _roster_index(team, a0)
	var rec := 0
	if i >= 0:
		if team.health[i] & 0xFFFFFFFF == 0:
			_sfx(SND_REFUSED)
			return
		rec = MwGfx.u32(rom, team.record + 0x18 + 4 * i)
	rink.players.create(p.player, team, p.slot, i & 0xFF, p.slot, rec)
	if p.slot == 5 and _demon_net_in(team):
		MwRinkMatch.set_top_net(rink, rom[MwRinkState.stadium_record(rom, s.stadium) + 5])
	_sfx(SND_CHANGE)


## `$10D74`: the list, the position's name, the comment (made once per
## cursor position, `$10B92`); without one: the portrait drawn, its clock
## stamped, the speech area cleared; with one: the health bar, the player
## figure, the speech frame with the comment, the portrait talking.
func _draw_subst(p: Page) -> void:
	var r := p.row
	_list(p)
	_lines(FONT, 13, 2 + r, 14, 2, _rom_text(MwGfx.u32(rom, POSITIONS + 4 * p.slot)))
	if p.comment == 0:
		p.comment = _comment(p)
		p.known_comment = true
		if p.comment == 0:
			_portrait_draw(p)
			p.stamp = _read_tick(p)
			p.known_stamp = true
			_fill(28, 1 + r, 11, 4, 0)
			return
	_health(p)
	_figure(p)
	MwScoreboardSim.speech_frame(self, PackedInt32Array([29, 2 + r, 9, 2]), false)
	var text: PackedByteArray = s.quote.slice(0, maxi(s.quote.find(0), 0)) if p.comment == 0xFFFFC4FE \
			else _rom_text(p.comment)
	_lines(FONT_CURSOR, 29, 2 + r, 9, 2, text)
	_portrait_pass(p)


## `$10D32` (Start on the substitution list): the list, the position's
## name, the portrait, its clock stamped, the speech area cleared.
func _draw_back(p: Page) -> void:
	var r := p.row
	_list(p)
	_lines(FONT, 13, 2 + r, 14, 2, _rom_text(MwGfx.u32(rom, POSITIONS + 4 * p.slot)))
	_portrait_draw(p)
	p.stamp = _read_tick(p)
	p.known_stamp = true
	_fill(28, 1 + r, 11, 4, 0)


## `$10B92`: the comment on the highlighted candidate: "IT'S EVIL" (the
## Demon Net), none (not a roster player), "UNDER THE ICE", "HE'S IN THE
## PEN", "HE'S DEAD", "HE'S HURTIN'" (health's high word below $40), "HE'S
## AN ENFORCER", else the coach's word (`$F420` category 9: his quote set,
## the player's line, the string by the record's word +4 - no RNG).
func _comment(p: Page) -> int:
	var team := p.team
	var a0 := p.records[p.cursor]
	if a0 == 0:
		return 0
	if a0 == DEMON_NET:
		return MwGfx.u32(rom, T_EVIL)
	var i := -1
	for k in 24:
		if MwGfx.u32(rom, team.record + 0x18 + 4 * k) == a0:
			i = k
			break
	if i < 0:
		return 0
	if _under_ice(team, i):
		return MwGfx.u32(rom, T_UNDER_THE_ICE)
	if rink.players._in_box(team, i):
		return MwGfx.u32(rom, T_PEN)
	var h := team.health[i] & 0xFFFFFFFF
	if h == 0:
		return MwGfx.u32(rom, T_DEAD)
	if MwRinkSim.s16(h >> 16) < 0x40:
		return MwGfx.u32(rom, T_HURTIN)
	if rom[a0 + 0xD] >> 4 != 0:
		return MwGfx.u32(rom, T_ENFORCER)
	return _coach_word(p.quote_set, i / 6, a0, team)


## `$F420` for category 9: the set's string picked by the record's word +4
## (no RNG). A set of one string (or none) is expanded into `$FFC4FE`
## instead ([method MwScoreboardSim.quote_pick]; none in the ROM).
func _coach_word(set: int, line: int, record: int, team: MwRinkState.Team) -> int:
	var t := MwGfx.u32(rom, QUOTES + 4 * QUOTE_CATEGORY)
	t = MwGfx.u32(rom, t + 4 * (line & 0xFFFF))
	t = MwGfx.u32(rom, t + 4 * (set & 0xFFFF))
	var count := MwGfx.u16(rom, t + 2)
	if count <= 1:
		return MwScoreboardSim.quote_pick(self, set, QUOTE_CATEGORY, line, team, team, record)
	return MwGfx.u32(rom, t + 4 + 4 * (MwGfx.u16(rom, record + 4) % count))


## `$10CD4`: a roster candidate's health bar (`$24516` at x $60 + health *
## $38 / 128 in sprite coordinates, row 2) and "HEALTH:".
func _health(p: Page) -> void:
	var i := _roster_index(p.team, p.records[p.cursor])
	if i < 0:
		return
	var hw := (p.team.health[i] >> 16) & 0xFFFF
	var x := ((((hw * 0x38) & 0xFFFF) >> 7) + 0x60) & 0xFFFF
	sprite_ops.append(["frame", HEALTH_BAR, MwRinkSim.s16(x - 0x80), (2 + p.row) * 8, 0, 0x60])
	_text(FONT, 3, 2 + p.row, MwGfx.u32(rom, T_HEALTH))


## `$11316`: the candidate's figure: a dead player's (not under the ice) or
## the Demon Net's; else his jersey number as sprites and his species'
## figure animation (`$1143E`, variant 4, +$84) - with the box's bars over
## it while he is in the penalty box.
func _figure(p: Page) -> void:
	var team := p.team
	var r := p.row
	var a0 := p.records[p.cursor]
	var i := _roster_index(team, a0)
	if i >= 0 and not _under_ice(team, i) and team.health[i] & 0xFFFFFFFF == 0:
		sprite_ops.append(["frame", FIGURE_DEAD, 0x34, (10 + r) * 8 + 4 - 0x10, 0, 0x20])
		return
	var species := rom[a0 + 7] & 0xF
	if species == 6:
		sprite_ops.append(["frame", FIGURE_NET, 0x34, (10 + r) * 8 + 4 - 0x10, 0, 0x20])
		return
	var number := rom[a0 + 4] & 0xFF
	sprite_ops.append(["sprite_text", FONT, 0x2C, (5 + r) * 8 + 1, 0xE0, 0,
			PackedByteArray([0x30 + number / 10, 0x30 + number % 10])])
	p.figure = MwAnimState.from_record(rom, MwGfx.u32(rom, FIGURES + 4 * species), 4)
	p.known_figure = true
	sprite_ops.append(MwScoreboardSim.anim_op(p.figure, 0x34, (10 + r) * 8 + 4, 0, p.attr))
	if rink.players._in_box(team, i):
		sprite_ops.append(["frame", BOX_BARS, 0x18, (7 + r) * 8 + 1 - 0x10, 0, 0x20])


## `$10C54`: the coach portrait of the team's coach (record +$C; `$B6D2`
## with size 0: no border; its quote set +$58), talking (`$B542`), its
## clock stamped.
func _coach(p: Page) -> void:
	var pt := p.portrait
	var coach := MwGfx.u32(rom, p.team.record + 0xC)
	pt.size = 0
	pt.x10 = 0
	pt.data = COACH_DEFAULT
	p.quote_set = MwGfx.u16(rom, 4)
	for i in 20:
		var a := COACHES + 10 * i
		if MwGfx.u32(rom, a) == coach:
			pt.data = MwGfx.u32(rom, a + 4)
			p.quote_set = MwGfx.u16(rom, a + 8)
			break
	p.known_set = true
	pt.start(rom, 0)
	p.known_portrait = true
	p.stamp = _read_tick(p)
	p.known_stamp = true


## `$10C7C`: the portrait's ticks since the last stamp (`$B572`), the speech
## bubble's tail, the portrait drawn.
func _portrait_pass(p: Page) -> void:
	var t := _read_tick(p)
	var e := (t - p.stamp) & 0xFFFF
	p.stamp = t
	var before := p.portrait.handle
	p.portrait.advance(self, e)
	if p.portrait.handle != before:
		p.known_voice = true
	sprite_ops.append(["piece", BUBBLE_TAIL, 0x120, ((4 + p.row) << 3) + 1, 0xE0, 0])
	_portrait_draw(p)


## `$10CAE`: the coach portrait at ($F0, row 5 + 1 px).
func _portrait_draw(p: Page) -> void:
	p.portrait.draw(self, 0xF0, ((5 + p.row) << 3) + 1, 0, p.attr)


# --- the done page --------------------------------------------------------------------------------

## `$11914`: done (+$60), nothing highlighted.
func _done_init(p: Page) -> void:
	p.new = 0
	p.handler = DONE_PASS
	p.cursor = 8
	p.done = 1


## `$1192C`: drawn as the positions page; Start: stays done; any other
## button: not done, back to the positions (cursor 0) or, Reserves off, the
## special plays.
func _done(p: Page) -> void:
	_draw_positions(p)
	if p.new & 0x80:
		_sfx(SND_MOVE)
		_done_init(p)
		return
	p.new &= 0x7F
	if p.new == 0:
		return
	_sfx(SND_MOVE)
	p.done = 0
	if s.reserves:
		p.cursor = 0
		_positions_init(p)
	else:
		_plays_init(p)


# --- the idle page (team B without a pad) ------------------------------------------------------------

## `$1145A` (page B): its clock stamped, `$FFC648` cleared; page A's team's
## on-ice players stopped (`player_stop`), facing the camera (variant 4).
func _idle_init(p: Page) -> void:
	p.handler = IDLE_PASS
	refresh = 0
	_known_refresh = true
	p.stamp = _read_tick(p)
	p.known_stamp = true
	for q in pages[0].team.players:
		if q.record != 0:
			rink.players.stop(q)
			q.anim.variant = 4
			_touched[q] = true


## `$11520` (page B): set up again after a line change; else the ticks since
## the stamp (`$FFC64A`) and page A's team's players: one whose animation
## stopped rolls a taunt (`$114CC`), the animation advanced, drawn at (50 +
## 45 * slot, 164) in page A's attr - not the goalie while page A's item 5 is
## the Demon Net.
func _idle(p: Page) -> void:
	if refresh != 0:
		_idle_init(p)
		return
	var t := _read_tick(p)
	idle_e = (t - p.stamp) & 0xFFFF
	_known_idle_e = true
	if idle_e != 0:
		p.stamp = t
	var a := pages[0]
	var x := 0x32
	for i in 6:
		var q := a.team.players[i]
		if q.record != 0:
			if i == 5 and a.records[5] == DEMON_NET:
				break
			if not q.anim.playing():
				MwScoreboardSim.taunt_roll(self, rink.players, q)
				_touched[q] = true
			q.anim.advance(idle_e)
			var op := MwScoreboardSim.anim_op(q.anim, x, 0xA4, 0, a.attr)
			op.append(BOARDS_BOTTOM)            # behind the boards: nothing below them (owner)
			sprite_ops.append(op)
		x += 0x2D


# --- helpers ---------------------------------------------------------------------------------------

## `$112BA`: Down / Right the next non-empty item (wrapping at 8), Up / Left
## the previous (Down first, then Up, Left, Right); a move plays sound $25
## and clears the comment.
func _cursor(p: Page) -> void:
	var b := p.new
	var dir := 0
	if b & 0x02:
		dir = 1
	elif b & 0x05:
		dir = -1
	elif b & 0x08:
		dir = 1
	if dir == 0:
		return
	_sfx(SND_MOVE)
	p.comment = 0
	p.known_comment = true
	for _k in 8:
		p.cursor += dir
		if p.cursor >= 8:
			p.cursor = 0
		elif p.cursor < 0:
			p.cursor = 7
		if p.items[p.cursor] != 0:
			return


## Items and records cleared (+$14..+$53).
func _clear_items(p: Page) -> void:
	for i in 8:
		p.items[i] = 0
		p.records[i] = 0
	p.known_items = true


## `$10A58`: the head areas cleared: (3, 2) 7 x 2, (13, 2) 14 x 2, then
## `$10A50`'s (28, 1) 11 x 4.
func _clear_heads(p: Page) -> void:
	_fill(3, 2 + p.row, 7, 2, 0)
	_fill(13, 2 + p.row, 14, 2, 0)
	_fill(28, 1 + p.row, 11, 4, 0)


## `$10ABC` / `$10AC4`: the side panels (3, 5) and (30, 5), 7 x 8, filled
## with [param cell] ($6015 / 0).
func _side_panels(p: Page, cell: int) -> void:
	_fill(3, 5 + p.row, 7, 8, cell)
	_fill(30, 5 + p.row, 7, 8, cell)


## `$10B0E`: the list area (13, 5) 14 x 8 cleared.
func _clear_list(p: Page) -> void:
	_fill(13, 5 + p.row, 14, 8, 0)


## `$10B36`: the non-empty items centred in 14 cells from (13, 5), the
## cursor's in the dark font.
func _list(p: Page) -> void:
	for i in 8:
		if p.items[i] == 0:
			continue
		_centred(FONT_CURSOR if i == p.cursor else FONT, 13, 5 + p.row + i, 14, _rom_text(p.items[i]))


func _fill(x: int, y: int, w: int, h: int, cell: int) -> void:
	window_ops.append(["fill", x, y, w, h, cell])


## `$109F8`: a ROM string at ([param x], [param y]) on the window.
func _text(font: int, x: int, y: int, text: int) -> void:
	window_ops.append(["text", font, x, y, ATTR, text])


## The string at ROM [param a] (without its 0).
func _rom_text(a: int) -> PackedByteArray:
	return MwGfx.rom_string(rom, a)


## `$B7E8`: [param v] as two digits (the tens a space when 0).
static func _digits(v: int) -> PackedByteArray:
	var w := v & 0xFFFF
	var tens := 0x30 + w / 10
	return PackedByteArray([0x20 if tens == 0x30 else tens & 0xFF, 0x30 + w % 10])


## `$10996`: [param text] centred in a field of [param width] blank glyphs
## (`_`) at ([param x], [param y]) - its spaces left blank, so a redraw
## erases what was there; a text wider than the field starts at its left.
## The copy counts the text's width in cells, not its characters (a 0
## copied ends the drawn string).
func _centred(font: int, x: int, y: int, width: int, text: PackedByteArray) -> void:
	var buf := PackedByteArray()
	buf.resize(width + 1)
	buf.fill(BLANK)
	buf[width] = 0
	var w := MwGfx.text_width(rom, font, text)
	var src := text.duplicate()
	src.append(0)
	var at := 0
	var count := w
	var room := MwRinkSim.s16(width - w)
	if room >= 0:
		at = room >> 1
		count = w - 1
	var k := 0
	while true:
		var c := src[k] if k < src.size() else 0
		k += 1
		if c != 0x20:
			buf[at] = c
		at += 1
		if buf[at] == 0:
			break
		count = (count - 1) & 0xFFFF
		if count == 0xFFFF:
			break
	window_ops.append(["text", font, x, y, ATTR, buf.slice(0, buf.find(0))])


## `$10A08`: [param text] word by word, one word a line (at most [param
## lines]), each centred ([method _centred]) from row [param y] down; a word
## longer than the field is cut. Rows after the text's end are not drawn.
func _lines(font: int, x: int, y: int, width: int, lines: int, text: PackedByteArray) -> void:
	var src := text.duplicate()
	src.append(0)
	var k := 0
	var buf := PackedByteArray()
	buf.resize(width + 2)
	var left := lines
	while left > 0:
		left -= 1
		var at := 0
		var count := width
		var ended := false
		while true:
			var c := src[k] if k < src.size() else 0
			k += 1
			buf[at] = c
			if c == 0:
				ended = true
				break
			at += 1
			if c == 0x20:
				break
			count -= 1
			if count < 0:
				break
		if not ended:
			buf[at - 1] = 0
		else:
			left = 0
		_centred(font, x, y, width, buf.slice(0, buf.find(0)))
		y += 1


## `$10B7A`: [param record]'s roster slot in [param team] (searched from the
## last), -1 if none.
func _roster_index(team: MwRinkState.Team, record: int) -> int:
	for i in range(23, -1, -1):
		if MwGfx.u32(rom, team.record + 0x18 + 4 * i) == record:
			return i
	return -1


## Team +$336 (a long): roster slot [param i] fell through the ice.
static func _under_ice(team: MwRinkState.Team, i: int) -> bool:
	var v := (team.x330[6] << 24) | (team.x330[7] << 16) | (team.x330[8] << 8) | team.x330[9]
	return v & (1 << (i & 31)) != 0


## `$7A6`: the Demon Net guards the top net for [param team] (it attacks
## down and the top net's style is 0).
func _demon_net_in(team: MwRinkState.Team) -> bool:
	return team.flags4 & 2 != 0 and s.nets[0].style == 0


# --- comparison --------------------------------------------------------------------------------------

func compare(ram: PackedByteArray, stack: PackedByteArray) -> Array:
	var d := MwScoreboardSim.Diff.new(MwScoreboardSim.Mem.new(ram, stack))
	d.word("pad mode $C646", MODE_RAM, mode2)
	if _known_refresh:
		d.word("refresh $C648", REFRESH_RAM, refresh)
	if _known_idle_e:
		d.word("idle ticks $C64A", IDLE_E_RAM, idle_e)
	d.flag("sound $C76C", SFX_RAM, sfx != 0)
	pages[0].compare(d, "A")
	pages[1].compare(d, "B")
	var ours := MwRinkRam.encode(s, ram)
	# the teams (players, their animation fields, the armed plays) and the top net
	d.ram_range(ours, MwRinkRam.TEAMS[0], MwRinkRam.TEAMS[1] + 0x4AA)
	d.ram_range(ours, NET_TOP, NET_TOP + 0x26)
	MwScoreboardSim.compare_anim_pad(d, _touched.keys())
	MwScoreboardSim.compare_setup(d, ours)
	MwScoreboardSim.compare_speech(d, ours)
	return d.out
