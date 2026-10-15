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
## (picture_04a066: the banners in front of the benches), signs_glass (that
## picture's tall glass with pointed tips, round the pens), fence
## (picture_03c264, two-sided), bench (the pens - benches, penalty boxes -
## and the hallways between them: the rink picture's kick strip and riveted
## tile, two-sided). The pens' walls and glass darken along the hallways
## (rink3d_arch). Plan 37: UV2 is the
## paint atlas's ([method set_paint], MwSplatterAtlas); the objects standing
## on the ice within MwRink3D.REFLECT_FADE px of it ([constant REFLECTED]:
## the padding, the signs, the fence, the glass) are reflected in it by mirrored copies
## of their meshes ([method set_reflections], rink3d_reflect_mesh).
## Owner, 2026-10-11: the banners in front of the benches, the side glass
## half-height on both sides, the tall glass round the pens, a thin post where
## the far end's thick glass ends, the hallways run on and fade to black
## (tools/blender/rink_build.py).

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
}
## A glass post on a picture's reference row: edge (colour 10), a 1-2 px middle
## in glass colours, edge.
const POST_EDGE := 10
## Render priority of what is drawn after the standing sprites and tested
## against their depth: the glass and the near end's outer wall (MwSprites3D).
const IN_FRONT_PRIORITY := 10
## Render priority of the reflections in the ice (plan 37,
## rink3d_reflect.gdshaderinc; MwSprites3D's and MwNet3D's too): after the
## ice's under-ice frames, before its hazards, shadows and markers and the
## standing sprites.
const REFLECT_PRIORITY := -7
const REFLECT_MESH := preload("res://src/rink3d/rink3d_reflect_mesh.gdshader")
const REFLECT_MESH_2S := preload("res://src/rink3d/rink3d_reflect_mesh_2s.gdshader")
## The mirror image under the ice (world y 0) of what stands on it.
const MIRROR := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)), Vector3.ZERO)
## The objects reflected (plan 37) -> [two-sided, mode] (the reflection
## shader's: 0 a picture, 3 the glass): what stands on the ice up to
## MwRink3D.REFLECT_FADE px - the padding (wall: its rink side; its outer
## face never shows in the ice), the signs' boards, the fence and the glass
## on them (from 19 px: its lowest rows, by its own alpha too). The near
## end's outer wall and the pens (bench, and since 2026-10-11 signs_glass:
## the tall glass round them) stand off the ice.
const REFLECTED := {"wall": [false, 0], "signs": [false, 0], "fence": [true, 0], "glass": [true, 3]}

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
var _reflections := {}          # object -> its mirrored MeshInstance3D (plan 37)
var _reflect_materials := {}    # object -> its reflection's material


func _ready() -> void:
	build()


## The model's mesh instances by object name.
func meshes() -> Dictionary:
	var out := {}
	if _model == null:
		return out
	for object_name in OBJECTS:
		var n := _model.find_child(object_name, true, false)
		if n is MeshInstance3D:
			out[object_name] = n
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
	for object_name in OBJECTS:
		var spec: Array = OBJECTS[object_name]
		var m := ShaderMaterial.new()
		m.shader = SHADERS[spec[1]]
		_set_picture(m, spec)
		if spec[1] == "floor":
			m.set_shader_parameter("ice_mask", ice_mask())
		if spec[1] == "glass" or spec[1] == "wall_front":
			m.render_priority = IN_FRONT_PRIORITY
		if spec[1] == "glass" or spec[1] == "fence":
			set_arch_parameters(m)
		_materials[object_name] = m
	var found := meshes()
	for mesh_name in found:
		(found[mesh_name] as MeshInstance3D).material_override = _materials[mesh_name]
	for board: String in REFLECTED:
		var mi: MeshInstance3D = found.get(board)
		if mi == null:
			continue
		var m := reflect_material(REFLECT_MESH_2S if REFLECTED[board][0] else REFLECT_MESH, REFLECTED[board][1])
		_set_picture(m, OBJECTS[board])
		_reflect_materials[board] = m
		var r := MeshInstance3D.new()
		r.name = board + "_reflection"
		r.mesh = mi.mesh
		r.transform = MIRROR * mi.transform
		r.material_override = m
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.get_parent().add_child(r)
		_reflections[board] = r
	_update_palette()


## The hallways' dark on material [param m] (rink3d_arch): where the pens'
## walls and glass darken to black along the hallways (MwBench3D.HALL_WEST,
## HALL_EAST).
static func set_arch_parameters(m: ShaderMaterial) -> void:
	m.set_shader_parameter("arch", Vector4(MwBench3D.HALL_WEST.x, MwBench3D.HALL_WEST.y, MwBench3D.HALL_EAST.x,
			MwBench3D.HALL_EAST.y))
	m.set_shader_parameter("arch_half_y", MwBench3D.ARCH_HALF_Y)


