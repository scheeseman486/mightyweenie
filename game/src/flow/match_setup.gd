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


## The 10 setup bytes at [param address] in the ROM.
static func from_rom(rom: PackedByteArray, address: int) -> MwMatchSetup:
	return from_bytes(rom.slice(address, address + FIELDS.size()))


static func from_bytes(b: PackedByteArray) -> MwMatchSetup:
	var s := MwMatchSetup.new()
	for i in FIELDS.size():
		s.set(FIELDS[i], b[i])
	return s


func to_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	for f in FIELDS:
		b.append(int(get(f)) & 0xFF)
	return b


func copy() -> MwMatchSetup:
	return from_bytes(to_bytes())


func equals(other: MwMatchSetup) -> bool:
	return other != null and to_bytes() == other.to_bytes()
