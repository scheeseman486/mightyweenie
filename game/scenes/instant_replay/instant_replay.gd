extends MwBetweenPlays
## Screen 7, the instant replay (plan 11; [MwReplaySim] around
## [MwInstantReplay]): the replay ring of the game's state (the rink's
## [MwRinkState] in [code]session.screens["rink"][/code], recorded by the
## rink passes) played back frame by frame. Plane B is the rink map
## (rink_load's `$4BE6`, picture `$24CFC`; its high-priority cells - the
## near boards and crowd - on PlaneBHigh above the low sprites) shown at
## each drawn frame's camera point; the window holds the A/B/C widget and
## its texts (all priority cells: WindowHigh); the sprites are the frame's
## records (and its hazards) through [MwScreenDraw], the info plates' tiles
## built in RAM from the markers the frames leave ([MwPlate]). The palette
## is the rink's (`$215E` with line 3 from `$1BD8A`). A pass that draws no
## frame leaves everything as it is (the original's sprite list stays
## uploaded and the planes keep their scroll).
##
## Live play: the pause menu's A (rink -> 7 -> 6, play continues) or a
## scoreboard's C (-> 7 -> back to that scoreboard). Run on its own, a demo
## match plays some seconds with the CPU's AI to fill the ring.
##
## Saved replays (plan 34): from the REPLAYS page (118) with a file
## ([code]data["replay_file"][/code], [MwReplayFile]): the file's match -
## its state at the end, its stadium and teams - and its whole recording,
## played from the first frame on (the replay's own verbs: rewind, slow,
## play, faster with A or C held); Start or Back go back to the page. A
## file that no longer opens goes straight back.
##
## In 3D (plan 20, the session's view, F1-F8 here too): each drawn frame's
## 3D frame (MwReplay3D, kept beside the ring by the rink passes) is shown
## through the Router's 3D view (MwRink3DHost) with the rink's cameras, as
## in play, blending to it over the time until the next frame (play, slow
## motion and rewind alike); its screen-space pieces show on the sprite
## layers, the widget stays in the window. A frame without a 3D frame shows
## in 2D. The hazards are the recorded ones (the 2D replay draws the
## recorded kinds at their live points, as the original).

## rink_load's plane B map (`$4BE6` with `$24D08`: picture `$24CFC`'s
## map, its size in cells at the picture's +8 / +$A).
const RINK_MAP := 0x24D08
## Demo: rink passes of 2 ticks in open play recorded before the replay.
const DEMO_PASSES := 150

var _frame_3d := {}         # the 3D frame of the frame drawn last (MwReplay3D)
var _scroll := Vector2.ZERO  # plane B's camera point (the frame drawn last)
var _list_2d: Array = []     # its 2D sprite list
var _shown_3d := false      # it was presented in 3D
## Plan 34: the saved replay's file ("" the match's), what it opened to
## (MwReplayFile.open: {} none), and whether it failed to open.
var saved_path := ""
var _saved := {}
var _refused := false


## Live play: the pause menu leaves its last read in the pads (`$48FC`'s
## loop runs read_joypads: the pausing pad's A), which picks the
## controlling pad; the rink scene keeps only the pausing pad's answer, so
## it is put back here. A scoreboard's sim keeps its own reads.
func _enter_screen(data: Dictionary) -> void:
	saved_path = str(data.get("replay_file", ""))
	if saved_path != "":
		_saved = MwReplayFile.open(saved_path)
		_refused = _saved.is_empty()
	if session != null and previous >= 0 and previous <= 6:
		var live := session.screens.get("rink") as MwRinkState
		if live != null:
			for p in live.pads_new.size():
				live.pads_new[p] = 0
			live.pads_new[(live.pause_pad >> 1) % live.pads_new.size()] = MwInstantReplay.NEW_A
	# plan 25: the wide picture is taken before the first pass, which draws
	# (presents) the replay's first frame - after it, that frame kept the
	# original's layout in a wide window until the next frame was drawn, and
	# the replay waits paused on it for the player's input
	if MwRom.available():
		MwRink3DHost.of(get_tree()).wide_for(self, MwSettings.wide())
	super._enter_screen(data)


## A saved replay's match (plan 34): the file's state; a file that failed
## to open, a match of its own (the screen leaves at once).
func _match_state() -> MwRinkState:
	if not _saved.is_empty():
		return _saved["state"]
	if _refused:
		return super._demo_state()
	return super._match_state()


