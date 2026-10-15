class_name MwPortMenu
extends MwScreen
## The port's own menus (plan 21; owner, 2026-10-08: a true options menu in
## the original's look), one scene for three screens ([constant MwScreens.PORT]):
##
## * 100, the front menu after the title (the main menu, as the owner calls it): START
##   GAME (plan 34: PLAY MODE), CREATE-A-TEAM (plan 38: the custom teams,
##   [MwCreateTeam]), team descriptions (screen 2, every team in turn),
##   OPTIONS, REPLAYS, CREDITS (the title screen's credits roll), QUIT
##   GAME (the screen and the music fade out, then the game closes); 1800
##   ticks without a press start the attract demo; Menu Back goes back to
##   the title. The project's own logo sits under the original's there
##   ([constant WEENIE_GAP]), the items a pixel closer together under it,
##   and the game's version in the bottom right corner ([method
##   version_text]).
## * Plan 34 (owner: the menu overhaul): 106 PLAY MODE (LOCAL PLAY, ONLINE
##   MULTIPLAYER - plan 35's online pages, 119-123: MwOnlineMenu), 107 LOCAL PLAY (EXHIBITION
##   and PLAYOFFS: the game setup's port variants, `MwSession.local_mode`;
##   continue playoffs), 108 continue playoffs (LOAD GAME: 109; PASSWORD: the
##   original's password screen over the playoffs), 109 SAVED GAMES, 118
##   REPLAYS (the saved replays and the recorded attract demos, newest
##   first - MwReplayFile: accept plays one on screen 7, DELETE asks first,
##   KEEP takes a demo out of the demos' limit).
## * 101, options: VISUALS (103: CAMERA, DISPLAY, ASPECT RATIO, and the 3D
##   view's ABACABB MODE - the arena's blood and oil -, DETAILED ICE and
##   REFLECTIONS, MwSettings.blood / ice_detail / reflections), GAMEPLAY
##   MODIFIERS (104: ENHANCE AUDIO, REPLAY LENGTH, REPLAY BLOOD - the 3D
##   replays' paint, MwSettings.replay_paint, off by default -, CHARACTER SELECT, CAPTAIN
##   MODE, LINE-UP SELECT), CONTROLS (105: ANALOG CONTROL - plan 22's stick
##   steering and pace -, SHOT HEIGHT BUTTONS - MwSettings.shot_heights: the
##   STANDARD layout's HIGH / LOW SHOT lift shots instead of the D-pad; off
##   by default -, CONTROLLER BINDINGS).
## * 102, controller bindings (plan 22: per verb): PLAYER (1-12, plan 34:
##   with its device's tag, dimmed while that gamepad isn't there), LAYOUT (STANDARD /
##   GENESIS, MwInputMap; a new layout drops the player's own bindings) and
##   the page of verbs (MwVerbs.PAGES) change with Left / Right; on a verb,
##   accept waits for the next input - any key but the function keys (the
##   views'), gamepad button or stick of any device - and binds it
##   ([MwSettings]). A STICK row binds the stick moved next to the page's
##   four directions, besides their D-pad (owner: analogue mappable). An input two verbs share on one screen stays on
##   both and shows red (owner). The menu then waits for that input to be let
##   go, so the press that was bound doesn't also move the menu (owner).
##   Each verb shows its key and its gamepad input as glyphs (plan 23:
##   "Z + PAD1 [A]", the gamepad's tag first); a long page scrolls, the
##   rink's off-screen arrows under it pointing to the verbs out of sight.
##   While a verb that shares its input with others by default is selected
##   (the original's one-button meanings, MwVerbs.GROUPS: PASS / LET PUCK GO
##   / CHANGE PLAYER and so on), the others' labels are drawn as the
##   highlight draws its own, dark - frame and grey ground round the label
##   alone - and they scroll into view with it: they can be combined (owner).
##
## Selecting: Menu Accept (`ui_accept`: Enter, Start, and in the STANDARD
## layout the gamepad's south button); Menu Back goes one screen up.
##
## The look and feel are the original menus': the main menu's scrolling
## starfield and palette, the logo cut from its backdrop, the menu fonts,
## the highlight frame (filled when the selection moves) with the dark font
## on the selected row, sound `$25` on every move and change, full-screen
## fades between screens. The pages' titles sit on the pause menu's plate
## (MwGlyphs.black_label, its grey: MwGlyphs.plate_palette; owner). The
## labels are the port's own text.

const BACKDROP := 0x41BF2            ## the game setup's backdrop (main_menu.gd)
## The logo inside the backdrop's stone frame (cells) and where it goes:
## on every page exactly where the game setup has it (plan 34, owner: the
## logo kept in one place throughout - the game setup's frame then crashes
## down around it, its window see-through).
const LOGO := Rect2i(15, 3, 10, 8)
const LOGO_AT := Vector2i(15, 3)
## The logo's lowest visible pixel line on the pages (its letters' feet; the
## rest of its cells is its black panel, see-through here).
const LOGO_FOOT := 81
## The project's own logo, mightyweenie's (the port's art, not the ROM's:
## `res://assets/logo/mightyweenie_logo.png`, the scene's WeenieLogo; owner,
## 2026-10-11: about 1 px under the original's logo, fading out when an item
## is chosen and back in on the way back): on the main page alone, centred
## on the screen, this many pixels of gap under [constant LOGO_FOOT], at its
## own size on whole pixels. It is one of the page's own layers, so it fades
## with the page in the cuts between menus ([member page_layers]) and with
## the whole screen in the fades.
const WEENIE_GAP := 1
## The game's version on the main page (owner, 2026-10-11: in the main
## menu's bottom right corner, fading out for any other menu as the
## project's logo does): right-aligned so its last letter is in this
## column, one cell in from the screen's right edge, on the last item's
## line (QUIT GAME's: [method version_top]); in the light font, dimmed
## ([constant DIM]), on the page's own layers like the project's logo, so
## it fades with the page in the cuts between menus and with the screen in
## the fades.
const VERSION_RIGHT := 38
## The game setup's top hangs this far above its place on the pages (owner,
## 2026-10-10: the overlay's part with the skull and its side decorations
## hangs at the top of the main menu from the start, lowers when the game
## setup comes in and goes back up when the player backs out): only its
## arch shows - rows 13-15 of the window, the skull and the wings to the
## sides - above the logo. The game setup comes in with a cut and lowers
## the top from here ([method MwMainMenu._start_slam]); its Back lifts it
## back here first.
const TOP_HANG := 104
## The port's menus change by cuts ([MwMenuCut], plan 40 M5; owner,
## 2026-10-10 and 2026-10-11): leaving for another starfield screen
## ([constant MwMenuCut.SCREENS]), the page's own layers fade out, then a
## cut, and the next page's fade in - as one picture, the same on every page
## ([member page_layers]; owner, 2026-10-11: the menus' fades made
## consistent); the starfield goes on where it was; the logo and the game
## setup's hanging top stay put - each fades only where one page shows it
## and the other doesn't ([method _shows_logo], [method _shows_top]).
const OPTIONS_LOGO_Y := 3
## The pages' titles, on the pause menu's black plate (MwGlyphs.black_label;
## owner): their rows.
const OPTIONS_TITLE_Y := 12
const BINDINGS_TITLE_Y := 3
const SOUND_MOVE := MwSoundIds.MOVE             ## `$13CEE` sound: row moved / value changed
const FONT_LIGHT := MwPlanePainter.FONT_MENU
const FONT_DARK := MwPlanePainter.FONT_SMALL
const TEXT_ATTR := MwMenuRows.TEXT_ATTR
## Menu rows like the original's (a frame 34 cells wide), centred on the
## screen: inside cells 3-36, edges in 2 and 37 (the game setup's start at 4).
const ROW_X := 3
const ROW_W := 0x22
## The front menu's centred items and their frame.
const ITEM_W := 14
## Waiting for an input to bind: given up after this many ticks.
const CAPTURE_TICKS := 300
## QUIT GAME: the fade-out (screen and music) before the game closes.
const QUIT_TICKS := 32
const OFF_ON := MwSettings.OFF_ON
## The bindings page: its first verb row and how many fit (one line fewer
## than the screen holds, for the scroll arrows under the list - owner).
const VERB_Y := 13
const VERBS_SHOWN := 6
## Between a verb's inputs (owner; "+" is the port's, [method MwGlyphs.text]).
const SEPARATOR := " + "
## The scroll arrows (owner: gameplay's arrow marking the selected players,
## light grey, centred): the rink's off-screen arrow
## ([constant MwRinkMatch.ARROWS]), its up and down variants under the
## list, each while verbs are hidden that way, centred on the screen
## together. In the menu's own palette: the fourth pad's arrow is all ink 8,
## which on line 2 (attr $40) is the light grey $AAA whatever the team.
const ARROW_PAD := 3
const ARROW_XOR := 0x40
const ARROW_UP := 6              ## variants: off the top, off the bottom (24 x 24 pixels)
const ARROW_DOWN := 2
const ARROW_W := 24
const ARROW_TOP := 196           ## pixels: centred in the 4 rows under the list
const ARROW_GAP := 8             ## pixels between the two
## A collision's value: drawn this colour (MwInputMap.collisions).
const RED := MwUiInk.RED
## The selected verb's partners' labels ([method _draw_partner]): the
## highlight's frame, ground and dark font at this shade.
const PAIR_DARK := MwUiInk.DARK

