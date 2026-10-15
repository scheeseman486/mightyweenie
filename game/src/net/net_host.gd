class_name MwNetHost
extends RefCounted
## The host's side of an online game (plan 35 sections 1-3, 5, 6): the
## handshake, the lobby, the merged input stream - node-free, polled
## ([method poll] with the time, [method step] once a tick), over any
## [MwNetTransport] (ENet with DTLS for real, the loopback in tests).
##
## * Every new connection gets the host's certificate (CERT) first; then
##   HELLO -> CHALLENGE -> AUTH -> WELCOME (or REFUSE). Checked in turn: the
##   version, build and verb table, the ROM, a wait after wrong passwords
##   or too many tries, a match running (only a proof of a machine's rejoin
##   key gets in - MwNetProtocol.rejoin_proof: the key itself never comes
##   back, version 6), room for the machine's players, then the password's
##   proof bound to the certificate's fingerprint (MwNetProtocol.proof). A wrong
##   password is answered with a wait that grows (1, 2, 4 ... 30 s) during
##   which that address is turned away.
## * The lobby ([member lobby], MwNetLobby): machines join and leave, their
##   local players join (JOIN_LOCAL) and leave (LEAVE_LOCAL), EXIT LOBBY
##   (BYE) removes a machine; [method start_match], [method end_match],
##   [method close] (CLOSE LOBBY), [method kick] (the key erased, the
##   address - an IPv6 one by its /64 - blocked while the server runs).
## * A machine that drops while a match runs keeps its players and key: the
##   key brings it back on the same numbers (section 5). In the lobby a drop
##   removes it.
## * Resync snapshots (section 5, work item 6): [method send_snapshot] sends
##   one in chunks on the reliable channel and starts the machine's stream
##   again from its tick; a machine asks for one (RESYNC: [signal
##   resync_requested]) and says when its game is taken up ([signal synced]).
## * The stream ([method step]): each tick every player's input merged
##   ([MwNetMerge]) and sent to every machine with the last ticks repeated
##   ([MwNetTickLog]) - every tick, or every second tick while the line to it
##   is full ([MwNetPace]: docs/net.md "A slow uplink"); resends on request;
##   hashes (MwNetProtocol.hashes) as the game adds them ([method add_hash]),
##   every [constant HASH_EVERY] ticks.
## * Security (section 6): every packet decoded and checked; garbage, a
##   message out of turn, another machine's player numbers or a flood drop
##   the peer; tries are rate-limited per address, resends per machine,
##   unauthenticated connections are few and short-lived (plan 45: at most
##   [constant MAX_PENDING_PER] from one address, HELLO within [constant
##   HELLO_DEADLINE_MS] - one address can't fill them). Tries and waits
##   count per address - an IPv6 one by its /64, which one machine can
##   change within ([method block_key]) - and old counts are forgotten.
##   Secrets - the password's key, the rejoin keys - are never logged.

## A connection from [param address] turned away - a blocked address, or a handshake check
## failed; [param code] is its [enum MwNetProtocol.Refusal].
signal refused(address: String, code: int)
## Machine [param id]'s connection was lost: while a match runs it stays, away, with its
## players and key; otherwise it leaves the lobby.
signal machine_dropped(id: int)
## Machine [param id] came back with its rejoin key (section 5), connected again on its
## player numbers.
signal machine_rejoined(id: int)
## The lobby closed ([method close]): every connection ended, every key gone.
signal closed
## A client's game disagreed with a hash of ours (work item 4: MwNetMatch
## logs both states): machine, stream tick, kind, the client's hash.
signal desync_reported(machine: int, tick: int, kind: int, value: PackedByteArray)
## Work item 6: a machine wants a resync snapshot (MwNetProtocol.Resync: its
## stream lost, its last snapshot failed).
signal resync_requested(machine: int, reason: int)
## Work item 6: a machine's game is taken up from snapshot [param id].
signal synced(machine: int, id: int)

