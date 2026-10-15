@tool
class_name RomPalette
extends Resource
## A palette built from the ROM when used: this resource stores only the
## recipe (which builders and ROM palettes, for which screen, teams and
## stadium), never colours. See docs/re/graphics.md, Palettes.
##
## Steps, applied in order to 64 colours that start black:
## [codeblock]
## screen_palette            $215E: all four lines
## rom <hex address> <line>  16 colours from the ROM as they are
## ice_line                  line 0 = the stadium's ice palette, colour 0 black
## team_line <a|b> <line> <style>
## panel_line <a|b> <line>
## menu_line <0-2>           line 3
## black <index>             one colour set to black ($149B2)
## word <hex address> <index> one colour = the ROM word there (a code
##                           constant, e.g. the credit pages' colours 9-10)
## clear <index>             one colour transparent (the port's own screens:
##                           the logo's black panel on the port menus)
## darker <index> <levels>   one colour darker by that many of the 8 levels of
##                           each channel (the port's: the pause menu's
##                           secondary when a team's two colours are alike)
## colour <index> <hex word> one colour set to that word (the port's: the
##                           CREATE-A-TEAM editor's colours, plan 38)
## coach_colours <a|b> <line> the team's coach's own colours on that line
##                           (2-3, 5-9), when a custom coach has some (plan 38)
## coach_line <a|b> <from> <to> line <from> copied to line <to> (past the
##                           four, as plan 34's lines) with the team's
##                           coach's own colours on it (plan 38: his portrait
##                           drawn on it, MwRinkDraw.portrait_lines)
## name_colours <a|b> <line> the team's name's own colours on that line
##                           (2-3, the big letters' face and shade), when a
##                           custom team has some (plan 38; a palette of the
##                           names' own: [method follow])
## player_lines              lines 4-11 after the four (the port's, plan 34):
##                           line 3 with the crossbones' face colour
##                           (MwPlayerColours.face_index of pad 1's frame)
##                           in players 5-12's colours - the rink's markers
##                           and arrows for them (MwRinkDraw.PORT_LINE)
## [/codeblock]

const SHADER := preload("res://src/rom/palette_swap.gdshader")

@export var screen := 0:
	set(v):
		screen = v
		_changed()
@export_range(0, 22) var team_a := 0:
	set(v):
		team_a = v
		_changed()
@export_range(0, 22) var team_b := 5:
	set(v):
		team_b = v
		_changed()
@export_range(0, 22) var stadium := 0:
	set(v):
		stadium = v
		_changed()
@export var steps := PackedStringArray(["screen_palette"]):
	set(v):
		steps = v
		_changed()

var _colours := PackedInt32Array()
var _texture: ImageTexture
var _clear := PackedInt32Array()      # indices the "clear" steps made transparent
var _bank := -1                       # MwCustomTeams.version built with (custom teams change)
var _extra := PackedStringArray()     # a following palette's own steps ([method follow])
var _setting := false                 # [method set_recipe] under way: one change told at its end


## A new palette of this recipe: screen [param screen_]'s [param steps_] for team A
## [param team_a_] and stadium [param stadium_]; team B [param team_b_] when given (>= 0).
static func make(screen_: int, steps_: PackedStringArray, team_a_ := 0, stadium_ := 0, team_b_ := -1) -> RomPalette:
	var palette := RomPalette.new()
	palette.screen = screen_
	palette.steps = steps_
	palette.team_a = team_a_
	palette.stadium = stadium_
	if team_b_ >= 0:
		palette.team_b = team_b_
	return palette


## Plan 40 (R6): a copy of [param base]'s recipe as it is now (screen,
## teams, stadium, steps) with [param extra] steps after it and, given,
## another team A ([param team_a_]) - unlike [method follow], it doesn't
## follow later changes. The custom coaches' palettes, the info plates' and
## the crowd's lines per team are made this way.
static func derived(base: RomPalette, extra := PackedStringArray(), team_a_ := -1) -> RomPalette:
	var palette := make(base.screen, base.steps + extra, team_a_ if team_a_ >= 0 else base.team_a, base.stadium,
			base.team_b)
	return palette


func _changed() -> void:
	if _setting:
		return
	_colours = PackedInt32Array()
	_texture = null
	emit_changed()


## The recipe's screen, teams, stadium and steps at once: built again and
## its users told once ([signal changed]), and not at all when nothing
## changes - the rink entered again in the same match (a faceoff, after a
## goal's scoreboard) told them five times, ~15 ms of a screen change that
## holds the main thread (owner, 2026-10-13: dropouts). True if it changed.
func set_recipe(screen_: int, team_a_: int, team_b_: int, stadium_: int, steps_: PackedStringArray) -> bool:
	if screen_ == screen and team_a_ == team_a and team_b_ == team_b and stadium_ == stadium and steps_ == steps:
		return false
	_setting = true
	screen = screen_
	team_a = team_a_
	team_b = team_b_
	stadium = stadium_
	steps = steps_
	_setting = false
	_changed()
	return true


## A palette for what [param base]'s screen writes in team names alone:
## [param base]'s recipe with [param extra] steps after it, kept in step
## with [param base] as it changes (its screen, teams, stadium, steps).
static func follow(base: RomPalette, extra: PackedStringArray) -> RomPalette:
	var palette := RomPalette.new()
	palette._extra = extra
	palette._copy(base)
	base.changed.connect(palette._copy.bind(base))
	return palette


func _copy(base: RomPalette) -> void:
	screen = base.screen
	team_a = base.team_a
	team_b = base.team_b
	stadium = base.stadium
	var new_steps := base.steps.duplicate()
	new_steps.append_array(_extra)
	steps = new_steps


