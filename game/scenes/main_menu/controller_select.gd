class_name MwControllerSelect
extends Node2D
## The controller selection (screen 110, plan 34 section 5): under the game
## setup's top - the teams' panels, their logos and names, the logo - one
## line per player in number order (players whose device is there or bound,
## and anyone already on a team), each in one of three columns: team A on
## the left, the middle (not playing), team B on the right. A line is the
## game setup's row bar with the player's number in their colour
## ([MwPlayerColours]) and their device's tag (plan 23: "XB3"), dimmed while
## the device is away.
##
## Each player moves their own line with their Left / Right (sound `$25`);
## a full team (six) refuses (sound `$2E`, the line shakes). Back on a team
## moves the line to the middle; player 1's Back in the middle goes back to
## the game setup. Player 1's accept goes on (the rules: [method refusal]).
## The players are the session's ([member MwSession.humans]).
##
## Online (plan 35 work item 4): the lines are the match's players
## ([member online]: every lobby player, whatever this machine's devices),
## without device tags (their devices are other machines'), dimmed while
## their machine is away (MwInputFrame.away); going on needs a player on a
## team (CPU v CPU is local only).
##
## Every line in the middle is CPU v CPU - a spectated match
## (MwSession.spectated): a local exhibition's alone (owner, 2026-10-10).
## The playoffs and online refuse it as they refuse their other set-ups
## ([method refusal]): sound `$2E`, player 1's line shaking, and the reason
## on the title plate for [constant MESSAGE_TICKS] ticks ([method say]).
## Short names: l a plane being painted (RomPlane).

## The selection is left: [param go_on] true to go on (accepted, the rules allowing it),
## false back to the game setup (a Back in the middle).
signal leave(go_on: bool)

const SOUND_MOVE := MwSoundIds.MOVE
const SOUND_REFUSED := MwSoundIds.REFUSED
const FONT := MwPlanePainter.FONT_MENU
const TEXT_ATTR := MwMenuRows.TEXT_ATTR
## The columns' first cells by team (0 team A, [constant MwHumans.MIDDLE]
## the middle, 1 team B) and their width.
const COLUMNS := {0: 3, MwHumans.MIDDLE: 15, 1: 27}
const COLUMN_W := 10
## The lines' area (pixels: plane A's rows 16-27) and their spacing: two
## rows apart while they fit, else one (twelve lines).
const TOP := 128
const HEIGHT := 96
const STEP := 16
const STEP_TIGHT := 8
const SHAKE_TICKS := 12
const AWAY := Color(1, 1, 1, 0.45)
## The title plate's row (between the panels, under the logo).
const TITLE_Y := 13
## The lines' text baseline row inside their layers.
const BASE := 2
## How long a refusal's reason stays on the title plate ([method say]).
const MESSAGE_TICKS := 90
## The title plate's text.
const TITLE := "CONTROLLER SELECT"
## The refusals' reasons ([method refusal]): CPU v CPU outside a local
## exhibition, the playoffs' team A without a player.
const EXHIBITION_ONLY := "EXHIBITION ONLY"
const LOCAL_ONLY := "LOCAL PLAY ONLY"
const TEAM_A_NEEDS := "TEAM A NEEDS A PLAYER"

## [method _press]'s answers.
const MOVED := 1
const GO_BACK := 2
const GO_ON := 3

var rom: PackedByteArray
var humans: MwHumans
var playoffs := false
var shown: Array[int] = []           ## the players with a line, in number order
var _bars := {}                       ## player -> RomPlane (the bar and the tag)
var _names := {}                      ## player -> RomPlane (the number, tinted)
var _shake := {}                      ## player -> ticks of shaking left
var _tiles: RomTileSet
var _palette: RomPalette
var _fill := 0
var _devices := -1
var _title: RomPlane
## The title plate's message ([method say]) and its ticks left (0: the title).
var message := ""
var _message_ticks := 0
## Plan 35: the online match's players (empty: a local game).
var online: Array = []
var _echoed := false                  ## plan 41: the lines show predicted presses
## The side each line was last drawn on (player -> team, MwHumans.MIDDLE the
## middle): what the screen shows, a prediction's included.
var drawn := {}
var _away := {}