enum Kind { ITEM, CHOICE, BINDING, LIST }

## The item pages (plan 34): [label, action] per item, in order. Centred,
## in a frame as wide as the page's widest label. Labels that are the
## original's own words come from the ROM at run time ([method label_text]:
## "@mode:N" the game setup's play mode value N, "@row:N" row N's label, a
## "+S" after it adds an S).
const ITEMS := {
	# owner, 2026-10-10: the options and the team descriptions swap places on the main menu.
	"main": [["START GAME", "start"], ["CREATE-A-TEAM", "create"], ["@mode:4+S", "teams"], ["OPTIONS", "options"],
			["REPLAYS", "replays"], ["CREDITS", "credits"], ["QUIT GAME", "quit"]],
	"play_mode": [["LOCAL PLAY", "local"], ["ONLINE MULTIPLAYER", "online"]],
	"local_play": [["EXHIBITION", "exhibition"], ["@mode:1", "playoffs"], ["@mode:3", "continue"]],
	"continue": [["LOAD GAME", "load"], ["PASSWORD", "password"]],
	"options": [["VISUALS", "visuals"], ["GAMEPLAY MODIFIERS", "modifiers"], ["CONTROLS", "controls"]],
}
## The choice pages: [label, setting] per row (left-justified label, the
## value right-justified, Left / Right change it: plan 40, I1 -
## MwSettings.SAVED's names, MwSettings.step / text); CONTROLS ends with the
## bindings' item.
const CHOICES := {
	# owner, 2026-10-11: ABACABB MODE (blood mode, after Mortal Kombat's blood code), DETAILED ICE
	# (the ice detail layer on or off) and REFLECTIONS added, each on by default (the 3D view's;
	# MwSettings.blood / ice_detail / reflections)
	"visuals": [["CAMERA", "camera"], ["DISPLAY", "fullscreen"], ["ASPECT RATIO", "aspect"],
			["ABACABB MODE", "blood"], ["DETAILED ICE", "ice_detail"], ["REFLECTIONS", "reflections"]],
	# owner, 2026-10-15: keeping the blood for the replays made optional, off by default
	# (MwSettings.replay_paint, by REPLAY LENGTH; VISUALS keeps its six rows on one page)
	"modifiers": [["ENHANCE AUDIO", "enhance_audio"], ["REPLAY LENGTH", "replay_length"],
			["REPLAY BLOOD", "replay_paint"], ["TICK RATE", "tick_rate"],
			["CHARACTER SELECT", "character_select"], ["CAPTAIN MODE", "captain_mode"],
			["LINE-UP SELECT", "lineup_select"], ["EXTENDED PENALTIES", "extended_penalties"],
			["EXTENDED CPU", "extended_cpu"]],
	"controls": [["ANALOG CONTROL", "analogue"], ["SHOT HEIGHT BUTTONS", "shot_heights"]],
}
## Each page's title, on the pause menu's plate (the main menu has none).
const TITLES := {
	"options": "OPTIONS", "visuals": "VISUALS", "modifiers": "GAMEPLAY MODIFIERS", "controls": "CONTROLS",
	"bindings": "CONTROLLER BINDINGS", "play_mode": "@row:3", "local_play": "LOCAL PLAY",
	"continue": "@mode:3", "saved_games": "SAVED GAMES", "replays": "REPLAYS",
}
## Menu Back: the screen one up (the main menu's: the title).
const UP := {
	"options": MwScreens.FRONT_MENU, "visuals": MwScreens.OPTIONS, "modifiers": MwScreens.OPTIONS,
	"controls": MwScreens.OPTIONS, "bindings": MwScreens.CONTROLS, "play_mode": MwScreens.FRONT_MENU,
	"local_play": MwScreens.PLAY_MODE, "continue": MwScreens.LOCAL_PLAY, "saved_games": MwScreens.CONTINUE,
	"replays": MwScreens.FRONT_MENU,
}
## Items not there yet: drawn dim and refused (none now: plan 35 brought
## online play).
const DISABLED: Array[String] = []
## The main page's items (owner, 2026-10-11, with the project's logo: the
## gaps between them about 1 px smaller to make room, off the tile grid if
## need be): the first item's text from this pixel line, the next ones
## [constant MAIN_ITEM_PITCH] pixels apart - a pixel closer than the
## two rows they were. Under the project's logo with the room a selected
## item's frame leaves above the next item's text (6 pixels: the frame
## takes a pixel line above the text and two below its 7); the last item's
## frame ends at line 214, inside the screen. The rows are drawn as every
## page's are, between the tile rows where their lines fall ([method
## item_top], [method _on]).
const MAIN_ITEM_TOP := 116
const MAIN_ITEM_PITCH := 15
## The other item pages' first item, under their title, and the spacing (rows).
const ITEM_Y := 15
const ITEM_STEP := 3
## The choice pages' first row, two rows apart; the bindings' item after a gap.
const CHOICE_Y := 15
## Plan 44: the choice rows a page holds (VISUALS' six); a longer page
## (GAMEPLAY MODIFIERS with EXTENDED PENALTIES and EXTENDED CPU) shows
## [constant CHOICES_SHOWN] and scrolls, the scroll arrows under them as
## the bindings' (one row fewer than the screen holds, for the arrows).
const CHOICES_FIT := 6
const CHOICES_SHOWN := 5
const SOUND_REFUSED := MwSoundIds.REFUSED          ## the password screen's refusal
## The list pages (109 saved games, 118 replays): their first line, two rows
## apart, how many show (the selection scrolls them, the bindings' arrows
## under them pointing to the lines out of sight - their top at
## [constant LIST_ARROW_TOP], pixels), the selected entry's detail line.
const LIST_Y := 15
const LIST_SHOWN := 4
const LIST_ARROW_TOP := 180
const DETAIL_Y := 26
## A save's round as the list names it (the port's words; by the run's
## round byte: 0 division finals, 1 conference championship, 2 the cup,
## 3 the first round).
const ROUND_NAMES := ["ROUND 2", "ROUND 3", "CUP FINAL", "ROUND 1"]
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
const DIM := MwUiInk.DIM

