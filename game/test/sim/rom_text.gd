extends RefCounted
## Game text in the fixtures by ROM address (nothing ROM-derived is
## committed, text included): a byte string the game built from ROM strings
## (a coach's quote: a template with team names put in) is stored as the
## ROM pieces it is made of, [[address, length], ...], and rebuilt from the
## ROM when a test loads it. Used for the state's `quote` buffer
## (`$FFC4FE`) in compare/fixtures/rink_gaps.json.

## The state paths that hold text ("quote/0" ...).
const PREFIX := "quote/"


## [param bytes] as the fewest pieces of [param rom] (greedy: the longest
## piece found at each point); a byte found nowhere (none in practice) is
## kept as [-1, value].
static func segments(rom: PackedByteArray, bytes: PackedByteArray) -> Array:
	var hay := rom.hex_encode()
	var out := []
	var i := 0
	while i < bytes.size():
		var best_at := -1
		var best_len := 0
		var n := 1
		while i + n <= bytes.size():
			var at := _find(hay, bytes.slice(i, i + n).hex_encode())
			if at < 0:
				break
			best_at = at
			best_len = n
			n += 1
		if best_at < 0:
			out.append([-1, bytes[i]])
			i += 1
		else:
			out.append([best_at, best_len])
			i += best_len
	return out


## The bytes [param segs] describe.
static func expand(rom: PackedByteArray, segs: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for sg in segs:
		if int(sg[0]) < 0:
			out.append(int(sg[1]))
		else:
			out.append_array(rom.slice(int(sg[0]), int(sg[0]) + int(sg[1])))
	return out


## The byte offset of [param needle] (hex) in [param hay] (hex), -1 if none.
static func _find(hay: String, needle: String) -> int:
	var from := 0
	while true:
		var at := hay.find(needle, from)
		if at < 0:
			return -1
		if at % 2 == 0:
			return at / 2
		from = at + 1
	return -1


## The text indices of a fixture's path list.
static func text_indices(paths: Array) -> Array:
	var out := []
	for i in paths.size():
		if str(paths[i]).begins_with(PREFIX):
			out.append(i)
	return out


## A fixture case written: its [param key] values' text (the whole buffer
## up to its last non-zero byte: what follows a quote's 0 is an older
## quote's tail) moved to case[key + "_text"] as ROM pieces, the values
## zeroed.
static func values_out(rom: PackedByteArray, case: Dictionary, key: String, idx: Array) -> void:
	var vals: Array = case[key]
	var b := PackedByteArray()
	var last := -1
	for j in idx.size():
		var v := int(vals[idx[j]]) if vals[idx[j]] != null else 0
		b.append(v)
		if v != 0:
			last = j
	if last < 0:
		return
	b = b.slice(0, last + 1)
	case[key + "_text"] = segments(rom, b)
	for i in idx:
		vals[i] = 0


## A fixture case read: its [param key] values' text put back from the ROM.
static func values_in(rom: PackedByteArray, case: Dictionary, key: String, idx: Array) -> void:
	if not case.has(key + "_text"):
		return
	var b := expand(rom, case[key + "_text"])
	var vals: Array = case[key]
	for j in idx.size():
		vals[idx[j]] = int(b[j]) if j < b.size() else 0


## The same for a list of changes [[path index, value], ...]: the text
## indices' values moved to case[key + "_text"] (the whole buffer, 0s
## included up to the last change).
static func changes_out(rom: PackedByteArray, case: Dictionary, key: String, idx: Array) -> void:
	var at := {}
	for j in idx.size():
		at[int(idx[j])] = j
	var keep := []
	var text := {}
	for c in case[key]:
		if (c[0] is int or c[0] is float) and at.has(int(c[0])):
			text[at[int(c[0])]] = int(c[1])
		else:
			keep.append(c)
	if text.is_empty():
		return
	var top := 0
	for j in text:
		top = maxi(top, int(j) + 1)
	var b := PackedByteArray()
	var mask := []
	for j in top:
		b.append(int(text.get(j, 0)))
		mask.append(1 if text.has(j) else 0)
	case[key] = keep
	case[key + "_text"] = {"pieces": segments(rom, b), "set": mask}


static func changes_in(rom: PackedByteArray, case: Dictionary, key: String, idx: Array) -> void:
	if not case.has(key + "_text"):
		return
	var t: Dictionary = case[key + "_text"]
	var b := expand(rom, t["pieces"])
	var mask: Array = t["set"]
	var list: Array = case[key]
	for j in mask.size():
		if int(mask[j]) != 0:
			list.append([idx[j], int(b[j])])
