extends GutTest
## Plan 36: MwPassPacer lays a pass's predicted 68000 work on the 60 Hz
## VBlanks as the original's rink loop does (the handlers, the DMA queue
## wait, the tick wait, the visit's fade-in), and MwPassCost's models have
## the fitted weights' shapes (docs/re/timing.md "Pass load").

const F := MwPassCost.FRAME_MCLK      # master clocks a frame: the pacer's units
const C := MwPassCost.MCLK            # master clocks a 68000 cycle


## A pass's work: [param before] etc. in frames (rounded to master clocks).
func _work(before: float, ru := 0.0, after := 0.0, rows := 0, words := 0) -> Dictionary:
	return {"before": int(before * F), "rink_update": int(ru * F), "after": int(after * F), "rows_words": rows,
			"words": words}


## A pacer after a reset, at its first pass (2 ticks), the pass [param w] begun.
func _started(w: Dictionary, first := false) -> MwPassPacer:
	var pacer := MwPassPacer.new()
	assert_false(pacer.vblank(0), "a pass after the resync's 2 ticks")
	assert_true(pacer.vblank(0))
	pacer.begin(w, first)
	return pacer


## VBlanks until the next pass starts.
func _elapsed(pacer: MwPassPacer, sound := 0, limit := 30) -> int:
	for i in limit:
		if pacer.vblank(sound):
			assert_eq(pacer.last_elapsed, i + 1)
			return i + 1
	return -1


func test_weights_fit_the_feature_vectors() -> void:
	assert_eq(MwPassCostWeights.PLAYERS.size(), 2 * MwPassCost.PLAYER_FEATURES)
	assert_eq(MwPassCostWeights.TEAMS.size(), MwPassCost.PPHASES.size() + 2)
	assert_eq(MwPassCostWeights.PHASE_COST.size(), 5 + 6 + MwPassCost.PHASES.size() + 2)
	assert_eq(MwPassCostWeights.RINK_UPDATE.size(), 6 + MwPassCost.OBJECT_KINDS + 1)
	assert_eq(MwPassCostWeights.CLOCK.size(), 7)
	assert_eq(MwPassCostWeights.A_REST.size(), 7 + MwPassCost.OBJECT_KINDS + MwPassCost.PPHASES.size() + 1)
	assert_eq(MwPassCostWeights.B_REST.size(), 1 + MwPassCost.PPHASES.size() + 2)
	for w in [MwPassCostWeights.DRAW_A, MwPassCostWeights.DRAW_B, MwPassCostWeights.DRAW_PUCK,
			MwPassCostWeights.DRAW_RINK, MwPassCostWeights.DRAW_PORTRAIT]:
		assert_eq(w.size(), 7)
	assert_eq(MwPassCostWeights.SOUND.size(), MwSound68k.Work.COUNT + 1)


## A pass in play: both teams' twelve on the ice, ten on the screen, a
## carrier; its cycles land where the recordings' do (3-4 frames).
func test_a_pass_in_play_costs_three_to_four_frames() -> void:
	var players := []
	for t in 2:
		for i in 6:
			var on := 1 if i < 5 else 0
			players.append([t, on, 5, 5, 1 if i == 5 else 0, 1 if t == 0 and i == 0 else 0, 0,
					1 if t == 0 and i == 0 else 0,
					0, 1 if i == 2 else 0, 0, -1, 0])
	var sec := [12, 6, 12, 1, 8, 40]
	var f := {"e": 4, "phase": 0, "phase_end": 0, "players": players, "window": [0, 0, 0, 0, 0],
			"draw_phase": [0, 0, 0, 0, 0, 0], "draw_team_a": sec, "draw_team_b": sec, "draw_puck": [1, 1, 1, 0, 0, 2],
			"draw_rink": [10, 6, 6, 0, 0, 30], "draw_portrait": [0, 0, 0, 0, 0, 0], "rows": 1, "objects": 0,
			"hazards": [2, 0, 0, 0], "teams": [0, 0], "nets": [1, 1], "kinds": [0, 0, 0, 0, 0, 0, 0, 0],
			"cam": [2, 3], "puck0": [1, 0, 0, 0], "replay": 1, "crowd": 50}
	var w := MwPassCost.work(f, [3, 6, 0, 0, 0])
	var total := float(w["before"]) + float(w["rink_update"]) + float(w["after"])
	assert_between(total, 2.5 * MwPassCost.FRAME, 4.5 * MwPassCost.FRAME, "%d cycles" % total)
	var m := MwPassCost.work_mclk(f, [3, 6, 0, 0, 0])
	assert_eq(typeof(m["before"]), TYPE_INT, "the pacer's work in integer master clocks")
	assert_almost_eq(float(m["before"]), float(w["before"]) * C, 0.5)
	assert_gt(float(w["before"]), float(w["after"]), "the team updates and the pads outweigh the draws")
	assert_eq(w["rows_words"], 64, "one plane B row")
	assert_eq(w["words"], 16 * (8 + 8) + 4 * (12 + 12 + 1 + 10))
	f["rows"] = 34
	assert_eq(MwPassCost.work(f, null)["rows_words"], 2048, "a full redraw")


