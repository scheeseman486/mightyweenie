class_name MwCrowdLife
extends RefCounted
## The crowd's life (plans 30-31): what drives the 3D crowd's movement and,
## with ENHANCE AUDIO, the crowd's noise. A small model stepped with the
## game's passes ([method step], MwRinkUpdate: live play only, so the
## pause and everything that stops the passes stop it) - repeatable: the
## same seed and the same passes give the same crowd. What it is at a pass
## ([method snapshot]: the seed, its clock, its liveliness, the lead, the
## wave) is all the crowd shader needs to draw every fan (each fan's own
## pace and moments come from the seed and his seat: rink3d_crowd), so a
## replay keeps that snapshot with each frame (MwReplay3D) instead of the
## fans' movements, and the replay's crowd moves, and sounds, as it did.
##
## * Liveliness follows the game's crowd level (MwRinkState.crowd: 50 calm,
##   +250 a shot or a hard hit, +1000 a goal, capped at 1250, -4 or -5 a
##   tick): from [constant LIFE_CALM] up to 1 at [constant LEVEL_FULL],
##   quick to rise, slow to settle.
## * The leading team's fans livelier (more with a bigger lead), the
##   trailing team's calmer (the shader, from [code]lead[/code] and
##   [code]lift[/code]).
## * In a quiet spell of live play a wave may go round the stands (its own
##   random numbers, from the seed), dying down when the play wakes the
##   crowd.
## * The noise ([method sound_level]): the liveliness as a crowd level
##   (0-1000, as the original sends `crowd_level`), plus a cheer while a
##   wave goes round.
## Presentation only: nothing of the game's state or random numbers.
## Plan 35: but its noise reaches the sound driver (whose answers the game
## waits on), so it is the same on every machine: its seed from the session
## (MwSession.STREAM_CROWD), and only IEEE's exactly rounded arithmetic
## (+ - * / and square roots) - its exponentials are [method det_exp], not
## the platform's maths library.

const TICKS_PER_S := float(MwRouter.TICK_HZ)
## The game's crowd level at which the crowd is at its liveliest, and its calm.
const LEVEL_CALM := 50
const LEVEL_FULL := 750
## The crowd's liveliness when calm (a few fans hop now and then).
const LIFE_CALM := 0.12
## Seconds the liveliness takes to rise (most of the way) and to settle.
const LIFE_RISE := 0.1
const LIFE_SETTLE := 3.0
## Waves: below this level the stands are quiet; after this long quiet one
## may start, with this chance a second (owner, 2026-10-09: 12% -> 22%); a
## lap takes this long; one or two laps; fading in and out over this long.
const WAVE_QUIET := 120
const WAVE_AFTER := 6.0
const WAVE_CHANCE := 0.22
const WAVE_LAP := 9.0
const WAVE_FADE := 1.5
## The leading team's fans: this much livelier, more with a bigger lead.
const LEAD_LIFT := 0.25
const LEAD_LIFT_PER_GOAL := 0.1
const LEAD_LIFT_MAX := 0.6
## The noise: a wave's cheer at its height (crowd level units).
const WAVE_CHEER := 200
## ln(1 - WAVE_CHANCE), written out (plan 35: no platform logarithm).
const LN_NO_WAVE := -0.2484613592984996
## The clock wraps after this many ticks (an hour).
const WRAP := 216000

## Whether the crowd's noise follows its life (ENHANCE AUDIO;
## MwSettings.apply_audio). Off: the original's, the game's crowd level.
static var drives_sound := true

var crowd_seed := 0
## The crowd's clock (ticks), its liveliness (0..1).
var ticks := 0
var life := LIFE_CALM
## The lead (-1 team B's, 0 none, 1 team A's) and how much livelier its fans are.
var lead := 0
var lift := 0.0
## The wave: seconds into it (< 0 none), where it started (radians round
## the rink, as the crowd shader measures), which way, how many laps.
var wave_t := -1.0
var wave_from := 0.0
var wave_dir := 1.0
var wave_laps := 1
var _quiet := 0.0
var _wave_end := 0.0             # when the wave started fading out early (s into it; 0 not)
var _rng := RandomNumberGenerator.new()


func _init(seed_ := 0) -> void:
	crowd_seed = seed_
	_rng.seed = seed_


## A pass of [param e] ticks: the game's crowd level [param level], the
## teams' goals [param score] (A, B), whether it is live play
## ([param live]: a wave may start).
func step(e: int, level: int, score: Vector2i, live: bool) -> void:
	var dt := e / TICKS_PER_S
	ticks = (ticks + e) % WRAP
	var target := lerpf(LIFE_CALM, 1.0, clampf(float(level - LEVEL_CALM) / (LEVEL_FULL - LEVEL_CALM), 0.0, 1.0))
	var tau := LIFE_RISE if target > life else LIFE_SETTLE
	if dt > 0.0:
		life = lerpf(life, target, 1.0 - det_exp(-dt / tau))
	lead = signi(score.x - score.y)
	lift = lead_lift(absi(score.x - score.y))
	_wave_step(dt, level, live)


