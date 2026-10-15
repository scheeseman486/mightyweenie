class_name MwOrganPool
extends RefCounted
## The organ pool (plan 39, owner 2026-10-10): organ tunes made for the port
## ([MwOrganTunes]: public-domain classics and two written for the port) that
## join the original's organ tunes - the goal song (`$09`) and the four
## period-start jingles (`$05-$08`). With [member MwAudio.organ_pool] on
## (ENHANCE AUDIO) each time one of those would play, one tune of the whole
## pool plays instead, picked at random ([method pick]).
##
## The tunes are written as notes ([Tune]) and encoded at start-up into the
## original's own sequence format (docs/re/sound.md 5.1), on the rink
## jingles' organ (instrument `$5B`, program 91) at the jingles' velocities
## and channel volume, so they sound like them and play through the ported
## driver exactly like the ROM's sequences: [MwAudio] appends them to its
## copy of the ROM, after its end ([constant BASE]). Stomp Manor's stomps are
## floor hits: the first stomp of the matchup chant's sample (sound `$1B`),
## played on the PCM mixer's extra voices ([member Tune.hits]).
##
## Writing more (docs/re/sound.md 13.12): the organ sounds an octave below the
## written key (its carrier runs at half the note's frequency); only two of
## its four operators follow the volume, so velocity changes its timbre (the
## jingles use 70-94 at channel volume 117); at most [constant MAX_NOTES]
## notes at once, leaving one of the rink's five FM channels for its FM
## effects; a pitch bend wraps in the driver for a bend up from a written
## note above ~832 Hz, down from one above ~1664 Hz.

## The rink jingles' organ.
const ORGAN := 0x5B
## The tempo byte: 150 BPM = one clock (1/24 beat) per 60 Hz tick, so every
## time below is in ticks.
const TEMPO := 150
## Controller 7 of every part (the jingles' 117).
const TRACK_VOLUME := 117
## Velocities are written 80-124 and played in the jingles' range 70-94.
const VEL_LO := 70
const VEL_HI := 94
## Notes sounding at once, at most (the original's jingles hold four).
const MAX_NOTES := 4
## Where the tunes start in the driver's copy of the ROM (the cartridge ends
## at `$1FFFFF`). The copy is the cartridge alone ([method extend_rom]): the
## game's view of the ROM has plan 38's custom teams from the same address
## (MwCustomOverlay.BASE, MwRom.data), a bank that differs from machine to
## machine - kept out, the tunes sit at the same addresses on every machine
## (the driver's RAM holds them; a resync snapshot carries it).
const BASE := 0x200000
## The original's tunes in the pool: the period-start jingles and the goal
## song.
const ORIGINALS: Array[int] = [5, 6, 7, 8, 9]

## The floor hit: values [constant HIT_FROM]..[constant HIT_TO] of sound
## [constant HIT_SOUND]'s decoded sample (its first stomp, ~0.34 s), faded in
## over [constant HIT_FADE_IN] and out over [constant HIT_FADE_OUT] values.
const HIT_SOUND := MwSoundIds.CHANT
const HIT_FROM := 620
const HIT_TO := 4300
const HIT_FADE_IN := 40
const HIT_FADE_OUT := 1400
## The hit's id in the chips' PCM mixer (above the ROM's 43 samples).
const HIT_SAMPLE_ID := 64

const _NOTE_NAMES := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

## The pick's own generator, for a pick without a stream (offline renders,
## tests: they seed it); never the game's random streams.
static var rng := _new_rng()

