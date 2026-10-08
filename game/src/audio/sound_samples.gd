class_name MwSoundSamples
extends RefCounted
## The PCM samples of the original's sound driver (plan 12), read from the
## ROM: the sample list, their decoding and Godot streams to play them natively
## at the rate the original's Z80 plays them.
##
## A port of `harness/mw_harness/sound_samples.py` (the reference parser,
## verified byte for byte against the DAC writes of the original in BlastEm;
## research in docs/re/sound.md). Nothing here is game content: the
## instrument table and the sample data are read from the ROM at run time.
##
## Instrument table ([constant INSTRUMENT_TABLE], `$E6A6` set at `$13C44`):
## 256 big-endian words, offsets from the table to instrument records. Record
## +0 is the kind: 0 = PCM sample, 3 = pitched PCM sample (the sequencer picks
## its pitch from a 48-note table at +`$16`); 1 / 2 / 4 / 5 are FM / PSG /
## other instruments of the 68k sequencer (not handled here). Sample records:
## [codeblock]
## +$00  byte   kind (0 or 3)
## +$01  byte   priority (voice allocation $16958 / $172A0)
## +$02  word   voices the sequencer may use (bit k = 68k voice 10 + k)
## +$04  long   bank mask: bit k = a copy of the sample exists k banks above the
##              bank of (SAMPLE_BASE + offset), at the same offset in the bank;
##              0 = the sample plays alone (no copy for mixing)
## +$08  long   offset of the sample header from SAMPLE_BASE ($E6AA)
## +$0C  word   pitch the sequencer uses when +$12 = 0 ($0100)
## +$0E  word   loop start, as an index into the sample data
## +$10  byte   bit 0: loop
## +$12  byte   1 = pitched by the sequencer's note (kind 3); +$13 note offset
## [/codeblock]
## Sample header in the 32 KB bank (the Z80 reads it through its bank window
## `$8000-$FFFF`): a codec byte (0 = raw unsigned 8-bit, 2 = 4-bit DPCM, other
## = "type 1", a marker byte follows; used by no sample), then the data, ended
## by a 0 byte (0 never occurs as a sample value). DPCM: two 4-bit codes per
## byte, high nibble first; value += delta[code] (mod 256, no clamping) from
## `$80`; the DAC gets every value. The 16 deltas are part of the Z80 driver
## (Z80 `$0112`).

const INSTRUMENT_TABLE := 0x1FF010    ## `$E6A6` (lea at `$13C44`)
const INSTRUMENT_COUNT := 256
const SAMPLE_BASE := 0x1C0000         ## `$E6AA` (lea at `$13C58`)
const SOUND_ID_TABLE := 0x1F5C6       ## sound_play `$13CEE`: id - `$12` -> instrument index (word, < 0 = none)
const SOUND_ID_FIRST := 0x12
const SOUND_ID_COUNT := 0x29          ## ids `$12-$3A` (`$13D2C` admits up to `$4C`: other data follows)
const CODEC_RAW := 0
const CODEC_TYPE1 := 1
const CODEC_DPCM := 2
const DRIVER_BLOB := 0x15C90          ## length word, then the code loaded at Z80 `$0000`
const DPCM_DELTA_TABLE := DRIVER_BLOB + 2 + 0x112   ## 16 signed bytes (Z80 `$0112`)

## NTSC Z80 clock: 53 693 175 Hz / 15 = 3 579 545 Hz.
const Z80_HZ := 53693175.0 / 15.0
## Extra T-states per Z80 read of the 68k bus through the bank window
## (BlastEm's arbitration model; ~3.3 measured on hardware).
const BUS_WAIT_T := 3
## Raw samples: the one-channel loop (Z80 `$021F`) takes 321 T-states plus
## one bank read per output sample = 324 T -> 3 579 545 / 324 = 11 047.98 Hz
## (BlastEm: exactly 324 T between DAC writes). With 2-4 samples mixing the
## loops take 317 / 314 / 311 T + 2 / 3 / 4 reads = 323 T (11 082 Hz, 0.3 %
## faster: not reproduced).
const RAW_PERIOD_T := 321 + BUS_WAIT_T
## DPCM: the high-nibble pass (Z80 `$03DA`) takes 330 T, the low-nibble pass
## 319 T, each + one bank read: 655 T per byte = 2 output samples ->
## 2 x 3 579 545 / 655 = 10 929.91 Hz on average.
const DPCM_PAIR_T := 330 + 319 + 2 * BUS_WAIT_T
## [member AudioStreamWAV.mix_rate] of raw samples: round(Z80_HZ / RAW_PERIOD_T).
const RAW_MIX_RATE := 11048
## [member AudioStreamWAV.mix_rate] of DPCM samples: round(2 * Z80_HZ / DPCM_PAIR_T).
const DPCM_MIX_RATE := 10930


