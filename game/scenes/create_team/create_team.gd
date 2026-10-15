class_name MwCreateTeam
extends MwScreen
## CREATE-A-TEAM (plan 38; owner, 2026-10-09 / 10), two screens of one scene:
##
## * 130, the team list (the port menus' look): NEW TEAM, COPY A TEAM (an
##   original team as the start), the saved teams - accept edits one, the
##   copy verb copies it, the delete verb deletes it (ARE YOU SURE?).
## * 132, the team editor (the team description's look: its header plate
##   with the team's logo, city and name in big letters): TEAM INFO, LOGO
##   AND COLOURS, COACH, NASTY PLAYS, ROSTER, HOME RINK (screen 138, the 3D
##   rink editor), BIO, SAVE TEAM - and their pages: a roster with its
##   players picked from the original's teams or made new, each player's
##   identity and ratings, any colour by its Genesis levels, the coach's
##   speeches (SPEECHES: what he says in the rink, by occasion and
##   situation, each line his own or his original coach's; owner,
##   2026-10-14: lines edited and written new, not only picked).
##
## The team being edited is a working copy ([member MwCustomTeams.editing]):
## the game's readers see it under [method MwCustomTeams.editing_id], so the
## pages draw it as the game will (its records, palettes, portraits); SAVE
## TEAM writes it to its file. Names and texts are typed on the text entry
## (131, pushed; [method team_text] makes the field). Every value is kept
## valid ([method MwCustomTeam.validate]). Prompts are the verbs' glyphs
## (plan 23; [MwVerbs] context CREATE).
##
## The editor's music (owner, 2026-10-10): the team description's, started
## as it starts it - the menus' music stops (`$C768`) and its crowd sequence
## `$10` plays, again whenever it ends (`$C7C2`) - from entering the editor
## through all its screens (130, 131, 132, 138: MwEditorMusic.enter,
## keep_up) until it leaves for the front menu, whose own music then comes
## back (MwPortMenu: the title's) (MwEditorMusic.leave).

const PLATE := 0x48738               ## the team description's header plate (8 rows)
const PLAYS := 0x1F07C               ## play names by play number (special plays screen)
const POSITIONS := 0x1CF0C           ## "CENTER" ... "GOALIE"
const LINE_HEADINGS := 0x1CE84       ## "STARTERS" ... by line
const SKATER_LABELS := [0x1CF24, 0x1CF3C]
const GOALIE_LABELS := [0x1CF54, 0x1CF68]
const SKULL_ANIM := "3EA6E"           ## the game setup's skull icons
const SKULL_ATTR := 0x13152 + 6        ## their attr (the team panel's icon record +6)
const SOUND_MOVE := MwSoundIds.MOVE
const SOUND_REFUSED := MwSoundIds.REFUSED
const SOUND_SAVED := MwSoundIds.KEY
## The coach page's box: its first text row and lines; the speeches it
## samples ([category, situation] of the rink's quote table).
const COACH_BOX_Y := 22
const COACH_BOX_LINES := 4
const SPEECH_SAMPLES := [[7, 0], [0, 1], [4, 4], [6, 0]]
## The coach's pages (his portrait beside the rows): his own and SPEECHES'
## three - the occasions, an occasion's situations, a situation's lines.
const COACH_PAGES := ["coach", "speeches", "situations", "lines"]
## The lines page's box: the line selected as the rink shows it (the
## speech box's 34 x 6 cells, `$1EA02`), its first text row.
const LINES_BOX_Y := 20
const SPEECH_COLUMNS := 34
const SPEECH_ROWS := 6
## The roster's mark before a player of the team's own.
const OWN_MARK := 0x2B
## The player's name in the header plate: the room it has (pixels from its
## left at x 72 to the plate's frame) - a longer one slides to its end and
## back, pausing [constant NAME_PAUSE] ticks at each end (owner).
const NAME_ROOM := 232
const NAME_PAUSE := 60
## Rows whose value is a number: Left / Right held repeat (owner).
const NUMBER_ROWS := ["skulls", "p_number", "p_weight", "rating", "p_aggression", "p_instinct", "p_bonus",
		"p_overall", "channel"]
## The team name's gentle note (owner: a note, never a stop).
const NAME_NOTE := "TEAM NAMES SHOULD END IN S, Z OR 5"
const LIGHT := MwEditorDraw.LIGHT
const DARK := MwEditorDraw.DARK
const MENU := MwEditorDraw.MENU
const WHITE := MwEditorDraw.WHITE
const YELLOW := MwEditorDraw.YELLOW
## The list's rows (plan 34's port pages: the logo where the game setup has
## it, the title under it, the rows from 15); the saved teams shown at once:
## three, or two with plan 34's scroll arrows under them once there are more
## (the prompts' row leaves room for the arrows under two; their top in
## pixels, 4 under the second team and 4 over the prompts).
const LIST_SHOWN := 3
const LIST_SHOWN_SCROLLED := 2
const LIST_FIRST := 20
const LIST_ARROW_TOP := 188
## Rows of the team look: the page heading, the first row, two apart.
const HEAD_Y := 9
const FIRST_Y := 12
const TOP_Y := 9                     ## pages without a heading (the editor's, the ratings)
## The team look's palette: the team description's (screen 2: the team's
## panel colours on line 0, its kit on line 1, the text line on 2).
const TEAM_STEPS := ["screen_palette", "black 0", "panel_line a 0", "team_line a 1 1", "rom 1bd6a 2", "word c20c 41"]
const MENU_STEPS := MwMenuBackdrop.STEPS
## Player faces' names (the stars' are their players' names, read at run time).
const SPECIES_FACES := ["SKELETON", "ROBOT", "TROLL", "GOALIE", "REFEREE"]
const SPECIES_NAMES := ["", "SKELETON", "ROBOT", "TROLL", "GOALIE"]
## The ten ratings as the team description lists them, column by column
## (its first five rows: [constant MwPlayerRecord.COLUMNS]).
const RATING_ORDER := MwPlayerRecord.COLUMNS

## The page's own layers, as one picture (the cuts' fades, [MwMenuCut]):
## everything but the backdrop, the stars and the menus' logo.
@onready var page_layers: CanvasGroup = $Page
@onready var plane: RomPlane = $Page/Plane
@onready var half_plane: RomPlane = $Page/HalfPlane
@onready var starfield: RomStarfield = $Starfield
@onready var palette: RomPalette = $Page/Plane.palette
@onready var swatch_layer: Node2D = $Page/Swatches
@onready var sprites: Node2D = $Page/Sprites
@onready var logo: RomSprite = $Page/Sprites/Logo
@onready var city_text: RomPieces = $Page/Sprites/City
@onready var name_text: RomPieces = $Page/Sprites/Name
@onready var skater: RomSprite = $Page/Sprites/Skater
@onready var portrait: MwPortrait = $Page/Sprites/Portrait
## The menus' logo (the list's), on a layer of its own under the page: it
## stays put in the cuts from and to the front menu, and fades out into the
## editor (plan 40, M5).
var logo_plane: RomPlane
## The cuts between the starfield screens (plan 40, M5, owner: the stars keep
## moving): the front menu, the list, the editor, the text entry.
var cut: MwMenuCut

var rom: PackedByteArray
## The page shown: list, edit, info, colours, coach, plays, roster, pick,
## player, ratings, colour.
var page := "list"
var rows: Array[Dictionary] = []
var row := 0
## Pages to go back to: [page, row].
var stack: Array = []
## The working copy and the id the game reads it under.
var team: MwCustomTeam
var id := -1
var dirty := false
## The list: the first saved team shown, the original team COPY A TEAM offers.
var list_top := 0
var copy_from := 0
## The list's saved teams, on and off ([method MwCustomTeams.all]): the
## "team" rows' indices.
var listed: Array[MwCustomTeam] = []
## The roster: line 0-3, position 0-5; a slot picked up to move (-1 none).
var line := 0
var cursor := 0
var moving := -1
## PICK A PLAYER: the original team shown, its line and position.
var pick_team := 0
var pick_line := 0
var pick_cursor := 0
## The swatch a colour row has its cursor on.
var swatch := 0
## SPEECHES: the occasion open ([constant MwCoachSpeeches.OCCASIONS]), its
## situation open (the rink's number) and the line being typed (past the
## last: a new one).
var speech_occasion := 0
var speech_situation := 0
var speech_line := 0
## The colour page: what it edits ({get: Callable, set: Callable}), its
## title, the word on entry (undo), the channel row.
var colour_target := {}
var colour_title := ""
var colour_undo := 0
## ARE YOU SURE? (plan 40, M4a, owner: the big ARE YOU SURE? is the
## standard): the question box every screen asks in, and what YES does.
var confirm: MwConfirmBox
var confirm_yes := Callable()
var _skulls: Array[RomSprite] = []
var _repeat := MwHoldRepeat.new()
var _name_palette: RomPalette
var _name_shown := PackedByteArray()
var _name_off := 0
var _name_dir := 1
var _name_wait := 0
## The list's scroll arrows: up, down.
var _arrows: Array[RomSprite] = []
var _icon_palette: RomPalette
var _portrait_on := false


