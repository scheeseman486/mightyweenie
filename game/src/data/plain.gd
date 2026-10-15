class_name MwPlain
extends RefCounted
## Plan 40 (S6): plain data - what JSON files and the network carry (ints,
## floats, bools, strings, arrays, string-keyed dictionaries) - read and
## written in one place. Every reader takes a value of the wrong type as its
## default instead of a script error: a custom team's JSON (MwCustomTeam
## .from_dict and the rest, plan 38), a host's start record (MwSession
## .from_record, MwHumans.from_record - the survey's B7: those cast bare),
## a snapshot's carried teams.

## Text read at most (characters) before a caller cleans it.
const TEXT_READ := 1024
## Untrusted plain data's bounds ([method plain_ok]): nulls, bools, ints,
## finite floats, strings of at most [constant STRING] characters, lists of
## at most [constant ITEMS] values, dictionaries of at most [constant KEYS]
## string keys, at most [constant DEPTH] deep and [constant VALUES] values
## in all (a carried custom team's JSON, MwCustomTeams).
const DEPTH := 6
const VALUES := 16384
const STRING := 1024
const ITEMS := 256
const KEYS := 64


## [param v] as an int: an int, a finite float (JSON's numbers, exact up to
## 2^53: a 32-bit random state comes through whole), a bool or a short
## string of digits; anything else [param default].
static func num(v: Variant, default := 0) -> int:
	if v is int:
		return v
	if v is float:
		return int(clampf(v, -9007199254740992.0, 9007199254740992.0)) if is_finite(v) else default
	if v is bool:
		return 1 if v else 0
	if v is String and (v as String).length() <= 12 and (v as String).is_valid_int():
		return (v as String).to_int()
	return default


## [param v] as text: a string (cut to [constant TEXT_READ]) or a number;
## anything else [param default].
static func text(v: Variant, default := "") -> String:
	if v is String:
		return (v as String).substr(0, TEXT_READ)
	if v is int or v is float:
		return str(v)
	return default


## [param digits] (up to 8 characters) as a hexadecimal number ("0E64"); 0 when
## it isn't one (without the engine's complaint).
static func hex(digits: String) -> int:
	var t := digits.substr(0, 8)
	return t.hex_to_int() if t.is_valid_hex_number() else 0


## [param v] as a flag: a bool, or a number not 0; anything else [param default].
static func flag(v: Variant, default := false) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return default


## [param v] as a dictionary ({} when it isn't one).
static func dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## [param v] as an array ([] when it isn't one; a packed array's values).
static func array(v: Variant) -> Array:
	if v is Array:
		return v
	if v is PackedInt32Array or v is PackedByteArray or v is PackedInt64Array or v is PackedStringArray \
			or v is PackedFloat32Array or v is PackedFloat64Array:
		return Array(v)
	return []


## [param v] as ints ([method num] each; [param default] for what isn't one).
static func ints(v: Variant, default := 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	for x in array(v):
		out.append(num(x, default))
	return out


## [param v] (an array of numbers, or bytes) as bytes, each & $FF.
static func bytes(v: Variant) -> PackedByteArray:
	if v is PackedByteArray:
		return v
	var out := PackedByteArray()
	for x in array(v):
		out.append(num(x) & 0xFF)
	return out


## Rows of ints as an Array of PackedInt32Array (the setup's extended pads
## and line-ups).
static func int_rows(v: Variant) -> Array:
	var out := []
	for row in array(v):
		out.append(ints(row))
	return out


## [param v] with every float (JSON's numbers) an int, arrays and
## dictionaries deep.
static func ints_from_json(v: Variant) -> Variant:
	if v is float:
		return int(v)
	if v is Array:
		var out := []
		for x in v:
			out.append(ints_from_json(x))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = ints_from_json(v[k])
		return out
	return v


## [param v] as plain arrays (packed int and byte arrays converted, deep).
static func to_plain(v: Variant) -> Variant:
	if v is PackedInt32Array or v is PackedByteArray:
		return Array(v)
	if v is Array:
		var out := []
		for x in v:
			out.append(to_plain(x))
		return out
	return v


## True when [param v] is plain data within the bounds above (untrusted:
## another machine's, before anything reads it).
static func plain_ok(v: Variant) -> bool:
	var budget := [VALUES]
	return _plain_ok(v, 0, budget)


static func _plain_ok(v: Variant, depth: int, budget: Array) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > DEPTH:
		return false
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(v)
		TYPE_STRING:
			return (v as String).length() <= STRING
		TYPE_ARRAY:
			var a: Array = v
			if a.is_typed() or a.size() > ITEMS:
				return false
			for x: Variant in a:
				if not _plain_ok(x, depth + 1, budget):
					return false
			return true
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.is_typed() or d.size() > KEYS:
				return false
			for k: Variant in d:
				if not k is String or (k as String).length() > STRING:
					return false
				if not _plain_ok(d[k], depth + 1, budget):
					return false
			return true
	return false
