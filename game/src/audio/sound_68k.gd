class_name MwSound68k
extends RefCounted
## The 68000 half of the original's sound driver (plan 12): the game's sound
## API (`$13BE0-$13FFF`), a MIDI-like sequencer and a channel allocator run
## once per 60 Hz tick, and the per-tick hand-over of "change records" to the
## Z80, which turns them into YM2612 / PSG writes and plays the PCM samples
## ([MwSoundZ80]).
##
## A port of the reference model `harness/mw_harness/sound68k.py` (byte-exact
## against the original in GPGX and BlastEm; research in docs/re/sound.md),
## checked against it tick by tick by `test/audio/sound68k_check.gd`. Like the
## model it keeps the original's state in an image of work RAM with the same
## byte layout ([member mem]: 64 KiB indexed by the address's low word; only
## `$FFCA2C-$FFCA4D` and `$FFE6A6-$FFF393` are used), because the original
## reuses fields with different widths, and the quirks that follow from that
## (stale fields, caches compared by word or by long) are part of its
## behaviour. Routines are named after the original's addresses. Nothing here
## is game content: sequences, instruments and tables are read from the ROM
## at run time.
##
## Use: [method reset], then per tick [method vblank] with the Z80 side; the
## game calls the API between ticks, as the original's main loop does between
## VBlanks. Handles and return values are the original's d0 (32-bit,
## unsigned: -1 is `$FFFFFFFF`). Calls are atomic here: the original can be
## interrupted by a VBlank in the middle of one (a CPU-timing artifact, 0.14 %
## of the ticks of a demo; deliberately not reproduced).

# --- ROM ---------------------------------------------------------------------
const Z80_DRIVER := 0x15C90          ## length word (= Z80 address of the FM patches), then the Z80 code
const INSTRUMENTS := 0x1FF010        ## 256 word offsets (from here) to instrument records ($15B4C)
const SAMPLES := 0x1C0000            ## sample offsets in instruments are relative to this ($15B46)
const SEQUENCES := 0x1F57E           ## sound ids 0..$11: sequence pointers (long)
const VOICE_IDS := 0x1F5C6           ## sound ids $12..$4C: instrument index (word, < 0 none)
const MUSIC_TITLE := 0x1CDC00        ## the sequence $13C66 starts
const MUSIC_GAME := 0x1CE2D0         ## the sequence $13C6E starts
const CHANNEL_RECORDS := 0x4CECE     ## 14 words: channel -> its record's offset from $FFE6B0
const ALLOC_CLASSES := 0x16930       ## 5 x 8 bytes: first struct offset, first mask bit, count - 1
const NOTE_FOLD := 0x169D6           ## MIDI notes $6C-$7F folded to $60-$6B (indexed -$6C)
const FM_FREQ := 0x169EA             ## 96 longs: linear F-number (block 0 units), C0..B7
const FM_VOLUME := 0x16B6A           ## volume 0..$7F -> attenuation $7F..0 (zeros beyond)
const PSG_PERIOD := 0x16BEA          ## words: PSG tone period by note index
const PSG_VOLUME := 0x16CAA          ## volume 0..$7F -> PSG attenuation $F..0
const SINE := 0x1F628                ## 65 words: quarter sine wave, 0..$7FFF
const TEMPO_NTSC := 0x17F06          ## 256 longs: BPM -> 24ths of a beat per tick (16.16), 60 Hz
const TEMPO_PAL := 0x18306           ## the same for 50 Hz

# --- work RAM: the driver ------------------------------------------------------
const RECORDS := 0xFFE6B0            ## change records copied to Z80 $0038 ($85 bytes)
const RECORDS_LEN := 0x85
const BANK_SHADOW := 0xFFE734        ## last sample bank written (byte, inside the copied block)
const DIRTY := 0xFFE735              ## records changed this tick (byte)
const PROGRAMS := 0xFFE736           ## 16 bytes: program per MIDI channel (note-on instrument)
const VOLUMES := 0xFFE746            ## 16 bytes: CC7 volume per MIDI channel ($7F at reset)
const BENDS := 0xFFE756              ## 16 words: pitch bend per MIDI channel (-64..63)
const TRACK_VOLUME := 0xFFE776       ## word: volume of the track sending the current note
const NOTE_VOLUME := 0xFFE778        ## word: channel volume * track volume >> 7
const PARSER_HANDLER := 0xFFE77A     ## long: handler of the current MIDI status
const PARSER_COUNT := 0xFFE77E       ## word: data bytes received (0 = expecting a status)
const PARSER_LENGTH := 0xFFE780      ## word: data bytes the current status takes
const NOTE_SERIAL := 0xFFE782        ## word: +1 per allocated note
const MIDI_CHANNEL := 0xFFE784       ## byte: channel of the current status
const MIDI_DATA := 0xFFE785          ## 2 bytes: the current message's data bytes
const LOCK := 0xFFE789               ## byte: a voice routine is changing state (the tick skips)
const VOICE_HANDLE := 0xFFE78A       ## long: last voice handle
const CHANNELS := 0xFFE78E           ## 14 channel structs of $42 bytes
const CHANNEL_SIZE := 0x42
const N_CHANNELS := 14
const SFX_CHANNELS := 0xFFEA22       ## the last four: the PCM voices (records at $FFE704 + 12 n)
const SEQ_HANDLE := 0xFFEB2A         ## long: last sequence handle
const QUEUE_HEAD := 0xFFEB2E         ## long: first pending note-off
const QUEUE_TAIL := 0xFFEB32         ## long: where the next note-off goes
const QUEUE_END := 0xFFEB36          ## long: end of the ring ($FFF384)
const NOTES_ON := 0xFFEB3A           ## word: note-ons allowed (cleared for a muted class)
const MUSIC_ENABLE := 0xFFEB3C       ## word: 1 (the setters $18764.. are never called)
const SFX_ENABLE := 0xFFEB3E         ## word: 1 (likewise)
const SEQ_LOCK := 0xFFEB40           ## byte: $80 while a sequence starts / stops
const QUEUE_COUNT := 0xFFEB41        ## byte: pending note-offs (max 64)
const QUEUE_PEAK := 0xFFEB42         ## byte: highest count seen
const TRACKS_ACTIVE := 0xFFEB43      ## byte: tracks playing
const TRACKS := 0xFFEB44             ## 32 track structs of $2A bytes
const TRACK_SIZE := 0x2A
const N_TRACKS := 32
const QUEUE := 0xFFF084              ## 64 note-offs of 12 bytes
const QUEUE_ENTRY := 12
const QUEUE_SIZE := 0x300
const TRACK_PROGRAMS := 0xFFF384     ## 16 bytes: program last sent per MIDI channel
const INSTRUMENT_BASE := 0xFFE6A6    ## long: INSTRUMENTS ($15B4C)
const SAMPLE_BASE := 0xFFE6AA        ## long: SAMPLES ($15B46)
const DRIVER_LENGTH := 0xFFE6AE      ## word: Z80 driver length = Z80 address of the patches

# --- work RAM: the game side ($13BE0-$13FFF) ----------------------------------------
const MUSIC_HANDLE := 0xFFCA2C       ## long: -1 none
const MUSIC_SEQ := 0xFFCA30          ## long: 0 none
const MUSIC_REPEAT := 0xFFCA34       ## word ($FFxx via st.b): restart the music when it ends
const MUSIC_FADE := 0xFFCA36         ## word: ticks left before the music stops
const API_DEPTH := 0xFFCA38          ## word: an API call is running (the tick skips crowd / timeout)
const CROWD_HANDLE := 0xFFCA3A       ## long: crowd voice handle, -1 none
const CROWD_RATE := 0xFFCA3E         ## word: current crowd playback rate
const CROWD_VOL := 0xFFCA40          ## word: current crowd volume
const CROWD_RATE_TARGET := 0xFFCA42
const CROWD_VOL_TARGET := 0xFFCA44
const CROWD_ON := 0xFFCA46           ## word ($FFxx via st.b)
const POSITIONAL := 0xFFCA48         ## long: handle of the last $13D58 sound
const POSITIONAL_AGE := 0xFFCA4C     ## word: ticks since it started (stopped at 60)

## The RAM the driver owns, as half-open ranges (see [method ram_image]).
const GAME_VARS_START := 0xFFCA2C
const GAME_VARS_END := 0xFFCA4E
const DRIVER_VARS_START := 0xFFE6A6
const DRIVER_VARS_END := 0xFFF394

# --- channel struct fields -------------------------------------------------------------
const CH_INSTR := 0x00         ## long: instrument record (-1 none)
const CH_PATCH := 0x04         ## long: instrument whose FM patch the Z80 has (-1 none)
const CH_RECORD := 0x08        ## long: its change record
const CH_CACHE := 0x0C         ## long (FM) / word (PCM, PSG): last output pitch; PCM voices: handle
const CH_SERIAL := 0x10        ## word: note serial (a note-off takes the oldest)
const CH_BEND_KEY := 0x12      ## word: note index (x2 / x4) the bend delta was computed for
const CH_BEND := 0x14          ## word: the MIDI channel's bend at note-on / last bend
const CH_BANKS := 0x16         ## long: bank mask of a PCM voice
const CH_BEND_DELTA := 0x1A    ## word (PCM, PSG) / long (FM)
const CH_INDEX := 0x1E         ## byte: 0..13
const CH_MIDI := 0x1F          ## byte: MIDI channel
const CH_STATE := 0x20         ## byte: $FF free, 0 music note, 1 voice (sound_play / crowd)
const CH_PRIORITY := 0x21      ## byte
const CH_RELEASE := 0x22       ## byte: FM release ticks left
const CH_NOTE := 0x23          ## byte: MIDI note
const CH_KEY := 0x24           ## byte: note index into the pitch tables
const CH_PHASE := 0x25         ## byte: 0 off, 1 sounding, 2 FM releasing
const CH_PENV_STATE := 0x26    ## bytes: modulator states (0, 2, 4, ...)
const CH_VENV_STATE := 0x27
const CH_ARP_STATE := 0x28
const CH_VIB_STATE := 0x29
const CH_VOLUME := 0x2A        ## word: velocity * note volume >> 7
const CH_PENV := 0x2C          ## word: pitch envelope value
const CH_PENV_TIMER := 0x2E
const CH_VENV := 0x30          ## word: volume envelope value
const CH_VENV_TIMER := 0x32
const CH_ARP := 0x34           ## word: arpeggio offset (note index)
const CH_ARP_TIMER := 0x36
const CH_ARP_STEP_TIMER := 0x38
const CH_ARP_POS := 0x3A
const CH_VIB := 0x3C           ## word: vibrato value
const CH_VIB_TIMER := 0x3E
const CH_VIB_PHASE := 0x40

