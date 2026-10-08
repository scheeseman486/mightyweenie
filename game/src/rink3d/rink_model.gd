@tool
class_name MwRinkModel
extends Node3D
## The 3D rink (plan 14): the glTF made in Blender from the physics tables
## (tools/blender/rink_build.py -> game/assets/rink3d/rink.glb: geometry and
## UVs only) with materials made here from the ROM when the scene loads, in
## the editor and in the game. Each of the model's objects maps one ROM
## picture (UV0 = its pixels) with one of the rink shaders; the stadium's
## colours come from [member palette]. Nothing decoded is saved.
##
## Objects: floor (rink picture, the ice), wall (rink picture: the solid
## boards, padding facing the rink and the dark grey wall outside, one-sided),
## near_wall (rink picture: the near end's outer wall, drawn after the
## standing sprites), glass (rink picture, translucent, solid posts), signs
## and signs_glass (picture_04a066), fence (picture_03c264, two-sided), bench
## and bench_glass (the pens, benches and referee's box: the rink picture's
## kick strip and riveted tile, two-sided, and glass).

const MODEL := "res://assets/rink3d/rink.glb"
const SHADERS := {
	"floor": preload("res://src/rink3d/rink3d_floor.gdshader"),
	"wall": preload("res://src/rink3d/rink3d_wall.gdshader"),
	"wall_front": preload("res://src/rink3d/rink3d_wall_front.gdshader"),
	"glass": preload("res://src/rink3d/rink3d_glass.gdshader"),
	"fence": preload("res://src/rink3d/rink3d_fence.gdshader"),
}
## object -> [ROM picture, shader, glass rows (picture rows [start, end) x2),
## rows where colour 3 is see-through too ([start, end)), posts (rows [start,
## end) where the posts stay solid, the row their columns are found on)]
const OBJECTS := {
	"floor": [MwRink3D.PICTURE_RINK, "floor", Vector4.ZERO],
	"wall": [MwRink3D.PICTURE_RINK, "wall", Vector4.ZERO],
	"near_wall": [MwRink3D.PICTURE_RINK, "wall_front", Vector4.ZERO],
	"glass": [MwRink3D.PICTURE_RINK, "glass", Vector4(40, 70, 808, 833), Vector2.ZERO, Vector3(808, 834, 820)],
	"signs": [MwRink3D.PICTURE_SIGNS, "wall", Vector4.ZERO],
	"signs_glass": [MwRink3D.PICTURE_SIGNS, "glass", Vector4(9, 40, 0, 0), Vector2(0, 9), Vector3(9, 40, 20)],
	"fence": [MwRink3D.PICTURE_FENCE, "fence", Vector4.ZERO],
	"bench": [MwRink3D.PICTURE_RINK, "fence", Vector4.ZERO],
	"bench_glass": [MwRink3D.PICTURE_RINK, "glass", Vector4(808, 833, 0, 0), Vector2.ZERO, Vector3(808, 834, 820)],
}
## A glass post on a picture's reference row: edge (colour 10), a 1-2 px middle
## in glass colours, edge.
const POST_EDGE := 10
## Render priority of what is drawn after the standing sprites and tested
## against their depth: the glass and the near end's outer wall (MwSprites3D).
const IN_FRONT_PRIORITY := 10

## The stadium's palette (the rink's: screen 4).
@export var palette: RomPalette:
	set(v):
		if palette and palette.changed.is_connected(_update_palette):
			palette.changed.disconnect(_update_palette)
		palette = v
		if palette:
			palette.changed.connect(_update_palette)
		_update_palette()

static var _pictures := {}
static var _posts := {}
static var _ice_mask: ImageTexture
var _model: Node3D
var _materials := {}


func _ready() -> void:
	build()


## The model's mesh instances by object name.
func meshes() -> Dictionary:
	var out := {}
	if _model == null:
		return out
	for name in OBJECTS:
		var n := _model.find_child(name, true, false)
		if n is MeshInstance3D:
			out[name] = n
	return out


## A ROM picture as an indexed (R8) texture, decoded once.
static func picture_texture(address: int) -> ImageTexture:
	if not _pictures.has(address):
		if not MwRom.available():
			return null
		var rom := MwRom.data()
		var img := MwGfx.picture_image(rom, MwGfx.picture(rom, address))
		_pictures[address] = ImageTexture.create_from_image(
				Image.create_from_data(img["w"], img["h"], false, Image.FORMAT_R8, img["px"]))
	return _pictures[address]


