class_name MwCharacterSelect
extends MwScreen
## The selection steps before a match (plan 34 section 7, work items 9-10;
## [MwSelection]): one scene for three screens, each running the steps that
## apply from its entry on, then fading out to the matchup:
##
## * **111, character selection** (entry `characters`; owner: six portraits
##   a side, one per position - the player picks a position, then its
##   character with Left / Right): team A's six positions on the left, team
##   B's on the right - C, LW, RW over LD, RD, G - each a card
##   ([MwCharacterCard]: the position's name large, the portrait of the
##   character who plays it), with each one's number, name and position
##   rating listed under them. The characters start as the rink's entry
##   would have them (plan 33's rehearsal, MwMatchRehearsal; a playoff run's
##   dead replaced), or as the last game left them. Each player's cursor is
##   their P<n> over the portrait (from the bottom up, left, right, left,
##   right, first come first) - the menus' frame in their colour once they have
##   taken the position (owner, 2026-10-12), filled when locked - moving
##   on their team's positions; accept takes one (a position another player
##   took refuses, sound `$2E`); with line-ups on, Left / Right then step the
##   position's characters ([method MwLineup.step]: one playing another
##   position swaps with it unless a player locked that one - refused) and
##   accept locks (the frame filled, the portrait pulls its face); with
##   line-ups off accept takes and locks at once (the position's starter).
##   Back unlocks, then gives the position back; player 1's Back with no
##   position goes back to the controller selection. Everyone locked:
##   READY for 30 ticks (a Back takes it back), then the vote, the panels or
##   the fade-out.
## * **The captain vote**: on 111 after the picks - the positions nobody
##   picked dim, each player's cursor becomes a ballot among their team's
##   picked characters (accept votes, Back takes it back) - or on its own
##   screen (112, entry `vote`) without character selection, between the
##   team's players, each listed with their P<n> and device tag, the
##   voters' ballots their tags beside the line they vote for.
##   [MwCaptainVote]: the most votes win; a tie votes again among the tied,
##   then the port's draw. The captain gets a C ([member MwHumans.captains]).
## * **The line-up panels** ([MwLineupPanel]; entry `lineups`, 113, alone
##   over the starfield, without a title - owner, 2026-10-10: the panels
##   covered it): team A's from above into the top half and team B's from
##   below into the bottom half, meeting in the middle - one team with
##   players: its panel alone, from above - with the game options' slam
##   ([MwSlam]), its thud and the whole picture's shake; a press lands them
##   at once (and does nothing else). Two landed over 111 / 112 cover it:
##   what was behind goes, the starfield left ([method _hide_behind]). Each shows DONE with the glyph of its
##   drivers' confirm ([method confirm_glyphs]). Up / Down browse a card's
##   candidates on that card alone, accept or Left / Right commit (the
##   swap), Back reverts ([method MwLineupPanel.browse]). Every panel READY:
##   the fade-out. Back on a panel that isn't READY with nothing browsed
##   (owner: the player can back out of the line-ups to the controller
##   selection): the controller selection for everyone, the
##   session's players as the screen found them ([method _leave_back]).
##
## What the steps decide goes to the session's players ([MwHumans]:
## [member MwHumans.positions], [member MwHumans.captains], [member
## MwHumans.lineups]) and, with line-ups on, to the setup for the rink's
## entry ([method MwSelection.finish], [method MwLineup.apply]).
##
## Online (plan 35 work item 4) nobody waits for a player whose machine is
## away (MwInputFrame.away): they get the first free position, locked; their
## ballot isn't waited for; a panel whose drivers are all away is READY.
##
## The look is the port menus': the starfield, the menu fonts and frames, the
## pause menu's plate for the title, the players' colours
## ([MwPlayerColours]), the original's portraits and team logos and names
## (read from the ROM at run time).
## Short names: v the captain vote (MwCaptainVote).

enum Stage { PICK, READY, VOTE, RESULT, PANELS, OUT }
enum Pick { MOVING, PICKED, LOCKED }

const SOUND_MOVE := MwSoundIds.MOVE
const SOUND_REFUSED := MwSoundIds.REFUSED
## Everyone locked: READY this long before going on.
const READY_TICKS := 30
## The captains shown (their C) before the panels or the fade-out.
const RESULT_TICKS := 60
## Every panel READY: this long before the fade-out.
const DONE_TICKS := 20
## The longest a portrait pulls its face before the next one's turn.
const FACE_TICKS := 120
## The titles: what to do now (owner, 2026-10-13: clearer, as instructions
## such as VOTE FOR CAPTAIN; were CHARACTER SELECT, CAPTAIN VOTE, CAPTAINS).
## Picking with line-ups off: a position (its starter plays it).
const TITLE_PICK := "PICK YOUR POSITION"
## Picking with line-ups on: a position, then who plays it.
const TITLE_PICK_LINEUPS := "PICK YOUR CHARACTER"
## Everyone locked (Back still takes it back).
const TITLE_READY := "READY"
const TITLE_VOTE := "VOTE FOR CAPTAIN"
## A tie: its voters vote again among the tied ([MwCaptainVote]).
const TITLE_REVOTE := "TIE - VOTE AGAIN"
## The result, its captains' C shown: one team voted, or both.
const TITLE_CAPTAIN := "CAPTAIN CHOSEN"
const TITLE_CAPTAINS := "CAPTAINS CHOSEN"
const FONT := MwPlanePainter.FONT_MENU
const FONT_DARK := MwPlanePainter.FONT_SMALL
const TEXT_ATTR := MwMenuRows.TEXT_ATTR
## 111's layout (cells): the title's row, the teams' names, each team's
## card columns (content's first cell), the card rows (C LW RW, LD RD G),
## the list of names under them; each team's half from its first cell.
const TITLE_Y := 1
const TEAM_Y := 3
const HALF_X := [0, 20]
const HALF_W := 20
const CARD_X := [[1, 7, 13], [22, 28, 34]]
const CARD_Y := [5, 13]
const LIST_Y := 22
## The list's columns by team: its first cell and the cell after its last.
const LIST_X := [[1, 18], [22, 39]]
## 112's layout: the players' lines (first row, rows apart), the ballots
## under each line (four a row, cells apart).
const LINE_Y := 6
const LINE_STEP := 3
const LINE_X := [2, 22]
const BALLOTS_A_ROW := 4
const BALLOT_STEP := 4
const DIM := MwUiInk.DARK

