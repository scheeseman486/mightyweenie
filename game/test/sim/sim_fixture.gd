extends SceneTree
## Builds compare/fixtures/sim_passes.json from the simulation recordings
## (out/sim/; local): passes chosen to cover what the segment does (every
## state a player enters, phase changes, puck flags gained and lost, tick
## sites, change of player, penalty calls, sounds, pad presses, rink
## objects, elapsed values), each stored as decoded fields: the start state
## as values along a path list, the end as the leaves that changed, each
## CPU think as the leaves it changed, the ticks the original read. Run with
## `tools/bin/sim-fixture` (one process per recording for the features,
## then the build).
##
##   -s res://test/sim/sim_fixture.gd -- --features NAME
##   -s res://test/sim/sim_fixture.gd -- --build [MAX]

const RUNS := ["cpu_s0", "p1_s9", "p1p2_s4", "cpu_s10", "p1_s8", "p1p2_s17", "coop_s14", "p1_s2",
		"cpu_s16", "p1_s5", "p4_s22"]
const OUT := "res://../compare/fixtures/sim_passes.json"
const MAX := 40
const PER_RUN := 2
## Line-up cases: [run, pass]: a new match (pass 0), faceoffs after a
## stoppage (screen 5) and period starts (screen 4); Reserves runs are left
## out (their line changes are plan 09).
const LINEUPS := [["cpu_s0", 0], ["p1_s9", 0], ["cpu_s10", 0], ["p1_s8", 0], ["p1p2_s17", 0], ["p1_s2", 0],
		["cpu_s16", 0], ["p4_s22", 0], ["p1_s9", 934], ["p1_s2", 2573], ["p4_s22", 3942], ["cpu_s0", 967],
		["cpu_s0", 2099], ["p4_s22", 2060]]
## The leaves the set-up, line-up and period change decide.
const LINEUP_LEAVES := "^(teams/\\d/players/\\d/(motion/(pos|vel)/\\d|angle|target_[xy]|state|substate|anim/(address|variant|frame|position|flags)|record|original|slot|position|flags|weapon|charges)|teams/\\d/(flags4|health/\\d+|x330/\\d|pads/\\d|attr|nearest)|puck/(motion/(pos|vel)/\\d|flags|anim/address|carrier)|faceoff_spot|hold_(bit|left)/\\d)$"


static func work_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../out/plan08/fixture").simplify_path()


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--features":
		_features(args[1])
	elif args.size() >= 1 and args[0] == "--build":
		_build(int(args[1]) if args.size() > 1 else MAX)
	else:
		print("usage: --features NAME | --build [MAX]")
	quit()


## What pass [param k] of [param rec] exercises.
static func features(rec: MwSimRecording, k: int) -> Array[String]:
	var a := rec.start(k)
	var b := rec.end(k)
	var f: Array[String] = ["e:%d" % rec.elapsed(k)]
	for t in 2:
		for i in 6:
			var p := MwRinkRam.player_address(t, i)
			var s0 := MwRinkRam.u8(a, p + 0x70)
			var s1 := MwRinkRam.u8(b, p + 0x70)
			if s1 != s0:
				f.append("st:%d" % s1)
			if MwRinkRam.u8(a, p + 0x71) != MwRinkRam.u8(b, p + 0x71):
				f.append("sub:%d.%d" % [s1, MwRinkRam.u8(b, p + 0x71)])
	var ph0 := MwRinkRam.u16(a, MwRinkRam.PHASE)
	var ph1 := MwRinkRam.u16(b, MwRinkRam.PHASE)
	if ph0 != ph1:
		f.append("ph:%d" % ph1)
	var pf0 := MwRinkRam.u8(a, MwRinkRam.PUCK + 0x3D)
	var pf1 := MwRinkRam.u8(b, MwRinkRam.PUCK + 0x3D)
	for bit in 8:
		var m := 1 << bit
		if pf1 & m and not pf0 & m:
			f.append("pk:+%X" % m)
		elif pf0 & m and not pf1 & m:
			f.append("pk:-%X" % m)
	for i in 8:
		var o := MwRinkRam.OBJECTS + 0x2A * i + 0x28
		if MwRinkRam.u8(a, o) != MwRinkRam.u8(b, o):
			f.append("obj:%d" % MwRinkRam.u8(b, o))
	for e in rec.log_entries("tk", k):
		f.append("tk:%d" % int(e[0]))
	for kind in ["chg", "pen"]:
		if not rec.log_entries(kind, k).is_empty():
			f.append(kind)
	for e in rec.log_entries("snd", k):
		f.append("snd:%d" % (int(e[1]) & 0xFF))
	for pad in 4:
		var n := MwRinkRam.u8(a, MwRinkRam.PADS + 2 * pad + 1)
		for bit in [0x10, 0x20, 0x40]:
			if n & bit:
				f.append("new:%X" % bit)
		if MwRinkRam.u8(a, MwRinkRam.HOLD + 2 * pad + 1) != 0:
			f.append("hold")
	if not (rec.passes[k]["ai"] as Array).is_empty():
		f.append("think")
	var uniq: Array[String] = []
	for x in f:
		if not x in uniq:
			uniq.append(x)
	return uniq


