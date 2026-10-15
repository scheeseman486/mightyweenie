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
## any input, or the demo's first exit, returns to the main menu. A
## spectated match (the port's CPU v CPU exhibition, MwSession.spectated):
## any player's Start pauses, into the spectators' menu (REPLAY, TEAM
## INFO, QUIT GAME - back to the game setup), and any player skips the
## speeches.
## A recorded match of the original (`mw_harness rink-dump` ->
## out/rink/dec/*.json) can be played back instead ([member playback_file]
## or the entry data's "playback").
##
## TICK RATE ORIGINAL (plan 36, [member MwSettings.tick_rate]): live play's
## passes as long as the original's 68000 would take - the pass's load
## (MwPassLoad) after its draw pass, its cycles (MwPassCost), laid out on the
## VBlanks with the sound driver's work by MwPassPacer, which the router's
## clock asks each tick ([method pass_pacer]). APPROXIMATED (and ORIGINAL in
## an online match, [method MwSettings.rink_tick_rate]): the same load summed
## in integers by MwPassApprox, the sound driver at its mean - the same on
## every machine. OVERCLOCKED: a pass every 2 ticks. The pause menu and the
## other screens keep their pace.
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
##
## Online (plan 35 work item 4, MwFlow.online): the players' network
## statuses reach the control layer every pass (MwRinkControl.set_net: the
## CPU plays for a machine that is away), a pause whose player's machine went
## away resumes, the port's pause menu for everyone without REPLAY (and with
## PLAYERS for the host's players), and only the 2D / 3D / 3D EXTENDED
## switch (the F keys' and Back's debug views are off: MwRinkViews.picked).
##
## Dead reckoning (plan 35 work item 5, a client online: MwSession.reckoning,
## MwNetReckoning): each picture draws the players and the puck "now" - the
## pass's draw made again ([method MwRinkUpdate.redraw]) on the state with
## their predicted, eased positions (and the camera's) swapped in, then the
## confirmed state put back; in 3D at sub-pixel points. Only the picture:
## everything else - sounds, goals, the crowd, the replay ring - comes from
## the confirmed pass. F9 switches it off and on (a debug build online).

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

var rom: PackedByteArray
var state: MwRinkState
var sim: MwRinkSim
var update: MwRinkUpdate
var phases: MwRinkPhases
var drawer: MwRinkDraw
## The port's pause menu's inputs (MwRinkPhases.menu_press) and their verbs.
const MENU_VERBS := {"up": "ui_up", "down": "ui_down", "select": "ui_accept", "resume": "ui_resume",
	"back": "ui_back"}

var painter: MwWindowPainter
## The port's pause menu (plan 23: the STANDARD layout's; MwRinkPhases.menu).
var pause_menu: MwPauseMenu
## Plan 34: everyone else's own menus (MwRinkControl.menus) over the game.
var own_menus: MwOwnMenus
var _playback: Array = []
var _play_at := 0
var _play_ticks := 0
var _phase_adds: Array = []
var _pass_frame := 0     # the physics frame of the latest pass, and its ticks (3D blending)
var _pass_len := 1
var _shown_3d := false   # the latest pass was presented in 3D
## TICK RATE's model of the pass's load (plan 36: MwPassLoad, ORIGINAL;
## MwPassApprox, APPROXIMATED - the same calls: wrap, clock_now, begin,
## work) and the pass lengths its pacer makes from it; null: OVERCLOCKED.
var _load_model: RefCounted = null
var _pacer: MwPassPacer = null
var _first_pass := true
var _segment_ran := false         # this pass ran its segment (not a paused pass's draw)
var _echoed := false              # plan 41: the menus show predicted presses
var _work := {}                   # the latest pass's work for the pacer (the dead reckoning's predictions)
var _coach_key := []     # what the coach's colours were set up for (plan 38)


