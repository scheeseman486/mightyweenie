extends SceneTree
## The rink pass between two simulation segments (MwRinkUpdate) against
## every pair of consecutive passes of the simulation recordings (`mw_harness
## sim-record` -> out/sim/NAME/; docs/compare.md, Simulation recordings).
## Run with `tools/bin/pass-check [NAME ...] [--show N] [--from I] [--count
## N] [--only TEXT]` or `--detail PASS`; `--fresh [--visit [--bisect]]`
## audits the live game's new matches ([member fresh_match]).
##
## For each pair (k, k+1) of passes in the same rink visit: the RAM at the
## end of pass k's segment (`$F9C8`) is decoded, MwRinkUpdate runs the rest
## of pass k with its elapsed ticks (after_segment), MwRinkPhases the puck
## rules and the phase handler (pass_end), the draws, then the start of
## pass k+1 with its own elapsed ticks (pass_start; the pads as recorded),
## and the result is compared byte for byte with the RAM at pass k+1's
## segment start (`$F98A`). Nothing is masked; what comes from outside the
## CPU is taken from the recording:
##
## * the tick at every live read (the VBlank interrupt moves it while the
##   pass runs): from the recording's tick log (recorder v3, by site
##   address); on the old recordings, without a log, every possible tick
##   (not decreasing, between the segment's end and the next pass's start;
##   the clock's from the pass start) is tried and the pair counts as
##   identical if one fits;
## * the sound driver's answers about the coach's voice (`$13D9C`: still
##   playing?) from the "vc" log (v3), else derived from the RAM (a new voice
##   handle, or the 480-tick pause set); a new voice's handle from the RAM;
## * the pause menu's answer (the recorder's "pauses").
##
## Pairs across a rink exit are the entries: the phase handler leaves for a
## screen, the screens in between are not run (their known effects are
## noted), then the entry (MwRinkPhases.enter) and the first pass's start.
##
## `--draws` (with `--visit`, recorder v4 runs): per pass, what the original
## draws outside the segment against ours, in order - the phase share's
## window plane writes and sprite pieces, the next pass start's clock texts
## ([method _draw_pass]).

const RUNS := ["cpu_s0", "p1_s9", "p1p2_s4", "cpu_s10", "p1_s8", "p1p2_s17", "coop_s14", "p1_s2",
		"cpu_s16", "p1_s5", "p4_s22"]
const RUNS3 := ["match_p1_s6", "match_cpu_s13", "playoff_p1_s19", "pause_p1_s7", "goalie_p1_s12", "attract"]
const MAX_TRIES := 160
const VOICE_POLL := 0xB5CA           ## `$B572`'s "still playing?" poll (return address in the "vc" log)


## What the pair's run reads from outside the CPU: the tick at each live
## read (from the recording's tick log when it has the site, else the
## pair's base tick plus [member pre] / [member clk]), the voice polls'
## answers, a new voice's handle, the pause menu's answer.
class TickPlan extends RefCounted:
	var t_end := 0                   ## the segment's end tick (end(k) `$FFCA56`)
	var t_pass := 0                  ## the next pass's start tick (start(k+1) `$C5FE`)
	var t_start := 0                 ## start(k+1) `$FFCA56`
	## Offsets of the reads before the pass start (from t_end) and of the
	## clock's (from t_pass), in order; a read beyond them takes the last.
	var pre: Array = []
	var clk: Array = []
	var reads: Array[int] = []       ## the tags read this run
	var values: Array = []           ## [tag, tick] per read this run
	var logged := {}                 ## tag -> [ticks] (recorder v3)
	var vc: Array = []               ## the driver's answers to the voice polls (v3), in order
	var vc_logged := false
	var voice_guess := 1             ## no log: the answer derived from the RAM
	var handle := 0                  ## a new voice's handle (the RAM after)
	var pause := 0                   ## the pause menu's answer (1 Start, 2 A, 3 B)
	## No tick log, at an exit: the phase handler's reads this many ticks
	## after the segment's end (its tick is not known).
	var exit_dt := 0
	var voices: Array = []           ## the answers given this run
	var _logged_at := {}
	var _n_pre := 0
	var _n_clk := 0
	var _vc_at := 0

	func reset() -> void:
		reads.clear()
		values.clear()
		voices.clear()
		_logged_at.clear()
		_n_pre = 0
		_n_clk = 0
		_vc_at = 0

	func tick_at(up: MwRinkUpdate, tag: int) -> void:
		reads.append(tag)
		_pick(up, tag)
		values.append([tag, up.s.tick])

	func voice_poll(_ph: MwRinkPhases, _handle: int) -> int:
		var v := voice_guess
		if vc_logged:
			v = int(vc[_vc_at]) if _vc_at < vc.size() else 0
			_vc_at += 1
		voices.append(v)
		return v

	func voice_handle(_ph: MwRinkPhases, _id: int) -> int:
		return handle

	func pause_result(_ph: MwRinkPhases) -> int:
		return pause

	func _pick(up: MwRinkUpdate, tag: int) -> void:
		if logged.has(tag):
			var at := int(_logged_at.get(tag, 0))
			var l: Array = logged[tag]
			if at < l.size():
				up.s.tick = int(l[at])
				_logged_at[tag] = at + 1
				return
		if exit_dt > 0 and MwRinkPhases.TICK_ADDRESSES.values().has(tag):
			up.s.tick = t_end + exit_dt
		elif tag == MwRinkUpdate.TICK_CLOCK:
			up.s.tick = t_pass + _offset(clk, _n_clk)
			_n_clk += 1
		else:
			up.s.tick = t_end + _offset(pre, _n_pre)
			_n_pre += 1

	static func _offset(l: Array, i: int) -> int:
		if l.is_empty():
			return 0
		return int(l[mini(i, l.size() - 1)])


var only := ""
## The replay ring's data (`$FF0000`, not in the recordings) as our passes
## wrote it, carried from pair to pair: dropping the oldest frame when the
## ring is full reads its header there.
var ring := PackedByteArray()
var _up: MwRinkUpdate = null
## The 16-byte rows where entries differ outside the modelled state.
var unmodelled := {}
## `--entry-rng`: print our draws in the entries checked (state, caller).
var debug_rng := false
## `--fresh` (the live game's new matches): the matchup entries also run on
## the state the live game makes for a new match (MwRink: a new
## MwRinkState with the session's RNG, playoffs and ref icons) instead of
## the one decoded from the RAM; what differs only then is state the
## original set before (at power-on, in earlier matches or screens) that the
## live game never sets up. With `--visit` the new match's first rink
## visit is played on from both; `--bisect` then finds which of those
## fields the play reads ([method _fresh_visits]).
var fresh_match := false
var bisect := false
## [method check_entry] makes the fresh state (set by the `--fresh` runs).
var _fresh_now := false
## Set before [code]new()[/code] to use the script as a library (screen-check
## carries the replay ring with [method check_pair] / [method check_entry]):
## nothing runs at creation.
static var library := false


func _init() -> void:
	if library:
		return
	var args := OS.get_cmdline_user_args()
	var names: Array[String] = []
	var show := 3
	var from := 0
	var count := 1 << 30
	var detail := -1
	var chain_at := -1
	var fixture := false
	var visit := false
	var phase_fixture := false
	var draw_fixture := false
	var i := 0
	while i < args.size():
		match args[i]:
			"--show":
				i += 1
				show = int(args[i])
			"--from":
				i += 1
				from = int(args[i])
			"--count":
				i += 1
				count = int(args[i])
			"--only":
				i += 1
				only = args[i]
			"--detail":
				i += 1
				detail = int(args[i])
			"--chain":
				i += 1
				chain_at = int(args[i])
			"--entry-rng":
				debug_rng = true
			"--fixture":
				fixture = true
			"--visit":
				visit = true
			"--phase-fixture":
				phase_fixture = true
			"--draws":
				draws_check = true
				visit = true
			"--draw-fixture":
				draw_fixture = true
			"--fresh":
				fresh_match = true
			"--bisect":
				bisect = true
			_:
				names.append(args[i])
		i += 1
	if names.is_empty():
		names.assign(RUNS)
	var rom := MwRom.data()
	if fixture:
		_build_fixture(rom, names)
		quit(0)
		return
	if phase_fixture:
		_build_phase_fixture(rom, names)
		quit(0)
		return
	if draw_fixture:
		_build_draw_fixture(rom, names)
		quit(0)
		return
	var failed := false
	for name in names:
		var rec := MwSimRecording.open(name)
		if rec == null:
			print("%s: no recording (tools/bin/py -m mw_harness sim-record %s)" % [name, name])
			failed = true
			continue
		if detail >= 0:
			_detail(rom, rec, detail)
			continue
		if chain_at >= 0:
			# the random draws after pass k's segment, in order (state, call site)
			for e in _chain(rec, chain_at, MwRinkRam.u32(rec.end(chain_at), MwRinkRam.RNG)):
				print("  %08X  $%05X%s" % [int(e[0]), int(e[1]), "  (entry)" if int(e[1]) in ENTRY_RNG_SITES else ""])
			continue
		if visit and not fresh_match:
			failed = _visits(rom, rec, from, count, show) or failed
			continue
		if fresh_match and visit:
			failed = _fresh_visits(rom, rec) or failed
			continue
		if fresh_match:
			failed = _fresh_audit(rom, rec, show) or failed
			continue
		failed = _run(rom, rec, from, count, show) or failed
	quit(1 if failed else 0)


func _run(rom: PackedByteArray, rec: MwSimRecording, from: int, count: int, show: int) -> bool:
	var n := 0
	var same := 0
	var same_other := 0
	var shown := 0
	var by_field := {}
	var tick_logs := _tick_logs(rec)
	var en := 0
	var en_same := 0
	var en_fields := {}
	var en_notes := {}
	var en_shown := 0
	ring = rec.ring_start()
	for k in range(from, mini(rec.count() - 1, from + count)):
		var p: Dictionary = rec.passes[k]
		var q: Dictionary = rec.passes[k + 1]
		if int(p["visit"]) != int(q["visit"]) or int(p["screen"]) != int(q["screen"]):
			en += 1
			var e := check_entry(rom, rec, k, tick_logs)
			var ed: PackedInt32Array = e[0]
			for note in e[1]:
				en_notes[note] = int(en_notes.get(note, 0)) + 1
			if ed.is_empty():
				en_same += 1
				continue
			var here := {}
			for addr in ed:
				here[_field_key(MwRinkRam.describe(addr))] = true
			for f in here:
				en_fields[f] = int(en_fields.get(f, 0)) + 1
			if en_shown < show:
				en_shown += 1
				var got: PackedByteArray = e[2]
				var out := []
				for addr in ed.slice(0, 10):
					out.append("%s ours %02X want %02X (was %02X)" % [MwRinkRam.describe(addr), MwRinkRam.u8(got, addr),
							MwRinkRam.u8(rec.start(k + 1), addr), MwRinkRam.u8(rec.end(k), addr)])
				print("  %s entry %d -> %d %s: %s%s" % [rec.name, k, k + 1, e[3], "; ".join(out),
						(" ... %d bytes" % ed.size()) if ed.size() > 10 else ""])
			continue
		n += 1
		var r := check_pair(rom, rec, k, tick_logs)
		var d: PackedInt32Array = r[0]
		if d.is_empty():
			if r[1]:
				same_other += 1
			else:
				same += 1
			continue
		var names_here := {}
		var match_only := only == ""
		for addr in d:
			var desc := MwRinkRam.describe(addr)
			names_here[_field_key(desc)] = true
			match_only = match_only or desc.contains(only)
		for f in names_here:
			by_field[f] = int(by_field.get(f, 0)) + 1
		if shown < show and match_only:
			shown += 1
			print("  %s pass %d -> %d (e %d/%d, phase %d -> %d): %s" % [rec.name, k, k + 1, rec.elapsed(k), rec.elapsed(k + 1),
					MwRinkRam.u16(rec.end(k), MwRinkRam.PHASE), MwRinkRam.u16(rec.start(k + 1), MwRinkRam.PHASE),
					_explain(rom, rec, k, d, tick_logs)])
	var worst := by_field.keys()
	worst.sort_custom(func(x: String, y: String) -> bool: return by_field[x] > by_field[y])
	var top := []
	for f in worst.slice(0, 10):
		top.append("%s %d" % [f, by_field[f]])
	print("%s: %d/%d pairs identical (%d with the base ticks, %d with other VBlank ticks), %d differ%s" % [rec.name,
			same + same_other, n, same, same_other, n - same - same_other,
			("  (" + ", ".join(top) + ")") if not top.is_empty() else ""])
	var etop := []
	for f in en_fields:
		etop.append("%s %d" % [f, en_fields[f]])
	var ent := []
	for note in en_notes:
		ent.append("%s %d" % [note, en_notes[note]])
	var rows := unmodelled.keys()
	rows.sort()
	unmodelled.clear()
	print("%s: %d/%d entries identical%s%s%s" % [rec.name, en_same, en, ("  (" + ", ".join(etop) + ")") if not etop.is_empty() else "",
			("  [" + ", ".join(ent) + "]") if not ent.is_empty() else "",
			("  unmodelled rows: " + " ".join(rows)) if not rows.is_empty() else ""])
	return same + same_other < n or en_same < en


