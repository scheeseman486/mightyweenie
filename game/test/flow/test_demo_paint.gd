extends "res://test/rom/rom_test_base.gd"
## The arena's paint in the demos and the replays (plan 37; owner: the demos
## show the blood / oil and the ice detail too, made again procedurally from
## a seed, the built-in demo from a single seed of its own): the attract demo
## paints from its own seed (MwSplatter.DEMO_SEED) and shows it in 3D; its
## saved replay, like any saved match, and the FULL GAME replay make the
## paint again from the recorded seed and inputs (MwSplatterReplay) - the
## same texels as the match at the same frame, played on, rewound, through
## screen 7; a file from before plays the ice's detail from a derived seed.
## The replays' paint is GAMEPLAY MODIFIERS' REPLAY BLOOD (MwSettings.replay_paint,
## off by default; owner, 2026-10-15): on here. A file's paint is made on a
## worker thread (MwSplatterReplay.Maker): the frames are checked once it has
## made them all ([method MwSplatterReplay.finish]; test_splatter.gd has the
## frames shown while it makes them).
## Short names: a the MwSplatterAtlas under test.

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var host: Node
var router: MwRouter
var rig := ScreenRig.new()
var pad: Pad
var _dir := ""
var _front := true
var _start_view := -1
var _replay_paint := false


func before_all() -> void:
	super.before_all()
	_dir = MwReplayFile.dir
	_front = MwSettings.front_menu
	_start_view = MwSettings.start_view
	_replay_paint = MwSettings.replay_paint
	MwSettings.front_menu = true          # (the demos are saved in the port's flow)
	MwSettings.replay_paint = true        # REPLAY BLOOD: the replays' paint under test


func after_all() -> void:
	MwReplayFile.dir = _dir
	MwSettings.front_menu = _front
	MwSettings.start_view = _start_view
	MwSettings.replay_paint = _replay_paint


func before_each() -> void:
	MwReplayFile.dir = "user://test_demo_paint_%d" % Time.get_ticks_usec()
	MwSettings.start_view = -1


func after_each() -> void:
	_free_router()
	MwSettings.start_view = -1
	var d := DirAccess.open(MwReplayFile.dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwReplayFile.dir))


func _free_router() -> void:
	if host:
		rig.free_host()
		host = null


## The attract demo from its matchup (the main menu's idle timeout leads
## there), the session's streams from [param seed_].
func _demo(seed_: int) -> void:
	_free_router()
	router = rig.make(self, MwSession.new(seed_, 0x1234567))
	host = rig.host
	router.session.attract = true             # (as the main menu leaves for it)
	pad = rig.pad
	var scene := MwRouter.instantiate_scene(3)
	scene.screen_id = 3
	router.adopt(scene, {})
	router.fader.uncover()


## Steps until the rink has played [param ticks] more ticks.
func _in_rink(ticks: int) -> MwRinkState:
	for i in 400:
		router.step()
		if router.current_id() == 4 and not router.busy():
			break
	assert_eq(router.current_id(), 4, "the demo's rink")
	for i in ticks:
		router.step()
	return router.session.screens["rink"] as MwRinkState


## Steps [param ticks] ticks, keeping the paint's digest and operations at
## each new frame of the match's recording (MwFullReplay index -> [digest,
## operations]) into [param live].
func _record(ticks: int, live: Dictionary) -> void:
	for i in ticks:
		router.step()
		var state := router.session.screens.get("rink") as MwRinkState
		if state == null or state.full_replay == null or state.splatter == null or router.current_id() != 4:
			continue
		var k := state.full_replay.size() - 1
		if k >= 0 and not live.has(k):
			live[k] = [state.splatter.atlas.digest(), state.splatter.atlas.count()]


func _floor(view: MwRinkView3D) -> ShaderMaterial:
	return view.model._materials["floor"] as ShaderMaterial