## One sample instrument (or a sample header found elsewhere, [method add_header]).
class Desc:
	var instrument := -1                ## instrument index (`$17CDE`'s d0); -1 for an ad-hoc header
	var record := -1                    ## ROM address of the instrument record
	var kind := -1                      ## 0 = sample, 3 = pitched sample
	var priority := 0
	var bank_mask := 0
	var offset := 0                     ## record +8
	var loop := false
	var loop_start := 0                 ## index into the data where a loop restarts
	var flags := 0                      ## record +`$10`
	var copies := PackedInt32Array()    ## ROM address of the header of every copy, lowest bank first
	var codec := 0                      ## the header's codec byte
	var data := 0                       ## ROM address of the first data byte (first copy)
	var length := 0                     ## data bytes before the 0 terminator
	var sound_ids := PackedInt32Array() ## sound_play ids that start it (pitch `$100`, volume `$80`)

	## ROM address of the first copy's header.
	func address() -> int:
		return copies[0]

	## DAC writes for one pass at pitch `$100` (DPCM: two per byte).
	func output_samples() -> int:
		return length * 2 if codec == CODEC_DPCM else length

	## Playback rate at pitch `$100`, playing alone (Hz, exact).
	func rate() -> float:
		return 2.0 * Z80_HZ / DPCM_PAIR_T if codec == CODEC_DPCM else Z80_HZ / RAW_PERIOD_T

	## The rate as the stream's integer mix rate.
	func mix_rate() -> int:
		return DPCM_MIX_RATE if codec == CODEC_DPCM else RAW_MIX_RATE

	## Whether the Z80 restarts it at [member loop_start] when it meets the end
	## marker (raw samples only: the DPCM path never loops).
	func loops() -> bool:
		return loop and codec != CODEC_DPCM and loop_start >= 0 and loop_start < length


var rom := PackedByteArray()
## Every sample instrument, in instrument-index order (one per record).
var descs: Array[Desc] = []
var _by_header := {}        # header ROM address (any copy) -> index into descs
var _by_instrument := {}    # instrument index -> index into descs
var _by_record := {}        # instrument record ROM address -> index into descs
var _decoded := {}          # index -> PackedByteArray
var _streams := {}          # index -> AudioStreamWAV


func _init(rom_: PackedByteArray = PackedByteArray()) -> void:
	rom = rom_
	if rom.size() < INSTRUMENT_TABLE + 2 * INSTRUMENT_COUNT:
		return
	var ids := sound_id_map()
	var seen := {}
	for i in INSTRUMENT_COUNT:
		var off := _u16(INSTRUMENT_TABLE + 2 * i)
		if seen.has(off):
			continue
		seen[off] = true
		var d := _parse(i, ids)
		if d != null:
			_add(d)
			_by_instrument[i] = descs.size() - 1


## Number of samples ([member descs]).
func count() -> int:
	return descs.size()


func desc(index: int) -> Desc:
	return descs[index]


## The sample whose header (any copy) is at [param window_address] (`$8000 |`
## the address in the bank) in bank [param bank] (68k address >> 15): what a
## Z80 PCM trigger gives (bytes +5, +6/+7). -1 if none.
func find(bank: int, window_address: int) -> int:
	return find_header((bank << 15) | (window_address & 0x7FFF))


## The sample with a copy of its header at ROM [param address], or -1.
func find_header(address: int) -> int:
	return _by_header.get(address, -1)


## The sample of the instrument record at ROM [param record] (what
## [method MwSound68k.instrument] returns), or -1.
func by_record(record: int) -> int:
	return _by_record.get(record, -1)


## The sample of instrument [param instrument], or -1.
func by_instrument(instrument: int) -> int:
	return _by_instrument.get(instrument, -1)


## A sample for a header at ROM [param address] that no instrument lists (the
## original could play one: `$17C1A` starts a raw pointer, but has no caller).
## Returns its index (the existing one if already known).
func add_header(address: int) -> int:
	var known := find_header(address)
	if known >= 0:
		return known
	var d := Desc.new()
	d.copies = PackedInt32Array([address])
	_describe_data(d)
	_add(d)
	return descs.size() - 1


## sound_play id -> instrument index (ids `$12-$3A` with an entry >= 0).
func sound_id_map() -> Dictionary:
	var out := {}
	for i in SOUND_ID_COUNT:
		var v := _u16(SOUND_ID_TABLE + 2 * i)
		if v < 0x8000:
			out[SOUND_ID_FIRST + i] = v
	return out


## DPCM code -> signed delta, as the driver has it.
func dpcm_deltas() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in 16:
		var b := rom[DPCM_DELTA_TABLE + i]
		out.append(b - 256 if b >= 0x80 else b)
	return out


