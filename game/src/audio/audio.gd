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
## Created by the Router autoload when the game runs with a display. Plan
## 35 (plan 40, D6: every router without one, the tests' too): a headless
## game, a recording or a replay steps the same driver as a model
## (no chips, no sound: [method setup]'s [code]with_chips[/code] false;
## MwRouter.use_driver_model), and every answer the game reads - busy,
## handles, [method sounding] - comes from the model, stepped by the ticks,
## never from the chips or the sound card: the enhancement voices are
## modelled too ([Extra]: their slot and the tick they end, from the
## sample's length and rate).

const BUFFER_LENGTH := 0.25       ## seconds the generator holds
## The chips' level in the mix: a full-volume FM channel is about 0.13 of
## full scale in MwChips; the title music peaks near 0.26. +4 dB brings the
## game's loudness near that of other software (peaks ~0.4).
const VOLUME_DB := 4.0
const BUFFER_TARGET := 0.07       ## seconds kept queued (latency)
const TICKS_PER_SECOND := float(MwRouter.TICK_HZ)
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
## The organ pool (plan 39, owner 2026-10-10; follows ENHANCE AUDIO): each
## time the goal song (`$09`) or a period-start jingle (`$05-$08`) would
## play, one of the pool's tunes plays instead, picked at random - those
## five and the port's ([MwOrganTunes]) ([method play_sound], [method
## random_sound]). The original's random streams are untouched. Plan 35: a
## tune's length is how long a carried goal song (MwSettings.goal_song_carries)
## holds the scoreboard, so the pool is a match rule (ENHANCE AUDIO's) and
## the pick comes from the session's organ stream ([method play_organ]).
## Off = the original's calls.
static var organ_pool := true

## A sound on one of the chips' extra voices. Plan 35: the model's own
## bookkeeping ([member slot], [member serial], [member end]) decides what
## the game hears asked ([method sounding]); the chips' voice only plays it.
class Extra:
	var voice := -1          ## the chips' voice id (4-15; -1: none - no chips, or taken over)
	var sample := -1         ## [MwSoundSamples] index
	var midi := -1           ## a music note's MIDI channel and key (-1: a voice)
	var note := -1
	var stops_at_note_off := false
	var until := -1          ## tick it fades at (-1: plays to its end)
	var slot := -1           ## the model's extra voice (4-15, as the chips' mixer picks one)
	var serial := 0          ## the model's start order (the oldest is taken over first)
	var end := -1            ## the tick it ends at in the model (-1: not before it is stopped)

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
## Port only ([method fade_in_voice]): voices rising from silence, each
## [handle, ticks, ticks done].
var _fade_ins: Array = []
## Most extra voices sounding at once so far (checks).
var extras_peak := 0
## Port only (plan 34, owner): the port's own FM effects, on the FM channel
## the music leaves free ([MwFmSfx]: FM6), written after each tick's driver
## work.
var fm_sfx := MwFmSfx.new()
var _tick := 0
## The model's extra voices: the mixer's (MwChips: voices 4-15).
const EXTRA_FIRST := 4
const EXTRA_END := 16
var _serial := 0
var _lengths := {}               # sample -> decoded frames (the model's sample lengths)
## The organ pool's own tunes ([method MwOrganPool.tunes]) and where each
## sits in [member rom], this driver's copy of the ROM.
var organ_tunes: Array[MwOrganPool.Tune] = []
var organ_addresses := PackedInt32Array()
## The last pick ([method MwOrganPool.pick]; -1: none yet).
var organ_last := -1
## The game whose organ stream picks the pool's tunes (plan 35's rules: a
## pool tune's length is how long a carried goal song holds the scoreboard,
## so every machine picks the same - [constant MwSession.STREAM_ORGAN]): the
## router's, set before its passes (MwRouter._passes). Null: the pool's own
## generator (offline renders, tests). A machine's own, not in a snapshot
## (the stream is, in the session).
var session: MwSession = null
## The playing pool tune whose floor hits are due: its handle (-1: none),
## its hit ticks, the ticks since it started and the voices its hits took.
## Chips only - heard, never asked: the model has no floor hits, and a
## resync stops them (presentation, [method before_restore]).
var _organ_handle := -1
var _organ_hits := PackedInt32Array()
var _organ_clock := 0
var _organ_voices := PackedInt32Array()
## What is heard on its own clock ([method start_pump], [MwAudioPump];
## owner, 2026-10-13: music dropouts after scoring): the pump while it runs,
## and the lock the game's calls take meanwhile ([method lock]).
var _pump: MwAudioPump = null
var _lock := Mutex.new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _pump != null:
		_pump.stop()                    # (its thread finished; a child pump goes with this node)
		if _pump.get_parent() != self:
			_pump.free()
		_pump = null


