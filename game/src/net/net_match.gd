class_name MwNetMatch
extends RefCounted
## The game over the network (plan 35 section 3, work item 4): one machine's
## side of an online match - the host's or a client's. Every machine runs
## the same game (the router and the real screens: the game options, the
## controller selection, the selection steps, the match, the screens between
## plays) from the same start record and the same input stream; this object
## feeds that stream, paces the router and proves the machines agree.
## Node-free; it reads no clock (the caller gives [method frame] the time).
##
## * **START GAME** ([method start_host]): the host makes the start record
##   ([method host_record]: a fresh session seed and its port streams, the
##   setup, the exhibition's flow, the match rules - the host's, the online
##   ones forced: [method online_rules] -, the player table with the
##   lobby's players and machines), sends it with START ([MwNetHost]
##   .start_match, [method encode_record]) and, like every client
##   ([method start_client], when [signal MwNetClient.started] fires),
##   resets its session from it ([method MwSession.reset_from_record]), the
##   match rules in force, the sound driver at power-on, the router afresh
##   in the pass clock's stream mode ([method MwRouter.reset_game]) on the
##   record's first screen.
## * **Custom teams (plan 38).** The host's custom teams travel in the
##   start record ([method host_record]: "custom_teams", each team's JSON -
##   START carries a record that outgrows one message in chunks, protocol
##   version 4) and in every resync snapshot (the session's [member
##   MwSession.custom_teams]); every machine plays the match with them in
##   use ([method MwCustomTeams.use_teams]: its own bank put aside, never
##   written) and gets its own bank back when the match is over for it -
##   the lobby, the host leaving, a kick, a lost connection, leaving
##   ([method _finish]). A record or snapshot whose teams aren't teams is
##   refused (the host dropped as for any garbage).
## * **The stream.** Each frame every machine samples its own players
##   ([member local]: the devices, or bots in tests) into their wire states
##   ([MwNetInput], [member locals] says which local player's actions are
##   which number's). A client sends them ([method MwNetClient.send_input]);
##   the host merges them with every machine's latest ([MwNetHost].step:
##   it never waits), adds the network statuses ([method _update_status])
##   and runs its game from that tick. A client takes the host's confirmed
##   ticks ([MwNetTickReceiver]) into its router's stream ([method
##   tick_input]: the two representations, below).
## * **The buffer (clients).** A client keeps [method buffer_target] ticks
##   (2 plus the measured jitter in ticks) between the newest confirmed tick
##   and the tick it runs: more than a packet's step beyond it (one tick, or
##   two while the host sends every second tick: MwNetTickReceiver.step), it
##   runs two ticks this frame (behind); below it, none (ahead: hold); else
##   one.
## * **Hashes.** Every pass of the rink and the screens between plays (the
##   rink's state, [MwNetHash].rink: kind [constant HASH_PASS]) and every
##   screen entered (the session, kind [constant HASH_SCREEN]); the host
##   sends its own ([method MwNetHost.add_hash]), a client compares each of
##   its own with the host's as they come. A mismatch is logged
##   ([member mismatches], [member log_lines]) with both states: the client
##   dumps its own and tells the host ([method MwNetClient.report_desync]),
##   which dumps its own for that tick ([member dumps]: debug builds; the
##   states of the last [constant KEEP_STATES] hashes kept for it) - and
##   the host repairs it with a resync snapshot (below).
## * **Resync (work item 6, section 5).** A machine back with its key
##   ([method start_rejoin]: WAITING, REJOINING AT THE NEXT FACE OFF on the
##   lobby page), one whose game parted from the host's (DESYNC) and one
##   whose stream has a gap the host can no longer fill (RESYNC LOST) get a
##   snapshot at the host's next safe point - the next screen change, every
##   faceoff line-up among them ([signal MwRouter.entering]):
##   [MwNetSnapshot] taken there, sent in chunks ([method
##   MwNetHost.send_snapshot]), the machine's stream started again at its
##   tick. The machine takes its game up from it ([method _load]: the
##   session, the sound driver's model, the router, at that tick of the
##   stream) once the stream holds the tick, and says so (SYNCED): a
##   rejoined machine's players, the CPU's meanwhile (DISCONNECTED), are
##   theirs again from the host's next tick ([method mark_synced]). Its
##   FULL GAME replay starts there; the hashes check the rest.
## * **Statuses (host).** A player whose machine sends nothing goes neutral
##   after 8 ticks (MwNetMerge), the CPU takes them after [constant
##   LAG_TICKS] (3 s: LAGGING), ENet's timeout drops the machine
##   (DISCONNECTED), a KICK erases it (KICKED). The status travels in the
##   stream (MwNetInput's spare bits -> MwTickInput.status -> the pass's
##   MwInputFrame.away), so the CPU takes and gives back on every machine at
##   the same tick (MwRinkControl.set_net).
## * **KICK (host).** The game's PLAYERS item (the pause menu or the own
##   menu of the host's players, MwRinkControl.kick_list) asks for a kick
##   inside the game, on every machine alike; the host's MwNetMatch carries
##   it out ([method MwNetHost.kick]: the key erased, the address blocked).
## * **Dead reckoning (clients, work item 5).** A client's rink draws its
##   actors "now" ([member reckoning], MwNetReckoning, in [member
##   MwSession.reckoning] while the match runs): [method host_lead] ticks
##   ahead of its confirmed state, its own players' skaters steered by
##   [method local_states]. Presentation only.
## * **The end.** Back from the game options to the lobby (the router asked
##   for [constant MwFlow.ONLINE_LOBBY] at the same tick everywhere): each
##   machine hands its router back (the realtime clock, its own devices, its
##   own settings) and the lobby page comes in; the host keeps the stream
##   going until every machine holds the last tick (or [constant
##   END_WAIT_MS]), then returns the lobby to OPEN ([method
##   MwNetHost.end_match]). The host leaving (CLOSE, a lost connection) or
##   a kick ends a client's match with a message, back to ONLINE
##   MULTIPLAYER ([constant MwFlow.ONLINE_MENU]).
## * **One input, two forms.** The wire's per-player state (MwNetInput: 54
##   verbs - every per-player verb, then the per-player forms of the menu
##   verbs - held bits, press counters, stick bytes, status bits, the shot
##   height's code) and the router's tick (MwTickInput: the shared menu
##   verbs - slot 0 - then each player's slot of exactly those 54 actions in
##   the same order, counters, stick codes, statuses, shot heights) convert
##   one to one ([method tick_input]): the wire's verb v of player n is
##   MwTickInput action slot_range(n).x + v; a stick's (angle, travel) bytes
##   are its MwStick code; the height's code is MwTickInput.heights'. **The shared menu
##   verbs** (slot 0: offline any player's device drives them) are the
##   host's P1's menu verbs online - the game options and every port
##   question any player could answer offline answer the host's P1; the
##   screens that tell players apart (the controller selection, character
##   selection, the votes, the line-ups, own menus) read each player's own
##   verbs as offline.
##
## The service ([method start_host] / [method start_client]: plan 35 work
## item 3's MwNetService, or a test's stand-in) is read for: [code]host[/code]
## (MwNetHost, the host's), [code]client[/code] (MwNetClient, a client's) and,
## when it has one, [code]local_input[/code] (an MwInputSource for this
## machine's devices; default MwLiveInput). The lobby and this machine's id
## come from the host / client.

## The match ended for this machine: [param reason] an [enum End], [param text] the message
## shown with it ([constant END_TEXT]; "" none). The router is handed back by then.
signal ended(reason: int, text: String)
## A client's hash differed from the host's (stream tick, kind).
signal desynced(tick: int, kind: int)
## Work item 6: this machine's game was taken up from a resync snapshot at
## stream tick [param tick] (the screen it entered there).
signal synced(tick: int, screen: int)

