extends "res://test/rom/rom_test_base.gd"
## Plan 45: what the game is done with is freed. The rink sim's parts and its
## CPU AI keep the sim, the control layer keeps the state it worked on - and
## RefCounted objects in a cycle are never freed - so a match's state (its
## full replay, its paint: tens of MB a match) outlived the match, every
## match and every attract demo. MwRinkSim.dispose, MwScreenSim.dispose and
## MwRinkState.retire break the cycles where the owners are done; these
## tests hold a weak reference and check it is gone.

const Bots := preload("res://test/support/bots.gd")


## A CPU v CPU match at its first faceoff, played [param passes] passes:
## [state, sim, update, phases].
func _played(passes: int) -> Array:
	var s := MwRinkState.new()
	s.rng = MlhRng.new(7)
	var sim := MwRinkSim.new(rom, s)
	sim.cpu = MwRinkAI.new()
	var update := MwRinkUpdate.new(sim)
	var phases := MwRinkPhases.new(update)
	MwRinkMatch.start(sim, 3, 3, 7, 4, false, 2)
	s.period = 1
	s.period_minutes = 5
	s.clock = 300
	phases.enter(5)
	for i in passes:
		var to := update.run_pass(2, phases)
		if to >= 0:
			MwRinkMatch.rink_exit(sim, to)
			phases.enter(5)
	return [s, sim, update, phases]


func test_a_disposed_sim_lets_its_state_go() -> void:
	if not need_rom():
		return
	var game := _played(200)
	var state_ref: WeakRef = weakref(game[0])
	var sim_ref: WeakRef = weakref(game[1])
	(game[1] as MwRinkSim).dispose()
	game.clear()
	assert_null(sim_ref.get_ref(), "the sim freed")
	assert_null(state_ref.get_ref(), "its state freed")


func test_without_dispose_the_sim_keeps_its_state() -> void:
	# the cycle the dispose breaks (if this fails, the cycle is gone and dispose is no longer needed)
	if not need_rom():
		return
	var game := _played(20)
	var state_ref: WeakRef = weakref(game[0])
	var sim: MwRinkSim = game[1]
	game.clear()
	assert_not_null(state_ref.get_ref(), "the sim's cycle keeps the state")
	sim.dispose()
	sim = null
	assert_null(state_ref.get_ref(), "freed once disposed")


func test_a_retired_state_with_its_control_layer_is_freed() -> void:
	if not need_rom():
		return
	var humans := Bots.humans_of("1+2.3")
	var s := MwRinkState.new()
	s.control = MwRinkControl.make(humans, humans.pad_players(rom), rom)
	s.control.check(s)                       # (the control layer keeps the state it worked on)
	var state_ref: WeakRef = weakref(s)
	s.retire()
	s = null
	assert_null(state_ref.get_ref(), "the state and its control layer freed")


func test_a_screens_sim_lets_the_match_state_go() -> void:
	if not need_rom():
		return
	var game := _played(60)
	(game[1] as MwRinkSim).dispose()
	var s: MwRinkState = game[0]
	game.clear()
	var state_ref: WeakRef = weakref(s)
	var board := MwScreenSims.make(12, rom)     # a scoreboard: it runs the rink's code with a sim of its own
	board.enter(s, 12, 4)
	s = null
	board = null                                # (its PREDELETE disposes its rink sim)
	assert_null(state_ref.get_ref(), "the match's state freed with the screen's sim")


## A whole CPU v CPU match through the router and the real scenes (1-minute
## periods): once the session lets go of it as a new match does, nothing else
## keeps the match's state - its full replay, its paint (the rink's sim, the
## screens' sims, the rehearsal disposed).
func test_a_finished_match_is_freed() -> void:
	if not need_rom():
		return
	var host := Node.new()
	add_child_autofree(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(1, 1)
	var setup := router.session.setup
	setup.pads = 5
	setup.period_minutes = 1
	setup.penalties = 1
	setup.team_a = 0
	setup.team_b = 5
	var view_was := MwSettings.start_view
	MwSettings.start_view = MwRinkViews.FLAT
	router.session.view = MwSettings.start_view
	var bot := Bots.MenuBot.new()
	bot.router = router
	bot.detours = 0
	bot.cpu = true
	router.screen_entered.connect(bot.on_entered)
	router.screen_resumed.connect(bot.on_resumed)
	router.input = bot
	host.add_child(router.use_driver_model(rom))
	var menu := (load(MwScreens.scene_path(1)) as PackedScene).instantiate() as MwScreen
	fader.cover()
	router.adopt(menu)
	var game_over := false
	var state_ref: WeakRef = null
	var replay_ref: WeakRef = null
	for n in 60000:
		router.step()
		var st := router.session.screens.get("rink") as MwRinkState
		if st != null and state_ref == null:
			state_ref = weakref(st)
		if st != null and st.full_replay != null and replay_ref == null:
			replay_ref = weakref(st.full_replay)
		if router.current_id() in [15, 16]:
			game_over = true
		if game_over and router.current_id() in [1, 11] and n > 1000:
			break
	MwSettings.start_view = view_was
	assert_true(game_over, "the match was played to its end")
	assert_not_null(state_ref, "a match state was made")
	# the session lets go of the match, as a new match's entry does (MwRink._live_entry: the last
	# match's state retired; MwSession.reset_from_record the same)
	(router.session.screens["rink"] as MwRinkState).retire()
	router.session.screens.erase("rink")
	await wait_physics_frames(2)                 # (the screens' scenes freed)
	assert_null(state_ref.get_ref(), "the match's state freed")
	assert_null(replay_ref.get_ref() if replay_ref != null else null, "its full replay freed")
