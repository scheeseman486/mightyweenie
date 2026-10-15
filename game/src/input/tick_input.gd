class_name MwTickInput
extends RefCounted
## One tick of every player's input as the input stream carries it (plan 35,
## docs/net.md): the actions held (a bitset over [method actions]: the
## shared menu verbs first, then each player's verbs and per-player menu
## verbs - one contiguous slot per player, [method slot_range]), a press
## counter per action (8 bits, wrapping: a counter that changed is a press -
## never lost, only late), each player's stick ([MwStick] code, 0 none) and
## each player's shot height ([member heights]: MwSettings.shot_heights).
##
## Held actions are as the player's machine sampled them (a turned view's
## directions already turned, a stick's eighth already held); the game reads
## them through [MwStreamInput].
##
## Online (plan 35 work item 4) a tick also carries each player's network
## status ([member status]: here, LAGGING, DISCONNECTED, KICKED - the host
## decides it, MwNetMatch), so the CPU takes a silent machine's players on
## every machine at the same tick; offline it is always 0.

## Players with a stick (MwVerbs.PLAYERS).
const PLAYERS := MwVerbs.PLAYERS

static var _actions: Array[String] = []
static var _index := {}

## Actions held: bit i of byte i >> 3 for action i ([method actions]).
var held := PackedByteArray()
## Press counters, one byte per action.
var counts := PackedByteArray()
## Players 1-12's stick codes (MwStick).
var sticks := PackedInt32Array()
## Players 1-12's network status (plan 35: [constant HERE] ... [constant
## KICKED]); not cumulative - each tick says it whole.
var status := PackedByteArray()
## Plan 40 (S7, one input tick): the tick as the wire has it - players
## 1-12's states (MwNetInput, [constant MwNetInput.TICK_SIZE] bytes) and the
## shared menu verbs' ([constant MwNetInput.SHARED]: offline anyone's,
## online the host's player 1's) - offline and online captured the same way
## (MwNetInput.capture), the stream's stored form (MwInputStream format 3)
## and what the game can read a player's own input from (MwInputFrame.state).
## Empty on a tick made field by field (a format 1 / 2 stream's, [method
## fill]'s): [method states] works them out.
var wire := PackedByteArray()
var shared := PackedByteArray()
## Players 1-12's shot heights as their machine sampled them
## (MwInputSource.heights, by that machine's MwSettings.shot_heights and the
## player's layout), coded [method height_code]: 0 the D-pad lifts the shot
## (the original; the option off, the GENESIS layout, no player), 1 none
## (the middle height), 2 HIGH SHOT, 3 LOW SHOT.
var heights := PackedByteArray()

## [member status]' values: the player's machine is here; silent for 3 s
## (the CPU plays for them until it sends again); dropped (ENet's timeout);
## kicked by the host.
const HERE := 0
const LAGGING := 1
const DISCONNECTED := 2
const KICKED := 3
## What the screens show for each status.
const STATUS_TEXT := ["", "LAGGING", "DISCONNECTED", "KICKED"]


func _init() -> void:
	var n := actions().size()
	held.resize((n + 7) >> 3)
	counts.resize(n)
	sticks.resize(PLAYERS)
	status.resize(PLAYERS)
	heights.resize(PLAYERS)


## Every action the stream knows, in a fixed order (MwVerbs.all_actions:
## the shared menu verbs, then players 1-12's).
static func actions() -> Array[String]:
	if _actions.is_empty():
		_actions = MwVerbs.all_actions()
		for i in _actions.size():
			_index[_actions[i]] = i
	return _actions


## The index of [param action] in [method actions], -1 if the stream
## doesn't carry it.
static func index_of(action: String) -> int:
	actions()
	return int(_index.get(action, -1))


