class_name MwNetProtocol
extends RefCounted
## The online game's messages (plan 35 section 1): versioned binary
## messages, their encoders and one checking decoder, the size caps, the
## channels, and the handshake's password proofs. Node-free: the host and
## client sessions ([MwNetHost], [MwNetClient]) send these through a
## transport ([MwNetTransport]: ENet with DTLS, or the loopback in tests).
##
## Every message starts with two bytes, its type and [constant VERSION];
## fields are big-endian ([MwNetBytes]). [method decode] checks everything -
## the size cap, the version, the type, the channel it came on, every
## length, count and range, and that nothing is left over - and gives {} for
## anything wrong: the sessions drop a peer that sends garbage (section 6).
## A message is at most [constant MAX_MESSAGE] bytes, so with ENet's and
## DTLS's headers a datagram stays under 1200 bytes.
##
## Two layouts are frozen across versions so machines of different versions
## can still tell each other so: HELLO's type byte and REFUSE whole (a host
## answers a HELLO of another version with REFUSE VERSION, and a client
## decodes REFUSE whatever its version byte).
##
## The password (section 1): never sent. Both sides derive a key from it
## ([method derive_key]: a deliberately slow chain of HMAC-SHA256, so a
## recorded proof only allows slow offline guessing), then each proves it
## knows the key with an HMAC over both nonces and the host certificate's
## fingerprint as that side sees it ([method proof]): the host its own
## certificate's, the client the one its DTLS session is pinned to. A man in
## the middle shows the client his own certificate, so the two fingerprints
## differ and neither proof checks out. docs/net.md has the whole exchange.
##
## Version 2 (work item 6): resync snapshots - SNAPSHOT (a blob too big for
## one message, in numbered chunks on the reliable channel: [MwNetChunks]),
## RESYNC (a client asking for one) and SYNCED (a client's game taken up
## from one).
##
## Version 3 (the shot heights, MwSettings.shot_heights): a player's state
## in INPUT, STREAM and RESEND grows to 64 bytes - the HIGH / LOW SHOT verbs
## and the shot height's code (MwNetInput.HEIGHT, a delta flag of its own);
## the messages' layouts are otherwise version 2's.
##
## Version 4 (plan 38's custom teams online): START carries the start record
## in chunks like SNAPSHOT's ([MwNetChunks]) - its size, the chunk's index
## and the count, then the chunk - since the host's custom teams travel in
## the record (about 1-2 KB each); a record that fits one message is one
## START as before.
##
## Version 5 (plan 43, input stamps): INPUT carries after its count the host
## tick each of its states is meant for - the first's (u32, [constant NONE]
## none), then each next one's step from the one before (u8: a client's
## stamps never go back) - the host merging each at its own (MwNetMerge
## stamped), so the client knows the tick its input lands at.
##
## Version 6 (plan 45, the audit's M3): HELLO's key field carries a proof of
## the rejoin key ([method rejoin_proof]: bound to the client's nonce and
## the fingerprint of the certificate its session is pinned to), never the
## key itself - so a man in the middle learns nothing it could rejoin with;
## the password's key takes [constant KDF_ROUNDS] rounds (version 5:
## 20 000). The layouts are version 5's.
## Short names: w the byte writer (MwNetBytes.Writer).

