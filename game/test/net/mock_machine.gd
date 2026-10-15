extends SceneTree
## One machine of tools/bin/net-mock's mock online game (docs/net.md "The
## mock session"): headless, the host or a client, its players bots
## (net_machines.gd's NetBot in the menus, live_match's GameBot on the
## rink), for a person to play with from the real game. Unlike the soak's
## machines (online_match.gd) it never finishes: the host waits for every
## machine, starts, and plays game after game (the bots never go Back to
## the lobby; a match that ends anyway - everyone gone - starts again once
## they are back); a client that fails to join or loses its connection
## joins again (with its key in mid-match: REJOIN) for as long as it runs.
## The controller selection waits for every player in the match on a team,
## the person's too (no timeout).
##
##   godot --headless -s res://test/net/mock_machine.gd -- --role host|client --dir DIR [options]
##     --port N         the host's port, or where a client connects (default 42150)
##     --address A      where a client connects (default 127.0.0.1)
##     --password P     (default MOCK)
##     --locals N       this machine's players (default 1)
##     --name K         a client's name (its folder: DIR/client<K>)
##     --machines N     the host: the machines it waits for, its own among them (default 2)
##     --players N      the host: the players it waits for, every machine's
##                      together (default 2; the person's second player
##                      joins in the lobby with a press)
##     --start-after S  the host: START GAME S seconds after every machine and
##                      player is in (default 5)
##     --control FILE   the host: a line "start" in it (the file written
##                      anew) starts at once, every machine in or not
##     --minutes N      the host: period length (default 2)
##     --wait N         ticks before a bot presses on a scoreboard (default 400)
##     --seed N         the bots' seed (default 1)
##     --leave-free N   the position the bots take last (MwLineup: 0 C ... 5 G;
##                      default -1: none) - the person's to pick (NetBot.leave_free)
##     --person-from A  the host: the person's machine reaches it from address A
##                      (net-mock: their proxy's, 127.0.0.1); with --leave-free,
##                      their first player starts the match seated on it
##                      ([method _start_record])
##
## Prints "mock <role>: ..." lines on what changes (the launcher shows the
## host's), and the net code's log.

const Machines := preload("res://test/net/net_machines.gd")
const Bots := preload("res://test/support/bots.gd")

const FRAME_MS := 1000.0 / 60.0

var _args := {}
var _role := "host"
var _who := "host"
var _router: MwRouter
var _session: MwSession
var _service: Machines.Service
var _bot: Machines.NetBot
var _host: MwNetHost
var _client: MwNetClient
var _match: MwNetMatch
var _join := []
var _retry_at := -1
var _ready_since := -1            # the host: every machine in since (ms)
var _control_mtime := 0
var _said := ""
var _logged := 0
var _rate_from := 0
var _frames := 0
var _status_at := 0


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
	_who = _role + str(_args.get("name", ""))
	var dir := str(_args.get("dir", OS.get_user_data_dir().path_join("net_mock")))
	var mine := dir.path_join(_who)
	DirAccess.make_dir_recursive_absolute(mine)
	MwNetIdentity.dir = mine                     # the host's key kept: the person's game knows it
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
			var stand_in := MwScreen.new()                # the online pages: stand-ins (nobody looks)
			stand_in.screen_id = int(id_)
			return stand_in
		return MwRouter.instantiate_scene(id_)
	node.add_child(_router.use_driver_model(MwRom.data()))
	_bot = Machines.NetBot.new()
	_bot.router = _router
	_bot.seed_value = int(_args.get("seed", "1"))
	_bot.wait = int(_args.get("wait", "400"))
	_bot.leave_free = int(_args.get("leave-free", "-1"))
	_bot.away_ticks = 1 << 30                    # the person is waited for
	_router.screen_entered.connect(_bot.on_entered)
	_router.screen_resumed.connect(_bot.on_resumed)
	_router.screen_entered.connect(func(id: int, _v: int, tick: int, prev: int) -> void:
		print("mock %s screen %d <- %d at tick %d" % [_who, id, prev, tick]))
	_service = Machines.Service.new()
	_service.local_input = _bot
	var port := int(_args.get("port", "42150"))
	var locals := int(_args.get("locals", "1"))
	var password := str(_args.get("password", "MOCK"))
	if _role == "host":
		var id := MwNetIdentity.load_or_create()
		var enet := MwNetEnet.host(port, id)
		if enet.error != OK:
			print("mock host: port %d is taken" % port)
			quit(1)
			return
		_host = MwNetHost.new(enet, id.der, password)
		_host.open()
		for k in range(2, locals + 1):
			_host.join_local(k)
		_service.host = _host
		print("mock host: listening on port %d, %d player(s) here" % [enet.local_port(), locals])
	else:
		_join = [str(_args.get("address", "127.0.0.1")), port, password, locals]
		_new_client()


