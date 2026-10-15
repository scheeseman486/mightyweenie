class_name MwSettings
extends RefCounted
## The port's options (plan 21; owner, 2026-10-08), kept in
## `user://settings.cfg` and saved whenever the options menus change one:
##
## * [member camera]: the view every match starts in ([constant CAMERAS]: 2D,
##   3D - the follow camera -, 2D EXTENDED - the orthographic view zooming
##   to keep the human players' characters and the puck in the picture,
##   plan 44 - or 3D EXTENDED - the follow camera zooming so, plan 34; the
##   matchup sets [member MwSession.view] from it), and with it whether the
##   match is an EXTENDED one ([method extended_play]). Plan 20's other
##   views stay on the F keys, debug views for now (owner).
## * [member enhance_audio]: plan 12's enhancement switches
##   ([member MwAudio.free_music_samples], [member MwAudio.free_effects]),
##   plan 31's crowd noise and plan 39's organ pool ([member MwAudio.organ_pool]).
## * [member fullscreen]: the window full screen or windowed.
## * [member layouts], [member bindings], [member sticks]: each player's
##   layout (MwInputMap: STANDARD or GENESIS), the verbs they rebound, one
##   input each (plan 22: bindings are per verb), and the sticks they rebound
##   (a stick drives the direction verbs besides their D-pad binding). The
##   function keys are never bound: they stay the rink's views (plan 20,
##   debug views - owner).
## * [member analogue]: a stick steers and sets the pace (plan 22, owner: on
##   by default); off: the original's 8 directions at full speed.
## * [member shot_heights]: the shot's height on inputs of its own in the
##   STANDARD layout (owner, 2026-10-09; MwVerbs.SHOT_HEIGHTS); off (the
##   default): the original's - the D-pad's Up / Down lift the shot.
## * [member replay_length]: the instant replay's reach (plan 28, owner: the
##   whole game's length): FULL GAME (the default) or ORIGINAL (the last
##   play, as the original's ring holds it).
## * [member tick_rate]: the rink's pass lengths (plan 36, owner): OVERCLOCKED
##   (a pass every 2 ticks, 30 a second, the default), APPROXIMATED or
##   ORIGINAL (each pass as long as the original's 68000 would take,
##   MwPassPacer: 3.8 ticks on average; ORIGINAL with the running sound
##   driver's work, APPROXIMATED in integers with the driver at its mean -
##   the same on every machine, so online play forces it for ORIGINAL:
##   [method rink_tick_rate]). On-rink gameplay only; the menus and the
##   other screens keep their pace.
## * [member front_menu]: the port's own main menu after the title (screens
##   100-102, `scenes/port_menu/`); off: the original's title -> credits ->
##   game setup. Not in the menus (tests and comparisons turn it off).
## * [member team_name_colours]: team names in the big font each in its own
##   team's colours, the score panel's scores light grey (owner,
##   2026-10-09); off: the original's. Not in the menus.
## * [member character_select], [member captain_mode], [member lineup_select]
##   (plan 34, GAMEPLAY MODIFIERS): when players pick their characters (5+
##   players, or also 3+ on a team), how many players make a local playoff
##   game a captains' game (5+ or 2+), and whether players and captains
##   choose the line-up before the game when Reserves are on.
## * [member net_port], [member net_address] (plan 35, the online pages):
##   the last port hosted on and address joined (passwords are never kept).
## * [member goal_song_carries]: the goal song plays to its end in the goal
##   scoreboard when the rink is left before it ends; the scoreboard's crowd
##   or music then fades in (owner, 2026-10-09); off: the original's (the
##   rink's exit stops every sound). Not in the menus.
## * [member flat_shadows]: in 3D, the shadows drawn into the rink's sprites
##   laid flat on the ice beneath them, black over black, none in the bench
##   area (owner, 2026-10-09, MwFlatShadows); off: the original's dithers in
##   the frames. 2D is always the original's. Not in the menus.
## * [member blood], [member ice_detail], [member reflections] (plan 37, 3D
##   only; owner, 2026-10-11, the VISUALS page's ABACABB MODE, DETAILED ICE
##   and REFLECTIONS): the blood and oil painted on the arena and in flight,
##   the ice's own detail, the ice as a mirror - what the 3D view draws, never
##   what the paint's model does ([member splatter], always running), so a
##   match, its replays and the demos record the same whatever they are.
## * [member replay_paint] (GAMEPLAY MODIFIERS' REPLAY BLOOD; owner,
##   2026-10-15): whether the 3D replays show that paint as it was. Off by
##   default; drawing only, as the others (the matches record it all the same).
## * [member splatter] (plan 37): the paint's model itself. Not in the menus.
##
## Everything is static: one set of settings per run of the game.
##
## Plan 35 (docs/net.md, the settings' classes): a setting that changes the
## game's logic or flow is a **match rule** ([constant MATCH_RULES]) - an
## online match takes the host's ([method match_rules] into the start
## record, [method use_match_rules] on every machine, [method
## own_match_rules] after); the rest are **local** ([constant LOCAL]: the
## picture, the window, the controls), each machine's own. A player's
## controller layout changes the logic too (RECLAIM, the pause menu): it
## travels with the player in the start record's player table
## (MwSession.layouts).

