extends SceneTree
## Renders the audio driver offline into a WAV (plan 12 checks):
##   tools/bin/godot-headless -s res://test/audio/render_check.gd -- OUT.wav SCRIPT [TICKS]
## SCRIPT: "title" (the title music), "game" (the menus' music), "id:N" (sound
## id N, then silence), "crowd:L" (the crowd at level L). Needs the mw_audio
## extension and the ROM.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not ClassDB.class_exists("MwChips"):
		push_error("usage: -- OUT.wav SCRIPT [TICKS] (needs MwChips)")
		quit(2)
		return
	var out_path: String = args[0]
	var what: String = args[1]
	var ticks := int(args[2]) if args.size() > 2 else 600
	var audio := MwAudio.new()
	audio.setup(MwRom.data(), false)
	match what.get_slice(":", 0):
		"title":
			audio.s68k.music_title()
		"game":
			audio.s68k.music_game()
		"id":
			audio.s68k.sound_play(what.get_slice(":", 1).hex_to_int() if what.get_slice(":", 1).begins_with("0x") else int(what.get_slice(":", 1)))
		"crowd":
			audio.s68k.crowd_level(int(what.get_slice(":", 1)))
	var pcm := PackedByteArray()
	var peak := 0.0
	var t0 := Time.get_ticks_usec()
	for i in ticks:
		var batch := audio.s68k.vblank(audio.z80)
		if not batch.is_empty():
			audio.z80.apply_batch(batch)
		audio.z80.advance(not batch.is_empty())
		var frames: PackedVector2Array = audio.chips.call("render", audio.frames_this_tick())
		var at := pcm.size()
		pcm.resize(at + frames.size() * 4)
		for f in frames.size():
			var l := clampi(int(frames[f].x * 32767.0), -32768, 32767)
			var r := clampi(int(frames[f].y * 32767.0), -32768, 32767)
			peak = maxf(peak, absf(frames[f].x))
			pcm.encode_s16(at + 4 * f, l)
			pcm.encode_s16(at + 4 * f + 2, r)
	var us := Time.get_ticks_usec() - t0
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(round(float(audio.chips.call("sample_rate"))))
	wav.data = pcm
	wav.save_to_wav(out_path)
	print("rendered %d ticks (%.1f s) in %.2f s; peak %.3f -> %s" % [ticks, ticks / 60.0, us / 1e6, peak, out_path])
	quit(0)