## The unsigned 8-bit values the DAC receives for one pass of sample
## [param index] at pitch `$100` and full volume (`$80`: the driver's volume
## table is then the identity). Cached. Empty for a type-1 header (no sample
## uses that codec; its decoder in the driver is broken).
func decode(index: int) -> PackedByteArray:
	if _decoded.has(index):
		return _decoded[index]
	var d := descs[index]
	var out := PackedByteArray()
	if d.codec == CODEC_RAW:
		out = rom.slice(d.data, d.data + d.length)
	elif d.codec == CODEC_DPCM:
		var deltas := dpcm_deltas()
		out.resize(2 * d.length)
		var v := 0x80
		for i in d.length:
			var b := rom[d.data + i]
			v = (v + deltas[b >> 4]) & 0xFF
			out[2 * i] = v
			v = (v + deltas[b & 0xF]) & 0xFF
			out[2 * i + 1] = v
	_decoded[index] = out
	return out


## Sample [param index] as a stream: 16-bit signed mono PCM (unsigned 8-bit
## `s` -> `(s - $80) << 8`), [member AudioStreamWAV.mix_rate]
## [constant RAW_MIX_RATE] (raw) or [constant DPCM_MIX_RATE] (DPCM), looping
## from [member Desc.loop_start] to the end for a looping sample (the Z80 jumps
## to the loop address when it meets the end marker). Cached; null for a
## type-1 header.
func stream(index: int) -> AudioStreamWAV:
	if _streams.has(index):
		return _streams[index]
	var d := descs[index]
	var values := decode(index)
	if values.is_empty() and d.codec == CODEC_TYPE1:
		return null
	var pcm := PackedByteArray()
	pcm.resize(2 * values.size())
	for i in values.size():
		pcm[2 * i + 1] = values[i] ^ 0x80     # high byte of (s - $80) << 8; low byte 0
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = d.mix_rate()
	s.stereo = false
	s.data = pcm
	if d.loops():
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = d.loop_start
		s.loop_end = d.length
	_streams[index] = s
	return s


## The driver's 256-byte volume table (`$0C07` -> Z80 `$1B00`) for a volume
## byte: `$80` = identity, 0 = constant `$80`; above `$80` it amplifies and
## wraps around (16-bit arithmetic as the Z80's).
static func volume_table(volume: int) -> PackedByteArray:
	var acc := ((0x80 - volume) & 0xFF) << 8
	var step := (2 * volume) & 0x1FF
	var out := PackedByteArray()
	out.resize(256)
	for i in 256:
		out[i] = (acc >> 8) & 0xFF
		acc = (acc + step) & 0xFFFF
	return out


## The DAC value for 1-4 channels' current bytes (the first already through
## the volume table): signed sum around `$80`, clamped to 0..255 (the clamp
## table Z80 `$1C00-$1FFF`). With 4 channels the original loses the carry of
## the first addition (Z80 `$06FC`: XOR A clears it before ADC A,A), so about
## half the outputs clip to 0; [param carry_bug] false gives the intended sum.
static func mix(values: PackedInt32Array, carry_bug := true) -> int:
	var total := 0
	if values.size() == 4 and carry_bug:
		total = ((values[0] + values[1]) & 0xFF) + values[2] + values[3]
	else:
		for v in values:
			total += v
	return clampi(total - 0x80 * (values.size() - 1), 0, 255)


func _add(d: Desc) -> void:
	descs.append(d)
	if d.record >= 0:
		_by_record[d.record] = descs.size() - 1
	for c in d.copies:
		if not _by_header.has(c):
			_by_header[c] = descs.size() - 1


func _parse(index: int, ids: Dictionary) -> Desc:
	var rec := INSTRUMENT_TABLE + _u16(INSTRUMENT_TABLE + 2 * index)
	var kind := rom[rec]
	if kind != 0 and kind != 3:
		return null
	var d := Desc.new()
	d.instrument = index
	d.record = rec
	d.kind = kind
	d.priority = rom[rec + 1]
	d.bank_mask = _u32(rec + 4)
	d.offset = _u32(rec + 8)
	d.loop_start = _u16(rec + 0xE)
	d.flags = rom[rec + 0x10]
	d.loop = (d.flags & 1) != 0
	var a := SAMPLE_BASE + d.offset
	for k in 32:
		if (d.bank_mask >> k) & 1:
			d.copies.append((((a >> 15) + k) << 15) | (a & 0x7FFF))
	if d.copies.is_empty():
		d.copies.append(a)
	_describe_data(d)
	for sid: int in ids:
		if ids[sid] == index:
			d.sound_ids.append(sid)
	return d


## Codec, data start and length from the header of [param d]'s first copy.
func _describe_data(d: Desc) -> void:
	var h := d.copies[0]
	d.codec = rom[h]
	d.data = h + (1 if d.codec == CODEC_RAW or d.codec == CODEC_DPCM else 2)
	var e := d.data
	while e < rom.size() and rom[e] != 0:
		e += 1
	d.length = e - d.data


func _u16(a: int) -> int:
	return (rom[a] << 8) | rom[a + 1]


func _u32(a: int) -> int:
	return (_u16(a) << 16) | _u16(a + 2)
