class_name MwNetTickLog
extends RefCounted
## The sending side of a numbered run of ticks (plan 35 section 3, "The
## stream"): the host's merged stream (numbered by host tick) and a
## client's own players' input states (numbered by the client's sequence)
## both go out this way. Node-free; [MwNetTickReceiver] is the other end.
##
## Each packet repeats the newest ticks ([constant MwNetProtocol.MAX_TICKS])
## coded as changes ([MwNetInput.write_tick]): the first from the tick the
## receiver last acknowledged - which it holds - or from blank, each next one
## from the tick before it. Ticks the receiver acknowledged aren't sent
## again, so a quiet stream costs a few bytes a tick. A tick's change from
## the one before is coded once and kept ([member _chain]), whoever it is
## sent to. The last [constant RING] ticks are kept for resends
## ([method encode_range]).

const RING := 512
## The body of one message: the cap less the message's own fields.
const BODY_LIMIT := MwNetProtocol.MAX_MESSAGE - 32

## The first tick of the run (the tick before it is blank).
var first := 0
## The newest tick (first - 1: none yet).
var newest := -1
var _ticks := {}
var _chain := {}


func _init(first_no := 0) -> void:
	start(first_no)


## Starts a new run at tick [param first_no].
func start(first_no: int) -> void:
	first = first_no
	newest = first_no - 1
	_ticks.clear()
	_chain.clear()


## Appends [param tick] (a [constant MwNetInput.TICK_SIZE] array) as the
## next tick; returns its number.
func push(tick: PackedByteArray) -> int:
	var prev := get_tick(newest)
	newest += 1
	_ticks[newest] = tick
	_chain[newest] = MwNetInput.encode_tick(prev, tick)
	var old := newest - RING
	if _ticks.has(old):
		_ticks.erase(old)
		_chain.erase(old)
	return newest


## True when tick [param n] is still kept.
func has(n: int) -> bool:
	return _ticks.has(n)


## Tick [param n]: blank before the run starts (and for unknown ticks).
func get_tick(n: int) -> PackedByteArray:
	return _ticks[n] if _ticks.has(n) else MwNetInput.blank_tick()


## The oldest tick still kept.
func oldest() -> int:
	return maxi(first, newest - RING + 1)


## The next packet for a receiver that holds tick [param ack] ([constant
## MwNetProtocol.NONE]: nothing yet) and needs nothing before [param
## floor_no]: {base, first, count, body}, or {} when it holds everything.
## The newest ticks go first when they don't all fit.
func encode(ack: int, floor_no := 0, max_ticks := MwNetProtocol.MAX_TICKS,
		limit := BODY_LIMIT) -> Dictionary:
	var acked := ack != MwNetProtocol.NONE and ack >= floor_no
	var from := maxi(newest - max_ticks + 1, maxi(floor_no, first))
	if acked:
		from = maxi(from, ack + 1)
	if from > newest:
		return {}
	var base := ack if acked and _ticks.has(ack) else MwNetProtocol.NONE
	while true:
		var head := _first_bytes(base, from)
		var size := head.size()
		for n in range(from + 1, newest + 1):
			size += (_chain[n] as PackedByteArray).size()
		if size <= limit or from == newest:
			var body := head
			for n in range(from + 1, newest + 1):
				body.append_array(_chain[n])
			return {"base": base, "first": from, "count": newest - from + 1, "body": body}
		from += 1
	return {}


## Ticks [param from] to [param to] for a resend, as one or more
## {base, first, count, body} (each within one message, the first coded
## from the tick before [param from] - if the receiver, which needs nothing
## before [param floor_no], holds it - or else from blank, each next one
## from the last tick of the one before); ticks no longer kept are left out.
func encode_range(from: int, to: int, floor_no := 0, limit := BODY_LIMIT) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	from = maxi(from, maxi(oldest(), floor_no))
	to = mini(to, newest)
	var base := from - 1 if from - 1 >= floor_no and _ticks.has(from - 1) else MwNetProtocol.NONE
	while from <= to:
		var body := _first_bytes(base, from)
		var count := 1
		while from + count <= to and count < MwNetProtocol.MAX_RESEND \
				and body.size() + (_chain[from + count] as PackedByteArray).size() <= limit:
			body.append_array(_chain[from + count])
			count += 1
		out.append({"base": base, "first": from, "count": count, "body": body})
		base = from + count - 1
		from += count
	return out


## Tick [param n] coded from [param base] (a tick number or NONE: blank).
func _first_bytes(base: int, n: int) -> PackedByteArray:
	if _chain.has(n) and (base == n - 1 and _ticks.has(base) or base == MwNetProtocol.NONE and n == first):
		return (_chain[n] as PackedByteArray).duplicate()
	var b := MwNetInput.blank_tick() if base == MwNetProtocol.NONE else get_tick(base)
	return MwNetInput.encode_tick(b, _ticks[n])
