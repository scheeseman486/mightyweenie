extends RefCounted
## Plan 35 work item 4's online matches in one process: a host and clients
## on the loopback network (net_test_base.gd's World, seeded loss, delay,
## jitter, duplication, reordering, outages), each machine running the
## whole game - its own router, the real screens, its own sound driver
## model - through MwNetMatch, its players driven by bots of its own
## ([NetBot]) that look only at that machine's game. Used by
## test_net_match.gd (GUT); online_match.gd uses the bots (a whole match,
## a process a machine).
##
## One process holds every machine, so the few statics the game keeps per
## process (the sound driver and its port bookkeeping, MwLiveInput.turns,
## plan 38's custom team bank and its view past the ROM) are swapped in and
## out around each machine's frame ([Machine]; [method Machine.set_bank]
## gives a machine a bank of its own).
##
## Work item 6 (rejoin and resync): a machine's connection dropped
## ([method drop]), the machine back with its key - as it was, or as a fresh
## process with only the rejoin record on disk ([method rejoin]) - waiting
## for its snapshot (MwNetMatch.start_rejoin); a change made to every
## machine's game at the same stream tick ([method at_tick]: the period's
## clock run down, so a safe point comes soon).

const NetBase := preload("res://test/net/net_test_base.gd")
const Bots := preload("res://test/support/bots.gd")

## A frame's milliseconds (60 Hz: 17, 17, 16).
const FRAME_MS := [17, 17, 16]


## What MwNetMatch reads from work item 3's MwNetService.
class Service extends RefCounted:
	var host: MwNetHost
	var client: MwNetClient
	var local_input: MwInputSource


## One machine: its router and screens under a node of its own, its
## session, its service, its bot and - once START came - its match.
class Machine extends RefCounted:
	var id := 0
	var name := ""
	var node: Node
	var fader: MwScreenFader
	var router: MwRouter
	var session: MwSession
	var service := Service.new()
	var bot: NetBot
	var net_match: MwNetMatch
	## Its frames skipped (a silent machine: nothing sent, nothing run).
	var frozen := false
	## Why its match ended (-1: running or not started).
	var ended := -1
	## What [method watch] saw change: name -> [[stream tick, value] ...].
	var events := {}
	## The snapshot loads seen (MwNetMatch.synced_at; the harness's stall
	## count starts again after each).
	var synced_seen := -1
	var _watched := {}
	var _statics := {}

	## After every pass of this machine's game, [param probe] (this machine
	## -> a value) - each change noted in [member events] with its stream
	## tick, so machines can be compared tick for tick.
	func watch(what: String, probe: Callable) -> void:
		events[what] = []
		router.pass_ended.connect(func(_b: Dictionary) -> void:
			if net_match == null or net_match.phase != MwNetMatch.Phase.PLAYING:
				return
			var v: Variant = probe.call(self)
			if not _watched.has(what) or _watched[what] != v:
				_watched[what] = v
				(events[what] as Array).append([net_match.stream_tick(router.tick), v]))

	func _init(parent: Node, name_: String) -> void:
		name = name_
		node = Node.new()
		node.name = name_
		parent.add_child(node)
		fader = MwScreenFader.new()
		node.add_child(fader)
		router = MwRouter.new(node, fader)
		router.session = MwSession.new(1, 1)
		session = router.session
		router.factory = func(id_: Variant) -> MwScreen:
			if id_ is int and int(id_) in [MwFlow.ONLINE_MENU, MwFlow.ONLINE_LOBBY]:
				var stand_in := MwScreen.new()        # work item 3's pages: stand-ins here
				stand_in.screen_id = int(id_)
				return stand_in
			return MwRouter.instantiate_scene(id_)
		var audio := router.use_driver_model(MwRom.data())
		node.add_child(audio)
		_statics = {"driver": audio, "heard": null, "carried": MwSound.NONE, "fade": false,
				"turns": PackedInt32Array(), "bank": MwCustomTeams.save_state()}
		bot = NetBot.new()
		bot.router = router
		router.screen_entered.connect(bot.on_entered)
		router.screen_resumed.connect(bot.on_resumed)
		service.local_input = bot

	## This machine's statics in (before its frame).
	func enter() -> void:
		MwSound.driver = _statics["driver"]
		MwSound.heard = _statics["heard"]         # (plan 41 work item 3: a client's heard driver)
		MwSound.carried = _statics["carried"]
		MwSound._fade_pending = _statics["fade"]
		MwLiveInput.turns = _statics["turns"]
		MwCustomTeams.load_state(_statics["bank"])

	## ... and out (after it).
	func leave() -> void:
		_statics = {"driver": MwSound.driver, "heard": MwSound.heard, "carried": MwSound.carried,
				"fade": MwSound._fade_pending,
				"turns": MwLiveInput.turns,
				"bank": MwCustomTeams.save_state()}

	## Plan 38: this machine's own custom team bank is [param teams] (none put
	## aside, nothing being edited).
	func set_bank(teams: Array) -> void:
		enter()
		MwCustomTeams.clear()
		for team: MwCustomTeam in teams:
			MwCustomTeams.teams.append(team)
		MwCustomTeams.rebuild()
		leave()

	## Plan 38: this machine's bank as it is now: {teams, in_use, overlay}.
	func bank() -> Dictionary:
		enter()
		var out := {"teams": MwCustomTeams.teams.duplicate(), "in_use": MwCustomTeams.teams_in_use(),
				"overlay": MwRom.overlay()}
		leave()
		return out

	func rink() -> MwRinkState:
		return session.screens.get("rink") as MwRinkState

	func free_all() -> void:
		router.driver = null
		for stacked in router.stack:
			if stacked.get_parent():
				stacked.get_parent().remove_child(stacked)
			stacked.free()
		router.stack.clear()
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()


