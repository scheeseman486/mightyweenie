extends Node2D
## Plan 14 proof: recorded matches of the original played back in the 2D rink
## and the 3D rink, switching instantly. Recordings are `mw_harness
## rink-dump` output (out/rink/dec/*.json, local; docs/compare.md). Both views
## draw the same recorded state each pass: the 2D one as the rink scene does
## (planes, two sprite layers), the 3D one through MwRinkView3D, with the
## screen-space pieces and the clock widget on top.
##
## Keys: F3 2D / 3D, F4 camera (follow, calibration, overview, reverse),
## F5 next recording, F6 3D at the window's resolution / at 320 x 224,
## F7 frame rate cap (the display's, none, 30, 60), Space pause, Left / Right
## one pass while paused.
##
## The passes keep the recording's timing on the 60 Hz physics tick whatever
## the frame rate; the 3D view is drawn every frame, between passes
## (MwRinkView3D.blend_to). The 2D view shows each pass as it is.
##
## In 3D at the window's resolution the window scales its 2D content as canvas
## items (fractional, aspect kept) instead of as one 320 x 224 image, and the
## 3D viewport renders every window pixel of the 320 x 224 screen. The 2D view
## keeps the project's pixel-exact scaling.

## Folder of recordings (empty: <repo>/out/rink/dec).
@export var recordings_dir := ""
@export var start_3d := true
## 3D at the window's resolution (F6), else at 320 x 224 like the 2D view.
@export var hi_res_3d := true

@onready var palette: RomPalette = $Backdrop.palette
@onready var plane_low: RomTileMapLayer = $PlaneLow
@onready var plane_high: RomTileMapLayer = $PlaneHigh
@onready var sprites_low: MwSpriteLayer = $SpritesLow
@onready var sprites_high: MwSpriteLayer = $SpritesHigh
@onready var view_box: SubViewportContainer = $View3D
@onready var view: MwRinkView3D = $View3D/Viewport/RinkView3D
@onready var screen_low: MwSpriteLayer = $ScreenLow
@onready var screen_high: MwSpriteLayer = $ScreenHigh
@onready var window: RomPlane = $Window
@onready var info: Label = $Info

const MODES := ["follow", "calibration", "overview", "reverse"]
## Frame rate caps (F7): name, vsync, max fps (0 = none).
const CAPS := [["display", true, 0], ["uncapped", false, 0], ["30 fps", false, 30], ["60 fps", false, 60]]

var rom: PackedByteArray
var drawer: MwRinkDraw3D
var files := PackedStringArray()
var file_i := 0
var passes: Array = []
var at := 0
var ticks := 0
var show_3d := true
var paused := false
var cap := 0
var _info := ""
var _fps_wait := 0.0
var _scale_mode: Window.ContentScaleMode
var _scale_stretch: Window.ContentScaleStretch


func _ready() -> void:
	show_3d = start_3d
	var root := get_tree().root
	_scale_mode = root.content_scale_mode
	_scale_stretch = root.content_scale_stretch
	root.size_changed.connect(_fit_view)
	_fit_view()
	_apply_cap()
	if not MwRom.available():
		info.text = "no ROM (tools/bin/setup-rom)"
		return
	rom = MwRom.data()
	drawer = MwRinkDraw3D.new(rom)
	view.palette = palette
	var dir := recordings_dir
	if dir == "":
		dir = ProjectSettings.globalize_path("res://").path_join("../out/rink/dec").simplify_path()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			files.append(dir.path_join(f))
	files.sort()
	if files.is_empty():
		info.text = "no recordings in " + dir
		return
	_load(0)


func _load(i: int) -> void:
	file_i = posmod(i, files.size())
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(files[file_i]))
	passes = (d as Dictionary).get("passes", []) if d is Dictionary else []
	at = 0
	ticks = 0
	if not passes.is_empty():
		var first: Dictionary = passes[0]["state"]
		palette.team_a = int(first.get("team_a", 0))      # not in the recordings: default teams
		palette.team_b = int(first.get("team_b", 5))
		palette.stadium = int(first.get("stadium", 0))
	for layer: MwSpriteLayer in [sprites_low, sprites_high, screen_low, screen_high]:
		layer.palette = palette          # the layers keep a material made from the old colours
	_present()


func _physics_process(_delta: float) -> void:
	if paused or passes.is_empty():
		return
	ticks += 1
	var moved := false
	while at + 1 < passes.size() and ticks >= int(passes[at + 1]["e"]):
		ticks -= int(passes[at + 1]["e"])
		at += 1
		moved = true
	if moved:
		_present(true)