func _new_client() -> void:
	_client = MwNetClient.new()
	_client.connector = func(a: String, p: int, der: PackedByteArray) -> MwNetTransport:
		return MwNetEnet.client(a, p, der)
	_client.state_changed.connect(func(st: int) -> void:
		if st == MwNetClient.State.LOBBY:
			_say("in the lobby"))
	_client.started.connect(func(match_id: int, first_tick: int, record: PackedByteArray) -> void:
		_play(MwNetMatch.start_client(_session, _router, _service, match_id, first_tick, record)))
	_client.rejoined.connect(func(_match_id: int, _first: int) -> void:
		_say("back in the match with its key, waiting for a snapshot")
		_play(MwNetMatch.start_rejoin(_session, _router, _service)))
	_service.client = _client
	_logged = 0
	_client.connect_to(_join[0], _join[1], _join[2], _join[3])


## A match begun (START, or back in one with the key): the bots on this
## machine's players.
func _play(net_match: MwNetMatch) -> void:
	if net_match == null:
		_say("no match from the start record")
		return
	_match = net_match
	_match.keep_hashes = false
	_match.dump_dir = str(_args.get("dir", "user://net_mock")).path_join("desync")
	for n: int in _match.locals:
		_match.locals[n] = n                     # the bots press their numbers' actions
	_bot.players.assign(_match.lobby.numbers_of(_match.machine))
	_bot.teams.clear()
	_bot.game_bots.clear()
	for p in _bot.players:
		_bot.teams[p] = 0 if p % 2 == 1 else 1   # odd numbers team A, even team B
		_bot.game_bots[p] = Bots.GameBot.new(p, _bot.seed_value)
	_bot.expected = _match.lobby.players.size()
	_rate_from = Time.get_ticks_msec()
	_frames = 0
	_say("playing: machine %d, players %s" % [_match.machine, str(_bot.players)])


func _say(what: String) -> void:
	if what != _said:
		_said = what
		print("mock %s: %s" % [_who, what])


func _process(_delta: float) -> bool:
	_print_log()
	_write_status(Time.get_ticks_msec())
	if _match != null:
		_run_frames()
		return false
	var now := Time.get_ticks_msec()
	if _host != null:
		_host.poll(now)
		_lobby(now)
	else:
		_client.poll(now)
		if _client.state == MwNetClient.State.DONE and _match == null:
			if _retry_at < 0:
				_retry_at = now + maxi(1, _client.refusal_wait) * 1000
				_say("couldn't join (fail %d, refusal %d): again in %d s" % [_client.fail, _client.refusal,
						maxi(1, _client.refusal_wait)])
			elif now >= _retry_at:
				_retry_at = -1
				_new_client()
	OS.delay_msec(4)
	return false


## The host's lobby: START GAME once every machine is in and
## --start-after seconds went by, or at once on the control file's "start".
func _lobby(now: int) -> void:
	var machines := _host.lobby.machines.size()
	var want := int(_args.get("machines", "2"))
	var players := _host.lobby.players.size()
	var want_players := int(_args.get("players", "2"))
	_say("lobby: %d of %d machines in, %d of %d players" % [machines, want, players, want_players])
	var go := _control_says_start()
	if machines >= want and players >= want_players:
		if _ready_since < 0:
			_ready_since = now
		go = go or now - _ready_since >= int(float(_args.get("start-after", "5")) * 1000.0)
	else:
		_ready_since = -1
	if not go:
		return
	_session.setup.period_minutes = int(_args.get("minutes", "2"))
	_ready_since = -1
	_play(MwNetMatch.start_host(_session, _router, _service, _start_record()))
	if _match != null:
		print("mock host: START GAME - %d machines, %d player(s)" % [machines, players])