## A machine's players as bots: menus pressed as a player would (only this
## machine's players, only what this machine's game shows), gameplay bots on
## the rink (live_match.gd's), and a script of presses on top ([member
## presses]: QUIT GAME, a pause, a kick ...). A pattern of taps of one
## harmless verb on the rink counts the presses ([member tapped]).
class NetBot extends MwInputSource:
	var router: MwRouter
	## This machine's players.
	var players: Array[int] = []
	## The controller selection: number -> team (0 A, 1 B) for this
	## machine's players; [member expected] players on teams in all before
	## P1 goes on.
	var teams := {}
	var expected := 0
	## ... or after this many ticks on the controller selection without
	## them (15 s: a machine away; net-mock's bots wait for the person).
	var away_ticks := 900
	## The machine's round trip (ticks): a press whose effect a bot looks for
	## before the next (the selection's cursor moving on to a free card)
	## comes no faster - over a slow link two would land before it saw the
	## first and it could go round the taken cards for ever (net-mock).
	var lag_ticks := 0
	## The game options visited this many times: P1 goes Back to the lobby
	## (0: never).
	var back_after := 0
	## The position (MwLineup: 0 C, 1 LW, 2 RW, 3 LD, 4 RD, 5 G) the bots
	## take only when no other is free on their team - net-mock's, left for
	## the person (owner, 2026-10-12: always left in goal, a forward to stay
	## free; 2026-10-13: the centre in particular): the bots go to the first
	## other free one, across the rows too. -1: each takes the free one its
	## cursor comes to first, as before. The person's cursor starts on it
	## ([method seat_person]).
	var leave_free := -1
	## Gameplay bots (number -> live_match's GameBot).
	var game_bots := {}
	## [router tick, player, action, hold ticks]: scripted presses, in tick
	## order (the actions' names as the router knows them, e.g.
	## "p3_ui_accept").
	var presses: Array = []
	## Taps of [constant TAP_VERB] on the rink, every [member tap_every]
	## ticks (0: none), until [member tap_until] (router tick).
	var tap_every := 0
	var tap_until := 1 << 30
	var tapped := {}
	var _tapped_at := -1
	var quiet := false
	var screen := -1
	var entered := 0
	var visits := {}
	var _held := {}
	var _taps := {}
	var _hold := {}       # action -> release tick
	var _next_press := 0
	var _was := {}
	var seed_value := 1
	## Called every tick with this bot (scripted play that looks at the
	## game: a pause menu's items, a list).
	var hook := Callable()
	## Ticks before a player presses on a scoreboard, the replay or the
	## stats (plus 7 a player number; work item 7's soak shortens it).
	var wait := 400
	## Shot heights (MwSettings.shot_heights' form, MwInputSource.heights):
	## every [member height_every] ticks on the rink each of this machine's
	## players holds the next height (-1 the D-pad's, 0 none, 1 high, 2 low),
	## the other players the D-pad's (0: no heights - as the option off).
	var height_every := 0
	var _heights: Array = []

	const TAP_VERB := "zamboni_whip"

	func on_entered(id: int, _visit: int, tick_: int, _prev: int) -> void:
		screen = id
		entered = tick_
		visits[id] = int(visits.get(id, 0)) + 1

	func on_resumed(id: int, _visit: int, tick_: int) -> void:
		screen = id
		entered = tick_

	## [param action] held for [param ticks] ticks from now (unless held).
	func pulse(action: String, ticks := 4) -> void:
		_pulse(action, ticks)

	func _pulse(action: String, ticks := 4) -> void:
		var t := router.tick
		if not _hold.has(action):
			_hold[action] = t + ticks

	## Every [param every] ticks from [param after] ticks after the screen's
	## entry: [param verb] pressed for player [param p].
	func _every(p: int, verb: String, after: int, every: int) -> void:
		var since := router.tick - entered - after
		if since >= 0 and since % every == 0:
			_pulse(MwVerbs.player_action(p, verb))

	func tick() -> void:
		var t := router.tick
		for a in _hold.keys():
			if t >= int(_hold[a]):
				_hold.erase(a)
		while _next_press < presses.size() and int(presses[_next_press][0]) <= t:
			var press: Array = presses[_next_press]       # (a client's tick may jump by two)
			_hold[str(press[2])] = t + int(press[3])
			_next_press += 1
		if not quiet:
			_menus(t)
		if hook.is_valid():
			hook.call(self)
		_held = {}
		for a in _hold:
			_held[a] = true
		if screen in [4, 5, 6, 18] and not quiet:
			# the play's verbs only (the pause menu's own on the same buttons
			# would steer a menu the player has open)
			var ctx := [MwVerbs.Context.FIGHT] if screen == 18 else [MwVerbs.Context.GAMEPLAY]
			for p: int in game_bots:
				if router.session.humans.team_of(p) != MwHumans.MIDDLE:
					_held.merge(MwVerbs.pad_actions(p, (game_bots[p] as Bots.GameBot).mask(t), ctx))
			# (once a tick: a game held on that tick - its stream stalled - would
			# otherwise tap every frame, a burst no player makes: plan 43 met one
			# of 26 presses across a 500 ms outage, past the merge's 16)
			if tap_every > 0 and t < tap_until and t % tap_every == 0 and t != _tapped_at and screen in [4, 5, 6]:
				_tapped_at = t
				for p in players:
					_taps[MwVerbs.action(p, TAP_VERB)] = true
					tapped[p] = int(tapped.get(p, 0)) + 1
		_heights = []
		if height_every > 0 and screen in [4, 5, 6] and not quiet:
			@warning_ignore("integer_division")
			var step := t / height_every
			for n in range(1, MwVerbs.PLAYERS + 1):
				_heights.append(posmod(step + n, 4) - 1 if n in players else -1)
		# as a device's "just pressed": every new hold is also a tap (a press
		# then never gets lost, only late - the stream's press counters)
		for a in _held:
			if not _was.has(a):
				_taps[a] = true
		_was = _held.duplicate()

	func _menus(_t: int) -> void:
		var humans := router.session.humans
		match screen:
			1:
				if 1 in players:
					if back_after > 0 and int(visits.get(1, 0)) > back_after:
						_every(1, "ui_back", 90, 60)
					else:
						_every(1, "ui_accept", 90, 60)
			MwScreens.CONTROLLER_SELECT:
				for p in players:
					if teams.has(p) and humans.team_of(p) != int(teams[p]):
						_every(p, "ui_left" if int(teams[p]) == 0 else "ui_right", 30 + 3 * p, 20)
				# P1 goes on once everyone expected is on a team - or after 15 s
				# without them (a machine away: the soak's lossy networks)
				if 1 in players and (humans.total() >= expected or router.tick - entered > away_ticks):
					_every(1, "ui_accept", 60, 30)
			MwScreens.CHARACTER_SELECT, MwScreens.CAPTAIN_VOTE, MwScreens.LINEUPS:
				_selection(humans)
			3:
				for p in players:
					_every(p, "ui_accept", 120, 60)
			7, 8, 10, 12, 13, 14, 15, 16, 17:
				for p in players:
					_every(p, "ui_accept", wait + 7 * p, 90)

	## The selection steps: pick a free position and lock it, vote, accept
	## the line-up panels.
	func _selection(humans: MwHumans) -> void:
		var cs := router.current() as MwCharacterSelect
		if cs == null:
			return
		for p in players:
			if humans.team_of(p) == MwHumans.MIDDLE:
				continue
			var t := humans.team_of(p)
			match cs.stage:
				MwCharacterSelect.Stage.PICK:
					var pick := int(cs.picks.get(p, MwCharacterSelect.Pick.LOCKED))
					if pick == MwCharacterSelect.Pick.MOVING and leave_free >= 0:
						var at := int(cs.cursor.get(p, 0))
						var want := _free_position(cs.taken[t], at)
						if want == at:
							_every(p, "ui_accept", 26 + 2 * p, 12)
						elif (want >= 3) != (at >= 3):
							_every(p, "ui_down", 20 + 2 * p, 12 + lag_ticks)   # (the other row)
						else:
							_every(p, "ui_right", 20 + 2 * p, 12 + lag_ticks)
					elif pick == MwCharacterSelect.Pick.MOVING:
						var taken: Dictionary = cs.taken[t]
						if taken.has(int(cs.cursor.get(p, 0))):
							_every(p, "ui_right", 20 + 2 * p, 12 + lag_ticks)
						else:
							_every(p, "ui_accept", 26 + 2 * p, 12)
					elif pick == MwCharacterSelect.Pick.PICKED:
						_every(p, "ui_accept", 26 + 2 * p, 12)
				MwCharacterSelect.Stage.VOTE:
					_every(p, "ui_accept", 20 + 2 * p, 15)
				MwCharacterSelect.Stage.PANELS:
					_every(p, "ui_accept", 30 + 2 * p, 20)

	## [param record] (a match's start record, MwNetMatch.host_record's) with
	## net-mock's person, player [param person], seated on their number's side
	## (odd A, even B: as the bots go) with [param pos] the position they last
	## played - so the character selection's cursor starts on it (each
	## player's cursor on their last position: MwCharacterSelect._start_picks)
	## and accepting at once takes it, the bots leaving it ([member
	## leave_free]). Owner, 2026-10-13: no change, still only the goalie - the
	## bots left the centre, but the person's cursor still started on the
	## goalie's card (their team's last player's).
	static func seat_person(record: Dictionary, person: int, pos: int) -> void:
		var h: Dictionary = (record["players"] as Dictionary)["humans"]
		var side: Array = h["a" if person % 2 == 1 else "b"]
		if not person in side:
			side.append(person)
			side.sort()
		(h["positions"] as Dictionary)[str(person)] = pos

	## The position a bot goes for from its cursor [param at], [param taken]
	## the team's taken ones: the first free one in order from the cursor but
	## [member leave_free], that one when no other is free (its cursor where
	## it is when none is).
	func _free_position(taken: Dictionary, at: int) -> int:
		for i in MwLineup.POSITIONS:
			var pos := (at + i) % MwLineup.POSITIONS
			if pos != leave_free and not taken.has(pos):
				return pos
		return leave_free if not taken.has(leave_free) else at

	func sample(_contexts: Array) -> Dictionary:
		return _held

	## Plan 43: the sticks (MwStick codes, players 1-12) at router tick t:
	## [member stick_fn] (t -> PackedInt32Array); none - no stick, the D-pad's.
	var stick_fn := Callable()

	func stick_codes() -> PackedInt32Array:
		return stick_fn.call(router.tick) if stick_fn.is_valid() else PackedInt32Array()

	func heights() -> Array:
		return _heights

	func taps() -> Dictionary:
		var out := _taps
		_taps = {}
		return out


