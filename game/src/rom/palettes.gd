@tool
class_name MwPalettes
extends RefCounted
## Palette builders: how the original composes CRAM from ROM pieces
## (docs/re/graphics.md, Palettes), mirroring harness/mw_harness/palettes.py.
## They return Genesis colour words; [method texture] turns 64 of them into the
## palette texture the palette-swap shader reads.
##
## * `$215E` [method screen_palette] - all four lines; every screen.
## * `$22A6` [method team_line] - a team's line (styles 1/2).
## * `$235E` [method ice_line] - line 0 = the stadium's ice palette.
## * `$2398` [method menu_line] - line 3 of the main menu.
## * `$23B0` [method panel_line] - a team's colours on a panel line.

const TEAM_TABLE := 0x18D8A
const TEAM_SIZE := 0x9E
const DEFAULT_PALETTE := 0x1BD0A
const TEAM_LINE_BASES := {1: 0x1BD2A, 2: 0x1BD4A}
const MENU_LINES := 0x1BE0A
const ICE_PALETTES := 0x1BE36
const COLOUR_PAIRS := 0x1BE4E
const PAIR_FLAGS := 0x1BE5A
const PANEL_COLOURS := 0x1BE6E


static func team_record(team: int) -> int:
	return TEAM_TABLE + team * TEAM_SIZE


## Address of the ice palette of stadium [param stadium] ($FFB0E4).
static func ice_palette(rom: PackedByteArray, stadium: int) -> int:
	var record := MwGfx.u32(rom, team_record(stadium) + 0x10)
	return MwGfx.u32(rom, ICE_PALETTES + 4 * rom[record + 4])


## The colour pair for colours 1 and 10 of lines 1-2 ($21B0).
static func colour_pair(rom: PackedByteArray, screen: int, pal := false) -> PackedInt32Array:
	var table := COLOUR_PAIRS
	if rom[PAIR_FLAGS + screen]:
		table += 8 if pal else 4
	return MwGfx.words(rom, table, 2)


static func _team_colours(rom: PackedByteArray, team: int, line: PackedInt32Array, at: int) -> void:
	var c := team_record(team) + 0x80
	var w := MwGfx.words(rom, c, 2)
	line[at + 2] = w[0]; line[at + 3] = w[1]
	w = MwGfx.words(rom, c + 4, 2)
	line[at + 5] = w[0]; line[at + 6] = w[1]
	w = MwGfx.words(rom, c + 0x10, 2)
	line[at + 7] = w[0]; line[at + 8] = w[1]
	line[at + 9] = MwGfx.u16(rom, c + 0x14)


## `$215E`: 64 colours (see the class description and graphics.md).
static func screen_palette(rom: PackedByteArray, screen: int, team_a: int, stadium: int,
		pal := false) -> PackedInt32Array:
	var p := MwGfx.words(rom, DEFAULT_PALETTE, 64)
	var ice := MwGfx.words(rom, ice_palette(rom, stadium), 16)   # 8 longs: all of line 0
	for i in 16:
		p[i] = ice[i]
	p[16 + 11] = p[5]
	p[32 + 11] = p[5]
	var pair := colour_pair(rom, screen, pal)
	p[16 + 1] = pair[0]; p[32 + 1] = pair[0]
	p[16 + 10] = pair[1]; p[32 + 10] = pair[1]
	_team_colours(rom, team_a, p, 16)
	return p


## `$22A6`: style 1 = `$1BD2A` + the team's colours, style 2 = `$1BD4A`.
static func team_line(rom: PackedByteArray, screen: int, team: int, stadium: int, style: int,
		pal := false) -> PackedInt32Array:
	var line := MwGfx.words(rom, TEAM_LINE_BASES[style], 16)
	var pair := colour_pair(rom, screen, pal)
	line[1] = pair[0]
	line[10] = pair[1]
	if style != 2:
		_team_colours(rom, team, line, 0)
	line[11] = MwGfx.u16(rom, ice_palette(rom, stadium) + 10)
	return line


## `$235E` + `$149B2`: the ice palette with colour 0 black.
static func ice_line(rom: PackedByteArray, stadium: int) -> PackedInt32Array:
	var line := MwGfx.words(rom, ice_palette(rom, stadium), 16)
	line[0] = 0
	return line


## `$2398`: one of the main menu's three line-3 palettes.
static func menu_line(rom: PackedByteArray, index: int) -> PackedInt32Array:
	return MwGfx.words(rom, MwGfx.u32(rom, MENU_LINES + 4 * index), 16)


## `$23B0`: panel colours around the seven team colours at [param colours]
## (a team record's +$7C pointer).
static func panel_line(rom: PackedByteArray, screen: int, colours: int, pal := false) -> PackedInt32Array:
	var line := MwGfx.words(rom, PANEL_COLOURS, 2)
	line.append_array(MwGfx.words(rom, colours, 7))
	line.append_array(MwGfx.words(rom, PANEL_COLOURS + 4, 7))
	var pair := colour_pair(rom, screen, pal)
	line[1] = pair[0]
	line[10] = pair[1]
	return line


static func team_panel_line(rom: PackedByteArray, screen: int, team: int) -> PackedInt32Array:
	return panel_line(rom, screen, MwGfx.u32(rom, team_record(team) + 0x7C))


## The palette texture for the palette-swap shader: 64x1 RGBA, colour i at
## x = i; colour 0 of each line has alpha 0 (transparent).
static func texture(colours: PackedInt32Array) -> ImageTexture:
	var img := Image.create_empty(64, 1, false, Image.FORMAT_RGBA8)
	for i in mini(colours.size(), 64):
		var c := MwGfx.color(colours[i])
		c.a = 0.0 if i % 16 == 0 else 1.0
		img.set_pixel(i, 0, c)
	return ImageTexture.create_from_image(img)


# --- builder cases hashed for the tests (palettes.builder_cases) -------------------
static func builder_cases() -> Array:
	var cases := []
	for screen in [1, 3, 4, 14, 18]:
		for ts in [[0, 0], [5, 12], [22, 22]]:
			cases.append(["screen_palette", [screen, ts[0], ts[1]]])
	for ts in [[0, 0], [5, 12], [22, 22]]:
		for style in [1, 2]:
			cases.append(["team_line", [1, ts[0], ts[1], style]])
	for s in 23:
		cases.append(["ice_line", [s]])
	for i in 3:
		cases.append(["menu_line", [i]])
	for t in [0, 5, 22]:
		cases.append(["panel_line", [8, t]])
	return cases


static func run_case(rom: PackedByteArray, name: String, args: Array) -> PackedInt32Array:
	match name:
		"screen_palette":
			return screen_palette(rom, args[0], args[1], args[2])
		"team_line":
			return team_line(rom, args[0], args[1], args[2], args[3])
		"ice_line":
			return ice_line(rom, args[0])
		"menu_line":
			return menu_line(rom, args[0])
		"panel_line":
			return team_panel_line(rom, args[0], args[1])
	return PackedInt32Array()
