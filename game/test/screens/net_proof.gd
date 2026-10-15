extends RefCounted
## Plan 35's offline proof (docs/net.md): a local match recorded - its start
## record, its input stream (live_match.gd's bots captured tick by tick:
## held actions, press counters, sticks), its hashes (the rink every pass,
## the session at every screen change) - and replayed from the record and
## the stream alone, giving the same hashes. Used by net_determinism.gd
## (two processes, tools/bin/net-determinism) and the GUT test
## (test_net_proof.gd, one process).

const Bots := preload("res://test/support/bots.gd")


## Records a match from the game setup (screen 1) for [param ticks] ticks:
## [param opts] as live_match.gd's options ("seed", "pads", "minutes",
## "penalties", "teams", "humans", "owners", "captains", "bots", "view";
## "heights": the bots' shot heights, MenuBot.height_every; "tick-rate":
## plan 36's TICK RATE, a match rule in the record).
## [param parent] holds the screens while it runs (freed after).
static func record(parent: Node, opts: Dictionary, ticks: int) -> MwNetRecording:
	var rom := MwRom.data()
	var host := Node.new()
	parent.add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(int(opts.get("seed", 1)), 1)
	var su := router.session.setup
	su.pads = int(opts.get("pads", 5))
	su.period_minutes = int(opts.get("minutes", 1))
	su.penalties = int(opts.get("penalties", 1))
	var teams := str(opts.get("teams", "0,5")).split(",")
	su.team_a = int(teams[0])
	su.team_b = int(teams[1])
	MwSettings.start_view = int(opts.get("view", MwRinkViews.FLAT))
	router.session.view = MwSettings.start_view
	var rate_was := MwSettings.tick_rate
	if opts.has("tick-rate"):
		MwSettings.tick_rate = str(opts["tick-rate"]).to_upper()
	var bot := Bots.MenuBot.new()
	bot.router = router
	if opts.has("humans"):
		var humans := Bots.humans_of(str(opts["humans"]))
		if int(opts.get("owners", 0)) != 0:
			for t in 2:
				for i in (humans.teams[t] as Array).size():
					humans.positions[humans.teams[t][i]] = i
		if opts.has("captains"):
			var c := str(opts["captains"]).split(".")
			humans.captains = [int(c[0]), int(c[1]) if c.size() > 1 else 0]
			bot.captains = true
		router.session.humans = humans
		humans.apply_to(su)
		router.session.pad_map = humans.pad_players(rom)
		if int(opts.get("bots", 1)) != 0:
			for t in 2:
				for p: int in humans.teams[t]:
					bot.game_bots.append(Bots.GameBot.new(p, int(opts.get("seed", 1))))
	bot.cpu = su.pads == 5
	bot.height_every = int(opts.get("heights", 0))
	router.screen_entered.connect(bot.on_entered)
	router.screen_resumed.connect(bot.on_resumed)
	host.add_child(router.use_driver_model(rom))
	var rec := MwNetRecording.new()
	rec.record = router.session.to_record(1, router.tick)
	# plan 40 (S5): started as an online match starts from its record (MwGameStart), on
	# the realtime clock: the bots' input goes into the stream as it is sampled
	MwGameStart.begin(router, router.session, rec.record, MwPassClock.realtime())
	MwStreamInput.new(rec.stream, bot).attach(router)
	rec.watch(router)
	MwGameStart.enter_first(router, rec.record)
	for i in ticks:
		router.step()
	_end(router, host)
	MwGameStart.own_context()
	MwSettings.tick_rate = rate_was
	return rec


## Replays [param rec] from its record and stream alone (a fresh session,
## the record's match rules in force and its custom teams in use - plan 38:
## none when it has none, whatever this machine's bank - the pass clock in
## stream mode, the sound driver's model): the hashes it gives.
static func replay(parent: Node, rec: MwNetRecording) -> Array:
	var host := Node.new()
	parent.add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	MwSettings.start_view = -1                  # this machine's own view: the record decides the opening's flow
	host.add_child(router.use_driver_model(MwRom.data()))
	# plan 40 (S5): as every machine of an online match starts (MwGameStart)
	MwGameStart.begin(router, MwSession.new(1, 1), rec.record, MwPassClock.streamed(rec.stream))
	MwStreamInput.new(rec.stream).attach(router)
	var mine := MwNetRecording.new()
	mine.watch(router)
	MwGameStart.enter_first(router, rec.record)
	while router.step():
		pass
	_end(router, host)
	MwGameStart.own_context()
	return mine.hashes


static func _end(router: MwRouter, host: Node) -> void:
	router.stack.clear()
	if MwSound.driver == router.audio:
		MwSound.driver = null
	MwSettings.start_view = -1
	host.get_parent().remove_child(host)
	host.free()                              # the screens with it (they are its children)