## The network (the loopback's [member world], or real ENet with DTLS on
## 127.0.0.1: [member enet]), the host and the clients, the machines (the
## host first), and what the run measured.
var world: NetBase.World
var enet := false
var host: MwNetHost
var clients: Array[MwNetClient] = []
var machines: Array[Machine] = []
var parent: Node
var frame_no := 0
## The longest wait (ms) between the host making a stream tick and a
## client running it.
var max_stall_ms := 0
## The taps of [constant NetBot.TAP_VERB] in the host's stream, by player,
## and the ticks that carried two of one player's at once (never, by the
## merge's rule).
var taps_seen := {}
var double_taps := 0
## The host's stream ticks that carried a shot height other than the
## D-pad's (NetBot.height_every).
var height_ticks := 0
var _bank_before := {}           # the test's custom team bank (restored by free_all)
var _made_at := {}               # stream tick -> host time
var _ran := {}                   # machine -> stream ticks run so far
var _tap_counters := {}


## A host and [param client_locals] clients (each its number of local
## players) on the loopback under [param conditions], the host's second
## local player joined when [param host_locals] is 2; everyone in the
## lobby. Machines get their players' numbers from the lobby.
## With [param identity] the machines meet over real ENet with DTLS on
## 127.0.0.1 (the host's key and certificate; [param conditions] unused).
func _init(parent_: Node, seed_value: int, conditions := {}, client_locals: Array = [1, 2, 1],
		host_locals := 1, identity: MwNetIdentity = null) -> void:
	parent = parent_
	_bank_before = MwCustomTeams.save_state()
	var all_in := func() -> bool:
		for net_client in clients:
			if net_client.state != MwNetClient.State.LOBBY:
				return false
		return true
	if identity == null:
		var link := conditions.duplicate()
		link.erase("outages")
		# a new host at the loopback's address every time, never a known host whose key changed (plan 45:
		# TRUST is asked with a password too; a script whose before_each doesn't empty the files met it)
		MwNetKnownHosts.forget(NetBase.World.HOST_ADDRESS, MwNetProtocol.PORT)
		world = NetBase.World.new(seed_value, "pw", link)
		host = world.host
		for i in range(2, host_locals + 1):
			host.join_local(i)
		for n in client_locals:
			# one at a time: machine 1 is the first client, its players the next numbers ...
			var net_client := world.join("pw", int(n))
			clients.append(net_client)
			world.run_until(func() -> bool: return net_client.state == MwNetClient.State.LOBBY, 60000)
		world.run(300)
	else:
		enet = true
		var transport := MwNetEnet.host(0, identity)
		host = MwNetHost.new(transport, identity.der, "pw", NetBase.World.net_info())
		host.open()
		for i in range(2, host_locals + 1):
			host.join_local(i)
		var port := (transport as MwNetEnet).local_port()
		for n in client_locals:
			var net_client := MwNetClient.new()
			net_client.info = NetBase.World.net_info()
			net_client.connect_to("127.0.0.1", port, "pw", int(n))
			clients.append(net_client)
			var end := Time.get_ticks_msec() + 20000
			while Time.get_ticks_msec() < end and not all_in.call():
				_poll_all()
				OS.delay_msec(1)
	var hosting := Machine.new(parent, "host")
	hosting.service.host = host
	hosting.id = 0
	machines.append(hosting)
	for net_client in clients:
		var m := Machine.new(parent, "client%d" % net_client.machine)
		m.service.client = net_client
		m.id = net_client.machine
		machines.append(m)
		net_client.started.connect(func(match_id: int, first_tick: int, record: PackedByteArray) -> void:
			m.enter()
			m.net_match = MwNetMatch.start_client(m.session, m.router, m.service, match_id, first_tick, record)
			if m.net_match != null:
				_bots_numbers(m.net_match)
			m.leave())
	for m in machines:
		m.bot.players.assign(host.lobby.numbers_of(m.id))
		m.bot.seed_value = seed_value