func test_the_attract_demo_shows_its_own_seed_s_paint_in_3d() -> void:
	if not need_rom():
		return
	MwSettings.start_view = MwRinkViews.FOLLOW
	_demo(0x61F2415D)
	var state := _in_rink(700)
	assert_true(router.session.attract)
	assert_not_null(state.splatter, "the paint")
	assert_eq(state.splatter.seed, MwSplatter.DEMO_SEED, "the demo's own seed")
	assert_gt(state.splatter.atlas.count(), MwSplatter.SPLOTCHES, "the ice's detail and the skates' since")
	var view := MwRink3DHost.existing(get_tree()).view()
	assert_eq(view.camera.mode, MwRinkCamera3D.Mode.FOLLOW, "in 3D")
	assert_same(view._paint, state.splatter.atlas, "the match's atlas on the model")
	assert_true(bool(_floor(view).get_shader_parameter("paint_on")), "the paint on the ice")
	assert_eq(_floor(view).get_shader_parameter("paint"), state.splatter.atlas.texture())
	var a := state.splatter.atlas
	a.seek(MwSplatter.SPLOTCHES)
	var ice := a.digest()
	a.seek(a.count())
	var crowd := state.crowd_life.crowd_seed
	assert_eq(ice, MwSplatter.new(MwSplatter.DEMO_SEED).atlas.digest(), "the ice as its seed makes it")
	# another demo (other teams, another crowd): the same seed, the same ice
	_demo(0x0BADCAFE)
	var st2 := _in_rink(20)
	assert_ne(st2.crowd_life.crowd_seed, crowd, "another crowd")
	assert_eq(st2.splatter.seed, MwSplatter.DEMO_SEED, "the same seed every time it runs")
	st2.splatter.atlas.seek(MwSplatter.SPLOTCHES)
	assert_eq(st2.splatter.atlas.digest(), ice, "the same ice")
	st2.splatter.atlas.seek(st2.splatter.atlas.count())


## The demo kept as its replay (plan 34) paints as the match did: the
## seed recorded, each frame's texels the live match's at that frame (played
## on, rewound, fast); the FULL GAME replay of the match going on shows the
## match's own atlas as it was; screen 7 playing the file in 3D shows it.
func test_a_saved_demo_paints_as_the_match_did() -> void:
	if not need_rom():
		return
	_demo(0x61F2415D)
	var live := {}
	_in_rink(0)
	_record(1500, live)
	var state := router.session.screens["rink"] as MwRinkState
	var frames := state.full_replay.size()
	assert_gt(frames, 300, "a demo's frames")
	assert_gt(int(live[frames - 1][1]), int(live[0][1]) + 100, "painted since its first frame")
	# the FULL GAME replay of the match going on: its own atlas
	var in_game := MwFullReplayPlayback.new(state, rom, state.full_replay)
	assert_same(in_game.paint.live, state.splatter, "the match's own")
	for k in [frames - 1, 40, 200, 3]:
		in_game.shown["at"] = k
		var g := in_game.frame_3d()
		var ga := g["splat"]["atlas"] as MwSplatterAtlas
		ga.seek(int(g["splat"]["ops"]))
		assert_eq(ga.digest(), live[k][0], "in game: frame %d as it was" % k)
	state.splatter.atlas.seek(state.splatter.atlas.count())
	# any input ends the demo; it is kept as a replay
	pad.held = {"p1_a": true, "a": true}
	for i in 3:
		router.step()
	pad.held = {}
	for i in 200:
		router.step()
		if router.current_id() == 1:
			break
	assert_false(router.session.attract, "the demo over")
	var files := MwReplayFile.list()
	assert_eq(files.size(), 1, "the demo kept")
	var path: String = files[0]["path"]
	assert_eq(files[0]["header"]["mode"], "demo")
	var got := MwReplayFile.open(path)
	assert_eq(got["paint"], "recorded")
	var saved: MwRinkState = got["state"]
	assert_null(saved.splatter, "no paint in the file's state")
	assert_eq(saved.full_replay.splat_seed, MwSplatter.DEMO_SEED, "its seed recorded")
	var pb := MwFullReplayPlayback.new(saved, rom, saved.full_replay)
	assert_null(pb.paint.live)
	assert_false(pb.paint.derived)
	pb.paint.finish()
	# on from the first frame (some skipped: fast), then back
	var order := [0, 1, 2, 10, 11, 40, 120, 121, frames - 1, 200, 3, 0, 150]
	for k: int in order:
		pb.shown["at"] = k
		var f := pb.frame_3d()
		var a := f["splat"]["atlas"] as MwSplatterAtlas
		assert_eq(int(f["splat"]["ops"]), int(live[k][1]), "frame %d: the match's operations" % k)
		a.seek(int(f["splat"]["ops"]))
		assert_eq(a.digest(), live[k][0], "frame %d: the match's texels" % k)
	# screen 7 plays the file in 3D: the paint on the model, the frame's
	MwSettings.start_view = MwRinkViews.FOLLOW
	router.session.view = MwRinkViews.FOLLOW
	router.go(7, {"replay_file": path})
	for i in 200:
		router.step()
		if router.current_id() == 7 and not router.busy():
			break
	assert_eq(router.current_id(), 7, "screen 7 plays the file")
	var rs := (router.current() as MwBetweenPlays).sim as MwReplaySim
	(rs.replay as MwFullReplayPlayback).paint.finish()
	for i in 60:
		router.step()
	var at := int(rs.replay.shown["at"])
	assert_gt(at, 5, "playing")
	var view := MwRink3DHost.existing(get_tree()).view()
	assert_not_null(view._paint, "the paint made again on the model")
	for i in 30:              # the rendered frames' blends seek it a share each (MwRinkView3D.PAINT_USEC)
		await wait_frames(1)
		if view._paint.shown() == view._paint_ops:
			break
	assert_true(bool(_floor(view).get_shader_parameter("paint_on")))
	assert_eq(view._paint.digest(), live[at][0], "frame %d as the match was" % at)