@onready var plane: RomPlane = $Plane
@onready var starfield: RomStarfield = $Starfield
@onready var palette: RomPalette = $Plane.palette

var rom: PackedByteArray
var humans: MwHumans
var stage := Stage.PICK
## The steps from this entry still to come ("vote", "lineups").
var steps: Array[String] = []
## Each team's line-up (null: a team without players).
var lineups: Array = [null, null]
## The cards by team and position (111).
var cards: Array = [[], []]
## player -> their cursor: a position (picking, voting on 111) or a line
## (voting on 112: an index into the vote's candidates).
var cursor := {}
## player -> [enum Pick] (111).
var picks := {}
## Each team's position -> the player who took it.
var taken: Array = [{}, {}]
## Each team's vote (null: none).
var votes: Array = [null, null]
var panels: Array[MwLineupPanel] = []
var rehearsal: MwMatchRehearsal
## The title shown ("": none - the line-up panels).
var title := ""

var _timer := 0
var _layers := {}                    # player -> RomPlane: their frame (and 112's line), in their colour
var _tag_layers := {}                # player -> RomPlane: their P<n> over the cards, in their colour
var _title: RomPlane
var _list: RomPlane                  # 111's names, 112's lines
var _names: RomPlane                 # the teams' names
var _portrait_palettes: Array[RomPalette] = []
var _logo_palettes: Array[RomPalette] = []
var _name_palette: RomPalette
var _on_vote_screen := false
var _faces: Array[MwCharacterCard] = []   # locked cards waiting to pull their faces
var _face: MwCharacterCard                # the one pulling its face now
var _face_ticks := 0                      # ... for this long
var _found := {}                          # the players' positions, captains, line-ups as the screen found them
var _glyphs_for := []                     # the glyph generation and devices the panels' glyphs were picked for
var _card_of := {}                        # player -> the card (Vector2i(team, position)) their cursor was last on
var _arrival := {}                        # player -> when they came to it (the tags' order there)
var _arrived := 0
var _echoed := false                      # plan 41: the picks or the vote show predicted presses
## Plan 45 (determinism L1): [method predict_local]'s presses are running -
## a card's face is never put to rest by one (its portrait and its voices
## are the game's: [method _keep_selection] doesn't keep them).
var _predicting := false
## What the picks last drew (player -> [Vector2i(team, position), their
## Pick]): what the screen shows, a prediction's included.
var drawn := {}
## The controller selection the line-up panels are pushed over, in sight
## (owner, 2026-10-12: it doesn't fade; MwRouter's "over"): its picture
## under this screen's, its starfield and black left out - this screen's
## own, carried on from it, drawn under it - and its title plate fading out
## ([method MwScreen.covered_fades]); backing out the panels pull back off
## it and the plate fades back in ([method _pull_back]). Null: none (113
## entered any other way: Back goes to 110 by a fade).
var under: MwScreen = null
## The pull back's ticks so far (-1: not pulling back).
var _pull := -1
## Its covered layers' fade (0 shown .. 1 gone).
var _cover := 0.0


func _enter_screen(data: Dictionary) -> void:
	if not MwRom.available() or session == null:
		return
	rom = MwRom.data()
	humans = session.humans
	_found = {"positions": humans.positions.duplicate(), "captains": humans.captains.duplicate(),
			"lineups": humans.lineups.duplicate(true)}
	palette.team_a = session.setup.team_a
	palette.screen = 1
	palette.steps = PackedStringArray(["screen_palette", "black 0"])
	starfield.start(session.rng_aux)
	under = MwScreen.under_of(data)
	if under != null:
		_come_over(under)
	_make_palettes()
	_title = _layer("Title", MwGlyphs.plate_palette(palette))
	_names = _layer("TeamNames", palette)
	_list = _layer("List", palette)
	_build_lineups()
	match entry:
		"vote":
			_on_vote_screen = true
			steps = ["lineups"]
			_draw_team_names()
			_start_vote()
		"lineups":
			_start_panels()                      # no title: the panels cover the screen
		_:
			steps = ["vote", "lineups"]
			_draw_team_names()
			_start_picks()


## Coming over [param _screen] (the controller selection): its picture stays
## under this screen's, without its own starfield and black - this
## screen's, the stars going on where they were ([member
## MwSession.menu_stars]), drawn under it ([member CanvasItem.z_index]).
func _come_over(_screen: MwScreen) -> void:
	starfield.restore(session.menu_stars)
	_show_under_sky(false)


## [member under]'s starfield and black shown ([param on]: its own again,
## leaving - its stars where this screen's are, this screen's gone) or left
## out (this screen's drawn under it instead).
func _show_under_sky(on: bool) -> void:
	if under == null or not is_instance_valid(under):
		return
	for n in ["Backdrop", "Starfield"]:
		var c := under.get_node_or_null(n) as CanvasItem
		if c != null:
			c.visible = on
		var mine := get_node_or_null(n) as CanvasItem
		if mine != null:
			mine.z_index = -1
			mine.visible = not on
	var stars := under.get_node_or_null("Starfield") as RomStarfield
	if on and stars != null:
		stars.restore(starfield.state())


## [member under]'s covered layers (its title) at [member _cover]: faded
## over the menus' cut ([constant MwMenuCut.FADE_TICKS]) as the panels come,
## back as they pull back.
func _cover_pass(elapsed: int) -> void:
	if under == null or not is_instance_valid(under):
		return
	var to := 0.0 if _pull >= 0 else 1.0
	if _cover == to:
		return
	var d := float(elapsed) / MwMenuCut.FADE_TICKS
	_cover = minf(_cover + d, to) if to > _cover else maxf(_cover - d, to)
	for c in under.covered_fades():
		c.modulate.a = 1.0 - _cover


