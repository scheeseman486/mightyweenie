class_name MwNetClient
extends RefCounted
## A joining machine's side of an online game (plan 35 sections 1-3, 5, 6):
## connecting with the certificate check, the handshake, the lobby's copy,
## the stream's receiving end and the machine's own inputs - node-free,
## polled ([method poll] with the time), over transports made by
## [member connector] (ENet with DTLS for real, the loopback in tests).
##
## Connecting ([method connect_to]):
## [codeblock]
##   known certificate for this address? -- no --> FETCHING: unpinned, take CERT,
##        | yes                                       compare with known hosts
##        v                                           (CHANGED, password or not: TRUST,
##   CONNECTING: pinned to it (DTLS fails             ask - trust_new_key / cancel)
##        | unless the host holds that key;            |
##        | a failure fetches it again: changed?) <----+
##        v
##   HANDSHAKE: HELLO -> CHALLENGE -> AUTH -> WELCOME (check the host's proof)
##        v                                     or REFUSE (refusal, refusal_wait)
##   LOBBY <-> RUNNING (START; the lobby's state)  ... DONE (fail says why)
## [/codeblock]
## The proofs bind the fingerprint of the certificate the session is pinned
## to (MwNetTransport.pinned_fingerprint), so with a password a man in the
## middle - who can only pin us to his own certificate - fails them. The
## pinned certificate is remembered on first use ([MwNetKnownHosts]) and a
## change is asked about (section 6) - plan 45 (the audit's M3): with a
## password too, since our proof (AUTH) would go to whoever holds the new
## certificate, and it lets him guess the password offline.
##
## Keys (section 5): the rejoin key comes with WELCOME, is kept in memory
## and in [MwNetRejoin] while a match may need it, and goes with the
## connection's end unless the connection was lost (LOST keeps it: JOIN
## GAME to the same address offers REJOIN). A key the host turns away (A
## MATCH IS RUNNING: the match it was for is over) goes too. Plan 45
## (protocol version 6): HELLO carries only a proof of it
## (MwNetProtocol.rejoin_proof, bound to our nonce and the pinned
## certificate) - the key itself never goes back to anyone.
##
## Resync (section 5, work item 6): a WELCOME into a running match is a
## rejoin ([signal rejoined]: the game waits for a snapshot); SNAPSHOT
## chunks are put together ([MwNetChunks]) - the stream starts again at the
## snapshot's tick when its first chunk comes - and once whole and the
## stream holds its tick, [method snapshot_ready] ([method take_snapshot]);
## [method request_resync] (RESYNC) and [method report_synced] (SYNCED)
## tell the host.

## The session moved on to [param state] (a [enum State]).
signal state_changed(state: int)
## A known host showed another certificate than last time, with a password
## or without (plan 45); the page asks: [method trust_new_key] or [method
## cancel].
signal key_changed(old_fingerprint: PackedByteArray, new_fingerprint: PackedByteArray)
## START came and its record is whole: match [param match_id], its stream from
## [param first_tick], [param record] the start record as sent.
signal started(match_id: int, first_tick: int, record: PackedByteArray)
## The session ended (DONE): [param reason] says why, a [enum Fail].
signal failed(reason: int)
## Work item 6: WELCOME into a running match - a rejoin; its stream from
## [param first_tick], its game from a snapshot to come.
signal rejoined(match_id: int, first_tick: int)
## Work item 6: snapshot [param id] for stream tick [param at_tick] is whole.
signal snapshot_received(id: int, at_tick: int)

enum State { IDLE, CONNECTING, FETCHING, TRUST, HANDSHAKE, LOBBY, RUNNING, DONE }
## Why a session ended.
enum Fail { NONE, NO_ANSWER, REFUSED, HOST_PROOF, PROTOCOL, LOST, CLOSED, KICKED, EXITED, CANCELLED }
const FAIL_TEXT := {
	Fail.NO_ANSWER: "NO ANSWER FROM THE HOST",
	Fail.HOST_PROOF: "THE HOST FAILED THE PASSWORD CHECK",
	Fail.PROTOCOL: "THE HOST SENT SOMETHING WRONG",
	Fail.LOST: "CONNECTION LOST",
	Fail.CLOSED: "THE HOST CLOSED THE LOBBY",
	Fail.KICKED: "THE HOST KICKED YOU",
}