# --- track struct fields ------------------------------------------------------------------
const TR_STATE := 0x00         ## byte: 0 playing, 1 free, $FF paused (pause: the unused $1881C)
const TR_CHANNEL := 0x01       ## byte: MIDI channel
const TR_LOOP_COUNT := 0x02
const TR_INDEX := 0x03         ## byte: track number in its sequence
const TR_TEMPO := 0x04         ## long: 16.16 clocks per tick
const TR_FRACTION := 0x08      ## word: fractional clock
const TR_VOLUME := 0x0A        ## word: $80 = full
const TR_VOLUME_TARGET := 0x0C
const TR_FADE_STEP := 0x0E
const TR_LOOP := 0x10          ## long: loop start
const TR_START := 0x14         ## long: first event (after the initial delta)
const TR_POS := 0x18           ## long: next event
const TR_WAIT := 0x1C          ## long: clocks to wait - 1
const TR_FIRST_WAIT := 0x20    ## long
const TR_HANDLE := 0x24        ## long: sequence handle
const TR_PROGRAM := 0x28       ## byte: program
const TR_SLOT := 0x29          ## byte: 0..31

## Instrument types (byte 0) = allocation classes.
const PCM := 0
const FM := 1
const PSG := 2
const PCM_PITCHED := 3
const NOISE := 4

## MIDI status >> 4 & 7 -> handler address kept at $E77A and the data bytes it
## takes (table $173CA): note off, note on, aftertouch, control, program,
## channel pressure, pitch bend, system.
const _MSG_HANDLER := [0x173EA, 0x174D2, 0x1797C, 0x178AA, 0x178F0, 0x1797C, 0x17904, 0x1797E]
const _MSG_LENGTH := [2, 2, 2, 2, 1, 2, 2, 2]
const _MSG_NAME := ["note_off", "note_on", "nothing", "control", "program", "nothing", "bend", "nothing"]
## [member drops] kinds.
const DROP_KILLED := 0
const DROP_STOLEN := 1
const DROP_CUT := 2
const DROP_REFUSED := 3
const DROP_NOTE_OFF := 4
## The bytes of the records $15BA8 resets to $FF ("no change") after a copy.
const _RECORD_RESETS := [0, 4, 0xA, 0xE, 0x14, 0x18, 0x1E, 0x22, 0x28, 0x2C, 0x32, 0x36,
		0x3C, 0x42, 0x48, 0x4E, 0x54, 0x58, 0x60, 0x64, 0x6C, 0x70, 0x78, 0x7C]

## Why the last [method vblank] sent nothing: `$17B20`'s early returns.
enum Skip { NONE, Z80, LOCK }

## Image of work RAM `$FF0000-$FFFFFF` (only the sound areas are used).
var mem := PackedByteArray()
## The ROM.
var rom := PackedByteArray()
## 50 Hz console: PAL tempo table (the original tests the version register).
var pal := false
## Bits 8-15 of the caller's d5 in [method music_fade_out] (see there).
var d5_high := 0
## Called with (kind, ...) for every MIDI message (kind, channel, data 1,
## data 2) and channel allocation ("alloc", channel 0-13, instrument index).
var trace := Callable()
## [enum Skip]: why the last [method vblank] did nothing.
var skipped := Skip.NONE
## The PCM sounds the driver cut short or refused since the last [method
## take_drops], for want of a channel or a bank, or by the positional rule
## (observation only: recording them changes nothing in the driver; the audio
## service's enhancement switches play them anyway, [member MwAudio.free_music_samples],
## [member MwAudio.free_effects]). Entries:
## [code][DROP_KILLED, v, state, midi, note][/code] PCM struct v (0-3 = Z80
## channel v) killed by `$172A0` for a new sample sharing no bank with it;
## [code][DROP_STOLEN, v, 0, midi, note][/code] its music note taken over by
## `$16958` for a new sound (state: what struct v held, 0 a music note, 1 a
## voice; a note's MIDI channel and key); [code][DROP_CUT, v, 1][/code] the
## positional voice on it stopped by `$13CEE` / `$13D58` for the next sound
## (not the 60-tick limit: that is the positional sounds' length);
## [code][DROP_REFUSED, instrument, rate, volume, state, midi, note][/code] a
## sample note (state 0) or voice (1, midi and note -1) that could not start:
## its instrument record, rate (8.8) and volume (`$80` = unity) as it would
## have played; [code][DROP_NOTE_OFF, midi, note][/code] a note-off that found
## no note (the note was refused, killed or stolen).
var drops: Array = []
## Whether [member drops] are noted (off: the checks and tests).
var note_drops := false

var _stolen := -1              # the music note's struct allocate() last took, else -1
var _stolen_note := [-1, -1]   # its MIDI channel and key
var _cutting := false          # inside the positional rule's sound_stop calls

var _vlq_end := 0              # where the number the last _vlq() read ended


func _init(rom_data: PackedByteArray) -> void:
	rom = rom_data
	mem.resize(0x10000)


# --- memory ------------------------------------------------------------------------------
## Work RAM byte / word / long at [param a] (big-endian; `a & $FFFF`).
func r8(a: int) -> int:
	return mem[a & 0xFFFF]


func r16(a: int) -> int:
	var i := a & 0xFFFF
	return (mem[i] << 8) | mem[i + 1]


func r32(a: int) -> int:
	return (r16(a) << 16) | r16(a + 2)


func w8(a: int, v: int) -> void:
	mem[a & 0xFFFF] = v & 0xFF


func w16(a: int, v: int) -> void:
	var i := a & 0xFFFF
	mem[i] = (v >> 8) & 0xFF
	mem[i + 1] = v & 0xFF


func w32(a: int, v: int) -> void:
	w16(a, v >> 16)
	w16(a + 2, v)


func rom8(a: int) -> int:
	return rom[a & 0xFFFFFF]


func rom16(a: int) -> int:
	var i := a & 0xFFFFFF
	return (rom[i] << 8) | rom[i + 1]


func rom32(a: int) -> int:
	return (rom16(a) << 16) | rom16(a + 2)


static func _s8(v: int) -> int:
	v &= 0xFF
	return v - 0x100 if v & 0x80 else v


static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v & 0x8000 else v


static func _s32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v & 0x80000000 else v


## A RAM address as the original stores it: `lea $xxxx.w` sign-extends, so
## pointers into $FF8000-$FFFFFF read $FFFFxxxx.
static func _ptr(a: int) -> int:
	return a | 0xFF000000


## `$17EE4`: MIDI variable-length number at ROM [param a]; [member _vlq_end]
## = the address after it.
func _vlq(a: int) -> int:
	var v := 0
	while true:
		var b := rom8(a)
		a += 1
		v = ((v << 7) | (b & 0x7F)) & 0xFFFFFFFF
		if (b & 0x80) == 0:
			break
	_vlq_end = a
	return v


## ROM address of instrument [param index] (the table at `$E6A6`).
func instrument(index: int) -> int:
	var base := r32(INSTRUMENT_BASE)
	return base + rom16(base + 2 * (index & 0x7FFF))


## RAM address of channel struct [param n] (0-13).
func channel(n: int) -> int:
	return CHANNELS + n * CHANNEL_SIZE


## The sound RAM: `$FFCA2C-$FFCA4D` then `$FFE6A6-$FFF393` (checks, tests).
func ram_image() -> PackedByteArray:
	var out := mem.slice(GAME_VARS_START & 0xFFFF, GAME_VARS_END & 0xFFFF)
	out.append_array(mem.slice(DRIVER_VARS_START & 0xFFFF, DRIVER_VARS_END & 0xFFFF))
	return out


# --- set-up ------------------------------------------------------------------------------
## `$13C18` (also `$13BE0` at boot): game-side state cleared, all driver state
## reset (`$16922` = `$168BE` clearing `$FFE6B0-$FFE735`, `$18706`, `$15C14`),
## the instrument and sample bases set (`$15B4C`, `$15B46`). The Z80 side's
## upload (driver, FM patches) is [method MwSoundZ80.reset].
func reset() -> void:
	w32(MUSIC_HANDLE, 0xFFFFFFFF)
	w32(MUSIC_SEQ, 0)
	w16(MUSIC_REPEAT, 0)
	w16(MUSIC_FADE, 0)
	w16(API_DEPTH, 0)
	w32(CROWD_HANDLE, 0xFFFFFFFF)
	w16(CROWD_ON, 0)
	w32(POSITIONAL, 0xFFFFFFFF)
	w16(POSITIONAL_AGE, 0)
	for a in range(RECORDS, RECORDS + 0x86):
		w8(a, 0)
	w16(DRIVER_LENGTH, rom16(Z80_DRIVER))
	_seq_init()
	_channels_init()
	w32(INSTRUMENT_BASE, INSTRUMENTS)       # $15B4C (the FM patches go to the Z80 after the driver)
	for n in N_CHANNELS:
		w32(channel(n) + CH_PATCH, 0xFFFFFFFF)
	for c in 16:
		w8(VOLUMES + c, 0x7F)
	w32(SAMPLE_BASE, SAMPLES)               # $15B46


## `$18706`: tracks free (only state and slot written), queue empty.
func _seq_init() -> void:
	w8(QUEUE_COUNT, 0)
	w8(TRACKS_ACTIVE, 0)
	w8(QUEUE_PEAK, 0)
	w32(QUEUE_HEAD, _ptr(QUEUE))
	w32(QUEUE_TAIL, _ptr(QUEUE))
	w32(QUEUE_END, _ptr(QUEUE + QUEUE_SIZE))
	w32(SEQ_HANDLE, 0)
	for i in N_TRACKS:
		var t := TRACKS + i * TRACK_SIZE
		w8(t + TR_STATE, 1)
		w8(t + TR_SLOT, i)
	w16(MUSIC_ENABLE, 1)
	w16(SFX_ENABLE, 1)
	w8(SEQ_LOCK, 0)


