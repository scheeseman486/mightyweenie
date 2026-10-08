class_name MwSoundZ80
extends RefCounted
## What the original's Z80 sound driver does (plan 12): the driver (ROM
## `$15C90`, uploaded to Z80 `$0000`) is a register writer plus a 4-channel
## PCM mixer; it does no sequencing. Once per 60 Hz tick the 68000
## ([MwSound68k]) may copy a 133-byte batch to Z80 `$0038-$00BC`; the Z80
## turns it into YM2612 / PSG writes and PCM channel commands, then mixes the
## playing samples into the YM2612's DAC until the next batch.
##
## The port does not execute the driver and does not mix: the chip writes go
## to an [MwSoundOut], the samples play natively ([MwSoundSamples]); what it
## keeps is everything the rest of the game can observe: the order of the
## writes, the four PCM channel states (positions, ends, loops) and the
## status bytes the 68000 polls ([method voice_status]), advanced each tick by
## the Z80's mixing time so that samples end on the original's ticks (the
## "still playing?" answers the game waits on). Research: docs/re/sound.md
## (the Z80 driver); checked against the driver's own code run in a Z80 core and
## against the busy lengths measured in GPGX (test/audio/soundz80_check.gd).
##
## Use, per tick (the audio service):
## [codeblock]
## var batch := s68k.vblank(z80)        # reads voice_status / clear_voice
## if not batch.is_empty():
##     z80.apply_batch(batch)
## z80.advance(not batch.is_empty())
## [/codeblock]
##
## The mixing time model: the Z80 has [constant FRAME_T] T-states per tick.
## Each output sample costs the period of the mixer running (1 raw channel
## 321 T, 2 / 3 / 4 channels 317 / 314 / 311 T, DPCM 330 / 319 T alternately,
## + [member bus_wait_t] per bank read); the 68000's bus requests
## ([constant BUSREQ_CHECK_T], [constant BUSREQ_STATUS_T] or
## [constant BUSREQ_COPY_T], [member extra_hold_t]), a batch (leaving the
## mixer, processing, recount, re-entry, a volume table rebuild) and the end
## or loop of a sample take time from it. The constants are the driver's
## T-states summed along its code paths (BlastEm's timing agrees to the
## T-state). Positions advance by whole output samples; an output whose period
## starts before the tick boundary counts in that tick ([member carry_t] holds
## the overlap), an end becomes visible when its status write falls before the
## boundary. Checked against the driver's code: statuses identical every tick,
## positions within one output sample (where in its period the Z80 polls).
##
## Deliberately not reproduced (inaudible, or never reached with this ROM's
## data): the mixing itself (hard clipping, the 4-channel carry bug:
## [method MwSoundSamples.mix] has them), the 323 T period of 2-4 channels for
## the playback rate, the DAC pauses, reads through a foreign bank by the 2-4
## channel mixers (a channel's own copy is used), DPCM samples read as raw
## bytes by those mixers (timing only), the broken type-1 codec (timed as raw),
## a loop bank different from the sample's bank, the exact 68000 DMA bus holds
## (an average, [member extra_hold_t]).

