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
##
## Flat shadows (MwSettings.flat_shadows, owner, 2026-10-09; MwFlatShadows):
## a standing frame's shadow pixels (colour 11 of the team lines: the ice in
## shadow) are left out of its billboard and laid on the ice beneath it as a
## flat, its dither kept (rink3d_sprite_shadow: turned to the camera as the
## billboard is, the shade colour but never lighter than the floor - black
## over the black beyond the ice), drawn before every other translucent
## thing; the stick's shadow stays on the billboard, drawn by a pass of its
## own after the colours with the same colour rule (rink3d_sprite_stick); a
## figure in
## the bench area (outside the side boards: the benches, the boxes, the ways
## to the arches) has no shadow. Not for the calibration camera
## ([member original_order]: the original's frames as they are).
## Reflections (plan 37, [member reflections]: MwSettings.reflections, not
## for the calibration camera): each standing frame on the ice with rows
## within MwRink3D.REFLECT_FADE px above it is drawn again flipped about its
## point (rink3d_sprite_reflect), row n above the ice at
## MwRink3D.reflect_alpha(n), after the under-ice frames and before the
## hazards, shadows and markers (MwRinkModel.REFLECT_PRIORITY): the
## standing frames cover it where they stand in front.
## Nothing is saved: the pool, textures and materials are made at run time.

const SPRITE := preload("res://src/rink3d/rink3d_sprite.gdshader")
const SPRITE_2D := preload("res://src/rink3d/rink3d_sprite_2d.gdshader")
const SPRITE_DEPTH := preload("res://src/rink3d/rink3d_sprite_depth.gdshader")
const SPRITE_OPS := preload("res://src/rink3d/rink3d_sprite_ops.gdshader")
const SPRITE_BLEND := preload("res://src/rink3d/rink3d_sprite_blend.gdshader")
const SPRITE_SHADOW := preload("res://src/rink3d/rink3d_sprite_shadow.gdshader")
const SPRITE_STICK := preload("res://src/rink3d/rink3d_sprite_stick.gdshader")
const SPRITE_REFLECT := preload("res://src/rink3d/rink3d_sprite_reflect.gdshader")
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
## Ground layers' render priority below every other translucent thing's (0):
## depth d at d - GROUND_PRIORITY, those above the under-ice frames (d > 0)
## one more, over the reflections in the ice (MwRinkModel.REFLECT_PRIORITY).
const GROUND_PRIORITY := 8
## Operator pixels' render priority: after the near wall and the glass.
const OPS_PRIORITY := MwRinkModel.IN_FRONT_PRIORITY + 1
## The flat shadows' render priority (MwFlatShadows): before every other
## translucent thing, the ground layers included - they read the floor the
## opaque pass drew.
const SHADOW_PRIORITY := -GROUND_PRIORITY - 1
## The flat shadows' height above the ice (m): the original's shadow depth (2).
const SHADOW_ON_ICE := 0.0012
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
## Whether the standing frames on the ice are reflected in it (plan 37;
## the view: MwSettings.reflections, never the calibration camera's).
var reflections := true
## Whether the frames on the ice lie flat shadows (the view's MwViewLayers:
## MwSettings.flat_shadows, never the calibration camera's).
var flat_shadows := true

var _quad := QuadMesh.new()
var _pool: Array[MeshInstance3D] = []
var _shown := 0
var _frames := {}      # key -> {tex, x0, y0, w, h, ops, key, shadow, stick}
var _materials := {}   # key + place -> ShaderMaterial


func _init() -> void:
	_quad.size = Vector2.ONE