func _enter_screen(data: Dictionary) -> void:
	super._enter_screen(data)
	if not MwRom.available():
		return
	rom = MwRom.data()
	drawer = MwRinkDraw3D.new(rom)
	painter = MwWindowPainter.new(window, rom)
	# port only (plan 38): a custom team's name - and the window's other
	# letters in its colours - in colours of its own, on a palette of the
	# window's own, which the pause menu and the players' own menus take as
	# the window's (the sprites keep the shared one)
	window.palette = MwScreenPalettes.names(palette)
	pause_menu = MwPauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.setup(window, rom)
	own_menus = MwOwnMenus.new()
	own_menus.name = "OwnMenus"
	add_child(own_menus)
	own_menus.setup(window, rom)
	_host().wide_for(self, MwSettings.wide())      # plan 25: ASPECT RATIO WIDE
	var su := session.setup if session else MwMatchSetup.new()
	# (all at once, and nothing redone when the match's rink comes again - owner,
	# 2026-10-13: a goal's screen changes held the main thread long enough to cut
	# the music)
	palette.set_recipe(screen_id, su.team_a, su.team_b, su.stadium,
			MwCustomTeams.coach_lines(rom, palette.steps, su.team_a, su.team_b, [1, 1]))   # plan 38
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
		_warm_run_ahead()
	_present(false, true)


## Plan 42: an online client's run-ahead does its first-time work (its copies
## compiled, its sound model made) as the rink is entered - under the fade -
## not at its first picture (MwNetRunAhead.warm).
func _warm_run_ahead() -> void:
	if session == null or session.reckoning == null:
		return
	var ra := session.reckoning.run_ahead
	if ra != null and ra.active():
		ra.warm(self)


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
			last.retire()                    # plan 45: the last match's state let go of
		if session and not session.attract:
			# plan 34: the players' seats, owned positions and captains (the opening line-up reads them)
			state.control = MwRinkControl.make(session.humans, session.pad_map, rom)
			state.control.go_online(session.online)     # plan 35: the match's machines
			state.spectated = session.spectated()       # CPU v CPU: everyone watches (MwSession.spectated)
	if state.control != null:
		for seat in state.control.seats:     # B tapped twice reclaims with the GENESIS layout
			seat.taps = _layout_of(seat.player) == "GENESIS"
	if session:
		session.screens["rink"] = state
		state.rng = session.rng                 # one main stream (`$FFB096`)
	if state.full_replay == null:
		# plan 28: the whole match kept - plan 34: always, for the saved replays
		# (REPLAY LENGTH only limits how far the in-game replay reaches)
		state.full_replay = MwFullReplay.new()
	# the match's crowd (plan 31: its seed kept in the replays; plan 35: from the
	# session's crowd stream, the same on every machine), benches (plan 32) and
	# paint (plan 37) - the 3D opening's crowd and paint going on (plan 33)
	MwMatchModels.make(state, session, data)
	sim = MwRinkSim.new(rom, state)
	sim.live = true                          # the sound calls reach the driver (plan 12)
	sim.cpu = MwRinkAI.new()                 # CPU players think as the original's (`$3BFE`)
	match MwSettings.rink_tick_rate(MwFlow.online(session)):
		"ORIGINAL":
			var pass_load := MwPassLoad.new(rom)  # plan 36: a new visit (`rink_load` empties the tile cache)
			pass_load.live = true
			_load_model = pass_load
			_pacer = MwPassPacer.new()
			_pacer.sound = MwPassPacer.driver_sound
		"APPROXIMATED":
			_load_model = MwPassApprox.new(rom)
			_pacer = MwPassPacer.new()        # the sound driver at its mean
	if _load_model != null:
		sim.cpu = _load_model.wrap(sim.cpu)   # the AI's thinks counted
	_first_pass = true
	_work = {}
	state.pace = PackedInt32Array()          # plan 35's hash: this visit's pacer, once it has paced a pass
	update = MwRinkUpdate.new(sim)
	MwReplay3D.use(update)                   # the original's sprite list, placed in the world too; 3D replay frames
	phases = MwRinkPhases.new(update)
	# plan 35: online everyone's pause is the port's menu (the original's has A - REPLAY)
	var online := MwFlow.online(session)
	phases.port_menu = func(player: int) -> bool: return online or _layout_of(player) == "STANDARD"
	phases.online = online
	if new_match and last == null:
		MwRinkMatch.boot_icons(sim)
	var screen := 4 if entry == "period_start" else (5 if entry == "faceoff" else 6)
	var spot := int(data.get("faceoff_spot", state.faceoff_spot)) if entry == "faceoff" else -1
	if new_match and session != null:
		MwSelection.for_the_rink(session, su)  # plan 40 (S13): the players' match pads and line-ups
	if new_match:
		su.take_extended_rules()               # plan 44: an EXTENDED match (match rules: online always)
		if session != null:                    # (its views' group, as the matchup sets it)
			session.extended_views = su.extended_play
			session.view = MwRinkViews.grouped(session.view, su.extended_play)
	var to := enter_match(sim, phases, su, new_match, session.playoffs if session else null,
			session != null and session.attract, screen, spot)
	if new_match:
		palette.stadium = su.stadium            # the playoffs: the home team's
	painter.paint(phases.window_ops, state)    # `rink_load`'s cleared window, the clock widget
	if to >= 0:
		_leave(to)


