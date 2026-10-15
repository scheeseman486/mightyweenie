class_name MwInputStream
extends RefCounted
## The players' input, tick by tick (plan 35, docs/net.md): what makes a
## game from its start record (MwSession.to_record). Each tick numbered
## like the router's ([member first_tick] on); [method last_tick] is the
## last confirmed one - the pass clock's stream mode (MwPassClock.STREAM)
## runs a tick only once it is here. Offline a recording fills it as the
## game runs (MwStreamInput with a source); online the network does (plan
## 35 work item 4) - the host merging each machine's players.
##
## Saved delta-coded ([method to_bytes]): per tick only what changed. A
## long online session keeps only its recent ticks ([method drop_before]).

const MAGIC := "MWIS"
## 3 (plan 40, S7): each tick's states as the wire has them (MwTickInput
## .states: the shared menu verbs' and players 1-12's, MwNetInput), coded as
## the network codes them (MwNetInput.write_delta / write_tick) - whatever a
## player's state holds, the stream carries it as it is; the header names the
## wire's table (MwNetInput.schema). 2: the shot heights' changes ([constant
## _HEIGHT]); 1: none. Formats 1 and 2 still read (and [method to_bytes]
## writes 2 when asked).
const FORMAT := 3
const _HELD := 0x0000
const _PRESS := 0x4000
const _STICK := 0x8000
const _STATUS := 0xC000
## A shot height's change: the status' kind with bit 13 set (a status's
## player index never reaches it).
const _HEIGHT := 0xE000

## The router tick of the first entry.
var first_tick := 1
var ticks: Array[MwTickInput] = []


## The last tick the stream holds ([member first_tick] - 1: none yet).
func last_tick() -> int:
	return first_tick + ticks.size() - 1


## Whether the stream holds tick [param t] ([member first_tick] to
## [method last_tick]).
func has_tick(t: int) -> bool:
	return t >= first_tick and t <= last_tick()


## Tick [param t]'s input (null if the stream doesn't hold it).
func at(t: int) -> MwTickInput:
	return ticks[t - first_tick] if has_tick(t) else null


## [param ti] as the next tick.
func append(ti: MwTickInput) -> void:
	ticks.append(ti)


## Only ticks up to [param t] kept.
func truncate(t: int) -> void:
	ticks.resize(clampi(t - first_tick + 1, 0, ticks.size()))


## Only ticks from [param t] on kept (their numbers stay: [member
## first_tick] moves up) - an online game plays each tick once, so it lets
## the old ones go.
func drop_before(t: int) -> void:
	var n := clampi(t - first_tick, 0, ticks.size())
	if n > 0:
		ticks = ticks.slice(n)
		first_tick += n


## The stream as bytes: a header, then per tick its changes against the tick
## before (held bits flipped, counters changed, sticks changed, network
## statuses changed - plan 35 work item 4 -, shot heights changed -
## MwTickInput.heights; a stream without any reads as before).
func to_bytes(format := FORMAT) -> PackedByteArray:
	if format >= 3:
		return _wire_bytes()
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	b.put_data(MAGIC.to_ascii_buffer())
	b.put_u16(format)
	b.put_u16(MwTickInput.actions().size())
	b.put_u32(first_tick)
	b.put_u32(ticks.size())
	var before := MwTickInput.new()
	for ti in ticks:
		var ev := PackedInt32Array()
		if ti.held != before.held:
			for k in ti.held.size():
				var x := ti.held[k] ^ before.held[k]
				for bit in 8:
					if x & (1 << bit):
						ev.append(_HELD | ((k << 3) | bit))
		if ti.counts != before.counts:
			for i in ti.counts.size():
				if ti.counts[i] != before.counts[i]:
					ev.append(_PRESS | i)
					ev.append(ti.counts[i])
		for p in ti.sticks.size():
			if ti.sticks[p] != before.sticks[p]:
				ev.append(_STICK | p)
				ev.append(ti.sticks[p])
		if ti.status != before.status:
			for p in ti.status.size():
				if ti.status[p] != before.status[p]:
					ev.append(_STATUS | p)
					ev.append(ti.status[p])
		if ti.heights != before.heights:
			for p in ti.heights.size():
				if ti.heights[p] != before.heights[p]:
					ev.append(_HEIGHT | p)
					ev.append(ti.heights[p])
		b.put_u16(ev.size())
		for e in ev:
			b.put_u16(e)
		before = ti
	return b.data_array


