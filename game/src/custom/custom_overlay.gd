class_name MwCustomOverlay
extends RefCounted
## The custom teams as bytes in the original's layouts (plan 38), seen past
## the ROM's end: [method MwRom.data] returns the ROM with these appended,
## so the port's readers - which pass teams, players, coaches and stadiums
## around as addresses and read `rom[record + offset]` - read a custom team
## exactly as they read an original one. The ROM's own bytes are never
## written; the view is never saved (the JSON files are the truth) and is
## rebuilt whenever the bank changes ([method MwCustomTeams.rebuild]). With
## no custom team it is empty and the ROM is read alone.
##
## Per team, from [constant BASE] on (every block word-aligned):
## [codeblock]
## strings        city, name, bio, coach's quote, coach, rink, players' names
## panel colours  7 words (team +$7C points here)
## players        16-byte record (14 + 2 spare for a non-enforcer), then a
##                star entry like `$1CC2C`'s (record.l, portrait data.l,
##                quote set.w) - zeros when he has his species' face
## coach          record (name.l); +4 an entry like `$1CD26`'s (record.l,
##                portrait data.l, quote set.w); +$E a flag word
##                ([constant OWN_COLOURS], [constant OWN_SPEECHES]) and 7
##                colours of his own; +$1E his speech table.l; then his
##                portrait data: his face's with his own voice (+8); then,
##                with speeches of his own, their lines, their sets and
##                his speech table ([method _speeches])
## rink           its 16 ice colours, then the stadium record
## team           the $9E-byte record, then +$9E the special plays (3),
##                +$A1 the playoff place, +$A2 the name's own colours:
##                [constant NAME_SET] when it has some, then 2 words
## [/codeblock]
## Addresses stay far below $FF0000 (RAM to [MwMenuRows]) and 2^24 (the
## bench snapshots keep records as floats).

const BASE := 0x200000
const TEAM_EXTRA := MwTeams.SIZE
const STAR := 16             ## player record + 16: his star entry
const COACH_ENTRY := 4       ## coach record + 4: his entry
const COACH_COLOURS := 0xE   ## coach record + $E: flag.w, 7 words
const COACH_SPEECHES := 0x1E ## coach record + $1E: his speech table.l (with OWN_SPEECHES)
const COACH_SIZE := 0x22     ## a coach's block (a view from before his speeches: $1E)
const OWN_COLOURS := 1       ## coach flag: 7 colours of his own at +$10
const OWN_SPEECHES := 2      ## coach flag: speeches of his own, the table at +$1E (owner, 2026-10-14)
const ICE_BEFORE := 0x20     ## stadium record - $20: its 16 colours
const NAME_COLOURS := 0xA2   ## team record + $A2: flag.w, 2 words (the name's colours)
const PLAYOFF_PLACE := TEAM_EXTRA + 3   ## team record + $A1: the conference place it plays the playoffs in
## The flag of a name with colours of its own (a word no other block starts
## with: older views, a saved replay's, end the record at +$A2).
const NAME_SET := 0x4E43


## The view of [param teams] (custom ids 23..), built on [param rom] (the ROM
## alone). Returns {"bytes": PackedByteArray, "records": PackedInt32Array}.
static func build(rom: PackedByteArray, teams: Array[MwCustomTeam]) -> Dictionary:
	var b := PackedByteArray()
	var records := PackedInt32Array()
	for team in teams:
		records.append(_team(rom, b, team))
	return {"bytes": b, "records": records}


static func _at(b: PackedByteArray) -> int:
	return BASE + b.size()


static func _align(b: PackedByteArray) -> void:
	if b.size() & 1:
		b.append(0)


static func _string(b: PackedByteArray, text: String) -> int:
	var at := _at(b)
	b.append_array(text.to_ascii_buffer())
	b.append(0)
	_align(b)
	return at


static func _long(b: PackedByteArray, at: int, v: int) -> void:
	MwGfx.put_u32(b, at - BASE, v)


static func _word(b: PackedByteArray, at: int, v: int) -> void:
	MwGfx.put_u16(b, at - BASE, v)


static func _words(b: PackedByteArray, words: PackedInt32Array) -> int:
	var at := _at(b)
	for w in words:
		b.append((w >> 8) & 0xFF)
		b.append(w & 0xFF)
	return at