const PATH := "user://settings.cfg"
## The views a match can start in: the original's 2D, 3D (owner: plan 20's
## follow camera; its other views are reached with the F keys only), 2D
## EXTENDED (plan 44: the orthographic view framing the human players'
## characters and the puck) or 3D EXTENDED (plan 34: the follow camera
## framing them). The EXTENDED two make an EXTENDED match (plan 44,
## [method extended_play]); player 1's VIEW switch goes between the 2D and
## the 3D of the match's group (MwRinkViews.toggled). The file keeps the
## text (an older file's "3D EXTENDED" is still 3D EXTENDED).
const CAMERAS: Array[String] = ["2D", "3D", "2D EXTENDED", "3D EXTENDED"]
const CAMERA_VIEWS: Array[int] = [MwRinkViews.FLAT, MwRinkViews.FOLLOW, MwRinkViews.EXTENDED_2D,
		MwRinkViews.EXTENDED]
## Plan 21's per-button bindings (an older settings file): each becomes the
## bindings of the verbs on that Genesis button ([method load_file]).
const OLD_BUTTONS: Array[String] = ["UP", "DOWN", "LEFT", "RIGHT", "A", "B", "C", "START", "BACK", "VIEW"]

## [member aspect]'s values (the options' ASPECT RATIO), the default first.
const ASPECTS: Array[String] = ["ORIGINAL", "WIDE"]
## [member replay_length]'s values (the options' REPLAY LENGTH), the default first.
const REPLAYS: Array[String] = ["FULL GAME", "ORIGINAL"]
## [member character_select]'s values (plan 34; owner): character selection
## comes with more than 4 players on teams, or also with 3 or 4 on one team
## when there are 4 or fewer in all. The default first.
const CHARACTER_SELECTS: Array[String] = ["5+ PLAYERS", "3+ ON A TEAM"]
## [member captain_mode]'s values (plan 34; owner: 5+ players or 2+ players):
## how many players on teams make a local playoff game a captains' game. The
## default first.
const CAPTAIN_MODES: Array[String] = ["5+ PLAYERS", "2+ PLAYERS"]

## Plan 35: the match rules (see the class notes). [code]opening_view[/code]:
## the view (MwRinkViews) whose flow the match's opening takes (2D: 300
## ticks or a press, then a fade; 3D: the players' show until a press,
## plan 33) - [method view] when the rules are a machine's own;
## [code]idle_attract[/code]: the main menu's idle timeout into the attract
## demo (MwAttract.idle_attract; off online); [code]tick_rate[/code]: the
## rink's pass lengths (plan 36: the host's TICK RATE, ORIGINAL played as
## APPROXIMATED online - [method rink_tick_rate]); [code]extended_play[/code]
## (plan 44): an EXTENDED match - the players humans drive count as on the
## original's screen wherever they are (MwRinkState.extended_play): this
## machine's CAMERA in the EXTENDED group, always online
## (MwNetMatch.online_rules); [code]extended_penalties[/code] (plan 44,
## GAMEPLAY MODIFIERS' EXTENDED PENALTIES): in an EXTENDED match the
## referee stops play for an offender anywhere on the rink, not only on the
## original's screen (MwRinkState.extended_penalties);
## [code]extended_cpu[/code] (plan 44, EXTENDED CPU): in an EXTENDED match
## the CPU's players count as on the original's screen wherever they are
## too (MwRinkState.extended_cpu).
const MATCH_RULES: Array[String] = ["enhance_audio", "replay_length", "character_select", "captain_mode",
		"lineup_select", "front_menu", "goal_song_carries", "opening_view", "idle_attract", "tick_rate",
		"extended_play", "extended_penalties", "extended_cpu"]
