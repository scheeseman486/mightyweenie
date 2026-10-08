class_name MwAudio
extends Node
## The game's audio (plan 12): our port of the original's sound driver on the
## 60 Hz tick, heard through the `mw_audio` GDExtension.
##
## Per tick, first thing (the original's VBlank task `$13DE8` runs before the
## main loop's pass, docs/re/sound.md):
## [codeblock]
## batch = s68k.vblank(z80)        # the 68000's driver tick: sequencer, channels,
##                                 # the 133-byte batch for the Z80
## z80.apply_batch(batch)          # the Z80: YM2612 / PSG writes, PCM triggers
## z80.advance(...)                # the Z80's mixing time until the next tick
## render one tick of audio        # MwChips: FM + PSG + the PCM samples
## [/codeblock]
## The game calls the driver's API through [MwSound] between ticks, inside
## the screens' passes, where the original's code does.
##
## Rendering: `MwChips` makes the YM2612's native rate (7 670 453 / 144 Hz);
## an [AudioStreamGenerator] at that rate takes one tick of it per tick and
## Godot resamples to the output. The buffer is kept around [constant
## BUFFER_TARGET] seconds full by rendering a frame more or less per tick
## (0.1 %) when the game's tick clock and the sound card's drift apart.
##
## Created by the Router autoload when the game runs with a display (headless
## runs - tests, checks - keep the silent [MwSound] stand-in).

const BUFFER_LENGTH := 0.25       ## seconds the generator holds
## The chips' level in the mix: a full-volume FM channel is about 0.13 of
## full scale in MwChips; the title music peaks near 0.26. +4 dB brings the
## game's loudness near that of other software (peaks ~0.4).
const VOLUME_DB := 4.0
const BUFFER_TARGET := 0.07       ## seconds kept queued (latency)
const TICKS_PER_SECOND := 60.0
## [member free_effects]: the longest the crowd's loop goes on after an effect
## killed it, waiting for the driver to restart it (ticks).
const CROWD_HOLD_TICKS := 120
## The crowd's instrument (`$13E52`: a looped, pitched sample).
const CROWD_INSTRUMENT := 0x50
## A held crowd that times out fades over this many ticks.
const CROWD_FADE_TICKS := 6

## Enhancement switches (owner, 2026-10-08; on by default - owner, 2026-10-08;
## off = the original; the options menu sets them, plan 21). They change
## only what is heard: the driver - its handles, its "still playing?" answers,
## its timing - stays the original's (it notes what it drops,
## [member MwSound68k.drops], and these play it on the chips' extra voices).
##
## The music's sample notes - the menus' music's drums, the sequences' samples
## - play where the original drops them: a note refused because an effect
## from another ROM bank plays (the Z80 reads every sample through one bank,
## `$172A0`) or no channel is free (`$16958`), and a note an effect kills or
## takes the channel of. Each plays on an extra voice until its note-off, as
## it would have.
static var free_music_samples := true
## Effects play out where the original cuts them short or refuses them: for
## want of a bank (`$172A0`) or a channel (`$16958`), or by the positional rule
## (`$13CEE` / `$13D58`: any new sound stops the last positional one; the
## 60-tick limit stays). A sample started again cuts its earlier copy, as in
## the original: the rink's sounds repeated every pass or two stay single.
## Looping samples stay as the original, but for the crowd: killed by an
## effect, it goes on until the driver restarts it (or [constant
## CROWD_HOLD_TICKS] at most).
static var free_effects := true

## A sound on one of the chips' extra voices.
class Extra:
	var voice := -1          ## the chips' voice id (4-15)
	var sample := -1         ## [MwSoundSamples] index
	var midi := -1           ## a music note's MIDI channel and key (-1: a voice)
	var note := -1
	var stops_at_note_off := false
	var until := -1          ## tick it fades at (-1: plays to its end)

