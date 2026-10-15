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

## The port's own quote sets (written by the owner; not ROM text). Same
## template codes as the ROM's quotes. Each line must fit screen 17's speech
## box (36 x 5 cells, the speech font: one cell a character, words wrapped,
## the rest cut) with every pair of teams - `test_forfeit_lines.gd` checks -
## and use no character the speech font lacks (`$ & * + ; < > \ ^`).
##
## The referee's message after a manual forfeit (the port's pause menu,
## [member MwRinkState.forfeit_manual]; plan 26), in place of the ROM's
## category 13 situation 1 set: `[` the forfeiting team's city and name,
## `{` its name, `}` the winner's name; a name ending in "s" followed by
## "'s" takes "'" alone ("Hounds'", "Lynx's"; owner). One is picked as the
## ROM's set of four is (`rng_range(0, 3)` on the main stream), so the random
## stream moves the same either way.
const MANUAL_FORFEIT := [
	"} win the game, as all of the {'s players disappeared, leaving behind mutant shaped puffs of smoke.",
	"[ have lost the game, their dignity and their sponsorship. The } won the game, not that it was difficult.",
	"If you're going to drag me here and make me watch this trash, the least you could do is commit. [ have "
			+ "forfeited and I'm going back to bed.",
	"The { decided to waste everyone's time, so I decided to put all their players through a meat grinder. Game over.",
]


## Plan 40 (D1): `$F420` in one place - the team description, the rink's
## speeches, the scoreboards, the special plays and CREATE-A-TEAM's sample
## walk the table and expand through these. The table's three levels: the
## category, then the situation (the team description's: the team group -
## 0 conference teams, 1 teams 20-21, 2 team 22), then the set.

## The set [param set_index] of [param category] / [param situation]: its
## address (a value word, a count word, the string pointers).
static func set_at(rom: PackedByteArray, category: int, situation: int, set_index: int) -> int:
	var t := MwGfx.u32(rom, TABLE + 4 * category)
	t = MwGfx.u32(rom, t + 4 * situation)
	return MwGfx.u32(rom, t + 4 * set_index)


## [method set_at] for a coach (record [param coach]): a custom coach's own
## set there when he has one ([method MwCustomOverlay.coach_speech_set]:
## CREATE-A-TEAM's speeches, owner 2026-10-14), else his base set
## [param set_index]'s.
static func coach_set_at(rom: PackedByteArray, category: int, situation: int, set_index: int, coach: int) -> int:
	var own := MwCustomOverlay.coach_speech_set(rom, coach, category, situation)
	return own if own != 0 else set_at(rom, category, situation, set_index)


## The set's value word (the rink keeps it: `$C616`).
static func value_of(rom: PackedByteArray, set_addr: int) -> int:
	return MwGfx.u16(rom, set_addr)