## The recording's tick reads between segments by our tags (recorder v3:
## sites by address in meta "tick_sites"): {pass: {tag: [ticks]}}, or {}.
static func _tick_logs(rec: MwSimRecording) -> Dictionary:
	var sites: Dictionary = rec.meta.get("tick_sites", {})
	var tags := {}
	for a in sites:
		var addr := ("%s" % a).hex_to_int()
		if MwRinkUpdate.TICK_ADDRESSES.has(addr):
			tags[int(sites[a])] = MwRinkUpdate.TICK_ADDRESSES[addr]
		elif MwRinkPhases.TICK_ADDRESSES.has(addr):
			tags[int(sites[a])] = MwRinkPhases.TICK_ADDRESSES[addr]
	if tags.is_empty():
		return {}
	var out := {}
	var d: Dictionary = rec.meta["log_data"].get("tk", {})
	for key in d:
		var per := {}
		for e in d[key][1]:
			var t := int(tags.get(int(e[0]), -1))
			if t >= 0:
				if not per.has(t):
					per[t] = []
				per[t].append(int(e[1]))
		if not per.is_empty():
			out[int(key)] = per
	return out


## The plan of pair (k, k+1): base ticks, the tick log, the voice polls'
## answers, the pause menu's answer.
static func make_plan(rec: MwSimRecording, k: int, tick_logs: Dictionary) -> TickPlan:
	var plan := TickPlan.new()
	var a := rec.end(k)
	var b := rec.start(k + 1)
	plan.t_end = MwRinkRam.u32(a, MwRinkRam.TICK)
	plan.t_pass = MwRinkRam.u32(b, MwRinkRam.PASS_TICK)
	plan.t_start = MwRinkRam.u32(b, MwRinkRam.TICK)
	plan.logged = tick_logs.get(k, {})
	plan.vc_logged = (rec.meta["log_data"] as Dictionary).has("vc")
	for e in rec.log_entries("vc", k, true):
		if int(e[0]) & 0xFFFFFF == VOICE_POLL:
			plan.vc.append(1 if int(e[1]) != 0 else 0)
	var pt := MwRinkRam.PORTRAIT
	plan.handle = MwRinkRam.u32(b, pt + 0x18)
	plan.voice_guess = 1
	if MwRinkRam.u16(b, pt + 0x12) == 0 and MwRinkRam.u16(b, pt + 0x14) == 0xFE20:
		plan.voice_guess = 0                     # the pause after two voices was set
	elif plan.handle != 0 and plan.handle != MwRinkRam.u32(a, pt + 0x18):
		plan.voice_guess = 0                     # a new voice started
	for pz in rec.meta.get("pauses", []):
		if int(pz[0]) == k + 1:
			plan.pause = int(pz[3])
	return plan


## Pair (k, k+1): [differences, whether other ticks than the base ones were
## needed, (unused), our RAM, the tick plan of the run returned].
func check_pair(rom: PackedByteArray, rec: MwSimRecording, k: int, tick_logs: Dictionary, from := PackedByteArray()) -> Array:
	var plan := make_plan(rec, k, tick_logs)
	var b := rec.start(k + 1)
	var start_ring := ring
	var run := run_pair(rom, rec, k, plan, from)
	var d := MwRinkRam.diff(run[0], b)
	var best_ring: PackedByteArray = run[2]
	ring = best_ring
	if d.is_empty() or plan.reads.is_empty() or not plan.logged.is_empty():
		return [d, false, [], run[0], plan]
	# other ticks: every non-decreasing choice of the reads before the pass
	# start within [t_end, t_pass], the clock's within [t_pass, t_start]
	var n_pre := 0
	var n_clk := 0
	for t in plan.reads:
		if t == MwRinkUpdate.TICK_CLOCK:
			n_clk += 1
		else:
			n_pre += 1
	var tries := 0
	for pre in _monotonic(n_pre, maxi(plan.t_pass - plan.t_end, 0)):
		for clk in _monotonic(n_clk, maxi(plan.t_start - plan.t_pass, 0)):
			if (pre + clk + [0]).max() == 0:
				continue
			tries += 1
			if tries > MAX_TRIES:
				return [d, false, [], run[0], plan]
			plan.pre = pre
			plan.clk = clk
			ring = start_ring
			var r2 := run_pair(rom, rec, k, plan, from)
			var d2 := MwRinkRam.diff(r2[0], b)
			if d2.is_empty():
				ring = r2[2]
				return [d2, true, [], r2[0], plan]
	ring = best_ring
	return [d, false, [], run[0], plan]


## Non-decreasing sequences of [param n] values in 0..[param top].
static func _monotonic(n: int, top: int) -> Array:
	var out := [[]]
	for i in n:
		var next := []
		for s in out:
			var lo: int = s[s.size() - 1] if not (s as Array).is_empty() else 0
			for v in range(lo, top + 1):
				next.append(s + [v])
		out = next
	return out


var _ph: MwRinkPhases = null


## The update and the phases on one simulation for the whole run (the
## state decoded into it: its parts point at each other, new ones per pair
## would never be freed).
func _parts(rom: PackedByteArray) -> Array:
	if _up == null:
		_up = MwRinkUpdate.new(MwRinkSim.new(rom, MwRinkState.new()))
		_ph = MwRinkPhases.new(_up)
	return [_up, _ph]


## Run the gap of pair (k, k+1) with [param plan] (the replay ring's data
## from [member ring]): [our RAM, (unused), the ring's data after, the exit
## screen the phase handler chose (-1 none)].
func run_pair(rom: PackedByteArray, rec: MwSimRecording, k: int, plan: TickPlan, from := PackedByteArray()) -> Array:
	var a := rec.end(k) if from.is_empty() else from
	var b := rec.start(k + 1)
	plan.reset()
	var parts := _parts(rom)
	var up: MwRinkUpdate = parts[0]
	var ph: MwRinkPhases = parts[1]
	var sim := up.sim
	var s := sim.s
	MwRinkRam.decode_into(rom, s, a)
	s.net_slack = 1 if int(rec.passes[k]["screen"]) == 6 else -1
	s.replay.ring_bytes = ring.duplicate() if ring.size() == MwRinkState.ReplayRing.SIZE \
			else MwRinkState.ReplayRing.new().ring_bytes     # (packed arrays are shared by reference)
	sim.log_rng = true
	sim.rng_log.clear()
	sim.events.clear()
	sim.hooks = null
	up.hooks = plan
	ph.hooks = plan
	up.after_segment(rec.elapsed(k))
	var to := ph.pass_end(rec.elapsed(k))
	if to < 0:
		up.draws([], MwRinkPhases.RULES_DRAWN, ph.overlays, ph.sprite_ops)
	s.tick = MwRinkRam.u32(b, MwRinkRam.PASS_TICK)
	up.pass_start(rec.elapsed(k + 1))
	for pad in 4:
		s.pads_held[pad] = MwRinkRam.u8(b, MwRinkRam.PADS + 2 * pad)
		s.pads_new[pad] = MwRinkRam.u8(b, MwRinkRam.PADS + 2 * pad + 1)
	var got := MwRinkRam.encode(s, a)
	return [got, [], s.replay.ring_bytes, to]


static func _field_key(desc: String) -> String:
	var parts := desc.split(" ")
	if parts.size() >= 3 and parts[0].begins_with("T") and parts[1].begins_with("P"):
		return "P " + " ".join(parts.slice(2))
	if parts.size() >= 2 and parts[0].begins_with("T"):
		return "T " + parts[1]
	if parts[0] == "object" or parts[0] == "hazard" or parts[0] == "plate":
		return parts[0] + " " + " ".join(parts.slice(2))
	return desc


func _explain(rom: PackedByteArray, rec: MwSimRecording, k: int, d: PackedInt32Array, tick_logs: Dictionary) -> String:
	var plan := make_plan(rec, k, tick_logs)
	var a := rec.end(k)
	var b := rec.start(k + 1)
	var got: PackedByteArray = run_pair(rom, rec, k, plan)[0]
	var out := []
	var seen := {}
	for addr in d:
		var desc := MwRinkRam.describe(addr)
		if only != "" and not desc.contains(only):
			continue
		if seen.has(desc):
			continue
		seen[desc] = true
		out.append("%s ours %02X want %02X (was %02X)" % [desc, MwRinkRam.u8(got, addr), MwRinkRam.u8(b, addr), MwRinkRam.u8(a, addr)])
		if out.size() >= 8:
			out.append("... %d bytes" % d.size())
			break
	return "; ".join(out)


func _detail(rom: PackedByteArray, rec: MwSimRecording, k: int) -> void:
	var a := rec.end(k)
	var b := rec.start(k + 1)
	var logs := _tick_logs(rec)
	ring = rec.ring_start()
	var r := check_pair(rom, rec, k, logs)
	var d: PackedInt32Array = r[0]
	var plan: TickPlan = r[4]
	print("pair %d -> %d: e %d/%d, phase %d/%d -> %d/%d, ticks end %d pass %d start %d; %d bytes differ" % [k, k + 1,
			rec.elapsed(k), rec.elapsed(k + 1), MwRinkRam.u16(a, MwRinkRam.PHASE), MwRinkRam.u16(a, MwRinkRam.SUBPHASE),
			MwRinkRam.u16(b, MwRinkRam.PHASE), MwRinkRam.u16(b, MwRinkRam.SUBPHASE), plan.t_end, plan.t_pass, plan.t_start, d.size()])
	var got: PackedByteArray = r[3]
	for addr in d.slice(0, 60):
		print("  $%06X %s: ours %02X want %02X (was %02X)" % [addr, MwRinkRam.describe(addr), MwRinkRam.u8(got, addr), MwRinkRam.u8(b, addr), MwRinkRam.u8(a, addr)])
	print("original rng_next after the segment (caller, state before):")
	for e in rec.log_entries("rn", k, true):
		print("  $%06X  %08X" % [int(e[0]) & 0xFFFFFF, int(e[1])])
	print("original rng_range after the segment (caller, lo, hi, state):")
	for e in rec.log_entries("rr", k, true):
		print("  $%06X  %d %d  %08X" % [int(e[0]) & 0xFFFFFF, MwRinkSim.s16(int(e[1])), MwRinkSim.s16(int(e[2])), int(e[3])])
	print("ours: ", _up.sim.rng_log)
	print("phase handler log: ", rec.log_entries("ph", k, true), " sounds: ", rec.log_entries("sd", k, true))
	print("ticks read: ", plan.values, " other ticks: ", r[1], " logged: ", plan.logged)
	print("voice answers: ", plan.voices, " recorded: ", plan.vc, " pause: ", plan.pause, " events: ", _up.sim.events)


