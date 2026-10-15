class_name MwMatchSetup
extends RefCounted
## The game setup the main menu edits: the original's 10 bytes at
## `$FFB0DE`-`$FFB0E7` (docs/re/screens.md, Main menu), named. Values are
## read from the ROM's tables (boot defaults, attract demo); nothing here is
## a copy of them.

## `setup_defaults` ($458E) copies these 10 bytes at boot.
const BOOT_DEFAULTS := 0x1C190
## `attract_setup_begin` ($459C) loads these; $FF = picked at random.
const DEMO := 0x1C19A
const RANDOM := 0xFF
## Pad mode 5: CPU vs CPU (the attract demo).
const PADS_DEMO := 5

var team_a := 0            ## $FFB0DE: team on the P1 side
var team_b := 0            ## $FFB0DF
var pads := 0              ## $FFB0E0: pad mode 0-4 (5 = demo)
var play_mode := 0         ## $FFB0E1: regular, playoffs, playoffs 2 of 3, continue, team description
var period_index := 0      ## $FFB0E2: 3:00 / 5:00 / 8:00
var period_minutes := 0    ## $FFB0E3
var stadium := 0           ## $FFB0E4
var penalties := 0         ## $FFB0E5
var reserves := 0          ## $FFB0E6
var death_index := 0       ## $FFB0E7

const FIELDS := ["team_a", "team_b", "pads", "play_mode", "period_index", "period_minutes",
		"stadium", "penalties", "reserves", "death_index"]

## Plan 34 (the port's, not one of the 10 bytes; plan 40, S13: filled at
## the rink's entry from the players, MwSelection.for_the_rink): an extended set-up's
## players - each team's match pads in number order (player n is pad n - 1:
## [method MwHumans.match_pads]), set with [member pads] by the controller
## selection ([method MwHumans.apply_to]). Empty for the set-ups the
## original could have had, whose players are the pad mode [member pads];
## in an extended one [member pads] is the nearest original mode.
var extended: Array = []
## Plan 34 (the port's; plan 40, S13: filled at the rink's entry,
## MwSelection.for_the_rink): the line-ups chosen before the match (character
## selection, the line-up panels; [method MwSelection.finish]) - per team
## six roster slots by position, or empty for the original's starters -
## made at the rink's entry ([method MwLineup.apply]). Empty: the match is
## the original's.
var lineups: Array = []
## Plan 44 (the port's; filled at a new match's rink entry from
## MwSettings.extended_play): an EXTENDED match - the players humans drive
## count as on the original's screen wherever they are
## (MwRinkState.extended_play). False: the original's.
var extended_play := false
## Plan 44 (the port's; with [member extended_play]): EXTENDED PENALTIES -
## the referee stops play for an offender anywhere on the rink
## (MwRinkState.extended_penalties). False: the original's.
var extended_penalties := false
## Plan 44 (the port's; with [member extended_play]): EXTENDED CPU - the
## CPU's players count as on the original's screen wherever they are too
## (MwRinkState.extended_cpu). False: the original's.
var extended_cpu := false


## Plan 44: an EXTENDED match's rules (MwSettings.extended_play, its
## EXTENDED PENALTIES and EXTENDED CPU) into this setup - a new match's rink entry and its
## rehearsal (MwRink, MwMatchRehearsal).
func take_extended_rules() -> void:
	extended_play = MwSettings.extended_play()
	extended_penalties = extended_play and MwSettings.extended_penalties
	extended_cpu = extended_play and MwSettings.extended_cpu


## The 10 setup bytes at [param address] in the ROM.
static func from_rom(rom: PackedByteArray, address: int) -> MwMatchSetup:
	return from_bytes(rom.slice(address, address + FIELDS.size()))


## A set-up from the 10 bytes [param b], in [constant FIELDS]' order (the
## original's); the port's fields at their defaults.
static func from_bytes(b: PackedByteArray) -> MwMatchSetup:
	var su := MwMatchSetup.new()
	for i in FIELDS.size():
		su.set(FIELDS[i], b[i])
	return su


## The 10 set-up bytes in the original's order ([constant FIELDS]); the port's
## fields are not in them.
func to_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	for f in FIELDS:
		b.append(int(get(f)) & 0xFF)
	return b


## A copy: the 10 bytes and the port's fields (the extended players and the
## line-ups deep-copied).
func copy() -> MwMatchSetup:
	var su := from_bytes(to_bytes())
	su.extended = extended.duplicate(true)
	su.lineups = lineups.duplicate(true)
	su.extended_play = extended_play
	su.extended_penalties = extended_penalties
	su.extended_cpu = extended_cpu
	return su


## Whether [param other] holds the same 10 bytes (the port's fields are not
## compared; null: false).
func equals(other: MwMatchSetup) -> bool:
	return other != null and to_bytes() == other.to_bytes()