## The rink's entry on [param rink_sim] (its state new for [param new_match], or
## the match's) and its phase handler [param phase_handler]: a new match's set-up
## from [param su] (`$B2B0`: the clock, the stadium - the playoffs' home
## team's, written back to [param su] as `$B2F0` does - the rink and the
## teams), the options and the match's flags, the faceoff [param spot]
## (>= 0), the phase handler's entry for [param screen] (4 period start, 5
## faceoff, 6 play on), the camera, the benches (plan 32: filled for the
## first frame). Returns the phase handler's exit (-1 none). Shared with the
## 3D intro's rehearsal of it (plan 33, MwMatchRehearsal).
static func enter_match(rink_sim: MwRinkSim, phase_handler: MwRinkPhases, su: MwMatchSetup, new_match: bool,
		playoffs: MwPlayoffs, attract: bool, screen: int, spot := -1) -> int:
	var s := rink_sim.s
	if new_match:
		var setup := su.copy()
		setup.period_minutes = maxi(su.period_minutes, 1)
		MwRinkMatch.matchup_setup(rink_sim, setup, playoffs.series if playoffs else 0)
		MwLineup.apply(rink_sim, setup.lineups)      # plan 34: the line-ups chosen before the match
		su.stadium = setup.stadium
	s.period_minutes = maxi(su.period_minutes, 1)
	s.period_row = su.period_index
	s.penalties = su.penalties
	s.play_mode = su.play_mode
	s.fight_block = 1 if attract else 0     # `$FFCA1C`: the attract demo
	if playoffs != null:
		s.playoffs = playoffs
	if spot >= 0:
		s.faceoff_spot = spot
	var to := phase_handler.enter(screen)
	s.camera.update(rink_sim.rom, 0, null)
	if s.bench_life != null:
		s.bench_life.step(0, rink_sim)
	return to


## Leaving live play for [param id] (the phase handler's exit: `rink_exit`
## is done); the attract demo's end restores the setup (`$45E4`).
func _leave(id: int) -> void:
	if session != null and session.attract and id == 1:
		if MwSettings.front_menu:
			MwReplayFile.save_demo(session, state)   # plan 34: each demo kept as its own replay (owner)
		id = session.attract_return               # the port's front menu if it started the demo
		session.end_attract()
	exit_to(id)


## Leaves for screen [param id] as [method MwScreen.exit_to] does ([param data], [param fade],
## [param ticks] passed on), unless the rink is already leaving.
func exit_to(id: int, data := {}, fade := true, ticks := -1) -> void:
	if leaving():
		return
	super.exit_to(id, data, fade, ticks)


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	super._screen_pass(elapsed, input)
	if rom.is_empty():
		return
	MwSound.reset_swaps()                       # plan 45 (D8): a prediction stopped mid-swap put right
	if session != null and session.reckoning != null:
		session.reckoning.restore_left()        # (the same for a picture)
	if not _playback.is_empty():
		_play_ticks += elapsed
		while _play_at + 1 < _playback.size() and _play_ticks >= int(_playback[_play_at + 1]["e"]):
			_play_ticks -= int(_playback[_play_at + 1]["e"])
			_play_at += 1
		_show_recorded(_play_at)
	elif not leaving():
		_live_pass(elapsed, input)
	_pass_frame = Engine.get_physics_frames()
	_pass_len = maxi(elapsed, 1)
	_present()