## `$15BA8`: every record's flag / value bytes back to $FF ("no change").
func _records_unchanged() -> void:
	for o: int in _RECORD_RESETS:
		w32(RECORDS + o, 0xFFFFFFFF)
	w8(DIRTY, 0)


## `$15C14`: channels free, each record "changed, key off" (sent at the next tick).
func _channels_init() -> void:
	w32(VOICE_HANDLE, 0)
	w16(NOTE_SERIAL, 0)
	w16(TRACK_VOLUME, 0x80)
	_records_unchanged()
	for n in N_CHANNELS:
		var c := channel(n)
		w8(c + CH_STATE, 0xFF)
		w8(c + CH_INDEX, n)
		w32(c + CH_INSTR, 0xFFFFFFFF)
		w32(c + CH_PATCH, 0xFFFFFFFF)
		var rec := RECORDS + rom16(CHANNEL_RECORDS + 2 * n)
		w32(c + CH_RECORD, _ptr(rec))
		w16(rec, 0)
	for c in 16:
		w16(BENDS + 2 * c, 0)
	w8(LOCK, 0)
	w16(NOTES_ON, 1)
	w8(DIRTY, 1)
	w16(PARSER_COUNT, 0)


# --- the game's API ($13BE0-$13FFF) ---------------------------------------------------------
## `$13C66`: the title music (also the play-offs champion's), repeated.
func music_title() -> void:
	music_start(MUSIC_TITLE)


## `$13C6E`: the menus' music, repeated.
func music_game() -> void:
	music_start(MUSIC_GAME)


## `$13C66` / `$13C6E`: play sequence [param seq] (ROM address) and repeat it;
## nothing restarts if it is already the current music.
func music_start(seq: int) -> void:
	if r32(MUSIC_SEQ) != seq:
		if r32(MUSIC_SEQ) != 0:
			seq_stop(r32(MUSIC_HANDLE))
		w32(MUSIC_SEQ, seq)
		w32(MUSIC_HANDLE, seq_start(seq))
	w8(MUSIC_REPEAT, 0xFF)          # st.b: the word's high byte
	w16(MUSIC_FADE, 0)


## `$13CAC`: stop the music after [param ticks] (0 = 1) ticks. It also asks the
## sequencer for a fade to 0 with step ($100 + ticks) / 2 / ticks, but `$1896C`
## moves only that step's (negated) low byte into d5 before storing the word:
## the high byte is the caller's d5 bits 8-15 ([member d5_high]). With $FF the
## step is -4..-1 and the track volume rises; otherwise it is >= $F8 and the
## volume is 0 at the next clock (new notes muted, sounding ones play on). The
## music stops when the count ends either way.
func music_fade_out(ticks: int) -> void:
	if r32(MUSIC_SEQ) == 0:
		return
	ticks &= 0xFFFF
	if ticks == 0:
		ticks = 1
	w16(MUSIC_FADE, ticks)
	@warning_ignore("integer_division")
	var q := (((0x100 + ticks) & 0xFFFF) >> 1) / ticks         # divu.w
	seq_fade(r32(MUSIC_HANDLE), -1, 0, -q, d5_high << 8)


## `$13C04` (match, play-offs, fight): music fade (its d0 [param fade_ticks]
## is the caller's, so the tracks get stale fade fields), crowd off, then
## [method reset]. `$13C18` also re-uploads the Z80 driver: the caller resets
## [MwSoundZ80] too ([method MwAudio.enter_match]).
func enter_match(fade_ticks: int) -> void:
	music_fade_out(fade_ticks)
	crowd_off()
	reset()


## `$13CEE`: stops the last positional sound, then starts [param id]: ids
## 0..$11 are sequences (handle with bit 31 set), $12..$4C sample voices
## (instrument from `$1F5C6`, rate $100, volume $100 -> $80). Returns the
## handle (-1 = `$FFFFFFFF` when the voice could not start; for ids the tables
## don't cover, garbage as in the original).
func sound_play(id: int) -> int:
	_api(1)
	_cut_positional()
	var d0 := id & 0xFFFF
	var handle := 0
	if d0 < 0x12:
		var seq := rom32(SEQUENCES + 4 * d0)
		handle = (seq_start(seq) | 0x80000000) if seq != 0 else 4 * d0
	elif d0 - 0x12 < 0x3B:
		var index := rom16(VOICE_IDS + 2 * (d0 - 0x12))
		handle = index if (index & 0x8000) != 0 else voice_start(index, 0x100, 0x100)
	else:
		handle = d0 - 0x12
	_api(-1)
	return handle & 0xFFFFFFFF


## `$13CE2`: sound 5 + (rng & 3), [param rng_value] being the caller's draw
## from the game's generator (`$4BC6`).
func random_sound(rng_value: int) -> int:
	return sound_play(5 + (rng_value & 3))


## `$13D58` (the rink's objects): when the object is on screen ([param
## on_screen]: `$5C3C`, the caller's test), stop the last positional sound,
## start this one, restart its 60-tick limit and the crowd if it stopped.
## Returns the original's d0: the id (its low word; the high word is stale in
## the original). The handle is kept at `$FFCA48`.
func positional(id: int, on_screen: bool) -> int:
	_api(1)
	if on_screen:
		_cut_positional()
		w32(POSITIONAL, sound_play(id))
		w16(POSITIONAL_AGE, 0)
		crowd_restart()
	_api(-1)
	return id & 0xFFFF


## `$13D92`: stop the last positional sound.
func stop_positional() -> void:
	sound_stop(r32(POSITIONAL))


## The positional rule's stop of the last positional sound (`sound_stop` of
## `$FFCA48`), noted in [member drops].
func _cut_positional() -> void:
	_cutting = true
	sound_stop(r32(POSITIONAL))
	_cutting = false


func _drop(entry: Array) -> void:
	if note_drops:
		drops.append(entry)


## The drops noted since the last call ([member drops]), oldest first.
func take_drops() -> Array:
	var d := drops
	drops = []
	return d


## `$13D9C`: is the sequence or voice [param handle] still playing?
func sound_busy(handle: int) -> bool:
	if (handle & 0x80000000) != 0:
		return seq_busy(handle & 0x7FFFFFFF)
	return voice_busy(handle)


## `$13DC2`: stop the sequence or voice [param handle].
func sound_stop(handle: int) -> void:
	_api(1)
	if (handle & 0x80000000) != 0:
		seq_stop(handle & 0x7FFFFFFF)
	else:
		voice_stop(handle)
	_api(-1)


## `$13E52`: crowd noise (instrument $50, a looped sample on the fourth PCM
## voice) at [param level] 0..1000: started if needed (rate $E0, volume $40),
## then rate and volume glide (`$13F1C`, per tick) towards $C0 + q and
## $80 + 2q, q = level * $80 / 1000.
func crowd_level(level: int) -> void:
	_api(1)
	var h := r32(CROWD_HANDLE)
	if not (r16(CROWD_ON) != 0 and (h & 0x80000000) == 0 and voice_busy(h)):
		w16(CROWD_RATE, 0xE0)
		w16(CROWD_VOL, 0x40)
		h = voice_start(0x50, 0xE0, 0x40)
		w32(CROWD_HANDLE, h)
		if (h & 0x80000000) != 0:
			_api(-1)
			return
		w8(CROWD_ON, 0xFF)
	@warning_ignore("integer_division")
	var q := (((level & 0xFFFF) * 0x80) / 1000) & 0xFFFF
	w16(CROWD_VOL_TARGET, 2 * q + 0x80)
	w16(CROWD_RATE_TARGET, q + 0xC0)
	_api(-1)


## `$13EB6`: restart the crowd voice (current rate / volume) when it is on but
## no longer playing.
func crowd_restart() -> void:
	_api(1)
	if r16(CROWD_ON) != 0:
		var h := r32(CROWD_HANDLE)
		if (h & 0x80000000) != 0 or not voice_busy(h):
			w32(CROWD_HANDLE, voice_start(0x50, r16(CROWD_RATE), r16(CROWD_VOL)))
	_api(-1)


## `$13EEA`: crowd off by fading (volume -8 per tick, then stopped).
func crowd_fade() -> void:
	w16(CROWD_ON, 0)
	w16(CROWD_VOL_TARGET, 0)


## `$13EFC`: crowd voice stopped at once.
func crowd_off() -> void:
	_api(1)
	var h := r32(CROWD_HANDLE)
	if (h & 0x80000000) == 0:
		voice_stop(h)
		w32(CROWD_HANDLE, 0xFFFFFFFF)
	w16(CROWD_ON, 0)
	_api(-1)


## `$CA38` += [param d]: the API depth the tick tests.
func _api(d: int) -> void:
	w16(API_DEPTH, r16(API_DEPTH) + d)


## `$13F1C`: crowd rate +-4 and volume +-8 per tick towards the targets; at
## volume 0 with the crowd off, the voice is stopped.
func _crowd_tick() -> void:
	var h := r32(CROWD_HANDLE)
	if (h & 0x80000000) != 0:
		return
	var rate := _s16(r16(CROWD_RATE))
	var target := _s16(r16(CROWD_RATE_TARGET))
	if rate != target:
		rate = mini(rate + 4, target) if rate < target else maxi(rate - 4, target)
		w16(CROWD_RATE, rate)
		voice_rate(h, rate)
	var vol := _s16(r16(CROWD_VOL))
	target = _s16(r16(CROWD_VOL_TARGET))
	if vol == target:
		return
	vol = mini(vol + 8, target) if vol < target else maxi(vol - 8, target)
	if vol == 0 and r16(CROWD_ON) == 0:
		voice_stop(h)
		w32(CROWD_HANDLE, 0xFFFFFFFF)
		return
	w16(CROWD_VOL, vol)
	voice_volume(h, vol)