## Plan 35: the local settings - drawing, the window, the controls (the
## camera a player watches with, analogue control, the shot heights and the
## bindings shape their own input before it enters the stream - the shot
## heights as each player's height, or the D-pad's, in MwTickInput.heights;
## MwScreenFader.smooth_fades too). Plan 37's 3D paint, reflections and flat
## shadows are pixels only (MwSplatter reads the confirmed game and never
## writes it; it is in no hash and no resync snapshot), and so are the
## VISUALS page's ABACABB MODE, DETAILED ICE and REFLECTIONS (what the 3D
## view draws of it).
const LOCAL: Array[String] = ["camera", "start_view", "fullscreen", "aspect", "analogue", "shot_heights",
		"team_name_colours", "crowd_duck", "layouts", "bindings", "sticks", "net_port", "net_address",
		"splatter", "flat_shadows", "reflections", "blood", "ice_detail", "replay_paint"]
## [member tick_rate]'s values (the options' TICK RATE), the default first.
const TICK_RATES: Array[String] = ["OVERCLOCKED", "APPROXIMATED", "ORIGINAL"]
## Plan 40 (I1): the saved settings, one row each - name -> [section, key,
## default, values]: values a choice's texts (the setting is one of them;
## [member camera] is its index, saved as the text), [] a flag or a plain
## value. [method load_file], [method save], the defaults, a match rule's
## value ([method use_match_rules]) and the options' rows ([method step],
## [method text]) read it; the file's sections, keys and their order are
## as they always were (layouts, bindings and sticks follow these).
const SAVED := {
	"camera": ["game", "camera", 0, CAMERAS],
	"enhance_audio": ["audio", "enhance", true, []],
	"fullscreen": ["display", "fullscreen", false, []],
	"aspect": ["display", "aspect", "ORIGINAL", ASPECTS],
	"blood": ["display", "blood", true, []],
	"ice_detail": ["display", "ice_detail", true, []],
	"reflections": ["display", "reflections", true, []],
	"analogue": ["controls", "analogue", true, []],
	"shot_heights": ["controls", "shot_heights", false, []],
	"replay_length": ["game", "replay_length", "FULL GAME", REPLAYS],
	"replay_paint": ["game", "replay_paint", false, []],
	"character_select": ["game", "character_select", "5+ PLAYERS", CHARACTER_SELECTS],
	"captain_mode": ["game", "captain_mode", "5+ PLAYERS", CAPTAIN_MODES],
	"lineup_select": ["game", "lineup_select", true, []],
	"net_port": ["net", "port", MwNetProtocol.PORT, []],
	"net_address": ["net", "address", "", []],
	"tick_rate": ["game", "tick_rate", "OVERCLOCKED", TICK_RATES],
	"extended_penalties": ["game", "extended_penalties", false, []],
	"extended_cpu": ["game", "extended_cpu", false, []],
}
## A flag's texts in the options (OFF, ON); FULLSCREEN's own.
const OFF_ON := ["OFF", "ON"]
const DISPLAY := ["WINDOWED", "FULLSCREEN"]

