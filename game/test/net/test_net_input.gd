extends "res://test/net/net_test_base.gd"
## Plan 35 work item 2: a player's input on the wire (MwNetInput) - the verb
## table matches MwVerbs, states and their deltas round-trip, garbage
## deltas are refused - and the host's merge (MwNetMerge): presses one a
## tick, never lost, silent players neutral after 8 ticks, a new source's
## counters not read as presses.
## Short names: m the MwNetMerge under test, r the MwNetBytes.Reader under test.

const I := preload("res://src/net/net_input.gd")


func test_verb_table_covers_every_player_verb() -> void:
	var want: Array[String] = []
	want.append_array(MwVerbs.player_verbs())
	want.append_array(MwVerbs.menu_verbs())
	assert_eq(I.VERBS.size(), I.COUNT)
	assert_eq(I.VERBS, want,
			"the wire's verbs are MwVerbs' per-player and menu verbs (a new verb: add it here and the schema changes)")
	assert_false(MwVerbs.VIEW_TOGGLE in I.VERBS, "the view switch only draws")
	assert_eq(I.HELD_BYTES, (I.COUNT + 7) / 8)
	assert_eq(I.LAST_HELD_MASK, (1 << (I.COUNT - 8 * (I.HELD_BYTES - 1))) - 1)
	assert_eq(I.LAST_HELD_MASK & I.STATUS_BITS, 0, "the status past the verbs")
	assert_eq(I.STATUS_BITS >> I.STATUS_SHIFT, 3, "two bits")
	assert_eq(I.STICK, I.COUNTERS + I.COUNT)
	assert_eq(I.HEIGHT, I.STICK + 2, "the shot height after the stick")
	assert_eq(I.SIZE, I.HEIGHT + 1)
	assert_true(MwVerbs.SHOT_HIGH in I.VERBS and MwVerbs.SHOT_LOW in I.VERBS, "the shot heights' verbs")
	assert_eq(I.index_of("punch"), 4)
	assert_eq(I.index_of("view_toggle"), -1)


func test_states_and_presses() -> void:
	var bytes := I.blank()
	bytes = I.next_state(bytes, PackedInt32Array([0, 51]), PackedInt32Array([0, 51]), Vector2i(200, 128))
	assert_true(I.is_held(bytes, 0))
	assert_true(I.is_held(bytes, 51))
	assert_eq(I.held_verbs(bytes), PackedInt32Array([0, 51]))
	assert_eq(I.stick(bytes), Vector2i(200, 128))
	var t := I.next_state(bytes, PackedInt32Array(), PackedInt32Array([51]), Vector2i(200, 0))
	assert_eq(I.held_verbs(t), PackedInt32Array(), "a tap: pressed, not held")
	assert_eq(I.pressed_verbs(bytes, t), PackedInt32Array([51]))
	assert_eq(I.stick(t), Vector2i.ZERO, "a centred stick has one form")
	var w := bytes
	for i in 300:
		w = I.next_state(w, PackedInt32Array(), PackedInt32Array([7]))
	assert_eq(I.counter(w, 7), 300 & 0xFF, "counters wrap")
	assert_eq(I.presses(bytes, w, 7), 300 - 256, "...so only fewer than 256 presses between two states the host "
			+ "decodes count right (8.5 s of presses at the fastest)")
	var u := I.from_actions(I.blank(), 3, {"p3_pass": true, "p3_ui_back": true}, {"p3_ui_back": true, "p2_pass": true})
	assert_true(I.is_held(u, I.index_of("pass")))
	assert_true(I.is_held(u, I.index_of("ui_back")))
	assert_eq(I.pressed_verbs(I.blank(), u), PackedInt32Array([I.index_of("ui_back")]),
			"another player's action ignored")


