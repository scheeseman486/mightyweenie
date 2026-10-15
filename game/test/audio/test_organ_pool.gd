extends "res://test/rom/rom_test_base.gd"
## The organ pool (plan 39, owner 2026-10-10): tunes made for the port
## ([MwOrganTunes]) beside the original's organ tunes (`$05-$09`); with
## [member MwAudio.organ_pool] (ENHANCE AUDIO) each of those plays one tune of
## the whole pool at random from the pool's own generator.
## Short names: t the MwOrganPool.Tune under test.

const STOMP_MANOR := 7     ## its index in the pool (0-4 the original's, 5.. ours)

var audio: MwAudio
var _pool := true


func before_each() -> void:
	_pool = MwAudio.organ_pool
	MwAudio.organ_pool = true


func after_each() -> void:
	MwAudio.organ_pool = _pool
	MwSound.driver = null
	if audio:
		audio.free()
		audio = null


func _audio() -> MwAudio:
	audio = MwAudio.new()
	audio.setup(rom, false)
	return audio


## A sequence of the ROM (one track) read back as a tune, velocities as
## played: notes, program and controller 7 (the only events the jingles use).
func _tune_from_rom(seq: int) -> MwOrganPool.Tune:
	var t := MwOrganPool.Tune.new("rom")
	var a := seq + ((rom[seq + 4] << 8) | rom[seq + 5])
	var ch := (rom[seq + 6] << 8) | rom[seq + 7]
	t.part(ch)
	var r := _vlq(a)
	var clock: int = r[0]
	a = r[1]
	while true:
		var op := rom[a]
		a += 1
		if op < 0xD9:
			var vel := 0x7F
			if op & 0x80:
				vel = rom[a]
				a += 1
			r = _vlq(a)
			t.raw(ch, clock, r[0], (op & 0x7F) + 24, vel)
			a = r[1]
		elif op == 0xD9:
			break
		elif op == 0xDC:
			t.program = rom[a]
			a += 1
		elif op == 0xDF:
			t.volume = rom[a + 1]
			a += 2
		else:
			fail_test("event %02X not expected" % op)
			break
		r = _vlq(a)
		clock += r[0]
		a = r[1]
	return t


func _vlq(a: int) -> Array:
	var v := 0
	while true:
		var b := rom[a]
		a += 1
		v = (v << 7) | (b & 0x7F)
		if b & 0x80 == 0:
			return [v, a]
	return [v, a]


## The batch the 68000 side builds (`$FFE6B0-$FFE734`).
func _batch(driver: MwSound68k) -> PackedByteArray:
	var out := PackedByteArray()
	for i in 133:
		out.append(driver.r8(0xFFE6B0 + i))
	return out


## The encoder: the ROM's goal song read back and re-encoded drives the
## driver exactly as the ROM's own bytes, tick for tick.
func test_the_encoder_reproduces_the_goal_song() -> void:
	if not need_rom():
		return
	var seq := (rom[0x1F57E + 36] << 24) | (rom[0x1F57E + 37] << 16) | (rom[0x1F57E + 38] << 8) | rom[0x1F57E + 39]
	var tune := _tune_from_rom(seq)
	var tempo := rom[seq + 1]
	var bytes := MwOrganPool.encode(tune)
	bytes[1] = tempo
	var copy := rom.duplicate()
	var at := copy.size()
	copy.append_array(bytes)
	var by_id := MwSound68k.new(copy)
	var by_address := MwSound68k.new(copy)
	by_id.reset()
	by_address.reset()
	var ha := by_id.sound_play(9)
	var hb := by_address.play_sequence(at)
	var ticks := 0
	var same := true
	while (by_id.sound_busy(ha) or by_address.sound_busy(hb)) and ticks < 600:
		for driver: MwSound68k in [by_id, by_address]:
			driver.channels_tick()
			driver.seq_tick()
		if _batch(by_id) != _batch(by_address):
			same = false
			break
		ticks += 1
	assert_true(same, "the same batch on every tick (to tick %d)" % ticks)
	assert_between(ticks, 390, 400, "the whole song (396 ticks)")
	assert_eq(by_id.r16(MwSound68k.NOTE_SERIAL), by_address.r16(MwSound68k.NOTE_SERIAL), "as many notes")


