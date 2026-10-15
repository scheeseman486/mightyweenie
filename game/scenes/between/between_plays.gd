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
##
## Online (plan 35 work item 4): the players' network statuses reach the
## control layer (MwRinkControl.set_net: who is away counts nowhere), the
## scoreboards' replay choice does nothing and its line is gone (owner: no
## replays watched online; the recording goes on), and SAVE REPLAY? is the
## host's P1's to answer - every machine shows it and waits for the answer
## in the stream; only the host writes the file.
##
## A spectated match (MwRinkState.spectated: the port's CPU v CPU
## exhibition): every player's pad bytes, OR'd, are every pad's ([method
## spectators]) - any player skips and continues wherever the original
## waits for a pad (any pad, pad 1, the fouled team's, the replay's) - and
## the scoreboards' menus pick no special plays (their B line gone, B
## taking nobody to screen 10: the CPU decides for both teams); anyone
## answers SAVE REPLAY?.

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
## Plan 34: the game-over scoreboards' SAVE REPLAY? ([method asks_replay])
## and the screen they left for, after it.
var replay_question: MwConfirmBox
var _then := -1
## Plan 35: the scoreboards whose menu offers the instant replay on C, and
## C's bit in their pad bytes.
const REPLAY_CHOICE: Array[int] = [12, 13, 14, 15, 16, 17]
const REPLAY_BUTTON := 0x20
## The scoreboards whose menu offers the special plays (and Reserves) page
## on B (`$8E94`: 12-14; `$E8DE`: 17), and B's bit: none in a spectated
## match ([method spectators]).
const PLAYS_CHOICE: Array[int] = [12, 13, 14, 17]
const PLAYS_BUTTON := 0x10


func _ready() -> void:
	fades_in_itself = false


## Port only (plan 38): the screens that draw a coach's portrait set up his
## own colours here ([member MwRinkDraw.portrait_mark], the layers'
## [member MwSpriteLayer.alt_palette]); the others draw no coach.
func _coach_colours() -> void:
	pass


func _enter_screen(_data: Dictionary) -> void:
	if not MwRom.available():
		return
	rom = MwRom.data()
	sim = MwScreenSims.make(screen_id, rom)
	if sim == null:
		return
	state = _match_state()
	if state == null:
		state = _demo_state()
	drawer = MwScreenDraw.new(rom)
	painter_b = MwWindowPainter.new(plane_b, rom)
	painter_w = MwWindowPainter.new(window, rom)
	painter_w.prompt_ctx = MwPrompts.context_for(MwScreens.contexts(screen_id))   # plan 23: the prompts' glyphs
	if painter_w.prompt_ctx == MwVerbs.Context.SCOREBOARD:
		painter_w.prompt_style = MwGlyphs.Style.TEXT    # the backdrop runs on under the window (owner)
	var su := session.setup if session else MwMatchSetup.new()
	palette.screen = screen_id
	palette.team_a = MwTeams.id_of(state.teams[0].record)
	palette.team_b = MwTeams.id_of(state.teams[1].record)
	palette.stadium = _stadium(su)
	# port only (plan 38): a custom team's name - and the window's other
	# letters in its colours - in colours of its own, on a palette of the
	# window's own (sprites and plane B keep the shared one)
	window.palette = MwScreenPalettes.names(palette)
	if window.high_cells:
		window.high_cells.palette = window.palette
	_coach_colours()
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
	if replay_question != null and replay_question.active:
		replay_question.handle(input)
		return
	if sim == null or _leaving:
		return
	var held := []
	var new := []
	for p in pads_read(state):
		var b := pad_bytes(input, p + 1, MwScreens.contexts(screen_id))
		held.append(b.x)
		new.append(b.y)
	if state.spectated:
		spectators(input, MwScreens.contexts(screen_id), held, new,
				screen_id in PLAYS_CHOICE and int(sim.get("menu") if "menu" in sim else 0) != 0)
	if state.control != null:
		state.control.set_net(input.away if input != null else {})   # plan 35: whose machine is away
		state.control.screen_pads(screen_id, held, new)    # plan 34: who counts here (captains, QUIT GAME)
	if MwFlow.online(session) and screen_id in REPLAY_CHOICE:
		for i in held.size():                       # plan 35: no replay watched online (C)
			held[i] &= ~REPLAY_BUTTON
			new[i] &= ~REPLAY_BUTTON
	state.tick = (state.tick + elapsed) & 0xFFFFFFFF
	sim.begin_pass()
	var to := sim.step(elapsed, held, new)
	_draw_pass()
	if to >= 0:
		_leaving = true
		if asks_replay(session, screen_id, to, state):
			_ask_replay(to)
		else:
			exit_to(to, {}, true, MwScreenSim.FADE_OUT)


## Plan 34 (owner: at a match's end the local player or the host is asked
## whether to save the replay to disk): the port's flow asks when a
## game-over scoreboard (15, 16 - a final whistle or a forfeit) leaves for
## the next screen (not for the stats or the replay, which come back to
## it): SAVE REPLAY? in the pause menu's ARE YOU SURE? look, player 1
## answering, NO first. Not in the attract demo, nor with nothing recorded
## (plan 35: by the match - a machine that rejoined it asks as the others).
static func asks_replay(session_: MwSession, id: int, to: int, s: MwRinkState) -> bool:
	return session_ != null and MwSettings.front_menu and not session_.attract and id in [15, 16] \
			and to in [1, 11] and s != null and s.full_replay != null and s.full_replay.recorded() > 0