## Connecting must be done within this.
const CONNECT_MS := 15000
const PING_EVERY_MS := 500

## Makes a transport: func(address: String, port: int, pinned_der:
## PackedByteArray) -> MwNetTransport. Default: MwNetEnet.client.
var connector: Callable = func(a: String, p: int, der: PackedByteArray) -> MwNetTransport:
	return MwNetEnet.client(a, p, der)
var transport: MwNetTransport
var state := State.IDLE
var fail := Fail.NONE
## A REFUSE's code (MwNetProtocol.Refusal) and wait in seconds.
var refusal := 0
var refusal_wait := 0
var address := ""
var port := MwNetProtocol.PORT
## {build, rom, schema} (default: this build's, MwNetHost.local_info).
var info := {}
var lobby := MwNetLobby.new()
var machine := -1
## This machine's player numbers.
var numbers: Array[int] = []
var match_id := 0
## The host's stream as it arrives (confirmed ticks run the game).
var stream := MwNetTickReceiver.new()
## This machine's players' input states as sent.
var inputs := MwNetTickLog.new()
## The host's state hashes: (tick * 4 + kind) -> 8 bytes - those of the
## ticks the stream may hold (plan 45, L4), at most [constant HASHES_KEPT].
var host_hashes := {}
## Plan 45 (L4): the most hashes [member host_hashes] keeps: past it the
## old ones go (more than [constant MwNetTickReceiver.RING] ticks behind the
## stream's newest), and if that isn't enough, all of them.
const HASHES_KEPT := 4 * MwNetTickReceiver.RING
var rtt_ms := 0
var jitter_ms := 0
## The host's tick as of the last pong (-1: none).
var host_tick := -1
## Work item 6: the resync snapshot being put together (or the last one).
var snapshot := MwNetChunks.new()
## Plan 38 (protocol version 4): the start record being put together from
## its START chunks ([signal started] once whole).
var record_parts := MwNetChunks.new()
var log_lines := PackedStringArray()
var _key := PackedByteArray()
var _rejoin := PackedByteArray()
var _der := PackedByteArray()
var _fetched := PackedByteArray()
var _locals := 1
var _nonce := PackedByteArray()
var _host_nonce := PackedByteArray()
var _now := 0
var _since := -1
var _input_ack := MwNetProtocol.NONE
## Plan 43: the host tick each input state sent is meant for (sequence ->
## stamp; the last [constant STAMPS_KEPT]), and how early the host held this
## machine's input: each STREAM's (the stamp of the newest input it had
## decoded) - (the newest tick it carries), in ticks, oldest first (the last
## [constant SLACKS_KEPT]) - MwNetMatch's lead control takes them.
const STAMPS_KEPT := 256
const SLACKS_KEPT := 120
var stamps := {}
var slacks := PackedInt32Array()
var slack_count := 0                  # slacks reported in all (a new one: the count moved)
var _ping_seq := 0
var _last_ping := -1000000
var _refetched := false


## Starts joining [param host_address] (an IP address; an IPv6 one with or
## without brackets) on [param host_port] with [param password] and [param
## locals] local players; a rejoin key kept for this address ([MwNetRejoin])
## goes along as its proof (plan 45: never the key itself).
func connect_to(host_address: String, host_port := MwNetProtocol.PORT, password := "", locals := 1) -> void:
	if info.is_empty():
		info = MwNetHost.local_info()
	address = host_address.strip_edges().trim_prefix("[").trim_suffix("]")
	port = host_port
	_key = MwNetProtocol.derive_key(password)
	_locals = clampi(locals, 1, MwNetInput.PLAYERS)
	_rejoin = MwNetRejoin.key_for(address, port)
	_der = MwNetKnownHosts.lookup(address, port)
	_refetched = false
	_since = -1
	fail = Fail.NONE
	refusal = 0
	if _der.is_empty():
		_open(PackedByteArray(), State.FETCHING)
	else:
		_open(_der, State.CONNECTING)


## The certificate (DER) of the host this session is pinned to.
func host_certificate() -> PackedByteArray:
	return _der


## The rejoin key in memory (never log it; tests and the rejoin flow).
func rejoin_key() -> PackedByteArray:
	return _rejoin


