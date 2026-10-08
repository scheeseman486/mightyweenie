extends "res://test/rom/rom_test_base.gd"
## The rink pass between two simulation segments (MwRinkUpdate) and the
## rink entries (MwRinkPhases.enter: MwRinkMatch.enter, with the CPU line
## changes and special plays at the line-up) against the original
## (compare/fixtures/rink_gaps.json from `tools/bin/pass-check --fixture`;
## decoded fields only). Each gap starts from the state at the end of a
## recorded segment, runs the rest of that pass (the update, the puck rules
## and the phase handler: MwRinkPhases) and the next pass's start with the
## ticks the original read (and the sound driver's voice answers), and must
## end with every field the original had at the next segment's start. Each
## entry starts from the state just before the entry (after rink_exit and
## what the screens in between changed) and must end as the original's
## first pass started.


## Game text in the fixture by ROM address.
const RomText := preload("res://test/sim/rom_text.gd")
var fx: Dictionary
var paths: Array


## The tick the original read at each live read, in order; the voice
## answers, a new voice's handle, the pause menu's answer.
class Ticks extends RefCounted:
	var list: Array = []
	var at := 0
	var voices: Array = []
	var handle := 0
	var pause := 0
	var _v := 0

	func tick_at(up: MwRinkUpdate, _tag: int) -> void:
		if at < list.size():
			up.s.tick = int(list[at][1])
			at += 1

	func voice_poll(_ph: MwRinkPhases, _h: int) -> int:
		var v := int(voices[_v]) if _v < voices.size() else 0
		_v += 1
		return v

	func voice_handle(_ph: MwRinkPhases, _id: int) -> int:
		return handle

	func pause_result(_ph: MwRinkPhases) -> int:
		return pause


func before_all() -> void:
	super.before_all()
	fx = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_gaps.json")))
	paths = fx["paths"]
	# the quote buffer's text is stored as ROM pieces (rom_text.gd)
	if MwRom.available():
		var idx := RomText.text_indices(paths)
		for g in fx["gaps"]:
			RomText.values_in(MwRom.data(), g, "start", idx)
			RomText.changes_in(MwRom.data(), g, "end", idx)
		for c in fx["entries"]:
			RomText.values_in(MwRom.data(), c, "before", idx)
			RomText.changes_in(MwRom.data(), c, "end", idx)


## A state from leaf values along the fixture's path list.
func _state(values: Array) -> MwRinkState:
	var d := MwSimDict.to_dict(MwRinkState.new())
	var changes := {}
	for i in paths.size():
		changes[paths[i]] = values[i]
	MwSimDict.patch_dict(d, changes)
	return MwSimDict.from_dict(d)


## "path want/got" for every leaf of [param s] that differs from [param
## start] patched with [param end] ([[path index, value], ...]); the tick
## counter is the VBlank's.
func _differences(s: MwRinkState, start: Array, end: Array) -> Array:
	var want := {}
	for i in paths.size():
		want[paths[i]] = start[i]
	for c in end:
		want[paths[int(c[0])]] = c[1]
	var got := MwSimDict.leaves(MwSimDict.to_dict(s))
	var out := []
	for p in want:
		if p == "tick":
			continue
		var w: Variant = want[p]
		var g: Variant = got.get(p)
		var same: bool = (int(w) == int(g)) if (w is float or w is int) and (g is float or g is int) else w == g
		if not same:
			out.append("%s %s/%s" % [p, str(w), str(g)])
	return out


func _pads(s: MwRinkState, pads: Array) -> void:
	for p in 4:
		s.pads_held[p] = int(pads[2 * p])
		s.pads_new[p] = int(pads[2 * p + 1])


func test_fixture_covers_the_gaps_and_entries() -> void:
	var feats := {}
	for g in fx["gaps"]:
		for f in g["features"]:
			feats[f] = true
	for f in ["throw", "fire", "shark", "under_ice", "pit", "lamp", "clock", "replay", "impale_record", "arrow"]:
		assert_true(feats.has(f), "a gap with %s" % f)
	var kinds := {}
	for e in fx["entries"]:
		for f in e["features"]:
			kinds[f] = true
	for f in ["screen 4", "screen 5", "fight", "direct", "line change", "goalie roll", "special play"]:
		assert_true(kinds.has(f), "an entry with %s" % f)


