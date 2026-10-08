class_name MwRink
extends MwPlaceholderScreen
## Screens 4, 5 and 6: the rink (docs/re/rink.md). Drawn like the original
## from an [MwRinkState]: the rink picture as plane B (its high-priority
## cells - the near boards and crowd - as a second layer in front of the
## players), the draw pass's sprite list in two sprite layers, the clock
## widget in the window plane, the stadium's palette (`screen_palette` lines
## 0-2, line 3 `$1BD8A`, constant during play), and the camera moving the
## planes and sprites.
##
## Live play runs a rink pass as the original (MwRinkUpdate's pass start,
## the pads the players' verbs make (MwGameplayPads), the simulation
## segment (MwRinkSim) with the CPU players' AI (MwRinkAI), the rest of the
## update, the puck rules and phase handler (MwRinkPhases), the draw pass)
## and follows the screens the phase handler leaves for (12 after a goal,
## 14 at a period's end, 18 a fight, 5 after a stoppage, 15 / 16 game over,
## 7 / 10 from the pause menu...). Start pauses (the pause menu: the game
## stands still until the pad that paused answers). In the attract demo
## any input, or the demo's first exit, returns to the main menu.
## A recorded match of the original (`mw_harness rink-dump` ->
## out/rink/dec/*.json) can be played back instead ([member playback_file]
## or the entry data's "playback").
##
## Views of the same play (plans 14 and 20, docs/rink3d.md): the original's
## 2D (default) and the 3D rink (MwRinkView3D) through seven cameras
## (MwRinkViews), picked any time with F1-F8 or stepped through with a pad's
## Back button (not gameplay verbs, the simulation never sees them) and kept
## across screens 4-6 ([member MwSession.view]). The views that look another
## way than the 2D turn the pads' directions with the camera (MwLiveInput,
## [method _update_turns]). Both show the same draw pass: the
## simulation's drawer is an MwRinkDraw3D, whose sprite list is the
## original's and which also places every frame in the world. The 3D view
## is the Router's (MwRink3DHost, plan 20: built at launch, kept for the
## whole run, behind the screens); in 3D the planes and the 2D sprite layers
## hide, the screen-space pieces show in ScreenLow / ScreenHigh, and the
## window scales its 2D content as canvas items so the 3D view renders
## every window pixel (as the proof scene does). Entered in 2D, the rink
## primes the view once with its first pass, unseen, so the first switch
## shows at once.

## A recording to play back (absolute path), empty = live.
@export var playback_file := ""

@onready var plane_low: RomTileMapLayer = $PlaneLow
@onready var plane_high: RomTileMapLayer = $PlaneHigh
@onready var sprites_low: MwSpriteLayer = $SpritesLow
@onready var sprites_high: MwSpriteLayer = $SpritesHigh
@onready var window: RomPlane = $Window
@onready var palette: RomPalette = $Backdrop.palette
@onready var screen_low: MwSpriteLayer = $ScreenLow
@onready var screen_high: MwSpriteLayer = $ScreenHigh

## The settings without a session (a rink scene run on its own).
static var _view := MwRinkViews.FLAT
static var _across := false

var rom: PackedByteArray
var state: MwRinkState
var sim: MwRinkSim
var update: MwRinkUpdate
var phases: MwRinkPhases
var drawer: MwRinkDraw
var painter: MwWindowPainter
var _playback: Array = []
var _play_at := 0
var _play_ticks := 0
var _phase_adds: Array = []
var _exiting := false
var _pass_frame := 0     # the physics frame of the latest pass, and its ticks (3D blending)
var _pass_len := 1
var _shown_3d := false   # the latest pass was presented in 3D


