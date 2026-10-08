class_name MwNet3D
extends Node3D
## A goal net as a 3D model (plan 17, docs/rink3d.md, Nets): the standard
## net's or the Battle Net's low-poly model ([member style]), made by numbers
## in Blender (tools/blender/net_build.py -> assets/rink3d/net_<style>.glb),
## coloured with the stadium's palette like the original's drawing (line 0:
## the ice palette). The model is the far net at its spot (origin on the goal
## line, mouth to the south); [method place] stands it at a net's point and
## turns it round for the near net. Presentation only.
##
## Each material's name carries its palette indices (net_build.py):
## [code]bar_L_I[/code], [code]spike_L_I[/code] and [code]outline_L_I[/code] flat colours
## (rink3d_net_flat), [code]net_L_O_I[/code] the stippled netting, outer and
## inner colour (rink3d_net_netting), [code]shadow_L_F[/code] the ground
## shadow inside (rink3d_net_shadow): the ROM's own, the ice the front
## drawing shows through the mouth ([method ground_decal]), with the fill
## colour where the drawing hides the ground (the sides, behind the back
## bar; owner). [code]hidden[/code]: faces never drawn (rink3d_net_hidden),
## the feet of the Battle Net's spikes on the netting.

## The models by net style (MwRinkState.NET_ANIMS: 0 Demon Net, 1 standard,
## 2 Battle Net); the Demon Net keeps its drawings.
const MODELS := {
	1: preload("res://assets/rink3d/net_standard.glb"),
	2: preload("res://assets/rink3d/net_battle.glb"),
}
const FLAT := preload("res://src/rink3d/rink3d_net_flat.gdshader")
const NETTING := preload("res://src/rink3d/rink3d_net_netting.gdshader")
const SHADOW := preload("res://src/rink3d/rink3d_net_shadow.gdshader")
const HIDDEN := preload("res://src/rink3d/rink3d_net_hidden.gdshader")
## Each style's front drawing (the far net: variant 1 of its animation),
## where its ground shadow comes from, and the ground it shows through the
## mouth (rink px from the net's point; x across, d behind the goal line,
## both inclusive): between the posts' inner edges, from the posts' feet
## back to the back netting's bottom bar. Ground pixel (x, d) is the
## drawing's pixel (ox + x, oy - 1 - d). The Battle Net's drawing has the
## same ground pixels, its origin a pixel lower: d one less.
const GROUNDS := {
	1: {"frame": 0x3DAE6, "x": Vector2i(-19, 18), "d": Vector2i(2, 13)},
	2: {"frame": 0x1FC82, "x": Vector2i(-19, 18), "d": Vector2i(1, 12)},
}

## The net style shown (1 standard, 2 Battle Net); set before it enters the tree.
var style := 1

var palette: RomPalette:
	set(v):
		if palette and palette.changed.is_connected(_update_palette):
			palette.changed.disconnect(_update_palette)
		palette = v
		if palette:
			palette.changed.connect(_update_palette)
		_update_palette()

var _materials: Array[ShaderMaterial] = []
var _model: Node3D


func _ready() -> void:
	_model = MODELS[style].instantiate()
	add_child(_model)
	var decal: Texture2D = null
	if MwRom.available():
		decal = ImageTexture.create_from_image(ground_decal(MwRom.data(), style))
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var m := material_for(src.resource_name if src else "", decal, style)
			if m:
				mi.set_surface_override_material(s, m)
				_materials.append(m)
	_update_palette()


## The material for a model material named [param name] (see above); null
## for an unknown name.
static func material_for(name: String, decal: Texture2D = null, style_ := 1) -> ShaderMaterial:
	if name == "hidden":
		var hidden := ShaderMaterial.new()
		hidden.shader = HIDDEN
		return hidden
	var parts := name.split("_")
	if parts.size() < 3:
		return null
	var line := int(parts[1]) * 16
	var m := ShaderMaterial.new()
	match parts[0]:
		"bar", "spike", "outline":
			m.shader = FLAT
			m.set_shader_parameter("index", line + int(parts[2]))
		"net":
			if parts.size() < 4:
				return null
			m.shader = NETTING
			m.set_shader_parameter("outer", line + int(parts[2]))
			m.set_shader_parameter("inner", line + int(parts[3]))
		"shadow":
			m.shader = SHADOW
			m.set_shader_parameter("fill", line + int(parts[2]))
			m.set_shader_parameter("decal", decal)
			m.set_shader_parameter("ground_x", GROUNDS[style_]["x"])
			m.set_shader_parameter("ground_d", GROUNDS[style_]["d"])
		_:
			return null
	return m


## The style of a net drawn with animation record [param anim] if it has a
## model, else -1.
static func model_style(rom: PackedByteArray, anim: int) -> int:
	for s: int in MODELS:
		if anim == MwGfx.u32(rom, MwRinkState.NET_ANIMS + 4 * s):
			return s
	return -1


## The ground shadow a style's front drawing shows through its mouth, as an
## R8 image of palette indices (line * 16 + colour; 0 = the ice shows):
## pixel (x - x0, d - d0) for ground pixel (x, d) (GROUNDS).
static func ground_decal(rom: PackedByteArray, style_ := 1) -> Image:
	var g: Dictionary = GROUNDS[style_]
	var gx: Vector2i = g["x"]
	var gd: Vector2i = g["d"]
	var f := MwGfx.frame_image(rom, MwGfx.frame_pieces(rom, g["frame"]))
	var w := gx.y - gx.x + 1
	var h := gd.y - gd.x + 1
	var src: PackedByteArray = f["px"]
	var px := PackedByteArray()
	px.resize(w * h)
	for d in range(gd.x, gd.y + 1):
		for x in range(gx.x, gx.y + 1):
			var c: int = f["ox"] + x
			var r: int = f["oy"] - 1 - d
			px[(d - gd.x) * w + x - gx.x] = src[r * f["w"] + c]
	return Image.create_from_data(w, h, false, Image.FORMAT_R8, px)


## The palette index the shadow shows at ground pixel ([param x], [param d])
## (0: the ice; as rink3d_net_shadow does it), [param decal] being
## [method ground_decal]'s and [param fill] the fill index.
static func shadow_index(decal: Image, x: int, d: int, fill := 6, style_ := 1) -> int:
	var gx: Vector2i = GROUNDS[style_]["x"]
	var gd: Vector2i = GROUNDS[style_]["d"]
	if x < gx.x or x > gx.y or d > gd.y:
		return fill
	if d < gd.x:
		return 0
	return decal.get_pixel(x - gx.x, d - gd.x).r8


## Stands the net at [param at] (rink px, its point on the goal line), its
## mouth to the south ([param mouth] 1, the far net) or the north (-1).
func place(at: Vector3, mouth: int) -> void:
	transform = Transform3D(Basis(Vector3.UP, 0.0 if mouth > 0 else PI), MwRink3D.world(at.x, at.y, at.z))


func _update_palette() -> void:
	var tex: Texture2D = palette.texture() if palette else null
	for m in _materials:
		m.set_shader_parameter("palette", tex)