## One tune: its parts (one per MIDI channel, all on the organ) and its
## floor hits.
class Tune:
	var name := ""
	## Every part's program and controller 7.
	var program := ORGAN
	var volume := TRACK_VOLUME
	## MIDI channel -> events [tick, order, serial, kind, a, b, c]; kind
	## "note" (a key, b velocity, c length) or "bend" (a -64..63).
	var parts := {}
	## Ticks (from the tune's start) of its floor hits.
	var hits := PackedInt32Array()
	var _serial := 0

	func _init(name_: String) -> void:
		name = name_

	func part(ch: int) -> int:
		parts[ch] = []
		return ch

	## A note: [param k] a name ("F#3") or a MIDI key; [param vel] 80-124.
	func note(ch: int, t: int, duration: int, k: Variant, vel := 100) -> void:
		var key := MwOrganPool.key(k)
		assert(key >= 24 and key <= 111 and duration >= 1)
		var v := clampi(vel, 80, 124)
		raw(ch, t, duration, key, VEL_LO + int(round((v - 80) * float(VEL_HI - VEL_LO) / 44.0)))

	## A note at the velocity [param velocity] as played (1-127).
	func raw(ch: int, t: int, duration: int, key: int, velocity: int) -> void:
		_add(ch, [t, 2, "note", key, velocity, duration])

	func chord(ch: int, t: int, duration: int, keys: Array, vel := 100) -> void:
		for k: Variant in keys:
			note(ch, t, duration, k, vel)

	## A pitch bend, -64..63 (63 ~ the bend range up, 12 semitones; linear
	## in frequency).
	func bend(ch: int, t: int, value: float) -> void:
		_add(ch, [t, 1, "bend", clampi(int(round(value)), -64, 63)])

	## Bends from [param v0] at [param t0] to [param v1] at [param t1].
	func glide(ch: int, t0: int, t1: int, v0: float, v1: float, step := 1) -> void:
		var t := t0
		while t <= t1:
			bend(ch, t, v0 + (v1 - v0) * float(t - t0) / float(maxi(1, t1 - t0)))
			t += step

	func hit(t: int) -> void:
		hits.append(t)

	## A line of notes from tick [param t] (a float, so fractional units add
	## up exactly): [param seq] holds [names, units] or [names, units,
	## velocity], names null (a rest), a note or an Array of notes (a chord),
	## each [param unit] ticks a unit. Every note sounds on every part of
	## [param layers] ([channel, key shift, velocity offset]) and lasts [param
	## gate] of its time (at least [param minlen] ticks), always ending before
	## the next starts. Returns the time after the line.
	func line(t: float, seq: Array, unit: float, layers: Array, vel := 100, gate := 0.8, minlen := 2) -> float:
		for item: Array in seq:
			var names: Variant = item[0]
			var v: int = int(item[2]) if item.size() > 2 else vel
			var dur := float(item[1]) * unit
			var start := MwOrganPool.tick(t)
			var e := MwOrganPool.tick(t + dur)
			if names != null:
				var list: Array = names if names is Array else [names]
				var ln := maxi(1, mini(maxi(minlen, MwOrganPool.tick(dur * gate)), e - start - 1))
				for layer: Array in layers:
					for n: Variant in list:
						note(int(layer[0]), start, ln, MwOrganPool.key(n) + int(layer[1]), v + int(layer[2]))
			t += dur
		return t

	## The tick its last note ends (the sequence's length).
	func length() -> int:
		var e := 0
		for ch: int in parts:
			for ev: Array in parts[ch]:
				e = maxi(e, int(ev[0]) + (int(ev[6]) if ev[3] == "note" else 0))
		return e

	## Notes sounding at once, at most (a note holding its channel through
	## its note-off tick).
	func most_notes() -> int:
		var busy := {}
		for ch: int in parts:
			for ev: Array in parts[ch]:
				if ev[3] == "note":
					for x in range(int(ev[0]), int(ev[0]) + int(ev[6]) + 1):
						busy[x] = int(busy.get(x, 0)) + 1
		var most := 0
		for x: int in busy:
			most = maxi(most, int(busy[x]))
		return most

	func _add(ch: int, ev: Array) -> void:
		ev.insert(2, _serial)          # keeps the order of equal events
		_serial += 1
		parts[ch].append(ev)


## [param k] as a MIDI key: an int, or a name such as "C4" (60), "F#3",
## "Bb2", "E#3".
static func key(k: Variant) -> int:
	if k is int:
		return k
	var text := String(k)
	var n: int = _NOTE_NAMES[text[0]]
	var i := 1
	while text[i] == "#" or text[i] == "b":
		n += 1 if text[i] == "#" else -1
		i += 1
	return n + 12 * (int(text.substr(i)) + 1)


## The pool's own tunes, in order ([MwOrganTunes]).
static func tunes() -> Array[Tune]:
	return MwOrganTunes.all()


## How many tunes the pool picks from: the original's and ours.
static func size() -> int:
	return ORIGINALS.size() + MwOrganTunes.COUNT


## [param x] rounded to a tick (halves up).
static func tick(x: float) -> int:
	return floori(x + 0.5)


## A tune of the pool at random, uniformly: 0..4 the original's
## ([constant ORIGINALS]), 5.. ours ([method tunes]). From [param stream]
## when given (plan 35: the session's organ stream, MwAudio.play_organ - one
## draw, the same on every machine), else from [member rng].
static func pick(stream: MlhRng = null) -> int:
	if stream != null:
		return stream.range_value(0, size() - 1)
	return rng.randi_range(0, size() - 1)


