extends "res://test/rom/rom_test_base.gd"
## MwSound68k, the port of the 68000 sound driver: its state after a reset,
## handles and busy answers of voices and sequences, the structure of a
## sequence's first block, the crowd glide, the positional sounds' 60-tick
## limit, the music fade-out and a pending Z80. The tick-by-tick proof
## against the reference model is test/audio/sound68k_check.gd (recordings
## in out/plan12/port68k/, ROM-derived); these tests read no expectations
## from the ROM beyond what the driver itself reads.

const Check := preload("res://test/audio/sound68k_check.gd")

## Sound ids used here (the game's API numbers): a sample voice (puck), a
## sequence (the coach voice), a looping voice (the crowd instrument by id).
const VOICE_ID := 0x27
const SEQUENCE_ID := 0x0B


func _driver() -> MwSound68k:
	var s := MwSound68k.new(rom)
	s.reset()
	return s


## Offset of channel [param n]'s change record in the block.
static func _rec(s: MwSound68k, n: int) -> int:
	return (s.r32(s.channel(n) + MwSound68k.CH_RECORD) & 0xFFFF) - (MwSound68k.RECORDS & 0xFFFF)


## The voice channel (10-13) holding [param handle], or -1.
static func _voice_channel(s: MwSound68k, handle: int) -> int:
	for n in range(10, 14):
		var c := s.channel(n)
		if s.r8(c + MwSound68k.CH_STATE) == 1 and s.r32(c + MwSound68k.CH_CACHE) == handle:
			return n
	return -1


func test_memory_helpers_are_big_endian() -> void:
	var s := MwSound68k.new(PackedByteArray())
	s.w32(0xFFE6A6, 0x12345678)
	assert_eq([s.r8(0xFFE6A6), s.r8(0xFFE6A9)], [0x12, 0x78])
	assert_eq(s.r16(0xFFE6A8), 0x5678)
	assert_eq(s.r32(0xFFFFE6A6), 0x12345678, "addresses wrap to the low word, as $FFFFxxxx pointers")
	s.w16(0xFFE6AE, -2)
	assert_eq(s.r16(0xFFE6AE), 0xFFFE)
	assert_eq(MwSound68k._s16(0xFFFE), -2)
	assert_eq(MwSound68k._s8(0x80), -128)


func test_reset_state() -> void:
	if not need_rom():
		return
	var s := _driver()
	assert_eq(s.r32(MwSound68k.MUSIC_HANDLE), 0xFFFFFFFF, "no music")
	assert_eq(s.r32(MwSound68k.MUSIC_SEQ), 0)
	assert_eq(s.r32(MwSound68k.CROWD_HANDLE), 0xFFFFFFFF, "no crowd")
	assert_eq(s.r32(MwSound68k.POSITIONAL), 0xFFFFFFFF, "no positional sound")
	assert_eq(s.r16(MwSound68k.API_DEPTH), 0)
	assert_eq(s.r32(MwSound68k.INSTRUMENT_BASE), MwSound68k.INSTRUMENTS)
	assert_eq(s.r32(MwSound68k.SAMPLE_BASE), MwSound68k.SAMPLES)
	assert_eq(s.r16(MwSound68k.DRIVER_LENGTH), s.rom16(MwSound68k.Z80_DRIVER), "the FM patches follow the Z80 driver")
	assert_eq(s.r8(MwSound68k.TRACKS_ACTIVE), 0)
	assert_eq(s.r8(MwSound68k.QUEUE_COUNT), 0)
	assert_eq(s.r32(MwSound68k.QUEUE_HEAD), MwSound68k.QUEUE | 0xFF000000, "pointers as the original stores them")
	assert_eq(s.r32(MwSound68k.QUEUE_TAIL), s.r32(MwSound68k.QUEUE_HEAD))
	for i in MwSound68k.N_TRACKS:
		var t := s.track_state(i)
		assert_eq(t.state, 1, "track %d free" % i)
		assert_eq(s.r8(MwSound68k.TRACKS + i * MwSound68k.TRACK_SIZE + MwSound68k.TR_SLOT), i)
	var records := {}
	for n in MwSound68k.N_CHANNELS:
		var c := s.channel_state(n)
		assert_eq([c.state, c.instrument], [0xFF, 0xFFFFFFFF], "channel %d free" % n)
		assert_eq(s.r8(s.channel(n) + MwSound68k.CH_INDEX), n)
		var o := _rec(s, n)
		assert_true(o >= 0 and o < MwSound68k.RECORDS_LEN, "channel %d's record inside the block" % n)
		records[o] = true
	assert_eq(records.size(), MwSound68k.N_CHANNELS, "one record per channel")
	for ch in 16:
		assert_eq(s.r8(MwSound68k.VOLUMES + ch), 0x7F, "MIDI channel volume")
	assert_eq(s.ram_image().size(), (MwSound68k.GAME_VARS_END - MwSound68k.GAME_VARS_START) + (MwSound68k.DRIVER_VARS_END - MwSound68k.DRIVER_VARS_START))


