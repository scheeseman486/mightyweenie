class_name MwMatchup
extends MwScreen
## Screen 3, the matchup (`screen_03_matchup` $B172; docs/re/menus.md,
## Matchup): the rink's centre ice behind the two teams' names, "VS", and
## the stadium with its hazards - or, in the playoffs, the round and the
## state of the series. 300 ticks or A/B/C/Start on any pad (plan 34: any
## player's), then the rink.
## In the attract demo nothing is shown: the demo setup is loaded and the
## rink follows at once.
##
## In a 3D view (plan 33, docs/rink3d.md, The match's opening) the text
## stays over the match's opening in 3D (MwMatchIntro3D: the crowd chanting
## with this screen's crowd sound, the players coming out and showing off)
## for as long as the player likes: a press swings the text out to the top
## and bottom and lines them up, the chant's last bar plays out and the
## crowd's noise fades in, and the rink takes over without a fade once they
## are in place; a second press skips to the rink with the fade. Its length
## changes nothing in the game (no random numbers here; the rink keeps its
## own tick).
##
## Plan 35: which flow the opening takes (2D: 300 ticks or a press; 3D: the
## show until a press) is a match rule ([method MwSettings.opening_view]:
## the match's own camera, or online the host's), and the 3D flow's model
## runs whether or not this machine draws it (MwMatchIntro3D without a
## view: the 2D picture stays). The opening's own random choices come from
## the session's opening stream (MwSession.STREAM_OPENING).

const RINK_CAMERA := Vector2i(0x60, 0x15D)   ## `$14CDE`: plane B shows the rink map from here
const SHOW_TICKS := 300                       ## `$12C`
## Entry -> the timer starts: loading takes 7 ticks in the original
## (GPGX: screen 3 -> 4 in 339 ticks = 7 + 300 + the 32-tick fade-out).
const LOAD_TICKS := 7
const FONT_TITLE := MwFonts.TITLE
const FONT_SMALL := MwFonts.HEADING
const FONT_BIG := MwFonts.BIG
const VS := 0x5078A
const NO_HAZARDS := 0x5078D
const HAZARD_NAMES := 0x1CB20     ## 8 names by stadium hazard bit (record +$B)
const ROUND_NAMES := 0x1CB40      ## 2 strings per round
const SERIES_TEXTS := 0x1CB60     ## per series state: prefix, then (after its 0) suffix
const SERIES_TEAM := 0x1CB70      ## per series state: word, the team named (-1 none, 0 A, 1 B)
const ATTR := 0x60
const PRIORITY := 0x80
const SOUND_CROWD := MwSoundIds.CHANT
const PRESS_BITS := 0xF0          ## A, B, C, Start
## The 3D opening (plan 33): the text's rows from here down swing out to the
## bottom, those above to the top, over SWING_TICKS from the press; the
## crowd's noise fades in over CROWD_FADE_IN ticks after the chant's last bar.
const SPLIT_ROW := 11
const SWING_TICKS := 36
const CROWD_FADE_IN := 90

@onready var plane: RomPlane = $Window
@onready var rink: RomTileMapLayer = $Rink
@onready var palette: RomPalette = $Window.palette

var rom: PackedByteArray
var setup: MwMatchSetup
var _ticks := 0
var _sound := MwSound.NONE                    ## D7: the crowd's handle (-1 at first)
var _leaving := false
## The match's opening in 3D (plan 33; null in 2D and the attract demo).
var intro: MwMatchIntro3D = null
var _swing_at := -1                           ## the press's tick (-1: not yet)
var _heard := false                           ## the chant heard last pass
var _handing_over := false                    ## leaving for the rink with no fade


func _ready() -> void:
	fades_in_itself = false


func _enter_screen(_data: Dictionary) -> void:
	if not MwRom.available() or session == null:
		return
	rom = MwRom.data()
	setup = session.setup
	_match_setup()
	session.view = MwSettings.view()          # every match (the demo too) starts in the options' camera (plan 21)
	session.extended_views = MwSettings.extended_play()   # plan 44: its group (online: EXTENDED)
	if session.attract:
		return                                # nothing drawn; the first pass leaves
	MwSound.music_fade_out(32)                # `$B188`
	rink.position = Vector2(-RINK_CAMERA)
	palette.screen = 3
	palette.team_a = setup.team_a
	palette.team_b = setup.team_b
	palette.stadium = setup.stadium
	palette.steps = PackedStringArray(["screen_palette"])
	# port only (plan 38): a custom team's name in colours of its own - the
	# window's text on a palette of its own (lines 1-2 are the teams' names
	# only there; the picture keeps the shared one)
	plane.palette = MwScreenPalettes.names(palette)
	var flow_3d := MwRinkViews.opens_3d(MwSettings.opening_view())     # (plan 44: 2D EXTENDED opens as 2D)
	var drawn_3d := flow_3d and MwRinkViews.opens_3d(session.view)
	if drawn_3d:
		_split_text()
	plane.wipe()
	_centred(FONT_TITLE, MwGfx.rom_string(rom, VS), 9, ATTR)
	_team(setup.team_a, 0x0C, 0x20)
	_team(setup.team_b, 0x02, 0x40)
	if setup.play_mode < 1:
		_stadium_text()
	else:
		_round_text()
	if flow_3d:
		_start_intro(drawn_3d)