## The page's own layers - everything but the backdrop, the stars, the logo
## and the game setup's hanging top: the planes, the tinted ones
## (collisions red, the dim, the pair hint's dark), the title's plate, the
## scroll arrows, the YES / NO box, the project's logo, the online pages'
## own. A CanvasGroup: they are put together first, and the cuts between
## menus fade the result ([method MwMenuCut.apply]) - the page as one picture,
## no layer showing through another or its edges mid-fade (owner,
## 2026-10-11: on OPTIONS the text's outline faded apart from the text).
## Their own modulates (the tints) stay as they are.
@onready var page_layers: CanvasGroup = $Page
@onready var plane: RomPlane = $Page/Plane
## Text centred on half a cell: the same tiles 4 pixels to the right.
@onready var half_plane: RomPlane = $Page/HalfPlane
@onready var starfield: RomStarfield = $Starfield
@onready var palette: RomPalette = $Page/Plane.palette
## The project's logo ([constant WEENIE_GAP]): the main page's alone (the
## online pages' scene, [MwOnlineMenu], has none).
@onready var weenie: Sprite2D = get_node_or_null("Page/WeenieLogo")

var _drawn_full := false        # the FULLSCREEN value drawn last (Alt+Enter changes it, plan 28)
var rom: PackedByteArray
## The page: "main", "options" or "bindings" (the entry variant).
var page := "main"
## Rows of the page: {kind, label, y, action / verb}.
var rows: Array[Dictionary] = []
var row := 0
## Bindings: the player (1-12), the page of verbs (MwVerbs.PAGES), the first
## verb row shown, and the verb waiting for its input ("" none).
var player := 1
var bind_page := 0
var scroll := 0
var capturing := ""
var idle := 0
## What QUIT GAME does once the fade-out is over (tests put their own here).
var quit_game := func() -> void: get_tree().quit()

var _fill := true                    # the highlight is filled on its next drawing
var _capture_left := 0
var _settle := false                 # ignore the pads until everything is released
var _bound: InputEvent = null        # ... and the input just bound
var _quit_left := -1                 # QUIT GAME: ticks of fade-out left (-1: not quitting)
var _red: RomPlane                   # collisions' values and ABACABB MODE's label, tinted ...
var _red_ink: RomPlane               # ... and red on the highlight's bar ([method _red_for])
var _dim: RomPlane                   # items not there yet, dimmed; the main page's version
## The saved games' page: "load" (from the continue page) or "save" (the
## game setup's SAVE GAME).
var list_mode := "load"
## YES / NO questions (overwrite, delete).
var confirm: MwConfirmBox
var _asked := ""                     # what the question is about: "overwrite", "delete"
var _item_w := ITEM_W                # the item pages' frame width (cells)
var _pair: RomPlane                  # the selected verb's partners' labels, highlighted dark
var _partners: Array[int] = []       # their rows ([method _pair_rows]; the selected one too)
var _plate: RomPlane                 # the page's title on its plate, in the plate's grey
var _arrows: Array[RomSprite] = []   # the scroll arrows: up, down
var _collisions := {}                # MwInputMap.collisions(), at the last drawing
var _devices := -1                   # MwInputMap.devices_changed, at the last drawing
## The game setup's top, hanging ([constant TOP_HANG]); hidden on the
## bindings page, whose title is up there (and the lobby's).
var top: RomPlane
## The logo, on a layer of its own (the page's text fades round it).
var logo_plane: RomPlane
## The cuts between menus ([MwMenuCut]: the page's layers as one, the logo,
## the top; the stars carried on).
var cut: MwMenuCut
## Rows between the tile rows ([method _on]): per layer, its twins by the
## pixels they are moved down ({layer: {dy: twin}}).
var _twins := {}


func _enter_screen(data: Dictionary) -> void:
	page = entry if entry != "" else "main"
	if weenie:
		weenie.visible = page == "main"
		weenie.position = Vector2(weenie_at())
	if not MwRom.available():
		return
	rom = MwRom.data()
	if session:
		session.take_port_defaults()         # PENALTIES on, RESERVES enabled (owner, 2026-10-15)
		palette.team_a = session.setup.team_a
		starfield.start(session.rng_aux)
		if data.get("cut", false) or data.get("menu_cut", false):
			_restore_starfield()             # a cut from another menu: the stars going on
	palette.screen = 1
	# line 1: the logo's colours as on the game setup screen; its black panel
	# (colour 15) see-through, so the starfield shows around the letters (owner)
	palette.steps = PackedStringArray(MwMenuBackdrop.STEPS)
	MwSound.music_title()                # the title's music goes on (it did into the credits); kept if it plays
	var st: Dictionary = session.screens.get(screen_id, {}) if session else {}
	player = int(st.get("player", 1))
	bind_page = int(st.get("bind_page", 0))
	list_mode = str(data.get("mode", st.get("mode", "load")))
	_make_top()
	logo_plane = plane.duplicate() as RomPlane
	logo_plane.name = "LogoPlane"
	add_child(logo_plane)
	move_child(logo_plane, page_layers.get_index())     # under the page, over the top
	_logo(LOGO_AT.y)                         # every page has it, shown or not (its fades)
	# the page's own layers, in drawing order: PairPlane, Plane, DimPlane,
	# RedPlane, RedInkPlane, HalfPlane, TitlePlane, the arrows
	_red_ink = page_layer("RedInkPlane", plane.get_index() + 1, RED)
	_red_ink.screen_tint = true           # the dark font's black letters red, its bar white
	_red = page_layer("RedPlane", plane.get_index() + 1, RED)
	_dim = page_layer("DimPlane", plane.get_index() + 1, DIM)
	# under the plane: the highlight's frame stays on top
	_pair = page_layer("PairPlane", plane.get_index(), PAIR_DARK)
	_plate = page_layer("TitlePlane", half_plane.get_index() + 1)
	_plate.palette = MwGlyphs.plate_palette(palette)
	_arrows = MwScrollArrows.make(page_layers, palette)    # plan 40 (M3)
	# the question box (over the whole screen: z_index): the page's too, so a
	# page leaving with it open fades as one picture with it
	confirm = MwConfirmBox.new()
	confirm.name = "Confirm"
	page_layers.add_child(confirm)
	confirm.setup(plane, rom)
	confirm.answered.connect(_answered)
	_build_rows()
	row = clampi(int(st.get("row", 0)), 0, rows.size() - 1)
	_scroll_to_row()
	_draw()
	_menu_entry(data)


## The version the main page shows ([constant VERSION_ROW]): "V" and the
## project's `application/config/version` - the one the replays' headers and
## the online HELLO carry as their build ([method MwNetHost.build_id]) - or
## "DEV" when the project has none.
static func version_text() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges().to_upper()
	return "V" + v if v != "" else "DEV"


## The version's top pixel line ([constant VERSION_RIGHT]): the main page's
## last item's, so the two read as one line at the screen's foot.
static func version_top() -> int:
	return main_item_top((ITEMS["main"] as Array).size() - 1)


## Where the project's logo goes ([constant WEENIE_GAP]): its top left
## corner, in pixels.
func weenie_at() -> Vector2i:
	var size := Vector2i(weenie.texture.get_size()) if weenie and weenie.texture else Vector2i.ZERO
	return Vector2i(_half(320 - size.x), LOGO_FOOT + 1 + WEENIE_GAP)


## A new layer of the page's own ([member page_layers]): the plane's tiles
## and palette, named [param name_], tinted [param tint], at [param at]
## among them (the online pages' too).
func page_layer(name_: String, at := -1, tint := Color.WHITE) -> RomPlane:
	return MwUiInk.layer_like(page_layers, plane, name_, tint, at)


## The main page's item [param i]: its text's top pixel line ([constant
## MAIN_ITEM_TOP]; its frame, when selected, a line above and two below).
static func main_item_top(i: int) -> int:
	return MAIN_ITEM_TOP + MAIN_ITEM_PITCH * i


## Item [param i]'s text's top pixel line on item page [param name_]: the
## main page's ([method main_item_top]), the others' on the tile rows
## ([constant ITEM_Y], [constant ITEM_STEP]).
static func item_top(name_: String, i: int) -> int:
	return main_item_top(i) if name_ == "main" else 8 * (ITEM_Y + ITEM_STEP * i)


