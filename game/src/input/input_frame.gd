class_name MwInputFrame
extends RefCounted
## What one pass of a screen sees: the actions held when the pass started
## and those newly pressed since the previous pass started (the original reads
## "newly pressed" once per pass). Actions are MwVerbs action names.

var held := {}       # action -> true
var pressed := {}    # action -> true
## Players 1-4's analogue sticks (MwInputSource.sticks; empty: none).
var sticks: Array = []
## Players 1-12's shot heights (MwInputSource.heights; empty: the D-pad's).
var heights: Array = []
## Plan 35: the players whose machine is away online (player number ->
## MwTickInput status: LAGGING, DISCONNECTED, KICKED); the CPU plays for
## them. Empty offline.
var away := {}
## Plan 40 (S7): the pass's tick as the wire has it (MwInputSource.tick_input;
## null: none) and the original's pads' players (the session's pad map when
## the screen remaps; empty: none) - [method state].
var tick: MwTickInput = null
var pad_map := PackedInt32Array()


## The frame of [param held_now]: newly pressed, the actions in it that [param held_before] (the
## previous pass's) lacked.
static func make(held_now: Dictionary, held_before: Dictionary) -> MwInputFrame:
	var input := MwInputFrame.new()
	input.held = held_now
	for a in held_now:
		if not held_before.has(a):
			input.pressed[a] = true
	return input


## True when [param action] is held.
func is_held(action: String) -> bool:
	return held.has(action)


## True when [param action] was newly pressed since the previous pass.
func is_pressed(action: String) -> bool:
	return pressed.has(action)


## Player [param player]'s verb newly pressed (menu verbs: any player).
func player_pressed(player: int, verb: String) -> bool:
	return pressed.has(MwVerbs.action(player, verb))


## Player [param player]'s own menu verb newly pressed (`p2_ui_left`).
func menu_pressed(player: int, verb: String) -> bool:
	return pressed.has(MwVerbs.menu_action(player, verb))


## Player [param player]'s [param verb] held (menu verbs: any player).
func player_held(player: int, verb: String) -> bool:
	return held.has(MwVerbs.action(player, verb))


## Player [param player]'s analogue stick (MwInputSource.sticks): each axis
## -256..256; ZERO when none (the D-pad as the original).
func stick(player: int) -> Vector2i:
	return sticks[player - 1] if player >= 1 and player <= sticks.size() else Vector2i.ZERO


## Player [param player]'s shot height (MwInputSource.heights): 0 none, 1
## high, 2 low; -1 when the D-pad lifts the shot (the original).
func height(player: int) -> int:
	return heights[player - 1] if player >= 1 and player <= heights.size() else -1


## Plan 40 (S7): player [param player]'s own state this pass as the wire
## has it (MwNetInput: a new per-player input is read from here); a remapped
## screen's pad [param player] is its player's (pads past the map: none).
## Empty without one.
func state(player: int) -> PackedByteArray:
	if tick == null or player < 1 or player > MwNetInput.PLAYERS:
		return PackedByteArray()
	var n := player
	if not pad_map.is_empty():
		n = pad_map[player - 1] if player <= pad_map.size() else 0
		if n < 1:
			return PackedByteArray()
	return MwNetInput.player(tick.states()[1], n)


## Player [param player]'s "newly pressed" pad byte as the original keeps it,
## from that player's verbs in [param contexts] (the screen's: MwScreens).
func pad_bits(player: int, contexts: Array) -> int:
	return MwVerbs.pad_byte(pressed, player, contexts)


## Plan 40 (I2): the newly pressed bytes of players 1-[param n] OR'd (the
## original's screens that read any pad).
func any_pad_bits(n: int, contexts: Array) -> int:
	var bits := 0
	for p in range(1, n + 1):
		bits |= pad_bits(p, contexts)
	return bits


## The same for the held actions.
func held_bits(player: int, contexts: Array) -> int:
	return MwVerbs.pad_byte(held, player, contexts)
