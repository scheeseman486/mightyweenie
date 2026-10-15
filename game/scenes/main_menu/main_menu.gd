class_name MwMainMenu
extends MwScreen
## Screen 1, the main menu (`screen_01_main_menu` $136DE; docs/re/menus.md,
## Main menu): the original's row menu over the starfield, the two team
## panels, the torches. Ported routine by routine; the menu's data (rows,
## strings, tables, positions) is read from the ROM at run time.
##
## P1 drives the rows (and P2 too in the pad modes where P1 and P2 share a
## team); in the other modes the other pads edit team B directly, as in the
## original. 1800 ticks without a press start the attract demo.
##
## The port's variants (plan 34; [member MwSession.local_mode] in the front
## menu's flow): EXHIBITION and PLAYOFFS. No pads row and no play mode row
## (owner: no pad or player selection any more, and no play mode selection);
## the rows under them close the gap, and the last slot holds the port's
## PLAY GAME (the playoffs: SAVE GAME beside it once a game of the run has
## been played since it was started or loaded). In the playoffs the
## stadium's slot is SERIES (owner: the series picks the stadium), and a run
## in progress keeps its teams. Start or PLAY GAME plays; Menu Back goes to
## LOCAL PLAY (from a run in progress after a question). The top graphic -
## the window's rows 0-15 and every sprite in it - falls in on entry with
## the FACE OFF! drop's slam ([MwSlam]), around the logo: the logo stays
## where the port's menus show it, on a layer of its own with its black
## panel see-through as there, and the falling window has a hole for it
## (owner: the window's middle see-through, so the logo lines up exactly),
## and one for the black strip under the logo, above the arch's skull
## (owner: that black see-through too). From LOCAL PLAY it comes in with a
## cut, the starfield going on where it was; the menus' music starts with
## the thud.
## There the port's pages already show the top hanging with only its arch
## in view ([constant MwPortMenu.TOP_HANG], owner 2026-10-10): it falls from
## there, the menu's text fading in, and Menu Back lifts it back there, the
## text fading out, before the cut back to LOCAL PLAY. Landing, it bounces
## and settles ([member MwSlam.bounces]); only the top shakes - the stars,
## the text and the logo stay, the logo always under the window (owner: a
## cleaner landing, the logo fixed in place, never on top).
## Back from the controller selection (110), where the top rose off the
## screen, it falls back in front of the logos ([MwBrickWall]).
##
## Online (plan 35 work item 4: the exhibition variant, MwFlow.online): the
## host's P1 drives the rows (the shared menu verbs - online the host's
## P1's, MwNetMatch), nobody else edits team B, and Back takes everyone
## back to the lobby ([constant MwFlow.ONLINE_LOBBY]). The controller
## selection lists the match's players (the lobby's).

const START_SCREENS := 0x13A6C     ## next screen by play mode (`$13A6C`)
const PERIOD_MINUTES := 0x1C1D2    ## minutes by period index (`$45F0`)
const PLAYOFF_NEXT_A := 0x1F522    ## next team B in conference 0-9 (+23: backwards)
const PLAYOFF_NEXT_B := 0x1F550    ## ... in conference 10-19
const TORCHES := [0x13526, 0x1352E]  ## x, y, depth, attr XOR of each torch
const TORCH_ANIM := "anim_041bca"
const TORCH_SECOND_START := 0x580
const FLICKER := 0x135E6           ## next line-3 palette: [current * 4 + rng(0, 2)]
const BACKDROP := 0x41BF2
const BACKDROP_ROWS := 16
const STADIUM_ROW := MwMenuRows.STADIUM_ROW
const SOUND_MOVE := MwSoundIds.MOVE           ## `$13CEE` sound: row moved / value changed
## The original's main menu loop takes 3 ticks a pass (BlastEm records: 3.02
## on average); our passes are 1 tick, so what it does at random once per
## pass (the torchlight flicker) runs once per 3 ticks here (owner, plan 02).
const PASS_TENTHS := 30
## Entry -> its first pass: loading takes 14 ticks in the original (the
## screen is still black). The panels' timers start there.
const LOAD_TICKS := 14
const SCREEN_SIZE := Vector2(320, 224)
## The menu's text (plane A: the rows) fading in as the top falls from the
## port's pages, and out as it rises back (owner), in ticks.
const TEXT_FADE_TICKS := 32
## Menu Back: a star's voice fades out this fast ([method _quiet_panels]).
const VOICE_FADE_TICKS := 12
## The top's second crash, as it lands from its first bounce: [MwSlam]'s
## (the line-up panels' too).
const SECOND_CRASH_RATE := MwSlam.SECOND_CRASH_RATE
const SECOND_CRASH_VOLUME := MwSlam.SECOND_CRASH_VOLUME
## Back to LOCAL PLAY: the top's rise to where the pages hang it, in ticks
## - the controller selection's rise ([constant MwBrickWall.RISE_TICKS]),
## its gate's clinks timed to it.
const LIFT_TICKS := MwBrickWall.RISE_TICKS
## The black strip right above the arch's skull (row 11 between the pillars,
## under the logo): see-through in the port's variants (owner; the other
## black areas - under the names, under the panels - stay).
const SKULL_STRIP := Rect2i(15, 11, 10, 1)
## The port's rows (plan 34) beside the original's 0-9: SERIES (the
## playoffs, in the stadium's slot) and the action row (PLAY GAME, and SAVE
## GAME in a run).
const SERIES_ROW := 10
const ACTION_ROW := 11
const SERIES_Y := 18
const ACTION_Y := 26
const ROW_X := 4
const VALUE_X := 20
const VALUE_W := 18
const ROW_W := 0x22
## The playoffs' action row: SAVE GAME in the left half, PLAY GAME in the right.
const HALF_W := 16
const SERIES_NAMES := ["SINGLE GAMES", "BEST OF 3"]
## Rows below the play mode move up a slot (2 cells) in the variants.
const VARIANT_SHIFT := {4: -2, 6: -2, 7: -2, 8: -2, 9: -2}
## Up / Down in the variants (the original's `$139A8` / `$139B2` without the
## pads and play mode rows); the playoffs swap the stadium for SERIES.
const UP_EXHIBITION := {0: 1, 1: 0, 4: 0, 6: 4, 7: 6, 8: 7, 9: 8, ACTION_ROW: 9}
const DOWN_EXHIBITION := {0: 4, 1: 4, 4: 6, 6: 7, 7: 8, 8: 9, 9: ACTION_ROW, ACTION_ROW: ACTION_ROW}
const UP_PLAYOFFS := {0: 1, 1: 0, 4: 0, SERIES_ROW: 4, 7: SERIES_ROW, 8: 7, 9: 8, ACTION_ROW: 9}
const DOWN_PLAYOFFS := {0: 4, 1: 4, 4: SERIES_ROW, SERIES_ROW: 7, 7: 8, 8: 9, 9: ACTION_ROW, ACTION_ROW: ACTION_ROW}

