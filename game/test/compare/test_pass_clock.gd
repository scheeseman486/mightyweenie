extends GutTest
## MwPassClock: realtime pass lengths (approved model) and exact replay of a
## recorded pass sequence.


func _run(clock: MwPassClock, screen: int, from_tick: int, ticks: int) -> Array:
	clock.screen_entered(screen, from_tick)
	var out: Array = []
	for t in range(from_tick, from_tick + ticks):
		for b in clock.due(t):
			out.append(b)
	return out


func test_realtime_menus_every_tick() -> void:
	var b := _run(MwPassClock.realtime(), 1, 100, 10)
	assert_eq(b.size(), 9)
	for x in b:
		assert_eq(x.elapsed, 1)
	assert_eq(b[0].tick, 101)
	assert_eq(b[0].pass, 0)
	assert_eq(b[-1].pass, 8)


func test_realtime_gameplay_every_second_tick() -> void:
	var b := _run(MwPassClock.realtime(), 5, 0, 21)
	assert_eq(b.size(), 10)
	for x in b:
		assert_eq(x.elapsed, 2)
		assert_eq(int(x.tick) % 2, 0)


func test_realtime_table_is_a_setting() -> void:
	var clock := MwPassClock.realtime({5: 3})
	assert_eq(clock.pass_length(5), 3)
	assert_eq(clock.pass_length(1), 1)


func test_replay_reproduces_recorded_passes() -> void:
	var records := [
		{"event": "screen", "screen": 4, "visit": 1, "tick": 5000},
		{"screen": 4, "visit": 1, "pass": 0, "tick": 5002, "elapsed": 1},
		{"screen": 4, "visit": 1, "pass": 1, "tick": 5006, "elapsed": 4},
		{"screen": 4, "visit": 1, "pass": 2, "tick": 5009, "elapsed": 3},
		{"event": "screen", "screen": 4, "visit": 2, "tick": 6000},
		{"screen": 4, "visit": 2, "pass": 0, "tick": 6007, "elapsed": 7},
	]
	var clock := MwPassClock.replay(records)
	# our ticks start elsewhere: boundaries keep their offsets from the entry
	var first := _run(clock, 4, 100, 20)
	var got := []
	for b in first:
		got.append([b.tick, b.elapsed, b.pass, b.visit])
	assert_eq(got, [[102, 1, 0, 1], [106, 4, 1, 1], [109, 3, 2, 1]])
	var second := _run(clock, 4, 300, 20)
	assert_eq(second.size(), 1)
	assert_eq([second[0].tick, second[0].elapsed, second[0].visit], [307, 7, 2])


func test_resume_continues_a_visit() -> void:
	var records := [
		{"event": "screen", "screen": 8, "visit": 1, "tick": 0},
		{"screen": 8, "visit": 1, "pass": 0, "tick": 1, "elapsed": 1},
		{"event": "screen", "screen": 9, "visit": 1, "tick": 2},
		{"screen": 9, "visit": 1, "pass": 0, "tick": 3, "elapsed": 1},
		{"event": "resume", "screen": 8, "visit": 1, "tick": 5},
		{"screen": 8, "visit": 1, "pass": 1, "tick": 6, "elapsed": 5},
	]
	var clock := MwPassClock.replay(records)
	clock.screen_entered(8, 0)
	assert_eq(clock.due(1).size(), 1)
	clock.screen_entered(9, 2)
	assert_eq(clock.due(3)[0].screen, 9)
	clock.resume(8, 1)
	var b := clock.due(6)
	assert_eq([b[0].screen, b[0].pass, b[0].elapsed], [8, 1, 5])
