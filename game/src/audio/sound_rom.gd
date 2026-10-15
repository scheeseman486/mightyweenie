class_name MwSoundRom
extends RefCounted
## The sound driver's ROM tables (docs/re/sound.md). Plan 40 (D8): one owner
## - the 68000 side ([MwSound68k]), the Z80's ([MwSoundZ80]), the samples'
## parser ([MwSoundSamples]) and the stats screen read them from here.

const Z80_DRIVER := 0x15C90    ## a length word (= the Z80 address of the FM patches), then the code loaded at Z80 $0000
const SAMPLES := 0x1C0000      ## sample offsets in instruments are relative to this ($15B46; `$E6AA`)
const SEQUENCES := 0x1F57E     ## sound ids 0..$11: sequence pointers (long)
const VOICE_IDS := 0x1F5C6     ## sound ids $12..$4C: instrument index (word, < 0 none)
const INSTRUMENTS := 0x1FF010  ## 256 word offsets (from here) to instrument records ($15B4C; `$E6A6`)
const MUSIC_GAME := 0x1CE2D0   ## the sequence `$13C6E` starts (the stats screens' music)
