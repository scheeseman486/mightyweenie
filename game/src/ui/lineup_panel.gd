class_name MwLineupPanel
extends Node2D
## A team's line-up panel before the match (plan 34 section 7; owner: the
## top team's menu crashes in from above, the bottom team's from below,
## meeting in the middle - only the top one for a single player; the captain
## may skip it, leaving the players the characters they picked). Half the
## screen (40 x 14 cells) in the original's menu look: the menus' frame
## glyphs and fonts, the team's logo and name (read from the ROM), six
## cards - C, LW, RW, LD, RD, G ([MwCharacterCard]: portrait, rating for the
## position, number, and the P<n> of the player who took it - without
## character selection, the drivers' on the highlighted card) - and on the
## bottom edge the highlighted card's number and name (left) and DONE with
## the glyph of the button that confirms before it (right), READY there once
## confirmed (owner, 2026-10-12: the glyph had been on the top edge - the
## screen's first row for the top panel, against the other panel's bottom
## edge for the bottom one - and READY a white highlight box clipping its R;
## both now the bottom edge's bands, the menus' hint place).
##
## The team's captain drives it - or its one player, or without a captain
## all its players, OR'd as the original's co-op Reserves page reads both
## pads ([member drivers]). Left / Right move between the cards (owner,
## 2026-10-10: DONE isn't an item to select, just the right button's glyph
## beside it; SKIP dropped as redundant). Up / Down browse the card's
## candidates ([method browse]; owner, 2026-10-10: no other player is
## switched out until accept, Left or Right is pressed): the card alone
## shows the one browsed ([member preview]), nobody else in the line-up
## moves; a candidate who plays another card - a duplicate - turns that
## card's texts red until he is committed, the card committing him would
## swap ([method swap_card]; owner, 2026-10-12). Accept, or Left / Right to
## another card, commits him ([method commit]: [method MwLineup.place], so a
## character playing another card swaps with it; players keep their own
## positions whoever plays them); Back puts the card's character back (the
## change undone, the menu not left). With nothing browsed, accept (DONE:
## the glyph's button) keeps the line-up as it stands and sets
## [member is_ready] ([method confirm]: a browsed candidate is committed
## first); Back takes READY back - and on a panel that isn't READY and shows
## nothing browsed leaves the line-ups ([method handle] says so: the screen
## goes back to the controller selection). The glyphs are the drivers' own
## ([member glyphs], [method set_glyphs]: the screen picks them for the
## drivers' layouts and devices). All of it follows the presses alone, so
## online (plan 35) every machine browses and commits alike.
##
## It comes in with the game setup top's slam ([MwSlam], the FACE OFF! drop,
## bouncing and landing: [member MwSlam.bounces] - owner, 2026-10-12: the
## panels had missed the slam's bounce fixes): [member from_below]
## mirrored - rising from under the screen into the bottom half - else
## falling from above into the top half; it shakes itself (not the whole
## screen: the stars stay still), the screen plays the crash on each of the
## first two bounces ([method MwSlam.crash]). Presentation only.

const COLS := 40
const ROWS := 14
const HEIGHT := ROWS * 8
## The cards' content cells (MwCharacterCard, COMPACT) and their row.
const CARD_X := [2, 8, 14, 20, 26, 32]
const CARD_Y := 5
## The team's name (the big font, its colours: the rink's score panel's
## look) beside the logo; on the bottom edge the highlighted card's number
## and name (its plate's round end at [constant DETAIL_X]), and the
## confirm's glyph and DONE - READY once confirmed - ending over the last
## card's right edge.
const NAME_X := 8
const NAME_Y := 1
const DETAIL_Y := ROWS - 1
const DETAIL_X := 2
const DONE_Y := ROWS - 1
const DONE_END := 37
const DONE := "DONE"
const READY := "READY"
## The most glyph cells beside DONE (several drivers on different devices:
## each distinct glyph, in their order, while they fit) - clear of the
## longest number and name before them.
const GLYPH_CELLS := 8
const LOGO_AT := Vector2(8, 2)
## Returned by [method handle]: Back on a panel that isn't READY - out of
## the line-ups.
const LEAVE := -1
const FONT := MwPlanePainter.FONT_MENU
const FONT_DARK := MwPlanePainter.FONT_SMALL
const FONT_NAME := MwRinkPhases.BIG_FONT
const TEXT_ATTR := MwMenuRows.TEXT_ATTR