const VERSION := 6
## The default port (owner).
const PORT := 42032
## The largest message, header included.
const MAX_MESSAGE := 1024
const CHANNELS := 3
## Channel 0: reliable and ordered (control, lobby, start, resends).
const CH_RELIABLE := 0
## Channel 1: unreliable (inputs, the stream, hashes).
const CH_INPUT := 1
## Channel 2: unreliable (pings).
const CH_PING := 2
## "No tick / no sequence number" in 32-bit fields.
const NONE := 0xFFFFFFFF
const NONCE_BYTES := 16
const PROOF_BYTES := 32
const KEY_BYTES := 32
const SHA1_BYTES := 20
const HASH_BYTES := 8
const MAX_BUILD := 64
const MAX_ADDRESS := 64
const MIN_CERT := 64
const MAX_CERT := 1000
## The start record (START, version 4): at most this many bytes in all
## (MwNetMatch.encode_record's: deflated, the host's custom teams in it), in
## chunks of [constant RECORD_CHUNK] (the last one the rest; an empty record
## is one empty chunk).
const MAX_RECORD := 1 << 19
const RECORD_CHUNK := 960
## Ticks in one stream or input packet (the last 8 repeated).
const MAX_TICKS := 8
## Ticks one resend may ask for.
const MAX_RESEND := 64
const MAX_MACHINE := 15
const MAX_HASHES := 8
## A snapshot's chunk (the last one shorter), and the largest snapshot
## (work item 6: MwNetSnapshot's bytes - about 40 KB in a match).
const SNAPSHOT_CHUNK := 960
const MAX_SNAPSHOT := 1 << 20
## The password key's derivation rounds ([method derive_key]). Plan 45
## (version 6): 50 000 - each offline guess of a recorded proof 2.5 times
## version 5's cost (20 000). Once per join (MwNetClient.connect_to) and
## once when the server starts: 56-83 ms on the sandbox VM (about 1.3 us a
## round), a whole join's main-thread time over DTLS on 127.0.0.1 69-98 ms.
const KDF_ROUNDS := 50000

enum Type { CERT = 1, HELLO, CHALLENGE, AUTH, WELCOME, REFUSE, LOBBY, JOIN_LOCAL, LEAVE_LOCAL,
		START, CLOSE, BYE, INPUT, STREAM, RESEND_REQUEST, RESEND, HASHES, PING, PONG, DESYNC,
		SNAPSHOT, RESYNC, SYNCED }
const LAST_TYPE := Type.SYNCED
## The channel each type travels on (anything else is garbage).
const CHANNEL_OF := {
	Type.CERT: CH_RELIABLE, Type.HELLO: CH_RELIABLE, Type.CHALLENGE: CH_RELIABLE,
	Type.AUTH: CH_RELIABLE, Type.WELCOME: CH_RELIABLE, Type.REFUSE: CH_RELIABLE,
	Type.LOBBY: CH_RELIABLE, Type.JOIN_LOCAL: CH_RELIABLE, Type.LEAVE_LOCAL: CH_RELIABLE,
	Type.START: CH_RELIABLE, Type.CLOSE: CH_RELIABLE, Type.BYE: CH_RELIABLE,
	Type.INPUT: CH_INPUT, Type.STREAM: CH_INPUT, Type.RESEND_REQUEST: CH_RELIABLE,
	Type.RESEND: CH_RELIABLE, Type.HASHES: CH_INPUT, Type.PING: CH_PING, Type.PONG: CH_PING,
	Type.DESYNC: CH_RELIABLE, Type.SNAPSHOT: CH_RELIABLE, Type.RESYNC: CH_RELIABLE,
	Type.SYNCED: CH_RELIABLE,
}

## Why a host turns a machine away (REFUSE), each with the page's message.
enum Refusal { VERSION = 1, ROM, WRONG_PASSWORD, WAIT, FULL, RUNNING, BLOCKED, BUSY }
const LAST_REFUSAL := Refusal.BUSY
const REFUSAL_TEXT := {
	Refusal.VERSION: "THE HOST RUNS ANOTHER VERSION",
	Refusal.ROM: "THE HOST HAS ANOTHER ROM",
	Refusal.WRONG_PASSWORD: "WRONG PASSWORD",
	Refusal.WAIT: "TOO MANY TRIES - WAIT %d S",
	Refusal.FULL: "THE LOBBY IS FULL",
	Refusal.RUNNING: "A MATCH IS RUNNING",
	Refusal.BLOCKED: "THE HOST HAS BLOCKED YOU",
	Refusal.BUSY: "THE HOST IS BUSY - TRY AGAIN",
}
## Why a host ends a machine's connection (CLOSE).
enum Close { CLOSED = 1, KICKED, DROPPED }
const LAST_CLOSE := Close.DROPPED

