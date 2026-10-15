class_name MwPlayerRecord
extends RefCounted
## The original's player record (14 bytes, 16 for an enforcer;
## docs/re/menus.md, Team records). Plan 40 (D4): the one description of
## its rating nibbles - the team description's Player page, CREATE-A-TEAM's
## RATINGS page and [MwCustomPlayer] read them from here (the sims read
## their own bytes as the 68000 does).
##
## [codeblock]
## +0 name (string pointer)  +4 number  +5 0  +6 weight  +7 side << 4 | species
## +8 STAMINA << 4 | overall  +9 FIGHTING << 4 | SKATING  +A PASSING << 4 | SPEED
## +B OFFENSE << 4 | DEFENSE  +C POWER << 4 | ACCURACY   +D enforcer << 4 | CHECKING
## +E aggression << 4 | weapon  +F instinct << 4 | weapon-hit bonus (enforcers)
## [/codeblock]

const NAME := 0
const NUMBER := 4
const WEIGHT := 6
const SPECIES := 7         ## low nibble: species; high: side
const OVERALL := 8         ## low nibble
const ENFORCER := 0xD      ## high nibble set: an enforcer (two more bytes)
const AGGRESSION := 0xE    ## high nibble; low: his weapon
const INSTINCT := 0xF      ## high nibble; low: his weapon-hit bonus

## The ten ratings by name, in the team description's order (a goalie's
## labels differ: POWER / ACCURACY are BLOCK LEFT / RIGHT, CHECKING is
## CONSISTENCY, FIGHTING is WOUNDING).
const RATINGS := ["skating", "speed", "stamina", "power", "accuracy", "offense", "defense",
		"passing", "checking", "fighting"]
## Where each rating sits in the record: [byte, high nibble] - the ten, and
## an enforcer's aggression and instinct.
const NIBBLES := {
	"stamina": [8, true], "skating": [9, false], "fighting": [9, true], "speed": [0xA, false],
	"passing": [0xA, true], "defense": [0xB, false], "offense": [0xB, true],
	"accuracy": [0xC, false], "power": [0xC, true], "checking": [0xD, false],
	"aggression": [AGGRESSION, true], "instinct": [INSTINCT, true],
}
## The team description's two columns, row by row (`$C278`; the sixth row
## an enforcer's only, never a goalie's).
const COLUMNS := [["skating", "speed", "stamina", "power", "accuracy", "aggression"],
		["offense", "defense", "passing", "checking", "fighting", "instinct"]]


## Rating [param rating] ([constant NIBBLES]) of the player record at
## [param record].
static func nibble(rom: PackedByteArray, record: int, rating: String) -> int:
	var n: Array = NIBBLES[rating]
	var b := rom[record + int(n[0])]
	return b >> 4 if n[1] else b & 0x0F


## The record at [param record] is an enforcer's.
static func enforcer(rom: PackedByteArray, record: int) -> bool:
	return rom[record + ENFORCER] >> 4 != 0
