extends "res://test/rom/rom_test_base.gd"
## Plan 34: saved replays (MwReplayFile) - the file and its header, the
## names, another ROM's file refused, 3D frames another format wrote played
## in 2D, the end of a match's question, the recorded demos and their limit,
## the REPLAYS page (118) and screen 7's saved variant.

const NONE := [0, 0, 0, 0]
const C := MwInstantReplay.NEW_C
const START := MwInstantReplay.START
const FRAMES := 12
## A clock for the names: 2026-10-09 21:14:05 UTC.
const CLOCK := 1791580445.0

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var s: MwRinkState
var up: MwRinkUpdate
var record_frame := 0
var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad
var _dir := ""
var _front := true


func before_all() -> void:
	super.before_all()
	_dir = MwReplayFile.dir
	_front = MwSettings.front_menu
	MwSettings.front_menu = true


func after_all() -> void:
	MwReplayFile.dir = _dir
	MwReplayFile.clock = -1.0
	MwSettings.front_menu = _front


func before_each() -> void:
	MwReplayFile.dir = "user://test_replays_%d" % Time.get_ticks_usec()
	MwReplayFile.clock = CLOCK
	if rom.is_empty():
		return
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	var sim := MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 4, 9, 4, 0, false, 2)
	up = MwRinkUpdate.new(sim)
	MwRinkPhases.new(up).enter(5)
	s.tick = 1000
	s.teams[0].score = 3
	s.teams[1].score = 2
	record_frame = MwGfx.u32(rom, MwReplaySim.HAZARD_FRAMES)
	s.full_replay = MwFullReplay.new()
	s.replay.reset()
	for k in FRAMES:
		_record_frame(k)


func after_each() -> void:
	if host:
		rig.free_host()
		host = null
	var d := DirAccess.open(MwReplayFile.dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwReplayFile.dir))


func _record_frame(k: int, store := s.full_replay) -> void:
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
	store.add(s.replay, start, {"shown": Vector2(_cam(k))})     # as MwRinkUpdate.draws


static func _cam(k: int) -> Vector2i:
	return Vector2i(40 + 10 * k, 200 + 30 * k)


func _header(mode := "exhibition") -> Dictionary:
	var session := MwSession.new()
	session.setup.team_a = 9
	session.setup.team_b = 4
	return MwReplayFile.header_for(session, s, mode)


# --- the file -------------------------------------------------------------------------------------

func test_a_saved_match_reads_back_frame_for_frame() -> void:
	if not need_rom():
		return
	var path := MwReplayFile.save(s, _header())
	assert_ne(path, "", "written")
	var h := MwReplayFile.header_of(path)
	assert_eq([h["mode"], h["score"], h["team_a"], h["team_b"], h["stadium"], h["frames"]],
			["exhibition", [3, 2], 9, 4, s.stadium, FRAMES], "the header")
	assert_eq(int(h["ticks"]), 2 * FRAMES, "each frame's recorded pass length")
	assert_eq(h["rom_sha1"], RomArchive.MLH_SHA1)
	var got := MwReplayFile.open(path)
	assert_false(got.is_empty(), "opens")
	assert_true(got["sides"], "its 3D frames this build's")
	var state: MwRinkState = got["state"]
	assert_eq([state.teams[0].record, state.teams[1].record, state.stadium, state.teams[0].score],
			[s.teams[0].record, s.teams[1].record, s.stadium, 3], "the match's state")
	for i in FRAMES:
		assert_eq(state.full_replay.words(i), s.full_replay.words(i), "frame %d's words" % i)
		assert_eq(state.full_replay.side(i).get("shown"), Vector2(_cam(i)), "frame %d's 3D frame" % i)


