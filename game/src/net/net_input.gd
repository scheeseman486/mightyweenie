class_name MwNetInput
extends RefCounted
## One player's input as the network carries it, and a tick of them (plan
## 35 section 3, "The stream"): the held verbs as a bitset, a press counter
## per verb (8 bits, wrapping: a changed counter is a press - never lost,
## only late), the skating stick quantised to two bytes and the shot height
## (MwTickInput.heights' code). Nothing here is
## a node; the stream's encoders ([MwNetTickLog], [MwNetTickReceiver]) and
## the host's merge ([MwNetMerge]) work on these byte arrays.
##
## A player's state is [constant SIZE] bytes:
## [codeblock]
##   0 .. 6     held verbs: verb i is bit (i & 7) of byte (i >> 3)
##   7 .. 60    press counters, one byte per verb (VERBS order)
##   61         the stick's angle (0-255: 256 steps a turn)
##   62         the stick's travel (0: centred - 255: full)
##   63         the shot height's code (0-3: MwTickInput.height_code)
## [/codeblock]
## A tick is the twelve players' states end to end (player n at
## (n - 1) * SIZE); a player not in the match stays blank (all zero).
##
## The verbs are every per-player verb of [MwVerbs] - gameplay, fight,
## replay, the Zamboni, RECLAIM, the shot heights, then the menu verbs each
## player has a form
## of (`p2_ui_left`) - but not the 2D / 3D view switch, which only draws
## (section 3, Views). [constant VERBS] is the wire's order: a new verb in
## MwVerbs fails test_net_input until it is added here, and adding one
## changes [method schema], so machines with different tables refuse each
## other at the handshake (MwNetProtocol, HELLO).
##
## The shot height (MwSettings.shot_heights): the player's machine decides
## it by its own setting and the player's layout (MwLiveInput.heights) and
## sends its code ([constant HEIGHT]: 0 the D-pad lifts the shot, the
## original's; 1 none, 2 high, 3 low) - the game reads it, not the HIGH /
## LOW SHOT verbs' bits, so the option is each machine's own (local, as
## ANALOG CONTROL). A code above 3 is malformed.
##
## The status (plan 35 work item 4): two bits past the verbs in the held
## bitset's last byte ([constant STATUS_BITS]) carry the player's network
## status in the host's stream (MwTickInput.HERE, LAGGING, DISCONNECTED,
## KICKED): the host decides it ([MwNetMerge.set_status]) and every
## machine's game reads it at the same tick. A machine's own states leave
## them 0; the merge overwrites whatever comes.
##
## Deltas: a state is coded as its change from a base state (the same
## player's previous tick, or the tick the receiver acknowledged): a flags
## byte then the parts that changed - the held bitset whole, the changed
## counters (verb, value pairs, or all of them when that is shorter), the
## stick, the shot height. A tick codes a 16-bit mask of the players that
## changed, then their deltas; an unchanged tick is two bytes.
## Short names: w the byte writer (MwNetBytes.Writer).

const VERBS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right", "punch", "dive", "special_play",
	"pass", "release_puck", "change_player", "wrist_shot", "slap_shot", "check", "pause",
	"fight_block", "fight_punch", "fight_pause", "replay_rewind", "replay_slow", "replay_play",
	"replay_exit", "zamboni_whip", "reclaim", "shot_high", "shot_low",
	"ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_delete", "ui_keep", "ui_back",
	"ui_skip", "ui_info_return", "ui_next_page", "ui_new_playoffs", "ui_starfield_stop",
	"ui_starfield_turn", "ui_password_done", "ui_pick_letter", "ui_erase_letter", "ui_cancel",
	"ui_resume", "ui_pause_replay", "ui_pause_timeout", "ui_view_stats", "ui_view_special_plays",
	"ui_view_replay", "ui_stats_switch", "ui_plays_done", "ui_nasty_play", "ui_choose_play",
	"ui_phony_play",
]
const COUNT := 54
const HELD_BYTES := 7
## The held bitset's last byte: the verbs' bits ([constant STATUS_BITS]
## past them).
const LAST_HELD_MASK := 0x3F
## The status' two bits in the held bitset's last byte (work item 4), and
## their shift.
const STATUS_BITS := 0xC0
const STATUS_SHIFT := 6
const COUNTERS := 7
const STICK := 61
## The shot height's code (0-3; MwTickInput.height_code).
const HEIGHT := 63
const SIZE := 64
const PLAYERS := MwVerbs.PLAYERS
const TICK_SIZE := PLAYERS * SIZE
## Plan 40 (S7): the shared slot - the menu verbs anyone drives offline
## (their own names, `ui_left`), a state like a player's (MwTickInput.shared;
## online the host's player 1's).
const SHARED := 0
## Every player's bit in a tick's player mask (player n: bit n - 1).
const ALL_PLAYERS := 0xFFF