## One gameplay pass: its start (MwRinkUpdate: pass counter, clock), the
## pads (players 1-4 on pads 0-3, as the router mapped them; plan 34, an
## extended set-up: players 1-12 on its match pads 0-11, MwHumans.pad_index),
## the segment, the rest of the rink update
## (objects, camera, crowd...), the puck rules and the phase handler, the
## draw pass. While the pause menu is open (`$48FC`'s busy loop) the game
## stands still: the tick counter runs and the pad that paused answers. A
## spectated match (MwSession.spectated) also reads every player's pad for
## the spectators' pause and skips ([method watch_pads]).
func _live_pass(elapsed: int, input: MwInputFrame) -> void:
	_segment_ran = false
	if state.control != null and input != null:
		state.control.set_net(input.away)         # plan 35: whose machine is away, as the stream says
	if phases.paused:
		state.tick += elapsed
		var paused_exit: int
		var by := state.control.seat_on_pad(state.pause_pad >> 1) if state.control != null else null
		if by != null and by.net != 0:
			paused_exit = phases.resume_now()               # plan 35: the match never waits for a machine away
		elif not phases.menu.is_empty():
			# the port's menu (plan 23): the pausing player's verbs
			paused_exit = phases.menu_press(menu_verbs(input, int(phases.menu["player"]),
					_layout_of(int(phases.menu["player"]))))
		else:
			# the original's menu (plan 22: its own verbs; Back resumes)
			var pad := input.pad_bits((state.pause_pad >> 1) + 1, [MwVerbs.Context.PAUSE]) if input else 0
			paused_exit = phases.pause_press(pad)
		painter.paint(phases.window_ops, state)
		_handled(paused_exit)
		return
	# the pass (plan 40: the rink's own, MwRinkUpdate.run_pass); the draw pass in _handled
	var to := update.run_pass(elapsed, phases, _pass_input.bind(elapsed, input), _segment_done, false)
	painter.paint(phases.window_ops, state)    # the phase handler's texts (or the pause menu)
	_handled(to)


## A live pass's start, after MwRinkUpdate.pass_start: the clock's texts,
## the pads, a spectated match's watched pads, the own menus' verbs and the
## TICK RATE models' start - up to the segment.
func _pass_input(elapsed: int, input: MwInputFrame) -> void:
	painter.paint(update.window_ops, state)    # the clock's texts (`$261C`)
	if _load_model != null:
		_load_model.clock_now(update.window_ops)
	read_pads(state, sim, input)
	if _load_model != null:
		_load_model.begin(sim, elapsed)
	_segment_ran = _pacer != null


## A pass's pads from [param input] into [param s] and [param sim]
## (players 1-4 on pads 0-3, an extended set-up's on its match pads; the
## sticks, shot heights and direct steering), a spectated match's watched
## pads and the own menus' verbs - the live pass's and (plan 41) a client's
## run-ahead's.
static func read_pads(s: MwRinkState, sim_: MwRinkSim, input: MwInputFrame) -> void:
	var n := s.pads_held.size()
	while sim_.human.direct.size() < n:
		sim_.human.direct.append([])
	var all := MwGameplayPads.read_all(input, n)            # (plan 42: every pad in one go)
	for pad in n:
		var r: Dictionary = all[pad]
		s.pads_held[pad] = r["held"]
		s.pads_new[pad] = r["new"]
		s.pad_sticks[pad] = r["stick"]
		s.pad_heights[pad] = r["height"]
		sim_.human.direct[pad] = r["direct"]
	if s.spectated:
		watch_pads(s, input)
	if s.control != null:
		s.control.verbs = own_menu_verbs(s.control, input)


## A live pass's segment done (before the rest of the update).
func _segment_done() -> void:
	if state.control != null and session != null:
		session.humans.out = state.control.out_players()    # plan 34: who left, for the next controller selection


## After the phase handler: paused (nothing more this pass), leaving, or
## the draw pass (the handler's overlays included).
func _handled(to: int) -> void:
	_show_pause_menu()
	_show_own_menus()
	if to == MwRinkPhases.PAUSED:
		if _pacer != null:
			_pacer.reset()                    # the pause menu's own pace; play resumes in step
		return
	if to == MwRinkPhases.TEAM_INFO:
		_team_info()
		return
	if to >= 0:
		_leave(to)
		return
	_coach_colours()
	update.draws(_phase_adds, MwRinkPhases.RULES_DRAWN, phases.overlays, phases.sprite_ops)
	if _pacer != null and _segment_ran:
		_work = _load_model.work(update, phases)
		_pacer.begin(_work, _first_pass)
		_first_pass = false
		state.pace = _pacer.snapshot()       # plan 35: in the rink's hash (when the next passes come)
	_segment_ran = false


## The router's clock: the pacer of live play's passes with TICK RATE
## ORIGINAL or APPROXIMATED (not while paused, leaving or playing a
## recording back).
func pass_pacer() -> MwPassPacer:
	if _pacer == null or leaving() or not _playback.is_empty() or phases == null or phases.paused:
		return null
	return _pacer


