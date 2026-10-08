extends GutTest
## MwChips, the audio GDExtension (ymfm YM2612 + our SN76489; native/mw_audio).
## Skipped when the extension is not built (tools/bin/build-audio). The
## object is used untyped (ClassDB) so this script parses without it.

const Check := preload("res://test/audio/chips_check.gd")

var chips: Object
var rate := 0.0


func should_skip_script():
	if not ClassDB.class_exists("MwChips"):
		return "MwChips extension not built (tools/bin/build-audio)"
	return false


func before_each() -> void:
	chips = ClassDB.instantiate("MwChips")
	rate = chips.sample_rate()


func test_sample_rate_is_the_ym2612_native_rate() -> void:
	assert_almost_eq(rate, 7670453.0 / 144.0, 1e-6)


func test_render_sizes() -> void:
	assert_eq(chips.render(0).size(), 0)
	assert_eq(chips.render(-5).size(), 0)
	assert_eq(chips.render(1).size(), 1)
	assert_eq(chips.render(888).size(), 888, "one 60 Hz tick")


func test_silent_after_construction_and_after_reset() -> void:
	assert_eq(Check.peak(chips.render(2000)), 0.0, "new object")
	Check.program_fm_sine(chips, 0, 0, 4, 1083)
	Check.psg_tone(chips, 0, 254, 0)
	chips.ym_write(0, 0x2B, 0x80)
	chips.ym_write(0, 0x2A, 0xFF)
	assert_gt(Check.peak(chips.render(2000)), 0.1, "tones playing")
	chips.reset()
	assert_eq(Check.peak(chips.render(2000)), 0.0, "after reset")


func test_fm_tone_frequency_port_0() -> void:
	Check.program_fm_sine(chips, 0, 0, 4, 1083)
	var got := Check.measure_frequency(chips.render(int(rate / 2)), rate)
	assert_almost_eq(got, Check.fm_frequency(4, 1083, rate), Check.fm_frequency(4, 1083, rate) * 0.01)


func test_fm_tone_frequency_port_1() -> void:
	Check.program_fm_sine(chips, 1, 2, 3, 1200)  # channel 6
	var got := Check.measure_frequency(chips.render(int(rate / 2)), rate)
	assert_almost_eq(got, Check.fm_frequency(3, 1200, rate), Check.fm_frequency(3, 1200, rate) * 0.01)


func test_fm_stereo_pan() -> void:
	Check.program_fm_sine(chips, 0, 1, 4, 1083)
	chips.ym_write(0, 0xB5, 0x80)  # channel 2: left only
	var buf: PackedVector2Array = chips.render(4000)
	var left := 0.0
	var right := 0.0
	for v in buf:
		left = maxf(left, absf(v.x))
		right = maxf(right, absf(v.y))
	assert_gt(left, 0.1)
	assert_eq(right, 0.0)


func test_psg_tone_frequency_and_level() -> void:
	Check.psg_tone(chips, 1, 254, 0)
	var buf: PackedVector2Array = chips.render(int(rate / 2))
	var want := Check.psg_tone_frequency(254)
	assert_almost_eq(Check.measure_frequency(buf, rate), want, want * 0.01)
	assert_almost_eq(Check.peak(buf), 0.03365, 1e-4, "one channel at 0 dB")


func test_fm_psg_balance_matches_genesis_plus_gx() -> void:
	# Fundamental of a full-volume PSG square / of a full-volume FM sine:
	# 0.327 in Genesis Plus GX (out/plan12/ext/gp_balance.py), 0.322 here.
	Check.program_fm_sine(chips, 0, 0, 4, 1083)
	var fm := Check.fundamental_amplitude(chips.render(int(rate / 2)), rate)
	chips.reset()
	Check.psg_tone(chips, 0, 254, 0)
	var psg := Check.fundamental_amplitude(chips.render(int(rate / 2)), rate)
	assert_almost_eq(psg / fm, 0.327, 0.01)


func test_psg_attenuation_is_2_db_per_step() -> void:
	Check.psg_tone(chips, 0, 254, 0)
	var loud := Check.rms(chips.render(8000))
	Check.psg_tone(chips, 0, 254, 3)
	var soft := Check.rms(chips.render(8000))
	assert_almost_eq(20.0 * log(soft / loud) / log(10.0), -6.0, 0.1)
	chips.psg_write(0x9F)  # attenuation 15 = off
	chips.render(10)
	assert_eq(Check.peak(chips.render(1000)), 0.0)