## Builds the driver for [param rom_]; [param with_player] false: no Godot
## player (offline rendering, tests); [param with_chips] false: no chips
## at all - the driver as a model only (plan 35: nothing rendered, every
## answer the same).
func setup(rom_: PackedByteArray, with_player := true, with_chips := true) -> void:
	# the organ pool's tunes after the ROM's end, in this copy only (plan 39;
	# the model's too: a pool tune plays from here, busy for its length)
	organ_tunes = MwOrganPool.tunes()
	organ_addresses = PackedInt32Array()
	rom = MwOrganPool.extend_rom(rom_, organ_tunes, organ_addresses)
	if with_chips and ClassDB.class_exists("MwChips"):
		chips = ClassDB.instantiate("MwChips")
		_rate = float(chips.call("sample_rate"))
	out = MwAudioOut.new(chips)
	z80 = MwSoundZ80.new(rom, out)
	out.load_samples(z80.samples)
	if chips:
		var hit := MwOrganPool.hit_sample(z80.samples)
		if not hit.is_empty():
			chips.call("pcm_load", MwOrganPool.HIT_SAMPLE_ID, hit, MwOrganPool.hit_rate(z80.samples), -1)
	s68k = MwSound68k.new(rom)
	s68k.note_drops = free_music_samples or free_effects
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
	_fade_ins.clear()
	fm_sfx = MwFmSfx.new()
	out.reset_regs()
	_organ_handle = -1
	_organ_voices.clear()
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
	_fade_ins.clear()
	_organ_stop()


## Plan 35 work item 6: before the driver's model is taken from a resync
## snapshot (MwNetSnapshot): the chips' extra voices stopped - the model's
## extras and fades are about to be the snapshot's.
func before_restore() -> void:
	_stop_extras()
	_fade_ins.clear()
	_organ_stop()                  # plan 39's floor hits: the chips' only (a pool tune plays on without them)


## After the model was taken from a resync snapshot: the extra voices go on
## in the model, silent on the chips (theirs were this machine's); the chips
## - sound only - are reset and given the FM registers the model last wrote,
## so the music comes back with its next notes.
func after_restore() -> void:
	for extra in _extras:
		extra.voice = -1
	if chips == null:
		return
	chips.call("reset")
	for i in out.regs.size():
		if out.regs[i] >= 0:
			chips.call("ym_write", i >> 8, i & 0xFF, out.regs[i])


## Port only ([member MwSettings.goal_song_carries]): a rink exit that lets
## sequence [param keep] play on - [method MwSound68k.leave_keeping], the
## Z80 not reset (its samples of other sounds stop with the next batch), the
## extra voices stopped.
func carry_over(keep: int) -> void:
	s68k.leave_keeping(keep)
	_stop_extras()
	_fade_ins.clear()
	if _organ_handle != (keep & 0xFFFFFFFF):
		_organ_stop()


## Port only: voice [param handle] (the music after a carried goal song,
## [member MwSettings.goal_song_carries]; the crowd started from silence,
## MwSound.crowd_level - plan 40, D7) rises from silence to its volume over
## [param ticks] ticks, in the mix only (the driver's volume stays: its
## Z80 channel's level is scaled each tick, after the Z80 told the mixer
## its own).
func fade_in_voice(handle: int, ticks: int) -> void:
	if ticks > 0:
		_fade_ins.append([handle & 0xFFFFFFFF, ticks, 0])
		_fade_ins_tick(false)