## Port only (plan 38): the coach speaking (state +speaker: 0 team A's) in
## colours of his own when he is a custom coach with some: his portrait's
## pieces on a palette line of their own (12 team A's coach, 13 team B's:
## line 1 - which the original gives both coaches, `$A0` - with his colours,
## RomPalette "coach_line"), as plan 34's players 5-12 have theirs.
func _coach_colours() -> void:
	var t := clampi(state.speaker, 0, 1)
	var key := [t, MwCustomTeams.version, palette.team_a, palette.team_b]
	if key == _coach_key:
		return
	_coach_key = key
	var own := MwCustomTeams.has_coach_colours(rom, MwTeams.id_of(state.teams[t].record))
	for rink_drawer: MwRinkDraw in [drawer, update.drawer if update else null]:
		if rink_drawer != null:
			rink_drawer.portrait_lines = {1: MwRinkDraw.COACH_LINE + t} if own else {}


## The port's pause menu's verbs of player [param p] (layout [param
## layout]) this pass ([constant MENU_VERBS]: MwRinkPhases.menu_press).
## Where the original's lettered menu would be (the GENESIS layout: a
## spectated match's menu, online) Start is both Menu Accept and resume,
## and resume wins - so the lettered menu's A and B (REPLAY, TIMEOUT
## there) pick the selected item.
static func menu_verbs(input: MwInputFrame, p: int, layout: String) -> Dictionary:
	var v := {}
	if input == null:
		return v
	for k in MENU_VERBS:
		v[k] = input.menu_pressed(p, MENU_VERBS[k])
	if layout != "STANDARD":
		v["select"] = v["select"] or input.menu_pressed(p, "ui_pause_replay") \
				or input.menu_pressed(p, "ui_pause_timeout")
	return v


## A spectated match (MwRinkState.spectated): every player's pad bytes this
## pass (MwGameplayPads: players 1-12, whoever's device it is) in
## [member MwRinkState.watch_held] / [member MwRinkState.watch_new] - the
## spectators' pause and speech skips (MwRinkPhases); the simulation's
## pads stay as the router gave them.
static func watch_pads(s: MwRinkState, input: MwInputFrame) -> void:
	s.watch_held.resize(MwVerbs.PLAYERS)
	s.watch_new.resize(MwVerbs.PLAYERS)
	for i in MwVerbs.PLAYERS:
		var r := MwGameplayPads.read(input, i + 1)
		s.watch_held[i] = int(r["held"]) & 0xFF
		s.watch_new[i] = int(r["new"]) & 0xFF


## Plan 34: the menu verbs of the players whose own menu is open
## (MwRinkControl.verbs: the pause menu's, [constant MENU_VERBS]), read on
## their pad - the router hands the original's pads their players' verbs.
static func own_menu_verbs(control: MwRinkControl, input: MwInputFrame) -> Dictionary:
	var out := {}
	if input == null:
		return out
	for seat in control.seats:
		if seat.menu.is_empty():
			continue
		var v := {}
		for k in MENU_VERBS:
			v[k] = input.menu_pressed(seat.pad + 1, MENU_VERBS[k])
		out[seat.player] = v
	return out


## Plan 34: the own menus as the control layer has them - hidden under the
## pause menu (the game stands still, the captain's menu has the screen).
## The pause menu as the phase handler has it (closed when there is none).
func _show_pause_menu() -> void:
	if phases != null and phases.paused and not phases.menu.is_empty():
		var m := phases.menu
		if session != null and session.player_on_pad(int(m["player"])) != int(m["player"]):
			m = m.duplicate()                  # plan 34: the pad's player, as the controller selection put them
			m["line"] = "PLAYER %d" % session.player_on_pad(int(m["player"]))
		pause_menu.show_menu(m, state.pause_attr)
	elif pause_menu != null and pause_menu.visible:
		pause_menu.close()


