class_name MwSprites3D
extends Node3D
## The rink's sprites in 3D (plan 14): one quad per frame the draw pass draws
## ([member MwRinkDraw3D.items]), at its simulated position. Frames are
## composed from the ROM's pieces with the draw's attr (palette lines and
## flips, as the VDP shows them) into indexed textures, cached, and drawn
## with the rink's sprite shaders and the stadium's palette.
##
## * UPRIGHT and MAP frames are billboards (owner): one quad in the screen's
##   plane at the ice point under the frame's point, the frame raised by the
##   point's height in pixels as the original draws it, its pixels square on
##   screen at any resolution; frames at one point (a lamp on its stand) stay
##   lined up. Its depth is that of the frame standing upright at the ice
##   point, with the rows below the ice (stick blades, skates, splashes) lying
##   on the ice towards the camera (rink3d_billboard.gdshaderinc). Frames with
##   a pin (the winged skull in front of the far glass, MwRinkDraw3D) hang
##   from that point on the glass instead, raised by their height above it,
##   so they stay on the post they cover; they sort at the ice point under it.
##   Seen from the original's angle (the calibration camera) they all look
##   exactly as in 2D.
## * Flat cards (plan 16, MwRinkDraw3D's [code]flat[/code]): the winged
##   skulls' wings, and each skull while it rests on them, stand as vertical
##   cards facing south on their 2D spot (a vertical plane keeps the
##   original's projection), double-sided: the drawing reads the right way
##   from behind too. A skull flying after a goal is a billboard.
## * Each frame shows the side the camera sees (MwRinkFacing3D, applied by
##   the view before the frames come here).
## * GROUND and UNDER_ICE frames lie on the ice, the screen's down = south,
##   in the original's depth order (under-ice 0, hazards 1, shadows 2,
##   markers 3).
## * SCREEN frames are not drawn here (a 2D layer over the view shows them).
##
## Draw order (plan 16, owner: 3D gets its own, more accurate order): the
## rink, the stands and the crowd first, then the ground layers
## (translucent, in the original's depth order), then the standing frames,
## depth tested: what stands between the camera and a player hides him, and
## parts of a frame past the boards behind the player come forward
## (rink3d_billboard's boards_pull: no arm lost into the boards beside it).
## Then the near end's outer wall and the glass, tested against the frames'
## depth, then the standing frames' shadow / highlight operator pixels,
## half-transparent black and white over whatever is behind them, the glass
## included (rink3d_sprite_ops). The calibration camera keeps the original's
## 2D order ([member original_order]): standing frames over the boards and
## the crowd whatever their depth.
## Nothing is saved: the pool, textures and materials are made at run time.

const SPRITE := preload("res://src/rink3d/rink3d_sprite.gdshader")
const SPRITE_2D := preload("res://src/rink3d/rink3d_sprite_2d.gdshader")
const SPRITE_DEPTH := preload("res://src/rink3d/rink3d_sprite_depth.gdshader")
const SPRITE_OPS := preload("res://src/rink3d/rink3d_sprite_ops.gdshader")
const SPRITE_BLEND := preload("res://src/rink3d/rink3d_sprite_blend.gdshader")
const S := MwRink3D.METRES_PER_PX
## Height of the ground layers above the ice (m), per original depth 0-3:
## tiny, so they stay on the original's pixels seen from its angle.
const ON_ICE := [0.0004, 0.0008, 0.0012, 0.0016]
## Frames drawn at the same point later come forward by this much (m) each.
const SAME_POINT_BIAS := 0.01
## Flat cards at one spot (a skull resting on its wings) step forward by this (px).
const FLAT_STEP := 0.25
## Billboards reach beyond their quad mesh's bounds: frustum culling margin (m).
const CULL_MARGIN := 4.0
## Ground layers' render priority below every other translucent thing's (0).
const GROUND_PRIORITY := 8
## Operator pixels' render priority: after the near wall and the glass.
const OPS_PRIORITY := MwRinkModel.IN_FRONT_PRIORITY + 1
## The warm-up frame's key ([method warm_up]).
const WARM_KEY := "warm-up"