## The screen the phase handler leaves for after pass [param k] (from
## [param from], default the recorded segment end); without a tick log the
## handler's tick is not known (0-4 ticks after the segment): later ticks
## are tried until the exit is [param want].
func exit_of(rom: PackedByteArray, rec: MwSimRecording, k: int, plan: TickPlan, want: int, from := PackedByteArray()) -> int:
	var start_ring := ring
	var r := run_pair(rom, rec, k, plan, from)
	var to := int(r[3])
	if to != want and plan.logged.is_empty():
		for dt in range(1, 5):
			plan.exit_dt = dt
			ring = start_ring
			r = run_pair(rom, rec, k, plan, from)
			if int(r[3]) == want:
				to = want
				break
	ring = r[2]
	return to


## The recording's last pass (no next start): the screen its phase
## handler leaves for, from our segment end [param seg].
func _last_exit(rom: PackedByteArray, rec: MwSimRecording, k: int, logs: Dictionary, seg: PackedByteArray) -> int:
	var plan := TickPlan.new()
	plan.t_end = MwRinkRam.u32(seg, MwRinkRam.TICK)
	plan.t_pass = plan.t_end
	plan.t_start = plan.t_end
	plan.logged = logs.get(k, {})
	for pz in rec.meta.get("pauses", []):        # a pause menu in the last pass
		if int(pz[0]) == k + 1:
			plan.pause = int(pz[3])
	var parts := _parts(rom)
	var up: MwRinkUpdate = parts[0]
	var ph: MwRinkPhases = parts[1]
	MwRinkRam.decode_into(rom, up.s, seg)
	up.sim.hooks = null
	up.hooks = plan
	ph.hooks = plan
	up.after_segment(rec.elapsed(k))
	return ph.pass_end(rec.elapsed(k))


# --- the visit check ---------------------------------------------------------------------------

## `--visit`: every rink visit of the recording run from its first pass's
## segment start with only the recorded pads (the start of each pass) and
## elapsed ticks (and, from the recording, the ticks the original read, the
## sound driver's voice answers and the pause menu's answer): our AI,
## segment, update and phases throughout. Each pass's segment end and the
## next pass's segment start are compared with the original's.
func _visits(rom: PackedByteArray, rec: MwSimRecording, from: int, count: int, show: int) -> bool:
	var logs := _tick_logs(rec)
	ring = rec.ring_start()
	var parts := _parts(rom)
	var up: MwRinkUpdate = parts[0]
	var sim := up.sim
	var ai := MwRinkAI.new()
	var k := 0
	var visits := 0
	var whole := 0
	var seg_total := 0
	var seg_same := 0
	var gap_total := 0
	var gap_same := 0
	var failed := false
	var lines: Array[String] = []
	while k < rec.count():
		var k0 := k
		var k1 := k0
		while k1 + 1 < rec.count() and int(rec.passes[k1 + 1]["visit"]) == int(rec.passes[k0]["visit"]) \
				and int(rec.passes[k1 + 1]["screen"]) == int(rec.passes[k0]["screen"]):
			k1 += 1
		k = k1 + 1
		if k1 < from or k0 >= from + count:
			continue
		visits += 1
		var img := rec.start(k0)
		var segs := 0
		var gaps := 0
		var first := ""
		var exit_note := ""
		for j in range(k0, k1 + 1):
			var s := sim.s
			MwRinkRam.decode_into(rom, s, img)
			s.tick = MwRinkRam.u32(rec.start(j), MwRinkRam.TICK)
			sim.cpu = ai
			sim.hooks = MwReplayControl.new(rom, rec, j)
			sim.log_rng = false
			sim.run(rec.elapsed(j))
			var seg := MwRinkRam.encode(s, rec.end(j))
			var d := MwRinkRam.diff(seg, rec.end(j))
			seg_total += 1
			if d.is_empty():
				segs += 1
			elif first == "":
				first = "pass %d segment: %s" % [j, _describe_diff(seg, rec.end(j), rec.start(j), d)]
			if j == k1:
				# the visit's last pass: the phase handler leaves (unless the recording ended)
				var want := -1
				for e in rec.meta["screens"]:
					if int(e[0]) == j + 1:
						want = int(e[1])
						break
				if want < 0:
					break
				var to := -1
				if j + 1 >= rec.count():
					to = _last_exit(rom, rec, j, logs, seg)
				else:
					to = exit_of(rom, rec, j, make_plan(rec, j, logs), want, seg)
				if to != want:
					exit_note = "exit %d, the original's %d" % [to, want]
				if draws_check:
					_draw_pass(rom, rec, j, true)
				break
			var c := check_pair(rom, rec, j, logs, seg)
			if draws_check:
				_draw_pass(rom, rec, j, false)
			var dg: PackedInt32Array = c[0]
			gap_total += 1
			if dg.is_empty():
				gaps += 1
			elif first == "":
				first = "pass %d -> %d gap: %s" % [j, j + 1, _describe_diff(c[3], rec.start(j + 1), seg, dg)]
			img = c[3]
		seg_same += segs
		gap_same += gaps
		var n := k1 - k0 + 1
		var ok := segs == n and gaps == n - 1 and exit_note == ""
		if ok:
			whole += 1
		else:
			failed = true
		lines.append("  visit %d (screen %d, passes %d-%d): %d/%d segments, %d/%d gaps identical%s%s" % [
				int(rec.passes[k0]["visit"]), int(rec.passes[k0]["screen"]), k0, k1, segs, n, gaps, n - 1,
				("; " + exit_note) if exit_note != "" else "", ("; first: " + first) if first != "" else ""])
	for l in lines.slice(0, maxi(show, 0) if show < lines.size() else lines.size()):
		print(l)
	print("%s: %d/%d visits identical throughout; passes: %d/%d segments, %d/%d gaps identical" % [rec.name, whole, visits,
			seg_same, seg_total, gap_same, gap_total])
	if draws_check:
		failed = _draw_report(rec) or failed
	return failed


func _describe_diff(got: PackedByteArray, want: PackedByteArray, was: PackedByteArray, d: PackedInt32Array) -> String:
	var out := []
	var seen := {}
	for addr in d:
		var desc := MwRinkRam.describe(addr)
		if seen.has(desc):
			continue
		seen[desc] = true
		out.append("%s ours %02X want %02X (was %02X)" % [desc, MwRinkRam.u8(got, addr), MwRinkRam.u8(want, addr), MwRinkRam.u8(was, addr)])
		if out.size() >= 6:
			out.append("... %d bytes" % d.size())
			break
	return "; ".join(out)


# --- the draws outside the segment (recorder v4) -------------------------------------------------

const WINDOW_PLANE := 0xFFFFB0CA      ## the window's plane object `$FFB0CA` (as the code holds it)
const WINDOW_VRAM := 0xF000           ## its name table: 64 x 32 cells
const WIDGET_MAPS := [0x25D0, 0x25FC] ## `$25AA`'s map copies (the widget's frame, power-play or normal: part of "widget")
const RAM_TEXT := 8                   ## bytes of a RAM string the recorder logs

var draws_check := false
## [identical passes, passes, entries compared] by part: "win" (the phase
## share's window writes), "spr" (its sprite pieces), "clock" (the next
## pass start's clock texts).
var _dt := {}
var _dt_first: Array[String] = []
var _dt_other := 0


## Pass [param k]'s draws outside the segment against the recording's
## "win" / "spr" logs (recorder v4), in order: the phase share's (`$A5EC`,
## `$C84A`, `$FC58` up to its return or the rink exit) window plane writes
## ([member MwRinkPhases.window_ops]) and sprite pieces (the draw pass's
## [member MwRinkDraw.head]: the ref icons, the handler's overlays and
## sprites as placed); unless the rink is left ([param left]), the next
## pass start's clock texts ([member MwRinkUpdate.window_ops]).
func _draw_pass(rom: PackedByteArray, rec: MwSimRecording, k: int, left: bool) -> void:
	var win := share_parts(rec.log_entries("win", k, true))
	var spr := share_parts(rec.log_entries("spr", k, true))
	var snap := rec.end(k)
	var other: Array[String] = []
	_draw_tally("win", k, window_list(rom, _ph.window_ops), recorded_window(rom, win[1], snap, other))
	var want: Array[String] = []
	for e in spr[1]:
		if int(e[0]) == 2:
			want.append(piece_text(int(e[2]), int(e[3]), int(e[4]), int(e[5]), int(e[6])))
	var pieces: Array = _up.drawer.head
	if left:
		pieces = _up.drawer.head_pieces(_up.s, MwRinkPhases.RULES_DRAWN, _ph.overlays, _ph.sprite_ops)
	var got: Array[String] = []
	for a in pieces:
		got.append(piece_text(int(a[0]), int(a[1]), int(a[2]), int(a[3]), int(a[4])))
	_draw_tally("spr", k, got, want)
	if not left:
		_draw_tally("clock", k, window_list(rom, _up.window_ops), recorded_window(rom, win[2], snap, other))
	# window writes in the segment itself or to other planes in the share: none expected
	recorded_window(rom, rec.log_entries("win", k), snap, other)
	_dt_other += other.size()
	if not other.is_empty() and _dt_first.size() < 12:
		_dt_first.append("pass %d: writes to other planes: %s" % [k, ", ".join(other.slice(0, 3))])


func _draw_tally(part: String, k: int, got: Array[String], want: Array[String]) -> void:
	if not _dt.has(part):
		_dt[part] = [0, 0, 0]
	var t: Array = _dt[part]
	t[1] += 1
	t[2] += want.size()
	if got == want:
		t[0] += 1
		return
	if _dt_first.size() >= 12:
		return
	var i := 0
	while i < mini(got.size(), want.size()) and got[i] == want[i]:
		i += 1
	_dt_first.append("pass %d %s #%d: ours [%s] / original [%s]" % [k, part, i, "; ".join(got.slice(i, i + 3)),
			"; ".join(want.slice(i, i + 3))])


func _draw_report(rec: MwSimRecording) -> bool:
	if _dt.is_empty():
		print("%s: draws: no v4 draw logs (mw_harness sim-record NAME_d)" % rec.name)
		return false
	var out := []
	var failed := false
	for part in ["win", "spr", "clock"]:
		var t: Array = _dt.get(part, [0, 0, 0])
		out.append("%s %d/%d passes identical (%d entries)" % [part, t[0], t[1], t[2]])
		failed = failed or t[0] != t[1]
	print("%s: draws: %s; other planes %d" % [rec.name, ", ".join(out), _dt_other])
	for l in _dt_first:
		print("  " + l)
	failed = failed or _dt_other != 0
	_dt.clear()
	_dt_first.clear()
	_dt_other = 0
	return failed


## A pass's "after" log entries split at the phase share's markers (kind 0
## start, kind 9 end): [before, the share, after].
static func share_parts(entries: Array) -> Array:
	var out := [[], [], []]
	var part := 0
	for e in entries:
		var kind := int(e[0])
		if kind == 0 and part == 0:
			part = 1
		elif kind == 9 and part == 1:
			part = 2
		else:
			out[part].append(e)
	return out


static func _w(v: int) -> int:
	return MwRinkSim.s16(v & 0xFFFF)


