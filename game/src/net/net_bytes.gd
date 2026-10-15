class_name MwNetBytes
extends RefCounted
## Byte writing and reading for the network messages (plan 35 section 1,
## [MwNetProtocol]): big-endian (network order) integers, length-prefixed
## byte strings and short ASCII texts.
##
## The reader never fails loudly (plan 35 section 6: garbage never
## crashes): reading past the end, a length over its cap or a text that
## isn't printable ASCII clears [member Reader.ok] and gives zeroes or empty
## values from then on, so a decoder reads a whole message and checks
## [code]ok[/code] (and [method Reader.done]) once at the end.


## Builds a message.
class Writer:
	var data := PackedByteArray()

	func u8(v: int) -> void:
		data.append(v & 0xFF)

	func u16(v: int) -> void:
		data.append((v >> 8) & 0xFF)
		data.append(v & 0xFF)

	func u32(v: int) -> void:
		data.append((v >> 24) & 0xFF)
		data.append((v >> 16) & 0xFF)
		data.append((v >> 8) & 0xFF)
		data.append(v & 0xFF)

	func bytes(b: PackedByteArray) -> void:
		data.append_array(b)

	## [param b] after its length in one byte (at most 255 bytes).
	func blob8(b: PackedByteArray) -> void:
		u8(b.size())
		data.append_array(b)

	## [param b] after its length in two bytes.
	func blob16(b: PackedByteArray) -> void:
		u16(b.size())
		data.append_array(b)

	## [param value] (ASCII) after its length in one byte.
	func text(value: String) -> void:
		blob8(value.to_ascii_buffer())

	func size() -> int:
		return data.size()


## Reads a message; [member ok] turns false at the first problem.
class Reader:
	var data: PackedByteArray
	var pos := 0
	var ok := true

	func _init(d: PackedByteArray, start := 0) -> void:
		data = d
		pos = start
		if start > d.size():
			ok = false

	func remaining() -> int:
		return data.size() - pos if ok else 0

	## True when everything was read and nothing went wrong (a message with
	## bytes left over is malformed too).
	func done() -> bool:
		return ok and pos == data.size()

	func _need(n: int) -> bool:
		if not ok or n < 0 or pos + n > data.size():
			ok = false
			return false
		return true

	func u8() -> int:
		if not _need(1):
			return 0
		pos += 1
		return data[pos - 1]

	func u16() -> int:
		if not _need(2):
			return 0
		pos += 2
		return (data[pos - 2] << 8) | data[pos - 1]

	func u32() -> int:
		if not _need(4):
			return 0
		pos += 4
		return (data[pos - 4] << 24) | (data[pos - 3] << 16) | (data[pos - 2] << 8) | data[pos - 1]

	## A byte in [lo, hi]; anything else clears [member ok].
	func u8_in(lo: int, hi: int) -> int:
		var v := u8()
		if v < lo or v > hi:
			ok = false
			return lo
		return v

	func bytes(n: int) -> PackedByteArray:
		if not _need(n):
			return PackedByteArray()
		pos += n
		return data.slice(pos - n, pos)

	## A [method Writer.blob8] of [param lo] to [param hi] bytes.
	func blob8(lo: int, hi: int) -> PackedByteArray:
		var n := u8()
		if n < lo or n > hi:
			ok = false
			return PackedByteArray()
		return bytes(n)

	## A [method Writer.blob16] of [param lo] to [param hi] bytes.
	func blob16(lo: int, hi: int) -> PackedByteArray:
		var n := u16()
		if n < lo or n > hi:
			ok = false
			return PackedByteArray()
		return bytes(n)

	## A [method Writer.text] of at most [param hi] printable ASCII
	## characters (32-126).
	func text(hi: int) -> String:
		var b := blob8(0, hi)
		for c in b:
			if c < 32 or c > 126:
				ok = false
				return ""
		return b.get_string_from_ascii()


## Plan 40 (S6): [param v] packed as START's record and a resync snapshot
## carry it - its var_to_bytes length (32 bits) and the bytes compressed
## with [param mode] (FileAccess.COMPRESSION_*). [method packed_raw_size]
## reads the length back.
static func pack_var(v: Variant, mode: int) -> PackedByteArray:
	var raw := var_to_bytes(v)
	var writer := Writer.new()
	writer.u32(raw.size())
	writer.bytes(raw.compress(mode))
	return writer.data


## The unpacked size [method pack_var]'s bytes [param b] say (-1: too short).
static func packed_raw_size(b: PackedByteArray) -> int:
	if b.size() < 4:
		return -1
	return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]


## [method pack_var]'s bytes [param b] back - another machine's: their size
## checked first (at most [param max_raw] unpacked), no objects decoded;
## null when they aren't such bytes.
static func unpack_var(b: PackedByteArray, max_raw: int, mode: int) -> Variant:
	if b.size() < 5:
		return null
	var reader := Reader.new(b)
	var n := reader.u32()
	if not reader.ok or n <= 0 or n > max_raw:
		return null
	var raw := reader.bytes(reader.remaining()).decompress(n, mode)
	if raw.size() != n:
		return null
	return bytes_to_var(raw)
