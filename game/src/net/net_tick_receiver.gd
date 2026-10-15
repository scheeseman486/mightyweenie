class_name MwNetTickReceiver
extends RefCounted
## The receiving side of a numbered run of ticks ([MwNetTickLog]; plan 35
## section 3): a client rebuilds the host's stream with it, the host each
## machine's input states. Node-free.
##
## Packets decode against a tick it holds (or blank), in any order and
## any number of times; [member confirmed] is the newest tick held with
## every tick before it - a client runs a tick only once it is confirmed.
## A gap the repeated ticks won't fill (lost packets) is asked for again
## ([method resend_request]) - once: the request and its answer travel the
## reliable channel, so asking again only queues duplicates in front of
## later answers; only a request unanswered for [constant RESEND_PATIENCE_MS]
## (or 4 round trips) is repeated. With [member skip_gaps] (the host's
## inputs, which only use each player's latest state) the confirmed tick
## simply follows the newest.
##
## Everything is checked: a packet that doesn't decode, reaches too far
## ahead, changes players outside [member allowed] or contradicts a tick
## already held is BAD - the session drops its sender (section 6). But for
## a stream (not [member skip_gaps]) stuck at a gap, ticks past the window
## are FAR (work item 6): the sender went on far past what we hold, the gap
## can't be filled in time - [member lost], and a resync snapshot starts the
## run again ([method skip_to]).

enum Result { OK, NO_BASE, BAD, FAR }
const RING := 512
## How far past the confirmed tick a packet may reach.
const WINDOW := 1024
## A gap waits this long for the repeated ticks before a resend is asked.
const GAP_WAIT_MS := 50
## At most one resend request this often.
const RESEND_EVERY_MS := 120
## A request still unanswered after this long (or 4 round trips) is made
## again.
const RESEND_PATIENCE_MS := 1000
## Requests for the same gap before it counts as lost for good (the match
## then needs a resync snapshot: work item 6, MwNetMatch asks with RESYNC).
const MAX_TRIES := 12

## Players a packet may change (a player mask, MwNetInput.ALL_PLAYERS).
var allowed := MwNetInput.ALL_PLAYERS
var skip_gaps := false
## The first tick this receiver needs (the tick before it is blank).
var floor_no := 0
var confirmed := -1
var newest := -1
## A gap asked for [constant MAX_TRIES] times without coming: lost.
var lost := false
## Counters for tests and the soak's report.
var stats := {"packets": 0, "no_base": 0, "bad": 0, "requests": 0, "far": 0}
var _ticks := {}
var _advances := PackedInt32Array()      # how far the newest tick moved, the last packets that moved it
var _gap_since := -1
var _gap_at := -2
var _last_request := -1000000
var _tries := 0
var _asked := Vector2i(-1, -1)


func _init(first_no := 0) -> void:
	start(first_no)


## Starts receiving a run at tick [param first_no].
func start(first_no: int) -> void:
	floor_no = first_no
	confirmed = first_no - 1
	newest = first_no - 1
	lost = false
	_ticks.clear()
	_advances.clear()
	_gap_since = -1
	_gap_at = -2
	_tries = 0
	_asked = Vector2i(-1, -1)


## Work item 6: the run starts again at tick [param first_no] - a resync
## snapshot's, sent with the stream from that tick: the ticks before it
## are let go, those held from it on kept (confirmed again from it), and
## the gap's requests forgotten, a [member lost] one included.
func skip_to(first_no: int) -> void:
	floor_no = first_no
	for n in _ticks.keys():
		if n < first_no:
			_ticks.erase(n)
	newest = maxi(newest, first_no - 1)
	confirmed = first_no - 1
	if skip_gaps:
		confirmed = newest
	else:
		while _ticks.has(confirmed + 1):
			confirmed += 1
	lost = false
	_gap_since = -1
	_gap_at = -2
	_tries = 0
	_asked = Vector2i(-1, -1)


## The acknowledgement to send back: the newest tick held with all before
## it ([constant MwNetProtocol.NONE] before the first).
func ack() -> int:
	return confirmed if confirmed >= floor_no else MwNetProtocol.NONE


## Whether tick [param n] is held.
func has(n: int) -> bool:
	return _ticks.has(n)