# --- the line-ups ------------------------------------------------------------------------------------

## Each team's line-up: the original's starters (the rehearsal of the
## rink's entry, without line-ups; a run's dead replaced), or for a team with
## players the one the last game kept when it was this team's. A team
## without players is only shown (its line-up stays the original's).
func _build_lineups() -> void:
	if entry == "vote" and MwSelection.panel_teams(session).is_empty():
		return                               # the vote alone: no characters shown
	var su := MwSelection.for_the_rink(session, session.setup.copy())
	su.lineups = []
	rehearsal = MwMatchRehearsal.run(rom, su, session.rng.state, session.playoffs)
	var ids := [session.setup.team_a, session.setup.team_b]
	for t in 2:
		var lineup := MwLineup.new(rom, ids[t], MwLineup.starters_of(rehearsal, t), MwLineup.dead_mask(session, t))
		var kept: PackedInt32Array = humans.lineups[t]
		if humans.count(t) > 0 and kept.size() == MwLineup.POSITIONS and _kept_for(t) and _usable(lineup, kept):
			lineup.slots = kept.duplicate()
		lineups[t] = lineup


## True when the line-up kept for team [param t] was chosen for the team it
## has now: the session's last one for the same teams, or (a loaded run)
## the playoffs' team A - the run's own team.
func _kept_for(t: int) -> bool:
	var was := session.lineup_teams
	var ids := [session.setup.team_a, session.setup.team_b]
	if was.size() == 2:
		return int(was[t]) == ids[t]
	return t == 0 and MwFlow.port_playoffs(session)


static func _usable(lineup: MwLineup, kept: PackedInt32Array) -> bool:
	for pos in MwLineup.POSITIONS:
		if not kept[pos] in lineup.candidates(pos) or kept.count(kept[pos]) > 1:
			return false
	return true


func _palette_for(steps_: PackedStringArray, team: int) -> RomPalette:
	var team_palette := RomPalette.make(1, steps_, team, session.setup.stadium)
	return team_palette


func _make_palettes() -> void:
	var ids := [session.setup.team_a, session.setup.team_b]
	for t in 2:
		# the portraits: line 1 the team's colours (the game setup's panels showing a player)
		_portrait_palettes.append(_palette_for(PackedStringArray(["screen_palette", "black 0", "team_line a 1 1"]),
				ids[t]))
		# the logos: line 1 the team's panel colours (the game setup's panels)
		_logo_palettes.append(_palette_for(PackedStringArray(["screen_palette", "black 0", "panel_line a 1"]), ids[t]))
	# the teams' names: the matchup's palette (lines 1 and 2 the teams' colours)
	_name_palette = RomPalette.make(3, PackedStringArray(["screen_palette"] + MwScreenPalettes.NAMES),
			ids[0], session.setup.stadium)
	_name_palette.team_b = ids[1]


# --- drawing -------------------------------------------------------------------------------------

func _layer(n: String, pal: RomPalette) -> RomPlane:
	var layer := RomPlane.new()
	layer.name = n
	layer.tiles = plane.tiles
	layer.palette = pal
	add_child(layer)
	return layer


## The title on the pause menu's plate, centred ("": none).
func _set_title(text: String) -> void:
	_title.clear()
	title = text
	if text == "":
		return
	MwGlyphs.plate_title(_title, rom, FONT, text.to_ascii_buffer(), TITLE_Y, TEXT_ATTR)


## The picks' title: with line-ups on a player picks who plays too.
func pick_title() -> String:
	return TITLE_PICK_LINEUPS if MwSelection.lineups_on(session) else TITLE_PICK


## Each team's city and name over its half (the controller selection's
## look: the menu font).
func _draw_team_names() -> void:
	_names.clear()
	var ids := [session.setup.team_a, session.setup.team_b]
	for t in 2:
		var bytes := MwGfx.rom_string(rom, MwTeams.city(rom, ids[t]))
		bytes.append(0x20)
		bytes.append_array(MwGfx.rom_string(rom, MwTeams.name(rom, ids[t])))
		var w := MwGfx.text_width(rom, FONT, bytes)
		MwPlanePainter.text(_names, rom, FONT, bytes, HALF_X[t] + (HALF_W - w) / 2, TEAM_Y, TEXT_ATTR)


## Player [param p]'s layer (their frame and tag), tinted their colour.
func _player_layer(p: int) -> RomPlane:
	if not _layers.has(p):
		var layer := _layer("Player%d" % p, palette)
		layer.modulate = MwPlayerColours.colour(rom, p)
		move_child(layer, _list.get_index())     # under the cards
		_layers[p] = layer
	return _layers[p]


## Player [param p]'s tag layer (their P<n> over the cards' portraits),
## tinted their colour: over the cards.
func _player_tag_layer(p: int) -> RomPlane:
	if not _tag_layers.has(p):
		var layer := _layer("Tag%d" % p, palette)
		layer.modulate = MwPlayerColours.colour(rom, p)
		_tag_layers[p] = layer
	return _tag_layers[p]


## Every player's frame and tag cleared.
func _clear_player_layers() -> void:
	for p in _layers:
		(_layers[p] as RomPlane).clear()
	for p in _tag_layers:
		(_tag_layers[p] as RomPlane).clear()


## The cards' cells: team [param t]'s position [param pos].
func card_cell(t: int, pos: int) -> Vector2i:
	return Vector2i(CARD_X[t][pos % 3], CARD_Y[pos / 3])


# --- character selection (111) ------------------------------------------------------------------

