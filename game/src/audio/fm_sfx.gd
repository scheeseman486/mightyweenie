class_name MwFmSfx
extends RefCounted
## Port only (plan 34, owner): sound effects authored for the port as YM2612
## patches and per-tick strike lists, played on the FM channel the music
## leaves free. The first is "gate", a chain-link gate lifting - the
## controller selection's brick wall rising (owner: an FM sound of a
## chain-link gate going up, clink by clink, on any FM channel the music
## leaves spare).
##
## The spare channel is FM6 (part II's third channel). The menus' music
## (`$13C6E`) keys FM1-FM5 only and uses FM6 solely as the DAC for its drum
## samples (`$2B` = `$80` while samples play, which mutes FM6 on the chip);
## the title music (the playoffs champion's too) keys FM1-FM3 and FM5
## (test/audio/test_fm_sfx.gd checks both). The port mixes every sample
## natively ([MwAudioOut]: the DAC register `$2A` is never written), so
## FM6 can sound while the driver's DAC is "on": each tick, after the
## driver's batch, the effect writes `$2B` = `$00`; at its end it puts the
## driver's last `$2B` back, keys off, and gives every register it changed
## back the driver's value (or the chip's reset value when the driver never
## wrote it), so the driver finds FM6 as it left it. Should the driver write
## FM6 itself while an effect plays, the effect stops at once and leaves the
## channel to it.
##
## [method tick] returns a tick's register writes as `[port, register,
## value]` triples; [MwAudio] sends them to the chips after its driver tick
## (tests read them directly). A strike keys an operator pair on; a pair
## striking again is keyed off on the tick before (the YM2612 only restarts
## an envelope after a key-off), so a pair's strikes are 2 ticks apart at
## least.

## Part II (`$4002`/`$4003`): channels FM4-FM6.
const PORT := 1
## FM6 is part II's channel 2: its registers are `$xx + 2` on port 1.
const CHANNEL := 2
## FM6 in the key register `$28`'s channel field (FM4-FM6 = 4-6).
const KEY_CHANNEL := 6
const KEY := 0x28
const DAC_ENABLE := 0x2B
## Operators 1-4's register offsets (the YM2612's slot order: 1, 3, 2, 4).
const OPERATOR_OFFSETS := [0x0, 0x8, 0x4, 0xC]
## The key register's operator bits (>> 4): operators 1 + 2, operators 3 + 4.
const PAIR_A := 0x3
const PAIR_B := 0xC
## The carriers (operator numbers 1-4) of each algorithm 0-7.
const CARRIERS := [[4], [4], [4], [4], [2, 4], [2, 3, 4], [2, 3, 4], [1, 2, 3, 4]]
## Ticks between the last key-off and giving the registers back (the
## release has run out by then).
const RELEASE_TICKS := 4
## The YM2612's channel clock: F-number units are 53 267 / 2^21 Hz per
## block step (7 670 453 / 144 Hz output rate).
const FNUM_HZ := 7670453.0 / 144.0 / 2097152.0
## Values after a reset for the registers an effect writes (ymfm, the
## console: 0, but stereo on for `$B4`-`$B6`).
const RESET_PAN := 0xC0

## A patch: the channel's algorithm and feedback (operator 1's), and per
## operator 1-4: [DT1, MUL, TL, RS, AR, AM, D1R, D2R, D1L, RR] (register
## fields; TL 0.75 dB a step, 0 loudest; MUL 0 = x0.5).
##
## "gate": algorithm 4 - two independent pairs, each a modulator into a
## carrier, keyed separately: pair A (operators 1 -> 2) the link's clink,
## pair B (3 -> 4) a thinner, higher knock of the next link. Carriers x11
## and x15 of the channel's ~250-270 Hz, modulators x9 (with full feedback:
## a noisy splash) and x6: sparse odd partials (9, 11, 15, 21 x f, 2.3-5.5
## kHz) that make no chord, so it rings metallic instead of pitched. The
## modulators decay faster than the carriers - each strike starts as a
## bright, rough splash and rings out purer - and every envelope attacks at
## once and decays to silence by itself (D1L 15, no sustain): a struck
## object. Measured offline (docs/re/sound.md 13.11): 98-99 % of a
## strike's energy in 2-6 kHz, -20 dB 72-94 ms after its peak.
const GATE_PATCH := {
	"algorithm": 4,
	"feedback": 7,
	"operators": [
		[0, 9, 22, 1, 31, 0, 25, 14, 15, 10],   # 1: pair A's modulator (noisy: full feedback)
		[3, 11, 4, 1, 31, 0, 17, 10, 15, 9],    # 2: pair A's carrier
		[0, 6, 28, 1, 31, 0, 22, 12, 15, 10],   # 3: pair B's modulator
		[5, 15, 8, 1, 31, 0, 18, 10, 15, 9],    # 4: pair B's carrier
	],
}

