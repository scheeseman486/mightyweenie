extends "res://test/rom/rom_test_base.gd"
## MwSoundZ80, the port of what the Z80 sound driver does: a batch's chip
## writes in the original's order, the PCM channels (starts, stops, updates,
## the ch0 rule, loops, ends, the status handshake with the 68000), the DAC
## switch, and the mixing time per tick. Batches are built by hand; samples are
## picked from MwSoundSamples by their properties (no ROM bytes here). The
## proofs against the driver's code and the measured busy lengths are
## `soundz80_check.gd` and out/plan12/portz80/.


## Records the MwSoundOut calls as arrays.
class Recorder extends MwSoundOut:
	var calls: Array = []

	func ym_write(port: int, reg: int, value: int) -> void:
		calls.append(["ym", port, reg, value])

	func psg_write(value: int) -> void:
		calls.append(["psg", value])

	func pcm_start(ch: int, sample: int, from_index: int) -> void:
		calls.append(["start", ch, sample, from_index])

	func pcm_stop(ch: int) -> void:
		calls.append(["stop", ch])

	func pcm_rate(ch: int, step: int) -> void:
		calls.append(["rate", ch, step])

	func pcm_volume(ch: int, volume: int) -> void:
		calls.append(["volume", ch, volume])

	func take() -> Array:
		var c := calls
		calls = []
		return c

	func of(kind: String) -> Array:
		return calls.filter(func(c: Array) -> bool: return c[0] == kind)


var rec: Recorder


func before_each() -> void:
	rec = Recorder.new()


func _z80(with_rom := true) -> MwSoundZ80:
	return MwSoundZ80.new(rom if with_rom else PackedByteArray(), rec)


## A batch with no commands: every command byte `$FF` (as the 68000 leaves
## its shadow after a copy, `$15BA8`).
static func _batch() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(MwSoundZ80.BATCH_LEN)
	b.fill(0xFF)
	return b


## PCM trigger [param k]: start the sample whose header is at ROM [param header]
## (as `$17CDE` / `$17556` build it).
static func _start(b: PackedByteArray, k: int, header: int, step := 0x100, volume := 0x80, loop_start := -1) -> void:
	var o := MwSoundZ80.PCM_TRIGGERS + 12 * k
	var w := (header & 0x7FFF) | 0x8000
	b[o] = 0
	b[o + 1] = 1
	b[o + 2] = step >> 8
	b[o + 3] = step & 0xFF
	b[o + 4] = volume
	b[o + 5] = header >> 15
	b[o + 6] = w >> 8
	b[o + 7] = w & 0xFF
	b[o + 8] = 0
	if loop_start >= 0:
		var la := header + loop_start
		var lw := (la & 0x7FFF) | 0x8000
		b[o + 8] = 1
		b[o + 9] = la >> 15
		b[o + 10] = lw >> 8
		b[o + 11] = lw & 0xFF
	b[MwSoundZ80.BATCH_BANK] = header >> 15


static func _stop(b: PackedByteArray, k: int) -> void:
	var o := MwSoundZ80.PCM_TRIGGERS + 12 * k
	b[o] = 0
	b[o + 1] = 0


## PCM update of channel [param k] (`$17E62` / `$17EA2`): -1 = unchanged.
static func _update(b: PackedByteArray, k: int, step := -1, volume := -1) -> void:
	var o := MwSoundZ80.PCM_TRIGGERS + 12 * k
	b[o] = 0
	b[o + 1] = 0xFF
	if step >= 0:
		b[o + 2] = step >> 8
		b[o + 3] = step & 0xFF
	if volume >= 0:
		b[o + 4] = volume


## One tick of the service loop; returns the calls it made.
func _tick(z: MwSoundZ80, b: PackedByteArray = PackedByteArray()) -> Array:
	if not b.is_empty():
		z.apply_batch(b)
	z.advance(not b.is_empty())
	return rec.take()


## The first sample matching [param pred] (MwSoundSamples index), or -1.
static func _pick(z: MwSoundZ80, pred: Callable) -> int:
	for i in z.samples.count():
		if pred.call(z.samples.desc(i)):
			return i
	return -1


static func _raw_once(d: MwSoundSamples.Desc) -> bool:
	return d.codec == MwSoundSamples.CODEC_RAW and not d.loops()


# --- the chips ---------------------------------------------------------------------