static func piece_text(x: int, y: int, depth: int, attr: int, piece: int) -> String:
	return "(%d,%d) d%04X a%02X %X" % [_w(x), _w(y), depth & 0xFFFF, attr & 0xFF, piece & 0xFFFFFF]


static func _ascii(b: PackedByteArray) -> String:
	var t := ""
	for c in b:
		t += char(c) if c >= 0x20 and c < 0x7F else "\\x%02X" % c
	return "'" + t + "'"


## A text's entry: from a ROM string (its address) or RAM (its first
## [constant RAM_TEXT] bytes, all the recorder keeps).
static func text_text(rom: PackedByteArray, font: int, x: int, y: int, attr: int, src: Variant) -> String:
	var where := ""
	var b := PackedByteArray()
	if src is int:
		where = "@%X " % int(src)
		b = MwGfx.rom_string(rom, int(src))
	else:
		b = src as PackedByteArray
		if b.has(0):
			b = b.slice(0, b.find(0))             # draw_text stops at the 0
		b = b.slice(0, RAM_TEXT)
	return "text %X (%d,%d) %02X %s%s" % [font, x, y, attr & 0xFF, where, _ascii(b)]


static func fill_text(x: int, y: int, w: int, h: int, word: int) -> String:
	return "fill (%d,%d) %dx%d %04X" % [x, y, w, h, word & 0xFFFF]


static func _time_bytes(seconds: int) -> PackedByteArray:
	return MwClockHud.time_text(seconds)


## Our window plane operations ([member MwRinkPhases.window_ops] or
## [member MwRinkUpdate.window_ops]) as entries comparable with [method
## recorded_window]'s: "text_after" placed, a widget with its two texts.
static func window_list(rom: PackedByteArray, ops: Array) -> Array[String]:
	var out: Array[String] = []
	var after := 0
	for op in ops:
		match str(op[0]):
			"text", "text_after":
				var at := 2 if op[0] == "text" else 1
				var font := int(op[1])
				var x := int(op[2]) if op[0] == "text" else after
				var src: Variant = op[at + 3]
				var b: PackedByteArray = MwGfx.rom_string(rom, int(src)) if src is int else src
				if b.has(0):
					b = b.slice(0, b.find(0))
				out.append(text_text(rom, font, x, int(op[at + 1]), int(op[at + 2]), src))
				after = x + MwGfx.text_width(rom, font, b)
			"glyph":
				out.append("glyph %X (%d,%d) %02X %s" % [int(op[1]), int(op[2]), int(op[3]), int(op[4]) & 0xFF,
						_ascii(PackedByteArray([int(op[5])]))])
			"fill":
				out.append(fill_text(int(op[1]), int(op[2]), int(op[3]), int(op[4]), int(op[5])))
			"box":
				out.append("box (%d,%d) %dx%d filled %d erase 0" % [int(op[1]), int(op[2]), int(op[3]), int(op[4]),
						1 if op[5] else 0])
			"quote":
				out.append("quote %X (%d,%d) %dx%d %02X %s" % [int(op[1]), int(op[2]), int(op[3]), int(op[6]), int(op[7]),
						int(op[4]) & 0xFF, _ascii(op[5])])
			"widget":
				# `$25AA`: the frame, [the power-play clock,] the period, ["[]",] the clock
				var pp: bool = op[1]
				out.append("widget pp %d" % (1 if pp else 0))
				if pp:
					out.append(text_text(rom, MwClockHud.FONT, MwClockHud.PP_CLOCK_AT.x, MwClockHud.PP_CLOCK_AT.y,
							MwClockHud.ATTR, _time_bytes(int(op[4]) if op.size() > 4 else 0)))
				out.append(text_text(rom, MwClockHud.FONT, MwClockHud.PERIOD_AT.x, MwClockHud.PERIOD_AT.y, MwClockHud.ATTR,
						MwClockHud.period_text(rom, int(op[2]))))
				if pp:
					out.append(text_text(rom, MwClockHud.FONT, MwClockHud.PP_LABEL_AT.x, MwClockHud.PP_LABEL_AT.y,
							MwClockHud.ATTR, PackedByteArray([0x5B, 0x5D])))
				out.append(text_text(rom, MwClockHud.FONT, MwClockHud.CLOCK_AT.x, MwClockHud.CLOCK_AT.y, MwClockHud.ATTR,
						_time_bytes(int(op[3]))))
			_:
				out.append("? " + str(op))
	return out


