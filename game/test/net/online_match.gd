extends SceneTree
## Plan 35 work item 4: a whole online match, each machine its own process
## over real ENet with DTLS on localhost - the host and its clients run the
## whole game (MwNetMatch: the router, the real screens, the sound driver's
## model) with bots on their own players (net_machines.gd's NetBot): START
## GAME, the game options, the controller selection, the selection steps,
## the matchup, three periods, the screens between plays, SAVE REPLAY?,
## back on the game options, Back to the lobby. Each machine writes the
## hashes it made (every pass of the rink and the screens between plays,
## every screen entered) and prints what it measured; --role compare then
## compares every client's file with the host's.
##
## Work item 7 (tools/bin/net-soak runs it through tools/net/chaos_proxy.py):
## any address (IPv4 or IPv6), a password or none, shorter periods; a client
## joins again as a player would (after a refusal to wait, no answer or a
## connection lost - in mid-match with its key, REJOIN), and one killed and
## started again rejoins with the rejoin record in its folder; a "SOAK
## {json}" line at the end with what the soak reports: ticks, hashes,
## mismatches, stalls, joining, drops, the round trip, resends, snapshots,
## the traffic (MwNetEnet.traffic), the CPU time and memory; a client's
## buffer too (each frame of play: the ticks it holds, how far the host's
## game is ahead, the round trip) and what its stream received.
##
##   godot --headless -s res://test/net/online_match.gd -- --role host --clients N --dir DIR [options]
##   godot --headless -s res://test/net/online_match.gd -- --role client --name K --dir DIR [options]
##     --locals N    this machine's local players (default 1)
##     --port N      the host's port, or where a client connects (default 42099)
##     --address A   where a client connects (default 127.0.0.1; ::1 for IPv6)
##     --password P  (default "pw"; "" for none)
##     --teams SPEC  who plays where: team A's numbers, ".", team B's, "+"
##                   between numbers (default "1+3.2+4")
##     --minutes N   period length (default 1)
##     --clock S     each period's clock cut to S seconds when it starts, and
##                   a tie broken at overtime's start (a goal for team A) -
##                   every machine at the same tick: the test's rules, so a
##                   whole match fits a short run (0: off, the default)
##     --wait N      ticks before the bots press on a scoreboard (default 400)
##     --rate N      frames a second at most (default 400; 60: real time) - the
##                   host runs a tick a frame, a client up to two
##     --seed N      the bots' seed (default 1)
##     --limit N     give up after N seconds (default 600; what was played so
##                   far is still written and reported, "partial")
##     --rejoin 1    marks a client started again after its process died
##                   (net-soak); any client finds the rejoin record in its
##                   folder (DIR/client<K>) by itself, joins with its key and
##                   waits for the host's snapshot (MwNetMatch.start_rejoin)
##     --rejoin-lost N  a client whose connection is lost in mid-match joins
##                   again with its key at once, N times at most (default 3)
##     --throttle T  ENet's packet throttle for this machine's peers
##                   (MwNetEnet.throttle): "game" (MwNetEnet.THROTTLE, the
##                   default), "enet" (ENet's own: 5000:2:2) or
##                   INTERVAL:ACCELERATION:DECELERATION
##   godot --headless -s res://test/net/online_match.gd -- --role compare --dir DIR
##
## Prints a line per screen entered, then "<role> RESULT ok" or what failed.

const Machines := preload("res://test/net/net_machines.gd")
const Bots := preload("res://test/support/bots.gd")

