class_name MwTeams
extends RefCounted
## The original's team records (`$18D8A`, 23 x `$9E` bytes; `team_record`
## $368A), read from the ROM. Offsets as far as they are known
## (docs/re/menus.md, Team records) - plan 40 (D4): each field has one name
## here, the sims and the overlay read and write through them:
##
## [codeblock]
## +$00 city string      +$04 name string
## +$08 forwards' overall ratings summed, +$09 the backs', +$0A both
## +$0B skulls (the menus' icons, the CPU's playoff strength, the crowd)
## +$0C coach record     +$10 stadium record +$14 nasty plays (3 IDs)
## +$18 roster: 4 lines x 6 player pointers (C, LW, RW, LD, RD, G)
## +$78 logo frame       +$7C panel colours  +$80 kit colour words (4,
## again at +$88)        +$90 skin colour words (3)
## +$96 bio text         +$9A coach's quote
## [/codeblock]
##
## A coach record starts with the coach's name. A player record:
## [MwPlayerRecord].

const TABLE := 0x18D8A
const SIZE := 0x9E
const CITY := 0x00
const NAME := 0x04
const FORWARDS := 0x08
const BACKS := 0x09
const OVERALL := 0x0A
const SKULLS := 0x0B
const COACH := 0x0C
const STADIUM := 0x10
const NASTY := 0x14
const LOGO := 0x78
const PANEL := 0x7C
const KIT := 0x80
const SKIN := 0x90
const BIO := 0x96
const QUOTE := 0x9A
## The original's teams (ids 0-22). Custom teams (plan 38, [MwCustomTeams])
## follow as 23, 24, ...: [method count] is all of them.
const COUNT := 23
## The team rows' order (`$1C1A4`: position -> team) and its inverse (`$1C1BB`).
const MENU_ORDER := 0x1C1A4
const MENU_POSITION := 0x1C1BB


## Team [param team]'s record: the original's table, or a custom team's in
## [MwCustomOverlay]'s view of [method MwRom.data].
static func record(team: int) -> int:
	if team >= COUNT:
		var r := MwCustomTeams.record_of(team)
		return r if r != 0 else TABLE        # a custom team no longer there: team 0's, not garbage
	return TABLE + team * SIZE


## The team id of a team record (original or custom; -1: neither).
static func id_of(team_record: int) -> int:
	if MwCustomOverlay.is_custom(team_record):
		return MwCustomTeams.id_of(team_record)
	return (team_record - TABLE) / SIZE


## Every team the menus offer: the original's 23 and the bank's (the
## editor's working copy and a saved replay's teams are read by id - [method
## record] - but never offered; MwCustomTeams.readable counts them).
static func count() -> int:
	return COUNT + MwCustomTeams.count()


## Plan 40 (D3): team [param team] is a custom team the game reads - by its
## record in the view (the bank's, a saved replay's, the editor's working
## copy), the one path the game's readers take.
static func is_custom(team: int) -> bool:
	return team >= COUNT and MwCustomTeams.record_of(team) != 0


## The place team [param team] plays a playoff run in (plan 38): its own
## for an original team, a custom team's conference place (its record's
## +$A1, [method MwCustomOverlay.playoff_place]).
static func playoff_place(rom: PackedByteArray, team: int) -> int:
	return MwCustomOverlay.playoff_place(rom, record(team)) if is_custom(team) else team


## The address of team [param team]'s city string (+$00).
static func city(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + CITY)


## The address of team [param team]'s name string (+$04); [method name_text] gives the text.
static func name(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + NAME)


## The address of team [param team]'s coach record (+$0C), which starts with the coach's name.
static func coach(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + COACH)


## The ID of team [param team]'s nasty play [param i] (0-2; +$14, a signed byte).
static func nasty_play(rom: PackedByteArray, team: int, i: int) -> int:
	return MwGfx.s8(rom, record(team) + NASTY + i)


## The address of team [param team]'s bio text (+$96).
static func bio(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + BIO)


## The address of team [param team]'s coach's quote (+$9A).
static func coach_quote(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + QUOTE)


## The team's skulls (+$0B: the menus' icons - the featured players -, the
## CPU's strength in playoff games, the crowd's mix).
static func skulls(rom: PackedByteArray, team: int) -> int:
	return rom[record(team) + SKULLS]


## The address of team [param team]'s stadium record (+$10).
static func stadium_record(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + STADIUM)


## Roster slot [param index] = line * 6 + position.
static func player(rom: PackedByteArray, team: int, index: int) -> int:
	return roster_record(rom, record(team), index)


## The team record's roster (+$18): 24 player record pointers, roster slot =
## line * 6 + position.
const ROSTER := 0x18


## The player record in roster slot [param slot] of the team record at
## [param team_record] (an address, as the rink's teams hold it; 0: empty).
static func roster_record(rom: PackedByteArray, team_record: int, slot: int) -> int:
	return MwGfx.u32(rom, team_record + ROSTER + 4 * slot)


## The address of team [param team]'s logo frame (+$78).
static func logo_frame(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + LOGO)


## The address of team [param team]'s panel colours (+$7C: 7 colour words).
static func panel_colours(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + PANEL)


## Team [param team]'s name as text (the lists, the file names, the
## editors' pages).
static func name_text(rom: PackedByteArray, team: int) -> String:
	return MwGfx.rom_string(rom, name(rom, team)).get_string_from_ascii()