## Plan 41 (online, a client): this machine's players' presses its game
## hasn't run yet ([param presses]: player -> verbs) on the menus of the
## match - the pause menu of the player who paused, the own menus of those
## who have one open - shown at once: the highlight moved and the YES / NO
## answer stepped by the menus' own moves (MwMenuDict) on a copy; a choice,
## Start or Back is the game's to carry out (the presses after it wait).
## Drawn, then the menus put back; {} draws them as they are once more.
func predict_local(presses: Dictionary) -> void:
	if rom.is_empty() or phases == null or state == null:
		return
	var menus := []                          # [the menu, the player its verbs are read for]
	if phases.paused and not phases.menu.is_empty():
		if presses.has(int(phases.menu["player"])):
			menus.append([phases.menu, int(phases.menu["player"])])
	elif state.control != null:
		for seat in state.control.seats:
			if not seat.menu.is_empty() and presses.has(seat.pad + 1):
				menus.append([seat.menu, seat.pad + 1])
	if menus.is_empty():
		if _echoed:
			_echoed = false
			_show_pause_menu()
			_show_own_menus()
		return
	var kept := []
	for pair: Array in menus:
		kept.append((pair[0] as Dictionary).duplicate(true))
	MwLocalEcho.run(func() -> void:
		for pair: Array in menus:
			var m: Dictionary = pair[0]
			var who: int = pair[1]
			for verb: String in presses[who]:
				var v := menu_verbs(MwLocalEcho.frame(who, verb), who, _layout_of(who))
				if m.get("confirm", false):
					if MwMenuDict.confirm_verbs(m, v) != MwMenuDict.MOVED:
						break
				elif m.get("players", false) or not MwMenuDict.move(m, v):
					break                      # a choice: the game's
				MwSound.play(MwRinkPhases.MENU_MOVE))
	_show_pause_menu()
	_show_own_menus()
	for i in menus.size():
		var m: Dictionary = menus[i][0]
		m.clear()
		m.merge(kept[i])                     # (in place: the seats and the handler keep their dictionary)
	_echoed = true


func _show_own_menus() -> void:
	if own_menus == null:
		return
	if state == null or state.control == null or (phases != null and phases.paused):
		own_menus.close()
		return
	var attrs := []
	for team in state.teams:
		attrs.append((team.attr & 0xFF) | 0x80)
	var colours := {}
	for seat in state.control.seats:
		colours[seat.player] = MwPlayerColours.colour(rom, seat.player if state.extended else seat.pad + 1)
	own_menus.show_menus(state.control.menus(), attrs, colours)


## The pause menu's TEAM INFO (plan 29, owner): the team description (2)
## over the paused game - pushed, so this screen waits as it is (no passes,
## nothing reset) and comes back to its pause menu ([method _resume_screen]).
## The match's two teams; it opens on the pausing player's opponent's (a
## spectated match: team A's).
## The game's picture stays through the fade-out ([method _cover_screen]).
func _team_info() -> void:
	var paused_by := 0 if state.pause_team == MwRinkPhases.TEAM_WORDS[0] else 1
	var teams := []
	for team in state.teams:
		teams.append(MwTeams.id_of(team.record))
	# a spectated match: nobody's opponent - team A's first
	push(2, {"pause": true, "teams": teams, "side": 0 if state.spectated else 1 - paused_by})


## Under the cover, the team description about to come in: the 3D view and
## the wide picture given back (the description is 2D and pillarboxed).
## Owner: giving them back with the request showed the fade-out in the 2D
## view and the original's shape, a stale 2D frame first.
func _cover_screen() -> void:
	var host := MwRink3DHost.existing(get_tree())
	if host != null:
		host.show_for(self, false)
		host.wide_for(self, false)
	_shown_3d = false


## Back from the team description (plan 29): the picture as it was - the
## wide one taken again, the last pass shown, the pause menu.
func _resume_screen(_r := {}) -> void:
	if rom.is_empty() or state == null:
		return
	_host().wide_for(self, MwSettings.wide())
	_present(false)
	if phases != null and phases.paused and not phases.menu.is_empty():
		pause_menu.show_menu(phases.menu, state.pause_attr)


