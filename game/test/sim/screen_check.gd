extends SceneTree
## screen-check (plan 11): the screens between plays of recorder v5's
## recordings (`mw_harness sim-record` SCREEN_RUNS) run through our ports
## ([MwScreenSims]) pass for pass. Each screen visit starts from the RAM at
## the screen's call (decoded into an [MwRinkState]); each pass gets the
## original's elapsed ticks (d0 at the pass boundary, else the tick
## difference) and the pads its `read_joypads` saw (the RAM at the next
## record), then the fields the port models, the main random stream among
## them, are compared with the RAM at the next pass boundary; at the end
## the screen left for.
##
##   tools/bin/screen-check [NAME ...] [--only SCREEN] [--show N] [--detail VISIT]
##   tools/bin/screen-check [NAME ...] --fixture   (writes compare/fixtures/screen_visits.json)
##
## Audits of what live play does differently from these runs (they show
## as differences): `--fresh` gives no sim the RAM it keeps between visits
## (live play makes new sims: [member ScreenVisit.fresh]); `--deaf` answers
## every "still playing?" poll "ended", as live play does until the sound
## driver (plan 12; [member ScreenVisit.Hooks.deaf]).

const RUNS: Array[String] = []

## pass_check (as a library: [method _ring_at]).
const PassCheck := preload("res://test/sim/pass_check.gd")
## The visit runner shared with pass_check.
const ScreenVisit := preload("res://test/sim/screen_visit.gd")


var only := -1
var detail := -1
var fixture := false
## [method _ring_at]'s pass_check, the recording it runs and the rink
## pairs it has run.
var _rings: PassCheck = null
var _rings_rec := ""
var _rings_done := 0
var _rings_logs := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var names: Array[String] = []
	var show := 6
	var i := 0
	while i < args.size():
		match args[i]:
			"--only":
				i += 1
				only = int(args[i])
			"--show":
				i += 1
				show = int(args[i])
			"--detail":
				i += 1
				detail = int(args[i])
			"--fresh":
				ScreenVisit.fresh = true
			"--deaf":
				ScreenVisit.Hooks.deaf = true
			"--fixture":
				fixture = true
			_:
				names.append(args[i])
		i += 1
	var rom := MwRom.data()
	if fixture:
		_build_fixture(rom, names)
		if _rings != null:
			_rings.free()
		quit(0)
		return
	var failed := false
	for name in names:
		var rec := MwSimRecording.open(name)
		if rec == null:
			print("%s: no recording (tools/bin/py -m mw_harness sim-record %s)" % [name, name])
			failed = true
			continue
		if rec.screen_passes.is_empty():
			print("%s: no screen records (recorder v5: SCREEN_RUNS)" % name)
			continue
		failed = _check(rom, rec, show) or failed
	if _rings != null:
		_rings.free()
	quit(1 if failed else 0)


func _check(rom: PackedByteArray, rec: MwSimRecording, show: int) -> bool:
	var visits := rec.screen_visits()
	var lines: Array[String] = []
	var by_screen := {}
	var failed := false
	for vi in visits.size():
		var v: Array = visits[vi]
		var scr: int = v[2]
		if only >= 0 and scr != only:
			continue
		var sim := MwScreenSims.make(scr, rom)
		var tally: Array = by_screen.get(scr, [0, 0, 0, 0, 0])   # visits, identical, passes, identical, unported
		tally[0] += 1
		if sim == null or not ScreenVisit.ported(sim):
			tally[4] += 1
			by_screen[scr] = tally
			continue
		var r := _visit(rom, rec, v, sim, vi == detail)
		tally[1] += 1 if r[0] else 0
		tally[2] += int(r[1])
		tally[3] += int(r[2])
		by_screen[scr] = tally
		if not r[0]:
			failed = true
			lines.append("  visit %d (screen %d from %d, records %d-%d): %d/%d passes identical; %s" % [
					vi, scr, int(r[4]), int(v[0]), int(v[1]), int(r[2]), int(r[1]), r[3]])
	for l in lines.slice(0, show):
		print(l)
	var parts: Array[String] = []
	for scr in by_screen.keys():
		var t: Array = by_screen[scr]
		if t[4] == t[0]:
			parts.append("%d: %d visits (not ported)" % [scr, t[0]])
		else:
			parts.append("%d: %d/%d visits, %d/%d passes" % [scr, t[1], t[0] - t[4], t[3], t[2]])
	print("%s: %s" % [rec.name, ", ".join(parts)])
	return failed