## The set's strings' addresses, in order.
static func strings(rom: PackedByteArray, set_addr: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in MwGfx.u16(rom, set_addr + 2):
		out.append(MwGfx.u32(rom, set_addr + 4 + 4 * i))
	return out


## The string `$F420` takes from the set at [param set_addr]: none -
## [constant FALLBACK]; one - it; more - the one [param draw] picks
## ([code]draw.call(count - 1)[/code]: the caller's own random draw,
## rng_range(0, count - 1) on its stream, so every stream moves as before)
## or, [param counter] >= 0 (category 9), the counter's.
static func choose(rom: PackedByteArray, set_addr: int, draw: Callable, counter := -1) -> int:
	var count := MwGfx.u16(rom, set_addr + 2)
	if count == 1:
		return MwGfx.u32(rom, set_addr + 4)
	if count > 1:
		var i: int = counter % count if counter >= 0 else int(draw.call(count - 1)) & 0xFFFF
		return MwGfx.u32(rom, set_addr + 4 + 4 * i)
	return FALLBACK


## `$F420`: the quote of set [param index] in [param category] for team
## group [param group] (0 conference teams, 1 teams 20-21, 2 team 22):
## {"template": PackedByteArray, "value": the set's first word}.
## [param rng] picks among several strings; [param counter] does for
## category 9.
static func pick(rom: PackedByteArray, category: int, group: int, index: int, rng: MlhRng, counter := 0) -> Dictionary:
	var quote_set := set_at(rom, category, group, index)
	var text := choose(rom, quote_set, func(hi: int) -> int: return rng.range_value(0, hi), \
			counter if category == 9 else -1)
	return {"template": MwGfx.rom_string(rom, text), "value": value_of(rom, quote_set)}


## The codes' strings the original takes from its objects: `[` the team
## record [param team]'s city, a space and name, `{` its name, `}` the
## team record [param other]'s name, `@` the string at the record
## [param who] (-1: none - a5 holds no record there).
static func fields(rom: PackedByteArray, team: int, other: int, who := -1) -> Dictionary:
	var name := MwGfx.rom_string(rom, MwGfx.u32(rom, team + 4))
	var out := {"[": MwGfx.rom_string(rom, MwGfx.u32(rom, team)) + PackedByteArray([0x20]) + name, "{": name,
			"}": MwGfx.rom_string(rom, MwGfx.u32(rom, other + 4))}
	if who >= 0:
		out["@"] = MwGfx.rom_string(rom, MwGfx.u32(rom, who))
	return out


## The template with its codes replaced: [param fields_] maps "@", "[", "{"
## and "}" to the strings the original takes from its objects ("[" is a
## full name: first name, a space, then the "{" string); a code it lacks
## gives nothing. [param possessive]: as [method expand_into]'s.
static func expand(template: PackedByteArray, fields_: Dictionary, possessive := false) -> PackedByteArray:
	var f := fields_.duplicate()
	var bytes := PackedByteArray()
	bytes.resize(template.size() + 1)
	for code: String in CODES.values():
		if not f.has(code):
			f[code] = PackedByteArray()
		bytes.resize(bytes.size() + template.size() * (f[code] as PackedByteArray).size())
	return bytes.slice(0, expand_into(bytes, template, f, possessive))


## `$F420`'s copy into the quote buffer [param bytes] (`$FFC4FE`; nothing past
## its end): [param template] with its codes' strings from [param fields_]
## (a code without one: nothing, and a warning), then a terminator; returns
## where it is. [param possessive] (the port's own lines only, plan 26, and a
## custom coach's - the ROM's are copied as the original copies them): a
## code whose string ends
## in "s" followed by "'s" and no further letter gets "'" alone ("Hounds'";
## "Lynx's" stays).
static func expand_into(bytes: PackedByteArray, template: PackedByteArray, fields_: Dictionary,
		possessive := false) -> int:
	var out := 0
	var i := 0
	while i < template.size():
		var ch := template[i]
		i += 1
		if not CODES.has(ch):
			_put(bytes, out, ch)
			out += 1
			continue
		var code: String = CODES[ch]
		if not fields_.has(code):
			push_warning("MwQuotes: quote code %s without its string" % code)
			continue
		var from := out
		for b in (fields_[code] as PackedByteArray):
			_put(bytes, out, b)
			out += 1
		if possessive and out > from and out - 1 < bytes.size() and (bytes[out - 1] == 0x73 or bytes[out - 1] == 0x53) \
				and _plural_possessive(template, i):
			_put(bytes, out, 0x27)                  # "'" for "'s"
			out += 1
			i += 2
	_put(bytes, out, 0)
	return out


## [param template] continues at [param at] with "'s" (or "'S": a custom
## coach's line typed in capitals) and no further letter or digit (the
## possessive after a code).
static func _plural_possessive(template: PackedByteArray, at: int) -> bool:
	if at + 1 >= template.size() or template[at] != 0x27 or (template[at + 1] != 0x73 and template[at + 1] != 0x53):
		return false
	if at + 2 >= template.size():
		return true
	var c := template[at + 2]
	return not ((c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A))


static func _put(bytes: PackedByteArray, at: int, v: int) -> void:
	if at < bytes.size():
		bytes[at] = v & 0xFF
