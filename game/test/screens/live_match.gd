extends SceneTree
## Plan 11's live flow check, headless: a whole match through the router
## and the real scenes (the main menu, the matchup, the rink, every screen
## between plays) with a menu bot on the pads, at full speed.
##
##   tools/bin/godot-headless -s res://test/screens/live_match.gd -- [options]
##     --pads N       pad mode (5: CPU vs CPU, default; 0: P1 vs CPU ...)
##     --minutes N    period length in minutes (default 1)
##     --penalties N  0 / 1 (default 1)
##     --teams A,B    (default 0,5)
##     --seed N       the session's RNG seed (default 1)
##     --ticks N      give up after N ticks (default 200000)
##     --detours N    scoreboard visits that take a detour first (8 / 7 / 10; default 6)
##     --view3d N     1: the rink in its 3D follow view (plan 14 phase B; default 0) -
##                    the flow and the result must be the 2D run's
##     --view N       the rink's view (MwRinkViews, 0-8 - 8: 3D EXTENDED; overrides --view3d)
##     --humans A.B   plan 34: who plays, team A's players then team B's, "+"
##                    between numbers ("1+2+3." three on team A, ".5+7" team B
##                    only, "1+2+3+4+5+6.7+8+9+10+11+12" six a side); overrides
##                    --pads (the original's set-ups get their pad mode, the
##                    others play as extended set-ups)
##     --bots N       1: every playing human's pad driven by a gameplay bot on
##                    the rink and in fights (moves, passes, shots, checks;
##                    never Start); default 1 with --humans, else 0
##     --owners 1     plan 34 work item 9: each team's players own C, LW, RW,
##                    LD, RD, G in number order (an extended set-up's), as
##                    character selection would leave them
##     --captains A.B the teams' captains (player numbers; 0 none): captain mode
##                    (the control layer's invariants are checked every tick
##                    of the rink: MwRinkControl.check)
##     --menus P      who presses on the original's screens past the game
##                    setup: a player number ("9"), "+" between several, or
##                    "all" (every playing human); default 1. The title, the
##                    game setup and the port's pages stay player 1's (the
##                    host's), who presses on the game-over scoreboards too
##                    (SAVE REPLAY? is the host's question)
##     --quit P       players who QUIT GAME at the match's first rink pass (as
##                    from their own menu, MwRinkControl.request: the pause
##                    menu has none) ("+" between numbers; a whole team: the CPU team's
##                    decisions; everyone: both teams the CPU's) - nothing
##                    may wait on them
##     --leave P      a spectated match (--humans "." : nobody on a team, the port's
##                    CPU v CPU exhibition): player P pauses the rink's open play
##                    after --leave-at ticks (default 3000) and picks QUIT GAME,
##                    YES - the run must reach the game options (the game setup)
##                    with no game-over scoreboard. With --humans ".", --menus takes any player
##                    numbers (nobody plays: anyone continues between plays)
##     --tick-rate R  OVERCLOCKED (default), APPROXIMATED or ORIGINAL (plan 36: the rink's
##                    passes as long as the original's; the summary gives the
##                    rink passes' elapsed ticks, to set against BlastEm's)
##
## Start goes to every pad on the special plays screen (its second page
## waits for its own player). Prints each screen entry (tick, screen, entry) and a summary; exits 0
## when the match got back to the main menu (or the playoffs) through a
## game-over scoreboard with no script error, else 1.

const RINK := [4, 5, 6]


## The bots (plan 40: test/support/bots.gd; these names kept for the scripts
## that reach them through this one).
const Bots := preload("res://test/support/bots.gd")
const MenuBot = Bots.MenuBot
const GameBot = Bots.GameBot


## The players of [param spec] (--humans: "A.B", "+" between numbers).
static func humans_of(spec: String) -> MwHumans:
	return Bots.humans_of(spec)


