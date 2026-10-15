@tool
class_name MwScreenPalettes
extends RefCounted
## Which palette recipe ([RomPalette] steps) each screen fades to, as found
## by the checkpoints of test_gfx_original.py (docs/re/graphics.md). Used for
## editor previews and as the starting point of the screen scenes. Colours
## the screens animate at run time are not part of it.

## Plan 40 (R6): the rink's recipe, by name (screens 4-7, the 3D view, the
## matchup's opening, the rink editor; the rink and replay scenes add the
## port's player lines: [method rink]).
const RINK := ["screen_palette", "rom 1BD8A 3"]
## The team names' own colours (plan 38): team A's on line 1, team B's on 2
## ([method names]).
const NAMES := ["name_colours a 1", "name_colours b 2"]

const RECIPES := {
	1: ["screen_palette", "ice_line", "menu_line 0"],
	2: ["screen_palette", "panel_line a 0", "rom 1BD6A 2"],
	3: ["screen_palette"],
	4: RINK,
	5: RINK,
	6: RINK,
	7: RINK,
	8: ["screen_palette", "black 0", "panel_line a 1", "panel_line b 2"],
	9: ["screen_palette", "black 0", "panel_line a 1", "panel_line b 2"],
	10: ["screen_palette", "rom 1BE16 3"],
	11: ["screen_palette", "black 0", "rom 399B0 2"],
}
## Screen 0 changes palette per picture.
const TITLE := {
	"picture_039b9e": ["rom 3BF7A 2"],
	"picture_030148": ["rom 36C64 0", "rom 36C84 1"],
	"picture_04546c": ["screen_palette", "rom 1BD6A 0", "rom 1BB22 1"],
}


## The recipe ([RomPalette] steps) screen [param screen] fades to - on screen 0 picture
## [param key]'s (picture_04546c's when unknown); the screen palette alone for a screen not listed.
static func steps(screen: int, key := "") -> PackedStringArray:
	if screen == 0:
		return PackedStringArray(TITLE.get(key, TITLE["picture_04546c"]))
	return PackedStringArray(RECIPES.get(screen, ["screen_palette"]))


## A palette for [param screen] (and, on screen 0, the picture [param key]).
static func palette(screen: int, key := "", team_a := 0, team_b := 5, stadium := 0) -> RomPalette:
	var screen_palette := RomPalette.new()
	screen_palette.screen = screen
	screen_palette.team_a = team_a
	screen_palette.team_b = team_b
	screen_palette.stadium = stadium
	screen_palette.steps = steps(screen, key)
	return screen_palette


## The tile banks a screen loads, the [param last] one placed last (it wins
## where banks overlap).
static func banks(screen: int, last := "") -> PackedStringArray:
	var out := PackedStringArray()
	for kind in ["picture", "tilebank"]:
		for k in MwRom.keys(kind, screen):
			if k != last:
				out.append(k)
	if last != "":
		out.append(last)
	return out


## The rink's palette ([constant RINK]) for teams [param team_a] /
## [param team_b] in [param stadium] ([param ports]: with the port's player
## lines, plan 34).
static func rink(team_a := 0, team_b := 5, stadium := 0, ports := false) -> RomPalette:
	var recipe := PackedStringArray(RINK)
	if ports:
		recipe.append("player_lines")
	return RomPalette.make(4, recipe, team_a, stadium, team_b)


## The palette a screen writes its team names in: [param base]'s, kept in
## step with it, with the teams' own name colours (plan 38) - both teams'
## ([param sides] 2) or team A's alone (1).
static func names(base: RomPalette, sides := 2) -> RomPalette:
	return RomPalette.follow(base, PackedStringArray(NAMES.slice(0, sides)))
