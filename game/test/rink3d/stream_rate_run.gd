extends SceneTree
## Plan 40 (T7, step 2): one recorded game - its start record and its input
## stream (MwNetRecording, made once by the offline proof:
## test/screens/net_determinism.gd) - played at one frame rate cap as the
## game plays: the Router service stepping it on the physics ticks, every
## screen drawn (the rink in 3D, [param VIEW]). Its hashes (the rink every
## pass, the session at every screen: MwNetRecording.watch) are compared with
## the recording's by the offline proof's own comparer
## (MwNetRecording.first_difference): the frame rate changes nothing (owner:
## unlocked frame rate, no change to behaviour or timing). tools/bin/
## frame-rate-check stream records it and plays it at every cap side by side.
##
##   godot --path game -s res://test/rink3d/stream_rate_run.gd -- RECORDING CAP OUT.json [VIEW]
##
## CAP: display (vsync), uncapped, 30, 60, or jitter (uncapped, with random
## 0-50 ms stalls between frames). VIEW: the rink's camera at the start
## (MwRinkViews; default 7). OUT: one JSON object - the result ("equal" or
## the first difference), the ticks, frames, seconds, fps, the longest
## frame. Exits 0 when equal.

const VIEW := 7

var _out := ""
var _cap := ""
var _rec: MwNetRecording
var _mine := MwNetRecording.new()
var _router: MwRouter
var _stall := RandomNumberGenerator.new()
var _frames := 0
var _start_ms := 0
var _last_ms := 0
var _longest_ms := 0
var _tick0 := 0
var _done := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3 or not MwRom.available():
		printerr("stream_rate_run: RECORDING CAP OUT.json [VIEW] (and a ROM)")
		quit(2)
		return
	_rec = MwNetRecording.open(a[0])
	if _rec == null:
		printerr("stream_rate_run: no recording at %s" % a[0])
		quit(2)
		return
	_cap = a[1]
	_out = a[2]
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
	root.title = "frame rate check (stream): " + _cap
	var svc: Node = root.get_node("Router")
	_router = svc.router
	await process_frame
	MwSettings.start_view = int(a[3]) if a.size() > 3 else VIEW
	# as every machine of an online match starts (MwGameStart): the record's
	# session, its rules and teams, the pass clock on the stream
	MwGameStart.begin(_router, MwSession.new(1, 1), _rec.record, MwPassClock.streamed(_rec.stream))
	MwStreamInput.new(_rec.stream).attach(_router)
	_mine.watch(_router)
	MwGameStart.enter_first(_router, _rec.record)
	_tick0 = _router.tick
	_start_ms = Time.get_ticks_msec()
	_last_ms = _start_ms
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	var now := Time.get_ticks_msec()
	if _router.tick - _tick0 > 300:          # past the start-up's loading
		_longest_ms = maxi(_longest_ms, now - _last_ms)
	_last_ms = now
	if _cap == "jitter":
		OS.delay_msec(_stall.randi_range(0, 50))
	if not _done and _router.tick >= _rec.stream.last_tick():
		_finish()


func _finish() -> void:
	_done = true
	var diff := _rec.first_difference(_mine.hashes)
	var secs := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"cap": _cap, "result": "equal" if diff == "" else diff,
			"hashes": _mine.hashes.size(), "ticks": _router.tick - _tick0, "frames": _frames, "seconds": secs,
			"fps": _frames / maxf(secs, 0.001), "longest_frame_ms": _longest_ms}))
	f.close()
	MwGameStart.own_context()
	quit(0 if diff == "" else 1)
