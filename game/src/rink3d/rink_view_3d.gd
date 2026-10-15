class_name MwRinkView3D
extends Node3D
## The rink in 3D (plan 14): the model (MwRinkModel), the sprites
## (MwSprites3D) and the camera (MwRinkCamera3D), presented from the same
## node-free state and draw pass as the 2D view, once per pass, and between
## passes at any frame rate ([method blend_to], MwRinkBlend3D). Lives in its
## own SubViewport; a 2D layer over it shows the screen-space pieces
## ([method MwRinkDraw3D.screen_sprites]) and the HUD. Presentation only:
## nothing here changes the state.

## The time a rendered frame gives the paint's seek at most (us,
## MwSplatterAtlas.seek_toward; [member auto_blend], the game's screens): a
## replay rewound far back catches its paint up over a few frames instead
## of holding one, and the ticks of a slow frame no longer seek again each
## (owner, 2026-10-15: rewinding dropped the frame rate badly). Fast
## scrubbing shows the paint a little behind until it settles. It was a
## number of texels looked at (60000), but a seek's time is mostly restoring
## a copy and the operations themselves - 7 to 9 ms a frame scrubbing at the
## fastest on the desktop, one seek 23 ms (owner: replays still juddery and
## slow).
const PAINT_USEC := 3000

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
## Online: the match pads of this machine's players (MwRinkShot3D.local_pads)
## - 3D EXTENDED keeps only their characters in the picture with the puck
## (MwRinkShot3D.of_pads; owner, 2026-10-13: it widens for the local players
## only); null: every player's (offline - all of them local).
var local_pads: Variant = null

## Blending by itself every rendered frame (the game's rink scene, plan 14
## phase B): the way from the previous pass to the latest by the share of
## the latest pass's ticks gone by since its physics frame. Off: the owner
## calls [method blend_to] (the proof scene).
var auto_blend := false
## The crowd's life, the previous and the latest pass's (MwCrowdLife
## snapshots, plans 30-31; {} none): blended between passes like the frames.
var _prev_life := {}
var _life := {}
## The benches' and boxes' figures (plan 32): the latest pass's snapshot
## (MwBenchLife; {} none) and its frames (MwBench3D.items), the previous
## pass's frames by key: blended between passes like the game's.
var _bench := {}
var _bench_items: Array = []
var _prev_bench := {}
## Whether the benches' and boxes' figures are shown (plan 32; never from
## the calibration camera, which shows the original's picture).
var benches := true
## The arena's paint and particles (plan 37): the latest pass's snapshot
## (MwSplatter; {} none), its particles' frames (MwSplatter.items) and the
## previous pass's by key; the atlas shown on the model (seeked to the
## snapshot's operations: a replay shows the paint as it was). Neither from
## the calibration camera; the particles only with ABACABB MODE
## (MwSettings.blood).
var _splat := {}
var _splat_items: Array = []
var _prev_splat := {}
var _paint: MwSplatterAtlas = null
var _paint_shown := false
## The operations the paint is to show (the latest frame's; -1 none), and
## the rendered frame whose share of [constant PAINT_USEC] runs until
## [member _paint_until] (Time.get_ticks_usec; [method _paint_seek]).
var _paint_ops := -1
var _paint_ops_made := Callable()        # its count as a worker thread makes it (MwSplatterReplay), or none
var _paint_frame := -1
var _paint_until := 0
## Whether the reflections in the ice show (plan 37, MwSettings.reflections;
## not from the calibration camera): the model's, the nets' and the sprites'.
var _reflections_shown := true
## The paint's layers on the model (MwSettings.blood: bit 0, ABACABB MODE -
## the particles in flight too; MwSettings.ice_detail: bit 1, DETAILED ICE),
## followed every frame; -1 not yet.
var _layers_shown := -1
## The frames' own clock (plan 33, the match's opening: s, the frame's
## "clock"; < 0 none), the previous and the latest pass's: blended between
## passes for the camera ([member MwRinkCamera3D.clock]) and the crowd's
## chant (the frame's "chant", a MwChant, and "chant_first").
var _prev_clock := -1.0
var _clock := -1.0
var _chant: MwChant = null
var _chant_first := false
## The physics frame the latest pass was shown at and its ticks: rendered
## frames blend towards it ([member auto_blend]; [method pass_shown]).
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
	var scene_environment := Environment.new()
	scene_environment.background_mode = Environment.BG_COLOR
	scene_environment.background_color = Color.BLACK
	scene_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	scene_environment.tonemap_exposure = 1.0
	env.environment = scene_environment
	add_child(env)


func _process(delta: float) -> void:
	if auto_blend:
		var t := (Engine.get_physics_frames() - pass_frame + Engine.get_physics_interpolation_fraction()) \
				/ maxi(pass_ticks, 1)
		blend_to(clampf(t, 0.0, 1.0), delta)