## "gate"'s strikes: [tick, Hz (the channel's base frequency; the carriers
## sound at x11 and x15), level (attenuation added to the carriers' TL, half
## of it to the modulators': a softer knock is also duller), pairs]. A link
## clinks (pair A) and knocks its neighbour a tick or two later (pair B), the
## clinks coming quicker as the wall speeds up (its rise accelerates:
## [MwBrickWall], 30 ticks), the timing and pitch a little irregular, softer
## knocks between.
const GATE_STRIKES := [
	[1, 252.0, 0, PAIR_A | PAIR_B],     # the gate lets go: both at once
	[3, 266.0, 10, PAIR_B],
	[7, 259.0, 2, PAIR_A],
	[8, 247.0, 8, PAIR_B],
	[12, 263.0, 3, PAIR_A],
	[13, 271.0, 9, PAIR_B],
	[16, 255.0, 1, PAIR_A],
	[17, 261.0, 12, PAIR_B],
	[20, 249.0, 4, PAIR_A],
	[21, 268.0, 10, PAIR_B],
	[23, 258.0, 2, PAIR_A],
	[25, 251.0, 7, PAIR_B],
	[26, 264.0, 5, PAIR_A],
	[28, 256.0, 3, PAIR_A],
	[29, 270.0, 9, PAIR_B],
	[31, 253.0, 6, PAIR_A],
	[33, 262.0, 14, PAIR_B],            # the last link settles
]
## Ticks from the start to the key-off of everything (the last strike's
## ring has decayed under the music by then).
const GATE_LENGTH := 52

const EFFECTS := {
	"gate": {"patch": GATE_PATCH, "strikes": GATE_STRIKES, "length": GATE_LENGTH},
}

## The effect playing ("" none).
var effect := ""
var _patch: Dictionary
var _strikes: Array
var _length := 0
var _t := 0
var _keys := 0                  ## operators keyed on (bits 0-3 = operators 1-4)
var _touched := {}              ## (port << 8) | register -> true: written by the effect


## Starts effect [param name] (one of [constant EFFECTS]) from its first
## tick, replacing one that plays. False for an unknown name.
func start(name: String) -> bool:
	if not EFFECTS.has(name):
		return false
	var definition: Dictionary = EFFECTS[name]
	effect = name
	_patch = definition["patch"]
	_strikes = definition["strikes"]
	_length = int(definition["length"])
	_t = 0
	return true


## True from [method start] until the effect has given its registers back (its release included).
func playing() -> bool:
	return effect != ""


## Ends the effect: everything keyed off at the next tick, the registers
## given back [constant RELEASE_TICKS] later (at once if it had not started).
func stop() -> void:
	if effect == "":
		return
	if _t == 0:
		effect = ""
		return
	_t = maxi(_t, _length)


## The effect's register writes for this tick, made after the driver's:
## [param driver] holds the driver's last value per register (index
## `port * 256 + register`, -1 never written; [member MwAudioOut.regs]),
## [param taken] says the driver wrote FM6 this tick (the effect then ends
## without touching it).
func tick(driver := PackedInt32Array(), taken := false) -> Array:
	var w: Array = []
	if effect == "":
		return w
	if taken:
		_give_back(w, driver, false)
		return w
	if _t == 0:
		_keys = 0
		_touched.clear()
		_write(w, 0, KEY, KEY_CHANNEL)                  # FM6's operators off
		_write_patch(w)
	if _t < _length:
		for strike: Array in _strikes:
			if int(strike[0]) == _t:
				_strike(w, strike)
		for strike: Array in _strikes:                       # a pair striking next tick lets go now
			if int(strike[0]) == _t + 1 and _keys & int(strike[3]):
				_set_keys(w, _keys & ~int(strike[3]))
	elif _t == _length:
		_set_keys(w, 0)
	_write(w, 0, DAC_ENABLE, 0x00)                      # FM6 heard, the DAC "off"
	_t += 1
	if _t > _length + RELEASE_TICKS:
		_give_back(w, driver, true)
	return w