## Goes on with a host whose certificate changed (state TRUST).
func trust_new_key() -> void:
	if state == State.TRUST:
		_der = _fetched
		_since = -1
		_open(_der, State.CONNECTING)


## Gives up (any state).
func cancel() -> void:
	if state != State.DONE:
		_finish(Fail.CANCELLED)


## EXIT LOBBY: tells the host, ends the connection; the key goes.
func exit_lobby() -> void:
	if state == State.LOBBY or state == State.RUNNING:
		transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_RELIABLE, MwNetProtocol.bye())
		MwNetRejoin.clear()
		_finish(Fail.EXITED)


## A local device joins as this machine's local player [param local].
func join_local(local: int, device := 0) -> void:
	if state == State.LOBBY:
		transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_RELIABLE, MwNetProtocol.join_local(local, device))


## This machine's player [param number] leaves (not its first).
func leave_local(number: int) -> void:
	if state == State.LOBBY and number in numbers:
		transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_RELIABLE, MwNetProtocol.leave_local(number))


## One local tick of the match: [param states] (player number ->
## MwNetInput state) are this machine's players' latest; sent with the
## last ticks repeated. Plan 43: [param stamp], the host tick they are
## meant for (-1: none; never less than the last one's).
func send_input(states: Dictionary, stamp := -1) -> void:
	if state != State.RUNNING:
		return
	var t := MwNetInput.blank_tick()
	for n in numbers:
		if states.has(n):
			t = MwNetInput.with_player(t, n, states[n])
	var seq := inputs.push(t)
	if stamp >= 0:
		stamps[seq] = maxi(stamp, int(stamps.get(seq - 1, 0)))
		if stamps.size() > STAMPS_KEPT:
			for q: int in stamps.keys():
				if q <= seq - STAMPS_KEPT / 2:
					stamps.erase(q)
	var pkt := inputs.encode(_input_ack)
	if pkt.is_empty():
		return
	var first := int(pkt["first"])
	var sent := PackedInt32Array()
	for q in range(first, first + int(pkt["count"])):
		if not stamps.has(q):
			sent = PackedInt32Array()
			break
		sent.append(int(stamps[q]))
	transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_INPUT, MwNetProtocol.input(match_id,
			stream.ack(), pkt["base"], first, pkt["count"], pkt["body"], sent))


## Handles everything that arrived, at time [param now_ms].
func poll(now_ms: int) -> void:
	_now = now_ms
	if _since < 0:
		_since = now_ms
	if transport == null or state == State.IDLE:
		return
	transport.poll()
	if state == State.DONE:
		transport.take_events()    # a closed session's transport finishing its goodbyes
		return
	for ev in transport.take_events():
		if state == State.DONE:
			break
		match int(ev["kind"]):
			MwNetTransport.Kind.DISCONNECTED:
				_on_disconnect(bool(ev["error"]))
			MwNetTransport.Kind.PACKET:
				_on_packet(int(ev["channel"]), ev["data"])
	if state in [State.CONNECTING, State.FETCHING, State.HANDSHAKE] and _now - _since > CONNECT_MS:
		_finish(Fail.NO_ANSWER)
	if state == State.LOBBY or state == State.RUNNING:
		if _now - _last_ping >= PING_EVERY_MS:
			_last_ping = _now
			_ping_seq = (_ping_seq + 1) & 0xFFFF
			transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_PING, MwNetProtocol.ping(_ping_seq,
					_now & 0xFFFFFFFF))
	if state == State.RUNNING:
		var rr := stream.resend_request(_now, rtt_ms)
		if rr.x >= 0:
			transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_RELIABLE,
					MwNetProtocol.resend_request(rr.x, rr.y))


func _open(pinned: PackedByteArray, new_state: int) -> void:
	if transport != null:
		transport.abort()
	transport = connector.call(address, port, pinned)
	_set_state(new_state)


func _set_state(new_state: int) -> void:
	if state != new_state:
		state = new_state
		state_changed.emit(new_state)


## Ends the session; only what the host should still hear (EXIT LOBBY's
## BYE) needs a graceful close.
func _finish(reason: int) -> void:
	fail = reason
	if transport != null:
		if reason == Fail.EXITED:
			transport.close()
		else:
			transport.abort()
	_log("ended: %d" % reason)
	_set_state(State.DONE)
	failed.emit(reason)