## A text of a custom team to type on the text entry (131): the fonts'
## common characters ([constant MwCustomTeam.CHARSET]), letters in
## capitals, words one space apart, [param limit] at most; the team name
## with its gentle note. [param key] says which text it is.
static func team_text(key: String, title: String, text: String, limit: int) -> MwTextField:
	var field := MwTextField.new(MwTextField.Kind.TEXT)
	field.id = key
	field.title = title
	field.allowed = MwCustomTeam.CHARSET.replace(" ", "")
	field.spaces = true
	field.upper = true
	field.limit = limit
	if key in ["name", "new_name"]:
		field.advice = func(t: String) -> String:
			return NAME_NOTE if t != "" and not t.right(1).to_upper() in ["S", "Z", "5"] else ""
	field.set_text(MwCustomTeam.clean_text(text, limit))
	return field


func _exit_tree() -> void:
	if leaving_to >= 0:
		MwEditorMusic.leave(leaving_to)


func _enter_screen(data: Dictionary) -> void:
	resume_fresh = true                    # plan 40, S12: the text entry's time isn't caught up
	if not MwRom.available():
		return
	rom = MwRom.data()
	MwEditorMusic.enter()
	if session:
		starfield.start(session.rng_aux)
	portrait.rng = session.rng if session else MlhRng.new(1)
	portrait.set_palette(palette)
	_icon_palette = RomPalette.make(1, PackedStringArray(["screen_palette", "black 0"]), 0, 0)
	for i in 6:
		var sprite := RomSprite.new()
		sprite.palette = _icon_palette
		sprite.anim = SKULL_ANIM
		sprite.attr_xor = MwGfx.u16(rom, SKULL_ATTR)
		sprite.visible = false
		sprites.add_child(sprite)
		_skulls.append(sprite)
	_arrows = MwScrollArrows.make(sprites, palette)      # plan 40 (M3)
	confirm = MwConfirmBox.new()
	confirm.name = "Confirm"
	page_layers.add_child(confirm)
	confirm.setup(plane, rom)
	confirm.answered.connect(_answered)
	var st: Dictionary = session.screens.get(screen_id, {}) if session else {}
	if entry == "team":
		team = MwCustomTeams.editing
		if team == null:
			exit_to(MwScreens.CREATE_A_TEAM, {}, false)
			return
		id = MwCustomTeams.editing_id()
		dirty = bool(st.get("dirty", data.get("dirty", false)))
		page = str(st.get("page", "edit"))
		stack = st.get("stack", [])
		line = int(st.get("line", 0))
		cursor = int(st.get("cursor", 0))
		row = int(st.get("row", 0))
		speech_occasion = clampi(int(st.get("speech_occasion", 0)), 0, MwCoachSpeeches.OCCASIONS.size() - 1)
		speech_situation = int(st.get("speech_situation", 0))
		speech_line = int(st.get("speech_line", 0))
		if not MwCoachSpeeches.valid_key(MwCoachSpeeches.key(MwCoachSpeeches.category_of(speech_occasion),
				speech_situation)):
			speech_situation = int(MwCoachSpeeches.situations_of(speech_occasion)[0][0])
		if not page in ["edit", "info", "colours", "plays", "roster"] + COACH_PAGES:
			page = "edit"
			stack = []
	else:
		page = "list"
		copy_from = int(st.get("copy_from", 0))
		row = int(st.get("row", 0))
	_open(page, row)
	# the menus' logo under the page, in the menus' colours whatever the page's
	logo_plane = plane.duplicate() as RomPlane
	logo_plane.name = "LogoPlane"
	logo_plane.clear()                         # (the duplicate has the page's cells)
	logo_plane.palette = RomPalette.make(1, PackedStringArray(MENU_STEPS), palette_team_a(), palette_team_a())
	add_child(logo_plane)
	move_child(logo_plane, page_layers.get_index())
	MwMenuBackdrop.logo(logo_plane, rom, MwPortMenu.LOGO_AT.x, MwPortMenu.LOGO_AT.y)
	cut = MwMenuCut.new(page_layers, starfield, session, logo_plane)
	var by_cut := bool(data.get("menu_cut", false))
	if by_cut:
		cut.restore_stars()                   # the screen before's stars going on
	cut.enter(by_cut, data, _shows_logo())


## Remembers where the editor is (left for the rink editor or the text entry).
func _remember() -> void:
	if session == null:
		return
	if entry == "team":
		session.screens[screen_id] = {"page": page, "row": row, "stack": stack, "line": line,
				"cursor": cursor, "dirty": dirty, "speech_occasion": speech_occasion,
				"speech_situation": speech_situation, "speech_line": speech_line}
	else:
		session.screens[screen_id] = {"row": row, "copy_from": copy_from}


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty():
		return
	MwEditorMusic.keep_up()
	if not _pending_type.is_empty() and (cut == null or not cut.leaving()):
		# the next field straight on (a new team's city, then its name; then
		# the editor): the page, faded out for the text entry, isn't shown between
		var t := _pending_type
		_pending_type = []
		if t[0] == "edit":
			var fresh := _pending_new
			_pending_new = null
			_start_editing(fresh, null)
		else:
			_type(t[0], t[1], t[2], t[3])
		if cut == null or not cut.leaving():
			return
	if cut != null and cut.step(elapsed):
		return                                 # leaving by a cut: the page fading out, the stars on
	# back from the text entry the stars and the portrait's talking go on
	# from where they were instead of catching up (owner: the mouth raced after
	# backing in and out): resume_fresh
	var e := elapsed
	for i in e:
		starfield.step()
	if _portrait_on:
		portrait.advance(e)
	_scroll_name(e)
	if confirm != null and confirm.handle(input):
		return                                 # ARE YOU SURE? has the verbs
	var held := _repeat.step(input, e, _repeats())
	if held != 0:
		_change(held, true)
	if input == null:
		return
	if input.is_pressed("ui_back"):
		_back()
	elif input.is_pressed("ui_up"):
		_move(-1)
	elif input.is_pressed("ui_down"):
		_move(1)
	elif input.is_pressed("ui_left"):
		_change(-1)
	elif input.is_pressed("ui_right"):
		_change(1)
	elif input.is_pressed("ui_accept"):
		_accept()
	elif input.is_pressed("ui_editor_copy"):
		_verb("copy")
	elif input.is_pressed("ui_editor_delete"):
		_verb("delete")
	elif input.is_pressed("ui_editor_next"):
		_verb("next")
	elif input.is_pressed("ui_editor_previous"):
		_verb("previous")


## Back from the text entry (131): its text (its [param r]esult, plan 40)
## into the field it was asked for.
## (Plan 40, M5: back by a cut the stars go on from where the text entry
## left them and the page fades in.)
func _resume_screen(r := {}) -> void:
	if bool(r.get("done", false)):
		_typed(str(r.get("key", "")), str(r.get("text", "")))
	if cut != null:
		var by_cut := bool(r.get("menu_cut", false))
		if by_cut:
			cut.restore_stars()
		cut.enter(by_cut, r, _shows_logo())
	_draw()


## Plan 40 (M5): leaving for another starfield screen is a cut
## ([MwMenuCut]: the page fades out, the stars go on); anything else (the
## rink editor) as asked.
func exit_to(target_id: int, data := {}, fade := true, ticks := -1) -> void:
	if cut != null and cut.leaving():
		return                                 # already on its way
	if fade and cut != null and session != null and MwMenuCut.cuts_to(target_id):
		cut.leave(_cut_to.bind(target_id, data.duplicate()))
		return
	super.exit_to(target_id, data, fade, ticks)


## The cut itself, the page faded out ([param c]: the cut's data).
func _cut_to(c: Dictionary, target_id: int, data: Dictionary) -> void:
	data.merge(c, true)
	super.exit_to(target_id, data, false)


## Whether this screen shows the menus' logo (the list; the editor has the
## team's header there).
func _shows_logo() -> bool:
	return not _team_look()


## Team A of the menus' palette (the game setup's, as the port menus').
func palette_team_a() -> int:
	return session.setup.team_a if session else 0


func _sound(id_: int) -> void:
	MwSound.play(id_)


# --- pages ------------------------------------------------------------------------------------------
## Shows page [param text] with row [param r] selected.
func _open(text: String, r := 0) -> void:
	page = text
	_build_rows()
	row = clampi(r, 0, maxi(rows.size() - 1, 0))
	if not rows.is_empty() and rows[row].get("skip", false):
		_move(1, false)
	_start_portrait()
	_draw()


## Opens [param text] over the page shown (Back returns to it).
func _push(text: String, r := 0) -> void:
	stack.append([page, row])
	_open(text, r)


func _pop() -> void:
	var top: Array = stack.pop_back()
	_open(top[0], top[1])


func _row(action: String, label: String, y: int, extra := {}) -> void:
	var r := {"action": action, "label": label, "y": y, "x": 3, "w": 34}
	r.merge(extra, true)
	rows.append(r)