# --- timing (T-states of the NTSC Z80, 3 579 545 Hz) --------------------------
## Z80 T-states per NTSC frame (896 040 master clocks / 15).
const FRAME_T := 59736
const _NEVER := 1 << 40
## Per output sample, without bus waits: one raw channel (`$021F`), DPCM high /
## low nibble (`$03DA`), 2 / 3 / 4 channels (`$048A`, `$057D`, `$06E1`).
const PERIOD_RAW1_T := 321
const PERIOD_DPCM_HIGH_T := 330
const PERIOD_DPCM_LOW_T := 319
const PERIOD_MIX_T := [0, PERIOD_RAW1_T, 317, 314, 311]
## A bank crossing in the one-channel mixers (HL past `$FFFF`: HL = `$8000`, bank + 1).
const CROSS_T := 254
## The 68000's bus requests in `$17B20`: the `$BD` check (every tick), then the
## status checks (no batch) or the 133-byte copy + status checks (BlastEm).
const BUSREQ_CHECK_T := 122
const BUSREQ_STATUS_T := 232
const BUSREQ_COPY_T := 1533
## Leaving the mixer at its flag poll (saving its registers) up to `$01BB`;
## for an idle Z80 the poll loop `$01B3` (29 T + half its 36 T period).
const EXIT_IDLE_T := 47
const EXIT_T := {&"raw1": 80, &"dpcm": 86, &"mix2": 158, &"mix3": 224, &"mix4": 282}
## `$01BB` after the batch processing: clear `$BD`, jump to the recount.
const TICK_TAIL_T := 30
## `$088C` with nothing to do (14 blocks skipped, CALL / RET included).
const PROCESS_BASE_T := 489
## Extra T-states per FM block command (`$0975`): the block itself, key on
## (off then on) / off, patch / frequency / TL for part I / part II channels,
## each TL operator.
const FM_BLOCK_T := 169
const FM_KEY_ON_T := 364
const FM_KEY_OFF_T := 207
const FM_PATCH_T := [5262, 5282]
const FM_FREQ_T := [383, 403]
const FM_TL_T := [187, 207]
const FM_TL_OP_T := 145
## Extra T-states per PSG block command (`$0BA4`).
const PSG_BLOCK_T := 139
const PSG_OFF_T := 104
const PSG_ON_T := 27
const PSG_TONE_T := 240
const PSG_NOISE_T := 119
const PSG_VOL_T := 89
## Extra T-states per PCM trigger (`$0B09`): the trigger, a start by codec
## (raw, type 1, DPCM; + a bus wait per header byte), a stop, an update and its
## pitch / volume parts.
const PCM_TRIGGER_T := 40
const PCM_START_T := [775, 868, 841]
const PCM_STOP_T := 90
const PCM_UPDATE_T := 112
const PCM_PITCH_T := 71
const PCM_VOLUME_T := 33
## The recount `$014C`: base, per channel slot (playing: `$EE`/`$DE`/`$CE`,
## playing: `$BE`, idle), then some playing / none playing; the DAC switch.
const RECOUNT_T := 21
const SLOT_ACTIVE_T := 91
const SLOT_LAST_ACTIVE_T := 81
const SLOT_IDLE_T := 34
const RECOUNT_SOME_T := 19
const RECOUNT_NONE_T := 43
const DAC_SWITCH_T := 76
## `$01C6`: the dispatch on the channel count (DAC already on).
const DISPATCH_T := [0, 56, 68, 85, 95]
## Mixer entry up to its loop (volume table cached): `$01F0` raw / DPCM,
## `$045E`, `$0545`, `$069F`.
const ENTRY_T := {&"raw1": 483, &"dpcm": 442, &"mix2": 282, &"mix3": 346, &"mix4": 404}
## `$0C07` rebuilding the volume table (ch0's volume differs from the cached one).
const VOL_REBUILD_T := 12100
## End of the channel at list position i, from its mixer's loop top: [loop, stop]
## (the stop up to the jump to the recount).
const END_T := {
	&"raw1": [[363, 129]], &"dpcm": [[_NEVER, 108]],
	&"mix2": [[138, 169], [241, 324]],
	&"mix3": [[138, 235], [232, 373], [290, 431]],
	&"mix4": [[148, 303], [232, 431], [284, 483], [339, 538]],
}
## From the loop top to the `$F0` status write of a stopping channel.
const END_STATUS_T := {
	&"raw1": [119], &"dpcm": [98], &"mix2": [101, 224], &"mix3": [101, 207, 265],
	&"mix4": [111, 207, 259, 314],
}