## Shows [param items] (MwRinkDraw3D.items).
func show_items(items: Array) -> void:
	var rom := MwRom.data() if MwRom.available() else PackedByteArray()
	_shown = 0
	var seen := {}    # anchor -> count (frames at the same point or pin)
	var flat_n := 0   # flat cards so far: later ones a hair in front
	var flats := flat_shadows and not original_order
	for it: Dictionary in items:
		var place: int = it["place"]
		if place == MwRinkDraw3D.SCREEN or rom.is_empty():
			continue
		var f := frame_texture(rom, int(it["frame"]), int(it["attr"]), int(it.get("clip", NO_CLIP)))
		if f.is_empty():
			continue
		var at: Vector3 = it["at"]
		var off: Vector2i = it["offset"]
		var w: int = f["w"]
		var h: int = f["h"]
		var cx: float = f["x0"] + w / 2.0 + off.x
		var ground := MwRink3D.world(at.x, at.y, 0)
		var d := _ice_depth(it)
		if d >= 0:
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
		var bias := SAME_POINT_BIAS * k + float(it.get("bias", 0.0))   # (a bench figure's own, plan 32)
		if it.get("behind", false):
			# a carried puck on the far side of its carrier (MwRinkFacing3D,
			# plan 28): just behind him, so his body hides it
			bias = -SAME_POINT_BIAS
		var sort := bias + (0.0 if pin > 0.0 else at.z * S)
		# its shadow as a flat on the ice beneath it, none in the bench area (MwFlatShadows)
		var strip: bool = flats and pin <= 0.0 and f.get("shadow") != null
		var stick := false
		if strip and not MwFlatShadows.in_bench_area(at):
			_quad_at(Transform3D(Basis.IDENTITY, ground + Vector3(0, SHADOW_ON_ICE, 0)), _shadow_material(f),
					Vector4(float(f["x0"]) + off.x, float(f["y0"]) + off.y, w, h))
			stick = f.get("stick", false)      # its stick's shadow on the billboard
		_quad_at(Transform3D(Basis.IDENTITY, ground), _material(f, -1, strip, stick),
				Vector4(float(f["x0"]) + off.x, float(f["y0"]) + off.y - (at.z - pin), w, h),
				Vector2(pin, bias), sort, false, float(it.get("shade", 1.0)), float(it.get("darker", 0)))
		# its reflection in the ice, flipped about its point (plan 37)
		var top := float(f["y0"]) + off.y - (at.z - pin)
		if reflections and not original_order and pin <= 0.0 and reflected(at, top, h):
			_quad_at(Transform3D(Basis.IDENTITY, ground), _reflect_material(f),
					Vector4(float(f["x0"]) + off.x, top, w, h),
					Vector2.ZERO, sort, false, float(it.get("shade", 1.0)), float(it.get("darker", 0)))
	for i in range(_shown, _pool.size()):
		_pool[i].visible = false


## Makes [param items]' frames and materials (MwRinkDraw3D.items) without
## showing them: a screen about to show them first (the match's first frame
## after its opening, plan 33) finds them made, no frame decoded then.
func prepare(items: Array) -> void:
	var rom := MwRom.data() if MwRom.available() else PackedByteArray()
	if rom.is_empty():
		return
	for it: Dictionary in items:
		if int(it["place"]) == MwRinkDraw3D.SCREEN:
			continue
		var f := frame_texture(rom, int(it["frame"]), int(it["attr"]), int(it.get("clip", NO_CLIP)))
		if not f.is_empty():
			var d := _ice_depth(it)
			var strip: bool = d < 0 and flat_shadows and not original_order and f.get("shadow") != null
			_material(f, d, strip)
			if d < 0 and reflections and not original_order:
				_reflect_material(f)
			if strip:
				_shadow_material(f)
				if f.get("stick", false):
					_material(f, d, true, true)


## Whether a standing frame at [param at] whose top row is [param top] px
## from the ice point under it (y down: < 0 above the ice) and
## [param h] rows tall is reflected in the ice (plan 37): standing on the
## ice (inside the boards: not the benches, boxes and arches), some of its
## rows above the ice and within MwRink3D.REFLECT_FADE of it.
static func reflected(at: Vector3, top: float, h: int) -> bool:
	if absf(at.x) > MwFlatShadows.BOARD_X or absf(at.y) > MwSimCollide.BOARD_Y:
		return false
	return top < 0.0 and top + h > -MwRink3D.REFLECT_FADE


