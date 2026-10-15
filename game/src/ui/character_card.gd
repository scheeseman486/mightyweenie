class_name MwCharacterCard
extends Node2D
## A position's card on the selection screens (plan 34 section 7): the
## character who plays it, with the original's portrait (`$B51E`: a star's
## own, else his species', [MwPortrait]) - character selection's six a side
## (111) and the line-up panels' six a team. The node's origin is the
## content's top-left; the content is [constant W] cells wide (the
## portrait's 40 pixels) and [constant ROWS] rows tall, so the menus' frame
## (MwPlanePainter.frame) drawn around it fits the cells around - the
## screen's players' cursors draw it there in their colours.
##
## * [constant Style.BIG] (111): the position's name large (the matchup's
##   title font, two rows), then the portrait.
## * [constant Style.COMPACT] (the panels): the position and the
##   character's number on a row, the portrait, his rating for the position
##   on its bottom-right corner; the screen writes the P<n> of the player
##   who took the position on its bottom-left corner (MwLineupPanel,
##   [method tag_cell]).
##
## A captain's card shows a C over the portrait's corner; [method set_dim]
## greys it (the vote: positions nobody picked); [method set_red] turns its
## texts red (the panels: a browsed candidate who plays another card).
## Texts are the ROM's fonts and strings, read at run time.

enum Style { BIG, COMPACT }

const W := 5
const ROWS := 7
const FONT := MwPlanePainter.FONT_MENU
## The matchup's title font (two-cell glyphs).
const FONT_BIG := MwFonts.TITLE
const TEXT_ATTR := MwMenuRows.TEXT_ATTR
const DIM := MwUiInk.DARK
## [method set_red]'s tint: the port's red (the collisions' values on the
## controls pages, the online pages' notes).
const RED := MwPortMenu.RED
const PORTRAIT_ATTR := 0x20

var rom: PackedByteArray
var style := Style.BIG
## The position (0-5, MwHumans.POSITIONS) and the roster slot shown (-1 none).
var pos := 0
var slot := -1
var record := 0
var captain := false
## The texts are red ([method set_red]).
var red := false
var portrait := MwPortrait.new()
## The texts (label, rating, number) and the captain's C, over the portrait.
var text: RomPlane
var badge: RomPlane


## On [param tiles] in [param palette] (the screen's menu palette); the
## portrait in [param portrait_palette] (its team's colours on line 1).
func setup(rom_: PackedByteArray, tiles: RomTileSet, palette: RomPalette, portrait_palette: RomPalette,
		style_: Style, pos_: int) -> void:
	rom = rom_
	style = style_
	pos = pos_
	portrait.attr = PORTRAIT_ATTR
	portrait.set_palette(portrait_palette)
	add_child(portrait)
	text = _layer("Text", tiles, palette)
	badge = _layer("Badge", tiles, palette)


## The portrait's top-left (pixels, local).
func portrait_at() -> Vector2:
	return Vector2(0, 16 if style == Style.BIG else 8)


## Where the [param i]-th player's P<n> tag ([param w] cells wide) goes on a
## card of [param style_] (cells from its content's top-left), over the
## portrait from its bottom up, left, right, left, right ... (owner,
## 2026-10-12: within the portrait's frame, alternating sides up from the
## bottom; a COMPACT card's right side starts over its rating). At most a row
## over the portrait's top (owner: 8 px); six players a team take three rows,
## clear of the captain's C (top right).
static func tag_cell(style_: Style, i: int, w: int) -> Vector2i:
	var top := 2 if style_ == Style.BIG else 1      # the portrait's first row
	var bottom := ROWS - 1
	@warning_ignore("integer_division")
	var up := i / 2
	if i % 2 == 0:
		return Vector2i(0, maxi(bottom - up, top - 1))
	var right_bottom := bottom - (1 if style_ == Style.COMPACT else 0)
	return Vector2i(W - w, maxi(right_bottom - up, top - 1))


## Shows roster slot [param slot_] of [param lineup]'s team (its rating for
## this card's position).
func show_slot(lineup: MwLineup, slot_: int) -> void:
	if slot_ == slot and record == lineup.record(slot_):
		return
	slot = slot_
	record = lineup.record(slot_)
	portrait.set_player(rom, record, 0)
	portrait.face.state = null                  # a fresh animation state for the new face
	portrait.start(0)
	_still()
	portrait.place(portrait_at())
	_draw_text(lineup)


## The portrait's expression, once (a lock: its sounds play with it).
func pull_face() -> void:
	portrait.face.state = null
	portrait.start(1)


## True while the expression plays.
func pulling() -> bool:
	return portrait.which != 0 and portrait.face.is_running()


## Back to the still face (an unlock).
func rest() -> void:
	if portrait.which == 0:
		return
	portrait.face.state = null
	portrait.start(0)
	_still()


## The portrait's expression [param elapsed] ticks on (the still face stays still).
func advance(elapsed: int) -> void:
	if portrait.which != 0:
		portrait.advance(elapsed)


## Marks the card a captain's ([param on]): a C in the large font on the portrait's top-right
## corner; off: none.
func set_captain(on: bool) -> void:
	captain = on
	badge.clear()
	if on:
		# the C on the portrait's top-right corner, in the large font
		var c := "C".to_ascii_buffer()
		var w := MwGfx.text_width(rom, FONT_BIG, c)
		var row := int(portrait_at().y / 8)
		MwPlanePainter.text(badge, rom, FONT_BIG, c, W - w, row, TEXT_ATTR)


## Greys the card ([param on]: the vote's positions nobody picked), or back to full colour.
func set_dim(on: bool) -> void:
	modulate = DIM if on else Color.WHITE


## The texts (position, number, rating; the big label) in [constant RED],
## or back to their own colour.
func set_red(on: bool) -> void:
	red = on
	text.modulate = RED if on else Color.WHITE


## The talking face's first frame, still (the mouth closed, no voice).
func _still() -> void:
	var st := portrait.face.state
	if st:
		st.flags &= ~MwAnimState.PLAYING
		st.frame = 0
		portrait.face.refresh()


func _draw_text(lineup: MwLineup) -> void:
	text.clear()
	var label := MwHumans.POSITIONS[pos].to_ascii_buffer()
	if style == Style.BIG:
		var w := MwGfx.text_width(rom, FONT_BIG, label)
		MwPlanePainter.text(text, rom, FONT_BIG, label, (W - w) / 2, 0, TEXT_ATTR)
		return
	MwPlanePainter.text(text, rom, FONT, label, 0, 0, TEXT_ATTR)
	var n := str(lineup.number(slot)).to_ascii_buffer()
	MwPlanePainter.text(text, rom, FONT, n, W - MwGfx.text_width(rom, FONT, n), 0, TEXT_ATTR)
	var r := str(lineup.rating(slot, pos)).to_ascii_buffer()
	MwPlanePainter.text(text, rom, FONT, r, W - MwGfx.text_width(rom, FONT, r), ROWS - 1, TEXT_ATTR)


func _layer(n: String, tiles: RomTileSet, palette: RomPalette) -> RomPlane:
	var plane := RomPlane.new()
	plane.name = n
	plane.tiles = tiles
	plane.palette = palette
	add_child(plane)
	return plane
