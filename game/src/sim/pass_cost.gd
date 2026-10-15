class_name MwPassCost
extends RefCounted
## What a rink pass costs the original's 68000, in cycles, from its load
## features ([method MwPassLoad.features]; plan 36, docs/re/timing.md "Pass
## load"): linear models fitted on BlastEm load recordings
## ([MwPassCostWeights]), part by part as the rink loop `$F962` runs them:
##
## * before the DMA queue wait (`$148A8`): the clock's texts, the pads with
##   the 4-Way Play and `$95C8`, both team updates (per present player, on
##   or off the previous screen, by state, control, AI thinks; the teams'
##   own work), the puck, the objects, the rink update `$56EA` (plane B's
##   rows go into the DMA queue [constant RU_PRE] cycles in);
## * after it: the replay frame, the penalty timers, the puck rules, the
##   phase handler (window texts, its sprites), the draws (per piece, frame,
##   depth-sorted insert step and sprite tile cache upload), the queueing.
##
## [method handler] is the VBlank handler `$13F96` (the DMA queue drained,
## the fade engine, the sound driver: [method sound_cycles] from the
## driver's work that tick, [member MwSound68k.work]). [MwPassPacer] lays
## the parts and the handlers out on the 60 Hz VBlanks.
##
## Accuracy (held-out rink visits, against BlastEm): the pass's elapsed
## ticks exact on 84 % of passes and within one on 99.7 % (open loop, from
## each pass's measured start), the ticks of whole visits within 0.1 % (per
## run within about 2 %) with the sound driver at its mean; with the sound
## driver's work known 98 % (measured parts).

## Master clocks per 68000 cycle, per NTSC frame ([MwPassPacer]'s units:
## integers), and 68000 cycles per frame.
const MCLK := 7
const FRAME_MCLK := 896040
const FRAME := 896040.0 / 7.0
## Cycles into the rink update when plane B's rows go into the DMA queue.
const RU_PRE := 4110.0
## The rest of the pass before the wait / after it (loop glue, measured).
const A_GLUE := 114.0
const B_GLUE := 174.0
## The VBlank handler: entry, exit and `$14AD4`.
const H_BASE := 415.0
## `$14752`: the DMA queue drained, per word queued since the last VBlank.
const H_QUEUE := 523.0
const H_QUEUE_WORD := 5.806
## `$149F6`, the fade engine: idle, or a fade running (the visit's fade-in).
const H_FADE_IDLE := 3240.0
const H_FADE_RUNNING := 49630.0
## VBlanks the visit's fade-in runs after its first pass (`$C606`, 32 ticks
## with the last one cheap).
const FADE_VBLANKS := 31
## `$13DE8` (the sound driver's tick) on average, for runs without a driver
## and TICK RATE APPROXIMATED.
const SOUND_MEAN := 3684.0
const SOUND_MEAN_MCLK := 25788

## The player model's states, phases ([member MwRinkState.phase]) and on-screen counts.
const PSTATES := [0, 1, 2, 3, 4, 5, 8, 10, 14, 15, 20]
const PPHASES := [0, 1, 3, 4, 5, 8, 9, 10, 14]
## The phase handler model's phases.
const PHASES := [0, 1, 3, 5, 8, 9]
const OBJECT_KINDS := 23
const PLAYER_FEATURES := 14 + 11 + 9 + 13


static func _dot(w: Array, x: PackedFloat64Array) -> float:
	var total := 0.0
	for i in w.size():
		total += w[i] * x[i]
	return total


static func _b(c: bool) -> float:
	return 1.0 if c else 0.0


## Entries of [param a] equal to [param v] (numbers from JSON are floats).
static func _count(a: Array, v: int) -> float:
	var n := 0.0
	for x in a:
		if int(x) == v:
			n += 1.0
	return n