## One visit: [identical, passes, identical passes, first difference, from].
func _visit(rom: PackedByteArray, rec: MwSimRecording, v: Array, sim: MwScreenSim, show_all: bool) -> Array:
	var first: int = v[0]
	var last: int = v[1]
	var from := ScreenVisit.from_screen(rec, first)
	var s := MwRinkRam.decode(rom, rec.screen_ram(first))
	if sim.has_method("uses_ring") and bool(sim.call("uses_ring")):
		s.replay.ring_bytes = _ring_at(rom, rec, int(rec.screen_passes[first][0]))
	var acc := {"passes": 0, "same": 0, "note": ""}
	# the set-up, then each pass, against the next pass boundary; at the
	# end the screen left for and (`compare_exit`) what it left
	var each := func(j: int, to: int) -> void:
		if j > first and (to >= 0 or j == last):
			var want := ScreenVisit.next_screen(rec, j)
			if to != want:
				if acc["note"] == "":
					acc["note"] = "pass %d: leaves for %d, the original for %d" % [j, to, want]
			elif to >= 0 and sim.has_method("compare_exit"):
				# what the screen leaves: the next screen's entry record, or the rink's next segment start
				var n := int(rec.screen_passes[j][0])
				var rink_next := not ScreenVisit.contiguous(rec, j)
				var left := rec.screen_ram(j + 1) if not rink_next else (rec.start(n) if n < rec.count() else PackedByteArray())
				if not left.is_empty():
					var dx: Array = sim.call("compare_exit", left, rink_next)
					if not dx.is_empty() and acc["note"] == "":
						acc["note"] = "exit after pass %d: %s" % [j, _fmt(dx)]
					if show_all and not dx.is_empty():
						print("    exit: %s" % _fmt(dx))
			return
		if j + 1 > last:
			return
		acc["passes"] += 1
		var d := sim.compare(rec.screen_ram(j + 1), rec.screen_stack(j + 1))
		if sim.has_method("logged_draws") and bool(sim.call("logged_draws")):
			d.append_array(_draw_diffs(rom, rec, j, sim))
		var rng_want := MwRinkRam.u32(rec.screen_ram(j + 1), MwRinkRam.RNG)
		if s.rng.state != rng_want:
			d.push_front(["rng", "%08X" % s.rng.state, "%08X" % rng_want])
		if d.is_empty():
			acc["same"] += 1
		else:
			if acc["note"] == "":
				acc["note"] = "%s %d: %s" % ["set-up" if j == first else "pass", j, _fmt(d)]
			if show_all:
				print("    %d: %s" % [j, _fmt(d)])
	ScreenVisit.run(rec, v, s, sim, each)
	var note: String = acc["note"]
	return [note == "", int(acc["passes"]), int(acc["same"]), note if note != "" else "-", from]


## The replay ring's data (`$FF0000`, not in the recordings) at the
## screen entry after [param n] rink passes, as our rink passes wrote it:
## pass_check's pairs and entries run from the recording's start
## ([method MwSimRecording.ring_start]) up to the last pass before the
## entry (they carry the ring from pair to pair, the entries' screens in
## between included). Calls come in visit order; one run per recording.
func _ring_at(rom: PackedByteArray, rec: MwSimRecording, n: int) -> PackedByteArray:
	if _rings == null:
		PassCheck.library = true
		_rings = PassCheck.new()
	if _rings_rec != rec.name or n - 1 < _rings_done:
		_rings.ring = rec.ring_start()
		_rings_rec = rec.name
		_rings_done = 0
		_rings_logs = PassCheck._tick_logs(rec)
	while _rings_done < mini(n, rec.count()) - 1:
		var k := _rings_done
		var p: Dictionary = rec.passes[k]
		var q: Dictionary = rec.passes[k + 1]
		if int(p["visit"]) != int(q["visit"]) or int(p["screen"]) != int(q["screen"]):
			_rings.check_entry(rom, rec, k, _rings_logs)
		else:
			_rings.check_pair(rom, rec, k, _rings_logs)
		_rings_done += 1
	return _rings.ring.duplicate()


## Sims that opt in (`logged_draws()`): pass [param j]'s draws (the set-up's
## for the visit's first record) against the recorder's "win" / "spr" logs
## of that record, in order - the sprite pieces (`add_sprite_piece`: our
## "piece" operations, screen pixels + $80), the window plane's texts and
## fills and the map copies to it (`$1449C` into the window's name table;
## those to plane B are the planes' loading). [what, ours, theirs].
static func _draw_diffs(rom: PackedByteArray, rec: MwSimRecording, j: int, sim: MwScreenSim) -> Array:
	var out := []
	var want: Array[String] = []
	for e in rec.screen_log("spr", j):
		if int(e[0]) == 2:
			want.append(PassCheck.piece_text(int(e[2]), int(e[3]), int(e[4]), int(e[5]), int(e[6])))
	var got: Array[String] = []
	for op in sim.sprite_ops:
		if str(op[0]) == "piece":
			got.append(PassCheck.piece_text(int(op[2]) + 0x80, int(op[3]) + 0x80, int(op[5]), int(op[4]), int(op[1])))
		else:
			got.append("? " + str(op))
	_list_diff(out, "sprites", got, want)
	var other: Array[String] = []
	var logged := rec.screen_log("win", j)
	var maps: Array[String] = []
	for e in logged:
		var vram := int(e[4]) & 0xFFFF
		if int(e[0]) == 5 and vram >= PassCheck.WINDOW_VRAM:
			var at := vram - PassCheck.WINDOW_VRAM
			maps.append("map %X %dx%d (%d,%d) stride %d" % [int(e[2]) & 0xFFFFFF, (int(e[3]) & 0xFFFF) / 2, int(e[7]) & 0xFFFF,
					(at % 0x80) / 2, at / 0x80, (int(e[6]) & 0xFFFF) / 2])
	var ours_maps: Array[String] = []
	var ops := []
	for op in sim.window_ops:
		if str(op[0]) == "map":
			ours_maps.append("map %X %dx%d (%d,%d) stride %d" % [int(op[1]), int(op[3]), int(op[4]), int(op[5]), int(op[6]), int(op[2])])
		else:
			ops.append(op)
	_list_diff(out, "window", PassCheck.window_list(rom, ops), PassCheck.recorded_window(rom, logged, rec.screen_ram(j), other))
	_list_diff(out, "window maps", ours_maps, maps)
	return out