static func _team(rom: PackedByteArray, b: PackedByteArray, team: MwCustomTeam) -> int:
	var city := _string(b, team.city)
	var name := _string(b, team.name)
	var bio := _string(b, team.bio)
	var quote := _string(b, team.coach_quote)
	var panel := _words(b, team.logo_colours)
	# players
	var faces := MwCustomTeams.player_faces(rom)
	var player_at := PackedInt32Array()
	for player in team.players:
		var pname := _string(b, player.name)
		var at := _at(b)
		var player_record := player.record_bytes(pname)
		player_record.resize(STAR)
		b.append_array(player_record)
		b.resize(b.size() + 10)
		if player.face >= 0:
			var f: Array = faces[player.face]
			var q: int = f[1] if f[1] >= 0 else int(faces[6 + player.species - 1][1]) if player.species <= 4 else 7
			_long(b, at + STAR, at)
			_long(b, at + STAR + 4, f[0])
			_word(b, at + STAR + 8, q)
		player_at.append(at)
	# coach
	var custom_coach := team.coach
	var cname := _string(b, custom_coach.name)
	var coach := _at(b)
	b.resize(b.size() + COACH_SIZE)
	_long(b, coach, cname)
	var face: int = MwCustomTeams.coach_faces(rom)[custom_coach.face]
	var data := _at(b)
	b.append_array(rom.slice(face, face + 10))
	var a := face + 10
	while MwGfx.u16(rom, a) != 0xFFFF:
		b.append_array(rom.slice(a, a + 4))
		a += 4
	b.append_array(PackedByteArray([0xFF, 0xFF]))
	if custom_coach.voice >= 0:
		_word(b, data + 8, custom_coach.voice)
	_long(b, coach + COACH_ENTRY, coach)
	_long(b, coach + COACH_ENTRY + 4, data)
	_word(b, coach + COACH_ENTRY + 8, custom_coach.style)
	if not custom_coach.colours.is_empty():
		_word(b, coach + COACH_COLOURS, OWN_COLOURS)
		for i in 7:
			_word(b, coach + COACH_COLOURS + 2 + 2 * i, custom_coach.colours[i])
	if not custom_coach.speeches.is_empty():
		_word(b, coach + COACH_COLOURS, MwGfx.u16(b, coach + COACH_COLOURS - BASE) | OWN_SPEECHES)
		_long(b, coach + COACH_SPEECHES, _speeches(rom, b, custom_coach))
	# rink
	var rname := _string(b, team.rink.name)
	_words(b, team.rink.palette(rom))
	var stadium := _at(b)
	b.append_array(team.rink.record_bytes(rname))
	_align(b)
	# the team record
	var rec := _at(b)
	b.resize(b.size() + NAME_COLOURS + 6)
	_long(b, rec + MwTeams.CITY, city)
	_long(b, rec + MwTeams.NAME, name)
	var forwards := 0
	var backs := 0
	var slots := PackedInt32Array()
	for slot in MwCustomTeam.SLOTS:
		var entry := team.roster[slot]
		var pr := player_at[int(entry["player"])] if entry.has("player") \
				else MwTeams.player(rom, int(entry["team"]), int(entry["slot"]))
		slots.append(pr)
		var o := (b[pr - BASE + 8] if pr >= BASE else rom[pr + 8]) & 0x0F
		if slot % 6 < 3:
			forwards += o
		else:
			backs += o
	b[rec - BASE + MwTeams.FORWARDS] = forwards & 0xFF
	b[rec - BASE + MwTeams.BACKS] = backs & 0xFF
	b[rec - BASE + MwTeams.OVERALL] = (forwards + backs) & 0xFF
	b[rec - BASE + MwTeams.SKULLS] = team.skulls
	_long(b, rec + MwTeams.COACH, coach)
	_long(b, rec + MwTeams.STADIUM, stadium)
	for i in 3:
		b[rec - BASE + MwTeams.NASTY + i] = team.nasty[i]
	for index in slots.size():
		_long(b, rec + MwTeams.ROSTER + 4 * index, slots[index])
	_long(b, rec + MwTeams.LOGO, MwTeams.logo_frame(rom, team.logo))
	_long(b, rec + MwTeams.PANEL, panel)
	for i in 4:
		_word(b, rec + MwTeams.KIT + 2 * i, team.kit[i])
		_word(b, rec + MwTeams.KIT + 8 + 2 * i, team.kit[i])
	for i in 3:
		_word(b, rec + MwTeams.SKIN + 2 * i, team.skin[i])
	_long(b, rec + MwTeams.BIO, bio)
	_long(b, rec + MwTeams.QUOTE, quote)
	for i in 3:
		b[rec - BASE + TEAM_EXTRA + i] = team.specials[i]
	b[rec - BASE + PLAYOFF_PLACE] = team.playoff_place
	if not team.name_colours.is_empty():
		_word(b, rec + NAME_COLOURS, NAME_SET)
		for i in 2:
			_word(b, rec + NAME_COLOURS + 2 + 2 * i, team.name_colours[i])
	return rec