## The ice depth of a frame drawn on the ice (0-3), or -1 for one standing.
static func _ice_depth(it: Dictionary) -> int:
	var place: int = it["place"]
	if place == MwRinkDraw3D.GROUND or place == MwRinkDraw3D.UNDER_ICE:
		return clampi(int(it["depth"]), 0, 3)
	return -1


## Shows the next pooled quad: [param px_rect] and [param pin] are the
## billboard's (rink3d_billboard.gdshaderinc), unused for flat quads. Standing
## frames are drawn back to front by their ice point (Godot sorts translucent
## instances by their bounds' centre: the quad's origin), [param sort] brings
## one forward; [param shade] darkens it (an arch's dark, plan 32);
## [param darker]: its colours that many of each channel's 8 levels darker
## (plan 37: the oil in flight, MwSplatter.OIL_DARKER).
func _quad_at(xf: Transform3D, mat: ShaderMaterial, px_rect := Vector4(0, 0, 1, 1), pin := Vector2.ZERO,
		sort := 0.0, flat := false, shade := 1.0, darker := 0.0) -> void:
	while _pool.size() <= _shown:
		var new_quad := MeshInstance3D.new()
		new_quad.mesh = _quad
		new_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		new_quad.extra_cull_margin = CULL_MARGIN
		add_child(new_quad)
		_pool.append(new_quad)
	var mi := _pool[_shown]
	_shown += 1
	mi.transform = xf
	mi.material_override = mat
	mi.set_instance_shader_parameter("px_rect", px_rect)
	mi.set_instance_shader_parameter("pin", pin)
	mi.set_instance_shader_parameter("flat_card", 1.0 if flat else 0.0)
	mi.set_instance_shader_parameter("shade", shade)
	mi.set_instance_shader_parameter("darker", darker)
	mi.sorting_offset = sort        # frames at the same point: later ones in front
	mi.visible = true


## No [code]clip[/code] on an item: the whole frame.
const NO_CLIP := 0x7FFF


