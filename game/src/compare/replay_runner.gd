extends SceneTree
## Headless run of our side for a comparison (tools/bin/compare-godot):
##
##   godot --headless -s res://src/compare/replay_runner.gd -- \
##       --script compare/scripts/x.mwi --replay out/compare/x.original.jsonl \
##       --out out/compare/x.godot.jsonl [--from-screen 1]
##
## Plays the input script with MwScriptPlayer and times passes with
## MwPassClock in REPLAY mode, writing a pass record with MwPassRecorder.
## The screen flow itself is still taken from the original record: the
## screens are placeholders (plan 04) until plans 05+ build them, then this
## runner drives the real MwRouter with MwScriptedInput instead. So this
## proves the plumbing (timing replay, script timing, recording), not game
## behaviour. Ticks are our own (offset
## from the original's) to exercise the relative tick comparison.

const TICK_OFFSET := -1000   # our tick = original tick + offset


func _init() -> void:
	var args := _args()
	for k in ["script", "replay", "out"]:
		if not args.has(k):
			printerr("replay_runner: missing --%s" % k)
			quit(2)
			return
	var input_script := MwInputScript.load_file(args.script)
	if input_script.error != "":
		printerr("replay_runner: %s: %s" % [args.script, input_script.error])
		quit(2)
		return
	var records := _read_jsonl(args.replay)
	var from_screen := int(args.get("from-screen", "-1"))
	var code := run(input_script, records, from_screen, args.out)
	quit(code)


static func run(input_script: MwInputScript, records: Array, from_screen: int, out_path: String) -> int:
	# The stub screen flow: screen entries and resumes from the original record.
	var flow: Array = []
	var started := from_screen < 0
	var end_tick := -1
	for r in records:
		var ev: String = r.get("event", "")
		if ev == "screen" and not started and int(r.screen) == from_screen:
			started = true
		if not started:
			continue
		if ev == "screen" or ev == "resume":
			flow.append(r)
		elif ev == "end":
			end_tick = int(r.tick)
	if flow.is_empty() or end_tick < 0:
		printerr("replay_runner: no screens / no end in the original record")
		return 2
	var clock := MwPassClock.replay(records)
	var player := MwScriptPlayer.new(input_script)
	var rec := MwPassRecorder.new()
	rec.header(input_script.name, ["time", "input"])
	var read := [0, 0, 0, 0]        # pad words as the last pass read them
	var prev_held := [0, 0, 0, 0]
	var fi := 0
	var t := int(flow[0].tick) + TICK_OFFSET
	var last := end_tick + TICK_OFFSET
	var cur_prev := -1
	while t <= last:
		player.tick_start(t)
		if player.ended():
			break
		while fi < flow.size() and int(flow[fi].tick) + TICK_OFFSET <= t:
			_boundaries(clock, player, rec, read, prev_held, t)
			var r: Dictionary = flow[fi]
			if r.event == "screen":
				clock.screen_entered(int(r.screen), t)
				player.screen_entered(int(r.screen), t)
				rec.screen(int(r.screen), clock.visit, t, cur_prev)
				cur_prev = int(r.screen)
			else:
				clock.resume(int(r.screen), int(r.visit))
				player.resume(int(r.screen), int(r.visit))
				rec.resume(int(r.screen), int(r.visit), t)
			fi += 1
		_boundaries(clock, player, rec, read, prev_held, t)
		t += 1
	rec.end(t)
	var err := rec.save(out_path)
	if err != OK:
		printerr("replay_runner: cannot write %s (%s)" % [out_path, error_string(err)])
		return 2
	print("replay_runner: %d lines -> %s" % [rec.lines.size(), out_path])
	return 0


static func _boundaries(clock: MwPassClock, player: MwScriptPlayer, rec: MwPassRecorder,
		read: Array, prev_held: Array, t: int) -> void:
	for b in clock.due(t):
		rec.pass_line(b, read.duplicate())
		player.boundary(int(b.screen), int(b.visit), int(b.pass), t)
		# the next pass reads the pads right after its boundary
		for i in 4:
			var h := player.held(i + 1)
			read[i] = (h << 8) | (h & ~int(prev_held[i]) & 0xFF)
			prev_held[i] = h


static func _read_jsonl(path: String) -> Array:
	var out: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges() != "":
			out.append(JSON.parse_string(line))
	return out


static func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	return out