# --- the tick --------------------------------------------------------------------------------
## `$13DE8`, the VBlank task (every 60 Hz tick): music fade-out count and
## repeat, crowd glide, the positional sounds' 60-tick limit, then the
## driver's tick `$17B20`. Talks to the Z80 only through
## [method MwSoundZ80.batch_pending], [method MwSoundZ80.voice_status] and
## [method MwSoundZ80.clear_voice]. Returns the 133 bytes copied to Z80
## `$0038-$00BC` this tick (the change records; then Z80 `$00BD` = 1), or an
## empty array.
func vblank(z80: MwSoundZ80) -> PackedByteArray:
	var fade := r16(MUSIC_FADE)
	if fade != 0:
		fade -= 1
		w16(MUSIC_FADE, fade)
		if fade == 0:
			seq_stop(r32(MUSIC_HANDLE))
			w32(MUSIC_HANDLE, 0xFFFFFFFF)
			w32(MUSIC_SEQ, 0)
			w16(MUSIC_REPEAT, 0)
	if r16(MUSIC_REPEAT) != 0 and not seq_busy(r32(MUSIC_HANDLE)):
		w32(MUSIC_HANDLE, seq_start(r32(MUSIC_SEQ)))     # a new handle
	if r16(API_DEPTH) == 0:
		_crowd_tick()
		var age := (r16(POSITIONAL_AGE) + 1) & 0xFFFF
		w16(POSITIONAL_AGE, age)
		if age >= 60:
			sound_stop(r32(POSITIONAL))
	return driver_tick(z80)


## `$17B20`: modulators, sequencer, then the change records to the Z80 (when
## changed) and the PCM voices the Z80 reports ended freed.
func driver_tick(z80: MwSoundZ80) -> PackedByteArray:
	if z80.batch_pending():                 # the Z80 has not taken the last block
		skipped = Skip.Z80
		return PackedByteArray()
	if r8(LOCK) != 0:
		skipped = Skip.LOCK
		return PackedByteArray()
	skipped = Skip.NONE
	if r8(SEQ_LOCK) == 0:
		channels_tick()                     # $1715E
		seq_tick()                          # $18CD0
	var block := PackedByteArray()
	var copied := r8(DIRTY) != 0
	if copied:
		var start := RECORDS & 0xFFFF
		block = mem.slice(start, start + RECORDS_LEN)
	for v in 4:
		# Z80 status < 0 ($F0: the sample ended) and no command for that voice
		# this tick: status 0, the voice's channel free.
		var rec := RECORDS + 0x54 + 12 * v
		if (z80.voice_status(v) & 0x80) != 0 and (r8(rec) & 0x80) != 0:
			z80.clear_voice(v)
			w8(SFX_CHANNELS + v * CHANNEL_SIZE + CH_STATE, 0xFF)
	if copied:
		_records_unchanged()
	return block


# --- sequencer ($18890 ..) -------------------------------------------------------------------
## `$18890`: start every track of sequence [param seq] (ROM address) on a free
## track slot (searched from slot 0 for each); returns the new handle.
func seq_start(seq: int) -> int:
	var handle := (r32(SEQ_HANDLE) + 1) & 0xFFFFFFFF
	w32(SEQ_HANDLE, handle)
	var saved_lock := r8(SEQ_LOCK)
	w8(SEQ_LOCK, 0x80)
	var n_tracks := rom16(seq + 2)
	var tempo_table := TEMPO_PAL if pal else TEMPO_NTSC
	var i := 0
	while true:
		var pos := seq + _s16(rom16(seq + 4 + 4 * i))
		var midi_ch := rom16(seq + 6 + 4 * i)
		var t := -1
		for s in N_TRACKS:
			var u := TRACKS + s * TRACK_SIZE
			var st := r8(u + TR_STATE)
			if st != 0 and (st & 0x80) == 0:
				t = u
				break
		if t < 0:
			break
		w8(t + TR_STATE, 0)
		w8(TRACKS_ACTIVE, r8(TRACKS_ACTIVE) + 1)
		w32(t + TR_HANDLE, handle)
		w8(t + TR_INDEX, i)
		w8(t + TR_CHANNEL, midi_ch)
		w32(t + TR_TEMPO, rom32(tempo_table + 4 * rom8(seq + 1)))
		w16(t + TR_FRACTION, 0)
		w16(t + TR_VOLUME, 0x80)
		w16(t + TR_VOLUME_TARGET, 0x80)
		w16(t + TR_FADE_STEP, 0)
		var wait := _vlq(pos)
		pos = _vlq_end
		w32(t + TR_START, pos)
		w32(t + TR_POS, pos)
		if wait != 0:
			wait -= 1
		w32(t + TR_WAIT, wait)
		w32(t + TR_FIRST_WAIT, wait)
		i = (i + 1) & 0xFFFF
		if i == n_tracks:
			break
	w8(SEQ_LOCK, saved_lock)
	return handle


## `$187B4`: free the playing tracks of [param handle]; their pending
## note-offs get duration 0 (sent at the next tick).
func seq_stop(handle: int) -> void:
	var saved := r8(SEQ_LOCK)
	w8(SEQ_LOCK, 0x80)
	handle &= 0xFFFFFFFF
	for s in N_TRACKS:
		var t := TRACKS + s * TRACK_SIZE
		if r32(t + TR_HANDLE) != handle or r8(t + TR_STATE) != 0:
			continue
		w8(TRACKS_ACTIVE, r8(TRACKS_ACTIVE) - 1)
		w8(t + TR_STATE, 1)
		var slot := r8(t + TR_SLOT)
		var e := r32(QUEUE_HEAD)
		while e != r32(QUEUE_TAIL):
			if r8(e + 10) == slot:
				w32(e, 0)
			e += QUEUE_ENTRY
			if e == r32(QUEUE_END):
				e = _ptr(QUEUE)
	w8(SEQ_LOCK, saved)


## `$189BE`: a track of [param handle] is playing.
func seq_busy(handle: int) -> bool:
	handle &= 0xFFFFFFFF
	for s in N_TRACKS:
		var t := TRACKS + s * TRACK_SIZE
		if r8(t + TR_STATE) == 0 and r32(t + TR_HANDLE) == handle:
			return true
	return false


## `$1896C`: fade the tracks of [param handle] ([param track] < 0: all, else
## only the one with that index) to volume [param target]; [param step]'s low
## byte is the step per clock (0: jump at once). The stored step word is
## [param d5] with that byte moved into its low byte: its high byte is
## whatever the caller had in d5 (0 after a track that was at the target).
func seq_fade(handle: int, track: int, target: int, step: int, d5: int) -> void:
	for s in N_TRACKS:
		var t := TRACKS + s * TRACK_SIZE
		if r8(t + TR_STATE) != 0 or r32(t + TR_HANDLE) != (handle & 0xFFFFFFFF):
			continue
		if track >= 0 and r8(t + TR_INDEX) != track:
			continue
		d5 = (d5 & ~0xFF) | (step & 0xFF)
		if (step & 0xFF) == 0:
			w16(t + TR_VOLUME, target)
		w16(t + TR_VOLUME_TARGET, target)
		if r16(t + TR_VOLUME) == (target & 0xFFFF):
			d5 &= ~0xFFFF
		w16(t + TR_FADE_STEP, d5)
		if track >= 0:
			return


## `$18CD0`: pending note-offs (head to tail; an expired entry is replaced by
## the head entry, the head advances), then each playing track's whole clocks
## this tick.
func seq_tick() -> void:
	if r8(QUEUE_COUNT) != 0:
		var e := r32(QUEUE_HEAD)
		while true:
			var left := (r32(e) - r32(e + 4)) & 0xFFFFFFFF
			w32(e, left)
			if left == 0 or (left & 0x80000000) != 0:
				midi(0x80 | r8(e + 9))
				midi(r8(e + 8))
				midi(0)
				var head := r32(QUEUE_HEAD)
				if head != e:
					for k in range(0, 12, 4):
						w32(e + k, r32(head + k))
				head += QUEUE_ENTRY
				if head == r32(QUEUE_END):
					head = _ptr(QUEUE)
				w32(QUEUE_HEAD, head)
				w8(QUEUE_COUNT, r8(QUEUE_COUNT) - 1)
			e += QUEUE_ENTRY
			if e == r32(QUEUE_END):
				e = _ptr(QUEUE)
			if e == r32(QUEUE_TAIL):
				break
	if r8(TRACKS_ACTIVE) == 0:
		return
	for s in N_TRACKS:
		var t := TRACKS + s * TRACK_SIZE
		if r8(t + TR_STATE) != 0:
			continue
		var acc := r16(t + TR_FRACTION) + r32(t + TR_TEMPO)
		w16(t + TR_FRACTION, acc)
		for _clock in (acc >> 16) & 0xFFFF:
			if track_clock(t):
				return          # a sequence ended or looped: no more tracks this tick