func _show_recorded(i: int) -> void:
	var recorded_pass: Dictionary = _playback[i]
	state = MwRinkState.from_dict(rom, recorded_pass["state"])
	_phase_adds = recorded_pass.get("phase_adds", [])
	var c: Variant = recorded_pass["state"].get("clock")
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
	if session != null and session.reckoning != null:
		session.reckoning.restore_left()        # plan 45 (D8): a picture stopped mid-swap put right
	# plan 35 work item 5: a client draws its actors "now" (put back below);
	# a picture that doesn't follow the last (an entry, a view switched) snaps
	if not continuous and session != null and session.reckoning != null:
		session.reckoning.snap_next()
	var rk := _reckoning()
	# plan 41 work item 2: the client's run-ahead - the game's own passes on a
	# shadow of the state, drawn instead of it (the confirmed state untouched)
	var shown_state := state
	var ra := rk.run_ahead if rk != null and rk.run_ahead != null and rk.run_ahead.active() else null
	var at := ra.run(self, MwScreens.contexts(screen_id)) if ra != null else -1
	var shown_update := update
	if at >= 0:
		shown_state = ra.shadow
		shown_update = ra.update
		ra.lend(state)
	elif rk != null:
		rk.pacer = pass_pacer()                # plan 36: the predicted steps are the paced passes
		rk.pacer_work = _work
	var now := false
	if rk != null:
		if at >= 0:
			now = rk.apply_ahead(shown_state, ra.sim, at, int(ra.last["aim"]), continuous, view_3d())
		else:
			now = rk.apply(state, sim, continuous, view_3d(), phases.paused)
	var drawn := _drawn(now, shown_update if at >= 0 else null)
	var list: Array = drawn[0]
	var drawer_3d: MwRinkDraw3D = drawn[1]
	var tiles := _plate_tiles(shown_state)
	var three := view_3d() and drawer_3d != null
	_show_view(three)
	if three:
		var rink_view := MwRinkPresenter.view_3d(_host(), self, palette, view(), birds_eye_across())
		# online: 3D EXTENDED frames this machine's players
		rink_view.local_pads = MwRinkShot3D.local_pads(session, shown_state.extended)
		if now:
			rk.shift_items(drawer_3d.items)
		rink_view.present(shown_state, drawer_3d, tiles, continuous and _shown_3d)
		rink_view.pass_shown(_pass_len, _pass_frame)  # rendered frames blend towards this pass
		var screen := MwRink3DHost.screen_list(_host(), drawer_3d.screen_sprites(), drawer_3d.screen_sprites(true),
				MwRinkDraw.arrow_marks(shown_state), MwRinkViews.shows_arrows(view()), rom, drawer_3d.pieces)
		MwRinkPresenter.show_list([screen_low, screen_high], tiles, screen)
	else:
		var at2 := Vector2(-shown_state.camera.shown)
		var host := MwRink3DHost.existing(get_tree())
		if MwRinkPresenter.wide(host, self) and drawer_3d != null:
			# plan 25: the wide picture - the rink slides inside its picture, the
			# original's 320 x 224 centred; a list for the whole picture
			var w := MwRinkPresenter.wide_place(host, shown_state.camera.shown, rom)
			at2 += Vector2(w["slide"])
			list = drawer_3d.wide_list(w["size"], w["off"], w["slide"], MwRinkDraw.arrow_marks(shown_state))
		MwRinkPresenter.backdrop_fit($Backdrop as Control, host, self)
		MwRinkPresenter.show_list([sprites_low, sprites_high], tiles, list)
		plane_low.position = at2
		plane_high.position = at2
		if prime and drawer_3d != null:
			_prime_3d(drawer_3d, tiles)
	_shown_3d = three
	_update_turns()
	if now:
		rk.restore(shown_state)
	if at >= 0:
		ra.take_back()


## The pass's sprite list and the drawer that placed it in the world (live:
## the list the pass's draws made - or, [param again], that draw made again
## on the state as it is now (the dead reckoning's positions swapped in) with
## the scene's own drawer; otherwise drawn now).
func _drawn(again := false, ahead: MwRinkUpdate = null) -> Array:
	if ahead != null:
		# plan 41: the run-ahead's shadow's last pass drawn (again: its easing
		# swapped in) - plan 42: its draw made here only (MwRinkUpdate.defer_draws)
		return [ahead.redraw(drawer), drawer as MwRinkDraw3D]
	if _playback.is_empty() and update != null and update.s == state and not update.sprites.is_empty():
		if again:
			return [update.redraw(drawer), drawer as MwRinkDraw3D]
		return [update.sprites, update.drawer as MwRinkDraw3D]
	return [drawer.build(state, _phase_adds), drawer as MwRinkDraw3D]


## Plan 35 work item 5: the dead reckoning this picture draws through - a
## client's in live play once the pass has drawn (null: offline, the host,
## switched off, playback, leaving).
func _reckoning() -> MwNetReckoning:
	if session == null or session.reckoning == null or not session.reckoning.active():
		return null
	if not _playback.is_empty() or leaving() or state == null or update == null or update.s != state \
			or phases == null or not update.can_redraw():
		return null
	return session.reckoning