## The layers' opacity on entry ([method MwMenuCut.enter]): by a cut from
## another menu (or from the game setup) the page's layers fade in, the logo
## and the top from what the page before showed to what this one shows;
## otherwise (a fade, the first screen) as this page has them.
func _menu_entry(data: Dictionary) -> void:
	cut = MwMenuCut.new(page_layers, starfield, session, logo_plane, top)
	cut.enter(data.get("menu_cut", false) or (data.get("cut", false) and previous == 1), data, _shows_logo(),
			_shows_top())


## Whether this page shows the logo (the bindings have their title there).
func _shows_logo() -> bool:
	return page != "bindings"


## Whether this page shows the game setup's hanging top.
func _shows_top() -> bool:
	return page != "bindings"


## Leaving for another starfield screen ([method MwMenuCut.cuts_to]) is a
## cut after the page's own layers fade out ([method _menu_pass]); anything
## else as asked.
func exit_to(id: int, data := {}, fade := true, ticks := -1) -> void:
	if cut != null and cut.leaving():
		return                               # already on its way
	if fade and MwMenuCut.cuts_to(id) and session != null and cut != null:
		_leave_by_cut(id, data)
		return
	super.exit_to(id, data, fade, ticks)


func _leave_by_cut(id: int, data: Dictionary) -> void:
	cut.leave(_cut_to.bind(id, data.duplicate()))


## The cut itself, the page faded out ([param c]: the cut's data).
func _cut_to(c: Dictionary, id: int, data: Dictionary) -> void:
	data.merge(c, true)
	super.exit_to(id, data, false)


## The cuts' fades, [param elapsed] ticks on (every pass, first). True while
## leaving: the page answers nothing more (the stars still move).
func _menu_pass(elapsed: int) -> bool:
	return cut != null and cut.step(elapsed)


func _build_rows() -> void:
	rows.clear()
	if ITEMS.has(page):
		var items: Array = ITEMS[page]
		_item_w = ITEM_W
		for i in items.size():
			var label := label_text(rom, items[i][0])
			var line := item_top(page, i)
			rows.append({"kind": Kind.ITEM, "label": label, "action": items[i][1], "y": line >> 3, "dy": line & 7,
					"disabled": items[i][1] in DISABLED})
			if not rom.is_empty():
				_item_w = maxi(_item_w, _width(FONT_LIGHT, _ascii(label)) + 4)
		_item_w += _item_w % 2
		return
	if CHOICES.has(page):
		var y := CHOICE_Y
		for c in CHOICES[page]:
			rows.append({"kind": Kind.CHOICE, "label": c[0], "action": c[1], "y": y})
			y += 2
		if page == "controls":
			rows.append({"kind": Kind.ITEM, "label": "CONTROLLER BINDINGS", "action": "bindings", "y": y + 1})
		return
	match page:
		"replays":
			for replay in MwReplayFile.list():
				rows.append({"kind": Kind.LIST, "label": _replay_label(replay["header"]), "path": replay["path"],
						"info": replay["header"], "ok": replay["ok"], "y": 0})
		"saved_games":
			for slot in MwPlayoffSave.slots():
				rows.append({"kind": Kind.LIST, "label": "AUTOSAVE" if slot == MwPlayoffSave.AUTOSAVE
						else "SLOT %d" % slot,
						"slot": slot, "info": MwPlayoffSave.info(slot), "y": 0})
		"bindings":
			rows.append({"kind": Kind.CHOICE, "label": "PLAYER", "action": "player", "y": 6})
			rows.append({"kind": Kind.CHOICE, "label": "LAYOUT", "action": "layout", "y": 8})
			rows.append({"kind": Kind.CHOICE, "label": "CONTROLS", "action": "page", "y": 10})
			for v in MwVerbs.PAGES[bind_page][1]:
				if v == MwVerbs.VIEW_TOGGLE and player != 1:
					continue                 # player 1's only
				if MwInputMap.unused(player, v):
					continue                 # no use in the player's layout (the GENESIS pause menu's A / B)
				rows.append({"kind": Kind.BINDING, "label": MwVerbs.LABELS[v], "verb": v, "y": 0,
						"stick": MwVerbs.STICKS.has(v)})


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty():
		return
	if _menu_pass(elapsed):
		return
	if _drawn_full != MwSettings.fullscreen and capturing == "":
		_draw()                          # Alt+Enter changed it (plan 28)
	elif page == "bindings" and _devices != MwInputMap.devices_changed and capturing == "":
		_draw()                          # a gamepad came or went (plan 34)
	for i in elapsed:
		starfield.step()                 # VBlank task
	if _quit_left >= 0:
		_quit_left = maxi(_quit_left - elapsed, 0)
		if _quit_left == 0 and (fader == null or not fader.busy()):
			_quit_left = -2              # once
			quit_game.call()
		return
	if _quit_left == -2:
		return
	if capturing != "":
		_capture_left -= elapsed
		if _capture_left <= 0:
			capturing = ""               # nothing came: the binding stays
			_settle = true
			_draw()
		return
	if _settle:
		if (input != null and not input.held.is_empty()) or held_down(_bound):
			return
		_settle = false
		_bound = null
	idle += elapsed
	if input == null:
		return
	if not input.pressed.is_empty():
		idle = 0
	elif page == "main" and MwAttract.idle_out(idle):
		_attract()
		return
	if confirm != null and confirm.handle(input):
		return
	if input.is_pressed("ui_back"):
		_back()
	elif input.is_pressed("ui_delete") and page in ["saved_games", "replays"]:
		_delete()
	elif input.is_pressed("ui_keep") and page == "replays":
		_keep()
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


# --- actions -------------------------------------------------------------------------------------
func _move(d: int) -> void:
	row = posmod(row + d, rows.size())
	_scroll_to_row()
	_fill = true
	MwSound.play(SOUND_MOVE)
	_draw()


func _change(d: int) -> void:
	if page == "bindings":
		match rows[row].get("action", ""):
			"player":
				player = posmod(player - 1 + d, MwVerbs.PLAYERS) + 1
			"layout":
				var l := MwInputMap.LAYOUTS
				MwSettings.set_layout(player, l[posmod(l.find(MwSettings.layout(player)) + d, l.size())])
			"page":
				bind_page = posmod(bind_page + d, MwVerbs.PAGES.size())
				scroll = 0
			_:
				return
		_build_rows()                    # player 1 has the view switch
		row = mini(row, rows.size() - 1)
		_scroll_to_row()
	else:
		var setting: String = rows[row].get("action", "")
		if not MwSettings.SAVED.has(setting):
			return
		MwSettings.step(setting, d)          # (the 3D view follows the VISUALS at its next frame)
		MwSettings.save()
	_fill = true
	MwSound.play(SOUND_MOVE)
	_draw()


func _accept() -> void:
	_remember()
	if rows.is_empty():
		return
	var r := rows[row]
	if r.get("disabled", false):
		MwSound.play(SOUND_REFUSED)
		return
	match page:
		"main":
			match r.action:
				"start":
					exit_to(MwScreens.PLAY_MODE)
				"create":
					exit_to(MwScreens.CREATE_A_TEAM)
				"options":
					exit_to(MwScreens.OPTIONS)
				"teams":
					exit_to(2, {"browse": true})
				"replays":
					exit_to(MwScreens.REPLAYS)
				"credits":
					exit_to(0, {"credits": true})
				"quit":
					_quit()
		"play_mode":
			if r.action == "local":
				exit_to(MwScreens.LOCAL_PLAY)
			elif r.action == "online":
				exit_to(MwScreens.ONLINE)        # plan 35: the online pages
		"local_play":
			match r.action:
				"exhibition":
					_local_play("exhibition")
				"playoffs":
					_local_play("playoffs")
				"continue":
					exit_to(MwScreens.CONTINUE)
		"continue":
			match r.action:
				"load":
					exit_to(MwScreens.SAVED_GAMES, {"mode": "load"})
				"password":
					_password()
		"options":
			match r.action:
				"visuals":
					exit_to(MwScreens.VISUALS)
				"modifiers":
					exit_to(MwScreens.MODIFIERS)
				"controls":
					exit_to(MwScreens.CONTROLS)
		"controls":
			if r.action == "bindings":
				exit_to(MwScreens.BINDINGS)
		"saved_games":
			_saved_game(r)
		"replays":
			_replay(r)
		"bindings":
			if r.kind != Kind.BINDING:
				return
			capturing = r.verb
			_capture_left = CAPTURE_TICKS
			_draw()


