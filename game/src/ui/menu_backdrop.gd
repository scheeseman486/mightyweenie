class_name MwMenuBackdrop
extends RefCounted
## Plan 40 (M5): what the port's menu pages share of the game setup's
## backdrop - the palette their pages draw in and the logo cut from the
## backdrop's picture (the port menus, CREATE-A-TEAM's list, the game
## setup's logo apart). Each page keeps its own transitions and stars.

## The menu pages' palette: the screen's, colour 0 black, team A's panel
## on line 1, colour 31 see-through (the logo's black panel).
const STEPS := ["screen_palette", "black 0", "panel_line a 1", "clear 31"]


## The logo (MwPortMenu.LOGO of the backdrop's picture,
## MwPortMenu.BACKDROP) on [param plane] at cell ([param x], [param y]).
static func logo(plane: RomPlane, rom: PackedByteArray, x: int, y: int) -> void:
	var pic := MwGfx.picture(rom, MwPortMenu.BACKDROP)
	var w: int = pic["width"]
	var r := MwPortMenu.LOGO
	MwPlanePainter.map_rect(plane, rom, int(pic["map"]) + 2 * (r.position.y * w + r.position.x), w, r.size.x, r.size.y,
			x, y)