func test_reset_uploads_the_driver_and_the_patches() -> void:
	if not need_rom():
		return
	var z := _z80()
	var n := (rom[MwSoundZ80.Z80_DRIVER] << 8) | rom[MwSoundZ80.Z80_DRIVER + 1]
	var m := (rom[MwSoundZ80.FM_PATCHES_LEN] << 8) | rom[MwSoundZ80.FM_PATCHES_LEN + 1]
	assert_eq(z.ram.slice(n, n + m), rom.slice(MwSoundZ80.FM_PATCHES, MwSoundZ80.FM_PATCHES + m), "patches after the driver")
	assert_eq(z.ram.slice(0, n), rom.slice(MwSoundZ80.Z80_DRIVER + 2, MwSoundZ80.Z80_DRIVER + 2 + n))
	for k in 4:
		assert_eq(z.voice_status(k), 0)
	assert_false(z.dac_on)
	assert_false(z.batch_pending(), "every batch is taken at once")
	assert_eq(rec.calls, [], "the upload writes no chip register")


func test_fm_block_order_key_frequency_tl() -> void:
	var z := _z80(false)
	var b := _batch()
	var o := 3 * 10                     # block 3 = YM channel code 4 (part II, channel 0)
	b[o] = 0
	b[o + 1] = 1                        # key on
	b[o + 3] = 0x22                     # TL
	b[o + 4] = 0                        # frequency
	b[o + 5] = 0b1011                   # operators 1, 2, 4
	b[o + 8] = 0x23
	b[o + 9] = 0x45
	z.apply_batch(b)
	assert_eq(rec.take(), [["ym", 0, 0x28, 4], ["ym", 0, 0x28, 0xF4],
			["ym", 1, 0xA4, 0x23], ["ym", 1, 0xA0, 0x45],
			["ym", 1, 0x40, 0x22], ["ym", 1, 0x48, 0x22], ["ym", 1, 0x4C, 0x22]])
	b = _batch()
	b[20] = 0                           # block 2 = channel code 2: key off only
	b[21] = 0
	z.apply_batch(b)
	assert_eq(rec.take(), [["ym", 0, 0x28, 2]])


func test_fm_patch_from_z80_ram() -> void:
	if not need_rom():
		return
	var z := _z80()
	var base := (rom[MwSoundZ80.Z80_DRIVER] << 8) | rom[MwSoundZ80.Z80_DRIVER + 1]
	var regs := z.ram.slice(MwSoundZ80.Z80_PATCH_REGS, MwSoundZ80.Z80_PATCH_REGS + 26)
	for block in [1, 5]:
		var code: int = MwSoundZ80.FM_CODES[block]
		var patch := base + 26 * 2
		var b := _batch()
		b[10 * block] = 0
		b[10 * block + 2] = 0           # load the patch at +6/+7
		b[10 * block + 1] = 0           # then key off
		b[10 * block + 6] = patch >> 8
		b[10 * block + 7] = patch & 0xFF
		z.apply_batch(b)
		var calls := rec.take()
		assert_eq(calls.size(), 27, "26 patch registers, then the key")
		for i in 26:
			assert_eq(calls[i], ["ym", 1 if code & 4 else 0, regs[i] + (code & 3), rom[MwSoundZ80.FM_PATCHES + 52 + i]])
		assert_eq(calls[26], ["ym", 0, 0x28, code])


func test_psg_block_order_off_tone_attenuation() -> void:
	var z := _z80(false)
	var b := _batch()
	var o := MwSoundZ80.PSG_BLOCKS + 6 * 1
	b[o] = 0
	b[o + 1] = 0                        # off
	b[o + 2] = 5                        # attenuation
	b[o + 3] = 0                        # tone
	b[o + 4] = 0x01
	b[o + 5] = 0x23                     # N = $123
	var n := MwSoundZ80.PSG_BLOCKS + 6 * 3
	b[n] = 0
	b[n + 3] = 0                        # noise mode
	b[n + 5] = 0x05
	z.apply_batch(b)
	assert_eq(rec.take(), [["psg", 0xBF], ["psg", 0xA3], ["psg", 0x12], ["psg", 0xB5], ["psg", 0xE5]])


func test_blocks_fm_then_psg_then_pcm() -> void:
	if not need_rom():
		return
	var z := _z80()
	var i := _pick(z, _raw_once)
	var b := _batch()
	_start(b, 0, z.samples.desc(i).copies[0])
	b[MwSoundZ80.PSG_BLOCKS] = 0
	b[MwSoundZ80.PSG_BLOCKS + 2] = 3
	b[50] = 0                           # FM block 5
	b[51] = 0
	z.apply_batch(b)
	var kinds := rec.take().map(func(c: Array) -> String: return c[0])
	assert_eq(kinds, ["ym", "psg", "start", "ym", "rate", "volume"], "FM, PSG, PCM, DAC on, effective values")