## Plan 38: a match at a custom rink - between original teams too - keeps
## the custom teams' view (online the host's, in use for the match), so it
## plays back at that rink once the bank has changed.
func test_a_custom_rinks_match_keeps_the_view() -> void:
	if not need_rom():
		return
	var team := MwCustomTeam.from_original(MwRom.archive().bytes(), 9)
	team.rink.gravity = -40
	MwCustomTeams.teams.append(team)
	MwCustomTeams.rebuild()
	s.stadium = MwTeams.COUNT
	var h := _header()
	assert_true(maxi(h["team_a"], h["team_b"]) < MwTeams.COUNT, "original teams")
	assert_false((h["custom_view"] as Dictionary).is_empty(), "the view kept for the custom rink")
	var path := MwReplayFile.save(s, h)
	var view := MwRom.overlay()
	MwCustomTeams.clear()                                  # the bank changed since
	assert_eq(MwRom.overlay().size(), 0)
	var got := MwReplayFile.open(path)
	assert_false(got.is_empty(), "opens")
	assert_eq(MwRom.overlay(), view, "the custom rink as it was")
	assert_eq(MwGfx.s8(MwRom.data(), MwRinkState.stadium_record(MwRom.data(), MwTeams.COUNT) + 8), -40, "its gravity")
	MwCustomTeams.clear()


func test_the_3d_frames_cross_chunks() -> void:
	if not need_rom():
		return
	var store := MwFullReplay.new()
	for k in MwFullReplay.CHUNK + 20:
		_record_frame(k % 40, store)
	assert_eq(store.chunks.size(), 1, "a chunk closed every CHUNK frames")
	var back := MwFullReplay.from_data(store.to_data())
	for i in [0, MwFullReplay.CHUNK - 1, MwFullReplay.CHUNK, MwFullReplay.CHUNK + 19, 5]:
		assert_eq(back.side(i).get("shown"), Vector2(_cam(i % 40)), "frame %d" % i)
		assert_eq(store.side(i).get("shown"), Vector2(_cam(i % 40)), "frame %d live" % i)


func test_names_never_clash() -> void:
	if not need_rom():
		return
	var paths := []
	for i in 3:
		paths.append(MwReplayFile.save(s, _header()).get_file())
	assert_eq(paths.size(), 3)
	assert_ne(paths[0], paths[1])
	assert_ne(paths[1], paths[2])
	assert_ne(paths[0], paths[2])
	var t := MwPortMenu.local_time(int(CLOCK))
	var day := "%04d-%02d-%02d_%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute]
	assert_true(paths[0].begins_with(day + "_exhibition_"), paths[0])
	assert_true(paths[1].begins_with(day + "%02d_" % t.second), "the second one: with its seconds")
	assert_true(paths[2].begins_with(day + "%02d-2_" % t.second), "the third: a number")
	for p in paths:
		assert_true(p.ends_with(MwReplayFile.EXT))
		assert_eq(p, p.to_lower(), "file-safe")
		assert_false(" " in p, "file-safe")


func test_another_roms_file_is_refused() -> void:
	if not need_rom():
		return
	var h := _header()
	h["rom_sha1"] = "0".repeat(40)
	var path := MwReplayFile.save(s, h)
	assert_eq(MwReplayFile.open(path), {}, "refused")
	var listed := MwReplayFile.list()
	assert_eq(listed.size(), 1, "listed")
	assert_false(listed[0]["ok"], "as unreadable")


func test_another_formats_3d_frames_play_in_2d() -> void:
	if not need_rom():
		return
	var h := _header()
	h["side_format"] = MwReplayFile.SIDE_FORMAT + 1
	var got := MwReplayFile.open(MwReplayFile.save(s, h))
	assert_false(got["sides"])
	assert_eq(got["state"].full_replay.size(), FRAMES, "the frames all there")
	assert_eq(got["state"].full_replay.side(3), {}, "in 2D")


func test_a_damaged_file_is_refused() -> void:
	if not need_rom():
		return
	var path := MwReplayFile.save(s, _header())
	var b := FileAccess.get_file_as_bytes(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b.slice(0, b.size() - 40))
	f.close()
	assert_eq(MwReplayFile.open(path), {})