## An unauthenticated connection must finish the handshake within this.
const HANDSHAKE_MS := 10000
## Plan 45 (M1): ... and say HELLO within this (ms from its connecting): the
## host's CERT and the client's HELLO are a round trip, each reliable and
## sent again when lost, so several losses in a row must fit. On the
## loopback at the tests' worst (40 % loss, 250 ms) 120 joins all got in at
## 5 s; at 3 s, 9 failed. A connection that never says HELLO goes in half
## [constant HANDSHAKE_MS].
const HELLO_DEADLINE_MS := 5000
## Unauthenticated connections at most at once.
const MAX_PENDING := 8
## Plan 45 (M1): ... and from one address (an IPv6 one by its /64,
## [method block_key]), so one address can't fill [constant MAX_PENDING]
## and turn every join and rejoin away (BUSY). A machine's own two may
## overlap: the certificate fetched on its first contact, then the pinned
## session.
const MAX_PENDING_PER := 2
## HELLOs per address per window.
const HELLO_LIMIT := 5
const HELLO_WINDOW_MS := 10000
## Packets per peer per second before it counts as a flood.
const PACKET_LIMIT := 600
## Resend requests per machine per second (more are ignored).
const RESEND_LIMIT := 10
## Desync reports per machine at most this often (more are ignored).
const DESYNC_EVERY_MS := 250
## Resync requests per machine at most this often (more are ignored).
const RESYNC_EVERY_MS := 1000
const PING_EVERY_MS := 1000
## The lobby goes out again for ping changes at most this often.
const LOBBY_PING_EVERY_MS := 2000
## A machine gets the last hashes (HASHES) every this many ticks while they
## are recent: with a hash every pass (two ticks) each goes out 4 times. Sent
## every tick they were two thirds of the host's upload (the soak's slow
## uplink, docs/net.md).
const HASH_EVERY := 4
## The waits after each wrong password, in seconds.
const WAITS := [1, 2, 4, 8, 16, 30]

enum Stage { NEW, CHALLENGED, IN }


## One connection.
class Peer:
	var id := 0
	var address := ""
	## Its address's [method block_key] (plan 45: what its share of the
	## pending connections counts by).
	var block := ""
	var stage := Stage.NEW
	var since := 0
	var client_nonce := PackedByteArray()
	var host_nonce := PackedByteArray()
	var locals := 1
	var rejoin_machine := -1
	var machine := -1
	var window := 0
	var count := 0
	var resend_window := 0
	var resends := 0
	## The stream: the newest tick it holds with all before (NONE), the
	## first tick it needs.
	var ack := MwNetProtocol.NONE
	var floor_no := 0
	var inputs: MwNetTickReceiver
	var fed := -1
	## Plan 43: the host tick each of its input states is meant for
	## (sequence -> stamp; the last [constant STAMPS_KEPT]).
	var stamps := {}
	## How often its stream goes out (every tick, or every second tick while
	## its line is full).
	var pace := MwNetPace.new()
	var desync_at := -1000000
	var resync_at := -1000000


var transport: MwNetTransport
var lobby := MwNetLobby.new()
## {build, rom (20 bytes), schema}: what a machine must match.
var info := {}
var merge := MwNetMerge.new()
## Plan 43: input stamps kept a machine (sequences), and the most of a
## packet's states a stamped merge takes one by one (the rest: older).
const STAMPS_KEPT := 256
const FEED_MAX := 64
var stream := MwNetTickLog.new()
## The newest stream tick (-1: no match running).
var tick := -1
var log_lines := PackedStringArray()
var _key := PackedByteArray()
var _password := false
var _der := PackedByteArray()
var _fp := PackedByteArray()
var _peers := {}
var _keys := {}
var _fails := {}
var _hellos := {}
var _blocked := {}
var _hashes: Array = []
var _now := 0
var _last_ping := 0
var _last_prune := 0
var _last_lobby_ping := 0
var _ping_dirty := false
var _ping_seq := 0
var _snapshot_id := 0


## A host over [param transport_] (listening), showing the certificate [param der]
## (MwNetIdentity.der), with [param password] ("" for none) and [param
## build_info] (default: this build's, [method local_info]).
func _init(transport_: MwNetTransport, der: PackedByteArray, password := "", build_info := {}) -> void:
	transport = transport_
	_der = der
	_fp = MwNetIdentity.fingerprint_of(der)
	_key = MwNetProtocol.derive_key(password)
	_password = password != ""
	info = build_info if not build_info.is_empty() else local_info()


## What this build tells a host: {build, rom, schema}.
static func local_info() -> Dictionary:
	return {"build": build_id(), "rom": rom_sha1(), "schema": MwNetInput.schema()}


## The build: the project's version and the engine's (printable ASCII, as
## HELLO carries it).
static func build_id() -> String:
	var text := "%s / godot %s" % [str(ProjectSettings.get_setting("application/config/version", "dev")),
			str(Engine.get_version_info().get("string", ""))]
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		out += char(c) if c >= 32 and c <= 126 else "?"
	return out.left(MwNetProtocol.MAX_BUILD)


## The loaded ROM's SHA-1 (20 bytes; zeroes without a ROM).
static func rom_sha1() -> PackedByteArray:
	var sha := MwRom.archive().sha1 if MwRom.available() else ""
	var b := sha.hex_decode() if sha.length() == 40 and sha.is_valid_hex_number() else PackedByteArray()
	if b.size() != MwNetProtocol.SHA1_BYTES:
		b.resize(MwNetProtocol.SHA1_BYTES)
		b.fill(0)
	return b


