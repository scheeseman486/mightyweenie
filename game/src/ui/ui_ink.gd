class_name MwUiInk
extends RefCounted
## Plan 40 (M8): the port's menu tints, one owner each (a layer's modulate).

## A refusal or a clash: the light font's white letters tinted red (the
## port menus' collisions and ABACABB MODE, the keyboard's and the text
## entry's refused paste).
const RED := Color(1.0, 0.25, 0.2)
## Not there yet, an example: half grey (the port menus' dimmed items,
## CREATE-A-TEAM's fixed play, the text entry's example).
const DIM := Color(0.5, 0.5, 0.5)
## Darker: a pair's partner, the character cards' and selection's away.
const DARK := Color(0.42, 0.42, 0.42)


## Plan 40 (M8): a layer like [param src] (its tiles, palette and place),
## empty, named [param name_], tinted [param tint], under [param parent] -
## at child index [param at] (-1: last).
static func layer_like(parent: Node, src: RomPlane, name_: String, tint := Color.WHITE, at := -1) -> RomPlane:
	var plane := src.duplicate() as RomPlane
	plane.clear()
	plane.name = name_
	plane.modulate = tint
	parent.add_child(plane)
	if at >= 0:
		parent.move_child(plane, at)
	return plane
