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

## The view without a session (the scene run on its own).
static var _view := MwRinkViews.FLAT

var _frame_3d := {}         # the 3D frame of the frame drawn last (MwReplay3D)
var _list_2d: Array = []     # its 2D sprite list
var _shown_3d := false      # it was presented in 3D


## Live play: the pause menu leaves its last read in the pads (`$48FC`'s
## loop runs read_joypads: the pausing pad's A), which picks the
## controlling pad; the rink scene keeps only the pausing pad's answer, so
## it is put back here. A scoreboard's sim keeps its own reads.
func _enter_screen(data: Dictionary) -> void:
	if session != null and previous >= 0 and previous <= 6:
		var st := session.screens.get("rink") as MwRinkState
		if st != null:
			for p in 4:
				st.pads_new[p] = 0
			st.pads_new[(st.pause_pad >> 1) & 3] = MwInstantReplay.NEW_A
	super._enter_screen(data)


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
				var at := Vector2(-int(op[1]), -int(op[2]))
				plane_b.position = at
				plane_b.high_cells.position = at
			_:
				push_warning("instant replay: unknown plane B operation %s" % str(op[0]))
	painter_w.paint(sim.window_ops, state)
	if not sim.plane_ops.is_empty():
		var rs := sim as MwReplaySim
		_frame_3d = MwReplay3D.at(state.replay, int(rs.replay.shown.get("at", -1))) if rs and rs.replay else {}
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
	var three := MwRinkViews.is_3d(view()) and not _frame_3d.is_empty()
	for n: CanvasItem in [$Backdrop, plane_b, plane_b.high_cells]:
		n.visible = not three
	var host := MwRink3DHost.of(get_tree()) if three else MwRink3DHost.existing(get_tree())
	var list: Array
	if three:
		var v := host.borrow(self, palette)
		v.set_camera_mode(MwRinkViews.camera_mode(view(), session.birds_eye_across if session else false))
		v.present_frame(_frame_3d, tiles, new_frame and _shown_3d)
		var rs := sim as MwReplaySim
		v.pass_frame = Engine.get_physics_frames()     # rendered frames blend towards it ...
		v.pass_ticks = maxi(rs.replay.wait if rs and rs.replay else 1, 1)   # ... until the next one
		v.auto_blend = true
		host.show_for(self, true)
		list = _frame_3d["screen" if MwRinkViews.shows_arrows(view()) else "screen_no_arrows"]
	else:
		if host != null:
			host.show_for(self, false)
		list = _list_2d
	for layer in [sprites_low, sprites_high]:
		layer.ram_tiles = tiles
		layer.show_list(list)
	_shown_3d = three


## The view shown (MwRinkViews; the session's setting).
func view() -> int:
	return session.view if session else _view


func _unhandled_input(event: InputEvent) -> void:
	var v := MwRinkViews.picked(event, view())
	if v < 0:
		return
	get_viewport().set_input_as_handled()
	if session:
		MwRinkViews.select(session, v)
	else:
		_view = v
	if sim != null and state != null:
		_present(false)


func _exit_tree() -> void:
	var host := MwRink3DHost.existing(get_tree())
	if host != null:
		host.release(self)


## The rink map as a plane operation (["map", map, stride, w, h, x, y]):
## the whole picture from cell (0, 0); the camera point moves the plane.
static func rink_map_op(rom_: PackedByteArray) -> Array:
	var w := MwGfx.u16(rom_, MwRinkUpdate.MAP + 8)
	var h := MwGfx.u16(rom_, MwRinkUpdate.MAP + 0xA)
	return ["map", RINK_MAP, w, w, h, 0, 0]


## The info plates' VRAM tiles (`$FFBE80` + 256 * slot -> VRAM tile `$5F4`
## + 8 * slot) from the state's plate values, as the rink scene builds
## them: tile index -> 32 bytes.
static func plate_tiles(rom_: PackedByteArray, s: MwRinkState) -> Dictionary:
	var tiles := {}
	for slot in 4:
		var v: Array = s.plates[slot]
		var b := MwPlate.tiles(rom_, v[0], v[1], v[2])
		for n in 8:
			tiles[MwRinkDraw.PLATE_TILES + 8 * slot + n] = b.slice(32 * n, 32 * n + 32)
	return tiles


## Run on its own: the demo match ([method demo_replay_state]).
func _demo_state() -> MwRinkState:
	return demo_replay_state(rom, super._demo_state())


## [param s] (a match set up) after a faceoff and [constant DEMO_PASSES]
## passes of open play with the CPU's AI, the replay recording on, then
## left for the replay (`rink_exit` with 7: the open frame dropped) - or
## wherever the phase handler went first.
static func demo_replay_state(rom_: PackedByteArray, s: MwRinkState) -> MwRinkState:
	var rink := MwRinkSim.new(rom_, s)
	rink.cpu = MwRinkAI.new()
	var up := MwRinkUpdate.new(rink)
	MwReplay3D.use(up)                       # the 3D frames beside the ring (plan 20)
	var ph := MwRinkPhases.new(up)
	if ph.enter(5) >= 0:
		return s
	var played := 0
	for i in 600:
		s.tick = (s.tick + 2) & 0xFFFFFFFF
		up.pass_start(2)
		rink.run(2)
		up.after_segment(2)
		if ph.pass_end(2) >= 0:
			return s                             # left the rink (rink_exit done)
		up.draws([], MwRinkPhases.RULES_DRAWN, ph.overlays, ph.sprite_ops)
		if s.phase == MwRinkState.PHASE_PLAY:
			played += 1
			if played >= DEMO_PASSES:
				break
	MwRinkMatch.rink_exit(rink, 7)
	return s