# --- Z80 memory ------------------------------------------------------------------
const Z80_RAM_SIZE := 0x2000
const Z80_DRIVER := 0x15C90          ## ROM: length word (= Z80 address of the FM patches), then the code
const FM_PATCHES_LEN := 0x1FFB70     ## ROM: length word of the FM patches ($15B4C)
const FM_PATCHES := 0x1FFB72         ## ROM: the FM patches (26 bytes each), uploaded after the driver
const Z80_BATCH := 0x0038            ## the 68000's batch ($85 bytes) lands here
const BATCH_LEN := 0x85
const Z80_PATCH_REGS := 0x0871       ## the driver's patch register list (26 + 0 terminator)
const FM_BLOCKS := 0x00              ## batch offsets: 6 FM blocks x 10
const PSG_BLOCKS := 0x3C             ## 4 PSG blocks x 6
const PCM_TRIGGERS := 0x54           ## 4 PCM triggers x 12
const BATCH_BANK := 0x84             ## Z80 `$00BC`: bank of the last start (= 68k `$FFE734`)
## FM block k -> YM2612 channel code (bit 2 = part II).
const FM_CODES := [0, 1, 2, 4, 5, 6]
## TL registers by operator-mask bit (`$0A3E`).
const TL_REGS := [0x40, 0x48, 0x44, 0x4C]
## The recount's scan order: `$EE`, `$DE`, `$CE`, `$BE`; the first playing one is ch0.
const SCAN := [3, 2, 1, 0]
const STATUS_PLAYING := 0x01
const STATUS_ENDED := 0xF0


## One PCM channel: the 16 bytes at Z80 `$BE + 16 k` ([method bytes]) plus what
## the port needs instead of reading the sample through the bank window.
class Channel:
	var status := 0          ## +0: 0 idle / stopped, 1 playing, `$F0` ended (the 68k clears it)
	var bank := 0            ## +3: bank of the channel's copy of the sample
	var loop := 0            ## +4: bit 0 = loop
	var loop_addr := 0       ## +5/+6: loop address in the window (the trigger's + 1)
	var loop_bank := 0       ## +7
	var step := 0            ## +8/+9: pitch step 8.8 (`$100` = 1 byte per output)
	var frac := 0            ## +10: fraction accumulator (advanced while ch0)
	var volume := 0          ## +11: `$80` = unity
	var codec := 0           ## +12: 0 raw, 2 DPCM, else type 1
	var marker := 0          ## +13: type 1 marker
	var phase := 0           ## +14: DPCM nibble phase (0 = high nibble next)
	var value := 0           ## +15: DPCM value (`$80` at the start; [method MwSoundZ80.channel_bytes] updates it)
	var sample := -1         ## [MwSoundSamples] index (-1 none)
	var data := 0            ## ROM address of data byte 0 in the channel's copy
	var length := 0          ## data bytes before the end marker
	var index := 0           ## the Z80's pointer as an index into the data
	var loop_index := -1     ## where a loop restarts (index)
	var outputs := 0         ## output samples since the start

	## The window address the Z80 keeps in +1/+2 (and its bank, +3) for [member index].
	func window_address() -> int:
		return 0x8000 | ((data + index) & 0x7FFF)

	## The 16 bytes as the Z80 has them (positions as of the last tick; the
	## original only saves them when it leaves the mixer).
	func bytes() -> PackedByteArray:
		var a := window_address()
		return PackedByteArray([status, a & 0xFF, a >> 8, (data + index) >> 15, loop,
			loop_addr & 0xFF, loop_addr >> 8, loop_bank, step >> 8, step & 0xFF, frac, volume,
			codec, marker, phase, value])