func _start_picks() -> void:
	stage = Stage.PICK
	_set_title(pick_title())
	for t in 2:
		for pos in MwLineup.POSITIONS:
			var card := MwCharacterCard.new()
			card.name = "Card%d_%d" % [t, pos]
			var at := card_cell(t, pos)
			card.position = Vector2(8 * at.x, 8 * at.y)
			add_child(card)
			card.setup(rom, plane.tiles, palette, _portrait_palettes[t], MwCharacterCard.Style.BIG, pos)
			card.show_slot(lineups[t], lineups[t].slots[pos])
			card.set_captain(humans.captain_of(t) != 0 and humans.positions.get(humans.captain_of(t), -1) == pos)
			card.set_dim(humans.count(t) == 0)          # the CPU's team: shown, not picked
			cards[t].append(card)
	# the cursors: each player on their last position (unlocked), the others spread out
	for t in 2:
		var used := []
		for p: int in humans.teams[t]:
			var last := int(humans.positions.get(p, -1))
			if last >= 0 and not last in used:
				cursor[p] = last
				used.append(last)
		for p: int in humans.teams[t]:
			if not cursor.has(p):
				for pos in MwLineup.POSITIONS:
					if not pos in used:
						cursor[p] = pos
						used.append(pos)
						break
			picks[p] = Pick.MOVING
	_draw_picks()


## The players' frames and tags, the list of names.
func _draw_picks() -> void:
	_clear_player_layers()
	var on_card := {}                   # Vector2i(team, pos) -> players there, first come first
	for t in 2:
		for p: int in humans.teams[t]:
			var k := Vector2i(t, int(cursor.get(p, 0)))
			if _card_of.get(p) != k:
				_card_of[p] = k
				_arrived += 1
				_arrival[p] = _arrived
			if not on_card.has(k):
				on_card[k] = []
			on_card[k].append(p)
	for k: Vector2i in on_card:
		(on_card[k] as Array).sort_custom(func(a: int, b: int) -> bool: return _arrival[a] < _arrival[b])
	for k: Vector2i in on_card:
		var at := card_cell(k.x, k.y)
		var who: Array = on_card[k]
		for i in who.size():
			var p: int = who[i]
			var layer := _player_layer(p)
			# the frame in their colour once they have the character (owner,
			# 2026-10-12: only after that player has selected it): taken,
			# then filled locked; on the vote, filled once their ballot is
			# cast; moving, their P<n> alone shows where they are
			var pick: int = picks.get(p, Pick.MOVING)
			drawn[p] = [k, pick]
			var filled := pick == Pick.LOCKED
			var framed := pick != Pick.MOVING
			if stage == Stage.VOTE or stage == Stage.RESULT:
				filled = votes[k.x] != null and (votes[k.x] as MwCaptainVote).ballots.has(p)
				framed = filled
			if framed:
				MwPlanePainter.frame(layer, rom, at.x, at.y, MwCharacterCard.W, MwCharacterCard.ROWS, filled)
			_tag(layer, p, at, i)
	_draw_list()


## Player [param p]'s P<n>, the [param i]-th on the card at [param at]
## (first come first: the order they came to it), stacked over its portrait
## ([method MwCharacterCard.tag_cell]: from the bottom up, left, right, left,
## right; owner, 2026-10-12 - they had sat on the frame's corners, over the
## next card's).
func _tag(_plane: RomPlane, p: int, at: Vector2i, i: int) -> void:
	var t := ("P%d" % p).to_ascii_buffer()
	var c := MwCharacterCard.tag_cell(MwCharacterCard.Style.BIG, i, MwGfx.text_width(rom, FONT, t))
	MwPlanePainter.text(_player_tag_layer(p), rom, FONT, t, at.x + c.x, at.y + c.y, TEXT_ATTR)


## Under the cards, each position's character: number, name (cut short
## when a long one would meet the rating) and rating for the position.
func _draw_list() -> void:
	_list.clear()
	for t in 2:
		var lineup: MwLineup = lineups[t]
		if lineup == null or cards[t].is_empty():
			continue
		for pos in MwLineup.POSITIONS:
			var slot := lineup.slots[pos]
			var y := LIST_Y + pos
			var r := str(lineup.rating(slot, pos)).to_ascii_buffer()
			var rx: int = LIST_X[t][1] - MwGfx.text_width(rom, FONT, r)
			var n := ("%d " % lineup.number(slot)).to_ascii_buffer()
			var x: int = MwPlanePainter.text(_list, rom, FONT, n, LIST_X[t][0], y, TEXT_ATTR)
			var nm := _name_of(lineup, slot).to_ascii_buffer()
			while nm.size() > 1 and x + MwGfx.text_width(rom, FONT, nm) > rx - 1:
				nm = nm.slice(0, nm.size() - 1)
			MwPlanePainter.text(_list, rom, FONT, nm, x, y, TEXT_ATTR)
			MwPlanePainter.text(_list, rom, FONT, r, rx, y, TEXT_ATTR)


func _name_of(lineup: MwLineup, slot: int) -> String:
	var r := lineup.record(slot)
	return MwGfx.rom_string(rom, MwGfx.u32(rom, r)).get_string_from_ascii() if r != 0 else ""


## The positions locked on team [param t].
func locked(t: int) -> Array:
	var out := []
	for pos in taken[t]:
		if picks.get(taken[t][pos], Pick.MOVING) == Pick.LOCKED:
			out.append(pos)
	return out


func _pick_input(input: MwInputFrame) -> void:
	var sound := 0
	var changed := false
	for t in 2:
		for p: int in humans.teams[t]:
			if input.away.has(p) and picks.get(p, Pick.LOCKED) != Pick.LOCKED:
				_auto_pick(t, p)                 # plan 35: their machine is away online
				changed = true
	for t in 2:
		for p: int in humans.teams[t]:
			var press_sound := _pick_press(t, p, input)
			if press_sound == -1:
				return                       # left the screen
			if press_sound != 0:
				sound = press_sound if sound != SOUND_REFUSED else sound
				changed = true
	if sound != 0:
		MwSound.play(sound)
	if not changed:
		return
	for t in 2:
		for card: MwCharacterCard in cards[t]:
			card.show_slot(lineups[t], lineups[t].slots[card.pos])
	if stage == Stage.READY and not _all_locked():
		stage = Stage.PICK
		_set_title(pick_title())
	elif stage == Stage.PICK and _all_locked():
		stage = Stage.READY
		_timer = READY_TICKS
		_set_title(TITLE_READY)
	_draw_picks()