enum Role { HOST, CLIENT }
## WAITING (work item 6): a machine back in a running match, its game to
## come with the host's snapshot (the lobby page meanwhile).
enum Phase { PLAYING, ENDING, OVER, WAITING }
## Why the host owes a machine a resync snapshot (work item 6).
enum Want { REJOIN, DESYNC, LOST, FAILED }
## Why a match ended for this machine (PROTOCOL, plan 45: the host asked a
## client's game for a screen no online match shows - [constant ONLINE_SCREENS]).
enum End { NONE, LOBBY, HOST_LEFT, KICKED, LOST, LEFT, PROTOCOL }
const END_TEXT := {
	End.LOBBY: "",
	End.HOST_LEFT: "THE HOST LEFT - THE MATCH IS OVER",
	End.KICKED: "THE HOST KICKED YOU",
	End.LOST: "CONNECTION LOST",
	End.LEFT: "",
	End.PROTOCOL: "THE HOST SENT SOMETHING WRONG",
}
## Plan 45 (the audit's M2; rule S4): the screens an online match shows -
## the exhibition's way from the game options to the match and back
## (docs/net.md "The online exhibition"): the game options (1), the team
## descriptions (2, over the pause menu), the matchup (3), the rink (4-6),
## the stats (8, 9), the special plays (10), the scoreboards (12-17), the
## fight (18), the ref wasted (19), the controller selection and the
## selection steps (110-113). Not the title (0: no idle attract online, and
## its way on is the front menu), the instant replay (7: no replays watched
## online; its way on is REPLAYS) or the playoffs (11: an online match is an
## exhibition) - and none of the port's own pages, whose files and settings
## are this machine's. A client takes no other screen from the host - as the
## start record's first ([method decode_record]), a resync snapshot's
## ([method _load]) or one its game asks for on the stream's input ([method
## _strayed]); the lobby page ([constant MwFlow.ONLINE_LOBBY]) is the game's
## own way out. Anything else drops the host and ends the match there.
const ONLINE_SCREENS: Array[int] = [1, 2, 3, 4, 5, 6, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19,
		MwScreens.CONTROLLER_SELECT, MwScreens.CHARACTER_SELECT, MwScreens.CAPTAIN_VOTE, MwScreens.LINEUPS]
## The lobby page's line while a rejoined machine waits for its snapshot.
const REJOINING_TEXT := "REJOINING AT THE NEXT FACE OFF"

## Hash kinds (MwNetProtocol.HASHES): a pass of the rink or the screens
## between plays, the session at a screen change.
const HASH_PASS := 0
const HASH_SCREEN := 1
## The buffer's base (ticks) before the jitter.
const BUFFER_TICKS := 2
## Ticks a client runs in one frame at most (behind).
const CATCH_UP := 2
## A machine silent this long (ticks: 3 s) is LAGGING: the CPU plays for it.
const LAG_TICKS := 180
## Ticks of the router's stream kept behind the one running.
const KEEP_TICKS := 120
## The host waits this long at most for every machine to hold the match's
## last tick before the lobby opens again.
const END_WAIT_MS := 3000
## States kept for desync dumps (the newest hashes').
const KEEP_STATES := 240
## A client's hash whose host hash hasn't come this many ticks after the
## newest confirmed one is given up (unchecked).
const HASH_PATIENCE := 600
## After a desync is reported, the next one this many ticks later at the
## earliest (once apart, every hash differs).
const REPORT_EVERY := 300
## A start record unpacked is at most this many bytes ([method
## decode_record]; the host's custom teams make most of it).
const RECORD_RAW_MAX := 1 << 22
## Plan 41: the first menu verb of MwNetInput.VERBS (the menu verbs follow
## the gameplay ones), and the most presses the client-side menus keep.
const MENU_VERB := 25
const ECHO_MAX := 64
## Plan 41: the frames of this machine's input the run-ahead keeps.
const SENT_MAX := 240
## Plan 41: [member merge_bias]'s step towards each tick it is seen off by,
## and its bounds (ticks).
const MERGE_GAIN := 0.25
const MERGE_BIAS_MAX := 8.0

var role := Role.HOST
var phase := Phase.PLAYING
var end_reason := End.NONE
var session: MwSession
var router: MwRouter
var service: Object
var host: MwNetHost
var client: MwNetClient
var lobby: MwNetLobby
## This machine's id (0: the host).
var machine := 0
var match_id := 0
## The router tick of stream tick 0 (the record's tick + 1).
var base := 1
## The router's input stream (MwTickInput per router tick).
var stream := MwInputStream.new()
var input: MwStreamInput
## This machine's devices (MwLiveInput; tests: bots).
var local: MwInputSource
## This machine's players: number -> the local player whose actions are
## theirs (the devices: the machine's local player 1, 2 ...; bots: the
## number itself).
var locals := {}
## Whether [method frame] polls the host / client itself (the service may
## poll it instead: polling twice is harmless).
var polls := true
## Every hash this machine made, [stream tick, kind, screen, hash], when
## [member keep_hashes] (tests compare the machines).
var hashes: Array = []
var keep_hashes := false
## Mismatches found (clients): {tick, kind, screen, mine, host} - the first
## 100 (stats["mismatches"] counts them all).
var mismatches: Array = []
## Dump both states of a mismatch to [member dump_dir] (debug builds).
var dumps := OS.is_debug_build()
var dump_dir := "user://net/desync"
## Counters: frames, ticks run, frames held (nothing run though ticks were
## there), frames that ran two, hashes checked / unchecked, the longest run
## of frames without a tick, kicks; work item 6: snapshots sent (host) and
## taken up (clients), the last snapshot's bytes.
var stats := {"frames": 0, "ticks": 0, "held": 0, "doubled": 0, "checked": 0, "unchecked": 0,
		"longest_hold": 0, "kicks": 0, "snapshots": 0, "loaded": 0, "snapshot_bytes": 0}
## Work item 6: the stream tick this machine's game was last taken up from a
## resync snapshot at (-1: never) and the screen it entered there.
var synced_at := -1
var synced_screen := -1
var log_lines := PackedStringArray()
## A client's dead reckoning (work item 5; null on the host): the rink
## draws through it ([member MwSession.reckoning]).
var reckoning: MwNetReckoning = null
## Plan 41 (client): how many ticks the host's merge of this machine's
## input falls past [method ahead_tick]'s round-trip estimate, learnt from
## the stream ([method _learn_merge]) - the estimate's correction.
var merge_bias := 0.0
## Plan 43: input stamps. Each state a client sends carries the host tick
## it is meant for - [method ahead_tick], where its run-ahead shows it - and
## the host's merge takes it there (MwNetMerge.stamped), not as it happens
## to arrive: the client's own input then lands where it predicted it. The
## start record says whether this match's host merges so (`online.stamped`,
## [member stamped]); a client then steers [member merge_bias] by how early
## the host held its input ([method _steer_lead]) instead of by where its
## changes landed ([method _learn_merge]). `--no-input-stamps` on the host's
## command line: plan 41's merge, each state as it comes.
static var input_stamps := true
var stamped := false
var _last_stamp := 0
var _stamp_turn := false
var _slacks_steered := 0
## Plan 43: how early (ticks) a client's input is held at the host before
## it is due - the least of the last [constant SLACK_WINDOW] - and the lead's
## step towards it a frame.
const STAMP_SLACK := 0
const SLACK_WINDOW := 30
const STAMP_GAIN := 0.02
## Plan 41 work item 4: a client prints [method feel_line] every this many
## seconds (0: never) - `--net-feel=SECONDS` (tools/bin/net-mock passes 10:
## the run's you.log).
static var feel_every := 0

var _now := 0
var _states := {}            # number -> this machine's latest MwNetInput state
var _echo: Array = []        # client: this machine's menu presses not yet run [number, verb, counter after]
var _mine: Array = []        # client: [the router tick the host is expected to merge them at, {number: state}]
var _learned := -1           # client: the newest confirmed tick [method _learn_merge] looked at
var _feel_was := {}          # client: the run-ahead's stats at the last feel_line()
var _predicted: MwTickInput = null     # client: input_at's last prediction (plan 42)
var _predicted_from: MwTickInput = null    # ... the newest confirmed tick it was made from
var _predicted_mine := {}              # ... and this machine's states in it
var _echoing := false        # client: the screen on top shows some (plan 41)
var _next_pull := 0          # client: the next stream tick to take from the receiver
var _pending := {}           # client: (tick * 4 + kind) -> [tick, kind, hash, screen]
var _kept := {}              # (tick * 4 + kind) -> the state's bytes (dumps)
var _kept_order: Array[int] = []
var _kicked := {}            # host: machine -> true
var _unsynced := {}          # host: rejoined machines not synced yet
var _end_tick := -1          # the stream tick the game ended on
var _end_since := 0
var _hold := 0
var _reported := -1          # client: the stream tick of the last desync reported
var _hooks: Array = []       # [signal, callable] connected on the router
var _wants := {}             # host: machine -> Want (a snapshot owed at the next safe point)
var _sent := {}              # host: machine -> the id of the last snapshot sent to it
var _awaiting := {}          # host: machine -> [snapshot id, stream tick] sent, not taken up yet
var _asked := false          # client: a resync asked for (the stream lost)


