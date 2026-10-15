extends "res://test/net/net_test_base.gd"
## Plan 35 work item 2: the net messages (MwNetProtocol, MwNetBytes) - every
## message round-trips, malformed ones are refused (cut short, too long,
## out of range, another version, the wrong channel), random and mutated
## bytes never crash the decoders (fuzzing), and the proofs bind the
## password, both nonces and the certificate's fingerprint.

const P := preload("res://src/net/net_protocol.gd")


func _lobby() -> Dictionary:
	return {"state": 0, "match": 77, "machines": [
		{"id": 0, "host": true, "connected": true, "ping": 0, "address": ""},
		{"id": 3, "host": false, "connected": false, "ping": 123, "address": "fe80:0:0:0:1:2:3:4"}],
		"players": [{"number": 1, "machine": 0, "local": 1, "device": 0},
			{"number": 2, "machine": 3, "local": 1, "device": 4},
			{"number": 5, "machine": 3, "local": 2, "device": 1}]}


## One of every message, valid.
func _samples() -> Array[PackedByteArray]:
	var nonce := P.random_bytes(P.NONCE_BYTES)
	var key := P.random_bytes(P.KEY_BYTES)
	var proof := P.random_bytes(P.PROOF_BYTES)
	var rom_hash := P.random_bytes(P.SHA1_BYTES)
	var body := MwNetInput.encode_tick(MwNetInput.blank_tick(), MwNetInput.blank_tick())
	var out: Array[PackedByteArray] = [
		P.cert(fake_cert(3)),
		P.hello("build 1", rom_hash, 1234, nonce, 2, key),
		P.hello("build 1", rom_hash, 1234, nonce, 1, PackedByteArray()),
		P.challenge(nonce, true),
		P.auth(proof),
		P.welcome(proof, 3, key, 77, P.NONE, [2, 5], _lobby()),
		P.refuse(P.Refusal.WRONG_PASSWORD, 4),
		P.lobby(_lobby()),
		P.join_local(3, 9),
		P.leave_local(5),
		P.start(77, 0, 3, 0, 1, PackedByteArray([1, 2, 3])),
		P.start(77, 0, 0, 0, 1, PackedByteArray()),
		P.start(77, 0, 2000, 1, 3, P.random_bytes(P.RECORD_CHUNK)),
		P.start(77, 0, 2000, 2, 3, P.random_bytes(80)),
		P.close(P.Close.KICKED),
		P.bye(),
		P.input(77, P.NONE, P.NONE, 0, 1, body),
		P.stream(77, 12, 40, 41, 1, body),
		P.resend_request(10, 20),
		P.resend(77, P.NONE, 5, 1, body),
		P.hashes(77, [{"tick": 9, "kind": 0, "value": P.random_bytes(8)}]),
		P.ping(7, 123456),
		P.pong(7, 123456, P.NONE),
		P.desync(77, 900, 1, P.random_bytes(8)),
		P.snapshot(77, 3, 900, 2000, 2, 3, P.random_bytes(80)),
		P.snapshot(77, 3, 900, 2000, 0, 3, P.random_bytes(P.SNAPSHOT_CHUNK)),
		P.resync(77, P.Resync.LOST),
		P.synced(77, 3),
	]
	return out