## Opens the lobby: the host's machine and its first player, P1.
func open(device := 0) -> void:
	lobby.add_machine("", true)
	lobby.join(MwNetLobby.HOST_MACHINE, 1, device)


# --- polling --------------------------------------------------------------------------------------

## Handles everything that arrived, at time [param now_ms].
func poll(now_ms: int) -> void:
	_now = now_ms
	transport.poll()
	for ev in transport.take_events():
		match int(ev["kind"]):
			MwNetTransport.Kind.CONNECTED:
				_on_connect(int(ev["peer"]))
			MwNetTransport.Kind.DISCONNECTED:
				_on_disconnect(int(ev["peer"]))
			MwNetTransport.Kind.PACKET:
				_on_packet(int(ev["peer"]), int(ev["channel"]), ev["data"])
	for connection: Peer in _peers.values():
		if connection.stage == Stage.NEW and _now - connection.since > HELLO_DEADLINE_MS:
			_drop(connection, "no hello")              # plan 45 (M1)
		elif connection.stage != Stage.IN and _now - connection.since > HANDSHAKE_MS:
			_drop(connection, "handshake timeout")
	if _now - _last_ping >= PING_EVERY_MS:
		_last_ping = _now
		_ping_seq = (_ping_seq + 1) & 0xFFFF
		for peer: Peer in _peers.values():
			if peer.stage == Stage.IN:
				transport.send(peer.id, MwNetProtocol.CH_PING, MwNetProtocol.ping(_ping_seq, _now & 0xFFFFFFFF))
	if _ping_dirty and _now - _last_lobby_ping >= LOBBY_PING_EVERY_MS:
		_broadcast_lobby()
	if _now - _last_prune >= HELLO_WINDOW_MS:
		_last_prune = _now
		_prune()


## Forgets tries whose window has passed and waits long over (a wrong
## password's count lasts 10 minutes past its wait).
func _prune() -> void:
	for k in _hellos.keys():
		if _now - int(_hellos[k][0]) >= HELLO_WINDOW_MS:
			_hellos.erase(k)
	for k in _fails.keys():
		if _now - int(_fails[k][1]) >= 600000:
			_fails.erase(k)


## A new connection: turned away when its address is blocked, or when the
## unauthenticated connections are at [constant MAX_PENDING] - or at
## [constant MAX_PENDING_PER] from its address (plan 45, M1) - else shown
## the certificate.
func _on_connect(id: int) -> void:
	var address := transport.peer_address(id)
	var who := block_key(address)
	if _blocked.has(who):
		_log("blocked %s" % address)
		transport.send(id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.refuse(MwNetProtocol.Refusal.BLOCKED))
		transport.disconnect_peer(id)
		refused.emit(address, MwNetProtocol.Refusal.BLOCKED)
		return
	var pending := 0
	var mine := 0
	for connection: Peer in _peers.values():
		if connection.stage != Stage.IN:
			pending += 1
			if connection.block == who:
				mine += 1
	if pending >= MAX_PENDING or mine >= MAX_PENDING_PER:
		transport.send(id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.refuse(MwNetProtocol.Refusal.BUSY))
		transport.disconnect_peer(id)
		return
	var peer := Peer.new()
	peer.id = id
	peer.address = address
	peer.block = who
	peer.since = _now
	peer.window = _now
	_peers[id] = peer
	transport.send(id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.cert(_der))


func _on_disconnect(id: int) -> void:
	var peer: Peer = _peers.get(id)
	if peer == null:
		return
	_peers.erase(id)
	if peer.stage == Stage.IN and peer.machine >= 0:
		_log("machine %d lost" % peer.machine)
		_machine_lost(peer.machine)


func _machine_lost(machine: int) -> void:
	if not lobby.machines.has(machine):
		return
	if lobby.state == MwNetLobby.State.RUNNING:
		lobby.set_connected(machine, false)
	else:
		lobby.remove_machine(machine)
		_keys.erase(machine)
	machine_dropped.emit(machine)
	_broadcast_lobby()


