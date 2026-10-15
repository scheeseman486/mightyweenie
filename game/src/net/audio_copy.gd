class_name MwAudioCopy
extends RefCounted
## Plan 41 (online feel), work item 3: one sound driver's model copied into
## another ([MwRinkCopy] on its parts): what a resync snapshot carries of it
## (MwNetSnapshot.audio_state - the 68000 side, the Z80 side, the register
## mirror, the extra voices, the voices fading in, the FM effect, its tick
## and serials), object to object; the ROM, the samples made from it, the
## chips and each part's own output stay the destination's own. The
## run-ahead's shadow gets the game's driver this way at each rollback
## (MwNetRunAhead), and an online client's heard driver the game's model
## after a resync.

var copier := MwRinkCopy.new()


func _init() -> void:
	copier.keep[MwSound68k] = PackedStringArray(["rom", "trace"])
	copier.keep[MwSoundZ80] = PackedStringArray(["out", "samples", "rom"])
	copier.keep[MwAudioOut] = PackedStringArray(["chips"])


## [param src]'s state into [param dst] (both set up on the same ROM).
func copy_into(dst: MwAudio, src: MwAudio) -> void:
	copier.copy_roots([[dst.s68k, src.s68k], [dst.z80, src.z80], [dst.out, src.out]])
	for f: String in MwNetSnapshot.AUDIO_FIELDS:
		dst.set(f, copier.value(src.get(f)))
