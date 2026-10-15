extends "res://test/rom/rom_test_base.gd"
## MwAnimState: the original's anim_advance ($143CA), integer quirks included.


func _state(speed: int, flags: int, count: int) -> MwAnimState:
	var anim := MwAnimState.new()
	anim.speed = speed
	anim.flags = flags
	anim.count = count
	anim.play()
	return anim


func _frames(anim: MwAnimState, n: int, elapsed := 1) -> Array:
	var out := []
	for i in n:
		anim.advance(elapsed)
		out.append(anim.frame)
	return out


func test_looping_forward() -> void:
	var anim := _state(128, MwAnimState.LOOP | 1, 3)     # half a frame per tick
	assert_eq(_frames(anim, 8), [0, 1, 1, 2, 2, 0, 0, 1])
	assert_true(anim.playing())


func test_once_stops_on_the_last_frame() -> void:
	var anim := _state(128, 1, 5)
	assert_eq(_frames(anim, 10), [0, 1, 1, 2, 2, 3, 3, 4, 4, 4])
	assert_false(anim.playing(), "stopped at the end")
	assert_eq(anim.position, (5 << 8) - 1)
	anim.advance(5)
	assert_eq(anim.frame, 4, "a stopped animation stays")


func test_reverse() -> void:
	var anim := _state(256, MwAnimState.LOOP | 2, 4)
	assert_eq(_frames(anim, 5), [2, 1, 0, 3, 2])


func test_ping_pong_keeps_the_original_quirks() -> void:
	# length 2 x (5 - 1) frames; the way back floors one frame lower and the
	# turning point reads frame 5 (one past the last), as the original does
	var anim := _state(256, MwAnimState.LOOP | 3, 5)
	assert_eq(_frames(anim, 8), [1, 2, 3, 4, 5, 2, 1, 0])


func test_elapsed_multiplies_in_16_bits() -> void:
	var wrapping := _state(0x8000, MwAnimState.LOOP | 1, 255)
	wrapping.advance(3)
	assert_eq(wrapping.position, 0x8000, "0x18000 & 0xFFFF")
	var at_once := _state(43, MwAnimState.LOOP | 1, 12)
	var anim := _state(43, MwAnimState.LOOP | 1, 12)
	at_once.advance(7)
	for i in 7:
		anim.advance(1)
	assert_eq(at_once.position, anim.position, "elapsed ticks at once = one at a time")


func test_from_record() -> void:
	if not need_rom():
		return
	var anim := MwAnimState.from_record(rom, 0x4B748)      # title sparkle
	assert_eq([anim.speed, anim.flags, anim.count], [128, 1, 5])
	assert_false(anim.playing(), "anim_set leaves it stopped; the screen starts it")
	anim.play()
	assert_true(anim.playing())