func test_gaps_end_as_the_original() -> void:
	if not need_rom():
		return
	var failed := 0
	for g in fx["gaps"]:
		var s := _state(g["start"])
		for h in g["ring"]:                       # the oldest frames' headers (the ring's data is not recorded)
			s.replay.ring_bytes[int(h[0])] = (int(h[1]) >> 8) & 0xFF
			s.replay.ring_bytes[int(h[0]) + 1] = int(h[1]) & 0xFF
		var sim := MwRinkSim.new(rom, s)
		var up := MwRinkUpdate.new(sim)
		var ph := MwRinkPhases.new(up)
		var ticks := Ticks.new()
		ticks.list = g["ticks"]
		ticks.voices = g["voices"]
		ticks.handle = int(g["handle"])
		ticks.pause = int(g["pause"])
		up.hooks = ticks
		ph.hooks = ticks
		up.after_segment(int(g["e"]))
		assert_eq(ph.pass_end(int(g["e"])), -1, "the rink is not left")
		up.draws([], MwRinkPhases.RULES_DRAWN, ph.overlays)
		s.tick = int(g["pass_tick"])
		up.pass_start(int(g["e_next"]))
		_pads(s, g["pads"])
		var d := _differences(s, g["start"], g["end"])
		if not d.is_empty():
			failed += 1
			fail_test("%s pass %d (%s): %d fields differ: %s" % [g["run"], g["pass"], ", ".join(g["features"]), d.size(),
					", ".join(d.slice(0, 6))])
	assert_eq(failed, 0, "%d gaps as the original" % ((fx["gaps"] as Array).size() - failed))


func test_entries_as_the_original() -> void:
	if not need_rom():
		return
	for c in fx["entries"]:
		var s := _state(c["before"])
		var sim := MwRinkSim.new(rom, s)
		var up := MwRinkUpdate.new(sim)
		# entered one tick before the first pass starts (it waits for a VBlank)
		s.tick = int(c["pass_tick"]) - 1
		var to := MwRinkPhases.new(up).enter(int(c["screen"]))
		assert_eq(to, -1, "no forfeit")
		# the faceoff set-up reads the tick before rink_load's loading time
		s.puck.take_tick = int(c["take_tick"])
		s.tick = int(c["pass_tick"])
		up.pass_start(int(c["e_next"]))
		_pads(s, c["pads"])
		var d := _differences(s, c["before"], c["end"])
		assert_eq(d.size(), 0, "%s entry %d (screen %d: %s): %s" % [c["run"], c["pass"], c["screen"], ", ".join(c["features"]),
				", ".join(d.slice(0, 8))])


func test_replay_ring_drops_the_oldest_frames() -> void:
	var r := MwRinkState.ReplayRing.new()
	r.reset()
	var sizes := []
	for i in 300:                                 # frames of 2 + 2 * (i % 50) words + trailer
		r.open_frame(3)
		for w in i % 50:
			r.put_long(0x01020304)
		r.close_frame()
		sizes.append(2 + 4 * (i % 50) + 2)
		assert_true(r.used <= MwRinkState.ReplayRing.SIZE, "never over the size")
	# what is held: the newest frames that fit, read back by their headers
	var held := 0
	var n := 0
	var at := r.read
	while held < r.used:
		var h := (r.ring_bytes[at] << 8) | r.ring_bytes[at + 1]
		assert_eq(h & 7, 3, "header: elapsed ticks")
		held += 2 + ((h >> 3) & 0xFFFE)
		at = (at + 2 + ((h >> 3) & 0xFFFE)) % MwRinkState.ReplayRing.SIZE
		n += 1
	assert_eq(held, r.used, "frames fill the used bytes exactly")
	assert_eq(n, r.frames, "frame count")
	var tail := 0
	for i in n:
		tail += sizes[sizes.size() - 1 - i]
	assert_eq(tail, r.used, "the newest frames are kept")
	# an open frame given up leaves the ring as it was
	var was := [r.write, r.used, r.frames]
	r.open_frame(20)
	r.put_long(5)
	r.abandon_frame()
	assert_eq([r.write, r.used, r.frames], was, "abandoned")
	r.open_frame(20)
	r.close_frame()
	var h2 := (r.ring_bytes[was[0]] << 8) | r.ring_bytes[(was[0] + 1) % MwRinkState.ReplayRing.SIZE]
	assert_eq(h2, 0xF | (2 << 3), "elapsed capped at 15, length 2 bytes")