# --- PCM channels --------------------------------------------------------------------

func test_start_dac_and_end() -> void:
	if not need_rom():
		return
	var z := _z80()
	var i := _pick(z, _raw_once)
	var d := z.samples.desc(i)
	var b := _batch()
	_start(b, 2, d.copies[0])
	assert_eq(_tick(z, b).slice(0, 4), [["start", 2, i, 0], ["ym", 0, 0x2B, 0x80], ["rate", 2, 0x100], ["volume", 2, 0x80]])
	assert_eq(z.voice_status(2), MwSoundZ80.STATUS_PLAYING)
	assert_eq(z.active(), PackedInt32Array([2]))
	var ticks := 1
	var outputs := PackedInt32Array([z.channels[2].outputs])
	var calls := []
	while z.voice_status(2) == MwSoundZ80.STATUS_PLAYING and ticks < 1000:
		calls = _tick(z)
		ticks += 1
		outputs.append(z.channels[2].outputs)
	assert_eq(z.voice_status(2), MwSoundZ80.STATUS_ENDED, "ended")
	assert_eq(calls, [["stop", 2], ["ym", 0, 0x2B, 0x00]], "the end, then the DAC off")
	assert_eq(z.channels[2].outputs, d.length, "one output per byte")
	assert_eq(z.position(2), d.length, "at the end marker")
	for t in range(2, outputs.size() - 1):
		var per := outputs[t] - outputs[t - 1]
		assert_true(per == 183 or per == 184, "a tick without a batch mixes (59 736 - 354) / 324 outputs, got %d" % per)
	assert_eq(_tick(z), [], "nothing more")
	assert_eq(z.voice_status(2), MwSoundZ80.STATUS_ENDED, "until the 68000 clears it")
	z.clear_voice(2)
	assert_eq(z.voice_status(2), 0)
	b = _batch()
	_stop(b, 2)
	assert_eq(_tick(z, b), [], "a stop of an ended channel plays nothing")


func test_stop_command() -> void:
	if not need_rom():
		return
	var z := _z80()
	var i := _pick(z, _raw_once)
	var b := _batch()
	_start(b, 1, z.samples.desc(i).copies[0])
	_tick(z, b)
	_tick(z)
	b = _batch()
	_stop(b, 1)
	assert_eq(_tick(z, b), [["stop", 1], ["ym", 0, 0x2B, 0x00]])
	assert_eq(z.voice_status(1), 0, "stopped, not ended")


## `$13C04` re-uploads the driver (quirk 28): the samples stop at once, the
## DAC flag is forgotten while YM `$2B` keeps `$80` until a sample ends again.
func test_reset_stops_samples_and_forgets_the_dac() -> void:
	if not need_rom():
		return
	var z := _z80()
	var d := z.samples.desc(_pick(z, _raw_once))
	var b := _batch()
	_start(b, 0, d.copies[0])
	_start(b, 3, d.copies[0])
	_tick(z, b)
	_tick(z)
	z.reset()
	assert_eq(rec.take(), [["stop", 0], ["stop", 3]], "both stop, no DAC write")
	for k in 4:
		assert_eq(z.voice_status(k), 0)
	assert_false(z.dac_on, "the Z80 forgot it switched the DAC on")
	assert_eq(_tick(z), [], "the DAC stays on (FM 6 muted)")
	b = _batch()
	_start(b, 1, d.copies[0])
	var calls := _tick(z, b)
	assert_eq(calls.slice(0, 2), [["start", 1, z.samples.find_header(d.copies[0]), 0], ["ym", 0, 0x2B, 0x80]], "switched on again")
	while z.voice_status(1) == MwSoundZ80.STATUS_PLAYING:
		calls = _tick(z)
	assert_eq(calls, [["stop", 1], ["ym", 0, 0x2B, 0x00]], "off when that sample ends")
	z.reset()
	assert_eq(rec.take(), [], "nothing playing: nothing to stop")