func test_handler_cost() -> void:
	assert_almost_eq(MwPassCost.handler(0, false, 0.0), MwPassCost.H_BASE + MwPassCost.H_QUEUE + MwPassCost.H_FADE_IDLE,
			0.01)
	assert_almost_eq(MwPassCost.handler(1000, false, 0.0) - MwPassCost.handler(0, false, 0.0), 5806.0, 0.01,
			"per word drained")
	assert_almost_eq(MwPassCost.handler(0, true, 0.0) - MwPassCost.handler(0, false, 0.0), 46390.0, 0.01,
			"a fade running")
	var idle := PackedInt32Array()
	idle.resize(MwSound68k.Work.COUNT)
	var busy := idle.duplicate()
	busy[MwSound68k.Work.COPY] = 1
	assert_gt(MwPassCost.sound_cycles(busy), MwPassCost.sound_cycles(idle) + 2000.0, "a batch copied to the Z80")
	for words in [0, 64, 1000, 2048]:
		for fade in [false, true]:
			assert_almost_eq(float(MwPassCost.handler_mclk(words, fade, 0)), MwPassCost.handler(words, fade, 0.0) * C,
					1.0,
					"the pacer's integer handler")


func test_elapsed_counts_the_vblanks_a_pass_spans() -> void:
	var pacer := _started(_work(2.5))
	assert_eq(_elapsed(pacer), 2, "2.5 frames of work from a frame's start: two VBlanks")
	# the next pass starts where this one ended, 60 % into its frame
	pacer.begin(_work(1.4))
	assert_eq(_elapsed(pacer), 2, "1.4 frames from late in a frame: two")
	assert_eq(_elapsed(_started(_work(1.4))), 1, "from a frame's start: one")


func test_tick_wait() -> void:
	var pacer := _started(_work(0.01))
	assert_eq(_elapsed(pacer), 1, "a pass with no VBlank in it waits for the next")


func test_dma_queue_wait_after_queued_rows() -> void:
	var w := _work(0.2, 5000.0 / MwPassCost.FRAME, 0.98)
	assert_eq(_elapsed(_started(w)), 1, "no rows: straight on")
	w["rows_words"] = 64
	assert_eq(_elapsed(_started(w)), 2, "rows queued: the pass waits for the VBlank to drain them")


func test_handlers_slow_the_pass() -> void:
	var w := _work(2.9)
	assert_eq(_elapsed(_started(w), 0), 2)
	assert_eq(_elapsed(_started(w), 20000 * C), 3, "a busy sound driver costs a tick")


func test_fade_in_after_the_first_pass() -> void:
	var w := _work(1.6)
	var plain := _started(w)
	var faded := _started(w, true)
	var a := 0
	var b := 0
	for i in 6:
		a += _elapsed(plain)
		plain.begin(w)
		b += _elapsed(faded)
		faded.begin(w)
	assert_gt(b, a, "the fade engine's VBlanks slow the visit's first passes")


func test_reset_resyncs() -> void:
	var pacer := _started(_work(2.5))
	pacer.reset()
	assert_false(pacer.vblank(0))
	assert_true(pacer.vblank(0), "2 ticks after a reset (the pause menu)")


func test_snapshot_restores_the_timeline() -> void:
	var w := _work(1.7, 0.02, 0.9, 64, 300)
	var original := _started(w, true)
	assert_false(original.vblank(0))
	var pacer := MwPassPacer.new()
	pacer.restore(original.snapshot())
	assert_eq(pacer.snapshot(), original.snapshot())
	for i in 40:
		var ea := original.vblank(i * 997)
		assert_eq(pacer.vblank(i * 997), ea, "tick %d" % i)
		if ea:
			original.begin(w)
			pacer.begin(w)


## Plan 36 with plan 35's dead reckoning: [method MwPassPacer.predict] gives
## the passes the pacer itself makes when every pass to come does the same
## work - the first counted from the pass in flight's start
## ([method MwPassPacer.since_pass]) - and leaves the pacer as it was.
func test_predict_is_the_pacers_own_passes_on_a_copy() -> void:
	var w := _work(1.3, 0.05, 1.1, 64, 200)
	var pacer := _started(w, true)
	assert_eq(pacer.since_pass(), 0, "the pass just started")
	assert_false(pacer.vblank())
	assert_eq(pacer.since_pass(), 1, "a tick into it")
	var before := pacer.snapshot()
	var predicted := pacer.predict(40, w)
	assert_eq(pacer.snapshot(), before, "the pacer untouched")
	assert_eq(pacer.since_pass(), 1)
	assert_gt(predicted.size(), 5, "passes predicted: %s" % str(predicted))
	var real := PackedInt32Array()
	var since := 1
	for i in 40:
		since += 1
		if pacer.vblank():
			real.append(since)
			assert_eq(pacer.last_elapsed, since, "the router's elapsed ticks")
			since = 0
			pacer.begin(w)
	assert_eq(predicted, real, "the same passes")
	var fresh := MwPassPacer.new()
	assert_eq(fresh.since_pass(), 0)
	assert_eq(fresh.predict(7, {}), PackedInt32Array([2, 2, 2]), "no work yet: the resync's 2 ticks")
	assert_eq(pacer.predict(0, w), PackedInt32Array(), "no lead: no pass")
