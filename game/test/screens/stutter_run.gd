extends SceneTree
## Plan 27's stutter check (tools/bin/stutter-check; a display and a GPU):
## the real game from the boot screen - the Router autoload with its
## preloader, 3D host and audio service (no sound device) - driven by
## live_match's menu bot (CPU vs CPU) in a window, for MW_SECONDS. Logs the
## start, the first drawn frame, the preloader's finish and its slowest
## main-thread steps, the 3D host's stages, every screen entry and every
## frame slower than 25 ms (screen, tick, the fader's coverage). A slow
## frame is seen when a screen is up and the fader doesn't cover it fully;
## the run fails (exit 1) on any seen frame slower than MW_LIMIT_MS (50).
const Bots := preload("res://test/support/bots.gd")

var svc: Node
var router: MwRouter
var last := 0
var started := false
var first_draw := -1
var log_lines: PackedStringArray = []
var limit_ms := 120000
var stall_ms := 50.0
var frames := 0
var boot: Node
var host_stage := -1
var adopt_frame := 3     # MW_ADOPT_FRAME: later, so the 3D view is built before the title
var seen_stalls := 0


func _log(text: String) -> void:
	var line := "%8.1f  %s" % [Time.get_ticks_usec() / 1000.0, text]
	log_lines.append(line)
	print(line)


func _env(name: String, default: String) -> String:
	var v := OS.get_environment(name)
	return v if v != "" else default


func _initialize() -> void:
	_log("initialize (engine and autoloads ready)")
	RenderingServer.frame_post_draw.connect(func() -> void:
		if first_draw < 0:
			first_draw = Time.get_ticks_usec()
			_log("first frame drawn"), CONNECT_ONE_SHOT)


func _start() -> void:
	limit_ms = int(_env("MW_SECONDS", "120")) * 1000
	stall_ms = float(_env("MW_LIMIT_MS", "50"))
	adopt_frame = int(_env("MW_ADOPT_FRAME", "3"))
	MwSettings.fullscreen = false
	MwSettings.apply_display()
	var sz := _env("MW_SIZE", "960x540").split("x")
	if sz.size() == 2:
		DisplayServer.window_set_size(Vector2i(int(sz[0]), int(sz[1])))
	if OS.get_environment("MW_VIEW") != "":
		MwSettings.start_view = int(OS.get_environment("MW_VIEW"))
	svc = root.get_node("Router")
	router = svc.router
	var pre: MwPreloader = svc.preloader
	if pre.done():
		_preloaded(pre)
	else:
		pre.finished.connect(_preloaded.bind(pre))
	var su := router.session.setup
	su.pads = 5
	su.period_minutes = 1
	su.team_a = 0
	su.team_b = 5
	var bot := Bots.MenuBot.new()
	bot.router = router
	bot.detours = 3
	bot.cpu = true
	router.screen_entered.connect(bot.on_entered)
	router.screen_resumed.connect(bot.on_resumed)
	router.input = bot
	router.screen_entered.connect(func(id: int, visit: int, tick: int, prev: int) -> void:
		_log("enter screen %d (visit %d) tick %d from %d" % [id, visit, tick, prev]))
	boot = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	_log("boot scene added")


func _preloaded(pre: MwPreloader) -> void:
	_log("preload finished: %d scenes" % pre.scenes.size())
	for l in pre.slow_steps:
		_log("  preload step (ms since start, what, ms): " + l)


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if not started:
		started = true
		_start()
	elif frames == adopt_frame and router.current() == null:
		svc.fader.cover()
		router.adopt(boot as MwScreen)
		_log("boot adopted")
	if svc.rink_3d.stage != host_stage:
		host_stage = svc.rink_3d.stage
		_log("3D host stage %d" % host_stage)
	if last > 0 and now - last > 25000 and frames != adopt_frame:
		var ms := (now - last) / 1000.0
		var cover: float = svc.fader.coverage()
		var seen := router.current_id() >= 0 and cover < 1.0
		_log("slow frame %6.1f ms  screen %d tick %d fade %.2f host %d%s" % [ms, router.current_id(),
				router.tick, cover, svc.rink_3d.stage, "  SEEN" if seen else ""])
		if seen and ms > stall_ms:
			seen_stalls += 1
	last = now
	frames += 1
	if now / 1000 > limit_ms:
		_log("seen stalls over %d ms: %d" % [int(stall_ms), seen_stalls])
		var f := FileAccess.open(_env("MW_LOG", "user://stutter.log"), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(log_lines) + "\n")
		quit(1 if seen_stalls > 0 else 0)
	return false