## Port only (owner, 2026-10-12: a star's voice on the game setup kept
## talking after Menu Back - fade it out quickly): sound [param handle]
## stops now in the driver (`sound_stop`: the game's "still playing?" as for
## any stop), and in the mix a voice's sample still sounding fades out over
## [param ticks] ticks - moved off its channel onto an extra voice
## (MwChips.pcm_detach) and faded there. Sound [param id]'s copies on the
## extra voices (a sound the driver refused, played there: its handle says
## nothing - ENHANCE AUDIO) fade too and end now in the model. A sequence
## just stops.
func fade_out_sound(handle: int, ticks: int, id := -1) -> void:
	handle &= 0xFFFFFFFF
	var frames := maxi(int(ticks * _rate / TICKS_PER_SECOND), 1)
	if handle != MwSound.NONE and (handle & 0x80000000) == 0:
		var k := s68k.voice_channel(handle)
		if k >= 0 and chips != null and z80.playing(k):
			var v := int(chips.call("pcm_detach", k))
			if v >= 0:
				chips.call("pcm_fade", v, frames)
	if handle != MwSound.NONE:
		s68k.sound_stop(handle)
	var sample := z80.samples.by_sound_id(id) if id >= 0 else -1
	if sample < 0:
		return
	for e in _extras.duplicate():
		if e.sample == sample and e.midi < 0:
			if chips != null and e.voice >= 0:
				chips.call("pcm_fade", e.voice, frames)
			_extras.erase(e)


## The fading voices' levels for this tick ([param advance]: a tick went
## by); a voice gone (stopped, ended) drops out, one the Z80 has not started
## yet waits.
func _fade_ins_tick(advance := true) -> void:
	for f: Array in _fade_ins.duplicate():
		var k := s68k.voice_channel(int(f[0]))
		if k < 0:
			_fade_ins.erase(f)
			continue
		if not z80.playing(k):
			continue
		if advance:
			f[2] = int(f[2]) + 1
		var full := z80.effective_volume(k)
		if int(f[2]) >= int(f[1]):
			out.pcm_volume(k, full)
			_fade_ins.erase(f)
		else:
			@warning_ignore("integer_division")
			out.pcm_volume(k, full * int(f[2]) / int(f[1]))


## One 60 Hz tick: the VBlank's driver work, then a tick of audio.
func tick() -> void:
	step_driver()
	_render()


# --- the pump (what is heard on its own clock) ---------------------------------------------------

## Whether the driver is played by sound only - chips and a Godot player
## (a game with a display; never a model, a headless game or a test's).
func audible() -> bool:
	return _playback != null


## Whether this driver runs on the wall clock ([method start_pump]) rather
## than its router's ticks.
func pumping() -> bool:
	return _pump != null


## The pump while the driver runs on the wall clock (else null).
func pump_clock() -> MwAudioPump:
	return _pump


## From now on this driver ticks as the wall clock says ([MwAudioPump]): on
## a thread of its own ([param threaded]) or each frame on the main thread.
## Its router no longer steps it (MwRouter.step). Only for what is heard -
## a driver the game asks is stepped by the game's ticks.
func start_pump(threaded := MwAudioPump.threaded) -> void:
	if _pump != null:
		return
	_pump = MwAudioPump.new(self)
	if not threaded:
		add_child(_pump)
	_pump.start(threaded)


## Back to its router's ticks (the thread finished first).
func stop_pump() -> void:
	if _pump == null:
		return
	var pump := _pump
	pump.stop()
	_pump = null
	if pump.get_parent() == self:
		remove_child(pump)
	pump.free()


## The game's calls and a resync take this lock before they touch a
## pumped driver (the pump's thread holds it for each look). Recursive.
func lock() -> void:
	_lock.lock()


## Lets go of the lock [method lock] took (once for each [method lock]: it is recursive).
func unlock() -> void:
	_lock.unlock()


## Plan 41: the ticks this driver has run (MwHeard's clock).
func tick_count() -> int:
	return _tick


