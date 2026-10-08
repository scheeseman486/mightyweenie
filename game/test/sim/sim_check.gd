extends SceneTree
## The simulation segment against every pass of the simulation recordings
## (`mw_harness sim-record` -> out/sim/NAME/; docs/compare.md, Simulation
## recordings). Run with `tools/bin/sim-check [NAME ...] [--only TEXT]
## [--show N] [--from I] [--count N] [--roundtrip] [--think | --ai]`.
##
## Each pass starts from the recorded RAM at `$F98A` (decoded into an
## MwRinkState), runs MwRinkSim with the recorded elapsed ticks, CPU thinks
## replayed from the recording (MwReplayControl) and the tick the original
## read at each player and at the puck, and is compared byte for byte
## (MwRinkRam) with the recorded RAM at `$F9C8`. `--only` keeps differences
## whose description contains TEXT ("puck", "P3", "+$70"...).
##
## `--think`: the same, but at every recorded think the AI (MwRinkAI: `$3BFE`
## + `$8820`) runs first on the state and its AI-range RAM (`$FFB050`-
## `$FFBDC1`) is compared with the original's after the think (substate 0 of
## the states it entered included); then the state is put back and the
## recorded think applied, so the pass stays on track. `--ai`: the AI is
## the CPU control (no recorded thinks; the tick hooks stay).

const RUNS := ["cpu_s0", "p1_s9", "p1p2_s4", "cpu_s10", "p1_s8", "p1p2_s17", "coop_s14", "p1_s2",
		"cpu_s16", "p1_s5", "p4_s22"]
const REPLAY := 0
const THINK := 1
const AI := 2