## A frame drawn with [param attr] as an indexed texture: {tex, x0, y0, w,
## h, ops, shadow, stick, scorch}; x0/y0 = the texture's top-left relative to the
## frame's point; shadow: its shadow sorted (MwFlatShadows.mask: R8, 255 the
## flat on the ice, 128 the stick's on the billboard) or null when it has
## none (or is made of RAM tiles); stick: whether it has the stick's;
## scorch: the index of a fire's scorch mark, sorted with the shadows
## (MwFlatShadows.scorch_index; -1 none).
## Pieces as `add_sprite_piece` places them ($156C6): the draw's flips mirror
## the piece positions, the piece's attr XOR the draw's sets its palette line
## and flips; later pieces in front. [param clip]: the rows from this one
## down (frame y) left out (plan 37: the impale drops without their pool).
func frame_texture(rom: PackedByteArray, frame: int, attr: int, clip := NO_CLIP) -> Dictionary:
	var pieces := MwGfx.frame_pieces(rom, frame)
	var from_ram := false
	for piece: Dictionary in pieces:
		if int(piece["tile"]) < 0x800:
			from_ram = true
	var key := "%d:%d" % [frame, attr & (0x78 | MwRinkDraw.PORT_BITS)]
	if clip != NO_CLIP:
		key += ":c%d" % clip
	if from_ram:
		key += ":" + _ram_key(pieces, attr)
	if _frames.has(key):
		return _frames[key]
	var placed := []
	var b := [999, 999, -999, -999]
	for piece: Dictionary in pieces:
		var w := 8 * int(piece["w"])
		var h := 8 * int(piece["h"])
		var x := MwGfx.mirror_offset(int(piece["x"]), w, attr & 0x08 != 0)
		var y := MwGfx.mirror_offset(int(piece["y"]), h, attr & 0x10 != 0)
		placed.append([x, y, piece, ((int(piece["attr"]) ^ attr) & 0xF8) | (attr & MwRinkDraw.PORT_BITS)])
		b = [mini(b[0], x), mini(b[1], y), maxi(b[2], x + w), maxi(b[3], y + h)]
	if placed.is_empty():
		_frames[key] = {}
		return {}
	var tw: int = b[2] - b[0]
	var th: int = b[3] - b[1]
	var px := PackedByteArray()
	px.resize(tw * th)
	# RAM tiles, or the ROM with the original's sprite tile cache bug in three
	# pieces (MwSpriteCacheQuirk); plan 40 (R3): MwGfx's walk
	var source := MwGfx.TileSource.new(rom, true, ram_tiles)
	for placement: Array in placed:
		var piece: Dictionary = placement[2]
		var a: int = placement[3]
		MwGfx.blit_piece(px, tw, int(placement[0]) - b[0], int(placement[1]) - b[1],
				MwRinkDraw.tile_of(int(piece["tile"]), a),
				((int(piece["w"]) - 1) << 2) | (int(piece["h"]) - 1), MwRinkDraw.line_of(a), (a & 0x08) != 0,
				(a & 0x10) != 0, source)
	if clip != NO_CLIP:
		for row in range(maxi(clip - b[1], 0), th):
			for col in tw:
				px[row * tw + col] = 0
	var ops := false
	for v in px:
		if v == 62 or v == 63:
			ops = true
			break
	var shadow: ImageTexture = null
	var stick := false
	var scorch := MwFlatShadows.scorch_index(frame, attr)       # a fire's scorch: a shadow too
	if not from_ram:
		var m := MwFlatShadows.mask(px, tw, b[1], scorch)
		if not m.is_empty():
			shadow = ImageTexture.create_from_image(Image.create_from_data(tw, th, false, Image.FORMAT_R8, m))
			stick = m.has(MwFlatShadows.ON_STICK)
	var f := {"tex": ImageTexture.create_from_image(Image.create_from_data(tw, th, false, Image.FORMAT_R8, px)),
			"x0": b[0], "y0": b[1], "w": tw, "h": th, "ops": ops, "key": key, "shadow": shadow, "stick": stick,
			"scorch": scorch}
	if not from_ram:
		_frames[key] = f
	return f


## The material for frame [param f]: lying on the ice ([param ice_depth] 0-3,
## translucent, drawn before everything else translucent, in the original's
## depth order: they are under it all) or standing (-1: a billboard drawn in
## back-to-front order over the boards, writing its depth for the near wall
## and the glass drawn after it; its shadow / highlight operator pixels, if
## any, in a third pass after the glass). [param strip]: a standing frame
## without its shadow pixels (MwFlatShadows: drawn flat on the ice, or not
## at all); [param stick]: with its stick's shadow drawn after the colours
## (rink3d_sprite_stick).
func _material(f: Dictionary, ice_depth: int, strip := false, stick := false) -> ShaderMaterial:
	var key := "%s|%d%s%s" % [f["key"], ice_depth, "|flat" if strip else "", "|stick" if stick else ""]
	var m: ShaderMaterial = _materials.get(key)
	if m == null:
		if ice_depth < 0:          # depth, then colours, then (after the glass) operator pixels
			m = _new_material(SPRITE_DEPTH)
			m.next_pass = _new_material(SPRITE_2D if original_order else SPRITE)
			m.set_shader_parameter("strip_shadow", strip)
			m.next_pass.set_shader_parameter("strip_shadow", strip)
			var last: ShaderMaterial = m.next_pass
			if stick:
				last.next_pass = _new_material(SPRITE_STICK)
				last = last.next_pass
			if f["ops"]:
				last.next_pass = _new_material(SPRITE_OPS)
				last.next_pass.render_priority = OPS_PRIORITY
		else:
			m = _new_material(SPRITE_BLEND)
			m.render_priority = ice_depth - GROUND_PRIORITY + (1 if ice_depth > 0 else 0)
		_materials[key] = m
	for mat: ShaderMaterial in _passes(m):
		mat.set_shader_parameter("frame", f["tex"])
		mat.set_shader_parameter("strip_also", int(f.get("scorch", -1)))
		if mat.shader == SPRITE_STICK:
			mat.set_shader_parameter("shadow_mask", f["shadow"])
	return m