## Draws on [param window]'s tiles and palette; [param fill] the rows' bar word.
func setup(window: RomPlane, rom_: PackedByteArray, humans_: MwHumans, fill: int, is_playoffs: bool) -> void:
	rom = rom_
	humans = humans_
	_tiles = window.tiles
	_palette = window.palette
	_fill = fill
	playoffs = is_playoffs
	_title = title_plate(_tiles, _palette, rom)
	add_child(_title)
	refresh()


## The CONTROLLER SELECT plate on a layer of its own ([param tiles] and
## [param palette]: the window's) - also the game setup's, behind its
## falling wall on the way back from here ([MwBrickWall]).
static func title_plate(tiles: RomTileSet, palette: RomPalette, rom_: PackedByteArray) -> RomPlane:
	var l := RomPlane.new()
	l.name = "Title"
	l.tiles = tiles
	l.palette = MwGlyphs.plate_palette(palette)
	l.ready.connect(func() -> void: plate_text(l, rom_, TITLE), CONNECT_ONE_SHOT)
	return l


## [param text] on the title plate [param l] (centred to the pixel; what
## was there wiped).
static func plate_text(l: RomPlane, rom_: PackedByteArray, text: String) -> void:
	l.wipe()
	MwGlyphs.plate_title(l, rom_, FONT, text.to_ascii_buffer(), TITLE_Y, TEXT_ATTR)


## A refusal's [param why] on the title plate for [constant MESSAGE_TICKS]
## ticks, then the title again ([method handle]).
func say(why: String) -> void:
	message = why
	_message_ticks = MESSAGE_TICKS
	if is_instance_valid(_title) and _title.is_inside_tree():
		plate_text(_title, rom, why)


## The title plate, for the screen to put under its brick wall
## ([MwBrickWall]): no longer this node's.
func take_title() -> RomPlane:
	if _title != null and _title.get_parent() == self:
		remove_child(_title)
	return _title


## The players with a line: a device there or bound, or on a team.
static func players_shown(who_plays: MwHumans) -> Array[int]:
	var out: Array[int] = []
	for p in range(1, MwVerbs.PLAYERS + 1):
		if p == 1 or MwInputMap.connected(p) or who_plays.team_of(p) != MwHumans.MIDDLE or _bound(p):
			out.append(p)
	return out


static func _bound(p: int) -> bool:
	for v in MwVerbs.all_verbs():
		if MwSettings.binding(p, v) != null:
			return true
	return false


## Rebuilds the lines (the players shown change as gamepads come and go).
func refresh() -> void:
	_devices = MwInputMap.devices_changed
	if online.is_empty():
		shown = players_shown(humans)
	else:
		shown.assign(online)
	for p in _bars.keys():
		if not p in shown:
			(_bars[p] as Node).queue_free()
			(_names[p] as Node).queue_free()
			_bars.erase(p)
			_names.erase(p)
	for p in shown:
		if not _bars.has(p):
			_bars[p] = _layer("Bar%d" % p)
			_names[p] = _layer("Name%d" % p)
			(_names[p] as RomPlane).modulate = MwPlayerColours.colour(rom, p)
	draw()


## Every line where its player is.
func draw() -> void:
	var step := clampi(HEIGHT / maxi(shown.size(), 1), STEP_TIGHT, STEP)
	var top := TOP + (HEIGHT - shown.size() * step) / 2
	for i in shown.size():
		var p := shown[i]
		var bar: RomPlane = _bars[p]
		var name_plane: RomPlane = _names[p]
		bar.clear()
		name_plane.clear()
		drawn[p] = humans.team_of(p)
		var col: int = COLUMNS[humans.team_of(p)]
		var cell := MwPrompts.row(rom, FONT, BASE)          # the text's cell row
		MwPlanePainter.fill(bar, col, cell, COLUMN_W, 1, _fill)
		var n := ("P%d" % p).to_ascii_buffer()
		var tag := (MwInputMap.device_tag(p) if online.is_empty() else "").to_ascii_buffer()
		var w := MwGlyphs.text_width(rom, FONT, n) + 1 + MwGlyphs.text_width(rom, FONT, tag)
		var x := col + (COLUMN_W - w) / 2
		MwGlyphs.text(name_plane, rom, FONT, n, x, BASE, TEXT_ATTR)
		MwGlyphs.text(bar, rom, FONT, tag, x + MwGlyphs.text_width(rom, FONT, n) + 1, BASE, TEXT_ATTR)
		var shake := 0
		if int(_shake.get(p, 0)) > 0:
			shake = 2 if int(_shake[p]) / 2 % 2 == 0 else -2
		for l: RomPlane in [bar, name_plane]:
			l.position = Vector2(shake, top + i * step - 8 * cell)
		var here := MwInputMap.connected(p) if online.is_empty() else not _away.has(p)
		bar.modulate = Color.WHITE if here else AWAY
		name_plane.modulate = MwPlayerColours.colour(rom, p) * (Color.WHITE if here else AWAY)