func test_every_message_round_trips() -> void:
	var nonce := P.random_bytes(P.NONCE_BYTES)
	var key := P.random_bytes(P.KEY_BYTES)
	var rom_hash := P.random_bytes(P.SHA1_BYTES)
	var m := P.decode(P.hello("b", rom_hash, 0xDEADBEEF, nonce, 3, key))
	assert_eq(m.get("type"), P.Type.HELLO)
	assert_eq(m.get("build"), "b")
	assert_eq(m.get("rom"), rom_hash)
	assert_eq(m.get("schema"), 0xDEADBEEF)
	assert_eq(m.get("nonce"), nonce)
	assert_eq(m.get("locals"), 3)
	assert_eq(m.get("key"), key)
	var w := P.decode(P.welcome(key, 3, key, 77, 1000, [2, 5], _lobby()))
	assert_eq(w.get("machine"), 3)
	assert_eq(w.get("numbers"), [2, 5])
	assert_eq(w.get("tick"), 1000)
	assert_eq(w.get("lobby"), _lobby(), "the lobby round-trips")
	var inp := P.decode(P.input(77, 12, 40, 41, 3, PackedByteArray([0, 0, 0, 0, 0, 0]),
			PackedInt32Array([500, 501, 503])))
	assert_eq([inp.get("match"), inp.get("ack"), inp.get("base"), inp.get("first"), inp.get("count"), inp.get("stamps"),
			inp.get("body")], [77, 12, 40, 41, 3, PackedInt32Array([500, 501, 503]),
			PackedByteArray([0, 0, 0, 0, 0, 0])],
			"version 5's INPUT: each state's stamp")
	assert_eq(P.decode(P.input(77, 12, 40, 41, 2, PackedByteArray([0, 0, 0, 0]))).get("stamps"), PackedInt32Array(),
			"no stamps: none")
	var stream_message := P.decode(P.stream(77, 12, 40, 41, 2, PackedByteArray([0, 0, 0, 0])))
	assert_eq([stream_message.get("match"), stream_message.get("ack"), stream_message.get("base"),
			stream_message.get("first"), stream_message.get("count"), stream_message.get("body")],
			[77, 12, 40, 41, 2, PackedByteArray([0, 0, 0, 0])])
	var h := P.decode(P.hashes(5, [{"tick": 9, "kind": 1, "value": PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])}]))
	assert_eq(h.get("entries"), [{"tick": 9, "kind": 1, "value": PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])}])
	var ds := P.decode(P.desync(5, 900, 1, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])))
	assert_eq([ds.get("match"), ds.get("tick"), ds.get("kind"), ds.get("value")],
			[5, 900, 1, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])], "work item 4's DESYNC")
	var chunk := P.random_bytes(80)
	var sn := P.decode(P.snapshot(5, 65535, 900, 2000, 2, 3, chunk))
	assert_eq([sn.get("match"), sn.get("id"), sn.get("tick"), sn.get("size"), sn.get("index"), sn.get("count"),
			sn.get("chunk")], [5, 65535, 900, 2000, 2, 3, chunk], "work item 6's SNAPSHOT")
	var st := P.decode(P.start(5, 0, 2000, 2, 3, chunk))
	assert_eq([st.get("match"), st.get("tick"), st.get("size"), st.get("index"), st.get("count"), st.get("chunk")],
			[5, 0, 2000, 2, 3, chunk], "version 4's START: a chunk of the record")
	assert_eq(P.decode(P.resync(5, P.Resync.FAILED)).get("reason"), P.Resync.FAILED, "RESYNC")
	assert_eq(P.decode(P.synced(5, 12)).get("id"), 12, "SYNCED")
	for msg in _samples():
		var d := P.decode(msg)
		assert_false(d.is_empty(), "type %d decodes" % msg[0])
		assert_true(msg.size() <= P.MAX_MESSAGE)
		assert_false(P.decode(msg, int(P.CHANNEL_OF[msg[0]])).is_empty(), "on its channel")


func test_wrong_channel_version_or_type_refused() -> void:
	for msg in _samples():
		var ch := int(P.CHANNEL_OF[msg[0]])
		assert_true(P.decode(msg, (ch + 1) % P.CHANNELS).is_empty(), "type %d on another channel" % msg[0])
		var other := msg.duplicate()
		other[1] = P.VERSION + 1
		if msg[0] == P.Type.REFUSE:
			assert_false(P.decode(other).is_empty(), "REFUSE is decoded whatever the version")
		else:
			assert_true(P.decode(other).is_empty(), "type %d of another version" % msg[0])
	assert_eq(P.peek(PackedByteArray([P.Type.HELLO, 9])), Vector2i(P.Type.HELLO, 9))
	assert_true(P.decode(PackedByteArray([0, P.VERSION])).is_empty())
	assert_true(P.decode(PackedByteArray([P.LAST_TYPE + 1, P.VERSION])).is_empty())
	assert_true(P.decode(PackedByteArray()).is_empty())