var out: MwSoundOut
var samples: MwSoundSamples
var rom := PackedByteArray()
## Z80 RAM image: the driver and the FM patches as uploaded; the batch area
## gets each batch (patch addresses point into it).
var ram := PackedByteArray()
var channels: Array[Channel] = []
## Extra T-states per bank read (BlastEm 3; GPGX's timing is matched best by 0).
var bus_wait_t := 3
## Whether the 68000's bus requests take Z80 time ([constant BUSREQ_CHECK_T]...).
var bus_holds := true
## Further 68000 bus holds per tick (joypad, VDP DMA: ~200 T in gameplay, 0 at
## the title).
var extra_hold_t := 0
## Mixing time carried into the next tick (<= 0: the last output's period
## overlaps the boundary; > 0: an end in progress at the boundary).
var carry_t := 0
var dac_on := false
## Volume of the current volume table (`$0108`; 0 after the upload).
var vol_cache := 0
var _batch_cost := 0
var _reported_step := PackedInt32Array([-1, -1, -1, -1])
var _reported_volume := PackedInt32Array([-1, -1, -1, -1])


func _init(rom_: PackedByteArray = PackedByteArray(), out_: MwSoundOut = null) -> void:
	rom = rom_
	out = out_ if out_ != null else MwSoundOut.new()
	samples = MwSoundSamples.new(rom)
	for k in 4:
		channels.append(Channel.new())
	reset()


## The driver upload (`$13C18`: `$168BE` + `$15B4C`, at power-on and at
## every `$13C04`): the driver at Z80 `$0000`, the FM patches after it (ROM
## [constant FM_PATCHES], 494 bytes at Z80 `$0C2C`); PCM channels idle, the
## DAC flag (`$0109`) and the volume table cache (`$0108`) 0. The Z80's reset
## stops its samples at once ([method MwSoundOut.pcm_stop] for each playing
## channel); YM `$2B` is the YM2612's and keeps its value, so a DAC left on
## keeps FM 6 muted until the next sample ends (docs/re/sound.md, quirk 28).
func reset() -> void:
	if out != null:
		for k in channels.size():
			if channels[k].status & STATUS_PLAYING:
				out.pcm_stop(k)
	ram = PackedByteArray()
	ram.resize(Z80_RAM_SIZE)
	if rom.size() > FM_PATCHES:
		var n := _rom16(Z80_DRIVER)
		var m := _rom16(FM_PATCHES_LEN)
		for i in n:
			ram[i] = rom[Z80_DRIVER + 2 + i]
		for i in m:
			ram[(n + i) & 0x1FFF] = rom[FM_PATCHES + i]
	for k in 4:
		channels[k] = Channel.new()
		_reported_step[k] = -1
		_reported_volume[k] = -1
	carry_t = 0
	dac_on = false
	vol_cache = 0
	_batch_cost = 0


## Z80 `$00BD` != 0 (the last batch not yet taken): never, each batch is
## processed at once.
func batch_pending() -> bool:
	return false


## Status byte of PCM channel [param k] (Z80 `$BE + 16 k`): 0, 1 or `$F0`.
func voice_status(k: int) -> int:
	return channels[k].status


## The 68000 writing 0 to the status byte (acknowledging an end).
func clear_voice(k: int) -> void:
	channels[k].status = 0


## Playing channels in the recount's order; the first is ch0.
func active() -> PackedInt32Array:
	var act := PackedInt32Array()
	for k: int in SCAN:
		if channels[k].status & STATUS_PLAYING:
			act.append(k)
	return act


## The 16 bytes of channel [param k] as the Z80 has them ([method Channel.bytes]),
## the DPCM value (+15) brought up to date from the decoded sample.
func channel_bytes(k: int) -> PackedByteArray:
	var c := channels[k]
	if c.codec == MwSoundSamples.CODEC_DPCM and c.sample >= 0:
		var t := 2 * c.index + c.phase
		var v := samples.decode(c.sample)
		c.value = v[t - 1] if t > 0 and t <= v.size() else 0x80
	return c.bytes()


## Channel [param k]'s position in its decoded stream (raw: bytes, DPCM:
## nibbles) as the Z80 counts it.
func position(k: int) -> int:
	var c := channels[k]
	return 2 * c.index + c.phase if c.codec == MwSoundSamples.CODEC_DPCM else c.index