# --- starting ----------------------------------------------------------------------------------------

## START GAME on the host: the start record out with START, the host's game
## from it. [param service_] has [code]host[/code] (an MwNetHost whose lobby
## is open). [param record] (tests): this start record instead of
## [method host_record]'s. Null when the lobby isn't open (or the record
## doesn't fit).
static func start_host(session_: MwSession, router_: MwRouter, service_: Object, record := {}) -> MwNetMatch:
	var net_host: MwNetHost = service_.get("host")
	if net_host == null or net_host.lobby.state != MwNetLobby.State.OPEN:
		return null
	if record.is_empty():
		record = host_record(session_, net_host.lobby)
	if MwCustomTeams.parse_carried(record.get("custom_teams", {})) == null:
		push_error("MwNetMatch: the start record's custom teams aren't teams")
		return null
	var bytes := encode_record(record)
	if bytes.is_empty():
		return null
	var net_match := MwNetMatch.new()
	net_match.role = Role.HOST
	net_match.host = net_host
	net_match.lobby = net_host.lobby
	net_match.machine = MwNetLobby.HOST_MACHINE
	net_match.match_id = net_host.start_match(bytes)
	if net_match.match_id == 0:
		return null
	net_host.desync_reported.connect(net_match._on_desync_reported)
	net_host.machine_rejoined.connect(net_match._on_rejoined)
	net_host.resync_requested.connect(net_match._on_resync_requested)
	net_host.synced.connect(net_match._on_synced)
	net_match._begin(session_, router_, service_, record)
	return net_match


## A client's START ([signal MwNetClient.started]: [param match_id_],
## [param first_tick], the record's bytes [param record_bytes]): its game
## from the host's record. [param service_] has [code]client[/code]. Null
## when the record can't be read.
static func start_client(session_: MwSession, router_: MwRouter, service_: Object, match_id_: int,
		first_tick: int, record_bytes: PackedByteArray) -> MwNetMatch:
	var net_client: MwNetClient = service_.get("client")
	if net_client == null:
		return null
	var record := decode_record(record_bytes)
	if record.is_empty():
		net_client.reject_record()                          # garbage from the host: dropped, as the protocol does
		return null
	var net_match := MwNetMatch.new()
	net_match.role = Role.CLIENT
	net_match.client = net_client
	net_match.lobby = net_client.lobby
	net_match.machine = net_client.machine
	net_match.match_id = match_id_
	net_match._next_pull = first_tick
	net_match._begin(session_, router_, service_, record)
	return net_match


## Work item 6: a client back in a running match with its key ([signal
## MwNetClient.rejoined]): its game waits (WAITING) for the host's resync
## snapshot at the next safe point - the lobby page runs meanwhile on this
## machine's own clock (REJOINING AT THE NEXT FACE OFF) - and then runs from
## it. [param service_] has [code]client[/code] (running). Null without one,
## or without a router.
static func start_rejoin(session_: MwSession, router_: MwRouter, service_: Object) -> MwNetMatch:
	var net_client: MwNetClient = service_.get("client") if service_ != null else null
	if net_client == null or router_ == null or session_ == null or net_client.state != MwNetClient.State.RUNNING:
		return null
	var net_match := MwNetMatch.new()
	net_match.role = Role.CLIENT
	net_match.client = net_client
	net_match.lobby = net_client.lobby
	net_match.machine = net_client.machine
	net_match.match_id = net_client.match_id
	net_match.session = session_
	net_match.router = router_
	net_match.service = service_
	net_match.phase = Phase.WAITING
	net_match._next_pull = net_client.stream.floor_no
	net_match._take_locals()
	# a client's dead reckoning, as _begin makes it (plan 40's B2)
	net_match.reckoning = MwNetReckoning.new(net_match)
	session_.reckoning = net_match.reckoning
	router_.driver = net_match
	net_match._log("match %d: client, machine %d, players %s - back, waiting for a snapshot"
			% [net_match.match_id, net_match.machine,
			str(net_match.locals.keys())])
	return net_match


## The start record of an online match from the host's [param from]
## session (its setup's options) and [param lobby_] (its players): a fresh
## session seed (this match's random numbers), the exhibition's flow from
## the game options (screen 1, [member MwSession.local_mode] "exhibition",
## nobody on a team yet - the controller selection decides), the host's
## match rules made online ([method online_rules]), the player table (the
## lobby's numbers and machines; each player's controller layout - the
## host's own players' from its settings, the others' STANDARD: the lobby
## doesn't carry theirs yet), and plan 38's custom teams: the host's bank
## (its first [constant MwCustomTeams.CARRY_ONLINE], fewer when the record
## wouldn't fit START's cap), which every machine plays with. A team or
## rink of the host's setup that isn't among them (one past them, the
## editor's working copy) gives way to the original team whose playoff
## place it takes.
static func host_record(from: MwSession, lobby_: MwNetLobby) -> Dictionary:
	var match_session := MwSession.new()                       # fresh entropy: the match's session seed
	var mine := from.setup.copy() if from != null and from.setup != null else null
	if mine != null:
		match_session.setup = mine.copy()
	match_session.setup.play_mode = MwPlayoffs.MODE_REGULAR
	match_session.local_mode = "exhibition"
	match_session.humans = MwHumans.new()
	match_session.pad_map = PackedInt32Array([1, 2, 3, 4])
	match_session.after_selection = 3
	var players := []
	var machines := {}
	for n in lobby_.numbers():
		players.append(n)
		machines[str(n)] = lobby_.machine_of(n)
	match_session.online = {"players": players, "machines": machines, "stamped": 1 if input_stamps else 0}
	match_session.rules = online_rules()
	for n in range(1, MwVerbs.PLAYERS + 1):
		var local_count := int(lobby_.players[n]["local"]) if lobby_.players.has(n) else 0
		match_session.layouts[n] = MwSettings.layout(local_count) if lobby_.machine_of(n) == MwNetLobby.HOST_MACHINE \
				else MwInputMap.LAYOUTS[0]
	var limit := MwCustomTeams.CARRY_ONLINE
	while true:
		match_session.custom_teams = MwCustomTeams.record_teams(match_session.playoffs, limit)
		var n: int = (match_session.custom_teams.get("teams", []) as Array).size()
		for f in ["team_a", "team_b", "stadium"]:
			match_session.setup.set(f, _online_team(int(mine.get(f)) if mine != null
					else int(match_session.setup.get(f)), n))
		var r := match_session.to_record(1, 0)
		if n == 0:
			r.erase("custom_teams")                 # (the host's bank is no team of the match's)
			return r
		if not encode_record(r, false).is_empty():
			return r
		limit = n >> 1                              # too big for START: fewer of the host's teams
	return {}


## Plan 38: team (or stadium) [param id] of the host's setup as an online
## match carrying [param carried] of the host's custom teams takes it: an
## original one or a carried one as it is, another custom one the original
## team whose playoff place it takes, anything else team 0.
static func _online_team(id: int, carried: int) -> int:
	if id >= 0 and id < MwTeams.COUNT + carried:
		return id
	var team := MwCustomTeams.team(id)
	return team.playoff_place if team != null else 0


## The host's match rules as an online match plays them: the port's flow
## (front_menu), no idle timeout to the attract demo, an EXTENDED match
## (plan 44, owner: online play is always EXTENDED - the host's opening
## view in that group); the rest the host's (captains are always on online
## whatever CAPTAIN MODE says: MwSelection.captain_mode).
static func online_rules() -> Dictionary:
	var r := MwSettings.match_rules()
	r["front_menu"] = true
	r["idle_attract"] = false
	r["extended_play"] = true
	r["opening_view"] = MwRinkViews.grouped(int(r["opening_view"]), true)
	return r