func _on_packet(id: int, channel: int, data: PackedByteArray) -> void:
	var peer: Peer = _peers.get(id)
	if peer == null:
		return
	if _now - peer.window >= 1000:
		peer.window = _now
		peer.count = 0
	peer.count += 1
	if peer.count > PACKET_LIMIT:
		_drop(peer, "flood")
		return
	var m := MwNetProtocol.decode(data, channel)
	if m.is_empty():
		var head := MwNetProtocol.peek(data)
		if peer.stage == Stage.NEW and head.x == MwNetProtocol.Type.HELLO and head.y != MwNetProtocol.VERSION:
			_refuse(peer, MwNetProtocol.Refusal.VERSION)
		else:
			_drop(peer, "garbage")
		return
	var type := int(m["type"])
	if type == MwNetProtocol.Type.PING:
		transport.send(id, MwNetProtocol.CH_PING, MwNetProtocol.pong(m["seq"], m["time"], _tick_or_none()))
		return
	match peer.stage:
		Stage.NEW:
			if type == MwNetProtocol.Type.HELLO:
				_on_hello(peer, m)
			else:
				_drop(peer, "out of turn")
		Stage.CHALLENGED:
			if type == MwNetProtocol.Type.AUTH:
				_on_auth(peer, m)
			else:
				_drop(peer, "out of turn")
		Stage.IN:
			_on_message(peer, m)


# --- the handshake --------------------------------------------------------------------------------

func _on_hello(peer: Peer, m: Dictionary) -> void:
	var who := block_key(peer.address)
	var h: Array = _hellos.get(who, [_now, 0])
	if _now - int(h[0]) >= HELLO_WINDOW_MS:
		h = [_now, 0]
	h[1] = int(h[1]) + 1
	_hellos[who] = h
	if int(h[1]) > HELLO_LIMIT:
		_refuse(peer, MwNetProtocol.Refusal.WAIT, _seconds(int(h[0]) + HELLO_WINDOW_MS - _now))
		return
	var f: Array = _fails.get(who, [0, 0])
	if _now < int(f[1]):
		_refuse(peer, MwNetProtocol.Refusal.WAIT, _seconds(int(f[1]) - _now))
		return
	if str(m["build"]) != str(info["build"]) or int(m["schema"]) != int(info["schema"]):
		_refuse(peer, MwNetProtocol.Refusal.VERSION)
		return
	if m["rom"] != info["rom"]:
		_refuse(peer, MwNetProtocol.Refusal.ROM)
		return
	peer.locals = int(m["locals"])
	peer.rejoin_machine = _machine_with_key(m["key"], m["nonce"]) if lobby.state == MwNetLobby.State.RUNNING \
			else -1
	var why := _room_for(peer)
	if why != 0:
		_refuse(peer, why)
		return
	peer.client_nonce = m["nonce"]
	peer.host_nonce = MwNetProtocol.random_bytes(MwNetProtocol.NONCE_BYTES)
	peer.stage = Stage.CHALLENGED
	transport.send(peer.id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.challenge(peer.host_nonce, _password))


## 0 when [param peer] may come in now, else the refusal.
func _room_for(peer: Peer) -> int:
	if lobby.state == MwNetLobby.State.RUNNING:
		return 0 if peer.rejoin_machine >= 0 and lobby.machines.has(peer.rejoin_machine) \
				else MwNetProtocol.Refusal.RUNNING
	if lobby.state != MwNetLobby.State.OPEN:
		return MwNetProtocol.Refusal.BUSY
	if lobby.free_slots() < peer.locals or lobby.machines.size() > MwNetProtocol.MAX_MACHINE:
		return MwNetProtocol.Refusal.FULL
	return 0


## The machine whose rejoin key HELLO's [param proof] proves (-1: none):
## version 6 (plan 45, M3) - [method MwNetProtocol.rejoin_proof] of the key
## over the client's [param nonce] and our certificate's fingerprint, so the
## key itself never travels again after WELCOME. Every key is tried, each
## compared in constant time.
func _machine_with_key(proof: PackedByteArray, nonce: PackedByteArray) -> int:
	var found := -1
	if proof.size() != MwNetProtocol.KEY_BYTES:
		return -1
	for machine in _keys:
		if MwNetProtocol.same_secret(MwNetProtocol.rejoin_proof(_keys[machine], nonce, _fp), proof):
			found = machine
	return found