## Where [method load_file] / [method save] read and write (tests use another).
static var path := PATH
## Index into [constant CAMERAS].
static var camera := 0
## A view (MwRinkViews) every match starts in instead of [member camera]; -1
## none. Not saved: tests and `live_match.gd --view`.
static var start_view := -1
static var enhance_audio := true
static var fullscreen := false
## The picture's shape (plan 25): ORIGINAL (320 x 224, the default) or WIDE
## (the display's or the window's aspect: for now the 3D view; the rest
## pillarboxed).
static var aspect := ASPECTS[0]
static var analogue := true
## The shot heights on their own inputs (owner, 2026-10-09: optional, in
## the modern layout). The original lifts a human's shot by the D-pad held as
## it goes off - Up high, Down along the ice, else the middle height - in the
## screen's terms, so pushing towards the net lifts a shot at the top net and
## keeps one at the bottom net flat (docs/re/puck.md, Shots). On: in the
## STANDARD layout HIGH SHOT and LOW SHOT (MwVerbs.SHOT_HEIGHTS, the triggers
## by default) pick the height, neither the middle one, and the D-pad or the
## stick aims left / right only - a stick (ANALOGUE CONTROL) in proportion to
## its sideways push (MwLiveInput.heights, MwSimPuck.shot_aim). The GENESIS
## layout and CPU players keep the original's. Off by default (the
## original's).
static var shot_heights := false
static var replay_length := REPLAYS[0]
## Plan 34's GAMEPLAY MODIFIERS: [constant CHARACTER_SELECTS],
## [constant CAPTAIN_MODES], and the line-ups before the game (Reserves on).
static var character_select := CHARACTER_SELECTS[0]
static var captain_mode := CAPTAIN_MODES[0]
static var lineup_select := true
static var tick_rate := TICK_RATES[0]
## Plan 44 (owner: an EXTENDED PENALTIES option to switch it): in an
## EXTENDED match ([method extended_play]) the referee stops play for an
## offender anywhere on the rink (MwRinkPenalties.rule; the original's: only
## one on its screen). Off by default (the original's); 2D and 3D matches
## never.
static var extended_penalties := false
## Plan 44 (owner: an EXTENDED CPU option too, so the CPU's players collide
## with everything): in an EXTENDED match the CPU's players count as on the
## original's screen wherever they are, as the humans' do (MwSimCollide).
## Off by default (the CPU's keep the original's rule); 2D and 3D matches
## never.
static var extended_cpu := false
static var front_menu := true
## Team names in the big font in their team's own colours - its primary, the
## font's own face and shade on the team's line - and the rink's score
## panel's scores light grey (owner, 2026-10-09; MwWindowPainter, the
## playoffs' champion). Off: the original's - the panel's names and scores
## all on team A's line, the champion on line 2. Not saved.
static var team_name_colours := true
## The goal song (sound 9, `$9332`) carried over into the goal scoreboard
## (owner, 2026-10-09: the tune finishes there, then that scene's music fades
## in over a second). The original's rink exit (`$FBB4`: `$13C04`) resets
## the driver, so the 6.6 s song stops about 2.6 s in when no coach speech
## follows the goal (a CPU team's, or a skipped speech). On: the exit to a
## scoreboard (12, 15, 16) while it plays stops every other sound and lets
## it play on ([method MwSound.carry_over]); the scoreboard holds its crowd
## and its music until it ends, then fades the first of them in over a
## second ([constant MwSound.FADE_IN_TICKS]). Off: the original's. Live play
## only. Not saved.
static var goal_song_carries := true
## Plan 35: HOST GAME's last port and JOIN GAME's last address (the online
## pages remember them; passwords never).
static var net_port := MwNetProtocol.PORT
static var net_address := ""
## The 3D crowd makes way (owner, 2026-10-09: seen from the rink's bottom
## end, the crowd hid too much of it): the fans who hide the rink, between
## the camera and a player, the puck, the referee, a net, a standing object
## or the goal's flying skull, sink behind their seats until it shows, those
## near it side to side less (a wider, gentler curve during a goal), rising
## again once it has gone by (MwCrowdDuck). The main 3D cameras (follow, 3D
## EXTENDED) only. Off: the crowd stands as before. Presentation only; not
## saved.
static var crowd_duck := true
## Plan 37 (owner): blood and oil painted on the 3D arena for the whole
## match, particles from hits, pools under corpses, skates' streaks
## (MwSplatter; 3D only, the 2D view is the original's). On; not saved, not in
## the menus (tests, comparisons). Off: no model, no paint - the 3D view as
## before, and replays recorded without the paint's inputs. What the view
## shows of the paint is [member blood] and [member ice_detail]'s.
static var splatter := true
## ABACABB MODE (the VISUALS page; owner, 2026-10-11: blood mode, named after
## Mortal Kombat's blood code, on by default): the blood and oil the paint's
## model makes shown in 3D - painted on the ice, the boards, the glass and the
## fence (and in their reflections), and the particles in flight. Off: none
## of it drawn; the model runs on all the same (the ice's detail is its too,
## and a replay or a demo recorded with it off has the same data). The
## original's own blood - the fight's, the impale overlay's - is the game's
## art, 2D and 3D, and stays. Saved.
static var blood := true
## DETAILED ICE (the VISUALS page; owner, 2026-10-11: on by default): the
## ice's own detail in 3D - the splotches laid from the seed and the skates'
## scratches (MwSplatter; the floor shader's ice_detail). Off: the plain ice.
## Drawing only, as [member blood]. Saved.
static var ice_detail := true
## REPLAY BLOOD (GAMEPLAY MODIFIERS, by REPLAY LENGTH; owner, 2026-10-15:
## optional for its overhead, off by default): the 3D replays - the
## instant replay, FULL GAME, the saved replays and the demos - show the
## arena's paint as it was at each frame (the match's own seeked back and
## forth, or made again from the recording's seed and inputs:
## MwSplatterReplay). Off: they show the arena without it (no blood or oil,
## no ice detail, no particles in flight). The matches keep recording its
## inputs all the same, so any replay shows it once this is on. Saved.
static var replay_paint := false
## 3D only: the shadows the rink's sprites have in their frames (colour 11
## of the team lines: the ice in shadow) masked out of the standing frames
## and laid flat on the ice beneath them, the dither kept, never lighter than
## the floor - black over black - and none for figures in the bench area
## (owner, 2026-10-09; MwFlatShadows, MwSprites3D). Off: the original's
## dithered shadows inside the frames; the calibration camera keeps the
## original's. Not saved.
static var flat_shadows := true
## Plan 37 (owner, 3D only): the ice as a mirror - the standing sprites,
## the boards, signs, fence and glass and the nets reflected in it, each
## pixel row 50 % opaque at the ice and gone 24 rows up (first 25 % over 12
## rows, the same for the sprites and the rink's geometry, then both doubled;
## MwRink3D.REFLECT_ALPHA / REFLECT_FADE). Not for the calibration camera
## (the original's picture). The VISUALS page's REFLECTIONS (owner,
## 2026-10-11: on by default); saved. Off: no reflections (the view takes it
## at its next frame).
static var reflections := true
## Each player's layout (MwInputMap.LAYOUTS); missing: STANDARD.
static var layouts := {}
## Rebound verbs: "p<player>_<verb>" (MwVerbs) -> the input (an
## [InputEventKey], [InputEventJoypadButton] or [InputEventJoypadMotion]).
static var bindings := {}
## Rebound sticks: "p<player>_<direction verb>" (MwVerbs.STICKS) -> the
## axis direction ([InputEventJoypadMotion]) that drives it besides its
## binding above; missing: the layout's (the left stick).
static var sticks := {}
## Plan 35: the view whose flow the match's opening takes while a match's
## rules are in force ([method opening_view]); -1: [method view].
static var opening_view_rule := -1
## Plan 44: whether the match is an EXTENDED one while a match's rules are
## in force (1 / 0, [method extended_play]); -1: this machine's CAMERA.
static var extended_play_rule := -1
## Plan 35: this machine's own values of the match rules while a match's
## are in force ([method use_match_rules]; empty: none in force).
static var _own := {}