## Delta flags.
const D_HELD := 1
const D_SPARSE := 2
const D_DENSE := 4
const D_STICK := 8
const D_HEIGHT := 16

static var _index := {}


## A blank state: nothing held, every counter 0, the stick centred, the
## shot height the D-pad's.
static func blank() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE)
	return bytes


## A blank tick (every player blank).
static func blank_tick() -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(TICK_SIZE)
	return t


## The wire index of [param verb] (-1: not carried).
static func index_of(verb: String) -> int:
	if _index.is_empty():
		for i in VERBS.size():
			_index[VERBS[i]] = i
	return int(_index.get(verb, -1))


## A 32-bit number naming this table and layout: two machines must agree.
static func schema() -> int:
	var h := ("%d|%s|status2|height%d" % [SIZE, ",".join(VERBS), HEIGHT]).sha256_buffer()
	return (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]


## Whether player state [param state] holds verb [param verb] (its wire index, [method index_of]).
static func is_held(state: PackedByteArray, verb: int) -> bool:
	return state[verb >> 3] & (1 << (verb & 7)) != 0


## Verb [param verb]'s press counter (8 bits, wrapping) in player state [param state].
static func counter(state: PackedByteArray, verb: int) -> int:
	return state[COUNTERS + verb]


## The player's network status in a stream's state (0-3, MwTickInput.HERE
## ...).
static func status(state: PackedByteArray) -> int:
	return (state[HELD_BYTES - 1] & STATUS_BITS) >> STATUS_SHIFT


## [param state] with its status [param code] (0-3).
static func with_status(state: PackedByteArray, code: int) -> PackedByteArray:
	var bytes := state.duplicate()
	bytes[HELD_BYTES - 1] = (bytes[HELD_BYTES - 1] & ~STATUS_BITS) | ((code << STATUS_SHIFT) & STATUS_BITS)
	return bytes


## The stick: x = angle (0-255), y = travel (0-255).
static func stick(state: PackedByteArray) -> Vector2i:
	return Vector2i(state[STICK], state[STICK + 1])


## The shot height's code (0-3: MwTickInput.height_code).
static func height(state: PackedByteArray) -> int:
	return state[HEIGHT]