## The record as START carries it: its length (32 bits) and var_to_bytes
## deflated (at most MwNetProtocol.MAX_RECORD bytes - START's chunks, protocol
## version 4 - and [constant RECORD_RAW_MAX] unpacked; empty when it doesn't
## fit, [param complain]: an error then).
static func encode_record(record: Dictionary, complain := true) -> PackedByteArray:
	var b := MwNetBytes.pack_var(record, FileAccess.COMPRESSION_DEFLATE)
	var raw := MwNetBytes.packed_raw_size(b)
	if b.size() > MwNetProtocol.MAX_RECORD or raw > RECORD_RAW_MAX:
		if complain:
			push_error("MwNetMatch: the start record is %d bytes packed (%d raw), over START's cap" % [b.size(),
					raw])
		return PackedByteArray()
	return b


## [method encode_record]'s bytes back ({} when they aren't a record - also
## when its custom teams aren't teams: MwCustomTeams.parse_carried; plan 45:
## when its first screen is none an online match shows, [constant
## ONLINE_SCREENS]). The bytes come from the host: every size is checked
## before anything is made (at most [constant RECORD_RAW_MAX] unpacked; no
## objects decoded).
static func decode_record(b: PackedByteArray) -> Dictionary:
	var v: Variant = MwNetBytes.unpack_var(b, RECORD_RAW_MAX, FileAccess.COMPRESSION_DEFLATE)
	if not v is Dictionary or int((v as Dictionary).get("format", 0)) != MwSession.RECORD_FORMAT:
		return {}
	if not online_screen((v as Dictionary).get("screen", 1)):    # (MwSession.record_screen's default)
		return {}
	if MwCustomTeams.parse_carried((v as Dictionary).get("custom_teams", {})) == null:
		return {}
	return v


## Plan 45 (M2): whether [param id] (a screen ID, or an MwScreens.EXTRA key)
## is one an online match shows ([constant ONLINE_SCREENS]).
static func online_screen(id: Variant) -> bool:
	return id is int and ONLINE_SCREENS.has(id)


## Every machine alike (plan 40: MwGameStart): the session from the record,
## its context in force (the host's custom teams - checked before:
## decode_record, start_host - and match rules), the sound at power-on, the
## router afresh in stream mode on the record's first screen.
func _begin(session_: MwSession, router_: MwRouter, service_: Object, record: Dictionary) -> void:
	session = session_
	router = router_
	service = service_
	session.machine = machine                  # (a machine's own: the reset keeps them)
	reckoning = MwNetReckoning.new(self) if role == Role.CLIENT else null
	session.reckoning = reckoning              # work item 5: the rink draws "now" (clients)
	base = MwSession.record_tick(record) + 1
	stream = MwInputStream.new()
	stream.first_tick = base
	MwGameStart.begin(router, session, record, MwPassClock.streamed(stream))
	_take_stamps()
	if role == Role.CLIENT and MwHeard.split_online:
		router.split_audio(true)                 # plan 41 work item 3: the game's sound apart from what is heard
	input = MwStreamInput.new(stream)
	input.attach(router)
	_take_locals()
	_watch()
	MwGameStart.enter_first(router, record)
	router.driver = self
	_log("match %d: %s, machine %d, players %s" % [match_id, "host" if role == Role.HOST else "client",
			machine, str(locals.keys())])


## Plan 43: whether the match's host merges input at its stamps (the
## record's, a snapshot's session: `online.stamped`) - the host's merge so.
func _take_stamps() -> void:
	stamped = MwPlain.flag(session.online.get("stamped", 0))
	if role == Role.HOST and host != null:
		host.merge.stamped = stamped


## This machine's devices ([member local]: the service's, else MwLiveInput)
## and players ([member locals]: the lobby's numbers of this machine).
func _take_locals() -> void:
	var src: Variant = service.get("local_input") if service != null and "local_input" in service else null
	local = src if src is MwInputSource else MwLiveInput.new()
	locals = {}
	for n in lobby.numbers_of(machine):
		locals[n] = int(lobby.players[n]["local"])


# --- each frame ----------------------------------------------------------------------------------------

## One physics frame at [param now_ms] (the Router autoload calls it while
## [member MwRouter.driver] is this): the network polled, this machine's
## players sampled and sent (merged on the host), the ticks the stream
## allows run. False once the match is over for this machine (the router
## is its own again; this frame stepped it).
func frame(now_ms: int) -> bool:
	_now = now_ms
	stats["frames"] += 1
	MwSound.reset_swaps()                          # plan 45 (D8): a prediction stopped mid-swap put right
	if phase == Phase.OVER:
		MwCustomTeams.own_teams()                  # (done when it ended; nothing more to do then)
		router.step()
		return false
	if phase == Phase.WAITING:
		_waiting_frame()
	elif role == Role.HOST:
		_host_frame()
	else:
		_client_frame()
	return phase != Phase.OVER


func _host_frame() -> void:
	if polls:
		host.poll(_now)
	if phase == Phase.ENDING:
		host.step()                                  # the last ticks still repeated (nothing new)
		router.step()                                # the lobby page's, on this machine's clock
		if _all_hold(_end_tick) or _now - _end_since >= END_WAIT_MS:
			host.end_match()
			phase = Phase.OVER
			_log("the lobby is open again")
		return
	if host.lobby.state != MwNetLobby.State.RUNNING:
		_finish(End.LEFT)
		return
	_update_status()
	var t := host.step(_sample_local())
	stream.append(MwTickInput.from_wire(t))
	router.step()
	stats["ticks"] += 1
	_after_ticks()


func _client_frame() -> void:
	if polls:
		client.poll(_now)
	if _client_done():
		return
	# plan 43: the host tick it is meant for, never back. A tick of its own
	# (a state that shared one would replace, at the host, the one the
	# run-ahead already played there; presses sharing one come at once) -
	# but past the reckoning (a stalled stream stands it still; a round trip
	# that shrank brings it back) every other one shares the last one's, so
	# they come back to it at half a tick a frame and a stall never bunches
	# more than two together.
	var aim_at := _reckoned()
	var stamp := maxi(aim_at, _last_stamp + 1)
	if stamp > aim_at + 1:
		_stamp_turn = not _stamp_turn
		if _stamp_turn:
			stamp = _last_stamp
	client.send_input(_sample_local(), stream_tick(stamp))     # (the host's numbering)
	_last_stamp = stamp
	if stamped:
		_steer_lead()
	else:
		_learn_merge()
	if feel_every > 0 and int(stats["frames"]) % (feel_every * MwRouter.TICK_HZ) == 0 and phase == Phase.PLAYING:
		print(feel_line())
	# plan 41: the run-ahead's own input (plan 43: at the tick the host takes it)
	_mine.append([stamp if stamped else ahead_tick(), _states.duplicate()])
	if _mine.size() > SENT_MAX:
		_mine = _mine.slice(_mine.size() - SENT_MAX)
	if client.snapshot_ready():
		_load()                                         # work item 6: a desync or a lost stream repaired
		if phase != Phase.PLAYING:
			return
	_pull()
	if client.stream.lost and not _asked and not client.snapshot_pending():
		_ask_resync(MwNetProtocol.Resync.LOST, "the stream has a gap the host no longer holds")
	var ahead := lead()
	var target := buffer_target()
	var n := 1
	if ahead > target + client.stream.step():
		n = CATCH_UP
		stats["doubled"] += 1
	elif ahead < target:
		n = 0
		if ahead > 0:
			stats["held"] += 1
	_hold = _hold + 1 if mini(n, ahead) == 0 else 0
	stats["longest_hold"] = maxi(int(stats["longest_hold"]), _hold)
	for i in mini(n, ahead):
		if _strayed():
			return
		if not router.step():
			break
		stats["ticks"] += 1
		if _game_left():
			break
	if _strayed():
		return
	_after_ticks()
	_check_hashes()
	_echo_screens()
	# the host went back to the lobby and nothing more will come
	if phase == Phase.PLAYING and client.state == MwNetClient.State.LOBBY and lead() <= 0:
		_finish(End.LOBBY)