## The actions of slot [param slot] (0: the shared menu verbs, 1-12: that
## player's) as [first index, end index) - what one player's machine sends.
static func slot_range(slot: int) -> Vector2i:
	var shared_count := MwVerbs.menu_verbs().size()
	if slot <= 0:
		return Vector2i(0, shared_count)
	@warning_ignore("integer_division")
	var per := (actions().size() - shared_count) / PLAYERS
	return Vector2i(shared_count + (slot - 1) * per, shared_count + slot * per)


## Whether action [param i] ([method index_of]) is held.
func is_held(i: int) -> bool:
	return held[i >> 3] & (1 << (i & 7)) != 0


## Action [param i] held ([param on]) or let go.
func set_held(i: int, on: bool) -> void:
	if on:
		held[i >> 3] |= 1 << (i & 7)
	else:
		held[i >> 3] &= ~(1 << (i & 7))


## Action [param i] pressed once more (its counter wraps at 256).
func press(i: int) -> void:
	counts[i] = (counts[i] + 1) & 0xFF


## The held actions as the router's samples have them (action -> true).
func held_actions() -> Dictionary:
	var out := {}
	var names := actions()
	for b in held.size():
		var byte := held[b]
		if byte == 0:
			continue
		for k in 8:
			if byte & (1 << k):
				out[names[(b << 3) | k]] = true
	return out


## A tick that follows [param before]: its counters carried on, nothing
## held, no sticks, every shot height the D-pad's.
static func after(before: MwTickInput) -> MwTickInput:
	var tick_input := MwTickInput.new()
	if before != null:
		tick_input.counts = before.counts.duplicate()
	return tick_input


## Plan 40 (S7): the router's tick of an online match's stream tick
## [param t] (twelve MwNetInput states, the wire's form) - [method
## from_states] with the host's P1's menu verbs as the shared ones (online
## the host's P1 drives what any player drives offline).
static func from_wire(t: PackedByteArray) -> MwTickInput:
	return from_states(MwNetInput.player(t, 1), t)


## Plan 40 (S7, one input tick): the router's tick of twelve players' states
## [param t] and the shared menu verbs' [param shared_state] (MwNetInput):
## each player's verbs, counters, stick, status and shot height in their
## slot, the shared state's menu verbs in slot 0; both kept ([member wire],
## [member shared]).
static func from_states(shared_state: PackedByteArray, t: PackedByteArray) -> MwTickInput:
	if _menu_count < 0:
		_menu_count = MwVerbs.menu_verbs().size()
	var ti := MwTickInput.new()
	ti.wire = t.duplicate()
	ti.shared = shared_state.duplicate()
	var menu_first := MwNetInput.COUNT - _menu_count
	# the counters: slot 0's (the shared state's menu verbs), then every
	# player's slot as the wire has it (the same order)
	var press_counts := shared_state.slice(MwNetInput.COUNTERS + menu_first, MwNetInput.COUNTERS + MwNetInput.COUNT)
	for n in range(1, MwNetInput.PLAYERS + 1):
		var o := (n - 1) * MwNetInput.SIZE
		press_counts.append_array(t.slice(o + MwNetInput.COUNTERS, o + MwNetInput.COUNTERS + MwNetInput.COUNT))
		var first := _menu_count + (n - 1) * MwNetInput.COUNT
		for b in MwNetInput.HELD_BYTES:
			var byte: int = t[o + b]
			if b == MwNetInput.HELD_BYTES - 1:
				byte &= MwNetInput.LAST_HELD_MASK
			if byte == 0:
				continue
			for k in 8:
				if byte & (1 << k):
					ti.set_held(first + (b << 3) + k, true)
		var travel: int = t[o + MwNetInput.STICK + 1]
		ti.sticks[n - 1] = (t[o + MwNetInput.STICK] << 8) | travel if travel != 0 else MwStick.NONE
		ti.status[n - 1] = (t[o + MwNetInput.HELD_BYTES - 1] & MwNetInput.STATUS_BITS) >> MwNetInput.STATUS_SHIFT
		ti.heights[n - 1] = t[o + MwNetInput.HEIGHT] & 3
	ti.counts = press_counts
	# slot 0's held: the shared state's menu verbs
	for j in _menu_count:
		var v := menu_first + j
		if shared_state[v >> 3] & (1 << (v & 7)):
			ti.set_held(j, true)
	return ti