func test_cut_short_or_padded_refused() -> void:
	for msg in _samples():
		for n in range(0, msg.size()):
			var cut := msg.slice(0, n)
			# a stream's body is checked by the tick decoder, not here: cutting
			# into it leaves a message whose header is still whole
			if msg[0] in [P.Type.INPUT, P.Type.STREAM, P.Type.RESEND] and n >= msg.size() - 2:
				continue
			if not P.decode(cut).is_empty():
				fail_test("type %d cut to %d bytes decoded" % [msg[0], n])
				return
		var padded := msg.duplicate()
		padded.append(0)
		if not msg[0] in [P.Type.INPUT, P.Type.STREAM, P.Type.RESEND]:
			assert_true(P.decode(padded).is_empty(), "type %d with a byte too many" % msg[0])
	var big := PackedByteArray()
	big.resize(P.MAX_MESSAGE + 1)
	big[0] = P.Type.PING
	big[1] = P.VERSION
	assert_true(P.decode(big).is_empty(), "over the cap")


func test_out_of_range_fields_refused() -> void:
	var nonce := P.random_bytes(P.NONCE_BYTES)
	var rom_hash := P.random_bytes(P.SHA1_BYTES)
	assert_true(P.decode(P.hello("b", rom_hash, 1, nonce, 0, PackedByteArray())).is_empty(), "no local players")
	assert_true(P.decode(P.hello("b", rom_hash, 1, nonce, 13, PackedByteArray())).is_empty(), "13 local players")
	assert_true(P.decode(P.hello("b", rom_hash, 1, nonce, 1, PackedByteArray([1, 2, 3]))).is_empty(), "a short key")
	assert_true(P.decode(P.hello("b\u0001", rom_hash, 1, nonce, 1, PackedByteArray())).is_empty(), "control characters")
	assert_true(P.decode(P.join_local(13, 0)).is_empty())
	assert_true(P.decode(P.leave_local(0)).is_empty())
	assert_true(P.decode(P.close(9)).is_empty())
	assert_true(P.decode(P.resend_request(20, 10)).is_empty(), "backwards")
	assert_true(P.decode(P.resend_request(0, P.MAX_RESEND)).is_empty(), "too many")
	assert_true(P.decode(P.stream(1, 0, 5, 5, 1, PackedByteArray([0, 0]))).is_empty(), "base not before first")
	assert_true(P.decode(P.stream(1, 0, P.NONE, 1, 9, PackedByteArray([0, 0]))).is_empty(), "9 ticks")
	var key := P.random_bytes(P.KEY_BYTES)
	assert_true(P.decode(P.welcome(key, 3, key, 1, 0, [13], _lobby())).is_empty(), "player 13")
	assert_true(P.decode(P.welcome(key, 3, key, 1, 0, [2, 2], _lobby())).is_empty(), "a number twice")
	# version 4's START: the chunk's numbers must agree
	var c80 := P.random_bytes(80)
	assert_true(P.decode(P.start(1, 0, 2000, 2, 4, c80)).is_empty(), "a count the size doesn't make")
	assert_true(P.decode(P.start(1, 0, 2000, 3, 3, c80)).is_empty(), "an index past the count")
	assert_true(P.decode(P.start(1, 0, 2000, 1, 3, c80)).is_empty(), "a middle chunk short")
	assert_true(P.decode(P.start(1, 0, 2000, 2, 3, P.random_bytes(81))).is_empty(), "the last chunk long")
	assert_true(P.decode(P.start(1, 0, 0, 0, 1, PackedByteArray([1]))).is_empty(), "an empty record's chunk not empty")
	assert_true(P.decode(P.start(1, P.NONE, 3, 0, 1, PackedByteArray([1, 2, 3]))).is_empty(), "no first tick")
	var too_big := P.MAX_RECORD + 1
	assert_true(P.decode(P.start(1, 0, too_big, 0, ceili(too_big / float(P.RECORD_CHUNK)),
			P.random_bytes(P.RECORD_CHUNK))).is_empty(), "over the record's cap")
	assert_eq(P.start_messages(1, 0, PackedByteArray()).size(), 1, "an empty record: one START")
	var rec := P.random_bytes(P.RECORD_CHUNK * 2 + 5)
	var msgs := P.start_messages(1, 0, rec)
	assert_eq(msgs.size(), 3, "a record of three chunks: three STARTs")
	var parts := MwNetChunks.new()
	for i in [2, 0, 1]:
		var m := P.decode(msgs[i], P.CH_RELIABLE)
		assert_false(m.is_empty())
		m["id"] = 0
		assert_eq(parts.take(m), MwNetChunks.Result.DONE if i == 1 else MwNetChunks.Result.MORE)
	assert_eq(parts.use(), rec, "put together in any order")
	assert_eq(P.start_messages(1, 0, P.random_bytes(P.MAX_RECORD + 1)).size(), 0, "over the cap: no START")
	var bad := _lobby()
	bad["players"][1]["machine"] = 9
	assert_true(P.decode(P.lobby(bad)).is_empty(), "a player on a machine not listed")
	bad = _lobby()
	bad["players"][2]["number"] = 2
	assert_true(P.decode(P.lobby(bad)).is_empty(), "a number twice")
	bad = _lobby()
	bad["players"][2]["local"] = 1
	assert_true(P.decode(P.lobby(bad)).is_empty(), "a machine's local player twice")
	bad = _lobby()
	bad["machines"][1]["id"] = 0
	assert_true(P.decode(P.lobby(bad)).is_empty(), "a machine twice")


