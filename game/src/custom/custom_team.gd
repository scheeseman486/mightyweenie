class_name MwCustomTeam
extends RefCounted
## A custom team (plan 38, CREATE-A-TEAM): everything the original keeps for
## a team - its record (`$18D8A`, docs/re/menus.md), the side tables keyed
## by its address (coach face and lines, stars) and the code's per-team
## choices (menu order, conference place, special plays) - as plain fields,
## with its coach, players and rink. One readable JSON file per team
## (`user://teams/<id>.json`, [MwCustomTeams]); [method to_dict] /
## [method from_dict] / [method validate] are the only ways in and out, so a
## team in memory is always a valid one. [MwCustomOverlay] turns it into
## records in the original's layouts for the game.

const VERSION := 1
## The characters every font the names are drawn in has (the big, menu and
## dark fonts and the matchup's), without the quote codes `@ [ { }`.
const CHARSET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !\"#%',-.:?_"
const CITY_MAX := 10
const NAME_MAX := 10
## Bio and coach's quote: 7 lines of 36 cells after word wrap.
const TEXT_MAX := 7 * 36
## The play names' order (`$1F07C`): 0 is the "fake out" a used play becomes.
const PLAYS := ["fake_out", "exploding_puck", "rocket_puck", "waste_goalie", "nasty_goalie",
		"player_blast", "confusion", "armed_force", "skunk", "bribe_ref", "waste_ref", "jail_break"]
const WASTE_THE_REF := 10
## Nasty plays are 1-8 (the bio page lists their names); special plays any
## of 1-11, the second always Waste the Ref (the penalty box reads it).
const NASTY_MAX := 8
const SPECIAL_FIXED := 1
const POSITIONS := ["C", "LW", "RW", "LD", "RD", "G"]
const SLOTS := 24
const GOALIE_COLUMN := 5

## The file name without `.json` ("" until saved).
var id := ""
## Whether the game plays it (owner, 2026-10-11: CREATE-A-TEAM's list
## switches a team on and off): off, it stays in its file and the editor's
## list but has no game id, no team row and no place in a start record
## ([member MwCustomTeams.disabled]). Its file says `"enabled": false`
## only when off.
var enabled := true
var city := "NEW CITY"
var name := "NEW TEAMS"
var skulls := 3                          ## 0-6
## Where the team comes in the team rows: after this original team (menu
## order, `$1C1A4`), -1 first.
var menu_after := -1
## The original team (0-19) whose conference place it takes in the playoffs.
var playoff_place := 0
var logo := 0                            ## the logo of this original team
var logo_colours := PackedInt32Array()   ## 7 words: the panel colours 2-8
var kit := PackedInt32Array()            ## 4 words: shirt light / dark, pants light / dark
var skin := PackedInt32Array()           ## 3 words: skin light / dark, shade
## The name's colours of its own (owner, 2026-10-11: set apart from the
## rest): 2 words, the big letters' face and shade (colours 2-3 of
## whatever line the game writes the name on - its shirt's on most screens,
## its panel's on the stats); empty: as the game has them.
var name_colours := PackedInt32Array()
var bio := ""
var coach_quote := ""
var nasty := PackedInt32Array([1, 2, 3])         ## per period
var specials := PackedInt32Array([9, 10, 11])    ## [1] is always 10
## 24 slots, line * 6 + position: {"team": t, "slot": s} (an original
## player) or {"player": i} (an index into [member players]).
var roster: Array[Dictionary] = []
var players: Array[MwCustomPlayer] = []
var coach := MwCustomCoach.new()
var rink := MwCustomRink.new()
## Results kept by another part of the port: kept as read, never edited here.
var stats: Variant = null


## Keep the characters of [constant CHARSET], at most [param limit].
static func clean_text(text: String, limit: int) -> String:
	var out := ""
	for c in text:
		if CHARSET.contains(c):
			out += c
	return out.strip_edges().substr(0, limit)


## Plan 38 with plan 35: a team can arrive from the network (an online
## match's start record or snapshot: MwCustomTeams.use_teams), so every
## [code]from_dict[/code] reads its values through MwPlain's readers (plan
## 40, S6) - a value of the wrong type gives the default instead of a script
## error, a string is cut before it is cleaned (MwPlain.TEXT_READ) - and
## every list is read up to a bound; [method validate] clamps the rest.
## Lists read at most: colour words (longer lists are no colours), custom
## players, hazards.
const WORDS_READ := 32
const PLAYERS_READ := 256
const HAZARDS_READ := 256


## Colour words as text ("0E64").
static func words_out(words: PackedInt32Array) -> Array:
	var out := []
	for w in words:
		out.append("%04X" % (w & 0x0EEE))
	return out


