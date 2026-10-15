extends "res://test/net/net_test_base.gd"
## Plan 35 work item 2: the stream's two ends (MwNetTickLog,
## MwNetTickReceiver) without a network - packets rebuild the ticks
## exactly whatever is lost, repeated or reordered; acknowledged ticks
## aren't sent again; gaps are asked for and filled by resends; garbage and
## contradictions are refused.

const I := preload("res://src/net/net_input.gd")
const P := preload("res://src/net/net_protocol.gd")


func _ticks(n: int, seed_value: int) -> Array[PackedByteArray]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var states := []
	for p in I.PLAYERS:
		states.append(I.blank())
	var out: Array[PackedByteArray] = []
	for i in n:
		for p in [0, 3, 7]:
			if rng.randf() < 0.3:
				states[p] = I.next_state(states[p], PackedInt32Array([rng.randi_range(0, 10)]),
						PackedInt32Array([rng.randi_range(0, I.COUNT - 1)]), Vector2i(rng.randi_range(0, 255), 200))
		out.append(I.make_tick(states))
	return out


func _feed(rx: MwNetTickReceiver, pkt: Dictionary) -> int:
	return rx.receive(pkt["base"], pkt["first"], pkt["count"], pkt["body"])


func test_lossless_stream_rebuilds_exactly() -> void:
	var ticks := _ticks(100, 1)
	var tick_log := MwNetTickLog.new(0)
	var rx := MwNetTickReceiver.new(0)
	for t in ticks:
		tick_log.push(t)
		var pkt := tick_log.encode(rx.ack())
		assert_eq(_feed(rx, pkt), MwNetTickReceiver.Result.OK)
		assert_eq(pkt["count"], 1, "acknowledged ticks aren't repeated")
	assert_eq(rx.confirmed, 99)
	for i in 100:
		assert_eq(rx.get_tick(i), ticks[i])


func test_repeats_cover_lost_packets() -> void:
	var ticks := _ticks(60, 2)
	var tick_log := MwNetTickLog.new(0)
	var rx := MwNetTickReceiver.new(0)
	var acked := P.NONE
	for i in ticks.size():
		tick_log.push(ticks[i])
		var pkt := tick_log.encode(acked)
		if i % 4 != 3:    # three in four packets lost, and the acknowledgements with them
			continue
		assert_eq(_feed(rx, pkt), MwNetTickReceiver.Result.OK)
		acked = rx.ack()
	assert_eq(rx.confirmed, 59, "8 repeated ticks bridge 3 lost packets")
	for i in 60:
		assert_eq(rx.get_tick(i), ticks[i])


func test_gap_is_asked_for_and_resent() -> void:
	var ticks := _ticks(80, 3)
	var tick_log := MwNetTickLog.new(0)
	var rx := MwNetTickReceiver.new(0)
	for i in 20:
		tick_log.push(ticks[i])
		_feed(rx, tick_log.encode(rx.ack()))
	for i in range(20, 50):
		tick_log.push(ticks[i])      # an outage: 30 ticks never arrive
	tick_log.push(ticks[50])
	_feed(rx, tick_log.encode(rx.ack()))
	assert_eq(rx.confirmed, 19)
	assert_eq(rx.newest, 50)
	var req := rx.resend_request(1000)
	assert_eq(req, Vector2i(20, 42), "the ticks the repeats won't bring")
	assert_eq(rx.resend_request(1001), Vector2i(-1, -1), "not again at once")
	var chunks := tick_log.encode_range(req.x, req.y)
	for c in chunks:
		assert_true(P.resend(1, c["base"], c["first"], c["count"], c["body"]).size() <= P.MAX_MESSAGE)
		assert_eq(_feed(rx, c), MwNetTickReceiver.Result.OK)
	assert_eq(rx.confirmed, 50)
	for i in 51:
		assert_eq(rx.get_tick(i), ticks[i])
	assert_eq(rx.resend_request(5000), Vector2i(-1, -1), "nothing missing")