## The recorder's "win" records [param records] as entries ([method
## window_list]'s form); writes to other planes go to [param other]
## instead. RAM strings: the logged bytes; the quote from [param snap].
static func recorded_window(rom: PackedByteArray, records: Array, snap: PackedByteArray, other: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for e in records:
		var kind := int(e[0])
		var ret := int(e[1]) & 0xFFFFFF
		match kind:
			1:
				if int(e[4]) & 0xFFFFFFFF != WINDOW_PLANE:
					other.append("text from $%X" % ret)
					continue
				var a0 := int(e[2]) & 0xFFFFFFFF
				var src: Variant = a0
				if a0 >= 0x400000:
					var b := PackedByteArray()
					for v in [int(e[8]), int(e[9])]:
						for sh in [24, 16, 8, 0]:
							b.append((v >> sh) & 0xFF)
					var z := b.find(0)
					src = b.slice(0, z) if z >= 0 else b
				out.append(text_text(rom, int(e[3]) & 0xFFFFFF, _w(int(e[5])), _w(int(e[6])), int(e[7]), src))
			2:
				if int(e[4]) & 0xFFFFFFFF != WINDOW_PLANE:
					other.append("glyph from $%X" % ret)
					continue
				out.append("glyph %X (%d,%d) %02X %s" % [int(e[3]) & 0xFFFFFF, _w(int(e[5])), _w(int(e[6])), int(e[7]) & 0xFF,
						_ascii(PackedByteArray([int(e[2]) & 0xFF]))])
			3:
				if int(e[3]) & 0xFFFFFFFF != WINDOW_PLANE:
					other.append("fill from $%X" % ret)
					continue
				out.append(fill_text(_w(int(e[4])), _w(int(e[5])), _w(int(e[6])), _w(int(e[7])), int(e[2])))
			4:
				if ret == 0x14710:
					continue                     # `$146EA`'s own (logged as kind 3)
				var addr := int(e[3]) & 0xFFFF
				if addr < WINDOW_VRAM:
					other.append("VRAM fill from $%X" % ret)
					continue
				var off := addr - WINDOW_VRAM
				out.append(fill_text((off % 128) / 2, off / 128, (int(e[2]) & 0xFFFF) / 2, int(e[6]) & 0xFFFF, int(e[5])))
			5:
				if ret in WIDGET_MAPS:
					continue
				other.append("map copy from $%X" % ret)
			6:
				if int(e[3]) & 0xFFFFFFFF != WINDOW_PLANE:
					other.append("frame from $%X" % ret)
					continue
				out.append("box (%d,%d) %dx%d filled %d erase %d" % [_w(int(e[4])), _w(int(e[5])), _w(int(e[6])), _w(int(e[7])),
						1 if int(e[8]) & 0xFFFF else 0, 1 if int(e[9]) & 0xFFFF else 0])
			7:
				var a0 := int(e[2]) & 0xFFFFFF
				var b := PackedByteArray()
				if a0 >= 0xFF0000:
					var a := a0
					while a < MwRinkRam.BASE + MwRinkRam.SIZE and MwRinkRam.u8(snap, a) != 0 and b.size() < 512:
						b.append(MwRinkRam.u8(snap, a))
						a += 1
				else:
					b = MwGfx.rom_string(rom, a0)
				out.append("quote %X (%d,%d) %dx%d %02X %s" % [int(e[5]) & 0xFFFFFF, _w(int(e[6])), _w(int(e[7])), _w(int(e[8])),
						_w(int(e[9])), int(e[4]) & 0xFF, _ascii(b)])
			8:
				out.append("widget pp %d" % (int(e[2]) & 1))
			10:
				continue                         # a glyph's cells (the name-table model: --draw-fixture)
			_:
				other.append("kind %d" % kind)
	return out


## `--draw-fixture`: see the draw fixture section.
func _build_draw_fixture(_rom: PackedByteArray, _names: Array[String]) -> void:
	pass


# --- the rink entries ------------------------------------------------------------------------

## RNG callers of the entries' line-ups (return addresses): the CPU line
## changes' rolls, a substitute's creation, the special play's picks, the
## pad picks.
const ENTRY_RNG_SITES := [0xF52E, 0xF554, 0xF57C, 0x826, 0xF60E, 0xF690, 0x3A9A]
## The screen visit runner (recorder v5: the screens between two rink visits on our state).
const ScreenVisit := preload("res://test/sim/screen_visit.gd")
## Game text in the fixtures by ROM address.
const RomText := preload("res://test/sim/rom_text.gd")
## `$7F8` player_create's draw (+$3C).
const PLAYER_CREATE_RNG := 0x826


## Entry pair (k, k+1): [differences after masks, notes, our RAM, the
## screens, our RAM just before the entry].
func check_entry(rom: PackedByteArray, rec: MwSimRecording, k: int, tick_logs := {}) -> Array:
	var a := rec.end(k)
	var b := rec.start(k + 1)
	var screens: Array[int] = []
	for e in rec.meta["screens"]:
		if int(e[0]) == k + 1:
			screens.append(int(e[1]))
	var notes: Array[String] = []
	var plan := make_plan(rec, k, tick_logs)
	# the RNG chain after the segment (the draws in order, by state)
	var chain := _chain(rec, k, MwRinkRam.u32(a, MwRinkRam.RNG))
	var p0 := 0
	for i in chain.size():
		if not (int(chain[i][1]) in ENTRY_RNG_SITES):
			p0 = i + 1
	var want_rng := MwRinkRam.u32(b, MwRinkRam.RNG)
	var best: Array = []
	var start_ring := ring
	var tries: Array = range(p0, chain.size() + 1)
	if not screen_visits(rom, rec, k, screens).is_empty():
		tries = [p0]           # the screens run on our state: the entry's RNG is ours
	elif 3 in screens:
		# a new match: the main menu's team rows set their teams up too
		# (`$12F34` / `$13004` -> `$3698`, at its entry and at every change);
		# the matchup's own set-up creates the last 12 players
		var last := -1
		for i in chain.size():
			if int(chain[i][1]) == PLAYER_CREATE_RNG:
				last = i
		if last >= 11:
			tries = [last - 11]
	for start_at in tries:
		ring = start_ring
		var r := _run_entry(rom, rec, k, screens, plan, chain, start_at)
		if r[1] == want_rng or best.is_empty():
			best = r
			if r[1] == want_rng:
				break
	ring = best[3]
	var got: PackedByteArray = best[0]
	if best[1] != want_rng:
		notes.append("rng")
	notes.append_array(best[4])
	var d := _entry_masked(got, b, best[2], notes)
	return [d, notes, got, screens, best[5]]


## The after-segment draws of pass k in order: [[state before, site], ...].
static func _chain(rec: MwSimRecording, k: int, from: int) -> Array:
	var by := {}
	for e in rec.log_entries("rn", k, true):
		by[int(e[1]) & 0xFFFFFFFF] = int(e[0]) & 0xFFFFFF
	for e in rec.log_entries("rr", k, true):
		by[int(e[3]) & 0xFFFFFFFF] = int(e[0]) & 0xFFFFFF
	var out := []
	var r := MlhRng.new(from)
	while by.has(r.state) and out.size() < 4096:
		out.append([r.state, by[r.state]])
		r.next_state()
	return out


## One try of entry pair (k, k+1), the entry's draws starting at chain
## position [param start_at]: [our RAM, our RNG state at the end].
func _run_entry(rom: PackedByteArray, rec: MwSimRecording, k: int, screens: Array[int], plan: TickPlan,
		chain: Array, start_at: int) -> Array:
	var a := rec.end(k)
	var b := rec.start(k + 1)
	plan.reset()
	var parts := _parts(rom)
	var up: MwRinkUpdate = parts[0]
	var ph: MwRinkPhases = parts[1]
	var sim := up.sim
	var s := sim.s
	MwRinkRam.decode_into(rom, s, a)
	s.net_slack = 1 if int(rec.passes[k]["screen"]) == 6 else -1
	s.replay.ring_bytes = ring.duplicate()
	sim.rng_log.clear()
	sim.log_rng = debug_rng
	sim.events.clear()
	up.hooks = plan
	ph.hooks = plan
	var notes: Array[String] = []
	# the rest of pass k: the update, the puck rules and the phase handler, which leaves
	up.after_segment(rec.elapsed(k))
	var exit_to: int = screens[0]
	var to := ph.pass_end(rec.elapsed(k))
	var dt := 0
	while to != exit_to and plan.logged.is_empty() and dt < 4:
		# no tick log: the handler's tick is 0-4 ticks after the segment
		dt += 1
		plan.reset()
		plan.exit_dt = dt
		MwRinkRam.decode_into(rom, s, a)
		s.replay.ring_bytes = ring.duplicate()
		sim.events.clear()
		up.after_segment(rec.elapsed(k))
		to = ph.pass_end(rec.elapsed(k))
	if to != exit_to:
		notes.append("exit %d, the original's %d" % [to, exit_to])
		if to < 0:
			MwRinkMatch.rink_exit(sim, exit_to)
	# recorder v5: the screens in between run through their ports on our
	# state (screen_visit.gd: each pass with the original's elapsed ticks,
	# pads and sound answers), so what they leave in the rink is ours - the
	# replay's last frame, the penalty scoreboard's box, the fight's count
	# and spot, the comment's text box, the RNG; without screen records (or
	# with a screen not ported in the gap) it is taken from the recording
	# below, with a note
	var visits := screen_visits(rom, rec, k, screens)
	var ran := not visits.is_empty()
	for v in visits:
		ScreenVisit.run(rec, v[0], s, v[1])
	# what the screens in between leave: the instant replay (7) the frame it
	# drew last - its camera in the scroll buffers, its markers and plates
	# (recorder v5: MwReplaySim fed the recorded pads of each visit, so the
	# frame drawn last is the one the controls reached; before, the recorder
	# left it after 150 ticks with nothing pressed: the oldest frame); the
	# scroll buffers cleared by any other screen (a direct re-entry keeps
	# them); after a fight (18) or the referee (19) the fight screen counts
	# the fight (team +$49C) and the next faceoff's spot comes from them
	# (plan 11)
	if not ran and 7 in screens and s.replay.frames > 0:
		var replays := replay_visits(rec, k + 1)
		if replays.is_empty():
			var rp := MwInstantReplay.new(s, rom)
			rp.start(0)
			rp.leave()
		else:
			for v in replays:
				run_replay(rom, rec, v, s)
			notes.append("screen 7 from its records")
	if screens.size() > 1 and screens[screens.size() - 2] != 7:
		s.scroll_b = Vector2i.ZERO
		if screens[screens.size() - 2] == 3 and MwRinkRam.u16(b, MwRinkRam.FIGHT_BLOCK) == 0:
			# the matchup (not in the attract demo) shows the rink map from its camera point (`$14CDE`)
			var c := MwMatchup.RINK_CAMERA
			s.scroll_b = Vector2i((-c.x) & 0x1FF, c.y & 0xFF)
		elif screens[screens.size() - 2] == 3:
			# the attract demo's matchup draws nothing: the main menu's starfield scroll stays
			# (its motion: the scene's, outside these checks)
			s.scroll_b = Vector2i(MwRinkRam.u16(b, MwRinkRam.SCROLL_B), MwRinkRam.u16(b, MwRinkRam.SCROLL_B + 4))
			notes.append("main menu's starfield scroll")
	if not ran and (18 in screens or 19 in screens):
		if s.faceoff_spot != MwRinkRam.u8(b, MwRinkRam.FACEOFF_SPOT):
			notes.append("spot from screen 18")
			s.faceoff_spot = MwRinkRam.u8(b, MwRinkRam.FACEOFF_SPOT)
		if MwRinkRam.u16(b, MwRinkRam.GOAL_KIND) != s.goal_kind or MwRinkRam.u32(b, MwRinkRam.SCORER) != s.scorer:
			notes.append("fight screen $C63A")
			s.goal_kind = MwRinkRam.u16(b, MwRinkRam.GOAL_KIND)
			s.scorer = MwRinkRam.u32(b, MwRinkRam.SCORER)
		for t in 2:
			var at: int = MwRinkRam.TEAMS[t] + 0x49C
			if MwRinkRam.u16(a, at) != MwRinkRam.u16(b, at):
				notes.append("fight screen +$49C")
				s.teams[t].stats[0x49C - MwRinkState.Team.STATS_AT] = MwRinkRam.u8(b, at)
				s.teams[t].stats[0x49D - MwRinkState.Team.STATS_AT] = MwRinkRam.u8(b, at + 1)
	# the penalty scoreboard (17) sends the called players to the box (`$A2A4`, plan 10)
	if not ran and 17 in screens:
		sim.penalties.serve_calls()
		# the player whose penalty the scoreboard shows (`$FFC63C`; the screen: plan 11)
		if MwRinkRam.u32(b, MwRinkRam.SCORER) != s.scorer:
			notes.append("screen 17's player")
			s.scorer = MwRinkRam.u32(b, MwRinkRam.SCORER)
		# the box display's animations ran during the screen (its time: plan 11)
		for t in 2:
			for i in 3:
				var at: int = MwRinkRam.TEAMS[t] + MwRinkPenalties.entry(i)
				for off in [8, 9, 0xA]:
					if s.teams[t].stats[MwRinkPenalties.entry(i) + off - MwRinkState.Team.STATS_AT] != MwRinkRam.u8(b, at + off):
						if not "screen 17's box display" in notes:
							notes.append("screen 17's box display")
						s.teams[t].stats[MwRinkPenalties.entry(i) + off - MwRinkState.Team.STATS_AT] = MwRinkRam.u8(b, at + off)
	# the scoreboards' coach comment (12-17: `$F420` and the text box, plan 11)
	if not ran and screens.size() > 1:
		var bs := MwRinkRam.decode(rom, b)
		if bs.quote != s.quote or bs.text_box.cursor_x != s.text_box.cursor_x or bs.speech_box != s.speech_box:
			notes.append("screen %d's text box" % screens[0])
			s.quote = bs.quote
			s.text_box = bs.text_box
			s.speech_box = bs.speech_box
			s.box_fill = bs.box_fill
			s.box_c3bc = bs.box_c3bc
			s.quote_ptr = bs.quote_ptr
			s.coach_name = bs.coach_name
			s.quote_value = bs.quote_value
	# the recorder's pokes at the screens in between (a short clock, a tie)
	for pk in rec.meta.get("pokes", []):
		if int(pk[0]) != k + 1:
			continue
		var at := ("%s" % pk[2]).hex_to_int()
		var v := int(pk[3])
		if at == MwRinkRam.CLOCK:
			s.clock = v
		elif at == MwRinkRam.TEAMS[1] + 0x4A2:
			s.teams[1].score = v
		elif at == MwRinkRam.MINUTES:
			s.period_minutes = v
		notes.append("recorder poke")
	# the entry
	if not ran:
		s.rng.state = int(chain[start_at][0]) if start_at < chain.size() else MwRinkRam.u32(b, MwRinkRam.RNG)
	s.tick = MwRinkRam.u32(b, MwRinkRam.PASS_TICK) - 1
	# a new match from the menus: the matchup's set-up (`$B2B0`, plan 11)
	if 3 in screens:
		var at := MwRinkRam.SETUP - MwRinkRam.BASE
		var su := MwMatchSetup.from_bytes(b.slice(at, at + 10))
		if _fresh_now:
			# the live game's new match: a new state and its own sim (MwRink._live_entry)
			s = fresh_state(s)
			sim = MwRinkSim.new(rom, s)
			sim.rng_log = up.sim.rng_log
			sim.log_rng = up.sim.log_rng
			sim.events = up.sim.events
			up = MwRinkUpdate.new(sim)
			up.hooks = plan
			ph = MwRinkPhases.new(up)
			ph.hooks = plan
		MwRinkMatch.matchup_setup(sim, su, MwRinkRam.u8(b, 0xFFBD7C))
		if _fresh_now:
			# what MwRink._live_entry sets after the matchup's set-up
			s.period_minutes = maxi(su.period_minutes, 1)
			s.period_row = su.period_index
			s.penalties = su.penalties
			s.play_mode = su.play_mode
			s.fight_block = 1 if MwRinkRam.u16(b, MwRinkRam.FIGHT_BLOCK) != 0 else 0
	var before := MwRinkRam.encode(s, a)
	var entry := screens[screens.size() - 1]
	if ph.enter(entry) >= 0:
		return [MwRinkRam.encode(s, a), s.rng.state, _modeled(s), s.replay.ring_bytes, notes, before]
	var rng_end := s.rng.state
	if debug_rng:
		print("  entry %d try %d (chain %d draws):" % [k, start_at, chain.size()])
		for e in sim.rng_log:
			print("    %08X %s" % [int(e[0]), e[1]])
	# the faceoff set-up reads the tick before rink_load's loading time:
	# any tick between the exit and the entry's own fits
	var take := MwRinkRam.u32(b, MwRinkRam.PUCK + 0x26)
	if entry != 6 and take != s.puck.take_tick and take >= plan.t_end and take <= s.puck.take_tick:
		s.puck.take_tick = take
		notes.append("faceoff tick")
	# the first pass's start
	s.tick = MwRinkRam.u32(b, MwRinkRam.PASS_TICK)
	up.pass_start(rec.elapsed(k + 1))
	for pad in 4:
		s.pads_held[pad] = MwRinkRam.u8(b, MwRinkRam.PADS + 2 * pad)
		s.pads_new[pad] = MwRinkRam.u8(b, MwRinkRam.PADS + 2 * pad + 1)
	return [MwRinkRam.encode(s, a), rng_end, _modeled(s), s.replay.ring_bytes, notes, before]


## The state the live game makes for a new match (MwRink._live_entry): a
## new MwRinkState, with what the session hands on - the RNG, the playoffs,
## the ref icons (MwRinkMatch.boot_icons) - and what this check sets
## around it (the tick, the net slack, plane B's scroll).
static func fresh_state(s: MwRinkState) -> MwRinkState:
	var f := MwRinkState.new()
	for k in ["rng", "playoffs", "penalty", "stoppage", "tick", "net_slack", "scroll_b"]:
		f.set(k, s.get(k))
	return f


## `--fresh`: each matchup entry (a new match) as the RAM gives it and on a
## fresh state; prints what only the fresh one gets wrong, by field.
func _fresh_audit(rom: PackedByteArray, rec: MwSimRecording, show: int) -> bool:
	var tick_logs := _tick_logs(rec)
	var fields := {}
	var n := 0
	var bad := 0
	var shown := 0
	for k in rec.count() - 1:
		var p: Dictionary = rec.passes[k]
		var q: Dictionary = rec.passes[k + 1]
		if int(p["visit"]) == int(q["visit"]) and int(p["screen"]) == int(q["screen"]):
			continue
		var screens: Array[int] = []
		for e in rec.meta["screens"]:
			if int(e[0]) == k + 1:
				screens.append(int(e[1]))
		if not 3 in screens:
			continue
		n += 1
		ring = rec.ring_start()
		var e0 := check_entry(rom, rec, k, tick_logs)
		ring = rec.ring_start()
		_fresh_now = true
		var e1 := check_entry(rom, rec, k, tick_logs)
		_fresh_now = false
		var was := {}
		for addr in e0[0]:
			was[addr] = true
		var fresh_only := PackedInt32Array()
		for addr in e1[0]:
			if not was.has(addr):
				fresh_only.append(addr)
		if only != "":
			# --only TEXT: every byte of those fields, the RAM entry's and the fresh one's
			for addr in range(MwRinkRam.BASE, MwRinkRam.BASE + MwRinkRam.SIZE):
				var desc := MwRinkRam.describe(addr)
				if desc.contains(only) and MwRinkRam.u8(e0[2], addr) != MwRinkRam.u8(e1[2], addr):
					print("    %s: RAM entry %02X, fresh %02X, the original %02X" % [desc, MwRinkRam.u8(e0[2], addr),
							MwRinkRam.u8(e1[2], addr), MwRinkRam.u8(rec.start(k + 1), addr)])
		if fresh_only.is_empty():
			continue
		bad += 1
		var got: PackedByteArray = e1[2]
		var want := rec.start(k + 1)
		var here := {}
		for addr in fresh_only:
			var key := _field_key(MwRinkRam.describe(addr))
			if not here.has(key):
				here[key] = "%s ours %02X want %02X" % [MwRinkRam.describe(addr), MwRinkRam.u8(got, addr), MwRinkRam.u8(want, addr)]
		for key in here:
			if not fields.has(key):
				fields[key] = [0, here[key]]
			fields[key][0] += 1
		if shown < show:
			shown += 1
			print("  %s entry %d -> %d %s: %d bytes only on a fresh state: %s" % [rec.name, k, k + 1, screens, fresh_only.size(),
					"; ".join(here.values().slice(0, 12))])
	var keys := fields.keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return fields[x][0] > fields[y][0])
	print("%s: %d new matches, %d with fields only a fresh state gets wrong" % [rec.name, n, bad])
	for key in keys:
		print("    %-28s %d   e.g. %s" % [key, fields[key][0], fields[key][1]])
	return bad > 0