## Every rendered frame: the 3D view between the last two passes (the share of
## the next pass's interval gone by), and the frame rate.
func _process(delta: float) -> void:
	if show_3d and not passes.is_empty():
		var t := 1.0
		if not paused and at + 1 < passes.size():
			var e := maxi(int(passes[at + 1]["e"]), 1)
			t = (ticks + Engine.get_physics_interpolation_fraction()) / e
		view.blend_to(t)
	_fps_wait -= delta
	if _fps_wait <= 0.0:
		_fps_wait = 0.5
		_show_info()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F3:
			show_3d = not show_3d
			_fit_view()
		KEY_F4:
			view.set_camera_mode((view.camera.mode + 1) % MODES.size())
		KEY_F5:
			_load(file_i + 1)
			return
		KEY_F6:
			hi_res_3d = not hi_res_3d
			_fit_view()
		KEY_F7:
			cap = (cap + 1) % CAPS.size()
			_apply_cap()
		KEY_SPACE:
			paused = not paused
		KEY_RIGHT:
			at = mini(at + 1, passes.size() - 1)
		KEY_LEFT:
			at = maxi(at - 1, 0)
		_:
			return
	_present()


## The 3D view's resolution: every window pixel of the 320 x 224 screen (the
## window then scales 2D as canvas items), or 320 x 224 (the project's
## pixel-exact viewport scaling, as in 2D).
func _fit_view() -> void:
	var root := get_tree().root
	var vp: SubViewport = view_box.get_node("Viewport")
	var screen := Vector2(MwRink3D.SCREEN)
	if show_3d and hi_res_3d:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
		var k := minf(root.size.x / screen.x, root.size.y / screen.y)
		view_box.stretch = false
		vp.size = Vector2i((screen * k).round())
		view_box.scale = screen / Vector2(vp.size)
	else:
		root.content_scale_mode = _scale_mode
		root.content_scale_stretch = _scale_stretch
		view_box.scale = Vector2.ONE
		view_box.stretch = true
		view_box.size = screen


## The frame rate cap [member cap] (F7).
func _apply_cap() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if CAPS[cap][1] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = CAPS[cap][2]


## Shows pass [member at] in the current view; [param continuous]: it follows
## the pass shown before (the 3D view blends from it).
func _present(continuous := false) -> void:
	if passes.is_empty():
		return
	var p: Dictionary = passes[at]
	var state := MwRinkState.from_dict(rom, p["state"])
	var list := drawer.build(state, p.get("phase_adds", []))
	var tiles := {}
	for slot in 4:
		var v: Array = state.plates[slot]
		var b := MwPlate.tiles(rom, v[0], v[1], v[2])
		for n in 8:
			tiles[MwRinkDraw.PLATE_TILES + 8 * slot + n] = b.slice(32 * n, 32 * n + 32)
	for n: CanvasItem in [$Backdrop, plane_low, plane_high, sprites_low, sprites_high]:
		n.visible = not show_3d
	for n: CanvasItem in [view_box, screen_low, screen_high]:
		n.visible = show_3d
	view_box.get_node("Viewport").render_target_update_mode = \
			SubViewport.UPDATE_ALWAYS if show_3d else SubViewport.UPDATE_DISABLED
	if show_3d:
		view.present(state, drawer, tiles, continuous)
		var screen := drawer.screen_sprites()
		for layer: MwSpriteLayer in [screen_low, screen_high]:
			layer.ram_tiles = tiles
			layer.show_list(screen)
	else:
		for layer: MwSpriteLayer in [sprites_low, sprites_high]:
			layer.ram_tiles = tiles
			layer.show_list(list)
		plane_low.position = Vector2(-state.camera.shown)
		plane_high.position = Vector2(-state.camera.shown)
	var c: Variant = p["state"].get("clock")
	MwClockHud.erase(window, true)
	if c != null and int(c["flags"]) & 2:
		var pp := int(c["powerplay"]) if int(c["flags"]) & 1 else -1
		MwClockHud.draw(window, rom, int(c["period"]), int(c["seconds"]), pp)
	var res := ""
	if show_3d:
		var size: Vector2i = (view_box.get_node("Viewport") as SubViewport).size
		res = " %dx%d" % [size.x, size.y]
	_info = "%s%s  %s  %s  %d/%d%s" % ["3D" if show_3d else "2D", res, MODES[view.camera.mode] if show_3d else "",
			files[file_i].get_file().get_basename(), at, passes.size() - 1, "  paused" if paused else ""]
	_show_info()


func _show_info() -> void:
	if _info != "":
		info.text = "%s  %d fps (%s)" % [_info, roundi(Engine.get_frames_per_second()), CAPS[cap][0]]