## The effect's length in ticks, its release included.
func ticks() -> int:
	return _length + RELEASE_TICKS + 1


## The channel's block and F-number for [param hz]: the lowest block whose
## F-number fits in 11 bits (the finest steps).
static func fnum_block(hz: float) -> Vector2i:
	for block in 8:
		var f := int(round(hz / (FNUM_HZ * float(1 << block))))
		if f < 2048:
			return Vector2i(f, block)
	return Vector2i(2047, 7)


func _write_patch(w: Array) -> void:
	var alg: int = _patch["algorithm"]
	_write(w, PORT, 0xB0 + CHANNEL, (int(_patch["feedback"]) << 3) | alg)
	_write(w, PORT, 0xB4 + CHANNEL, RESET_PAN)          # both speakers, no LFO
	var ops: Array = _patch["operators"]
	for i in 4:
		var o: Array = ops[i]
		var at: int = OPERATOR_OFFSETS[i] + CHANNEL
		_write(w, PORT, 0x30 + at, (int(o[0]) << 4) | int(o[1]))
		_write(w, PORT, 0x40 + at, int(o[2]))
		_write(w, PORT, 0x50 + at, (int(o[3]) << 6) | int(o[4]))
		_write(w, PORT, 0x60 + at, (int(o[5]) << 7) | int(o[6]))
		_write(w, PORT, 0x70 + at, int(o[7]))
		_write(w, PORT, 0x80 + at, (int(o[8]) << 4) | int(o[9]))
		_write(w, PORT, 0x90 + at, 0)                   # no SSG-EG


## A strike: the channel's frequency, the struck pairs' levels, key on.
func _strike(w: Array, strike: Array) -> void:
	var fb := fnum_block(float(strike[1]))
	_write(w, PORT, 0xA4 + CHANNEL, (fb.y << 3) | (fb.x >> 8))   # the high byte first: latched
	_write(w, PORT, 0xA0 + CHANNEL, fb.x & 0xFF)
	var level: int = strike[2]
	var pairs: int = strike[3]
	var carriers: Array = CARRIERS[int(_patch["algorithm"])]
	var ops: Array = _patch["operators"]
	for i in 4:
		if not pairs & (1 << i):
			continue
		var add := level if (i + 1) in carriers else level >> 1
		_write(w, PORT, 0x40 + OPERATOR_OFFSETS[i] + CHANNEL, mini(int(ops[i][2]) + add, 127))
	_set_keys(w, _keys | pairs)


func _set_keys(w: Array, keys: int) -> void:
	_keys = keys
	_write(w, 0, KEY, (keys << 4) | KEY_CHANNEL)


func _write(w: Array, port: int, reg: int, value: int) -> void:
	w.append([port, reg, value])
	if reg >= 0x30:
		_touched[(port << 8) | reg] = true


## The end: keys off, the touched registers back to the driver's values
## ([param restore]; not when the driver took FM6 - it wrote its own), `$2B`
## back to the driver's.
func _give_back(w: Array, driver: PackedInt32Array, restore: bool) -> void:
	if restore:
		_set_keys(w, 0)
		var regs := _touched.keys()
		regs.sort()
		for k: int in regs:
			var v := driver[k] if k < driver.size() else -1
			if v < 0:
				var reg := k & 0xFF
				v = RESET_PAN if reg >= 0xB4 and reg <= 0xB6 else 0
			w.append([k >> 8, k & 0xFF, v])
	var dac := driver[DAC_ENABLE] if DAC_ENABLE < driver.size() else -1
	w.append([0, DAC_ENABLE, maxi(dac, 0)])
	effect = ""
	_touched.clear()
	_keys = 0