## The tick processing `$088C` of a 133-byte batch (Z80 `$0038-$00BC`, the
## 68000's `$FFE6B0-$FFE734`): FM blocks 0-5 (patch, key, frequency, TL),
## PSG blocks 0-3 (off, tone, attenuation), PCM triggers 0-3, then the
## recount (DAC switch). A field with bit 7 set means "no change".
func apply_batch(batch: PackedByteArray) -> void:
	if batch.size() != BATCH_LEN:
		push_error("MwSoundZ80: a batch is %d bytes" % BATCH_LEN)
		return
	for i in BATCH_LEN:
		ram[Z80_BATCH + i] = batch[i]
	var cost := _exit_cost() + TICK_TAIL_T + PROCESS_BASE_T
	for blk in 6:
		cost += _fm_block(batch, FM_BLOCKS + 10 * blk, FM_CODES[blk])
	for k in 4:
		cost += _psg_block(batch, PSG_BLOCKS + 6 * k, k)
	for k in 4:
		cost += _pcm_trigger(batch, PCM_TRIGGERS + 12 * k, k)
	cost += _recount()
	var act := active()
	if not act.is_empty():
		cost += _entry_cost(act)
	_batch_cost = cost
	_sync()


## One tick of mixing time: every playing channel advances by the output
## samples the Z80 mixes until the next tick's status check; ends ([constant
## STATUS_ENDED], [method MwSoundOut.pcm_stop]) and loops happen on the way.
## [param had_batch]: this tick's [method apply_batch] ran.
func advance(had_batch: bool) -> void:
	var hold := extra_hold_t
	if bus_holds:
		hold += BUSREQ_CHECK_T + (BUSREQ_COPY_T if had_batch else BUSREQ_STATUS_T)
	var act := active()
	if act.is_empty():
		carry_t = 0
		_batch_cost = 0
		return
	var budget := FRAME_T - hold + carry_t
	if had_batch:
		budget -= _batch_cost
	_batch_cost = 0
	while true:
		act = active()
		if act.is_empty():
			carry_t = 0
			return
		var path := _path(act)
		# the first end: fewest iterations, then the earliest in the list
		var j := _NEVER
		var i := 0
		for p in act.size():
			var n := _to_end(act[p], p, path)
			if n < j:
				j = n
				i = p
		var tj := _time_for(act, path, j) if j < _NEVER else _NEVER
		var ch := channels[act[i]]
		var loops := (ch.loop & 1) != 0 and path != &"dpcm" and ch.loop_index >= 0 and ch.loop_index < ch.length
		var reads := 1 if act.size() == 1 else i + 1
		var visible: int = tj if loops else tj + END_STATUS_T[path][i] + reads * bus_wait_t
		if j < _NEVER and visible < budget:
			_run(act, path, j)
			for p in i:
				_step_once(channels[act[p]], p == 0)
			var end_t: int = END_T[path][i][0 if loops else 1]
			budget -= tj + end_t + reads * bus_wait_t
			if loops:
				ch.index = ch.loop_index
				if i == 0:
					ch.frac = 0
				continue
			ch.status = STATUS_ENDED
			out.pcm_stop(act[i])
			_reported_step[act[i]] = -1
			_reported_volume[act[i]] = -1
			budget -= _recount()
			act = active()
			if not act.is_empty():
				budget -= _entry_cost(act)
			_sync()
			continue
		var n := mini(_iterations_before(act, path, budget), j)
		var tn := _time_for(act, path, n)
		_run(act, path, n)
		carry_t = budget - tn
		return


# --- batch processing ----------------------------------------------------------

