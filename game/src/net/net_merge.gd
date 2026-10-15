class_name MwNetMerge
extends RefCounted
## The host's merge (plan 35 section 3): each host tick, every player's
## input from the latest state their machine sent ([method feed]) - the
## host never waits for anyone. Node-free.
##
## * Held verbs, the stick and the shot height: the latest state's. A
##   player whose machine has sent nothing new for [constant HOLD_TICKS]
##   ticks goes neutral (nothing held, stick centred, the shot height the
##   D-pad's; "a silent machine", section 3) until it sends again; [method silent_ticks] tells the game how long (the
##   CPU takes over after 3 s, work item 4).
## * Presses: a changed counter in a machine's states is a press. The merge
##   counts them as they arrive and lets each verb's counter in the stream
##   advance by one a tick, so every press shows on a tick of its own - a
##   press is never lost, only late - even when a burst of a machine's
##   packets arrives at once after a loss. Every machine's states start
##   blank at the match's start ([method reset]), so presses count from
##   there; a new source of states for a player mid-match (a machine
##   rejoining, [method new_source]) starts counting from its first state,
##   so its counters never read as presses.

## * The status (work item 4): each player's network status (here, lagging,
##   disconnected, kicked: MwTickInput), as the host's game decides it
##   ([method set_status], MwNetMatch), goes into the stream in the held
##   bitset's spare bits (MwNetInput.status); whatever a machine put there
##   is overwritten.

## * Stamps (plan 43): with [member stamped] each machine's states come with
##   the host tick they are meant for ([method feed_at]: the client's own
##   reckoning of where its input lands, MwNetMatch.ahead_tick - the tick its
##   run-ahead shows them at) and wait for it: each tick ([method tick]) a
##   player's states due by then are taken in the order sent - the newest
##   the held input, the presses among them counted as any - and one come
##   too late is taken at once, as without stamps. A client's own input then
##   lands where it predicted it, not a tick either side as the packets
##   happen to arrive (owner, 2026-10-13: tried to see whether it helps).

## Ticks a player's last state lasts without news.
const HOLD_TICKS := 8
## Plan 43: ticks a stamped state may wait at most (a stamp further ahead
## waits this long), and states waiting at most for a player (more: the
## oldest taken at once).
const MAX_WAIT := 60
const MAX_QUEUE := 64
## Presses of one verb waiting at most (a flood of counter changes from a
## modified client can't queue more).
const MAX_PENDING := 16

var _last := MwNetInput.blank_tick()
var _active := PackedByteArray()
var _target: Array[PackedByteArray] = []
var _seen: Array[PackedByteArray] = []
var _sourced := PackedByteArray()
var _pending: Array[PackedInt32Array] = []
var _silent := PackedInt32Array()
var _status := PackedByteArray()
## Plan 43: states wait for their stamps ([method feed_at]); off, every
## state is taken as it comes.
var stamped := false
## Plan 43: stamped states' arrivals, per player number: {"on_time", "late",
## "slack": the sum of (stamp - the tick made next) of those on time}.
var stats := {}
var _queue: Array = []                  # per player: [[stamp, state] ...], in the order sent
var _at := 0                            # the tick the next [method tick] makes


func _init() -> void:
	reset()


## Forgets everything: every player blank and out of the match, every
## machine's counters starting from blank.
func reset() -> void:
	_last = MwNetInput.blank_tick()
	_active.resize(MwNetInput.PLAYERS)
	_active.fill(0)
	_sourced.resize(MwNetInput.PLAYERS)
	_sourced.fill(1)
	_silent.resize(MwNetInput.PLAYERS)
	_silent.fill(HOLD_TICKS)
	_status.resize(MwNetInput.PLAYERS)
	_status.fill(0)
	_target.clear()
	_seen.clear()
	_pending.clear()
	_queue.clear()
	stats = {}
	for i in MwNetInput.PLAYERS:
		_queue.append([])
		_target.append(MwNetInput.blank())
		_seen.append(MwNetInput.blank())
		var presses := PackedInt32Array()
		presses.resize(MwNetInput.COUNT)
		_pending.append(presses)


## The players in the match (player numbers 1-12); the others stay blank.
func set_players(numbers: Array) -> void:
	for i in MwNetInput.PLAYERS:
		_active[i] = 1 if (i + 1) in numbers else 0


## Whether player [param player] (1-12) is in the match ([method set_players]).
func is_active(player: int) -> bool:
	return _active[player - 1] == 1


## Player [param player]'s states come from a new source from now on: the
## next state's counters are its starting point, not presses.
func new_source(player: int) -> void:
	_sourced[player - 1] = 0
	(_queue[player - 1] as Array).clear()
	_silent[player - 1] = HOLD_TICKS


