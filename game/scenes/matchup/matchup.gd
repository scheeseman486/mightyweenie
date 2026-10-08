class_name MwMatchup
extends MwScreen
## Screen 3, the matchup (`screen_03_matchup` $B172; docs/re/menus.md,
## Matchup): the rink's centre ice behind the two teams' names, "VS", and
## the stadium with its hazards - or, in the playoffs, the round and the
## state of the series. 300 ticks or A/B/C/Start on any pad, then the rink.
## In the attract demo nothing is shown: the demo setup is loaded and the
## rink follows at once.

const RINK_CAMERA := Vector2i(0x60, 0x15D)   ## `$14CDE`: plane B shows the rink map from here
const SHOW_TICKS := 300                       ## `$12C`
## Entry -> the timer starts: loading takes 7 ticks in the original
## (GPGX: screen 3 -> 4 in 339 ticks = 7 + 300 + the 32-tick fade-out).
const LOAD_TICKS := 7
const FONT_TITLE := 0x22EE0
const FONT_SMALL := 0x22BEC
const FONT_BIG := 0x246FA
const VS := 0x5078A
const NO_HAZARDS := 0x5078D
const HAZARD_NAMES := 0x1CB20     ## 8 names by stadium hazard bit (record +$B)
const ROUND_NAMES := 0x1CB40      ## 2 strings per round
const SERIES_TEXTS := 0x1CB60     ## per series state: prefix, then (after its 0) suffix
const SERIES_TEAM := 0x1CB70      ## per series state: word, the team named (-1 none, 0 A, 1 B)
const ATTR := 0x60
const PRIORITY := 0x80
const SOUND_CROWD := 0x1B
const PRESS_BITS := 0xF0          ## A, B, C, Start

@onready var plane: RomPlane = $Window
@onready var rink: RomTileMapLayer = $Rink
@onready var palette: RomPalette = $Window.palette

var rom: PackedByteArray
var setup: MwMatchSetup
var _ticks := 0
var _sound := MwSound.NONE                    ## D7: the crowd's handle (-1 at first)
var _leaving := false


func _ready() -> void:
	fades_in_itself = false


func _enter_screen(_data: Dictionary) -> void:
	if not MwRom.available() or session == null:
		return
	rom = MwRom.data()
	setup = session.setup
	_match_setup()
	session.view = MwSettings.view()          # every match (the demo too) starts in the options' camera (plan 21)
	if session.attract:
		return                                # nothing drawn; the first pass leaves
	MwSound.music_fade_out(32)                # `$B188`
	rink.position = Vector2(-RINK_CAMERA)
	palette.screen = 3
	palette.team_a = setup.team_a
	palette.team_b = setup.team_b
	palette.stadium = setup.stadium
	palette.steps = PackedStringArray(["screen_palette"])
	plane.wipe()
	_centred(FONT_TITLE, MwGfx.rom_string(rom, VS), 9, ATTR)
	_team(setup.team_a, 0x0C, 0x20)
	_team(setup.team_b, 0x02, 0x40)
	if setup.play_mode < 1:
		_stadium_text()
	else:
		_round_text()


## `matchup_setup` ($B2B0): the attract demo's setup; in the playoffs the
## stadium alternates with the series (team A's when its bit 0 is set, else
## team B's). (Plan 08: the game clock, rink and teams are set up here.)
func _match_setup() -> void:
	if session.attract:
		session.begin_attract()
	if setup.play_mode != 0:
		setup.stadium = setup.team_a if session.playoffs.series & 1 else setup.team_b


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty():
		return
	if session.attract:
		MwSound.music_fade_out(1)             # `$B252` (`$B17E`: no wait, no fade)
		exit_to(4, {}, false)
		return
	_ticks += elapsed
	if _ticks <= LOAD_TICKS:
		return
	if input != null and input.is_pressed("ui_back") and setup.play_mode == 0:
		MwSound.stop(_sound)                  # Menu Back (plan 21): back to the game setup
		_leaving = true                       # (an exhibition only: the playoffs' state stays)
		exit_to(1)
		return
	var pads := 0
	if input:
		for p in range(1, 5):
			pads |= input.pad_bits(p)
	if _ticks - LOAD_TICKS < SHOW_TICKS:
		if not MwSound.busy(_sound):          # `$B1FE`
			_sound = MwSound.play(SOUND_CROWD)   # `$B20A`
		if pads & PRESS_BITS == 0:            # the pads are read after the sound
			return
	MwSound.stop(_sound)                      # `$B236`
	_leaving = true
	exit_to(4)


## Left after the 32-tick fade (`$B23C`-`$B24A` waits for it): the music's
## fade (`$B252`, 1 tick; nothing plays by then).
func _exit_tree() -> void:
	if _leaving:
		MwSound.music_fade_out(1)


## `$B28C`: [param s] centred on the 40-cell screen at [param row].
func _centred(font: int, s: PackedByteArray, row: int, attr: int) -> void:
	var x := (40 - MwGfx.text_width(rom, font, s)) >> 1
	MwPlanePainter.text(plane, rom, font, s, x, row, attr | PRIORITY)


## `$B260`: a team's city and name in the big font, 3 rows apart.
func _team(t: int, row: int, attr: int) -> void:
	_centred(FONT_BIG, MwGfx.rom_string(rom, MwTeams.city(rom, t)), row, attr)
	_centred(FONT_BIG, MwGfx.rom_string(rom, MwTeams.name(rom, t)), row + 3, attr)


## `matchup_stadium_text` ($B3FE): the stadium's name, its hazards.
func _stadium_text() -> void:
	var st := MwTeams.stadium_record(rom, setup.stadium)
	_centred(FONT_TITLE, MwGfx.rom_string(rom, MwGfx.u32(rom, st)), 0x14, ATTR)
	var mask := rom[st + 0x0B]
	var s := MwGfx.rom_string(rom, NO_HAZARDS)
	if mask != 0:
		s = PackedByteArray()
		for i in 8:
			if mask & 1:
				s.append_array(MwGfx.rom_string(rom, MwGfx.u32(rom, HAZARD_NAMES + 4 * i)))
				if mask >> 1 != 0:
					s.append(0x20)
			mask >>= 1
			if mask == 0:
				break
	_centred(FONT_SMALL, s, 0x18, ATTR)


## `$B472`: the playoff round (two lines); in best-of-3 runs the series.
func _round_text() -> void:
	var p: MwPlayoffs = session.playoffs
	var row := 0x15 - p.best_of_3
	var r := ROUND_NAMES + 8 * (p.round & 3)
	_centred(FONT_TITLE, MwGfx.rom_string(rom, MwGfx.u32(rom, r)), row, ATTR)
	_centred(FONT_TITLE, MwGfx.rom_string(rom, MwGfx.u32(rom, r + 4)), row + 2, ATTR)
	if p.best_of_3 == 0:
		return
	var text := MwGfx.u32(rom, SERIES_TEXTS + 4 * p.series)
	var s := MwGfx.rom_string(rom, text)
	var who := MwGfx.s16(rom, SERIES_TEAM + 2 * p.series)
	if who >= 0:
		var t := setup.team_a if who == 0 else setup.team_b
		s.append_array(MwGfx.rom_string(rom, MwTeams.name(rom, t)))
		s.append_array(MwGfx.rom_string(rom, text + MwGfx.rom_string(rom, text).size() + 1))
	_centred(FONT_SMALL, s, 0x18, ATTR)
