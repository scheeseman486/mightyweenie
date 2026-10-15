class_name MwAudioOut
extends MwSoundOut
## Where the audio service's [MwSoundZ80] output goes (plan 12): the YM2612
## and PSG writes to the chip emulators of the `mw_audio` GDExtension
## (`MwChips`), the PCM channels to its native sample mixer (the samples the
## original streams through the YM2612's DAC, played here from the ROM's data
## at their own rates, resampled - docs/re/sound.md).
##
## [member chips] is untyped: the extension may be missing (a build without
## it, or before `tools/bin/build-audio` ran), and then nothing is heard while
## the driver still runs (its answers to the game - busy, handles - do not
## depend on the chips).

## The `MwChips` object, or null.
var chips: Object = null
## Enhancement support ([member MwAudio.free_effects], [member MwAudio.free_music_samples]):
## per Z80 channel, an [MwAudio.Extra] to keep the channel's sample sounding as
## when the batch now being applied stops or replaces it (null: none).
var detach := [null, null, null, null]
## The extras made from [member detach] during the batch (taken by [MwAudio]).
var detached: Array = []
## The samples the Z80's channels started during the batch (MwAudio's "a
## sound started again cuts its earlier copies" rule; taken by [MwAudio]).
var started := PackedInt32Array()
## Port only (plan 34): the driver's last value of every YM2612 register,
## index `port * 256 + register` (-1: never written) - what an FM effect
## ([MwFmSfx]) gives back when it ends.
var regs := PackedInt32Array()
## Port only (plan 34): the driver wrote FM6 (a key-on, or one of its
## channel or operator registers) since [MwAudio] last looked - an FM
## effect playing there leaves it to the driver.
var fm6_taken := false


func _init(chips_: Object = null) -> void:
	chips = chips_
	reset_regs()


## Forgets the driver's register values (the chips were reset).
func reset_regs() -> void:
	regs.resize(512)
	regs.fill(-1)
	fm6_taken = false


## Loads every sample of [param samples] into the chips' PCM mixer, by its
## [MwSoundSamples] index (the ids [method pcm_start] passes).
func load_samples(samples: MwSoundSamples) -> void:
	if chips == null:
		return
	for i in samples.count():
		var desc := samples.desc(i)
		var data := samples.decode(i)
		chips.call("pcm_load", i, data, desc.rate(), desc.loop_start if desc.loops() else -1)


## [method MwSoundOut.ym_write]: [param value] kept as register [param reg] of part
## [param port] ([member regs]; FM6's key-on or its registers set
## [member fm6_taken]), then written to the chips.
func ym_write(port: int, reg: int, value: int) -> void:
	regs[(port & 1) * 256 + (reg & 0xFF)] = value
	if port == 0 and reg == MwFmSfx.KEY:
		fm6_taken = fm6_taken or (value & 7 == MwFmSfx.KEY_CHANNEL and value & 0xF0 != 0)
	elif port == MwFmSfx.PORT and reg >= 0x30 and reg & 3 == MwFmSfx.CHANNEL:
		fm6_taken = true
	if chips:
		chips.call("ym_write", port, reg, value)


## [method MwSoundOut.psg_write]: [param value] to the chips' PSG.
func psg_write(value: int) -> void:
	if chips:
		chips.call("psg_write", value)


## (Plan 35: the extras' bookkeeping - [member detach], [member started] -
## runs with or without chips: the model's answers never depend on them.)
func pcm_start(ch: int, sample: int, from_index: int) -> void:
	_detach(ch)
	started.append(sample)
	if chips:
		chips.call("pcm_start", ch, sample, from_index)


## [method MwSoundOut.pcm_stop]: channel [param ch]'s sample detached first when
## [member detach] marks it (it keeps sounding: [member detached]), then the
## chips stop the channel.
func pcm_stop(ch: int) -> void:
	_detach(ch)
	if chips:
		chips.call("pcm_stop", ch)


## The batch is over: channels marked in [member detach] that it did not
## stop or replace keep their sample as it is.
func end_batch() -> void:
	for k in 4:
		detach[k] = null


func _detach(ch: int) -> void:
	var entry: Variant = detach[ch]
	if entry == null:
		return
	detach[ch] = null
	entry.voice = int(chips.call("pcm_detach", ch)) if chips else -1
	detached.append(entry)


## [method MwSoundOut.pcm_rate]: channel [param ch]'s step [param step] to the chips.
func pcm_rate(ch: int, step: int) -> void:
	if chips:
		chips.call("pcm_rate", ch, step)


## [method MwSoundOut.pcm_volume]: channel [param ch]'s volume [param volume] to the
## chips.
func pcm_volume(ch: int, volume: int) -> void:
	if chips:
		chips.call("pcm_volume", ch, volume)