## Colour words read back from [method words_out]'s text ([param a]; numbers are taken too),
## each masked to [code]0x0EEE[/code]; none (the default) when the list is longer than
## [constant WORDS_READ].
static func words_in(a: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if a.size() > WORDS_READ:
		return out                             # no colour list is this long: the default
	for w: Variant in a:
		out.append((MwPlain.hex(w) if w is String else MwPlain.num(w)) & 0x0EEE)
	return out


## A copy of original team [param team]: its texts, colours, plays, coach,
## rink and players (referenced, not copied).
static func from_original(rom: PackedByteArray, team: int) -> MwCustomTeam:
	var custom_team := MwCustomTeam.new()
	var rec := MwTeams.record(team)
	custom_team.city = _rom_text(rom, MwTeams.city(rom, team))
	custom_team.name = _rom_text(rom, MwTeams.name(rom, team))
	custom_team.skulls = MwTeams.skulls(rom, team)
	custom_team.menu_after = team
	custom_team.playoff_place = MwCustomTeams.conference_place(team)
	custom_team.logo = team
	custom_team.logo_colours = MwGfx.words(rom, MwTeams.panel_colours(rom, team), 7)
	custom_team.kit = MwGfx.words(rom, rec + MwTeams.KIT, 4)
	custom_team.skin = MwGfx.words(rom, rec + MwTeams.SKIN, 3)
	custom_team.bio = _rom_text(rom, MwTeams.bio(rom, team))
	custom_team.coach_quote = _rom_text(rom, MwTeams.coach_quote(rom, team))
	for i in 3:
		custom_team.nasty[i] = MwTeams.nasty_play(rom, team, i)
	for slot in SLOTS:
		custom_team.roster.append({"team": team, "slot": slot})
	custom_team.coach = MwCustomCoach.from_team(rom, team)
	custom_team.rink = MwCustomRink.from_stadium(rom, team)
	custom_team.validate(rom)
	return custom_team


static func _rom_text(rom: PackedByteArray, a: int) -> String:
	return MwGfx.rom_string(rom, a).get_string_from_ascii().replace("\n", " ")


## Everything into range: texts cut to their limits and the charset, plays
## distinct (slot 2 Waste the Ref), a full roster with goalies in the G
## column, skaters elsewhere and nobody twice.
func validate(rom: PackedByteArray) -> void:
	city = clean_text(city, CITY_MAX)
	name = clean_text(name, NAME_MAX)
	if city == "":
		city = "CITY"
	if name == "":
		name = "TEAM"
	skulls = clampi(skulls, 0, 6)
	menu_after = clampi(menu_after, -1, MwTeams.COUNT - 1)
	playoff_place = clampi(playoff_place, 0, 19)
	logo = clampi(logo, 0, MwTeams.COUNT - 1)
	logo_colours = _words(logo_colours, 7, MwGfx.words(rom, MwTeams.panel_colours(rom, logo), 7))
	kit = _words(kit, 4, MwGfx.words(rom, MwTeams.record(logo) + 0x80, 4))
	skin = _words(skin, 3, MwGfx.words(rom, MwTeams.record(logo) + 0x90, 3))
	if name_colours.size() != 2:
		name_colours = PackedInt32Array()
	for i in name_colours.size():
		name_colours[i] &= 0x0EEE
	bio = clean_text(bio, TEXT_MAX)
	coach_quote = clean_text(coach_quote, TEXT_MAX)
	_plays()
	for player in players:
		player.validate()
	_roster(rom)
	coach.validate()
	rink.validate()


static func _words(w: PackedInt32Array, n: int, fallback: PackedInt32Array) -> PackedInt32Array:
	if w.size() != n:
		return fallback
	var out := w.duplicate()
	for i in n:
		out[i] &= 0x0EEE
	return out


## Plays: nasty 1-8, specials 1-11 with [1] = Waste the Ref, none twice
## (a later duplicate takes the first free play).
func _plays() -> void:
	nasty.resize(3)
	specials.resize(3)
	specials[SPECIAL_FIXED] = WASTE_THE_REF
	var used := [WASTE_THE_REF]
	for i in 3:
		var v := nasty[i]
		if v < 1 or v > NASTY_MAX or v in used:
			v = _free_play(used, NASTY_MAX)
		nasty[i] = v
		used.append(v)
	for i in [0, 2]:
		var v := specials[i]
		if v < 1 or v > 11 or v in used:
			v = _free_play(used, 11)
		specials[i] = v
		used.append(v)


static func _free_play(used: Array, top: int) -> int:
	for v in range(1, top + 1):
		if not v in used:
			return v
	return 1


## The roster's 24 slots made valid (see [method validate]); a slot that
## isn't is filled from [member playoff_place]'s roster, then any original.
func _roster(rom: PackedByteArray) -> void:
	roster.resize(SLOTS)
	var seen := {}
	for slot in SLOTS:
		var entry: Variant = roster[slot]
		var key := _key(entry)
		if key == "" or seen.has(key) or not _fits(rom, entry, slot):
			roster[slot] = {}
			continue
		seen[key] = true
	for slot in SLOTS:
		if not roster[slot].is_empty():
			continue
		var found := false
		for t in [playoff_place] + range(MwTeams.COUNT):
			for k in [slot] + range(slot % 6, SLOTS, 6):
				var candidate := {"team": t, "slot": k}
				if not seen.has(_key(candidate)) and _fits(rom, candidate, slot):
					roster[slot] = candidate
					seen[_key(candidate)] = true
					found = true
					break
			if found:
				break


func _key(entry: Variant) -> String:
	if not entry is Dictionary:
		return ""
	if entry.has("player"):
		var i := int(entry["player"])
		return "p%d" % i if i >= 0 and i < players.size() else ""
	if entry.has("team") and entry.has("slot"):
		var t := int(entry["team"])
		var k := int(entry["slot"])
		return "t%d.%d" % [t, k] if t >= 0 and t < MwTeams.COUNT and k >= 0 and k < SLOTS else ""
	return ""


## True when [param entry] may stand in slot [param slot] (goalies in the G column only).
func _fits(rom: PackedByteArray, entry: Dictionary, slot: int) -> bool:
	var species := 0
	if entry.has("player"):
		species = players[int(entry["player"])].species
	else:
		species = rom[MwTeams.player(rom, int(entry["team"]), int(entry["slot"])) + 7] & 0x0F
	return (species == MwCustomPlayer.GOALIE) == (slot % 6 == GOALIE_COLUMN)


## The player record of slot [param slot]'s original player, 0 for a custom one.
func original_record(rom: PackedByteArray, slot: int) -> int:
	var entry := roster[slot]
	if entry.has("player"):
		return 0
	return MwTeams.player(rom, int(entry["team"]), int(entry["slot"]))


## The team as its JSON file holds it: plays by name, colours as text, the roster as 4 lines of
## 6 slots, [code]"enabled": false[/code] only when off.
func to_dict() -> Dictionary:
	var lines := []
	for l in 4:
		var line := []
		for k in 6:
			line.append(roster[6 * l + k].duplicate())
		lines.append(line)
	var ps := []
	for player in players:
		ps.append(player.to_dict())
	var np := []
	for v in nasty:
		np.append(PLAYS[v])
	var sp := []
	for v in specials:
		sp.append(PLAYS[v])
	var d := {
		"version": VERSION, "city": city, "name": name, "skulls": skulls,
		"menu_after": menu_after, "playoff_place": playoff_place, "logo": logo,
		"logo_colours": words_out(logo_colours), "kit": words_out(kit), "skin": words_out(skin),
		"name_colours": null if name_colours.is_empty() else words_out(name_colours),
		"bio": bio, "coach_quote": coach_quote, "nasty_plays": np, "special_plays": sp,
		"coach": coach.to_dict(), "roster": lines, "players": ps, "rink": rink.to_dict(),
		"stats": stats,
	}
	if not enabled:
		d["enabled"] = false
	return d


## A team read from its JSON form [param d] ([method to_dict]) through MwPlain's readers, each
## list up to its bound, then made valid against [param rom] ([method validate]).
static func from_dict(rom: PackedByteArray, d: Dictionary) -> MwCustomTeam:
	var team := MwCustomTeam.new()
	team.city = MwPlain.text(d.get("city"), team.city)
	team.name = MwPlain.text(d.get("name"), team.name)
	team.skulls = MwPlain.num(d.get("skulls"), 3)
	team.enabled = MwPlain.flag(d.get("enabled"), true)
	team.menu_after = MwPlain.num(d.get("menu_after"), -1)
	team.playoff_place = MwPlain.num(d.get("playoff_place"), 0)
	team.logo = MwPlain.num(d.get("logo"), 0)
	for f in ["logo_colours", "kit", "skin"]:
		var w: Variant = d.get(f)
		if w is Array:
			team.set(f, words_in(w))
	var nc: Variant = d.get("name_colours")
	if nc is Array:
		team.name_colours = words_in(nc)
	team.bio = MwPlain.text(d.get("bio"))
	team.coach_quote = MwPlain.text(d.get("coach_quote"))
	var np: Variant = d.get("nasty_plays", [])
	var sp: Variant = d.get("special_plays", [])
	for i in 3:
		if np is Array and i < np.size():
			team.nasty[i] = maxi(0, PLAYS.find(MwPlain.text(np[i])))
		if sp is Array and i < sp.size():
			team.specials[i] = maxi(0, PLAYS.find(MwPlain.text(sp[i])))
	var c: Variant = d.get("coach")
	if c is Dictionary:
		team.coach = MwCustomCoach.from_dict(c)
	var ps: Variant = d.get("players", [])
	if ps is Array:
		for player: Variant in ps:
			if team.players.size() >= PLAYERS_READ:
				break
			if player is Dictionary:
				team.players.append(MwCustomPlayer.from_dict(player))
	var lines: Variant = d.get("roster", [])
	if lines is Array:
		for line: Variant in lines:
			if line is Array:
				for entry: Variant in line:
					if team.roster.size() < SLOTS:
						team.roster.append(_slot_in(entry))
	var r: Variant = d.get("rink")
	if r is Dictionary:
		team.rink = MwCustomRink.from_dict(r)
	team.stats = d.get("stats")
	team.validate(rom)
	return team


static func _slot_in(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	if entry.has("player"):
		return {"player": MwPlain.num(entry["player"], -1)}
	if entry.has("team") and entry.has("slot"):
		return {"team": MwPlain.num(entry["team"], -1), "slot": MwPlain.num(entry["slot"], -1)}
	return {}