## [[member shared], [member wire]] - worked out from the fields for a tick
## made field by field (the states [method from_states] would make it from).
func states() -> Array:
	if wire.size() == MwNetInput.TICK_SIZE and shared.size() == MwNetInput.SIZE:
		return [shared, wire]
	if _menu_count < 0:
		_menu_count = MwVerbs.menu_verbs().size()
	var menu_first := MwNetInput.COUNT - _menu_count
	var sh := MwNetInput.blank()
	for j in _menu_count:
		var v := menu_first + j
		if is_held(j):
			sh[v >> 3] |= 1 << (v & 7)
		sh[MwNetInput.COUNTERS + v] = counts[j]
	var t := MwNetInput.blank_tick()
	for n in range(1, MwNetInput.PLAYERS + 1):
		var o := (n - 1) * MwNetInput.SIZE
		var first := _menu_count + (n - 1) * MwNetInput.COUNT
		for v in MwNetInput.COUNT:
			if is_held(first + v):
				t[o + (v >> 3)] |= 1 << (v & 7)
			t[o + MwNetInput.COUNTERS + v] = counts[first + v]
		var c := sticks[n - 1]
		if MwStick.travel(c) != 0:
			t[o + MwNetInput.STICK] = MwStick.angle(c)
			t[o + MwNetInput.STICK + 1] = MwStick.travel(c)
		t[o + MwNetInput.HELD_BYTES - 1] |= (status[n - 1] << MwNetInput.STATUS_SHIFT) & MwNetInput.STATUS_BITS
		t[o + MwNetInput.HEIGHT] = heights[n - 1] & 3
	return [sh, t]


static var _menu_count := -1


## The code of shot height [param h] (MwInputSource.heights: -1 the D-pad's,
## 0 none, 1 high, 2 low) in [member heights]: 0-3.
static func height_code(h: int) -> int:
	return clampi(h + 1, 0, 3)


## The shot height (-1 the D-pad's, 0 none, 1 high, 2 low) of [param code]
## ([method height_code]).
static func height_of(code: int) -> int:
	return (code & 3) - 1


## Filled field by field (the tests' helper - the game captures through
## MwNetInput.capture, plan 40 S7): [param held_now] (action -> true), the
## actions pressed this tick [param presses] (counted), the sticks' codes
## [param codes], the shot heights [param heights_now] (MwInputSource
## .heights; empty: the D-pad's for everyone). Actions the stream doesn't
## carry are left out.
func fill(held_now: Dictionary, presses: Dictionary, codes: PackedInt32Array, heights_now: Array = []) -> void:
	for a in held_now:
		var i := index_of(a)
		if i >= 0:
			set_held(i, true)
	for a in presses:
		var i := index_of(a)
		if i >= 0:
			press(i)
	for p in mini(codes.size(), PLAYERS):
		sticks[p] = codes[p]
	for p in mini(heights_now.size(), PLAYERS):
		heights[p] = height_code(int(heights_now[p]))


## The players whose [member status] isn't [constant HERE]: player ->
## status.
func away() -> Dictionary:
	var out := {}
	for p in status.size():
		if status[p] != HERE:
			out[p + 1] = int(status[p])
	return out


## Whether [param tick_input] carries the same held actions, counters, sticks,
## statuses and shot heights ([member wire] and [member shared] not compared;
## null: false).
func equals(tick_input: MwTickInput) -> bool:
	return tick_input != null and held == tick_input.held and counts == tick_input.counts \
			and sticks == tick_input.sticks and status == tick_input.status \
			and heights == tick_input.heights
