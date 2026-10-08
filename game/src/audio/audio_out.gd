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


func _init(chips_: Object = null) -> void:
	chips = chips_


## Loads every sample of [param samples] into the chips' PCM mixer, by its
## [MwSoundSamples] index (the ids [method pcm_start] passes).
func load_samples(samples: MwSoundSamples) -> void:
	if chips == null:
		return
	for i in samples.count():
		var d := samples.desc(i)
		var data := samples.decode(i)
		chips.call("pcm_load", i, data, d.rate(), d.loop_start if d.loops() else -1)


func ym_write(port: int, reg: int, value: int) -> void:
	if chips:
		chips.call("ym_write", port, reg, value)


func psg_write(value: int) -> void:
	if chips:
		chips.call("psg_write", value)


func pcm_start(ch: int, sample: int, from_index: int) -> void:
	if chips:
		_detach(ch)
		started.append(sample)
		chips.call("pcm_start", ch, sample, from_index)


func pcm_stop(ch: int) -> void:
	if chips:
		_detach(ch)
		chips.call("pcm_stop", ch)


## The batch is over: channels marked in [member detach] that it did not
## stop or replace keep their sample as it is.
func end_batch() -> void:
	for k in 4:
		detach[k] = null


func _detach(ch: int) -> void:
	var e = detach[ch]
	if e == null:
		return
	detach[ch] = null
	var voice: int = chips.call("pcm_detach", ch)
	if voice >= 0:
		e.voice = voice
		detached.append(e)


func pcm_rate(ch: int, step: int) -> void:
	if chips:
		chips.call("pcm_rate", ch, step)


func pcm_volume(ch: int, volume: int) -> void:
	if chips:
		chips.call("pcm_volume", ch, volume)