## The owner's limits and the organ's: under 7 s, four notes at most, the
## organ only, keys in the driver's range, no bend that would wrap, the hits
## inside the tune.
func test_the_tunes_keep_the_rules() -> void:
	var names := []
	for t in MwOrganPool.tunes():
		names.append(t.name)
		assert_lt(t.length(), 7 * 60, "%s under 7 s" % t.name)
		assert_gt(t.length(), 5 * 60, "%s a tune, not a sting" % t.name)
		assert_lte(t.most_notes(), MwOrganPool.MAX_NOTES, t.name)
		assert_eq(t.program, MwOrganPool.ORGAN)
		for ch: int in t.parts:
			var notes: Array = t.parts[ch].filter(func(e: Array) -> bool: return e[3] == "note")
			for ev: Array in t.parts[ch]:
				if ev[3] == "note":
					assert_between(int(ev[4]), 24, 111, "%s key" % t.name)
					assert_between(int(ev[5]), MwOrganPool.VEL_LO, MwOrganPool.VEL_HI, "%s velocity" % t.name)
				elif ev[3] == "bend" and int(ev[4]) != 0:
					for n: Array in notes:
						if int(n[0]) <= int(ev[0]) and int(ev[0]) <= int(n[0]) + int(n[6]):
							# the driver's delta is a signed word of the F-number difference
							var f := 440.0 * pow(2.0, (int(n[4]) - 69) / 12.0) * 144.0 * pow(2.0, 21) / 7670453.0
							var wraps := f >= 32768.0 if int(ev[4]) > 0 else f / 2.0 >= 32768.0
							assert_false(wraps, "%s: a bend that wraps at tick %d" % [t.name, ev[0]])
		for h in t.hits:
			assert_between(h, 0, t.length(), "%s hit" % t.name)
	assert_eq(names, ["toccata", "mountain_king", "stomp_manor", "hearse_gallop",
			"funeral_march", "marionette", "bald_mountain", "little_fugue", "fifth_symphony",
			"moonlight", "requiem", "valkyries", "bells_prelude", "mars", "sugar_plum",
			"passacaglia", "scaffold", "erlking", "trolls", "carmen_fate"])
	assert_eq(MwOrganTunes.COUNT, names.size())
	assert_eq(MwOrganPool.size(), 25)


## Through the driver, the crowd on as in the rink: every note gets a
## channel, one of the five FM channels stays free for the rink's FM effects,
## the tune busy for its length.
func test_the_tunes_play_through_the_driver() -> void:
	if not need_rom():
		return
	_audio()
	var tunes := MwOrganPool.tunes()
	for i in tunes.size():
		var t: MwOrganPool.Tune = tunes[i]
		audio.reset()
		audio.s68k.crowd_level(500)
		for k in 4:
			audio.step_driver()
		var notes := 0
		for ch: int in t.parts:
			notes += t.parts[ch].filter(func(e: Array) -> bool: return e[3] == "note").size()
		var serial := audio.s68k.r16(MwSound68k.NOTE_SERIAL)
		var h := audio.play_pool_tune(MwOrganPool.ORIGINALS.size() + i)
		var ticks := 0
		var most := 0
		while audio.s68k.sound_busy(h) and ticks < 600:
			audio.step_driver()
			var used := 0
			for n in 6:
				if audio.s68k.r8(MwSound68k.CHANNELS + n * MwSound68k.CHANNEL_SIZE + MwSound68k.CH_STATE) == 0:
					used += 1
			most = maxi(most, used)
			ticks += 1
		assert_between(ticks, t.length(), t.length() + 3, "%s plays for its length" % t.name)
		assert_eq(audio.s68k.r16(MwSound68k.NOTE_SERIAL) - serial, notes, "%s: every note got a channel" % t.name)
		assert_lte(most, 4, "%s: an FM channel free for the effects" % t.name)


## The pick: uniform over the pool, from the pool's own generator only.
func test_the_pick_is_uniform_and_its_own() -> void:
	MwOrganPool.rng.seed = 39
	var counts := []
	counts.resize(MwOrganPool.size())
	counts.fill(0)
	for i in 1000 * MwOrganPool.size():
		counts[MwOrganPool.pick()] += 1
	for c: int in counts:
		assert_between(c, 850, 1150, "about 1000 each: %s" % str(counts))
	if not need_rom():
		return
	_audio()
	seed(1234)
	var expected := randi()
	seed(1234)
	for i in 20:
		audio.play_organ()
	assert_eq(randi(), expected, "Godot's global generator untouched")