## Format 3: the header (the magic, the format, the wire's schema, the
## first tick, the count), then per tick its shared state's change (a byte:
## changed or not, then MwNetInput.write_delta) and its players' (write_tick).
func _wire_bytes() -> PackedByteArray:
	var writer := MwNetBytes.Writer.new()
	writer.bytes(MAGIC.to_ascii_buffer())
	writer.u16(3)
	writer.u32(MwNetInput.schema())
	writer.u32(first_tick)
	writer.u32(ticks.size())
	var before: Array = [MwNetInput.blank(), MwNetInput.blank_tick()]
	for ti in ticks:
		var st := ti.states()
		if st[0] != before[0]:
			writer.u8(1)
			MwNetInput.write_delta(writer, before[0], st[0])
		else:
			writer.u8(0)
		MwNetInput.write_tick(writer, before[1], st[1])
		before = st
	return writer.data


## The stream from [method to_bytes]' bytes (null if they aren't one, or
## carry another set of actions or another wire; formats 1-3).
static func from_bytes(data: PackedByteArray) -> MwInputStream:
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	b.data_array = data
	if data.size() < 16 or (b.get_data(4)[1] as PackedByteArray).get_string_from_ascii() != MAGIC:
		return null
	var format := b.get_u16()
	if format == 3:
		return _from_wire_bytes(data)
	if format < 1 or format > 2 or b.get_u16() != MwTickInput.actions().size():
		return null
	var stream := MwInputStream.new()
	stream.first_tick = b.get_u32()
	var n := b.get_u32()
	var before := MwTickInput.new()
	for k in n:
		var ti := MwTickInput.new()
		ti.held = before.held.duplicate()
		ti.counts = before.counts.duplicate()
		ti.sticks = before.sticks.duplicate()
		ti.status = before.status.duplicate()
		ti.heights = before.heights.duplicate()
		var m := b.get_u16()
		var j := 0
		while j < m:
			var e := b.get_u16()
			j += 1
			match e & 0xC000:
				_HELD:
					ti.set_held(e & 0x3FFF, not ti.is_held(e & 0x3FFF))
				_PRESS:
					ti.counts[e & 0x3FFF] = b.get_u16() & 0xFF
					j += 1
				_STICK:
					ti.sticks[e & 0x3FFF] = b.get_u16()
					j += 1
				_STATUS:
					if e & 0x2000:            # _HEIGHT (format 2): a code 0-3
						ti.heights[(e & 0x1FFF) % MwTickInput.PLAYERS] = b.get_u16() & 3
					else:
						ti.status[(e & 0x1FFF) % MwTickInput.PLAYERS] = b.get_u16() & 0xFF
					j += 1
		stream.ticks.append(ti)
		before = ti
	return stream


static func _from_wire_bytes(data: PackedByteArray) -> MwInputStream:
	var reader := MwNetBytes.Reader.new(data, 6)
	if reader.u32() != MwNetInput.schema():
		return null
	var stream := MwInputStream.new()
	stream.first_tick = reader.u32()
	var n := reader.u32()
	if not reader.ok:
		return null
	var shared := MwNetInput.blank()
	var wire := MwNetInput.blank_tick()
	for k in n:
		var changed := reader.u8()
		if changed > 1:
			return null
		if changed == 1:
			shared = shared.duplicate()
			if not MwNetInput.read_delta_into(reader, shared, 0):
				return null
		wire = MwNetInput.read_tick(reader, wire)
		if not reader.ok or wire.is_empty():
			return null
		stream.ticks.append(MwTickInput.from_states(shared, wire))
	return stream