## Player [param p]'s presses (team [param t]); returns the sound (0 none,
## -1 the screen was left).
func _pick_press(t: int, p: int, input: MwInputFrame) -> int:
	var pos := int(cursor[p])
	var lu: MwLineup = lineups[t]
	var line_ups := MwSelection.lineups_on(session)
	match picks[p]:
		Pick.MOVING:
			var d := Vector2i.ZERO
			if input.menu_pressed(p, "ui_left"):
				d.x = -1
			elif input.menu_pressed(p, "ui_right"):
				d.x = 1
			elif input.menu_pressed(p, "ui_up") or input.menu_pressed(p, "ui_down"):
				d.y = 1
			if d != Vector2i.ZERO:
				cursor[p] = 3 * posmod(pos / 3 + d.y, 2) + posmod(pos % 3 + d.x, 3)
				return SOUND_MOVE
			if input.menu_pressed(p, "ui_accept"):
				if taken[t].has(pos):
					return SOUND_REFUSED             # another player's position
				taken[t][pos] = p
				picks[p] = Pick.PICKED if line_ups else Pick.LOCKED
				if picks[p] == Pick.LOCKED:
					_queue_face(cards[t][pos])
				return SOUND_MOVE
			if input.menu_pressed(p, "ui_back") and p == 1:
				_leave_back()
				return -1
		Pick.PICKED:
			if input.menu_pressed(p, "ui_left") or input.menu_pressed(p, "ui_right"):
				return lu.step(pos, -1 if input.menu_pressed(p, "ui_left") else 1, locked(t))
			if input.menu_pressed(p, "ui_accept"):
				picks[p] = Pick.LOCKED
				_queue_face(cards[t][pos])
				return SOUND_MOVE
			if input.menu_pressed(p, "ui_back"):
				taken[t].erase(pos)
				picks[p] = Pick.MOVING
				return SOUND_MOVE
		Pick.LOCKED:
			if input.menu_pressed(p, "ui_back"):
				_rest_face(cards[t][pos])
				if line_ups:
					picks[p] = Pick.PICKED
				else:
					taken[t].erase(pos)
					picks[p] = Pick.MOVING
				return SOUND_MOVE
	return 0


## Plan 35: player [param p] (team [param t]), whose machine is away,
## locked on their position or the first free one.
func _auto_pick(t: int, p: int) -> void:
	if picks[p] == Pick.MOVING:
		for pos in MwLineup.POSITIONS:
			if not taken[t].has(pos):
				taken[t][pos] = p
				cursor[p] = pos
				break
	if (taken[t] as Dictionary).values().has(p):
		picks[p] = Pick.LOCKED


## A lock's portrait pulls its face - one at a time (the voices one after
## another).
func _queue_face(card: MwCharacterCard) -> void:
	if not card in _faces and card != _face:
		_faces.append(card)


func _rest_face(card: MwCharacterCard) -> void:
	_faces.erase(card)
	if card == _face:
		_face = null
	if not _predicting:
		card.rest()


func _faces_pass(elapsed: int) -> void:
	_face_ticks += elapsed
	if _face != null and _face.pulling() and _face_ticks < FACE_TICKS:
		return
	_face = _faces.pop_front() if not _faces.is_empty() else null
	_face_ticks = 0
	if _face != null:
		_face.pull_face()


func _all_locked() -> bool:
	for p in picks:
		if picks[p] != Pick.LOCKED:
			return false
	return not picks.is_empty()


## The picks are made: each player's own position, the line-ups (line-ups
## on) - then the vote, the panels, or the fade-out.
func _picks_done() -> void:
	humans.positions.clear()
	for t in 2:
		for pos in taken[t]:
			humans.positions[int(taken[t][pos])] = int(pos)
		_keep_lineup(t)
	_next_step()


## Team [param t]'s line-up into the session's players (line-ups on; empty
## when it is the original's).
func _keep_lineup(t: int) -> void:
	var lineup: MwLineup = lineups[t]
	if lineup == null or humans.count(t) == 0 or not MwSelection.lineups_on(session):
		humans.lineups[t] = PackedInt32Array()
		return
	humans.lineups[t] = lineup.slots.duplicate() if lineup.changed() else PackedInt32Array()


func _next_step() -> void:
	while not steps.is_empty():
		var text: String = steps.pop_front()
		if text == "vote" and not MwSelection.voting_teams(session).is_empty():
			_start_vote()
			return
		if text == "lineups" and not MwSelection.panel_teams(session).is_empty():
			_start_panels()
			return
	_finish()


# --- the captain vote ----------------------------------------------------------------------------

func _start_vote() -> void:
	stage = Stage.VOTE
	_set_title(TITLE_VOTE)
	cursor.clear()
	for t in 2:
		if humans.count(t) == 1:
			humans.captains[t] = humans.teams[t][0]   # a team of one: its player
	for t in MwSelection.voting_teams(session):
		var v := MwCaptainVote.new(t, humans.teams[t], humans.teams[t])
		votes[t] = v
		for p: int in humans.teams[t]:
			cursor[p] = v.candidates.find(p)          # their own line / character first
	_draw_vote()


## The candidate player [param p]'s cursor is on.
func _ballot_of(t: int, p: int) -> int:
	var v: MwCaptainVote = votes[t]
	return v.candidates[posmod(int(cursor[p]), v.candidates.size())]


