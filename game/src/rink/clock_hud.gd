class_name MwClockHud
extends RefCounted
## The rink's clock widget in the window plane (`$25AA` draws, `$26F6`
## erases, `$261C` updates every pass; docs/re/rink.md, HUD): a 9x5 frame
## of tiles `$1BFC2` (VRAM `$578`) at cell (2, 22) with the game clock
## "MM:SS" at (4, 24) and the period ("1st".."3rd", "OT1".."OT6") at (5, 25),
## in font `$447F4` (attr `$E0`, priority: in front of the players). During a
## power play the frame is the 9x8 one at (2, 19), with "[]" at (4, 21) and
## the power-play clock at (4, 22). The values come from the rules (plan 09).

const FONT := 0x447F4
const MAP := 0x49136                 ## 9x5
const MAP_POWERPLAY := 0x49194       ## 9x8
const SUFFIXES := 0x1BFDC            ## "00stndrd"
const ATTR := 0xE0
const AT := Vector2i(2, 22)
const AT_POWERPLAY := Vector2i(2, 19)
const CLOCK_AT := Vector2i(4, 24)    ## $1BFCA
const PERIOD_AT := Vector2i(5, 25)   ## $1BFD6
const PP_CLOCK_AT := Vector2i(4, 22) ## $1BFD0
const PP_LABEL_AT := Vector2i(4, 21) ## $1BFE4
const BLANK := 0x8000


## `$27D8`: seconds -> "MM:SS" (minutes as two digits).
static func time_text(seconds: int) -> PackedByteArray:
	var m := seconds / 60
	var s := seconds % 60
	return PackedByteArray([0x30 + m / 10, 0x30 + m % 10, 0x3A, 0x30 + s / 10, 0x30 + s % 10])


## `$2748`: period 1-3 -> "1st".."3rd", 4+ -> "OT1".. (capped at "OT9").
static func period_text(rom: PackedByteArray, period: int) -> PackedByteArray:
	if period >= 4:
		return PackedByteArray([0x4F, 0x54, mini(0x2D + period, 0x39)])
	return PackedByteArray([0x30 + period, rom[SUFFIXES + 2 * period], rom[SUFFIXES + 2 * period + 1]])


## `$25AA`: the widget with the game clock ([param seconds] left in the
## period) and, when [param powerplay_seconds] >= 0, the power-play box.
static func draw(plane: RomPlane, rom: PackedByteArray, period: int, seconds: int, powerplay_seconds := -1) -> void:
	if powerplay_seconds >= 0:
		MwPlanePainter.map_rect(plane, rom, MAP_POWERPLAY, 9, 9, 8, AT_POWERPLAY.x, AT_POWERPLAY.y)
		MwPlanePainter.text(plane, rom, FONT, time_text(powerplay_seconds), PP_CLOCK_AT.x, PP_CLOCK_AT.y, ATTR)
	else:
		MwPlanePainter.map_rect(plane, rom, MAP, 9, 9, 5, AT.x, AT.y)
	MwPlanePainter.text(plane, rom, FONT, period_text(rom, period), PERIOD_AT.x, PERIOD_AT.y, ATTR)
	if powerplay_seconds >= 0:
		MwPlanePainter.text(plane, rom, FONT, PackedByteArray([0x5B, 0x5D]), PP_LABEL_AT.x, PP_LABEL_AT.y, ATTR)
	MwPlanePainter.text(plane, rom, FONT, time_text(seconds), CLOCK_AT.x, CLOCK_AT.y, ATTR)


## `$26F6`: the widget's cells blanked.
static func erase(plane: RomPlane, powerplay: bool) -> void:
	if powerplay:
		MwPlanePainter.fill(plane, AT_POWERPLAY.x, AT_POWERPLAY.y, 9, 8, BLANK)
	else:
		MwPlanePainter.fill(plane, AT.x, AT.y, 9, 5, BLANK)