## The columns of a picture's glass posts as a w x 1 R8 texture (255 = post):
## the edges found on [ref_row] and the 1-2 px between two edges. Decoded once.
static func post_columns(address: int, ref_row: int) -> ImageTexture:
	var key := "%d:%d" % [address, ref_row]
	if not _posts.has(key):
		if not MwRom.available():
			return null
		var rom := MwRom.data()
		var img := MwGfx.picture_image(rom, MwGfx.picture(rom, address))
		var w: int = img["w"]
		var px: PackedByteArray = img["px"]
		var mask := PackedByteArray()
		mask.resize(w)
		var last := -100
		for c in w:
			if px[ref_row * w + c] == POST_EDGE:
				mask[c] = 255
				if c - last >= 2 and c - last <= 3:
					for m in range(last + 1, c):
						mask[m] = 255
				last = c
		_posts[key] = ImageTexture.create_from_image(Image.create_from_data(w, 1, false, Image.FORMAT_R8, mask))
	return _posts[key]


## Loads the model and makes its materials (once). Safe off the scene tree
## and on a worker thread (plan 20, MwRink3DHost); [method _ready] does it if
## nobody did.
func build() -> void:
	if _model != null:
		return
	var scene := load(MODEL) as PackedScene
	if scene == null:
		push_warning("MwRinkModel: %s missing (tools/bin/rink3d-blender)" % MODEL)
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model, false, Node.INTERNAL_MODE_FRONT)    # internal: never saved with the scene
	for name in OBJECTS:
		var spec: Array = OBJECTS[name]
		var m := ShaderMaterial.new()
		m.shader = SHADERS[spec[1]]
		m.set_shader_parameter("picture", picture_texture(spec[0]))
		if spec[1] == "glass":
			m.set_shader_parameter("glass_rows", spec[2])
			m.set_shader_parameter("clear_rows", spec[3])
			var posts: Vector3 = spec[4]
			m.set_shader_parameter("post_cols", post_columns(spec[0], int(posts.z)))
			m.set_shader_parameter("post_rows", Vector2(posts.x, posts.y))
		if spec[1] == "floor":
			m.set_shader_parameter("ice_mask", ice_mask())
		if spec[1] == "glass" or spec[1] == "wall_front":
			m.render_priority = IN_FRONT_PRIORITY
		_materials[name] = m
	var found := meshes()
	for name in found:
		(found[name] as MeshInstance3D).material_override = _materials[name]
	_update_palette()


## The ice as an R8 mask over the rink picture (255 inside the boards, the
## physics boundary: the straight boards `BOARD_X` / `BOARD_Y` and the corner
## tables `$1C77E` far / `$1C81E` near, as MwSimCollide.corner reads them),
## built once. Plan 16: the floor shows only the ice; everything around it
## (the flat crowd, boards, signs, the pens) is black in 3D.
static func ice_mask() -> ImageTexture:
	if _ice_mask != null or not MwRom.available():
		return _ice_mask
	var rom := MwRom.data()
	var pic := picture_texture(MwRink3D.PICTURE_RINK)
	var w := pic.get_width()
	var h := pic.get_height()
	var px := PackedByteArray()
	px.resize(w * h)
	for row in h:
		var y := row - MwRink3D.MAP_ORIGIN.y           # the rink y on the ice under this row
		var limit := ice_half_width(rom, y)
		for x in range(maxi(1 - limit, -MwRink3D.MAP_ORIGIN.x), mini(limit, w - MwRink3D.MAP_ORIGIN.x)):
			px[row * w + x + MwRink3D.MAP_ORIGIN.x] = 255
	_ice_mask = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_R8, px))
	return _ice_mask


## The ice's half width at rink row [param y]: points with |x| below it are
## inside the boards (0: none).
static func ice_half_width(rom: PackedByteArray, y: int) -> int:
	var ay := absi(y)
	if ay >= MwSimCollide.BOARD_Y:
		return 0
	var lo := 0x144 if y >= 0 else 0x12A
	if ay < lo:
		return MwSimCollide.BOARD_X
	var tab := MwSimCollide.CORNER_BOTTOM if y >= 0 else MwSimCollide.CORNER_TOP
	return maxi(MwGfx.s16(rom, tab + 2 * (ay - lo) + 2), 0x6C)


func _update_palette() -> void:
	var tex: Texture2D = palette.texture() if palette else null
	for m: ShaderMaterial in _materials.values():
		m.set_shader_parameter("palette", tex)