func _on_disconnect(error: bool) -> void:
	match state:
		State.CONNECTING:
			# a pinned session that never got going: the host's certificate
			# may have changed (or nobody is there): fetch it to see
			if error and not _refetched:
				_refetched = true
				_open(PackedByteArray(), State.FETCHING)
			else:
				_finish(Fail.NO_ANSWER)
		State.FETCHING, State.HANDSHAKE:
			_finish(Fail.NO_ANSWER)
		State.LOBBY, State.RUNNING:
			_finish(Fail.LOST)


func _on_packet(channel: int, data: PackedByteArray) -> void:
	var m := MwNetProtocol.decode(data, channel)
	if m.is_empty():
		_finish(Fail.PROTOCOL)
		return
	var type := int(m["type"])
	if type == MwNetProtocol.Type.REFUSE and state in [State.CONNECTING, State.FETCHING, State.HANDSHAKE]:
		refusal = int(m["code"])
		refusal_wait = int(m["wait"])
		if refusal == MwNetProtocol.Refusal.RUNNING and not _rejoin.is_empty():
			MwNetRejoin.clear()                     # the match that key was for is over (or it was erased)
			_rejoin = PackedByteArray()
		_finish(Fail.REFUSED)
		return
	if type == MwNetProtocol.Type.PING and state in [State.HANDSHAKE, State.LOBBY, State.RUNNING]:
		transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_PING,
				MwNetProtocol.pong(m["seq"], m["time"], stream.ack()))
		return
	match state:
		State.CONNECTING, State.FETCHING:
			if type == MwNetProtocol.Type.CERT:
				_on_cert(m["der"])
			else:
				_finish(Fail.PROTOCOL)
		State.HANDSHAKE:
			if type == MwNetProtocol.Type.CHALLENGE and _host_nonce.is_empty():
				_host_nonce = m["nonce"]
				var bytes := MwNetProtocol.proof(_key, "client", _nonce, _host_nonce, transport.pinned_fingerprint())
				transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_RELIABLE, MwNetProtocol.auth(bytes))
			elif type == MwNetProtocol.Type.WELCOME and not _host_nonce.is_empty():
				_on_welcome(m)
			elif type in [MwNetProtocol.Type.STREAM, MwNetProtocol.Type.HASHES] and not _host_nonce.is_empty():
				pass    # work item 6: a running match's stream (unreliable) can overtake WELCOME - repeated anyway
			else:
				_finish(Fail.PROTOCOL)
		State.LOBBY, State.RUNNING:
			_on_message(m)


func _on_cert(der: PackedByteArray) -> void:
	var pinned := transport.pinned_fingerprint()
	if not pinned.is_empty():
		if MwNetIdentity.fingerprint_of(der) != pinned:
			_finish(Fail.PROTOCOL)
			return
		_nonce = MwNetProtocol.random_bytes(MwNetProtocol.NONCE_BYTES)
		_host_nonce = PackedByteArray()
		# plan 45 (M3): the rejoin key's proof, never the key (version 6)
		transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_RELIABLE, MwNetProtocol.hello(
				str(info["build"]), info["rom"], int(info["schema"]), _nonce, _locals,
				MwNetProtocol.rejoin_proof(_rejoin, _nonce, pinned)))
		_set_state(State.HANDSHAKE)
		return
	# a first contact (or a pinned session that failed): what certificate now?
	_fetched = der
	var known := MwNetKnownHosts.lookup(address, port)
	# plan 45 (M3): asked with a password too - our proof would go to the new certificate's holder
	if not known.is_empty() and known != der:
		_log("the host's certificate changed")
		transport.abort()
		_set_state(State.TRUST)
		key_changed.emit(MwNetIdentity.fingerprint_of(known), MwNetIdentity.fingerprint_of(der))
		return
	_der = der
	_open(der, State.CONNECTING)


