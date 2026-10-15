class_name MwCoachSpeeches
extends RefCounted
## A custom coach's own speeches (CREATE-A-TEAM; owner, 2026-10-14: speeches
## could be picked and viewed but not written or changed): what he says in
## the rink (`$F420`'s categories 0-7, picked by [MwRinkPhases] at a period's
## start, a game's end, a penalty and a goal) by occasion and situation. Any
## situation may have lines of his own ([member MwCustomCoach.speeches]); one
## without says his base quote set's ([member MwCustomCoach.style]: the
## original coach he was copied from), as the original's coaches do.
## [MwCustomOverlay] writes his lines as quote sets in the original's layout,
## so the rink picks one exactly as it picks the ROM's
## ([method MwQuotes.coach_set_at]).
##
## A line is kept as typed, the quote codes for the team names written as
## tokens a player can type ([constant TOKENS]); [method to_codes] gives the
## original's codes back.

## The occasions in the rink's order: [category, label, situations], each
## situation [its number, label] - the numbers the rink computes
## ([MwRinkPhases]: `_setup_period_start`, `_setup_game_over`,
## `_setup_penalty`, `_setup_goal`), in an order a player reads. A goal's
## situation 4 is never asked for: not listed.
const OCCASIONS := [
	[0, "1ST PERIOD", [[0, "FAVOURITES"], [1, "EVENLY MATCHED"], [2, "UNDERDOGS"], [3, "BIG UNDERDOGS"]]],
	[1, "PLAYOFF START", [[0, "FAVOURITES"], [1, "EVENLY MATCHED"], [2, "UNDERDOGS"], [3, "BIG UNDERDOGS"]]],
	[2, "2ND, 3RD PERIOD", [[0, "AHEAD BY 3+"], [1, "AHEAD BY 1-2"], [2, "TIED"], [3, "BEHIND BY 1-2"],
			[4, "BEHIND BY 3+"]]],
	[3, "OVERTIME", [[0, "OVERTIME"]]],
	[4, "GAME OVER", [[0, "WON, SHUTOUT"], [4, "WON BY 3+"], [5, "WON BY 1-2"], [3, "TIED"], [2, "LOST BY 1-2"],
			[1, "LOST BY 3+"]]],
	[5, "PLAYOFF RESULT", [[1, "CHAMPIONS"], [2, "WON SERIES 2-0"], [0, "WON, PLAYING ON"], [3, "LOST, PLAYING ON"],
			[4, "KNOCKED OUT"]]],
	[6, "PENALTY", [[0, "PENALTY"]]],
	[7, "GOAL", [[0, "A GOAL"], [1, "2-POINT GOAL"], [2, "POWER PLAY GOAL"], [3, "HAT TRICK"], [5, "DEMON NET GOAL"],
			[6, "OWN GOAL"]]],
]
## The situations each category's table holds in the ROM (`$1D404`): a
## custom coach's table has as many ([MwCustomOverlay]).
const SITUATIONS := [4, 4, 5, 1, 6, 5, 1, 7]
## The team names in a line: the token a player types for each of the
## original's quote codes (`[` the team's city and name, `{` its name, `}`
## the other team's), the longest first. `@` (a record's string) has none:
## no rink speech has one.
const TOKENS := [["#USFULL", "["], ["#THEM", "}"], ["#US", "{"]]
## What the text entry says about them.
const TOKENS_NOTE := "#US #THEM #USFULL: TEAM NAMES"
## The characters a line may have: every font's ([constant
## MwCustomTeam.CHARSET], so a token's `#` too) and the brackets the
## original's speeches use (the speech font has them).
const CHARSET := MwCustomTeam.CHARSET + "()"
## The pads' keys on the text entry ([member MwTextField.pages]): one page
## of the grid's 48 - the capitals (small letters type as capitals, as the
## editor's other texts; the fonts draw both alike), the digits and the
## signs; `_` the keyboard's alone.
const PAD_KEYS := [["ABC", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!?.,:'\"-#%()"]]
## The text entry's example while a line is empty (port text).
const EXAMPLE := "THE #THEM THINK THEY CAN SKATE. SHOW THEM WHAT THE ICE TASTES LIKE."
## Lines a situation has at most (the ROM's speeches have up to 4; the
## lines page shows five rows above its box).
const LINES_MAX := 5
## A line's characters at most as typed (the speech box is 34 x 6 cells;
## the original's longest, its codes as tokens, is shorter).
const LINE_MAX := 200
## Lines read from a file at most per situation (more are dropped).
const LINES_READ := 16


## The key of category [param category]'s situation [param situation] in
## [member MwCustomCoach.speeches].
static func key(category: int, situation: int) -> String:
	return "%d.%d" % [category, situation]


## Whether [param k] names a situation the rink asks for (one of
## [constant OCCASIONS]': a goal's 4 isn't).
static func valid_key(k: String) -> bool:
	var parts := k.split(".")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return false
	var category := int(parts[0])
	if category < 0 or category >= OCCASIONS.size():
		return false
	for st: Array in situations_of(category):
		if int(st[0]) == int(parts[1]):
			return true
	return false


## Occasion [param i]'s situations: [[situation, label], ...].
static func situations_of(i: int) -> Array:
	return OCCASIONS[i][2]


## Occasion [param i]'s category (the rink's).
static func category_of(i: int) -> int:
	return int(OCCASIONS[i][0])


## The situations the editor offers (every occasion's).
static func situation_count() -> int:
	var n := 0
	for o: Array in OCCASIONS:
		n += (o[2] as Array).size()
	return n


## How many situations [param coach] has lines of his own for: occasion
## [param i]'s, or every occasion's (-1).
static func own_count(coach: MwCustomCoach, i := -1) -> int:
	var n := 0
	for o in OCCASIONS.size():
		if i >= 0 and o != i:
			continue
		for st: Array in situations_of(o):
			if coach.speeches.has(key(category_of(o), int(st[0]))):
				n += 1
	return n


## The label of category [param category]'s situation [param situation]
## ("GOAL, HAT TRICK"; an occasion of one situation: its name alone).
static func label(category: int, situation: int) -> String:
	for o: Array in OCCASIONS:
		if int(o[0]) != category:
			continue
		var sits: Array = o[2]
		for st: Array in sits:
			if int(st[0]) == situation:
				return str(o[1]) if sits.size() == 1 else "%s, %s" % [o[1], st[1]]
	return ""


## A line as the editor keeps it: its characters in [constant CHARSET]
## (as typed: the original's speeches are in capitals and small letters),
## its tokens in capitals however typed, words one space apart, at most
## [constant LINE_MAX].
static func clean_line(text: String) -> String:
	var out := ""
	for c in text:
		if CHARSET.contains(c):
			out += c
	for t: Array in TOKENS:
		var token := str(t[0])
		var at := out.findn(token)
		while at >= 0:
			out = out.substr(0, at) + token + out.substr(at + token.length())
			at = out.findn(token, at + token.length())
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges().substr(0, LINE_MAX)


## [param speeches] (a coach's, as read) in range: situations of the rink's
## speeches only, each line cleaned ([method clean_line]), empty ones
## dropped, at most [constant LINES_MAX] a situation; a situation left with
## none dropped (it says the original's lines).
static func validate(speeches: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in speeches:
		if not k is String or not valid_key(k):
			continue
		var lines := PackedStringArray()
		for l: Variant in speeches[k]:
			if lines.size() >= LINES_MAX:
				break
			var t := clean_line(str(l))
			if t != "":
				lines.append(t)
		if not lines.is_empty():
			out[k] = lines
	return out


## [param line]'s tokens as the original's quote codes (the bytes the rink
## expands).
static func to_codes(line: String) -> String:
	var out := line
	for t: Array in TOKENS:
		out = out.replace(str(t[0]), str(t[1]))
	return out


## The original's quote [param text] as the editor keeps a line: its codes
## as tokens (a record's string, `@`, dropped).
static func from_codes(text: String) -> String:
	var out := text.replace("@", "")
	for t: Array in TOKENS:
		out = out.replace(str(t[1]), str(t[0]))
	return clean_line(out)


## The lines the base quote set [param style] of the ROM [param rom] says
## for [param category] / [param situation], as the editor keeps lines.
static func original_lines(rom: PackedByteArray, category: int, situation: int, style: int) -> PackedStringArray:
	var out := PackedStringArray()
	var t := MwQuotes.set_at(rom, category, situation, style)
	for src in MwQuotes.strings(rom, t):
		out.append(from_codes(MwGfx.rom_string(rom, src).get_string_from_ascii()))
	return out


## The lines [param coach] says for [param category] / [param situation]:
## his own, else his base set's ([method original_lines]).
static func lines_of(rom: PackedByteArray, coach: MwCustomCoach, category: int, situation: int) -> PackedStringArray:
	var k := key(category, situation)
	if coach.speeches.has(k):
		return coach.speeches[k]
	return original_lines(rom, category, situation, coach.style)


## [param line] as the rink would show it, [param us] the speaking team's
## name, [param city] its city, [param them] the other team's name (the
## port's possessive, as the rink's: [method MwRinkPhases._quote]).
static func expanded(line: String, us: String, city: String, them: String) -> PackedByteArray:
	return MwQuotes.expand(to_codes(line).to_ascii_buffer(), {"[": MwEditorDraw.ascii(city + " " + us),
			"{": MwEditorDraw.ascii(us), "}": MwEditorDraw.ascii(them)}, true)


## Whether [param line] fits the rink's speech box (`$1EA02`, the speech
## font, `$15860`'s layout) and its quote buffer, said by the coach of the
## team [param team_city] [param team_name] against any original team
## ([param rom]: the ROM).
static func fits(rom: PackedByteArray, line: String, team_city: String, team_name: String) -> bool:
	var font := MwRinkPhases.SPEECH_FONT
	var w := MwGfx.s16(rom, MwRinkPhases.SPEECH_BOX_AT + 4)
	var h := MwGfx.s16(rom, MwRinkPhases.SPEECH_BOX_AT + 6)
	var bytes := expanded(line, team_name, team_city, longest_name(rom))
	if bytes.size() >= MwRinkState.QUOTE_SIZE:
		return false
	return not bool(MwTextBox.layout(rom, font, bytes, w, h, MwGfx.u16(rom, font))["cut"])


## The longest of the original teams' names (the other team a line must
## fit with).
static func longest_name(rom: PackedByteArray) -> String:
	var best := ""
	for t in MwTeams.COUNT:
		var n := MwTeams.name_text(rom, t)
		if n.length() > best.length():
			best = n
	return best