func _build_rows() -> void:
	rows.clear()
	var y := TOP_Y if page in ["edit", "ratings"] + COACH_PAGES else FIRST_Y
	match page:
		"list":
			_row("new", "NEW TEAM", 15, {"item": true})
			_row("copy_original", "COPY A TEAM", 17)
			listed = MwCustomTeams.all()
			for i in listed.size():
				_row("team", "", 0, {"team": i})
		"edit":
			for a in [["info", "TEAM INFO"], ["colours", "LOGO AND COLOURS"], ["coach", "COACH"],
					["plays", "NASTY PLAYS"], ["roster", "ROSTER"], ["rink", "HOME RINK"], ["bio", "BIO"]]:
				_row(a[0], a[1], y)
				y += 2
			_row("save", "SAVE TEAM", y, {"item": true})
		"info":
			for a in [["city", "CITY"], ["name", "NAME"], ["skulls", "SKULLS"], ["menu_after", "MENU ORDER"],
					["playoff_place", "PLAYOFF PLACE"]]:
				_row(a[0], a[1], y)
				y += 2
		"colours":
			for a in [["logo", "LOGO"], ["logo_colours", "LOGO COLOURS"], ["name_colours", "NAME COLOURS"],
					["shirt", "SHIRT"], ["pants", "PANTS"], ["skin", "SKIN"]]:
				_row(a[0], a[1], y, {"w": 23})
				y += 2
		"coach":
			for a in [["coach_name", "NAME"], ["coach_face", "FACE"], ["coach_colours", "COLOURS"],
					["coach_voice", "VOICE"], ["coach_speeches", "SPEECHES"], ["coach_quote", "QUOTE"]]:
				_row(a[0], a[1], y, {"x": 13, "w": 25})
				y += 2
		"speeches":
			for i in MwCoachSpeeches.OCCASIONS.size():
				_row("speech_occasion", str(MwCoachSpeeches.OCCASIONS[i][1]), y, {"x": 13, "w": 25, "index": i})
				y += 2
		"situations":
			for st: Array in MwCoachSpeeches.situations_of(speech_occasion):
				_row("speech_situation", str(st[1]), y, {"x": 13, "w": 25, "situation": int(st[0])})
				y += 2
		"lines":
			var lines := _speech_lines()
			for i in lines.size():
				_row("speech_line", "", y, {"x": 13, "w": 25, "index": i})
				y += 2
			if lines.size() < MwCoachSpeeches.LINES_MAX:
				_row("speech_new", "NEW LINE", y, {"x": 13, "w": 25, "item": true})
		"plays":
			# two headings in the light font (rows 9 and 17), the note on 25
			for i in 3:
				_row("nasty", ["1ST PERIOD", "2ND PERIOD", "3RD PERIOD"][i], 11 + 2 * i, {"index": i})
			for i in 3:
				_row("special", "SPECIAL %d" % (i + 1), 19 + 2 * i,
						{"index": i, "skip": i == MwCustomTeam.SPECIAL_FIXED})
		"roster":
			for i in 6:
				_row("slot", "", 13 + 2 * i, {"index": i, "x": 2, "w": 36})
		"pick":
			for i in 6:
				_row("take", "", 13 + 2 * i, {"index": i, "x": 2, "w": 36})
		"player":
			# a goalie has one species and is never an enforcer (the original
			# has none; his code would hand him a weapon): no rows for them
			var goalie := _player().is_goalie()
			for a in [["p_name", "NAME"], ["p_number", "NUMBER"], ["p_species", "SPECIES"], ["p_face", "FACE"],
					["p_side", "SIDE"], ["p_weight", "WEIGHT"], ["p_enforcer", "ENFORCER"]]:
				if goalie and a[0] in ["p_species", "p_enforcer"]:
					continue
				_row(a[0], a[1], y, {"x": 13, "w": 25})
				y += 2
		"ratings":
			# down each column to its foot (an enforcer's two rows under it),
			# then the next column, then OVERALL (owner: the enforcer's rows
			# came last, out of the columns' order)
			var enforcer := _player().enforcer
			for col in 2:
				for i in 5:
					_row("rating", "", y + 2 * i, {"x": 1 + 20 * col, "w": 18, "rating": RATING_ORDER[col][i],
							"col": col, "index": i})
				if enforcer:
					_row(["p_aggression", "p_instinct"][col], "", y + 10, {"x": 1 + 20 * col, "w": 18})
					_row(["p_weapon", "p_bonus"][col], ["WEAPON", "HIT BONUS"][col], y + 12,
							{"x": 1 + 20 * col, "w": 18})
			_row("p_overall", "OVERALL", y + 14, {"x": 1, "w": 18})
		"colour":
			for i in 3:
				_row("channel", ["RED", "GREEN", "BLUE"][i], 16 + 2 * i, {"index": i, "x": 10, "w": 20})


## The team description's look: the editor (132); the list (130) and its
## questions have the port menus'.
func _team_look() -> bool:
	return entry == "team"


# --- moving and changing ----------------------------------------------------------------------------
func _move(d: int, sound := true) -> void:
	if rows.is_empty():
		return
	for k in rows.size():
		row = posmod(row + d, rows.size())
		if not rows[row].get("skip", false):
			break
	if page == "roster":
		cursor = rows[row]["index"]
	elif page == "pick":
		pick_cursor = rows[row]["index"]
	swatch = 0
	if sound:
		_sound(SOUND_MOVE)
	_draw()


func _back() -> void:
	_sound(SOUND_MOVE)
	match page:
		"list":
			_remember()
			exit_to(MwScreens.FRONT_MENU)
		"edit":
			if dirty:
				_ask("LEAVE WITHOUT SAVING", _leave_editor)
			else:
				_leave_editor()
		_:
			if stack.is_empty():
				_open("edit")
			else:
				_pop()


func _leave_editor() -> void:
	MwCustomTeams.stop_editing()
	if session:
		session.screens.erase(MwScreens.EDIT_TEAM)
	exit_to(MwScreens.CREATE_A_TEAM)


## ARE YOU SURE? over the page, [param question] on its plate (MwConfirmBox,
## as every screen asks; NO selected first): YES calls [param yes].
func _ask(question: String, yes: Callable) -> void:
	confirm_yes = yes
	confirm.open(question)


func _answered(yes: bool) -> void:
	var f := confirm_yes
	confirm_yes = Callable()
	if yes and f.is_valid():
		f.call()


## The working copy changed: kept valid, shown to the game again, redrawn.
func _changed() -> void:
	dirty = true
	MwCustomTeams.edited()
	rom = MwRom.data()
	_draw()


## Left / Right on the selected row ([param repeat]: held, [MwHoldRepeat]).
func _change(d: int, repeat := false) -> void:
	if rows.is_empty():
		return
	var r := rows[row]
	var a: String = r["action"]
	match a:
		"copy_original":
			var order := _original_order()
			copy_from = order[posmod(order.find(copy_from) + d, order.size())]
		"team":
			# on / off (owner, 2026-10-11): an off team stays here and in its
			# file, out of the game's team rows until switched on again
			var saved := listed[int(r["team"])]
			MwCustomTeams.set_enabled(saved, not saved.enabled)
			rom = MwRom.data()
		"skulls":
			team.skulls = clampi(team.skulls + d, 0, 6)
		"menu_after":
			var order := [-1] + Array(_original_order())
			team.menu_after = order[posmod(order.find(team.menu_after) + d, order.size())]
		"playoff_place":
			team.playoff_place = posmod(team.playoff_place + d, 20)
		"logo":
			team.logo = posmod(team.logo + d, MwTeams.COUNT)
		"logo_colours", "shirt", "pants", "skin", "coach_colours", "name_colours":
			if (a == "coach_colours" and team.coach.colours.is_empty()) \
					or (a == "name_colours" and team.name_colours.is_empty()):
				return
			swatch = posmod(swatch + d, _swatch_words(a).size())
			_sound(SOUND_MOVE)
			_draw()
			return
		"coach_face":
			team.coach.face = posmod(team.coach.face + d, 7)
		"coach_voice":
			var v := [-1] + MwCustomCoach.VOICES
			team.coach.voice = v[posmod(v.find(team.coach.voice) + d, v.size())]
		"nasty":
			team.nasty[r["index"]] = _next_play(team.nasty[r["index"]], d, MwCustomTeam.NASTY_MAX)
		"special":
			team.specials[r["index"]] = _next_play(team.specials[r["index"]], d, 11)
		"slot":
			line = posmod(line + d, 4)
		"take":
			pick_line = posmod(pick_line + d, 4)
		"p_number":
			_player().number = posmod(_player().number + d, 100)
		"p_species":
			var edited := _player()
			if edited.is_goalie():
				return
			edited.species = posmod(edited.species - 1 + d, 3) + 1
		"p_face":
			_player().face = posmod(_player().face + 1 + d, 12) - 1
		"p_side":
			_player().side ^= 1
		"p_weight":
			_player().weight = clampi(_player().weight + d, 1, 6)
		"p_enforcer":
			_player().enforcer = not _player().enforcer
		"rating":
			var player := _player()
			player.ratings[r["rating"]] = clampi(int(player.ratings[r["rating"]]) + d, 0, 10)
		"p_aggression":
			_player().aggression = clampi(_player().aggression + d, 0, 10)
		"p_instinct":
			_player().instinct = clampi(_player().instinct + d, 0, 10)
		"p_weapon":
			var w := MwCustomPlayer.WEAPONS
			_player().weapon = w[posmod(w.find(_player().weapon) + d, w.size())]
		"p_bonus":
			_player().bonus = clampi(_player().bonus + d, 0, 15)
		"p_overall":
			_player().overall = clampi(_player().overall + d, -1, 10)
		"channel":
			var lv := MwEditorDraw.levels(colour_target["get"].call())
			lv[r["index"]] = clampi(int(lv[r["index"]]) + d, 0, 7)
			colour_target["set"].call(MwEditorDraw.word(lv))
		"yes", "no":
			_move(d)
			return
		_:
			return
	if not repeat or _repeat.sound_due():
		_sound(SOUND_MOVE)
	if page == "list":
		_draw()
		return
	if page == "ratings":
		_build_rows()                       # the enforcer's rows come and go
	_changed()
	if a in ["coach_face", "coach_voice", "p_face", "p_species"]:
		_start_portrait()
		_draw()                             # (its restart hides it: shown again where it goes)