## `--fresh --visit`: the first rink visit of each new match played on from
## both entries (as `--visit` plays a visit on our state): the fields that
## only the fresh one gets wrong, split into those still wrong where the
## visit ends without having spread (left over, never read) and those that
## go wrong later (read: the fresh state changes the play), with the pass.
func _fresh_visits(rom: PackedByteArray, rec: MwSimRecording) -> bool:
	var logs := _tick_logs(rec)
	var any := false
	for k in rec.count() - 1:
		var p: Dictionary = rec.passes[k]
		var q: Dictionary = rec.passes[k + 1]
		if int(p["visit"]) == int(q["visit"]) and int(p["screen"]) == int(q["screen"]):
			continue
		var screens: Array[int] = []
		for e in rec.meta["screens"]:
			if int(e[0]) == k + 1:
				screens.append(int(e[1]))
		if not 3 in screens:
			continue
		ring = rec.ring_start()
		var e0 := check_entry(rom, rec, k, logs)
		ring = rec.ring_start()
		_fresh_now = true
		var e1 := check_entry(rom, rec, k, logs)
		_fresh_now = false
		var k0 := k + 1
		var k1 := k0
		while k1 + 1 < rec.count() and int(rec.passes[k1 + 1]["visit"]) == int(rec.passes[k0]["visit"]) \
				and int(rec.passes[k1 + 1]["screen"]) == int(rec.passes[k0]["screen"]):
			k1 += 1
		var base := _visit_diffs(rom, rec, logs, k0, k1, e0[2])
		var fresh := _visit_diffs(rom, rec, logs, k0, k1, e1[2])
		var at_entry := {}
		for addr in e1[0]:
			at_entry[addr] = true
		for addr in e0[0]:
			at_entry.erase(addr)
		var spread := {}       # field -> [first pass, example]
		var last := {}
		for i in fresh.size():
			var b_set := {}
			for addr in base[i][1]:
				b_set[addr] = true
			var here := {}
			for addr in fresh[i][1]:
				if b_set.has(addr):
					continue
				var key := _field_key(MwRinkRam.describe(addr))
				here[key] = true
				if not at_entry.has(addr) and not spread.has(key):
					spread[key] = [fresh[i][0], MwRinkRam.describe(addr)]
			if i == fresh.size() - 1:
				last = here
		var left := {}
		for addr in at_entry:
			var key := _field_key(MwRinkRam.describe(addr))
			if last.has(key):
				left[key] = true
		any = any or not spread.is_empty()
		print("%s: new match at pass %d, visit passes %d-%d: %d entry fields only fresh; still wrong at the visit's end: %s" % [
				rec.name, k + 1, k0, k1, at_entry.size(), ", ".join(left.keys()) if not left.is_empty() else "none"])
		var keys := spread.keys()
		keys.sort_custom(func(x: String, y: String) -> bool: return spread[x][0] < spread[y][0])
		for key in keys.slice(0, 8):
			print("    goes wrong later: %-26s first at %s (%s)" % [key, spread[key][0], spread[key][1]])
		if spread.is_empty() or not bisect:
			continue
		# which of the entry's fresh-only fields the play reads: each group
		# given the original's bytes alone, the visit played again
		var groups := {}
		for addr in at_entry:
			var g := _group_key(MwRinkRam.describe(addr))
			if not groups.has(g):
				groups[g] = []
			groups[g].append(addr)
		var base_n := _spread_count(base, _visit_diffs(rom, rec, logs, k0, k1, e1[2]), at_entry)
		for g in groups:
			var img: PackedByteArray = (e1[2] as PackedByteArray).duplicate()
			for addr in groups[g]:
				MwRinkRam.w8(img, addr, MwRinkRam.u8(e0[2], addr))
			var n := _spread_count(base, _visit_diffs(rom, rec, logs, k0, k1, img), at_entry)
			if n < base_n:
				print("    read: %-30s the original's bytes take the later differences from %d to %d" % [g, base_n, n])
				# which of its bytes, one at a time
				for addr in groups[g]:
					var one: PackedByteArray = (e1[2] as PackedByteArray).duplicate()
					MwRinkRam.w8(one, addr, MwRinkRam.u8(e0[2], addr))
					var m := _spread_count(base, _visit_diffs(rom, rec, logs, k0, k1, one), at_entry)
					if m < base_n:
						print("      %s (ours %02X, the original's %02X): %d to %d" % [MwRinkRam.describe(addr),
								MwRinkRam.u8(e1[2], addr), MwRinkRam.u8(e0[2], addr), base_n, m])
	return any


## A RAM field's group for `--bisect`: a player field by name (every
## player's), a team offset (both teams'), else the field without its byte
## offset.
static func _group_key(desc: String) -> String:
	var g := desc
	var m := RegEx.create_from_string("^T\\d P\\d \\+\\$[0-9A-F]+ (\\w+)$").search(g)
	if m:
		return "player " + m.get_string(1)
	m = RegEx.create_from_string("^(T)\\d (\\+\\$[0-9A-F]+)$").search(g)
	if m:
		return "team " + m.get_string(2)
	m = RegEx.create_from_string("^(.*?) \\+\\$[0-9A-F]+$").search(g)
	if m:
		return m.get_string(1)
	return g


## Pass-diff entries of [param fresh] (per pass) not in [param base] nor
## at the entry: how far the fresh state's differences spread.
static func _spread_count(base: Array, fresh: Array, at_entry: Dictionary) -> int:
	var n := 0
	for i in mini(base.size(), fresh.size()):
		var b_set := {}
		for addr in base[i][1]:
			b_set[addr] = true
		for addr in fresh[i][1]:
			if not b_set.has(addr) and not at_entry.has(addr):
				n += 1
	return n


## A rink visit (passes [param k0]-[param k1]) played on from RAM image
## [param img] as `--visit` does: per pass ["pass j segment" / "gap", the
## differing addresses].
func _visit_diffs(rom: PackedByteArray, rec: MwSimRecording, logs: Dictionary, k0: int, k1: int, img: PackedByteArray) -> Array:
	var out := []
	var parts := _parts(rom)
	var up: MwRinkUpdate = parts[0]
	var sim := up.sim
	var ai := MwRinkAI.new()
	for j in range(k0, k1 + 1):
		var s := sim.s
		MwRinkRam.decode_into(rom, s, img)
		s.tick = MwRinkRam.u32(rec.start(j), MwRinkRam.TICK)
		sim.cpu = ai
		sim.hooks = MwReplayControl.new(rom, rec, j)
		sim.log_rng = false
		sim.run(rec.elapsed(j))
		var seg := MwRinkRam.encode(s, rec.end(j))
		out.append(["pass %d segment" % j, MwRinkRam.diff(seg, rec.end(j))])
		if j == k1:
			break
		var c := check_pair(rom, rec, j, logs, seg)
		out.append(["pass %d gap" % j, c[0]])
		img = c[3]
	return out


## Recorder v5: the screen visits between rink passes [param k] and [param
## k] + 1 with their sims, [[visit, sim], ...] in order, when every screen
## of the gap (all but the rink entry at the end) has screen records and a
## port; else [].
static func screen_visits(rom: PackedByteArray, rec: MwSimRecording, k: int, screens: Array[int]) -> Array:
	if rec.screen_passes.is_empty() or screens.size() < 2:
		return []
	var visits := ScreenVisit.visits_after(rec, k + 1)
	if visits.size() != screens.size() - 1:
		return []
	var out := []
	for i in visits.size():
		var v: Array = visits[i]
		if int(v[2]) != screens[i]:
			return []
		var sm := MwScreenSims.make(screens[i], rom)
		if not ScreenVisit.ported(sm):
			return []
		out.append([v, sm])
	return out


## Recorder v5: the instant replay's visits after [param n] rink passes
## (screen records): [[first record, last record, the screen before (D7)],
## ...] in order; [] without screen records.
static func replay_visits(rec: MwSimRecording, n: int) -> Array:
	var out := []
	for v in rec.screen_visits():
		if int(v[2]) != 7 or int(rec.screen_passes[v[0]][0]) != n:
			continue
		var tick := int(rec.screen_passes[v[0]][2])
		var prev := int(rec.passes[n - 1]["screen"]) if n > 0 else -1    # (the rink's, if none listed)
		for x in rec.meta["screens"]:
			if int(x[1]) == 7 and int(x[2]) == tick:
				break
			prev = int(x[1])
		out.append([int(v[0]), int(v[1]), prev])
	return out


## Recorder v5: screen 7's visit [param v] ([method replay_visits]) on
## [param s] with MwReplaySim, each pass with its recorded elapsed ticks
## (d0 at `$9E70`) and pads (the next record's `$FFCA5A`; the last pass
## before the rink, which has no snapshot of its read: Start on the
## controlling pad, which is what left).
static func run_replay(rom: PackedByteArray, rec: MwSimRecording, v: Array, s: MwRinkState) -> void:
	var first: int = v[0]
	var last: int = v[1]
	var at_entry := rec.screen_ram(first)
	for pad in 4:
		s.pads_held[pad] = MwRinkRam.u8(at_entry, MwRinkRam.PADS + 2 * pad)
		s.pads_new[pad] = MwRinkRam.u8(at_entry, MwRinkRam.PADS + 2 * pad + 1)
	var sim := MwReplaySim.new(rom)
	sim.enter(s, 7, int(v[2]))
	for j in range(first + 1, last + 1):
		var e: Array = rec.screen_passes[j]
		var held := [0, 0, 0, 0]
		var new := [0, 0, 0, 0]
		if j + 1 < rec.screen_passes.size() and (j < last or int(rec.screen_passes[j + 1][0]) == int(e[0])):
			var r := rec.screen_ram(j + 1)
			for pad in 4:
				held[pad] = MwRinkRam.u8(r, MwRinkRam.PADS + 2 * pad)
				new[pad] = MwRinkRam.u8(r, MwRinkRam.PADS + 2 * pad + 1)
		elif j == last:
			new[sim.replay.pad] = MwInstantReplay.START
		if sim.step(int(e[4]), held, new) >= 0:
			break


