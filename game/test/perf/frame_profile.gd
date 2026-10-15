extends SceneTree
## Plan 45's frame profile (tools/bin/frame-profile; a display and a GPU, or
## Xvfb): the real game - the Router autoload with its preloader, 3D host and
## audio service - from the game setup (screen 1), driven by live_match's
## menu bot (CPU vs CPU) into a match and the screens between its plays,
## for MW_SECONDS. Every frame
## it records the frame's wall time; the game's own CPU time in the frame's
## physics steps (the router's ticks: the sim, the draw pass, the sound
## driver) and in its process step (the scenes' presentation, the 3D view),
## each bracketed by two probe nodes that run first and last; the main
## thread's time from the end of the process step to the frame drawn (the
## RenderingServer's work on it); the root viewport's and the 3D view's
## render times (CPU and GPU, the RenderingServer's measurements); the
## frame's draw calls, objects and primitives, video memory, static memory
## and object counts, with the screen, the rink's view and whether the 3D
## view is up. Writes MW_OUT.csv (a row a frame) and MW_OUT.txt (per screen
## and view: mean, median, 95th, 99th and worst of each time; the counts'
## means and peaks). Under Xvfb the wall time includes the frame's copy to
## the virtual screen: read the game's times and the GPU's instead.
##
## Environment: MW_SECONDS (default 90), MW_VIEW (the rink's view, MwRinkViews;
## default the options'), MW_ASPECT (ORIGINAL / WIDE), MW_SIZE (window size,
## default 1920x1080), MW_OUT (path without extension; default
## user://frame_profile), MW_MINUTES (period length, default 1), MW_TEAMS
## ("A,B", default 0,5). Presentation only: nothing here changes the game.
const Bots := preload("res://test/support/bots.gd")

const COLUMNS := ["frame", "usec", "screen", "view", "is_3d", "wall_ms", "process_ms", "physics_ms",
		"ticks", "draw_ms", "root_cpu_ms", "root_gpu_ms", "view_cpu_ms", "view_gpu_ms", "setup_cpu_ms", "draw_calls",
		"objects", "primitives", "video_mb", "texture_mb", "buffer_mb", "static_mb", "objects_db",
		"nodes", "orphans", "resources"]
## The columns summarised as times (mean, median, 95th, 99th, worst).
const TIMES := ["wall_ms", "process_ms", "physics_ms", "draw_ms", "root_cpu_ms", "root_gpu_ms",
		"view_cpu_ms", "view_gpu_ms"]
## The columns summarised as counts (mean, peak).
const COUNTS := ["draw_calls", "objects", "primitives", "video_mb", "static_mb", "objects_db",
		"nodes", "orphans"]

var _svc: Node
var _router: MwRouter
var _started := false
var _frames := 0
var _last_usec := 0
var _limit_usec := 0
var _rows: Array[PackedFloat64Array] = []
var _keys: PackedStringArray = []
var _boot: Node
var _entries: PackedStringArray = []
## The probes' clock readings this frame (usec): the process step's start and
## end, the physics steps' total and count, the frame drawn.
var _process_start := 0
var _process_end := 0
var _physics_usec := 0
var _physics_start := 0
var _physics_steps := 0
var _drawn := 0


## A probe node: runs first or last in the process and physics steps and
## reports the time to the profile.
class Probe:
	extends Node
	var profile: Object
	var first := true

	func _init(owner_: Object, first_: bool) -> void:
		profile = owner_
		first = first_
		var priority := -1000000 if first else 1000000
		process_priority = priority
		process_physics_priority = priority
		name = "ProfileFirst" if first else "ProfileLast"

	func _process(_delta: float) -> void:
		profile.call("_probe_process", first)

	func _physics_process(_delta: float) -> void:
		profile.call("_probe_physics", first)


func _probe_process(first: bool) -> void:
	if first:
		_process_start = Time.get_ticks_usec()
	else:
		_process_end = Time.get_ticks_usec()


func _probe_physics(first: bool) -> void:
	if first:
		_physics_start = Time.get_ticks_usec()
	else:
		_physics_usec += Time.get_ticks_usec() - _physics_start
		_physics_steps += 1


func _env(name: String, default: String) -> String:
	var value := OS.get_environment(name)
	return value if value != "" else default