## The lobby's states on the wire.
enum Lobby { OPEN, RUNNING }
## Why a client asks for a resync snapshot (RESYNC; a desync is told with
## DESYNC): its stream has a gap the host can no longer fill (LOST), or
## its game couldn't take up the last snapshot (FAILED).
enum Resync { LOST = 1, FAILED }
const LAST_RESYNC := Resync.FAILED

static var _crypto: Crypto


static func _c() -> Crypto:
	if _crypto == null:
		_crypto = Crypto.new()
	return _crypto


## A message's (type, version) without decoding it (-1, -1 when too short).
static func peek(data: PackedByteArray) -> Vector2i:
	return Vector2i(data[0], data[1]) if data.size() >= 2 else Vector2i(-1, -1)


static func _head(type: int) -> MwNetBytes.Writer:
	var w := MwNetBytes.Writer.new()
	w.u8(type)
	w.u8(VERSION)
	return w


static func _done(w: MwNetBytes.Writer) -> PackedByteArray:
	if w.size() > MAX_MESSAGE:
		push_error("MwNetProtocol: a message of %d bytes is over the cap" % w.size())
		return PackedByteArray()
	return w.data


# --- encoders -------------------------------------------------------------------------------------

## Host -> client on every new connection: the host's certificate (DER).
static func cert(der: PackedByteArray) -> PackedByteArray:
	var w := _head(Type.CERT)
	w.blob16(der)
	return _done(w)


## Client -> host: who is asking. [param rom_sha1] 20 bytes, [param nonce]
## 16, [param key] the proof of a rejoin key (32 bytes, [method
## rejoin_proof] - version 6: never the key itself) or empty.
static func hello(build: String, rom_sha1: PackedByteArray, schema: int, nonce: PackedByteArray,
		locals: int, key: PackedByteArray) -> PackedByteArray:
	var w := _head(Type.HELLO)
	w.text(build.left(MAX_BUILD))
	w.bytes(rom_sha1)
	w.u32(schema)
	w.bytes(nonce)
	w.u8(locals)
	w.blob8(key)
	return _done(w)


## Host -> client: the host's nonce; whether the host has a password.
static func challenge(nonce: PackedByteArray, password: bool) -> PackedByteArray:
	var w := _head(Type.CHALLENGE)
	w.bytes(nonce)
	w.u8(1 if password else 0)
	return _done(w)


## Client -> host: the client's proof ([method proof]).
static func auth(client_proof: PackedByteArray) -> PackedByteArray:
	var w := _head(Type.AUTH)
	w.bytes(client_proof)
	return _done(w)


## Host -> client: in. The host's proof, the machine's id, its rejoin key,
## the match ID, the host's tick (a match running: the stream continues
## after it), the machine's player numbers and the lobby ([method
## write_lobby]'s dictionary).
static func welcome(host_proof: PackedByteArray, machine: int, key: PackedByteArray, match_id: int,
		tick: int, numbers: Array, lobby_info: Dictionary) -> PackedByteArray:
	var w := _head(Type.WELCOME)
	w.bytes(host_proof)
	w.u8(machine)
	w.bytes(key)
	w.u32(match_id)
	w.u32(tick)
	var nb := PackedByteArray()
	for n in numbers:
		nb.append(int(n))
	w.blob8(nb)
	write_lobby(w, lobby_info)
	return _done(w)


## Host -> client: turned away ([enum Refusal]); [param wait_s] seconds
## before trying again makes sense (wrong password, too many tries).
static func refuse(code: int, wait_s := 0) -> PackedByteArray:
	var w := _head(Type.REFUSE)
	w.u8(code)
	w.u16(clampi(wait_s, 0, 0xFFFF))
	return _done(w)


## Host -> clients: the lobby whenever it changes.
static func lobby(d: Dictionary) -> PackedByteArray:
	var w := _head(Type.LOBBY)
	write_lobby(w, d)
	return _done(w)