func _on_welcome(m: Dictionary) -> void:
	var expect := MwNetProtocol.proof(_key, "host", _host_nonce, _nonce, transport.pinned_fingerprint())
	if not MwNetProtocol.same_secret(expect, m["proof"]):
		_finish(Fail.HOST_PROOF)
		return
	machine = int(m["machine"])
	numbers.assign(m["numbers"])
	_rejoin = m["key"]
	match_id = int(m["match"])
	MwNetKnownHosts.remember(address, port, _der)
	lobby.load_wire(m["lobby"])
	inputs.start(0)
	stamps.clear()
	slacks = PackedInt32Array()
	_input_ack = MwNetProtocol.NONE
	stream.allowed = _players_mask()
	MwNetRejoin.save(address, port, match_id, _rejoin)
	snapshot.reset()
	record_parts.reset()
	if lobby.state == MwNetLobby.State.RUNNING:
		stream.start(int(m["tick"]) + 1 if int(m["tick"]) != MwNetProtocol.NONE else 0)
		_set_state(State.RUNNING)
		rejoined.emit(match_id, stream.floor_no)     # work item 6: the game comes with a snapshot
	else:
		_set_state(State.LOBBY)


func _on_message(m: Dictionary) -> void:
	match int(m["type"]):
		MwNetProtocol.Type.LOBBY:
			var was_running := lobby.state == MwNetLobby.State.RUNNING
			lobby.load_wire(m["lobby"])
			numbers = lobby.numbers_of(machine)
			stream.allowed = _players_mask() if lobby.state != MwNetLobby.State.RUNNING else stream.allowed
			if was_running and lobby.state == MwNetLobby.State.OPEN:
				MwNetRejoin.clear()
				_set_state(State.LOBBY)
		MwNetProtocol.Type.START:
			# version 4: the record in chunks - the match begins with its first
			# (the stream taken from then on), the game once the record is whole
			if int(m["match"]) != match_id or state != State.RUNNING or record_parts.tick != int(m["tick"]):
				match_id = int(m["match"])
				record_parts.reset()
				stream.start(int(m["tick"]))
				stream.allowed = _players_mask()
				host_hashes.clear()
				snapshot.reset()
				_input_ack = MwNetProtocol.NONE
				_set_state(State.RUNNING)
			m["id"] = 0
			var r := record_parts.take(m)
			if r == MwNetChunks.Result.BAD:
				_finish(Fail.PROTOCOL)
				return
			if r == MwNetChunks.Result.DONE:
				MwNetRejoin.save(address, port, match_id, _rejoin)
				if record_parts.count > 1:
					_log("START: the record in %d chunks (%d bytes)" % [record_parts.count, record_parts.size])
				started.emit(match_id, int(m["tick"]), record_parts.use())
		MwNetProtocol.Type.CLOSE:
			var reason := int(m["reason"])
			if reason != MwNetProtocol.Close.DROPPED:
				MwNetRejoin.clear()
			_finish(Fail.KICKED if reason == MwNetProtocol.Close.KICKED
					else Fail.CLOSED if reason == MwNetProtocol.Close.CLOSED else Fail.PROTOCOL)
		MwNetProtocol.Type.STREAM, MwNetProtocol.Type.RESEND:
			if state != State.RUNNING or int(m["match"]) != match_id:
				return
			if m["type"] == MwNetProtocol.Type.STREAM:
				var ack := int(m["ack"])
				if ack != MwNetProtocol.NONE and ack > inputs.newest:
					_finish(Fail.PROTOCOL)
					return
				if ack != MwNetProtocol.NONE and (_input_ack == MwNetProtocol.NONE or ack > _input_ack):
					_input_ack = ack
				if ack != MwNetProtocol.NONE and stamps.has(ack):
					# plan 43: how early the host held our newest input when it made this tick
					slacks.append(int(stamps[ack]) - (int(m["first"]) + int(m["count"]) - 1))
					slack_count += 1
					if slacks.size() > SLACKS_KEPT:
						slacks = slacks.slice(slacks.size() - SLACKS_KEPT)
			if stream.receive(m["base"], m["first"], m["count"], m["body"]) == MwNetTickReceiver.Result.BAD:
				_finish(Fail.PROTOCOL)
		MwNetProtocol.Type.HASHES:
			if state != State.RUNNING or int(m["match"]) != match_id:
				return
			for entry: Dictionary in m["entries"]:
				# plan 45 (L4): only ticks the stream may hold - a host can't make this grow for ever
				var t := int(entry["tick"])
				if t >= stream.floor_no and t <= stream.confirmed + MwNetTickReceiver.WINDOW:
					host_hashes[t * 4 + int(entry["kind"])] = entry["value"]
			if host_hashes.size() > HASHES_KEPT:
				for k in host_hashes.keys():
					if (int(k) >> 2) < stream.newest - MwNetTickReceiver.RING:
						host_hashes.erase(k)
				if host_hashes.size() > HASHES_KEPT:
					host_hashes.clear()     # (only hashes planted far ahead are left: let them go, unchecked)
		MwNetProtocol.Type.SNAPSHOT:
			if state != State.RUNNING or int(m["match"]) != match_id:
				return
			var r := snapshot.take(m)
			if r == MwNetChunks.Result.BAD:
				_finish(Fail.PROTOCOL)
				return
			if snapshot.began:
				stream.skip_to(snapshot.tick)           # the host's stream starts again there
				_log("snapshot %d for tick %d coming (%d bytes)" % [snapshot.id, snapshot.tick, snapshot.size])
			if r == MwNetChunks.Result.DONE:
				snapshot_received.emit(snapshot.id, snapshot.tick)
		MwNetProtocol.Type.PONG:
			var sample := (_now - int(m["time"])) & 0xFFFFFFFF
			if sample < 60000:
				if rtt_ms == 0:
					rtt_ms = sample
				else:
					jitter_ms += (absi(sample - rtt_ms) - jitter_ms) / 4
					rtt_ms += (sample - rtt_ms) / 8
				host_tick = -1 if int(m["tick"]) == MwNetProtocol.NONE else int(m["tick"])
		_:
			_finish(Fail.PROTOCOL)