## Plan 35: with a session (the router's, MwRouter._passes) the pick is
## its organ stream's - the same on every machine of a game, the pool's own
## generator untouched - and a pool tune is busy for its length in the
## driver's model (no chips) as on the chips.
func test_the_pick_is_the_sessions_online() -> void:
	var first := MwSession.new(35, 39)
	var second := MwSession.new(35, 39)
	var picks := []
	for i in 60:
		picks.append(MwOrganPool.pick(first.port_stream(MwSession.STREAM_ORGAN)))
	for i in 60:
		assert_eq(MwOrganPool.pick(second.port_stream(MwSession.STREAM_ORGAN)), picks[i], "pick %d alike" % i)
	assert_gt(Array(picks).filter(func(k: int) -> bool: return k >= MwOrganPool.ORIGINALS.size()).size(), 0,
			"the port's tunes among them")
	if not need_rom():
		return
	var models: Array[MwAudio] = []
	for session: MwSession in [MwSession.new(7, 8), MwSession.new(7, 8)]:
		var model := MwAudio.new()
		model.setup(rom, false, false)
		model.session = session
		models.append(model)
	MwOrganPool.rng.seed = 5
	var own := MwOrganPool.rng.state
	for i in 12:
		var h0 := models[0].play_sound(9)
		var h1 := models[1].play_sound(9)
		assert_eq(models[1].organ_last, models[0].organ_last, "goal song %d: the same tune on both" % i)
		assert_eq(h1, h0)
		var ticks := 0
		while models[0].s68k.sound_busy(h0) and ticks < 700:
			models[0].step_driver()
			models[1].step_driver()
			assert_eq(models[1].s68k.sound_busy(h1), models[0].s68k.sound_busy(h0))
			ticks += 1
		assert_lt(ticks, 700, "a pool tune ends in the model")
	assert_eq(MwOrganPool.rng.state, own, "the pool's own generator not drawn")
	assert_true(models[0].session.streams.has(MwSession.STREAM_ORGAN), "the session's organ stream drawn")
	for audio_model in models:
		audio_model.free()


## Both ways in: the goal song and the period-start jingle play a pool tune;
## other sounds are the driver's; off, the original's.
func test_the_pool_replaces_only_the_organ_tunes() -> void:
	if not need_rom():
		return
	_audio()
	MwSound.driver = audio
	MwOrganPool.rng.seed = 3
	var seen := {}
	for i in 200:
		audio.organ_last = -1
		var h := MwSound.play(9)
		assert_ne(audio.organ_last, -1, "the goal song picks")
		assert_true(audio.s68k.sound_busy(h))
		seen[audio.organ_last] = true
		audio.organ_last = -1
		MwSound.random_sound(i)
		assert_ne(audio.organ_last, -1, "the period start picks")
		seen[audio.organ_last] = true
		audio.enter_match(1)
	assert_eq(seen.size(), MwOrganPool.size(), "every tune heard")
	audio.organ_last = -1
	MwSound.play(4)
	MwSound.play(0x26)
	assert_eq(audio.organ_last, -1, "the horn and the samples are the driver's")
	MwAudio.organ_pool = false
	for i in 8:
		MwSound.play(9)
		MwSound.random_sound(i)
	assert_eq(audio.organ_last, -1, "off: never")


## Off, the calls are the original's exactly: the same batches as the bare
## 68000 side.
func test_off_is_the_original() -> void:
	if not need_rom():
		return
	MwAudio.organ_pool = false
	_audio()
	var bare := MwSound68k.new(audio.rom)
	bare.reset()
	audio.s68k.reset()
	var h1 := audio.play_sound(9)
	var h2 := bare.sound_play(9)
	assert_eq(h1, h2)
	audio.random_sound(2)
	bare.random_sound(2)
	for i in 120:
		for driver: MwSound68k in [audio.s68k, bare]:
			driver.channels_tick()
			driver.seq_tick()
		assert_eq(_batch(audio.s68k), _batch(bare))