func test_ch0_rule_and_effective_values() -> void:
	if not need_rom():
		return
	var z := _z80()
	var a := z.samples.desc(_pick(z, func(d: MwSoundSamples.Desc) -> bool: return _raw_once(d) and d.length > 3000))
	var c := z.samples.desc(_pick(z, func(d: MwSoundSamples.Desc) -> bool: return d.loops()))
	var b := _batch()
	_start(b, 0, a.copies[0], 0x180, 0x60)
	assert_eq(_tick(z, b).slice(2), [["rate", 0, 0x180], ["volume", 0, 0x60]], "alone: ch0, its own pitch and volume")
	b = _batch()
	_start(b, 3, c.copies[0], 0xE0, 0x20, c.loop_start)
	var calls := _tick(z, b)
	assert_eq(calls.slice(1), [["rate", 0, 0x100], ["volume", 0, 0x80], ["rate", 3, 0xE0], ["volume", 3, 0x20]],
			"$EE comes first: ch0 = channel 3; channel 0 plays at step $100, volume $80")
	assert_eq(z.active(), PackedInt32Array([3, 0]))
	var p0 := z.position(0)
	var o0 := z.channels[0].outputs
	_tick(z)
	_tick(z)
	assert_eq(z.position(0) - p0, z.channels[0].outputs - o0, "channel 0: one byte per output")
	assert_between(z.channels[0].outputs - o0, 366, 368, "2 x (59 736 - 354) / 323 T: the 2-channel loop")
	b = _batch()
	_update(b, 0, 0x140, 0x70)
	assert_eq(_tick(z, b), [], "an update of a channel that is not ch0 changes nothing heard")
	b = _batch()
	_update(b, 3, -1, 0x30)
	assert_eq(_tick(z, b), [["volume", 3, 0x30]])
	b = _batch()
	_stop(b, 3)
	assert_eq(_tick(z, b), [["stop", 3], ["rate", 0, 0x140], ["volume", 0, 0x70]],
			"channel 0 is ch0 again, with the pitch and volume it was given meanwhile")


func test_ch0_advances_by_its_step() -> void:
	if not need_rom():
		return
	var z := _z80()
	var d := z.samples.desc(_pick(z, func(e: MwSoundSamples.Desc) -> bool: return _raw_once(e) and e.length > 3000))
	var b := _batch()
	_start(b, 3, d.copies[0], 0x80)
	_tick(z, b)
	var o := z.channels[3].outputs
	var p := z.channels[3].index * 256 + z.channels[3].frac
	_tick(z)
	_tick(z)
	var ch := z.channels[3]
	assert_eq(ch.index * 256 + ch.frac - p, (ch.outputs - o) * 0x80, "8.8 step per output")


func test_loop_never_ends() -> void:
	if not need_rom():
		return
	var z := _z80()
	var i := _pick(z, func(d: MwSoundSamples.Desc) -> bool: return d.loops())
	var d := z.samples.desc(i)
	var b := _batch()
	_start(b, 3, d.copies[0], 0x100, 0x80, d.loop_start)
	_tick(z, b)
	var ticks := 3 * d.length / 180 + 5
	for t in ticks:
		assert_eq(_tick(z), [], "no call while it loops")
	assert_eq(z.voice_status(3), MwSoundZ80.STATUS_PLAYING)
	assert_gt(z.channels[3].outputs, 2 * d.length)
	assert_between(z.position(3), d.loop_start, d.length)


func test_dpcm_alone_ignores_the_step() -> void:
	if not need_rom():
		return
	var z := _z80()
	var i := _pick(z, func(d: MwSoundSamples.Desc) -> bool: return d.codec == MwSoundSamples.CODEC_DPCM)
	var d := z.samples.desc(i)
	var b := _batch()
	_start(b, 3, d.copies[0], 0x200, 0x40)
	assert_eq(_tick(z, b).slice(2), [["rate", 3, 0x100], ["volume", 3, 0x40]], "one code per output; the volume table applies")
	var ticks := 1
	while z.voice_status(3) == MwSoundZ80.STATUS_PLAYING and ticks < 1000:
		_tick(z)
		ticks += 1
	assert_eq(z.channels[3].outputs, 2 * d.length, "two outputs per byte")
	var expect := 2 * d.length * 655 / 2 / (MwSoundZ80.FRAME_T - 354)
	assert_between(ticks, expect, expect + 2, "ends after its length at 655 T per byte")


func test_restart_while_playing() -> void:
	if not need_rom():
		return
	var z := _z80()
	var i := _pick(z, _raw_once)
	var b := _batch()
	_start(b, 0, z.samples.desc(i).copies[0])
	_tick(z, b)
	_tick(z)
	assert_gt(z.position(0), 0)
	assert_eq(_tick(z, b), [["start", 0, i, 0], ["rate", 0, 0x100], ["volume", 0, 0x80]], "restarted, DAC already on")
	assert_lt(z.position(0), 190)