func _on_auth(peer: Peer, m: Dictionary) -> void:
	var expect := MwNetProtocol.proof(_key, "client", peer.client_nonce, peer.host_nonce, _fp)
	var who := block_key(peer.address)
	if not MwNetProtocol.same_secret(expect, m["proof"]):
		var f: Array = _fails.get(who, [0, 0])
		f[0] = int(f[0]) + 1
		var wait: int = WAITS[mini(int(f[0]) - 1, WAITS.size() - 1)]
		f[1] = _now + wait * 1000
		_fails[who] = f
		_refuse(peer, MwNetProtocol.Refusal.WRONG_PASSWORD, wait)
		return
	_fails.erase(who)
	var why := _room_for(peer)
	if why != 0:
		_refuse(peer, why)
		return
	var machine := peer.rejoin_machine
	if machine >= 0:
		for other: Peer in _peers.values():
			if other != peer and other.machine == machine:
				other.machine = -1
				_peers.erase(other.id)
				transport.disconnect_peer(other.id, true)
		lobby.machines[machine]["address"] = peer.address
		lobby.set_connected(machine, true)
		for n in lobby.numbers_of(machine):
			merge.new_source(n)
		peer.floor_no = tick + 1
		_log("machine %d rejoined" % machine)
		machine_rejoined.emit(machine)
	else:
		machine = lobby.add_machine(peer.address)
		if machine < 0:
			_refuse(peer, MwNetProtocol.Refusal.FULL)
			return
		for local in range(1, peer.locals + 1):
			lobby.join(machine, local, 0)
		_keys[machine] = MwNetProtocol.random_bytes(MwNetProtocol.KEY_BYTES)
		peer.floor_no = 0
		_log("machine %d joined from %s" % [machine, peer.address])
	peer.machine = machine
	peer.stage = Stage.IN
	peer.ack = MwNetProtocol.NONE
	peer.inputs = MwNetTickReceiver.new(0)
	peer.inputs.skip_gaps = true
	peer.inputs.allowed = lobby.mask_of(machine)
	peer.fed = -1
	peer.stamps.clear()
	var host_proof := MwNetProtocol.proof(_key, "host", peer.host_nonce, peer.client_nonce, _fp)
	transport.send(peer.id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.welcome(host_proof, machine,
			_keys[machine], lobby.match_id, _tick_or_none(), lobby.numbers_of(machine), lobby.to_wire()))
	_broadcast_lobby(peer.id)


func _refuse(peer: Peer, code: int, wait_s := 0) -> void:
	_log("refused %s: %d" % [peer.address, code])
	transport.send(peer.id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.refuse(code, wait_s))
	transport.disconnect_peer(peer.id)
	_peers.erase(peer.id)
	refused.emit(peer.address, code)


## Drops [param peer] at once (garbage, a flood, out of turn, too slow).
func _drop(peer: Peer, why: String) -> void:
	_log("dropped %s: %s" % [peer.address, why])
	if peer.stage == Stage.IN:
		transport.send(peer.id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.close(MwNetProtocol.Close.DROPPED))
	transport.disconnect_peer(peer.id)
	_peers.erase(peer.id)
	if peer.stage == Stage.IN and peer.machine >= 0:
		_machine_lost(peer.machine)


# --- in the lobby and the match ------------------------------------------------------------------

