extends "res://test/rom/rom_test_base.gd"
## Plan 35 work item 1 (docs/net.md): the input stream - every player's
## verbs tick by tick (held bitsets, press counters, stick codes) - the
## router playing it (MwStreamInput) and the pass clock's stream mode.
## Short names: r the MwRouter under test, t the MwTickInput under test.


## A source pressing what [member script] says at each tick.
class Scripted extends MwInputSource:
	var router: MwRouter
	var plan := {}               ## tick -> {"held": {...}, "taps": {...}}
	var _now := {}
	func tick() -> void:
		_now = plan.get(router.tick, {})
	func sample(_contexts: Array) -> Dictionary:
		return _now.get("held", {})
	func taps() -> Dictionary:
		return _now.get("taps", {})
	func heights() -> Array:
		return _now.get("heights", [])


func test_tick_input_bits_and_counters() -> void:
	var t := MwTickInput.new()
	var names := MwTickInput.actions()
	assert_eq(names, MwVerbs.all_actions(), "every action the game defines")
	assert_eq(MwTickInput.slot_range(0), Vector2i(0, MwVerbs.menu_verbs().size()), "slot 0: the shared menu verbs")
	var r1 := MwTickInput.slot_range(1)
	var r12 := MwTickInput.slot_range(12)
	assert_eq(r12.y, names.size(), "twelve players' slots to the end")
	assert_true(names[r1.x].begins_with("p1_"), "player 1's slot")
	assert_true(names[r12.x].begins_with("p12_"), "player 12's")
	t.fill({"p3_pass": true, "ui_accept": true, "nonsense": true}, {"p3_pass": true}, PackedInt32Array([0, 0x4080]))
	assert_eq(t.held_actions(), {"ui_accept": true, "p3_pass": true}, "held (unknown actions left out)")
	assert_eq(t.counts[MwTickInput.index_of("p3_pass")], 1, "a press counted")
	assert_eq(t.sticks[1], 0x4080, "player 2's stick")
	var tick_input := MwTickInput.after(t)
	assert_eq(tick_input.held_actions(), {}, "the next tick holds nothing by itself")
	assert_eq(tick_input.counts, t.counts, "its counters carried on")
	for i in 256:
		tick_input.press(MwTickInput.index_of("p3_pass"))
	assert_eq(tick_input.counts[MwTickInput.index_of("p3_pass")], 1, "counters wrap at 256")


func test_the_stream_round_trips_as_bytes() -> void:
	var original := MwInputStream.new()
	original.first_tick = 41
	var before: MwTickInput = null
	for k in 50:
		var t := MwTickInput.after(before)
		var held := {}
		if k % 7 < 3:
			held["p1_move_up"] = true
		if k % 11 == 0:
			held["p12_ui_back"] = true
		t.fill(held, {"p2_wrist_shot": true} if k % 5 == 0 else {}, PackedInt32Array([k * 3 & 0xFFFF]))
		original.append(t)
		before = t
	var stream := MwInputStream.from_bytes(original.to_bytes())
	assert_not_null(stream)
	assert_eq(stream.first_tick, 41)
	assert_eq(stream.last_tick(), 90)
	for k in range(41, 91):
		assert_true(stream.at(k).equals(original.at(k)), "tick %d" % k)
	assert_null(MwInputStream.from_bytes(PackedByteArray([1, 2, 3])), "not a stream")
	assert_lt(original.to_bytes().size(), 50 * 20, "delta-coded: only the changes")