## True (the match finished) when the client's connection is over: kicked,
## the host gone, this machine leaving, or lost.
func _client_done() -> bool:
	if client.state != MwNetClient.State.DONE:
		return false
	match client.fail:
		MwNetClient.Fail.KICKED:
			_finish(End.KICKED)
		MwNetClient.Fail.CLOSED:
			_finish(End.HOST_LEFT)
		MwNetClient.Fail.CANCELLED, MwNetClient.Fail.EXITED:
			_finish(End.LEFT)
		_:
			_finish(End.LOST)
	return true


## Work item 6: a machine back in a running match, waiting for its
## snapshot: its (blank) states keep the stream's acknowledgements going,
## the lobby page runs on this machine's own clock, and the game is taken up
## once the snapshot is whole and the stream holds its tick. The match
## ending meanwhile (back to the lobby) ends it here too.
func _waiting_frame() -> void:
	if polls:
		client.poll(_now)
	if _client_done():
		return
	if client.state == MwNetClient.State.LOBBY:
		_finish(End.LOBBY)
		return
	client.send_input({})
	if client.snapshot_ready():
		_load()
		return
	router.step()


## The ticks a client keeps between the newest confirmed tick and the one it
## runs: [constant BUFFER_TICKS] plus the measured jitter in ticks.
func buffer_target() -> int:
	if client == null:
		return 0
	return BUFFER_TICKS + ceili(client.jitter_ms * MwRouter.TICK_HZ / 1000.0)


## How many ticks this machine holds beyond the one its game ran last.
func lead() -> int:
	return stream.last_tick() - router.tick


## Dead reckoning (work item 5): how far the host's game is ahead of the
## tick this client's game is at, in ticks - the ticks it holds beyond it
## ([method lead]: the buffer) and the stream's one-way trip (half the
## measured round trip, [member MwNetClient.rtt_ms]). 0 on the host.
func host_lead() -> int:
	if client == null:
		return 0
	return lead() + roundi(client.rtt_ms * 0.5 * MwRouter.TICK_HZ / 1000.0)


## This machine's players' latest wire states (number -> MwNetInput state,
## sampled this frame): their held directions steer their own skaters in
## the dead reckoning's picture.
func local_states() -> Dictionary:
	return _states


## The router tick stream tick [param n] runs on, and back.
func router_tick(n: int) -> int:
	return base + n


## The stream tick that router tick [param t] runs ([method router_tick] the other way).
func stream_tick(t: int) -> int:
	return t - base


## The client's newly confirmed ticks into the router's stream (one no
## longer held - the game far behind - asks for a resync snapshot, unless
## one is on its way: its stream starts at the snapshot's tick).
func _pull() -> void:
	while _next_pull <= client.stream.confirmed:
		var t := client.stream.get_tick(_next_pull)
		if t.is_empty():
			if not _asked and not client.snapshot_pending():
				_ask_resync(MwNetProtocol.Resync.LOST, "tick %d no longer held" % _next_pull)
			break
		stream.append(MwTickInput.from_wire(t))
		_next_pull += 1


## Work item 6: asks the host for a resync snapshot ([param reason],
## MwNetProtocol.Resync), once until one is taken up.
func _ask_resync(reason: int, why: String) -> void:
	_asked = true
	_log("%s: a resync asked" % why)
	client.request_resync(reason)


## After a frame's ticks: the game's requests (kicks, a DISCONNECT), the
## end, the stream's old ticks let go.
func _after_ticks() -> void:
	if phase != Phase.PLAYING:
		return
	var control := _control()
	if control != null:
		if role == Role.HOST:
			for m: int in control.kicks:
				if m != MwNetLobby.HOST_MACHINE and not _kicked.has(m):
					kick(m)
		elif machine in control.leaving:
			leave()                                     # our players all left: DISCONNECT
			return
	if _game_left():
		_finish(End.LOBBY)
		return
	if stats["frames"] % 60 == 0:
		stream.drop_before(router.tick - KEEP_TICKS)


## The match's control layer (null before the first rink).
func _control() -> MwRinkControl:
	var st: Variant = session.screens.get("rink")
	return (st as MwRinkState).control if st is MwRinkState else null


## The game asked for the lobby (Back from the game options): the same tick
## on every machine.
func _game_left() -> bool:
	var to: Variant = router.pending_id()
	return to is int and int(to) == MwFlow.ONLINE_LOBBY


## Plan 45 (M2): a client's game asked for a screen no online match shows
## ([constant ONLINE_SCREENS]; the lobby is the game's own way out) - only a
## host's stream takes it there (its P1's presses drive the shared menu
## verbs). Checked before each tick the client runs and after the last: a
## change asked for in one tick is made in a later one (MwRouter.step), so
## the screen is never entered - the host is dropped and the match ends
## ([method _refuse_host]). True when it ended so.
func _strayed() -> bool:
	var to: Variant = router.pending_id()
	if to == null or online_screen(to) or (to is int and int(to) == MwFlow.ONLINE_LOBBY):
		return false
	_refuse_host("the game asked for screen %s" % str(to))
	return true


## Plan 45 (M2): the host sent what no honest host sends ([param why]): it
## is dropped as for any garbage ([method MwNetClient.reject_host]: the
## rejoin key let go) and the match ends for this machine - back to ONLINE
## MULTIPLAYER with THE HOST SENT SOMETHING WRONG.
func _refuse_host(why: String) -> void:
	_log("the host's game went astray: " + why)
	push_warning("MwNetMatch: the host's game went astray: " + why)
	client.reject_host(why)
	_finish(End.PROTOCOL)


# --- this machine's players ------------------------------------------------------------------------

## This machine's players' states now (number -> MwNetInput state): the
## devices sampled in the current screen's contexts, presses counted from
## the devices' taps, sticks quantised, shot heights by this machine's
## setting and its players' layouts (MwLiveInput.heights).
func _sample_local() -> Dictionary:
	var out := {}
	if local == null or locals.is_empty():
		return out
	var sample := MwNetInput.sample_of(local, router.contexts())     # plan 40 (S7): offline's capture too
	for n: int in locals:
		var before: PackedByteArray = _states.get(n, MwNetInput.blank())
		var st := MwNetInput.capture(before, int(locals[n]), sample)
		if role == Role.CLIENT:
			_note_presses(n, before, st)
		_states[n] = st
		out[n] = st
	return out


# --- plan 41: client-side menus ------------------------------------------------------------------------

## Player [param n]'s menu presses between two of its states, logged in
## the order captured ([method unconfirmed]).
func _note_presses(n: int, before: PackedByteArray, after: PackedByteArray) -> void:
	for v in MwNetInput.pressed_verbs(before, after):
		if v < MENU_VERB:
			continue
		var c := int(before[MwNetInput.COUNTERS + v])
		for i in MwNetInput.presses(before, after, v):
			c = (c + 1) & 0xFF
			_echo.append([n, v, c, ahead_tick() + 1])      # (+1: the pass after the tick it is merged at)
	if _echo.size() > ECHO_MAX:
		_echo = _echo.slice(_echo.size() - ECHO_MAX)


## A client's menu presses its game hasn't run yet (player number -> an
## Array of verb names, in the order pressed): those whose press counter the screens'
## passes haven't reached ([method MwStreamInput.ran]) - a round trip and
## the buffer after they were made. The rest are let go. {} on the host.
## Into [param ids] (work item 3): player -> verb -> each of those presses'
## [counter, the router tick its game is expected to run it at], in order
## (what a predicted sound is keyed by and due at).
func unconfirmed(ids: Dictionary = {}) -> Dictionary:
	var out := {}
	if role != Role.CLIENT or input == null or _echo.is_empty():
		return out
	var ran := input.ran()
	var kept := []
	for press: Array in _echo:
		var at: int = MwTickInput.slot_range(int(press[0])).x + int(press[1])
		var d := (int(press[2]) - (int(ran[at]) if at < ran.size() else 0)) & 0xFF
		if d == 0 or d >= 128:
			continue                         # run (or behind what ran: a resync)
		kept.append(press)
		if not out.has(press[0]):
			out[press[0]] = []
		var verb: String = MwNetInput.VERBS[int(press[1])]
		(out[press[0]] as Array).append(verb)
		# plan 41 work item 3: each press's own id (its counter) - a predicted sound's key
		if not ids.has(press[0]):
			ids[press[0]] = {}
		if not (ids[press[0]] as Dictionary).has(verb):
			ids[press[0]][verb] = []
		(ids[press[0]][verb] as Array).append([int(press[2]), int(press[3])])
	_echo = kept
	return out