## FM block (`$0975`) at batch offset [param o] for YM channel code [param code].
func _fm_block(b: PackedByteArray, o: int, code: int) -> int:
	if b[o] & 0x80:
		return 0
	var cost := FM_BLOCK_T
	var port := 1 if code & 4 else 0
	var ch := code & 3
	if not (b[o + 2] & 0x80):
		# $09A3: 26 registers of the patch at Z80 (+6, +7), big-endian
		var a := (b[o + 6] << 8) | b[o + 7]
		var r := Z80_PATCH_REGS
		while ram[r] != 0:
			out.ym_write(port, ram[r] + ch, ram[a & 0x1FFF])
			a += 1
			r += 1
		cost += FM_PATCH_T[port]
	if not (b[o + 1] & 0x80):
		out.ym_write(0, 0x28, code)                      # key off (all operators)
		if b[o + 1] & 1:
			out.ym_write(0, 0x28, code + 0xF0)           # then all four on
			cost += FM_KEY_ON_T
		else:
			cost += FM_KEY_OFF_T
	if not (b[o + 4] & 0x80):
		out.ym_write(port, 0xA4 + ch, b[o + 8])          # block / F-number high first
		out.ym_write(port, 0xA0 + ch, b[o + 9])
		cost += FM_FREQ_T[port]
	if not (b[o + 3] & 0x80):
		cost += FM_TL_T[port]
		for bit in 4:
			if (b[o + 5] >> bit) & 1:
				out.ym_write(port, TL_REGS[bit] + ch, b[o + 3])
				cost += FM_TL_OP_T
	return cost


## PSG block (`$0BA4`) at batch offset [param o] for channel [param k] (3 = noise).
func _psg_block(b: PackedByteArray, o: int, k: int) -> int:
	if b[o] & 0x80:
		return 0
	var cost := PSG_BLOCK_T
	if not (b[o + 1] & 0x80):
		if b[o + 1] & 1:
			cost += PSG_ON_T
		else:
			out.psg_write(0x90 | (k << 5) | 15)          # attenuation 15: silent
			cost += PSG_OFF_T
	if not (b[o + 3] & 0x80):
		out.psg_write(0x80 | (k << 5) | (b[o + 5] & 0xF))
		if k != 3:
			out.psg_write(((b[o + 4] << 4) | (b[o + 5] >> 4)) & 0x3F)
			cost += PSG_TONE_T
		else:
			cost += PSG_NOISE_T                          # noise: the latch byte only
	if not (b[o + 2] & 0x80):
		out.psg_write(((0x90 | (k << 5)) | b[o + 2]) & 0xFF)   # OR, unmasked, as the Z80
		cost += PSG_VOL_T
	return cost


## PCM trigger (`$0B09`) at batch offset [param o] for channel [param k].
func _pcm_trigger(b: PackedByteArray, o: int, k: int) -> int:
	if b[o] & 0x80:
		return 0
	var cost := PCM_TRIGGER_T
	var ch := channels[k]
	if b[o + 1] & 0x80:
		# $0B84 update: pitch if +2 bit 7 clear, volume if +4 != $FF
		cost += PCM_UPDATE_T
		if not (b[o + 2] & 0x80):
			ch.step = (b[o + 2] << 8) | b[o + 3]
			cost += PCM_PITCH_T
		if b[o + 4] != 0xFF:
			ch.volume = b[o + 4]
			cost += PCM_VOLUME_T
	elif b[o + 1] & 1:
		cost += _pcm_start(b, o, k)
	else:
		cost += PCM_STOP_T
		if ch.status & STATUS_PLAYING:
			out.pcm_stop(k)
		ch.status = 0
		_reported_step[k] = -1
		_reported_volume[k] = -1
	return cost