func _random_state(rng: RandomNumberGenerator) -> PackedByteArray:
	var bytes := I.blank()
	for v in I.COUNT:
		if rng.randf() < 0.3:
			bytes[v >> 3] |= 1 << (v & 7)
		if rng.randf() < 0.5:
			bytes[I.COUNTERS + v] = rng.randi_range(0, 255)
	bytes[I.STICK] = rng.randi_range(0, 255)
	bytes[I.STICK + 1] = rng.randi_range(0, 255)
	bytes[I.HEIGHT] = rng.randi_range(0, 3)
	return bytes


func test_deltas_round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		var base := _random_state(rng)
		var bytes := base.duplicate()
		match i % 5:
			0:
				bytes = _random_state(rng)
			1:
				bytes[I.COUNTERS + rng.randi_range(0, I.COUNT - 1)] += 1
			2:
				bytes[I.STICK] = rng.randi_range(0, 255)
			3:
				bytes[I.HEIGHT] = (bytes[I.HEIGHT] + rng.randi_range(1, 3)) & 3
		var writer := MwNetBytes.Writer.new()
		I.write_delta(writer, base, bytes)
		var out := base.duplicate()
		var r := MwNetBytes.Reader.new(writer.data)
		assert_true(I.read_delta_into(r, out, 0) and r.done(), "delta %d reads" % i)
		if out != bytes:
			fail_test("delta %d differs" % i)
			return
	var ticks: Array[PackedByteArray] = [I.blank_tick()]
	for i in 30:
		var states := []
		for p in I.PLAYERS:
			states.append(_random_state(rng) if rng.randf() < 0.4 else I.player(ticks[-1], p + 1))
		ticks.append(I.make_tick(states))
	for i in range(1, ticks.size()):
		var b := I.encode_tick(ticks[i - 1], ticks[i])
		var r := MwNetBytes.Reader.new(b)
		assert_eq(I.read_tick(r, ticks[i - 1]), ticks[i])
	assert_eq(I.encode_tick(ticks[5], ticks[5]).size(), 2, "an unchanged tick is two bytes")
	var everything := I.encode_tick(I.blank_tick(), ticks[-1])
	assert_true(everything.size() < MwNetTickLog.BODY_LIMIT,
			"a whole tick from blank fits a message (%d)" % everything.size())


func test_malformed_deltas_refused() -> void:
	var cases := {
		"unknown flag": PackedByteArray([0x00, 0x01, 0x20]),
		"both counter forms": PackedByteArray([0x00, 0x01, 0x06]),
		"a shot height's code above 3": PackedByteArray([0x00, 0x01, 0x10, 4]),
		"a shot height cut short": PackedByteArray([0x00, 0x01, 0x10]),
		"verb out of range": PackedByteArray([0x00, 0x01, 0x02, 1, I.COUNT, 5]),
		"verbs out of order": PackedByteArray([0x00, 0x01, 0x02, 2, 5, 1, 3, 1]),
		"no counters": PackedByteArray([0x00, 0x01, 0x02, 0]),
		"cut short": PackedByteArray([0x00, 0x01, 0x08, 5]),
		"another player": PackedByteArray([0x00, 0x04, 0x08, 5, 5]),
	}
	for k in cases:
		var r := MwNetBytes.Reader.new(cases[k])
		var t := I.read_tick(r, I.blank_tick(), 0x3)
		assert_true(t.is_empty() or not r.done(), k)


