extends "res://test/rom/rom_test_base.gd"
## MwSoundSamples: the sample list read from the ROM's instrument table, the
## decoding and the streams. Expectations come from the format (descriptors,
## end markers, the DPCM rule), never from ROM bytes written here; the
## byte-for-byte proof against harness/mw_harness/sound_samples.py is
## `soundz80_check.gd samples` (hashes in out/plan12/portz80/).


func _samples() -> MwSoundSamples:
	return MwSoundSamples.new(rom)


func test_rates_follow_the_z80_loops() -> void:
	assert_eq(MwSoundSamples.RAW_MIX_RATE, roundi(MwSoundSamples.Z80_HZ / MwSoundSamples.RAW_PERIOD_T))
	assert_eq(MwSoundSamples.DPCM_MIX_RATE, roundi(2.0 * MwSoundSamples.Z80_HZ / MwSoundSamples.DPCM_PAIR_T))
	assert_eq(MwSoundSamples.RAW_PERIOD_T, 324, "321 T + one bank read")
	assert_eq(MwSoundSamples.DPCM_PAIR_T, 655, "330 + 319 T + two bank reads per byte")


func test_volume_table() -> void:
	var unity := MwSoundSamples.volume_table(0x80)
	for i in 256:
		assert_eq(unity[i], i, "$80 is the identity")
	var off := MwSoundSamples.volume_table(0)
	assert_eq([off[0], off[0x80], off[0xFF]], [0x80, 0x80, 0x80], "0: constant $80")
	var half := MwSoundSamples.volume_table(0x40)
	assert_eq([half[0], half[0x80], half[0xFF]], [0x40, 0x80, 0xBF], "$40: half the swing")
	var loud := MwSoundSamples.volume_table(0xC0)
	assert_eq([loud[0x80], loud[0xC0]], [0x80, 0xE0], "x1.5 around $80")
	assert_eq(loud[0xD6], (0x80 + (0xD6 - 0x80) * 3 / 2) & 0xFF, "wraps around above 255")


func test_mix_and_the_four_channel_carry_bug() -> void:
	assert_eq(MwSoundSamples.mix(PackedInt32Array([0x90])), 0x90)
	assert_eq(MwSoundSamples.mix(PackedInt32Array([0x90, 0x70])), 0x80, "signed sum around $80")
	assert_eq(MwSoundSamples.mix(PackedInt32Array([0xF0, 0xF0])), 0xFF, "clamped")
	assert_eq(MwSoundSamples.mix(PackedInt32Array([0x10, 0x10, 0x10])), 0, "clamped")
	var four := PackedInt32Array([0xC0, 0xC0, 0x80, 0x80])
	assert_eq(MwSoundSamples.mix(four), 0, "the carry of ch0 + ch1 is lost: clips to 0")
	assert_eq(MwSoundSamples.mix(four, false), 0xFF, "the intended sum")
	assert_eq(MwSoundSamples.mix(PackedInt32Array([0x70, 0x70, 0x80, 0x80])), 0x60, "no carry: as intended")


func test_without_rom_the_list_is_empty() -> void:
	var s := MwSoundSamples.new(PackedByteArray())
	assert_eq(s.count(), 0)
	assert_eq(s.find(0x38, 0x8000), -1)


func test_descriptors_and_end_markers() -> void:
	if not need_rom():
		return
	var s := _samples()
	assert_gt(s.count(), 0)
	var kinds := {}
	for i in s.count():
		var d := s.desc(i)
		kinds[d.codec] = true
		assert_true(d.kind == 0 or d.kind == 3, "sample %d: kind 0 or 3" % i)
		assert_eq(rom[d.copies[0]], d.codec, "sample %d: the header's codec byte" % i)
		assert_eq(d.data, d.copies[0] + 1, "sample %d: data after the codec byte" % i)
		assert_eq(rom[d.data + d.length], 0, "sample %d: ends with the 0 marker" % i)
		assert_false(rom.slice(d.data, d.data + d.length).has(0), "sample %d: no 0 before it" % i)
		var a := MwSoundSamples.SAMPLE_BASE + d.offset
		var want := PackedInt32Array()
		for k in 32:
			if (d.bank_mask >> k) & 1:
				want.append((((a >> 15) + k) << 15) | (a & 0x7FFF))
		if want.is_empty():
			want.append(a)
		assert_eq(d.copies, want, "sample %d: a copy per bank-mask bit, k banks up" % i)
		for c in d.copies:
			assert_eq(c & 0x7FFF, d.copies[0] & 0x7FFF, "sample %d: copies at the same offset in their banks" % i)
			assert_eq(rom.slice(c, c + d.length + 2), rom.slice(d.copies[0], d.copies[0] + d.length + 2),
					"sample %d: identical copies" % i)
			assert_eq(s.find(c >> 15, (c & 0x7FFF) | 0x8000), i, "sample %d: found from any copy's trigger" % i)
		if d.loop and d.codec == MwSoundSamples.CODEC_RAW:
			assert_true(d.loops(), "sample %d: loop start inside the data" % i)
	assert_eq(kinds.keys().size(), 2, "raw and DPCM samples, no type 1")