## The game setup's top as its screen draws it when it comes in: the
## backdrop's window rows with their holes (the logo's, the strip above the
## skull: [method MwMainMenu._logo_apart]) in the window's colours before the
## torchlight flickers - the arch is palette line 3 (the screen's), its
## outer cells line 0 (the ice line) - [constant TOP_HANG] up, under the
## page's text and logo.
func _make_top() -> void:
	top = RomPlane.new()
	top.name = "TopPlane"
	top.tiles = plane.tiles
	var pal := palette.duplicate() as RomPalette
	if session:
		pal.team_a = session.setup.team_a
		pal.team_b = session.setup.team_b
		pal.stadium = session.setup.stadium
	pal.steps = PackedStringArray(["screen_palette", "black 0", "ice_line"])
	top.palette = pal
	add_child(top)
	move_child(top, page_layers.get_index())
	MwPlanePainter.map_rows(top, rom, BACKDROP, 0, MwMainMenu.BACKDROP_ROWS, 0)
	for r: Rect2i in [LOGO, MwMainMenu.SKULL_STRIP]:
		MwPlanePainter.fill(top, r.position.x, r.position.y, r.size.x, r.size.y, 0x8000)
	top.position.y = -TOP_HANG


## The starfield where the game setup left it (Back there: a cut).
func _restore_starfield() -> void:
	starfield.restore(session.menu_stars)


## EXHIBITION / PLAYOFFS: the game setup in that variant (plan 34); the
## title's music fades as the original's START did. A cut, not a fade
## (owner): the logo stays where it is and the game setup's frame crashes
## down around it; the starfield goes on where it was.
func _local_play(mode: String) -> void:
	if session:
		session.local_mode = mode
		if mode == "playoffs":
			session.drop_run()                  # a new run: made when its first game starts
	MwSound.music_fade_out(32)
	_leave_by_cut(1, {"cut": true})            # the page's text out, then the cut (the stars saved then)


## PASSWORD: the original's way in - the game setup's CONTINUE play mode,
## its Start (`$11D8E`: no new run), the playoffs screen asking for the
## password over the bracket.
func _password() -> void:
	if session:
		session.local_mode = "playoffs"
		session.setup.play_mode = MwPlayoffs.MODE_CONTINUE
		session.playoffs.start(session.setup, session.rng)
	MwSound.music_fade_out(32)
	exit_to(11)


## QUIT GAME: the screen and the music fade out, then [member quit_game].
func _quit() -> void:
	_quit_left = QUIT_TICKS
	MwSound.music_fade_out(QUIT_TICKS)
	if fader:
		fader.fade_out(QUIT_TICKS)


## Menu Back: one screen up.
func _back() -> void:
	_remember()
	if page == "main":
		exit_to(0, {"title": true})
	elif page == "saved_games" and list_mode == "save":
		exit_to(1)                           # back to the game setup's SAVE GAME
	elif UP.has(page):
		exit_to(UP[page])


# --- the saved games (plan 34) ------------------------------------------------------------------
## Accept on a slot: LOAD GAME takes a save (the run's bracket next); SAVE
## GAME writes an empty slot, or a used one after OVERWRITE?. The autosave
## is written by the game alone.
func _saved_game(r: Dictionary) -> void:
	var info: Dictionary = r.info
	if list_mode == "load":
		if info.is_empty() or not info.ok or not MwPlayoffSave.load_into(session, r.slot):
			MwSound.play(SOUND_REFUSED)
			return
		MwSound.music_fade_out(32)
		exit_to(MwFlow.after_load(session), {"loaded": true})
		return
	if r.slot == MwPlayoffSave.AUTOSAVE:
		MwSound.play(SOUND_REFUSED)
		return
	if info.is_empty():
		_write(r.slot)
	else:
		_asked = "overwrite"
		confirm.open("OVERWRITE THIS SAVE")


## DELETE on a used slot or a replay: after ARE YOU SURE?.
func _delete() -> void:
	if rows.is_empty() or rows[row].kind != Kind.LIST or (rows[row].info as Dictionary).is_empty():
		MwSound.play(SOUND_REFUSED)
		return
	_asked = "delete"
	confirm.open("DELETE THIS REPLAY" if page == "replays" else "DELETE THIS SAVE")


func _answered(yes: bool) -> void:
	var what := _asked
	_asked = ""
	if not yes or rows.is_empty():
		_draw()
		return
	match what:
		"overwrite":
			_write(rows[row].slot)
		"delete":
			if page == "replays":
				MwReplayFile.delete(rows[row].path)
			else:
				MwPlayoffSave.delete(rows[row].slot)
			MwSound.play(SOUND_MOVE)
			_build_rows()
			row = clampi(row, 0, maxi(rows.size() - 1, 0))
			_scroll_to_row()
			_draw()


func _write(slot: int) -> void:
	if not MwPlayoffSave.save(session, slot):
		MwSound.play(SOUND_REFUSED)
		return
	MwSound.play(SOUND_MOVE)
	_remember()
	exit_to(1)


## What a slot's line shows: EMPTY, or the run's team (its name, read
## from the ROM) and its round; a custom team's run whose team is off or
## deleted says so (MwPlayoffSave.info's "why").
func _slot_value(info: Dictionary) -> String:
	if info.is_empty():
		return "EMPTY"
	if not info.ok:
		return str(info.get("why", "")) if str(info.get("why", "")) != "" else "UNREADABLE"
	var team_name := MwTeams.name_text(rom, int(info.team_a))
	return "%s  %s" % [team_name, ROUND_NAMES[int(info.round) & 3]]


## [param unix] as the player's clock reads it.
static func local_time(unix: int) -> Dictionary:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_dict_from_unix_time(unix + 60 * bias)


## The selected slot's detail: when it was saved, and the password the
## original showed then.
func _slot_detail(info: Dictionary) -> String:
	if not info.is_empty() and str(info.get("why", "")) == "TEAM IS OFF":
		return "SWITCH IT ON IN CREATE-A-TEAM"
	if info.is_empty() or not info.ok:
		return ""
	var t := local_time(int(info.time))
	var when := "%02d %s %d %02d:%02d" % [t.day, MONTHS[int(t.month) - 1], t.year, t.hour, t.minute]
	return when + ("  " + str(info.password) if str(info.password) != "" else "")


# --- the replays (plan 34) ---------------------------------------------------------------------
## Accept on a replay: screen 7 plays it (its saved variant), back here
## after; another ROM's or version's file is refused.
func _replay(r: Dictionary) -> void:
	if not r.ok:
		MwSound.play(SOUND_REFUSED)
		return
	MwSound.music_fade_out(32)
	exit_to(7, {"replay_file": r.path})


## KEEP on a recorded demo: out of the demos' limit (it stays when newer
## demos come). Refused on the others.
func _keep() -> void:
	if rows.is_empty() or rows[row].kind != Kind.LIST:
		return
	var h: Dictionary = rows[row].info
	if h.get("mode") != "demo" or h.get("kept", false) or not MwReplayFile.keep(rows[row].path):
		MwSound.play(SOUND_REFUSED)
		return
	MwSound.play(SOUND_MOVE)
	_build_rows()
	_draw()