func _on_message(peer: Peer, m: Dictionary) -> void:
	match int(m["type"]):
		MwNetProtocol.Type.INPUT:
			# inputs count only in their match (one in flight across a START
			# is ignored), and so does an acknowledgement of a tick the match
			# hasn't reached
			var ack := int(m["ack"])
			if lobby.state != MwNetLobby.State.RUNNING or int(m["match"]) != lobby.match_id \
					or ack != MwNetProtocol.NONE and ack > tick:
				return
			if ack != MwNetProtocol.NONE and ack >= peer.floor_no \
					and (peer.ack == MwNetProtocol.NONE or ack > peer.ack):
				peer.ack = ack
				peer.pace.acked(ack, _now)
			var r := peer.inputs.receive(m["base"], m["first"], m["count"], m["body"])
			if r == MwNetTickReceiver.Result.BAD:
				_drop(peer, "bad input")
				return
			var stamps: PackedInt32Array = m.get("stamps", PackedInt32Array())
			for i in stamps.size():
				peer.stamps[int(m["first"]) + i] = stamps[i]
			if peer.inputs.newest > peer.fed:
				if merge.stamped:
					# plan 43: every new state, each at its stamp (in the order sent)
					for q in range(maxi(peer.fed + 1, peer.inputs.newest - FEED_MAX + 1), peer.inputs.newest + 1):
						if not peer.inputs.has(q):
							continue
						var t := peer.inputs.get_tick(q)
						var stamp := int(peer.stamps.get(q, -1))
						for n in lobby.numbers_of(peer.machine):
							merge.feed_at(n, MwNetInput.player(t, n), stamp)
				else:
					var latest := peer.inputs.latest()
					for n in lobby.numbers_of(peer.machine):
						merge.feed(n, MwNetInput.player(latest, n))
				peer.fed = peer.inputs.newest
				if peer.stamps.size() > STAMPS_KEPT:
					for q: int in peer.stamps.keys():
						if q <= peer.fed - STAMPS_KEPT / 2:
							peer.stamps.erase(q)
		MwNetProtocol.Type.JOIN_LOCAL:
			if lobby.state == MwNetLobby.State.OPEN and lobby.join(peer.machine, m["local"], m["device"]) != 0:
				peer.inputs.allowed = lobby.mask_of(peer.machine)
				_broadcast_lobby()
		MwNetProtocol.Type.LEAVE_LOCAL:
			var n := int(m["number"])
			if lobby.machine_of(n) != peer.machine:
				_drop(peer, "not its player")
				return
			if lobby.state == MwNetLobby.State.OPEN and lobby.leave(n):
				peer.inputs.allowed = lobby.mask_of(peer.machine)
				_broadcast_lobby()
		MwNetProtocol.Type.RESEND_REQUEST:
			if _now - peer.resend_window >= 1000:
				peer.resend_window = _now
				peer.resends = 0
			peer.resends += 1
			if peer.resends > RESEND_LIMIT or tick < 0:
				return
			if int(m["from"]) < stream.oldest() and int(m["from"]) >= peer.floor_no \
					and _now - peer.resync_at >= RESYNC_EVERY_MS:
				# work item 6: ticks we no longer keep - only a snapshot brings that machine back
				peer.resync_at = _now
				_log("machine %d asks for ticks from %d: the stream no longer holds them"
						% [peer.machine, int(m["from"])])
				resync_requested.emit(peer.machine, MwNetProtocol.Resync.LOST)
			for c in stream.encode_range(m["from"], m["to"], peer.floor_no):
				transport.send(peer.id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.resend(lobby.match_id,
						c["base"], c["first"], c["count"], c["body"]))
		MwNetProtocol.Type.BYE:
			_log("machine %d left" % peer.machine)
			_keys.erase(peer.machine)
			var machine := peer.machine
			peer.machine = -1
			_peers.erase(peer.id)
			transport.disconnect_peer(peer.id)
			lobby.remove_machine(machine)
			_broadcast_lobby()
		MwNetProtocol.Type.DESYNC:
			if lobby.state != MwNetLobby.State.RUNNING or int(m["match"]) != lobby.match_id \
					or int(m["tick"]) > tick or _now - peer.desync_at < DESYNC_EVERY_MS:
				return
			peer.desync_at = _now
			_log("machine %d reports a desync at tick %d (kind %d)" % [peer.machine, int(m["tick"]), int(m["kind"])])
			desync_reported.emit(peer.machine, int(m["tick"]), int(m["kind"]), m["value"])
		MwNetProtocol.Type.RESYNC:
			if lobby.state != MwNetLobby.State.RUNNING or int(m["match"]) != lobby.match_id \
					or _now - peer.resync_at < RESYNC_EVERY_MS:
				return
			peer.resync_at = _now
			_log("machine %d asks for a resync (%d)" % [peer.machine, int(m["reason"])])
			resync_requested.emit(peer.machine, int(m["reason"]))
		MwNetProtocol.Type.SYNCED:
			if lobby.state == MwNetLobby.State.RUNNING and int(m["match"]) == lobby.match_id:
				synced.emit(peer.machine, int(m["id"]))
		MwNetProtocol.Type.PONG:
			var rtt := (_now - int(m["time"])) & 0xFFFFFFFF
			if rtt < 60000 and lobby.set_ping(peer.machine, rtt, 5):
				_ping_dirty = true
		_:
			_drop(peer, "out of turn")


## Sends the lobby to every machine in it (but [param skip]).
func _broadcast_lobby(skip := -1) -> void:
	_ping_dirty = false
	_last_lobby_ping = _now
	var msg := MwNetProtocol.lobby(lobby.to_wire())
	for peer: Peer in _peers.values():
		if peer.stage == Stage.IN and peer.id != skip:
			transport.send(peer.id, MwNetProtocol.CH_RELIABLE, msg)


func _tick_or_none() -> int:
	return tick if tick >= 0 else MwNetProtocol.NONE


# --- the host's controls -------------------------------------------------------------------------

## The host's own device joins as its local player [param local]; the
## number (0: full or not now).
func join_local(local: int, device := 0) -> int:
	if lobby.state != MwNetLobby.State.OPEN:
		return 0
	var n := lobby.join(MwNetLobby.HOST_MACHINE, local, device)
	if n != 0:
		_broadcast_lobby()
	return n


## The host's player [param number] leaves (not P1).
func leave_local(number: int) -> bool:
	if lobby.state != MwNetLobby.State.OPEN or lobby.machine_of(number) != MwNetLobby.HOST_MACHINE \
			or not lobby.leave(number):
		return false
	_broadcast_lobby()
	return true