static func _list_diff(out: Array, what: String, got: Array[String], want: Array[String]) -> void:
	if got == want:
		return
	var i := 0
	while i < mini(got.size(), want.size()) and got[i] == want[i]:
		i += 1
	out.append(["%s #%d (%d / %d)" % [what, i, got.size(), want.size()], got[i] if i < got.size() else "-",
			want[i] if i < want.size() else "-"])


static func _fmt(d: Array) -> String:
	var out: Array[String] = []
	for x in d.slice(0, 6):
		out.append("%s ours %s want %s" % [str(x[0]), str(x[1]), str(x[2])])
	return "; ".join(out) + (" ... %d" % d.size() if d.size() > 6 else "")


# --- the fixture ---------------------------------------------------------------------------------

const FIXTURE := "res://../compare/fixtures/screen_visits.json"
## The screens the fixture keeps (7 needs the replay ring's data and 8 RAM
## its state does not hold: their GUT tests are synthetic).
const FIXTURE_SCREENS := [10, 12, 14, 15, 16, 17, 18, 19]
const FIXTURE_PER_SCREEN := 2
const FIXTURE_MAX_PASSES := 1500


## `--fixture`: compare/fixtures/screen_visits.json from the recordings named
## (test/screens/test_screen_visits.gd): up to [constant FIXTURE_PER_SCREEN]
## identical visits per screen, each as decoded fields only - the state at
## the call as values along a path list (its text as ROM pieces:
## rom_text.gd), the entry's tick and pads, per pass the tick, elapsed
## ticks and pads, the hooks' answers by kind, the main random state after
## the set-up and each pass (the original's: the visit is identical), the
## screen left for and the fields changed at the end.
func _build_fixture(rom: PackedByteArray, names: Array[String]) -> void:
	var paths: Array = MwSimDict.leaves(MwSimDict.to_dict(MwRinkState.new())).keys()
	var index := {}
	for i in paths.size():
		index[paths[i]] = i
	var picked := {}
	var cases := []
	var sha := ""
	for name in names:
		var rec := MwSimRecording.open(name)
		if rec == null or rec.screen_passes.is_empty():
			continue
		sha = str(rec.meta.get("rom_sha1", sha))
		var visits := rec.screen_visits()
		for vi in visits.size():
			var v: Array = visits[vi]
			var scr := int(v[2])
			if not scr in FIXTURE_SCREENS or int(picked.get(scr, 0)) >= FIXTURE_PER_SCREEN:
				continue
			if int(v[1]) - int(v[0]) > FIXTURE_MAX_PASSES:
				continue
			var sim := MwScreenSims.make(scr, rom)
			if not ScreenVisit.ported(sim):
				continue
			var r := _visit(rom, rec, v, sim, false)
			if not r[0]:
				continue
			var s := MwRinkRam.decode(rom, rec.screen_ram(int(v[0])))
			var before := MwSimDict.to_dict(s)
			var leaves := MwSimDict.leaves(before)
			var start := []
			for p in paths:
				start.append(leaves.get(p))
			var hooks := ScreenVisit.Logged.new()
			var trace := []
			var rngs := []
			var each := func(_j: int, _to: int) -> void:
				rngs.append(s.rng.state)
			var to := ScreenVisit.run(rec, v, s, MwScreenSims.make(scr, rom), each, hooks, trace)
			var d := MwSimDict.diff(before, MwSimDict.to_dict(s))
			var end := []
			for p in d:
				if p != "tick":
					# (an object the screen made - the referee's - has no index: its path)
					end.append([index.get(p, p), d[p]])
			var case := {"run": rec.name, "visit": vi, "screen": scr, "from": ScreenVisit.from_screen(rec, int(v[0])),
					"start": start, "entry": trace[0], "passes": trace.slice(1), "answers": hooks.answers,
					"rng": rngs, "exit": to, "end": end}
			cases.append(PassCheck._text_out(rom, case, "start", paths))
			picked[scr] = int(picked.get(scr, 0)) + 1
	var doc := {"format": "mw-screen-visits/1",
			"note": "Screen visits of the screens between plays from screen-check --fixture (decoded fields only).",
			"rom_sha1": sha, "paths": paths, "visits": cases}
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	print("%d visits %s -> %s" % [cases.size(), picked, ProjectSettings.globalize_path(FIXTURE).simplify_path()])

