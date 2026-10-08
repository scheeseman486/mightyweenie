extends GutTest
## The router: passes on the 60 Hz tick, fades, push/pop, bookkeeping.

var host: Node
var fader: MwScreenFader
var router: MwRouter
var events := []


class Probe extends MwScreen:
	var passes: Array = []
	var resumed := 0
	func _screen_pass(elapsed: int, _input: MwInputFrame) -> void:
		passes.append(elapsed)
	func _resume_screen() -> void:
		resumed += 1


func before_each() -> void:
	host = Node.new()
	add_child(host)
	fader = MwScreenFader.new()
	host.add_child(fader)
	router = MwRouter.new(host, fader)
	router.factory = func(_id: Variant) -> MwScreen: return Probe.new()
	events = []
	router.screen_entered.connect(func(id: int, visit: int, tick: int, prev: int) -> void: events.append(["enter", id, visit, tick, prev]))
	router.screen_resumed.connect(func(id: int, visit: int, tick: int) -> void: events.append(["resume", id, visit, tick]))


func after_each() -> void:
	host.queue_free()


func _probe(id: int) -> Probe:
	var p := Probe.new()
	p.screen_id = id
	return p


func _steps(n: int) -> void:
	for i in n:
		router.step()


func test_menus_pass_every_tick_and_the_rink_every_two() -> void:
	var menu := _probe(1)
	router.adopt(menu)
	_steps(10)
	assert_eq(menu.passes, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	var rink := _probe(4)
	router.stack.clear()
	router.adopt(rink)
	_steps(10)
	assert_eq(rink.passes, [2, 2, 2, 2, 2])


func test_go_fades_out_32_ticks_then_in() -> void:
	var title := _probe(0)
	router.adopt(title)
	_steps(3)
	router.go(1)
	_steps(31)
	assert_eq(title.passes.size(), 3, "no passes while fading out")
	assert_eq(router.current(), title, "still the old screen while covered")
	router.step()                  # 32nd tick: fully covered, swap
	var menu := router.current()
	assert_ne(menu, title)
	assert_eq(menu.screen_id, 1)
	assert_eq(menu.previous, 0)
	assert_true(fader.busy(), "fading in")
	_steps(32)
	assert_false(fader.busy())
	assert_eq(fader.coverage(), 0.0)
	assert_eq(events.back(), ["enter", 1, 1, 35, 0])


func test_go_without_fade_is_immediate() -> void:
	router.adopt(_probe(MwScreens.BOOT))
	router.go(0, {}, false)
	router.step()
	assert_eq(router.current_id(), 0)
	assert_eq(fader.coverage(), 0.0)


func test_push_and_pop_keep_the_screen_underneath() -> void:
	var stats := _probe(8)
	router.adopt(stats)
	_steps(5)
	router.push(9)
	_steps(33)
	var player_stats := router.current()
	assert_eq(player_stats.screen_id, 9)
	assert_eq(router.stack.size(), 2)
	assert_false(stats.visible)
	var before := stats.passes.size()
	_steps(30)
	assert_eq(stats.passes.size(), before, "the screen underneath gets no passes")
	router.pop()
	_steps(33)
	assert_eq(router.current(), stats)
	assert_true(stats.visible)
	assert_eq(stats.resumed, 1)
	assert_eq(stats.previous, -1, "a pushed screen doesn't change where the one under it came from")
	assert_eq(events.back()[0], "resume")
	assert_eq(events.back().slice(1, 3), [8, 1])
	_steps(3)
	assert_gt(stats.passes.size(), before)


func test_visits_and_history() -> void:
	router.adopt(_probe(14))
	for target in [8, 14, 8]:
		router.go(target, {}, false)
		_steps(1)
	assert_eq(router.history, [14, 8, 14, 8])
	assert_eq(router.current().visit, 2)
	assert_eq(router.current().previous, 14)


func test_replay_clock_uses_the_originals_passes() -> void:
	var records := [
		{"event": "screen", "screen": 4, "visit": 1, "tick": 100},
		{"screen": 4, "visit": 1, "pass": 0, "tick": 103, "elapsed": 3},
		{"screen": 4, "visit": 1, "pass": 1, "tick": 107, "elapsed": 4},
		{"screen": 4, "visit": 1, "pass": 2, "tick": 110, "elapsed": 3},
	]
	router.clock = MwPassClock.replay(records)
	var rink := _probe(4)
	router.adopt(rink)
	var ends := []
	router.pass_ended.connect(func(b: Dictionary) -> void: ends.append(int(b.tick)))
	_steps(12)
	assert_eq(rink.passes, [3, 4, 3])
	assert_eq(ends, [3, 7, 10])


func test_only_the_first_request_counts() -> void:
	router.adopt(_probe(14))
	router.go(8, {}, false)
	router.go(10, {}, false)
	router.step()
	assert_eq(router.current_id(), 8)


func test_fade_length_when_leaving() -> void:
	router.adopt(_probe(0))
	router.go(1, {}, true, 30)
	_steps(29)
	assert_eq(router.current_id(), 0)
	router.step()
	assert_eq(router.current_id(), 1, "a 30-tick fade-out, then the next screen")


func test_a_screen_can_fade_itself_in() -> void:
	router.adopt(_probe(MwScreens.BOOT))
	fader.cover()
	router.factory = func(_id: Variant) -> MwScreen:
		var p := Probe.new()
		p.fades_in_itself = true
		return p
	router.go(0, {}, false)
	router.step()
	assert_eq(router.current_id(), 0)
	assert_eq(fader.coverage(), 1.0, "left covered")
	assert_false(fader.busy())


func test_screens_get_the_session_and_the_fader() -> void:
	router.adopt(_probe(1))
	assert_eq(router.current().session, router.session)
	assert_eq(router.current().fader, fader)