## Built again now (a custom team's colours edited), its users told
## ([signal changed]: materials and textures made from it follow).
func refresh() -> void:
	_changed()


## The 64 Genesis colour words (empty without the ROM).
func colours() -> PackedInt32Array:
	if _bank != MwCustomTeams.version and maxi(maxi(team_a, team_b), stadium) >= MwTeams.COUNT:
		_colours = PackedInt32Array()      # a custom team was edited: build again
		_texture = null
	if _colours.is_empty() and MwRom.available():
		_colours = build(MwRom.data())
		_bank = MwCustomTeams.version
	return _colours


## The colours [member steps] make, applied in order to 64 black ones (player_lines adds 128 more;
## an unknown step warns and is passed over); the clear steps' indices are kept for the texture.
func build(rom: PackedByteArray) -> PackedInt32Array:
	var c := PackedInt32Array()
	c.resize(64)
	_clear = PackedInt32Array()
	for step in steps:
		var a := step.split(" ", false)
		if a.is_empty():
			continue
		match a[0]:
			"screen_palette":
				c = MwPalettes.screen_palette(rom, screen, team_a, stadium)
			"rom":
				_put(c, int(a[2]), MwGfx.words(rom, a[1].hex_to_int(), 16))
			"ice_line":
				_put(c, 0, MwPalettes.ice_line(rom, stadium))
			"team_line":
				_put(c, int(a[2]), MwPalettes.team_line(rom, screen, _team(a[1]), stadium, int(a[3])))
			"panel_line":
				_put(c, int(a[2]), MwPalettes.team_panel_line(rom, screen, _team(a[1])))
			"menu_line":
				_put(c, 3, MwPalettes.menu_line(rom, int(a[1])))
			"black":
				c[int(a[1])] = 0
			"word":
				c[int(a[2])] = MwGfx.u16(rom, a[1].hex_to_int())
			"clear":
				_clear.append(int(a[1]))
			"darker":
				c[int(a[1])] = darker(c[int(a[1])], int(a[2]))
			"colour":
				c[int(a[1])] = a[2].hex_to_int() & 0x0EEE
			"coach_colours":
				_coach_colours(rom, c, _team(a[1]), int(a[2]))
			"coach_line":
				var to := int(a[3])
				while c.size() < 16 * (to + 1):
					c.append(0)
				for i in 16:
					c[16 * to + i] = c[16 * int(a[2]) + i]
				_coach_colours(rom, c, _team(a[1]), to)
			"name_colours":
				var own := MwCustomOverlay.name_colours(rom, MwTeams.record(_team(a[1])))
				for i in own.size():
					c[16 * int(a[2]) + 2 + i] = own[i]
			"player_lines":
				c.append_array(player_lines(rom, c))
			_:
				push_warning("RomPalette: unknown step '%s'" % step)
	return c


## Lines 4-11 (128 colours) for colours [param c]: line 3 again with its
## crossbones face index (pad 1's frame) in players 5-12's colours, player
## 5 first (MwPlayerColours).
static func player_lines(rom: PackedByteArray, c: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var face := MwPlayerColours.face_index(rom, 1)
	for player in range(5, MwPlayerColours.PLAYERS + 1):
		var line := c.slice(48, 64)
		if face > 0:
			line[face] = MwPlayerColours.face(rom, player)
		out.append_array(line)
	return out


func _team(which: String) -> int:
	return team_a if which == "a" else team_b


## Team [param team]'s coach's own colours (plan 38: a custom coach's, none
## for the original's) on line [param line] of [param c]: 2-3, 5-9.
static func _coach_colours(rom: PackedByteArray, c: PackedInt32Array, team: int, line: int) -> void:
	var own := MwCustomOverlay.coach_colours(rom, MwTeams.coach(rom, team))
	for i in own.size():
		c[16 * line + MwCustomCoach.COLOUR_INDICES[i]] = own[i]


## Genesis colour word [param word] darker by [param levels] of each
## channel's 8 levels (none below 0).
static func darker(word: int, levels: int) -> int:
	var out := 0
	for shift in [1, 5, 9]:
		out |= maxi(((word >> shift) & 7) - levels, 0) << shift
	return out


static func _put(c: PackedInt32Array, line: int, words: PackedInt32Array) -> void:
	for i in 16:
		c[16 * line + i] = words[i]


## 64x1 palette texture for the palette-swap shader (wider with
## "player_lines": a line of 16 each).
func texture() -> ImageTexture:
	if _texture == null and not colours().is_empty():
		_texture = MwPalettes.texture(colours())
		if not _clear.is_empty():
			var img := _texture.get_image()
			for i in _clear:
				img.set_pixel(i, 0, Color(0, 0, 0, 0))
			_texture = ImageTexture.create_from_image(img)
	return _texture


## A ShaderMaterial drawing indexed textures with this palette;
## [param shadow_highlight]: line 3's colours 14/15 as translucent
## highlight/shadow (the rink's sprites).
func material(shadow_highlight := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("palette", texture())
	m.set_shader_parameter("shadow_highlight", shadow_highlight)
	return m


## The backdrop colour (CRAM 0: the VDP's background colour register is 0).
func backdrop() -> Color:
	return MwGfx.color(colours()[0]) if not colours().is_empty() else Color.BLACK


## RGBA colour for an indexed value (CPU side: previews, tests).
func rgba(index: int) -> Color:
	if colours().is_empty() or index % 16 == 0:
		return Color(0, 0, 0, 0)
	return MwGfx.color(colours()[index])