var rom: PackedByteArray
## The team (0 A, 1 B) and its line-up.
var team := 0
var lineup: MwLineup
## The players whose presses count here.
var drivers: Array[int] = []
## position -> the player who took it (character selection; empty: none).
var owners := {}
## The highlighted card (0-5: C, LW, RW, LD, RD, G).
var cursor := 0
## The roster slot browsed on the highlighted card (Up / Down), shown on it
## but not yet in [member lineup] (-1: none - the card shows its own).
var preview := -1
var is_ready := false
var _echoed := false                 # plan 41: drawn with predicted presses
## What [method refresh] last drew: [the highlighted card, the browsed
## candidate, READY] (a prediction's included).
var drawn := [0, -1, false]
## The glyphs drawn beside DONE (MwGlyphs ids: "vk:13", "pad:START" ...),
## the drivers' confirm ([method set_glyphs]).
var glyphs := PackedStringArray()
var from_below := false
## Its place once landed (screen pixels) and its fall.
var place_y := 0
var slam: MwSlam
var cards: Array[MwCharacterCard] = []

var _back: RomPlane                  # the black slab and the frame
var _text: RomPlane
var _name: RomPlane                  # the team's name, in its colours
var _cursor: RomPlane                # the highlight frame
var _tags := {}                      # player -> RomPlane (their P<n>, in their colour)
var _logo: RomSprite
var _tiles: RomTileSet
var _palette: RomPalette


## Team [param team_] (0 team A, 1 team B: [member team]) with [param lineup_],
## driven by [param drivers_]; [param owners_] the positions' players.
## [param name_palette]: lines 1 and 2 the teams' colours (the matchup's).
func setup(rom_: PackedByteArray, tiles: RomTileSet, palette: RomPalette, portrait_palette: RomPalette,
		logo_palette: RomPalette, name_palette: RomPalette, team_: int, lineup_: MwLineup, drivers_: Array,
		owners_: Dictionary) -> void:
	rom = rom_
	_tiles = tiles
	_palette = palette
	team = team_
	lineup = lineup_
	drivers.assign(drivers_)
	owners = owners_
	_back = _layer("Back", MwGlyphs.plate_palette(palette))
	_text = _layer("Text", palette)
	_name = _layer("Name", name_palette)
	_cursor = _layer("Cursor", palette)
	MwGlyphs.black_frame(_back, rom, 1, 1, COLS - 2, ROWS - 2)
	_logo = RomSprite.new()
	_logo.name = "Logo"
	_logo.palette = logo_palette
	_logo.attr_xor = 0x20
	_logo.frame_addresses = PackedInt32Array([MwTeams.logo_frame(rom, lineup.team)])
	_logo.position = LOGO_AT
	add_child(_logo)
	for k in MwLineup.POSITIONS:
		var card := MwCharacterCard.new()
		card.name = "Card%d" % k
		card.position = Vector2(8 * CARD_X[k], 8 * CARD_Y)
		add_child(card)
		card.setup(rom, tiles, palette, portrait_palette, MwCharacterCard.Style.COMPACT, k)
		cards.append(card)
	_draw_name()
	refresh()


## Starts the crash in: from above (into the top half) or, [param below],
## from under the screen (into the bottom half).
func crash_in(top_y: int, below: bool) -> void:
	place_y = top_y
	from_below = below
	slam = MwSlam.new(HEIGHT)                # from just off the screen (FACE OFF!'s 180 px: a second of nothing)
	slam.bounces = true                      # it bounces and lands (owner), as the game setup's top
	_place()