## START GAME: every machine gets START with [param record] (the start
## record, work item 1: in chunks when it outgrows one message - protocol
## version 4, the host's custom teams in it) and the stream begins at tick
## 0. The match ID (a random 32-bit number), or 0 when the lobby isn't open
## or the record is over [constant MwNetProtocol.MAX_RECORD].
func start_match(record := PackedByteArray()) -> int:
	if lobby.state != MwNetLobby.State.OPEN or record.size() > MwNetProtocol.MAX_RECORD:
		return 0
	var id_bytes := MwNetProtocol.random_bytes(4)
	lobby.match_id = maxi(1, (id_bytes[0] << 24) | (id_bytes[1] << 16) | (id_bytes[2] << 8) | id_bytes[3])
	lobby.set_state(MwNetLobby.State.RUNNING)
	merge.reset()
	merge.set_players(lobby.numbers())
	stream.start(0)
	tick = -1
	_hashes.clear()
	var msgs := MwNetProtocol.start_messages(lobby.match_id, 0, record)
	for peer: Peer in _peers.values():
		if peer.stage == Stage.IN:
			peer.floor_no = 0
			peer.ack = MwNetProtocol.NONE
			peer.fed = -1
			peer.stamps.clear()
			peer.pace = MwNetPace.new()
			for msg in msgs:
				transport.send(peer.id, MwNetProtocol.CH_RELIABLE, msg)
	if msgs.size() > 1:
		_log("START: the record in %d chunks (%d bytes)" % [msgs.size(), record.size()])
	_broadcast_lobby()
	return lobby.match_id


## One host tick of the match: [param local_states] (player number ->
## MwNetInput state) are the host's own players' latest; returns the merged
## tick, which has been sent to every machine (empty outside a match) - to
## a machine whose line is full every second tick (its [MwNetPace]; the
## machines take turns, by number), its hashes every [constant HASH_EVERY].
## Each machine's share goes out at once (MwNetTransport.flush), the
## machines in turns: on a full line the router drops whatever comes last
## to its full queue, and in a fixed order that would be one machine's
## datagrams nearly every time (its stream starved, its connection lost).
func step(local_states := {}) -> PackedByteArray:
	if lobby.state != MwNetLobby.State.RUNNING:
		return PackedByteArray()
	for n in local_states:
		if lobby.machine_of(int(n)) == MwNetLobby.HOST_MACHINE:
			merge.feed(int(n), local_states[n])
	var t := merge.tick(stream.newest + 1)
	tick = stream.push(t)
	var hashes_msg := PackedByteArray()
	if not _hashes.is_empty() and int(_hashes[-1]["tick"]) > tick - 2 * MwNetProtocol.MAX_TICKS:
		hashes_msg = MwNetProtocol.hashes(lobby.match_id, _hashes)
	var peers := _peers.values()
	for i in peers.size():
		var peer: Peer = peers[(i + tick) % peers.size()]
		if peer.stage != Stage.IN:
			continue
		if (tick + peer.machine) % peer.pace.stride != 0:
			continue
		var pkt := stream.encode(peer.ack, peer.floor_no)
		if not pkt.is_empty():
			var input_ack := peer.inputs.newest if peer.inputs.newest >= 0 else MwNetProtocol.NONE
			if transport.send(peer.id, MwNetProtocol.CH_INPUT, MwNetProtocol.stream(lobby.match_id, input_ack,
					pkt["base"], pkt["first"], pkt["count"], pkt["body"])):
				peer.pace.sent(int(pkt["first"]) + int(pkt["count"]) - 1, _now)
		if not hashes_msg.is_empty() and (tick + peer.machine) % HASH_EVERY == 0:
			transport.send(peer.id, MwNetProtocol.CH_INPUT, hashes_msg)
		transport.flush()
	return t


## A state hash for the clients to compare (section 3): [param kind] 0 a
## rink pass, 1 the session at a screen change; [param value] 8 bytes.
func add_hash(at_tick: int, kind: int, value: PackedByteArray) -> void:
	var v := value.slice(0, MwNetProtocol.HASH_BYTES)
	v.resize(MwNetProtocol.HASH_BYTES)
	_hashes.append({"tick": at_tick, "kind": clampi(kind, 0, 3), "value": v})
	while _hashes.size() > MwNetProtocol.MAX_HASHES:
		_hashes.pop_front()