## Reads [member path] (missing file or keys: the defaults, [constant SAVED];
## plan 45: so is a file that isn't plain settings, MwUserFile.read_config).
static func load_file() -> void:
	var sc: GDScript = MwSettings
	for name: String in SAVED:
		sc.set(name, SAVED[name][2])
	layouts = {}
	bindings = {}
	sticks = {}
	var cfg := MwUserFile.read_config(path)
	if cfg == null:
		return
	for name: String in SAVED:
		var row: Array = SAVED[name]
		sc.set(name, _valid(name, cfg.get_value(row[0], row[1], _stored(name, row[2]))))
	for p in range(1, MwVerbs.PLAYERS + 1):
		var l := str(cfg.get_value("controls", "layout_p%d" % p, ""))
		if l in MwInputMap.LAYOUTS:
			layouts[p] = l
	if cfg.has_section("bindings"):
		var verbs := MwVerbs.all_verbs()
		for key in cfg.get_section_keys("bindings"):
			var bound_event := MwInputMap.decode_event(str(cfg.get_value("bindings", key, "")))
			if bound_event == null or not MwInputMap.bindable(bound_event):
				continue
			var pv := MwVerbs.parse_action(key)
			var player: int = pv[0]
			var name: String = pv[1]
			if name in verbs:
				bindings[key] = bound_event
			elif name in OLD_BUTTONS:
				# plan 21's button: its verbs, in the original's layout
				for v in verbs:
					if name in MwVerbs.genesis_buttons(v):
						bindings[_key(player, v)] = bound_event
	if cfg.has_section("sticks"):
		for key in cfg.get_section_keys("sticks"):
			var event := MwInputMap.decode_event(str(cfg.get_value("sticks", key, "")))
			if event is InputEventJoypadMotion and MwVerbs.is_direction(str(MwVerbs.parse_action(key)[1])):
				sticks[key] = event