## Plan 42 (speed): ticks this driver owes - a model nobody hears (the
## run-ahead's own, MwNetRunAhead) runs its ticks when the game next asks
## it something ([method settle]: MwSound does first), so a pass that asks
## nothing costs none and a rollback that copies it again drops them.
var owed := 0
## Plan 42 (second round): calls with no answer (a positional sound, the
## crowd off, a stop...) made while ticks are owed, kept in order with the
## owed ticks before each ([owed then, call, its arguments]) - [method
## settle] makes them between the ticks, as they came. Only calls that
## answer (a handle) and questions settle at once ([method call_later]).
var _later: Array = []
## Owed ticks past which a call made later settles anyway (a long carried
## run-ahead never asked: no long settle all at once).
const OWED_MAX := 120


## The ticks owed run, the calls made later made among them in their place.
func settle() -> void:
	var done := 0
	for c: Array in _later:
		while done < int(c[0]):
			done += 1
			tick()
		MwSound.call_on(self, c[1], c[2])
	_later.clear()
	while done < owed:
		done += 1
		tick()
	owed = 0


## Call [param fn] ([param args]; one with no answer) made after the ticks
## owed so far: kept for [method settle].
func call_later(fn: String, args: Array) -> void:
	_later.append([owed, fn, args])
	if owed > OWED_MAX:
		settle()


## Nothing owed any more (the driver taken from another: its ticks and
## calls as they were).
func forget_owed() -> void:
	owed = 0
	_later.clear()


## The driver's part of a tick (the 68000's VBlank work, the Z80's batch and
## mixing time, the extra voices) without rendering: offline renders and
## checks call it, then render [method frames_this_tick] frames themselves.
func step_driver() -> void:
	_organ_tick()
	var batch := s68k.vblank(z80)
	_extras_before(s68k.take_drops())
	if not batch.is_empty():
		z80.apply_batch(batch)
	out.end_batch()
	z80.advance(not batch.is_empty())
	_extras_after()
	if not _fade_ins.is_empty():
		_fade_ins_tick()
	s68k.note_drops = free_music_samples or free_effects
	_fm_effect_tick()
	_tick += 1


# --- the port's FM effects (plan 34) ------------------------------------------------------------

## Port only (plan 34, owner): starts FM effect [param effect_name] ([constant
## MwFmSfx.EFFECTS]) on FM6 with the next tick.
func fm_effect(effect_name: String) -> void:
	fm_sfx.start(effect_name)


## Port only: the FM effect ends (keyed off, FM6 given back).
func fm_effect_stop() -> void:
	fm_sfx.stop()


## After the driver's batch and mixing time: the effect's writes for this
## tick (its `$2B` = `$00` after the driver's own DAC switches).
func _fm_effect_tick() -> void:
	if not fm_sfx.playing():
		out.fm6_taken = false
		return
	var writes := fm_sfx.tick(out.regs, out.fm6_taken)
	out.fm6_taken = false
	if chips == null:
		return
	for w: Array in writes:
		chips.call("ym_write", w[0], w[1], w[2])
# --- the organ pool (plan 39) ----------------------------------------------------------------------

## `sound_play` for [MwSound]: with [member organ_pool], the pool's
## original tunes (`$05-$09`) play a tune of the pool instead ([method
## play_organ]); everything else is the driver's [method
## MwSound68k.sound_play].
func play_sound(id: int) -> int:
	if organ_pool and (id & 0xFFFF) in MwOrganPool.ORIGINALS:
		return play_organ()
	return s68k.sound_play(id)


## `$13CE2` for [MwSound] (the period-start jingle; [param rng_value] is the
## game's draw, made whatever plays): with [member organ_pool] a tune of the
## pool ([method play_organ]), else the driver's 5 + (r & 3).
func random_sound(rng_value: int) -> int:
	if organ_pool:
		return play_organ()
	return s68k.random_sound(rng_value)


## One of the pool's tunes at random ([method MwOrganPool.pick]); its handle.
## Plan 35: drawn from [member session]'s organ stream - the game waits on
## the tune (a carried goal song holds the scoreboard for its length), so
## every machine of an online match, and a replay of a recorded game, picks
## the same; without a session the pool's own generator.
func play_organ() -> int:
	var stream: MlhRng = session.port_stream(MwSession.STREAM_ORGAN) if session != null else null
	return play_pool_tune(MwOrganPool.pick(stream))