## The machine whose id is [param id] (null: none).
func machine(id: int) -> Machine:
	for m in machines:
		if m.id == id:
			return m
	return null


## The network's time: the loopback's clock, or the real one.
func now() -> int:
	return Time.get_ticks_msec() if enet else world.net.now_ms


func _poll_all() -> void:
	var t := now()
	host.poll(t)
	for net_client in clients:
		net_client.poll(t)


## START GAME ([param record]: a start record of the test's own, else the
## host's).
func start(record := {}) -> void:
	var hosting := machines[0]
	hosting.enter()
	hosting.net_match = MwNetMatch.start_host(hosting.session, hosting.router, hosting.service, record)
	_bots_numbers(hosting.net_match)
	hosting.leave()


## A match driven from here: polled by [method frame], its hashes kept, no
## dumps; the bots press their players' own numbers' actions (a machine's
## devices would be its local players 1, 2 ...).
static func _bots_numbers(nm: MwNetMatch) -> void:
	nm.polls = false
	nm.keep_hashes = true
	nm.dumps = false
	for n: int in nm.locals:
		nm.locals[n] = n


## One frame of every machine (the network advanced by a frame's time).
func frame() -> void:
	if not enet:
		world.net.advance(FRAME_MS[frame_no % 3])
	frame_no += 1
	var t := now()
	for m in machines:
		if not m.frozen:
			if m.id == 0:
				host.poll(t)
			else:
				m.enter()
				m.service.client.poll(t)     # START may begin its match
				m.leave()
	for m in machines:
		if m.frozen or m.net_match == null or m.ended >= 0:
			continue
		m.enter()
		var on := m.net_match.frame(t)
		m.leave()
		if m.net_match.synced_at != m.synced_seen:
			# taken up from a snapshot: its stalls count from there
			m.synced_seen = m.net_match.synced_at
			_ran[m.id] = m.net_match.stream_tick(m.router.tick)
		if m.id == 0 and m.net_match.phase == MwNetMatch.Phase.PLAYING:
			var n := m.net_match.stream_tick(m.router.tick)
			if not _made_at.has(n):
				_made_at[n] = t
				_count_taps(m.net_match.stream.at(m.router.tick))
		elif m.id != 0 and m.net_match.phase == MwNetMatch.Phase.PLAYING:
			var n := m.net_match.stream_tick(m.router.tick)
			var was := int(_ran.get(m.id, -1))
			for k in range(was + 1, n + 1):
				if _made_at.has(k):
					max_stall_ms = maxi(max_stall_ms, now() - int(_made_at[k]))
			_ran[m.id] = maxi(was, n)
		if not on:
			m.ended = m.net_match.end_reason