# --- plan 41: the run-ahead's input --------------------------------------------------------------------

## The router tick the host will merge this machine's input at, sent now:
## the newest confirmed tick and the round trip - where a client's run-ahead
## shows the game ([param share] of the round trip: 0.5 the host's own
## now, dead reckoning's reach). The newest confirmed tick on the host.
## Plan 43 (stamped): the stamp of the newest state sent - the tick the host
## takes it at - so the run-ahead never plays a tick a state still to be
## sent will be taken at (share of the way to it from the newest confirmed).
func ahead_tick(share := 1.0) -> int:
	if client == null:
		return router.tick
	if stamped and _last_stamp > 0:
		var last := stream.last_tick()
		return last + roundi(maxi(_last_stamp - last, 0) * share)
	return _reckoned(share)


## [method ahead_tick] as the round trip and [member merge_bias] reckon it.
func _reckoned(share := 1.0) -> int:
	return stream.last_tick() + roundi((client.rtt_ms * MwRouter.TICK_HZ / 1000.0 + merge_bias) * share)


## The stream's newest ticks against what this machine sent: each change of
## one of its players' held input (the held verbs, the stick, the shot
## height - not the counters, which the merge spreads a tick a press) found
## among the states sent ([member _mine]: the change sent nearest the tick
## it was expected at), [member merge_bias] stepped towards the ticks it
## landed off by.
func _learn_merge() -> void:
	var last := stream.last_tick()
	if _learned < 0 or last - _learned > SENT_MAX:
		_learned = last
		return
	for k in range(_learned + 1, last + 1):
		var previous := stream.at(k - 1)
		var tick_input := stream.at(k)
		if previous == null or tick_input == null:
			continue
		var sa: PackedByteArray = previous.states()[1]
		var sb: PackedByteArray = tick_input.states()[1]
		for n: int in _states:
			var hb := _held_part(MwNetInput.player(sb, n))
			if hb == _held_part(MwNetInput.player(sa, n)):
				continue
			var off := 1 << 30
			for i in range(_mine.size() - 1, 0, -1):
				var st: Variant = (_mine[i][1] as Dictionary).get(n)
				var was: Variant = (_mine[i - 1][1] as Dictionary).get(n)
				if st != null and _held_part(st) == hb and (was == null or _held_part(was) != hb):
					var d := k - int(_mine[i][0])
					if absi(d) < absi(off):
						off = d
			if off != 1 << 30:
				merge_bias = clampf(merge_bias + MERGE_GAIN * off, -MERGE_BIAS_MAX, MERGE_BIAS_MAX)
				stats["merge_seen"] = int(stats.get("merge_seen", 0)) + 1
	_learned = last


## Plan 43 (stamped): [member merge_bias] steered so the host holds this
## machine's input [constant STAMP_SLACK] tick(s) before it is due - by the
## least of the last [constant SLACK_WINDOW] slacks the stream reported
## (MwNetClient.slacks: the stamp of the newest input the host had against
## the tick it made): later when one came late, sooner when all came early;
## a step for each new one.
func _steer_lead() -> void:
	var sl := client.slacks
	if sl.size() < 4 or client.slack_count == _slacks_steered:
		return                                   # (a stalled stream says nothing new: no step)
	_slacks_steered = client.slack_count
	var least := 1 << 30
	for i in range(maxi(sl.size() - SLACK_WINDOW, 0), sl.size()):
		least = mini(least, sl[i])
	merge_bias = clampf(merge_bias + STAMP_GAIN * (STAMP_SLACK - least), -MERGE_BIAS_MAX, MERGE_BIAS_MAX)
	stats["slack"] = least


static func _static_init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-feel="):
			feel_every = maxi(a.get_slice("=", 1).to_int(), 0)
		elif a == "--no-input-stamps":
			input_stamps = false


## Plan 41 work item 4: how the online feel is doing on this client, one
## line - the round trip, the buffer, where its input lands (merge bias);
## the run-ahead's pictures, passes and time, its rollbacks (and why) and
## budget cuts since the last line; the predicted sounds heard, matched by
## the game, never made.
func feel_line() -> String:
	var out := "feel: tick %d, rtt %d ms, buffer %d, merge bias %.2f" % [router.tick,
			client.rtt_ms if client != null else 0, lead() if stream != null else 0, merge_bias]
	if stamped:
		out += " (input stamped, held %d tick(s) early at least)" % int(stats.get("slack", 0))
	var ra: MwNetRunAhead = reckoning.run_ahead if reckoning != null else null
	if ra != null:
		var st := ra.stats.duplicate()
		var was: Dictionary = _feel_was if not _feel_was.is_empty() else {}
		var d := {}
		for k in st:
			d[k] = int(st[k]) - int(was.get(k, 0))
		_feel_was = st
		var runs := maxi(int(d["runs"]), 1)
		out += ("; run-ahead %s: %d pictures, %.1f passes and %.2f ms each, %d rolled back (%d mispredicted: own %d, "
				+ "others %d; %d unlike), %d cut by the budget, %d slowed and %d skipped behind the stream") % [
				"on" if ra.active() else "off", int(d["runs"]), float(d["passes"]) / runs, d["us"] / 1000.0 / runs,
				int(d["rollbacks"]), int(d["mispredicted"]), int(d["mis_own"]), int(d["mis_other"]), int(d["unlike"]),
				int(d["budget"]), int(d["slowed"]), int(d["behind"])]
	if MwSound.heard != null:
		out += "; heard: %s" % str(MwSound.heard.stats)
	return out


## A player's state but its counters and status: what it holds.
static func _held_part(st: PackedByteArray) -> PackedByteArray:
	var h := MwNetInput.with_status(st, 0)
	return h.slice(0, MwNetInput.COUNTERS) + h.slice(MwNetInput.STICK, MwNetInput.SIZE)


## The router's input for tick [param k] as this client expects it: the
## stream's once it holds it; past the newest confirmed tick, that tick with
## this machine's players' states as sent for the host to merge by [param k]
## (each player's status the stream's) - every other player holding what the
## stream has them hold, pressing nothing new. Null without a stream.
func input_at(k: int) -> MwTickInput:
	var ti := stream.at(k)
	if ti != null:
		return ti
	var last := stream.at(stream.last_tick())
	if last == null:
		return null
	var mine := {}
	for i in range(_mine.size() - 1, -1, -1):
		if int(_mine[i][0]) <= k:
			mine = _mine[i][1]
			break
	# plan 42 (speed): the ticks predicted from the same newest tick and the
	# same states of this machine's are one tick (made once: from_states
	# reads every verb of every player)
	if is_same(last, _predicted_from) and _same_states(mine, _predicted_mine):
		return _predicted
	var st := last.states()
	var bytes: PackedByteArray = st[1]
	for n: int in mine:
		var conf := MwNetInput.player(bytes, n)
		bytes = MwNetInput.with_player(bytes, n, MwNetInput.with_status(mine[n], MwNetInput.status(conf)))
	_predicted = MwTickInput.from_states(st[0], bytes)
	_predicted_from = last
	_predicted_mine = mine
	return _predicted