## `--think`'s CPU control: our think against each recorded one, then the
## recorded one (through [MwReplayControl]).
class ThinkCheck extends RefCounted:
	var rom: PackedByteArray
	var rec: MwSimRecording
	var k := 0
	var replay: MwReplayControl
	var ai := MwRinkAI.new()
	var _thinks: Array = []          ## [a5, pre index, post index] of the pass
	var total := 0
	var same := 0
	var off_before := 0              ## thinks where our state already differed from the "before" snapshot
	var failures: Array[String] = []
	var show := 3
	var only := ""

	func _init(rom_: PackedByteArray, rec_: MwSimRecording, k_: int, replay_: MwReplayControl) -> void:
		rom = rom_
		rec = rec_
		k = k_
		replay = replay_
		var list: Array = rec.passes[k]["ai"]
		var i := 0
		while i + 1 < list.size():
			_thinks.append([int(list[i][1]) & 0xFFFFFF, int(list[i][2]), int(list[i + 1][2])])
			i += 2

	func think(sim: MwRinkSim, p: MwRinkState.Player, team: MwRinkState.Team, other: MwRinkState.Team) -> void:
		var a := MwRinkRam.player_address(p.team, p.index)
		var t: Array = []
		for i in _thinks.size():
			var e: Array = _thinks[i]
			if int(e[0]) == a:
				t = e
				_thinks.remove_at(i)
				break
		if t.is_empty():
			replay.think(sim, p, team, other)      # (notes "no recorded think")
			return
		var s := sim.s
		var pre := rec.ai(int(t[1]))
		var post := rec.ai(int(t[2]))
		var ours := MwRinkRam.encode(s, pre)
		var before := MwRinkRam.diff(ours, pre)
		if not before.is_empty():
			off_before += 1
		var tick := s.tick
		var phase := s.phase
		var jail := Vector2i(s.jail_tick, s.jail_count)
		var events := sim.events.size()
		var tk := replay._tk_at
		ai.think(sim, p, team, other)
		var d := MwRinkRam.diff(MwRinkRam.encode(s, pre), post)
		total += 1
		if d.is_empty():
			same += 1
		elif failures.size() < show:
			var why := _describe(s, p, d, MwRinkRam.encode(s, pre), pre, post)
			if not before.is_empty():
				why += " | our state before: " + _describe(s, p, before, ours, pre, pre)
			failures.append(why)
		# back to where the think started, then the original's think
		MwRinkRam.decode_into(rom, s, ours)
		s.tick = tick
		s.phase = phase
		s.jail_tick = jail.x
		s.jail_count = jail.y
		sim.events.resize(events)
		replay._tk_at = tk
		replay.think(sim, p, team, other)

	func _describe(s: MwRinkState, p: MwRinkState.Player, d: PackedInt32Array, got: PackedByteArray,
			pre: PackedByteArray, post: PackedByteArray) -> String:
		var out := []
		var seen := {}
		for addr in d:
			var desc := MwRinkRam.describe(addr)
			if only != "" and not desc.contains(only):
				continue
			if seen.has(desc):
				continue
			seen[desc] = true
			out.append("%s ours %02X want %02X (was %02X)" % [desc, MwRinkRam.u8(got, addr), MwRinkRam.u8(post, addr), MwRinkRam.u8(pre, addr)])
			if out.size() >= 6:
				out.append("... %d bytes" % d.size())
				break
		return "pass %d T%d P%d (phase %d, state %d): %s" % [k, p.team, p.index, s.phase, p.state, "; ".join(out)]

	func before_player(sim: MwRinkSim, p: MwRinkState.Player) -> void:
		replay.before_player(sim, p)

	func before_puck(sim: MwRinkSim) -> void:
		replay.before_puck(sim)

	func tick_at(sim: MwRinkSim, tag: int) -> void:
		replay.tick_at(sim, tag)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var names: Array[String] = []
	var only := ""
	var show := 3
	var from := 0
	var count := 1 << 30
	var roundtrip := false
	var mode := REPLAY
	var detail := -1
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--only":
				i += 1
				only = args[i]
			"--show":
				i += 1
				show = int(args[i])
			"--from":
				i += 1
				from = int(args[i])
			"--count":
				i += 1
				count = int(args[i])
			"--roundtrip":
				roundtrip = true
			"--think":
				mode = THINK
			"--ai":
				mode = AI
			"--detail":
				i += 1
				detail = int(args[i])
			_:
				names.append(a)
		i += 1
	if detail >= 0:
		_detail(rom_or_load(), names, detail, mode)
		quit(0)
		return
	if names.is_empty():
		names.assign(RUNS)
	var rom := MwRom.data()
	var failed := false
	var total := 0
	var total_ok := 0
	for name in names:
		var rec := MwSimRecording.open(name)
		if rec == null:
			print("%s: no recording (tools/bin/py -m mw_harness sim-record %s)" % [name, name])
			failed = true
			continue
		var ok := 0
		var n := 0
		var shown := 0
		var by_field := {}
		var thinks := 0
		var thinks_ok := 0
		var thinks_off := 0
		var think_fails: Array[String] = []
		for k in range(from, mini(rec.count(), from + count)):
			n += 1
			var d: PackedInt32Array
			if roundtrip:
				var st := rec.start(k)
				d = MwRinkRam.diff(MwRinkRam.encode(MwRinkRam.decode(rom, st), st), st)
				var en := rec.end(k)
				d.append_array(MwRinkRam.diff(MwRinkRam.encode(MwRinkRam.decode(rom, en), en), en))
			elif mode == THINK:
				var run := _run_pass(rom, rec, k, mode, show - think_fails.size(), only)
				var tc: ThinkCheck = run[2]
				thinks += tc.total
				thinks_ok += tc.same
				thinks_off += tc.off_before
				think_fails.append_array(tc.failures)
				var sim: MwRinkSim = run[0]
				d = MwRinkRam.diff(MwRinkRam.encode(sim.s, rec.start(k)), rec.end(k))
			else:
				d = check_pass(rom, rec, k, mode)
			var kept := PackedInt32Array()
			var names_here := {}
			for addr in d:
				var desc := MwRinkRam.describe(addr)
				if only == "" or desc.contains(only):
					kept.append(addr)
					names_here[_field_key(desc)] = true
			for f in names_here:
				by_field[f] = int(by_field.get(f, 0)) + 1
			if kept.is_empty():
				ok += 1
				continue
			if shown < show:
				shown += 1
				print("  %s pass %d (e %d, phase %d): %s" % [name, k, rec.elapsed(k), MwRinkRam.u16(rec.start(k), MwRinkRam.PHASE),
						_explain(rom, rec, k, kept, mode)])
		total += n
		total_ok += ok
		var worst := by_field.keys()
		worst.sort_custom(func(x: String, y: String) -> bool: return by_field[x] > by_field[y])
		var top := []
		for f in worst.slice(0, 8):
			top.append("%s %d" % [f, by_field[f]])
		if mode == THINK:
			for t in think_fails:
				print("  %s think %s" % [name, t])
			print("%s: %d/%d thinks identical%s" % [name, thinks_ok, thinks,
					("  (%d started from a state that differed)" % thinks_off) if thinks_off else ""])
			failed = failed or thinks_ok < thinks
		print("%s: %d/%d passes identical%s" % [name, ok, n, ("  (" + ", ".join(top) + ")") if not top.is_empty() else ""])
		failed = failed or ok < n
	print("total: %d/%d" % [total_ok, total])
	quit(1 if failed else 0)