func _start() -> void:
	_limit_usec = Time.get_ticks_usec() + int(_env("MW_SECONDS", "90")) * 1000000
	MwSettings.fullscreen = false
	if _env("MW_ASPECT", "") != "":
		MwSettings.aspect = _env("MW_ASPECT", "")
	MwSettings.apply_display()
	var size := _env("MW_SIZE", "1920x1080").split("x")
	if size.size() == 2:
		DisplayServer.window_set_size(Vector2i(int(size[0]), int(size[1])))
	if _env("MW_VIEW", "") != "":
		MwSettings.start_view = int(_env("MW_VIEW", ""))
	_svc = root.get_node("Router")
	_router = _svc.router
	_router.session = MwSession.new(7, 1)          # a fresh session, as live_match's (the front menu's
	var setup := _router.session.setup            # START GAME would reset its set-up to P1 v CPU)
	setup.pads = 5
	setup.period_minutes = int(_env("MW_MINUTES", "1"))
	var teams := _env("MW_TEAMS", "0,5").split(",")
	setup.team_a = int(teams[0])
	setup.team_b = int(teams[1])
	var bot := Bots.MenuBot.new()
	bot.router = _router
	bot.detours = 3
	bot.cpu = true
	_router.screen_entered.connect(bot.on_entered)
	_router.screen_resumed.connect(bot.on_resumed)
	_router.input = bot
	_router.screen_entered.connect(func(id: int, visit: int, tick: int, prev: int) -> void:
		_entries.append("%d,%d,%d,%d,%d,%.2f,%d" % [_frames, id, visit, tick, prev,
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				Performance.get_monitor(Performance.OBJECT_COUNT)]))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	root.add_child(Probe.new(self, true))
	root.add_child(Probe.new(self, false))
	RenderingServer.frame_post_draw.connect(func() -> void: _drawn = Time.get_ticks_usec())
	# the game setup (screen 1) first, as live_match: the title and the port's menus are not the
	# profile's subject, and the bot plays the original's menus from there
	_boot = (load(MwScreens.scene_path(1)) as PackedScene).instantiate()
	(_boot as MwScreen).screen_id = 1
	root.add_child(_boot)
	current_scene = _boot


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if not _started:
		_started = true
		_start()
		_last_usec = now
		return false
	if _frames == 3 and _router.current() == null:
		_svc.fader.cover()
		_router.adopt(_boot as MwScreen)
	var host: MwRink3DHost = _svc.rink_3d
	if host.viewport != null:
		RenderingServer.viewport_set_measure_render_time(host.viewport.get_viewport_rid(), true)
	if _frames > 3:
		_sample(now, host)
	_physics_usec = 0
	_physics_steps = 0
	_last_usec = now
	_frames += 1
	if now > _limit_usec:
		_finish()
		quit(0)
	return false


func _sample(now: int, host: MwRink3DHost) -> void:
	var root_rid := root.get_viewport_rid()
	var view_rid := host.viewport.get_viewport_rid() if host.viewport != null else RID()
	var shown_3d := host.visible and host.user != null
	var view := _router.session.view if _router.session != null else -1
	var row := PackedFloat64Array([
		_frames, now, _router.current_id(), view, 1.0 if shown_3d else 0.0,
		(now - _last_usec) / 1000.0,
		maxf(0.0, _process_end - _process_start) / 1000.0,      # last frame's (this one's has not run)
		_physics_usec / 1000.0,
		_physics_steps,
		maxf(0.0, _drawn - _process_end) / 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(root_rid),
		RenderingServer.viewport_get_measured_render_time_gpu(root_rid),
		RenderingServer.viewport_get_measured_render_time_cpu(view_rid) if view_rid.is_valid() else 0.0,
		RenderingServer.viewport_get_measured_render_time_gpu(view_rid) if view_rid.is_valid() else 0.0,
		RenderingServer.get_frame_setup_time_cpu(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
	])
	_rows.append(row)
	_keys.append("screen %d view %d%s" % [int(row[2]), int(row[3]), " 3D" if shown_3d else ""])


func _finish() -> void:
	var out := _env("MW_OUT", "user://frame_profile")
	var csv := FileAccess.open(out + ".csv", FileAccess.WRITE)
	if csv != null:
		csv.store_line(",".join(COLUMNS))
		for row in _rows:
			var cells := PackedStringArray()
			for value in row:
				cells.append("%.3f" % value)
			csv.store_line(",".join(cells))
	var lines := PackedStringArray()
	lines.append("frame profile: %d frames; window %s, aspect %s, view %s" % [_rows.size(),
			str(DisplayServer.window_get_size()), MwSettings.aspect, _env("MW_VIEW", "options'")])
	lines.append("adapter: %s / %s" % [RenderingServer.get_video_adapter_vendor(),
			RenderingServer.get_video_adapter_name()])
	var groups := {}
	for i in _rows.size():
		if not groups.has(_keys[i]):
			groups[_keys[i]] = []
		(groups[_keys[i]] as Array).append(i)
	for key: String in groups:
		var picked: Array = groups[key]
		lines.append("")
		lines.append("%s: %d frames" % [key, picked.size()])
		for column: String in TIMES:
			lines.append("  %-12s %s" % [column, _stats(picked, COLUMNS.find(column))])
		var counts := PackedStringArray()
		for column: String in COUNTS:
			var at := COLUMNS.find(column)
			var total := 0.0
			var peak := 0.0
			for i: int in picked:
				total += _rows[i][at]
				peak = maxf(peak, _rows[i][at])
			counts.append("%s %.1f (peak %.1f)" % [column, total / picked.size(), peak])
		lines.append("  " + ", ".join(counts))
	lines.append("")
	lines.append("screen entries (frame, screen, visit, tick, from, static MB, objects):")
	lines.append_array(_entries)
	var txt := FileAccess.open(out + ".txt", FileAccess.WRITE)
	if txt != null:
		txt.store_string("\n".join(lines) + "\n")
	print("\n".join(lines))


## Mean, median, 95th, 99th percentile and worst of column [param at] over the rows [param picked].
func _stats(picked: Array, at: int) -> String:
	var values := PackedFloat64Array()
	for i: int in picked:
		values.append(_rows[i][at])
	values.sort()
	var total := 0.0
	for value in values:
		total += value
	var count := values.size()
	return "mean %7.3f  p50 %7.3f  p95 %7.3f  p99 %7.3f  max %8.3f" % [total / count,
			values[count / 2], values[mini(count - 1, int(count * 0.95))],
			values[mini(count - 1, int(count * 0.99))], values[count - 1]]