# --- work item 6 -------------------------------------------------------------------------------------

## Machine [param id]'s connection drops (a crash, a cable): both ends see it
## (its match ends LOST at its next frame; the host keeps its players and
## key, the CPU playing them).
func drop(id: int) -> void:
	var m := machine(id)
	m.service.client.transport.disconnect_peer(MwNetTransport.HOST_PEER, true)


## Machine [param id] comes back with its rejoin key (the one MwNetRejoin
## keeps on disk - the test saves it): as it was, or with [param fresh] as
## a new process (a new router, session, sound driver and bot - nothing of
## the old game but the key on disk; its bot's settings are the test's to
## make again). A new client connects from the same address; once in, its
## match waits for the host's snapshot (MwNetMatch.start_rejoin). The
## machine.
func rejoin(id: int, fresh := false) -> Machine:
	var m := machine(id)
	var i := machines.find(m)
	if fresh:
		m.enter()
		m.free_all()
		m.leave()
		var again := Machine.new(parent, m.name)
		again.id = id
		again.bot.players.assign(host.lobby.numbers_of(id))
		again.bot.seed_value = m.bot.seed_value
		machines[i] = again
		m = again
	var old := m.service.client
	var net_client := MwNetClient.new()
	if enet:
		net_client.info = NetBase.World.net_info()
		net_client.connect_to("127.0.0.1", old.port, "pw", host.lobby.numbers_of(id).size())
	else:
		net_client = world.make_client({}, str(host.lobby.machines[id]["address"]))     # from where it was
		net_client.connect_to(NetBase.World.HOST_ADDRESS, MwNetProtocol.PORT, "pw", host.lobby.numbers_of(id).size())
	clients[clients.find(old)] = net_client
	m.service.client = net_client
	m.ended = -1
	m.net_match = null
	net_client.rejoined.connect(func(_match_id: int, _first: int) -> void:
		m.enter()
		m.net_match = MwNetMatch.start_rejoin(m.session, m.router, m.service)
		if m.net_match != null:
			_bots_numbers(m.net_match)
		m.leave())
	return m


