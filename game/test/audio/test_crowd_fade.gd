extends "res://test/rom/rom_test_base.gd"
## Plan 40 (D7, owner: 90 ticks): the crowd's fade-in from silence (the
## match's opening in 3D, CROWD_FADE_IN; a scoreboard after the carried goal
## song, MwSound.FADE_IN_TICKS) is the mix's - the driver starts the crowd
## and raises it as the original does (volume $40, 8 a tick), the mix ramps
## its output in over exactly the ticks asked.

var audio: MwAudio


func after_each() -> void:
	MwSound.driver = null
	if audio != null:
		audio.free()
		audio = null


func _driver() -> MwAudio:
	audio = MwAudio.new()
	audio.setup(MwRom.data(), false, false)
	MwSound.driver = audio
	return audio


func test_the_driver_starts_the_crowd_as_the_original() -> void:
	if not need_rom():
		return
	var a := _driver()
	MwSound.crowd_level(50, 90)
	assert_eq(a.s68k.r16(MwSound68k.CROWD_VOL), 0x40, "the original's start")
	assert_eq(a._fade_ins.size(), 1, "the mix's fade-in")
	assert_eq(int(a._fade_ins[0][0]), a.s68k.r32(MwSound68k.CROWD_HANDLE), "the crowd's voice")
	assert_eq(int(a._fade_ins[0][1]), 90, "over the ticks asked")
	for i in 20:
		a.step_driver()
	@warning_ignore("integer_division")
	var target := 0x80 + 2 * (50 * 0x80 / 1000)
	assert_eq(a.s68k.r16(MwSound68k.CROWD_VOL), target, "risen 8 a tick to the target, the original's pace")
	for i in 80:
		a.step_driver()
	assert_true(a._fade_ins.is_empty(), "in after 90 ticks")


func test_a_crowd_already_on_is_not_faded_again() -> void:
	if not need_rom():
		return
	var a := _driver()
	MwSound.crowd_level(50)
	for i in 10:
		a.step_driver()
	MwSound.crowd_level(300, 90)
	assert_true(a._fade_ins.is_empty(), "sounding: only its level changes")
	assert_true(a.s68k.crowd_sounding())


func test_the_driver_alone_is_the_originals() -> void:
	if not need_rom():
		return
	var a := _driver()
	a.s68k.crowd_level(50)
	assert_eq(a.s68k.r16(MwSound68k.CROWD_VOL), 0x40)
	assert_true(a._fade_ins.is_empty(), "no fade: the driver's call is the original's")
