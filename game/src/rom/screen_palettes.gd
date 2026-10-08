@tool
class_name MwScreenPalettes
extends RefCounted
## Which palette recipe ([RomPalette] steps) each screen fades to, as found
## by the checkpoints of test_gfx_original.py (docs/re/graphics.md). Used for
## editor previews and as the starting point of the screen scenes. Colours
## the screens animate at run time are not part of it.

const RECIPES := {
	1: ["screen_palette", "ice_line", "menu_line 0"],
	2: ["screen_palette", "panel_line a 0", "rom 1BD6A 2"],
	3: ["screen_palette"],
	4: ["screen_palette", "rom 1BD8A 3"],
	5: ["screen_palette", "rom 1BD8A 3"],
	6: ["screen_palette", "rom 1BD8A 3"],
	7: ["screen_palette", "rom 1BD8A 3"],
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


static func steps(screen: int, key := "") -> PackedStringArray:
	if screen == 0:
		return PackedStringArray(TITLE.get(key, TITLE["picture_04546c"]))
	return PackedStringArray(RECIPES.get(screen, ["screen_palette"]))


## A palette for [param screen] (and, on screen 0, the picture [param key]).
static func palette(screen: int, key := "", team_a := 0, team_b := 5, stadium := 0) -> RomPalette:
	var p := RomPalette.new()
	p.screen = screen
	p.team_a = team_a
	p.team_b = team_b
	p.stadium = stadium
	p.steps = steps(screen, key)
	return p


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