## A newer state of [param player]'s (from their machine's input, or the
## host's own players).
func feed(player: int, state: PackedByteArray) -> void:
	var i := player - 1
	if i < 0 or i >= MwNetInput.PLAYERS or state.size() != MwNetInput.SIZE:
		return
	_take(i, state)
	_silent[i] = 0


## Plan 43: a state of [param player]'s meant for host tick [param stamp]
## (-1: none - as [method feed]). With [member stamped] it waits for that
## tick (at most [constant MAX_WAIT]); a state due before the tick made next
## (late) is taken by it - every state in the order sent. Its arrival is
## news at once ([method silent_ticks]), whenever it is taken.
func feed_at(player: int, state: PackedByteArray, stamp: int) -> void:
	var i := player - 1
	if not stamped or stamp < 0 or i < 0 or i >= MwNetInput.PLAYERS or state.size() != MwNetInput.SIZE:
		feed(player, state)
		return
	_silent[i] = 0
	var st: Dictionary = stats.get(player, {"on_time": 0, "late": 0, "slack": 0})
	if stamp < _at:
		st["late"] += 1
	else:
		st["on_time"] += 1
		st["slack"] += stamp - _at
	stats[player] = st
	var queue: Array = _queue[i]
	queue.append([mini(stamp, _at + MAX_WAIT), state])
	if queue.size() > MAX_QUEUE:
		_take(i, (queue.pop_front() as Array)[1])


## A state of player index [param i]'s taken: its presses counted (since the
## last taken), the held input its.
func _take(i: int, state: PackedByteArray) -> void:
	if _sourced[i] == 1:
		var seen := _seen[i]
		var pend := _pending[i]
		for v in MwNetInput.COUNT:
			var c := MwNetInput.COUNTERS + v
			var d := (state[c] - seen[c]) & 0xFF
			if d != 0:
				pend[v] = mini(pend[v] + d, MAX_PENDING)
		_pending[i] = pend
	_sourced[i] = 1
	_seen[i] = state
	_target[i] = state


## Player [param player]'s network status from the next tick on (0-3,
## MwTickInput.HERE ...).
func set_status(player: int, code: int) -> void:
	if player >= 1 and player <= MwNetInput.PLAYERS:
		_status[player - 1] = clampi(code, 0, 3)


## Player [param player]'s network status as last set ([method set_status]: 0-3).
func status_of(player: int) -> int:
	return _status[player - 1]


## Ticks since [param player]'s last state ([constant HOLD_TICKS] and more:
## neutral).
func silent_ticks(player: int) -> int:
	return _silent[player - 1]


## Presses of [param player]'s still to come into the stream.
func pending(player: int) -> int:
	var n := 0
	for v in _pending[player - 1]:
		n += v
	return n


## The next tick of the stream ([param at]: its number, plan 43's stamps -
## -1: the one after the last).
func tick(at := -1) -> PackedByteArray:
	if at >= 0:
		_at = at
	if stamped:
		for i in MwNetInput.PLAYERS:
			var queue: Array = _queue[i]
			while not queue.is_empty() and int(queue[0][0]) <= _at:
				_take(i, (queue.pop_front() as Array)[1])
	_at += 1
	var out := PackedByteArray()
	for i in MwNetInput.PLAYERS:
		var o := i * MwNetInput.SIZE
		var bytes := _last.slice(o, o + MwNetInput.SIZE)
		if _active[i] == 0:
			out.append_array(MwNetInput.blank())
			continue
		var t := _target[i] if _silent[i] < HOLD_TICKS else MwNetInput.blank()
		for b in MwNetInput.HELD_BYTES:
			bytes[b] = t[b]
		var last_held := MwNetInput.HELD_BYTES - 1
		bytes[last_held] = (t[last_held] & MwNetInput.LAST_HELD_MASK) | (_status[i] << MwNetInput.STATUS_SHIFT)
		bytes[MwNetInput.STICK] = t[MwNetInput.STICK]
		bytes[MwNetInput.STICK + 1] = t[MwNetInput.STICK + 1]
		bytes[MwNetInput.HEIGHT] = t[MwNetInput.HEIGHT]
		var pend := _pending[i]
		for v in MwNetInput.COUNT:
			if pend[v] > 0:
				pend[v] -= 1
				var c := MwNetInput.COUNTERS + v
				bytes[c] = (bytes[c] + 1) & 0xFF
		_pending[i] = pend
		_silent[i] = mini(_silent[i] + 1, 1 << 30)
		out.append_array(bytes)
	_last = out
	return out


## The last tick made.
func last() -> PackedByteArray:
	return _last
