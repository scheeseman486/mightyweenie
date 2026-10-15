extends "res://test/rom/rom_test_base.gd"
## Plan 34, work item 8: an extended set-up (more players than the
## original's pad modes) through the real scenes - the rink reading every
## player's pad (players 1-12 as the match's pads, nothing remapped by the
## router), drawing their markers; the screens between plays reading the
## twelve pads (the special plays' page B for team B only). A spectated
## match (the port's CPU v CPU exhibition, nobody on a team): every
## player's press counts between plays, and no special plays are picked.

const Bots := preload("res://test/support/bots.gd")

var host: Node


func after_each() -> void:
	if host:
		host.free()
		host = null


## A router on screen [param id] for the players [param spec] (live_match's
## --humans form), with a gameplay bot on every player's pad and the menu
## bot ([member Bots.MenuBot]); [param state]: a rink state for the screens
## between plays.
func _router(id: int, spec: String, state: MwRinkState = null) -> MwRouter:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(5, 1)
	var humans := Bots.humans_of(spec)
	router.session.humans = humans
	humans.apply_to(router.session.setup)
	router.session.pad_map = humans.pad_players(rom)
	if state != null:
		router.session.screens["rink"] = state
	var bot := Bots.MenuBot.new()
	bot.router = router
	for t in 2:
		for p: int in humans.teams[t]:
			bot.game_bots.append(Bots.GameBot.new(p, 3))
	router.screen_entered.connect(bot.on_entered)
	router.screen_resumed.connect(bot.on_resumed)
	router.input = bot
	var scene := (load(MwScreens.scene_path(id)) as PackedScene).instantiate() as MwScreen
	scene.screen_id = id
	router.adopt(scene)
	fader.uncover()
	return router


func test_the_rink_reads_every_players_pad() -> void:
	if not need_rom():
		return
	var router := _router(4, "1+5+9+12.2+7")
	assert_true(MwHumans.identity(router.session.pad_map), "nothing remapped")
	var drove := {}
	var marks := 0
	var screens := {}
	router.screen_entered.connect(func(id: int, _v: int, _t: int, _p: int) -> void: screens[id] = true)
	for n in 2500:
		router.step()
		var rink := router.current() as MwRink
		if rink == null or rink.state == null:
			continue
		var state := rink.state
		if not state.extended:
			fail_test("the rink's state isn't the extended set-up's")
			return
		for team in state.teams:
			for p in team.players:
				if p.present and p.flags & MwRinkState.Player.HUMAN and state.pads_held[p.pad] != 0:
					drove[p.pad] = true
		marks = maxi(marks, rink.update.drawer.port_calls.size() if rink.update else 0)
	assert_eq(drove.keys().size(), 6, "every player's pad reached the skater they drive")
	assert_true(drove.has(11), "player 12's among them")
	assert_gt(marks, 6 * 3, "the players' markers, plates and tags drawn")
	gut.p("screens entered: %s" % str(screens.keys()))


func test_special_plays_page_b_for_team_b_only() -> void:
	if not need_rom():
		return
	var state := MwRinkState.new()
	state.rng = MlhRng.new(7)
	var sim := MwRinkSim.new(rom, state)
	var su := MwMatchSetup.new()
	var humans := Bots.humans_of(".6+11")
	humans.apply_to(su)
	MwRinkMatch.start(sim, 4, 9, 4, su.pads, true, 2, humans.match_pads())   # (plan 40, S13: the players' pads)
	MwRinkMatch.boot_icons(sim)
	state.period = 1
	state.clock = 180
	var router := _router(10, ".6+11", state)
	router.input = MwInputSource.new()
	for n in 60:
		router.step()
	var sp := (router.current() as MwBetweenPlays).sim as MwSpecialPlaysSim
	assert_eq(sp.live_page, 1)
	var cursor := sp.pages[1].cursor
	router.input = _Hold.new(MwVerbs.pad_actions(11, 0x02, MwScreens.contexts(10)))
	for n in 4:
		router.step()
	assert_ne(sp.pages[1].cursor, cursor, "player 11's Down, read among the twelve pads, moves page B")


class _Hold extends MwInputSource:
	var held := {}
	func _init(h: Dictionary) -> void:
		held = h
	func sample(_contexts: Array) -> Dictionary:
		return held.duplicate()


## A spectated match's goal scoreboard (MwRinkState.spectated): any
## player's press (nobody plays: players 1-12 alike) shows the menu and
## picks from it - but not its B, the special plays (the CPU decides for
## both teams), whose line isn't drawn.
func test_spectators_continue_between_plays_but_pick_no_special_plays() -> void:
	if not need_rom():
		return
	var state := MwRinkState.new()
	state.rng = MlhRng.new(7)
	var sim := MwRinkSim.new(rom, state)
	MwRinkMatch.start(sim, 4, 9, 4, 5, false, 2)
	MwRinkMatch.boot_icons(sim)
	MwRinkPhases.new(MwRinkUpdate.new(sim)).enter(5)
	state.period = 1
	state.clock = 180
	state.spectated = true
	state.phase = 3
	state.goal_kind = 0
	state.scoring = 0xFFFF0000 | int(MwScoreboardSim.TEAM_WORDS[0])
	state.scorer = MwScoreboardSim.player_long(state.teams[0].players[2])
	var router := _router(12, ".", state)
	assert_true(router.session.spectated())
	router.input = _Hold.new({})
	for n in 20:
		router.step()
	var sb := router.current() as MwBetweenPlays
	var board := sb.sim as MwScoreboardSim
	assert_eq(board.menu, 0, "the comment first")
	router.input = _Hold.new(MwVerbs.pad_actions(9, 0x80, MwScreens.contexts(12)))
	for n in 3:
		router.step()
	assert_eq(board.menu, 1, "player 9's Start shows the menu")
	router.input = _Hold.new({})
	for n in 80:
		router.step()
	router.input = _Hold.new(MwVerbs.pad_actions(4, 0x10, MwScreens.contexts(12)))
	for n in 3:
		router.step()
	router.input = _Hold.new({})
	for n in 20:
		router.step()
	assert_false(router.busy(), "B: no special plays page")
	assert_eq(router.current(), sb)
	router.input = _Hold.new(MwVerbs.pad_actions(11, 0x20, MwScreens.contexts(12)))
	for n in 3:
		router.step()
	assert_true(router.busy(), "player 11's C: the instant replay")
	assert_eq(router.pending_id(), 7)
	for reserves in [false, true]:
		var lines := MwScoreboardBackdrop.menu_texts(rom, 12, reserves)
		assert_eq(lines.filter(func(op: Array) -> bool: return MwScoreboardBackdrop.is_plays_line(rom, op)).size(), 1,
				"one B line (Reserves %s) left out" % str(reserves))
	var over := MwScoreboardBackdrop.menu_texts(rom, 15, false)
	assert_eq(over.filter(func(op: Array) -> bool: return MwScoreboardBackdrop.is_plays_line(rom, op)).size(), 0,
			"15 / 16 have none")
	var held := [0, 0, 0, 0]
	var new := [0, 0, 0, 0]
	MwBetweenPlays.spectators(MwInputFrame.make(MwVerbs.pad_actions(12, 0x90, MwScreens.contexts(12)), {}),
			MwScreens.contexts(12), held, new, true)
	assert_eq(new, [0x80, 0x80, 0x80, 0x80], "player 12's Start on every pad, its B on none (a menu up)")
