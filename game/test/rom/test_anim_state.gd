extends "res://test/rom/rom_test_base.gd"
## MwAnimState: the original's anim_advance ($143CA), integer quirks included.


func _state(speed: int, flags: int, count: int) -> MwAnimState:
	var s := MwAnimState.new()
	s.speed = speed
	s.flags = flags
	s.count = count
	s.play()
	return s


func _frames(s: MwAnimState, n: int, elapsed := 1) -> Array:
	var out := []
	for i in n:
		s.advance(elapsed)
		out.append(s.frame)
	return out


func test_looping_forward() -> void:
	var s := _state(128, MwAnimState.LOOP | 1, 3)     # half a frame per tick
	assert_eq(_frames(s, 8), [0, 1, 1, 2, 2, 0, 0, 1])
	assert_true(s.playing())


func test_once_stops_on_the_last_frame() -> void:
	var s := _state(128, 1, 5)
	assert_eq(_frames(s, 10), [0, 1, 1, 2, 2, 3, 3, 4, 4, 4])
	assert_false(s.playing(), "stopped at the end")
	assert_eq(s.position, (5 << 8) - 1)
	s.advance(5)
	assert_eq(s.frame, 4, "a stopped animation stays")


func test_reverse() -> void:
	var s := _state(256, MwAnimState.LOOP | 2, 4)
	assert_eq(_frames(s, 5), [2, 1, 0, 3, 2])


func test_ping_pong_keeps_the_original_quirks() -> void:
	# length 2 x (5 - 1) frames; the way back floors one frame lower and the
	# turning point reads frame 5 (one past the last), as the original does
	var s := _state(256, MwAnimState.LOOP | 3, 5)
	assert_eq(_frames(s, 8), [1, 2, 3, 4, 5, 2, 1, 0])


func test_elapsed_multiplies_in_16_bits() -> void:
	var s := _state(0x8000, MwAnimState.LOOP | 1, 255)
	s.advance(3)
	assert_eq(s.position, 0x8000, "0x18000 & 0xFFFF")
	var t := _state(43, MwAnimState.LOOP | 1, 12)
	var u := _state(43, MwAnimState.LOOP | 1, 12)
	t.advance(7)
	for i in 7:
		u.advance(1)
	assert_eq(t.position, u.position, "elapsed ticks at once = one at a time")


func test_from_record() -> void:
	if not need_rom():
		return
	var s := MwAnimState.from_record(rom, 0x4B748)      # title sparkle
	assert_eq([s.speed, s.flags, s.count], [128, 1, 5])
	assert_false(s.playing(), "anim_set leaves it stopped; the screen starts it")
	s.play()
	assert_true(s.playing())