## Writes [member path] (this machine's own values, whatever match's rules
## are in force). False, with a warning, when the file couldn't be written
## whole (plan 45: the old one stays).
static func save() -> bool:
	var cfg := ConfigFile.new()
	var sc: GDScript = MwSettings
	for name: String in SAVED:
		var row: Array = SAVED[name]
		cfg.set_value(row[0], row[1], _stored(name, _own.get(name, sc.get(name))))
	for p in layouts:
		cfg.set_value("controls", "layout_p%d" % p, layouts[p])
	for key in bindings:
		cfg.set_value("bindings", key, MwInputMap.encode_event(bindings[key]))
	for key in sticks:
		cfg.set_value("sticks", key, MwInputMap.encode_event(sticks[key]))
	return MwUserFile.write_config(cfg, path)


## Puts the settings into effect: the audio switches, the window and the
## input map.
static func apply() -> void:
	apply_audio()
	apply_display()
	MwInputMap.install()


## Plan 35: the match rules as they are now ([constant MATCH_RULES]: name
## -> value; plain data for the start record).
static func match_rules() -> Dictionary:
	return {
		"enhance_audio": enhance_audio,
		"replay_length": replay_length,
		"character_select": character_select,
		"captain_mode": captain_mode,
		"lineup_select": lineup_select,
		"front_menu": front_menu,
		"goal_song_carries": goal_song_carries,
		"opening_view": opening_view(),
		"idle_attract": MwAttract.idle_attract,
		"tick_rate": tick_rate,
		"extended_play": extended_play(),
		"extended_penalties": extended_penalties,
		"extended_cpu": extended_cpu,
	}


## Plan 35: a match's rules ([method match_rules]' form, e.g. the host's from
## the start record) in force from now on; this machine's own values are
## kept ([method save] writes those) until [method own_match_rules].
## Unknown or missing names stay as they are.
static func use_match_rules(rules: Dictionary) -> void:
	var now := match_rules()
	for k in MATCH_RULES:
		if not rules.has(k):
			continue
		if not _own.has(k):
			_own[k] = now[k]
		_set_rule(k, rules[k])
	apply_audio()


## Plan 35: this machine's own values back (no match's rules in force).
static func own_match_rules() -> void:
	for k in _own:
		_set_rule(k, _own[k])
	_own = {}
	opening_view_rule = -1
	extended_play_rule = -1
	apply_audio()


## Whether a match's rules are in force ([method use_match_rules]).
static func match_rules_in_force() -> bool:
	return not _own.is_empty()