## Genesis pad bits of the original's "newly pressed" bytes.
const B_UP := 1
const B_DOWN := 2
const B_LEFT := 4
const B_RIGHT := 8
const B_START := 0x80

@onready var plane: RomPlane = $Plane
@onready var starfield: RomStarfield = $Starfield
@onready var torches: Array[RomSprite] = [$TorchLeft, $TorchRight]
@onready var palette: RomPalette = $Plane.palette
@onready var panels: Array[MwTeamPanel] = [$PanelA, $PanelB]

var rom: PackedByteArray
var rows: MwMenuRows
var setup: MwMatchSetup
## The selected row (`d4`), the row drawn highlighted (`$C7C6`, -1 none) and
## P1's row while another pad edits team B (`$C7CA`, -1 none).
var row := 0
var current := -1
var saved_row := -1
## `$C7F6`: 0 the stadium follows team A, 1 chosen by the player, -1 playoffs.
var stadium_mode := 0
## `$C7F7`: line 3's palette (menu_line index).
var flicker := 0
## Ticks since the last new press (`$FFCA1E`).
var idle := 0

## Plan 34: "exhibition" or "playoffs" (the port's variants), "" the original.
var variant := ""
## The action row's selected item: 0 PLAY GAME, 1 SAVE GAME.
var action := 0
## The top graphic's fall (null when settled or not shown).
var slam: MwSlam
## Leaving a playoff run asks first.
var confirm: MwConfirmBox

## The variants' logo, still while the frame falls around it.
var logo_plane: RomPlane
## Screen 110 (plan 34): the controller selection under the game setup's top.
var select: MwControllerSelect
## 110's opening - the top rising off the screen - and its mirror back on
## the game setup (owner; null when neither runs).
var wall: MwBrickWall

var _fill := false        # `$C3B4`: fill the highlight on its next drawing
var _music_due := false   # the menus' music waits for the thud
var _group: Array[Node2D] = []          # the top graphic's layers and sprites
var _group_y := PackedFloat32Array()
var _group_x := PackedFloat32Array()
var _text_alpha := 1.0                    # the menu's text (plane A)
var _text_dir := 0                        # +1 fading in, -1 out, 0 still
var _text_ticks := TEXT_FADE_TICKS        # the whole fade's length
var _lift := -1                           # ticks into the rise back to the pages (-1: none)
var _lift_from := 0                       # px up when it began
var _loading := LOAD_TICKS
var _pending := 0
var _clock := 0           # ticks since entering (the panels' timers use it)
var _pass_tenths := 0


func _ready() -> void:
	fades_in_itself = false
	_clip_plane_a()


## The VDP shows plane A only below the window (rows 0-15 here): plane A goes
## into a clip from the window's last row down (as game stats' PlaneAClip),
## so of its row 15 - where the play mode row's highlight frame has its top
## edge - only the last pixel line shows, through its 1-pixel scroll, as on
## the original.
func _clip_plane_a() -> void:
	var plane_a := plane.lower
	if plane_a == null or plane_a.get_parent() is Control:
		return
	var top := plane.split_row * 8
	var clip := Control.new()
	clip.name = "PlaneAClip"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = Vector2(0, top)
	clip.size = Vector2(SCREEN_SIZE.x, SCREEN_SIZE.y - top)
	var parent := plane_a.get_parent()
	parent.add_child(clip)
	parent.move_child(clip, plane_a.get_index())
	var at := plane_a.position
	plane_a.reparent(clip, false)
	plane_a.position = at - Vector2(0, top)


## The tick counter as the panels read it (ticks since entering).
func idle_clock() -> int:
	return _clock


## The value row [param r] shows: byte [param r] of [member setup] ([constant MwMatchSetup.FIELDS]
## order).
func value(r: int) -> int:
	return setup.to_bytes()[r]


## Sets byte [param r] of [member setup] ([constant MwMatchSetup.FIELDS] order) to [param v]'s
## low byte.
func set_value(r: int, v: int) -> void:
	setup.set(MwMatchSetup.FIELDS[r], v & 0xFF)