var palette: RomPalette:
	set(v):
		if palette and palette.changed.is_connected(_update_palette):
			palette.changed.disconnect(_update_palette)
		palette = v
		if palette:
			palette.changed.connect(_update_palette)
		_update_palette()
## VRAM tiles built in RAM (the info plates): tile -> 32 bytes, as MwSpriteLayer.
var ram_tiles := {}
## The original's 2D order (the calibration camera) instead of the 3D one
## (plan 16): standing frames over the boards whatever their depth.
var original_order := false:
	set(v):
		if v != original_order:
			original_order = v
			_materials.clear()

var _quad := QuadMesh.new()
var _pool: Array[MeshInstance3D] = []
var _shown := 0
var _frames := {}      # key -> {tex, x0, y0, w, h, ops}
var _materials := {}   # key + place -> ShaderMaterial


func _init() -> void:
	_quad.size = Vector2.ONE


## Shows [param items] (MwRinkDraw3D.items).
func show_items(items: Array) -> void:
	var rom := MwRom.data() if MwRom.available() else PackedByteArray()
	_shown = 0
	var seen := {}    # anchor -> count (frames at the same point or pin)
	var flat_n := 0   # flat cards so far: later ones a hair in front
	for it: Dictionary in items:
		var place: int = it["place"]
		if place == MwRinkDraw3D.SCREEN or rom.is_empty():
			continue
		var f := frame_texture(rom, int(it["frame"]), int(it["attr"]))
		if f.is_empty():
			continue
		var at: Vector3 = it["at"]
		var off: Vector2i = it["offset"]
		var w: int = f["w"]
		var h: int = f["h"]
		var cx: float = f["x0"] + w / 2.0 + off.x
		var ground := MwRink3D.world(at.x, at.y, 0)
		if place == MwRinkDraw3D.GROUND or place == MwRinkDraw3D.UNDER_ICE:
			var d := clampi(int(it["depth"]), 0, 3)
			var cy: float = f["y0"] + h / 2.0 + off.y
			_quad_at(Transform3D(Basis(Vector3(w * S, 0, 0), Vector3(0, 0, -h * S), Vector3.UP),
					ground + Vector3(cx * S, ON_ICE[d], cy * S)), _material(f, d))
			continue
		if it.get("flat", false):
			# a flat card on its 2D spot, facing south (MwRinkDraw3D: the winged
			# skulls); a vertical plane keeps the original's projection
			var c := Vector3(at.x + cx, at.y + FLAT_STEP * flat_n, at.z - (f["y0"] + off.y) - h / 2.0)
			_quad_at(Transform3D(Basis(Vector3(w * S, 0, 0), Vector3(0, h * S, 0), Vector3(0, 0, 1)),
					MwRink3D.world(c.x, c.y, c.z)), _material(f, -1), Vector4(0, 0, 1, 1), Vector2.ZERO,
					SAME_POINT_BIAS * flat_n, true)
			flat_n += 1
			continue
		# hung from the ice point under it, or its pin on the far glass, and
		# raised above that by its height in pixels as the original draws it
		var pin := float(it.get("pin", 0))
		var anchor := Vector4(at.x, at.y, pin if pin > 0.0 else at.z, pin)
		var k: int = seen.get(anchor, 0)
		seen[anchor] = k + 1
		var sort := SAME_POINT_BIAS * k + (0.0 if pin > 0.0 else at.z * S)
		_quad_at(Transform3D(Basis.IDENTITY, ground), _material(f, -1),
				Vector4(float(f["x0"]) + off.x, float(f["y0"]) + off.y - (at.z - pin), w, h),
				Vector2(pin, SAME_POINT_BIAS * k), sort)
	for i in range(_shown, _pool.size()):
		_pool[i].visible = false