var rom := PackedByteArray()
var s68k: MwSound68k
var z80: MwSoundZ80
var out: MwAudioOut
## The `MwChips` extension object; null if the extension is not available.
var chips: Object = null
var player: AudioStreamPlayer
var _gen: AudioStreamGenerator
var _playback: AudioStreamGeneratorPlayback
var _frac := 0.0
var _rate := 53267.0
var _extras: Array[Extra] = []
## Most extra voices sounding at once so far (checks).
var extras_peak := 0
var _tick := 0


## Builds the driver for [param rom_]; [param with_player] false: no Godot
## player (offline rendering, tests).
func setup(rom_: PackedByteArray, with_player := true) -> void:
	rom = rom_
	if ClassDB.class_exists("MwChips"):
		chips = ClassDB.instantiate("MwChips")
		_rate = float(chips.call("sample_rate"))
	out = MwAudioOut.new(chips)
	z80 = MwSoundZ80.new(rom, out)
	out.load_samples(z80.samples)
	s68k = MwSound68k.new(rom)
	s68k.note_drops = chips != null and (free_music_samples or free_effects)
	reset()
	if with_player and chips != null:
		_gen = AudioStreamGenerator.new()
		_gen.mix_rate = _rate
		_gen.buffer_length = BUFFER_LENGTH
		player = AudioStreamPlayer.new()
		player.name = "Chips"
		player.stream = _gen
		player.volume_db = VOLUME_DB
		add_child(player)
		player.play()
		_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback


## Power-on: the chips, the Z80 driver upload and the 68000's set-up
## (`$13BE0` -> `$13C18`).
func reset() -> void:
	_extras.clear()
	if chips:
		chips.call("reset")
	z80.reset()
	s68k.reset()


## `$13C04` (entering or leaving a match, the pause menu): the 68000's
## part ([method MwSound68k.enter_match]: music fade, crowd off, its reset)
## and `$13C18`'s re-upload of the Z80 driver ([method MwSoundZ80.reset]:
## its samples stop at once). The YM2612 is not reset: its notes stop with
## the next tick's batch (every channel "changed, key off").
func enter_match(fade_ticks: int) -> void:
	s68k.enter_match(fade_ticks)
	z80.reset()
	_stop_extras()


## One 60 Hz tick: the VBlank's driver work, then a tick of audio.
func tick() -> void:
	step_driver()
	_render()


## The driver's part of a tick (the 68000's VBlank work, the Z80's batch and
## mixing time, the extra voices) without rendering: offline renders and
## checks call it, then render [method frames_this_tick] frames themselves.
func step_driver() -> void:
	var batch := s68k.vblank(z80)
	_extras_before(s68k.take_drops())
	if not batch.is_empty():
		z80.apply_batch(batch)
	out.end_batch()
	z80.advance(not batch.is_empty())
	_extras_after()
	s68k.note_drops = chips != null and (free_music_samples or free_effects)
	_tick += 1


# --- the enhancement switches' extra voices -----------------------------------------------------

## What the driver dropped since the last tick ([member MwSound68k.drops]):
## the channels to keep sounding when this tick's batch stops or replaces them,
## the refused sounds started, the note-offs of notes it did not have.
func _extras_before(drops: Array) -> void:
	for d: Array in drops:
		match int(d[0]):
			MwSound68k.DROP_KILLED, MwSound68k.DROP_STOLEN, MwSound68k.DROP_CUT:
				_keep(d)
			MwSound68k.DROP_REFUSED:
				_refused(d)
			MwSound68k.DROP_NOTE_OFF:
				_note_off(int(d[1]), int(d[2]))


## A channel's sample cut short: kept on an extra voice if its switch is on
## and it does not loop (the crowd: held until the driver restarts it).
func _keep(d: Array) -> void:
	var v: int = d[1]
	var is_note := int(d[2]) == 0
	if not (free_music_samples if is_note else free_effects):
		return
	var ch := z80.channels[v]
	if not (ch.status & MwSoundZ80.STATUS_PLAYING) or ch.sample < 0:
		return
	var desc := z80.samples.desc(ch.sample)
	var e := Extra.new()
	e.sample = ch.sample
	if desc.loops():
		if is_note or desc.instrument != CROWD_INSTRUMENT:
			return
		e.until = _tick + CROWD_HOLD_TICKS
	if is_note:
		e.midi = d[3]
		e.note = d[4]
		e.stops_at_note_off = desc.flags & 2 == 0
	out.detach[v] = e


