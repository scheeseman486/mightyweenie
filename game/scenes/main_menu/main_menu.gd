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

const START_SCREENS := 0x13A6C     ## next screen by play mode (`$13A6C`)
const PERIOD_MINUTES := 0x1C1D2    ## minutes by period index (`$45F0`)
const TEAM_MENU_ORDER := 0x1C1A4   ## menu position -> team (`$4620`)
const TEAM_MENU_POS := 0x1C1BB     ## team -> menu position (`$4606`)
const PLAYOFF_NEXT_A := 0x1F522    ## next team B in conference 0-9 (+23: backwards)
const PLAYOFF_NEXT_B := 0x1F550    ## ... in conference 10-19
const TORCHES := [0x13526, 0x1352E]  ## x, y, depth, attr XOR of each torch
const TORCH_ANIM := "anim_041bca"
const TORCH_SECOND_START := 0x580
const FLICKER := 0x135E6           ## next line-3 palette: [current * 4 + rng(0, 2)]
const BACKDROP := 0x41BF2
const BACKDROP_ROWS := 16
const STADIUM_ROW := MwMenuRows.STADIUM_ROW
const SOUND_MOVE := 0x25           ## `$13CEE` sound: row moved / value changed
## The original's main menu loop takes 3 ticks a pass (BlastEm records: 3.02
## on average); our passes are 1 tick, so what it does at random once per
## pass (the torchlight flicker) runs once per 3 ticks here (owner, plan 02).
const PASS_TENTHS := 30
## Entry -> its first pass: loading takes 14 ticks in the original (the
## screen is still black). The panels' timers start there.
const LOAD_TICKS := 14
const SCREEN_SIZE := Vector2(320, 224)

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

var _fill := false        # `$C3B4`: fill the highlight on its next drawing
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
	var a := plane.lower
	if a == null or a.get_parent() is Control:
		return
	var top := plane.split_row * 8
	var clip := Control.new()
	clip.name = "PlaneAClip"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = Vector2(0, top)
	clip.size = Vector2(SCREEN_SIZE.x, SCREEN_SIZE.y - top)
	var parent := a.get_parent()
	parent.add_child(clip)
	parent.move_child(clip, a.get_index())
	var at := a.position
	a.reparent(clip, false)
	a.position = at - Vector2(0, top)


## The tick counter as the panels read it (ticks since entering).
func idle_clock() -> int:
	return _clock


func value(r: int) -> int:
	return setup.to_bytes()[r]


func set_value(r: int, v: int) -> void:
	setup.set(MwMatchSetup.FIELDS[r], v & 0xFF)


func _enter_screen(_data: Dictionary) -> void:
	if not MwRom.available() or session == null:
		return
	rom = MwRom.data()
	setup = session.setup
	rows = MwMenuRows.new(rom)
	session.reseed_aux()
	MwSound.music_game()                    # `$136F2`: the menus' music (kept if it plays)
	idle = 0
	session.end_attract()
	_load_backdrop()
	var st: Dictionary = session.screens.get(1, {})
	var first := previous == 0 or st.is_empty()
	if not first:
		stadium_mode = int(st["stadium_mode"])
		current = int(st["current"])
	for p in 2:
		panels[p].setup_panel(self, p)
	for r in MwMenuRows.ROWS:
		if rows.has_row(r) and r != STADIUM_ROW:
			rows.draw(plane, r, value(r), r == current)
			_handler(r, 1)
	row = 0 if first else int(st["row"])
	saved_row = -1
	_fill = true
	current = row
	_highlight()
	starfield.start(session.rng_aux)
	_start_torches()
	flicker = 0


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
	for p in panels:
		steps.append_array(p.palette_steps())
	if _flickered:
		steps.append("menu_line %d" % flicker)
	palette.steps = steps


var _flickered := false


func _start_torches() -> void:
	for i in 2:
		var a: int = TORCHES[i]
		var t := torches[i]
		t.position = Vector2(MwGfx.u16(rom, a), MwGfx.u16(rom, a + 2))
		t.attr_xor = MwGfx.u16(rom, a + 6)
		t.restart()
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
	current = row
	_highlight()
	for r in range(2, MwMenuRows.ROWS):
		if rows.has_row(r):
			rows.draw(plane, r, value(r), r == current, true)
	for t in torches:
		t.advance(elapsed)
	_pass_tenths += 10 * elapsed
	while _pass_tenths >= PASS_TENTHS:
		_pass_tenths -= PASS_TENTHS
		_flicker_step()
	for p in panels:
		p.step(elapsed)
	if input != null and input.is_pressed("ui_back") and MwSettings.front_menu:
		_back()
		return
	_menu_input(input)


## `$13572`: one time in four, the torchlight picks its next palette.
func _flicker_step() -> void:
	var rng := session.rng_aux
	if rng.next_state() & 3 != 0:
		return
	var d := rng.range_value(0, 2)
	flicker = rom[FLICKER + flicker * 4 + d]
	_flickered = true
	_update_palette()


## The original's "newly pressed" byte of player [param p] (menu verbs).
static func pad_bits(input: MwInputFrame, p: int) -> int:
	return input.pad_bits(p) if input else 0


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
			if idle < MwAttract.IDLE_TICKS:
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
	rows.unhighlight(plane, row)
	current = -1
	rows.draw(plane, row, value(row), false)
	row = to
	current = row
	_fill = true
	_highlight()
	rows.draw(plane, row, value(row), true)


## Left / Right: the next value (teams in the menu's order), then the row's handler.
func _change(dir: int) -> void:
	var v := value(row)
	if row < 2:
		v = rom[TEAM_MENU_POS + v]
	v += dir
	if v < 0:
		v = rows.count(row) - 1
	elif v >= rows.count(row):
		v = 0
	if row < 2:
		v = rom[TEAM_MENU_ORDER + v]
	set_value(row, v)
	_handler(row, dir)
	_fill = true
	_highlight()
	rows.draw(plane, row, value(row), true)
	MwSound.play(SOUND_MOVE)                # `$13A06`


## Menu Back (plan 21): remember the row, back to the port's front menu.
func _back() -> void:
	session.screens[1] = {"row": row, "current": current, "stadium_mode": stadium_mode}
	MwSound.music_fade_out(32)
	exit_to(MwScreens.FRONT_MENU)


## Start: remember the row, fade out, go where the play mode says.
func _start() -> void:
	session.screens[1] = {"row": row, "current": current, "stadium_mode": stadium_mode}
	session.playoffs.start(setup, session.rng)     # $11D8E
	var next := 3 if session.attract else rom[START_SCREENS + setup.play_mode]
	exit_to(next)


func _highlight() -> void:
	rows.highlight(plane, row, _fill)
	_fill = false


func _draw_row(r: int) -> void:
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
		if a >= 20:
			a = 9 if a == 20 else 0
		setup.team_a = a
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
			var a := setup.team_a
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