## The match's opening in 3D (plan 33): the Router's 3D view borrowed (in the
## rink's palette, wide as the options say) behind the text, this screen's
## rink picture and backdrop hidden. Plan 35: not [param drawn] (this
## machine shows 2D while the match's rule is 3D), the opening's model alone.
func _start_intro(drawn := true) -> void:
	var opening_seed := session.port_seed(MwSession.STREAM_OPENING)
	if not drawn:
		intro = MwMatchIntro3D.new(rom, session, null,
				MwRinkViews.camera_mode(MwSettings.opening_view(), session.birds_eye_across),
				Vector2(320, 224), opening_seed)
		return
	var host := MwRink3DHost.of(get_tree())
	host.wide_for(self, MwSettings.wide())
	var pal := MwScreenPalettes.rink(setup.team_a, setup.team_b, setup.stadium)
	var view := host.borrow(self, pal)
	if view == null:
		return
	intro = MwMatchIntro3D.new(rom, session, view, MwRinkViews.camera_mode(session.view, session.birds_eye_across),
			host.view_size, opening_seed)
	host.show_for(self, true)
	$Backdrop.visible = false
	rink.visible = false


## In 3D the text's rows from [constant SPLIT_ROW] down are painted into a
## plane of their own (RomPlane's lower plane), so the halves can swing
## apart at the press (plan 33).
func _split_text() -> void:
	var low := RomPlane.new()
	low.name = "WindowLower"
	low.tiles = plane.tiles
	low.palette = plane.palette
	add_child(low)
	plane.lower = low
	plane.split_row = SPLIT_ROW


## The text's halves [param t] ticks after the press: out to the top and
## the bottom with a little swing back first (an ease-in "back" curve),
## whole pixels; hidden once out of the picture.
func _swing_text(t: int) -> void:
	var low := plane.lower
	if low == null:
		return
	var u := clampf(float(t) / SWING_TICKS, 0.0, 1.0)
	var c1 := 1.2                             # the swing back: about 5% of the way
	var f := (c1 + 1.0) * u * u * u - c1 * u * u
	var host := MwRink3DHost.existing(get_tree())
	var margin := float(host.column_origin().y) if host != null else 0.0
	plane.position.y = -roundf(f * (SPLIT_ROW * 8 + margin))
	low.position.y = roundf(f * (MwRink3D.SCREEN.y - SPLIT_ROW * 8 + margin))
	plane.visible = u < 1.0
	low.visible = u < 1.0


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
	if intro != null:
		_intro_pass(elapsed, input)
		return
	if _ticks <= LOAD_TICKS:
		return
	if input != null and input.is_pressed("ui_back") and setup.play_mode == 0:
		MwSound.stop(_sound)                  # Menu Back (plan 21): back to the game setup
		_leaving = true                       # (an exhibition only: the playoffs' state stays)
		exit_to(1)
		return
	var pads := _pads(input)
	if _ticks - LOAD_TICKS < SHOW_TICKS:
		# `$B1FE` (and not while ENHANCE AUDIO plays it on an extra voice: a
		# sound the driver refused has no handle to ask)
		if not MwSound.busy(_sound) and not MwSound.sounding(SOUND_CROWD):
			_sound = MwSound.play(SOUND_CROWD)   # `$B20A`
		if pads & PRESS_BITS == 0:            # the pads are read after the sound
			return
	MwSound.stop(_sound)                      # `$B236`
	_leaving = true
	exit_to(4)


## The newly pressed bytes of every pad OR'd (`$B1FE`'s A / B / C / Start
## on any pad): pads 1-4, or every player's in an extended set-up (plan 34:
## [method MwSession.screen_pads] - players 5-12 skip it too).
func _pads(input: MwInputFrame) -> int:
	return input.any_pad_bits(session.screen_pads(), [MwVerbs.Context.MATCHUP]) if input else 0


## A pass of the 3D opening (plan 33): the crowd's sound ([method
## _intro_sound]), Menu Back as in 2D; a press swings the text out and lines
## the players up, a second skips to the rink (fading); once all are in
## place and the camera is the match's, the rink without a fade. The match's
## crowd goes with it either way.
func _intro_pass(elapsed: int, input: MwInputFrame) -> void:
	var leave := -1
	var fade := true
	if _ticks > LOAD_TICKS:
		if input != null and input.is_pressed("ui_back") and setup.play_mode == 0:
			MwSound.stop(_sound)
			if intro.cast.lining_up:
				MwSound.crowd_off()
			_leaving = true
			exit_to(1)
			return
		_intro_sound()
		var pads := _pads(input)
		if pads & PRESS_BITS:
			if intro.cast.lining_up:
				leave = 4                     # skipped: the fade
			else:
				intro.line_up()
				_swing_at = _ticks
	intro.step(elapsed)
	if _swing_at >= 0:
		_swing_text(_ticks - _swing_at)
	if leave < 0 and intro.done():
		leave = 4
		fade = false                          # in place: the rink takes over as it is
		_handing_over = true
	if leave >= 0:
		MwSound.stop(_sound)
		_leaving = true
		exit_to(leave, {"crowd_life": intro.life, "splatter": intro.splat}, fade)