## The material of frame [param f]'s reflection in the ice (plan 37,
## rink3d_sprite_reflect).
func _reflect_material(f: Dictionary) -> ShaderMaterial:
	var key := "%s|reflect" % f["key"]
	var m: ShaderMaterial = _materials.get(key)
	if m == null:
		m = _new_material(SPRITE_REFLECT)
		m.render_priority = MwRinkModel.REFLECT_PRIORITY
		MwRinkModel.set_reflect_parameters(m)
		_materials[key] = m
	m.set_shader_parameter("frame", f["tex"])
	m.set_shader_parameter("strip_also", int(f.get("scorch", -1)))
	return m


## The material of frame [param f]'s shadow as a flat on the ice
## (rink3d_sprite_shadow, MwFlatShadows).
func _shadow_material(f: Dictionary) -> ShaderMaterial:
	var key := "%s|shadow" % f["key"]
	var m: ShaderMaterial = _materials.get(key)
	if m == null:
		m = _new_material(SPRITE_SHADOW)
		m.render_priority = SHADOW_PRIORITY
		_materials[key] = m
	m.set_shader_parameter("mask", f["shadow"])
	var scorch := int(f.get("scorch", -1))
	m.set_shader_parameter("shade_index", scorch if scorch >= 0 else MwFlatShadows.SHADE_INDEX)
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
## with operator pixels and a stick shadow, its flat shadow, its reflection,
## a flat card, a frame on the ice)
## for the 3D host's
## warm-up render (plan 20, MwRink3DHost: their shaders compiled before
## anyone looks), or hides them again (off).
func warm_up(on: bool) -> void:
	for key: String in _materials.keys():
		if key.begins_with(WARM_KEY):
			_materials.erase(key)
	_shown = 0
	if on:
		var px := PackedByteArray([1, 62, 63, 1])
		var flat := PackedByteArray([255, MwFlatShadows.ON_STICK, 0, 0])
		var f := {"tex": ImageTexture.create_from_image(Image.create_from_data(2, 2, false, Image.FORMAT_R8, px)),
				"x0": -1, "y0": -2, "w": 2, "h": 2, "ops": true, "key": WARM_KEY, "stick": true,
				"shadow": ImageTexture.create_from_image(Image.create_from_data(2, 2, false, Image.FORMAT_R8, flat))}
		var ground := MwRink3D.world(0, 40, 0)
		_quad_at(Transform3D(Basis.IDENTITY, ground), _material(f, -1, true, true), Vector4(-1, -2, 2, 2))
		_quad_at(Transform3D(Basis.IDENTITY, ground + Vector3(0, SHADOW_ON_ICE, 0)), _shadow_material(f),
				Vector4(-1, -2, 2, 2))
		_quad_at(Transform3D(Basis.IDENTITY, ground), _reflect_material(f), Vector4(-1, -2, 2, 2))
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


## The RAM tiles' contents of [param pieces] drawn with [param attr] (its
## bank: MwRinkDraw.tile_of) as a cache key.
func _ram_key(pieces: Array, attr := 0) -> String:
	var parts := PackedStringArray()
	for piece: Dictionary in pieces:
		var tile := MwRinkDraw.tile_of(int(piece["tile"]), attr)
		if tile >= 0x800:
			continue
		for n in int(piece["w"]) * int(piece["h"]):
			var raw: PackedByteArray = ram_tiles.get(tile + n, PackedByteArray())
			parts.append(str(hash(raw)))
	return ",".join(parts)