static func _set_rule(k: String, v: Variant) -> void:
	if SAVED.has(k):
		var sc: GDScript = MwSettings
		sc.set(k, _valid(k, v))              # (a choice's text checked, a flag a bool)
		return
	match k:
		"front_menu": front_menu = bool(v)
		"goal_song_carries": goal_song_carries = bool(v)
		"opening_view": opening_view_rule = int(v) if _own.has(k) and int(v) >= 0 else -1
		"extended_play": extended_play_rule = (1 if bool(v) else 0) if _own.has(k) else -1
		"idle_attract": MwAttract.idle_attract = bool(v)


## Plan 40 (I1): saved setting [param name]'s value [param v] as read (the
## file, a match's rules): a choice's text if it is one, else its default;
## [member camera] the index of its text; a flag a bool; the port and the
## address within bounds.
static func _valid(name: String, v: Variant) -> Variant:
	var row: Array = SAVED[name]
	var values: Array = row[3]
	match name:
		"camera":
			return maxi(values.find(str(v)), 0)
		"net_port":
			return int(v) if v is int and int(v) >= 1 and int(v) <= 65535 else row[2]
		"net_address":
			return str(v) if v is String and str(v).length() <= MwNetAddress.MAX_TEXT else row[2]
	if not values.is_empty():
		return str(v) if str(v) in values else row[2]
	return bool(v)


## [param v] of saved setting [param name] as the file keeps it ([member
## camera]: its text).
static func _stored(name: String, v: Variant) -> Variant:
	return CAMERAS[clampi(int(v), 0, CAMERAS.size() - 1)] if name == "camera" else v


## Plan 40 (I1): saved setting [param name] one step on ([param d] +1 / -1):
## a choice the next of its values (round), a flag turned; what it changes
## at once follows (the audio switches, the window, HIGH / LOW SHOT's
## inputs). The options' rows; the caller saves.
static func step(name: String, d: int) -> void:
	var sc: GDScript = MwSettings
	var values: Array = SAVED[name][3]
	if name == "camera":
		camera = posmod(camera + d, CAMERAS.size())
	elif not values.is_empty():
		sc.set(name, values[posmod(values.find(sc.get(name)) + d, values.size())])
	else:
		sc.set(name, not bool(sc.get(name)))
	match name:
		"enhance_audio":
			apply_audio()
		"fullscreen":
			apply_display()
		"shot_heights":
			MwInputMap.install()               # HIGH / LOW SHOT get their inputs (or lose them)


## Plan 40 (I1): saved setting [param name] as the options show it.
static func text(name: String) -> String:
	var sc: GDScript = MwSettings
	if name == "camera":
		return camera_name()
	if name == "fullscreen":
		return DISPLAY[1 if fullscreen else 0]
	if not (SAVED[name][3] as Array).is_empty():
		return str(sc.get(name))
	return OFF_ON[1 if bool(sc.get(name)) else 0]


## Plan 35: the view whose flow the match's opening takes - a match's rule
## ([member opening_view_rule]) or the view a match starts in ([method view]).
static func opening_view() -> int:
	return opening_view_rule if opening_view_rule >= 0 else view()


## [member enhance_audio] -> plan 12's two switches, plan 31's crowd noise,
## plan 39's organ pool.
static func apply_audio() -> void:
	MwAudio.free_music_samples = enhance_audio
	MwAudio.free_effects = enhance_audio
	MwAudio.organ_pool = enhance_audio            # plan 39: the organ pool
	MwCrowdLife.drives_sound = enhance_audio     # plan 31: the crowd's noise follows its life


## True when the picture takes the display's or the window's shape
## ([member aspect] WIDE; MwRink3DHost reads it when the 3D view shows).
static func wide() -> bool:
	return aspect == "WIDE"


## [member fullscreen] -> the window (Godot's borderless full screen); nothing
## without a display. A maximised window stays as it is when windowed.
static func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## The tick rate the rink plays: [member tick_rate], but APPROXIMATED for
## ORIGINAL in an online match ([param online]: plan 35 - every machine must
## pace the passes alike, and ORIGINAL reads each machine's own sound
## driver in floating point; APPROXIMATED is integers from the shared state).
static func rink_tick_rate(online: bool) -> String:
	if online and tick_rate == "ORIGINAL":
		return "APPROXIMATED"
	return tick_rate


## True when the instant replay reaches back over the whole match
## (MwFullReplay, plan 28).
static func full_replays() -> bool:
	return replay_length == REPLAYS[0]