func test_nothing_recorded_saves_nothing() -> void:
	if not need_rom():
		return
	s.full_replay = MwFullReplay.new()
	assert_eq(MwReplayFile.save(s, _header()), "")


# --- the question at a match's end ----------------------------------------------------------------

func test_the_question_comes_once_a_match_when_it_ends() -> void:
	if not need_rom():
		return
	var session := MwSession.new()
	assert_true(MwBetweenPlays.asks_replay(session, 15, 1, s), "the game over, on to the game setup")
	assert_true(MwBetweenPlays.asks_replay(session, 16, 11, s), "a playoff game over, on to the bracket")
	assert_false(MwBetweenPlays.asks_replay(session, 15, 7, s), "not for the replay (it comes back)")
	assert_false(MwBetweenPlays.asks_replay(session, 15, 8, s), "nor the stats")
	assert_false(MwBetweenPlays.asks_replay(session, 14, 4, s), "not at a period's end")
	session.attract = true
	assert_false(MwBetweenPlays.asks_replay(session, 15, 1, s), "not in the attract demo")
	session.attract = false
	MwSettings.front_menu = false
	assert_false(MwBetweenPlays.asks_replay(session, 15, 1, s), "not in the original's flow")
	MwSettings.front_menu = true
	s.full_replay = MwFullReplay.new()
	assert_false(MwBetweenPlays.asks_replay(session, 15, 1, s), "not with nothing recorded")


func test_the_game_over_asks_then_saves_and_goes_on() -> void:
	if not need_rom():
		return
	var session := MwSession.new()
	session.local_mode = "exhibition"
	session.screens["rink"] = s
	_router(session)
	_adopt(15)
	var board := router.current() as MwBetweenPlays
	board._leaving = true
	board._ask_replay(1)
	assert_true(board.replay_question.active, "SAVE REPLAY?")
	assert_eq(board.replay_question.sure, 1, "NO first")
	_press("ui_up")
	_press("ui_accept")
	assert_false(board.replay_question.active)
	var listed := MwReplayFile.list()
	assert_eq(listed.size(), 1, "saved")
	assert_eq(listed[0]["header"]["mode"], "exhibition")
	assert_true(_until(1), "then on to the game setup")


func test_no_saves_nothing() -> void:
	if not need_rom():
		return
	var session := MwSession.new()
	session.screens["rink"] = s
	_router(session)
	_adopt(16)
	var board := router.current() as MwBetweenPlays
	board._leaving = true
	board._ask_replay(11)
	_press("ui_accept")
	assert_eq(MwReplayFile.list().size(), 0, "nothing written")
	assert_true(_until(11), "on to the bracket")


# --- demos -----------------------------------------------------------------------------------------

func test_demos_are_kept_without_a_question_the_newest_ten() -> void:
	if not need_rom():
		return
	var session := MwSession.new()
	var short := MwRinkState.new()
	short.teams = s.teams
	short.full_replay = MwFullReplay.new()
	assert_eq(MwReplayFile.save_demo(session, short), "", "nothing recorded: not kept")
	assert_eq(MwReplayFile.save_demo(session, s), "", "under 10 s of play: not kept")
	for k in MwReplayFile.DEMO_MIN_TICKS / 2:
		_record_frame(k % 30)
	var first := MwReplayFile.save_demo(session, s)
	assert_ne(first, "", "10 s: kept")
	assert_eq(MwReplayFile.header_of(first)["mode"], "demo")
	assert_true(MwReplayFile.keep(first), "KEEP")
	for i in MwReplayFile.DEMOS_KEPT + 2:
		MwReplayFile.clock = CLOCK + 60 * (i + 1)
		assert_ne(MwReplayFile.save_demo(session, s), "")
	var demos := MwReplayFile.list()
	assert_eq(demos.size(), MwReplayFile.DEMOS_KEPT + 1, "the newest ten, and the kept one")
	assert_true(demos.any(func(e: Dictionary) -> bool: return e["path"] == first), "the kept one stays")
	assert_eq(int(demos[0]["header"]["time"]), int(CLOCK) + 60 * (MwReplayFile.DEMOS_KEPT + 2), "newest first")
	assert_false(MwReplayFile.keep(MwReplayFile.save(s, _header())), "KEEP is a demo's")


