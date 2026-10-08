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


static func make(screen_: int, steps_: PackedStringArray, team_a_ := 0, stadium_ := 0) -> RomPalette:
	var p := RomPalette.new()
	p.screen = screen_
	p.steps = steps_
	p.team_a = team_a_
	p.stadium = stadium_
	return p


func _changed() -> void:
	_colours = PackedInt32Array()
	_texture = null
	emit_changed()


## The 64 Genesis colour words (empty without the ROM).
func colours() -> PackedInt32Array:
	if _colours.is_empty() and MwRom.available():
		_colours = build(MwRom.data())
	return _colours


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
			_:
				push_warning("RomPalette: unknown step '%s'" % step)
	return c


func _team(which: String) -> int:
	return team_a if which == "a" else team_b


static func _put(c: PackedInt32Array, line: int, words: PackedInt32Array) -> void:
	for i in 16:
		c[16 * line + i] = words[i]


## 64x1 palette texture for the palette-swap shader.
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