## A replay's line: the teams (their names, read from the ROM) and the score
## (plan 45: read through MwPlain - a shared file's header, MwReplayFile.plain_header).
func _replay_label(h: Dictionary) -> String:
	var score := MwPlain.ints(h.get("score"))
	if score.size() != 2:
		score = PackedInt32Array([0, 0])
	var names := MwPlain.array(h.get("names"))
	if names.size() == 2:                  # plan 38: the names as they were (custom teams change)
		return "%s %d-%d %s" % [MwPlain.text(names[0]).to_upper(), score[0], score[1],
				MwPlain.text(names[1]).to_upper()]
	return "%s %d-%d %s" % [_team_name(MwPlain.num(h.get("team_a"))), score[0], score[1],
			_team_name(MwPlain.num(h.get("team_b")))]


func _team_name(team: int) -> String:
	if rom.is_empty() or team < 0 or team >= MwCustomTeams.readable():
		return "?"
	return MwTeams.name_text(rom, team)


## A replay's value: the time it was saved (UNREADABLE: another ROM's or
## version's).
func _replay_value(r: Dictionary) -> String:
	if not r.get("ok", false):
		return "UNREADABLE"
	var t := local_time(int(r.info.get("time", 0)))
	return "%02d:%02d" % [t.hour, t.minute]


## The selected replay's detail: the day, the mode (the playoffs' round;
## DEMO for the demos, KEPT once kept) and how long the recording runs.
static func replay_detail(h: Dictionary) -> String:
	var t := local_time(int(h.get("time", 0)))
	var mode := str(h.get("mode", "")).to_upper()
	match str(h.get("mode", "")):
		"playoffs":
			mode = ROUND_NAMES[int(h.get("round", 0)) & 3]
		"demo":
			mode = "DEMO KEPT" if h.get("kept", false) else "DEMO"
	var secs := int(h.get("ticks", 0)) / 60
	return "%02d %s %d  %s  %d:%02d" % [t.day, MONTHS[int(t.month) - 1], t.year, mode, secs / 60, secs % 60]


## Idle on the front menu: the attract demo, as the game setup's idle does
## (`$138BE`: as if Start was pressed, then the matchup with the demo setup);
## the demo comes back here.
func _attract() -> void:
	session.attract = true
	session.attract_return = MwScreens.FRONT_MENU
	session.playoffs.start(session.setup, session.rng)     # `$11D8E`, as the game setup's Start
	MwSound.music_fade_out(32)
	exit_to(3)


func _remember() -> void:
	if session:
		session.screens[screen_id] = {"row": row, "player": player, "bind_page": bind_page, "mode": list_mode}


## Binding capture: the next input pressed, from any device.
func _input(event: InputEvent) -> void:
	if capturing == "" or event.is_echo() or not event.is_pressed():
		return
	var captured := MwInputMap.normalized(event)
	if captured == null:
		return
	get_viewport().set_input_as_handled()
	take_binding(captured)


## Binds [param event] to the verb waiting for one (also tests). A stick row
## takes a stick moved (the whole stick: MwSettings.set_stick); a key or a
## button there gives up.
func take_binding(event: InputEvent) -> void:
	if capturing == "":
		return
	if MwVerbs.STICKS.has(capturing):
		if MwInputMap.stick_axes(event).is_empty():
			if event is InputEventJoypadMotion:
				return                       # a trigger, or a stick barely moved: still waiting
			capturing = ""
			_settle = true
			_bound = event
			_draw()
			return
		MwSettings.set_stick(player, capturing, event)
	else:
		MwSettings.set_binding(player, capturing, event)
	capturing = ""
	_settle = true
	_bound = event
	_fill = true
	MwSound.play(SOUND_MOVE)
	_draw()


## True while [param event] (a binding: key, gamepad button or stick direction)
## is held down. A key held after it was bound repeats, and the repeats are
## presses of the actions it now drives (Godot counts echoes), so the menu
## waits for the input itself, not just for its actions.
static func held_down(event: InputEvent) -> bool:
	if event is InputEventKey:
		return Input.is_physical_key_pressed(event.physical_keycode)
	if event is InputEventJoypadButton:
		return Input.is_joy_button_pressed(event.device, event.button_index)
	if event is InputEventJoypadMotion:
		return Input.get_joy_axis(event.device, event.axis) * signf(event.axis_value) >= MwInputMap.DEADZONE / 2.0
	return false


# --- drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	_drawn_full = MwSettings.fullscreen
	_devices = MwInputMap.devices_changed
	_partners = []
	_clear(plane)
	_clear(half_plane)
	_clear(_plate)
	_clear(_dim)
	match page:
		"main":
			# the logos: their own layers (logo_plane, weenie); the version, bottom right
			var v := _ascii(version_text())
			var y := version_top()
			MwGlyphs.text(_on(_dim, y & 7), rom, FONT_LIGHT, v, VERSION_RIGHT + 1 - _width(FONT_LIGHT, v), y >> 3,
					TEXT_ATTR)
		"bindings":
			_clear_red()
			_clear(_pair)
			_centred(TITLES[page], BINDINGS_TITLE_Y, FONT_LIGHT, true)
			_collisions = MwInputMap.collisions()
			_partners = _pair_rows(row)
		_:
			_clear_red()                      # VISUALS: ABACABB MODE's red label (the online pages redraw theirs after)
			_centred(label_text(rom, page_title()), OPTIONS_TITLE_Y, FONT_LIGHT, true)
	for i in rows.size():
		var r := rows[i]
		if r.kind == Kind.BINDING:
			var k := i - _first_verb() - scroll
			if k < 0 or k >= VERBS_SHOWN:
				continue                     # scrolled out
			r.y = VERB_Y + 2 * k
		elif r.kind == Kind.LIST:
			var k := i - scroll
			if k < 0 or k >= LIST_SHOWN:
				continue
			r.y = LIST_Y + 2 * k
		elif r.kind == Kind.CHOICE and _choices_scroll():
			var k := i - scroll
			if k < 0 or k >= CHOICES_SHOWN:
				continue                     # scrolled out (plan 44)
			r.y = CHOICE_Y + 2 * k
		_draw_row(i, i == row)
	if page == "saved_games" and not rows.is_empty():
		_centred(_slot_detail(rows[row].info), DETAIL_Y, FONT_LIGHT)
	elif page == "replays":
		if rows.is_empty():
			_centred("NO REPLAYS YET", LIST_Y, FONT_LIGHT)
		else:
			_centred(replay_detail(rows[row].info), DETAIL_Y, FONT_LIGHT)
	_fill = false
	_draw_arrows()


## The hint that verbs can share an input (owner, 2026-10-09: the verbs that
## share an input by default get a dark border round the label alone while
## any of them is selected, and then the grey ground behind the text too):
## while the selected verb is one of the original's one-button meanings
## (MwVerbs.GROUPS: a button's tap, hold and other situation, on its input
## by default - bound together they keep the original's tap / hold timing,
## apart each acts at once), each other one's [param label] at cell
## ([param x], [param y]) is drawn as the highlight draws its own - the
## frame filled, the dark font - round the label alone, on a plane under
## the main one at [constant PAIR_DARK]. Their rows come into view with it
## ([method _scroll_to_row]).
func _draw_partner(label: PackedByteArray, x: int, y: int, dy := 0) -> void:
	var on := _on(_pair, dy)
	MwPlanePainter.frame(on, rom, x, y, _width(FONT_DARK, label), 1, true)
	MwGlyphs.text(on, rom, FONT_DARK, label, x, y, TEXT_ATTR)


## The rows of the verbs that share row [param i]'s input by default (its
## MwVerbs.GROUPS group, its own row included); empty for any other row.
func _pair_rows(i: int) -> Array[int]:
	var out: Array[int] = []
	if i < 0 or i >= rows.size() or rows[i].kind != Kind.BINDING:
		return out
	var group: Array = []
	for g in MwVerbs.GROUPS:
		if rows[i].verb in g:
			group = g
	if group.is_empty():
		return out
	for j in rows.size():
		if rows[j].kind == Kind.BINDING and rows[j].verb in group:
			out.append(j)
	return out


