class_name MwSoundOut
extends RefCounted
## Where [MwSoundZ80] sends what the original's Z80 does to the outside
## world (plan 12): the YM2612 and PSG register writes it makes, and the PCM
## channel events that the game plays natively instead of through the
## YM2612's DAC.
##
## A base class with no-op methods: the audio service extends it to feed the
## chip emulators and the PCM players, tests extend it to record the calls.
## Every call happens inside [method MwSoundZ80.apply_batch] or
## [method MwSoundZ80.advance], i.e. on the 60 Hz tick the original's Z80
## makes it in, in the original's order (docs/re/sound.md, the Z80 driver):
## per batch the FM blocks 0-5 (patch, key, frequency, TL), the PSG blocks
## 0-3 (off, tone, attenuation), the PCM triggers 0-3 ([method pcm_start] /
## [method pcm_stop]), the DAC switch, then the effective rate and volume of
## every playing PCM channel that changed; during the mixing time the ends of
## samples ([method pcm_stop]), each followed by the DAC switch and the
## changed rates / volumes.
##
## PCM channels [code]ch[/code] 0-3 are the Z80's channel states `$BE`, `$CE`,
## `$DE`, `$EE` (68k voices 10-13). The Z80 mixes them in software: only the
## first playing one of `$EE`, `$DE`, `$CE`, `$BE` ("ch0") honours its pitch
## and volume, the others play at step `$100` and volume `$80`. The values
## passed here already have that rule applied.


## A YM2612 register write: [param port] 0 = part I (`$4000`/`$4001`),
## 1 = part II (`$4002`/`$4003`). Includes the DAC enable `$2B` (`$80` while
## any PCM channel plays, `$00` when none does: FM channel 6 is muted while
## the DAC is on, as on the hardware). The DAC data register `$2A` is never
## written: the samples are played natively.
func ym_write(_port: int, _reg: int, _value: int) -> void:
	pass


## A byte written to the SN76489 PSG (`$7F11`).
func psg_write(_value: int) -> void:
	pass


## PCM channel [param ch] starts [param sample] (an [MwSoundSamples] index,
## -1 if the header is not a known sample) at [param from_index] (index into
## its decoded data, [method MwSoundSamples.decode]; [MwSoundZ80] always
## passes 0: every start is from the sample's beginning). Replaces whatever
## the channel played. Always followed, in the same call of [MwSoundZ80], by
## [method pcm_rate] and [method pcm_volume] for it. The audio service plays
## it in the `mw_audio` extension's sample mixer ([MwAudioOut]).
func pcm_start(_ch: int, _sample: int, _from_index: int) -> void:
	pass


## PCM channel [param ch] stops: a stop command, or the end of its sample (the
## Z80's end marker; looping samples never end by themselves).
func pcm_stop(_ch: int) -> void:
	pass


## The effective playback step of PCM channel [param ch] from now on: 8.8
## fixed point, `$100` = the sample's own rate ([method MwSoundSamples.mix_rate]);
## `$100` for every channel but ch0 and for a DPCM sample.
func pcm_rate(_ch: int, _step: int) -> void:
	pass


## The effective volume of PCM channel [param ch] from now on: `$80` = unity
## (linear, [param volume] / `$80`; the original amplifies above `$80` with
## wrap-around); `$80` for every channel but ch0.
func pcm_volume(_ch: int, _volume: int) -> void:
	pass