## Shows the next pooled quad: [param px_rect] and [param pin] are the
## billboard's (rink3d_billboard.gdshaderinc), unused for flat quads. Standing
## frames are drawn back to front by their ice point (Godot sorts translucent
## instances by their bounds' centre: the quad's origin), [param sort] brings
## one forward.
func _quad_at(xf: Transform3D, mat: ShaderMaterial, px_rect := Vector4(0, 0, 1, 1), pin := Vector2.ZERO,
		sort := 0.0, flat := false) -> void:
	while _pool.size() <= _shown:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = CULL_MARGIN
		add_child(mi)
		_pool.append(mi)
	var mi := _pool[_shown]
	_shown += 1
	mi.transform = xf
	mi.material_override = mat
	mi.set_instance_shader_parameter("px_rect", px_rect)
	mi.set_instance_shader_parameter("pin", pin)
	mi.set_instance_shader_parameter("flat_card", 1.0 if flat else 0.0)
	mi.sorting_offset = sort        # frames at the same point: later ones in front
	mi.visible = true


## A frame drawn with [param attr] as an indexed texture: {tex, x0, y0, w,
## h, ops}; x0/y0 = the texture's top-left relative to the frame's point.
## Pieces as `add_sprite_piece` places them ($156C6): the draw's flips mirror
## the piece positions, the piece's attr XOR the draw's sets its palette line
## and flips; later pieces in front.
func frame_texture(rom: PackedByteArray, frame: int, attr: int) -> Dictionary:
	var pieces := MwGfx.frame_pieces(rom, frame)
	var from_ram := false
	for p: Dictionary in pieces:
		if int(p["tile"]) < 0x800:
			from_ram = true
	var key := "%d:%d" % [frame, attr & 0x78]
	if from_ram:
		key += ":" + _ram_key(pieces)
	if _frames.has(key):
		return _frames[key]
	var placed := []
	var b := [999, 999, -999, -999]
	for p: Dictionary in pieces:
		var w := 8 * int(p["w"])
		var h := 8 * int(p["h"])
		var x: int = -int(p["x"]) - w if attr & 0x08 else int(p["x"])
		var y: int = -int(p["y"]) - h if attr & 0x10 else int(p["y"])
		placed.append([x, y, p, (int(p["attr"]) ^ attr) & 0xF8])
		b = [mini(b[0], x), mini(b[1], y), maxi(b[2], x + w), maxi(b[3], y + h)]
	if placed.is_empty():
		_frames[key] = {}
		return {}
	var tw: int = b[2] - b[0]
	var th: int = b[3] - b[1]
	var px := PackedByteArray()
	px.resize(tw * th)
	for e: Array in placed:
		var p: Dictionary = e[2]
		var a: int = e[3]
		var hf := (a & 0x08) != 0
		var vf := (a & 0x10) != 0
		var line := (a >> 5) & 3
		var pw := int(p["w"])
		var ph := int(p["h"])
		var tile := int(p["tile"])
		for cx in pw:
			for cy in ph:
				var n := cx * ph + cy
				var t: PackedByteArray
				if tile < 0x800:
					var raw: PackedByteArray = ram_tiles.get(tile + n, PackedByteArray())
					t = MwSpriteLayer._indices(raw) if raw.size() == 32 else PackedByteArray()
				else:
					# the original's sprite tile cache bug in three pieces (MwSpriteCacheQuirk)
					var shown := MwSpriteCacheQuirk.tile(tile, ((pw - 1) << 2) | (ph - 1), n)
					if shown >= 0x800 and (shown << 5) + 32 <= rom.size():
						t = MwGfx.tile_indices(rom, shown << 5)
				if t.is_empty():
					continue
				var dx := pw - 1 - cx if hf else cx
				var dy := ph - 1 - cy if vf else cy
				MwGfx.blit_tile(px, tw, int(e[0]) - b[0] + dx * 8, int(e[1]) - b[1] + dy * 8, t, line, hf, vf)
	var ops := false
	for v in px:
		if v == 62 or v == 63:
			ops = true
			break
	var f := {"tex": ImageTexture.create_from_image(Image.create_from_data(tw, th, false, Image.FORMAT_R8, px)),
			"x0": b[0], "y0": b[1], "w": tw, "h": th, "ops": ops, "key": key}
	if not from_ram:
		_frames[key] = f
	return f


