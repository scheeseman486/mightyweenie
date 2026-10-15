class_name MwSlam
extends RefCounted
## A picture falling into place and slamming down with a shake (plan 34,
## owner: the game options' top graphic comes into the scene this way; the
## line-up panels crash in the same way). The motion is the
## original's own slam, the FACE OFF! drop (`$AD08`, docs/re/phases.md 4.4;
## MwRinkPhases._drop_step): the puck's motion parameters (gravity -24/256,
## restitution `$80`) from a height, the thud (sound `$15`) on the first
## bounce, and while it bounces up a sideways shake of twice its upward
## speed in pixels (at most 48), the sign flipping every pass; settled when
## the upward speed drops under 1 px - or, [member bounces], after bouncing
## on until a bounce would be slower than 1 px a tick. The rink's passes are 2 ticks, so it
## steps every 2 ticks here as well. Presentation only: nothing it does
## touches a random stream.

const THUD := MwSoundIds.THUD
## The second bounce's crash (owner, 2026-10-10: the crash sound on both
## bounces, the second a little lower and softer): the sample at 7/8 of its
## rate (about two semitones down) and 11/16 of its volume (about -3 dB).
const SECOND_CRASH_RATE := 0xE0
const SECOND_CRASH_VOLUME := 0xB0
## A bounce off the ground slower than this (1 px a tick, in 1/256 px) ends
## it: down to stay.
const MIN_BOUNCE := 0x100
## FACE OFF!'s letters start 180 px up.
const HEIGHT := 180
const PASS_TICKS := 2

var motion := MwMotion.new()
var params := MwMotion.Params.new(-24, 0x80, 3, 3)
var done := false
## False (FACE OFF!'s, the line-up panels'): in place at the top of its first
## bounce, where it rises slower than 1 px a pass. True (the game setup's
## top; owner, 2026-10-10: bouncing nicely, not snapping down):
## it falls back from there and bounces again, each bounce half as fast (a
## quarter as high), until one would be slower than 1 px a tick
## ([constant MIN_BOUNCE]); then it is down to stay.
var bounces := false
## The sideways shake this pass (px; 0 when falling or settled).
var shake := 0
## True on the pass a thud is due (the caller plays it): the first bounce's,
## and with [member bounces] the second's too (owner: the crash sound on
## both bounces, the second a little lower and softer - [member impacts]
## tells which).
var thud := false
## Touch downs that bounced so far (1: the first).
var impacts := 0
var _passes := 0
var _ticks := 0


func _init(drop_height := HEIGHT) -> void:
	motion.init(0, 0, drop_height)


## The crash of bounce [param impact] (1: the thud; 2: the second, lower
## and softer; 0 or more than 2: none) - the game setup's top and the
## line-up panels.
static func crash(impact: int) -> void:
	if impact == 1:
		MwSound.play(THUD)
	elif impact == 2:
		MwSound.play_voice(THUD, SECOND_CRASH_RATE, SECOND_CRASH_VOLUME)


## The height above its place (px; 0 settled).
func height() -> int:
	return 0 if done else MwMotion.asr(motion.pos[2], 8)


## [param elapsed] ticks: a pass every [constant PASS_TICKS].
func advance(elapsed: int) -> void:
	thud = false
	if done:
		return
	_ticks += elapsed
	while _ticks >= PASS_TICKS and not done:
		_ticks -= PASS_TICKS
		_pass(PASS_TICKS)


## Lands at once (a press skips it).
func settle() -> void:
	done = true
	shake = 0
	motion.pos[2] = 0


func _pass(e: int) -> void:
	var old_vz := motion.vel[2]
	motion.step(params, e)
	if old_vz < 0:
		if motion.vel[2] < 0:
			shake = 0
			_passes += 1
			return                                    # still falling
		if motion.vel[2] < MIN_BOUNCE:
			settle()                                  # too slow to bounce (again): down to stay
			return
		impacts += 1
		thud = impacts == 1 or (bounces and impacts == 2)
	var vz := motion.vel[2]
	if vz < 0 or (bounces and vz == 0):
		shake = 0                                     # falling back after a bounce
		_passes += 1
		return
	var d := MwMotion.asr(vz, 8)
	if d == 0:
		if not bounces:
			settle()                                  # FACE OFF!'s: in place at its first bounce's top
			return
		shake = 0                                     # the top of a bounce: it falls back
		_passes += 1
		return
	d = mini(absi(d), 0x18) * 2
	shake = -d if _passes & 1 == 0 else d
	_passes += 1