func _stadium(su: MwMatchSetup) -> int:
	return (_saved["state"] as MwRinkState).stadium if not _saved.is_empty() else super._stadium(su)


## A saved replay's frames for the sim, and where it leaves for.
func _sim_made() -> void:
	var rs := sim as MwReplaySim
	if rs == null or saved_path == "":
		return
	if not _saved.is_empty():
		rs.saved = (_saved["state"] as MwRinkState).full_replay
	rs.leave_to = MwScreens.REPLAYS


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if _refused and not _leaving:
		_leaving = true
		exit_to(MwScreens.REPLAYS)
		return
	super._screen_pass(elapsed, input)


## Draws what the pass asked for: plane B's map and scroll ([member
## MwScreenSim.plane_ops] "rink" / "scroll"), the window's operations, and -
## only when a frame was drawn (plane_ops is then not empty) - the new
## sprite list with the plates' RAM tiles; the events.
func _draw_pass() -> void:
	for op in sim.plane_ops:
		match str(op[0]):
			"rink":
				painter_b.paint([rink_map_op(rom)], state)
			"scroll":
				_scroll = Vector2(int(op[1]), int(op[2]))
				plane_b.position = -_scroll
				plane_b.high_cells.position = -_scroll
			_:
				push_warning("instant replay: unknown plane B operation %s" % str(op[0]))
	painter_w.paint(sim.window_ops, state)
	if not sim.plane_ops.is_empty():
		var rs := sim as MwReplaySim
		_frame_3d = rs.replay.frame_3d() if rs and rs.replay else {}
		var crowd: Dictionary = _frame_3d.get("crowd", {})
		if MwCrowdLife.drives_sound and not crowd.is_empty():
			MwSound.crowd_level(MwCrowdLife.sound_level(crowd))     # plan 31: the noise the frame had
		_list_2d = drawer.list(state, sim.sprite_ops)
		_present(true)
	for ev in sim.events:
		_event(ev)


## The frame drawn last, in the view shown: the 2D sprite list over plane
## B, or its 3D frame through the 3D view. [param new_frame]: a frame was
## just drawn (it blends from the one before in 3D); false: the same frame
## again (a view picked).
func _present(new_frame: bool) -> void:
	var tiles := plate_tiles(rom, state)
	var three := MwRinkViews.is_3d(view()) and _frame_3d.has("items")
	for n: CanvasItem in [$Backdrop, plane_b, plane_b.high_cells]:
		n.visible = not three
	var host := MwRink3DHost.of(get_tree()) if three else MwRink3DHost.existing(get_tree())
	var list: Array
	if three:
		var rink_view := MwRinkPresenter.view_3d(host, self, palette, view(), MwRinkViews.across_of(session))
		rink_view.present_frame(_frame_3d, tiles, new_frame and _shown_3d)
		var rs := sim as MwReplaySim
		# rendered frames blend towards it until the next one
		rink_view.pass_shown(rs.replay.wait if rs and rs.replay else 1)
		host.show_for(self, true)
		list = MwRink3DHost.screen_list(host, _frame_3d["screen"], _frame_3d["screen_no_arrows"],
				_frame_3d.get("arrows", []), MwRinkViews.shows_arrows(view()), rom, _frame_3d.get("pieces", []))
	else:
		if host != null:
			host.show_for(self, false)
		list = _list_2d
		var at := -_scroll
		MwRinkPresenter.backdrop_fit($Backdrop as Control, host, self)
		if MwRinkPresenter.wide(host, self):
			# plan 25: the wide picture, as the rink's: the rink slides inside its
			# picture, the frame as drawn live (its pieces; else the records moved)
			var w := MwRinkPresenter.wide_place(host, Vector2i(_scroll), rom)
			var size: Vector2i = w["size"]
			var off: Vector2i = w["off"]
			var slide: Vector2i = w["slide"]
			at += Vector2(slide)
			if _frame_3d.has("pieces"):
				var piece_drawer := MwRinkDraw3D.new(rom)
				piece_drawer.pieces = _frame_3d["pieces"]
				list = piece_drawer.wide_list(size, off, slide, _frame_3d.get("arrows", []))
			else:
				var moved := drawer.adds.map(func(a: Array) -> Array:
					return [int(a[0]) + slide.x, int(a[1]) + slide.y, a[2], a[3], a[4]])
				var o := MwRinkDraw.SPRITE_ORIGIN
				list = MwRinkDraw.list_of(rom, moved, Vector2i(MwRinkDraw.CLIP_MIN - off.x, o + size.x - off.x),
						0x7FFFFFFF,
						Vector2i(MwRinkDraw.CLIP_MIN - off.y, o + size.y - off.y))
		plane_b.position = at
		plane_b.high_cells.position = at
	if not painter_w.overlays.is_empty():
		list = list.duplicate()
		for g in painter_w.overlays:              # the widget's button glyphs (plan 23), in front
			list.push_front(MwRinkDraw.glyph_entry(g[0], g[1], g[2]))
	MwRinkPresenter.show_list([sprites_low, sprites_high], tiles, list)
	_shown_3d = three