func _ask_replay(to: int) -> void:
	_then = to
	replay_question = MwConfirmBox.new()
	replay_question.name = "ReplayQuestion"
	add_child(replay_question)
	replay_question.setup(window, rom)
	replay_question.player = 1
	var who := session.player_on_pad(1)
	var line := ""
	if MwFlow.online(session):
		replay_question.player = 0                  # plan 35: the host's P1 (the shared menu verbs)
		who = 1
	elif state != null and state.spectated:
		replay_question.player = 0                  # a spectated match: nobody's more than another's
		line = "ANY PLAYER"
	replay_question.answered.connect(_replay_answered)
	replay_question.open(line if line != "" else "PLAYER %d" % who, "SAVE REPLAY?")


## YES: the match's recording written ([MwReplayFile], named for the day,
## the mode and the teams); then on to where the scoreboard was going.
func _replay_answered(yes: bool) -> void:
	if yes and session.machine <= 0:                # plan 35: online only the host writes it
		var mode := session.local_mode if session.local_mode in MwReplayFile.MODES \
				else ("playoffs" if screen_id == 16 else "exhibition")
		if MwFlow.online(session):
			mode = "online"
		MwReplayFile.save_match(session, state, mode)
	exit_to(_then, {}, true, MwScreenSim.FADE_OUT)


## The match the screen shows: the session's (the rink's state, kept across
## screens). Virtual (screen 7's saved replays: the file's).
func _match_state() -> MwRinkState:
	return session.screens.get("rink") as MwRinkState if session else null


## The stadium whose colours the screen takes: the setup's (the playoffs:
## the home team's, as the rink wrote it back). Virtual.
func _stadium(su: MwMatchSetup) -> int:
	return su.stadium


## Called with the sim made, before its set-up ([method MwScreenSim.enter]):
## what a screen hands its sim beyond the game's state (the stats' second
## random stream). Virtual.
func _sim_made() -> void:
	pass


## The picture banks of this screen's VRAM (empty: the scene's own). Virtual.
func _banks() -> PackedStringArray:
	return PackedStringArray()


## The sim's sprite operations as this screen draws them (a screen with
## button prompts among its sprites puts the port's glyphs in: plan 23).
## Virtual.
func _sprite_ops(ops: Array) -> Array:
	return ops


## Draws what the sim's pass asked for. Virtual (call the base first).
func _draw_pass() -> void:
	painter_b.paint(sim.plane_ops, state)
	var w_ops := sim.window_ops
	if MwFlow.online(session) and screen_id in REPLAY_CHOICE:
		w_ops = w_ops.filter(func(op: Array) -> bool: return not MwScoreboardBackdrop.is_replay_line(rom, op))
	if state != null and state.spectated and screen_id in PLAYS_CHOICE:
		w_ops = w_ops.filter(func(op: Array) -> bool: return not MwScoreboardBackdrop.is_plays_line(rom, op))
	painter_w.paint(w_ops, state)
	var list := drawer.list(state, _sprite_ops(sim.sprite_ops))
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
	var rink_sim := MwRinkSim.new(rom, s)
	MwRinkMatch.start(rink_sim, 0, 0, 5, 0, false, 2)
	MwRinkMatch.boot_icons(rink_sim)
	s.penalties = 1
	s.period = 1
	s.clock = 180
	rink_sim.dispose()                       # plan 45: done with it (its cycle would keep the state)
	return s


## How many pads the screens between plays read for [param s]'s match: the
## original's four, or an extended set-up's twelve match pads (plan 34:
## player n is pad n - 1, MwHumans.pad_index).
static func pads_read(s: MwRinkState) -> int:
	return MwVerbs.PLAYERS if s != null and s.extended else 4


## A spectated match's pads ([param held], [param new]: the pads the
## screen reads, as [method pad_bytes] made them): every player's (1-12)
## bytes in the screen's [param contexts] OR'd, on every pad - nobody plays,
## so the original's "any pad", "pad 1" and "the pad that asked" all mean
## anyone. With [param plays_off] (a scoreboard's menu is up) B is nobody's:
## the special plays page is never picked.
static func spectators(input: MwInputFrame, contexts: Array, held: Array, new: Array, plays_off := false) -> void:
	var h := 0
	var n := 0
	for p in range(1, MwVerbs.PLAYERS + 1):
		var b := pad_bytes(input, p, contexts)
		h |= b.x
		n |= b.y
	if plays_off:
		h &= ~PLAYS_BUTTON
		n &= ~PLAYS_BUTTON
	for i in held.size():
		held[i] = h
		if i < new.size():
			new[i] = n


## The original's pad bytes of player [param player] (1-4) in the screen's
## [param contexts] ([MwVerbs]): Vector2i(held, newly pressed).
static func pad_bytes(input: MwInputFrame, player: int, contexts: Array) -> Vector2i:
	if input == null:
		return Vector2i.ZERO
	return Vector2i(input.held_bits(player, contexts), input.pad_bits(player, contexts))
