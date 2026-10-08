extends MwBetweenPlays
## Screen 8, the game stats, with 9, the player stats, inside it (plan 11;
## [MwStatsSim]; the original's `$FFB05E` stays 8 while 9 runs, so the
## router never shows scenes/player_stats). What renders where:
## * plane B: the starfield ([RomStarfield], picture `$4546C`) at the sim's
##   starfield position ([member MwStatsSim.star], moved by the original's
##   VBlank task every tick); [code]$PlaneB[/code] stays empty (the sim's
##   [member MwScreenSim.plane_ops] are);
## * plane A ([code]$PlaneAClip/PlaneA[/code]): the stats rows (8) or a page
##   of the player stats (9's plane A text box) from [member
##   MwStatsSim.plane_a_ops], scrolled by [member MwStatsSim.scroll_a] and
##   shown below the window's rows only (the clip; the VDP shows the window
##   instead of plane A there);
## * the window: the title and team names (8) or 9's other text box, over
##   the top [member MwStatsSim.window_rows] rows (8: 9; 9: all or none -
##   the original's double buffer);
## * sprites: the team logos and the scroll arrows ([MwScreenDraw]
##   "piece"s); a pass that uploads no list (8's last) leaves the shown one;
## * palette: screen 8's (`screen_palette`, colour 0 black, the teams'
##   panel lines on lines 1 / 2; 9's set-up makes the same).
## 8's A and 9's Start switch screens within one sim pass: the scene fades
## out (32 ticks; no passes, as the original waits for the fade), shows the
## other screen's set-up and fades it in. Start in 8 leaves (the base's
## 32-tick fade). Live play hands the session's second random stream
## ([member MwSession.rng_aux]) to the sim for the starfield's directions.

@onready var starfield: RomStarfield = $Starfield
@onready var plane_a_clip: Control = $PlaneAClip
@onready var plane_a: RomPlane = $PlaneAClip/PlaneA

const SCREEN_SIZE := Vector2(320, 224)

var painter_a: MwWindowPainter
## The screen the sim showed after the last pass drawn (8 or 9).
var _shown := 8
## A pass that switched between 8 and 9: the fade covers the screen, its
## draws and the events after the fade wait.
var _covering := false
var _held_window: Array = []
var _held_plane_a: Array = []
var _held_sprites: Array = []
var _held_events: Array = []


func _enter_screen(data: Dictionary) -> void:
	_shown = 8
	_covering = false
	_held_window = []
	_held_plane_a = []
	_held_sprites = []
	_held_events = []
	super._enter_screen(data)


## The sim's second random stream: the session's (a fresh one run alone),
## plane A's painter.
func _sim_made() -> void:
	var st := sim as MwStatsSim
	if st == null:
		return
	st.aux = session.rng_aux if session != null else MlhRng.new((randi() & 0x7FFFFFFF) | 1)
	painter_a = MwWindowPainter.new(plane_a, rom)
	plane_a.wipe()


## While the switch's fade runs no pass runs (the tick goes on); once
## covered the other screen is shown and fades in.
func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if _covering:
		if state:
			state.tick = (state.tick + elapsed) & 0xFFFFFFFF
		if fader != null and fader.busy():
			return
		_uncover()
		return
	super._screen_pass(elapsed, input)


## A pass's draws; a pass that switched between 8 and 9 plays the events
## before its fade, starts the fade and holds the rest.
func _draw_pass() -> void:
	var st := sim as MwStatsSim
	if st == null:
		super._draw_pass()
		return
	if st.shown != _shown and fader != null:
		_shown = st.shown
		var i := 0
		while i < sim.events.size() and str(sim.events[i][0]) != "fade_out":
			_event(sim.events[i])
			i += 1
		_held_events = sim.events.slice(i + 1)
		_held_window = sim.window_ops.duplicate()
		_held_plane_a = st.plane_a_ops.duplicate()
		_held_sprites = sim.sprite_ops.duplicate()
		_covering = true
		fader.fade_out(MwScreenSim.FADE_OUT)
		return
	_shown = st.shown
	_show(sim.window_ops, st.plane_a_ops, sim.sprite_ops)
	for ev in sim.events:
		_event(ev)


## The held screen painted under the cover, its events, the fade-in (the
## sound calls the switch's pass made after its fade-out first).
func _uncover() -> void:
	_covering = false
	sim.fade_over()
	_show(_held_window, _held_plane_a, _held_sprites)
	for ev in _held_events:
		_event(ev)
	_held_window = []
	_held_plane_a = []
	_held_sprites = []
	_held_events = []
	if fader != null:
		fader.fade_in(MwStatsSim.FADE_IN)


## The planes' operations and the sprites painted, the scrolls, the
## window's rows and the starfield's position applied.
func _show(window_ops: Array, plane_a_ops: Array, sprite_ops: Array) -> void:
	var st := sim as MwStatsSim
	painter_b.paint(sim.plane_ops, state)
	painter_w.paint(window_ops, state)
	painter_a.paint(plane_a_ops, state)
	if not sprite_ops.is_empty():
		var list := drawer.list(state, sprite_ops)
		sprites_low.show_list(list)
		sprites_high.show_list(list)
	var top := 8.0 * clampi(st.window_rows, 0, 28)
	window.visible = st.window_rows > 0
	plane_a_clip.position = Vector2(0, top)
	plane_a_clip.size = Vector2(SCREEN_SIZE.x, maxf(SCREEN_SIZE.y - top, 0))
	plane_a_clip.visible = top < SCREEN_SIZE.y
	# VDP scrolls: screen x shows plane x - hscroll, line y plane line y + vscroll
	plane_a.position = Vector2(st.hscroll_a, -top - st.scroll_a)
	starfield.vx = 0
	starfield.vy = 0
	starfield.x = st.star.pos[0]
	starfield.y = st.star.pos[1]
	starfield.step()                          # placed where the sim's VBlanks left it


## The sim's events: the music (the sim calls the driver itself) and the
## palette fades (the router's and [method _uncover]'s) need nothing.
func _event(_ev: Array) -> void:
	pass