## The bytes of the snapshot our state models (MwRinkRam.encode writes
## them whatever the template holds): {address offset: true}.
static func _modeled(s: MwRinkState) -> Dictionary:
	var zero := PackedByteArray()
	zero.resize(MwRinkRam.SIZE)
	var ones := PackedByteArray()
	ones.resize(MwRinkRam.SIZE)
	ones.fill(0xFF)
	var x := MwRinkRam.encode(s, zero)
	var y := MwRinkRam.encode(s, ones)
	var out := {}
	for i in MwRinkRam.SIZE:
		if x[i] == y[i]:
			out[i] = true
	return out


## The entry's differences in the bytes our state models (the rest belongs
## to the other screens, the main loop, the sound driver or unported code;
## only counted, in [param notes]).
func _entry_masked(got: PackedByteArray, want: PackedByteArray, modeled: Dictionary, notes: Array[String]) -> PackedInt32Array:
	var out := PackedInt32Array()
	var other := {}
	for addr in MwRinkRam.diff(got, want):
		if modeled.has(addr - MwRinkRam.BASE):
			out.append(addr)
		else:
			other["$%04X" % ((addr & 0xFFF0) & 0xFFFF)] = true
	if not other.is_empty():
		notes.append("unmodelled bytes")
		for key in other:
			unmodelled[key] = true
	return out


# --- the GUT fixture -------------------------------------------------------------------------

const FIXTURE := "res://../compare/fixtures/rink_gaps.json"
## Gap features and how many pairs to keep of each.
const GAP_FEATURES := {"throw": 2, "fire": 1, "shark": 2, "under_ice": 2, "pit": 1, "lamp": 1, "clock": 1, "replay": 2,
		"impale_record": 1, "arrow": 1, "box_countdown": 2, "box_release": 2, "power_play": 2, "call_stops_play": 2,
		"minor_cancelled": 1, "jail_break": 1}