func _router(clock: MwPassClock = null) -> MwRouter:
	var host := Node.new()
	add_child_autofree(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var r := MwRouter.new(host, fader, clock)
	r.factory = func(_id: Variant) -> MwScreen:
		var sc := MwScreen.new()
		return sc
	return r


func test_recording_and_playing_give_the_same_frames() -> void:
	var r := _router()
	var src := Scripted.new()
	src.router = r
	src.plan = {1: {"held": {"ui_accept": true}}, 2: {}, 3: {"taps": {"p2_pass": true}},
			4: {"held": {"p1_move_left": true}}, 5: {"held": {"p1_move_left": true}}}
	var rec := MwStreamInput.new(null, src)
	rec.attach(r)
	var frames := []
	r.pass_ended.connect(func(_b: Dictionary) -> void: frames.append(r._frame.pressed.duplicate()))
	r.adopt(MwScreen.new())
	for i in 6:
		r.step()
	assert_eq(rec.stream.first_tick, 1)
	assert_eq(rec.stream.last_tick(), 6, "a tick captured each tick")
	# the stream played into a fresh router: the same frames
	var playback_router := _router(MwPassClock.streamed(MwInputStream.from_bytes(rec.stream.to_bytes())))
	var play := MwStreamInput.new(playback_router.clock.stream)
	play.attach(playback_router)
	var frames2 := []
	playback_router.pass_ended.connect(func(_b: Dictionary) -> void: frames2.append( \
			playback_router._frame.pressed.duplicate()))
	playback_router.adopt(MwScreen.new())
	var n := 0
	while playback_router.step():
		n += 1
	assert_eq(n, 6, "every tick of the stream, then it holds")
	assert_eq(playback_router.tick, 6)
	assert_false(playback_router.step(), "still held: no tick past the stream")
	assert_eq(playback_router.tick, 6)
	assert_eq(frames2, frames, "the same presses each pass")
	assert_true(frames[3].has("p2_pass"), "a tap between samples is seen (its counter moved)")


## The shot heights (MwSettings.shot_heights) in the stream: captured from
## the source as it gave them (MwTickInput.heights), coded on disk (format 2:
## their changes), played back to the frames; a format 1 stream (none)
## reads with every height the D-pad's.
func test_shot_heights_are_recorded_and_played() -> void:
	var r := _router()
	var src := Scripted.new()
	src.router = r
	var hs := []
	hs.resize(MwVerbs.PLAYERS)
	hs.fill(-1)
	var h1 := hs.duplicate()
	h1[0] = 1
	h1[11] = 2
	var h2 := hs.duplicate()
	h2[6] = 0
	src.plan = {1: {"heights": h1}, 2: {"heights": h1}, 3: {}, 4: {"heights": h2}}
	var rec := MwStreamInput.new(null, src)
	rec.attach(r)
	var seen := []
	r.pass_ended.connect(func(_b: Dictionary) -> void: seen.append(r._frame.heights.duplicate()))
	r.adopt(MwScreen.new())
	for i in 5:
		r.step()
	assert_eq(rec.stream.at(1).heights[0], MwTickInput.height_code(1), "player 1's HIGH SHOT")
	assert_eq(rec.stream.at(1).heights[11], MwTickInput.height_code(2), "player 12's LOW SHOT")
	assert_eq(rec.stream.at(3).heights.count(0), MwVerbs.PLAYERS, "none given: the D-pad's")
	assert_true(seen.has(h1) and seen.has(h2), "the frames' heights as the source gave them")
	assert_true(seen.has([]), "every one the D-pad's: none (as a source without them)")
	var bytes := rec.stream.to_bytes()
	var back := MwInputStream.from_bytes(bytes)
	for k in range(1, 6):
		assert_true(back.at(k).equals(rec.stream.at(k)), "tick %d's heights on disk" % k)
	var playback_router := _router(MwPassClock.streamed(back))
	var play := MwStreamInput.new(playback_router.clock.stream)
	play.attach(playback_router)
	var seen2 := []
	playback_router.pass_ended.connect(func(_b: Dictionary) -> void: seen2.append( \
			playback_router._frame.heights.duplicate()))
	playback_router.adopt(MwScreen.new())
	while playback_router.step():
		pass
	assert_eq(seen2, seen, "played back: the same heights each pass")
	# format 1 (before the shot heights): no height events, read as before
	var plain := MwInputStream.new()
	var t := MwTickInput.new()
	t.fill({"p1_pass": true}, {}, PackedInt32Array())
	plain.append(t)
	var old := plain.to_bytes(2)             # (plan 40, S7: the writer of the formats before)
	old[5] = 1                               # the format's low byte
	var read := MwInputStream.from_bytes(old)
	assert_not_null(read, "a format 1 stream still reads")
	assert_true(read.at(1).equals(t))
	old[5] = 2
	assert_true(MwInputStream.from_bytes(old).at(1).equals(t), "a format 2 stream still reads")
	old[5] = 4
	assert_null(MwInputStream.from_bytes(old), "a format from the future doesn't")


func test_the_clock_holds_until_the_stream_confirms() -> void:
	var stream := MwInputStream.new()
	var r := _router(MwPassClock.streamed(stream))
	r.input = MwStreamInput.new(stream)
	(r.input as MwStreamInput).router = r
	r.adopt(MwScreen.new())
	assert_false(r.step(), "nothing confirmed: held")
	assert_eq(r.tick, 0)
	stream.append(MwTickInput.new())
	stream.append(MwTickInput.new())
	assert_true(r.step())
	assert_true(r.step())
	assert_false(r.step(), "two ticks confirmed, two run")
	assert_eq(r.tick, 2)
	assert_true(MwPassClock.realtime().ready(99), "realtime never holds")


func test_screen_changes_keep_their_tick_whatever_loading_takes() -> void:
	var entered := []
	for slow in [false, true]:
		var r := _router()
		r.factory = func(_id: Variant) -> MwScreen:
			if slow:
				OS.delay_msec(40)              # a slow load: the picture waits, not the timeline
			return MwScreen.new()
		var at := []
		r.screen_entered.connect(func(id: int, _v: int, tick: int, _p: int) -> void: at.append([id, tick]))
		r.adopt(MwScreen.new())
		for i in 100:
			if i == 10:
				r.go(3)
			if i == 60:
				r.go(4, {}, false)
			r.step()
		entered.append(at)
	assert_eq(entered[1], entered[0], "the same screens at the same ticks")


func test_the_router_steps_the_driver_model() -> void:
	if not need_rom():
		return
	var stream := MwInputStream.new()
	var r := _router(MwPassClock.streamed(stream))
	var audio := r.use_driver_model(rom)
	add_child_autofree(audio)
	assert_same(MwSound.driver, audio, "the game's sound calls reach the model")
	assert_null(audio.chips, "no chips: nothing rendered")
	r.adopt(MwScreen.new())
	var h := MwSound.play(0x1B)
	assert_true(MwSound.busy(h), "a voice playing, answered by the model")
	r.step()
	assert_eq(audio._tick, 0, "held: no driver tick either")
	for i in 30:
		stream.append(MwTickInput.new())
	while r.step():
		pass
	assert_eq(audio._tick, 30, "a driver tick each game tick")
	MwSound.driver = null


## Plan 40 (S7, one input tick): offline a tick is captured as the network
## captures a machine's players - every player's state and the shared menu
## verbs' through MwNetInput.capture - and gives the fields the old field by
## field capture gave; the stream keeps the states and stores them as they
## are (format 3), the network's statuses included.
func test_offline_is_captured_in_the_wires_form() -> void:
	var r := _router()
	var src := Scripted.new()
	src.router = r
	var hs := []
	hs.resize(MwVerbs.PLAYERS)
	hs.fill(-1)
	hs[2] = 1
	src.plan = {1: {"held": {"ui_accept": true, "p3_pass": true, "p12_ui_back": true}},
			2: {"held": {"p3_pass": true}, "taps": {"p2_wrist_shot": true, "ui_back": true}, "heights": hs},
			3: {"taps": {"p2_wrist_shot": true}}}
	var rec := MwStreamInput.new(null, src)
	rec.attach(r)
	r.adopt(MwScreen.new())
	for i in 4:
		r.step()
	# the field by field capture of the same ticks
	var before: MwTickInput = null
	for k in range(1, 4):
		var tick_plan: Dictionary = src.plan.get(k, {})
		var t := MwTickInput.after(before)
		t.fill(tick_plan.get("held", {}), tick_plan.get("taps", {}), PackedInt32Array(), tick_plan.get("heights", []))
		assert_true(rec.stream.at(k).equals(t), "tick %d: the same fields" % k)
		before = t
	var st: Array = rec.stream.at(2).states()
	assert_eq(st[1].size(), MwNetInput.TICK_SIZE, "players 1-12 as the wire has them")
	assert_true(MwNetInput.is_held(MwNetInput.player(st[1], 3), MwNetInput.index_of("pass")), "player 3's PASS")
	assert_eq(MwNetInput.height(MwNetInput.player(st[1], 3)), MwTickInput.height_code(1), "his HIGH SHOT")
	assert_eq(MwNetInput.counter(st[0], MwNetInput.index_of("ui_back")), 1, "the shared Menu Back")
	assert_eq(MwNetInput.counter(MwNetInput.player(st[1], 2), MwNetInput.index_of("wrist_shot")), 1)
	# format 3: the states as they are, back
	var bytes := rec.stream.to_bytes()
	assert_eq(bytes.decode_u8(5), 3, "format 3")
	var back := MwInputStream.from_bytes(bytes)
	for k in range(1, 5):
		assert_eq(back.at(k).states(), rec.stream.at(k).states(), "tick %d's states" % k)
		assert_true(back.at(k).equals(rec.stream.at(k)))
	# an online tick: the statuses ride in the states, P1's menu verbs are the shared ones
	var wire := MwNetInput.make_tick([MwNetInput.from_actions(MwNetInput.blank(), 1, {"p1_ui_accept": true}, {}),
			MwNetInput.with_status(MwNetInput.blank(), MwTickInput.LAGGING)])
	var online := MwInputStream.new()
	online.append(MwTickInput.from_wire(wire))
	var stream := MwInputStream.from_bytes(online.to_bytes())
	assert_eq(stream.at(1).away(), {2: MwTickInput.LAGGING}, "player 2's machine lagging, stored")
	assert_true(stream.at(1).held_actions().has("ui_accept"), "the host's P1 drives the shared menu verbs")
	var bad := bytes.duplicate()
	bad.encode_u8(9, bad.decode_u8(9) ^ 1)
	assert_null(MwInputStream.from_bytes(bad), "another wire's table: refused")


## Plan 40 (S7): offline play's live capture keeps only the tick before and
## this one, and lets the editors' own verbs (never in the stream) through.
func test_the_live_capture() -> void:
	var r := _router()
	var src := Scripted.new()
	src.router = r
	var local_verb: String = MwVerbs.local_verbs()[0]
	src.plan = {3: {"held": {local_verb: true, "p1_pass": true}, "taps": {local_verb: true}}}
	var live := MwStreamInput.live(src)
	live.attach(r)
	var seen := []
	r.pass_ended.connect(func(_b: Dictionary) -> void: seen.append([r._frame.held.duplicate(), \
			r._frame.pressed.duplicate()]))
	r.adopt(MwScreen.new())
	for i in 6:
		r.step()
	assert_true(live.stream.ticks.size() <= 2, "the tick before and this one")
	assert_eq(live.stream.last_tick(), r.tick)
	assert_true(seen.any(func(f: Array) -> bool: return f[0].has(local_verb) and f[0].has("p1_pass")),
			"the local verb held through, beside the stream's")
	assert_true(seen.any(func(f: Array) -> bool: return f[1].has(local_verb)), "and pressed")
	assert_eq(r._frame.state(1).size(), MwNetInput.SIZE, "the frame: a player's own state")


## Plan 40 (S7): offline play through the live capture gives every pass the
## frame the devices read directly gave (the held and newly pressed actions,
## the shot heights) - the same game, one form.
func test_the_live_capture_plays_as_the_devices_read_directly() -> void:
	var hs := []
	hs.resize(MwVerbs.PLAYERS)
	hs.fill(-1)
	hs[0] = 2
	var plan := {2: {"held": {"p1_move_up": true, "ui_accept": true}}, 3: {"held": {"p1_move_up": true},
			"taps": {"p2_pass": true}}, 5: {"taps": {"ui_back": true, "p3_check": true}, "heights": hs},
			6: {"held": {"p4_ui_left": true}}, 9: {"taps": {"p1_pass": true}}}
	var runs := []
	for live in [false, true]:
		var r := _router()
		var src := Scripted.new()
		src.router = r
		src.plan = plan
		if live:
			MwStreamInput.live(src).attach(r)
		else:
			r.input = src
		var frames := []
		r.pass_ended.connect(func(_b: Dictionary) -> void:
			frames.append([r._frame.held.duplicate(), r._frame.pressed.duplicate(), r._frame.heights.duplicate()]))
		r.adopt(MwScreen.new())
		for i in 12:
			r.step()
		runs.append(frames)
	assert_eq(runs[1], runs[0], "the same frames")