## `$0B1B`: the header is read with the bank in `$00BC`; the channel keeps
## the trigger's bank (+5); the data follows the codec byte (and a marker for
## type 1).
func _pcm_start(b: PackedByteArray, o: int, k: int) -> int:
	var ch := channels[k]
	ch.bank = b[o + 5]
	var window := (b[o + 6] << 8) | b[o + 7]
	var header := (b[BATCH_BANK] << 15) | (window & 0x7FFF)
	ch.codec = _rom8(header)
	var skip := 1
	if ch.codec != MwSoundSamples.CODEC_RAW:
		if ch.codec != MwSoundSamples.CODEC_DPCM:
			ch.marker = _rom8(header + 1)
			skip = 2
		ch.phase = 0
		ch.value = 0x80
	var cost: int = PCM_START_T[ch.codec] if ch.codec <= MwSoundSamples.CODEC_DPCM else PCM_START_T[MwSoundSamples.CODEC_TYPE1]
	cost += skip * bus_wait_t
	ch.data = ((ch.bank << 15) | (window & 0x7FFF)) + skip
	ch.sample = samples.find_header(header)
	if ch.sample < 0 and header < rom.size():
		ch.sample = samples.add_header(header)
	ch.length = samples.desc(ch.sample).length if ch.sample >= 0 else 0
	ch.index = 0
	ch.outputs = 0
	ch.volume = b[o + 4]
	ch.loop = b[o + 8]
	ch.loop_addr = (((b[o + 10] << 8) | b[o + 11]) + 1) & 0xFFFF
	ch.loop_bank = b[o + 9]
	ch.loop_index = ((ch.loop_bank << 15) | (ch.loop_addr & 0x7FFF)) - ch.data
	ch.step = (b[o + 2] << 8) | b[o + 3]
	ch.frac = 0
	ch.status = STATUS_PLAYING
	_reported_step[k] = -1
	_reported_volume[k] = -1
	out.pcm_start(k, ch.sample, 0)
	return cost


# --- recount, effective values ------------------------------------------------------

## `$014C` + `$01C6`: the recount and the dispatch; switches the DAC (YM `$2B`)
## when the first channel starts or the last one stops. Returns its T-states.
func _recount() -> int:
	var t := RECOUNT_T
	var n := 0
	for k: int in SCAN:
		if channels[k].status & STATUS_PLAYING:
			t += SLOT_LAST_ACTIVE_T if k == 0 else SLOT_ACTIVE_T
			n += 1
		else:
			t += SLOT_IDLE_T
	if n == 0:
		t += RECOUNT_NONE_T
		if dac_on:
			dac_on = false
			out.ym_write(0, 0x2B, 0x00)
			t += DAC_SWITCH_T
		return t
	t += RECOUNT_SOME_T + DISPATCH_T[n]
	if not dac_on:
		dac_on = true
		out.ym_write(0, 0x2B, 0x80)
		t += DAC_SWITCH_T
	return t


## Mixer entry; `$0C07` rebuilds the volume table when ch0's volume is not the cached one.
func _entry_cost(act: PackedInt32Array) -> int:
	var t: int = ENTRY_T[_path(act)]
	var v := channels[act[0]].volume
	if v != vol_cache:
		vol_cache = v
		t += VOL_REBUILD_T
	return t


## Leaving what the Z80 was doing when the batch's flag came: a mixer or the idle poll.
func _exit_cost() -> int:
	var act := active()
	if act.is_empty():
		return EXIT_IDLE_T
	var t: int = EXIT_T[_path(act)]
	return t


## Tells [member out] the effective step / volume of every playing channel that changed.
func _sync() -> void:
	var act := active()
	for k in 4:
		var ch := channels[k]
		if not (ch.status & STATUS_PLAYING):
			_reported_step[k] = -1
			_reported_volume[k] = -1
			continue
		var step := 0x100
		var volume := 0x80
		if k == act[0]:
			volume = ch.volume
			if not (act.size() == 1 and ch.codec == MwSoundSamples.CODEC_DPCM):
				step = ch.step
		if step != _reported_step[k]:
			_reported_step[k] = step
			out.pcm_rate(k, step)
		if volume != _reported_volume[k]:
			_reported_volume[k] = volume
			out.pcm_volume(k, volume)


# --- mixing time ----------------------------------------------------------------------