func test_psg_periodic_noise_has_16_bit_period() -> void:
	# Noise clocked by tone 2 (divider 16, silent): one pulse per 16 shifts.
	Check.psg_tone(chips, 2, 16, 15)
	chips.psg_write(0xE3)
	chips.psg_write(0xF0)
	var want := Check.psg_tone_frequency(16) / 16.0
	var got := Check.measure_frequency(chips.render(int(rate / 2)), rate)
	assert_almost_eq(got, want, want * 0.01)


func test_dac_level() -> void:
	var full: float = chips.dac_full_scale()
	assert_between(full, 0.05, 0.3)
	chips.ym_write(0, 0x2B, 0x80)
	chips.ym_write(0, 0x2A, 0xFF)
	var high: float = chips.render(16)[15].x
	chips.ym_write(0, 0x2A, 0x80)
	var centre: float = chips.render(16)[15].x
	assert_almost_eq(high - centre, full, 1e-6)
	assert_almost_eq(centre, 0.0, 1e-6)


# --- the PCM mixer (native samples; extra voices for MwAudio's enhancement switches) ---

## A test sample: n values of a square wave around $80 (not a ROM sample).
static func _square(n: int) -> PackedByteArray:
	var d := PackedByteArray()
	for i in n:
		d.append(0xC0 if (i >> 3) & 1 == 0 else 0x40)
	return d


static func _peak(frames: PackedVector2Array) -> float:
	var p := 0.0
	for f in frames:
		p = maxf(p, absf(f.x))
	return p


func test_pcm_channel_plays_and_ends() -> void:
	chips.pcm_load(0, _square(1100), 11000.0, -1)
	chips.pcm_start(1, 0, 0)
	assert_true(chips.pcm_active(1))
	assert_eq(chips.pcm_sample(1), 0)
	assert_gt(_peak(chips.render(1000)), 0.01, "sounds")
	chips.render(int(rate * 0.2))
	assert_false(chips.pcm_active(1), "ended after its 0.1 s")
	assert_eq(chips.pcm_sample(1), -1)


func test_pcm_detach_keeps_the_voice_on_an_extra() -> void:
	chips.pcm_load(0, _square(11000), 11000.0, -1)
	chips.pcm_start(2, 0, 0)
	chips.render(500)
	var e: int = chips.pcm_detach(2)
	assert_between(e, 4, 15, "an extra voice")
	assert_false(chips.pcm_active(2), "the channel is free")
	assert_eq(chips.pcm_sample(e), 0, "the extra plays it on")
	assert_gt(_peak(chips.render(1000)), 0.01)
	assert_eq(chips.pcm_detach(2), -1, "a silent channel: nothing to keep")
	chips.pcm_stop(e)
	assert_false(chips.pcm_active(e))


func test_pcm_extras_take_the_oldest_when_full() -> void:
	chips.pcm_load(0, _square(110000), 11000.0, -1)
	chips.pcm_load(1, _square(110000), 11000.0, -1)
	var first: int = chips.pcm_start_extra(0, 0x100, 0x80)
	for i in 11:
		chips.pcm_start_extra(0, 0x100, 0x80)
	var again: int = chips.pcm_start_extra(1, 0x100, 0x80)
	assert_eq(again, first, "all 12 busy: the oldest is taken")
	assert_eq(chips.pcm_sample(first), 1)
	chips.pcm_stop_all()
	for v in 16:
		assert_false(chips.pcm_active(v))


func test_pcm_fade_ends_the_voice() -> void:
	chips.pcm_load(0, _square(110000), 11000.0, 0)
	var e: int = chips.pcm_start_extra(0, 0x100, 0x80)
	chips.render(100)
	chips.pcm_fade(e, 1000)
	var a := _peak(chips.render(200))
	chips.render(600)
	var b := _peak(chips.render(150))
	assert_lt(b, a, "fading")
	chips.render(100)
	assert_false(chips.pcm_active(e), "stopped after the fade (a loop)")