## Plan 40 (S12): a pass shown, [param ticks] long, at physics frame
## [param frame] (-1: now) - the frames rendered until the next one blend
## towards it ([param blend]: [member auto_blend]). The rink's, its instant
## replay's, the match's opening's and TEST SKATE's hand-off.
func pass_shown(ticks: int, frame := -1, blend := true) -> void:
	pass_frame = frame if frame >= 0 else Engine.get_physics_frames()
	pass_ticks = maxi(ticks, 1)
	auto_blend = blend


## The camera mode (MwRinkCamera3D.Mode).
func set_camera_mode(m: int) -> void:
	camera.mode = m as MwRinkCamera3D.Mode


## Shows [param state] with [param draw]'s placements (run its build first)
## and the info plates' RAM tiles, as they are. [param continuous]: this pass
## follows the one presented before, so [method blend_to] can show the way
## from it (false after a jump: a new match, a seek).
func present(state: MwRinkState, draw: MwRinkDraw3D, ram_tiles: Dictionary, continuous := false) -> void:
	present_frame(MwReplay3D.frame(state, draw, false), ram_tiles, continuous)


## Shows a frame as [method present] makes it or the replay keeps it
## (MwReplay3D.frame: {items, shot, shown[, crowd, bench, splat]}), with the info
## plates' RAM tiles.
## [param continuous]: it follows the frame presented before (the view
## blends from it, backwards too: a rewound replay). With [member
## auto_blend] on, the next rendered frame's blend shows it - only that one
## is seen, and several passes can run before a frame is rendered (a replay
## rewinding fast: owner, 2026-10-15, rewinding still juddered and was slow);
## else it shows at once.
func present_frame(f: Dictionary, ram_tiles: Dictionary, continuous := false) -> void:
	world.scale = camera.world_scale()
	_prev_life = _life if continuous else {}
	_life = f.get("crowd", {})
	var clock_was := _clock
	_clock = float(f.get("clock", -1.0))
	_prev_clock = clock_was if continuous and clock_was >= 0.0 else _clock
	_chant = f.get("chant") as MwChant
	_chant_first = bool(f.get("chant_first", false))
	_prev_bench = MwRinkBlend3D.by_key(_bench_items) if continuous else {}
	_bench = f.get("bench", {})
	_bench_items = MwBench3D.items(_bench, MwRom.data() if MwRom.available() else PackedByteArray())
	_prev_splat = MwRinkBlend3D.by_key(_splat_items) if continuous else {}
	_splat = f.get("splat", {})
	_splat_items = MwSplatter.items(_splat)
	var atlas := _splat.get("atlas") as MwSplatterAtlas
	if atlas != null:
		_paint_ops = int(_splat.get("ops", 0))   # a replay's frame: the paint as it was ([method _paint_seek])
	_paint_ops_made = _splat.get("ops_made", Callable())
	if atlas != _paint:
		_paint = atlas
		_paint_shown = false
		model.set_paint(atlas.texture() if atlas != null else null, false)
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
	if not auto_blend:
		blend_to(1.0)


## Brings the paint toward the latest frame's operations: the live paint's
## latest at once (its last copy is near; the match paints on from its
## texels), a replay's frame - and anything on an atlas that [member
## MwSplatterAtlas.follows] another - within this rendered frame's share of
## [constant PAINT_USEC] (the rest in the frames after); without [member
## auto_blend] (the proof scene, the tests: frames shown one at a time) at
## once. A recording's paint made on a worker thread gives its frame's
## count as far as made, asked again each time (MwSplatterReplay: "ops_made").
func _paint_seek() -> void:
	if _paint_ops_made.is_valid():
		_paint_ops = int(_paint_ops_made.call())   # (a recording's paint made on a worker thread: as far as made)
	if _paint_ops < 0 or _paint.shown() == _paint_ops:
		return
	if not auto_blend or (_paint_ops >= _paint.count() and not _paint.follows):
		_paint.seek(_paint_ops)
		return
	var frame := Engine.get_process_frames()
	if frame != _paint_frame:
		_paint_frame = frame
		_paint_until = Time.get_ticks_usec() + PAINT_USEC
	if Time.get_ticks_usec() < _paint_until:
		_paint.seek_toward(_paint_ops, -1, func() -> bool: return Time.get_ticks_usec() < _paint_until)