func _enter_screen(data: Dictionary) -> void:
	super._enter_screen(data)
	if not MwRom.available():
		return
	rom = MwRom.data()
	drawer = MwRinkDraw3D.new(rom)
	painter = MwWindowPainter.new(window, rom)
	var su := session.setup if session else MwMatchSetup.new()
	palette.screen = screen_id
	palette.team_a = su.team_a
	palette.team_b = su.team_b
	palette.stadium = su.stadium
	# the rink follows its own exits (MwRinkPhases), the attract demo's end included
	exits = {}
	attract_role = Attract.NONE
	var file: String = data.get("playback", playback_file)
	if file != "" and FileAccess.file_exists(file):
		_playback = (JSON.parse_string(FileAccess.get_file_as_string(file)) as Dictionary).get("passes", [])
	if not _playback.is_empty():
		var first: Dictionary = _playback[0]["state"]
		palette.team_a = int(first.get("team_a", su.team_a))
		palette.team_b = int(first.get("team_b", su.team_b))
		palette.stadium = int(first.get("stadium", su.stadium))
		_show_recorded(0)
	else:
		_live_entry(su, data)
	_present(false, true)


## The live state (kept in the session across screens 4-6): a new match
## from the matchup (`$3698` / `$3700`: teams on the ice), a faceoff at a
## period start and after a stoppage (`$AB2C`), play continuing after a
## pause-menu replay.
func _live_entry(su: MwMatchSetup, data: Dictionary) -> void:
	state = session.screens.get("rink") as MwRinkState if session else null
	var new_match: bool = data.get("new_match", state == null or previous == 3 or state.stadium != su.stadium)
	var last := state
	if new_match:
		state = MwRinkState.new()
		if last != null:                    # the ref icons live from power-on (MwRinkMatch.boot_icons)
			state.penalty = last.penalty
			state.stoppage = last.stoppage
	if session:
		session.screens["rink"] = state
		state.rng = session.rng                 # one main stream (`$FFB096`)
	sim = MwRinkSim.new(rom, state)
	sim.live = true                          # the sound calls reach the driver (plan 12)
	sim.cpu = MwRinkAI.new()                 # CPU players think as the original's (`$3BFE`)
	update = MwRinkUpdate.new(sim)
	MwReplay3D.use(update)                   # the original's sprite list, placed in the world too; 3D replay frames
	phases = MwRinkPhases.new(update)
	if new_match and last == null:
		MwRinkMatch.boot_icons(sim)
	if new_match:
		# the matchup's set-up (`$B2B0`): the clock, the stadium, the rink and the teams
		var setup := su.copy()
		setup.period_minutes = maxi(su.period_minutes, 1)
		MwRinkMatch.matchup_setup(sim, setup, session.playoffs.series if session else 0)
		su.stadium = setup.stadium              # the playoffs: the home team's (written back as `$B2F0`)
		palette.stadium = su.stadium
	state.period_minutes = maxi(su.period_minutes, 1)
	state.period_row = su.period_index
	state.penalties = su.penalties
	state.play_mode = su.play_mode
	state.fight_block = 1 if session != null and session.attract else 0   # `$FFCA1C`: the attract demo
	if session:
		state.playoffs = session.playoffs
	if entry == "faceoff":
		state.faceoff_spot = int(data.get("faceoff_spot", state.faceoff_spot))
	var screen := 4 if entry == "period_start" else (5 if entry == "faceoff" else 6)
	var to := phases.enter(screen)
	painter.paint(phases.window_ops, state)    # `rink_load`'s cleared window, the clock widget
	state.camera.update(rom, 0, null)
	if to >= 0:
		_leave(to)


## Leaving live play for [param id] (the phase handler's exit: `rink_exit`
## is done); the attract demo's end restores the setup (`$45E4`).
func _leave(id: int) -> void:
	if session != null and session.attract and id == 1:
		id = session.attract_return               # the port's front menu if it started the demo
		session.end_attract()
	exit_to(id)


func exit_to(id: int, data := {}, fade := true, ticks := -1) -> void:
	if _exiting:
		return
	_exiting = true
	super.exit_to(id, data, fade, ticks)


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	super._screen_pass(elapsed, input)
	if rom.is_empty():
		return
	if not _playback.is_empty():
		_play_ticks += elapsed
		while _play_at + 1 < _playback.size() and _play_ticks >= int(_playback[_play_at + 1]["e"]):
			_play_ticks -= int(_playback[_play_at + 1]["e"])
			_play_at += 1
		_show_recorded(_play_at)
	elif not _exiting:
		_live_pass(elapsed, input)
	_pass_frame = Engine.get_physics_frames()
	_pass_len = maxi(elapsed, 1)
	_present()


