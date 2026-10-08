extends SceneTree
## Plan 14 desktop check (needs a display): a recorded demo played through
## the proof scene in 3D (follow camera, between-pass interpolation) from
## its first pass to its last, at one frame rate cap, writing the tick at
## which each pass came up. Runs at different caps must write the same
## lines (tools/bin/frame-rate-check demo).
##
##   godot --path game -s res://test/rink3d/demo_rate_run.gd -- OUT.jsonl CAP RECORDING
##
## CAP as in frame_rate_run.gd (display, uncapped, 30, 60, jitter).

var _out: FileAccess
var _proof: Node
var _cap := ""
var _ticks := 0
var _shown := -1
var _frames := 0
var _start_ms := 0
var _last_ms := 0
var _longest_ms := 0
var _stall := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3 or not MwRom.available():
		printerr("demo_rate_run: OUT.jsonl CAP RECORDING (and a ROM)")
		quit(2)
		return
	_out = FileAccess.open(a[0], FileAccess.WRITE)
	_cap = a[1]
	_stall.seed = 1
	root.title = "frame rate check (demo): " + _cap
	_proof = load("res://scenes/_proof/rink3d.tscn").instantiate()
	_proof.paused = true
	root.add_child(_proof)
	for i in 3:
		await process_frame
	var i := 0
	for f: String in _proof.files:
		if f.get_file().get_basename() == a[2]:
			break
		i += 1
	_proof._load(i)
	_proof.cap = ["display", "uncapped", "30", "60"].find(_cap) if _cap != "jitter" else 1
	_proof._apply_cap()
	await physics_frame
	_proof.paused = false
	_start_ms = Time.get_ticks_msec()
	_last_ms = _start_ms
	physics_frame.connect(_on_tick)
	process_frame.connect(_on_frame)


func _on_tick() -> void:
	_ticks += 1
	var at: int = _proof.at
	if at != _shown:
		_shown = at
		_out.store_line(JSON.stringify({"pass": at, "tick": _ticks}))
	if at >= _proof.passes.size() - 1:
		_finish()


func _on_frame() -> void:
	_frames += 1
	var now := Time.get_ticks_msec()
	if _ticks > 60:
		_longest_ms = maxi(_longest_ms, now - _last_ms)
	_last_ms = now
	if _cap == "jitter":
		OS.delay_msec(_stall.randi_range(0, 50))


func _finish() -> void:
	if _out == null:
		return
	var secs := (Time.get_ticks_msec() - _start_ms) / 1000.0
	_out.store_line(JSON.stringify({"event": "end", "cap": _cap, "ticks": _ticks, "frames": _frames,
			"seconds": secs, "fps": _frames / maxf(secs, 0.001), "longest_frame_ms": _longest_ms}))
	_out.close()
	_out = null
	print("demo_rate_run %s: %d passes in %d ticks, %d frames in %.1f s (%.0f fps, longest frame %d ms)" % [
			_cap, _proof.passes.size(), _ticks, _frames, secs, _frames / maxf(secs, 0.001), _longest_ms])
	quit()