## The verbs held in [param state].
static func held_verbs(state: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in COUNT:
		if is_held(state, v):
			out.append(v)
	return out


## The verbs pressed between [param before] and [param after] (their
## counters differ; [method presses] says how many times).
static func pressed_verbs(before: PackedByteArray, after: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in COUNT:
		if before[COUNTERS + v] != after[COUNTERS + v]:
			out.append(v)
	return out


## How many presses of [param verb] lie between two states (counters wrap).
static func presses(before: PackedByteArray, after: PackedByteArray, verb: int) -> int:
	return (after[COUNTERS + verb] - before[COUNTERS + verb]) & 0xFF


## The next local state after [param prev]: [param held] the verbs held now,
## [param pressed] those newly pressed since [param prev] (each counts one
## press, wrapping at 256), [param stick_v] the quantised stick (angle,
## travel; travel 0 keeps the angle 0 so a centred stick has one form),
## [param height_code] the shot height (0-3, MwTickInput.height_code; 0 the
## D-pad's).
static func next_state(prev: PackedByteArray, held: PackedInt32Array, pressed: PackedInt32Array,
		stick_v := Vector2i.ZERO, height_code := 0) -> PackedByteArray:
	var bytes := prev.duplicate()
	for i in HELD_BYTES:
		bytes[i] = 0
	for v in held:
		if v >= 0 and v < COUNT:
			bytes[v >> 3] |= 1 << (v & 7)
	for v in pressed:
		if v >= 0 and v < COUNT:
			bytes[COUNTERS + v] = (bytes[COUNTERS + v] + 1) & 0xFF
	var travel := clampi(stick_v.y, 0, 255)
	bytes[STICK] = clampi(stick_v.x, 0, 255) if travel > 0 else 0
	bytes[STICK + 1] = travel
	bytes[HEIGHT] = clampi(height_code, 0, 3)
	return bytes


## [method next_state] from a player's action names (MwInputFrame's held and
## pressed dictionaries) for [param p]: each carried verb's
## [method MwVerbs.player_action] ([method action_names]). An online
## machine's players each tick (MwNetMatch._sample_local) and the tests'.
static func from_actions(prev: PackedByteArray, p: int, held_actions: Dictionary,
		pressed_actions: Dictionary, stick_v := Vector2i.ZERO, height_code := 0) -> PackedByteArray:
	var names := action_names(p)
	var held := PackedInt32Array()
	var pressed := PackedInt32Array()
	for v in COUNT:
		if held_actions.has(names[v]):
			held.append(v)
		if pressed_actions.has(names[v]):
			pressed.append(v)
	return next_state(prev, held, pressed, stick_v, height_code)


## Player [param p]'s action name of each carried verb, in
## [constant VERBS]' order (made once a player). [constant SHARED]: the
## menu verbs' own names, nothing for the others.
static func action_names(p: int) -> PackedStringArray:
	if not _names.has(p):
		var a := PackedStringArray()
		for v in VERBS:
			if p == SHARED:
				a.append(v if v.begins_with("ui_") else "")
			else:
				a.append(MwVerbs.player_action(p, v))
		_names[p] = a
	return _names[p]


## Plan 40 (S7, one input tick): what [param source] gives this tick in
## [param contexts] (the screen's) - the actions held, those pressed since
## the last tick, the sticks' codes, the shot heights - for [method capture].
## The one sampling of a machine's devices, offline (MwStreamInput) and
## online (MwNetMatch._sample_local) alike.
static func sample_of(source: MwInputSource, contexts: Array) -> Dictionary:
	source.tick()
	return {"held": source.sample(contexts), "taps": source.taps(), "codes": source.stick_codes(),
			"heights": source.heights()}


## Plan 40 (S7, one input tick): device slot [param k]'s state this tick
## after [param prev], from [param sample] ([method sample_of]): the verbs held
## and newly pressed by slot k's names ([method action_names]; k
## [constant SHARED]: the shared menu verbs), its stick (the k-th code,
## MwStick) and its shot height (the k-th, MwTickInput.height_code). Offline
## every slot is captured (MwStreamInput); online this machine's players
## (k their local pad). A new per-player input is sampled in [method
## sample_of], laid out in the state ([constant SIZE]) and coded with it,
## here.
static func capture(prev: PackedByteArray, k: int, sample: Dictionary) -> PackedByteArray:
	var codes: PackedInt32Array = sample.get("codes", PackedInt32Array())
	var heights: Array = sample.get("heights", [])
	var code := codes[k - 1] if k >= 1 and k <= codes.size() else MwStick.NONE
	var hc := MwTickInput.height_code(int(heights[k - 1])) if k >= 1 and k <= heights.size() else 0
	return from_actions(prev, k, sample.get("held", {}), sample.get("taps", {}),
			Vector2i(MwStick.angle(code), MwStick.travel(code)), hc)


static var _names := {}


## Player [param n]'s (1-12) state in [param tick].
static func player(tick: PackedByteArray, n: int) -> PackedByteArray:
	return tick.slice((n - 1) * SIZE, n * SIZE)


## A tick from twelve states (index 0 = player 1; missing ones blank).
static func make_tick(states: Array) -> PackedByteArray:
	var t := PackedByteArray()
	for i in PLAYERS:
		var bytes: PackedByteArray = states[i] if i < states.size() else PackedByteArray()
		if bytes.size() == SIZE:
			t.append_array(bytes)
		else:
			t.append_array(blank())
	return t


## [param tick] with player [param n]'s state replaced by [param state].
static func with_player(tick: PackedByteArray, n: int, state: PackedByteArray) -> PackedByteArray:
	var t := tick.duplicate()
	var o := (n - 1) * SIZE
	for i in SIZE:
		t[o + i] = state[i]
	return t


# --- deltas ---------------------------------------------------------------------------------------

## Writes [param state] as a change from [param base] (both [constant SIZE]
## bytes; [param bo] / [param so] are where the state starts in each array,
## so a tick's players are coded without slicing).
static func write_delta(w: MwNetBytes.Writer, base: PackedByteArray, state: PackedByteArray,
		bo := 0, so := 0) -> void:
	var flags := 0
	for i in HELD_BYTES:
		if base[bo + i] != state[so + i]:
			flags |= D_HELD
			break
	var changed := PackedInt32Array()
	for v in COUNT:
		if base[bo + COUNTERS + v] != state[so + COUNTERS + v]:
			changed.append(v)
	if not changed.is_empty():
		flags |= D_SPARSE if 1 + 2 * changed.size() < COUNT else D_DENSE
	if base[bo + STICK] != state[so + STICK] or base[bo + STICK + 1] != state[so + STICK + 1]:
		flags |= D_STICK
	if base[bo + HEIGHT] != state[so + HEIGHT]:
		flags |= D_HEIGHT
	w.u8(flags)
	if flags & D_HELD:
		for i in HELD_BYTES:
			w.u8(state[so + i])
	if flags & D_SPARSE:
		w.u8(changed.size())
		for v in changed:
			w.u8(v)
			w.u8(state[so + COUNTERS + v])
	elif flags & D_DENSE:
		for v in COUNT:
			w.u8(state[so + COUNTERS + v])
	if flags & D_STICK:
		w.u8(state[so + STICK])
		w.u8(state[so + STICK + 1])
	if flags & D_HEIGHT:
		w.u8(state[so + HEIGHT])


## Reads a [method write_delta] into [param out] at [param o] (which holds
## the base state there); false when malformed (unknown flags, both counter
## forms, a verb out of range or out of order, held bits past the table and
## the status, a shot height's code above 3).
static func read_delta_into(reader: MwNetBytes.Reader, out: PackedByteArray, o: int) -> bool:
	var flags := reader.u8()
	if not reader.ok or flags & ~0x1F != 0 or (flags & D_SPARSE != 0 and flags & D_DENSE != 0):
		reader.ok = false
		return false
	if flags & D_HELD:
		var h := reader.bytes(HELD_BYTES)
		if not reader.ok or h[HELD_BYTES - 1] & ~(LAST_HELD_MASK | STATUS_BITS) != 0:
			reader.ok = false
			return false
		for i in HELD_BYTES:
			out[o + i] = h[i]
	if flags & D_SPARSE:
		var n := reader.u8_in(1, COUNT)
		var last := -1
		for k in n:
			var v := reader.u8()
			var c := reader.u8()
			if not reader.ok or v <= last or v >= COUNT:
				reader.ok = false
				return false
			last = v
			out[o + COUNTERS + v] = c
	elif flags & D_DENSE:
		var b := reader.bytes(COUNT)
		if not reader.ok:
			return false
		for v in COUNT:
			out[o + COUNTERS + v] = b[v]
	if flags & D_STICK:
		out[o + STICK] = reader.u8()
		out[o + STICK + 1] = reader.u8()
	if flags & D_HEIGHT:
		var hc := reader.u8()
		if not reader.ok or hc > 3:
			reader.ok = false
			return false
		out[o + HEIGHT] = hc
	return reader.ok


## Writes [param tick] as a change from [param base] (two ticks): the mask
## of changed players, then each one's delta.
static func write_tick(w: MwNetBytes.Writer, base: PackedByteArray, tick: PackedByteArray) -> void:
	var mask := 0
	for p in PLAYERS:
		var o := p * SIZE
		for i in SIZE:
			if base[o + i] != tick[o + i]:
				mask |= 1 << p
				break
	w.u16(mask)
	for p in PLAYERS:
		if mask & (1 << p):
			write_delta(w, base, tick, p * SIZE, p * SIZE)


## The bytes of [method write_tick].
static func encode_tick(base: PackedByteArray, tick: PackedByteArray) -> PackedByteArray:
	var w := MwNetBytes.Writer.new()
	write_tick(w, base, tick)
	return w.data


## Reads a [method write_tick] against [param base]; empty when malformed
## or when it changes a player outside [param allowed] (a player mask: a
## machine may only send its own players, a stream only the match's).
static func read_tick(reader: MwNetBytes.Reader, base: PackedByteArray, allowed := ALL_PLAYERS) -> PackedByteArray:
	var mask := reader.u16()
	if not reader.ok or mask & ~allowed != 0:
		reader.ok = false
		return PackedByteArray()
	var t := base.duplicate()
	for p in PLAYERS:
		if mask & (1 << p) and not read_delta_into(reader, t, p * SIZE):
			return PackedByteArray()
	return t