## Whether the panel is down to stay: its crash in done, or never started.
func landed() -> bool:
	return slam == null or slam.done


## [param elapsed] ticks of the crash; on the pass of a crash the bounce it
## is (1 the first, 2 the second: [method MwSlam.crash]), else 0.
func advance(elapsed: int) -> int:
	for card in cards:
		card.advance(elapsed)
	if slam == null or slam.done:
		return 0
	slam.advance(elapsed)
	_place()
	return slam.impacts if slam.thud else 0


## Lands the panel at once (a press skips the crash in; [method MwSlam.settle]).
func settle() -> void:
	if slam != null:
		slam.settle()
		_place()


## The sideways shake this pass (px; 0 while falling, once landed, or with no crash in).
func shake() -> int:
	return slam.shake if slam != null and not slam.done else 0


## Where it is: [member place_y] less its height (more, rising from
## below), shaken sideways while it bounces.
func _place() -> void:
	var h := slam.height() if slam != null else 0
	position.y = place_y + (h if from_below else -h)
	position.x = shake()


## Backing out over the controller selection (MwCharacterSelect's pull
## back): [param f] of the way (0 in place .. 1 gone) back where it came
## from - off the top, or off the bottom (the screen: two panels high)
## rising from below.
func pull_back(f: float) -> void:
	var off := float(place_y + HEIGHT) if not from_below else float(2 * HEIGHT - place_y)
	position = Vector2(0, place_y + roundi(off * f) * (1 if from_below else -1))


## The glyphs of its drivers' confirm ([member glyphs]); redrawn when they
## change (a player picks up another device).
func set_glyphs(ids: PackedStringArray) -> void:
	if ids == glyphs:
		return
	glyphs = ids
	refresh()


## One pass of its drivers' presses ([param input]); returns the sound to
## play (0: none), or [constant LEAVE]: Back while not READY with nothing
## browsed.
func handle(input: MwInputFrame) -> int:
	if input == null:
		return 0
	var press := func(verb: String) -> bool:
		for p in drivers:
			if input.menu_pressed(p, verb):
				return true
		return false
	if is_ready:
		if press.call("ui_back"):
			is_ready = false
			refresh()
			return MwLineup.SOUND_MOVE
		return 0
	var sound := 0
	if press.call("ui_left") or press.call("ui_right"):
		commit()                                 # the browsed one in (owner)
		cursor = posmod(cursor + (-1 if press.call("ui_left") else 1), MwLineup.POSITIONS)
		sound = MwLineup.SOUND_MOVE
	elif press.call("ui_up") or press.call("ui_down"):
		sound = browse(-1 if press.call("ui_up") else 1)
	elif press.call("ui_accept"):
		if preview >= 0:
			commit()                             # the browsed one in; DONE is the next press
		else:
			is_ready = true                      # DONE: the line-up as it stands
		sound = MwLineup.SOUND_MOVE
	elif press.call("ui_back"):
		if preview < 0:
			return LEAVE
		preview = -1                             # the change backed out of, not the menu (owner)
		sound = MwLineup.SOUND_MOVE
	if sound != 0:
		refresh()
	return sound


## Plan 41 (online, a client): its drivers' presses on this machine that
## its game hasn't run yet ([param presses]: player -> verbs) shown at once -
## [method handle] runs them on the panel (the highlight, the browsed
## candidate, the line-up, READY; Back out of the line-ups is the game's to
## do), [method refresh] draws, and the panel is put back as it was; {}
## draws it as it is once more after a prediction.
func predict(presses: Dictionary) -> void:
	if presses.is_empty():
		if _echoed:
			_echoed = false
			refresh()
		return
	var kept := [cursor, preview, is_ready, lineup.slots.duplicate()]
	MwLocalEcho.run(func() -> void:
		for p: int in presses:
			for verb: String in presses[p]:
				handle(MwLocalEcho.frame(p, verb))
		refresh())
	cursor = kept[0]
	preview = kept[1]
	is_ready = kept[2]
	lineup.slots = kept[3]
	_echoed = true