## Whether Left / Right held repeats on the selected row (a number's).
func _repeats() -> bool:
	return not rows.is_empty() and str(rows[row]["action"]) in NUMBER_ROWS


## The next play from [param v] by [param d] among 1..[param top] that no
## other slot holds (Waste the Ref is special play 2's, always).
func _next_play(v: int, d: int, top: int) -> int:
	var used := Array(team.nasty) + Array(team.specials)
	used.erase(v)
	var n := v
	for k in top:
		n = posmod(n - 1 + d, top) + 1
		if not n in used:
			return n
	return v


## Accept on the selected row.
func _accept() -> void:
	if rows.is_empty():
		return
	var r := rows[row]
	_sound(SOUND_MOVE)
	match str(r["action"]):
		"new":
			_new_team()
		"copy_original":
			var copied := MwCustomTeam.from_original(MwRom.archive().bytes(), copy_from)
			_start_editing(copied, null)
		"team":
			var saved := listed[int(r["team"])]
			var copied := MwCustomTeam.from_dict(MwRom.archive().bytes(), saved.to_dict())
			copied.id = saved.id
			_start_editing(copied, saved, false)
		"info", "colours", "coach", "plays", "roster":
			_push(r["action"])
		"rink":
			_remember()
			exit_to(MwScreens.HOME_RINK)
		"bio":
			_type("bio", "BIO", team.bio, MwCustomTeam.TEXT_MAX)
		"save":
			_save()
		"city":
			_type("city", "TEAM CITY", team.city, MwCustomTeam.CITY_MAX)
		"name":
			_type("name", "TEAM NAME", team.name, MwCustomTeam.NAME_MAX)
		"coach_name":
			_type("coach_name", "COACH'S NAME", team.coach.name, MwCustomCoach.NAME_MAX)
		"coach_quote":
			_type("coach_quote", "COACH'S QUOTE", team.coach_quote, MwCustomTeam.TEXT_MAX)
		"coach_speeches":
			_push("speeches")
		"speech_occasion":
			speech_occasion = int(r["index"])
			var situations := MwCoachSpeeches.situations_of(speech_occasion)
			if situations.size() == 1:              # (overtime, a penalty: their lines straight away)
				speech_situation = int(situations[0][0])
				_push("lines")
			else:
				_push("situations")
		"speech_situation":
			speech_situation = int(r["situation"])
			_push("lines")
		"speech_line", "speech_new":
			speech_line = int(r["index"]) if r["action"] == "speech_line" else _speech_lines().size()
			var lines := _speech_lines()
			_type("speech_line", MwCoachSpeeches.label(_speech_category(), speech_situation),
					lines[speech_line] if speech_line < lines.size() else "", MwCoachSpeeches.LINE_MAX)
		"coach_colours":
			if team.coach.colours.is_empty():
				team.coach.colours = _coach_team_colours()
				_changed()
			else:
				_edit_swatch("coach_colours")
		"name_colours":
			if team.name_colours.is_empty():
				team.name_colours = team.kit.slice(0, 2)       # from the shirt's, as most screens draw it
				_changed()
			else:
				_edit_swatch("name_colours")
		"logo_colours", "shirt", "pants", "skin":
			_edit_swatch(r["action"])
		"slot":
			_edit_player(line * 6 + cursor)
		"take":
			_take()
		"p_name":
			_type("p_name", "PLAYER'S NAME", _player().name, MwCustomPlayer.NAME_MAX)
		"channel":
			_pop()


## The extra verbs: copy / pick (A), delete / new (B), next (C), previous.
func _verb(v: String) -> void:
	match page:
		"list":
			if rows.is_empty() or rows[row]["action"] != "team":
				return
			var saved := listed[int(rows[row]["team"])]
			_sound(SOUND_MOVE)
			if v == "copy":
				var copied := MwCustomTeam.from_dict(MwRom.archive().bytes(), saved.to_dict())
				copied.id = ""
				copied.enabled = true                   # (a new team plays, whatever the one it copies)
				_start_editing(copied, null)
			elif v == "delete":
				_ask("DELETE THE %s" % saved.name.to_upper(), func() -> void:
					MwCustomTeams.delete(saved)
					rom = MwRom.data()
					_open("list", 2))
		"roster":
			if v == "copy":
				pick_team = 0
				pick_line = line
				pick_cursor = cursor
				_push("pick", cursor)
			elif v == "delete":
				_new_player(line * 6 + cursor)
			elif v == "next":
				_move_slot()
		"pick":
			if v == "next" or v == "previous":
				pick_team = posmod(pick_team + (1 if v == "next" else -1), MwTeams.COUNT)
				_sound(SOUND_MOVE)
				_draw()
		"player":
			if v == "next":
				_open("ratings")
		"ratings":
			if v == "previous" or v == "next":
				_open("player")
		"colour":
			if v == "delete":
				colour_target["set"].call(colour_undo)
				_changed()
		"speeches", "situations":
			var own := _own_speech_keys()
			if v == "delete" and not own.is_empty():
				_sound(SOUND_MOVE)
				_ask("BACK TO THE ORIGINAL LINES", func() -> void:
					for k in own:
						team.coach.speeches.erase(k)
					_changed())
		"lines":
			if v == "delete" and rows[row]["action"] == "speech_line":
				_sound(SOUND_MOVE)
				_set_speech_line(int(rows[row]["index"]), "")
		"coach":
			if v == "delete" and rows[row]["action"] == "coach_colours" and not team.coach.colours.is_empty():
				team.coach.colours = PackedInt32Array()      # back to the team's colours
				_changed()
		"colours":
			if v == "delete" and rows[row]["action"] == "name_colours" and not team.name_colours.is_empty():
				team.name_colours = PackedInt32Array()       # back to the game's (the shirt's, the panel's)
				_changed()


# --- what the rows do ---------------------------------------------------------------------------------
var _pending_new: MwCustomTeam = null
var _pending_type := []
var player_slot := -1


## NEW TEAM: a team to fill in (an original's players to start from), its
## city and name typed first.
func _new_team() -> void:
	var fresh := MwCustomTeam.from_original(MwRom.archive().bytes(), 0)
	fresh.bio = ""
	fresh.coach_quote = ""
	fresh.menu_after = -1
	fresh.coach.name = "COACH"
	fresh.rink.name = "NEW RINK"
	_pending_new = fresh
	_type("new_city", "TEAM CITY", "", MwCustomTeam.CITY_MAX)


func _start_editing(working_copy: MwCustomTeam, of: MwCustomTeam, is_new := true) -> void:
	_remember()
	MwCustomTeams.edit(working_copy, of)
	if session:
		session.screens.erase(MwScreens.EDIT_TEAM)
	exit_to(MwScreens.EDIT_TEAM, {"dirty": is_new})


func _save() -> void:
	MwCustomTeams.save(team)
	MwCustomTeams.stop_editing()
	_sound(SOUND_SAVED)
	if session:
		session.screens.erase(MwScreens.EDIT_TEAM)
		session.screens[MwScreens.CREATE_A_TEAM] = {"row": 2 + MwCustomTeams.all().find(team), "copy_from": copy_from}
	exit_to(MwScreens.CREATE_A_TEAM)


## Types [param key]'s text on the text entry (131): the bio and the
## coach's quote wrapped as the team description's boxes wrap them (no
## more lines than they show) with an example while empty; a player's name
## in words of [constant MwCustomPlayer.WORD_MAX] at most.
func _type(key: String, title: String, text: String, limit: int) -> void:
	_remember()
	var field := team_text(key, title, text, limit)
	match key:
		"bio", "coach_quote":
			# wrapped as the team description's box wraps it, no more lines
			# than it shows; an example while empty (owner)
			var box := MwTeamDescription.BIO_BOX if key == "bio" else MwTeamDescription.COACH_BOX
			var w := MwGfx.s16(rom, box + 4)
			@warning_ignore("integer_division")
			var most := MwGfx.s16(rom, box + 6) / maxi(MwGfx.u16(rom, LIGHT), 1)
			var r := rom
			field.lines = most
			field.width = w
			field.example = MwTextEntry.bio_example(team) if key == "bio" else MwTextEntry.coach_quote_example(team)
			field.fits = func(t: String) -> bool:
				for word in t.split(" ", false):
					if word.length() > w:
						return false
				return MwEditorDraw.wrap(r, LIGHT, MwEditorDraw.ascii(t), w).size() <= most
		"speech_line":
			# a line as the rink's speech box shows it (34 x 6 cells, its
			# names filled in: [method MwCoachSpeeches.fits]); the team names
			# as tokens, the note saying which
			var r := rom
			var city := team.city
			var team_name := team.name
			field.allowed = MwCoachSpeeches.CHARSET.replace(" ", "")
			field.pages = MwCoachSpeeches.PAD_KEYS
			field.lines = SPEECH_ROWS
			field.width = SPEECH_COLUMNS
			field.example = MwCoachSpeeches.EXAMPLE
			field.advice = func(_t: String) -> String: return MwCoachSpeeches.TOKENS_NOTE
			field.fits = func(t: String) -> bool:
				return MwCoachSpeeches.fits(r, MwCoachSpeeches.clean_line(t), city, team_name)
			field.set_text(MwCoachSpeeches.clean_line(text))
		"p_name":
			field.fits = func(t: String) -> bool:              # the header and panels split it into words of 10
				for word in t.split(" ", false):
					if word.length() > MwCustomPlayer.WORD_MAX:
						return false
				return true
	if cut != null and session != null:
		# a cut (plan 40, M5): the page out, the text entry's in, the stars going on
		cut.leave(func(c: Dictionary) -> void: push(MwScreens.TEXT_ENTRY, {"field": field}.merged(c), false))
	else:
		push(MwScreens.TEXT_ENTRY, {"field": field})