func test_first_tick_sends_key_off_everywhere() -> void:
	if not need_rom():
		return
	var s := _driver()
	var z := Check.make_stub(rom)
	var block := s.vblank(z)
	assert_eq(block.size(), MwSound68k.RECORDS_LEN, "the 133 bytes for Z80 $0038")
	for n in MwSound68k.N_CHANNELS:
		var o := _rec(s, n)
		assert_eq([block[o], block[o + 1]], [0, 0], "channel %d: changed, key off" % n)
	assert_eq(s.r8(MwSound68k.DIRTY), 0, "the records are marked unchanged after the copy")
	assert_eq(s.r8(_rec(s, 0) + MwSound68k.RECORDS), 0xFF, "flag bytes back to $FF")
	assert_true(s.vblank(z).is_empty(), "nothing changed: no block")
	assert_eq(s.skipped, MwSound68k.Skip.NONE)


func test_voice_handle_and_busy() -> void:
	if not need_rom():
		return
	var s := _driver()
	var z := Check.make_stub(rom)
	s.vblank(z)
	var h := s.sound_play(VOICE_ID)
	assert_eq(h, 1, "the first voice handle")
	assert_true(s.sound_busy(h))
	var n := _voice_channel(s, h)
	assert_true(n >= 10, "a PCM voice channel holds the handle")
	var k := n - 10
	# the Z80 reports the end in the tick the start goes out: not freed yet
	z.status[k] = 0xF0
	var block := s.vblank(z)
	var o := _rec(s, n)
	assert_eq([block[o], block[o + 1]], [0, 1], "start command")
	assert_eq((block[o + 2] << 8) | block[o + 3], 0x100, "rate 1:1")
	assert_eq(block[o + 4], 0x80, "volume $100 / 2")
	assert_eq((block[o + 6] & 0x80), 0x80, "address in the Z80's bank window")
	assert_eq(z.clears.size(), 0, "a voice with a command this tick is not freed")
	assert_true(s.sound_busy(h))
	# the next tick: freed, the Z80 status cleared
	z.status[k] = 0xF0
	s.vblank(z)
	assert_eq(Array(z.clears), [k])
	assert_false(s.sound_busy(h), "the Z80's end frees the voice")
	# stop: busy ends at once and the stop goes out at the next tick
	var h2 := s.sound_play(VOICE_ID)
	assert_eq(h2, h + 1)
	n = _voice_channel(s, h2)
	s.sound_stop(h2)
	assert_false(s.sound_busy(h2))
	block = s.vblank(z)
	o = _rec(s, n)
	assert_eq([block[o], block[o + 1]], [0, 0], "stop command")


