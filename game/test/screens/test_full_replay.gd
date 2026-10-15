extends "res://test/rom/rom_test_base.gd"
## Plan 28: the whole match's replay (MwFullReplay, MwFullReplayPlayback;
## REPLAY LENGTH: FULL GAME). Frames recorded as test_replay's, by the
## rink's own recording code, kept in the store as MwRinkUpdate.draws keeps
## them; a faceoff empties the ring between: the original's replay shows
## the frames since, the full one starts there and reaches back over the
## whole match. The ring is never touched.

const NONE := [0, 0, 0, 0]
const A := MwInstantReplay.NEW_A
const C := MwInstantReplay.NEW_C
const START := MwInstantReplay.START
## Before the faceoff, then after it (the ring's).
const BEFORE := 5
const AFTER := 3

var sim: MwRinkSim
var s: MwRinkState
var up: MwRinkUpdate
var record_frame := 0
var _was := ""


## CPU players that stay put (plan 40: test/support/idle_cpu.gd).
const Idle := preload("res://test/support/idle_cpu.gd")


func before_each() -> void:
	_was = MwSettings.replay_length
	MwSettings.replay_length = MwSettings.REPLAYS[0]
	if rom.is_empty():
		return
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = Idle.new()
	MwRinkMatch.start(sim, 4, 9, 4, 0, false, 2)
	up = MwRinkUpdate.new(sim)
	MwRinkPhases.new(up).enter(5)
	s.tick = 1000
	record_frame = MwGfx.u32(rom, MwReplaySim.HAZARD_FRAMES)
	s.full_replay = MwFullReplay.new()
	s.replay.reset()
	for k in BEFORE:
		_record_frame(k)
	s.replay.reset()                     # a faceoff (`$9CE8`): the ring emptied
	for k in range(BEFORE, BEFORE + AFTER):
		_record_frame(k)


func after_each() -> void:
	MwSettings.replay_length = _was


func _record_frame(k: int) -> void:
	s.camera.x = _cam(k).x << 8
	s.camera.y = _cam(k).y << 8
	s.camera.amp = 0
	for t in 2:
		var marker := s.teams[t].markers[0]
		marker.x = 10 * k + t
		marker.y = 5 * k
		marker.number = 10 + k
	up.replay_head(2)
	for i in k % 3 + 1:
		up.replay_sprite(0x80 + 8 * i, 0x90 + 2 * k, 0x100 + i, 0x08, record_frame)
	var start := s.replay.frame_start
	s.replay.close_frame()
	s.full_replay.add(s.replay, start, {"shown": Vector2(_cam(k))})     # as MwRinkUpdate.draws


static func _cam(k: int) -> Vector2i:
	return Vector2i(40 + 10 * k, 200 + 30 * k)


func _enter() -> MwReplaySim:
	s.pads_new[0] = A
	var rp := MwReplaySim.new(rom)
	rp.enter(s, 7, 4)
	return rp


func _step(rp: MwReplaySim, held := 0, new := 0) -> int:
	s.tick += 1
	var h := NONE.duplicate()
	var n := NONE.duplicate()
	h[0] = held
	n[0] = new
	rp.begin_pass()
	return rp.step(1, h, n)


func _shown(rp: MwReplaySim) -> int:
	return ((rp.replay.shown["camera"] as Vector2i).x - 40) / 10


func test_every_frame_is_kept_whatever_the_ring_drops() -> void:
	if not need_rom():
		return
	assert_eq(s.replay.frames, AFTER, "the ring: since the faceoff")
	assert_eq(s.full_replay.size(), BEFORE + AFTER, "the store: all of them")
	var w := s.full_replay.words(0)
	assert_eq(w[0], w[w.size() - 1], "a whole frame: the header repeated as its trailer")


func test_it_starts_where_the_original_does_and_rewinds_over_the_match() -> void:
	if not need_rom():
		return
	var ring := [s.replay.read, s.replay.used, s.replay.write, s.replay.frames, s.replay.ring_bytes.duplicate()]
	var rp := _enter()
	assert_true(rp.replay is MwFullReplayPlayback)
	assert_eq(_shown(rp), BEFORE, "the ring's oldest frame, as the original")
	for i in 400:
		_step(rp, A, A if i == 0 else 0)
		if _shown(rp) == 0:
			break
	assert_eq(_shown(rp), 0, "back to the match's first frame, before the faceoff")
	assert_eq(rp.replay.frame_3d().get("shown"), Vector2(_cam(0)), "its 3D frame")
	_step(rp, C, C)
	for i in 400:
		_step(rp)
		if _shown(rp) == BEFORE + AFTER - 1:
			break
	assert_eq(_shown(rp), BEFORE + AFTER - 1, "and on to the last")
	assert_eq(_step(rp, START, START), 6, "Start leaves, back to play")
	assert_eq([s.replay.read, s.replay.used, s.replay.write, s.replay.frames, s.replay.ring_bytes], ring,
			"the ring untouched")


func test_original_keeps_the_rings_reach() -> void:
	if not need_rom():
		return
	MwSettings.replay_length = "ORIGINAL"
	var rp := _enter()
	assert_false(rp.replay is MwFullReplayPlayback)
	for i in 200:
		_step(rp, A, A if i == 0 else 0)
	assert_eq(_shown(rp), BEFORE, "the ring's oldest is as far back as it goes")


func test_held_a_and_c_go_faster() -> void:
	assert_eq(MwFullReplayPlayback.extra_frames(0), 0)
	assert_eq(MwFullReplayPlayback.extra_frames(MwFullReplayPlayback.FAST_AFTER), 0, "the original's speeds first")
	assert_eq(MwFullReplayPlayback.extra_frames(MwFullReplayPlayback.FAST_AFTER + 1), 1, "then twice")
	assert_eq(MwFullReplayPlayback.extra_frames(MwFullReplayPlayback.FAST_AFTER + MwFullReplayPlayback.FAST_STEP), 3)
	assert_eq(MwFullReplayPlayback.extra_frames(100000), MwFullReplayPlayback.FAST_MAX - 1, "capped")


func test_a_3d_frame_survives_the_store() -> void:
	if not need_rom():
		return
	var passes: Array = JSON.parse_string(FileAccess.get_file_as_string(
			repo_path("compare/fixtures/rink_draw.json")))["passes"]
	var state := MwRinkState.from_dict(rom, passes[0]["state"])
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(state, passes[0]["phase_adds"])
	var side := MwReplay3D.frame(state, drawer)
	var store := MwFullReplay.new()
	state.replay.reset()
	state.replay.open_frame(2)
	var start := state.replay.frame_start
	state.replay.close_frame()
	store.add(state.replay, start, side)
	var back := store.side(0)
	assert_eq(str(back["items"]), str(side["items"]))
	assert_eq(back["pieces"], side["pieces"])
	assert_eq(back["shown"], side["shown"])
	var stored: MwRinkShot3D = side["shot"]
	var shot: MwRinkShot3D = back["shot"]
	assert_eq([shot.look, shot.puck, shot.players, shot.carrier, shot.phase, shot.score],
			[stored.look, stored.puck, stored.players, stored.carrier, stored.phase, stored.score])
	store.seal()
	assert_lt(store.chunks[0].size(), var_to_bytes(MwFullReplay.side_to_data(side)).size(), "compressed")
	assert_eq(str(store.side(0)["items"]), str(side["items"]), "read back from a closed chunk")
