class_name MwInputFrame
extends RefCounted
## What one pass of a screen sees: the actions held when the pass started
## and those newly pressed since the previous pass started (the original reads
## "newly pressed" once per pass). Actions are MwVerbs action names.

var held := {}       # action -> true
var pressed := {}    # action -> true

## Menu verb -> bit of the original's pad bytes (`read_joypads` $1407E:
## S A C B R L D U).
const PAD_BITS := {"ui_up": 0x01, "ui_down": 0x02, "ui_left": 0x04, "ui_right": 0x08,
		"ui_option_b": 0x10, "ui_option_c": 0x20, "ui_option_a": 0x40, "ui_accept": 0x80}


static func make(held_now: Dictionary, held_before: Dictionary) -> MwInputFrame:
	var f := MwInputFrame.new()
	f.held = held_now
	for a in held_now:
		if not held_before.has(a):
			f.pressed[a] = true
	return f


func is_held(action: String) -> bool:
	return held.has(action)


func is_pressed(action: String) -> bool:
	return pressed.has(action)


## Player [param player]'s verb newly pressed (menu verbs: any player).
func player_pressed(player: int, verb: String) -> bool:
	return pressed.has(MwVerbs.action(player, verb))


## Player [param player]'s own menu verb newly pressed (`p2_ui_left`).
func menu_pressed(player: int, verb: String) -> bool:
	return pressed.has(MwVerbs.menu_action(player, verb))


func player_held(player: int, verb: String) -> bool:
	return held.has(MwVerbs.action(player, verb))


## Player [param player]'s "newly pressed" pad byte as the original keeps it,
## from that player's menu verbs ([constant PAD_BITS]).
func pad_bits(player: int) -> int:
	var bits := 0
	for v in PAD_BITS:
		if menu_pressed(player, v):
			bits |= PAD_BITS[v]
	return bits