## Work item 6: resync snapshot [param data] (MwNetSnapshot's bytes) of the
## game at stream tick [param at_tick] for machine [param machine], in
## chunks on the reliable channel (SNAPSHOT); its stream starts again at
## that tick (nothing before it sent or used as a base, nothing acknowledged
## yet - the stream's next packets carry the tick, coded from blank). The
## snapshot's id (1-65535, counting up), or 0 when the machine isn't
## connected, no match runs or the snapshot is over the cap.
func send_snapshot(machine: int, at_tick: int, data: PackedByteArray) -> int:
	if lobby.state != MwNetLobby.State.RUNNING or data.is_empty() or data.size() > MwNetProtocol.MAX_SNAPSHOT \
			or at_tick < 0 or at_tick > tick:
		return 0
	var peer := _peer_of(machine)
	if peer == null:
		return 0
	_snapshot_id = _snapshot_id % 0xFFFF + 1
	var chunks := MwNetChunks.split(data)
	for i in chunks.size():
		transport.send(peer.id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.snapshot(lobby.match_id, _snapshot_id,
				at_tick, data.size(), i, chunks.size(), chunks[i]))
	peer.floor_no = at_tick
	peer.ack = MwNetProtocol.NONE
	peer.pace.forget()
	_log("snapshot %d for machine %d at tick %d: %d bytes" % [_snapshot_id, machine, at_tick, data.size()])
	return _snapshot_id


## The connection machine [param machine] is in on (null: none).
func _peer_of(machine: int) -> Peer:
	for peer: Peer in _peers.values():
		if peer.stage == Stage.IN and peer.machine == machine:
			return peer
	return null


## Back to the lobby after a match: machines still away are removed and
## their keys die (section 5).
func end_match() -> void:
	if lobby.state != MwNetLobby.State.RUNNING:
		return
	lobby.set_state(MwNetLobby.State.OPEN)
	tick = -1
	for id in lobby.machines.keys():
		if not bool(lobby.machines[id]["connected"]):
			lobby.remove_machine(id)
			_keys.erase(id)
	_broadcast_lobby()


## KICK (section 3): machine [param machine] is told and dropped, its key
## erased and its address blocked while the server runs; its players leave
## the lobby (in a match the CPU takes them, work item 4).
func kick(machine: int) -> void:
	if machine == MwNetLobby.HOST_MACHINE or not lobby.machines.has(machine):
		return
	_blocked[block_key(str(lobby.machines[machine]["address"]))] = true
	_keys.erase(machine)
	for peer: Peer in _peers.values():
		if peer.machine == machine:
			transport.send(peer.id, MwNetProtocol.CH_RELIABLE, MwNetProtocol.close(MwNetProtocol.Close.KICKED))
			transport.disconnect_peer(peer.id)
			_peers.erase(peer.id)
	_log("machine %d kicked" % machine)
	lobby.remove_machine(machine)
	_broadcast_lobby()


## CLOSE LOBBY (or the host leaving): every machine told, every connection
## ended, every key gone.
func close() -> void:
	var msg := MwNetProtocol.close(MwNetProtocol.Close.CLOSED)
	for peer: Peer in _peers.values():
		if peer.stage == Stage.IN:
			transport.send(peer.id, MwNetProtocol.CH_RELIABLE, msg)
	transport.close()
	_peers.clear()
	_keys.clear()
	tick = -1
	lobby.set_state(MwNetLobby.State.CLOSED)
	closed.emit()


## What a block covers: an IPv4 address itself, an IPv6 address its /64
## (which one machine can change within, section 3).
static func block_key(address: String) -> String:
	var a := address.strip_edges().to_lower()
	if not ":" in a:
		return a
	var halves := a.split("::")
	var head := halves[0].split(":", false) if halves[0] != "" else PackedStringArray()
	var tail := PackedStringArray()
	if halves.size() > 1 and halves[1] != "":
		tail = halves[1].split(":", false)
	var groups := PackedStringArray(head)
	for i in maxi(0, 8 - head.size() - tail.size()):
		groups.append("0")
	groups.append_array(tail)
	var out := PackedStringArray()
	for i in mini(4, groups.size()):
		out.append(str(groups[i].hex_to_int()))
	return "v6:" + ":".join(out)


## The peers' count and stages, for tests: {pending, in}.
func peer_counts() -> Dictionary:
	var c := {"pending": 0, "in": 0}
	for peer: Peer in _peers.values():
		c["in" if peer.stage == Stage.IN else "pending"] += 1
	return c


## Machine [param machine]'s pace (tests, the soak; null: not connected).
func pace_of(machine: int) -> MwNetPace:
	var peer := _peer_of(machine)
	return peer.pace if peer != null else null


## Machine [param machine]'s stream acknowledgement (tests, the soak).
func machine_ack(machine: int) -> int:
	for peer: Peer in _peers.values():
		if peer.machine == machine:
			return peer.ack
	return MwNetProtocol.NONE


static func _seconds(ms: int) -> int:
	return maxi(1, ceili(ms / 1000.0))


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 200:
		log_lines.remove_at(0)
