extends SceneTree
## Plan 14 desktop check (needs a display): the whole game, played from the
## boot screen by a fixed input pattern, at one frame rate cap, writing what
## every pass did. Runs at different caps must write the same lines: the
## frame rate changes nothing in the game (owner: unlocked frame rate, no
## change to behaviour or timing). tools/bin/frame-rate-check runs the caps
## side by side and compares them.
##
##   godot --path game -s res://test/rink3d/frame_rate_run.gd -- OUT.jsonl CAP TICKS
##
## CAP: display (vsync), uncapped, 30, 60, or jitter (uncapped, with random
## 0-50 ms stalls between frames). TICKS: 60 Hz ticks to run.
##
## The input: START on the title, a co-op game (P1 + P2 against the CPU) from
## the main menu, then
## in the rink both pads skate in turning directions and press A, B and C
## at their own rhythms; START moves the screens between plays on. Only the
## tick count and the screen's entry tick decide what is held, so every run
## gets the same input.
##
## Each pass line: the router's boundary (screen, visit, pass, tick,
## elapsed), both random streams, and on rink screens a hash of the whole
## simulation state (MwSimDict). The last line: frames drawn, frame rate.

const SEEDS := [0x2545F491, 0x6C8E9CF5]

var _out: FileAccess
var _router: MwRouter
var _input := PatternInput.new()
var _ticks := 0
var _tick0 := 0        # router tick at the boot screen's adoption (ticks before it vary)
var _cap := ""
var _stall := RandomNumberGenerator.new()
var _frames := 0
var _start_ms := 0
var _longest_ms := 0
var _last_ms := 0


class PatternInput:
	extends MwInputSource
	## The pattern (see the script's doc). Pad bits as MwInputScript.PAD_BITS.

	const DIRS := [0x01, 0x09, 0x08, 0x0A, 0x02, 0x06, 0x04, 0x05]   # U, UR, R, DR, D, DL, L, UL
	var router: MwRouter
	var screen := -1
	var entered := 0       # router tick of the screen's entry
	var rink_from := 0     # ticks after the entry when rink play starts

	func entered_screen(id: int, at_tick: int) -> void:
		screen = id
		entered = at_tick
		rink_from = 1500 if id == 4 else 200

	func pads() -> Array[int]:
		var t := router.tick - entered
		var out: Array[int] = [0, 0]
		match screen:
			-1:
				pass
			0:                                        # title: skip to the main menu
				if t >= 120 and (t - 120) % 200 < 4:
					out[0] = 0x80
			1:                                        # main menu: pads 1-2, then start
				if t >= 200 and t < 204:
					out[0] = 0x02                     # down to the pad row
				elif (t >= 240 and t < 244) or (t >= 280 and t < 284):
					out[0] = 0x08                     # PAD 1 / PAD 2, then PAD 1-2 / SEGA
				elif t >= 320 and t < 324:
					out[0] = 0x80
			4, 5, 6:                                  # play (no START: it is the pause verb)
				if t >= rink_from:
					var u := t - rink_from
					out[0] = DIRS[(u / 60) % 8] if u % 60 < 50 else 0
					out[1] = DIRS[(u / 45 + 3) % 8] if u % 45 < 38 else 0
					if u % 97 < 4:
						out[0] |= 0x20                # C
					if u % 151 < 4:
						out[0] |= 0x40                # A
					if u % 113 < 4:
						out[1] |= 0x10                # B
					if u % 173 < 4:
						out[1] |= 0x20
			18:                                       # fight: punch
				if t % 40 < 4:
					out[0] = 0x40
			_:                                        # screens between plays: on
				if t >= 250 and (t - 250) % 200 < 4:
					out[0] = 0x80
		return out

	func sample(contexts: Array) -> Dictionary:
		var held := {}
		var masks := pads()
		for p in masks.size():
			for button in MwInputScript.PAD_BITS:
				if masks[p] & MwInputScript.PAD_BITS[button]:
					for ctx in contexts:
						for verb in MwVerbs.verbs_of(ctx, button):
							held[MwVerbs.action(p + 1, verb)] = true
							if ctx == MwVerbs.Context.MENU:
								held[MwVerbs.menu_action(p + 1, verb)] = true
		return held


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3 or not MwRom.available():
		printerr("frame_rate_run: OUT.jsonl CAP TICKS (and a ROM)")
		quit(2)
		return
	_out = FileAccess.open(a[0], FileAccess.WRITE)
	_cap = a[1]
	_ticks = int(a[2])
	_stall.seed = 1
	match _cap:
		"display":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			Engine.max_fps = 0
		"30", "60":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = int(_cap)
		_:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
	root.title = "frame rate check: " + _cap
	var svc: Node = root.get_node("Router")
	_router = svc.router
	_router.session = MwSession.new(SEEDS[0], SEEDS[1])
	_input.router = _router
	_router.input = _input
	_router.screen_entered.connect(func(id: int, _visit: int, at_tick: int, _prev: int) -> void:
		_input.entered_screen(id, at_tick))
	_router.pass_ended.connect(_on_pass)
	change_scene_to_file("res://scenes/boot/boot.tscn")
	await process_frame
	await process_frame
	_tick0 = _router.tick
	svc._adopt()
	_start_ms = Time.get_ticks_msec()
	_last_ms = _start_ms
	process_frame.connect(_on_frame)


func _on_pass(b: Dictionary) -> void:
	var s := _router.session
	var line := {"screen": b.screen, "visit": b.visit, "pass": b.pass, "tick": int(b.tick) - _tick0, "elapsed": b.elapsed,
			"rng": s.rng.state, "rng_aux": s.rng_aux.state}
	var top := _router.current()
	if top is MwRink and (top as MwRink).state != null:
		line["state"] = str(MwSimDict.to_dict((top as MwRink).state)).md5_text()
	_out.store_line(JSON.stringify(line))
	if _router.tick - _tick0 >= _ticks:
		_finish()


func _on_frame() -> void:
	_frames += 1
	var now := Time.get_ticks_msec()
	if _router.tick - _tick0 > 300:          # past the start-up's loading
		_longest_ms = maxi(_longest_ms, now - _last_ms)
	_last_ms = now
	if _cap == "jitter":
		OS.delay_msec(_stall.randi_range(0, 50))


func _finish() -> void:
	if _out == null:
		return
	var secs := (Time.get_ticks_msec() - _start_ms) / 1000.0
	_out.store_line(JSON.stringify({"event": "end", "cap": _cap, "ticks": _router.tick - _tick0, "frames": _frames,
			"seconds": secs, "fps": _frames / maxf(secs, 0.001), "longest_frame_ms": _longest_ms}))
	_out.close()
	_out = null
	print("frame_rate_run %s: %d ticks, %d frames in %.1f s (%.0f fps, longest frame %d ms)" % [
			_cap, _router.tick - _tick0, _frames, secs, _frames / maxf(secs, 0.001), _longest_ms])
	quit()
