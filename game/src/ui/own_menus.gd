class_name MwOwnMenus
extends Node2D
## Plan 34 (section 7, owner): everyone else's own menus as the rink draws
## them (MwRinkControl holds their state, [method MwRinkControl.menus]) - a
## small window per player in the pause menu's look (MwPauseMenu), stacked
## down their team's side of the screen (team A's on the left, team B's on
## the right, in player-number order) over the running game:
##
## * their player line, "PLAYER n", in the menu font on the pause menu's
##   black plate (MwGlyphs.black_frame), the letters in their colour (the
##   crossbones' they play with: MwPlayerColours - players 1-4 the
##   original's pads' in the set-ups the original could have had);
## * plan 35 (online): a player whose machine is away gets a window with
##   its status (LAGGING, DISCONNECTED, KICKED) in grey and no items; the
##   host's players' PLAYERS list has a line per remote machine and BACK;
## * the items (RESUME, QUIT GAME; after QUIT GAME, REJOIN) in the menu font
##   in their team's colours - the selected one in the team's primary, the
##   others in its secondary (as the pause menu's items), on a see-through
##   dark backing (true translucency) so they read over the ice; ARE YOU
##   SURE? (grey) over YES / NO for QUIT GAME;
## * the title screen's eye (`$4B70E`, as the pause menu's) left of the
##   selected item.
##
## Every layer shares the window plane's tiles and palette (fades
## included); the colours are the layers' modulation (the menu font's white
## letters take it, its black outline stays black).

const FONT := MwFonts.LIGHT                 ## the light menu font (the pause menu's player line)
const EYE := MwPauseMenu.EYE
const TOP := 8                        ## pixels: the first window's top
const SIDE := 8                       ## pixels from the screen's side
const GAP := 8                        ## pixels between one player's window and the next
const ROW := 12                       ## pixels from line to line under the name (room for the eye)
const ITEM_X := 3                     ## cells: the items (the eye left of them)
const BACKING := Color(0, 0, 0, 0.55)
const GREY := Color(0.75, 0.75, 0.75)
## The layers of one window (and [constant MAX_ITEMS] item lines).
const PARTS := ["Plate", "Name", "Title"]
const MAX_ITEMS := 13

var rom: PackedByteArray
var _window: RomPlane
var _title_palette: RomPalette
## player -> {"root": Node2D, "back": ColorRect, parts: RomPlane, "eye": RomSprite}
var _boxes := {}


## Makes the menus like [param window] (its tiles and palette).
func setup(window: RomPlane, rom_: PackedByteArray) -> void:
	rom = rom_
	_window = window
	z_index = 19
	_title_palette = RomPalette.make(0, PackedStringArray(MwPauseMenu.TITLE_PALETTE))
	visible = false


## Draws [param list] ([method MwRinkControl.menus]: {player, team, menu,
## pad}) - team [param attrs] (each team's window attr: line and priority,
## the pause menu's `$FFC5C4` form), [param colours] (player -> the colour
## their letters take). Windows of players not in the list go.
func show_menus(list: Array, attrs: Array, colours: Dictionary) -> void:
	var shown := {}
	var at := [TOP, TOP]
	for m: Dictionary in list:
		var player := int(m["player"])
		var t := int(m["team"])
		shown[player] = true
		var box := _box(player)
		_paint(box, m["menu"], player, int(attrs[t]), colours.get(player, Color.WHITE))
		var w := int(box["width"])
		var x := SIDE if t == 0 else 320 - SIDE - w
		(box["root"] as Node2D).position = Vector2(x, int(at[t]))
		at[t] = int(at[t]) + int(box["height"]) + GAP
	for player in _boxes.keys():
		if not shown.has(player):
			(_boxes[player]["root"] as Node).queue_free()
			_boxes.erase(player)
	visible = not list.is_empty()


## Hides every window (the pause menu over them; the rink left).
func close() -> void:
	show_menus([], [0, 0], {})


## How many windows show (tests).
func count() -> int:
	return _boxes.size()