## Every machine's game changed by [param what] (what.call(machine)) at the
## start of stream tick [param n] - the same tick everywhere, so their games
## stay one (a machine not running then, or later taken up from a snapshot,
## gets the change with the host's game).
func at_tick(n: int, what: Callable) -> void:
	for m in machines:
		var mm := m
		m.router.tick_started.connect(func(t: int) -> void:
			if mm.net_match != null and mm.net_match.phase == MwNetMatch.Phase.PLAYING \
					and mm.net_match.stream_tick(t) == n:
				what.call(mm))


## The host's stream tick [param ti]: the taps of the bots' verb it carries
## (counters that moved), per player; more than one a tick is noted.
func _count_taps(ti: MwTickInput) -> void:
	if ti == null:
		return
	if ti.heights.count(0) != ti.heights.size():
		height_ticks += 1
	for p in range(1, MwVerbs.PLAYERS + 1):
		var i := MwTickInput.index_of(MwVerbs.action(p, NetBot.TAP_VERB))
		var c := int(ti.counts[i])
		var d := (c - int(_tap_counters.get(p, 0))) & 0xFF
		if d > 0:
			taps_seen[p] = int(taps_seen.get(p, 0)) + d
			if d > 1:
				double_taps += 1
		_tap_counters[p] = c