## The scroll arrows: up while verbs are hidden above, down while below,
## the ones shown centred on the screen together.
func _draw_arrows() -> void:
	if _arrows.is_empty():
		return
	var lines := rows.size() - _first_verb()
	var room := VERBS_SHOWN
	var arrows_top := ARROW_TOP
	var shown := page == "bindings"
	if not rows.is_empty() and rows[0].kind == Kind.LIST:
		lines = rows.size()                  # the list pages (plan 34)
		room = LIST_SHOWN
		arrows_top = LIST_ARROW_TOP
		shown = true
	elif _choices_scroll():
		lines = rows.size()                  # a long choice page (plan 44)
		room = CHOICES_SHOWN
		shown = true
	shown = shown and lines > room
	MwScrollArrows.place(_arrows, rom, shown and scroll > 0, shown and scroll + room < lines, arrows_top)


## Plan 44: whether this choice page has more rows than it holds
## ([constant CHOICES_FIT]): it scrolls ([constant CHOICES_SHOWN]).
func _choices_scroll() -> bool:
	return CHOICES.has(page) and (CHOICES[page] as Array).size() > CHOICES_FIT


## The index of the bindings page's first verb row.
func _first_verb() -> int:
	for i in rows.size():
		if rows[i].kind == Kind.BINDING:
			return i
	return rows.size()


## Keeps the selected verb row inside the shown ones.
func _scroll_to_row() -> void:
	if not rows.is_empty() and rows[0].kind == Kind.LIST:
		scroll = MwScrollArrows.follow(scroll, row, LIST_SHOWN)
		return
	if _choices_scroll():
		scroll = MwScrollArrows.follow(scroll, row, CHOICES_SHOWN, rows.size())
		return
	if page != "bindings":
		return
	var k := row - _first_verb()
	scroll = 0 if k < 0 else MwScrollArrows.follow(scroll, k, VERBS_SHOWN)
	# the selected verb's partners come into view with it ([method _draw_partner])
	var pairs := _pair_rows(row)
	if not pairs.is_empty():
		var last: int = pairs.max() - _first_verb()
		var first: int = pairs.min() - _first_verb()
		if last >= scroll + VERBS_SHOWN:
			scroll = last - VERBS_SHOWN + 1
		if first < scroll:
			scroll = first


## The logo cut from the game setup's backdrop, from row [param y].
func _logo(y: int) -> void:
	MwMenuBackdrop.logo(logo_plane, rom, LOGO_AT.x, y)      # plan 40 (M5)


## Row [param i] (every page's, one way): on its cell row ("y"), and when
## its line falls between the tile rows ("dy" pixels below the cell row:
## the main page's items) on the layers' twins moved down that far
## ([method _on]) - the highlight frame with it.
func _draw_row(i: int, selected: bool) -> void:
	var r := rows[i]
	var y: int = r.y
	var dy: int = r.get("dy", 0)
	var centred_item: bool = r.kind == Kind.ITEM and (ITEMS.has(page) or r.get("centred", false))
	var x0 := _half(40 - _item_w) if centred_item else ROW_X
	var w := _item_w if centred_item else ROW_W
	MwMenuRow.frame(_on(plane, dy), rom, x0, y, w, selected)      # plan 40 (M1): MwMenuRow's look
	var font := MwMenuRow.font(selected)
	var label := _ascii(r.label)
	if r.kind == Kind.ITEM:
		var dim: bool = r.get("disabled", false)
		_text_centred(label, 2 * x0 + w, y, font, false, _dim if dim else null, dy)
		return
	if not selected and i in _partners:
		_draw_partner(label, x0, y, dy)      # the pair hint
	elif r.get("action", "") == "blood" and MwSettings.blood:
		# owner, 2026-10-11: the ABACABB MODE label red while it is on, white
		# while off: the light font's white letters tinted red; selected, the
		# dark font's black letters screened red with its bar left white
		# (tinted, the bar would go red with them)
		MwGlyphs.text(_on(_red_for(selected), dy), rom, font, label, x0, y, TEXT_ATTR)
	else:
		_text(label, x0, y, font, dy)
	var value := MwMenuRow.cut(rom, font, _ascii(_value(r)), MwMenuRow.room(rom, font, label, w))
	var on := plane
	if r.kind == Kind.BINDING and _collided(r) and capturing != r.verb:
		on = _red_for(selected)              # the input is another verb's too, on some screen
	elif r.get("action", "") == "player" and not MwInputMap.connected(player):
		on = _dim                            # plan 34: the player's gamepad isn't there
	on = _on(on, dy)
	if r.kind == Kind.BINDING and capturing != r.verb and not MwGlyphs.tiles().is_empty():
		var parts := stick_parts(player, r.verb) if r.get("stick", false) else binding_parts(player, r.verb)
		_parts(on, parts, x0 + w, y, font, MwGlyphs.Style.SELECTED if selected else MwGlyphs.Style.NORMAL)
		return
	MwGlyphs.text(on, rom, font, value, x0 + w - _width(font, value), y, TEXT_ATTR)


## Draws [param parts] ([method binding_parts]) right-aligned to cell
## [param right] on row [param y]: glyphs on the row's cells, tags and
## names in [param font].
func _parts(on: RomPlane, parts: Array, right: int, y: int, font: int, style: int) -> void:
	var total := 0
	for part in parts:
		total += _part_width(part, font, style)
	var x := right - total
	var cell_row := MwPrompts.row(rom, font, y)
	for part in parts:
		if part.has("glyph"):
			MwGlyphs.put_cells(on, MwGlyphs.cells(part["glyph"], style), x, cell_row)
		else:
			MwGlyphs.text(on, rom, font, _ascii(part["text"]), x, y, TEXT_ATTR)
		x += _part_width(part, font, style)


func _part_width(part: Dictionary, font: int, style: int) -> int:
	if part.has("glyph"):
		return MwGlyphs.cells(part["glyph"], style).size()
	return _width(font, _ascii(part["text"]))


## True when row [param r]'s input collides (MwInputMap.collisions): a
## verb's own binding, or a stick row's axes.
func _collided(r: Dictionary) -> bool:
	if r.get("stick", false):
		for v in MwVerbs.STICKS[r.verb]:
			if _collisions.has(MwVerbs.player_key(player, v) + MwInputMap.STICK_MARK):
				return true
		return false
	return _collisions.has(MwVerbs.player_key(player, r.verb))


## What a row shows on its right.
func _value(r: Dictionary) -> String:
	match r.kind:
		Kind.CHOICE:
			match r.action:
				"player":
					return "%d  %s" % [player, MwInputMap.device_tag(player)]   # plan 34: whose device
				"layout":
					return MwSettings.layout(player)
				"page":
					return MwVerbs.PAGES[bind_page][0]
			return MwSettings.text(r.action)
		Kind.LIST:
			if page == "saved_games":
				return _slot_value(r.info)
			if page == "replays":
				return _replay_value(r)
			return str(r.get("value", ""))
		Kind.BINDING:
			if capturing == r.verb:
				return "MOVE A STICK" if r.get("stick", false) else "PRESS ANY INPUT"
			if r.get("stick", false):
				return stick_text(player, r.verb)
			return binding_text(player, r.verb)
	return ""


## [param verb]'s inputs for player [param p] as the menu draws them with
## glyphs (plan 23): the first key's cap, " + " (owner: a separator between
## a verb's inputs), then the first gamepad input's tag ("XB1"; owner: none
## for the keyboard - there is one) and glyph; an input without a glyph by
## its name. Parts: {glyph} or {text}.
static func binding_parts(p: int, verb: String) -> Array:
	var bound := MwSettings.binding(p, verb)
	var events: Array[InputEvent] = MwInputMap.default_events(p, verb)
	if bound != null:
		events = [bound]
	var key: InputEvent = null
	var pad: InputEvent = null
	for event in events:
		if event is InputEventKey and key == null:
			key = event
		elif not event is InputEventKey and pad == null:
			pad = event
	var out := []
	for e in [key, pad]:
		if e == null:
			continue
		if not out.is_empty():
			out.append({"text": SEPARATOR})
		out.append_array(event_parts(e))
	return out if not out.is_empty() else [{"text": "NONE"}]