## One gameplay pass: its start (MwRinkUpdate: pass counter, clock), the
## pads (players 1-4 on pads 0-3), the segment, the rest of the rink update
## (objects, camera, crowd...), the puck rules and the phase handler, the
## draw pass. While the pause menu is open (`$48FC`'s busy loop) the game
## stands still: the tick counter runs and the pad that paused answers.
func _live_pass(elapsed: int, input: MwInputFrame) -> void:
	state.tick += elapsed
	if phases.paused:
		var r := MwGameplayPads.read(input, (state.pause_pad >> 1) + 1)
		var to := phases.pause_press(int(r["new"]))
		painter.paint(phases.window_ops, state)
		_handled(to)
		return
	update.pass_start(elapsed)
	painter.paint(update.window_ops, state)    # the clock's texts (`$261C`)
	for pad in 4:
		var r := MwGameplayPads.read(input, pad + 1)
		state.pads_held[pad] = r["held"]
		state.pads_new[pad] = r["new"]
		sim.human.direct[pad] = r["direct"]
	sim.run(elapsed)
	update.after_segment(elapsed)
	var to := phases.pass_end(elapsed)
	painter.paint(phases.window_ops, state)    # the phase handler's texts (or the pause menu)
	_handled(to)


## After the phase handler: paused (nothing more this pass), leaving, or
## the draw pass (the handler's overlays included).
func _handled(to: int) -> void:
	if to == MwRinkPhases.PAUSED:
		return
	if to >= 0:
		_leave(to)
		return
	update.draws(_phase_adds, MwRinkPhases.RULES_DRAWN, phases.overlays, phases.sprite_ops)


func _show_recorded(i: int) -> void:
	var p: Dictionary = _playback[i]
	state = MwRinkState.from_dict(rom, p["state"])
	_phase_adds = p.get("phase_adds", [])
	var c: Variant = p["state"].get("clock")
	if c != null:
		var pp := int(c["powerplay"]) if int(c["flags"]) & 1 else -1
		MwClockHud.erase(window, true)
		if int(c["flags"]) & 2:                 # `$B077` bit 1: the widget is up
			MwClockHud.draw(window, rom, int(c["period"]), int(c["seconds"]), pp)


## The draw pass into the view shown: the sprite layers and the planes at
## the camera, or the 3D view (live: the list and placements the pass's draws
## made). [param continuous]: this pass follows the one shown before (the 3D
## view blends from it). [param prime]: in 2D, prime the 3D view with it.
func _present(continuous := true, prime := false) -> void:
	var drawn := _drawn()
	var list: Array = drawn[0]
	var d: MwRinkDraw3D = drawn[1]
	var tiles := _plate_tiles()
	var three := view_3d() and d != null
	_show_view(three)
	if three:
		var v := _host().borrow(self, palette)
		v.set_camera_mode(MwRinkViews.camera_mode(view(), birds_eye_across()))
		v.present(state, d, tiles, continuous and _shown_3d)
		v.pass_frame = _pass_frame             # rendered frames blend towards this pass
		v.pass_ticks = _pass_len
		v.auto_blend = true
		var screen := d.screen_sprites(not MwRinkViews.shows_arrows(view()))
		for layer in [screen_low, screen_high]:
			layer.ram_tiles = tiles
			layer.show_list(screen)
	else:
		for layer in [sprites_low, sprites_high]:
			layer.ram_tiles = tiles
			layer.show_list(list)
		var at := Vector2(-state.camera.shown)
		plane_low.position = at
		plane_high.position = at
		if prime and d != null:
			_prime_3d(d, tiles)
	_shown_3d = three
	_update_turns()


