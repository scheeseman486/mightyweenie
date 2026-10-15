extends "res://test/rom/rom_test_base.gd"
## Plan 35 work item 1 (docs/net.md): analogue sticks quantised at the input
## layer - an angle and a travel, a byte each (MwStick) - in the units the
## simulation's readers use (256 angle steps, MwHumanControl.stick_angle).


func test_codes() -> void:
	assert_eq(MwStick.encode(Vector2i.ZERO), MwStick.NONE, "no stick")
	assert_eq(MwStick.encode(Vector2i(256, 0)), 255, "full right: angle 0, travel 255")
	assert_eq(MwStick.angle(MwStick.encode(Vector2i(0, 256))), 0x40, "down: $40")
	assert_eq(MwStick.angle(MwStick.encode(Vector2i(-256, 0))), 0x80, "left: $80")
	assert_eq(MwStick.angle(MwStick.encode(Vector2i(181, -181))), 0xE0, "up-right")
	assert_eq(MwStick.travel(MwStick.encode(Vector2i(128, 0))), 128, "half way")
	assert_eq(MwStick.encode(Vector2i(0, 1)), (0x40 << 8) | 1, "the least that counts: travel 1")


func test_decoded_as_the_readers_take_it() -> void:
	if not need_rom():
		return
	assert_eq(MwStick.decode(MwStick.NONE, rom), Vector2i.ZERO)
	assert_eq(MwStick.decode(MwStick.encode(Vector2i(256, 0)), rom), Vector2i(256, 0), "full travel right")
	assert_eq(MwStick.decode(MwStick.encode(Vector2i(181, 181)), rom), Vector2i(181, 181), "a full diagonal, as before")
	for a in range(0, 256, 5):
		for t in [40, 128, 255]:
			var v := MwStick.decode((a << 8) | t, rom)
			var got := MwTrig.angle_of(rom, v.x, v.y)
			assert_true(absi(((got - a + 128) & 0xFF) - 128) <= 1,
					"angle %d travel %d reads back as %d (the readers' 256 steps)" % [a, t, got])
			@warning_ignore("integer_division")
			var length: int = (t * 256 + 127) / 255
			assert_true(absf(Vector2(v).length() - length) <= 1.0, "its length %d" % length)


func test_turns_are_exact() -> void:
	var c := MwStick.encode(Vector2i(0, -256))
	assert_eq(MwStick.angle(MwStick.turned(c, 2)), 0, "up, a quarter clockwise: right")
	assert_eq(MwStick.angle(MwStick.turned(c, 1)), 0xE0, "an eighth: up-right")
	assert_eq(MwStick.turned(c, 8), c, "a whole turn")
	assert_eq(MwStick.travel(MwStick.turned(c, 3)), MwStick.travel(c))
	assert_eq(MwStick.eighth(MwStick.encode(Vector2i(256, 30))), 0, "the D-pad's eighth: right")
	assert_eq(MwStick.eighth(MwStick.encode(Vector2i(-181, -181))), 5, "up-left")


func test_live_input_gives_the_game_the_quantised_stick() -> void:
	if not need_rom():
		return
	var live := MwLiveInput.new()
	live.sample([MwVerbs.Context.GAMEPLAY])
	var codes := live.stick_codes()
	assert_eq(codes.size(), MwVerbs.PLAYERS if MwSettings.analogue else 0, "a code per player in play")
	for p in codes.size():
		assert_eq(live.sticks()[p], MwStick.decode(codes[p], rom), "the game reads the code decoded")
	var src := MwInputSource.new()
	assert_eq(src.stick_codes(), PackedInt32Array(), "no sticks, no codes")