## The opening's sound: the chant (sound `$1B`) kept going as in 2D until
## the line-up - each time it is heard starting (on the driver's channel or,
## with ENHANCE AUDIO, an extra voice: a sound the driver refused has no
## handle) the crowd is told; then its last bar plays out and the crowd's
## noise fades in from silence at the level the match will give it. Without
## a driver (headless) nothing is ever heard: each request counts as a start.
func _intro_sound() -> void:
	var heard := MwSound.busy(_sound) or MwSound.sounding(SOUND_CROWD)
	if heard and not _heard:
		intro.chant_started()
	_heard = heard
	if heard:
		return
	if not intro.cast.lining_up:
		_sound = MwSound.play(SOUND_CROWD)
		if MwSound.driver == null:
			intro.chant_started()
	else:
		MwSound.crowd_level(intro.noise_level(), CROWD_FADE_IN)


## Left after the 32-tick fade (`$B23C`-`$B24A` waits for it): the music's
## fade (`$B252`, 1 tick; nothing plays by then). The 3D view given back.
func _exit_tree() -> void:
	if _leaving:
		MwSound.music_fade_out(1)
	if intro != null:
		intro.detach()
		var host := MwRink3DHost.existing(get_tree())
		if host != null:
			if _handing_over:
				host.pass_on(self)            # the rink takes the picture as it is
			else:
				host.release(self)


## `$B28C`: [param bytes] centred on the 40-cell screen at [param row].
func _centred(font: int, bytes: PackedByteArray, row: int, attr: int) -> void:
	MwPlanePainter.centred(plane, rom, font, bytes, 0, 40, row, attr | PRIORITY)


## `$B260`: a team's city and name in the big font, 3 rows apart.
func _team(t: int, row: int, attr: int) -> void:
	_centred(FONT_BIG, MwGfx.rom_string(rom, MwTeams.city(rom, t)), row, attr)
	_centred(FONT_BIG, MwGfx.rom_string(rom, MwTeams.name(rom, t)), row + 3, attr)


## `matchup_stadium_text` ($B3FE): the stadium's name, its hazards.
func _stadium_text() -> void:
	var st := MwTeams.stadium_record(rom, setup.stadium)
	_centred(FONT_TITLE, MwGfx.rom_string(rom, MwGfx.u32(rom, st)), 0x14, ATTR)
	var mask := rom[st + 0x0B]
	var bytes := MwGfx.rom_string(rom, NO_HAZARDS)
	if mask != 0:
		bytes = PackedByteArray()
		for i in 8:
			if mask & 1:
				bytes.append_array(MwGfx.rom_string(rom, MwGfx.u32(rom, HAZARD_NAMES + 4 * i)))
				if mask >> 1 != 0:
					bytes.append(0x20)
			mask >>= 1
			if mask == 0:
				break
	if MwGfx.text_width(rom, FONT_SMALL, bytes) > 40:
		# port only (plan 38): a custom rink's words past the 40 cells (the
		# original's 40-byte line) on two lines, split at the middle word
		var words := bytes.get_string_from_ascii().split(" ")
		var half := ceili(words.size() / 2.0)
		_centred(FONT_SMALL, " ".join(words.slice(0, half)).to_ascii_buffer(), 0x18, ATTR)
		_centred(FONT_SMALL, " ".join(words.slice(half)).to_ascii_buffer(), 0x19, ATTR)
		return
	_centred(FONT_SMALL, bytes, 0x18, ATTR)


## `$B472`: the playoff round (two lines); in best-of-3 runs the series.
func _round_text() -> void:
	var playoffs: MwPlayoffs = session.playoffs
	var row := 0x15 - playoffs.best_of_3
	var r := ROUND_NAMES + 8 * (playoffs.round & 3)
	_centred(FONT_TITLE, MwGfx.rom_string(rom, MwGfx.u32(rom, r)), row, ATTR)
	_centred(FONT_TITLE, MwGfx.rom_string(rom, MwGfx.u32(rom, r + 4)), row + 2, ATTR)
	if playoffs.best_of_3 == 0:
		return
	var text := MwGfx.u32(rom, SERIES_TEXTS + 4 * playoffs.series)
	var bytes := MwGfx.rom_string(rom, text)
	var who := MwGfx.s16(rom, SERIES_TEAM + 2 * playoffs.series)
	if who >= 0:
		var t := setup.team_a if who == 0 else setup.team_b
		bytes.append_array(MwGfx.rom_string(rom, MwTeams.name(rom, t)))
		bytes.append_array(MwGfx.rom_string(rom, text + MwGfx.rom_string(rom, text).size() + 1))
	_centred(FONT_SMALL, bytes, 0x18, ATTR)