func test_reordered_and_duplicated_packets() -> void:
	var ticks := _ticks(40, 4)
	var tick_log := MwNetTickLog.new(0)
	var pkts: Array[Dictionary] = []
	for t in ticks:
		tick_log.push(t)
		pkts.append(tick_log.encode(P.NONE))
	var rx := MwNetTickReceiver.new(0)
	var order := range(pkts.size())
	order.reverse()
	for i in order:
		assert_eq(_feed(rx, pkts[i]), MwNetTickReceiver.Result.OK)
		assert_eq(_feed(rx, pkts[i]), MwNetTickReceiver.Result.OK, "a duplicate is harmless")
	assert_eq(rx.newest, 39)
	assert_eq(rx.confirmed, 39)
	for i in 40:
		assert_eq(rx.get_tick(i), ticks[i])


func test_receiver_refuses_garbage() -> void:
	var ticks := _ticks(20, 5)
	var tick_log := MwNetTickLog.new(0)
	for t in ticks:
		tick_log.push(t)
	var rx := MwNetTickReceiver.new(0)
	var pkt := tick_log.encode(P.NONE)
	assert_eq(rx.receive(5, 6, 1, pkt["body"]), MwNetTickReceiver.Result.NO_BASE, "a base it doesn't hold")
	assert_eq(rx.receive(P.NONE, 5000, 1, PackedByteArray([0, 0])), MwNetTickReceiver.Result.BAD, "too far ahead")
	assert_eq(rx.receive(P.NONE, 0, 2, PackedByteArray([0, 0])), MwNetTickReceiver.Result.BAD, "a tick short")
	assert_eq(rx.receive(P.NONE, 0, 1, PackedByteArray([0, 0, 0])), MwNetTickReceiver.Result.BAD, "a byte over")
	rx.allowed = 0x1
	assert_eq(_feed(rx, pkt), MwNetTickReceiver.Result.BAD, "players outside the allowed mask")
	rx.allowed = I.ALL_PLAYERS
	assert_eq(_feed(rx, pkt), MwNetTickReceiver.Result.OK)
	var other := _ticks(20, 6)
	var log2 := MwNetTickLog.new(0)
	for t in other:
		log2.push(t)
	assert_eq(_feed(rx, log2.encode(P.NONE)), MwNetTickReceiver.Result.BAD, "contradicting ticks it holds")


func test_rejoiner_starts_mid_stream() -> void:
	var ticks := _ticks(120, 7)
	var tick_log := MwNetTickLog.new(0)
	for i in 100:
		tick_log.push(ticks[i])
	var rx := MwNetTickReceiver.new(100)    # rejoined after tick 99
	assert_eq(rx.ack(), P.NONE)
	for i in range(100, 120):
		tick_log.push(ticks[i])
		if i % 3 == 0:
			continue
		assert_eq(_feed(rx, tick_log.encode(rx.ack(), 100)), MwNetTickReceiver.Result.OK)
	assert_eq(rx.confirmed, 119)
	for i in range(100, 120):
		assert_eq(rx.get_tick(i), ticks[i])
	assert_false(rx.has(99), "nothing before its start")
	var rx2 := MwNetTickReceiver.new(100)
	for c in tick_log.encode_range(100, 110, 100):
		assert_eq(c["base"], P.NONE, "a resend from its start is coded from blank, not from a tick it never had")
		assert_eq(_feed(rx2, c), MwNetTickReceiver.Result.OK)
	assert_eq(rx2.confirmed, 110)


func test_newest_ticks_first_when_too_big() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var tick_log := MwNetTickLog.new(0)
	for i in 8:
		var states := []
		for p in I.PLAYERS:
			var bytes := I.blank()
			for v in I.COUNT:
				bytes[I.COUNTERS + v] = rng.randi_range(0, 255)
			states.append(bytes)
		tick_log.push(I.make_tick(states))
	var pkt := tick_log.encode(P.NONE)
	assert_lt(pkt["count"], 8, "eight busy ticks don't fit one message")
	assert_eq(pkt["first"] + pkt["count"] - 1, 7, "the newest is always in")
	assert_true(P.stream(1, P.NONE, pkt["base"], pkt["first"], pkt["count"], pkt["body"]).size() <= P.MAX_MESSAGE)
