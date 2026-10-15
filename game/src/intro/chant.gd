class_name MwChant
extends RefCounted
## The crowd's chant at the match's opening (plan 33, docs/rink3d.md, The
## match's opening; owner: the We Will Rock You chant):
## the matchup's crowd sound (`$1B`, restarted whenever it stops) is one
## sample, one bar of stomp, stomp, clap. This keeps when it last started
## and how long it runs from start to start, so the crowd shader can jump on
## the stomps and shake on the clap (MwStands3D.chant).
##
## The beats are where the sample's sounds peak (seconds into it, measured
## from the ROM's sample: the stomps where its low band's envelope peaks,
## the clap where its high band's does; [method measure] does it again and
## test_chant keeps the two in step). The sample's length comes from the ROM
## at run time.

const SOUND := MwSoundIds.CHANT
## The stomps' thumps peak (s into the sample): the jumps land on them.
const STOMPS := [0.10, 0.51]
## The clap's burst peaks (s into the sample): the shake is at its widest.
const CLAP := 0.84
## The matchup restarts the sound the pass after the voice ends (`$B1FE`):
## about this long after the sample's end (s).
const RESTART := 2.0 / MwRouter.TICK_HZ

## The clock (s) the sound last started at (< 0: not yet), and the time
## before (< 0: none).
var started := -1.0
var _before := -1.0
## Seconds from one start to the next: the sample's length and the
## restart's, then as measured between starts.
var period := 1.55
## The bar now playing is the last (the line-up): the crowd stops chanting
## after its clap ([constant LAST_ENDS] s into it), before the next bar's
## first jump would leave.
var last := false
const LAST_ENDS := CLAP + 0.35
var _nominal := 1.55


func _init(rom: PackedByteArray = PackedByteArray()) -> void:
	if not rom.is_empty():
		var m := measure(rom, false)
		if m.has("length"):
			period = float(m["length"]) + RESTART
	_nominal = period


## The sound started (again) at clock [param at] (s).
func start(at: float) -> void:
	if started >= 0.0 and at > started and absf(at - started - _nominal) < 0.2:
		period = at - started                # (a start cut short or held up says nothing)
	_before = started
	started = at


## Seconds since the sound last started, at clock [param now] (< 0: none).
## A frame shown a little behind the clock, before the latest start, is in
## the bar before.
func time(now: float) -> float:
	if started >= 0.0 and now >= started:
		return now - started if not (last and now - started > LAST_ENDS) else -1.0
	if _before >= 0.0 and now >= _before:
		return now - _before
	return -1.0


## The chant's sample measured: {length (s), stomps: [s, s], clap: s}
## ([param beats] false: the length only). Its PCM as the driver plays it
## (MwSoundSamples), at its rate; the low band a 3 ms moving average, the
## high band what a 0.8 ms one leaves, their envelopes 50 ms moving
## averages of their sizes (a stomp of a whole crowd is no sharper); the
## stomps the low envelope's highest points in 0-0.3 s and 0.3-0.7 s, the
## clap the high one's in 0.7-1.1 s.
static func measure(rom: PackedByteArray, beats := true) -> Dictionary:
	var smp := MwSoundSamples.new(rom)
	var sample := smp.by_sound_id(SOUND)
	if sample < 0:
		return {}
	var pcm := smp.decode(sample)
	var rate := smp.desc(sample).rate()
	var out := {"length": pcm.size() / rate}
	if not beats:
		return out
	var x := PackedFloat32Array()
	x.resize(pcm.size())
	for i in pcm.size():
		x[i] = float(pcm[i]) - 128.0
	var low := _smooth(x, int(rate * 0.003))
	var high := PackedFloat32Array()
	high.resize(x.size())
	var fine := _smooth(x, int(rate * 0.0008))
	for i in x.size():
		high[i] = absf(x[i] - fine[i])
		low[i] = absf(low[i])
	var low_env := _smooth(low, int(rate * 0.05))
	var high_env := _smooth(high, int(rate * 0.05))
	out["stomps"] = [_peak(low_env, rate, 0.0, 0.3), _peak(low_env, rate, 0.3, 0.7)]
	out["clap"] = _peak(high_env, rate, 0.7, 1.1)
	return out


## A centred moving average of [param n] values.
static func _smooth(v: PackedFloat32Array, n: int) -> PackedFloat32Array:
	n = maxi(n, 1)
	var out := PackedFloat32Array()
	out.resize(v.size())
	var acc := 0.0
	var half := n / 2
	for i in v.size() + half:
		if i < v.size():
			acc += v[i]
		if i - n >= 0:
			acc -= v[i - n]
		var c := i - half
		if c >= 0 and c < v.size():
			out[c] = acc / n
	return out


## The time (s) of [param env]'s highest point between [param a] and
## [param b] (s).
static func _peak(env: PackedFloat32Array, rate: float, a: float, b: float) -> float:
	var i0 := int(a * rate)
	var i1 := mini(int(b * rate), env.size())
	var best := i0
	for i in range(i0, i1):
		if env[i] > env[best]:
			best = i
	return best / rate
