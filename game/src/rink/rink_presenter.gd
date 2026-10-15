class_name MwRinkPresenter
extends RefCounted
## Plan 40 (R5): what the rink scene and the instant replay both do to show
## a frame - the 3D view lent in the view's camera mode, sprite lists put on
## their layers with the info plates' tiles, and the 2D picture in WIDE
## (plan 25): the rink sliding inside its picture, the backdrop over the
## whole picture. Each scene keeps what is its own (the rink: the dead
## reckoning, the live pass, the first pass primed in 3D; the replay: its
## frames' own lists and the records of old frames). The picture's shape
## itself is the 3D host's (MwRink3DHost: it scales the window).


## [param host]'s 3D view lent to [param user] with [param palette], in
## view [param view]'s camera mode ([param across]: birds-eye across).
static func view_3d(host: MwRink3DHost, user: Object, palette: RomPalette, view: int, across: bool) -> MwRinkView3D:
	var borrowed := host.borrow(user, palette)
	borrowed.set_camera_mode(MwRinkViews.camera_mode(view, across))
	return borrowed


## [param list] shown on the sprite [param layers], with the info plates'
## RAM tiles [param tiles].
static func show_list(layers: Array, tiles: Dictionary, list: Array) -> void:
	for layer: MwSpriteLayer in layers:
		layer.ram_tiles = tiles
		layer.show_list(list)


## True when [param user]'s 2D picture is wide (the host's wide picture is
## its, plan 25).
static func wide(host: MwRink3DHost, user: Object) -> bool:
	return host != null and host.wide_user == user and host.is_wide()


## The wide 2D picture's placement for the sim camera's point
## [param shown]: {size: the picture, off: the original's 320 x 224 in it,
## slide: [method wide_slides]}.
static func wide_place(host: MwRink3DHost, shown: Vector2i, rom: PackedByteArray) -> Dictionary:
	var size := Vector2i(host.view_size)
	var off := host.column_origin()
	return {"size": size, "off": off, "slide": wide_slides(shown, size, off, rink_picture_size(rom))}


## The backdrop [param bd] (the ice's colour behind the picture's
## see-through ice) over the whole picture, wide or not.
static func backdrop_fit(bd: Control, host: MwRink3DHost, user: Object) -> void:
	if wide(host, user):
		bd.position = -Vector2(host.column_origin())
		bd.size = host.view_size
	else:
		bd.position = Vector2.ZERO
		bd.size = Vector2(MwRink3D.SCREEN)


## Plan 25: how far the wide 2D picture draws the rink from where the
## original puts it (pixels, + right): the picture [param width] wide, its
## original 320 column [param off] in, shows the rink picture (
## [param picture] pixels wide) from the sim camera's x [param shown] less
## [param off], kept inside the picture (owner: no black beside the boards;
## a picture wider than the rink's: centred on it).
static func wide_slide(shown: int, width: int, off: int, picture: int) -> int:
	var left := shown - off
	var keep := clampi(left, 0, picture - width) if width <= picture else floori((picture - width) / 2.0)
	return left - keep


## [method wide_slide] both ways: the picture [param size] with the
## original's 320 x 224 at [param off], the rink picture [param picture]
## (pixels), the sim camera's point [param shown].
static func wide_slides(shown: Vector2i, size: Vector2i, off: Vector2i, picture: Vector2i) -> Vector2i:
	return Vector2i(wide_slide(shown.x, size.x, off.x, picture.x), wide_slide(shown.y, size.y, off.y, picture.y))


## The rink picture's size (pixels): 512 x 904.
static func rink_picture_size(rom_: PackedByteArray) -> Vector2i:
	var pic := MwGfx.picture(rom_, MwRink3D.PICTURE_RINK)
	return 8 * Vector2i(int(pic["width"]), int(pic["height"]))