## Pass [param k] run as [param mode] wants: [sim, replay, think check or null].
static func _run_pass(rom: PackedByteArray, rec: MwSimRecording, k: int, mode: int, show := 0, only := "") -> Array:
	var s := MwRinkRam.decode(rom, rec.start(k))
	var sim := MwRinkSim.new(rom, s)
	var replay := MwReplayControl.new(rom, rec, k)
	var tc: ThinkCheck = null
	sim.hooks = replay
	match mode:
		THINK:
			tc = ThinkCheck.new(rom, rec, k, replay)
			tc.show = maxi(show, 0)
			tc.only = only
			sim.cpu = tc
			sim.hooks = tc
		AI:
			sim.cpu = MwRinkAI.new()
		_:
			sim.cpu = replay
	sim.run(rec.elapsed(k))
	return [sim, replay, tc]


## One pass: the differences (addresses) between our segment and the original's.
static func check_pass(rom: PackedByteArray, rec: MwSimRecording, k: int, mode := REPLAY) -> PackedInt32Array:
	var run := _run_pass(rom, rec, k, mode)
	var sim: MwRinkSim = run[0]
	if sim == null or sim.puck == null or sim.players == null:
		return PackedInt32Array([MwRinkRam.BASE])          # the simulation did not compile
	return MwRinkRam.diff(MwRinkRam.encode(sim.s, rec.start(k)), rec.end(k))


static func rom_or_load() -> PackedByteArray:
	return MwRom.data()