## Up / Down on the highlighted card ([param dir] -1 / +1): its next
## candidate ([method MwLineup.candidates], round the list) shown on it as
## [member preview] - nobody else moves; back at the card's own character,
## nothing browsed. Returns the sound ([constant MwLineup.SOUND_REFUSED]:
## no other candidate).
func browse(dir: int) -> int:
	var list := lineup.candidates(cursor)
	if list.size() < 2:
		return MwLineup.SOUND_REFUSED
	var i := posmod(list.find(shown(cursor)) + dir, list.size())
	preview = -1 if list[i] == lineup.slots[cursor] else list[i]
	return MwLineup.SOUND_MOVE


## The browsed candidate into the line-up at the highlighted card
## ([method MwLineup.place]: one playing another card swaps with it); true
## when there was one.
func commit() -> bool:
	if preview < 0:
		return false
	lineup.place(cursor, preview)
	preview = -1
	return true


## READY without a press (online: the drivers' machines are away): a
## browsed candidate is committed first, as DONE would leave it.
func confirm() -> void:
	commit()
	is_ready = true
	refresh()


## The roster slot card [param pos] shows: the browsed candidate on the
## highlighted card, else the line-up's.
func shown(pos: int) -> int:
	return preview if pos == cursor and preview >= 0 else lineup.slots[pos]


## The card whose character committing the browsed one would swap (the card
## he plays now: it takes the highlighted card's character), its texts red
## (owner, 2026-10-12: the red shows the character accepting would swap -
## it had marked the highlighted card); -1: none.
func swap_card() -> int:
	return lineup.slots.find(preview) if duplicate_shown() else -1


## True while the browsed candidate plays another card (committing him
## swaps the two).
func duplicate_shown() -> bool:
	return preview >= 0 and preview in lineup.slots


## Redraws the cards, the detail line, DONE or READY and the highlight.
func refresh() -> void:
	drawn = [cursor, preview, is_ready]
	for k in cards.size():
		cards[k].show_slot(lineup, shown(k))
		cards[k].set_red(k == swap_card())
	_text.clear()
	MwPlanePainter.frame(_text, rom, 1, 1, COLS - 2, ROWS - 2, false)
	_draw_name()
	_cursor.clear()
	_draw_done()
	if not is_ready:
		MwPlanePainter.frame(_cursor, rom, CARD_X[cursor], CARD_Y, MwCharacterCard.W, MwCharacterCard.ROWS, false)
	var slot := shown(cursor)
	var text := "%d %s" % [lineup.number(slot), _player_name(slot)]
	_plate(_text, text, DETAIL_X, DETAIL_Y)
	_draw_tags()


## The cells of [member glyphs] beside DONE: each distinct one while they
## fit in [constant GLYPH_CELLS] (none without the glyph sheets).
func glyph_cells() -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var w := 0
	for id in glyphs:
		var c := MwGlyphs.cells(id, MwGlyphs.Style.TEXT)
		if c.is_empty() or w + c.size() > GLYPH_CELLS:
			continue
		out.append(c)
		w += c.size()
	return out


## Where DONE's tab on the bottom edge starts (its first blank cell): the
## glyphs, a space, DONE, a blank at each end, ending at [constant
## DONE_END]; READY's once confirmed (no glyphs).
func done_x() -> int:
	var w := 0
	if not is_ready:
		for c in glyph_cells():
			w += c.size()
	var text_w := MwGfx.text_width(rom, FONT, (READY if is_ready else DONE).to_ascii_buffer())
	return DONE_END - (1 + w + (1 if w > 0 else 0) + text_w + 1) + 1