## A custom coach's own speeches ([member MwCustomCoach.speeches]) in the
## original's layout (`$1D404`'s): each situation's lines as strings (their
## tokens as the quote codes), a set for it - the value word of his base
## set's ([member MwCustomCoach.style]: the portrait's talk), the count, the
## strings' pointers - and a table of 8 longs (categories 0-7), each
## pointing to its situations' set pointers
## ([constant MwCoachSpeeches.SITUATIONS]; 0: none of his own - his base
## set's lines). Returns the table's address.
static func _speeches(rom: PackedByteArray, b: PackedByteArray, coach: MwCustomCoach) -> int:
	var sets := {}
	for k: String in coach.speeches:
		var parts := k.split(".")
		var strings := PackedInt32Array()
		for line in (coach.speeches[k] as PackedStringArray):
			strings.append(_string(b, MwCoachSpeeches.to_codes(line)))
		var at := _at(b)
		b.resize(b.size() + 4 + 4 * strings.size())
		_word(b, at, MwQuotes.value_of(rom, MwQuotes.set_at(rom, int(parts[0]), int(parts[1]), coach.style)))
		_word(b, at + 2, strings.size())
		for i in strings.size():
			_long(b, at + 4 + 4 * i, strings[i])
		sets[k] = at
	var table := _at(b)
	var categories := MwCoachSpeeches.SITUATIONS.size()
	b.resize(b.size() + 4 * categories)
	for category in categories:
		var situations := _at(b)
		b.resize(b.size() + 4 * int(MwCoachSpeeches.SITUATIONS[category]))
		_long(b, table + 4 * category, situations)
		for situation in int(MwCoachSpeeches.SITUATIONS[category]):
			_long(b, situations + 4 * situation, int(sets.get(MwCoachSpeeches.key(category, situation), 0)))
	return table


## True for an address in the view.
static func is_custom(address: int) -> bool:
	return address >= BASE and address < 0xFF0000


## The special play in slot [param i] (0-2) of team record [param record]
## (the original: 9, 10, 11 for every team, `$3698`).
static func special(rom: PackedByteArray, record: int, i: int) -> int:
	if is_custom(record):
		return rom[record + TEAM_EXTRA + i]
	return 9 + i


## The conference place (0-19) the custom team of record [param record]
## plays a playoff run in (MwTeams.playoff_place).
static func playoff_place(rom: PackedByteArray, record: int) -> int:
	return rom[record + PLAYOFF_PLACE]


## A custom team's name's own 2 colours (team record [param record]), empty
## for the game's (every original team, and a custom one without).
static func name_colours(rom: PackedByteArray, record: int) -> PackedInt32Array:
	if not is_custom(record) or record + NAME_COLOURS + 6 > rom.size() \
			or MwGfx.u16(rom, record + NAME_COLOURS) != NAME_SET:
		return PackedInt32Array()
	return MwGfx.words(rom, record + NAME_COLOURS + 2, 2)


## A custom coach's own 7 colours (shirt 2-3, pants 5-6, skin 7-8, shade 9),
## empty for his team's (every original coach).
static func coach_colours(rom: PackedByteArray, coach: int) -> PackedInt32Array:
	if not is_custom(coach) or (MwGfx.u16(rom, coach + COACH_COLOURS) & OWN_COLOURS) == 0:
		return PackedInt32Array()
	return MwGfx.words(rom, coach + COACH_COLOURS + 2, 7)


## The set of a custom coach's own lines (coach record [param coach]) for
## [param category] / [param situation] ([MwRinkPhases]' speeches, 0-7):
## its address ([method _speeches]), 0 when he has none of his own there
## (he says his base set's) and for every original coach. Read with care:
## a view may be a saved replay's (a shared file) - a table or a set
## outside the view, or a line without its end, is none.
static func coach_speech_set(rom: PackedByteArray, coach: int, category: int, situation: int) -> int:
	if not is_custom(coach) or not _inside(rom, coach + COACH_COLOURS, COACH_SIZE - COACH_COLOURS) \
			or (MwGfx.u16(rom, coach + COACH_COLOURS) & OWN_SPEECHES) == 0:
		return 0
	if category < 0 or category >= MwCoachSpeeches.SITUATIONS.size() or situation < 0 \
			or situation >= int(MwCoachSpeeches.SITUATIONS[category]):
		return 0
	var at := MwGfx.u32(rom, coach + COACH_SPEECHES) + 4 * category
	if not _inside(rom, at, 4):
		return 0
	at = MwGfx.u32(rom, at) + 4 * situation
	if not _inside(rom, at, 4):
		return 0
	var set_addr := MwGfx.u32(rom, at)
	if set_addr == 0 or not _inside(rom, set_addr, 4):
		return 0
	var count := MwGfx.u16(rom, set_addr + 2)
	if count == 0 or count > MwCoachSpeeches.LINES_MAX or not _inside(rom, set_addr + 4, 4 * count):
		return 0
	for i in count:
		var line := MwGfx.u32(rom, set_addr + 4 + 4 * i)
		if not _inside(rom, line, 1) or rom.find(0, line) < 0:
			return 0
	return set_addr


## Whether [param size] bytes from [param at] are in the view.
static func _inside(rom: PackedByteArray, at: int, size: int) -> bool:
	return at >= BASE and at + size <= rom.size()
