class_name MwQuotes
extends RefCounted
## The original's quote picker (`$F420`; docs/re/menus.md, Team
## description): a table `$1D404` of quote sets by category, team group and
## index. A set is `value.w, count.w, string pointers`: no strings - the
## fallback at `$50D2D`; one - that one; more - one picked with the main
## random stream (category 9: by a counter instead). The chosen template is
## expanded into a buffer (`$FFC4FE`), where `@`, `[`, `{` and `}` insert
## strings of the caller's objects (a player's names, ...). The team
## description asks for category 12 (a star player's quote).

const TABLE := 0x1D404
const FALLBACK := 0x50D2D
## Template codes -> [method expand] field names.
const CODES := {0x40: "@", 0x5B: "[", 0x7B: "{", 0x7D: "}"}


## `$F420`: the quote of set [param index] in [param category] for team
## group [param group] (0 conference teams, 1 teams 20-21, 2 team 22):
## {"template": PackedByteArray, "value": the set's first word}.
## [param rng] picks among several strings; [param counter] does for
## category 9.
static func pick(rom: PackedByteArray, category: int, group: int, index: int, rng: MlhRng, counter := 0) -> Dictionary:
	var by_group := MwGfx.u32(rom, TABLE + 4 * category)
	var sets := MwGfx.u32(rom, by_group + 4 * group)
	var s := MwGfx.u32(rom, sets + 4 * index)
	var value := MwGfx.u16(rom, s)
	var count := MwGfx.u16(rom, s + 2)
	var text := FALLBACK
	if count == 1:
		text = MwGfx.u32(rom, s + 4)
	elif count > 1:
		var i := counter % count if category == 9 else rng.range_value(0, count - 1)
		text = MwGfx.u32(rom, s + 4 + 4 * i)
	return {"template": MwGfx.rom_string(rom, text), "value": value}


## The template with its codes replaced: [param fields] maps "@", "[", "{"
## and "}" to the strings the original takes from its objects ("[" is a
## full name: first name, a space, then the "{" string).
static func expand(template: PackedByteArray, fields: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	for c in template:
		if CODES.has(c):
			out.append_array(fields.get(CODES[c], PackedByteArray()))
		else:
			out.append(c)
	return out