## `--fixture`: compare/fixtures/rink_gaps.json from the recordings named
## (default: a few): gaps showing [constant GAP_FEATURES] and entries (a
## period start, a stoppage re-entry, a fight's, a Reserves line change, a
## CPU special play), each as decoded fields only - the state before as
## values along a path list, the leaves that changed, the ticks read, the
## phase handler's outputs. A gap is kept only if every leaf of ours equals
## the original's (no masked difference).
func _build_fixture(rom: PackedByteArray, names: Array[String]) -> void:
	if names == RUNS:
		names.assign(["p1p2_s4", "cpu_s16", "coop_s14", "p1_s9", "soak_22_v1", "soak_1_v5", "soak_2_v11", "soak_144_v15"])
	var paths: Array = MwSimDict.leaves(MwSimDict.to_dict(MwRinkState.new())).keys()
	var index := {}
	for i in paths.size():
		index[paths[i]] = i
	var gaps := []
	var entries := []
	var have := {}
	var entry_kinds := {}
	for name in names:
		var rec := MwSimRecording.open(name)
		if rec == null:
			continue
		ring = rec.ring_start()
		var logs := _tick_logs(rec)
		for k in rec.count() - 1:
			var p: Dictionary = rec.passes[k]
			var q: Dictionary = rec.passes[k + 1]
			var a := rec.end(k)
			var b := rec.start(k + 1)
			if int(p["visit"]) != int(q["visit"]) or int(p["screen"]) != int(q["screen"]):
				var kinds := _entry_kinds(rec, k, a, b)
				var fresh := false
				for kd in kinds:
					fresh = fresh or not entry_kinds.has(kd)
				if not fresh:
					continue
				var e := check_entry(rom, rec, k, logs)
				if not (e[0] as PackedInt32Array).is_empty() or "rng" in e[1]:
					continue
				for kd in kinds:
					entry_kinds[kd] = true
				entries.append(_entry_case(rom, rec, k, e, kinds, paths, index))
				continue
			var feats := _gap_features(rom, a, b)
			var wanted := false
			for f in feats:
				wanted = wanted or int(have.get(f, 0)) < int(GAP_FEATURES[f])
			var ring_before := ring
			var r := check_pair(rom, rec, k, logs)   # (every pair: the replay ring's data is carried)
			if not wanted or not (r[0] as PackedInt32Array).is_empty():
				continue
			var ours := MwSimDict.leaves(MwSimDict.to_dict(MwRinkRam.decode(rom, r[3])))
			var want := MwSimDict.leaves(MwSimDict.to_dict(MwRinkRam.decode(rom, b)))
			var same := true
			for path in want:
				if path != "tick" and want[path] != ours[path]:
					same = false
					break
			if not same:
				continue
			for f in feats:
				have[f] = int(have.get(f, 0)) + 1
			var g := _gap_case(rom, rec, k, feats, r[4], paths, index)
			g["ring"] = _ring_headers(ring_before, a)
			gaps.append(g)
	var doc := {"format": "mw-rink-gaps/1",
			"note": "Rink passes between segments and rink entries from pass-check --fixture (decoded fields only).",
			"rom_sha1": MwSimRecording.open(names[0]).meta["rom_sha1"], "paths": paths, "gaps": gaps, "entries": entries}
	var f := FileAccess.open(FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	print("%d gaps %s, %d entries %s -> %s" % [gaps.size(), have, entries.size(), entry_kinds.keys(),
			ProjectSettings.globalize_path(FIXTURE).simplify_path()])


# --- the phase fixture -------------------------------------------------------------------------

const PHASE_FIXTURE := "res://../compare/fixtures/rink_phases.json"
const PHASE_RUNS := ["match_p1_s6", "pause_p1_s7", "goalie_p1_s12", "match_cpu_s13", "playoff_p1_s19", "attract", "p1_s9",
		"soak_22_v1", "soak_1_v5", "soak_1_v10", "soak_21_v4", "soak_5_v5", "soak_144_v15"]


## `--phase-fixture`: compare/fixtures/rink_phases.json from the recordings
## named (default the recorder v3 runs): one gap per match-flow transition
## (phase / subphase changes, the faceoff, goal and stoppage steps, the
## puck rules, the pause menu's resume, the coach speech's starts, voices,
## expressions and ends, the clock, 0:00) and one per exit screen, each as
## decoded fields only: the state at the segment's end (the first case's
## leaves in full, each other as changes from the case before, along the
## path list), the
## ticks read, the voice answers, the pause answer, the playoff run, and
## the leaves that changed at the next segment start (or the exit screen).
## A gap is kept only if ours equals the original's.
func _build_phase_fixture(rom: PackedByteArray, names: Array[String]) -> void:
	if names == RUNS:
		names.assign(PHASE_RUNS)
	var paths: Array = MwSimDict.leaves(MwSimDict.to_dict(MwRinkState.new())).keys()
	var index := {}
	for i in paths.size():
		index[paths[i]] = i
	var cases := []
	var have := {}
	var base: Array = []
	for name in names:
		var rec := MwSimRecording.open(name)
		if rec == null:
			continue
		ring = rec.ring_start()
		var logs := _tick_logs(rec)
		for k in rec.count() - 1:
			var p: Dictionary = rec.passes[k]
			var q: Dictionary = rec.passes[k + 1]
			var a := rec.end(k)
			var b := rec.start(k + 1)
			var ring_before := ring
			var feats: Array = []
			var exit := -1
			if int(p["visit"]) != int(q["visit"]) or int(p["screen"]) != int(q["screen"]):
				for e in rec.meta["screens"]:
					if int(e[0]) == k + 1:
						exit = int(e[1])
						break
				feats = ["exit %d" % exit]
				if have.has(feats[0]):
					ring = run_pair(rom, rec, k, make_plan(rec, k, logs))[2]
					continue
				var plan := make_plan(rec, k, logs)
				var to := exit_of(rom, rec, k, plan, exit)
				if to != exit:
					continue
				have[feats[0]] = 1
				var c := _phase_case(rom, rec, k, feats, plan, paths, index, base, exit)
				c["ring"] = _ring_headers(ring_before, a)
				base = _values(rom, a, paths)
				cases.append(c)
				continue
			feats = _phase_features(rec, k, a, b)
			var wanted := false
			for f in feats:
				wanted = wanted or not have.has(f)
			var r2 := check_pair(rom, rec, k, logs)
			if not wanted or not (r2[0] as PackedInt32Array).is_empty():
				continue
			for f in feats:
				have[f] = 1
			var c2 := _phase_case(rom, rec, k, feats, r2[4], paths, index, base, -1)
			c2["ring"] = _ring_headers(ring_before, a)
			base = _values(rom, a, paths)
			cases.append(c2)
	var doc := {"format": "mw-rink-phases/1",
			"note": "Match-flow transitions of the rink pass (MwRinkPhases) from pass-check --phase-fixture (decoded fields only).",
			"rom_sha1": MwSimRecording.open(names[0]).meta["rom_sha1"], "paths": paths, "cases": cases}
	var f := FileAccess.open(PHASE_FIXTURE, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	var keys := have.keys()
	keys.sort()
	print("%d cases: %s -> %s" % [cases.size(), ", ".join(keys), ProjectSettings.globalize_path(PHASE_FIXTURE).simplify_path()])


## The match-flow transitions gap (k, k+1) shows (from the RAM).
static func _phase_features(rec: MwSimRecording, k: int, a: PackedByteArray, b: PackedByteArray) -> Array:
	var out := []
	var ph0 := MwRinkRam.u16(a, MwRinkRam.PHASE)
	var ph1 := MwRinkRam.u16(b, MwRinkRam.PHASE)
	var sb0 := MwRinkRam.u16(a, MwRinkRam.SUBPHASE)
	var sb1 := MwRinkRam.u16(b, MwRinkRam.SUBPHASE)
	if ph0 != ph1 or sb0 != sb1:
		out.append("phase %d/%d -> %d/%d" % [ph0, sb0, ph1, sb1])
	if ph0 == 1 or ph0 == 9:
		var f0 := MwRinkRam.u8(a, MwRinkRam.FACEOFF_STEP)
		var f1 := MwRinkRam.u8(b, MwRinkRam.FACEOFF_STEP)
		if f0 != f1:
			out.append("faceoff %d -> %d" % [f0, f1])
	if ph0 == 9 and sb0 == 2:
		if MwRinkRam.u32(a, MwRinkRam.DROP_OBJ) == 0 and MwRinkRam.u32(b, MwRinkRam.DROP_OBJ) != 0:
			out.append("drop thud")
		if MwRinkRam.u16(a, MwRinkRam.PLANE_B + 4) != MwRinkRam.u16(b, MwRinkRam.PLANE_B + 4):
			out.append("drop shake")
	if ph0 == 3:
		var g0 := MwRinkRam.u16(a, MwRinkRam.GOAL_MESSAGE)
		var g1 := MwRinkRam.u16(b, MwRinkRam.GOAL_MESSAGE)
		if g0 != g1:
			out.append("goal %d -> %d" % [g0, g1])
	var r0 := MwRinkRam.u16(a, MwRinkRam.PUCK_RULE)
	var r1 := MwRinkRam.u16(b, MwRinkRam.PUCK_RULE)
	if r0 != r1 or (ph0 == 0 and ph1 == 8):
		out.append("rule %d -> %d (phase %d -> %d)" % [r0, r1, ph0, ph1])
	if MwRinkRam.u16(a, MwRinkRam.RULE_HOLD) != 0xFFFF and MwRinkRam.u16(b, MwRinkRam.RULE_HOLD) == 0xFFFF:
		out.append("goalie hold")
	for pz in rec.meta.get("pauses", []):
		if int(pz[0]) == k + 1:
			out.append("pause %d" % int(pz[3]))
	var pt := MwRinkRam.PORTRAIT
	if MwRinkRam.u32(a, pt + 0x18) != MwRinkRam.u32(b, pt + 0x18) and MwRinkRam.u32(b, pt + 0x18) != 0:
		out.append("voice")
	if MwRinkRam.u16(a, pt + 0x12) == 0 and MwRinkRam.u16(b, pt + 0x12) == 1:
		out.append("expression")
	if MwRinkRam.u16(b, pt + 0x14) == 0xFE20 and MwRinkRam.u16(a, pt + 0x14) != 0xFE20:
		out.append("voices pause")
	var q0 := MwRinkRam.u16(a, MwRinkRam.CROWD_QUIET)
	var q1 := MwRinkRam.u16(b, MwRinkRam.CROWD_QUIET)
	if q0 != q1:
		out.append("speech %s (phase %d)" % ["start" if q1 != 0 else "end", ph0])
	if MwRinkRam.u32(a, MwRinkRam.QUOTE_PTR) != MwRinkRam.u32(b, MwRinkRam.QUOTE_PTR) \
			or MwRinkRam.u16(a, MwRinkRam.QUOTE_VALUE) != MwRinkRam.u16(b, MwRinkRam.QUOTE_VALUE) \
			or MwRinkRam.u8(a, MwRinkRam.QUOTE) != MwRinkRam.u8(b, MwRinkRam.QUOTE):
		out.append("quote (phase %d)" % ph0)
	if MwRinkRam.u16(a, MwRinkRam.CLOCK) != MwRinkRam.u16(b, MwRinkRam.CLOCK):
		out.append("clock")
	if ph0 == 0 and ph1 == 5:
		out.append("0:00")
	return out


func _phase_case(rom: PackedByteArray, rec: MwSimRecording, k: int, feats: Array, plan: TickPlan, paths: Array,
		index: Dictionary, base: Array, exit: int) -> Dictionary:
	var a := rec.end(k)
	var b := rec.start(k + 1)
	var c := _gap_case(rom, rec, k, feats, plan, paths, index)
	if exit >= 0:
		c["end"] = []
		c["exit"] = exit
	if not base.is_empty():
		var full: Array = c["start"]
		var d := []
		for i in full.size():
			if full[i] != base[i]:
				d.append([i, full[i]])
		c.erase("start")
		c["start_diff"] = d
	var po := MwRinkRam.decode(rom, a).playoffs
	c["playoffs"] = [po.rng.state, po.dead[0], po.dead[1], po.seed, po.pair, po.conference, po.best_of_3, po.flag_11,
			po.series, po.round, po.flags]
	return c


## What gap (k, k+1) shows (from the RAM: no simulation).
static func _gap_features(rom: PackedByteArray, a: PackedByteArray, b: PackedByteArray) -> Array:
	var out := []
	for i in 8:
		var o := MwRinkRam.OBJECTS + MwRinkRam.OBJECT_SIZE * i
		var k0 := MwRinkRam.u8(a, o + 0x28)
		var k1 := MwRinkRam.u8(b, o + 0x28)
		if k0 == 0 and k1 >= 0xC:
			out.append("throw")
		if k0 == 0xC and k1 == 4:
			out.append("fire")
		if k0 >= 0xC and k1 == 0:
			out.append("pit")
		if k0 == 1 and MwRinkRam.u16(a, MwRinkRam.PHASE) == 0:
			out.append("shark")
		if k0 >= 8 and k0 <= 10 and MwRinkRam.s16(a, o + 0x26) < 0 and MwRinkRam.u16(a, MwRinkRam.PHASE) == 0:
			out.append("under_ice")
	for l in [0xB4, 0xD8]:
		if MwRinkRam.s32(a, MwRinkRam.RINK + l + 0x10) != 0:
			out.append("lamp")
	if MwRinkRam.u16(a, MwRinkRam.CLOCK) != MwRinkRam.u16(b, MwRinkRam.CLOCK):
		out.append("clock")
	if MwRinkRam.u16(a, MwRinkRam.REPLAY + 0x10) != MwRinkRam.u16(b, MwRinkRam.REPLAY + 0x10):
		out.append("replay")
	if MwRinkRam.u32(a, MwRinkRam.IMPALE) != MwRinkRam.u32(b, MwRinkRam.IMPALE):
		out.append("impale_record")
	for t in 2:
		for kk in [0x33A, 0x34E]:
			if MwRinkRam.u8(a, MwRinkRam.TEAMS[t] + kk + 7) != MwRinkRam.u8(b, MwRinkRam.TEAMS[t] + kk + 7):
				out.append("arrow")
	# penalties (plan 10): the box (team +$362..+$3A1), the power play
	for t in 2:
		var tb: int = MwRinkRam.TEAMS[t]
		for i in 3:
			if MwRinkRam.u16(a, tb + MwRinkPenalties.entry(i) + 0xC) != MwRinkRam.u16(b, tb + MwRinkPenalties.entry(i) + 0xC):
				out.append("box_countdown")
		if MwRinkRam.u8(b, tb + MwRinkPenalties.COUNT) < MwRinkRam.u8(a, tb + MwRinkPenalties.COUNT):
			out.append("box_release")
		if MwRinkRam.u8(b, tb + MwRinkPenalties.PENDING) < MwRinkRam.u8(a, tb + MwRinkPenalties.PENDING) \
				and MwRinkRam.u16(b, MwRinkRam.PHASE) == 0:
			out.append("minor_cancelled")
	if MwRinkRam.u16(a, MwRinkRam.PHASE) == 0 and MwRinkRam.u16(b, MwRinkRam.PHASE) == 2:
		out.append("call_stops_play")
	if (MwRinkRam.u8(a, MwRinkRam.CLOCK_WIDGET) ^ MwRinkRam.u8(b, MwRinkRam.CLOCK_WIDGET)) & 9 \
			or MwRinkRam.u16(a, MwRinkRam.PP_SECONDS) != MwRinkRam.u16(b, MwRinkRam.PP_SECONDS):
		out.append("power_play")
	if MwRinkRam.u16(b, MwRinkRam.JAIL + 4) != MwRinkRam.u16(a, MwRinkRam.JAIL + 4):
		out.append("jail_break")
	var uniq := []
	for x in out:
		if not x in uniq:
			uniq.append(x)
	return uniq


## The headers of the oldest frames in the replay ring (data at `$FF0000`
## is not in the recordings: ours, carried): [[offset, word], ...] - what
## dropping frames to make room reads.
static func _ring_headers(data: PackedByteArray, a: PackedByteArray) -> Array:
	var out := []
	var at := MwRinkRam.u16(a, MwRinkRam.REPLAY + 0xC)
	var used := MwRinkRam.u16(a, MwRinkRam.REPLAY + 0xE)
	var seen := 0
	while seen < used and out.size() < 4 and data.size() == MwRinkState.ReplayRing.SIZE:
		var w := (data[at] << 8) | data[(at + 1) % MwRinkState.ReplayRing.SIZE]
		out.append([at, w])
		var n := 2 + ((w >> 3) & 0xFFFE)
		seen += n
		at = (at + n) % MwRinkState.ReplayRing.SIZE
	return out


static func _values(rom: PackedByteArray, r: PackedByteArray, paths: Array) -> Array:
	var l := MwSimDict.leaves(MwSimDict.to_dict(MwRinkRam.decode(rom, r)))
	var out := []
	for p in paths:
		out.append(l.get(p))
	return out


static func _changes(rom: PackedByteArray, from: PackedByteArray, to: PackedByteArray, index: Dictionary) -> Array:
	var d := MwSimDict.diff(MwSimDict.to_dict(MwRinkRam.decode(rom, from)), MwSimDict.to_dict(MwRinkRam.decode(rom, to)))
	var out := []
	for p in d:
		if p != "tick":
			out.append([index[p], d[p]])
	return out


static func _pads(b: PackedByteArray) -> Array:
	var out := []
	for i in 8:
		out.append(MwRinkRam.u8(b, MwRinkRam.PADS + i))
	return out


func _gap_case(rom: PackedByteArray, rec: MwSimRecording, k: int, feats: Array, plan: TickPlan, paths: Array, index: Dictionary) -> Dictionary:
	var a := rec.end(k)
	var b := rec.start(k + 1)
	return _text_out(rom, {"run": rec.name, "pass": k, "e": rec.elapsed(k), "e_next": rec.elapsed(k + 1), "features": feats,
			"start": _values(rom, a, paths), "ticks": plan.values.duplicate(), "voices": plan.voices.duplicate(),
			"handle": plan.handle, "pause": plan.pause, "pass_tick": MwRinkRam.u32(b, MwRinkRam.PASS_TICK),
			"pads": _pads(b), "end": _changes(rom, a, b, index)}, "start", paths)


## A case's text (the quote buffer) as ROM pieces ([code]rom_text.gd[/code]):
## no game text in the fixture.
static func _text_out(rom: PackedByteArray, case: Dictionary, key: String, paths: Array) -> Dictionary:
	var idx := RomText.text_indices(paths)
	RomText.values_out(rom, case, key, idx)
	RomText.changes_out(rom, case, "end", idx)
	return case


## What entry (k, k+1) shows: its screen, a fight before it, a CPU line
## change (a substitute created at the line-up), a special play armed.
static func _entry_kinds(rec: MwSimRecording, k: int, a: PackedByteArray, b: PackedByteArray) -> Array:
	var out := []
	var screens := []
	for e in rec.meta["screens"]:
		if int(e[0]) == k + 1:
			screens.append(int(e[1]))
	out.append("screen %d" % screens[screens.size() - 1])
	if 18 in screens:
		out.append("fight")
	if 17 in screens:
		for t in 2:
			if MwRinkRam.u8(a, MwRinkRam.TEAMS[t] + MwRinkPenalties.PENDING) != 0:
				out.append("penalty box")
	if screens.size() == 1:
		out.append("direct")
	var chain := _chain(rec, k, MwRinkRam.u32(a, MwRinkRam.RNG))
	for c in chain:
		if int(c[1]) == 0xF52E:
			out.append("line change")
			break
	for c in chain:
		if int(c[1]) == 0xF57C or int(c[1]) == 0xF554:
			out.append("goalie roll")
			break
	for t in 2:
		var sp := MwRinkRam.u8(b, MwRinkRam.TEAMS[t] + 0x4A5)
		if sp != 0 and sp != MwRinkRam.u8(a, MwRinkRam.TEAMS[t] + 0x4A5):
			out.append("special play")
	return out


func _entry_case(rom: PackedByteArray, rec: MwSimRecording, k: int, e: Array, kinds: Array, paths: Array, index: Dictionary) -> Dictionary:
	var b := rec.start(k + 1)
	var before: PackedByteArray = e[4]
	var screens: Array = e[3]
	return _text_out(rom, {"run": rec.name, "pass": k, "screen": screens[screens.size() - 1], "features": kinds,
			"before": _values(rom, before, paths), "take_tick": MwRinkRam.u32(b, MwRinkRam.PUCK + 0x26),
			"e_next": rec.elapsed(k + 1), "pass_tick": MwRinkRam.u32(b, MwRinkRam.PASS_TICK), "pads": _pads(b),
			"end": _changes(rom, before, b, index)}, "before", paths)