func _enter_screen(data: Dictionary) -> void:
	if not MwRom.available() or session == null:
		return
	rom = MwRom.data()
	setup = session.setup
	rows = MwMenuRows.new(rom)
	session.reseed_aux()
	if session.local_mode == "" or not MwSettings.front_menu:
		MwSound.music_game()                # `$136F2`: the menus' music (kept if it plays)
	idle = 0
	session.end_attract()
	_load_backdrop()
	if entry == "controllers":
		_enter_controllers(data)
		return
	if previous == MwScreens.CONTROLLER_SELECT or (data.get("cut", false) and previous == MwScreens.LOCAL_PLAY):
		_loading = 0                         # the same picture (110), or its top already hanging there: a cut
	var st: Dictionary = session.screens.get(1, {})
	var first := previous == 0 or st.is_empty()
	if not first:
		stadium_mode = int(st["stadium_mode"])
		current = int(st["current"])
	variant = session.local_mode if MwSettings.front_menu else ""
	if variant != "":
		_enter_variant()
		_logo_apart()
		_stars_apart()
	for p in 2:
		panels[p].setup_panel(self, p)
	for r in MwMenuRows.ROWS:
		if rows.has_row(r) and r != STADIUM_ROW:
			if _shown(r):
				rows.draw(plane, r, value(r), r == current)
			if locked() and r in [0, 1, MwMenuRows.PLAY_MODE_ROW]:
				continue                         # a run keeps its teams (the bracket set this game's)
			_handler(r, 1)
	if locked():
		stadium_mode = -1
		_load_team(0)
		_load_team(1)
	row = 0 if first else int(st["row"])
	if variant != "":
		row = _variant_row(row, first)
		_draw_port_rows()
	saved_row = -1
	_fill = true
	current = row
	_highlight()
	starfield.start(session.rng_aux)
	if variant != "" and data.get("cut", false):
		_restore_starfield()
	_start_torches()
	flicker = 0
	if data.get("cut", false) and previous == MwScreens.CONTROLLER_SELECT:
		_restore_torchlight()
	if variant != "":
		_start_slam(data.get("cut", false))


## The starfield where the screen before left it (a cut between the port's
## screens: the port menus, the controller selection).
func _restore_starfield() -> void:
	starfield.restore(session.menu_stars)


func _save_starfield() -> void:
	session.menu_stars = starfield.state()


## The torchlight across the cuts between the game setup and the controller
## selection (plan 34): line 3's palette, the flicker's pass clock and both
## torches' animation where they were, so the bricks' colours don't snap.
func _save_torchlight() -> void:
	var t := [flicker, _flickered, _pass_tenths]
	for torch in torches:
		t.append_array([torch.state.position, torch.state.frame] if torch.state else [0, 0])
	session.screens["torchlight"] = t


func _restore_torchlight() -> void:
	var t: Array = session.screens.get("torchlight", [])
	if t.size() < 7:
		return
	flicker = int(t[0])
	_flickered = bool(t[1])
	_pass_tenths = int(t[2])
	for i in 2:
		var anim := torches[i].state
		if anim:
			anim.position = int(t[3 + 2 * i])
			anim.frame = int(t[4 + 2 * i])
			torches[i].refresh()
	_update_palette()


## Leaves for [param id]: the controller selection and back by a cut (the
## same picture's top stays; the starfield and the torchlight go on; back
## from 110, the wall's state for its fall); from 110 the line-up panels
## (113) are pushed over this picture, no fade - they crash in over it, the
## stars going on, the CONTROLLER SELECT plate fading ([method
## covered_fades]), and backing out they pull back off it (owner,
## 2026-10-12: no fade; MwRouter's "over"); elsewhere the fade.
func _go(id: int) -> void:
	if entry == "controllers" and id == MwScreens.LINEUPS:
		_save_starfield()
		MwSound.fm_effect_stop()                # (the wall's clinks, if it still rises)
		push(id, {"over": true}, false)
	elif id == MwScreens.CONTROLLER_SELECT or (entry == "controllers" and id == 1):
		_save_starfield()
		_save_torchlight()
		if entry == "controllers" and wall != null:
			session.screens["wall"] = wall.state()
			MwSound.fm_effect_stop()            # the clinks stop with the rise
		exit_to(id, {"cut": true}, false)
	else:
		exit_to(id)


## Screen 110 (plan 34, section 5): the game setup's top - the panels with
## the teams' logos, their names, the logo, the torches - and the players'
## columns below ([MwControllerSelect]); no slam, the menus' music going on.
## The panels hold their logos, then the top rises off the screen leaving
## the logos, the names and the CONTROLLER SELECT plate ([MwBrickWall],
## owner); the players' lines move meanwhile.
func _enter_controllers(data: Dictionary) -> void:
	resume_fresh = true                  # the line-up panels' time over it isn't caught up (a port screen)
	variant = session.local_mode if session.local_mode != "" else "exhibition"
	_loading = 0                         # the game setup's picture, already loaded
	_enter_variant()
	_logo_apart()
	_music_due = false
	for p in 2:
		panels[p].setup_panel(self, p)
	_load_team(0)
	_load_team(1)
	for r in [0, 1]:
		rows.draw(plane, r, value(r), false)
	starfield.start(session.rng_aux)
	if data.get("cut", false):
		_restore_starfield()
	_start_torches()
	flicker = 0
	if data.get("cut", false) and previous == 1:
		_restore_torchlight()
	select = MwControllerSelect.new()
	select.name = "ControllerSelect"
	add_child(select)
	select.online = session.online_players()       # plan 35: the match's players, the lobby's
	select.setup(plane, rom, session.humans, rows.fill_word(7), variant == "playoffs")
	select.leave.connect(_controllers_done)
	for panel in panels:
		panel.hold()                             # owner: any animation stops first
	wall = MwBrickWall.new(self)
	wall.lift(select.take_title())
	wall.open()                              # once faded in (from the bracket)


## Plan 41 (online, a client): the controller selection shows this
## machine's players' presses its game hasn't run yet at once.
func predict_local(presses: Dictionary) -> void:
	if entry == "controllers" and select != null and is_instance_valid(select):
		select.predict(presses)


## 110 under the line-up panels (pushed over it in sight): the CONTROLLER
## SELECT plate fades out under them and back in as they pull back.
func covered_fades() -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	if entry == "controllers" and wall != null and wall.title != null:
		out.append(wall.title)
	return out


## Back from the line-up panels (pushed over 110): the stars where they
## left them ([member MwSession.menu_stars]).
func _resume_screen(result := {}) -> void:
	if entry == "controllers" and bool(result.get("menu_stars", false)):
		_restore_starfield()


## The controller selection is done: back to the game setup, or on - the
## original's pad mode derived from the players and each pad given its
## player (MwHumans; an extended set-up: the nearest mode and the teams'
## match pads, nothing remapped).
func _controllers_done(go_on: bool) -> void:
	if not go_on:
		_go(1)
		return
	session.humans.apply_to(setup)
	session.pad_map = session.humans.pad_players(rom)
	_go(MwFlow.after_controllers(session))