## Pool tune [param k]: 0-4 the original's (`sound_play` of [constant
## MwOrganPool.ORIGINALS][k]), 5-8 the pool's own ([member organ_tunes]),
## started as a sequence of this driver's ROM copy, with its floor hits.
## Returns the handle.
func play_pool_tune(k: int) -> int:
	organ_last = k
	var n := MwOrganPool.ORIGINALS.size()
	if k < n:
		return s68k.sound_play(MwOrganPool.ORIGINALS[k])
	var h := s68k.play_sequence(organ_addresses[k - n])
	var hits := organ_tunes[k - n].hits
	if not hits.is_empty() and chips != null:
		_organ_handle = h
		_organ_hits = hits
		_organ_clock = 0
	return h


## Each tick before the driver's: the floor hits due on this tick of the
## tune (so a hit at tick t starts with the sequence's clock t); a tune
## stopped or ended takes its hits with it.
func _organ_tick() -> void:
	if _organ_handle < 0:
		return
	if not s68k.seq_busy(_organ_handle & 0x7FFFFFFF):   # `sound_busy` without its API count
		_organ_stop()
		return
	for t in _organ_hits:
		if t == _organ_clock:
			_start_hit()
	_organ_clock += 1


## A floor hit on the chips' extra voices (the mixer's pick: the first free,
## else the oldest's). An extra whose voice it took loses it, as
## [method _add_extra] has it - the extra plays on in the model, and its stop
## no longer cuts the hit (plan 40, the survey's B8). Returns the voice.
func _start_hit() -> int:
	var v := int(chips.call("pcm_start_extra", MwOrganPool.HIT_SAMPLE_ID, 0x100, 0x80))
	_organ_voices.append(v)
	for extra in _extras:
		if v >= 0 and extra.voice == v:
			extra.voice = -1
	return v


## No more floor hits; those sounding stop.
func _organ_stop() -> void:
	if chips != null:
		for v in _organ_voices:
			if v >= 0 and int(chips.call("pcm_sample", v)) == MwOrganPool.HIT_SAMPLE_ID:
				chips.call("pcm_stop", v)
	_organ_voices.clear()
	_organ_handle = -1


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
	var extra := Extra.new()
	extra.sample = ch.sample
	if desc.loops():
		if is_note or desc.instrument != CROWD_INSTRUMENT:
			return
		extra.until = _tick + CROWD_HOLD_TICKS
	else:
		var left := 1.0 - float(ch.index) / maxf(ch.length, 1.0)
		extra.end = _end_tick(ch.sample, ch.step, left)
	if is_note:
		extra.midi = d[3]
		extra.note = d[4]
		extra.stops_at_note_off = desc.flags & 2 == 0
	out.detach[v] = extra


## The model's end of sample [param sample] played at 8.8 step [param step]
## with [param left] of it (0..1) to go: the tick its last frame plays in, at
## the sample's own rate (MwChips plays it so). -1: never (a stopped step).
func _end_tick(sample: int, step: int, left := 1.0) -> int:
	if step <= 0:
		return -1
	var frames := float(_length(sample)) * left
	var per_tick := z80.samples.desc(sample).rate() * step / 256.0 / TICKS_PER_SECOND
	return _tick + ceili(frames / per_tick)


## Sample [param sample]'s length in frames (decoded once).
func _length(sample: int) -> int:
	if not _lengths.has(sample):
		_lengths[sample] = z80.samples.decode(sample).size()
	return _lengths[sample]


## The model's extra voice for a new sound (the mixer's rule: the first one
## free, else the oldest's); a sound there is taken over.
func _model_slot() -> int:
	var used := {}
	var oldest: Extra = null
	for extra in _extras:
		used[extra.slot] = true
		if oldest == null or extra.serial < oldest.serial:
			oldest = extra
	for v in range(EXTRA_FIRST, EXTRA_END):
		if not used.has(v):
			return v
	return oldest.slot