var _args := {}
var _role := "host"
var _name := ""
var _dir := ""
var _service: Machines.Service
var _router: MwRouter
var _session: MwSession
var _match: MwNetMatch
var _bot: Machines.NetBot
var _host: MwNetHost
var _client: MwNetClient
var _t0 := 0
var _frames := 0
var _logged := 0
var _rate_from := 0
var _phase := "lobby"
var _result := ""
var _games := 0
var _transports: Array[MwNetEnet] = []     # every transport this machine made (a client: one per session)
var _linger_until := 0
var _join := []                            # a client's connect_to arguments, for another try
var _tries := 1
var _retry_at := -1
var _partial := false                      # the time limit came first: what was played is reported
var _join_t0 := 0
var _join_ms := -1
var _match_t0 := 0
var _match_cpu0 := 0.0
var _ticks_seen := 0
var _last_tick_ms := -1
var _synced_seen := -1
var _waited_ms := -1
var _stall := {"max_ms": 0, "over_250ms": 0, "over_1s": 0}
var _drops := 0                            # connections lost in mid-match and joined again
var _dropped_at := -1
var _away_ms := 0                          # from each loss to the snapshot taken up
var _old_hashes: Array = []                # the hashes of this machine's matches before a loss
var _old_mismatches := 0
var _old_ticks := 0
var _old_checked := 0
var _lost_match: MwNetMatch = null         # a match whose connection was lost, until back in it
## A client's buffer, sampled each frame of play: the ticks it holds beyond
## the one it ran (MwNetMatch.lead), how far the host's game is ahead
## (host_lead, ms) and the round trip (ms).
var _lead_sum := 0
var _lead_max := 0
var _host_leads := PackedInt32Array()
var _host_lead_sum := 0
var _rtt_sum := 0
var _rtt_max := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			_args[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	_role = str(_args.get("role", "host"))
	var throttle := str(_args.get("throttle", "game"))
	if throttle == "enet":
		MwNetEnet.throttle = [5000, 2, 2]
	elif throttle != "game":
		var parts := throttle.split(":")
		MwNetEnet.throttle = [int(parts[0]), int(parts[1]), int(parts[2])]
	_name = str(_args.get("name", ""))
	_dir = str(_args.get("dir", OS.get_user_data_dir().path_join("online_match")))
	_t0 = Time.get_ticks_msec()
	if _role == "compare":
		_compare()
		return
	var mine := _dir.path_join(_role + _name)
	DirAccess.make_dir_recursive_absolute(mine)
	MwNetIdentity.dir = mine
	MwNetKnownHosts.path = mine.path_join("known_hosts.cfg")
	MwNetRejoin.path = mine.path_join("rejoin.cfg")
	MwReplayFile.dir = mine.path_join("replays")
	var node := Node.new()
	root.add_child(node)
	var fader := MwScreenFader.new()
	node.add_child(fader)
	_router = MwRouter.new(node, fader)
	_session = MwSession.new()
	_router.session = _session
	_router.factory = func(id_: Variant) -> MwScreen:
		if id_ is int and int(id_) in [MwFlow.ONLINE_MENU, MwFlow.ONLINE_LOBBY]:
			var stand_in := MwScreen.new()            # work item 3's pages: stand-ins here
			stand_in.screen_id = int(id_)
			return stand_in
		return MwRouter.instantiate_scene(id_)
	node.add_child(_router.use_driver_model(MwRom.data()))
	_bot = Machines.NetBot.new()
	_bot.router = _router
	_bot.seed_value = int(_args.get("seed", "1"))
	_bot.back_after = 1                          # after a game: Back to the lobby
	_bot.wait = int(_args.get("wait", "400"))
	_router.screen_entered.connect(_bot.on_entered)
	_router.screen_resumed.connect(_bot.on_resumed)
	_router.screen_entered.connect(func(id: int, _v: int, tick: int, prev: int) -> void:
		if id == 1 and prev in [15, 16]:
			_games += 1
		print("%s %7d  %3d <- %3d" % [_role + _name, tick, id, prev]))
	var clock := int(_args.get("clock", "0"))
	if clock > 0:
		# at the start of each tick, on every machine alike (the same state at
		# the same stream tick): a period's clock above S is cut to S; and as
		# a tie goes on into sudden-death overtime period after period (the
		# original's rule), which short periods would make endless, overtime
		# starts with a goal for team A
		_router.tick_started.connect(func(_t: int) -> void:
			var rink := _session.screens.get("rink") as MwRinkState
			if _match == null or _match.phase != MwNetMatch.Phase.PLAYING or rink == null:
				return
			if rink.clock > clock:
				rink.clock = clock
			if MwRinkSim.s8(rink.period) > 3 and rink.teams[0].score == rink.teams[1].score:
				rink.teams[0].score += 1)
	_service = Machines.Service.new()
	_service.local_input = _bot
	var port := int(_args.get("port", "42099"))
	var locals := int(_args.get("locals", "1"))
	var password := str(_args.get("password", "pw"))
	if _role == "host":
		var id := MwNetIdentity.load_or_create()
		var enet := MwNetEnet.host(port, id)
		if enet.error != OK:
			_fail("the port is taken")
			return
		_transports.append(enet)
		_host = MwNetHost.new(enet, id.der, password)
		_host.open()
		for k in range(2, locals + 1):
			_host.join_local(k)
		_service.host = _host
		print("host: listening on port %d" % enet.local_port())
	else:
		_join_t0 = Time.get_ticks_msec()
		_join = [str(_args.get("address", "127.0.0.1")), port, password, locals]
		_new_client()


## A client's session: its transports counted, its joining timed, its
## match started by START or - back with its key - by the rejoin.
func _new_client() -> void:
	_client = MwNetClient.new()
	var made := _transports
	_client.connector = func(a: String, p: int, der: PackedByteArray) -> MwNetTransport:
		var t := MwNetEnet.client(a, p, der)
		made.append(t)
		return t
	_client.state_changed.connect(func(st: int) -> void:
		if _join_ms < 0 and st in [MwNetClient.State.LOBBY, MwNetClient.State.RUNNING]:
			_join_ms = Time.get_ticks_msec() - _join_t0
			print("%s: joined in %d ms (%d DTLS sessions)" % [_role + _name, _join_ms, _transports.size()]))
	_client.started.connect(func(match_id: int, first_tick: int, record: PackedByteArray) -> void:
		_match = MwNetMatch.start_client(_session, _router, _service, match_id, first_tick, record)
		_setup_match())
	_client.rejoined.connect(func(_match_id: int, _first: int) -> void:
		print("%s: back in the match with its key, waiting for a snapshot" % (_role + _name))
		_match = MwNetMatch.start_rejoin(_session, _router, _service)
		_setup_match())
	_service.client = _client
	_client.connect_to(_join[0], _join[1], _join[2], _join[3])


## The client's connection was lost in mid-match (ENet gave up on a
## reliable message: under heavy loss its retransmissions back off until it
## does): it joins again with its rejoin key at once, as a player choosing
## REJOIN would, and waits for the host's snapshot - its hashes so far kept
## for the comparison.
func _rejoin_lost(t: int) -> void:
	_drops += 1
	_dropped_at = t
	for line in _match.log_lines:
		print("%s log: %s" % [_role + _name, line])
	print("%s: the connection was lost at stream tick %d; joining again with its key (REJOIN)" % [_role + _name,
			_match.stream_tick(_router.tick)])
	_lost_match = _match
	_match = null
	_phase = "lobby"
	_new_client()


func _setup_match() -> void:
	if _match == null:
		_fail("no match from the start record")
		return
	if _lost_match != null:
		# back after a loss: what the lost match ran and hashed is kept
		_old_hashes.append_array(_lost_match.hashes)
		_old_mismatches += _lost_match.mismatches.size()
		_old_ticks += int(_lost_match.stats["ticks"])
		_old_checked += int(_lost_match.stats["checked"])
		_lost_match = null
	_match.keep_hashes = true
	_match.dump_dir = _dir.path_join("desync")
	_rate_from = Time.get_ticks_msec()
	_frames = 0
	if _match_t0 == 0:
		_match_t0 = _rate_from
		_match_cpu0 = _cpu_seconds()
	for n: int in _match.locals:
		_match.locals[n] = n                     # the bots press their numbers' actions
	_phase = "playing"
	_bot.players.assign(_match.lobby.numbers_of(_match.machine))
	var spec := str(_args.get("teams", "1+3.2+4")).split(".")
	var expected := 0
	for t in mini(spec.size(), 2):
		for x in spec[t].split("+", false):
			expected += 1
			if int(x) in _bot.players:
				_bot.teams[int(x)] = t
	_bot.expected = expected
	for p in _bot.players:
		_bot.game_bots[p] = Bots.GameBot.new(p, _bot.seed_value)
	print("%s: machine %d, players %s, match %d" % [_role + _name, _match.machine, str(_bot.players),
			_match.match_id])


func _process(_delta: float) -> bool:
	if _phase == "linger":
		_linger()
		return false
	if _result != "":
		return _finish()
	var net_log := _host.log_lines if _host != null else (_client.log_lines if _client != null else PackedStringArray())
	while _logged < net_log.size():
		print("%s net: %s" % [_role + _name, net_log[_logged]])
		_logged += 1
	var now := Time.get_ticks_msec()
	if now - _t0 > int(_args.get("limit", "600")) * 1000:
		_fail("time limit in phase %s on screen %d" % [_phase, _router.current_id()])
		if _match == null and _lost_match != null:
			_match = _lost_match                      # lost, not back in: what it played is reported
			_phase = "playing"
		if _match != null and _phase in ["playing", "ending"]:
			_partial = true
			_write_hashes()                          # what was played is still compared
			_soak_line()
		return false
	match _phase:
		"lobby":
			if _role == "host":
				_host.poll(now)
				var want := int(_args.get("clients", "1"))
				var joined := 0
				for id in _host.lobby.machines:
					if int(id) != 0:
						joined += 1
				if joined >= want:
					_session.setup.period_minutes = int(_args.get("minutes", "1"))
					_session.setup.penalties = 1
					_match = MwNetMatch.start_host(_session, _router, _service)
					_setup_match()
			else:
				_client.poll(now)
				if _client.state == MwNetClient.State.DONE and _match == null:
					_join_again(now)
				elif _lost_match != null and _client.state == MwNetClient.State.LOBBY:
					# back after a loss, but the match was over meanwhile: what
					# it played is reported
					_fail("the connection was lost near the end: the match was over when it came back")
					_match = _lost_match
					_lost_match = null
					_done()
			OS.delay_msec(2)                            # many machines wait on one CPU
		"playing", "ending":
			# many frames in one of the engine's (its own frame costs more than a
			# tick of the game), --rate frames a second at most (the host's ticks;
			# a client sends its inputs once a frame, and a host takes 600 packets
			# a second from a machine before it calls it a flood)
			var until := now + 25
			var every := 1000.0 / float(int(_args.get("rate", "400")))
			while _phase in ["playing", "ending"] and Time.get_ticks_msec() < until:
				var t := Time.get_ticks_msec()
				var due := (t - _rate_from) / every
				if _frames >= due:
					# asleep until the next frame is due (at most 2 ms at a time)
					OS.delay_usec(clampi(int((_frames - due) * every * 1000.0), 100, 2000))
					continue
				_frames = maxi(_frames, floori(due) - 4) + 1     # no bursts after a slow spell
				if not _match.frame(t):
					if _client != null and _match.end_reason == MwNetMatch.End.LOST \
							and _drops < int(_args.get("rejoin-lost", "3")):
						_rejoin_lost(t)
					else:
						_done()
				else:
					_measure(t)
	return false


func _write_hashes() -> void:
	var f := FileAccess.open(_dir.path_join("hashes_%s%s.txt" % [_role, _name]), FileAccess.WRITE)
	for record: Array in _old_hashes + _match.hashes:
		f.store_line("%d %d %d %d" % [record[0], record[1], record[2], record[3]])
	f.close()


## A client that couldn't join tries again as a player would - after a
## refusal's wait (WAIT: its address tried too often; BUSY: too many
## joining at once), when nobody answered (the handshake lost) or when the
## connection was lost in the lobby - five times at most; anything else
## fails the run.
func _join_again(now: int) -> void:
	var again := _client.fail in [MwNetClient.Fail.NO_ANSWER, MwNetClient.Fail.LOST] \
			or (_client.fail == MwNetClient.Fail.REFUSED
			and _client.refusal in [MwNetProtocol.Refusal.WAIT, MwNetProtocol.Refusal.BUSY])
	if not again or _tries >= 6:
		_fail("couldn't join: fail %d, refusal %d (%d tries)" % [_client.fail, _client.refusal, _tries])
	elif _retry_at < 0:
		_retry_at = now + maxi(1, _client.refusal_wait) * 1000
		print("%s: couldn't join (fail %d, refusal %d), again in %d s" % [_role + _name, _client.fail,
				_client.refusal, maxi(1, _client.refusal_wait)])
	elif now >= _retry_at:
		_retry_at = -1
		_tries += 1
		_client.connect_to(_join[0], _join[1], _join[2], _join[3])


## The stalls: the longest wall-clock stretch this machine's game stood
## still while playing (no tick run), and how many stretches passed 250 ms
## and 1 s - counted from the first tick, and again from each snapshot
## taken up (a rejoiner's wait is [member _waited_ms]).
func _measure(t: int) -> void:
	if _match.synced_at != _synced_seen:
		_synced_seen = _match.synced_at
		_last_tick_ms = t
		_ticks_seen = int(_match.stats["ticks"])
		var waited := t - (_dropped_at if _dropped_at >= 0 else _match_t0)
		if _dropped_at >= 0:
			_away_ms += waited
			_dropped_at = -1
		elif _waited_ms < 0:
			_waited_ms = waited
		print("%s: taken up from a snapshot at stream tick %d (screen %d) after %d ms" % [_role + _name,
				_match.synced_at, _match.synced_screen, waited])
		return
	if _match.phase != MwNetMatch.Phase.PLAYING:
		return
	if _client != null:
		var lead := _match.lead()
		_lead_sum += lead
		_lead_max = maxi(_lead_max, lead)
		_host_leads.append(roundi(_match.host_lead() * 1000.0 / 60.0))
		_host_lead_sum += _host_leads[-1]
		_rtt_sum += _client.rtt_ms
		_rtt_max = maxi(_rtt_max, _client.rtt_ms)
	var ticks := int(_match.stats["ticks"])
	if ticks == _ticks_seen:
		return
	if _last_tick_ms >= 0:
		var gap := t - _last_tick_ms
		_stall["max_ms"] = maxi(int(_stall["max_ms"]), gap)
		if gap >= 250:
			_stall["over_250ms"] += 1
		if gap >= 1000:
			_stall["over_1s"] += 1
	_last_tick_ms = t
	_ticks_seen = ticks


## The match is over for this machine: the hash file written, the result.
func _done() -> void:
	_phase = "over"
	_write_hashes()
	var st := _match.stats
	print("%s: ended %d after %d ticks, %d game(s); %d hashes made; mismatches %d; stats %s" % [_role + _name,
			_match.end_reason, st["ticks"], _games, _match.hashes.size(), _match.mismatches.size(), str(st)])
	if _client != null:
		print("%s: rtt %d ms, jitter %d ms, resend requests %d" % [_role + _name, _client.rtt_ms,
				_client.jitter_ms, _client.stream.stats["requests"]])
	for line in _match.log_lines:
		print("%s log: %s" % [_role + _name, line])
	_soak_line()
	if _match.end_reason != MwNetMatch.End.LOBBY:
		_fail("ended %d, not back in the lobby" % _match.end_reason)
	elif _games < 1:
		_fail("no whole game played")
	elif _old_mismatches + _match.mismatches.size() > 0:
		_fail("%d mismatches" % (_old_mismatches + _match.mismatches.size()))
	else:
		_result = "ok"
	# the host stays (its lobby open, as the game's) until every client has
	# finished its game and left; a client leaves (EXIT LOBBY)
	if _client != null:
		_client.exit_lobby()
	_phase = "linger"
	_linger_until = mini(Time.get_ticks_msec() + (60000 if _host != null else 1000),
			_t0 + int(_args.get("limit", "600")) * 1000)


## After the match: the host polls its lobby until the clients have left
## (or a minute); a client lets its goodbye go out (a second at most).
func _linger() -> void:
	var now := Time.get_ticks_msec()
	OS.delay_msec(2)
	if _host != null:
		_host.poll(now)
		if _host.lobby.machines.size() > 1 and now < _linger_until:
			return
	else:
		MwNetEnet.service_lingering()
		if not MwNetEnet._lingering.is_empty() and now < _linger_until:
			return
	_phase = "over"
	if _result == "":
		_result = "ok"


## The "SOAK {json}" line tools/bin/net-soak reads: what this machine ran
## and measured, its traffic summed over its transports, its CPU time and
## memory.
func _soak_line() -> void:
	var now := Time.get_ticks_msec()
	var traffic := {}
	for enet in _transports:
		for k: String in enet.traffic:
			if k == "throttle_low":
				traffic[k] = mini(int(traffic.get(k, 32)), int(enet.traffic[k]))
			else:
				traffic[k] = int(traffic.get(k, 0)) + int(enet.traffic[k])
	var st := _match.stats
	var d := {"role": _role, "name": _name, "end": _match.end_reason, "games": _games, "partial": _partial,
			"ticks": _old_ticks + int(st["ticks"]), "frames": st["frames"],
			"hashes": _old_hashes.size() + _match.hashes.size(),
			"checked": _old_checked + int(st["checked"]), "unchecked": st["unchecked"],
			"mismatches": _old_mismatches + int(st.get("mismatches", 0)), "drops": _drops, "away_ms": _away_ms,
			"held": st["held"], "doubled": st["doubled"], "longest_hold_frames": st["longest_hold"],
			"stall_max_ms": _stall["max_ms"], "stalls_over_250ms": _stall["over_250ms"],
			"stalls_over_1s": _stall["over_1s"], "snapshots": st["snapshots"], "loaded": st["loaded"],
			"snapshot_bytes": st["snapshot_bytes"], "synced_at": _match.synced_at, "waited_ms": _waited_ms,
			"join_ms": _join_ms, "join_tries": _tries, "sessions": _transports.size(),
			"match_s": (now - _match_t0) / 1000.0, "wall_s": (now - _t0) / 1000.0,
			"cpu_s": _cpu_seconds(), "match_cpu_s": _cpu_seconds() - _match_cpu0, "rss_max_kb": _rss_max_kb(),
			"traffic": traffic}
	if _client != null:
		d["rtt_ms"] = _client.rtt_ms
		d["jitter_ms"] = _client.jitter_ms
		d["resend_requests"] = _client.stream.stats["requests"]
		d["stream"] = _client.stream.stats
		var n := _host_leads.size()
		if n > 0:
			var leads := _host_leads.duplicate()
			leads.sort()
			d["buffer"] = {"frames": n, "lead_mean": snappedf(float(_lead_sum) / n, 0.01), "lead_max": _lead_max,
					"host_lead_mean_ms": roundi(float(_host_lead_sum) / n),
					"host_lead_p95_ms": leads[mini(n - 1, n * 95 / 100)], "host_lead_max_ms": leads[n - 1],
					"rtt_mean_ms": roundi(float(_rtt_sum) / n), "rtt_max_ms": _rtt_max}
	d["throttle"] = MwNetEnet.throttle
	if _host != null:
		# each machine's pace (MwNetPace): times slowed to every second tick, ms so, the longest queue seen
		var paces := {}
		for m in _host.lobby.machines:
			var pace := _host.pace_of(int(m))
			if int(m) != 0 and pace != null:
				paces[str(m)] = pace.stats
		d["paces"] = paces
	print("SOAK " + JSON.stringify(d))


## This process's CPU time so far (user + system, seconds; Linux's
## /proc/self/stat - 0 elsewhere).
static func _cpu_seconds() -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0.0
	var line := f.get_line()                       # (/proc's files have no length: read by line)
	var rest := line.substr(line.rfind(")") + 2).split(" ")
	if rest.size() < 13:
		return 0.0
	return (float(rest[11]) + float(rest[12])) / 100.0         # utime, stime (fields 14, 15) at 100 a second


## This process's largest resident memory (kB; Linux's /proc - 0 elsewhere).
static func _rss_max_kb() -> int:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmHWM:"):
			return int(line.split(":")[1].strip_edges().split(" ")[0])
	return 0


## Every client's hash file against the host's: each (tick, kind) both
## made must be equal.
func _compare() -> void:
	var host := _read(_dir.path_join("hashes_host.txt"))
	if host.is_empty():
		_fail("no host hashes")
		return
	var clients := 0
	var compared := 0
	for f in DirAccess.get_files_at(_dir):
		if not f.begins_with("hashes_client"):
			continue
		clients += 1
		var mine := _read(_dir.path_join(f))
		var n := 0
		for k in mine:
			if not host.has(k):
				continue
			n += 1
			if host[k] != mine[k]:
				_fail("%s: tick %d kind %d differs (%s, the host %s)" % [f, k >> 2, k & 3, mine[k], host[k]])
				return
		print("compare: %s - %d of its %d hashes compared, all equal (the host made %d)" % [f, n, mine.size(),
				host.size()])
		if n == 0:
			_fail("%s: no hash in common with the host's" % f)
			return
		compared += n
	if clients == 0:
		_fail("no client files")
	elif _result == "":
		print("compare: %d clients, %d hashes compared, all equal" % [clients, compared])
		_result = "ok"


static func _read(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var fields := f.get_line().split(" ", false)
		if fields.size() == 4:
			out[int(fields[0]) * 4 + int(fields[1])] = fields[3]
	return out


func _fail(why: String) -> void:
	if _result == "":
		_result = "failed: " + why


func _finish() -> bool:
	print("%s RESULT %s (%.1f s)" % [_role + _name, _result, (Time.get_ticks_msec() - _t0) / 1000.0])
	quit(0 if _result == "ok" else 1)
	return true