## The view shown (MwRinkViews; the session's setting).
func view() -> int:
	return MwRinkViews.view_of(session)


func _unhandled_input(event: InputEvent) -> void:
	var v := MwRinkViews.picked(event, view(), true, MwRinkViews.extended_of(session))
	if v < 0:
		return
	get_viewport().set_input_as_handled()
	MwRinkViews.select(session, v)          # (without a session: MwRinkViews.lone_view)
	if sim != null and state != null:
		_present(false)


func _exit_tree() -> void:
	var rs := sim as MwReplaySim
	var full := rs.replay as MwFullReplayPlayback if rs != null else null
	if full != null and full.paint != null:
		full.paint.stop()                          # its worker thread done before the ROM's view changes
	var host := MwRink3DHost.existing(get_tree())
	if host != null:
		host.release(self)
	if _saved.get("view", false):
		MwCustomTeams.rebuild()                    # plan 38: the bank's view again (plan 45: whenever open showed one)


## The rink map as a plane operation (["map", map, stride, w, h, x, y]):
## the whole picture from cell (0, 0); the camera point moves the plane.
static func rink_map_op(rom_: PackedByteArray) -> Array:
	var w := MwGfx.u16(rom_, MwRinkUpdate.MAP + 8)
	var h := MwGfx.u16(rom_, MwRinkUpdate.MAP + 0xA)
	return ["map", RINK_MAP, w, w, h, 0, 0]


## The info plates' VRAM tiles (`$FFBE80` + 256 * slot -> VRAM tile `$5F4`
## + 8 * slot) from the state's plate values, as the rink scene builds
## them: tile index -> 32 bytes (MwPlate.ram_tiles).
static func plate_tiles(rom_: PackedByteArray, s: MwRinkState) -> Dictionary:
	return MwPlate.ram_tiles(rom_, s.plates)


## Run on its own: the demo match ([method demo_replay_state]).
func _demo_state() -> MwRinkState:
	return demo_replay_state(rom, super._demo_state())


## [param s] (a match set up) after a faceoff and [constant DEMO_PASSES]
## passes of open play with the CPU's AI, the replay recording on, then
## left for the replay (`rink_exit` with 7: the open frame dropped) - or
## wherever the phase handler went first.
static func demo_replay_state(rom_: PackedByteArray, s: MwRinkState) -> MwRinkState:
	var rink := MwRinkSim.new(rom_, s)
	_demo_play(rink, s)
	rink.dispose()                           # plan 45: done with it (its cycle would keep the state)
	return s


## [method demo_replay_state]'s play: [param rink] on [param s] from the
## faceoff to the replay, or wherever the phase handler went first.
static func _demo_play(rink: MwRinkSim, s: MwRinkState) -> void:
	rink.cpu = MwRinkAI.new()
	var up := MwRinkUpdate.new(rink)
	MwReplay3D.use(up)                       # the 3D frames beside the ring (plan 20)
	var ph := MwRinkPhases.new(up)
	if ph.enter(5) >= 0:
		return
	var played := 0
	for i in 600:
		if up.run_pass(2, ph) >= 0:              # the rink's own pass (plan 40)
			return                               # left the rink (rink_exit done)
		if s.phase == MwRinkState.PHASE_PLAY:
			played += 1
			if played >= DEMO_PASSES:
				break
	MwRinkMatch.rink_exit(rink, 7)
