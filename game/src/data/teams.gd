class_name MwTeams
extends RefCounted
## The original's team records (`$18D8A`, 23 x `$9E` bytes; `team_record`
## $368A), read from the ROM. Offsets as far as they are known
## (docs/re/menus.md, Team records):
##
## [codeblock]
## +$00 city string      +$04 name string    +$0B featured players (panel)
## +$0C coach record     +$10 stadium record +$14 nasty plays (3 IDs)
## +$18 roster: 4 lines x 6 player pointers (C, LW, RW, LD, RD, G)
## +$78 logo frame       +$7C panel colours  +$80 colour words (palettes.gd)
## +$96 bio text         +$9A coach's quote
## [/codeblock]
##
## A coach record starts with the coach's name. A player record:
## [codeblock]
## +0 name string  +4 number  +7 species (low nibble)
## +8..+F ratings, a nibble each (team description, Player page)
## [/codeblock]

const TABLE := 0x18D8A
const SIZE := 0x9E
const COUNT := 23


static func record(team: int) -> int:
	return TABLE + team * SIZE


static func city(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team))


static func name(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + 4)


static func coach(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + 0x0C)


static func nasty_play(rom: PackedByteArray, team: int, i: int) -> int:
	return MwGfx.s8(rom, record(team) + 0x14 + i)


static func bio(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + 0x96)


static func coach_quote(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + 0x9A)


static func featured(rom: PackedByteArray, team: int) -> int:
	return rom[record(team) + 0x0B]


static func stadium_record(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + 0x10)


## Roster slot [param index] = line * 6 + position.
static func player(rom: PackedByteArray, team: int, index: int) -> int:
	return MwGfx.u32(rom, record(team) + 0x18 + 4 * index)


static func logo_frame(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + 0x78)


static func panel_colours(rom: PackedByteArray, team: int) -> int:
	return MwGfx.u32(rom, record(team) + 0x7C)
