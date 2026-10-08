extends "res://test/rom/rom_test_base.gd"
## The screens between plays against the original, from recordings
## (compare/fixtures/screen_visits.json from `tools/bin/screen-check
## --fixture`; decoded fields only): each visit starts from the state at
## the screen's call, gets the original's ticks, pads and sound answers
## pass by pass, and must draw the original's random numbers after its
## set-up and every pass, leave for the original's screen and change the
## state as the original did. Screens 7 and 8 are tested from synthetic
## states (they need the replay ring's data and RAM the state does not
## hold).

const ScreenVisit := preload("res://test/sim/screen_visit.gd")
const RomText := preload("res://test/sim/rom_text.gd")

var fx: Dictionary
var paths: Array


func before_all() -> void:
	super.before_all()
	fx = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/screen_visits.json")))
	paths = fx["paths"]
	# the quote buffer's text is stored as ROM pieces (rom_text.gd)
	if MwRom.available():
		var idx := RomText.text_indices(paths)
		for c in fx["visits"]:
			RomText.values_in(MwRom.data(), c, "start", idx)
			RomText.changes_in(MwRom.data(), c, "end", idx)


## A state from leaf values along the fixture's path list.
func _state(values: Array) -> MwRinkState:
	var d := MwSimDict.to_dict(MwRinkState.new())
	var changes := {}
	for i in paths.size():
		changes[paths[i]] = values[i]
	MwSimDict.patch_dict(d, changes)
	return MwSimDict.from_dict(d)


func test_fixture_covers_the_screens() -> void:
	var seen := {}
	for c in fx["visits"]:
		seen[int(c["screen"])] = true
	for scr in [10, 12, 14, 15, 16, 17, 18, 19]:
		assert_true(seen.has(scr), "a visit of screen %d" % scr)


func test_visits_play_as_the_original() -> void:
	if not need_rom():
		return
	var rom := MwRom.data()
	for c in fx["visits"]:
		var what := "%s visit %d (screen %d)" % [c["run"], int(c["visit"]), int(c["screen"])]
		var problem := _play(rom, c)
		assert_eq(problem, "", what)


## One visit: "" when it plays as the original, else the first difference.
func _play(rom: PackedByteArray, c: Dictionary) -> String:
	var scr := int(c["screen"])
	var s := _state(c["start"])
	var entry: Array = c["entry"]
	s.tick = int(entry[0])
	var pads: Array = entry[1]
	for p in 4:
		s.pads_held[p] = int(pads[2 * p])
		s.pads_new[p] = int(pads[2 * p + 1])
	var sim := MwScreenSims.make(scr, rom)
	sim.hooks = ScreenVisit.Replayed.new(c["answers"])
	sim.enter(s, scr, int(c["from"]))
	var rngs: Array = c["rng"]
	if s.rng.state != int(rngs[0]):
		return "set-up: rng %08X, the original's %08X" % [s.rng.state, int(rngs[0])]
	var to := -1
	var passes: Array = c["passes"]
	for i in passes.size():
		var p: Array = passes[i]
		s.tick = int(p[0])
		var held := []
		var new := []
		for k in 4:
			held.append(int(p[2][k]))
			new.append(int(p[3][k]))
		sim.begin_pass()
		to = sim.step(int(p[1]), held, new)
		if s.rng.state != int(rngs[i + 1]):
			return "pass %d: rng %08X, the original's %08X" % [i, s.rng.state, int(rngs[i + 1])]
		if to >= 0:
			break
	if to != int(c["exit"]):
		return "left for %d, the original for %d" % [to, int(c["exit"])]
	var want := {}
	var values: Array = c["start"]
	for i in paths.size():
		want[paths[i]] = values[i]
	for e in c["end"]:
		want[paths[int(e[0])] if (e[0] is int or e[0] is float) else str(e[0])] = e[1]
	var got := MwSimDict.leaves(MwSimDict.to_dict(s))
	for path in want:
		if path == "tick":
			continue
		var w: Variant = want[path]
		var g: Variant = got.get(path)
		var same: bool = (int(w) == int(g)) if (w is float or w is int) and (g is float or g is int) else w == g
		if not same:
			return "at the end: %s %s, the original's %s" % [path, str(g), str(w)]
	return ""