## The shot heights (MwSettings.shot_heights): each player's code (0 the
## D-pad's, 1 none, 2 high, 3 low: MwTickInput.height_code) in its own
## byte, its own delta flag; the merge passes it on, a silent player's goes
## back to the D-pad's; the router's form carries it whole.
func test_shot_heights_on_the_wire() -> void:
	for h in [-1, 0, 1, 2]:
		assert_eq(MwTickInput.height_of(MwTickInput.height_code(h)), h, "height %d round trip" % h)
	assert_eq(MwTickInput.height_code(7), 3, "codes stay 0-3")
	var bytes := I.from_actions(I.blank(), 5, {"p5_shot_high": true}, {}, Vector2i.ZERO, MwTickInput.height_code(1))
	assert_eq(I.height(bytes), 2, "HIGH SHOT's code")
	assert_true(I.is_held(bytes, I.index_of("shot_high")), "the verb's bit travels too")
	assert_eq(I.height(I.next_state(bytes, PackedInt32Array(), PackedInt32Array(), Vector2i.ZERO, 9)), 3, "clamped")
	var writer := MwNetBytes.Writer.new()
	var base := I.blank()
	var only_height := base.duplicate()
	only_height[I.HEIGHT] = 3
	I.write_delta(writer, base, only_height)
	assert_eq(writer.data, PackedByteArray([I.D_HEIGHT, 3]), "a height alone: its flag and one byte")
	var out := base.duplicate()
	var r := MwNetBytes.Reader.new(writer.data)
	assert_true(I.read_delta_into(r, out, 0) and r.done())
	assert_eq(out, only_height)
	var m := MwNetMerge.new()
	m.set_players([12])
	m.feed(12, bytes)
	var t := m.tick()
	assert_eq(I.height(I.player(t, 12)), 2, "player 12's height merged")
	var ti := MwTickInput.from_wire(t)
	assert_eq(ti.heights[11], 2, "the router's form: the same code")
	for i in MwNetMerge.HOLD_TICKS:
		t = m.tick()
	assert_eq(I.height(I.player(t, 12)), 0, "silent: the D-pad's")


func test_merge_one_press_a_tick_none_lost() -> void:
	var m := MwNetMerge.new()
	m.set_players([1, 4])
	var bytes := I.blank()
	m.feed(4, bytes)
	for i in 5:
		bytes = I.next_state(bytes, PackedInt32Array(), PackedInt32Array([4, 9]))
	m.feed(4, bytes)   # five presses of two verbs arrive at once (a burst after a loss)
	var prev := m.last()
	var seen := 0
	for i in 8:
		var t := m.tick()
		var a := I.player(prev, 4)
		var b := I.player(t, 4)
		assert_true(I.presses(a, b, 4) <= 1 and I.presses(a, b, 9) <= 1, "at most one press a tick")
		seen += I.presses(a, b, 4)
		prev = t
	assert_eq(seen, 5, "every press comes through")
	assert_eq(I.counter(I.player(prev, 4), 9), 5)
	assert_eq(m.pending(4), 0)
	assert_eq(I.player(prev, 2), I.blank(), "a player not in the match stays blank")


func test_merge_silent_player_goes_neutral() -> void:
	var m := MwNetMerge.new()
	m.set_players([2])
	var bytes := I.next_state(I.blank(), PackedInt32Array([0]), PackedInt32Array([0]), Vector2i(64, 255))
	m.feed(2, I.blank())
	m.feed(2, bytes)
	var t := PackedByteArray()
	for i in MwNetMerge.HOLD_TICKS:
		t = m.tick()
		assert_true(I.is_held(I.player(t, 2), 0), "held for tick %d" % i)
	t = m.tick()
	assert_false(I.is_held(I.player(t, 2), 0), "neutral after %d silent ticks" % MwNetMerge.HOLD_TICKS)
	assert_eq(I.stick(I.player(t, 2)), Vector2i.ZERO)
	assert_eq(I.counter(I.player(t, 2), 0), 1, "the press stays counted")
	assert_eq(m.silent_ticks(2), MwNetMerge.HOLD_TICKS + 1)
	m.feed(2, bytes)
	assert_true(I.is_held(I.player(m.tick(), 2), 0), "back when it speaks again")


