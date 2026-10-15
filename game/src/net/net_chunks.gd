class_name MwNetChunks
extends RefCounted
## A blob too big for one message - a resync snapshot (plan 35 section 5,
## work item 6: MwNetSnapshot's bytes, tens of kilobytes), or a start record
## with the host's custom teams in it (plan 38, protocol version 4) - cut
## into numbered chunks for the reliable channel ([method split]: SNAPSHOT
## or START messages, [constant MwNetProtocol.SNAPSHOT_CHUNK] / [constant
## MwNetProtocol.RECORD_CHUNK] bytes each, the last the rest) and put back
## together on the other side ([method take]). Node-free.
##
## The receiving end holds one blob at a time: a newer id (16 bits,
## counting up and wrapping) replaces an unfinished older one, an older id
## is stale. Every chunk is checked against the blob's numbers (the decoder
## already checked each chunk's own: MwNetProtocol._chunk_ok); a chunk that
## contradicts them, or one held already with other bytes, is BAD - the
## client drops a host that sends it (section 6).

## What a chunk did: one more of the blob (MORE), the blob is whole (DONE),
## one of an older blob or a whole blob's again (STALE), a contradiction (BAD).
enum Result { MORE, DONE, STALE, BAD }

## The blob being put together: its id (-1 none yet), stream tick, size and
## chunk count; [member complete] once every chunk is here.
var id := -1
var tick := -1
var size := 0
var count := 0
var complete := false
## The whole blob was taken ([method use]): its chunks are stale now.
var used := false
## True when the last [method take] began a new blob (its first chunk to
## arrive - not necessarily chunk 0).
var began := false
var _parts := {}


## [param blob] in chunks of [param chunk] bytes (the last one the rest;
## none for nothing).
static func split(blob: PackedByteArray, chunk := MwNetProtocol.SNAPSHOT_CHUNK) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var at := 0
	while at < blob.size():
		out.append(blob.slice(at, at + chunk))
		at += chunk
	return out


## Takes a decoded SNAPSHOT message ([param m]: id, tick, size, index,
## count, chunk); a [enum Result].
func take(m: Dictionary) -> int:
	began = false
	var mid := int(m["id"])
	if mid != id:
		if id >= 0 and ((mid - id) & 0xFFFF) >= 0x8000:
			return Result.STALE                      # an older snapshot's chunk
		id = mid
		tick = int(m["tick"])
		size = int(m["size"])
		count = int(m["count"])
		complete = false
		used = false
		_parts.clear()
		began = true
	elif complete or used:
		return Result.STALE
	if int(m["tick"]) != tick or int(m["size"]) != size or int(m["count"]) != count:
		return Result.BAD
	var i := int(m["index"])
	var chunk: PackedByteArray = m["chunk"]
	if i < 0 or i >= count:
		return Result.BAD
	if _parts.has(i):
		return Result.MORE if _parts[i] == chunk else Result.BAD
	_parts[i] = chunk
	if _parts.size() < count:
		return Result.MORE
	complete = true
	return Result.DONE


## The whole blob (empty until [member complete]).
func data() -> PackedByteArray:
	if not complete or _parts.size() != count:
		return PackedByteArray()
	var out := PackedByteArray()
	for i in count:
		out.append_array(_parts[i])
	return out if out.size() == size else PackedByteArray()


## The whole blob, taken once (empty when it isn't whole or was taken).
func use() -> PackedByteArray:
	if used:
		return PackedByteArray()
	var out := data()
	if complete:
		used = true
		_parts.clear()
	return out


## Forgets the blob (a new match).
func reset() -> void:
	id = -1
	tick = -1
	size = 0
	count = 0
	complete = false
	used = false
	began = false
	_parts.clear()