## One player's features (from [method MwPassLoad.features]' "players"
## entry [param a]) into [param acc]: the on-screen half or the off-screen.
static func add_player(acc: PackedFloat64Array, a: Array, f: Dictionary) -> void:
	var on := int(a[1])
	var o := 0 if on == 1 else PLAYER_FEATURES
	var hz: Array = f["hazards"]
	var v := PackedFloat64Array()
	v.resize(PLAYER_FEATURES)
	v[0] = 1.0
	v[1] = float(a[7])                  # controlled by a pad
	v[2] = _b(int(a[9]) > 0)            # thought this pass
	v[3] = float(a[9])                  # thinks
	v[4] = float(a[5])                  # carries the puck
	v[5] = float(a[4])                  # goalie
	v[6] = _b(int(a[0]) == 0)           # team A
	v[7] = float(f["e"])
	v[8] = float(a[8])                  # thinks soon (timer <= 0)
	v[9] = _b(int(a[11]) >= 0)          # armed
	for j in 4:
		v[10 + j] = _count(hz, j + 1)        # thin ice, pits, holes, mines
	var i := 14
	for st in PSTATES:
		v[i] = _b(int(a[6]) == st)
		i += 1
	for q in PPHASES:
		v[i] = _b(int(f["phase"]) == q)
		i += 1
	var shown := int(a[2]) + int(a[3])
	for j in 13:
		v[i] = _b(shown == j)
		i += 1
	for k in PLAYER_FEATURES:
		acc[o + k] += v[k]


static func _kinds(f: Dictionary) -> Array:
	var out := []
	var ks: Array = f["kinds"]
	for j in OBJECT_KINDS:
		out.append(_count(ks, j + 1))
	return out


static func _phases(f: Dictionary, table: Array) -> Array:
	var out := []
	for q in table:
		out.append(_b(int(f["phase"]) == q))
	return out


static func _vec(a: Array) -> PackedFloat64Array:
	var v := PackedFloat64Array()
	for x in a:
		v.append(float(x))
	return v


## The team updates: per player plus the teams' own work.
static func teams(f: Dictionary) -> float:
	var acc := PackedFloat64Array()
	acc.resize(2 * PLAYER_FEATURES)
	for a in f["players"]:
		add_player(acc, a, f)
	var own := _vec(_phases(f, PPHASES) + [float(f["players"].size()), 1.0])
	return _dot(MwPassCostWeights.PLAYERS, acc) + _dot(MwPassCostWeights.TEAMS, own)


## One draw part's cycles: the weights [param w] on its six counts [param sec] (a
## [code]draw_*[/code] entry of [method MwPassLoad.features]) and a constant term.
static func draw(sec: Array, w: Array) -> float:
	return _dot(w, _vec(sec.slice(0, 6) + [1.0]))


## The phase handler's cycles from the features [param f]: its window texts, its
## draws, the phase it ran in and whether the phase changed.
static func phase_handler(f: Dictionary) -> float:
	var win: Array = f["window"]
	var d: Array = f["draw_phase"]
	return _dot(MwPassCostWeights.PHASE_COST, _vec(win.slice(0, 5) + d.slice(0, 6) + _phases(f, PHASES)
			+ [_b(int(f["phase_end"]) != int(f["phase"])), 1.0]))


## The rink update's (`$56EA`) cycles from the features [param f]: plane B's rows
## (past 4: a full redraw), the objects (also counted apart in phases 0 and 1), the
## top net's style and the objects' kinds.
static func rink_update(f: Dictionary) -> float:
	var r := int(f["rows"])
	var full := r > 4
	var setup := int(f["phase"]) in [0, 1]
	var nets: Array = f["nets"]
	return _dot(MwPassCostWeights.RINK_UPDATE, _vec([0 if full else r, _b(full), f["objects"],
			float(f["objects"]) * _b(setup), _b(int(nets[0]) == 0), _b(int(nets[0]) == 2)] + _kinds(f) + [1.0]))


## The clock's texts ([param clock_counts]: [method MwPassLoad._window]'s counts
## for the pass start's clock, null: none known).
static func clock(clock_counts: Variant) -> float:
	var x := [0, 0, 0, 0, 0, 1.0, 1.0]
	if clock_counts != null:
		var w: Array = clock_counts
		x = w.slice(0, 5) + [_b(int(w[0]) == 0), 1.0]
	return _dot(MwPassCostWeights.CLOCK, _vec(x))