var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	var args := _args()
	var host := Node.new()
	root.add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(int(args.get("seed", "1")), 1)
	var su := router.session.setup
	su.pads = int(args.get("pads", "5"))
	su.period_minutes = int(args.get("minutes", "1"))
	su.penalties = int(args.get("penalties", "1"))
	var teams := str(args.get("teams", "0,5")).split(",")
	su.team_a = int(teams[0])
	su.team_b = int(teams[1])
	# every match starts in the options' view (the matchup sets it): override that
	MwSettings.start_view = MwRinkViews.FOLLOW if int(args.get("view3d", "0")) != 0 else MwRinkViews.FLAT
	if args.has("view"):
		MwSettings.start_view = int(args["view"])
	router.session.view = MwSettings.start_view
	var rate_was := MwSettings.tick_rate
	MwSettings.tick_rate = str(args.get("tick-rate", MwSettings.TICK_RATES[0])).to_upper()
	var rink_passes := {}            # elapsed ticks -> rink passes (live play, not paused)
	router.pass_ended.connect(func(b: Dictionary) -> void:
		if int(b.screen) in RINK:
			rink_passes[int(b.elapsed)] = int(rink_passes.get(int(b.elapsed), 0)) + 1)
	var bot := MenuBot.new()
	bot.router = router
	bot.detours = int(args.get("detours", "6"))
	if args.has("humans"):
		var humans := humans_of(str(args["humans"]))
		if int(args.get("owners", "0")) != 0:
			for t in 2:
				for i in (humans.teams[t] as Array).size():
					humans.positions[humans.teams[t][i]] = i
		if args.has("captains"):
			var c := str(args["captains"]).split(".")
			humans.captains = [int(c[0]), int(c[1]) if c.size() > 1 else 0]
			bot.captains = true
		if args.has("menus") and humans.total() == 0:
			bot.menu_players = []                  # a spectated match: anyone continues
			for p in range(1, MwVerbs.PLAYERS + 1):
				if str(args["menus"]) == "all" or str(p) in str(args["menus"]).split("+"):
					bot.menu_players.append(p)
		elif args.has("menus"):
			bot.menu_players = []
			for t in 2:
				for p: int in humans.teams[t]:
					if str(args["menus"]) == "all" or str(p) in str(args["menus"]).split("+"):
						bot.menu_players.append(p)
		router.session.humans = humans
		humans.apply_to(su)
		router.session.pad_map = humans.pad_players(MwRom.data())
		if int(args.get("bots", "1")) != 0:
			for t in 2:
				for p: int in humans.teams[t]:
					bot.game_bots.append(GameBot.new(p, int(args.get("seed", "1"))))
		print("players %s, pad mode %d%s" % [str(humans.teams), su.pads,
				" (extended)" if not humans.match_pads().is_empty() else ""])
	var spectated := router.session.spectated()
	# CPU v CPU: no special plays (the attract demo's pad mode: page B never
	# finishes) - a spectated match's B picks nothing, so it is tried there
	bot.cpu = su.pads == 5 and not spectated
	if spectated:
		print("spectated (CPU v CPU exhibition): menus %s" % str(bot.menu_players))
	if args.has("leave"):
		bot.leave_player = int(args["leave"])
		bot.leave_at = int(args.get("leave-at", "3000"))
	router.screen_entered.connect(bot.on_entered)
	router.screen_resumed.connect(bot.on_resumed)
	router.input = bot
	host.add_child(router.use_driver_model(MwRom.data()))   # (plan 40, D6: the one "still playing?")
	var entries: Array = []
	router.screen_entered.connect(func(id: int, _visit: int, tick: int, prev: int) -> void:
		var e := router.current().entry if router.current() else ""
		entries.append([tick, id, prev, e])
		print("%7d  %2d <- %2d  %s" % [tick, id, prev, e]))
	router.screen_resumed.connect(func(id: int, _visit: int, tick: int) -> void:
		print("%7d  %2d (resumed)" % [tick, id]))
	var menu := (load(MwScreens.scene_path(1)) as PackedScene).instantiate() as MwScreen
	fader.cover()
	router.adopt(menu)
	var quits := str(args.get("quit", "")).split("+", false)
	var limit := int(args.get("ticks", "200000"))
	var started := Time.get_ticks_msec()
	var game_over := false
	var done := false
	var n := 0
	var broken := 0
	while n < limit:
		router.step()
		n += 1
		var id := router.current_id()
		var live: MwRinkState = router.session.screens.get("rink") as MwRinkState
		if not quits.is_empty() and live != null and live.control != null:
			for quitter in quits:
				live.control.request(int(quitter), "quit")    # plan 34: at the next pass
			print("quit: %s" % str(quits))
			quits = PackedStringArray()
		if live != null and live.control != null and id >= 4 and id <= 6:
			var text := live.control.check(live)
			if text != "":
				broken += 1
				if broken < 5:
					print("control: %s (tick %d)" % [text, n])
		if id in [15, 16]:
			game_over = true
		if game_over and id in [1, 11] and n > 1000:
			done = true
			break
		if bot.left and id == 1 and not router.busy():
			done = not game_over and router.history.size() >= 2 and router.history[-2] in RINK
			print("left the match for the game setup%s" % ("" if done else " - through a scoreboard!"))
			break
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	var seen := {}
	for e in entries:
		seen[int(e[1])] = int(seen.get(int(e[1]), 0)) + 1
	var state: MwRinkState = router.session.screens.get("rink") as MwRinkState
	print("ticks %d in %.1f s (%.0f ticks/s); screens %s" % [n, secs, n / maxf(secs, 0.001), str(seen)])
	if state:
		print("score %d-%d, period %d" % [state.teams[0].score if "score" in state.teams[0] else -1,
			state.teams[1].score if "score" in state.teams[1] else -1, state.period])
	print("presses: %d" % bot.log.size())
	if broken > 0:
		print("control invariants broken on %d ticks" % broken)
		done = false
	if spectated and seen.has(10):
		print("a spectated match reached the special plays page")
		done = false
	var passes := 0
	var ticks := 0
	for e in rink_passes:
		passes += int(rink_passes[e])
		ticks += int(e) * int(rink_passes[e])
	if passes > 0:
		var dist := []
		for e in range(1, 10):
			dist.append("%d:%.3f" % [e, float(rink_passes.get(e, 0)) / passes])
		print("rink passes (TICK RATE %s): %d, mean %.3f ticks; elapsed %s" % [MwSettings.tick_rate, passes,
				float(ticks) / passes, " ".join(dist)])
	MwSettings.tick_rate = rate_was
	print("RESULT %s" % ("ok" if done else "tick limit, on screen %d" % router.current_id()))
	quit(0 if done else 1)
	return true


func _args() -> Dictionary:
	return preload("res://test/support/cli.gd").args()      # (plan 40: one copy)