## Random bytes, and valid messages with random bytes changed, never crash
## a decoder: the protocol's, the tick decoder's, the lobby's.
func test_fuzzed_decodes_never_crash() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	var samples := _samples()
	var decoded := 0
	for i in 3000:
		var data := PackedByteArray()
		if i % 3 == 0:
			for j in rng.randi_range(0, 64 if i % 2 else P.MAX_MESSAGE + 8):
				data.append(rng.randi_range(0, 255))
			if data.size() >= 2 and i % 6 == 0:
				data[0] = rng.randi_range(1, P.LAST_TYPE)
				data[1] = P.VERSION
		else:
			data = samples[rng.randi_range(0, samples.size() - 1)].duplicate()
			for k in rng.randi_range(1, 4):
				if data.size() > 2:
					data[rng.randi_range(2, data.size() - 1)] = rng.randi_range(0, 255)
		var m := P.decode(data, -1)
		if not m.is_empty():
			decoded += 1
			if m.has("body"):
				var rx := MwNetTickReceiver.new(int(m["first"]) if int(m["base"]) == P.NONE else 0)
				rx.receive(m["base"], m["first"], m["count"], m["body"])
			if m.has("lobby"):
				MwNetLobby.new().load_wire(m["lobby"])
		var reader := MwNetBytes.Reader.new(data)
		MwNetInput.read_tick(reader, MwNetInput.blank_tick())
	assert_gt(decoded, 100, "mutations still decode often enough to reach the inner decoders")


func test_reader_stops_at_the_end() -> void:
	var reader := MwNetBytes.Reader.new(PackedByteArray([1, 2, 3]))
	assert_eq(reader.u16(), 0x0102)
	assert_eq(reader.u16(), 0, "past the end")
	assert_false(reader.ok)
	assert_eq(reader.u8(), 0, "stays failed")
	var writer := MwNetBytes.Writer.new()
	writer.u32(0xFFFFFFFE)
	writer.text("HI")
	writer.blob16(PackedByteArray([9]))
	var r2 := MwNetBytes.Reader.new(writer.data)
	assert_eq(r2.u32(), 0xFFFFFFFE)
	assert_eq(r2.text(8), "HI")
	assert_eq(r2.blob16(1, 1), PackedByteArray([9]))
	assert_true(r2.done())


func test_proofs_bind_everything() -> void:
	var k := P.derive_key("hunter2")
	assert_eq(k.size(), 32)
	assert_eq(k, P.derive_key("hunter2"), "the same password, the same key")
	assert_ne(k, P.derive_key("hunter3"))
	assert_ne(P.derive_key(""), k)
	var a := P.random_bytes(16)
	var b := P.random_bytes(16)
	var fp := MwNetIdentity.fingerprint_of(fake_cert(1))
	var proof := P.proof(k, "client", a, b, fp)
	assert_true(P.same_secret(proof, P.proof(k, "client", a, b, fp)))
	assert_false(P.same_secret(proof, P.proof(k, "host", a, b, fp)), "the side")
	assert_false(P.same_secret(proof, P.proof(k, "client", b, a, fp)), "the nonces' order")
	assert_false(P.same_secret(proof, P.proof(k, "client", a, b, MwNetIdentity.fingerprint_of(fake_cert(2)))),
			"another certificate (a man in the middle)")
	assert_false(P.same_secret(proof, P.proof(P.derive_key("x"), "client", a, b, fp)), "another password")
	assert_false(P.same_secret(PackedByteArray(), PackedByteArray()), "empty never matches")