## The material for frame [param f]: lying on the ice ([param ice_depth] 0-3,
## translucent, drawn before everything else translucent, in the original's
## depth order: they are under it all) or standing (-1: a billboard drawn in
## back-to-front order over the boards, writing its depth for the near wall
## and the glass drawn after it; its shadow / highlight operator pixels, if
## any, in a third pass after the glass).
func _material(f: Dictionary, ice_depth: int) -> ShaderMaterial:
	var key := "%s|%d" % [f["key"], ice_depth]
	var m: ShaderMaterial = _materials.get(key)
	if m == null:
		if ice_depth < 0:          # depth, then colours, then (after the glass) operator pixels
			m = _new_material(SPRITE_DEPTH)
			m.next_pass = _new_material(SPRITE_2D if original_order else SPRITE)
			if f["ops"]:
				m.next_pass.next_pass = _new_material(SPRITE_OPS)
				m.next_pass.next_pass.render_priority = OPS_PRIORITY
		else:
			m = _new_material(SPRITE_BLEND)
			m.render_priority = ice_depth - GROUND_PRIORITY
		_materials[key] = m
	for mat: ShaderMaterial in _passes(m):
		mat.set_shader_parameter("frame", f["tex"])
	return m


func _new_material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("palette", palette.texture() if palette else null)
	m.set_shader_parameter("boards_rule", not original_order)
	return m


static func _passes(m: Material) -> Array:
	var out := []
	while m:
		out.append(m)
		m = m.next_pass
	return out


## Shows a frame of every sprite kind at centre ice (on: a standing frame
## with operator pixels, a flat card, a frame on the ice) for the 3D host's
## warm-up render (plan 20, MwRink3DHost: their shaders compiled before
## anyone looks), or hides them again (off).
func warm_up(on: bool) -> void:
	for key: String in _materials.keys():
		if key.begins_with(WARM_KEY):
			_materials.erase(key)
	_shown = 0
	if on:
		var px := PackedByteArray([1, 62, 63, 1])
		var f := {"tex": ImageTexture.create_from_image(Image.create_from_data(2, 2, false, Image.FORMAT_R8, px)),
				"x0": -1, "y0": -2, "w": 2, "h": 2, "ops": true, "key": WARM_KEY}
		var ground := MwRink3D.world(0, 40, 0)
		_quad_at(Transform3D(Basis.IDENTITY, ground), _material(f, -1), Vector4(-1, -2, 2, 2))
		_quad_at(Transform3D(Basis(Vector3(2 * S, 0, 0), Vector3(0, 2 * S, 0), Vector3(0, 0, 1)),
				ground + Vector3(4 * S, S, 0)), _material(f, -1), Vector4(0, 0, 1, 1), Vector2.ZERO, 0.0, true)
		_quad_at(Transform3D(Basis(Vector3(2 * S, 0, 0), Vector3(0, 0, -2 * S), Vector3.UP),
				ground + Vector3(-4 * S, ON_ICE[0], 0)), _material(f, 0))
	for i in range(_shown, _pool.size()):
		_pool[i].visible = false


func _update_palette() -> void:
	var tex: Texture2D = palette.texture() if palette else null
	for m: ShaderMaterial in _materials.values():
		for mat: ShaderMaterial in _passes(m):
			mat.set_shader_parameter("palette", tex)


func _ram_key(pieces: Array) -> String:
	var parts := PackedStringArray()
	for p: Dictionary in pieces:
		var tile := int(p["tile"])
		if tile >= 0x800:
			continue
		for n in int(p["w"]) * int(p["h"]):
			var raw: PackedByteArray = ram_tiles.get(tile + n, PackedByteArray())
			parts.append(str(hash(raw)))
	return ",".join(parts)
