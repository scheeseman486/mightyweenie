class_name MwBrickWall
extends RefCounted
## The controller selection's opening (screen 110, plan 34, owner): the brick
## background rises back up, leaving the game's logo, the team title and the
## teams' logos in place; the logos' backgrounds fade first; an animation
## playing is stopped before it, and the CONTROLLER SELECT title stays where
## it was; the logos and text are masked so they sit behind the rising wall.
##
## The brick wall is the game setup's top: the window plane's rows 0-15 (the
## backdrop `$41BF2`), the torches and the featured players' skulls under
## the panels. On 110 the panels hold their team's logo ([method
## MwTeamPanel.hold]: no portrait, no skater), then the panels' logo
## backgrounds (their windows' cells under the names: the black above the
## logo, the gradient behind it) fade out, then the wall rises off the top,
## faster and faster, to the clinks of a chain-link gate ([MwFmSfx] "gate",
## owner). What stays - the logo (already on a layer of its own, [member
## MwMainMenu.logo_plane]), the teams' logos (their panels' Logo and Ring
## sprites), the teams' names and the CONTROLLER SELECT plate - sits on
## layers under the window ([method lift]), which has holes where they
## showed through before: the faded cells and the names' glyph cells (their
## paper is the font's own, so the picture is the same until it moves; a
## selected team row's highlight goes with its name).
## Rising, the wall's lower rows pass in front of them and its bottom edge
## uncovers them; the plate, under the arch at first, comes out as the arch
## goes by.
##
## The way back (110 -> 1, player 1's Back) is the mirror: the wall falls
## back with the game setup's slam ([MwSlam], its thud and shake) from where
## it was, in front of the same layers, then the logo backgrounds fade back
## in and the cells go back into the window ([method merge]); the panels
## take up their cycle again. Entering the game setup any other way, the
## top falls in whole as before.

enum Phase { DOWN, WAIT, FADE_OUT, RISE, UP, FALL, FADE_IN, DONE }

## The logo backgrounds' fade (1/3 s) and the rise (1/2 s), in ticks.
const FADE_TICKS := 20
const RISE_TICKS := 30
## The rise's end: the window's 16 rows (128 px) above their place, off the
## top of the screen.
const HEIGHT := 128
## The panels' logo backgrounds: their windows' rows 3-10 (cells; the names
## are on rows 1-2, the black strip under the panel on row 11).
const BACKS := [Rect2i(4, 3, 10, 8), Rect2i(26, 3, 10, 8)]
## Where the teams' names are drawn (team rows 0 and 1; glyphs reach a cell
## above their baseline row).
const NAMES := [Rect2i(4, 0, 10, 4), Rect2i(26, 0, 10, 4)]
## Tile keys from here up are ROM tiles - the fonts' glyphs (RomTileSet); the
## window's own tiles (the backdrop, the rows' fill) are VRAM bank tiles.
const GLYPH_KEYS := 0x800
## A selected team row's fill (the game setup's highlight, [constant
## MwMenuRows.SELECTED_FILL]): it stays with the name it highlights.
const SELECTED_KEY := MwMenuRows.SELECTED_FILL & 0x7FF
const SELECTED_LINE := (MwMenuRows.SELECTED_FILL >> 13) & 3
## The FM effect of the rise ([MwFmSfx]).
const SOUND := "gate"

var menu: MwMainMenu
var phase := Phase.DOWN
## The wall's height above its place (px, whole: the pixel grid).
var height := 0
## The panels' logo backgrounds' opacity.
var backs_alpha := 1.0
## The layers under the window ([method lift]).
var backs: RomPlane
var logos: Node2D
var names: RomPlane
var title: RomPlane
## What rises (110): the window, the panels (their skull icons), the torches.
var group: Array[Node2D] = []
var _group_y := PackedFloat32Array()
var _t := 0


func _init(main_menu: MwMainMenu) -> void:
	menu = main_menu


## Puts what stays on layers under the window - the logo backgrounds, the
## teams' logos, their names and [param title_layer] (the CONTROLLER SELECT
## plate; null for none) - and cuts the window's holes for them. The panels
## must be held ([method MwTeamPanel.hold]) with their names drawn.
func lift(title_layer: RomPlane) -> void:
	var plane := menu.plane
	backs = _layer("LogoBacks")
	for r: Rect2i in BACKS:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_move_cell(plane, backs, x, y)
	logos = Node2D.new()
	logos.name = "TeamLogos"
	_under_window(logos)
	for panel in menu.panels:
		for sprite: RomSprite in [panel.ring, panel.logo]:          # the ring under the logo, as in the panel
			sprite.reparent(logos, true)
	names = _layer("TeamNames")
	for r: Rect2i in NAMES:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := plane.cell(x, y)
				var key: int = c["key"]
				if key >= GLYPH_KEYS or (key == SELECTED_KEY and int(c["line"]) == SELECTED_LINE):
					_move_cell(plane, names, x, y)
	title = title_layer
	if title != null:
		if title.get_parent() != null:
			title.get_parent().remove_child(title)
		_under_window(title)
	group = [plane, menu.panels[0], menu.panels[1], menu.torches[0], menu.torches[1]]
	_group_y = PackedFloat32Array()
	for n in group:
		_group_y.append(n.position.y)