## The text entry's [param text] for [param key].
func _typed(key: String, text: String) -> void:
	match key:
		"new_city":
			_pending_new.city = text
			_pending_new.rink.name = (text + " ARENA").substr(0, MwCustomRink.NAME_MAX)
			_pending_type = ["new_name", "TEAM NAME", "", MwCustomTeam.NAME_MAX]
			return
		"new_name":
			_pending_new.name = text
			_pending_new.validate(MwRom.archive().bytes())
			_pending_type = ["edit"]            # on the next pass (the router is resuming this screen)
			return
		"city":
			team.city = text
		"name":
			team.name = text
		"bio":
			team.bio = text
		"coach_name":
			team.coach.name = text
		"coach_quote":
			team.coach_quote = text
		"speech_line":
			_set_speech_line(speech_line, text)
			return
		"p_name":
			_player().name = text
		_:
			return
	_changed()


## SPEECHES' open occasion's category (the rink's).
func _speech_category() -> int:
	return MwCoachSpeeches.category_of(speech_occasion)


## The lines the coach says in the open situation: his own, else his
## original coach's (a copy: changed, it is set back whole).
func _speech_lines() -> PackedStringArray:
	return MwCoachSpeeches.lines_of(rom, team.coach, _speech_category(), speech_situation).duplicate()


## Line [param i] of the open situation typed as [param text]: empty deletes
## it, past the last adds one. His lines are his own from then on (the
## original's copied first) - unless they come out as the original's, or
## none are left: then he says the original's again.
func _set_speech_line(i: int, text: String) -> void:
	var lines := _speech_lines()
	var typed := MwCoachSpeeches.clean_line(text)
	if i < lines.size():
		if typed == "":
			lines.remove_at(i)
		else:
			lines[i] = typed
	elif typed != "" and lines.size() < MwCoachSpeeches.LINES_MAX:
		lines.append(typed)
	var k := MwCoachSpeeches.key(_speech_category(), speech_situation)
	if lines.is_empty() or lines == MwCoachSpeeches.original_lines(rom, _speech_category(), speech_situation,
			team.coach.style):
		team.coach.speeches.erase(k)
	else:
		team.coach.speeches[k] = lines
	_build_rows()
	row = clampi(row, 0, maxi(rows.size() - 1, 0))
	_changed()


## The situations of his own lines the selected row stands for (an
## occasion's on the occasions page, its own on the situations page).
func _own_speech_keys() -> Array:
	var out := []
	if rows.is_empty():
		return out
	var r := rows[row]
	var occasion := int(r["index"]) if page == "speeches" else speech_occasion
	for st: Array in MwCoachSpeeches.situations_of(occasion):
		if page == "situations" and int(st[0]) != int(r["situation"]):
			continue
		var k := MwCoachSpeeches.key(MwCoachSpeeches.category_of(occasion), int(st[0]))
		if team.coach.speeches.has(k):
			out.append(k)
	return out


## [param kept] (a line as kept: names as tokens) as the rink shows it for
## this team (the other team: his playoff place's, as the coach page's
## sample).
func _speech_shown(kept: String) -> PackedByteArray:
	return MwCoachSpeeches.expanded(kept, team.name, team.city, MwTeams.name_text(rom, team.playoff_place))


## [param text] cut to [param cells] cells in the rows' fonts, ".." where cut.
func _fitted(text: String, cells: int) -> String:
	var wide := func(measured: String) -> int:
		return maxi(MwEditorDraw.width(rom, LIGHT, measured), MwEditorDraw.width(rom, DARK, measured))
	if wide.call(text) <= cells:
		return text
	var cut_text := text
	while cut_text.length() > 1 and int(wide.call(cut_text.strip_edges() + "..")) > cells:
		cut_text = cut_text.left(cut_text.length() - 1)
	return cut_text.strip_edges() + ".."


## The colour words a colour row edits.
func _swatch_words(a: String) -> PackedInt32Array:
	match a:
		"logo_colours":
			return team.logo_colours
		"shirt":
			return team.kit.slice(0, 2)
		"pants":
			return team.kit.slice(2, 4)
		"skin":
			return team.skin
		"coach_colours":
			return team.coach.colours if not team.coach.colours.is_empty() else _coach_team_colours()
		"name_colours":
			return team.name_colours
	return PackedInt32Array()


## The colours a coach wears with his team's: line 1's 2-3, 5-9 (team A's).
func _coach_team_colours() -> PackedInt32Array:
	var c := palette.colours()
	var out := PackedInt32Array()
	for i in MwCustomCoach.COLOUR_INDICES:
		out.append(c[16 + i] if c.size() >= 32 else 0)
	return out


## The COLOUR page for swatch [member swatch] of row [param a].
func _edit_swatch(a: String) -> void:
	var i := swatch
	var getter := func() -> int: return _swatch_words(a)[i]
	var setter := func(w: int) -> void:
		match a:
			"logo_colours":
				team.logo_colours[i] = w
			"shirt":
				team.kit[i] = w
			"pants":
				team.kit[2 + i] = w
			"skin":
				team.skin[i] = w
			"coach_colours":
				team.coach.colours[i] = w
			"name_colours":
				team.name_colours[i] = w
	colour_target = {"get": getter, "set": setter}
	colour_title = {"logo_colours": "LOGO COLOUR %d", "shirt": "SHIRT %d", "pants": "PANTS %d",
			"skin": "SKIN %d", "coach_colours": "COACH'S COLOUR %d", "name_colours": "NAME COLOUR %d"}[a] % (i + 1)
	colour_undo = getter.call()
	_push("colour")


## The custom player in roster slot [member player_slot].
func _player() -> MwCustomPlayer:
	var occupant := team.roster[player_slot] if player_slot >= 0 else {}
	if occupant.has("player"):
		return team.players[int(occupant["player"])]
	return MwCustomPlayer.new()


## Roster slot [param slot]'s player on his pages (an original one copied
## first: editing one makes a custom copy, the original stays as it is).
func _edit_player(slot: int) -> void:
	var occupant := team.roster[slot]
	if not occupant.has("player"):
		var player := MwCustomPlayer.from_record(MwRom.archive().bytes(),
				MwTeams.player(rom, int(occupant["team"]), int(occupant["slot"])))
		player.source = {"team": int(occupant["team"]), "slot": int(occupant["slot"])}
		team.players.append(player)
		team.roster[slot] = {"player": team.players.size() - 1}
		_changed()
	player_slot = slot
	_push("player")


## A new player for slot [param slot] (a goalie in the G column).
func _new_player(slot: int) -> void:
	var player := MwCustomPlayer.new()
	player.species = MwCustomPlayer.GOALIE if slot % 6 == MwCustomTeam.GOALIE_COLUMN else 1
	player.number = 1 + slot
	team.players.append(player)
	team.roster[slot] = {"player": team.players.size() - 1}
	_sound(SOUND_MOVE)
	_changed()
	player_slot = slot
	_push("player")


## PICK A PLAYER: the original player under the cursor into the roster slot.
func _take() -> void:
	var from := {"team": pick_team, "slot": pick_line * 6 + pick_cursor}
	var slot := line * 6 + cursor
	var rec := MwTeams.player(rom, pick_team, pick_line * 6 + pick_cursor)
	var goalie := (rom[rec + 7] & 0x0F) == MwCustomPlayer.GOALIE
	if goalie != (slot % 6 == MwCustomTeam.GOALIE_COLUMN) or from in team.roster:
		_sound(SOUND_REFUSED)
		return
	team.roster[slot] = from
	_changed()
	_pop()


## The roster's MOVE: the first press picks a slot up, the second swaps it
## with the slot under the cursor (goalies stay in the G column).
func _move_slot() -> void:
	var slot := line * 6 + cursor
	if moving < 0:
		moving = slot
		_sound(SOUND_MOVE)
		_draw()
		return
	if (moving % 6 == MwCustomTeam.GOALIE_COLUMN) != (slot % 6 == MwCustomTeam.GOALIE_COLUMN):
		_sound(SOUND_REFUSED)
		moving = -1
		_draw()
		return
	var keep := team.roster[slot]
	team.roster[slot] = team.roster[moving]
	team.roster[moving] = keep
	moving = -1
	_sound(SOUND_MOVE)
	_changed()


## The original's 23 teams in the team rows' order (`$1C1A4`).
func _original_order() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in MwTeams.COUNT:
		out.append(rom[MwTeams.MENU_ORDER + i])
	return out


## The roster's suggested skulls: the original's step with the sum of the
## 24 players' overall ratings (104 none ... 201 six).
func _suggested_skulls() -> int:
	var sum := 0
	for slot in MwCustomTeam.SLOTS:
		sum += rom[MwTeams.player(rom, id, slot) + 8] & 0x0F
	return clampi(roundi((sum - 104) * 6.0 / (201 - 104)), 0, 6)