func _load_backdrop() -> void:
	plane.wipe()
	MwPlanePainter.map_rows(plane, rom, BACKDROP, 0, BACKDROP_ROWS, 0)
	_update_palette()


## The palette as the original builds it: screen palette, colour 0 black,
## the stadium's ice on line 0, the panels' team colours on lines 1-2, the
## torchlight's palette on line 3 once it flickered.
func _update_palette() -> void:
	palette.screen = 1
	palette.team_a = setup.team_a
	palette.team_b = setup.team_b
	palette.stadium = setup.stadium
	var steps := PackedStringArray(["screen_palette", "black 0", "ice_line"])
	for panel in panels:
		steps.append_array(panel.palette_steps())
	if _flickered:
		steps.append("menu_line %d" % flicker)
	palette.steps = steps


var _flickered := false


func _start_torches() -> void:
	for i in 2:
		var a: int = TORCHES[i]
		var sprite := torches[i]
		sprite.position = Vector2(MwGfx.u16(rom, a), MwGfx.u16(rom, a + 2))
		sprite.attr_xor = MwGfx.u16(rom, a + 6)
		sprite.restart()
	torches[1].state.position = TORCH_SECOND_START


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rows == null:
		return
	idle += elapsed
	_clock += elapsed
	if _loading > 0:                            # still loading: no pass yet
		_loading -= elapsed
		_pending += elapsed
		if _loading > 0:
			return
		elapsed = _pending
	for i in elapsed:
		starfield.step()                        # VBlank task
	if select != null:
		_backdrop_pass(elapsed)
		if not _exiting():
			select.handle(elapsed, input)
		return
	current = row
	_highlight()
	for r in range(2, MwMenuRows.ROWS):
		if rows.has_row(r) and _shown(r):
			rows.draw(plane, r, value(r), r == current, true)
	if variant != "":
		_draw_port_rows(true)                   # as `$12D18` redraws rows 2-9's text every pass
		_slam_pass(elapsed, input)
	for sprite in torches:
		sprite.advance(elapsed)
	_pass_tenths += 10 * elapsed
	while _pass_tenths >= PASS_TENTHS:
		_pass_tenths -= PASS_TENTHS
		_flicker_step()
	for panel in panels:
		panel.step(elapsed)
	if _lift >= 0:
		_lift_pass(elapsed, input)                 # back to LOCAL PLAY: nothing else answers
		return
	if confirm != null and confirm.handle(input):
		return
	if input != null and input.is_pressed("ui_back") and MwSettings.front_menu:
		_back()
		return
	if variant != "":
		_variant_input(input)
		return
	_menu_input(input)


## What runs behind the controller selection: the wall's opening, the
## torches, their light, the panels (holding their logos).
func _backdrop_pass(elapsed: int) -> void:
	if wall != null:
		wall.advance(elapsed, _exiting())
	for sprite in torches:
		sprite.advance(elapsed)
	_pass_tenths += 10 * elapsed
	while _pass_tenths >= PASS_TENTHS:
		_pass_tenths -= PASS_TENTHS
		_flicker_step()
	for panel in panels:
		panel.step(elapsed)


func _exiting() -> bool:
	return fader != null and fader.busy()


## `$13572`: one time in four, the torchlight picks its next palette.
func _flicker_step() -> void:
	var rng := session.rng_aux
	if rng.next_state() & 3 != 0:
		return
	var d := rng.range_value(0, 2)
	flicker = rom[FLICKER + flicker * 4 + d]
	_flickered = true
	_update_palette()


## Plan 35: the "newly pressed" byte the shared menu verbs make in the game
## setup's context (online: the host's P1's; plan 40: MwVerbs.pad_byte's
## player 0).
static func shared_bits(input: MwInputFrame) -> int:
	return input.pad_bits(0, [MwVerbs.Context.SETUP]) if input else 0


## The original's "newly pressed" byte of player [param p] (the game
## setup's verbs: MwVerbs.Context.SETUP).
static func pad_bits(input: MwInputFrame, p: int) -> int:
	return input.pad_bits(p, [MwVerbs.Context.SETUP]) if input else 0


func _menu_input(input: MwInputFrame) -> void:
	var others := pad_bits(input, 3) | pad_bits(input, 4)
	if setup.pads < 2:
		others |= pad_bits(input, 2)
	var d5 := 0
	if others == 0:
		var mine := pad_bits(input, 1)
		if setup.pads >= 2:
			mine |= pad_bits(input, 2)
		if mine == 0:
			if not MwAttract.idle_out(idle):
				return
			session.attract = true              # as if Start was pressed
			d5 = B_START
		else:
			d5 = mine if pad_bits(input, 1) & B_START else mine & 0x7F
			idle = 0
		if saved_row >= 0:                      # P1 takes the menu back
			_select(saved_row, true)
			saved_row = -1
		if d5 & (B_LEFT | B_RIGHT) == 0:
			if d5 & B_UP:
				_move(rows.up(row))
				return
			if d5 & B_DOWN:
				_move(rows.down(row))
				return
	else:
		d5 = others & 0x7F
		idle = 0
		if saved_row < 0:                       # another pad edits team B
			rows.unhighlight(plane, row)
			current = -1
			rows.draw(plane, row, value(row), false)
			saved_row = row
		row = 1
		current = 1
		_fill = false
		rows.draw(plane, 1, value(1), true)
	if d5 & B_LEFT:
		_change(-1)
	elif d5 & B_RIGHT:
		_change(1)
	elif d5 & B_START:
		_start()


## Up / Down: unselect the row, select [param to]; the sound (`$1395A` /
## `$1399E`).
func _move(to: int) -> void:
	_select(to, false)
	MwSound.play(SOUND_MOVE)