## The info plates' RAM tiles of the state shown (MwPlate.ram_tiles).
func _plate_tiles(shown_state: MwRinkState = null) -> Dictionary:
	var s := shown_state if shown_state != null else state
	return MwPlate.ram_tiles(rom, s.plates, s.control != null and s.control.captain_mode)


## Entered in 2D: the 3D view (if built yet) shows this first pass once,
## unseen, under the fade (once per run: its sprite textures and materials
## stay), so the first switch to 3D shows at once (plan 20).
func _prime_3d(drawer_3d: MwRinkDraw3D, tiles: Dictionary) -> void:
	var host := MwRink3DHost.existing(get_tree())
	if host == null or not host.is_built() or host.primed or host.user != null:
		return
	host.borrow(self, palette).present(state, drawer_3d, tiles, false)
	host.prime()


# --- the 3D view (plan 14) ---------------------------------------------------------------------

## The view shown (MwRinkViews; the session's setting).
func view() -> int:
	return MwRinkViews.view_of(session)


## The birds-eye view's layout: the goals left and right (true).
func birds_eye_across() -> bool:
	return MwRinkViews.across_of(session)


## True when the rink shows in 3D.
func view_3d() -> bool:
	return MwRinkViews.is_3d(view())


## Shows view [param v] (MwRinkViews); the birds-eye view picked again
## switches its layout. The view picked shows the current pass at once.
func select_view(v: int) -> void:
	MwRinkViews.select(session, v)          # (without a session: MwRinkViews.lone_view)
	if not rom.is_empty() and state != null:
		_present(false)


func _unhandled_input(event: InputEvent) -> void:
	if _reckoning_key(event, KEY_F9):
		get_viewport().set_input_as_handled()
		MwNetReckoning.enabled = not MwNetReckoning.enabled    # plan 35 work item 5: the debug switch
		if not rom.is_empty() and state != null:
			_present(false)
		return
	if _reckoning_key(event, KEY_F10):
		get_viewport().set_input_as_handled()
		MwNetRunAhead.enabled = not MwNetRunAhead.enabled      # plan 41 work item 2: the run-ahead's
		if not rom.is_empty() and state != null:
			_present(false)
		return
	if phases != null and phases.paused:
		return                                # the pause menu has the pads (its Back, Select's too)
	var v := MwRinkViews.picked(event, view(), not MwFlow.online(session), MwRinkViews.extended_of(session))
	if v >= 0:
		get_viewport().set_input_as_handled()
		select_view(v)


## F9 / F10 ([param key]) in a debug build online: the dead reckoning's
## and the run-ahead's debug switches (plan 35 work item 5, plan 41 work
## item 2; keys no view or binding uses).
func _reckoning_key(event: InputEvent, key: Key) -> bool:
	return OS.is_debug_build() and MwFlow.online(session) and event is InputEventKey \
			and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == key


## Player [param player]'s controller layout as the game's logic reads it
## (plan 35: the session's player table - online the player's own machine's
## - else this machine's settings).
func _layout_of(player: int) -> String:
	return session.layout_of(player) if session else MwSettings.layout(player)


## The pads' turns for the view shown (MwLiveInput.turns): every pad by the
## view's turn, player 1's by the camera's heading in first person; none
## while paused (the pause menu reads the pads as they are), in playback, or
## once the rink is leaving.
func _update_turns() -> void:
	var t := 0
	var first := 0
	if view_3d() and not leaving() and _playback.is_empty() and (phases == null or not phases.paused):
		t = MwRinkViews.turn(view(), birds_eye_across())
		first = t
		if view() == MwRinkViews.FIRST_PERSON:
			var host := MwRink3DHost.existing(get_tree())
			if host != null and host.is_built():
				first = host.view().camera.turn_eighths()
	var turns := PackedInt32Array()
	turns.resize(MwVerbs.PLAYERS)
	turns.fill(t)
	# the first person's player: pad 1's (plan 34: the rider's, MwRinkShot3D.rider_pad)
	var rider := MwRinkShot3D.rider_pad(state) if state != null else 0
	turns[(session.player_on_pad(rider + 1) if session else rider + 1) - 1] = first
	MwLiveInput.turns = turns


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
	MwLiveInput.turns = PackedInt32Array()
	if sim != null:
		sim.dispose()                        # plan 45: its cycles would keep the match's state
	var host := MwRink3DHost.existing(get_tree())
	if host != null:
		host.release(self)