## `$189E0`: one MIDI clock (1/24 beat) of track [param t]: the volume fade,
## then the events due. True when a sequence stopped / looped. (No state
## test: a track that ended earlier in this tick runs its remaining clocks
## again from its last saved position.)
func track_clock(t: int) -> bool:
	var vol := _s16(r16(t + TR_VOLUME))
	var target := _s16(r16(t + TR_VOLUME_TARGET))
	var step := _s16(r16(t + TR_FADE_STEP))
	if vol != target:
		if vol < target:
			vol = _s16(vol + step)
			if not vol < target:
				vol = target
		else:
			vol = _s16(vol - step)
			if not vol > target:
				vol = target
		w16(t + TR_VOLUME, vol)
	var wait := r32(t + TR_WAIT)
	if wait != 0:
		w32(t + TR_WAIT, wait - 1)
		return false
	var enable := SFX_ENABLE if (r8(t + TR_HANDLE) & 0x80) != 0 else MUSIC_ENABLE
	if r16(enable) == 0:
		w16(NOTES_ON, 0)
	var pos := r32(t + TR_POS)
	var ch := r8(t + TR_CHANNEL)
	while true:
		var op := rom8(pos)
		pos += 1
		if op < 0xD9:
			pos = _note(t, op, pos)
		elif op > 0xEA or op == 0xE6:
			push_error("MwSound68k: illegal sequence opcode $%X at $%X" % [op, pos - 1])
			return false
		elif op == 0xE2:                    # loop start: count
			w8(t + TR_LOOP_COUNT, rom8(pos))
			pos += 1
			w32(t + TR_LOOP, pos)
		elif op == 0xE3:                    # loop end
			var n := r8(t + TR_LOOP_COUNT)
			if n != 0:
				w8(t + TR_LOOP_COUNT, n - 1)
				pos = r32(t + TR_LOOP)
		elif op == 0xD9:                    # end of track (position not saved)
			if r8(t + TR_STATE) == 0:
				w8(t + TR_STATE, 1)
				w8(TRACKS_ACTIVE, r8(TRACKS_ACTIVE) - 1)
			return false
		elif op == 0xDA:                    # end of sequence: all its tracks
			var h := r32(t + TR_HANDLE)
			for s in N_TRACKS:
				var u := TRACKS + s * TRACK_SIZE
				if r8(u + TR_STATE) == 0 and r32(u + TR_HANDLE) == h:
					w8(u + TR_STATE, 1)
					w8(TRACKS_ACTIVE, r8(TRACKS_ACTIVE) - 1)
			w16(NOTES_ON, 1)
			return true
		elif op == 0xDB:                    # restart all its tracks
			var h := r32(t + TR_HANDLE)
			for s in N_TRACKS:
				var u := TRACKS + s * TRACK_SIZE
				if r8(u + TR_STATE) == 0 and r32(u + TR_HANDLE) == h:
					w32(u + TR_POS, r32(u + TR_START))
					w32(u + TR_WAIT, r32(u + TR_FIRST_WAIT))
					w16(u + TR_FRACTION, 0)
			w16(NOTES_ON, 1)
			return true
		elif op == 0xDC:                    # program change
			midi(0xC0 | ch)
			var prog := rom8(pos)
			pos += 1
			w8(t + TR_PROGRAM, prog)
			w8(TRACK_PROGRAMS + ch, prog)
			midi(prog)
		elif op == 0xDD or op == 0xDE:      # one ignored byte (DD: the tempo in BPM)
			pos += 1
		elif op == 0xDF:                    # control change
			midi(0xB0 | ch)
			midi(rom8(pos))
			midi(rom8(pos + 1))
			pos += 2
		elif op == 0xE5:                    # pitch bend
			midi(0xE0 | ch)
			midi(rom8(pos))
			midi(rom8(pos + 1))
			pos += 2
		elif op == 0xE7:                    # skip n bytes
			pos += 1 + rom8(pos)
		elif op == 0xEA:                    # skip 1 byte
			pos += 1
		# $E0 $E1 $E4 $E8 $E9: no operand, nothing
		var delta := _vlq(pos)
		pos = _vlq_end
		if delta != 0:
			w32(t + TR_POS, pos)
			w32(t + TR_WAIT, delta - 1)
			w16(NOTES_ON, 1)
			return false
	return false


## A note event (`$18BCA`): key (+ velocity byte if bit 7, else $7F), VLQ
## length in clocks; note-off queued, the program re-sent if the channel's
## last one differs, note-on sent. Skipped when the length or the track
## volume is 0 or the queue is full. Returns the position after it.
func _note(t: int, op: int, pos: int) -> int:
	var key := op
	var vel := 0x7F
	if (op & 0x80) != 0:
		key = op & 0x7F
		vel = rom8(pos)
		pos += 1
	var length := _vlq(pos)
	pos = _vlq_end
	if length == 0:
		return pos
	var vol := r16(t + TR_VOLUME)
	if vol == 0:
		return pos
	w16(TRACK_VOLUME, vol)
	if key >= 0x58:
		push_error("MwSound68k: note $%X out of range" % key)
		return pos
	key += 0x18
	if r8(QUEUE_COUNT) == 0x40:
		return pos
	var e := r32(QUEUE_TAIL)
	w32(e, (((length & 0xFFFF) << 16) - r16(t + TR_FRACTION)) & 0xFFFFFFFF)
	w32(e + 4, r32(t + TR_TEMPO))
	var ch := r8(t + TR_CHANNEL)
	w8(e + 8, key)
	w8(e + 9, ch)
	w8(e + 10, r8(t + TR_SLOT))
	e += QUEUE_ENTRY
	if e == r32(QUEUE_END):
		e = _ptr(QUEUE)
	w32(QUEUE_TAIL, e)
	var n := (r8(QUEUE_COUNT) + 1) & 0xFF
	w8(QUEUE_COUNT, n)
	if not _s8(n) < _s8(r8(QUEUE_PEAK)):
		w8(QUEUE_PEAK, n)
	if ch != 9:
		var prog := r8(t + TR_PROGRAM)
		if prog != r8(TRACK_PROGRAMS + ch):
			midi(0xC0 | ch)
			midi(prog)
	midi(0x90 | ch)
	midi(key)
	midi(vel)
	return pos


# --- MIDI messages ($17356) ------------------------------------------------------------------
## `$17356`: one byte of a MIDI message (running status kept); a complete
## message goes to its handler (table `$173CA`, address kept at `$E77A`).
func midi(byte: int) -> void:
	var count := r16(PARSER_COUNT)
	if count == 0:
		if (byte & 0x80) != 0:
			w8(MIDI_CHANNEL, byte & 0x0F)
			var m := (byte >> 4) & 7
			w16(PARSER_LENGTH, _MSG_LENGTH[m])
			w32(PARSER_HANDLER, _MSG_HANDLER[m])
			w16(PARSER_COUNT, 1)
			return
		count = 1
		w16(PARSER_COUNT, 1)
	w8(MIDI_DATA + count - 1, byte)
	if count != r16(PARSER_LENGTH):
		w16(PARSER_COUNT, count + 1)
		return
	w16(PARSER_COUNT, 0)
	var address := r32(PARSER_HANDLER)
	if trace.is_valid():
		trace.call(_MSG_NAME[_MSG_HANDLER.find(address)], r8(MIDI_CHANNEL), r8(MIDI_DATA), r8(MIDI_DATA + 1))
	match address:
		0x173EA:
			_msg_note_off()
		0x174D2:
			_msg_note_on()
		0x178AA:
			_msg_control()
		0x178F0:
			_msg_program()
		0x17904:
			_msg_bend()
		_:
			pass        # $1797C / $1797E: aftertouch, channel pressure, $Fx: ignored


## `$178F0`: program change.
func _msg_program() -> void:
	w8(PROGRAMS + r8(MIDI_CHANNEL), r8(MIDI_DATA))


## `$178AA`: control change; only controller 7 (channel volume) does something.
func _msg_control() -> void:
	if r8(MIDI_DATA) == 7:
		w8(VOLUMES + r8(MIDI_CHANNEL), r8(MIDI_DATA + 1))


## `$17904`: bend = second data byte - $40, re-applied to the channel's music
## notes (FM, PSG, pitched PCM; plain PCM keeps its rate).
func _msg_bend() -> void:
	var ch := r8(MIDI_CHANNEL)
	var bend := (r8(MIDI_DATA + 1) - 0x40) & 0xFFFF
	w16(BENDS + 2 * ch, bend)
	for n in N_CHANNELS:
		var c := channel(n)
		if r8(c + CH_STATE) != 0 or r8(c + CH_MIDI) != ch:
			continue
		w16(c + CH_BEND, bend)
		w16(c + CH_BEND_KEY, 0)
		var kind := rom8(r32(c + CH_INSTR))
		if kind == PSG:
			_psg_pitch(c)
		elif kind == PCM_PITCHED:
			_pcm_pitch(c)
		elif kind == FM:
			_fm_pitch(c)


## `$173EA`: note off for the oldest sounding music note with this channel and
## key (the last of equal serials).
func _msg_note_off() -> void:
	var key := r8(MIDI_DATA)
	var ch := r8(MIDI_CHANNEL)
	var found := -1
	var serial := 0
	for n in N_CHANNELS:
		var o := channel(n)
		if (r8(o + CH_STATE) == 0 and r8(o + CH_MIDI) == ch
				and r8(o + CH_NOTE) == key and r8(o + CH_PHASE) == 1):
			if found < 0 or serial >= r16(o + CH_SERIAL):
				found = o
				serial = r16(o + CH_SERIAL)
	if found < 0:
		_drop([DROP_NOTE_OFF, ch, key])
		return
	var c := found
	w8(c + CH_PHASE, 0)
	var instr := r32(c + CH_INSTR)
	var kind := rom8(instr)
	var rec := r32(c + CH_RECORD)
	if kind == PCM or kind == PCM_PITCHED:
		if (rom8(instr + 0x10) & 2) != 0:   # one-shot: plays on
			return
		w8(rec + 1, 0)
		w8(rec, 0)
		w8(DIRTY, 1)
		w8(c + CH_STATE, 0xFF)
	elif kind == FM:
		var release := rom8(instr + 0x41)
		if release != 0:
			w8(c + CH_PHASE, 2)
			w8(c + CH_RELEASE, release)
		else:
			w8(c + CH_STATE, 0xFF)
		w8(rec + 1, 0)
		w8(rec, 0)
		w8(DIRTY, 1)
	else:                                   # PSG, noise
		w8(rec + 1, 0)
		w8(rec + 2, 0xFF)
		w8(rec, 0)
		w8(DIRTY, 1)
		w8(c + CH_STATE, 0xFF)


## `$174D2`: note on: instrument = the channel's program (channel 9: key +
## $5C), a channel allocated for its class, then the type's note-on.
func _msg_note_on() -> void:
	if r16(NOTES_ON) == 0:
		return
	if r8(MIDI_DATA + 1) == 0:
		_msg_note_off()
		return
	var ch := r8(MIDI_CHANNEL)
	var cv := r8(VOLUMES + ch)
	if cv == 0:
		return
	w16(NOTE_VOLUME, ((cv * r16(TRACK_VOLUME)) & 0xFFFF) >> 7)
	var index := (r8(MIDI_DATA) + 0x5C) if ch == 9 else r8(PROGRAMS + ch)
	var instr := instrument(index)
	var c := allocate(rom8(instr), rom8(instr + 1), rom16(instr + 2))
	if c < 0:
		if rom8(instr) == PCM or rom8(instr) == PCM_PITCHED:
			_refused_note(instr)
		return
	w16(NOTE_SERIAL, r16(NOTE_SERIAL) + 1)
	w8(c + CH_PRIORITY, rom8(instr + 1))
	var kind := rom8(instr)
	if trace.is_valid():
		@warning_ignore("integer_division")
		trace.call("alloc", (c - CHANNELS) / CHANNEL_SIZE, index)
	if kind == PCM or kind == PCM_PITCHED:
		_pcm_note_on(c, instr)
	elif kind == FM:
		_fm_note_on(c, instr)
	elif kind == PSG:
		_psg_note_on(c, instr)
	elif kind == NOISE:
		_noise_note_on(c, instr)