## Whether this machine's players' states [param a] and [param b] (number
## -> state) are the same.
static func _same_states(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for n: int in a:
		if not b.has(n) or a[n] != b[n]:
			return false
	return true


## After a frame's ticks: the screen on top shows this machine's presses
## not yet run (MwScreen.predict_local) - once more with none after it
## showed some, so it draws its own model again.
func _echo_screens() -> void:
	var top := router.current()
	if top == null:
		return
	var ids := {}
	var presses := unconfirmed(ids) if MwLocalEcho.enabled else {}
	MwLocalEcho.press_ids = ids
	if presses.is_empty() and not _echoing:
		return
	_echoing = not presses.is_empty()
	top.predict_local(presses)


# --- the host: statuses and kicks ---------------------------------------------------------------------

## Each player's network status for the next tick ([method status_of]).
func _update_status() -> void:
	for n: int in session.online_players():
		host.merge.set_status(n, status_of(n))


## Player [param n]'s network status (MwTickInput.HERE ...): the host's own
## always here; a kicked machine's KICKED; a dropped one (or one back but
## not synced yet) DISCONNECTED; a machine silent for [constant LAG_TICKS]
## LAGGING.
func status_of(n: int) -> int:
	var m := session.machine_of(n)
	if m == MwNetLobby.HOST_MACHINE:
		return MwTickInput.HERE
	if _kicked.has(m) or not lobby.machines.has(m):
		return MwTickInput.KICKED
	if not bool(lobby.machines[m]["connected"]) or _unsynced.has(m):
		return MwTickInput.DISCONNECTED
	if host.merge.silent_ticks(n) >= LAG_TICKS:
		return MwTickInput.LAGGING
	return MwTickInput.HERE


## A dropped machine came back with its key: its players stay
## DISCONNECTED (the CPU's) until its game is synced again - a snapshot at
## the next safe point (work item 6), then [method mark_synced].
func _on_rejoined(m: int) -> void:
	_unsynced[m] = true
	_awaiting.erase(m)                     # a new connection: whatever was on its way is gone
	_wants[m] = Want.REJOIN
	_log("machine %d rejoined: the CPU plays for it until it is synced" % m)


## Machine [param m]'s game is the host's again (work item 6): its players
## are theirs from the next tick.
func mark_synced(m: int) -> void:
	_unsynced.erase(m)


## Work item 6: machine [param m] asked for a resync snapshot (its stream
## lost - unless one is on its way, which starts its stream again -, its
## last snapshot failed).
func _on_resync_requested(m: int, reason: int) -> void:
	if reason == MwNetProtocol.Resync.LOST and _awaiting.has(m):
		return
	if reason == MwNetProtocol.Resync.FAILED:
		_awaiting.erase(m)
	if not _wants.has(m):
		_wants[m] = Want.LOST if reason == MwNetProtocol.Resync.LOST else Want.FAILED


## Work item 6: machine [param m]'s game is taken up from snapshot
## [param id]: if it is the last one sent to it, its players are theirs.
func _on_synced(m: int, id: int) -> void:
	if int(_sent.get(m, -1)) != id:
		return
	_awaiting.erase(m)
	_log("machine %d synced (snapshot %d)" % [m, id])
	mark_synced(m)


## Work item 6: a screen change on the host - a safe point. The machines
## owed a snapshot ([member _wants]; connected, not kicked) get one of the
## game as it is now ([MwNetSnapshot]); one that couldn't be sent to waits
## for the next. Not when leaving the match (the lobby, ONLINE MULTIPLAYER).
func _on_entering(request: Dictionary, previous: int) -> void:
	if role != Role.HOST or phase != Phase.PLAYING or _wants.is_empty():
		return
	var to: Variant = request.get("id")
	if not to is int or int(to) in [MwFlow.ONLINE_LOBBY, MwFlow.ONLINE_MENU]:
		return
	var targets: Array[int] = []
	for m: int in _wants.keys():
		if _kicked.has(m) or not lobby.machines.has(m):
			_wants.erase(m)
		elif bool(lobby.machines[m]["connected"]):
			targets.append(m)
	if targets.is_empty():
		return
	var n := stream_tick(router.tick)
	var d := MwNetSnapshot.capture(router, request, previous, base, input)
	if d.has("errors"):
		_log("snapshot at tick %d: left out %s" % [n, str(d["errors"])])
	var bytes := MwNetSnapshot.to_bytes(d)
	stats["snapshot_bytes"] = bytes.size()
	for m in targets:
		var id := host.send_snapshot(m, n, bytes)
		if id == 0:
			continue
		_sent[m] = id
		_awaiting[m] = [id, n]
		_wants.erase(m)
		stats["snapshots"] += 1
		_log("snapshot %d for machine %d at tick %d (screen %d): %d bytes" % [id, m, n, int(to), bytes.size()])


## KICK machine [param m] (its key erased, its address blocked; its
## players KICKED in the stream from the next tick).
func kick(m: int) -> void:
	_kicked[m] = true
	stats["kicks"] += 1
	host.kick(m)
	_log("kicked machine %d" % m)


## Every connected client holds stream tick [param t].
func _all_hold(t: int) -> bool:
	for id in lobby.machines:
		if int(id) == MwNetLobby.HOST_MACHINE or not bool(lobby.machines[id]["connected"]):
			continue
		var ack := host.machine_ack(int(id))
		if ack == MwNetProtocol.NONE or ack < t:
			return false
	return true


# --- hashes ---------------------------------------------------------------------------------------------

func _watch() -> void:
	var on_pass := func(b: Dictionary) -> void:
		var id := int(b.screen)
		var st: Variant = session.screens.get("rink")
		if st is MwRinkState and id >= 4 and id <= 17:
			var bytes := var_to_bytes(MwNetHash.rink_dict(st))
			_hashed(router.tick, HASH_PASS, id, MwNetHash.digest_bytes(bytes), bytes)
	var on_screen := func(id: int, _visit: int, tick: int, _prev: int) -> void:
		var r := session.to_record()
		r.erase("screen")
		r.erase("tick")
		var bytes := var_to_bytes(MwNetHash.plain(r))
		_hashed(tick, HASH_SCREEN, id, MwNetHash.digest_bytes(bytes), bytes)
	router.pass_ended.connect(on_pass)
	router.screen_entered.connect(on_screen)
	_hooks = [[router.pass_ended, on_pass], [router.screen_entered, on_screen]]
	if role == Role.HOST:
		router.entering.connect(_on_entering)
		_hooks.append([router.entering, _on_entering])


func _unwatch() -> void:
	for h: Array in _hooks:
		if (h[0] as Signal).is_connected(h[1]):
			(h[0] as Signal).disconnect(h[1])
	_hooks = []


## A hash of this machine's game at router tick [param t] ([param bytes]:
## what was hashed, kept for a dump).
func _hashed(t: int, kind: int, screen: int, h: int, bytes: PackedByteArray) -> void:
	var n := stream_tick(t)
	if n < 0:
		return
	if keep_hashes:
		hashes.append([n, kind, screen, h])
	var key := n * 4 + kind
	if dumps:
		_kept[key] = bytes
		_kept_order.append(key)
		while _kept_order.size() > KEEP_STATES:
			_kept.erase(_kept_order.pop_front())
	if role == Role.HOST:
		host.add_hash(n, kind, hash_bytes(h))
	else:
		_pending[key] = [n, kind, h, screen]


## The client's hashes against the host's, as they come.
func _check_hashes() -> void:
	if _pending.is_empty():
		return
	for key: int in _pending.keys():
		var entry: Array = _pending[key]
		var theirs := client.host_hash(int(entry[0]), int(entry[1]))
		if theirs.is_empty():
			if client.stream.newest - int(entry[0]) > HASH_PATIENCE:
				_pending.erase(key)
				stats["unchecked"] += 1
			continue
		_pending.erase(key)
		stats["checked"] += 1
		var mine := hash_bytes(int(entry[2]))
		if mine != theirs:
			_mismatch(int(entry[0]), int(entry[1]), int(entry[3]), mine, theirs)


## A hash of ours differed from the host's: noted; the first of a run (and
## then one every [constant REPORT_EVERY] ticks: once apart, every later
## hash differs too) logged, dumped and reported to the host.
func _mismatch(n: int, kind: int, screen: int, mine: PackedByteArray, theirs: PackedByteArray) -> void:
	stats["mismatches"] = int(stats.get("mismatches", 0)) + 1
	if mismatches.size() < 100:
		mismatches.append({"tick": n, "kind": kind, "screen": screen, "mine": mine.hex_encode(),
				"host": theirs.hex_encode()})
	if _reported >= 0 and n - _reported < REPORT_EVERY or client.snapshot_pending():
		return                                      # (a snapshot on its way replaces this game anyway)
	_reported = n
	_log("desync at tick %d (%s, screen %d): ours %s, the host's %s" % [n,
			"pass" if kind == HASH_PASS else "screen", screen, mine.hex_encode(), theirs.hex_encode()])
	_dump(n, kind, "client%d" % machine)
	client.report_desync(n, kind, mine)
	desynced.emit(n, kind)


## The host: a client reported a desync - our state for that tick dumped
## beside its, and a resync snapshot owed it at the next safe point.
func _on_desync_reported(m: int, n: int, kind: int, value: PackedByteArray) -> void:
	_log("machine %d disagrees at tick %d (%s): theirs %s" % [m, n, "pass" if kind == HASH_PASS else "screen",
			value.hex_encode()])
	_dump(n, kind, "host")
	var on_way: Array = _awaiting.get(m, [])
	if not _wants.has(m) and (on_way.is_empty() or n > int(on_way[1])):
		_wants[m] = Want.DESYNC             # (not for a game a snapshot on its way replaces)


## Writes the kept state of stream tick [param n], [param kind] ([member
## dumps]: debug builds) as text, named for the match, the tick, the kind
## and [param who]; the path, or "".
func _dump(n: int, kind: int, who: String) -> String:
	if not dumps or not _kept.has(n * 4 + kind):
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dump_dir))
	var path := dump_dir.path_join("%d_%d_%d_%s.txt" % [match_id, n, kind, who])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(var_to_str(bytes_to_var(_kept[n * 4 + kind])))
	f.close()
	_log("dumped %s" % path)
	return path