func _box(player: int) -> Dictionary:
	if _boxes.has(player):
		return _boxes[player]
	var root := Node2D.new()
	root.name = "Player%d" % player
	add_child(root)
	var back := ColorRect.new()
	back.name = "Backing"
	back.color = BACKING
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)
	var box := {"root": root, "back": back, "width": 0, "height": 0}
	var parts := PARTS.duplicate()
	for i in MAX_ITEMS:
		parts.append("Item%d" % i)
	for part: String in parts:
		var plane := RomPlane.new()
		plane.name = part
		plane.tiles = _window.tiles
		plane.palette = MwGlyphs.plate_palette(_window.palette) if part == "Plate" else _window.palette
		root.add_child(plane)
		box[part] = plane
	var eye := RomSprite.new()
	eye.name = "Eye"
	eye.anim = EYE
	eye.palette = _title_palette
	eye.attr_xor = 0x80
	root.add_child(eye)
	box["eye"] = eye
	_boxes[player] = box
	return box


## One window: [param menu] (MwRinkControl.Seat.menu) for [param player],
## the items in team attr [param attr], the name in [param colour]: the
## name's row at the top, then a line every [constant ROW] pixels (each
## line its own layer, placed to the pixel).
func _paint(box: Dictionary, menu: Dictionary, player: int, attr: int, colour: Color) -> void:
	for part: String in PARTS:
		(box[part] as RomPlane).wipe()
	for i in MAX_ITEMS:
		(box["Item%d" % i] as RomPlane).wipe()
	var confirm: bool = menu.get("confirm", false)
	var items: Array = ["YES", "NO"] if confirm else menu.get("items", [])
	var sel := int(menu.get("sure", 1)) if confirm else int(menu.get("sel", 0))
	var label := ("PLAYER %d" % player).to_ascii_buffer()
	var cells := MwGlyphs.text_width(rom, FONT, label)
	MwGlyphs.black_frame(box["Plate"], rom, 1, 0, cells, 1)
	MwGlyphs.text(box["Name"], rom, FONT, label, 1, 0, 0xE0)
	(box["Name"] as RomPlane).modulate = colour
	var y := ROW
	var width := cells + 2
	if confirm or menu.has("note"):
		var bytes := ("ARE YOU SURE?" if confirm else str(menu["note"])).to_ascii_buffer()
		var title: RomPlane = box["Title"]
		MwGlyphs.text(title, rom, FONT, bytes, 1, 0, 0xE0)
		title.modulate = GREY
		title.position = Vector2(0, y)
		width = maxi(width, MwGlyphs.text_width(rom, FONT, bytes) + 2)
		y += ROW
	# the pause menu's colours (plan 40, M8, owner: one darkening for an alike secondary)
	var w := MwPauseMenu.item_words(_window.palette.colours() if _window.palette else PackedInt32Array(), attr)
	var primary := MwGfx.color(w[0]) if not w.is_empty() else Color.WHITE
	var secondary := MwGfx.color(w[1]) if not w.is_empty() else GREY
	var eye: RomSprite = box["eye"]
	for i in mini(items.size(), MAX_ITEMS):
		var plane: RomPlane = box["Item%d" % i]
		var b := (items[i] as String).to_ascii_buffer()
		MwGlyphs.text(plane, rom, FONT, b, ITEM_X, 0, 0xE0)
		plane.modulate = primary if i == sel else secondary
		plane.position = Vector2(0, y)
		if i == sel:
			eye.position = Vector2(8 * ITEM_X - 10, y + 4)
		width = maxi(width, ITEM_X + MwGlyphs.text_width(rom, FONT, b) + 1)
		y += ROW
	var back: ColorRect = box["back"]
	back.position = Vector2(0, 10)
	back.size = Vector2(8 * width, y - ROW + 8 + 2 - 10)
	box["width"] = 8 * width
	box["height"] = y - ROW + 10
	eye.visible = not items.is_empty()
	if eye.sprite_frames and not eye.is_playing():
		eye.play()