## Alt+Enter (either Enter): the window between full screen and windowed,
## as the Options row does (owner, 2026-10-08: no binding shows it).
static func is_display_toggle(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.alt_pressed \
			and (event.keycode in [KEY_ENTER, KEY_KP_ENTER] or event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER])


## [member fullscreen] flipped, applied and saved (Alt+Enter).
static func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply_display()
	if DisplayServer.get_name() != "headless":
		save()


## [param player]'s layout (MwInputMap.LAYOUTS).
static func layout(player: int) -> String:
	return layouts.get(player, MwInputMap.LAYOUTS[0])


## [param player] takes layout [param name] afresh: their own bindings go;
## the input map is rebuilt and the file saved.
static func set_layout(player: int, name: String) -> void:
	layouts[player] = name
	for v in MwVerbs.all_verbs():
		bindings.erase(_key(player, v))
		sticks.erase(_key(player, v))
	MwInputMap.install()
	save()


## The camera a new match starts in ([constant CAMERAS]).
static func camera_name() -> String:
	return CAMERAS[clampi(camera, 0, CAMERAS.size() - 1)]


## The view (MwRinkViews) a match starts in: the options' CAMERA (or
## [member start_view]) in the match's group (plan 44: online the
## EXTENDED one whatever CAMERA says - its 2D or its 3D).
static func view() -> int:
	return MwRinkViews.grouped(_camera_view(), extended_play())


## The view this machine's CAMERA (or [member start_view]) names.
static func _camera_view() -> int:
	return start_view if start_view >= 0 else CAMERA_VIEWS[clampi(camera, 0, CAMERA_VIEWS.size() - 1)]


## Plan 44: whether this machine's CAMERA (or [member start_view]) is one of
## the EXTENDED group.
static func camera_extended() -> bool:
	return MwRinkViews.is_extended(_camera_view())


## Plan 44: whether a match now is an EXTENDED one - a match's rule while
## its rules are in force ([member extended_play_rule]; online: always),
## else this machine's CAMERA ([method camera_extended]).
static func extended_play() -> bool:
	return extended_play_rule == 1 if extended_play_rule >= 0 else camera_extended()


static func _key(player: int, verb: String) -> String:
	return MwVerbs.player_key(player, verb)


## The input [param player] (1-4) rebound [param verb] to, or null (the
## layout's default).
static func binding(player: int, verb: String) -> InputEvent:
	return bindings.get(_key(player, verb))


## [param player]'s [param verb] is [param event] from now on (null: back to
## the layout's default); the input map is rebuilt and the file saved. An
## input another verb also has stays on both (owner): the bindings menu
## shows a collision red (MwInputMap.collisions).
static func set_binding(player: int, verb: String, event: InputEvent) -> void:
	if event == null:
		bindings.erase(_key(player, verb))
	else:
		bindings[_key(player, verb)] = MwInputMap.normalized(event)
	MwInputMap.install()
	save()


## The axis direction [param player] bound to direction verb [param verb]
## (MwVerbs.STICKS), or null (the layout's: [method
## MwInputMap.default_stick]).
static func stick_binding(player: int, verb: String) -> InputEvent:
	return sticks.get(_key(player, verb))


## [param player]'s stick set [param set_name] (MwVerbs.STICKS) is the stick
## [param motion] moved (a gamepad's left or right stick: its x axis for
## left / right, its y axis for up / down), on that gamepad; null: back to
## the layout's. The input map is rebuilt and the file saved.
static func set_stick(player: int, set_name: String, motion: InputEvent) -> void:
	var verbs: Array = MwVerbs.STICKS[set_name]
	var axes := MwInputMap.stick_axes(motion)
	for i in 4:
		var key := _key(player, verbs[i])
		if axes.is_empty():
			sticks.erase(key)
			continue
		var m := InputEventJoypadMotion.new()
		m.device = motion.device
		m.axis = axes[1 if i < 2 else 0]                # up / down: y; left / right: x
		m.axis_value = -1.0 if i % 2 == 0 else 1.0      # up, left: negative
		sticks[key] = m
	MwInputMap.install()
	save()