## The rest of the pass before the DMA queue wait, from the features [param f]: the
## puck at the segment's start, the objects and their kinds, the elapsed ticks, the
## phase.
static func rest_before(f: Dictionary) -> float:
	var puck_state: Array = f["puck0"]
	var fl := int(puck_state[0])
	return _dot(MwPassCostWeights.A_REST, _vec([f["objects"], fl & 1, (fl >> 1) & 1, _b(int(puck_state[1]) > 0),
			_b(int(puck_state[2]) > 0), _b(int(puck_state[3]) > 0), f["e"]] + _kinds(f) + _phases(f, PPHASES) + [1.0]))


## The rest of the pass after the DMA queue wait, from the features [param f]: the
## replay recording on, the phase and whether it changed.
static func rest_after(f: Dictionary) -> float:
	return _dot(MwPassCostWeights.B_REST, _vec([_b(int(f["replay"]) != 0)] + _phases(f, PPHASES)
			+ [_b(int(f["phase_end"]) != int(f["phase"])), 1.0]))


## The pass's work for [MwPassPacer]: {"before": cycles up to the DMA queue
## wait (the rink update's last [code]rink_update - RU_PRE[/code] cycles
## after the rows are queued: "rink_update"), "after": cycles after the
## wait, "rows_words": words the rink update queues, "words": words queued
## after the wait (tile uploads, the sprite list)}. [param clock_counts]:
## see [method clock].
static func work(f: Dictionary, clock_counts: Variant) -> Dictionary:
	var before := teams(f) + clock(clock_counts) + rest_before(f) + A_GLUE
	var ru := rink_update(f)
	var after := phase_handler(f) + rest_after(f) + B_GLUE
	after += draw(f["draw_team_a"], MwPassCostWeights.DRAW_A) + draw(f["draw_team_b"], MwPassCostWeights.DRAW_B)
	after += draw(f["draw_puck"], MwPassCostWeights.DRAW_PUCK) + draw(f["draw_rink"], MwPassCostWeights.DRAW_RINK)
	after += draw(f["draw_portrait"], MwPassCostWeights.DRAW_PORTRAIT)
	var rows := int(f["rows"])
	var tiles := 0
	var adds := 0
	for sec in ["draw_phase", "draw_team_a", "draw_team_b", "draw_puck", "draw_rink", "draw_portrait"]:
		tiles += int(f[sec][4])
		adds += int(f[sec][0])
	return {"before": maxf(before, 0.0), "rink_update": maxf(ru, 0.0), "after": maxf(after, 0.0),
			"rows_words": 2048 if rows > 4 else 64 * rows, "words": 16 * tiles + 4 * adds}


## `$13F96`'s cycles: [param words] queued since the last VBlank, a fade
## running ([param fade]), the sound driver's [param sound] cycles.
static func handler(words: int, fade: bool, sound: float) -> float:
	return H_BASE + H_QUEUE + H_QUEUE_WORD * words + (H_FADE_RUNNING if fade else H_FADE_IDLE) + sound


## [method handler] in master clocks, in integers ([MwPassPacer]):
## [param sound] in master clocks.
static func handler_mclk(words: int, fade: bool, sound: int) -> int:
	return 6566 + words * 40642 / 1000 + (347410 if fade else 22680) + sound


## [method work] in master clocks (integers, rounded) for [MwPassPacer].
static func work_mclk(f: Dictionary, clock_counts: Variant) -> Dictionary:
	var w := work(f, clock_counts)
	for k in ["before", "rink_update", "after"]:
		w[k] = int(roundf(float(w[k]) * MCLK))
	return w


## `$13DE8`'s cycles for the driver's work counts of one tick
## ([member MwSound68k.work]) (ORIGINAL only: APPROXIMATED takes the mean).
static func sound_cycles(work_counts: PackedInt32Array) -> float:
	var w := MwPassCostWeights.SOUND
	var cycles: float = w[w.size() - 1]
	for i in mini(work_counts.size(), w.size() - 1):
		cycles += w[i] * work_counts[i]
	return maxf(cycles, 0.0)