## Note + transpose -> note index (e.g. `$17710`): signed bytes $6C..$7F
## folded down by octaves (table `$169D6`); then -12 (C0 = 0).
func _fold(key: int) -> int:
	key &= 0xFF
	if _s8(key) >= 0x0C and _s8(key) >= 0x6C:
		key = rom8(NOTE_FOLD + key - 0x6C)
	return (key - 0x0C) & 0xFF


## `$17556`: a sample note (one-shot when flag bit 1 is set).
func _pcm_note_on(c: int, instr: int) -> void:
	if (r16(TRACK_VOLUME) & 0xFF) < rom8(instr + 0x15):
		return
	w32(c + CH_INSTR, instr)
	var stolen := _stolen == c
	var bank := _pcm_conflicts(c, r8(c + CH_PRIORITY), rom32(instr + 4))
	if bank < 0:
		_refused_note(instr)
		return
	w32(c + CH_BANKS, rom32(instr + 4))
	w16(c + CH_SERIAL, r16(NOTE_SERIAL))
	w32(c + CH_CACHE, 0)
	w32(c + CH_BEND_DELTA, 0)
	w16(c + CH_BEND_KEY, 0)
	var ch := r8(MIDI_CHANNEL)
	w8(c + CH_MIDI, ch)
	if rom8(instr + 0x12) != 0:
		w16(c + CH_BEND, r16(BENDS + 2 * ch))
		var k := (r8(MIDI_DATA) + rom8(instr + 0x13) - 0x24) & 0xFF
		if (k & 0x80) != 0 or k >= 0x30:
			return
		w8(c + CH_KEY, k)
	var rec := r32(c + CH_RECORD)
	if stolen:
		@warning_ignore("integer_division")
		_drop([DROP_STOLEN, (c - SFX_CHANNELS) / CHANNEL_SIZE, 0, _stolen_note[0], _stolen_note[1]])
	_pcm_pitch(c)
	w8(rec + 4, 0x80)
	w8(rec + 1, 1)
	_pcm_address(rec, instr, bank)
	w8(rec, 0)
	w8(c + CH_STATE, 0)
	w8(c + CH_NOTE, r8(MIDI_DATA))
	w8(c + CH_PHASE, 1)


## A sample note that could not start (no channel, or no bank shared with the
## sounds playing): [member drops] gets it with the rate `$16D32` would have
## given it (without a bend) and volume `$80` (velocity is ignored); a pitched
## note outside the instrument's 48 is dropped by the original anyway.
func _refused_note(instr: int) -> void:
	var rate := rom16(instr + 0xC)
	if rom8(instr + 0x12) != 0:
		var k := (r8(MIDI_DATA) + rom8(instr + 0x13) - 0x24) & 0xFF
		if (k & 0x80) != 0 or k >= 0x30:
			return
		rate = rom16(instr + 0x16 + k * 2)
	_drop([DROP_REFUSED, instr, rate, 0x80, 0, r8(MIDI_CHANNEL), r8(MIDI_DATA)])


## PCM record bytes 5-7 (bank, address | $8000 high, low), 8 (loop flag),
## 9-11 (loop bank and address).
func _pcm_address(rec: int, instr: int, bank: int) -> void:
	var a := (rom32(instr + 8) + r32(SAMPLE_BASE)) & 0xFFFFFFFF
	w8(rec + 7, a | 0x8000)
	w8(rec + 6, (a | 0x8000) >> 8)
	var b := ((a >> 15) + bank) & 0xFF
	w8(rec + 5, b)
	w8(BANK_SHADOW, b)
	w8(DIRTY, 1)
	var loop := rom8(instr + 0x10) & 1
	w8(rec + 8, loop)
	if loop != 0:
		a = (rom16(instr + 0xE) + rom32(instr + 8) + r32(SAMPLE_BASE)) & 0xFFFFFFFF
		w8(rec + 0xB, a | 0x8000)
		w8(rec + 0xA, (a | 0x8000) >> 8)
		w8(rec + 9, (a >> 15) + bank)


## `$17656`: an FM note (the patch is sent when the channel had another).
func _fm_note_on(c: int, instr: int) -> void:
	var rec := r32(c + CH_RECORD)
	w16(c + CH_SERIAL, r16(NOTE_SERIAL))
	w8(c + CH_STATE, 0)
	var ch := r8(MIDI_CHANNEL)
	w8(c + CH_MIDI, ch)
	w16(c + CH_BEND, r16(BENDS + 2 * ch))
	w8(DIRTY, 1)
	w8(c + CH_PENV_STATE, 0)
	w8(c + CH_ARP_STATE, 0)
	w8(c + CH_VIB_STATE, 0)
	w32(c + CH_BEND_DELTA, 0)
	w16(c + CH_BEND_KEY, 0)
	w16(c + CH_ARP, 0)
	w16(c + CH_VIB, 0)
	w16(c + CH_VIB_TIMER, 0)
	w16(c + CH_PENV, rom16(instr + 0xE))
	w16(c + CH_PENV_TIMER, rom16(instr + 0xC))
	w16(c + CH_ARP_TIMER, rom16(instr + 0x1C))
	if r32(c + CH_PATCH) != instr:
		w32(c + CH_PATCH, instr)
		w8(rec + 2, 0)
		w16(rec + 6, r16(DRIVER_LENGTH) + rom16(instr + 6))
	w32(c + CH_INSTR, instr)
	w8(rec + 5, rom8(instr + 0x40))
	var vol := ((r8(MIDI_DATA + 1) * r16(NOTE_VOLUME)) & 0xFFFF) >> 7
	w16(c + CH_VOLUME, vol)
	w8(rec + 3, rom8(FM_VOLUME + vol))
	w8(rec + 4, 0)
	var key := r8(MIDI_DATA)
	w8(c + CH_NOTE, key)
	w8(c + CH_KEY, _fold(key + rom8(instr + 9)))
	w32(c + CH_CACHE, 0)
	_fm_pitch(c)
	w8(rec + 1, 1)
	w8(rec, 0)
	w8(c + CH_PHASE, 1)
	w8(c + CH_STATE, 0)


## `$17754`: a PSG tone note (no PSG instrument exists in this game).
func _psg_note_on(c: int, instr: int) -> void:
	var rec := r32(c + CH_RECORD)
	w16(c + CH_SERIAL, r16(NOTE_SERIAL))
	w32(c + CH_INSTR, instr)
	w32(c + CH_PATCH, instr)
	w8(c + CH_STATE, 0)
	var ch := r8(MIDI_CHANNEL)
	w8(c + CH_MIDI, ch)
	w16(c + CH_BEND, r16(BENDS + 2 * ch))
	w8(DIRTY, 1)
	w8(c + CH_PENV_STATE, 0)
	w8(c + CH_VENV_STATE, 0)
	w8(c + CH_ARP_STATE, 0)
	w8(c + CH_VIB_STATE, 0)
	w32(c + CH_BEND_DELTA, 0)
	w16(c + CH_BEND_KEY, 0)
	w16(c + CH_ARP, 0)
	w16(c + CH_VIB, 0)
	w16(c + CH_VIB_TIMER, 0)
	w16(c + CH_PENV, rom16(instr + 0xC))
	w16(c + CH_PENV_TIMER, rom16(instr + 0xA))
	w16(c + CH_VENV, rom16(instr + 0x40))
	w16(c + CH_VENV_TIMER, rom16(instr + 0x3E))
	w16(c + CH_ARP_TIMER, rom16(instr + 0x1A))
	var vol := ((r8(MIDI_DATA + 1) * r16(NOTE_VOLUME)) & 0xFFFF) >> 7
	w16(c + CH_VOLUME, vol)
	_psg_volume(c)
	w8(rec + 3, 0)
	var key := r8(MIDI_DATA)
	w8(c + CH_NOTE, key)
	w8(c + CH_KEY, _fold(key + rom8(instr + 7)))
	w32(c + CH_CACHE, 0)
	_psg_pitch(c)
	w8(rec + 1, 1)
	w8(rec, 0)
	w8(c + CH_PHASE, 1)
	w8(c + CH_STATE, 0)


## `$17840`: a noise note (unused in this game).
func _noise_note_on(c: int, instr: int) -> void:
	var rec := r32(c + CH_RECORD)
	w16(c + CH_SERIAL, r16(NOTE_SERIAL))
	w32(c + CH_INSTR, instr)
	w32(c + CH_PATCH, instr)
	w8(c + CH_MIDI, r8(MIDI_CHANNEL))
	w8(DIRTY, 1)
	var vol := ((r8(MIDI_DATA + 1) * r16(NOTE_VOLUME)) & 0xFFFF) >> 7
	w16(c + CH_VOLUME, vol)
	_psg_volume(c)
	w8(rec + 3, 0)
	w8(c + CH_NOTE, r8(MIDI_DATA))
	w16(rec + 4, rom8(instr + 5))
	w8(rec + 1, 1)
	w8(rec, 0)
	w8(c + CH_PHASE, 1)
	w8(c + CH_STATE, 0)


