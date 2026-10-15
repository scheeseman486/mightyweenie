extends GutTest
## Plan 45 (docs/style.md D8, stability M4): what a prediction swaps into
## the game's globals is put back whatever happens, and an online match
## whose frame stops on a script error is left rather than frozen. The
## reckoning's own (MwNetReckoning.restore_left) is test_net_reckoning's: it
## needs a match.


## A stand-in for MwNetMatch as MwRouter.drive drives it: [member fail] makes
## its frame stop on a script error (an index out of range) - frame returns
## false then (a typed function's default), the match not over.
class FakeMatch:
	extends RefCounted
	var fail := false
	var going := true
	var frames := 0
	var abandoned := 0

	func frame(_now_ms: int) -> bool:
		frames += 1
		if fail:
			var none: Array = []
			return none[frames]                # (the error: frame stops here)
		return going

	func over() -> bool:
		return not going

	func abandon() -> void:
		abandoned += 1
		going = false


var _was := {}


func before_each() -> void:
	_was = {"driver": MwSound.driver, "quiet": MwSound.quiet, "predicting": MwSound.predicting,
			"key": MwSound.predict_key, "due": MwSound.predict_due, "state": MwSound.snapshot_state()}


func after_each() -> void:
	MwSound.end_swap()
	MwSound.driver = _was["driver"]
	MwSound.quiet = _was["quiet"]
	MwSound.predicting = _was["predicting"]
	MwSound.predict_key = _was["key"]
	MwSound.predict_due = _was["due"]
	MwSound.restore_state(_was["state"])


## The globals a swap changes, changed as a prediction changes them.
func _swap_in(driver: MwAudio) -> void:
	MwSound.driver = driver
	MwSound.quiet = not _was["quiet"]
	MwSound.predicting = true
	MwSound.predict_key = "ahead:99"
	MwSound.predict_due = 99


func _globals() -> Array:
	return [MwSound.driver, MwSound.quiet, MwSound.predicting, MwSound.predict_key, MwSound.predict_due]


func test_a_swap_ended_puts_everything_back() -> void:
	var before := _globals()
	var model := MwAudio.new()
	MwSound.begin_swap()
	_swap_in(model)
	MwSound.end_swap()
	assert_eq(_globals(), before)
	assert_false(MwSound.reset_swaps(), "nothing left open")
	model.free()


func test_a_swap_left_open_is_put_back_before_the_games_ticks() -> void:
	var before := _globals()
	var model := MwAudio.new()
	MwSound.begin_swap()
	_swap_in(model)                             # ... and the prediction stopped before its end_swap
	assert_true(MwSound.reset_swaps(), "the open swap found")
	assert_push_error("swap was left open")
	assert_eq(_globals(), before, "the game's globals back")
	assert_false(MwSound.reset_swaps(), "once")
	model.free()


func test_a_swap_begun_over_an_open_one_keeps_the_true_globals() -> void:
	var before := _globals()
	var model := MwAudio.new()
	MwSound.begin_swap()
	_swap_in(model)
	MwSound.begin_swap()                        # the next prediction (the last one stopped)
	assert_push_error("swap was left open")
	assert_eq(_globals(), before, "the open one put back first")
	_swap_in(model)
	MwSound.end_swap()
	assert_eq(_globals(), before, "and its own end puts back the game's, not the stopped one's")
	model.free()


func test_a_local_echos_swap_leaves_the_driver_alone() -> void:
	var model := MwAudio.new()
	MwSound.begin_swap(false)
	MwSound.quiet = true
	MwSound.driver = model                      # (a driver changed meanwhile is not the echo's to put back)
	MwSound.end_swap()
	assert_eq(MwSound.quiet, _was["quiet"])
	assert_same(MwSound.driver, model)
	model.free()


func test_the_local_echo_puts_back_what_it_swapped() -> void:
	var before := _globals()
	var inside := []
	MwLocalEcho.run(func() -> void: inside.append([MwSound.quiet, MwSound.predicting]))
	assert_eq(inside, [[true, true]], "quiet and predicting while it runs")
	assert_eq(_globals(), before, "as they were after")
	assert_false(MwSound.reset_swaps())


func test_models_left_lent_to_the_run_aheads_shadow_are_taken_back() -> void:
	var ra := MwNetRunAhead.new()
	var confirmed := MwRinkState.new()
	confirmed.crowd_life = MwCrowdLife.new(1)
	confirmed.bench_life = MwBenchLife.new(1)
	assert_false(ra.take_back_left(), "nothing lent")
	ra.lend(confirmed)                          # ... and the picture stopped before its take_back
	ra.run(null, [])                            # (no match: it runs nothing - but takes them back first)
	assert_push_error("left lent to the shadow")
	assert_eq([ra.shadow.crowd_life, ra.shadow.bench_life, ra.shadow.splatter], [null, null, null])
	assert_not_null(confirmed.crowd_life, "the match's own untouched")


# --- MwRouter.drive (stability M4) -------------------------------------------------------------------

func _router() -> MwRouter:
	var host := Node.new()
	add_child_autofree(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	return MwRouter.new(host, fader)


func test_a_driver_is_dropped_when_its_frame_says_so() -> void:
	var router := _router()
	var m := FakeMatch.new()
	router.driver = m
	assert_true(router.drive(0))
	assert_same(router.driver, m)
	m.going = false
	assert_false(router.drive(17))
	assert_null(router.driver, "the router its own again")
	assert_eq([m.frames, m.abandoned], [2, 0])
	assert_false(router.drive(34), "no driver: nothing")


func test_a_frame_stopped_by_an_error_leaves_the_match() -> void:
	var router := _router()
	var m := FakeMatch.new()
	m.fail = true
	router.driver = m
	assert_false(router.drive(0))
	assert_null(router.driver, "dropped - not kept on a stream nobody feeds")
	assert_eq(m.abandoned, 1, "the match left (its router, clock and input handed back)")
	assert_push_error("frame stopped on an error")
	for e in get_errors():
		e.handled = true                        # (the script error itself)