## The portrait the page shows (the coach's, a player's), talking.
func _start_portrait() -> void:
	_portrait_on = false
	portrait.hide_now()
	if page in COACH_PAGES:
		portrait.attr = 0x20
		portrait.set_data(rom, MwPortrait.coach_data(rom, MwTeams.coach(rom, id)), 0)
	elif page == "player" and player_slot >= 0:
		portrait.attr = 0x20
		portrait.set_player(rom, MwTeams.player(rom, id, player_slot), 1)
	else:
		return
	portrait.start(0)
	_portrait_on = true


# --- drawing ----------------------------------------------------------------------------------------
var _plate: RomPlane
var _dim: RomPlane


func _draw() -> void:
	if rom.is_empty():
		return
	if _plate == null:
		_plate = plane.duplicate() as RomPlane
		_plate.name = "TitlePlane"
		page_layers.add_child(_plate)
		page_layers.move_child(_plate, half_plane.get_index() + 1)
		_dim = plane.duplicate() as RomPlane          # plan 40 (M1): a dimmed row, as the port menus'
		_dim.name = "DimPlane"
		_dim.modulate = MwMenuRow.DIM
		page_layers.add_child(_dim)
		page_layers.move_child(_dim, plane.get_index() + 1)
	plane.clear()
	half_plane.clear()
	_plate.clear()
	_dim.clear()
	for c in swatch_layer.get_children():
		c.queue_free()
	for skull in _skulls:
		skull.visible = false
	for sprite in _arrows:
		sprite.visible = false
	skater.visible = false
	_palette()
	var team_look := _team_look()
	$Backdrop.visible = true
	logo.visible = false
	city_text.visible = false
	name_text.visible = false
	if team_look:
		MwPlanePainter.map_rows(plane, rom, PLATE, 0, 8, 0)
		if page in ["player", "ratings"]:
			_player_header()
		else:
			_team_header()
	portrait.visible = _portrait_on
	if _portrait_on:
		portrait.place(Vector2(16, 72) if page in COACH_PAGES else Vector2(24, 104))
	match page:
		"list":
			_draw_list()
		"roster", "pick":
			_draw_roster()
		_:
			_draw_page()


## The palette: the port menus' on the list, the team description's for the
## working copy (its panel colours, kit, coach's own colours) elsewhere.
func _palette() -> void:
	if not _team_look():
		palette.screen = 1
		palette.team_a = palette_team_a()
		palette.stadium = palette.team_a
		palette.steps = PackedStringArray(MENU_STEPS)
		_plate.palette = MwGlyphs.plate_palette(palette)
		return
	palette.screen = 2
	palette.team_a = id
	palette.team_b = id
	palette.stadium = id
	palette.steps = PackedStringArray(TEAM_STEPS)
	_plate.palette = MwGlyphs.plate_palette(palette)
	# the coach's own colours on a palette of his portrait's own (as the team
	# description draws him): the page's line 1 stays the team's, so the
	# header's letters keep the team's colours (owner)
	var own := MwCustomTeams.coach_palette(rom, palette, id, "a", 1) if page in COACH_PAGES else null
	portrait.set_palette(own if own != null else palette)


## The header plate: the team's logo, city and name in big letters (the
## name's own colours on a palette of the letters' own, owner).
func _team_header() -> void:
	if _name_palette == null:
		_name_palette = MwScreenPalettes.names(palette, 1)
	city_text.palette = _name_palette
	name_text.palette = _name_palette
	logo.position = Vector2(16, 16)
	logo.frame_addresses = PackedInt32Array([MwTeams.logo_frame(rom, id)])
	logo.visible = true
	name_text.region_enabled = false
	_big(city_text, MwGfx.rom_string(rom, MwTeams.city(rom, id)), Vector2(64, 8))
	_big(name_text, MwGfx.rom_string(rom, MwTeams.name(rom, id)), Vector2(64, 32))


## The header plate on a player's pages: his number and name (the whole
## name: one too long for the plate slides, [method _scroll_name]).
func _player_header() -> void:
	city_text.palette = palette                 # a player's number and name: the shirt's, as the game has them
	name_text.palette = palette
	var rec := MwTeams.player(rom, id, player_slot)
	_big(city_text, MwTeamDescription._digits(rom[rec + 4], false), Vector2(16, 20))
	var n := MwGfx.rom_string(rom, MwGfx.u32(rom, rec))
	_big(name_text, n, Vector2(72, 20))
	if n != _name_shown:
		_name_shown = n
		_name_off = 0
		_name_dir = 1
		_name_wait = NAME_PAUSE
	_clip_name()


## The name's window on the plate: [constant NAME_ROOM] pixels of it from
## [member _name_off] (a name that fits: all of it).
func _clip_name() -> void:
	var t := name_text.texture
	if t == null or t.get_width() <= NAME_ROOM:
		name_text.region_enabled = false
		return
	_name_off = clampi(_name_off, 0, t.get_width() - NAME_ROOM)
	name_text.region_enabled = true
	name_text.region_rect = Rect2(_name_off, 0, NAME_ROOM, t.get_height())


## [param elapsed] ticks of the long name's slide: a pixel a tick to one
## end, a pause, back to the other (the passes': no wall clock).
func _scroll_name(elapsed: int) -> void:
	if not name_text.visible or not name_text.region_enabled or not page in ["player", "ratings"]:
		return
	var room := name_text.texture.get_width() - NAME_ROOM
	for i in elapsed:
		if _name_wait > 0:
			_name_wait -= 1
			continue
		_name_off += _name_dir
		if _name_off <= 0 or _name_off >= room:
			_name_dir = -_name_dir
			_name_wait = NAME_PAUSE
	_clip_name()


func _big(node: RomPieces, bytes: PackedByteArray, at: Vector2) -> void:
	node.set_pieces(MwSpriteText.fixed(rom, MwEditorDraw.BIG, bytes, 0x20)[0])
	node.position = at
	node.visible = true


func _title(text: String, y: int) -> void:
	MwGlyphs.plate_title(_plate, rom, LIGHT, MwEditorDraw.ascii(text), y, MENU)


func _draw_list() -> void:
	_title("CREATE-A-TEAM", MwPortMenu.OPTIONS_TITLE_Y)
	var n := listed.size()
	var shown := list_shown(n)
	list_top = MwScrollArrows.follow(list_top, row - 2, shown, n) if row >= 2 \
			else clampi(list_top, 0, maxi(n - shown, 0))
	for i in rows.size():
		var r := rows[i]
		if r["action"] == "team":
			var k := int(r["team"]) - list_top
			if k < 0 or k >= shown:
				continue
			r["y"] = LIST_FIRST + 2 * k
	for i in rows.size():
		var r := rows[i]
		if r["action"] == "team" and (int(r["team"]) < list_top or int(r["team"]) >= list_top + shown):
			continue
		_draw_row(r, i == row, MENU)
	if n == 0:
		MwEditorDraw.centred(plane, half_plane, rom, LIGHT, "NO TEAMS OF YOUR OWN YET", LIST_FIRST + 2, MENU)
	_draw_arrows(list_top > 0, list_top + shown < n)
	MwPrompts.verbs(plane, rom, [["ui_left", "ON/OFF"], ["ui_accept", "EDIT"], ["ui_editor_copy", "COPY"],
			["ui_editor_delete", "DELETE"]], 27, MENU)


## How many saved teams the list shows for [param n] saved.
static func list_shown(n: int) -> int:
	return LIST_SHOWN if n <= LIST_SHOWN else LIST_SHOWN_SCROLLED


## The list's scroll arrows (plan 34's list pages': the rink's off-screen
## arrow, light grey on the menu palette's line 2): up while saved teams are
## out of sight above, down while below, the ones shown centred together.
func _draw_arrows(up: bool, down: bool) -> void:
	MwScrollArrows.place(_arrows, rom, up, down, LIST_ARROW_TOP)


func _draw_rows() -> void:
	for i in rows.size():
		_draw_row(rows[i], i == row, WHITE if _team_look() else MENU)


func _draw_row(r: Dictionary, selected: bool, attr: int) -> void:
	if r.get("item", false):
		MwEditorDraw.item(plane, half_plane, rom, r["label"], r["x"], r["y"], r["w"], selected, attr)
		return
	MwEditorDraw.row(plane, rom, _label(r), _value(r), r["x"], r["y"], r["w"], selected, attr,
			_dim if r.get("skip", false) else null)
	var a: String = r["action"]
	if a in ["logo_colours", "shirt", "pants", "skin", "coach_colours", "name_colours"]:
		if (a != "coach_colours" or not team.coach.colours.is_empty()) \
				and (a != "name_colours" or not team.name_colours.is_empty()):
			MwEditorDraw.swatches(swatch_layer, _swatch_words(a), int(r["x"]) + int(r["w"]), r["y"],
					swatch if selected else -1)
	if a == "skulls":
		for k in 6:
			_skulls[k].visible = k < team.skulls
			_skulls[k].position = Vector2(8 * (int(r["x"]) + int(r["w"])) - 6 - 12 * k, 8 * int(r["y"]) + 6)