## Frames until [param done] holds (or [param limit] frames); true if it did.
func run_until(done: Callable, limit: int) -> bool:
	for i in limit:
		if done.call():
			return true
		frame()
	return done.call()


func run(frames: int) -> void:
	for i in frames:
		frame()


## The first disagreement between a client's hashes and the host's (""
## none), and how many were compared.
func compare_hashes() -> Dictionary:
	var host_h := {}
	for record: Array in machines[0].net_match.hashes:
		host_h[int(record[0]) * 4 + int(record[1])] = record
	var compared := 0
	for m in machines.slice(1):
		if m.net_match == null:
			continue
		for record: Array in m.net_match.hashes:
			var k := int(record[0]) * 4 + int(record[1])
			if not host_h.has(k):
				continue
			compared += 1
			if host_h[k] != record:
				return {"ok": false, "compared": compared,
						"why": "%s at tick %d kind %d: %s, the host %s"
						% [m.name, record[0], record[1], str(record), str(host_h[k])]}
	return {"ok": true, "compared": compared, "why": ""}


## Every machine's game, freed.
func free_all() -> void:
	for m in machines:
		m.enter()
		m.free_all()
	MwSound.driver = null
	MwSound.heard = null
	MwSound.reset()
	MwLiveInput.turns = PackedInt32Array()
	MwSettings.own_match_rules()
	MwCustomTeams.load_state(_bank_before)     # plan 38: the test's bank as it was
