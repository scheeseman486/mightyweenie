class_name MwBetweenPlays
extends MwScreen
## The scenes of the screens between plays (plan 11): a node-free
## [MwScreenSim] ([MwScreenSims]) runs the screen as the original does,
## pass for pass, on the game's state (the rink's [MwRinkState], kept in
## the session across screens); this scene feeds it the pads and draws what
## each pass asks for: plane B and the window from its operations
## ([MwWindowPainter]; cells with the priority bit on the planes'
## [member RomPlane.high_cells], above the low sprites), its sprites
## ([MwScreenDraw]) in two layers by priority. The sim makes its own sound
## calls ([MwSound], live play: no hooks); those it made after its exit's
## fade-out started are made once the fade is over and the screen left
## ([method MwScreenSim.fade_over]). A sim's choice of the next screen
## leaves after the original's 32-tick fade.
##
## Screens with more (the instant replay's rink, the stats' plane A and
## starfield) extend [method _draw_pass].

@onready var plane_b: RomPlane = $PlaneB
@onready var window: RomPlane = $Window
@onready var sprites_low: MwSpriteLayer = $SpritesLow
@onready var sprites_high: MwSpriteLayer = $SpritesHigh
@onready var palette: RomPalette = $Backdrop.palette

var rom: PackedByteArray
var sim: MwScreenSim
var state: MwRinkState
var drawer: MwScreenDraw
var painter_b: MwWindowPainter
var painter_w: MwWindowPainter
var _leaving := false
## Checks only (test/screens/visual_check.gd): called with the sim made,
## before its set-up ([method MwScreenSim.enter]) - to give it comparison
## hooks or the RAM its state does not hold.
var on_sim_made := Callable()


func _ready() -> void:
	fades_in_itself = false


func _enter_screen(_data: Dictionary) -> void:
	if not MwRom.available():
		return
	rom = MwRom.data()
	sim = MwScreenSims.make(screen_id, rom)
	if sim == null:
		return
	state = session.screens.get("rink") as MwRinkState if session else null
	if state == null:
		state = _demo_state()
	drawer = MwScreenDraw.new(rom)
	painter_b = MwWindowPainter.new(plane_b, rom)
	painter_w = MwWindowPainter.new(window, rom)
	var su := session.setup if session else MwMatchSetup.new()
	palette.screen = screen_id
	palette.team_a = (state.teams[0].record - MwRinkMatch.TEAM_RECORDS) / MwRinkMatch.TEAM_SIZE
	palette.team_b = (state.teams[1].record - MwRinkMatch.TEAM_RECORDS) / MwRinkMatch.TEAM_SIZE
	palette.stadium = su.stadium
	var banks := _banks()
	if not banks.is_empty():
		for plane in [plane_b, window]:
			plane.tiles = plane.tiles.duplicate()
			plane.tiles.banks = banks
			if plane.high_cells:
				plane.high_cells.tiles = plane.tiles
			plane.build()
			if plane.high_cells:
				plane.high_cells.build()
	plane_b.wipe()
	window.wipe()
	_sim_made()
	if on_sim_made.is_valid():
		on_sim_made.call(sim)
	sim.begin_pass()
	sim.enter(state, screen_id, previous)
	_draw_pass()


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if sim == null or _leaving:
		return
	var held := []
	var new := []
	for p in 4:
		var b := pad_bytes(input, p + 1, MwScreens.contexts(screen_id))
		held.append(b.x)
		new.append(b.y)
	state.tick = (state.tick + elapsed) & 0xFFFFFFFF
	sim.begin_pass()
	var to := sim.step(elapsed, held, new)
	_draw_pass()
	if to >= 0:
		_leaving = true
		exit_to(to, {}, true, MwScreenSim.FADE_OUT)


## Called with the sim made, before its set-up ([method MwScreenSim.enter]):
## what a screen hands its sim beyond the game's state (the stats' second
## random stream). Virtual.
func _sim_made() -> void:
	pass


## The picture banks of this screen's VRAM (empty: the scene's own). Virtual.
func _banks() -> PackedStringArray:
	return PackedStringArray()


## Draws what the sim's pass asked for. Virtual (call the base first).
func _draw_pass() -> void:
	painter_b.paint(sim.plane_ops, state)
	painter_w.paint(sim.window_ops, state)
	var list := drawer.list(state, sim.sprite_ops)
	sprites_low.show_list(list)
	sprites_high.show_list(list)
	for ev in sim.events:
		_event(ev)


## A sim event beyond its draws (palette changes in the subclasses). The
## sounds' events need nothing: the sim called the driver itself. Virtual.
func _event(_ev: Array) -> void:
	pass


## Left (after the exit's fade): the sound calls the sim made after its
## fade-out started (`$8EE0`'s music stop, `$E496` / `$D95C` after the
## fight's card...).
func _exit_tree() -> void:
	if sim != null:
		sim.fade_over()


## A match state for a screen run on its own (from the editor): teams 0
## and 5 at stadium 0, penalties on.
func _demo_state() -> MwRinkState:
	var s := MwRinkState.new()
	var sim_ := MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim_, 0, 0, 5, 0, false, 2)
	MwRinkMatch.boot_icons(sim_)
	s.penalties = 1
	s.period = 1
	s.clock = 180
	return s


## The original's pad bytes of player [param player] (1-4) in the screen's
## [param contexts] ([MwVerbs]): Vector2i(held, newly pressed).
static func pad_bytes(input: MwInputFrame, player: int, contexts: Array) -> Vector2i:
	var held := 0
	var new := 0
	if input == null:
		return Vector2i.ZERO
	for ctx in contexts:
		for button in MwGameplayPads.BITS:
			var bit: int = MwGameplayPads.BITS[button]
			for verb in MwVerbs.verbs_of(int(ctx), button):
				var action := MwVerbs.menu_action(player, verb) if verb.begins_with("ui_") else MwVerbs.action(player, verb)
				if input.held.has(action):
					held |= bit
				if input.pressed.has(action):
					new |= bit
	return Vector2i(held, new)