func _vote_input(input: MwInputFrame) -> void:
	var sound := 0
	var dropped := false
	for t in 2:
		var vote: MwCaptainVote = votes[t]
		if vote == null or vote.winner != 0:
			continue
		for p: int in vote.voters.duplicate():
			if input.away.has(p) and not vote.ballots.has(p):
				vote.voters.erase(p)                    # plan 35: their machine is away: not waited for
				dropped = true
	for t in 2:
		var v: MwCaptainVote = votes[t]
		if v == null or v.winner != 0:
			continue
		for p: int in humans.teams[t]:
			var press_sound := _vote_press(t, p, input)
			if press_sound == -1:
				return                           # left the screen
			sound = press_sound if press_sound != 0 else sound
	if sound == 0 and not dropped:
		return
	if sound != 0:
		MwSound.play(sound)
	var counted := false
	for t in 2:
		var v: MwCaptainVote = votes[t]
		for k in 2:             # (plan 35: counted again when the tied's voters are all away)
			if v == null or v.winner != 0 or not v.all_voted():
				break
			counted = true
			if v.count(MwCaptainVote.stream(session)) != 0:
				humans.captains[t] = v.winner
			else:
				for p: int in humans.teams[t]:
					cursor[p] = 0                    # the tied vote again
				_set_title(TITLE_REVOTE)
	if counted and _votes_over():
		stage = Stage.RESULT
		_timer = RESULT_TICKS
		_set_title(TITLE_CAPTAINS if votes[0] != null and votes[1] != null else TITLE_CAPTAIN)
	_draw_vote()


## Player [param p]'s presses on the vote (team [param t]'s, open);
## returns the sound (0 none, -1 the screen was left).
func _vote_press(t: int, p: int, input: MwInputFrame) -> int:
	var v: MwCaptainVote = votes[t]
	if v.ballots.has(p):
		if input.menu_pressed(p, "ui_back"):
			v.unvote(p)
			return SOUND_MOVE
		return 0
	var d := 0
	if input.menu_pressed(p, "ui_left") or input.menu_pressed(p, "ui_up"):
		d = -1
	elif input.menu_pressed(p, "ui_right") or input.menu_pressed(p, "ui_down"):
		d = 1
	if d != 0:
		cursor[p] = posmod(int(cursor[p]) + d, v.candidates.size())
		return SOUND_MOVE
	if input.menu_pressed(p, "ui_accept"):
		v.vote(p, _ballot_of(t, p))
		return SOUND_MOVE
	if input.menu_pressed(p, "ui_back") and p == 1 and _on_vote_screen:
		_leave_back()
		return -1
	return 0


func _votes_over() -> bool:
	for v in votes:
		if v != null and (v as MwCaptainVote).winner == 0:
			return false
	return true


func _draw_vote() -> void:
	if _on_vote_screen:
		_draw_vote_lines()
		return
	_clear_player_layers()
	for t in 2:
		var v: MwCaptainVote = votes[t]
		for card: MwCharacterCard in cards[t]:
			var p := humans.owner_of(t, card.pos)
			card.set_dim(p == 0 or (v != null and not p in v.candidates and v.winner == 0))
			card.set_captain(p != 0 and humans.captain_of(t) == p)
		if v == null:
			continue
		var on_card := {}
		for p: int in humans.teams[t]:
			var pos := int(humans.positions.get(_ballot_of(t, p), 0))
			if not on_card.has(pos):
				on_card[pos] = []
			on_card[pos].append(p)
		for pos: int in on_card:
			var at := card_cell(t, pos)
			var who: Array = on_card[pos]
			for i in who.size():
				var p: int = who[i]
				var layer := _player_layer(p)
				if v.winner == 0 and v.ballots.has(p):
					# cast (owner: once selected)
					MwPlanePainter.frame(layer, rom, at.x, at.y, MwCharacterCard.W, MwCharacterCard.ROWS, true)
				_tag(layer, p, at, i)
	_draw_list()


## 112: each voting team's players, a line each (P<n>, device tag; the
## captain's C), the ballots' tags under the line they point at - on a bar
## of their colour once cast.
func _draw_vote_lines() -> void:
	_list.clear()
	_clear_player_layers()
	for t in 2:
		var line := 0
		for p: int in humans.teams[t]:
			var y := LINE_Y + LINE_STEP * line
			var layer := _player_layer(p)
			var text := "P%d %s" % [p, MwInputMap.device_tag(p)]
			MwPlanePainter.text(layer, rom, FONT, text.to_ascii_buffer(), LINE_X[t], y, TEXT_ATTR)
			if humans.captain_of(t) == p:
				MwPlanePainter.text(_list, rom, FONT, "C".to_ascii_buffer(), LINE_X[t] - 2, y, TEXT_ATTR)
			line += 1
		var v: MwCaptainVote = votes[t]
		if v == null or v.winner != 0:
			continue
		var n := {}
		for p: int in humans.teams[t]:
			var c := _ballot_of(t, p)
			var row: int = (humans.teams[t] as Array).find(c)
			var k := int(n.get(c, 0))
			n[c] = k + 1
			var x: int = LINE_X[t] + 1 + BALLOT_STEP * (k % BALLOTS_A_ROW)
			var y: int = LINE_Y + LINE_STEP * row + 1 + k / BALLOTS_A_ROW
			var layer := _player_layer(p)
			var tag := ("P%d" % p).to_ascii_buffer()
			if v.ballots.has(p):
				MwPlanePainter.fill(layer, x, y, MwGfx.text_width(rom, FONT, tag), 1, MwPlanePainter.FILL_WORD)
				MwPlanePainter.text(layer, rom, FONT_DARK, tag, x, y, TEXT_ATTR)
			else:
				MwPlanePainter.text(layer, rom, FONT, tag, x, y, TEXT_ATTR)


# --- the line-up panels -------------------------------------------------------------------------