## The confirm's glyphs and DONE - or READY - at the bottom edge's right,
## over the frame's line as the detail line sits at its left, on the black
## version of the titles' plate with its round ends (owner, 2026-10-12:
## MwGlyphs.black_frame, the ends at [method done_x] and
## [constant DONE_END]), the glyphs on it ([enum MwGlyphs.Style] TEXT).
func _draw_done() -> void:
	var x := done_x()
	MwGlyphs.black_frame(_text, rom, x + 1, DONE_Y, DONE_END - x - 1, 1)
	x += 1
	if is_ready:
		MwPlanePainter.text(_text, rom, FONT, READY.to_ascii_buffer(), x, DONE_Y, TEXT_ATTR)
		return
	var cells := glyph_cells()
	for c: PackedInt32Array in cells:
		x = MwGlyphs.put_cells(_text, c, x, MwPrompts.row(rom, FONT, DONE_Y))
	if not cells.is_empty():
		x += 1
	MwPlanePainter.text(_text, rom, FONT, DONE.to_ascii_buffer(), x, DONE_Y, TEXT_ATTR)


## Each position's player (P<n>), in their colour, over the bottom-left
## corner of its card's portrait, on the rating's row (owner, 2026-10-12:
## it had sat on the row under the card) - or, nobody having taken a
## position (no character selection: the controller selection's line-ups),
## the drivers' on the highlighted card, stacked as character selection
## stacks its players' ([method MwCharacterCard.tag_cell]; owner,
## 2026-10-12: the roster's tags on the portrait too, for consistency).
func _draw_tags() -> void:
	for p in _tags:
		(_tags[p] as RomPlane).clear()
	var by := tags()
	for pos: int in by:
		var on: Array = by[pos]
		for i in on.size():
			var p: int = on[i]
			if not _tags.has(p):
				var plane := _layer("Tag%d" % p, _palette)
				plane.modulate = MwPlayerColours.colour(rom, p)
				_tags[p] = plane
			var t := ("P%d" % p).to_ascii_buffer()
			var at := MwCharacterCard.tag_cell(MwCharacterCard.Style.COMPACT, i, MwGfx.text_width(rom, FONT, t))
			MwPlanePainter.text(_tags[p], rom, FONT, t, CARD_X[pos] + at.x, CARD_Y + at.y, TEXT_ATTR)


## The P<n> tags on the cards ([method _draw_tags]): card -> its players,
## in stacking order.
func tags() -> Dictionary:
	var out := {}
	for pos in owners:
		out[int(pos)] = [int(owners[pos])]
	if owners.is_empty() and not drivers.is_empty():
		out[cursor] = drivers.duplicate()
	return out


func _draw_name() -> void:
	_name.clear()
	var nm := MwGfx.rom_string(rom, MwTeams.name(rom, lineup.team))
	MwPlanePainter.text(_name, rom, FONT_NAME, nm, NAME_X, NAME_Y, 0x20 if team == 0 else 0x40)


func _player_name(slot: int) -> String:
	var r := lineup.record(slot)
	return MwGfx.rom_string(rom, MwGfx.u32(rom, r)).get_string_from_ascii() if r != 0 else ""


## [param text] on the black version of the titles' plate over the frame's
## line ([method _draw_done]'s; owner, 2026-10-12: the character name's
## text too), its round left end at cell [param x] of row [param y] of
## [param on].
func _plate(on: RomPlane, text: String, x: int, y: int) -> void:
	var b := text.to_ascii_buffer()
	MwGlyphs.black_frame(on, rom, x + 1, y, MwGfx.text_width(rom, FONT, b), 1)
	MwPlanePainter.text(on, rom, FONT, b, x + 1, y, TEXT_ATTR)


func _layer(n: String, palette: RomPalette) -> RomPlane:
	var plane := RomPlane.new()
	plane.name = n
	plane.tiles = _tiles
	plane.palette = palette
	add_child(plane)
	return plane
