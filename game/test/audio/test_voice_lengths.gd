extends "res://test/rom/rom_test_base.gd"
## Plan 40 (D6, owner: one answer to whether a sound still plays - the
## driver's). The rink's sims that don't drive the sound (MwRinkSim.live off:
## the match's opening's rehearsal, the instant replay's demo) predict how
## long a coach's voice plays by MwRinkPhases.VOICE_TICKS (measured from the
## original's runs); on the rink's passes (every 2 ticks) that prediction
## must be the driver model's own answer, which live play hears.


func test_the_rinks_voice_lengths_are_the_drivers() -> void:
	if not need_rom():
		return
	for id: int in MwRinkPhases.VOICE_TICKS:
		var audio := MwAudio.new()
		audio.setup(MwRom.data(), false, false)
		var h := audio.play_sound(id)
		var n := 0
		while audio.s68k.sound_busy(h) and n < 1000:
			audio.step_driver()
			n += 1
		audio.free()
		var table: int = MwRinkPhases.VOICE_TICKS[id]
		var same := true
		for k in range(0, n + 4, 2):
			same = same and (k < table) == (k < n)
		assert_true(n > 100 and same, "voice $%02X: the driver plays it %d ticks, the table %d" % [id, n, table])