func _path(act: PackedInt32Array) -> StringName:
	if act.size() == 1:
		return &"dpcm" if channels[act[0]].codec == MwSoundSamples.CODEC_DPCM else &"raw1"
	return [&"", &"", &"mix2", &"mix3", &"mix4"][act.size()]


## Output samples of channel [param k] (list position [param p]) before the
## one that meets its end marker.
func _to_end(k: int, p: int, path: StringName) -> int:
	var ch := channels[k]
	if path == &"dpcm":
		return maxi(0, 2 * ch.length - (2 * ch.index + ch.phase))
	if p == 0:
		var pos := ch.index * 256 + ch.frac
		var end := ch.length * 256
		if pos >= end:
			return 0
		if ch.step == 0:
			return _NEVER
		return (end - pos + ch.step - 1) / ch.step
	return maxi(0, ch.length - ch.index)


## T-states of [param n] output samples from the current positions.
func _time_for(act: PackedInt32Array, path: StringName, n: int) -> int:
	var ch := channels[act[0]]
	if path == &"dpcm":
		var hi := PERIOD_DPCM_HIGH_T + bus_wait_t
		var lo := PERIOD_DPCM_LOW_T + bus_wait_t
		var first := hi if ch.phase == 0 else lo
		var second := lo if ch.phase == 0 else hi
		var t := (n + 1) / 2 * first + n / 2 * second
		var t0 := 2 * ch.index + ch.phase
		t += CROSS_T * (((ch.data + ((t0 + n) >> 1)) >> 15) - ((ch.data + (t0 >> 1)) >> 15))
		return t
	var t: int = n * (PERIOD_MIX_T[act.size()] + act.size() * bus_wait_t)
	if path == &"raw1":
		var p0 := ch.index * 256 + ch.frac
		var p1 := p0 + n * ch.step
		t += CROSS_T * (((ch.data + (p1 >> 8)) >> 15) - ((ch.data + (p0 >> 8)) >> 15))
	return t


## Output samples whose period starts before [param budget] T-states (bank crossings ignored).
func _iterations_before(act: PackedInt32Array, path: StringName, budget: int) -> int:
	if budget <= 0:
		return 0
	if path == &"dpcm":
		var hi := PERIOD_DPCM_HIGH_T + bus_wait_t
		var lo := PERIOD_DPCM_LOW_T + bus_wait_t
		var first := hi if channels[act[0]].phase == 0 else lo
		var q := budget / (hi + lo)
		var rem := budget - q * (hi + lo)
		var n := 2 * q
		if rem > 0:
			n += 1
		if rem > first:
			n += 1
		return n
	var period: int = PERIOD_MIX_T[act.size()] + act.size() * bus_wait_t
	return (budget + period - 1) / period


## Every playing channel advances by [param n] output samples: ch0 by its
## 8.8 step (raw), the others by one byte each, a lone DPCM channel by one nibble.
func _run(act: PackedInt32Array, path: StringName, n: int) -> void:
	for p in act.size():
		var ch := channels[act[p]]
		ch.outputs += n
		if path == &"dpcm":
			var t := 2 * ch.index + ch.phase + n
			ch.index = t >> 1
			ch.phase = t & 1
		elif p == 0:
			var pos := ch.index * 256 + ch.frac + n * ch.step
			ch.index = pos >> 8
			ch.frac = pos & 0xFF
		else:
			ch.index += n


## A channel read (and advanced) without an output: the channels before an
## ended one in the 2-4 channel mixers.
func _step_once(ch: Channel, is_ch0: bool) -> void:
	if is_ch0:
		var pos := ch.index * 256 + ch.frac + ch.step
		ch.index = pos >> 8
		ch.frac = pos & 0xFF
	else:
		ch.index += 1


func _rom8(a: int) -> int:
	return rom[a] if a >= 0 and a < rom.size() else 0


func _rom16(a: int) -> int:
	return (rom[a] << 8) | rom[a + 1]