func test_two_starts_one_dac_switch() -> void:
	if not need_rom():
		return
	var z := _z80()
	var i := _pick(z, _raw_once)
	var b := _batch()
	_start(b, 0, z.samples.desc(i).copies[0])
	_start(b, 1, z.samples.desc(i).copies[0])
	var calls := _tick(z, b)
	assert_eq(calls.filter(func(c: Array) -> bool: return c[0] == "ym"), [["ym", 0, 0x2B, 0x80]])
	b = _batch()
	_stop(b, 0)
	assert_eq(_tick(z, b), [["stop", 0]], "one still plays: the DAC stays on")
	b = _batch()
	_stop(b, 1)
	assert_eq(_tick(z, b), [["stop", 1], ["ym", 0, 0x2B, 0x00]])


func test_the_status_handshake_with_the_68000() -> void:
	if not need_rom():
		return
	var z := _z80()
	var s := MwSound68k.new(rom)
	s.reset()
	var sid := -1
	for id: int in z.samples.sound_id_map():
		var j := z.samples.by_instrument(z.samples.sound_id_map()[id])
		if j >= 0 and _raw_once(z.samples.desc(j)):
			sid = id
			break
	var h := s.sound_play(sid)
	var ended := -1
	var freed := -1
	for t in 400:
		var batch := s.vblank(z)
		if not batch.is_empty():
			z.apply_batch(batch)
		z.advance(not batch.is_empty())
		if ended < 0 and z.active().is_empty():
			ended = t
		if not s.sound_busy(h):
			freed = t
			break
	assert_gt(ended, 0)
	assert_eq(freed, ended + 1, "the 68000 frees the voice at the tick after the Z80's $F0")
	for k in 4:
		assert_eq(z.voice_status(k), 0, "and clears the status")


func test_volume_rebuild_costs_mixing_time() -> void:
	if not need_rom():
		return
	var z := _z80()
	var d := z.samples.desc(_pick(z, func(e: MwSoundSamples.Desc) -> bool: return e.loops()))
	var b := _batch()
	_start(b, 3, d.copies[0], 0x100, 0x80, d.loop_start)
	_tick(z, b)
	var o := z.channels[3].outputs
	b = _batch()
	_update(b, 3, -1, 0x80)
	_tick(z, b)
	var same := z.channels[3].outputs - o
	o = z.channels[3].outputs
	b = _batch()
	_update(b, 3, -1, 0x90)
	_tick(z, b)
	var rebuilt := z.channels[3].outputs - o
	assert_almost_eq(same - rebuilt, MwSoundZ80.VOL_REBUILD_T / 324, 1, "a new volume: 12 100 T without output")


func test_channel_bytes_as_the_z80_keeps_them() -> void:
	if not need_rom():
		return
	var z := _z80()
	var r := z.samples.desc(_pick(z, func(e: MwSoundSamples.Desc) -> bool: return e.loops()))
	var d := z.samples.desc(_pick(z, func(e: MwSoundSamples.Desc) -> bool: return e.codec == MwSoundSamples.CODEC_DPCM))
	var b := _batch()
	_start(b, 3, r.copies[0], 0xE0, 0x40, r.loop_start)
	_tick(z, b)
	_tick(z)
	var c := z.channel_bytes(3)
	var a := r.data + z.channels[3].index
	assert_eq(c.size(), 16)
	assert_eq([c[0], c[1] | (c[2] << 8), c[3]], [1, 0x8000 | (a & 0x7FFF), a >> 15], "status, pointer in the window, bank")
	assert_eq([c[4], c[5] | (c[6] << 8), c[7]], [1, 0x8000 | ((r.data + r.loop_start) & 0x7FFF), (r.data + r.loop_start) >> 15],
			"loop flag, loop address (the trigger's + 1), loop bank")
	assert_eq([c[8], c[9], c[11], c[12]], [0x00, 0xE0, 0x40, MwSoundSamples.CODEC_RAW], "step, volume, codec")
	b = _batch()
	_start(b, 2, d.copies[0])
	_tick(z, b)
	_stop(b, 3)
	b[MwSoundZ80.PCM_TRIGGERS + 24] = 0xFF      # only the stop of channel 3
	_tick(z, b)
	_tick(z)
	c = z.channel_bytes(2)
	var t := z.position(2)
	assert_eq([c[12], c[14], c[15]], [MwSoundSamples.CODEC_DPCM, t & 1, z.samples.decode(z.samples.find_header(d.copies[0]))[t - 1]],
			"DPCM: nibble phase and the value after the last code")