## Shows the way from the previous pass to the latest at [param t] (0 = the
## previous pass's points, 1 = the latest's), for frames drawn between
## passes: the owner calls it every rendered frame with the share of the pass
## interval gone by, [param dt] the rendered frame's time (s: the cameras'
## smoothing steps by it; 0 none). A free camera is placed before it. Each
## frame shows the side the camera sees (MwRinkFacing3D); nets with a model
## show it instead of their drawing (MwNets3D), but for the calibration
## camera, which also leaves out the benches' figures (plan 32, MwBench3D;
## the players coming on come out of the east arch's dark in the others). The first-person camera's rider's frames and
## any too close to its lens are not drawn ([method lens_items]).
func blend_to(t: float, dt := 0.0) -> void:
	var shot := MwRinkShot3D.blend(_prev_shot, _shot, t)
	camera.shot = shot.of_pads(local_pads) if local_pads is PackedInt32Array and shot != null else shot
	if not _life.is_empty():
		stands.show_life(MwCrowdLife.blend(_prev_life, _life, t))      # the crowd as the passes say
	camera.dt = dt
	camera.clock = lerpf(_prev_clock, _clock, t) if _clock >= 0.0 else -1.0
	if _chant != null:
		stands.chant(_chant.time(camera.clock), _chant.period, _chant_first)   # plan 33: as the frame shows it
	camera.follow(MwRinkBlend3D.point(_prev_shown, _shown, t))
	var ws := camera.world_scale()          # (the match's opening glides into ORTHO's, plan 33)
	if world.scale != ws:
		world.scale = ws
	var layers := layers_now()               # plan 40 (R2): decided once, here
	sprite_layers(layers)
	var mirror := layers.reflections         # plan 37: the ice as a mirror
	if mirror != _reflections_shown:
		_reflections_shown = mirror
		model.set_reflections(mirror)
		nets.reflections = mirror
	if _paint != null:
		_paint_seek()
		_paint.flush()                      # new paint uploaded (at most once a frame)
	if layers.paint != _paint_shown:
		_paint_shown = layers.paint
		model.set_paint(_paint.texture() if _paint != null else null, layers.paint)
	var bits := (1 if layers.blood else 0) | (2 if layers.ice_detail else 0)
	if bits != _layers_shown:
		_layers_shown = bits                  # the VISUALS page's switches, at once
		model.set_paint_layers(layers.blood, layers.ice_detail)
	var boards := camera.cut_boards()      # cameras beyond the end boards look over them
	stands.cutaway(camera if boards != 0.0 else null, boards)
	var rom := MwRom.data() if MwRom.available() else PackedByteArray()
	var items := MwRinkBlend3D.items(_prev, _items, t)
	if not layers.original:
		items = MwBench3D.arch_shade(items)       # plan 32: on from the east arch's dark
		if layers.benches:
			items = items + MwRinkBlend3D.items(_prev_bench, _bench_items, t)
		if layers.particles and not _splat_items.is_empty():
			items = items + MwRinkBlend3D.items(_prev_splat, _splat_items, t)   # plan 37: in flight
	items = MwRinkFacing3D.apply(items, camera, rom)
	items = lens_items(items, camera)
	_make_way(items, rom, dt, layers.crowd_duck)
	stands.satan_make_way(MwStands3D.satan_figures(items), dt)      # Satan steps aside
	items = nets.take(items, sprites.original_order)
	sprites.show_items(items)
	for it: Dictionary in items:
		if it.get("key", "") == "puck/body":
			stands.watch(it["at"], camera)
			break


## The layers this view shows now (MwViewLayers: the settings, the
## camera's mode, the match's paint, [member benches]).
func layers_now() -> MwViewLayers:
	return MwViewLayers.of(camera.mode, _paint != null, benches)


## The sprites' part of [param layers]: the original's order, the flat
## shadows, the reflections.
func sprite_layers(layers: MwViewLayers) -> void:
	sprites.original_order = layers.original
	sprites.flat_shadows = layers.flat_shadows
	sprites.reflections = layers.reflections


## The crowd makes way for the things on the ice as this frame shows them
## (MwCrowdDuck; owner, 2026-10-09: the near end's fans hid the bottom of
## the rink), [param dt] s after the frame before, more widely during a
## goal (the frame's phase; the lamps' skulls count then). The main 3D cameras
## only ([method ducks]), with [member MwSettings.crowd_duck] on; in the
## other views the crowd stands.
func _make_way(items: Array, rom: PackedByteArray, dt: float, duck: bool) -> void:
	if not duck or rom.is_empty():
		stands.clear_way()
		return
	var scoring := _shot != null and _shot.phase == MwRinkState.PHASE_GOAL
	stands.make_way(MwCrowdDuck.things(items, func(it: Dictionary) -> Vector4: return drawing(it, rom), scoring), dt, \
			scoring)


## True for the cameras the crowd makes way in: the main 3D camera (owner:
## that one only - FOLLOW) and 3D EXTENDED, the same camera widened (owner,
## 2026-10-10: the crowd ducking at the rink's bottom end there too, the same
## way).
static func ducks(mode: MwRinkCamera3D.Mode) -> bool:
	return mode == MwRinkCamera3D.Mode.FOLLOW or mode == MwRinkCamera3D.Mode.EXTENDED


## Where frame [param it] (an UPRIGHT MwRinkDraw3D item) is drawn round its
## ice point: left, top, width, height px, y down (MwSprites3D's px_rect;
## zero: no drawing).
func drawing(it: Dictionary, rom: PackedByteArray) -> Vector4:
	var f := sprites.frame_texture(rom, int(it["frame"]), int(it["attr"]))
	if f.is_empty():
		return Vector4.ZERO
	var at: Vector3 = it["at"]
	var off: Vector2i = it["offset"]
	return Vector4(float(f["x0"]) + off.x, float(f["y0"]) + off.y - at.z, float(f["w"]), float(f["h"]))


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
