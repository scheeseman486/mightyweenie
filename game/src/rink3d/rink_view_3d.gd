class_name MwRinkView3D
extends Node3D
## The rink in 3D (plan 14): the model (MwRinkModel), the sprites
## (MwSprites3D) and the camera (MwRinkCamera3D), presented from the same
## node-free state and draw pass as the 2D view, once per pass, and between
## passes at any frame rate ([method blend_to], MwRinkBlend3D). Lives in its
## own SubViewport; a 2D layer over it shows the screen-space pieces
## ([method MwRinkDraw3D.screen_sprites]) and the HUD. Presentation only:
## nothing here changes the state.

@onready var world: Node3D = $World
@onready var model: MwRinkModel = $World/Model
@onready var sprites: MwSprites3D = $World/Sprites
@onready var camera: MwRinkCamera3D = $Camera

var _prev := {}                 # the previous pass's frames by key (MwRinkBlend3D)
var _items: Array = []          # the latest pass's frames
var _prev_shown := Vector2.ZERO # the sim camera's shown point, previous and latest pass
var _shown := Vector2.ZERO
var _prev_shot: MwRinkShot3D    # the play, previous and latest pass (the game's views)
var _shot: MwRinkShot3D

## Blending by itself every rendered frame (the game's rink scene, plan 14
## phase B): the way from the previous pass to the latest by the share of
## the latest pass's ticks gone by since its physics frame. Off: the owner
## calls [method blend_to] (the proof scene).
var auto_blend := false
var pass_frame := 0
var pass_ticks := 1

## The stands and their crowd (plan 15), made at load.
var stands: MwStands3D
## The nets with a 3D model (plan 17), in place of their drawings.
var nets: MwNets3D
var _built := false

var palette: RomPalette:
	set(v):
		palette = v
		if is_node_ready():
			model.palette = v
			sprites.palette = v
			stands.palette = v
			nets.palette = v


func _ready() -> void:
	build()
	if palette:
		model.palette = palette
		sprites.palette = palette
		stands.palette = palette
		nets.palette = palette


## Makes everything heavy once (plan 20): the rink model's textures, the
## stands and their crowd cut from the ROM, the nets' holder, the
## environment. Safe off the scene tree and on a worker thread
## (MwRink3DHost builds the view at launch that way); [method _ready] does
## it if nobody did.
func build() -> void:
	if _built:
		return
	_built = true
	var w := get_node("World")
	(w.get_node("Model") as MwRinkModel).build()
	stands = MwStands3D.new()
	stands.name = "Stands"
	stands.build()
	w.add_child(stands)
	nets = MwNets3D.new()
	nets.name = "Nets"
	w.add_child(nets)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	env.environment = e
	add_child(env)


func _process(delta: float) -> void:
	if auto_blend:
		var t := (Engine.get_physics_frames() - pass_frame + Engine.get_physics_interpolation_fraction()) / maxi(pass_ticks, 1)
		blend_to(clampf(t, 0.0, 1.0), delta)


## The camera mode (MwRinkCamera3D.Mode).
func set_camera_mode(m: int) -> void:
	camera.mode = m as MwRinkCamera3D.Mode


## Shows [param state] with [param draw]'s placements (run its build first)
## and the info plates' RAM tiles, as they are. [param continuous]: this pass
## follows the one presented before, so [method blend_to] can show the way
## from it (false after a jump: a new match, a seek).
func present(state: MwRinkState, draw: MwRinkDraw3D, ram_tiles: Dictionary, continuous := false) -> void:
	var shown := Vector2(state.camera.shown)
	present_frame({"items": draw.items, "shot": MwRinkShot3D.make(state, draw.items, shown), "shown": shown},
			ram_tiles, continuous)


## Shows a frame as [method present] makes it or the replay keeps it
## (MwReplay3D.frame: {items, shot, shown}), with the info plates' RAM tiles.
## [param continuous]: it follows the frame presented before (the view
## blends from it, backwards too: a rewound replay).
func present_frame(f: Dictionary, ram_tiles: Dictionary, continuous := false) -> void:
	world.scale = camera.world_scale()
	sprites.ram_tiles = ram_tiles
	var shown: Vector2 = f["shown"]
	_prev = MwRinkBlend3D.by_key(_items) if continuous else {}
	_prev_shown = _shown if continuous else shown
	_items = f["items"]
	_shown = shown
	_prev_shot = _shot if continuous else null
	_shot = f["shot"]
	if not continuous:
		camera.snap()
	blend_to(1.0)


## Shows the way from the previous pass to the latest at [param t] (0 = the
## previous pass's points, 1 = the latest's), for frames drawn between
## passes: the owner calls it every rendered frame with the share of the pass
## interval gone by, [param dt] the rendered frame's time (s: the cameras'
## smoothing steps by it; 0 none). A free camera is placed before it. Each
## frame shows the side the camera sees (MwRinkFacing3D); nets with a model
## show it instead of their drawing (MwNets3D), but for the calibration
## camera. The first-person camera's rider's frames and any too close to
## its lens are not drawn ([method lens_items]).
func blend_to(t: float, dt := 0.0) -> void:
	camera.shot = MwRinkShot3D.blend(_prev_shot, _shot, t)
	camera.dt = dt
	camera.follow(MwRinkBlend3D.point(_prev_shown, _shown, t))
	sprites.original_order = camera.mode == MwRinkCamera3D.Mode.CALIBRATION
	var boards := camera.cut_boards()      # cameras beyond the end boards look over them
	stands.cutaway(camera if boards != 0.0 else null, boards)
	var rom := MwRom.data() if MwRom.available() else PackedByteArray()
	var items := MwRinkFacing3D.apply(MwRinkBlend3D.items(_prev, _items, t), camera, rom)
	items = lens_items(items, camera)
	items = nets.take(items, sprites.original_order)
	sprites.show_items(items)
	for it: Dictionary in items:
		if it.get("key", "") == "puck/body":
			stands.watch(it["at"], camera)
			break


## [param items] without the frames [param cam] must not draw: its hidden
## subject's (the first-person camera's rider: body, weapon, shadow...) and
## upright frames standing within [member MwRinkCamera3D.lens_clear_px] of
## its lens (seen from above).
static func lens_items(items: Array, cam: MwRinkCamera3D) -> Array:
	var hidden := cam.hidden_subject()
	if hidden == "":
		return items
	var eye := MwRink3D.rink(cam.global_position if cam.is_inside_tree() else cam.position)
	var out: Array = []
	var prefix := hidden + "/"
	for it: Dictionary in items:
		var key: String = it.get("key", "")
		if key.begins_with(prefix):
			continue
		if int(it["place"]) == MwRinkDraw3D.UPRIGHT:
			var at: Vector3 = it["at"]
			if Vector2(at.x - eye.x, at.y - eye.y).length() < cam.lens_clear_px:
				continue
		out.append(it)
	return out