## The pass's sprite list and the drawer that placed it in the world (live:
## the list the pass's draws made; otherwise drawn now).
func _drawn() -> Array:
	if _playback.is_empty() and update != null and update.s == state and not update.sprites.is_empty():
		return [update.sprites, update.drawer as MwRinkDraw3D]
	return [drawer.build(state, _phase_adds), drawer as MwRinkDraw3D]


## The info plates' RAM tiles of the state shown.
func _plate_tiles() -> Dictionary:
	var tiles := {}
	for slot in 4:
		var v: Array = state.plates[slot]
		var b := MwPlate.tiles(rom, v[0], v[1], v[2])
		for n in 8:
			tiles[MwRinkDraw.PLATE_TILES + 8 * slot + n] = b.slice(32 * n, 32 * n + 32)
	return tiles


## Entered in 2D: the 3D view (if built yet) shows this first pass once,
## unseen, under the fade (once per run: its sprite textures and materials
## stay), so the first switch to 3D shows at once (plan 20).
func _prime_3d(d: MwRinkDraw3D, tiles: Dictionary) -> void:
	var host := MwRink3DHost.existing(get_tree())
	if host == null or not host.is_built() or host.primed or host.user != null:
		return
	host.borrow(self, palette).present(state, d, tiles, false)
	host.prime()


# --- the 3D view (plan 14) ---------------------------------------------------------------------

## The view shown (MwRinkViews; the session's setting).
func view() -> int:
	return session.view if session else _view


## The birds-eye view's layout: the goals left and right (true).
func birds_eye_across() -> bool:
	return session.birds_eye_across if session else _across


## True when the rink shows in 3D.
func view_3d() -> bool:
	return MwRinkViews.is_3d(view())


## Shows view [param v] (MwRinkViews); the birds-eye view picked again
## switches its layout. The view picked shows the current pass at once.
func select_view(v: int) -> void:
	if session:
		MwRinkViews.select(session, v)
	else:
		v = posmod(v, MwRinkViews.COUNT)
		if v == MwRinkViews.BIRDS_EYE and _view == v:
			_across = not _across
		_view = v
	if not rom.is_empty() and state != null:
		_present(false)


func _unhandled_input(event: InputEvent) -> void:
	var v := MwRinkViews.picked(event, view())
	if v >= 0:
		get_viewport().set_input_as_handled()
		select_view(v)


## The pads' turns for the view shown (MwLiveInput.turns): every pad by the
## view's turn, player 1's by the camera's heading in first person; none
## while paused (the pause menu reads the pads as they are), in playback, or
## once the rink is leaving.
func _update_turns() -> void:
	var t := 0
	var first := 0
	if view_3d() and not _exiting and _playback.is_empty() and (phases == null or not phases.paused):
		t = MwRinkViews.turn(view(), birds_eye_across())
		first = t
		if view() == MwRinkViews.FIRST_PERSON:
			var host := MwRink3DHost.existing(get_tree())
			if host != null and host.is_built():
				first = host.view().camera.turn_eighths()
	MwLiveInput.turns = PackedInt32Array([first, t, t, t])


func _host() -> MwRink3DHost:
	return MwRink3DHost.of(get_tree())


## Shows the 3D view (the host's, the screen-space layers) or the 2D one
## (the backdrop, planes and sprite layers).
func _show_view(three: bool) -> void:
	for n: CanvasItem in [$Backdrop, plane_low, plane_high, sprites_low, sprites_high]:
		n.visible = not three
	for n: CanvasItem in [screen_low, screen_high]:
		n.visible = three
	var host := MwRink3DHost.existing(get_tree()) if not three else _host()
	if host == null:
		return
	if three and not host.shown_for(self):
		host.borrow(self, palette)
		for layer: MwSpriteLayer in [screen_low, screen_high]:
			layer.palette = palette
	host.show_for(self, three)


func _exit_tree() -> void:
	MwLiveInput.turns = PackedInt32Array([0, 0, 0, 0])
	var host := MwRink3DHost.existing(get_tree())
	if host != null:
		host.release(self)