func test_sequence_handle_and_busy() -> void:
	if not need_rom():
		return
	var s := _driver()
	var z := Check.make_stub(rom)
	var h := s.sound_play(SEQUENCE_ID)
	assert_eq(h & 0x80000000, 0x80000000, "sequence handles have bit 31 set")
	assert_eq(h & 0x7FFFFFFF, s.r32(MwSound68k.SEQ_HANDLE))
	assert_true(s.sound_busy(h))
	var seq := s.rom32(MwSound68k.SEQUENCES + 4 * SEQUENCE_ID)
	assert_eq(s.r8(MwSound68k.TRACKS_ACTIVE), s.rom16(seq + 2), "one track slot per track of the sequence")
	var ticks := 0
	while s.sound_busy(h) and ticks < 2000:
		s.vblank(z)
		ticks += 1
	assert_true(ticks > 1 and ticks < 2000, "the sequence ends by itself (%d ticks)" % ticks)
	assert_eq(s.r8(MwSound68k.TRACKS_ACTIVE), 0)
	var h2 := s.sound_play(SEQUENCE_ID)
	assert_eq(h2, h + 1)
	s.sound_stop(h2)
	assert_false(s.sound_busy(h2), "stopped")


func test_music_first_block_structure() -> void:
	if not need_rom():
		return
	var s := _driver()
	var z := Check.make_stub(rom)
	s.vblank(z)
	s.music_title()
	assert_eq(s.r8(MwSound68k.TRACKS_ACTIVE), s.rom16(MwSound68k.MUSIC_TITLE + 2))
	var block := PackedByteArray()
	for i in 600:
		block = s.vblank(z)
		if not block.is_empty():
			break
	assert_false(block.is_empty(), "the music sends a block")
	var key_ons := 0
	for n in MwSound68k.N_CHANNELS:
		var o := _rec(s, n)
		if block[o] != 0:
			continue
		if n < 6:       # FM record: key, patch, attenuation, frequency
			assert_true(block[o + 1] in [0, 1], "FM %d key byte" % n)
			if block[o + 1] == 1:
				key_ons += 1
				assert_eq(block[o + 4], 0, "FM %d: frequency sent with the note" % n)
				var bf := (block[o + 8] << 8) | block[o + 9]
				assert_true(bf >> 11 < 8 and (bf & 0x7FF) < 0x800, "FM %d: block << 11 | F-number" % n)
				assert_true(block[o + 3] <= 0x7F, "FM %d: attenuation" % n)
			if block[o + 2] == 0:
				var patch := (block[o + 6] << 8) | block[o + 7]
				assert_true(patch >= s.r16(MwSound68k.DRIVER_LENGTH), "FM %d: patch after the Z80 driver" % n)
		elif n < 10:
			fail_test("PSG / noise channel %d used: the game has no such instrument" % n)
		else:           # PCM record: start with an address in the bank window
			assert_true(block[o + 1] in [0, 1, 0xFF])
			if block[o + 1] == 1:
				key_ons += 1
				assert_eq(block[o + 6] & 0x80, 0x80)
				assert_eq(block[o + 5], block[MwSound68k.BANK_SHADOW - MwSound68k.RECORDS], "bank also kept in the block's last byte")
	assert_true(key_ons > 0, "notes start in the first block")


func test_crowd_glide() -> void:
	if not need_rom():
		return
	var s := _driver()
	var z := Check.make_stub(rom)
	s.vblank(z)
	s.crowd_level(1000)
	var h := s.r32(MwSound68k.CROWD_HANDLE)
	assert_eq(_voice_channel(s, h), 13, "the crowd plays on the fourth PCM voice")
	assert_eq([s.r16(MwSound68k.CROWD_RATE), s.r16(MwSound68k.CROWD_VOL)], [0xE0, 0x40], "started at rate $E0, volume $40")
	assert_eq([s.r16(MwSound68k.CROWD_RATE_TARGET), s.r16(MwSound68k.CROWD_VOL_TARGET)], [0xC0 + 0x80, 0x80 + 0x100], "q = 1000 * $80 / 1000")
	var o := _rec(s, 13)
	var block := s.vblank(z)
	assert_eq([s.r16(MwSound68k.CROWD_RATE), s.r16(MwSound68k.CROWD_VOL)], [0xE4, 0x48], "+4 / +8 per tick")
	assert_eq((block[o + 2] << 8) | block[o + 3], 0xE4, "rate to the Z80")
	assert_eq(block[o + 4], 0x48 >> 1, "volume / 2 to the Z80")
	for i in 40:
		s.vblank(z)
	assert_eq([s.r16(MwSound68k.CROWD_RATE), s.r16(MwSound68k.CROWD_VOL)], [0x140, 0x180], "targets reached and held")
	s.crowd_level(0)
	s.vblank(z)
	assert_eq([s.r16(MwSound68k.CROWD_RATE), s.r16(MwSound68k.CROWD_VOL)], [0x13C, 0x178], "gliding down")
	s.crowd_fade()
	var ticks := 0
	while s.sound_busy(h) and ticks < 100:
		s.vblank(z)
		ticks += 1
	assert_eq(ticks, 0x178 >> 3, "faded out at -8 per tick, then stopped")
	assert_eq(s.r32(MwSound68k.CROWD_HANDLE), 0xFFFFFFFF)