## One pass: each shown player's verbs. Returns nothing; [signal leave]
## says when the screen is done (go on, or back to the game setup).
func handle(elapsed: int, input: MwInputFrame) -> void:
	if _devices != MwInputMap.devices_changed:
		refresh()
	if not online.is_empty() and input != null and input.away != _away:
		_away = input.away.duplicate()
		draw()
	if _message_ticks > 0:
		_message_ticks = maxi(_message_ticks - elapsed, 0)
		if _message_ticks == 0:
			message = ""
			if is_instance_valid(_title) and _title.is_inside_tree():
				plate_text(_title, rom, TITLE)
	var moved := false
	for p in _shake.keys():
		_shake[p] = maxi(int(_shake[p]) - elapsed, 0)
		moved = true
		if _shake[p] == 0:
			_shake.erase(p)
	if input != null:
		for p in shown:
			match _press(p, input):
				MOVED:
					moved = true
				GO_BACK:
					leave.emit(false)
					return
				GO_ON:
					leave.emit(true)
					return
	if moved:
		draw()


## Player [param p]'s presses in [param input]: their line moved (or
## shaken), or player 1 going back or on (the caller leaves) - [constant
## MOVED], [constant GO_BACK], [constant GO_ON]; 0 nothing.
func _press(p: int, input: MwInputFrame) -> int:
	var d := 0
	if input.menu_pressed(p, "ui_left"):
		d = -1
	elif input.menu_pressed(p, "ui_right"):
		d = 1
	elif input.menu_pressed(p, "ui_back"):
		if humans.team_of(p) == MwHumans.MIDDLE:
			return GO_BACK if p == 1 else 0
		humans.set_team(p, MwHumans.MIDDLE)
		MwSound.play(SOUND_MOVE)
		return MOVED
	elif p == 1 and input.menu_pressed(p, "ui_accept"):
		var why := refusal()
		if why != "":
			MwSound.play(SOUND_REFUSED)
			_shake[1] = SHAKE_TICKS
			say(why)
			return MOVED
		MwSound.play(SOUND_MOVE)
		return GO_ON
	if d == 0:
		return 0
	if humans.move(p, d):
		MwSound.play(SOUND_MOVE)
	else:
		MwSound.play(SOUND_REFUSED)
		_shake[p] = SHAKE_TICKS
	return MOVED


## Plan 41 (online, a client): this machine's players' presses its game
## hasn't run yet ([param presses]: player -> verbs) shown at once - their
## lines moved on a copy of the sides by [method _press] (going on or back
## is the game's to decide: never shown early), drawn, the sides put back;
## {} draws the sides as they are once more after a prediction.
func predict(presses: Dictionary) -> void:
	if presses.is_empty():
		if _echoed:
			_echoed = false
			draw()
		return
	var real := humans
	var shake := _shake.duplicate()
	humans = real.copy()
	MwLocalEcho.run(func() -> void:
		for p: int in presses:
			if p in shown:
				for verb: String in presses[p]:
					_press(p, MwLocalEcho.frame(p, verb))
		draw())
	humans = real
	_shake = shake
	_echoed = true


## Why the players can't go on ("" they can; the reason as the title plate
## shows it, [method say]): nobody on a team - CPU v CPU, a spectated match
## (MwSession.spectated) - is a local exhibition's alone (owner,
## 2026-10-10; plan 34 section 5: local only), so the playoffs and
## online refuse it; the playoffs need a player on team A (the run's team).
## Any other set-up plays - the original's, or an extended one (MwHumans).
func refusal() -> String:
	if humans.total() == 0 and not online.is_empty():
		return LOCAL_ONLY                         # plan 35: CPU v CPU is local only
	if humans.total() == 0 and playoffs:
		return EXHIBITION_ONLY
	if playoffs and humans.count(0) == 0:
		return TEAM_A_NEEDS
	return ""


func _layer(n: String) -> RomPlane:
	var l := RomPlane.new()
	l.name = n
	l.tiles = _tiles
	l.palette = _palette
	add_child(l)
	return l
