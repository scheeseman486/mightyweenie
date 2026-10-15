class_name MwNetPace
extends RefCounted
## How often the host sends one machine its stream (docs/net.md "A slow
## uplink"): every tick, or every second tick while the line is full.
## Node-free; [MwNetHost] keeps one for each machine.
##
## A full line shows as a queue: each datagram waits its turn in a router's
## buffer, so the round trip stands above what it was on the idle line. The
## round trip here is the stream's own: from the step a STREAM went out in to
## the INPUT that acknowledged its newest tick ([method sent], [method
## acked]) - a sample a frame, no traffic of its own. Its lowest value in each
## window of [constant WINDOW_MS] and [constant WINDOW_SAMPLES] samples counts
## (a busy frame or a screen being made on either machine, or a gap waiting
## for a resend, doesn't last a whole window; a queue does), set against the
## floor: the lowest window of the last half minute to minute. Two windows in
## a row [constant QUEUE_MS] or more above it, or one twice that: a STREAM
## every second tick ([member stride] 2) - half the datagrams, about half the
## host's upload; each STREAM still carries the last 8 ticks, so a tick goes
## out 4 times instead of 8. Back to every tick once the queue has stayed
## under [constant CLEAR_MS] for [constant BACK_MS]; each time that proves
## too early (slowed again within [constant RELAPSE_MS]) the wait doubles,
## up to [constant BACK_MAX_MS].
##
## ENet's packet throttle would drop datagrams on a full line too, but it
## can't see one in a match: it takes its round trips from the reliable
## messages' acknowledgements, a few a minute once the stream flows
## (MwNetEnet.THROTTLE).

## The lowest round trip of each window this long (ms) counts ...
const WINDOW_MS := 500
## ... a window of this many samples at least (after a stretch without any -
## the stream stuck at a gap - the late ones alone are no window).
const WINDOW_SAMPLES := 8
## A queue this long (ms above the floor) two windows in a row, or twice
## this long in one: every second tick.
const QUEUE_MS := 50
## A queue under this long: the line is clear.
const CLEAR_MS := 20
## The floor is the lowest window of this long (ms) and of the one before.
const FLOOR_MS := 30000
## Clear this long (ms): every tick again - the first time; doubled after
## each relapse, up to [constant BACK_MAX_MS].
const BACK_MS := 10000
const BACK_MAX_MS := 80000
## Slowed again within this long (ms) of going back to every tick: a relapse.
const RELAPSE_MS := 30000
## Packets kept waiting for their acknowledgement.
const KEEP := 64

## A STREAM every this many ticks (1 or 2).
var stride := 1
## The last window's queue (ms above the floor; -1 before the first).
var queue_ms := -1
## The last round trip measured (ms; -1 before the first).
var round_trip := -1
## For the soak and the tests: times slowed down, ms spent slowed (to the
## last window), the longest queue seen (ms).
var stats := {"slowed": 0, "slow_ms": 0, "queue_max_ms": 0}

var _sent: Array = []                      # [newest tick, ms] of each packet sent, oldest first
var _win_start := -1
var _win_min := -1
var _win_n := 0
var _floor := -1                           # the lowest window since _floor_start
var _floor_last := -1                      # ... and of the FLOOR_MS before
var _floor_start := -1
var _queued := 0                           # windows in a row with a queue
var _clear_since := -1
var _back := BACK_MS
var _changed_at := -1                      # when the stride last changed
var _last_window := -1


## A STREAM whose newest tick is [param newest] went out at [param now_ms].
func sent(newest: int, now_ms: int) -> void:
	if not _sent.is_empty() and int(_sent[-1][0]) >= newest:
		return
	_sent.append([newest, now_ms])
	if _sent.size() > KEEP:
		_sent.pop_front()


## The machine acknowledged tick [param ack] - it holds it and every tick
## before - at [param now_ms]: a round trip, the newest packet it covers.
func acked(ack: int, now_ms: int) -> void:
	var at := -1
	while not _sent.is_empty() and int(_sent[0][0]) <= ack:
		at = int(_sent.pop_front()[1])
	if at >= 0:
		sample(now_ms - at, now_ms)


## The packets waiting for an acknowledgement are let go (the machine's
## stream starts again: a resync snapshot).
func forget() -> void:
	_sent.clear()


## A round trip of [param rtt_ms] measured at [param now_ms].
func sample(rtt_ms: int, now_ms: int) -> void:
	round_trip = rtt_ms
	if _win_n == 0:
		_win_start = now_ms
	_win_min = rtt_ms if _win_n == 0 else mini(_win_min, rtt_ms)
	_win_n += 1
	if now_ms - _win_start >= WINDOW_MS and _win_n >= WINDOW_SAMPLES:
		_window(_win_min, now_ms)
		_win_n = 0


## A window's lowest round trip [param low]: the queue, and the stride.
func _window(low: int, now_ms: int) -> void:
	if _floor_start < 0 or now_ms - _floor_start >= FLOOR_MS:
		_floor_last = _floor
		_floor = -1
		_floor_start = now_ms
	_floor = low if _floor < 0 else mini(_floor, low)
	queue_ms = low - (_floor if _floor_last < 0 else mini(_floor, _floor_last))
	stats["queue_max_ms"] = maxi(int(stats["queue_max_ms"]), queue_ms)
	if stride == 2 and _last_window >= 0:
		stats["slow_ms"] += now_ms - _last_window
	_last_window = now_ms
	_queued = _queued + 1 if queue_ms >= QUEUE_MS else 0
	if queue_ms >= CLEAR_MS:
		_clear_since = -1
	elif _clear_since < 0:
		_clear_since = now_ms
	if stride == 1 and (_queued >= 2 or queue_ms >= 2 * QUEUE_MS):
		if _changed_at >= 0 and now_ms - _changed_at < RELAPSE_MS:
			_back = mini(2 * _back, BACK_MAX_MS)      # back too early: wait longer next time
		else:
			_back = BACK_MS
		stride = 2
		_changed_at = now_ms
		stats["slowed"] += 1
	elif stride == 2 and _clear_since >= 0 and now_ms - _clear_since >= _back:
		stride = 1
		_changed_at = now_ms