func _select(to: int, _restore: bool) -> void:
	_unhighlight(row)
	current = -1
	_draw_row(row)
	row = to
	current = row
	_fill = true
	_highlight()
	_draw_row(row)


func _unhighlight(r: int) -> void:
	if r >= SERIES_ROW:
		_port_frame(r, false, false)
	else:
		rows.unhighlight(plane, r)


## Left / Right: the next value (teams in the menu's order, `$1C1BB` /
## `$1C1A4`, with the custom teams after the teams they follow - plan 38,
## [method MwCustomTeams.menu_order]), then the row's handler.
func _change(dir: int) -> void:
	var v := value(row)
	var order := MwCustomTeams.menu_order(rom)
	if row < 2:
		v = order.find(v)
	v += dir
	if v < 0:
		v = rows.count(row) - 1
	elif v >= rows.count(row):
		v = 0
	if row < 2:
		v = order[v]
	set_value(row, v)
	_handler(row, dir)
	_fill = true
	_highlight()
	rows.draw(plane, row, value(row), true)
	MwSound.play(SOUND_MOVE)                # `$13A06`


## Menu Back (plan 21): remember the row, back to the port's front menu -
## plan 34: to LOCAL PLAY, where the port's flow came from.
func _back() -> void:
	if MwFlow.online(session):
		session.screens[1] = {"row": row, "current": current, "stadium_mode": stadium_mode}
		_quiet_panels()
		MwSound.music_fade_out(32)
		exit_to(MwFlow.ONLINE_LOBBY)               # plan 35: everyone back to the lobby
		return
	if variant == "playoffs" and session.run_started:
		confirm.open("LEAVE THE PLAYOFFS")      # unsaved progress goes
		return
	_leave()


func _leave() -> void:
	session.screens[1] = {"row": row, "current": current, "stadium_mode": stadium_mode}
	_quiet_panels()
	MwSound.music_fade_out(32)
	if variant == "playoffs":
		session.drop_run()
	if variant != "" and session.local_mode != "":
		_start_lift()                               # the top back up where LOCAL PLAY hangs it
		return
	exit_to(MwScreens.LOCAL_PLAY if session.local_mode != "" else MwScreens.FRONT_MENU)


## Menu Back's way out (owner, 2026-10-12): a star's voice in a team panel
## doesn't talk on over the next menu - it fades out over [constant
## VOICE_FADE_TICKS], and the panels start no more.
func _quiet_panels() -> void:
	for panel in panels:
		panel.quiet(VOICE_FADE_TICKS)


## Start: remember the row, fade out, go where the play mode says.
func _start() -> void:
	session.screens[1] = {"row": row, "current": current, "stadium_mode": stadium_mode}
	session.playoffs.start(setup, session.rng)     # $11D8E
	var next := 3 if session.attract else rom[START_SCREENS + setup.play_mode]
	exit_to(next)


func _highlight() -> void:
	if row >= SERIES_ROW:
		_port_frame(row, true, _fill)
	else:
		rows.highlight(plane, row, _fill)
	_fill = false


func _draw_row(r: int) -> void:
	if r >= SERIES_ROW:
		_draw_port_row(r, r == current)
	elif _shown(r):
		rows.draw(plane, r, value(r), r == current)


# --- row handlers (called after a value changed; dir = the original's d1) ----------------------
func _handler(r: int, dir: int) -> void:
	match r:
		0:
			_team_a(dir)
		1:
			_team_b(dir)
		3:
			_play_mode()
		4:
			setup.period_minutes = rom[PERIOD_MINUTES + setup.period_index]
		STADIUM_ROW:
			_stadium()
		_:
			pass   # pads: the 4-Way Play adapter is always there (owner)


## `$12F34`: team A. In the playoffs only conference teams 0-19, team B kept
## in A's conference; the stadium follows team A unless the player chose one.
func _team_a(dir: int) -> void:
	if stadium_mode < 0:
		var a := setup.team_a
		if a >= 20 and not MwTeams.is_custom(a):
			a = 9 if a == 20 else 0
		setup.team_a = a
		a = MwPlayoffs.place(a)          # plan 38: a custom team plays in its place's stead
		var b := setup.team_b
		var ok := b < 20 and b != a and ((a >= 10) == (b >= 10))
		if not ok:
			var d := a - dir                    # d1 = $FF (left) / 1 (right)
			if d < 0:
				d += 10
			elif d >= 20:
				d -= 10
			elif a >= 10 and d < 10:
				d += 10
			elif a < 10 and d >= 10:
				d -= 10
			setup.team_b = d
			_load_team(1)
			_draw_row(1)
	if stadium_mode <= 0:
		setup.stadium = setup.team_a
		_draw_row(STADIUM_ROW)
		_update_palette()
	_load_team(0)


## `$13004`: team B. In the playoffs it skips to the next team of team A's
## conference ($1F522 / $1F550, backwards at +23).
func _team_b(dir: int) -> void:
	if stadium_mode < 0:
		var guard := 0
		while guard < 64:
			guard += 1
			var a := MwPlayoffs.place(setup.team_a)   # plan 38
			var b := setup.team_b
			var table := PLAYOFF_NEXT_B if a >= 10 else PLAYOFF_NEXT_A
			var step: bool
			if a >= 10:
				step = b == a or b >= 20 or b < 10
			else:
				step = b == a or b >= 10
			if step:
				if dir < 0:
					table += 23
				b = rom[table + b]
			setup.team_b = b
			if b != a:
				break
	_load_team(1)


## `$130C2`: play mode. Playoff modes restrict the teams and tie the stadium
## to team A; the others let it follow team A again unless it was chosen.
func _play_mode() -> void:
	var m := setup.play_mode
	if m == 0 or m == 4:
		if stadium_mode <= 0:
			stadium_mode = 0
	else:
		stadium_mode = -1
		_team_a(-1)


## `$12F04`: stadium. In the playoffs it stays team A's; otherwise the
## player's choice stops it following team A.
func _stadium() -> void:
	if stadium_mode < 0:
		setup.stadium = setup.team_a
		_draw_row(STADIUM_ROW)
	else:
		stadium_mode = 1
	_update_palette()