## Stomp Manor's floor hits: one on each of its ticks, stopped with it.
func test_the_floor_hits() -> void:
	if not need_rom():
		return
	_audio()
	if audio.chips == null:
		pending("no MwChips extension")
		return
	var t: MwOrganPool.Tune = audio.organ_tunes[STOMP_MANOR - MwOrganPool.ORIGINALS.size()]
	assert_eq(t.name, "stomp_manor")
	assert_eq(t.hits.size(), 7)
	audio.play_pool_tune(STOMP_MANOR)
	var started := PackedInt32Array()
	var before := 0
	for tick in t.length() + 2:
		audio.step_driver()
		if audio._organ_voices.size() > before:
			started.append(tick)
			before = audio._organ_voices.size()
	assert_eq(started, t.hits, "a hit on each of its ticks")
	assert_eq(audio._organ_handle, -1, "done with the tune")
	# stopped with the tune
	var h := audio.play_pool_tune(STOMP_MANOR)
	for tick in 40:
		audio.step_driver()
	var v: int = audio._organ_voices[audio._organ_voices.size() - 1]
	assert_eq(int(audio.chips.call("pcm_sample", v)), MwOrganPool.HIT_SAMPLE_ID, "a hit sounding")
	audio.s68k.sound_stop(h)
	audio.step_driver()
	assert_eq(audio._organ_handle, -1)
	assert_false(bool(audio.chips.call("pcm_active", v)), "the hit stopped with the tune")
	audio.play_pool_tune(STOMP_MANOR)
	audio.step_driver()
	audio.enter_match(1)
	assert_eq(audio._organ_handle, -1, "a driver reset ends the hits")


## The hit's sample: a slice of the chant's sample, faded both ends.
func test_the_hit_sample() -> void:
	if not need_rom():
		return
	var samples := MwSoundSamples.new(rom)
	var hit := MwOrganPool.hit_sample(samples)
	assert_eq(hit.size(), MwOrganPool.HIT_TO - MwOrganPool.HIT_FROM)
	assert_eq(hit[0], 0x80, "fades in from silence")
	assert_almost_eq(int(hit[hit.size() - 1]), 0x80, 1, "fades out to silence")
	assert_almost_eq(MwOrganPool.hit_rate(samples), 10930.0, 1.0)


## Plan 40 (the survey's B1): the driver's copy is the cartridge and the
## tunes alone - a bank of custom teams in the game's view (MwRom.data, its
## overlay from the same address) never moves them, so every machine's
## driver has the tunes at the same addresses whatever its bank.
func test_the_tunes_sit_where_they_do_whatever_the_bank() -> void:
	if not need_rom():
		return
	var plain := MwRom.archive().bytes()
	var tunes := MwOrganPool.tunes()
	var at := PackedInt32Array()
	var copy := MwOrganPool.extend_rom(plain, tunes, at)
	var viewed := plain.duplicate()
	viewed.append_array(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]))     # a bank's overlay past the end
	var at2 := PackedInt32Array()
	var copy2 := MwOrganPool.extend_rom(viewed, tunes, at2)
	assert_eq(at2, at, "the same addresses")
	assert_eq(copy2, copy, "the same copy")
	assert_eq(at[0], MwOrganPool.BASE, "the first right after the cartridge")


## Plan 40 (the survey's B8): a floor hit that takes an extra's chips voice
## (the mixer's oldest when every voice is busy, or one the extra no longer
## sounds on) leaves that extra without it - its stop no longer cuts the hit.
func test_a_hit_takes_its_voice_from_the_extras() -> void:
	if not need_rom():
		return
	_audio()
	if audio.chips == null:
		pending("no MwChips extension")
		return
	var extra := MwAudio.Extra.new()
	extra.sample = 0
	extra.voice = MwAudio.EXTRA_FIRST           # a voice the chips have free again (its sound ended there)
	extra.slot = MwAudio.EXTRA_FIRST
	audio._extras.append(extra)
	var v := audio._start_hit()
	assert_eq(v, MwAudio.EXTRA_FIRST, "the mixer's first free voice")
	assert_eq(extra.voice, -1, "the extra lost it")
	audio._chips_stop(extra)
	assert_true(bool(audio.chips.call("pcm_active", v)), "its stop leaves the hit sounding")
	audio._extras.clear()
