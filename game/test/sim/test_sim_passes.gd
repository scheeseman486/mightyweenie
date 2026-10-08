extends "res://test/rom/rom_test_base.gd"
## The simulation segment (MwRinkSim) against passes of the original
## (compare/fixtures/sim_passes.json, from tools/bin/sim-fixture): each
## pass from its recorded start state with the recorded CPU thinks and tick
## reads must end with every field the original had; and the set-up,
## line-up and period change against the original's state at a new match,
## after stoppages and at period starts.

var fx: Dictionary
var paths: Array


func before_all() -> void:
	super.before_all()
	fx = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/sim_passes.json")))
	paths = fx["paths"]


## A state from leaf values along the fixture's path list.
func _state(values: Array) -> MwRinkState:
	var d := MwSimDict.to_dict(MwRinkState.new())
	var changes := {}
	for i in paths.size():
		changes[paths[i]] = values[i]
	MwSimDict.patch_dict(d, changes)
	return MwSimDict.from_dict(d)


## "path want/got" for the leaves of [param s] that differ from [param want]
## ([[path index, value], ...] or {path: value}).
func _differences(s: MwRinkState, want: Dictionary, skip: Array = []) -> Array:
	var got := MwSimDict.leaves(MwSimDict.to_dict(s))
	var out := []
	# The plates are RAM tiles: values that draw the same (LD / RD both
	# show "D") are the same plate.
	for slot in 4:
		var w := []
		var g := []
		for i in 3:
			w.append(int(want.get("plates/%d/%d" % [slot, i], got["plates/%d/%d" % [slot, i]])))
			g.append(int(got["plates/%d/%d" % [slot, i]]))
		if MwPlate.tiles(rom, w[0], w[1], w[2]) == MwPlate.tiles(rom, g[0], g[1], g[2]):
			for i in 3:
				skip = skip + ["plates/%d/%d" % [slot, i]]
	for p in want:
		if p in skip:
			continue
		var w: Variant = want[p]
		var g: Variant = got.get(p)
		var same: bool = (int(w) == int(g)) if (w is float or w is int) and (g is float or g is int) else w == g
		if not same:
			out.append("%s %s/%s" % [p, str(w), str(g)])
	return out


func test_fixture_covers_the_segment() -> void:
	assert_gt((fx["passes"] as Array).size(), 30)
	var feats: Array = fx["features"]
	for f in ["ph:3", "ph:4", "ph:14", "pk:+1", "pk:+40", "pk:+80", "tk:1", "tk:2", "tk:3", "chg", "new:10", "new:20", "new:40", "hold", "think"]:
		assert_has(feats, f, "a pass with %s" % f)


func test_passes_end_as_the_original() -> void:
	if not need_rom():
		return
	var failed := 0
	for entry in fx["passes"]:
		var start: Array = entry["start"]
		var s := _state(start)
		var sim := MwRinkSim.new(rom, s)
		var ctl := MwFixtureControl.new(paths, entry)
		sim.cpu = ctl
		sim.hooks = ctl
		sim.run(int(entry["e"]))
		var want := {}
		for i in paths.size():
			want[paths[i]] = start[i]
		for c in entry["end"]:
			want[paths[int(c[0])]] = c[1]
		var d := _differences(s, want, ["tick"])
		if not d.is_empty() or not ctl.notes.is_empty():
			failed += 1
			fail_test("%s pass %d (%s): %d fields differ: %s %s" % [entry["run"], entry["pass"], ", ".join(entry["features"]),
					d.size(), ", ".join(d.slice(0, 6)), ctl.notes])
	assert_eq(failed, 0, "%d passes as the original" % ((fx["passes"] as Array).size() - failed))


func test_setup_lineup_and_period_change_as_the_original() -> void:
	if not need_rom():
		return
	for c in fx["lineups"]:
		var s: MwRinkState
		if c.has("setup"):
			s = MwRinkState.new()
		else:
			s = _state(c["before"])
		var sim := MwRinkSim.new(rom, s)
		if c.has("setup"):
			var su: Dictionary = c["setup"]
			MwRinkMatch.start(sim, int(su["stadium"]), int(su["team_a"]), int(su["team_b"]), int(su["pads"]),
					int(su["reserves"]) != 0, int(su["death_index"]))
		else:
			if int(c["screen"]) == 4:
				MwRinkMatch.period_end(sim)
			MwRinkMatch.rink_exit(sim, int(c["screen"]))
		MwRinkMatch.faceoff(sim, int(c["spot"]))
		var want := {}
		for e in c["expect"]:
			want[paths[int(e[0])]] = e[1]
		# Who of a two-pad team gets which pad is a random draw before the
		# line-up (the RNG then is not recorded): compare the human count.
		var skip := []
		for t in 2:
			if s.teams[t].pads[0] != 0xFF and s.teams[t].pads[1] != 0xFF:
				var humans := 0
				var humans_want := 0
				for i in 6:
					var key := "teams/%d/players/%d/flags" % [t, i]
					skip.append(key)
					humans += int(s.teams[t].players[i].flags & 0xC != 0)
					humans_want += int(int(want.get(key, 0)) & 0xC != 0)
					if int(want.get(key, 0)) & ~0xC != s.teams[t].players[i].flags & ~0xC:
						fail_test("%s %d: %s other flags" % [c["run"], c["pass"], key])
				assert_eq(humans, humans_want, "%s %d team %d: humans" % [c["run"], c["pass"], t])
		var d := _differences(s, want, skip)
		assert_eq(d.size(), 0, "%s pass %d (screen %d, spot %d): %s" % [c["run"], c["pass"], c["screen"], c["spot"], ", ".join(d.slice(0, 8))])