## `$3698` + `$13072`: a team's panel starts over with that team.
func _load_team(which: int) -> void:
	panels[which].reset(setup.team_a if which == 0 else setup.team_b)
	_update_palette()


# --- plan 34: the port's variants ----------------------------------------------------------------
## EXHIBITION / PLAYOFFS: the play mode they mean, the rows moved up.
func _enter_variant() -> void:
	rows.shift = VARIANT_SHIFT
	if variant == "exhibition":
		setup.play_mode = MwPlayoffs.MODE_REGULAR
	elif locked():
		setup.play_mode = MwPlayoffs.MODE_BEST_OF_3 if session.playoffs.best_of_3 != 0 \
				else MwPlayoffs.MODE_PLAYOFFS
	elif setup.play_mode != MwPlayoffs.MODE_BEST_OF_3:
		setup.play_mode = MwPlayoffs.MODE_PLAYOFFS
	confirm = MwConfirmBox.new()
	confirm.name = "Confirm"
	add_child(confirm)
	confirm.setup(plane, rom)
	confirm.answered.connect(func(yes: bool) -> void:
		if yes:
			_leave())


## Whether the original's row [param r] shows (the variants leave out the
## pads, the play mode and - the playoffs - the stadium).
func _shown(r: int) -> bool:
	if variant == "":
		return true
	if r == MwMenuRows.PADS_ROW or r == MwMenuRows.PLAY_MODE_ROW:
		return false
	return not (variant == "playoffs" and r == STADIUM_ROW)


## True while the playoffs' teams can't change (a run in progress).
func locked() -> bool:
	return variant == "playoffs" and session.run_started


## The row to start on: a hidden or locked one moves on; back from a game
## of a run in progress, PLAY GAME.
func _variant_row(r: int, first: bool) -> int:
	if locked() and session.run_games > 0 and (first or previous != MwScreens.CONTROLLER_SELECT):
		r = ACTION_ROW
	if r == MwMenuRows.PADS_ROW or r == MwMenuRows.PLAY_MODE_ROW or r == 5:
		r = 4
	if variant == "playoffs" and r == STADIUM_ROW:
		r = SERIES_ROW
	if variant == "exhibition" and r == SERIES_ROW:
		r = STADIUM_ROW
	if locked() and r < 2:
		r = 4
	action = 0
	return r


func _up(r: int) -> int:
	var t := UP_PLAYOFFS if variant == "playoffs" else UP_EXHIBITION
	var to: int = t.get(r, 4)
	return 4 if locked() and to < 2 else to


func _down(r: int) -> int:
	var t := DOWN_PLAYOFFS if variant == "playoffs" else DOWN_EXHIBITION
	return t.get(r, 4)


## SAVE GAME is offered: a game of the run played since it was started or loaded.
func can_save() -> bool:
	return variant == "playoffs" and session.run_started and session.run_games > 0


func _draw_port_rows(text_only := false) -> void:
	if variant == "playoffs":
		_draw_port_row(SERIES_ROW, current == SERIES_ROW, text_only)
	_draw_port_row(ACTION_ROW, current == ACTION_ROW, text_only)


## The port's rows drawn as the original's rows 3-9 are (`$12D1E`): each
## item's cells filled with the row's fill word, or `$60DD` when selected;
## the text in the menu font, or the dark one when selected.
## [param text_only]: the text alone, over what is there (`$12D18`).
func _draw_port_row(r: int, selected: bool, text_only := false) -> void:
	var fill := MwMenuRows.SELECTED_FILL if selected else rows.fill_word(7)
	var light := MwPlanePainter.FONT_MENU
	var dark := MwPlanePainter.FONT_SMALL
	if r == SERIES_ROW:
		if not text_only:
			MwPlanePainter.fill(plane, ROW_X, SERIES_Y, VALUE_X - ROW_X - 1, 1, fill)
			MwPlanePainter.fill(plane, VALUE_X, SERIES_Y, VALUE_W, 1, fill)
		var font := dark if selected else light
		MwPlanePainter.text(plane, rom, font, "SERIES".to_ascii_buffer(), ROW_X, SERIES_Y, MwMenuRows.TEXT_ATTR)
		var v: String = SERIES_NAMES[1 if setup.play_mode == MwPlayoffs.MODE_BEST_OF_3 else 0]
		MwPlanePainter.text(plane, rom, font, v.to_ascii_buffer(), VALUE_X, SERIES_Y, MwMenuRows.TEXT_ATTR)
		return
	if not can_save():
		if not text_only:
			MwPlanePainter.fill(plane, ROW_X, ACTION_Y, ROW_W, 1, fill)
		_centred_text("PLAY GAME", ROW_X, ROW_W, dark if selected else light)
		return
	for i in 2:                                   # SAVE GAME | PLAY GAME
		var x := ROW_X if i == 1 else ROW_X + ROW_W - HALF_W
		var on := selected and action == i
		if not text_only:
			MwPlanePainter.fill(plane, x, ACTION_Y, HALF_W, 1, MwMenuRows.SELECTED_FILL if on else rows.fill_word(7))
		_centred_text("SAVE GAME" if i == 1 else "PLAY GAME", x, HALF_W, dark if on else light)


func _centred_text(t: String, x: int, w: int, font: int) -> void:
	MwPlanePainter.centred(plane, rom, font, t.to_ascii_buffer(), x, w, ACTION_Y, MwMenuRows.TEXT_ATTR)


## The highlight frame of a port row (`$135F2`'s 34-cell frame; the action
## row's selected half in a run).
func _port_frame(r: int, on: bool, filled: bool) -> void:
	var x := ROW_X
	var w := ROW_W
	var y := SERIES_Y if r == SERIES_ROW else ACTION_Y
	if r == ACTION_ROW and can_save():
		for i in 2:
			MwPlanePainter.erase_frame(plane, ROW_X if i == 1 else ROW_X + ROW_W - HALF_W, y, HALF_W, 1)
		x = ROW_X if action == 1 else ROW_X + ROW_W - HALF_W
		w = HALF_W
	if on:
		MwPlanePainter.frame(plane, rom, x, y, w, 1, filled)
	else:
		MwPlanePainter.erase_frame(plane, x, y, w, 1)