## Tick [param n] (empty when not held).
func get_tick(n: int) -> PackedByteArray:
	return _ticks[n] if _ticks.has(n) else PackedByteArray()


## The newest tick held (empty before any).
func latest() -> PackedByteArray:
	return get_tick(newest)


## How many new ticks a packet brings, lately: 1, or 2 while the sender
## sends every second tick (the host on a full line, [MwNetPace]) - most of
## the last 8 packets that brought any brought two or more. A client's
## buffer lets its lead swing that much (MwNetMatch).
func step() -> int:
	var big := 0
	for a in _advances:
		if a >= 2:
			big += 1
	return 2 if big * 2 > _advances.size() else 1


## Takes a packet's ticks: [param count] ticks from [param first_no] coded
## from [param base] ([constant MwNetProtocol.NONE]: blank). A [enum
## Result].
func receive(base: int, first_no: int, count: int, body: PackedByteArray) -> int:
	stats["packets"] += 1
	var last := first_no + count - 1
	var reach := newest if skip_gaps else confirmed
	if count >= 1 and last > reach + WINDOW and not skip_gaps and newest > confirmed:
		lost = true                               # stuck at a gap the sender has long gone past
		stats["far"] += 1
		return Result.FAR
	if count < 1 or last > reach + WINDOW:
		stats["bad"] += 1
		return Result.BAD
	var prev: PackedByteArray
	if base == MwNetProtocol.NONE:
		prev = MwNetInput.blank_tick()
	elif _ticks.has(base):
		prev = _ticks[base]
	else:
		stats["no_base"] += 1
		return Result.NO_BASE
	var reader := MwNetBytes.Reader.new(body)
	var got: Array[PackedByteArray] = []
	for i in count:
		var t := MwNetInput.read_tick(reader, prev, allowed)
		if t.is_empty():
			stats["bad"] += 1
			return Result.BAD
		got.append(t)
		prev = t
	if not reader.done():
		stats["bad"] += 1
		return Result.BAD
	var before := newest
	for i in count:
		var n := first_no + i
		if n < floor_no or n <= newest - RING:
			continue
		if _ticks.has(n):
			if _ticks[n] != got[i]:
				stats["bad"] += 1
				return Result.BAD
			continue
		_ticks[n] = got[i]
		newest = maxi(newest, n)
	if newest > before:
		_advances.append(newest - before)
		if _advances.size() > 8:
			_advances.remove_at(0)
	if skip_gaps:
		confirmed = newest
	else:
		while _ticks.has(confirmed + 1):
			confirmed += 1
	for n in _ticks.keys():
		if n <= newest - RING:
			_ticks.erase(n)
	return Result.OK


## The ticks to ask for again now ([param now_ms]; [param rtt_ms] the round
## trip, 0 if unknown): Vector2i(from, to), or (-1, -1). A gap is asked for
## once it has waited [constant GAP_WAIT_MS] or lies further back than the
## repeated ticks reach; a gap an earlier request covers waits for its
## answer for [constant RESEND_PATIENCE_MS] (or 4 round trips); at most one
## request every [constant RESEND_EVERY_MS].
func resend_request(now_ms: int, rtt_ms := 0) -> Vector2i:
	if skip_gaps or newest <= confirmed:
		_gap_since = -1
		return Vector2i(-1, -1)
	if _gap_at != confirmed:
		_gap_at = confirmed
		_gap_since = now_ms
		_tries = 0
	var due := now_ms - _gap_since >= GAP_WAIT_MS or newest - confirmed > MwNetProtocol.MAX_TICKS
	if not due or now_ms - _last_request < RESEND_EVERY_MS:
		return Vector2i(-1, -1)
	var from := confirmed + 1
	if from >= _asked.x and from <= _asked.y and now_ms - _last_request < maxi(RESEND_PATIENCE_MS, 4 * rtt_ms):
		return Vector2i(-1, -1)
	var to := from
	while to + 1 < newest and not _ticks.has(to + 1) and to + 1 - from < MwNetProtocol.MAX_RESEND:
		to += 1
	_last_request = now_ms
	_asked = Vector2i(from, to)
	_tries += 1
	if _tries > MAX_TRIES:
		lost = true
	stats["requests"] += 1
	return Vector2i(from, to)
