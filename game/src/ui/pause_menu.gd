class_name MwPauseMenu
extends Node2D
## The port's pause menu as the rink draws it (plan 23, owner; the STANDARD
## layout - MwRinkPhases.menu holds its state, [method MwRinkPhases.menu_press]
## its answers): over the frozen rink, centred to the pixel (owner: the
## pixel grid is the rule, not the tile grid), each line on its own layer -
##
## * the title, "PAUSE" (or "ARE YOU SURE?"), in the big block-letter font
##   in greys whatever the team (MwGlyphs "grey");
## * the pausing player, "PLAYER n", in the menu font on a black plate
##   (MwGlyphs.black_label: the menus' selection frame recoloured black, as
##   wide as the text; the port menus title their pages with it too);
## * the items (REPLAY - not online -, TIMEOUT when offered, TEAM INFO,
##   online the host's PLAYERS, FORFEIT; a spectated match's REPLAY, TEAM
##   INFO, QUIT GAME; or YES, NO) in the big font in the pausing team's
##   colours, one under another: the selected
##   one in the team's primary colour (the font's own face and shade on the
##   team's line), the others in its secondary (MwGlyphs "secondary"; owner),
##   darker when the team's two colours are alike (owner; [method alike]);
## * the title screen's eye (`$4B70E`, its own palette and attr, looping) on
##   each side of the selected item, 2 px above its middle.
##
## The layers share the window plane's tiles and palette (fades included);
## the items' layers take a copy with the secondary darker when it is needed
## ([method items_palette]).
## Short names: l a plane being painted (RomPlane).

const BIG := MwFonts.BIG
const SMALL := MwFonts.LIGHT
const EYE := "anim_04b70e"
## The title screen's palette (its eyes' colours): `pal_title` of the title scene.
const TITLE_PALETTE := ["rom 36C64 0", "rom 36C84 1"]
const TITLE_Y := 2          ## the title's baseline row
const PLAYER_Y := 6         ## the player line's row
const ITEMS_Y := 9          ## the first item's baseline row (the confirm menu's one row lower)
const ITEM_GAP := 4         ## rows from item to item
const EYE_GAP := 16         ## pixels from an item's end to its eye's middle
## the title, the player line, up to five items (plan 29: TEAM INFO; plan 35's PLAYERS list scrolls in five)
const LAYERS := 7
## A team's two colours are alike when their faces (colours 2 and 5 of its
## line) differ by at most this many levels, the channels' differences
## summed (the yellow team's are the same; the khaki and orange teams' a
## level or two apart); its secondary is then drawn this many levels darker.
const ALIKE_LEVELS := 2
const DARKER_LEVELS := 2

var rom: PackedByteArray
var _window_palette: RomPalette
var _item_palette: RomPalette        # the items' copy with the secondary darker
var _item_key := ""                  # what it was made from
## What [method show_menu] last showed: {confirm, sel} (plan 41: a
## client's prediction included).
var shown := {}
var _layers: Array[RomPlane] = []
var _eyes: Array[RomSprite] = []


## Makes the layers like [param window] (its tiles and palette) and the eyes.
## [param tiles]: other tiles (a screen whose VRAM lacks the menu's fonts:
## [method with_fonts]).
func setup(window: RomPlane, rom_: PackedByteArray, tiles: RomTileSet = null) -> void:
	rom = rom_
	_window_palette = window.palette
	z_index = 20
	for i in LAYERS:
		var l := RomPlane.new()
		l.name = "Line%d" % i
		l.tiles = tiles if tiles != null else window.tiles
		l.palette = window.palette
		add_child(l)
		_layers.append(l)
	var title := RomPalette.make(0, PackedStringArray(TITLE_PALETTE))
	for i in 2:
		var sprite := RomSprite.new()
		sprite.name = "Eye%d" % i
		sprite.anim = EYE
		sprite.palette = title
		sprite.attr_xor = 0x80
		add_child(sprite)
		_eyes.append(sprite)
	close()


## [param tiles] with the menu's fonts (the big font, the menu font, the
## frame glyphs) - itself when it has them all, else a copy that adds them
## (the fonts stay in the ROM's tile space: nothing of the screen's moves).
static func with_fonts(tiles: RomTileSet) -> RomTileSet:
	var want := PackedStringArray()
	for f in [BIG, SMALL, MwPlanePainter.FONT_SMALL]:
		var key := "font_%06x" % f
		if not tiles.fonts.has(key):
			want.append(key)
	if want.is_empty():
		return tiles
	var tile_set := tiles.duplicate() as RomTileSet
	tile_set.fonts = tiles.fonts + want
	return tile_set