## 110: the opening starts once the screen has faded in (from the playoffs
## bracket; from the game setup it is a cut).
func open() -> void:
	phase = Phase.WAIT
	_t = 0
	height = 0
	backs_alpha = 1.0
	place()


## The game setup from 110: the wall [param from_height] up (the menu's slam
## brings it down), the logo backgrounds at [param alpha].
func close(from_height: int, alpha: float) -> void:
	height = from_height
	backs_alpha = alpha
	phase = Phase.FALL if from_height > 0 else Phase.FADE_IN
	_t = roundi(alpha * FADE_TICKS)
	if backs:
		backs.modulate.a = backs_alpha


## 110's opening, [param elapsed] ticks on; [param fading] while the screen
## still fades in.
func advance(elapsed: int, fading: bool) -> void:
	if phase == Phase.WAIT:
		if fading:
			return
		phase = Phase.FADE_OUT                  # this pass is the fade's first
		_t = 0
	match phase:
		Phase.FADE_OUT:
			_t += elapsed
			backs_alpha = maxf(1.0 - float(_t) / FADE_TICKS, 0.0)
			if _t >= FADE_TICKS:
				phase = Phase.RISE                # its tick 0: the clinks start
				_t -= FADE_TICKS
				height = rise_height(_t)
				MwSound.fm_effect(SOUND)
		Phase.RISE:
			_t += elapsed
			height = rise_height(_t)
			if _t >= RISE_TICKS:
				phase = Phase.UP
	place()


## The rise's height [param t] ticks in: accelerating from rest (a quadratic
## ease-in), off the top at [constant RISE_TICKS].
static func rise_height(t: int) -> int:
	var f := clampf(float(t) / RISE_TICKS, 0.0, 1.0)
	return floori(HEIGHT * f * f)


## True while the wall moves or the backgrounds fade (110's opening).
func busy() -> bool:
	return phase in [Phase.WAIT, Phase.FADE_OUT, Phase.RISE, Phase.FALL, Phase.FADE_IN]


## The game setup: the slam has landed; the logo backgrounds fade back in.
func landed() -> void:
	if phase == Phase.FALL:
		phase = Phase.FADE_IN
		height = 0


## The game setup, [param elapsed] ticks on: the logo backgrounds fade back
## in, then everything goes back into the window.
func come_in(elapsed: int) -> void:
	if phase != Phase.FADE_IN:
		return
	_t += elapsed
	backs_alpha = minf(float(_t) / FADE_TICKS, 1.0)
	if backs:
		backs.modulate.a = backs_alpha
	if _t >= FADE_TICKS:
		finish()


## The game setup at once (a press): in place, merged, the panels going on.
func finish() -> void:
	height = 0
	backs_alpha = 1.0
	merge()
	phase = Phase.DONE


## The wall and the backgrounds where they are now (110's opening).
func place() -> void:
	for i in group.size():
		group[i].position.y = _group_y[i] - height
	if backs:
		backs.modulate.a = backs_alpha


## Back into the window: the lifted cells where it has holes, the logos into
## their panels; the layers gone, the panels' cycle going on.
func merge() -> void:
	var plane := menu.plane
	for layer: RomPlane in [backs, names]:
		if layer == null:
			continue
		for at in layer.get_used_cells():
			if int(plane.cell(at.x, at.y)["key"]) == 0:
				_move_cell(layer, plane, at.x, at.y)
	if logos != null:
		for team_panel in menu.panels:
			for sprite: RomSprite in [team_panel.ring, team_panel.logo]:
				sprite.reparent(team_panel, true)
			team_panel.move_child(team_panel.ring, 0)
			team_panel.move_child(team_panel.logo, 1)
	for n: Node in [backs, logos, names, title]:
		if n != null:
			n.get_parent().remove_child(n)
			n.queue_free()
	backs = null
	logos = null
	names = null
	title = null
	for panel in menu.panels:
		panel.release()


## The state the game setup needs for the mirror: [height, alpha].
func state() -> Array:
	return [height, backs_alpha]


func _layer(n: String) -> RomPlane:
	var plane := RomPlane.new()
	plane.name = n
	plane.tiles = menu.plane.tiles
	plane.palette = menu.plane.palette
	_under_window(plane)
	return plane


## [param node] right under the window (above what is there already).
func _under_window(node: Node) -> void:
	menu.add_child(node)
	menu.move_child(node, menu.plane.get_index())


static func _move_cell(from: RomPlane, to: RomPlane, x: int, y: int) -> void:
	var c := from.cell(x, y)
	if int(c["key"]) == 0:
		return
	to.put(x, y, c["key"], c["line"], c["hflip"], c["vflip"])
	from.put(x, y, 0, 0)