func test_positional_sixty_tick_limit() -> void:
	if not need_rom():
		return
	var s := _driver()
	var z := Check.make_stub(rom)
	s.vblank(z)
	assert_eq(s.positional(VOICE_ID, false), VOICE_ID, "off screen: nothing, d0 = the id")
	assert_eq(s.r32(MwSound68k.POSITIONAL), 0xFFFFFFFF)
	assert_eq(s.positional(VOICE_ID, true), VOICE_ID)
	var h := s.r32(MwSound68k.POSITIONAL)
	assert_true(s.sound_busy(h))
	for i in 59:
		s.vblank(z)
	assert_true(s.sound_busy(h), "still playing after 59 ticks")
	s.vblank(z)
	assert_false(s.sound_busy(h), "stopped at the 60th tick")
	# any sound_play cuts the last positional sound (quirk Q2)
	s.positional(VOICE_ID, true)
	h = s.r32(MwSound68k.POSITIONAL)
	s.vblank(z)
	s.sound_play(VOICE_ID)
	assert_false(s.sound_busy(h), "cut by the next sound")


func test_music_fade_out_and_repeat() -> void:
	if not need_rom():
		return
	var s := _driver()
	var z := Check.make_stub(rom)
	s.music_game()
	var h := s.r32(MwSound68k.MUSIC_HANDLE)
	s.music_game()
	assert_eq(s.r32(MwSound68k.MUSIC_HANDLE), h, "the same music does not restart")
	s.vblank(z)
	s.music_fade_out(30)
	for i in 29:
		s.vblank(z)
	assert_eq(s.r32(MwSound68k.MUSIC_SEQ), MwSound68k.MUSIC_GAME, "still on before the count ends")
	s.vblank(z)
	assert_eq(s.r32(MwSound68k.MUSIC_SEQ), 0, "stopped after 30 ticks")
	assert_eq(s.r32(MwSound68k.MUSIC_HANDLE), 0xFFFFFFFF)
	assert_eq(s.r8(MwSound68k.TRACKS_ACTIVE), 0)


func test_random_sound_is_sound_five_to_eight() -> void:
	if not need_rom():
		return
	for v in [0, 1, 2, 3, 0xFFFE]:
		var a := _driver()
		var b := _driver()
		assert_eq(a.random_sound(v), b.sound_play(5 + (v & 3)))
		assert_true(a.ram_image() == b.ram_image(), "rng value $%X: the same state" % v)


func test_pending_z80_skips_the_tick() -> void:
	if not need_rom():
		return
	var s := _driver()
	var z := Check.make_stub(rom)
	s.music_title()
	z.pending = true
	var game_vars := MwSound68k.GAME_VARS_END - MwSound68k.GAME_VARS_START
	var before := s.ram_image().slice(game_vars)
	var age := s.r16(MwSound68k.POSITIONAL_AGE)
	assert_true(s.vblank(z).is_empty())
	assert_eq(s.skipped, MwSound68k.Skip.Z80)
	assert_true(s.ram_image().slice(game_vars) == before, "the driver's tick ($17B20) did nothing")
	assert_eq(s.r16(MwSound68k.POSITIONAL_AGE), age + 1, "$13DE8's own steps still run")
	z.pending = false
	assert_false(s.vblank(z).is_empty())
	assert_eq(s.skipped, MwSound68k.Skip.NONE)
