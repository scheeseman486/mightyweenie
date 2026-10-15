class_name MwScrollArrows
extends RefCounted
## Plan 40 (M3): a list's scroll arrows and its "keep the selection in view"
## - the port menus' lists and bindings, CREATE-A-TEAM's team list. The two
## arrows are the rink's off-screen arrow (the pad's, MwRinkMatch.ARROWS),
## the up one hanging from its top, the down one standing on its foot; the
## ones shown side by side round the screen's middle.


## The two arrows (up, down) for [param parent], on [param palette].
static func make(parent: Node, palette: RomPalette) -> Array[RomSprite]:
	var out: Array[RomSprite] = []
	for v in [MwPortMenu.ARROW_UP, MwPortMenu.ARROW_DOWN]:
		var sprite := RomSprite.new()
		sprite.name = "ScrollUp" if v == MwPortMenu.ARROW_UP else "ScrollDown"
		sprite.palette = palette
		sprite.attr_xor = MwPortMenu.ARROW_XOR
		sprite.variant = v
		sprite.visible = false
		parent.add_child(sprite)
		out.append(sprite)
	return out


## [param arrows] ([method make]'s) shown as [param up] / [param down] say,
## side by side round x 160, the up one's top at [param top] px.
static func place(arrows: Array[RomSprite], rom: PackedByteArray, up: bool, down: bool, top: int) -> void:
	arrows[0].visible = up
	arrows[1].visible = down
	var on := arrows.filter(func(a: RomSprite) -> bool: return a.visible)
	var w := MwPortMenu.ARROW_W
	@warning_ignore("integer_division")
	var x := 160 - (on.size() * (w + MwPortMenu.ARROW_GAP) - MwPortMenu.ARROW_GAP) / 2
	var anim := "%X" % MwGfx.u32(rom, MwRinkMatch.ARROWS + 4 * MwPortMenu.ARROW_PAD)
	for sprite: RomSprite in on:
		if sprite.anim != anim:
			sprite.anim = anim
		# the origin is the arrow's middle; the up variant hangs from it, the down one stands on it
		@warning_ignore("integer_division")
		sprite.position = Vector2(x + w / 2, top if sprite == arrows[0] else top + w)
		x += w + MwPortMenu.ARROW_GAP


## A list's first shown entry ([param first] before) so that entry
## [param sel] is among the [param shown] from it; [param count] >= 0:
## never past the list's end either.
static func follow(first: int, sel: int, shown: int, count := -1) -> int:
	var f := clampi(first, sel - shown + 1, sel)
	if count >= 0:
		f = clampi(f, 0, maxi(count - shown, 0))
	return f