## A sound the driver refused: started on an extra voice (not a loop).
func _refused(d: Array) -> void:
	var is_note := int(d[4]) == 0
	if not (free_music_samples if is_note else free_effects):
		return
	var i := z80.samples.by_record(int(d[1]))
	if i < 0:
		return
	var desc := z80.samples.desc(i)
	if desc.loops() or _length(i) == 0:
		return
	_restarted(i)
	var extra := Extra.new()
	extra.voice = int(chips.call("pcm_start_extra", i, int(d[2]), int(d[3]))) if chips != null else -1
	extra.sample = i
	extra.end = _end_tick(i, int(d[2]))
	if is_note:
		extra.midi = d[5]
		extra.note = d[6]
		extra.stops_at_note_off = desc.flags & 2 == 0
	_add_extra(extra)


## A note-off the driver had no note for: the oldest extra of that note stops.
func _note_off(midi: int, note: int) -> void:
	for extra in _extras:
		if extra.midi == midi and extra.note == note and extra.stops_at_note_off:
			_chips_stop(extra)
			_extras.erase(extra)
			return


## The chips' voice of [param extra] stopped (if it still has one).
func _chips_stop(extra: Extra) -> void:
	if chips != null and extra.voice >= 0:
		chips.call("pcm_stop", extra.voice)


## Sample [param sample] starts (on a channel or an extra voice): its copies
## on extra voices stop, as the original's restart of a sound does (a held
## crowd fades out quickly instead: the driver's restarted one takes over).
func _restarted(sample: int) -> void:
	for e in _extras.duplicate():
		if e.sample == sample:
			if e.until >= 0:
				_chips_fade(e)
			else:
				_chips_stop(e)
			_extras.erase(e)


func _chips_fade(extra: Extra) -> void:
	if chips != null and extra.voice >= 0:
		chips.call("pcm_fade", extra.voice, int(CROWD_FADE_TICKS * _rate / TICKS_PER_SECOND))


## [param extra] on an extra voice: the model's slot (one taken over leaves the
## model), the chips' voice (one the chips took over loses its voice).
func _add_extra(extra: Extra) -> void:
	extra.slot = _model_slot()
	_serial += 1
	extra.serial = _serial
	for o in _extras.duplicate():
		if o.slot == extra.slot:
			_extras.erase(o)            # the model's voices were all busy: the oldest's taken over
		elif extra.voice >= 0 and o.voice == extra.voice:
			o.voice = -1                # the chips took that voice over (it plays on in the model)
	_extras.append(extra)
	extras_peak = maxi(extras_peak, _extras.size())


## After the batch: the kept channels' new extras, then the earlier copies
## of the samples the batch started stopped (also those just kept: a sound cut
## by itself stays cut); extras that ended dropped; a held crowd fades when
## its time is up or the crowd was turned off.
func _extras_after() -> void:
	for extra: Extra in out.detached:
		_add_extra(extra)
	out.detached.clear()
	for sample in out.started:
		_restarted(sample)
	out.started.clear()
	var crowd_on := s68k.r16(MwSound68k.CROWD_ON) != 0
	for e in _extras.duplicate():
		if e.end >= 0 and _tick >= e.end:
			_extras.erase(e)            # ended in the model (the chips' voice ends by itself)
		elif e.until >= 0 and (_tick >= e.until or not crowd_on):
			_chips_fade(e)
			e.until = -1
			e.end = _tick + CROWD_FADE_TICKS


## Port only (plan 33): whether sound [param id]'s sample (a `$12`..
## voice) is sounding, on a driver channel or an extra voice - plan 35: as
## the model has them (the Z80's channels, the extras' modelled ends), the
## same with or without chips and sound.
func sounding(id: int) -> bool:
	var sample := z80.samples.by_sound_id(id)
	if sample < 0:
		return false
	for ch in z80.channels:
		if ch.sample == sample and ch.status & MwSoundZ80.STATUS_PLAYING:
			return true
	for extra in _extras:
		if extra.sample == sample and (extra.end < 0 or _tick < extra.end):
			return true
	return false


func _stop_extras() -> void:
	for extra in _extras:
		_chips_stop(extra)
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