## The variants' pads: P1 drives the rows (and Start / PLAY GAME plays);
## any other player's Left / Right edits team B, as the original's P3 / P4
## do (not while a run keeps its teams; plan 34, an extended set-up: players
## 2-12, MwSession.screen_pads). Idle: the attract demo, as the original's.
func _variant_input(input: MwInputFrame) -> void:
	# plan 34: team A's captain drives the rows as well as P1 (between playoff games)
	var captain := MwRinkControl.captain_screen_pad(session.humans, session.pad_map) if session else 0
	var others := 0
	for p in range(2, (session.screen_pads() if session else 4) + 1):
		if p != captain:
			others |= pad_bits(input, p)
	others &= B_LEFT | B_RIGHT
	var mine := pad_bits(input, 1)
	if captain > 1:
		mine |= pad_bits(input, captain)
	if MwFlow.online(session):
		# plan 35: the host's P1 alone (the shared verbs: never remapped to a pad)
		others = 0
		mine = shared_bits(input)
	if others != 0 and not locked():
		idle = 0
		if saved_row < 0:
			_unhighlight(row)
			current = -1
			_draw_row(row)
			saved_row = row
		row = 1
		current = 1
		_fill = false
		rows.draw(plane, 1, value(1), true)
		_change(-1 if others & B_LEFT else 1)
		return
	if mine == 0:
		if MwAttract.idle_out(idle):
			session.attract = true              # as if Start was pressed
			_start()
		return
	idle = 0
	if saved_row >= 0:                          # P1 takes the menu back
		_select(saved_row, true)
		saved_row = -1
	if mine & B_UP:
		_move(_up(row))
	elif mine & B_DOWN:
		_move(_down(row))
	elif mine & (B_LEFT | B_RIGHT):
		_variant_change(-1 if mine & B_LEFT else 1)
	elif mine & B_START:
		if row == ACTION_ROW and can_save() and action == 1:
			_save_game()
		else:
			_play()


func _variant_change(dir: int) -> void:
	match row:
		ACTION_ROW:
			if not can_save():
				return
			_port_frame(ACTION_ROW, false, false)
			action ^= 1
			_fill = true
			_draw_port_row(ACTION_ROW, true)
			_highlight()
			MwSound.play(SOUND_MOVE)
		SERIES_ROW:
			if locked():
				MwSound.play(MwPortMenu.SOUND_REFUSED)
				return
			setup.play_mode = MwPlayoffs.MODE_BEST_OF_3 if setup.play_mode == MwPlayoffs.MODE_PLAYOFFS \
					else MwPlayoffs.MODE_PLAYOFFS
			_fill = true
			_highlight()
			_draw_port_row(SERIES_ROW, true)
			MwSound.play(SOUND_MOVE)
		_:
			_change(dir)


## PLAY GAME (or Start): the playoffs' first game makes the run (`$11D8E`
## as the original's Start; the bracket follows), a run in progress goes on
## to its next game; an exhibition is the original's regular game.
func _play() -> void:
	session.screens[1] = {"row": row, "current": current, "stadium_mode": stadium_mode}
	if session.attract:
		_start()
		return
	if variant == "playoffs" and session.run_started:
		_go(MwFlow.after_options(session, false))
		return
	session.playoffs.start(setup, session.rng)     # $11D8E
	if variant == "playoffs":
		session.begin_run()
	_go(MwFlow.after_options(session, variant == "playoffs"))


## SAVE GAME: the saved games' list in its save mode (work item 3).
func _save_game() -> void:
	session.screens[1] = {"row": row, "current": current, "stadium_mode": stadium_mode}
	MwSound.play(SOUND_MOVE)
	exit_to(MwScreens.SAVED_GAMES, {"mode": "save"})


# --- the slam -------------------------------------------------------------------------------------
## The top graphic starts above the screen and falls once the screen has
## faded in - not when coming back from the saved games. Back from the
## controller selection it falls from where its wall had risen to, in front
## of the logos, names and title left there ([method _close_wall]).
func _start_slam(cut := false) -> void:
	_group = [plane, panels[0], panels[1], torches[0], torches[1]]
	_group_y = PackedFloat32Array()
	_group_x = PackedFloat32Array()
	for n in _group:
		_group_y.append(n.position.y)
		_group_x.append(n.position.x)
	slam = null
	if previous == MwScreens.CONTROLLER_SELECT:
		_close_wall()
		return
	if previous == MwScreens.SAVED_GAMES:
		return
	if cut and previous == MwScreens.LOCAL_PLAY:
		slam = MwSlam.new(MwPortMenu.TOP_HANG)  # from where the pages hang it (owner)
		_fade_text(0.0, 1)
	else:
		slam = MwSlam.new()
	slam.bounces = true                       # it bounces and lands (owner)
	_place_group()


## 110's opening backwards (owner): the wall falls with the slam from its
## height there, the logo backgrounds fade back in once it landed, then
## the panels' cycle goes on. Nothing to do if the wall had not moved.
func _close_wall() -> void:
	var st: Array = session.screens.get("wall", [0, 1.0])
	session.screens.erase("wall")
	var h := int(st[0])
	var alpha := float(st[1])
	if h <= 0 and alpha >= 1.0:
		return
	for panel in panels:
		panel.hold()
	wall = MwBrickWall.new(self)
	wall.lift(MwControllerSelect.title_plate(plane.tiles, plane.palette, rom))
	wall.close(h, alpha)
	if h > 0:
		slam = MwSlam.new(h)
		slam.bounces = true
		_place_group()