func _start_panels() -> void:
	stage = Stage.PANELS
	_set_title("")                               # the panels cover it (owner)
	var teams := MwSelection.panel_teams(session)
	var both := teams.size() == 2
	for i in teams.size():
		var t := teams[i]
		var pn := MwLineupPanel.new()
		pn.name = "Panel%d" % t
		add_child(pn)
		var owners := {}
		for p: int in humans.teams[t]:
			if humans.positions.has(p):
				owners[int(humans.positions[p])] = p
		pn.setup(rom, plane.tiles, palette, _portrait_palettes[t], _logo_palettes[t], _name_palette, t, lineups[t],
				drivers(t), owners)
		pn.crash_in(MwLineupPanel.HEIGHT * i, both and i == 1)
		panels.append(pn)
	_pick_glyphs()


## The panels' DONE glyphs again when the devices or the glyphs changed (a
## player picked up another device, a gamepad came or went).
func _pick_glyphs() -> void:
	var now := [MwGlyphs.generation, MwInputMap.devices_changed]
	if now == _glyphs_for:
		return
	_glyphs_for = now
	for pn in panels:
		pn.set_glyphs(confirm_glyphs(pn.drivers))


## The glyphs of [param players]' confirm (Menu accept), distinct, in their
## order: each one's own input on the device they play on
## ([method MwGlyphs.player_glyph]). Online (plan 35) a player on this
## machine is its local player (the lobby's: their bindings and device);
## one on another machine shows their layout's default for the kind of
## device the lobby has for them ([method MwGlyphs.layout_glyph]) - their
## bindings are their machine's. Presentation only: nothing of it is in the
## stream or the hashes.
func confirm_glyphs(players: Array[int]) -> PackedStringArray:
	var out := PackedStringArray()
	var lobby: MwNetLobby = session.net.lobby() if MwFlow.online(session) and session.net != null else null
	for p in players:
		var g := MwGlyphs.player_glyph(p, "ui_accept")
		if lobby != null and lobby.players.has(p):
			var lobby_player: Dictionary = lobby.players[p]
			if int(lobby_player["machine"]) == session.machine:
				g = MwGlyphs.player_glyph(int(lobby_player["local"]), "ui_accept")
			else:
				g = MwGlyphs.layout_glyph("ui_accept", session.layout_of(p),
						MwNetService.device_family(int(lobby_player.get("device", MwNetService.Device.PAD))))
		if g != "" and not g in out:
			out.append(g)
	return out


## The players who drive team [param t]'s panel: its captain, its one
## player, or all of them.
func drivers(t: int) -> Array[int]:
	var out: Array[int] = []
	var c := humans.captain_of(t)
	if c != 0 and c in humans.teams[t]:
		out.append(c)
	else:
		out.assign(humans.teams[t])
	return out


func _panels_pass(elapsed: int, input: MwInputFrame) -> void:
	var crash := 0
	var falling := false
	for pn in panels:
		if not pn.landed():
			falling = true
	if falling and input != null and not input.pressed.is_empty():
		for pn in panels:
			pn.settle()                          # a press: in place at once - and nothing else
	_pick_glyphs()
	for pn in panels:
		if not (fader != null and fader.busy()):
			crash = maxi(crash, pn.advance(elapsed))   # (two panels bounce together: one crash)
	MwSlam.crash(crash)                          # each panel shakes itself (MwLineupPanel._place)
	if falling:
		return
	if panels.size() == 2:
		_hide_behind()
	var sound := 0
	for pn in panels:
		var press_sound := pn.handle(input)
		if press_sound == MwLineupPanel.LEAVE:
			_leave_back()                        # Back on a panel that isn't READY
			return
		sound = press_sound if press_sound != 0 else sound
		if input != null and not input.away.is_empty() and not pn.is_ready \
				and pn.drivers.all(func(d: int) -> bool: return input.away.has(d)):
			pn.confirm()                             # plan 35: its drivers' machines are away
	if sound != 0:
		MwSound.play(sound)
	if stage == Stage.PANELS and _panels_ready():
		stage = Stage.OUT
		_timer = DONE_TICKS
		for pn in panels:
			humans.lineups[pn.team] = pn.lineup.slots.duplicate() if pn.lineup.changed() else PackedInt32Array()
	elif stage == Stage.OUT and not _panels_ready():
		stage = Stage.PANELS                     # a READY taken back in time


## Two panels landed cover the whole screen: what 111 / 112 showed behind
## them goes (its cards, lines and names would show through the gaps at the
## panels' rounded edges), leaving the starfield as on 113.
func _hide_behind() -> void:
	for t in 2:
		for card: MwCharacterCard in cards[t]:
			card.visible = false
	for layer: RomPlane in [_title, _names, _list]:
		layer.visible = false
	for p in _layers:
		(_layers[p] as RomPlane).visible = false
	for p in _tag_layers:
		(_tag_layers[p] as RomPlane).visible = false


func _panels_ready() -> bool:
	for pn in panels:
		if not pn.is_ready:
			return false
	return not panels.is_empty()


# --- the pass ---------------------------------------------------------------------------------------

# --- plan 41: client-side menus -------------------------------------------------------------------

## Online, a client: this machine's players' presses its game hasn't run
## yet ([param presses]: player -> verbs) shown at once - the picks, the
## vote and the panels by their own per-player handlers ([method
## _pick_press], [method _vote_press], [method MwLineupPanel.predict]) on
## the selection, drawn, and the selection put back ([method _keep_selection]);
## nothing a player decides for everyone (player 1's Back, the stage's
## changes, the faces' voices) happens here. {} draws the selection as it is
## once more after a prediction.
func predict_local(presses: Dictionary) -> void:
	if rom.is_empty() or _pull >= 0 or _exiting():
		return
	if stage in [Stage.PANELS, Stage.OUT]:
		for pn in panels:
			pn.predict(MwLocalEcho.of(presses, pn.drivers))
		return
	if not stage in [Stage.PICK, Stage.READY, Stage.VOTE]:
		return
	if presses.is_empty():
		if _echoed:
			_echoed = false
			_draw_stage()
		return
	var kept := _keep_selection()
	_predicting = true
	MwLocalEcho.run(func() -> void:
		for p: int in presses:
			var t := humans.team_of(p)
			if t == MwHumans.MIDDLE:
				continue
			for verb: String in presses[p]:
				if p == 1 and verb == "ui_back":
					continue                     # player 1's Back leaves: the game's to do
				var f := MwLocalEcho.frame(p, verb)
				if stage == Stage.VOTE:
					if votes[t] != null and (votes[t] as MwCaptainVote).winner == 0:
						_vote_press(t, p, f)
				elif picks.has(p):
					_pick_press(t, p, f)
		_draw_stage())
	_predicting = false
	_put_back(kept)
	_echoed = true