func _features(name: String) -> void:
	var rec := MwSimRecording.open(name)
	if rec == null:
		print("%s: no recording" % name)
		return
	var out := []
	for k in rec.count():
		out.append([k, features(rec, k)])
	DirAccess.make_dir_recursive_absolute(work_dir())
	var f := FileAccess.open(work_dir().path_join(name + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": name, "passes": out}))
	print("%s: %d passes" % [name, out.size()])


## Greedy cover: the pass with the most features not yet covered, until
## all are or [param most] passes are picked; then at least PER_RUN per run.
static func choose(runs: Dictionary, most: int) -> Array:
	var covered := {}
	var picked := []
	var taken := {}
	while picked.size() < most:
		var best: Array = []
		var gain := 0
		for name in runs:
			for e in runs[name]:
				var g := 0
				for x in e[1]:
					if not covered.has(x):
						g += 1
				if g > gain:
					gain = g
					best = [name, int(e[0]), e[1]]
		if gain == 0:
			break
		picked.append(best)
		taken["%s/%d" % [best[0], best[1]]] = true
		for x in best[2]:
			covered[x] = true
	for name in runs:
		var n := 0
		for p in picked:
			if p[0] == name:
				n += 1
		var list: Array = runs[name]
		var step := maxi(1, list.size() / (PER_RUN + 1))
		var i := step
		while n < PER_RUN and i < list.size():
			var key := "%s/%d" % [name, int(list[i][0])]
			if not taken.has(key):
				picked.append([name, int(list[i][0]), list[i][1]])
				taken[key] = true
				n += 1
			i += step
	return picked


func _build(most: int) -> void:
	var rom := MwRom.data()
	var runs := {}
	for name in RUNS:
		var path := work_dir().path_join(name + ".json")
		if FileAccess.file_exists(path):
			runs[name] = (JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary)["passes"]
	var picked := choose(runs, most)
	var paths: Array = MwSimDict.leaves(MwSimDict.to_dict(MwRinkState.new())).keys()
	var index := {}
	for i in paths.size():
		index[paths[i]] = i
	var entries := []
	var covered := {}
	for name in RUNS:
		var mine: Array = picked.filter(func(p: Array) -> bool: return p[0] == name)
		if mine.is_empty():
			continue
		var rec := MwSimRecording.open(name)
		mine.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
		for p in mine:
			var k: int = p[1]
			entries.append(_entry(rom, rec, k, p[2], paths, index))
			for x in p[2]:
				covered[x] = true
	var feats := covered.keys()
	feats.sort()
	var lineups := []
	for c in LINEUPS:
		var rec := MwSimRecording.open(c[0])
		if rec != null:
			lineups.append(_lineup(rom, rec, c[1], paths, index))
	var sha := ""
	if not entries.is_empty():
		sha = MwSimRecording.open(RUNS[0]).meta["rom_sha1"]
	var doc := {
		"format": "mw-sim-passes/1",
		"note": "Simulation segment passes from tools/bin/sim-fixture (decoded fields only).",
		"rom_sha1": sha,
		"features": feats,
		"paths": paths,
		"passes": entries,
		"lineups": lineups,
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	print("%d passes, %d features, %d paths -> %s (%d bytes)" % [entries.size(), feats.size(), paths.size(),
			ProjectSettings.globalize_path(OUT).simplify_path(), FileAccess.get_file_as_bytes(OUT).size()])


static func _pairs(changes: Dictionary, index: Dictionary) -> Array:
	var out := []
	for path in changes:
		out.append([index[path], changes[path]])
	return out


static func _entry(rom: PackedByteArray, rec: MwSimRecording, k: int, feats: Array, paths: Array, index: Dictionary) -> Dictionary:
	var start := rec.start(k)
	var s0 := MwRinkRam.decode(rom, start)
	var d0 := MwSimDict.to_dict(s0)
	var start_leaves := MwSimDict.leaves(d0)
	var values := []
	for p in paths:
		values.append(start_leaves.get(p))
	var d1 := MwSimDict.to_dict(MwRinkRam.decode(rom, rec.end(k)))
	var thinks := []
	var ai: Array = rec.passes[k]["ai"]
	var i := 0
	while i + 1 < ai.size():
		var a5 := int(ai[i][1]) & 0xFFFFFF
		var pre := MwRinkRam.decode(rom, start)
		MwRinkRam.decode_into(rom, pre, rec.ai(int(ai[i][2])))
		var post := MwRinkRam.decode(rom, start)
		MwRinkRam.decode_into(rom, post, rec.ai(int(ai[i + 1][2])))
		var who := Vector2i(-1, -1)
		for t in 2:
			for j in 6:
				if MwRinkRam.player_address(t, j) == a5:
					who = Vector2i(t, j)
		thinks.append([who.x, who.y, _pairs(MwSimDict.diff(MwSimDict.to_dict(pre), MwSimDict.to_dict(post)), index)])
		i += 2
	var ent := []
	for e in rec.log_entries("ent", k):
		ent.append(int(e[MwReplayControl.ENT_TICK]))
	var tk := []
	for e in rec.log_entries("tk", k):
		tk.append([int(e[0]), int(e[1])])
	var pk: Variant = null
	var pl := rec.log_entries("pk", k)
	if not pl.is_empty():
		pk = int(pl[0][1])
	return {"run": rec.name, "pass": k, "e": rec.elapsed(k), "features": feats, "start": values,
			"end": _pairs(MwSimDict.diff(d0, d1), index), "thinks": thinks, "ent": ent, "tk": tk, "pk": pk}


## A line-up case: the setup (pass 0) or the state before (the previous
## pass's end), the screen it enters, and the leaves the original had then.
static func _lineup(rom: PackedByteArray, rec: MwSimRecording, k: int, paths: Array, index: Dictionary) -> Dictionary:
	var re := RegEx.create_from_string(LINEUP_LEAVES)
	var want := MwSimDict.leaves(MwSimDict.to_dict(MwRinkRam.decode(rom, rec.start(k))))
	var expect := []
	for p in want:
		if re.search(p):
			expect.append([index[p], want[p]])
	var screen := 4
	for en in rec.meta["screens"]:
		if int(en[0]) == k and int(en[1]) in [4, 5]:
			screen = int(en[1])
	var out := {"run": rec.name, "pass": k, "screen": screen, "expect": expect,
			"spot": MwRinkRam.u8(rec.start(k), MwRinkRam.FACEOFF_SPOT)}
	if k == 0:
		var su: Dictionary = rec.meta["setup"]
		out["setup"] = {"stadium": int(su.get("0xffb0e4", 0)), "team_a": int(su["0xffb0de"]), "team_b": int(su["0xffb0df"]),
				"pads": int(su["0xffb0e0"]), "reserves": int(su.get("0xffb0e6", 0)), "death_index": int(su.get("0xffb0e7", 0))}
	else:
		var before := MwSimDict.leaves(MwSimDict.to_dict(MwRinkRam.decode(rom, rec.end(k - 1))))
		var values := []
		for p in paths:
			values.append(before.get(p))
		out["before"] = values
	return out