## An object's picture on material [param m] ([param spec]: its OBJECTS
## entry), and for glass its rows and posts (rink3d_glass_body).
static func _set_picture(m: ShaderMaterial, spec: Array) -> void:
	m.set_shader_parameter("picture", picture_texture(spec[0]))
	if spec[1] == "glass":
		m.set_shader_parameter("glass_rows", spec[2])
		m.set_shader_parameter("clear_rows", spec[3])
		var posts: Vector3 = spec[4]
		m.set_shader_parameter("post_cols", post_columns(spec[0], int(posts.z)))
		m.set_shader_parameter("post_rows", Vector2(posts.x, posts.y))


## A reflection's material (plan 37, rink3d_reflect_mesh_body.gdshaderinc):
## [param shader] one- or two-sided, [param mode] 0 a picture, 1 one colour,
## 2 a netting, 3 the glass; the ice, the fade and the draw order set.
static func reflect_material(shader: Shader, mode: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = REFLECT_PRIORITY
	m.set_shader_parameter("mode", mode)
	set_reflect_parameters(m)
	return m


## The parameters every reflection shader shares (rink3d_reflect.gdshaderinc).
static func set_reflect_parameters(m: ShaderMaterial) -> void:
	m.set_shader_parameter("reflect_alpha", MwRink3D.REFLECT_ALPHA)
	m.set_shader_parameter("reflect_fade", float(MwRink3D.REFLECT_FADE))
	m.set_shader_parameter("reflect_ice", ice_mask())
	m.set_shader_parameter("reflect_origin", Vector2(MwRink3D.MAP_ORIGIN))


## The mirrored copies of the objects reflected in the ice (plan 37):
## {object: MeshInstance3D}.
func reflections() -> Dictionary:
	return _reflections


## Shows the reflections in the ice (plan 37, MwSettings.reflections; never
## from the calibration camera) or hides them.
func set_reflections(on: bool) -> void:
	for r: MeshInstance3D in _reflections.values():
		r.visible = on


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
		var limit := MwRinkShape.half_width(rom, y)
		for x in range(maxi(1 - limit, -MwRink3D.MAP_ORIGIN.x), mini(limit, w - MwRink3D.MAP_ORIGIN.x)):
			px[row * w + x + MwRink3D.MAP_ORIGIN.x] = 255
	_ice_mask = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_R8, px))
	return _ice_mask


## The paint's strength over the ice's markings (plan 37, owner: about 75 %
## over any pixel but the main ice colour - the lines and the like); on the
## plain ice and the boards it is solid, on glass 50 %.
static var paint_marks_alpha := 0.75
## The ice's own detail (plan 37, owner: dark and light splotches of ~10 %
## opacity, the skates' scratches): towards black or white by this much.
## 15 % after the owner's review (a little stronger; 10-30 % rendered side
## by side).
static var ice_detail_alpha := 0.15

## The paint's layers shown ([method set_paint_layers]).
var _blood := true
var _detail := true


## The arena's paint (plan 37, MwSplatterAtlas's texture; null: none) on
## the ice, the boards, the glass and the fence, shown when [param on]
## (its layers as [method set_paint_layers] last said).
func set_paint(tex: Texture2D, on: bool) -> void:
	for m: ShaderMaterial in _materials.values() + _reflect_materials.values():
		m.set_shader_parameter("paint", tex)
		m.set_shader_parameter("paint_on", on and tex != null)
		m.set_shader_parameter("paint_marks_alpha", paint_marks_alpha)
		m.set_shader_parameter("ice_detail_alpha", ice_detail_alpha)
	set_paint_layers(_blood, _detail)


## Which of the paint's layers show (the VISUALS page, MwSettings): the
## blood and oil ([param blood], ABACABB MODE: on the ice, the boards, the
## glass, the fence and their reflections) and the ice's own detail
## ([param detail], DETAILED ICE: the floor). The atlas keeps both whatever
## is shown.
func set_paint_layers(blood: bool, detail: bool) -> void:
	_blood = blood
	_detail = detail
	for m: ShaderMaterial in _materials.values() + _reflect_materials.values():
		m.set_shader_parameter("paint_blood", blood)
		m.set_shader_parameter("ice_detail", detail)


func _update_palette() -> void:
	var tex: Texture2D = palette.texture() if palette else null
	for m: ShaderMaterial in _materials.values() + _reflect_materials.values():
		m.set_shader_parameter("palette", tex)