## One pass in detail: differences, the original's RNG calls (caller address,
## state before) and ours, the skating calls and the entry notes.
func _detail(rom: PackedByteArray, names: Array[String], k: int, mode: int) -> void:
	var rec := MwSimRecording.open(names[0] if not names.is_empty() else RUNS[0])
	var start := rec.start(k)
	var s := MwRinkRam.decode(rom, start)
	var sim := MwRinkSim.new(rom, s)
	var replay := MwReplayControl.new(rom, rec, k)
	sim.cpu = MwRinkAI.new() if mode == AI else replay
	sim.hooks = replay
	sim.log_rng = true
	sim.run(rec.elapsed(k))
	var d := MwRinkRam.diff(MwRinkRam.encode(s, start), rec.end(k))
	print("pass %d e %d phase %d: %d bytes differ" % [k, rec.elapsed(k), MwRinkRam.u16(start, MwRinkRam.PHASE), d.size()])
	print("  " + _explain(rom, rec, k, d, mode))
	print("original rng_next (caller, state before):")
	for e in rec.log_entries("rn", k):
		print("  $%06X  %08X" % [int(e[0]) & 0xFFFFFF, int(e[1])])
	print("original rng_range (caller, lo, hi, state):")
	for e in rec.log_entries("rr", k):
		print("  $%06X  %d %d  %08X" % [int(e[0]) & 0xFFFFFF, MwRinkSim.s16(int(e[1])), MwRinkSim.s16(int(e[2])), int(e[3])])
	print("ours:")
	for e in sim.rng_log:
		print("  %08X  %s" % [int(e[0]), e[1]])
	print("original skate calls (caller, a5, d0):")
	for e in rec.log_entries("sk", k):
		print("  $%06X  $%06X  %d" % [int(e[0]) & 0xFFFFFF, int(e[1]) & 0xFFFFFF, int(e[2]) & 0xFFFF])
	print("original thinks: ", rec.passes[k]["ai"])
	var s0 := MwRinkRam.decode(rom, start)
	var s1 := MwRinkRam.decode(rom, rec.end(k))
	for pp in [["start", s0.puck], ["want", s1.puck], ["ours", s.puck]]:
		var q: MwRinkState.Puck = pp[1]
		print("  puck %s: flags %02X carrier %s pos %s vel %s anim $%X" % [pp[0], q.flags, MwRinkRam.word_of(s, q.carrier) if pp[0] == "ours" else "-", q.motion.pixels(), q.motion.vel, q.anim.address])
	for t in 2:
		for i in 6:
			var a := s0.teams[t].players[i]
			var b := s1.teams[t].players[i]
			var o := s.teams[t].players[i]
			if not a.present:
				continue
			if a.state != 0 or b.state != 0 or o.state != 0 or b.anim_id != o.anim_id:
				print("  T%d P%d state %d/%d anim %d pos %X -> want %d/%d anim %d pos %X, ours %d/%d anim %d pos %X%s" % [t, i,
						a.state, a.substate, a.anim_id, a.anim.position, b.state, b.substate, b.anim_id, b.anim.position,
						o.state, o.substate, o.anim_id, o.anim.position, "  (carrier)" if s0.puck.carrier == a else ""])
	print("penalties: ", rec.log_entries("pen", k), " events: ", sim.events)


static func _field_key(desc: String) -> String:
	# "T0 P3 +$70 state" -> "P +$70 state"; "T1 +$4A0" -> "T +$4A0"
	var parts := desc.split(" ")
	if parts.size() >= 3 and parts[0].begins_with("T") and parts[1].begins_with("P"):
		return "P " + " ".join(parts.slice(2))
	if parts.size() >= 2 and parts[0].begins_with("T"):
		return "T " + parts[1]
	if parts[0] == "object" or parts[0] == "hazard" or parts[0] == "plate":
		return parts[0] + " " + " ".join(parts.slice(2))
	return desc


static func _explain(rom: PackedByteArray, rec: MwSimRecording, k: int, d: PackedInt32Array, mode := REPLAY) -> String:
	var start := rec.start(k)
	var run := _run_pass(rom, rec, k, mode)
	var sim: MwRinkSim = run[0]
	var replay: MwReplayControl = run[1]
	var got := MwRinkRam.encode(sim.s, start)
	var want := rec.end(k)
	var out := []
	var seen := {}
	for addr in d:
		var desc := MwRinkRam.describe(addr)
		if seen.has(desc):
			continue
		seen[desc] = true
		out.append("%s ours %02X want %02X (was %02X)" % [desc, MwRinkRam.u8(got, addr), MwRinkRam.u8(want, addr), MwRinkRam.u8(start, addr)])
		if out.size() >= 8:
			out.append("... %d bytes" % d.size())
			break
	if not replay.notes.is_empty():
		out.append("| " + " | ".join(replay.notes))
	return "; ".join(out)