# --- channel allocation ($16958, $172A0) -----------------------------------------------------
## `$16958`: a channel of class [param kind] allowed by [param mask]: the first
## free one, else the music note with the lowest priority <= [param priority]
## (the last of equals); -1 if none. Voices (state 1) are never taken. FM has
## 5 channels while any PCM voice is in use, 6 otherwise.
func allocate(kind: int, priority: int, mask: int) -> int:
	var e := ALLOC_CLASSES + 8 * kind
	var first := rom16(e)
	var bit := rom16(e + 2)
	var count := rom16(e + 4)
	if (count & 0x8000) != 0:
		count = 4
		var all_free := true
		for v in 4:
			if (r8(SFX_CHANNELS + v * CHANNEL_SIZE + CH_STATE) & 0x80) == 0:
				all_free = false
				break
		if all_free:
			count = 5
	var best := -1
	var c := CHANNELS + first
	for _i in count + 1:
		if (mask & bit & 0xFFFF) != 0:
			var st := r8(c + CH_STATE)
			if (st & 0x80) != 0:
				_stolen = -1
				return c
			if st == 0:
				var p := r8(c + CH_PRIORITY)
				if priority >= p:
					priority = p
					best = c
		bit = (bit << 1) & 0xFFFF
		c += CHANNEL_SIZE
	_stolen = best
	if best >= 0:
		_stolen_note = [r8(best + CH_MIDI), r8(best + CH_NOTE)]
	return best


## `$172A0`: all PCM voices play from the one 32 KiB ROM bank the Z80 maps, so
## a new sample must share a bank with the others. A voice whose bank mask
## (instrument +4) overlaps narrows the choice to the common banks; one that
## doesn't is killed when its priority <= [param priority], else the new sound
## fails (-1, nothing killed). Returns the bank offset (lowest bit of the
## remaining mask) to add to the sample's own bank.
func _pcm_conflicts(c: int, priority: int, banks: int) -> int:
	var kill := 0                           # bit v: voice v to stop
	for v in 4:
		var o := SFX_CHANNELS + v * CHANNEL_SIZE
		if o == c or (r8(o + CH_STATE) & 0x80) != 0:
			continue
		var common := r32(o + CH_BANKS) & banks
		if common != 0:
			banks = common
		elif priority < r8(o + CH_PRIORITY):
			return -1
		else:
			kill |= 1 << v
	for v in 4:                             # (no dirty flag: the caller sets it)
		if (kill & (1 << v)) != 0:
			var o := SFX_CHANNELS + v * CHANNEL_SIZE
			_drop([DROP_KILLED, v, r8(o + CH_STATE), r8(o + CH_MIDI), r8(o + CH_NOTE)])
			var rec := RECORDS + 0x54 + 12 * v
			w8(rec + 1, 0)
			w8(rec, 0)
			w8(SFX_CHANNELS + v * CHANNEL_SIZE + CH_STATE, 0xFF)
	if banks == 0:
		return 0
	var n := 0
	while (banks & 1) == 0:
		banks >>= 1
		n += 1
	return n


# --- PCM voices ($17CDE ..) ----------------------------------------------------------------------
## `$17CDE`: sample instrument [param index] as a voice (state 1, not a music
## note): [param rate] (8.8, $100 = 1:1) and [param volume] (/2 into the
## record). Any of the 4 PCM voices when rate = $100 and volume = $100, else
## only the fourth. Returns a handle or -1 (`$FFFFFFFF`).
func voice_start(index: int, rate: int, volume: int) -> int:
	volume = (volume & 0xFFFF) >> 1
	var instr := instrument(index)
	var kind := PCM if (rate & 0xFFFF) == 0x100 and volume == 0x80 else PCM_PITCHED
	var c := allocate(kind, rom8(instr + 1), 0xFFFF)
	if c < 0:
		_drop([DROP_REFUSED, instr, rate & 0xFFFF, volume, 1, -1, -1])
		return 0xFFFFFFFF
	var stolen := _stolen == c
	w8(c + CH_PRIORITY, rom8(instr + 1))
	w32(c + CH_INSTR, instr)
	var bank := _pcm_conflicts(c, r8(c + CH_PRIORITY), rom32(instr + 4))
	if bank < 0:
		_drop([DROP_REFUSED, instr, rate & 0xFFFF, volume, 1, -1, -1])
		return 0xFFFFFFFF
	if stolen:
		@warning_ignore("integer_division")
		_drop([DROP_STOLEN, (c - SFX_CHANNELS) / CHANNEL_SIZE, 0, _stolen_note[0], _stolen_note[1]])
	w32(c + CH_BANKS, rom32(instr + 4))
	w32(c + CH_CACHE, 0)
	w32(c + CH_BEND_DELTA, 0)
	w16(c + CH_BEND_KEY, 0)
	w8(c + CH_MIDI, r8(MIDI_CHANNEL))
	var rec := r32(c + CH_RECORD)
	w16(rec + 2, rate)
	w8(rec + 4, volume)
	w8(rec + 1, 1)
	_pcm_address(rec, instr, bank)
	w8(rec, 0)
	w8(c + CH_STATE, 1)
	w8(c + CH_NOTE, r8(MIDI_DATA))
	w8(c + CH_PHASE, 1)
	var handle := (r32(VOICE_HANDLE) + 1) & 0xFFFFFFFF
	w32(VOICE_HANDLE, handle)
	w32(c + CH_CACHE, handle)
	return handle


## The voice channel (state 1) holding [param handle], or -1.
func _voice(handle: int) -> int:
	handle &= 0xFFFFFFFF
	for v in 4:
		var c := SFX_CHANNELS + v * CHANNEL_SIZE
		if r8(c + CH_STATE) == 1 and r32(c + CH_CACHE) == handle:
			return c
	return -1


## `$17DFA`: stop voice [param handle].
func voice_stop(handle: int) -> void:
	var c := _voice(handle)
	if c < 0:
		return
	if _cutting:
		@warning_ignore("integer_division")
		_drop([DROP_CUT, (c - SFX_CHANNELS) / CHANNEL_SIZE, 1])
	var rec := r32(c + CH_RECORD)
	w8(rec + 1, 0)
	w8(rec, 0)
	w8(DIRTY, 1)
	w8(c + CH_STATE, 0xFF)


## `$17E3E`: the voice is still allocated (freed by a stop, a steal or the
## Z80's end-of-sample status, seen at a tick).
func voice_busy(handle: int) -> bool:
	return _voice(handle) >= 0


## `$17E62`: voice playback rate (8.8).
func voice_rate(handle: int, rate: int) -> void:
	var c := _voice(handle)
	if c >= 0:
		var rec := r32(c + CH_RECORD)
		w16(rec + 2, rate)
		w8(rec, 0)
		w8(DIRTY, 1)


## `$17EA2`: voice volume ($100 = unity), / 2 into record byte 4.
func voice_volume(handle: int, volume: int) -> void:
	var c := _voice(handle)
	if c >= 0:
		var rec := r32(c + CH_RECORD)
		w8(rec + 4, (volume & 0xFFFF) >> 1)
		w8(rec, 0)
		w8(DIRTY, 1)


# --- per-tick channel update ($1715E) ------------------------------------------------------------
## `$1715E`: for each music note (state 0): priority decay, FM release,
## modulators, pitch / volume output.
func channels_tick() -> void:
	for n in N_CHANNELS:
		var c := channel(n)
		if r8(c + CH_STATE) != 0:
			continue
		var instr := r32(c + CH_INSTR)
		var kind := rom8(instr)
		if kind == PCM or kind == PCM_PITCHED:
			_decay(c, instr + 0x11)
		elif kind == NOISE:
			_decay(c, instr + 6)
		elif kind == PSG:
			_decay(c, instr + 6)
			var mods := rom8(instr + 9)
			if mods != 0:
				if (mods & 1) != 0:
					_envelope(c, instr + 0xA, CH_PENV_STATE, CH_PENV, CH_PENV_TIMER)
				if (mods & 2) != 0:
					_arpeggio(c, instr + 0x1A)
				if (mods & 4) != 0:
					_vibrato(c, instr + 0x30)
				if (mods & 8) != 0:
					_envelope(c, instr + 0x3E, CH_VENV_STATE, CH_VENV, CH_VENV_TIMER)
					_psg_volume(c)
				_psg_pitch(c)
		elif kind == FM:
			_decay(c, instr + 8)
			if r8(c + CH_PHASE) == 2:
				var left := (r8(c + CH_RELEASE) - 1) & 0xFF
				w8(c + CH_RELEASE, left)
				if left == 0:
					w8(c + CH_PHASE, 0)
					w8(c + CH_STATE, 0xFF)
					continue
			var mods := rom8(instr + 0xB)
			if mods != 0:
				if (mods & 1) != 0:
					_envelope(c, instr + 0xC, CH_PENV_STATE, CH_PENV, CH_PENV_TIMER)
				if (mods & 2) != 0:
					_arpeggio(c, instr + 0x1C)
				if (mods & 4) != 0:
					_vibrato(c, instr + 0x32)
				_fm_pitch(c)


## Priority -= the instrument's decay at ROM [param at] while non-zero (no
## clamp: it wraps).
func _decay(c: int, at: int) -> void:
	var p := r8(c + CH_PRIORITY)
	if p != 0:
		w8(c + CH_PRIORITY, p - rom8(at))


## `$16F28` (pitch) / `$16FB4` (volume): delay, attack to a peak, decay to a
## sustain level, release to 0. Parameters at ROM [param p] (words): +0 delay,
## +2 start value (copied at note-on), +4 attack step, +6 peak, +8 decay step,
## +$A sustain, +$C release step. The channel fields: state, value, timer.
func _envelope(c: int, p: int, f_state: int, f_value: int, f_timer: int) -> void:
	var state := r8(c + f_state)
	if state == 0:
		var t := _s16(r16(c + f_timer) - 1)
		w16(c + f_timer, t)
		if t < 0:
			w8(c + f_state, 2)
	elif state == 2:
		var v := _s16(r16(c + f_value) + rom16(p + 4))
		w16(c + f_value, v)
		if v > _s16(rom16(p + 6)):
			w16(c + f_value, rom16(p + 6))
			w8(c + f_state, 4)
	elif state == 4:
		var v := _s16(r16(c + f_value) - rom16(p + 8))
		w16(c + f_value, v)
		if not v > _s16(rom16(p + 0xA)):
			w16(c + f_value, rom16(p + 0xA))
			w8(c + f_state, 6)
	elif state == 6:
		var v := _s16(r16(c + f_value) - rom16(p + 0xC))
		w16(c + f_value, v)
		if not v > 0:
			w16(c + f_value, 0)
			w8(c + f_state, 8)