## The kept state of stream tick [param n], [param kind] (empty: none).
func kept_state(n: int, kind: int) -> PackedByteArray:
	return _kept.get(n * 4 + kind, PackedByteArray())


## A hash (63 bits) as the 8 bytes HASHES carries.
static func hash_bytes(h: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(8)
	for i in 8:
		b[i] = (h >> (56 - 8 * i)) & 0xFF
	return b


# --- work item 6: taking a game up from a resync snapshot ------------------------------------------------

## The client's game taken up from the host's snapshot (whole, its tick in
## the stream): the router reset at its tick in the stream mode, the session,
## the sound driver's model and the router's state the snapshot's
## (MwNetSnapshot.restore), the match rules in force, the stream followed
## from that tick, the screen entered as the host entered it (MwRouter
## .resume_entry) - its entry's hash then checks the session against the
## host's at once. SYNCED tells the host. A snapshot that can't be read or
## taken up asks for another (the game waits meanwhile).
func _load() -> void:
	var snap := client.take_snapshot()
	var n := int(snap.get("tick", -1))
	var d := MwNetSnapshot.from_bytes(snap.get("data", PackedByteArray()))
	if d.is_empty() or int(d["tick"]) - int(d["base"]) != n:
		_failed_load("snapshot %d unreadable" % int(snap.get("id", -1)))
		return
	if not online_screen(d["screen"]):
		_refuse_host("snapshot %d enters screen %d" % [int(snap["id"]), int(d["screen"])])    # plan 45 (M2)
		return
	_unwatch()
	stream = MwInputStream.new()
	var errors := PackedStringArray()
	var entry := MwGameStart.take_up(router, session, d, stream, errors)   # its context in force (plan 40)
	if entry.is_empty():
		_failed_load("snapshot %d not taken up: %s" % [int(snap["id"]), str(errors.slice(0, 5))])
		return
	base = int(d["base"])
	session.machine = machine
	_take_stamps()
	input = MwStreamInput.new(stream)
	input.attach(router)
	input.take_up(d["seen"], int(d["tick"]))
	_next_pull = n
	_pull()
	_pending.clear()
	_kept.clear()
	_kept_order.clear()
	_reported = -1
	_asked = false
	hashes.clear()
	_watch()
	phase = Phase.PLAYING
	router.driver = self
	synced_at = n
	synced_screen = int((entry["request"] as Dictionary)["id"])
	stats["loaded"] += 1
	stats["snapshot_bytes"] = (snap["data"] as PackedByteArray).size()
	_log("taken up from snapshot %d at tick %d (screen %d, %d bytes)" % [int(snap["id"]), n, synced_screen,
			stats["snapshot_bytes"]])
	router.resume_entry(entry["request"], int(entry["previous"]))
	client.report_synced(int(snap["id"]))
	synced.emit(n, synced_screen)


## A snapshot that couldn't be taken up: logged, another asked for; the game
## waits for it (WAITING: nothing of it runs).
func _failed_load(why: String) -> void:
	_log(why)
	push_warning("MwNetMatch: " + why)
	phase = Phase.WAITING
	_asked = true
	client.request_resync(MwNetProtocol.Resync.FAILED)


# --- the end --------------------------------------------------------------------------------------------

## The match is over for this machine ([param why]): the router handed back
## (the realtime clock, this machine's devices, its own settings, its own
## custom teams - plan 38), and, unless the game itself left for the lobby,
## on to ONLINE MULTIPLAYER with the reason. The host keeps its stream going
## until every machine holds the last tick (ENDING). A machine still
## waiting for its snapshot (WAITING) ends the same way.
func _finish(why: int) -> void:
	if phase != Phase.PLAYING and phase != Phase.WAITING:
		return
	var was_waiting := phase == Phase.WAITING
	end_reason = why
	_end_tick = stream_tick(router.tick)
	_end_since = _now
	_unwatch()
	router.split_audio(false)                      # (plan 41: one driver again)
	router.clock = MwPassClock.realtime()
	MwStreamInput.live(local if local is MwLiveInput else MwLiveInput.new()).attach(router)   # (plan 40, S7)
	MwGameStart.own_context()                      # its own rules and bank again (plan 38)
	session.custom_teams = {}
	session.online = {}
	session.machine = -1
	session.reckoning = null
	var text: String = END_TEXT.get(why, "")
	_log("the match is over for this machine: %d %s" % [why, text])
	if why != End.LOBBY:
		_sounds_off()
		router.force_go(MwFlow.ONLINE_MENU, {"message": text})
	elif was_waiting and router.current_id() != MwFlow.ONLINE_LOBBY:
		_sounds_off()
		router.force_go(MwFlow.ONLINE_LOBBY, {})    # (a snapshot that failed left another screen)
	if role == Role.HOST and why == End.LOBBY:
		phase = Phase.ENDING
	else:
		phase = Phase.OVER
	ended.emit(why, text)


## The match left for the online pages from wherever it stands (DISCONNECT,
## CLOSE, the host gone, a kick, a lost connection): its sounds stopped as
## the game's own leaving of a match stops them - `$13C04`, the music faded
## at once, the crowd off, the driver reset, the port's extra voices and
## organ stopped (MwSound.enter_match, as MwRinkPhases' exits) - on the
## driver that is heard (one again: after [method MwRouter.split_audio]).
## Owner, 2026-10-13: the crowd's noise went on after quitting an online game
## for the menu. The game's own way back to the lobby (Back from the game
## options) has stopped them on its screens already.
func _sounds_off() -> void:
	MwSound.enter_match(0)


## Plan 45 (stability M4): the match is over for this machine ([method
## frame] returns false then - and when a script error stopped it: [method
## MwRouter.drive] tells them apart).
func over() -> bool:
	return phase == Phase.OVER


## Plan 45 (stability M4): this machine leaves a match whose [method frame]
## stopped on a script error - the router, its clock and its input given
## back and the online pages shown - instead of freezing on a stream nobody
## feeds ([method MwRouter.drive] calls it when [method frame] returned
## false before the match was [method over]).
func abandon() -> void:
	if phase == Phase.OVER:
		return
	if role == Role.CLIENT:
		client.cancel()
	elif host != null:
		host.close()
	_finish(End.LEFT)
	phase = Phase.OVER                             # (ENDING: the router was handed back already)


## Leaves the match from this machine (a client's DISCONNECT: the key kept
## for a rejoin; the host's: everyone's match ends).
func leave() -> void:
	if phase != Phase.PLAYING:
		return
	if role == Role.CLIENT:
		client.cancel()
	else:
		host.close()
	_finish(End.LEFT)


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 200:
		log_lines.remove_at(0)
