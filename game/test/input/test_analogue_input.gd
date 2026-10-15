extends GutTest
## Analogue control's input side (plan 22; MwSettings.analogue): a stick's
## dead zone and travel, its turn with the turned views, the D-pad eighth it
## holds, the frames and pads that carry it; no stick without the option or
## outside play.

var _analogue := true


func before_all() -> void:
	_analogue = MwSettings.analogue


func after_all() -> void:
	MwSettings.analogue = _analogue


func test_dead_zone_and_travel() -> void:
	assert_eq(MwLiveInput.stick_of(Vector2(0.1, 0.1)), Vector2i.ZERO, "inside the dead zone: none")
	assert_eq(MwLiveInput.stick_of(Vector2(1, 0)), Vector2i(256, 0), "full travel")
	assert_eq(MwLiveInput.stick_of(Vector2(0.6, 0)), Vector2i(128, 0), "half the travel past the dead zone")
	assert_eq(MwLiveInput.stick_of(Vector2(0.8, -0.8)), Vector2i(181, -181), "a diagonal to the gate: full travel")


## Plan 40 (I4): the turn the game takes - the quantised code's
## (MwStick.turned), 32 angle steps an eighth.
func test_the_stick_turns_with_the_view() -> void:
	var up := MwStick.encode(MwLiveInput.stick_of(Vector2(0, -1)))
	var right := MwStick.encode(MwLiveInput.stick_of(Vector2(1, 0)))
	assert_eq(MwStick.turned(up, 2), right, "up, a quarter clockwise: right")
	assert_eq(MwStick.eighth(MwStick.turned(up, 1)), 7, "an eighth: up-right")
	assert_eq(MwStick.turned(right, 8), right, "a whole turn")


func test_the_stick_holds_the_move_verbs_of_its_eighth() -> void:
	var eighth_of := func(v: Vector2i) -> int: return MwStick.eighth(MwStick.encode(v))
	var out := MwLiveInput.with_eighth({"p1_move_left": true, "p1_pass": true}, 1, eighth_of.call(Vector2i(256, 30)))
	assert_eq_deep(out, {"p1_move_right": true, "p1_pass": true})
	out = MwLiveInput.with_eighth({}, 2, eighth_of.call(Vector2i(-181, -181)))
	assert_eq_deep(out, {"p2_move_up": true, "p2_move_left": true})
	out = MwLiveInput.with_eighth({"p1_move_down": true}, 2, eighth_of.call(Vector2i(10, 250)))
	assert_eq_deep(out, {"p1_move_down": true, "p2_move_down": true})    # another player's verbs stay


func test_frames_and_pads_carry_the_stick() -> void:
	var input := MwInputFrame.make({"p2_move_right": true}, {})
	assert_eq(input.stick(2), Vector2i.ZERO, "no sticks: none")
	input.sticks = [Vector2i.ZERO, Vector2i(200, -40), Vector2i.ZERO, Vector2i.ZERO]
	assert_eq(input.stick(2), Vector2i(200, -40))
	assert_eq(input.stick(5), Vector2i.ZERO)
	assert_eq(MwGameplayPads.read(input, 2)["stick"], Vector2i(200, -40))
	assert_eq(MwGameplayPads.read(input, 2)["held"], 0x08, "the D-pad as before")
	assert_eq(MwGameplayPads.read(null, 1)["stick"], Vector2i.ZERO)


func test_sticks_only_in_play_and_with_the_option() -> void:
	var live := MwLiveInput.new()
	MwSettings.analogue = true
	live.sample([MwVerbs.Context.GAMEPLAY, MwVerbs.Context.PAUSE])
	assert_eq(live.sticks().size(), MwVerbs.PLAYERS, "play: a stick per player")
	live.sample([MwVerbs.Context.MENU])
	assert_eq(live.sticks(), [], "menus: none")
	MwSettings.analogue = false
	live.sample([MwVerbs.Context.GAMEPLAY])
	assert_eq(live.sticks(), [], "the option off: none (the original's 8 directions)")
	assert_eq(MwInputSource.new().sticks(), [], "other sources (scripted input): none")


func test_the_pace_follows_the_travel() -> void:
	assert_eq(MwSimPlayers.stick_pace(0x300, Vector2i.ZERO), 0x300, "no stick: the top speed")
	assert_eq(MwSimPlayers.stick_pace(0x300, Vector2i(256, 0)), 0x300, "full travel: the same")
	assert_eq(MwSimPlayers.stick_pace(0x300, Vector2i(0, -64)), 0x150, "a quarter: a quarter and a bit")
	assert_eq(MwSimPlayers.stick_pace(0x300, Vector2i(1, 0)), 0xC0, "at the dead zone: a quarter")