## `$17040`: after +0 ticks, for +4 ticks cycle through the +2.b note offsets
## at +6.. (words), each held +3.b + 1 ticks; then offset 0.
func _arpeggio(c: int, p: int) -> void:
	var state := r8(c + CH_ARP_STATE)
	if state == 0:
		var t := _s16(r16(c + CH_ARP_TIMER) - 1)
		w16(c + CH_ARP_TIMER, t)
		if t >= 0:
			return
		w8(c + CH_ARP_STATE, 2)
		w16(c + CH_ARP_TIMER, rom16(p + 4))
		w16(c + CH_ARP_STEP_TIMER, rom8(p + 3))
		w16(c + CH_ARP_POS, 0xFFFF)
		state = 2
	if state == 2:
		var t := _s16(r16(c + CH_ARP_TIMER) - 1)
		w16(c + CH_ARP_TIMER, t)
		if t < 0:
			w8(c + CH_ARP_STATE, 4)
			w16(c + CH_ARP, 0)
			return
		t = _s16(r16(c + CH_ARP_STEP_TIMER) - 1)
		w16(c + CH_ARP_STEP_TIMER, t)
		if t >= 0:
			return
		w16(c + CH_ARP_STEP_TIMER, rom8(p + 3))
		var pos := (r16(c + CH_ARP_POS) + 1) & 0xFFFF
		if not _s8(pos) < _s8(rom8(p + 2)):
			pos = 0
		w16(c + CH_ARP_POS, pos)
		w16(c + CH_ARP, rom16(p + 6 + 2 * _s16(pos)))


## `$170C6`: from tick +0 to tick +2 (counted from the note-on): phase += +4;
## value = sine(((phase & +$A) + +$C) >> 2) / 2 * +6 >> 14, clamped to
## +-(+8).
func _vibrato(c: int, p: int) -> void:
	var state := r8(c + CH_VIB_STATE)
	if state == 0:
		var timer := _s16(r16(c + CH_VIB_TIMER))
		if timer < _s16(rom16(p)):
			w16(c + CH_VIB_TIMER, timer + 1)
			return
		w8(c + CH_VIB_STATE, 2)
		w16(c + CH_VIB_PHASE, 0)
		state = 2
	if state == 2:
		var timer := _s16(r16(c + CH_VIB_TIMER))
		if not timer < _s16(rom16(p + 2)):
			w8(c + CH_VIB_STATE, 4)
			w16(c + CH_VIB, 0)
			return
		var phase := (r16(c + CH_VIB_PHASE) + rom16(p + 4)) & 0xFFFF
		w16(c + CH_VIB_PHASE, phase)
		var a := _s16((phase & rom16(p + 0xA)) + rom16(p + 0xC)) >> 2
		var s := sine(a) >> 1
		var v := _s16((s * _s16(rom16(p + 6))) >> 14)
		var limit := _s16(rom16(p + 8))
		if v > limit:
			v = limit
		if v < _s16(-limit):
			v = _s16(-limit)
		w16(c + CH_VIB, v)
		w16(c + CH_VIB_TIMER, timer + 1)


## `$14214`: sine of [param angle] (256 steps per turn), -$7FFF..$7FFF.
func sine(angle: int) -> int:
	var i := angle & 0x3F
	if (angle & 0x40) != 0:
		i = 0x40 - i
	var v := rom16(SINE + 2 * i)
	return -v if (angle & 0x80) != 0 else v


# --- pitch / volume output -----------------------------------------------------------------------
## `$16DAC`: note index + arpeggio -> linear F-number (table `$169EA`), + bend
## (towards +-(+$A) notes), detune (+4), pitch envelope, vibrato; when
## changed, normalised to block << 11 | F-number in record bytes 8-9.
func _fm_pitch(c: int) -> void:
	var instr := r32(c + CH_INSTR)
	var k := ((r8(c + CH_KEY) + r16(c + CH_ARP)) * 4) & 0xFFFF
	var f := rom32(FM_FREQ + _s16(k))
	var bend := _s16(r16(c + CH_BEND))
	if bend != 0 and rom8(instr + 0xA) != 0:
		if k != r16(c + CH_BEND_KEY):
			w16(c + CH_BEND_KEY, k)
			var r := rom8(instr + 0xA) * 4
			var k2 := _s16(k - r if bend < 0 else k + r)
			var d := _s16(rom32(FM_FREQ + k2) - f)              # muls.w: low words
			w32(c + CH_BEND_DELTA, (d * absi(bend)) >> 6)
		f += r32(c + CH_BEND_DELTA)
	f += _s8(rom8(instr + 4))
	f += r16(c + CH_PENV)                                       # unsigned word
	f += _s16(r16(c + CH_VIB))
	f &= 0xFFFFFFFF
	if f == r32(c + CH_CACHE):
		return
	w32(c + CH_CACHE, f)
	var block := 0
	while _s32(f) >= 0x800:
		block += 0x800
		f >>= 1
	var rec := r32(c + CH_RECORD)
	w16(rec + 8, block + f)
	w8(rec + 4, 0)
	w8(rec, 0)
	w8(DIRTY, 1)


## `$16D32`: rate = +$C, or (pitched, +$12 != 0) the note's word at +$16, bent
## towards +-(+$14) notes; record bytes 2-3 when changed.
func _pcm_pitch(c: int) -> void:
	var instr := r32(c + CH_INSTR)
	var rate := rom16(instr + 0xC)
	if rom8(instr + 0x12) != 0:
		var k := (r8(c + CH_KEY) * 2) & 0xFF
		rate = rom16(instr + 0x16 + k)
		var bend := _s16(r16(c + CH_BEND))
		if bend != 0 and rom8(instr + 0x14) != 0:
			if k != r16(c + CH_BEND_KEY):
				w16(c + CH_BEND_KEY, k)
				var r := rom8(instr + 0x14) * 2
				var k2 := _s16(k - r if bend < 0 else k + r)
				var d := _s16(rom16(instr + 0x16 + k2) - rate)
				w16(c + CH_BEND_DELTA, (d * absi(bend)) >> 6)
			rate = (rate + r16(c + CH_BEND_DELTA)) & 0xFFFF
	if rate == r16(c + CH_CACHE):
		return
	w16(c + CH_CACHE, rate)
	var rec := r32(c + CH_RECORD)
	w16(rec + 2, rate)
	w8(rec, 0)
	w8(DIRTY, 1)


## `$16E60`: PSG period (unused in this game).
func _psg_pitch(c: int) -> void:
	var instr := r32(c + CH_INSTR)
	var k := ((r8(c + CH_KEY) + r16(c + CH_ARP)) * 2) & 0xFFFF
	var f := rom16(PSG_PERIOD + _s16(k))
	var bend := _s16(r16(c + CH_BEND))
	if bend != 0 and rom8(instr + 8) != 0:
		if k != r16(c + CH_BEND_KEY):
			w16(c + CH_BEND_KEY, k)
			var r := rom8(instr + 8) * 2
			var k2 := _s16(k - r if bend < 0 else k + r)
			var d := _s16(rom16(PSG_PERIOD + k2) - f)
			w16(c + CH_BEND_DELTA, (d * absi(bend)) >> 6)
		f += r16(c + CH_BEND_DELTA)
	f = _s16(f + _s8(rom8(instr + 4)) + r16(c + CH_PENV) + r16(c + CH_VIB))
	if f < 0:
		f = 0
	if f == r16(c + CH_CACHE):
		return
	w16(c + CH_CACHE, f)
	var rec := r32(c + CH_RECORD)
	w16(rec + 4, f)
	w8(rec + 3, 0)
	w8(rec, 0)
	w8(DIRTY, 1)


## `$16EF6`: PSG attenuation (unused in this game).
func _psg_volume(c: int) -> void:
	var v := _s16((_s16(r16(c + CH_VENV)) >> 7) + _s16(r16(c + CH_VOLUME)))
	v = clampi(v, 0, 0x7F)
	var rec := r32(c + CH_RECORD)
	w8(rec + 2, rom8(PSG_VOLUME + v))
	w8(rec, 0)
	w8(DIRTY, 1)


# --- inspection ------------------------------------------------------------------------------------
## Track [param slot] (0-31) decoded (tests, tools).
func track_state(slot: int) -> Dictionary:
	var t := TRACKS + slot * TRACK_SIZE
	return {
		state = r8(t + TR_STATE), channel = r8(t + TR_CHANNEL), index = r8(t + TR_INDEX),
		tempo = r32(t + TR_TEMPO), fraction = r16(t + TR_FRACTION),
		volume = _s16(r16(t + TR_VOLUME)), volume_target = _s16(r16(t + TR_VOLUME_TARGET)),
		fade_step = _s16(r16(t + TR_FADE_STEP)), pos = r32(t + TR_POS), wait = r32(t + TR_WAIT),
		handle = r32(t + TR_HANDLE), program = r8(t + TR_PROGRAM),
	}


## Channel struct [param n] (0-13) decoded: the fields every kind uses.
func channel_state(n: int) -> Dictionary:
	var c := channel(n)
	return {
		state = r8(c + CH_STATE), instrument = r32(c + CH_INSTR), midi = r8(c + CH_MIDI),
		note = r8(c + CH_NOTE), key = r8(c + CH_KEY), phase = r8(c + CH_PHASE),
		priority = r8(c + CH_PRIORITY), serial = r16(c + CH_SERIAL), cache = r32(c + CH_CACHE),
		volume = r16(c + CH_VOLUME),
	}


## Pending note-offs, head to tail: [time left 16.16, step, key, channel, slot].
func queue() -> Array:
	var out := []
	var e := r32(QUEUE_HEAD)
	for _i in r8(QUEUE_COUNT):
		out.append([r32(e), r32(e + 4), r8(e + 8), r8(e + 9), r8(e + 10)])
		e += QUEUE_ENTRY
		if (e & 0xFFFF) == ((QUEUE + QUEUE_SIZE) & 0xFFFF):
			e = _ptr(QUEUE)
	return out
