extends SceneTree
## Plan 15 cinematic (desktop, needs a display; plan 16 shots added): a
## recorded match played back in the 3D rink with the stands half full, the
## camera flying a fixed list of shots round the play for two minutes and
## twenty seconds (MwRinkCamera3D FREE mode; each sprite shows the side the
## camera sees, MwRinkFacing3D; the 3D draw order hides players behind the
## crowd). The crowd makes way for the camera among it (near_hide_px). No
## HUD. Record it with Godot's movie maker:
##
##   godot --path game --fixed-fps 60 --write-movie OUT.avi \
##       -s res://test/rink3d/crowd_cinema.gd -- [RECORDING [START_S [OCCUPANCY]]]
##
## The movie maker records at the project's viewport size (320 x 224): for
## 1920 x 1080 put an override.cfg next to project.godot for the run (not
## committed) with display/window/size/viewport_width, viewport_height and
## the window size overrides set. The script renders at the window's size.
##
## At 60 fps each frame is one tick of the sim's 60 Hz: the passes keep the
## recording's timing and the view moves between them every frame
## (MwRinkView3D.blend_to), as in the proof scene at an unlocked rate.
##
## RECORDING: a basename in out/rink/dec (default demo_s3), START_S: seconds
## into it (6), OCCUPANCY: 0..1 (0.5). Presentation only.

const PROOF_DIR := "../out/rink/dec"
const LENGTH := 140.0           # s of film
const FADE_IN := 1.0
const FADE_OUT := 2.0
const FOCUS_RATE := 2.5         # 1/s: how fast the smoothed focus catches the play

var rom: PackedByteArray
var drawer: MwRinkDraw3D
var view: MwRinkView3D
var cam: MwRinkCamera3D
var passes: Array = []
var at := 0
var ticks := 0
var film := 0.0
var started := false
var focus := Vector3.ZERO
var fade: ColorRect
var shots: Array = []
var _shot_shown := -1
var _last_print := -1


## The shots, in order: [seconds, blend-in seconds (0 = cut), name, pose]. A
## pose takes the shot's progress u (0..1), the smoothed focus f and the
## game camera's own focus g (rink px, on the ice) and gives [camera at,
## looking at (rink px), vertical fov].
func _shots() -> Array:
	return [
		[14.0, 0.0, "reveal over the near crowd", func(u: float, f: Vector3, _g: Vector3) -> Array:
			var e := _ease(u)
			return [Vector3(40, 494, 150).lerp(Vector3(0, 860, 600), e),
					Vector3(f.x * 0.5, f.y * 0.5 + 60, 10).lerp(Vector3(0, 20, 0), e), lerpf(52, 44, e)]],
		[12.0, 2.5, "broadcast", func(_u: float, _f: Vector3, g: Vector3) -> Array:
			return [g + Vector3(0, 240, 240), g, 36.0]],
		[16.0, 3.0, "orbit over the left stands", func(u: float, f: Vector3, _g: Vector3) -> Array:
			var a := deg_to_rad(lerpf(0, -115, _ease(u)))
			var c := Vector3(f.x * 0.5, f.y * 0.7, 0)
			return [c + Vector3(sin(a) * 340, cos(a) * 340, 300), f, 46.0]],
		[12.0, 0.0, "low in the far corner", func(u: float, f: Vector3, _g: Vector3) -> Array:
			return [Vector3(lerpf(-150, -95, u), -350, 50),
					Vector3(f.x * 0.7, maxf(f.y + 60, -200), 25), 52.0]],
		[14.0, 0.0, "behind the far crowd", func(u: float, f: Vector3, _g: Vector3) -> Array:
			return [Vector3(lerpf(-170, 170, _ease(u)), -610, 270), f, 48.0]],
		# over the heads of the rows in front, moving along with the play so it
		# looks across the rink rather than along its own row
		[12.0, 0.0, "a fan's eye, left stands", func(_u: float, f: Vector3, _g: Vector3) -> Array:
			return [Vector3(-345, clampf(f.y + 90, -250, 280), 185), f + Vector3(0, 0, 10), 55.0]],
		[14.0, 0.0, "cable cam over the right boards", func(u: float, f: Vector3, _g: Vector3) -> Array:
			return [Vector3(150, lerpf(330, -330, _ease(u)), 100), f + Vector3(-60, 0, 0), 50.0]],
		# plan 16: the referee watching the play from his pen, then the far net
		# and its goalie from behind
		[10.0, 0.0, "the referee's pen", func(u: float, f: Vector3, _g: Vector3) -> Array:
			return [Vector3(140, lerpf(150, -110, _ease(u)), 80), Vector3(232, 7, 40).lerp(f, 0.35), 45.0]],
		[10.0, 0.0, "behind the far net", func(u: float, f: Vector3, _g: Vector3) -> Array:
			return [Vector3(lerpf(-70, 70, _ease(u)), -366, 42), Vector3(f.x * 0.5, -180, 10), 55.0]],
		[12.0, 2.5, "reverse, from the far end", func(_u: float, f: Vector3, _g: Vector3) -> Array:
			return [f + Vector3(0, -260, 220), f, 40.0]],
		[14.0, 3.0, "pull back, the whole house", func(u: float, f: Vector3, _g: Vector3) -> Array:
			var e := _ease(u)
			var a := deg_to_rad(lerpf(200, 160, e))
			var r := lerpf(500, 1150, e)
			return [Vector3(sin(a) * r, cos(a) * r, lerpf(350, 950, e)), f.lerp(Vector3(0, 20, 0), e), lerpf(46, 42, e)]],
	]