## A row's label (some come from the ROM's own texts).
func _label(r: Dictionary) -> String:
	match str(r["action"]):
		"team":
			var saved := listed[int(r["team"])]
			return ("ON  " if saved.enabled else "OFF ") + (saved.city + " " + saved.name).to_upper()
		"rating":
			var labels: Array = GOALIE_LABELS if _player().is_goalie() else SKATER_LABELS
			return _rom_text(MwGfx.u32(rom, int(labels[int(r["col"])]) + 4 * int(r["index"])))
		"p_aggression":
			return _rom_text(MwGfx.u32(rom, int(SKATER_LABELS[0]) + 4 * 5))
		"p_instinct":
			return _rom_text(MwGfx.u32(rom, int(SKATER_LABELS[1]) + 4 * 5))
		"speech_line":
			var lines := _speech_lines()
			var i := int(r["index"])
			return _fitted("%d %s" % [i + 1, lines[i] if i < lines.size() else ""], int(r["w"]))
	return r["label"]


func _rom_text(a: int) -> String:
	return MwGfx.rom_string(rom, a).get_string_from_ascii().strip_edges()


## A row's value as shown.
func _value(r: Dictionary) -> String:
	match str(r["action"]):
		"copy_original":
			return _team_name(copy_from)
		"team":
			var saved := listed[int(r["team"])]
			return "%d SKULL%s" % [saved.skulls, "" if saved.skulls == 1 else "S"]
		"info":
			return "%d SKULL%s" % [team.skulls, "" if team.skulls == 1 else "S"]
		"coach":
			return team.coach.name
		"roster":
			return "%d OF YOUR OWN" % team.players.size() if not team.players.is_empty() else "ORIGINAL PLAYERS"
		"rink":
			return team.rink.name
		"city":
			return team.city
		"name":
			return team.name
		"menu_after":
			return "FIRST" if team.menu_after < 0 else "AFTER " + _team_name(team.menu_after)
		"playoff_place":
			return _team_name(team.playoff_place)
		"logo":
			return "%d OF %d" % [team.logo + 1, MwTeams.COUNT]
		"coach_name":
			return team.coach.name
		"coach_face":
			return "%d OF 7" % (team.coach.face + 1)
		"coach_colours":
			return "TEAM'S" if team.coach.colours.is_empty() else ""
		"name_colours":
			return "STANDARD" if team.name_colours.is_empty() else ""
		"coach_voice":
			return "FACE'S" if team.coach.voice < 0 else "%d OF %d" % [MwCustomCoach.VOICES.find(team.coach.voice) + 1,
					MwCustomCoach.VOICES.size()]
		"coach_speeches":
			var n := MwCoachSpeeches.own_count(team.coach)
			return "ORIGINAL" if n == 0 else "%d OF %d OWN" % [n, MwCoachSpeeches.situation_count()]
		"speech_occasion":
			var n := MwCoachSpeeches.own_count(team.coach, int(r["index"]))
			var total := MwCoachSpeeches.situations_of(int(r["index"])).size()
			return "ORIGINAL" if n == 0 else "OWN" if total == 1 else "%d OF %d OWN" % [n, total]
		"speech_situation":
			return "OWN" if team.coach.speeches.has(MwCoachSpeeches.key(_speech_category(), int(r["situation"]))) \
					else "ORIGINAL"
		"coach_quote":
			return team.coach_quote if team.coach_quote != "" else "NONE YET"
		"bio":
			return "EDIT"
		"nasty":
			return _play_name(team.nasty[r["index"]])
		"special":
			return _play_name(team.specials[r["index"]])
		"p_name":
			return _player().name
		"p_number":
			return str(_player().number)
		"p_species":
			return SPECIES_NAMES[_player().species]
		"p_face":
			return _face_name(_player().face)
		"p_side":
			return "RIGHT" if _player().side == 1 else "LEFT"
		"p_weight":
			return "%d OF 6" % _player().weight
		"p_enforcer":
			return "YES" if _player().enforcer else "NO"
		"rating":
			return str(_player().ratings[r["rating"]])
		"p_aggression":
			return str(_player().aggression)
		"p_instinct":
			return str(_player().instinct)
		"p_weapon":
			return "%d OF %d" % [MwCustomPlayer.WEAPONS.find(_player().weapon) + 1, MwCustomPlayer.WEAPONS.size()]
		"p_bonus":
			return str(_player().bonus)
		"p_overall":
			var player := _player()
			return "AUTO %d" % player.overall_value() if player.overall < 0 else str(player.overall)
		"channel":
			return "%d OF 7" % int(MwEditorDraw.levels(colour_target["get"].call())[r["index"]])
	return ""


func _team_name(t: int) -> String:
	return MwTeams.name_text(rom, t).to_upper()


## A play's name: the team description's list for 0-8 (its `_` padding
## dropped), the special plays screen's for 9-11.
func _play_name(p: int) -> String:
	if p <= MwCustomTeam.NASTY_MAX:
		return _rom_text(MwGfx.u32(rom, MwTeamDescription.NASTY_NAMES + 4 * p)).replace("_",
				" ").strip_edges().to_upper()
	return _rom_text(MwGfx.u32(rom, PLAYS + 4 * p)).to_upper()


## Player face [param f]'s name: a star's is his player's, then the species'.
func _face_name(f: int) -> String:
	if f < 0:
		return "SPECIES'"
	if f < 6:
		return _rom_text(MwGfx.u32(rom, MwGfx.u32(rom, MwPortrait.STARS + 10 * f))).to_upper()
	return SPECIES_FACES[f - 6]


## A page of rows in the team look: its heading, the rows, its notes and prompts.
func _draw_page() -> void:
	var heads := {"info": "TEAM INFO", "colours": "LOGO AND COLOURS", "coach": "",
			"plays": "", "player": "PLAYER", "colour": colour_title}
	var h: String = heads.get(page, "")
	if page == "plays":
		var nasty := MwGfx.rom_string(rom, MwGfx.u32(rom, MwTeamDescription.NASTY_HEADING)).get_string_from_ascii()
		MwEditorDraw.centred(plane, half_plane, rom, LIGHT, nasty.strip_edges().to_upper(), 9, YELLOW)
		MwEditorDraw.centred(plane, half_plane, rom, LIGHT, "SPECIAL PLAYS", 17, YELLOW)
	elif h != "":
		MwEditorDraw.centred(plane, half_plane, rom, MwEditorDraw.HEADING, h, HEAD_Y, WHITE)
	_draw_rows()
	var back := ["ui_back", "BACK"]
	match page:
		"edit":
			MwPrompts.verbs(plane, rom, [["ui_accept", "SELECT"], back], 27, WHITE)
		"info":
			MwEditorDraw.centred(plane, half_plane, rom, LIGHT, "THE ROSTER SUGGESTS %d SKULLS" % _suggested_skulls(),
					22, YELLOW)
			var last := team.name.right(1).to_upper()
			if not last in ["S", "Z", "5"]:
				MwEditorDraw.centred(plane, half_plane, rom, LIGHT, "TEAM NAMES SHOULD END IN S, Z OR 5", 24, YELLOW)
			MwPrompts.verbs(plane, rom, [["ui_left", "CHANGE"], ["ui_accept", "TYPE"], back], 27, WHITE)
		"colours":
			skater.palette = palette
			skater.attr_xor = 0x20
			skater.anim = "%X" % MwGfx.u32(rom, MwGfx.u32(rom, 0x1C48C + 4 * 3))
			skater.variant = 4
			skater.position = Vector2(276, 146)
			skater.visible = true
			MwEditorDraw.text(plane, rom, LIGHT, "HOME KIT", 30, 22, YELLOW)
			var parts := [["ui_left", "LOGO / COLOUR"], ["ui_accept", "EDIT"]]
			if rows[row]["action"] == "name_colours" and not team.name_colours.is_empty():
				parts.append(["ui_editor_delete", "STANDARD"])
			parts.append(back)
			MwPrompts.verbs(plane, rom, parts, 27, WHITE)
		"coach":
			_coach_box()
			var parts := [["ui_left", "CHANGE"], ["ui_accept", "EDIT"]]
			if rows[row]["action"] == "coach_colours" and not team.coach.colours.is_empty():
				parts.append(["ui_editor_delete", "TEAM'S"])
			parts.append(back)
			MwPrompts.verbs(plane, rom, parts, 27, WHITE)
		"speeches", "situations":
			if page == "speeches":
				MwEditorDraw.centred(plane, half_plane, rom, LIGHT, "WHAT HE SAYS IN THE RINK, AND WHEN", 25, YELLOW)
			else:
				_situation_box()
			var parts := [["ui_accept", "OPEN"]]
			if not _own_speech_keys().is_empty():
				parts.append(["ui_editor_delete", "ORIGINAL"])
			parts.append(back)
			MwPrompts.verbs(plane, rom, parts, 27, WHITE)
		"lines":
			_lines_box()
			var on_line: bool = not rows.is_empty() and rows[row]["action"] == "speech_line"
			var parts := [["ui_accept", "EDIT" if on_line else "TYPE"]]
			if on_line:
				parts.append(["ui_editor_delete", "DELETE"])
			parts.append(back)
			MwPrompts.verbs(plane, rom, parts, 27, WHITE)
		"plays":
			MwEditorDraw.centred(plane, half_plane, rom, LIGHT, "NO PLAY TWICE", 25, YELLOW)
			MwPrompts.verbs(plane, rom, [["ui_left", "CHANGE"], back], 27, WHITE)
		"player":
			MwPrompts.verbs(plane, rom, [["ui_left", "CHANGE"], ["ui_editor_next", "RATINGS"], back], 27, WHITE)
		"ratings":
			var player := _player()
			var fit := _fit(player, player_slot % 6)
			var pos := _rom_text(MwGfx.u32(rom, POSITIONS + 4 * (player_slot % 6)))
			MwEditorDraw.centred(plane, half_plane, rom, LIGHT, "FIT AS %s: %d" % [pos, fit], TOP_Y + 16, YELLOW)
			MwPrompts.verbs(plane, rom, [["ui_left", "CHANGE"], ["ui_editor_previous", "PLAYER"], back], 27, WHITE)
		"colour":
			var big := ColorRect.new()
			big.color = MwGfx.color(colour_target["get"].call())
			big.size = Vector2(96, 16)
			big.position = Vector2(8 * 14, 8 * 12)
			swatch_layer.add_child(big)
			MwPrompts.verbs(plane, rom, [["ui_left", "CHANGE"], ["ui_editor_delete", "UNDO"], ["ui_accept", "DONE"]],
					27, WHITE)