## Draws [param menu] (MwRinkPhases.menu) with the items in palette attr
## [param attr] (the pausing team's, `$FFC5C4`). Plan 34's YES / NO
## questions ([MwConfirmBox]) give their own "title" and plate "line".
func show_menu(menu: Dictionary, attr: int) -> void:
	for l in _layers:
		l.wipe()
	visible = true
	var confirm: bool = menu.get("confirm", false)
	var title := str(menu.get("title", "ARE YOU SURE?" if confirm else "PAUSE"))
	var items: Array = ["YES", "NO"] if confirm else menu.get("items", [])
	var sel: int = int(menu.get("sure", 1)) if confirm else int(menu.get("sel", 0))
	shown = {"confirm": confirm, "sel": sel}
	var t := _place(_layers[0], BIG, title)
	MwGlyphs.rom_text(_layers[0], rom, BIG, title.to_ascii_buffer(), t, TITLE_Y, attr, "grey")
	var who := str(menu.get("line", "PLAYER %d" % int(menu.get("player", 1))))
	MwGlyphs.black_label(_layers[1], rom, SMALL, who.to_ascii_buffer(), _place(_layers[1], SMALL, who), PLAYER_Y, 0xE0)
	var first := ITEMS_Y + (1 if confirm else 0)
	var pal := items_palette(attr)
	for l in _layers.slice(2):
		if l.palette != pal:
			l.palette = pal
	# plan 35: a longer list (the host's PLAYERS) scrolls to keep the selection in view
	var rows_shown := LAYERS - 2
	var off := 0 if confirm else MwScrollArrows.follow(0, sel, rows_shown, items.size())    # plan 40 (M3)
	for i in mini(items.size() - off, rows_shown):
		var l := _layers[2 + i]
		var y := first + ITEM_GAP * i
		var x := _place(l, BIG, items[off + i])
		var b := (items[off + i] as String).to_ascii_buffer()
		if off + i != sel:
			MwGlyphs.rom_text(l, rom, BIG, b, x, y, attr, "secondary")
		else:
			MwPlanePainter.text(l, rom, BIG, b, x, y, attr)
			var left := x * 8 + int(l.position.x)
			var right := left + 8 * MwGfx.text_width(rom, BIG, b)
			var cy := y * 8 + 12
			_eyes[0].position = Vector2(left - EYE_GAP, cy)
			_eyes[1].position = Vector2(right + EYE_GAP, cy)
	for sprite in _eyes:
		sprite.visible = true
		if sprite.sprite_frames and not sprite.is_playing():
			sprite.play()


## The items' palette for the team line of [param attr]: the window's, or
## when the team's two colours are alike a copy with its secondary (colours
## 5-6) [constant DARKER_LEVELS] levels darker (RomPalette "darker").
func items_palette(attr: int) -> RomPalette:
	var line := (attr >> 5) & 3
	var c := _window_palette.colours() if _window_palette else PackedInt32Array()
	if c.is_empty() or not alike(c[16 * line + 2], c[16 * line + 5]):
		return _window_palette
	var palette := _window_palette
	var key := "%d|%d|%d|%d|%d|%s" % [line, palette.screen, palette.team_a, palette.team_b, palette.stadium,
			",".join(palette.steps)]
	if key != _item_key:
		_item_key = key
		_item_palette = palette.duplicate() as RomPalette
		_item_palette.steps = palette.steps + PackedStringArray(["darker %d %d" % [16 * line + 5, DARKER_LEVELS],
				"darker %d %d" % [16 * line + 6, DARKER_LEVELS]])
	return _item_palette


## The items' two colour words for the team line of [param attr] in the
## palette colours [param c]: the selected item's (colour 2) and the
## others' (colour 5), [constant DARKER_LEVELS] levels darker when the two
## are alike - as [method items_palette] colours them (plan 40, M8: the
## own menus take theirs from here). Empty when [param c] is short.
static func item_words(c: PackedInt32Array, attr: int) -> PackedInt32Array:
	var line := (attr >> 5) & 3
	if c.size() <= 16 * line + 5:
		return PackedInt32Array()
	var a := c[16 * line + 2]
	var b := c[16 * line + 5]
	return PackedInt32Array([a, RomPalette.darker(b, DARKER_LEVELS) if alike(a, b) else b])


## Whether Genesis colours [param a] and [param b] are alike: at most
## [constant ALIKE_LEVELS] levels apart, the channels' differences summed.
static func alike(a: int, b: int) -> bool:
	var d := 0
	for shift in [1, 5, 9]:
		d += absi(((a >> shift) & 7) - ((b >> shift) & 7))
	return d <= ALIKE_LEVELS


## Hides the menu.
func close() -> void:
	visible = false
	for l in _layers:
		l.wipe()
	for sprite in _eyes:
		sprite.visible = false


## The cell [param text] starts at in [param font] centred on the screen to
## the pixel: layer [param l] moves by the half cell an odd width leaves.
func _place(l: RomPlane, font: int, text: String) -> int:
	var px := (320 - 8 * MwGfx.text_width(rom, font, text.to_ascii_buffer())) / 2
	l.position = Vector2(px % 8, 0)
	return px / 8