static func _new_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


# --- the encoder ------------------------------------------------------------------------------

## [param tune] in the original's sequence format (docs/re/sound.md 5.1):
## the header (format byte, tempo, track count, each track's offset and MIDI
## channel), then per track a VLQ wait and (event, VLQ wait) pairs - program
## `$DC`, controller 7 `$DF`, notes (`$80 | key - 24`, velocity, VLQ
## length), bends `$E5` - ending with `$D9`. Padded to an even length.
static func encode(tune: Tune) -> PackedByteArray:
	var channels: Array = tune.parts.keys()
	channels.sort()
	var bodies: Array[PackedByteArray] = []
	for ch: int in channels:
		var evs: Array = [[0, 0, -2, "prog"], [0, 0, -1, "vol"]]
		evs.append_array(tune.parts[ch])
		var end := 0
		for ev: Array in tune.parts[ch]:
			end = maxi(end, int(ev[0]) + (int(ev[6]) if ev[3] == "note" else 0))
		evs.sort_custom(func(a: Array, b: Array) -> bool:
			if a[0] != b[0]:
				return a[0] < b[0]
			if a[1] != b[1]:
				return a[1] < b[1]
			return a[2] < b[2])
		evs.append([end, 9, 0, "end"])
		var body := vlq(int(evs[0][0]))
		for i in evs.size():
			var ev: Array = evs[i]
			match ev[3]:
				"prog":
					body.append_array(PackedByteArray([0xDC, tune.program]))
				"vol":
					body.append_array(PackedByteArray([0xDF, 7, tune.volume]))
				"bend":
					body.append_array(PackedByteArray([0xE5, 0, int(ev[4]) + 0x40]))
				"note":
					var op := int(ev[4]) - 24
					if int(ev[5]) >= 127:
						body.append(op)
					else:
						body.append_array(PackedByteArray([0x80 | op, int(ev[5])]))
					body.append_array(vlq(int(ev[6])))
				"end":
					body.append(0xD9)
					break
			body.append_array(vlq(int(evs[i + 1][0]) - int(ev[0])))
		bodies.append(body)
	var n := channels.size()
	var out := PackedByteArray([0, TEMPO, n >> 8, n & 0xFF])
	var off := 4 + 4 * n
	for k in n:
		out.append_array(PackedByteArray([off >> 8, off & 0xFF, int(channels[k]) >> 8, int(channels[k]) & 0xFF]))
		off += bodies[k].size()
	for b in bodies:
		out.append_array(b)
	if out.size() % 2 == 1:
		out.append(0)
	return out


## A MIDI variable-length quantity (7 bits a byte, bit 7 = more follow).
static func vlq(v: int) -> PackedByteArray:
	var out := PackedByteArray([v & 0x7F])
	v >>= 7
	while v > 0:
		out.insert(0, 0x80 | (v & 0x7F))
		v >>= 7
	return out


## A copy of [param rom]'s cartridge (anything past [constant BASE] left
## out: the custom-team overlay of MwRom.data) with every tune of [param
## list] after it from [constant BASE] (each at an even address); [param
## addresses] gets their addresses.
static func extend_rom(rom: PackedByteArray, list: Array[Tune], addresses: PackedInt32Array) -> PackedByteArray:
	var out := rom.slice(0, mini(rom.size(), BASE))
	out.resize(BASE)
	for tune in list:
		addresses.append(out.size())
		out.append_array(encode(tune))
	return out


## The floor hit's DAC values (unsigned 8-bit, the mixer's format) from
## [param samples], or empty if the ROM has no such sample.
static func hit_sample(samples: MwSoundSamples) -> PackedByteArray:
	var sample := samples.by_sound_id(HIT_SOUND)
	if sample < 0:
		return PackedByteArray()
	var data := samples.decode(sample)
	var cut := data.slice(HIT_FROM, HIT_TO)
	for k in HIT_FADE_IN:
		cut[k] = _faded(cut[k], float(k) / HIT_FADE_IN)
	for k in HIT_FADE_OUT:
		var i := cut.size() - HIT_FADE_OUT + k
		cut[i] = _faded(cut[i], 1.0 - float(k + 1) / HIT_FADE_OUT)
	return cut


## The hit's playback rate (its sample's, Hz).
static func hit_rate(samples: MwSoundSamples) -> float:
	return samples.desc(samples.by_sound_id(HIT_SOUND)).rate()


static func _faded(v: int, g: float) -> int:
	return clampi(int(round(0x80 + (v - 0x80) * g)), 1, 255)