func test_sound_ids_map_to_their_samples() -> void:
	if not need_rom():
		return
	var s := _samples()
	var ids := s.sound_id_map()
	assert_gt(ids.size(), 0)
	for sid: int in ids:
		var i := s.by_instrument(ids[sid])
		if i < 0:
			continue
		assert_true(s.desc(i).sound_ids.has(sid), "id $%02X listed by its sample" % sid)


func test_decode_raw_and_dpcm() -> void:
	if not need_rom():
		return
	var s := _samples()
	var deltas := s.dpcm_deltas()
	assert_eq(deltas.size(), 16)
	for i in s.count():
		var d := s.desc(i)
		var v := s.decode(i)
		assert_eq(v.size(), d.output_samples(), "sample %d: one value per DAC write" % i)
		if d.codec == MwSoundSamples.CODEC_RAW:
			assert_eq(v, rom.slice(d.data, d.data + d.length), "sample %d: raw = the data" % i)
		else:
			var first := rom[d.data]
			var a := (0x80 + deltas[first >> 4]) & 0xFF
			assert_eq([v[0], v[1]], [a, (a + deltas[first & 15]) & 0xFF], "sample %d: high nibble first, from $80" % i)
			var last := rom[d.data + d.length - 1]
			assert_eq(v[v.size() - 1], (v[v.size() - 2] + deltas[last & 15]) & 0xFF, "sample %d: deltas mod 256" % i)


func test_streams() -> void:
	if not need_rom():
		return
	var s := _samples()
	for i in s.count():
		var d := s.desc(i)
		var w := s.stream(i)
		assert_same(s.stream(i), w, "cached")
		assert_eq(w.format, AudioStreamWAV.FORMAT_16_BITS)
		assert_false(w.stereo)
		assert_eq(w.mix_rate, MwSoundSamples.DPCM_MIX_RATE if d.codec == MwSoundSamples.CODEC_DPCM else MwSoundSamples.RAW_MIX_RATE)
		assert_eq(w.data.size(), 2 * d.output_samples(), "sample %d: 16 bits per value" % i)
		var v := s.decode(i)
		for j in [0, v.size() / 2, v.size() - 1]:
			assert_eq(w.data.decode_s16(2 * j), (v[j] - 0x80) << 8, "sample %d value %d: (s - $80) << 8" % [i, j])
		if d.loops():
			assert_eq([w.loop_mode, w.loop_begin, w.loop_end], [AudioStreamWAV.LOOP_FORWARD, d.loop_start, d.length],
					"sample %d: loops from its loop start to the end" % i)
		else:
			assert_eq(w.loop_mode, AudioStreamWAV.LOOP_DISABLED, "sample %d: plays once" % i)


func test_ad_hoc_headers() -> void:
	if not need_rom():
		return
	var s := _samples()
	var n := s.count()
	var d := s.desc(0)
	assert_eq(s.add_header(d.copies[0]), 0, "a known header")
	assert_eq(s.count(), n)
	var h := d.data + 1          # inside the first sample: a header the 68000 never sends
	var i := s.add_header(h)
	assert_eq(i, n)
	assert_eq(s.find_header(h), i)
	var e := s.desc(i)
	assert_eq(e.instrument, -1)
	assert_eq(rom[e.data + e.length], 0, "runs to the next 0")