## One input's parts: a gamepad's tag first (owner: the device before the
## glyph), then its glyph (a stick direction: the stick's and the
## direction's); its name when it has no glyph.
static func event_parts(event: InputEvent) -> Array:
	var out := []
	var glyphs := MwGlyphs.stick_glyphs(event)
	if glyphs.is_empty():
		var g := MwGlyphs.glyph_of(event)
		if g != "":
			glyphs.append(g)
	if glyphs.is_empty():
		return [{"text": MwInputMap.event_name(event)}]
	if not event is InputEventKey:
		out.append({"text": MwGlyphs.tag(event.device) + " "})
	for g in glyphs:
		out.append({"glyph": g})
	return out


## A stick row's parts: its gamepad's tag and the stick's glyph (LS / RS),
## or the up direction's input when the four aren't one stick's axes.
static func stick_parts(p: int, stick_set: String) -> Array:
	var verbs: Array = MwVerbs.STICKS[stick_set]
	var up := MwInputMap.stick_events(p, verbs[0])
	if up.is_empty():
		return [{"text": "NONE"}]
	var t := stick_text(p, stick_set)
	if t.ends_with(" LS") or t.ends_with(" RS"):
		return [{"text": MwGlyphs.tag(up[0].device) + " "}, {"glyph": "pad:" + t.right(2)}]
	return event_parts(up[0])


## Stick set [param stick_set] (MwVerbs.STICKS) of player [param p] as the
## menu shows it: the gamepad and stick ("PAD1 LS"), or its up input when
## the four aren't one stick's axes; "NONE".
static func stick_text(p: int, stick_set: String) -> String:
	var verbs: Array = MwVerbs.STICKS[stick_set]
	var ev: Array[InputEvent] = []
	for v in verbs:
		var events := MwInputMap.stick_events(p, v)
		if events.is_empty():
			return "NONE"
		ev.append(events[0])
	var axes := MwInputMap.stick_axes(ev[0])
	var whole := not axes.is_empty()
	for i in 4:
		var m := ev[i] as InputEventJoypadMotion
		whole = whole and m.device == ev[0].device and m.axis == axes[1 if i < 2 else 0] \
				and m.axis_value == (-1.0 if i % 2 == 0 else 1.0)
	if not whole:
		return MwInputMap.event_name(ev[0])
	return "PAD%d %s" % [ev[0].device + 1, "LS" if axes[0] == JOY_AXIS_LEFT_X else "RS"]


## The inputs of [param verb] for player [param p] as the menu shows them:
## the bound one, or the layout's defaults (the first key and the first
## gamepad input).
static func binding_text(p: int, verb: String) -> String:
	var bound := MwSettings.binding(p, verb)
	if bound != null:
		return MwInputMap.event_name(bound)
	var names := PackedStringArray()
	var key := false
	var pad := false
	for event in MwInputMap.default_events(p, verb):
		if event is InputEventKey and not key:
			names.append(MwInputMap.event_name(event))
			key = true
		elif not event is InputEventKey and not pad:
			names.append(MwInputMap.event_name(event))
			pad = true
	return " / ".join(names) if not names.is_empty() else "NONE"


## The page's title ([constant TITLES]; the saved games' says what they're for).
func page_title() -> String:
	if page == "saved_games":
		return "SAVE GAME" if list_mode == "save" else "LOAD GAME"
	return TITLES.get(page, "")


## [param text] as shown: the original's words read from the ROM for "@mode:N"
## (the game setup's play mode value N) and "@row:N" (row N's label), a
## trailing "+S" adding an S; anything else as it is.
static func label_text(rom_bytes: PackedByteArray, text: String) -> String:
	if not text.begins_with("@") or rom_bytes.is_empty():
		return text
	var plus := text.ends_with("+S")
	var key := text.trim_suffix("+S")
	var menu_rows := MwMenuRows.new(rom_bytes)
	var n := int(key.get_slice(":", 1))
	var at := menu_rows.string_of(MwMenuRows.PLAY_MODE_ROW, 1, n) if key.begins_with("@mode:") \
			else menu_rows.string_of(n, 0, 0)
	return MwGfx.rom_string(rom_bytes, at).get_string_from_ascii() + ("S" if plus else "")


func _centred(text: String, y: int, font: int, plate := false) -> void:
	_text_centred(_ascii(text), 40, y, font, plate)


## [param b] centred on [param twice_centre] / 2 cells, to half a cell: an odd
## leftover goes on the plane shifted 4 pixels right. [param plate]: on the
## pause menu's plate (MwGlyphs.black_label, its player line), on the
## title's own layer in the plate's grey (shifted the same way) - the
## pages' titles, one a page. [param on]: a tinted layer instead (a dim
## item), shifted the same way. [param dy]: a row between the tile rows
## ([method _on]).
func _text_centred(b: PackedByteArray, twice_centre: int, y: int, font: int, plate := false,
		on: RomPlane = null, dy := 0) -> void:
	if plate:
		MwGlyphs.plate_title(_on(_plate, dy), rom, font, b, y, TEXT_ATTR, twice_centre)    # plan 40 (M2)
		return
	var c := MwMenuRow.centred_x(rom, font, b, twice_centre)
	var x := c.x
	if on != null:
		var layer := _on(on, dy)
		layer.position.x = 4 * c.y
		MwGlyphs.text(layer, rom, font, b, x, y, TEXT_ATTR)
	else:
		MwGlyphs.text(_on(half_plane if c.y != 0 else plane, dy), rom, font, b, x, y, TEXT_ATTR)


func _text(b: PackedByteArray, x: int, y: int, font: int, dy := 0) -> void:
	MwGlyphs.text(_on(plane, dy), rom, font, b, x, y, TEXT_ATTR)


## [param layer] for a row on the tile rows; for one whose line falls
## [param dy] pixels (1-7) below its cell row - the main page's items
## ([method item_top]; owner, 2026-10-10: they need not keep to the tile
## grid) - the layer's twin moved down that far: its tiles, palette, tint
## and place, made when first drawn on, right over it (the page's layers
## keep their order) and cleared with it ([method _clear]). Rows sharing
## an offset share the twin, as rows on the tile rows share the layer.
func _on(layer: RomPlane, dy: int) -> RomPlane:
	if dy == 0:
		return layer
	var twins: Dictionary = _twins.get(layer, {})
	if not twins.has(dy):
		var twin := layer.duplicate() as RomPlane
		twin.clear()
		twin.name = "%sDown%d" % [layer.name, dy]
		twin.position = layer.position + Vector2(0, dy)
		var parent := layer.get_parent()
		parent.add_child(twin)
		var at := layer.get_index()
		for earlier: RomPlane in twins.values():
			at = maxi(at, earlier.get_index())
		parent.move_child(twin, at + 1)
		twins[dy] = twin
		_twins[layer] = twins
	return twins[dy]


## The red layer for a row's text: [member _red] off the highlight (the light
## font's white letters tinted red), [member _red_ink] on it (the dark font's
## black letters screened red, its bar left white - tinted, the bar would go
## red with them). ABACABB MODE's label while on, a binding's input that is
## another verb's too.
func _red_for(selected: bool) -> RomPlane:
	return _red_ink if selected else _red


## Clears both red layers ([method _red_for]) and their twins.
func _clear_red() -> void:
	_clear(_red)
	_clear(_red_ink)


## Clears [param layer] and its twins ([method _on]).
func _clear(layer: RomPlane) -> void:
	layer.clear()
	for twin: RomPlane in (_twins.get(layer, {}) as Dictionary).values():
		twin.clear()


## Cells of [param b] in [param font] ("+" included: [method MwGlyphs.text]).
func _width(font: int, b: PackedByteArray) -> int:
	return MwGlyphs.text_width(rom, font, b)


static func _half(v: int) -> int:
	@warning_ignore("integer_division")
	return v / 2


static func _ascii(text: String) -> PackedByteArray:
	return text.to_ascii_buffer()
