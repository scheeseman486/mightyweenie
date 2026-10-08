extends SceneTree
## Check of the audio extension (MwChips: ymfm YM2612 + our SN76489), run
## headless:
##   tools/bin/godot-headless -s res://test/audio/chips_check.gd
## Programs an FM tone (algorithm 7, one carrier: a sine), a PSG tone and a
## periodic-noise tone with hand-written register values, renders 1 s of each,
## writes them as WAVs to out/plan12/ext/, measures their fundamentals (zero
## crossings) against the frequencies the registers ask for, reads the DAC's
## levels and times the render. Exit code 0 when every frequency is within 1 %.
## The static helpers are shared with test_chips.gd (GUT).

const OUT_DIR := "out/plan12/ext"  # relative to the repository root


func _init() -> void:
	if not ClassDB.class_exists("MwChips"):
		printerr("MwChips not loaded - build it with tools/bin/build-audio")
		quit(2)
		return
	var chips: Object = ClassDB.instantiate("MwChips")
	var rate: float = chips.sample_rate()
	var frames := int(round(rate))  # 1 s
	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").path_join(OUT_DIR).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("MwChips: sample_rate %.4f Hz, dac_full_scale %.6f" % [rate, chips.dac_full_scale()])
	var ok := true

	# FM: channel 1 (port 0) and channel 5 (port 1), block 4.
	for setup: Array in [[0, 0, 4, 1083, "fm_ch1_440"], [1, 1, 4, 1600, "fm_ch5_650"]]:
		chips.reset()
		program_fm_sine(chips, setup[0], setup[1], setup[2], setup[3])
		var buf: PackedVector2Array = chips.render(frames)
		var want := fm_frequency(setup[2], setup[3], rate)
		ok = report(setup[4], buf, rate, want, out_dir) and ok

	# PSG tone: channel 0, divider 254, 0 dB.
	chips.reset()
	psg_tone(chips, 0, 254, 0)
	ok = report("psg_ch0_440", chips.render(frames), rate, psg_tone_frequency(254), out_dir) and ok

	# FM / PSG balance: fundamental of the PSG square over that of the FM sine
	# (Genesis Plus GX, the reference emulator: 0.327, out/plan12/ext/gp_balance.py).
	chips.reset()
	program_fm_sine(chips, 0, 0, 4, 1083)
	var fm_amp := fundamental_amplitude(chips.render(frames), rate)
	chips.reset()
	psg_tone(chips, 0, 254, 0)
	var psg_amp := fundamental_amplitude(chips.render(frames), rate)
	print("balance: fundamental FM sine %.5f, PSG square %.5f, PSG/FM %.4f (GPGX 0.3272)"
			% [fm_amp, psg_amp, psg_amp / fm_amp])

	# PSG periodic noise clocked by tone 2 (divider 16, tone 2 itself silent):
	# one pulse every 16 shifts of the 16-bit register.
	chips.reset()
	psg_tone(chips, 2, 16, 15)
	chips.psg_write(0xE3)  # noise: periodic, clock = tone 2
	chips.psg_write(0xF0)  # noise attenuation 0
	ok = report("psg_periodic_noise", chips.render(frames), rate, psg_tone_frequency(16) / 16.0, out_dir) and ok

	# White noise, for listening.
	chips.reset()
	chips.psg_write(0xE4)
	chips.psg_write(0xF0)
	var noise: PackedVector2Array = chips.render(frames)
	save_wav(noise, rate, out_dir.path_join("psg_white_noise.wav"))
	print("psg_white_noise: rms %.4f" % rms(noise))

	# DAC: $2B = $80, levels for $2A = $FF / $80 / $00 (left side; pan $C0).
	chips.reset()
	chips.ym_write(0, 0x2B, 0x80)
	var levels := {}
	for value: int in [0xFF, 0x80, 0x00]:
		chips.ym_write(0, 0x2A, value)
		levels[value] = chips.render(64)[63].x
	print("DAC ($2B=$80): $FF -> %.6f, $80 -> %.6f, $00 -> %.6f; $FF-$80 = %.6f (dac_full_scale %.6f)"
			% [levels[0xFF], levels[0x80], levels[0x00], levels[0xFF] - levels[0x80], chips.dac_full_scale()])
	chips.ym_write(0, 0x2B, 0x00)
	print("DAC off: %.6f" % chips.render(64)[63].x)

	# Render speed: 10 s of FM + PSG in one-tick chunks (60 Hz).
	chips.reset()
	program_fm_sine(chips, 0, 0, 4, 1083)
	psg_tone(chips, 0, 254, 0)
	var tick_frames := int(round(rate / 60.0))
	var t0 := Time.get_ticks_usec()
	for i in 600:
		chips.render(tick_frames)
	var usec := Time.get_ticks_usec() - t0
	print("render speed: %.2f ms per second of audio (%d-frame chunks)" % [usec / 10000.0, tick_frames])

	print("RESULT: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


## Prints the measured fundamental of `buf` against `want`, writes NAME.wav.
static func report(name: String, buf: PackedVector2Array, rate: float, want: float, out_dir: String) -> bool:
	var got := measure_frequency(buf, rate)
	var err := (got - want) / want * 100.0
	var ok := absf(err) < 1.0
	save_wav(buf, rate, out_dir.path_join(name + ".wav"))
	print("%s: expected %.3f Hz, measured %.3f Hz (%+.3f %%), peak %.4f, rms %.4f %s"
			% [name, want, got, err, peak(buf), rms(buf), "ok" if ok else "OUT OF TOLERANCE"])
	return ok


## YM2612 tone: f = fnum * 2^block * sample_rate / 2^21 (MUL = 1).
static func fm_frequency(block: int, fnum: int, rate: float) -> float:
	return fnum * pow(2.0, block) * rate / 2097152.0


## PSG tone: f = clock / (32 N).
static func psg_tone_frequency(divider: int) -> float:
	return 3579545.0 / (32.0 * divider)


## A sine-like FM voice on one channel (port 0/1, channel 0-2 of that port):
## algorithm 7 (four carriers), only operator 4 audible (TL 0, the others
## TL $7F), MUL 1, instant attack, full sustain; then key on.
static func program_fm_sine(chips: Object, port: int, ch: int, block: int, fnum: int) -> void:
	var key_code := ch | (port << 2)
	chips.ym_write(0, 0x22, 0x00)  # LFO off
	chips.ym_write(0, 0x27, 0x00)  # channel 3 normal mode, timers off
	chips.ym_write(0, 0x28, key_code)  # key off
	for slot: int in [0x0, 0x4, 0x8, 0xC]:  # operators 1, 3, 2, 4
		chips.ym_write(port, 0x30 + slot + ch, 0x01)  # DT 0, MUL 1
		chips.ym_write(port, 0x40 + slot + ch, 0x00 if slot == 0xC else 0x7F)  # TL
		chips.ym_write(port, 0x50 + slot + ch, 0x1F)  # RS 0, AR 31
		chips.ym_write(port, 0x60 + slot + ch, 0x00)  # AM off, D1R 0
		chips.ym_write(port, 0x70 + slot + ch, 0x00)  # D2R 0
		chips.ym_write(port, 0x80 + slot + ch, 0x0F)  # SL 0, RR 15
		chips.ym_write(port, 0x90 + slot + ch, 0x00)  # SSG-EG off
	chips.ym_write(port, 0xB0 + ch, 0x07)  # feedback 0, algorithm 7
	chips.ym_write(port, 0xB4 + ch, 0xC0)  # left + right
	chips.ym_write(port, 0xA4 + ch, (block << 3) | (fnum >> 8))  # high byte first
	chips.ym_write(port, 0xA0 + ch, fnum & 0xFF)
	chips.ym_write(0, 0x28, 0xF0 | key_code)  # key on, all operators


## PSG tone channel 0-2: divider (10 bits) and attenuation (0-15), as the
## original's Z80 writes them (latch + data byte, then attenuation).
static func psg_tone(chips: Object, channel: int, divider: int, attenuation: int) -> void:
	chips.psg_write(0x80 | (channel << 5) | (divider & 0x0F))
	chips.psg_write((divider >> 4) & 0x3F)
	chips.psg_write(0x90 | (channel << 5) | attenuation)


## Fundamental from the rising zero crossings (linear interpolation) of the
## left channel, after `skip_s` seconds and with the mean removed.
static func measure_frequency(buf: PackedVector2Array, rate: float, skip_s := 0.05) -> float:
	var start := int(skip_s * rate)
	if buf.size() - start < 2:
		return 0.0
	var mean := 0.0
	for i in range(start, buf.size()):
		mean += buf[i].x
	mean /= buf.size() - start
	var first := -1.0
	var last := -1.0
	var count := 0
	var prev := buf[start].x - mean
	for i in range(start + 1, buf.size()):
		var cur := buf[i].x - mean
		if prev < 0.0 and cur >= 0.0:
			var t := (i - 1) + (-prev) / (cur - prev)
			if first < 0.0:
				first = t
			last = t
			count += 1
		prev = cur
	if count < 2:
		return 0.0
	return (count - 1) * rate / (last - first)


## Amplitude of the left channel's fundamental (the frequency measured by
## measure_frequency), by correlation with a sine and a cosine over whole
## periods after `skip_s`.
static func fundamental_amplitude(buf: PackedVector2Array, rate: float, skip_s := 0.05) -> float:
	var f := measure_frequency(buf, rate, skip_s)
	if f <= 0.0:
		return 0.0
	var start := int(skip_s * rate)
	var periods := floorf((buf.size() - start) * f / rate)
	var n := int(periods * rate / f)
	var s := 0.0
	var c := 0.0
	var w := TAU * f / rate
	for i in n:
		var x := buf[start + i].x
		s += x * sin(w * i)
		c += x * cos(w * i)
	return 2.0 * sqrt(s * s + c * c) / n


static func peak(buf: PackedVector2Array) -> float:
	var p := 0.0
	for v in buf:
		p = maxf(p, maxf(absf(v.x), absf(v.y)))
	return p


static func rms(buf: PackedVector2Array) -> float:
	if buf.is_empty():
		return 0.0
	var s := 0.0
	for v in buf:
		s += v.x * v.x
	return sqrt(s / buf.size())


## 16-bit stereo WAV at the chips' rate (rounded to whole Hz).
static func save_wav(buf: PackedVector2Array, rate: float, path: String) -> Error:
	var data := PackedByteArray()
	data.resize(buf.size() * 4)
	for i in buf.size():
		data.encode_s16(i * 4, int(clampf(buf[i].x, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(buf[i].y, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(round(rate))
	wav.data = data
	return wav.save_to_wav(path)