## What drives the crowd's look and noise now: {seed, ticks, life, lead,
## lift, wave_angle, wave_amp} (plain data: a replay keeps it with each
## frame).
func snapshot() -> Dictionary:
	return {"seed": crowd_seed, "ticks": ticks, "life": life, "lead": lead, "lift": lift,
			"wave_angle": wave_angle(), "wave_amp": wave_amp()}


## How much livelier the leading team's fans are with a lead of [param goals].
static func lead_lift(goals: int) -> float:
	if goals <= 0:
		return 0.0
	return minf(LEAD_LIFT + LEAD_LIFT_PER_GOAL * (goals - 1), LEAD_LIFT_MAX)


## Where the wave is (radians round the rink, as the crowd shader measures;
## not wrapped, so it blends).
func wave_angle() -> float:
	return wave_from + wave_dir * TAU * maxf(wave_t, 0.0) / WAVE_LAP


## The wave's strength now (0 none).
func wave_amp() -> float:
	if wave_t < 0.0:
		return 0.0
	var length := wave_laps * WAVE_LAP
	var a := minf(wave_t / WAVE_FADE, (length - wave_t) / WAVE_FADE)
	if _wave_end > 0.0:
		a = minf(a, 1.0 - (wave_t - _wave_end) / WAVE_FADE)
	return clampf(a, 0.0, 1.0)


## Starts a wave now (and tests): from a place, a way and a number of laps
## its random numbers pick.
func start_wave() -> void:
	wave_t = 0.0
	_wave_end = 0.0
	wave_from = _rng.randf() * TAU
	wave_dir = -1.0 if _rng.randf() < 0.5 else 1.0
	wave_laps = 1 + _rng.randi_range(0, 1)


func _wave_step(dt: float, level: int, live: bool) -> void:
	_quiet = _quiet + dt if level < WAVE_QUIET and live else 0.0
	if wave_t >= 0.0:
		wave_t += dt
		if _wave_end == 0.0 and level >= WAVE_QUIET:
			_wave_end = wave_t                  # the play woke them: the wave dies down
		if wave_amp() <= 0.0 and wave_t > WAVE_FADE:
			wave_t = -1.0
			_quiet = 0.0
		return
	if _quiet > WAVE_AFTER and _rng.randf() < 1.0 - det_exp(LN_NO_WAVE * dt):   # 1 - (1 - chance)^dt
		start_wave()


## e^[param x] with + - * / alone (plan 35): halved into [-0.5, 0.5], a
## Taylor series to 18 terms (past double precision there), squared back -
## every step exactly rounded by IEEE 754, so every machine gets the same
## bits (a maths library's exp may differ in the last one).
static func det_exp(x: float) -> float:
	var k := 0
	while absf(x) > 0.5 and k < 64:
		x *= 0.5
		k += 1
	var term := 1.0
	var sum := 1.0
	for n in range(1, 19):
		term = term * x / n
		sum += term
	for i in k:
		sum *= sum
	return sum


## The crowd's noise for snapshot [param snap] (a crowd level, 0-1000):
## its liveliness as the level that makes it, plus a wave's cheer.
static func sound_level(snap: Dictionary) -> int:
	var x := clampf((float(snap.get("life", LIFE_CALM)) - LIFE_CALM) / (1.0 - LIFE_CALM), 0.0, 1.0)
	var level := LEVEL_CALM + x * (LEVEL_FULL - LEVEL_CALM) + float(snap.get("wave_amp", 0.0)) * WAVE_CHEER
	return clampi(roundi(level), 0, 1000)


## Between snapshots [param a] and [param b] at [param t] (0 = a, 1 = b),
## for frames drawn between passes; a ({}: none) is [param b].
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	if a.is_empty() or t >= 1.0 or b.is_empty():
		return b
	var out := b.duplicate()
	var ta := float(a["ticks"])
	var tb := float(b["ticks"])
	if tb < ta - WRAP / 2.0:
		tb += WRAP                              # the clock wrapped between them
	out["ticks"] = lerpf(ta, tb, t)
	out["life"] = lerpf(float(a["life"]), float(b["life"]), t)
	out["lift"] = lerpf(float(a["lift"]), float(b["lift"]), t)
	out["wave_angle"] = lerpf(float(a["wave_angle"]), float(b["wave_angle"]), t)
	out["wave_amp"] = lerpf(float(a["wave_amp"]), float(b["wave_amp"]), t)
	return out
