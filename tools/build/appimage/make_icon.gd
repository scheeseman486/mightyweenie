extends SceneTree
## The AppImage's icon (tools/build/appimage.sh): the project's logo
## (game/assets/logo/mightyweenie_logo.png, its own art) scaled up by whole
## pixels, nearest, centred on black in a 256 x 256 PNG - drawn at build
## time, so no image is kept for it.
##   godot --headless --path game -s tools/build/appimage/make_icon.gd -- LOGO.png OUT.png

const SIZE := 256
## The logo's widest at most (a margin left round it).
const ROOM := 240


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var logo := Image.load_from_file(args[0])
	if logo == null:
		quit(1)
		return
	logo.convert(Image.FORMAT_RGBA8)
	var k := maxi(1, ROOM / logo.get_width())
	logo.resize(logo.get_width() * k, logo.get_height() * k, Image.INTERPOLATE_NEAREST)
	var icon := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	icon.fill(Color.BLACK)
	icon.blend_rect(logo, Rect2i(Vector2i.ZERO, logo.get_size()), (Vector2i(SIZE, SIZE) - logo.get_size()) / 2)
	quit(0 if icon.save_png(args[1]) == OK else 1)