## The match's start record: the host's ([method MwNetMatch.host_record])
## with net-mock's person seated on the position the bots leave them
## (--leave-free; NetBot.seat_person: their side by number, that position
## the one they last played, so the character selection's cursor starts on
## it) - their first player, on the machine reaching the host from
## --person-from (the bots' clients come from addresses of their own).
## {}: the host's as it is (no person found, or no position left).
func _start_record() -> Dictionary:
	var from := str(_args.get("person-from", ""))
	if from == "" or _bot.leave_free < 0:
		return {}
	var theirs: Array = []
	for m: int in _host.lobby.machines:
		var d: Dictionary = _host.lobby.machines[m]
		if m != MwNetLobby.HOST_MACHINE and str(d.get("address", "")) == from:
			theirs.append_array(_host.lobby.numbers_of(m))
	if theirs.is_empty():
		return {}
	theirs.sort()
	var record := MwNetMatch.host_record(_session, _host.lobby)
	if record.is_empty():
		return {}
	Machines.NetBot.seat_person(record, int(theirs[0]), _bot.leave_free)
	print("mock host: P%d seated on team %s, position %d" % [theirs[0], "A" if int(theirs[0]) % 2 == 1 else "B",
			_bot.leave_free])
	return record


func _control_says_start() -> bool:
	var path := str(_args.get("control", ""))
	if path == "" or not FileAccess.file_exists(path):
		return false
	var t := FileAccess.get_modified_time(path)
	if t == _control_mtime:
		return false
	var first := _control_mtime == 0
	_control_mtime = t
	return not first and FileAccess.get_file_as_string(path).strip_edges() == "start"


## The match's frames at 60 a second (the host makes a tick a frame), a
## few at a time between the engine's own; after it the lobby again - or,
## the connection lost, joining again with the key.
func _run_frames() -> void:
	if _client != null:
		_bot.lag_ticks = ceili(_client.rtt_ms * 60.0 / 1000.0) + 2
	var until := Time.get_ticks_msec() + 25
	while _match != null and Time.get_ticks_msec() < until:
		var t := Time.get_ticks_msec()
		var due := (t - _rate_from) / FRAME_MS
		if _frames >= due:
			OS.delay_usec(clampi(int((_frames - due) * FRAME_MS * 1000.0), 100, 2000))
			continue
		_frames = maxi(_frames, floori(due) - 4) + 1     # no bursts after a slow spell
		if not _match.frame(t):
			var why := _match.end_reason
			for line in _match.log_lines:
				print("mock %s log: %s" % [_who, line])
			_match = null
			_say("the match ended (%d)" % why)
			if _client != null and why in [MwNetMatch.End.LOST, MwNetMatch.End.HOST_LEFT, MwNetMatch.End.KICKED]:
				_new_client()


## The host's DIR/status.txt, every second: the lobby's machines (their
## address, players and ping) and the game's screen (net-mock's "status").
func _write_status(now: int) -> void:
	if _host == null or now - _status_at < 1000:
		return
	_status_at = now
	var lines := PackedStringArray()
	var screen := _router.current_id() if _match != null else -1
	lines.append("%s; %d machines, %d players" % ["playing, screen %d" % screen if _match != null else "lobby",
			_host.lobby.machines.size(), _host.lobby.players.size()])
	var cs := _router.current() as MwCharacterSelect if _match != null else null
	if cs != null:
		lines.append("  selection: stage %d, picks %s, cursors %s, taken %s, sides %s" % [cs.stage, str(cs.picks),
				str(cs.cursor), str(cs.taken), str(_session.humans.teams)])
	for m: int in _host.lobby.machines:
		var d: Dictionary = _host.lobby.machines[m]
		var nums := _host.lobby.numbers_of(m)
		lines.append("  machine %d %-22s P%s  %s" % [m, "host (bots)" if m == 0 else str(d["address"]),
				",P".join(PackedStringArray(nums.map(func(n: int) -> String: return str(n)))),
				"" if m == 0 else ("ping %d ms" % int(d["ping"]) if d["connected"] else "away")])
	var f := FileAccess.open(str(_args.get("dir", "user://net_mock")).path_join("status.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()


func _print_log() -> void:
	var net_log := _host.log_lines if _host != null else (_client.log_lines if _client != null else PackedStringArray())
	while _logged < net_log.size():
		print("mock %s net: %s" % [_who, net_log[_logged]])
		_logged += 1
