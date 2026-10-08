class_name MwScreenDraw
extends MwRinkDraw
## The sprite list of a screen between plays: a pass's sprite operations
## ([member MwScreenSim.sprite_ops], screen pixels: these screens draw
## through the window plane or an unscrolled plane B) through the original's
## primitives (`draw_frame` `$A07E`, `draw_anim_object` `$14444`,
## `add_sprite_piece` `$156C6`, `draw_text_sprites` `$F3CC`, the portrait
## `$B61C`): depth-sorted and clipped as the VDP list the original builds.
##
## An "anim" operation with a ninth value (a screen row: the scoreboards'
## players standing behind the boards) cuts its pieces' pixels from that
## row down: its entries carry the row (sprite coordinates) as a seventh
## value, which [MwSpriteLayer] honours. Not the original's (owner);
## [member cut_rows] false draws as the original (the visual check).

## Whether operations' cut rows apply (false: exactly the original's pixels).
static var cut_rows := true


## The sprite list ([method MwRinkDraw.sprites]) of [param ops] for [param s].
func list(s: MwRinkState, ops: Array) -> Array:
	state = s
	calls = []
	adds = []
	_entries = [[0, 0, 0, 0, 0, 0]]
	_links = PackedInt32Array([0])
	for op in ops:
		var o: Array = op
		var p: Vector3i
		match str(o[0]):
			"anim":
				# ["anim", record, variant, frame, x, y, depth, attr]
				p = to_sprite(Vector3i(int(o[4]), int(o[5]), int(o[6])), false)
				var first := _entries.size()
				draw_anim_frame(int(o[1]), int(o[2]), int(o[3]), p.x, p.y, int(o[6]), int(o[7]))
				if o.size() > 8 and cut_rows:
					var row := to_sprite(Vector3i(0, int(o[8]), 0), false).y
					for i in range(first, _entries.size()):
						(_entries[i] as Array).append(row)
			"frame":
				# ["frame", frame, x, y, depth, attr]
				p = to_sprite(Vector3i(int(o[2]), int(o[3]), int(o[4])), false)
				draw_frame(p.x, p.y, int(o[4]), int(o[5]), int(o[1]))
			"piece", "portrait", "sprite_text":
				phase_sprite(o)
			_:
				push_warning("MwScreenDraw: unknown sprite operation %s" % str(o[0]))
	return sprites()
