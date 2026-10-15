class_name MwCustomPlayer
extends RefCounted
## A custom player (plan 38, CREATE-A-TEAM): everything a player record
## holds (14 bytes, 16 for an enforcer; docs/re/menus.md, Team records), and
## his face, as plain values. Port-only: [MwCustomOverlay] turns him into a
## record in the original's layout, the JSON file of his team keeps him
## ([method to_dict] / [method from_dict]). Values are always valid: every
## way in goes through [method validate].
##
## The record's layout: [MwPlayerRecord].

## The ten ratings by name, in the team description's order, and where
## each sits in the record ([MwPlayerRecord]: plan 40, D4).
const RATINGS := MwPlayerRecord.RATINGS
const NIBBLES := MwPlayerRecord.NIBBLES
## Species by number (+7 low nibble): skaters 1-3, goalies 4.
const SPECIES := ["", "skeleton", "robot", "troll", "goalie"]
const GOALIE := 4
## The weapons an enforcer may own (+$E low nibble; 3, bombs, would throw
## practically for ever and is not offered).
const WEAPONS := [0, 1, 2, 4]
## Name limits (the Reserves list's 14 cells; header, panel and Fight Card
## split at the first space into two lines of 10).
const NAME_MAX := 14
const WORD_MAX := 10

var name := "NEW PLAYER"
var number := 0                ## 0-99
var weight := 3                ## 1-6: check and slash damage only
var species := 1               ## 1-4 (4: goalie)
var side := 0                  ## 0 left, 1 right (position rating, AI)
var ratings := {}              ## rating name -> 0-10
var overall := -1              ## 0-10, -1: automatic (the rounded mean of the ten)
var enforcer := false
var aggression := 5            ## enforcers: 0-10
var weapon := 0                ## enforcers: one of WEAPONS
var instinct := 5              ## enforcers: 0-10
var bonus := 5                 ## enforcers: weapon-hit bonus 0-15
## His face: an index into [method MwCustomTeams.player_faces] (0-10), -1 his
## species' face. A face makes him a "star" (own portrait, voice, quotes).
var face := -1
## Informative: the original player he was copied from ({"team", "slot"}), or {}.
var source := {}


func _init() -> void:
	for r in RATINGS:
		ratings[r] = 5


## The overall rating used: [member overall], or the rounded mean of the ten.
func overall_value() -> int:
	if overall >= 0:
		return overall
	var sum := 0
	for r in RATINGS:
		sum += int(ratings[r])
	return clampi(roundi(sum / 10.0), 0, 10)


## True for a goalie ([member species] [constant GOALIE]).
func is_goalie() -> bool:
	return species == GOALIE


## Clamp everything into range (names cut to the limits and the charset).
func validate() -> void:
	name = MwCustomTeam.clean_text(name, NAME_MAX)
	var words := name.split(" ", false)
	for i in words.size():
		words[i] = words[i].substr(0, WORD_MAX)
	name = " ".join(words)
	if name == "":
		name = "NO NAME"
	number = clampi(number, 0, 99)
	weight = clampi(weight, 1, 6)
	species = clampi(species, 1, 4)
	if species == GOALIE:
		enforcer = false               # none in the original; a goalie's code isn't an enforcer's
	side = clampi(side, 0, 1)
	for r in RATINGS:
		ratings[r] = clampi(int(ratings.get(r, 5)), 0, 10)
	for k in ratings.keys():
		if not k in RATINGS:
			ratings.erase(k)
	overall = clampi(overall, -1, 10)
	aggression = clampi(aggression, 0, 10)
	if not weapon in WEAPONS:
		weapon = 0
	instinct = clampi(instinct, 0, 10)
	bonus = clampi(bonus, 0, 15)
	face = clampi(face, -1, 10)