## Client -> host: a local device joined as the machine's local player
## [param local] (1-12); [param device] is the page's glyph kind.
static func join_local(local: int, device: int) -> PackedByteArray:
	var w := _head(Type.JOIN_LOCAL)
	w.u8(local)
	w.u8(device)
	return _done(w)


## Client -> host: player [param number] (one of the machine's) leaves.
static func leave_local(number: int) -> PackedByteArray:
	var w := _head(Type.LEAVE_LOCAL)
	w.u8(number)
	return _done(w)


## Host -> clients: START GAME - the match ID, the stream's first tick and
## chunk [param index] of [param count] of the start record (work item 1's
## bytes, opaque here; [param size] bytes in all - version 4: [method
## start_messages] cuts it).
static func start(match_id: int, tick: int, size: int, index: int, count: int,
		chunk: PackedByteArray) -> PackedByteArray:
	var w := _head(Type.START)
	w.u32(match_id)
	w.u32(tick)
	w.u32(size)
	w.u16(index)
	w.u16(count)
	w.blob16(chunk)
	return _done(w)


## Every START message of [param record] (empty when it is over [constant
## MAX_RECORD]): one per [constant RECORD_CHUNK] bytes, one for an empty
## record.
static func start_messages(match_id: int, tick: int, record: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if record.size() > MAX_RECORD:
		return out
	var chunks := MwNetChunks.split(record, RECORD_CHUNK)
	if chunks.is_empty():
		chunks.append(PackedByteArray())
	for i in chunks.size():
		out.append(start(match_id, tick, record.size(), i, chunks.size(), chunks[i]))
	return out


## Host -> client: the end of this machine's connection ([enum Close]).
static func close(reason: int) -> PackedByteArray:
	var w := _head(Type.CLOSE)
	w.u8(reason)
	return _done(w)


## Client -> host: EXIT LOBBY (the key dies with it).
static func bye() -> PackedByteArray:
	return _done(_head(Type.BYE))


## Client -> host, every tick of a match: the match ID (an input or an
## acknowledgement from another match is ignored), [param ack] the newest
## stream tick the client holds with every one before it, then [param
## count] input states from sequence number [param first], coded from
## state [param base] ([constant NONE]: from blank) - [MwNetTickLog.encode]'s
## body. Version 5 (plan 43): [param stamps], the host tick each state is
## meant for (count of them, never going back, each at most 255 past the
## one before; empty: none) - the first's, then each next one's step.
static func input(match_id: int, ack: int, base: int, first: int, count: int,
		body: PackedByteArray, stamps := PackedInt32Array()) -> PackedByteArray:
	var w := _head(Type.INPUT)
	w.u32(match_id)
	w.u32(ack)
	w.u32(base)
	w.u32(first)
	w.u8(count)
	var has := stamps.size() == count
	w.u32(stamps[0] if has else NONE)
	for i in range(1, count):
		w.u8(clampi(stamps[i] - stamps[i - 1], 0, 255) if has else 0)
	w.bytes(body)
	return _done(w)


## Host -> client, every tick: the match ID, [param input_ack] the newest
## input sequence the host decoded from this machine, then [param count]
## stream ticks from [param first] coded from tick [param base].
static func stream(match_id: int, input_ack: int, base: int, first: int, count: int,
		body: PackedByteArray) -> PackedByteArray:
	var w := _head(Type.STREAM)
	w.u32(match_id)
	w.u32(input_ack)
	w.u32(base)
	w.u32(first)
	w.u8(count)
	w.bytes(body)
	return _done(w)


## Client -> host: send ticks [param from] to [param to] again.
static func resend_request(from: int, to: int) -> PackedByteArray:
	var w := _head(Type.RESEND_REQUEST)
	w.u32(from)
	w.u32(to)
	return _done(w)


## Host -> client (reliable): stream ticks asked for again.
static func resend(match_id: int, base: int, first: int, count: int, body: PackedByteArray) -> PackedByteArray:
	var w := _head(Type.RESEND)
	w.u32(match_id)
	w.u32(base)
	w.u32(first)
	w.u8(count)
	w.bytes(body)
	return _done(w)


## Host -> clients: the match's latest state hashes ({tick, kind, value
## (8 bytes)}), repeated in several packets like the stream.
static func hashes(match_id: int, entries: Array) -> PackedByteArray:
	var w := _head(Type.HASHES)
	w.u32(match_id)
	w.u8(entries.size())
	for entry: Dictionary in entries:
		w.u32(int(entry["tick"]))
		w.u8(int(entry["kind"]))
		w.bytes(entry["value"])
	return _done(w)


## Either way (on [constant CH_PING]): a ping numbered [param seq] (16 bits), sent
## at the sender's [param time_ms] (32 bits); [method pong] gives both back.
static func ping(seq: int, time_ms: int) -> PackedByteArray:
	var w := _head(Type.PING)
	w.u16(seq)
	w.u32(time_ms)
	return _done(w)


## The answer to a ping: its numbers back and the sender's current tick
## ([constant NONE] outside a match).
static func pong(seq: int, time_ms: int, tick: int) -> PackedByteArray:
	var w := _head(Type.PONG)
	w.u16(seq)
	w.u32(time_ms)
	w.u32(tick)
	return _done(w)


## Client -> host (work item 4): the client's game disagrees with the
## host's hash at [param tick] (stream tick) of [param kind]; [param value]
## the client's own hash (8 bytes). The host logs it with its state.
static func desync(match_id: int, tick: int, kind: int, value: PackedByteArray) -> PackedByteArray:
	var w := _head(Type.DESYNC)
	w.u32(match_id)
	w.u32(tick)
	w.u8(kind)
	var v := value.slice(0, HASH_BYTES)
	v.resize(HASH_BYTES)
	w.bytes(v)
	return _done(w)


## Host -> client (work item 6): chunk [param index] of [param count] of
## resync snapshot [param id] (16 bits, counting up) for stream tick [param
## tick], [param size] bytes in all ([MwNetChunks.split]'s pieces).
static func snapshot(match_id: int, id: int, tick: int, size: int, index: int, count: int,
		chunk: PackedByteArray) -> PackedByteArray:
	var w := _head(Type.SNAPSHOT)
	w.u32(match_id)
	w.u16(id)
	w.u32(tick)
	w.u32(size)
	w.u16(index)
	w.u16(count)
	w.blob16(chunk)
	return _done(w)


## Client -> host (work item 6): a resync snapshot wanted at the next safe
## point ([enum Resync]).
static func resync(match_id: int, reason: int) -> PackedByteArray:
	var w := _head(Type.RESYNC)
	w.u32(match_id)
	w.u8(reason)
	return _done(w)


## Client -> host (work item 6): the game is taken up from snapshot
## [param id] (the host then gives a rejoined machine its players back).
static func synced(match_id: int, id: int) -> PackedByteArray:
	var w := _head(Type.SYNCED)
	w.u32(match_id)
	w.u16(id)
	return _done(w)


## The lobby: {state ([enum Lobby]), match, machines: [{id, host, connected,
## ping, address}], players: [{number, machine, local, device}]}.
static func write_lobby(w: MwNetBytes.Writer, d: Dictionary) -> void:
	w.u8(int(d.get("state", Lobby.OPEN)))
	w.u32(int(d.get("match", 0)))
	var machines: Array = d.get("machines", [])
	w.u8(machines.size())
	for m: Dictionary in machines:
		w.u8(int(m["id"]))
		w.u8((1 if m.get("host", false) else 0) | (2 if m.get("connected", true) else 0))
		w.u16(clampi(int(m.get("ping", 0)), 0, 0xFFFF))
		w.text(str(m.get("address", "")).left(MAX_ADDRESS))
	var players: Array = d.get("players", [])
	w.u8(players.size())
	for player: Dictionary in players:
		w.u8(int(player["number"]))
		w.u8(int(player["machine"]))
		w.u8(int(player["local"]))
		w.u8(int(player.get("device", 0)))


# --- the decoder ----------------------------------------------------------------------------------

## The message in [param data] as a dictionary ("type" and its fields), or
## {} for anything malformed. [param channel] (when >= 0) must be the
## type's ([constant CHANNEL_OF]).
static func decode(data: PackedByteArray, channel := -1) -> Dictionary:
	if data.size() < 2 or data.size() > MAX_MESSAGE:
		return {}
	var type: int = data[0]
	if type < 1 or type > LAST_TYPE:
		return {}
	if data[1] != VERSION and type != Type.REFUSE:
		return {}
	if channel >= 0 and int(CHANNEL_OF[type]) != channel:
		return {}
	var reader := MwNetBytes.Reader.new(data, 2)
	var m := {"type": type}
	match type:
		Type.CERT:
			m["der"] = reader.blob16(MIN_CERT, MAX_CERT)
		Type.HELLO:
			m["build"] = reader.text(MAX_BUILD)
			m["rom"] = reader.bytes(SHA1_BYTES)
			m["schema"] = reader.u32()
			m["nonce"] = reader.bytes(NONCE_BYTES)
			m["locals"] = reader.u8_in(1, MwNetInput.PLAYERS)
			m["key"] = reader.blob8(0, KEY_BYTES)
			if (m["key"] as PackedByteArray).size() not in [0, KEY_BYTES]:
				return {}
		Type.CHALLENGE:
			m["nonce"] = reader.bytes(NONCE_BYTES)
			m["password"] = reader.u8_in(0, 1) == 1
		Type.AUTH:
			m["proof"] = reader.bytes(PROOF_BYTES)
		Type.WELCOME:
			m["proof"] = reader.bytes(PROOF_BYTES)
			m["machine"] = reader.u8_in(0, MAX_MACHINE)
			m["key"] = reader.bytes(KEY_BYTES)
			m["match"] = reader.u32()
			m["tick"] = reader.u32()
			var nb := reader.blob8(1, MwNetInput.PLAYERS)
			var numbers: Array[int] = []
			for n in nb:
				if n < 1 or n > MwNetInput.PLAYERS or n in numbers:
					return {}
				numbers.append(n)
			m["numbers"] = numbers
			m["lobby"] = read_lobby(reader)
		Type.REFUSE:
			m["code"] = reader.u8_in(1, LAST_REFUSAL)
			m["wait"] = reader.u16()
		Type.LOBBY:
			m["lobby"] = read_lobby(reader)
		Type.JOIN_LOCAL:
			m["local"] = reader.u8_in(1, MwNetInput.PLAYERS)
			m["device"] = reader.u8()
		Type.LEAVE_LOCAL:
			m["number"] = reader.u8_in(1, MwNetInput.PLAYERS)
		Type.START:
			m["match"] = reader.u32()
			m["tick"] = reader.u32()
			m["size"] = reader.u32()
			m["index"] = reader.u16()
			m["count"] = reader.u16()
			m["chunk"] = reader.blob16(0, RECORD_CHUNK)
			if not reader.ok or not _start_ok(m):
				return {}
		Type.CLOSE:
			m["reason"] = reader.u8_in(1, LAST_CLOSE)
		Type.BYE:
			pass
		Type.INPUT, Type.STREAM:
			m["match"] = reader.u32()
			m["ack"] = reader.u32()
			m["base"] = reader.u32()
			m["first"] = reader.u32()
			m["count"] = reader.u8_in(1, MAX_TICKS)
			if not _ticks_ok(m):
				return {}
			if type == Type.INPUT:
				# version 5 (plan 43): each state's stamp (none: NONE first)
				var first_stamp := reader.u32()
				var stamps := PackedInt32Array()
				if first_stamp != NONE:
					stamps.append(first_stamp)
				for i in range(1, int(m["count"])):
					var step := reader.u8()
					if first_stamp != NONE:
						stamps.append(stamps[-1] + step)
				m["stamps"] = stamps
			m["body"] = reader.bytes(reader.remaining())
		Type.RESEND_REQUEST:
			m["from"] = reader.u32()
			m["to"] = reader.u32()
			if int(m["to"]) < int(m["from"]) or int(m["to"]) - int(m["from"]) >= MAX_RESEND \
					or int(m["to"]) == NONE:
				return {}
		Type.RESEND:
			m["match"] = reader.u32()
			m["base"] = reader.u32()
			m["first"] = reader.u32()
			m["count"] = reader.u8_in(1, MAX_RESEND)
			if not _ticks_ok(m):
				return {}
			m["body"] = reader.bytes(reader.remaining())
		Type.HASHES:
			m["match"] = reader.u32()
			var n := reader.u8_in(1, MAX_HASHES)
			var entries := []
			for _i in n:
				entries.append({"tick": reader.u32(), "kind": reader.u8_in(0, 3), "value": reader.bytes(HASH_BYTES)})
			m["entries"] = entries
		Type.PING:
			m["seq"] = reader.u16()
			m["time"] = reader.u32()
		Type.PONG:
			m["seq"] = reader.u16()
			m["time"] = reader.u32()
			m["tick"] = reader.u32()
		Type.DESYNC:
			m["match"] = reader.u32()
			m["tick"] = reader.u32()
			m["kind"] = reader.u8_in(0, 3)
			m["value"] = reader.bytes(HASH_BYTES)
		Type.SNAPSHOT:
			m["match"] = reader.u32()
			m["id"] = reader.u16()
			m["tick"] = reader.u32()
			m["size"] = reader.u32()
			m["index"] = reader.u16()
			m["count"] = reader.u16()
			m["chunk"] = reader.blob16(1, SNAPSHOT_CHUNK)
			if not reader.ok or not _chunk_ok(m):
				return {}
		Type.RESYNC:
			m["match"] = reader.u32()
			m["reason"] = reader.u8_in(1, LAST_RESYNC)
		Type.SYNCED:
			m["match"] = reader.u32()
			m["id"] = reader.u16()
	if not reader.done():
		return {}
	if type == Type.WELCOME or type == Type.LOBBY:
		if (m["lobby"] as Dictionary).is_empty():
			return {}
	return m


## A tick run's numbers make sense: the base before the first tick, no tick
## past [constant NONE], and at least two bytes a tick in the body.
static func _ticks_ok(m: Dictionary) -> bool:
	var base := int(m["base"])
	var first := int(m["first"])
	var last := first + int(m["count"]) - 1
	if first == NONE or last >= NONE:
		return false
	return base == NONE or base < first


## A snapshot chunk's numbers agree: a size within the cap, the count the
## size makes, an index within it, the chunk as long as its place says (the
## last one the rest), a tick.
static func _chunk_ok(m: Dictionary) -> bool:
	var size := int(m["size"])
	var count := int(m["count"])
	var index := int(m["index"])
	if size < 1 or size > MAX_SNAPSHOT or int(m["tick"]) == NONE:
		return false
	if count != ceili(size / float(SNAPSHOT_CHUNK)) or index >= count:
		return false
	var want := SNAPSHOT_CHUNK if index < count - 1 else size - SNAPSHOT_CHUNK * (count - 1)
	return (m["chunk"] as PackedByteArray).size() == want


## A START chunk's numbers agree (version 4): a size within the cap, the
## count the size makes (one for an empty record), an index within it, the
## chunk as long as its place says, a first tick.
static func _start_ok(m: Dictionary) -> bool:
	var size := int(m["size"])
	var count := int(m["count"])
	var index := int(m["index"])
	if size > MAX_RECORD or int(m["tick"]) == NONE:
		return false
	if count != maxi(1, ceili(size / float(RECORD_CHUNK))) or index >= count:
		return false
	var want := RECORD_CHUNK if index < count - 1 else size - RECORD_CHUNK * (count - 1)
	return (m["chunk"] as PackedByteArray).size() == want


## Reads [method write_lobby]; {} when malformed (unknown flags, repeated
## ids or numbers, a player on a machine not listed, a machine's local
## number used twice).
static func read_lobby(reader: MwNetBytes.Reader) -> Dictionary:
	var d := {"state": reader.u8_in(0, 1), "match": reader.u32()}
	var machines := []
	var ids := {}
	var n := reader.u8_in(1, MAX_MACHINE + 1)
	for _i in n:
		var id := reader.u8_in(0, MAX_MACHINE)
		var flags := reader.u8_in(0, 3)
		var machine_ping := reader.u16()
		var address := reader.text(MAX_ADDRESS)
		if not reader.ok or ids.has(id):
			reader.ok = false
			return {}
		ids[id] = true
		machines.append({"id": id, "host": flags & 1 != 0, "connected": flags & 2 != 0, "ping": machine_ping,
				"address": address})
	var players := []
	var numbers := {}
	var slots := {}
	var np := reader.u8_in(0, MwNetInput.PLAYERS)
	for _i in np:
		var number := reader.u8_in(1, MwNetInput.PLAYERS)
		var machine := reader.u8()
		var local := reader.u8_in(1, MwNetInput.PLAYERS)
		var device := reader.u8()
		var slot := machine * 16 + local
		if not reader.ok or numbers.has(number) or not ids.has(machine) or slots.has(slot):
			reader.ok = false
			return {}
		numbers[number] = true
		slots[slot] = true
		players.append({"number": number, "machine": machine, "local": local, "device": device})
	d["machines"] = machines
	d["players"] = players
	return d if reader.ok else {}


# --- the password proofs --------------------------------------------------------------------------

## Fresh random bytes (nonces, rejoin keys, match IDs).
static func random_bytes(n: int) -> PackedByteArray:
	return _c().generate_random_bytes(n)


## The key both sides derive from the password (empty: no password, which
## still derives a key - anyone can compute it, and TOFU protects that case,
## section 6). A chain of [constant KDF_ROUNDS] HMAC-SHA256s keyed by the
## password's salted hash, so each offline guess costs as much.
static func derive_key(password: String) -> PackedByteArray:
	var k0 := ("mightyweenie-net-1:" + password).to_utf8_buffer()
	var key := _c().hmac_digest(HashingContext.HASH_SHA256, "mightyweenie-net-kdf".to_utf8_buffer(), k0)
	var u := "mightyweenie-net-kdf-1".to_utf8_buffer()
	for _i in KDF_ROUNDS:
		u = _c().hmac_digest(HashingContext.HASH_SHA256, key, u)
	return u


## A side's proof: HMAC-SHA256 keyed by [param key] over the side's label
## ("host" or "client"), its own nonce, the other's nonce and the
## certificate fingerprint as this side sees it. The labels keep one side's
## proof from being replayed as the other's.
static func proof(key: PackedByteArray, side: String, own_nonce: PackedByteArray,
		other_nonce: PackedByteArray, fingerprint: PackedByteArray) -> PackedByteArray:
	var msg := ("mightyweenie-net-proof-%s" % side).to_utf8_buffer()
	msg.append_array(own_nonce)
	msg.append_array(other_nonce)
	msg.append_array(fingerprint)
	return _c().hmac_digest(HashingContext.HASH_SHA256, key, msg)


## Version 6 (plan 45, M3): what HELLO carries for rejoin key [param key] -
## HMAC-SHA256 keyed by it over a label, the client's nonce [param nonce]
## and the fingerprint of the certificate the session is pinned to ([param
## fingerprint]), so the key itself never travels after WELCOME gave it: a
## man in the middle (another certificate) gets a proof the host won't take
## and can't learn the key from. Empty without a key.
static func rejoin_proof(key: PackedByteArray, nonce: PackedByteArray,
		fingerprint: PackedByteArray) -> PackedByteArray:
	if key.size() != KEY_BYTES:
		return PackedByteArray()
	var msg := "mightyweenie-net-rejoin".to_utf8_buffer()
	msg.append_array(nonce)
	msg.append_array(fingerprint)
	return _c().hmac_digest(HashingContext.HASH_SHA256, key, msg)


## Compares two proofs or keys in constant time.
static func same_secret(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	return _c().constant_time_compare(a, b)