## The coach page's box under the rows (owner: SPEECHES and the quote were
## unclear): with SPEECHES selected one of his speeches, as he says it in
## the rink; else his team description quote (an example, dimmed, while
## he has none).
func _coach_box() -> void:
	var speeches: bool = rows[row]["action"] == "coach_speeches"
	MwPlanePainter.frame(plane, rom, 2, COACH_BOX_Y, 36, COACH_BOX_LINES, false)
	MwEditorDraw.text(plane, rom, LIGHT, " IN THE RINK, HE SAYS: " if speeches else " HIS QUOTE: ", 3, COACH_BOX_Y - 1,
			YELLOW)
	var text := _sample_speech() if speeches else MwEditorDraw.ascii(team.coach_quote)
	var attr := WHITE
	if not speeches and team.coach_quote == "":
		text = MwEditorDraw.ascii(MwTextEntry.coach_quote_example(team))
		attr = YELLOW
	var l := MwEditorDraw.wrap(rom, LIGHT, text, 36)
	MwEditorDraw.lines(plane, rom, LIGHT, l, 0, COACH_BOX_LINES, 2, COACH_BOX_Y, 36, attr)


## One of the coach's speeches: the first that fits the box of his own
## lines (in the occasions' order), else of his original coach's for a
## goal (category 7), a period's start (0), a big win (4) or a penalty (6),
## with this team's names (the other team: his playoff place's).
func _sample_speech() -> PackedByteArray:
	var first := PackedByteArray()
	var samples := []
	for o in MwCoachSpeeches.OCCASIONS.size():
		for st: Array in MwCoachSpeeches.situations_of(o):
			if team.coach.speeches.has(MwCoachSpeeches.key(MwCoachSpeeches.category_of(o), int(st[0]))):
				samples.append([MwCoachSpeeches.category_of(o), int(st[0])])
	samples.append_array(SPEECH_SAMPLES)
	for cs: Array in samples:
		for said in MwCoachSpeeches.lines_of(rom, team.coach, int(cs[0]), int(cs[1])):
			var bytes := _speech_shown(said)
			if first.is_empty():
				first = bytes
			if MwEditorDraw.wrap(rom, LIGHT, bytes, 36).size() <= COACH_BOX_LINES:
				return bytes
	return first


## The situations page's box: the selected situation's first line as the
## rink shows it (none: the original's own fallback, `$50D2D`), as many
## rows as the coach page's box holds.
func _situation_box() -> void:
	var situation := int(rows[row]["situation"])
	var lines := MwCoachSpeeches.lines_of(rom, team.coach, _speech_category(), situation)
	var title := " %s: " % MwCoachSpeeches.label(_speech_category(), situation)
	var text := _speech_shown(lines[0]) if not lines.is_empty() else MwGfx.rom_string(rom, MwQuotes.FALLBACK)
	if lines.size() > 1:
		title = " %s (1 OF %d): " % [MwCoachSpeeches.label(_speech_category(), situation), lines.size()]
	_speech_frame(title, text, COACH_BOX_Y, COACH_BOX_LINES, WHITE)


## The lines page's box: the selected line as the rink shows it, its rows
## and cells the rink's speech box's (NEW LINE: what typing one does).
func _lines_box() -> void:
	var title := " %s: " % MwCoachSpeeches.label(_speech_category(), speech_situation)
	if not rows.is_empty() and rows[row]["action"] == "speech_line":
		var lines := _speech_lines()
		_speech_frame(title, _speech_shown(lines[int(rows[row]["index"])]), LINES_BOX_Y, SPEECH_ROWS, WHITE)
	else:
		_speech_frame(title, MwEditorDraw.ascii("A NEW LINE FOR HIM TO SAY HERE, ONE OF HIS OWN. "
				+ MwCoachSpeeches.TOKENS_NOTE + "."), LINES_BOX_Y, SPEECH_ROWS, YELLOW)


## A framed box of [param rows_] rows from row [param y] with
## [param title] on its top edge: [param text] wrapped as the rink's speech
## box wraps it ([constant SPEECH_COLUMNS] cells), cut to the rows.
func _speech_frame(title: String, text: PackedByteArray, y: int, rows_: int, attr: int) -> void:
	MwPlanePainter.frame(plane, rom, 2, y, 36, rows_, false)
	MwEditorDraw.text(plane, rom, LIGHT, _fitted(title, 34), 3, y - 1, YELLOW)
	var l := MwEditorDraw.wrap(rom, LIGHT, text, SPEECH_COLUMNS)
	MwEditorDraw.lines(plane, rom, LIGHT, l, 0, rows_, 3, y, SPEECH_COLUMNS, attr)


## The position rating (`$1121E`, MwSimPlayers.position_rating) of
## [param player]'s record in column [param pos]: how the substitutions and the
## CPU's line changes rate him there.
func _fit(player: MwCustomPlayer, pos: int) -> int:
	return MwSimPlayers.position_rating(player.record_bytes(0), 0, pos)


## What roster slot [param slot] holds, for the line under the roster's
## heading: a player of the team's own (made here, or copied from an
## original team's and edited), or an original team's player borrowed.
func _slot_info(slot: int) -> String:
	var occupant := team.roster[slot]
	if not occupant.has("player"):
		return "BORROWED FROM THE " + _team_name(int(occupant["team"]))
	var player := team.players[int(occupant["player"])]
	if player.source.has("team"):
		return "+ YOUR OWN, FROM THE " + _team_name(int(player.source["team"]))
	return "+ YOUR OWN PLAYER"


## The roster page (the team description's): a line's six players with
## number, name and position; or PICK A PLAYER's original team.
func _draw_roster() -> void:
	var pick := page == "pick"
	var t := pick_team if pick else id
	var l := pick_line if pick else line
	var heading := _rom_text(MwGfx.u32(rom, LINE_HEADINGS + 4 * l))
	if pick:
		var pos := _rom_text(MwGfx.u32(rom, POSITIONS + 4 * cursor))
		MwEditorDraw.centred(plane, half_plane, rom, MwEditorDraw.HEADING, "PICK A " + pos, HEAD_Y, WHITE)
		MwEditorDraw.centred(plane, half_plane, rom, LIGHT, "%s - %s" % [_team_name(t), heading], 11, YELLOW)
	else:
		MwEditorDraw.centred(plane, half_plane, rom, MwEditorDraw.HEADING, heading, HEAD_Y, WHITE)
		MwEditorDraw.centred(plane, half_plane, rom, LIGHT, _slot_info(l * 6 + cursor), 11, YELLOW)
	for i in 6:
		var rec := MwTeams.player(rom, t, l * 6 + i)
		var sel := i == (pick_cursor if pick else cursor)
		var r := rows[i]
		if sel:
			MwPlanePainter.frame(plane, rom, r["x"], r["y"], r["w"], 1, true)
		var f := DARK if sel else LIGHT
		var attr := WHITE
		if not pick and moving == l * 6 + i:
			attr = YELLOW
		if pick and (((rom[rec + 7] & 0x0F) == MwCustomPlayer.GOALIE) != (cursor == MwCustomTeam.GOALIE_COLUMN)):
			attr = YELLOW                      # can't stand in the slot
		# the row: a "+" before the number marks a player of the team's own
		# (made here, or an original's copy edited here; owner: the mark
		# before the number), the borrowed originals have none
		var b := PackedByteArray()
		b.resize(36)
		b.fill(MwPlanePainter.CH_BLANK)
		if not pick and team.roster[l * 6 + i].has("player"):
			b[0] = OWN_MARK
		MwTeamDescription._overlay(b, 1, MwTeamDescription._digits(rom[rec + 4], false))
		MwTeamDescription._overlay(b, 4, MwGfx.rom_string(rom, MwGfx.u32(rom, rec)))
		MwTeamDescription._overlay(b, 0x17, MwGfx.rom_string(rom, MwGfx.u32(rom, POSITIONS + 4 * i)))
		MwGlyphs.text(plane, rom, f, b, 2, r["y"], attr)
	if pick:
		MwPrompts.verbs(plane, rom, [["ui_accept", "TAKE"], ["ui_editor_previous", "TEAM"],
				["ui_editor_next", "TEAM"], ["ui_left", "LINE"]], 25, WHITE)
		MwPrompts.verbs(plane, rom, [["ui_back", "BACK"]], 27, WHITE)
	else:
		MwPrompts.verbs(plane, rom, [["ui_accept", "EDIT"], ["ui_editor_copy", "PICK"],
				["ui_editor_delete", "NEW"]], 25, WHITE)
		MwPrompts.verbs(plane, rom, [["ui_editor_next", "PUT DOWN" if moving >= 0 else "MOVE"], ["ui_left", "LINE"],
				["ui_back", "BACK"]], 27, WHITE)