## The record bytes (16 for an enforcer, else 14) with the name at [param name_at].
func record_bytes(name_at: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(16 if enforcer else 14)
	MwGfx.put_u32(b, 0, name_at)
	b[4] = number
	b[5] = 0
	b[6] = weight
	b[7] = (side << 4) | species
	b[8] = overall_value()
	for r in RATINGS:
		var n: Array = NIBBLES[r]
		var v: int = ratings[r]
		b[n[0]] |= (v << 4) if n[1] else v
	if enforcer:
		b[0xD] |= 0x10
		b[0xE] = (aggression << 4) | weapon
		b[0xF] = (instinct << 4) | bonus
	return b


## A custom copy of the original player record at [param record].
static func from_record(rom: PackedByteArray, record: int) -> MwCustomPlayer:
	var player := MwCustomPlayer.new()
	player.name = MwGfx.rom_string(rom, MwGfx.u32(rom, record)).get_string_from_ascii()
	player.number = rom[record + 4]
	player.weight = rom[record + 6]
	player.species = rom[record + 7] & 0x0F
	player.side = rom[record + 7] >> 4
	for r in RATINGS:
		player.ratings[r] = MwPlayerRecord.nibble(rom, record, r)
	player.overall = rom[record + 8] & 0x0F
	if player.overall == player.overall_auto():
		player.overall = -1
	player.enforcer = rom[record + 0xD] >> 4 != 0
	if player.enforcer:
		player.aggression = rom[record + 0xE] >> 4
		player.weapon = rom[record + 0xE] & 0x0F
		player.instinct = rom[record + 0xF] >> 4
		player.bonus = rom[record + 0xF] & 0x0F
	player.face = MwCustomTeams.face_of_record(rom, record)
	player.validate()
	return player


## The automatic overall (the rounded mean of the ten ratings).
func overall_auto() -> int:
	var keep := overall
	overall = -1
	var v := overall_value()
	overall = keep
	return v


## The player as his team's JSON file holds him: species and side by name, [code]"auto"[/code]
## for an automatic overall, an enforcer's values only for an enforcer, the source when known.
func to_dict() -> Dictionary:
	var d := {
		"name": name, "number": number, "weight": weight, "species": SPECIES[species],
		"side": "right" if side == 1 else "left", "ratings": ratings.duplicate(),
		"overall": "auto" if overall < 0 else overall, "face": face,
	}
	if enforcer:
		d["enforcer"] = {"aggression": aggression, "weapon": weapon, "instinct": instinct, "bonus": bonus}
	if not source.is_empty():
		d["source"] = source.duplicate()
	return d


## A player read from his JSON form [param d] ([method to_dict]) through MwPlain's readers, then
## made valid ([method validate]).
static func from_dict(d: Dictionary) -> MwCustomPlayer:
	var player := MwCustomPlayer.new()
	player.name = MwPlain.text(d.get("name"), player.name)
	player.number = MwPlain.num(d.get("number"), 0)
	player.weight = MwPlain.num(d.get("weight"), 3)
	player.species = maxi(1, SPECIES.find(MwPlain.text(d.get("species"), "skeleton")))
	player.side = 1 if MwPlain.text(d.get("side"), "left") == "right" else 0
	var r: Variant = d.get("ratings", {})
	if r is Dictionary:
		for k in RATINGS:
			player.ratings[k] = MwPlain.num(r.get(k), 5)
	var o: Variant = d.get("overall", "auto")
	player.overall = -1 if o is String else MwPlain.num(o, -1)
	player.face = MwPlain.num(d.get("face"), -1)
	var enforcer_value: Variant = d.get("enforcer")
	player.enforcer = enforcer_value is Dictionary
	if player.enforcer:
		player.aggression = MwPlain.num(enforcer_value.get("aggression"), 5)
		player.weapon = MwPlain.num(enforcer_value.get("weapon"), 0)
		player.instinct = MwPlain.num(enforcer_value.get("instinct"), 5)
		player.bonus = MwPlain.num(enforcer_value.get("bonus"), 5)
	var source_value: Variant = d.get("source")
	if source_value is Dictionary:
		player.source = {"team": MwPlain.num(source_value.get("team"), 0),
				"slot": MwPlain.num(source_value.get("slot"), 0)}
	player.validate()
	return player