## What the stage shows, drawn from the selection as it is.
func _draw_stage() -> void:
	if stage == Stage.VOTE:
		_draw_vote()
		return
	for t in 2:
		for card: MwCharacterCard in cards[t]:
			card.show_slot(lineups[t], lineups[t].slots[card.pos])
	_draw_picks()


## What the picks and the vote change (cursors, picks, positions taken,
## the line-ups' slots, the faces waiting, the ballots, the tags' order of
## arrival), copied.
func _keep_selection() -> Dictionary:
	var slots := []
	for lu in lineups:
		slots.append((lu as MwLineup).slots.duplicate() if lu != null else null)
	var ballots := []
	for v in votes:
		ballots.append((v as MwCaptainVote).ballots.duplicate() if v != null else null)
	return {"cursor": cursor.duplicate(), "picks": picks.duplicate(),
			"taken": [(taken[0] as Dictionary).duplicate(), (taken[1] as Dictionary).duplicate()],
			"slots": slots, "faces": _faces.duplicate(), "face": _face, "ballots": ballots,
			"card_of": _card_of.duplicate(), "arrival": _arrival.duplicate(), "arrived": _arrived}


func _put_back(k: Dictionary) -> void:
	cursor = k["cursor"]
	picks = k["picks"]
	taken = k["taken"]
	for t in lineups.size():
		if lineups[t] != null:
			(lineups[t] as MwLineup).slots = k["slots"][t]
	_faces = k["faces"]
	_face = k["face"]
	_card_of = k["card_of"]                  # (the tags' order on a card is the game's)
	_arrival = k["arrival"]
	_arrived = k["arrived"]
	for t in votes.size():
		if votes[t] != null:
			(votes[t] as MwCaptainVote).ballots = k["ballots"][t]


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty():
		return
	for i in elapsed:
		starfield.step()                         # VBlank task
	for t in 2:
		for card: MwCharacterCard in cards[t]:
			card.advance(elapsed)
	_faces_pass(elapsed)
	_cover_pass(elapsed)
	if _pull >= 0:
		_pull_pass(elapsed, input)
		return
	if _exiting():
		return
	match stage:
		Stage.PICK:
			if input != null:
				_pick_input(input)
		Stage.READY:
			if input != null:
				_pick_input(input)
			if stage == Stage.READY:
				_timer -= elapsed
				if _timer <= 0:
					_picks_done()
		Stage.VOTE:
			if input != null:
				_vote_input(input)
		Stage.RESULT:
			_timer -= elapsed
			if _timer <= 0:
				_next_step()
		Stage.PANELS:
			_panels_pass(elapsed, input)
		Stage.OUT:
			_panels_pass(elapsed, input)
			if stage == Stage.OUT:
				_timer -= elapsed
				if _timer <= 0:
					_finish()


func _exiting() -> bool:
	return leaving() or (fader != null and fader.busy() and stage == Stage.OUT and _timer <= 0)


## Back to the controller selection: player 1's Back with nothing taken (or
## on the vote's own screen), a driver's Back on a line-up panel that isn't
## READY. The session's players go back as the screen found them - their
## positions, captains and line-ups ([member MwHumans.lineups]: as before
## the screen opened, owner) - and the controller selection's accept runs
## the selection steps again from the first that applies.
func _leave_back() -> void:
	if not _found.is_empty():
		humans.positions = (_found["positions"] as Dictionary).duplicate()
		humans.captains = (_found["captains"] as Array).duplicate()
		humans.lineups = (_found["lineups"] as Array).duplicate(true)
	if under != null and is_instance_valid(under) and stage == Stage.PANELS:
		_pull_back()
		return
	exit_to(MwScreens.CONTROLLER_SELECT)


## The pull back off the controller selection (owner, 2026-10-12: it fades
## back in when the player backs out to it, with the brick menu's sound
## effect and pull back animation borrowed): the panels go back the way they
## came - team A's up off the top, team B's down off the bottom - from rest,
## faster and faster over [constant MwBrickWall.RISE_TICKS] as 110's wall
## rises, to its gate's clinks
## ([constant MwBrickWall.SOUND]), the CONTROLLER SELECT plate fading back
## in; then this screen pops, the stars handed back. A press ends it at
## once, the clinks too (as the game setup's lift).
func _pull_back() -> void:
	_pull = 0
	for pn in panels:
		pn.settle()
	MwSound.fm_effect(MwBrickWall.SOUND)


func _pull_pass(elapsed: int, input: MwInputFrame) -> void:
	_pull += elapsed
	if input != null and not input.pressed.is_empty() and _pull < MwBrickWall.RISE_TICKS:
		_pull = MwBrickWall.RISE_TICKS
		MwSound.fm_effect_stop()
	var f := clampf(float(_pull) / MwBrickWall.RISE_TICKS, 0.0, 1.0)
	f = f * f                                    # from rest, faster and faster (MwBrickWall.rise_height)
	for pn in panels:
		pn.pull_back(f)
	if _pull < MwBrickWall.RISE_TICKS or leaving():
		return
	for c in under.covered_fades():
		c.modulate.a = 1.0                       # the plate whole (a press, before its fade's end)
	_show_under_sky(true)
	session.menu_stars = starfield.state()
	pop({"menu_stars": true}, false)


## The steps are over: the setup takes the line-ups, the fade-out to the match.
func _finish() -> void:
	if leaving():
		return
	stage = Stage.OUT
	exit_to(MwSelection.finish(session))