static func _ease(u: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(u, 0.0, 1.0))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var name := a[0] if a.size() > 0 else "demo_s3"
	var start_s := float(a[1]) if a.size() > 1 else 6.0
	var occupancy := float(a[2]) if a.size() > 2 else 0.5
	if not MwRom.available():
		printerr("crowd_cinema: no ROM")
		quit(2)
		return
	var path := ProjectSettings.globalize_path("res://").path_join(PROOF_DIR).path_join(name + ".json").simplify_path()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	passes = (d as Dictionary).get("passes", []) if d is Dictionary else []
	if passes.is_empty():
		printerr("crowd_cinema: no passes in ", path)
		quit(2)
		return
	shots = _shots()
	var total := 0.0
	for s: Array in shots:
		total += s[0]
	print("crowd_cinema: ", name, " from ", start_s, " s, occupancy ", occupancy, ", ", shots.size(), " shots, ", total, " s")

	root.title = "mightyweenie - plan 15 crowd cinema"
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	rom = MwRom.data()
	drawer = MwRinkDraw3D.new(rom)
	var first: Dictionary = passes[0]["state"]
	var team_a := int(first.get("team_a", 0))
	var palette := RomPalette.make(4, PackedStringArray(["screen_palette", "rom 1BD8A 3"]), team_a, int(first.get("stadium", 0)))
	palette.team_b = int(first.get("team_b", 5))
	view = load("res://src/rink3d/rink_view_3d.tscn").instantiate()
	view.palette = palette
	root.add_child(view)
	cam = view.camera
	cam.mode = MwRinkCamera3D.Mode.FREE
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.far = 400.0
	view.stands.occupancy = occupancy
	view.stands.near_hide_px = 48.0

	var layer := CanvasLayer.new()
	root.add_child(layer)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.size = Vector2(root.size)
	layer.add_child(fade)

	# the pass START_S into the recording
	var t := 0
	while at + 1 < passes.size() and t + int(passes[at + 1]["e"]) <= roundi(start_s * 60.0):
		t += int(passes[at + 1]["e"])
		at += 1
	_present(false)
	focus = _game_focus(1.0)
	for i in 2:
		await process_frame
	started = true
	physics_frame.connect(_on_tick)
	process_frame.connect(_on_frame)


## The sim's 60 Hz tick: the recording's passes at their own timing.
func _on_tick() -> void:
	ticks += 1
	var moved := false
	while at + 1 < passes.size() and ticks >= int(passes[at + 1]["e"]):
		ticks -= int(passes[at + 1]["e"])
		at += 1
		moved = true
	if moved:
		_present(true)


## Pass [member at] into the view, the players turned for the camera's heading.
func _present(continuous: bool) -> void:
	var p: Dictionary = passes[at]
	var state := MwRinkState.from_dict(rom, p["state"])
	drawer.build(state, p.get("phase_adds", []))
	var tiles := {}
	for slot in 4:
		var v: Array = state.plates[slot]
		var b := MwPlate.tiles(rom, v[0], v[1], v[2])
		for n in 8:
			tiles[MwRinkDraw.PLATE_TILES + 8 * slot + n] = b.slice(32 * n, 32 * n + 32)
	view.present(state, drawer, tiles, continuous)


## The share of the next pass's interval gone by.
func _blend() -> float:
	if at + 1 >= passes.size():
		return 1.0
	var e := maxi(int(passes[at + 1]["e"]), 1)
	return (ticks + Engine.get_physics_interpolation_fraction()) / e


## The ice point the game's own camera looks at (rink px).
func _game_focus(t: float) -> Vector3:
	return MwRinkCamera3D.look_point(MwRinkBlend3D.point(view._prev_shown, view._shown, t))


func _on_frame() -> void:
	if not started:
		return
	var dt := root.get_process_delta_time()     # the movie maker's fixed step when recording
	film += dt
	var t := _blend()
	var g := _game_focus(t)
	focus = focus.lerp(g, 1.0 - exp(-FOCUS_RATE * dt))
	_place(g)                     # the camera first: the sprites turn for it
	view.blend_to(t)
	var k := 1.0
	if film < FADE_IN:
		k = film / FADE_IN
	elif film > LENGTH - FADE_OUT:
		k = (LENGTH - film) / FADE_OUT
	fade.size = Vector2(root.size)
	fade.color = Color(0, 0, 0, 1.0 - clampf(k, 0.0, 1.0))
	if int(film) != _last_print:
		_last_print = int(film)
		print("film %3d s  pass %d/%d" % [_last_print, at, passes.size() - 1])
	if film >= LENGTH or at + 1 >= passes.size():
		print("crowd_cinema: done, ", Engine.get_frames_drawn(), " frames")
		quit()


## The camera for the film's time: the current shot's pose, blended from the
## previous shot's last pose over the blend-in.
func _place(g: Vector3) -> void:
	var t0 := 0.0
	var i := 0
	while i < shots.size() - 1 and film >= t0 + shots[i][0]:
		t0 += shots[i][0]
		i += 1
	var s: Array = shots[i]
	var local := film - t0
	var pose: Array = s[3].call(local / s[0], focus, g)
	if i > 0 and s[1] > 0.0 and local < s[1]:
		var before: Array = shots[i - 1][3].call(1.0, focus, g)
		var w := smoothstep(0.0, 1.0, local / s[1])
		pose = [(before[0] as Vector3).lerp(pose[0], w), (before[1] as Vector3).lerp(pose[1], w), lerpf(before[2], pose[2], w)]
	if i != _shot_shown:
		_shot_shown = i
		print("shot %d: %s" % [i + 1, s[2]])
	var from: Vector3 = pose[0]
	var to: Vector3 = pose[1]
	var p := MwRink3D.world(from.x, from.y, from.z)
	cam.fov = pose[2]
	cam.transform = Transform3D(Basis.looking_at(MwRink3D.world(to.x, to.y, to.z) - p, Vector3.UP), p)
