@tool
class_name RomSprite
extends AnimatedSprite2D
## A sprite animation of the original, built from the ROM when the scene
## loads: frames are composed from their pieces (docs/re/graphics.md,
## Animation/Frame) into indexed textures drawn with the palette-swap shader.
## Stores only references (catalogue key or address, variant, palette); the
## generated SpriteFrames, material and offset are never saved.
##
## Each variant (direction) of the animation becomes its own SpriteFrames
## animation ("v0", "v1", ...), all frames on one canvas so the origin stays
## put. Speed is the original's: speed/256 frames per 60 Hz tick.

## Catalogue key of an animation ("anim_04ceb2").
@export var anim := "":
	set(v):
		anim = v
		state = null
		_queue()
## Or explicit frame addresses (a frame group, single pieces...), one animation.
@export var frame_addresses := PackedInt32Array():
	set(v):
		frame_addresses = v
		_queue()
@export var variant := 0:
	set(v):
		variant = v
		if sprite_frames and sprite_frames.has_animation("v%d" % v):
			animation = "v%d" % v
@export var palette: RomPalette:
	set(v):
		if palette and palette.changed.is_connected(_update_material):
			palette.changed.disconnect(_update_material)
		palette = v
		if palette:
			palette.changed.connect(_update_material)
		_update_material()
## The caller's attr XOR (`draw_anim_object` D3): bits 5-6 change the
## pieces' palette lines. (Bit 7, priority, is the scene's draw order.)
@export var attr_xor := 0:
	set(v):
		attr_xor = v
		_queue()
## Build only the animation of [member variant] (players' animations
## have many directions; a screen showing one sets this).
@export var only_variant := false:
	set(v):
		only_variant = v
		_queue()
## Play in the editor too.
@export var preview := true
## Frames chosen by the original's animation object ([member state]),
## stepped by the screen's passes ([method advance]) instead of playing on
## wall-clock time. Starts stopped; [method restart] plays it.
@export var tick_driven := false

const GENERATED := ["sprite_frames", "material", "offset", "animation", "centered", "frame", "frame_progress"]

## The animation object of a tick-driven sprite (from the record of [member anim]).
var state: MwAnimState


var _queued := false


func _ready() -> void:
	rebuild()


## Rebuild once at the end of the frame (several properties change together
## when a scene loads or the inspector edits); before _ready, _ready builds.
func _queue() -> void:
	if is_inside_tree() and not _queued:
		_queued = true
		_rebuild_deferred.call_deferred()


func _rebuild_deferred() -> void:
	_queued = false
	rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name in GENERATED:
		property.usage &= ~PROPERTY_USAGE_STORAGE


func rebuild() -> void:
	if not MwRom.available() or (anim == "" and frame_addresses.is_empty()):
		sprite_frames = null
		return
	var rom := MwRom.data()
	var lists := []          # [[name, [[pieces, flips], ...], fps], ...]
	if anim != "":
		var an := MwGfx.animation(rom, _anim_address())
		for v in an["variants"].size():
			if only_variant and v != variant:
				continue
			var frames := []
			for o in MwGfx.anim_offsets(rom, an, v):
				frames.append([_xor(MwGfx.frame_pieces(rom, an["frames"] + o)), an["variants"][v][1]])
			lists.append(["v%d" % v, frames, MwGfx.anim_fps(an)])
	else:
		var frames := []
		for a in frame_addresses:
			frames.append([_xor(MwGfx.frame_pieces(rom, a)), 0])
		lists.append(["v0", frames, 5.0])
	# one canvas for everything so the origin never moves
	var b := [999, 999, -999, -999]
	for l in lists:
		for f in l[1]:
			var fb := MwGfx.frame_bounds(MwGfx.flip_pieces(f[0], f[1]))
			if fb[2] > fb[0]:
				b = [mini(b[0], fb[0]), mini(b[1], fb[1]), maxi(b[2], fb[2]), maxi(b[3], fb[3])]
	if b[2] <= b[0]:
		sprite_frames = null
		return
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for l in lists:
		sf.add_animation(l[0])
		sf.set_animation_speed(l[0], l[2])
		for f in l[1]:
			var img := MwGfx.frame_image(rom, f[0], f[1], b)
			var image := Image.create_from_data(img["w"], img["h"], false, Image.FORMAT_R8, img["px"])
			sf.add_frame(l[0], ImageTexture.create_from_image(image))
	sprite_frames = sf
	centered = false
	offset = Vector2(b[0], b[1])
	animation = "v%d" % variant if sf.has_animation("v%d" % variant) else "v0"
	_update_material()
	if tick_driven:
		if state == null:
			state = MwAnimState.from_record(rom, _anim_address()) if anim != "" else MwAnimState.new()
		stop()
		_show()
	elif preview or not Engine.is_editor_hint():
		play()


func _anim_address() -> int:
	var e := MwRom.entry(anim)
	return int(e["address"]) if not e.is_empty() else anim.hex_to_int()


func _xor(pieces: Array) -> Array:
	if attr_xor & 0x60:
		for p in pieces:
			p["attr"] = int(p["attr"]) ^ (attr_xor & 0x60)
	return pieces


## Tick-driven: start the animation from its first frame.
func restart() -> void:
	if state:
		state.play()
		_show()


## Tick-driven: advance by [param elapsed] ticks (`anim_advance`).
func advance(elapsed: int) -> void:
	if state:
		state.advance(elapsed)
		_show()


## Tick-driven: true until a non-looping animation has finished.
func is_running() -> bool:
	return state != null and state.playing()


## Tick-driven: show the state's frame (after setting it directly).
func refresh() -> void:
	_show()


func _show() -> void:
	if sprite_frames and state and sprite_frames.has_animation(animation):
		frame = clampi(state.frame, 0, sprite_frames.get_frame_count(animation) - 1)


func _update_material() -> void:
	material = palette.material() if palette and palette.texture() else null