func test_merge_new_source_counts_afresh() -> void:
	var m := MwNetMerge.new()
	m.set_players([3])
	var bytes := I.blank()
	for i in 3:
		bytes = I.next_state(bytes, PackedInt32Array(), PackedInt32Array([1]))
	m.feed(3, bytes)
	for i in 5:
		m.tick()
	assert_eq(I.counter(I.player(m.last(), 3), 1), 3)
	m.new_source(3)    # a rejoined machine: its counters start anywhere
	var fresh := I.next_state(I.blank(), PackedInt32Array(), PackedInt32Array([1]))
	m.feed(3, fresh)
	for i in 5:
		m.tick()
	assert_eq(I.counter(I.player(m.last(), 3), 1), 3, "no presses invented from the new counters")
	m.feed(3, I.next_state(fresh, PackedInt32Array(), PackedInt32Array([1])))
	m.tick()
	assert_eq(I.counter(I.player(m.last(), 3), 1), 4, "its next press counts")


func test_merge_caps_a_flood() -> void:
	var m := MwNetMerge.new()
	m.set_players([1])
	var bytes := I.blank()
	m.feed(1, bytes)
	for i in 50:
		bytes = bytes.duplicate()
		bytes[I.COUNTERS + 2] = (bytes[I.COUNTERS + 2] + 200) & 0xFF
		m.feed(1, bytes)
	assert_eq(m.pending(1), MwNetMerge.MAX_PENDING, "a modified client can't queue more")


## Plan 43: with stamps each state waits for the host tick it is meant for
## and is taken there, in the order sent - a stick moving every tick lands
## a state a tick, as the client predicted it; one come late is taken at
## once; the presses among states taken together still come one a tick;
## arriving is news (no neutral while one waits); a stamp too far ahead
## waits MAX_WAIT at most. Off, every state as it comes.
func test_merge_stamped_states_wait_for_their_ticks() -> void:
	var m := MwNetMerge.new()
	m.stamped = true
	m.set_players([5])
	var states: Array[PackedByteArray] = []
	var bytes := I.blank()
	for i in 4:
		bytes = I.next_state(bytes, PackedInt32Array(), PackedInt32Array([2]) if i == 2 else PackedInt32Array(),
				Vector2i(10 * (i + 1), 255))
		states.append(bytes)
	m.tick(0)                                     # tick 0 made: the next is 1
	for i in 4:
		m.feed_at(5, states[i], 3 + i)            # all four arrive now, for ticks 3-6
	var sticks := []
	for k in range(1, 8):
		sticks.append(I.stick(I.player(m.tick(k), 5)).x)
	assert_eq(sticks, [0, 0, 10, 20, 30, 40, 40], "each at its own tick")
	assert_eq(m.stats[5], {"on_time": 4, "late": 0, "slack": 2 + 3 + 4 + 5}, "on time, 2-5 ticks early")
	m = MwNetMerge.new()
	m.stamped = true
	m.set_players([5])
	m.tick(9)
	m.feed_at(5, states[3], 4)                    # late: taken by the next tick, its press too
	var t := m.tick(10)
	assert_eq(I.stick(I.player(t, 5)).x, 40, "a late state at once")
	assert_eq(I.counter(I.player(t, 5), 2), 1, "its press")
	assert_eq(m.stats[5]["late"], 1)
	var far := I.next_state(states[3], PackedInt32Array(), PackedInt32Array(), Vector2i(90, 255))
	m.feed_at(5, far, 1000)
	var waited := 0
	for k in range(11, 11 + MwNetMerge.MAX_WAIT):
		t = m.tick(k)
		if I.stick(I.player(t, 5)).x == 40:
			waited += 1
		m.feed_at(5, far, 1000)                   # (its machine still sending: news)
	assert_eq(waited, MwNetMerge.MAX_WAIT, "the far one waiting, the player not neutral meanwhile")
	t = m.tick(11 + MwNetMerge.MAX_WAIT)
	assert_eq(I.stick(I.player(t, 5)).x, 90, "a stamp too far ahead waits MAX_WAIT at most")
	m.stamped = false
	m.feed_at(5, states[0], 5000)
	assert_eq(I.stick(I.player(m.tick(), 5)).x, 10, "off: as it comes")