## Tells the host our game disagreed with its hash at [param at_tick] of
## [param kind] ([param value]: ours) - work item 4; the host logs it with
## its own state.
func report_desync(at_tick: int, kind: int, value: PackedByteArray) -> void:
	if state == State.RUNNING:
		transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_RELIABLE,
				MwNetProtocol.desync(match_id, at_tick, kind, value))


## Work item 6: a resync snapshot whole and its tick in the stream (the
## game can be taken up from it now).
func snapshot_ready() -> bool:
	return snapshot.complete and not snapshot.used and stream.confirmed >= snapshot.tick


## Work item 6: true while a snapshot is on its way or whole but not taken.
func snapshot_pending() -> bool:
	return snapshot.id >= 0 and not snapshot.used


## Work item 6: the whole snapshot - {id, tick, data} - taken (it isn't
## ready again until another comes); {} when none is ready.
func take_snapshot() -> Dictionary:
	if not snapshot_ready():
		return {}
	return {"id": snapshot.id, "tick": snapshot.tick, "data": snapshot.use()}


## Work item 6: asks the host for a resync snapshot at its next safe point
## ([enum MwNetProtocol.Resync]: the stream lost, the last snapshot failed).
func request_resync(reason: int) -> void:
	if state == State.RUNNING:
		_log("resync asked (%d)" % reason)
		transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_RELIABLE, MwNetProtocol.resync(match_id, reason))


## Plan 38: the start record START brought can't be read
## (MwNetMatch.start_client: garbage, custom teams that aren't teams) - the
## host is dropped as for any garbage it sends (Fail.PROTOCOL), and the
## match's rejoin key let go.
func reject_record() -> void:
	reject_host("the start record can't be read")


## Plan 45 (M2): the host sent something this machine's game won't take
## ([param why], logged) - a record or snapshot it can't read, a screen no
## online match shows (MwNetMatch.ONLINE_SCREENS): the host is dropped as
## for any garbage it sends (Fail.PROTOCOL), and the match's rejoin key let
## go.
func reject_host(why: String) -> void:
	if state in [State.LOBBY, State.RUNNING]:
		_log(why)
		MwNetRejoin.clear()
		_rejoin = PackedByteArray()
		_finish(Fail.PROTOCOL)


## Work item 6: tells the host our game is taken up from snapshot [param id].
func report_synced(id: int) -> void:
	if state == State.RUNNING:
		transport.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_RELIABLE, MwNetProtocol.synced(match_id, id))


## The host's hash for [param at_tick] and [param kind] (empty: none came).
func host_hash(at_tick: int, kind: int) -> PackedByteArray:
	return host_hashes.get(at_tick * 4 + kind, PackedByteArray())


func _players_mask() -> int:
	var mask := 0
	for n in lobby.numbers():
		mask |= 1 << (n - 1)
	return mask


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 200:
		log_lines.remove_at(0)