## A sound the driver refused: started on an extra voice (not a loop).
func _refused(d: Array) -> void:
	var is_note := int(d[4]) == 0
	if not (free_music_samples if is_note else free_effects):
		return
	var i := z80.samples.by_record(int(d[1]))
	if i < 0:
		return
	var desc := z80.samples.desc(i)
	if desc.loops():
		return
	_restarted(i)
	var voice: int = chips.call("pcm_start_extra", i, int(d[2]), int(d[3]))
	if voice < 0:
		return
	var e := Extra.new()
	e.voice = voice
	e.sample = i
	if is_note:
		e.midi = d[5]
		e.note = d[6]
		e.stops_at_note_off = desc.flags & 2 == 0
	_add_extra(e)


## A note-off the driver had no note for: the oldest extra of that note stops.
func _note_off(midi: int, note: int) -> void:
	for e in _extras:
		if e.midi == midi and e.note == note and e.stops_at_note_off:
			chips.call("pcm_stop", e.voice)
			_extras.erase(e)
			return


## Sample [param sample] starts (on a channel or an extra voice): its copies
## on extra voices stop, as the original's restart of a sound does (a held
## crowd fades out quickly instead: the driver's restarted one takes over).
func _restarted(sample: int) -> void:
	for e in _extras.duplicate():
		if e.sample == sample:
			if e.until >= 0:
				chips.call("pcm_fade", e.voice, int(CROWD_FADE_TICKS * _rate / TICKS_PER_SECOND))
			else:
				chips.call("pcm_stop", e.voice)
			_extras.erase(e)


func _add_extra(e: Extra) -> void:
	for o in _extras.duplicate():       # the chips took that voice over (all were busy)
		if o.voice == e.voice:
			_extras.erase(o)
	_extras.append(e)
	extras_peak = maxi(extras_peak, _extras.size())


## After the batch: the kept channels' new extras, then the earlier copies
## of the samples the batch started stopped (also those just kept: a sound cut
## by itself stays cut); extras that ended dropped; a held crowd fades when
## its time is up or the crowd was turned off.
func _extras_after() -> void:
	for e: Extra in out.detached:
		_add_extra(e)
	out.detached.clear()
	for sample in out.started:
		_restarted(sample)
	out.started.clear()
	var crowd_on := s68k.r16(MwSound68k.CROWD_ON) != 0
	for e in _extras.duplicate():
		if int(chips.call("pcm_sample", e.voice)) != e.sample:
			_extras.erase(e)
		elif e.until >= 0 and (_tick >= e.until or not crowd_on):
			chips.call("pcm_fade", e.voice, int(CROWD_FADE_TICKS * _rate / TICKS_PER_SECOND))
			e.until = -1


func _stop_extras() -> void:
	for e in _extras:
		chips.call("pcm_stop", e.voice)
	_extras.clear()


## The audio frames one tick produces (fractions carried over).
func frames_this_tick() -> int:
	_frac += _rate / TICKS_PER_SECOND
	var n := int(_frac)
	_frac -= n
	return n


func _render() -> void:
	if chips == null:
		return
	var n := frames_this_tick()
	if _playback == null:
		chips.call("render", n)        # keep the chips' time with the ticks
		return
	var free := _playback.get_frames_available()
	var queued := int(_gen.buffer_length * _rate) - free
	var target := int(BUFFER_TARGET * _rate)
	if queued > target * 2:
		n = maxi(n - 8, 0)             # far ahead (a hitch made ticks run late): catch up
	elif queued > target:
		n -= 1
	elif queued < target / 2:
		n += 8                         # starving: refill
	elif queued < target:
		n += 1
	var frames: PackedVector2Array = chips.call("render", n)
	if frames.size() > free:
		frames = frames.slice(0, free)
	_playback.push_buffer(frames)