func _slam_pass(elapsed: int, input: MwInputFrame) -> void:
	var pressed := input != null and not input.pressed.is_empty()
	if _lift >= 0:
		return                                      # rising back ([method _lift_pass])
	if pressed and _text_dir > 0:
		_fade_text(1.0, 0)                          # a press: the text at once too
	_text_pass(elapsed)
	if slam != null:
		if pressed:
			slam.settle()                           # a press: in place at once
		elif fader == null or not fader.busy():
			slam.advance(elapsed)
			if slam.thud and slam.impacts == 1:
				MwSound.play(MwSlam.THUD)
				_start_music()
			elif slam.thud:                         # the second bounce's (owner): lower, softer
				MwSound.play_voice(MwSlam.THUD, SECOND_CRASH_RATE, SECOND_CRASH_VOLUME)
		_place_group()
		if slam.done:
			slam = null
	if slam != null:
		return
	_start_music()
	if wall != null:                                # back from 110: the backgrounds fade in
		wall.landed()
		if pressed:
			wall.finish()
		else:
			wall.come_in(elapsed)
		if not wall.busy():
			wall = null


## The variants' music: the menus' (`$136F2`), once the frame has landed.
func _start_music() -> void:
	if _music_due:
		_music_due = false
		MwSound.music_game()


## The stars in their own colours (the port's variants): the starfield's
## picture is palette line 3, the line the torchlight rewrites ([method
## _flicker_step], `menu_line`) - on the Genesis they share it, so the
## original's stars flicker darker with the torches; the port's pages have
## no torches and show line 3 as the screen's palette has it, so the stars
## dimmed going in and brightened coming out (owner: the starfield's palette
## shifted). Here they keep the screen palette's line 3 always; the
## original's game setup (no front menu) keeps the shared line.
func _stars_apart() -> void:
	var pal := palette.duplicate() as RomPalette
	pal.steps = PackedStringArray(["screen_palette", "black 0"])
	starfield.palette = pal


## The logo on a layer of its own, as the port's menus draw it (their
## palette: line 1 the logo's colours, its black panel see-through), and a
## hole for it in the window.
func _logo_apart() -> void:
	_music_due = true
	var r := MwPortMenu.LOGO
	MwPlanePainter.fill(plane, r.position.x, r.position.y, r.size.x, r.size.y, 0x8000)
	var k := SKULL_STRIP
	MwPlanePainter.fill(plane, k.position.x, k.position.y, k.size.x, k.size.y, 0x8000)
	logo_plane = RomPlane.new()
	logo_plane.name = "LogoPlane"
	logo_plane.tiles = plane.tiles
	var pal := palette.duplicate() as RomPalette
	pal.steps = PackedStringArray(MwMenuBackdrop.STEPS)
	logo_plane.palette = pal
	add_child(logo_plane)
	move_child(logo_plane, plane.get_index())          # under the window: the frame falls in front
	MwMenuBackdrop.logo(logo_plane, rom, r.position.x, r.position.y)      # plan 40 (M5)


func _place_group() -> void:
	_place_top(slam.height() if slam else 0, slam.shake if slam else 0)


## The top [param h] px above its place, shaken [param dx] px sideways (the
## stars, the menu's text and the logo stay; the logo is under the window,
## which passes in front of it falling, bouncing and rising - owner: the
## logo fixed in place, never on top).
func _place_top(h: int, dx: int) -> void:
	for i in _group.size():
		_group[i].position = Vector2(_group_x[i] + dx, _group_y[i] - h)


## The menu's text from [param alpha], fading [param dir] (+1 in, -1 out)
## at a whole fade's pace of [param ticks].
func _fade_text(alpha: float, dir: int, ticks := TEXT_FADE_TICKS) -> void:
	_text_alpha = alpha
	_text_dir = dir
	_text_ticks = maxi(ticks, 1)
	_show_text()


func _text_pass(elapsed: int) -> void:
	if _text_dir == 0:
		return
	_text_alpha = clampf(_text_alpha + _text_dir * float(elapsed) / _text_ticks, 0.0, 1.0)
	if _text_alpha <= 0.0 or _text_alpha >= 1.0:
		_text_dir = 0
	_show_text()


func _show_text() -> void:
	var plane_a := plane.lower
	if plane_a == null:
		return
	var clip := plane_a.get_parent() as CanvasItem
	(clip if clip is Control else plane_a).modulate.a = _text_alpha


## Menu Back to LOCAL PLAY (owner): the top rises from where it is to where
## the port's pages hang it ([constant MwPortMenu.TOP_HANG]) as the
## controller selection's wall rises - faster and faster, to the gate's
## clinks ([constant MwBrickWall.SOUND]; owner: the wall going back up
## has its sound) - the text fading out, the logo staying (the rising
## window passes in front of it), then the cut to LOCAL PLAY, whose top
## hangs just there; the clinks ring out over it (the title music leaves
## FM6 free: [MwFmSfx]). A press ends it at once, the clinks too.
func _start_lift() -> void:
	_lift_from = slam.height() if slam else 0
	slam = null
	_lift = 0
	_fade_text(_text_alpha, -1, LIFT_TICKS * 3 / 4)   # gone before the top gets there
	_place_top(_lift_from, 0)
	MwSound.fm_effect(MwBrickWall.SOUND)


func _lift_pass(elapsed: int, input: MwInputFrame) -> void:
	_lift += elapsed
	if input != null and not input.pressed.is_empty() and _lift < LIFT_TICKS:
		_lift = LIFT_TICKS
		MwSound.fm_effect_stop()
	var f := clampf(float(_lift) / LIFT_TICKS, 0.0, 1.0)
	f = f * f                                    # from rest, faster and faster (MwBrickWall.rise_height)
	_place_top(roundi(lerpf(_lift_from, MwPortMenu.TOP_HANG, f)), 0)
	_text_pass(elapsed)
	if _lift >= LIFT_TICKS:
		_lift = -1
		_save_starfield()
		exit_to(MwScreens.LOCAL_PLAY, {"cut": true}, false)