## A file from before the seed was kept (its 3D frames' paint an object's
## id, no inputs): it opens and plays, the ice's detail from a derived seed
## (the crowd's, which those builds painted from), no blood - and says so.
func test_an_older_file_plays_the_ice_from_a_derived_seed() -> void:
	if not need_rom():
		return
	_demo(0x13572468)
	_in_rink(700)
	var state := router.session.screens["rink"] as MwRinkState
	var crowd := state.crowd_life.crowd_seed
	var store := state.full_replay
	assert_gt(store.size(), 20)
	# the store as an older build wrote it: the atlas in each 3D frame (var_to_bytes:
	# the object's id), no inputs, no seed
	var old := MwFullReplay.new()
	for i in store.size():
		var d := MwFullReplay.side_to_data(store.side(i))
		if d.has("splat"):
			d["splat"].erase("in")
			d["splat"]["atlas"] = state.splatter.atlas
		old.frames.append(store.frames[i])
		var raw := var_to_bytes(d)
		old.side_at.append(old._open.size())
		old.side_len.append(raw.size())
		old._open.append_array(raw)
	var data := old.to_data()
	data.erase("splat_seed")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MwReplayFile.dir))
	var h := MwReplayFile.header_for(router.session, state, "demo")
	var path := MwReplayFile.dir.path_join("old.mwreplay")
	assert_true(MwReplayFile._write(path, h, var_to_bytes({"state": MwSimDict.to_dict(state), "replay": data})))
	var got := MwReplayFile.open(path)
	assert_false(got.is_empty(), "opens")
	assert_true(got["sides"], "in 3D")
	assert_eq(got["paint"], "derived", "says so")
	var saved: MwRinkState = got["state"]
	assert_eq(saved.full_replay.splat_seed, -1, "no seed kept")
	var pb := MwFullReplayPlayback.new(saved, rom, saved.full_replay)
	assert_true(pb.paint.derived)
	pb.paint.finish()
	assert_eq(pb.paint.seed, crowd, "the crowd's seed")
	var ice := MwSplatter.new(crowd).atlas.digest()
	for k in [0, store.size() - 1]:
		pb.shown["at"] = k
		var f := pb.frame_3d()
		var a := f["splat"]["atlas"] as MwSplatterAtlas
		a.seek(int(f["splat"]["ops"]))
		assert_eq(int(f["splat"]["ops"]), MwSplatter.SPLOTCHES, "frame %d: the ice's detail only" % k)
		assert_eq(a.digest(), ice, "frame %d: the ice as the match's seed makes it" % k)