# --- the page and screen 7 -------------------------------------------------------------------------

func test_the_page_lists_plays_deletes_and_keeps() -> void:
	if not need_rom():
		return
	var match_path := MwReplayFile.save(s, _header())
	MwReplayFile.clock = CLOCK + 60
	var demo_path := MwReplayFile.save(s, _header("demo"))
	var session := MwSession.new()
	_router(session)
	_adopt(MwScreens.REPLAYS)
	var page := router.current() as MwPortMenu
	assert_eq(page.rows.size(), 2)
	assert_eq(page.rows[0].path, demo_path, "newest first")
	assert_true(MwPortMenu.replay_detail(page.rows[0].info).contains("DEMO"))
	_press("ui_keep")
	assert_true(MwReplayFile.header_of(demo_path)["kept"], "KEEP on the demo")
	assert_true(MwPortMenu.replay_detail(page.rows[0].info).contains("KEPT"))
	_press("ui_down")
	_press("ui_keep")
	assert_false(MwReplayFile.header_of(match_path).has("kept") and MwReplayFile.header_of(match_path)["kept"],
			"refused on a match")
	_press("ui_delete")
	assert_true(page.confirm.active, "ARE YOU SURE?")
	_press("ui_up")
	_press("ui_accept")
	assert_false(FileAccess.file_exists(match_path), "deleted")
	assert_eq(page.rows.size(), 1)
	assert_eq(page.row, 0)
	_press("ui_accept")
	assert_true(_until(7), "accept plays it on screen 7")
	var rp := (router.current() as MwBetweenPlays).sim as MwReplaySim
	assert_not_null(rp.saved, "the file's frames")
	assert_true(rp.replay.play, "playing (from the first frame: below)")
	_run(4 * FRAMES)
	assert_eq(rp.replay.shown["camera"], _cam(FRAMES - 1), "on to the last")
	_press("replay_exit")
	assert_true(_until(MwScreens.REPLAYS), "Start: back to the page")


func test_the_saved_playback_shows_the_in_game_frames() -> void:
	if not need_rom():
		return
	var got := MwReplayFile.open(MwReplayFile.save(s, _header()))
	var state: MwRinkState = got["state"]
	var rp := MwReplaySim.new(rom)
	rp.saved = state.full_replay
	rp.leave_to = MwScreens.REPLAYS
	rp.enter(state, 7, MwScreens.REPLAYS)
	var seen := [rp.replay.shown["camera"]]
	for i in 6 * FRAMES:
		state.tick += 1
		rp.begin_pass()
		rp.step(1, NONE, NONE)
		if rp.replay.shown["camera"] != seen[-1]:
			seen.append(rp.replay.shown["camera"])
	var want := []
	for k in FRAMES:
		want.append(_cam(k))
	assert_eq(seen, want, "every frame, in order")
	assert_eq(rp.replay.frame_3d().get("shown"), Vector2(_cam(FRAMES - 1)), "with its 3D frame")
	state.tick += 1
	rp.begin_pass()
	var n := NONE.duplicate()
	n[0] = START
	assert_eq(rp.step(1, NONE, n), MwScreens.REPLAYS, "Start: the page")


# --- helpers ---------------------------------------------------------------------------------------

func _router(session: MwSession) -> void:
	router = rig.make(self, session)
	host = rig.host
	pad = rig.pad


func _adopt(id: int, data := {}) -> void:
	var scene := MwRouter.instantiate_scene(id)
	scene.screen_id = id
	router.adopt(scene, data)
	router.fader.uncover()


func _run(ticks: int) -> void:
	rig.run(ticks)


func _press(action: String, after := 10) -> void:
	rig.hold({action: true, "p1_" + action: true}, 3, after)


func _until(id: int, limit := 900) -> bool:
	return rig.until(id, limit, 20)
