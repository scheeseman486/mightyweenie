class_name MwVerbs
extends RefCounted
## The input verbs (docs/re/input.md; plan 22: every screen's meanings are
## verbs, owner 2026-10-08: verbs throughout, no longer the Genesis pad's
## buttons) and, per context, the original's Genesis button each verb was on.
##
## Gameplay names follow the manual (docs/re/manual.md): A punches (or uses
## a weapon; held: dive, or fire a special play), B passes (held: releases
## the puck; without it: changes player), C shoots (wrist shot, held: slap
## shot; without the puck: check / speed burst; the goalie slashes). Each
## meaning is its own verb (owner, 2026-10-06); a button's verbs on one
## input play the original's tap / hold timing ([constant GROUPS],
## MwGameplayPads, MwHumanControl).
##
## Each screen reads the verbs of its contexts ([constant MwScreens.TABLE]);
## a context is one screen's (or screen family's) set of meanings, so one
## input can mean "pass" in play and "accept" in a menu. [constant
## PAD_TO_VERB] is the original's layout: which Genesis button each verb was
## on. The screens still hand their original-faithful sims Genesis pad bytes,
## built from the verbs ([method pad_byte]); scripted input (comparisons,
## tests) presses a Genesis pad's verbs ([method pad_actions]). Bindings are
## per verb ([MwInputMap], [MwSettings]).
##
## Per-player verbs are actions named `p1_pass` ...; menu verbs (`ui_*`) are
## shared - any player drives menus, as in the original - and each also has a
## per-player action (`p1_ui_accept`) for screens that tell players apart.
##
## Plan 34: twelve players (the original's four pads are players 1-4; the
## controller selection decides who plays), and RECLAIM.
##
## Plan 38 with plan 35: CREATE-A-TEAM's editor contexts
## ([constant LOCAL_CONTEXTS]) are this machine's own screens, never online
## and never in a match. Their own verbs ([method local_verbs]: the
## editor's, met in no other context) are shared like the menu verbs (any
## player's inputs; the action is the verb's name, `rink_place`) and stay
## out of the input stream: [method menu_verbs], [method player_verbs] and
## [method all_actions] are the stream's (MwTickInput, MwNetInput - plan
## 35's wire and schema as before), [method every_action] adds the local
## ones for the devices (MwLiveInput, MwInputMap).

const PLAYERS := 12

## Input contexts: which verbs a screen listens to.
enum Context { MENU, GAMEPLAY, FIGHT, REPLAY, ZAMBONI, TITLE, SETUP, TEAM_INFO, MATCHUP,
		PLAYOFFS, PASSWORD, PAUSE, SCOREBOARD, STATS, SPECIAL_PLAYS, CREATE, RINK_EDIT, TEXT_ENTRY }

const MOVE: Array[String] = ["move_up", "move_down", "move_left", "move_right"]
const NAV: Array[String] = ["ui_up", "ui_down", "ui_left", "ui_right"]
const GAMEPLAY: Array[String] = ["move_up", "move_down", "move_left", "move_right",
		"pass", "release_puck", "change_player", "wrist_shot", "slap_shot", "check",
		"punch", "dive", "special_play", "pause"]
## The gameplay verbs on the original's A / B / C (tap, hold, other situation).
const BUTTON_VERBS := {
	"B": ["pass", "release_puck", "change_player"],
	"C": ["wrist_shot", "slap_shot", "check"],
	"A": ["punch", "dive", "special_play"],
}
## Verbs that may share one input on one screen: the original's one-button
## meanings told apart by tap / hold / situation (owner: the Genesis mappings
## stay possible).
const GROUPS: Array = [["pass", "release_puck", "change_player"], ["wrist_shot", "slap_shot", "check"],
		["punch", "dive", "special_play"]]
const FIGHT: Array[String] = ["fight_punch", "fight_block", "fight_pause"]
const REPLAY: Array[String] = ["replay_rewind", "replay_slow", "replay_play", "replay_exit"]
const ZAMBONI: Array[String] = ["zamboni_whip"]
## Player 1's 2D / 3D switch (owner): not in any screen's contexts (the rink
## reads it, MwRinkViews); bindable like a verb.
const VIEW_TOGGLE := "view_toggle"
## Plan 34 (owner): taking back the character a player owns from a teammate
## who has it (owned play). A port verb, on no Genesis button: in the
## STANDARD layout the gamepad's left shoulder (keyboard Q for player 1);
## the GENESIS layout has no input for it - B tapped twice without the puck
## reclaims there (a 3-button pad has no spare button).
const RECLAIM := "reclaim"
## The port's shot heights (owner, 2026-10-09: inputs of their own, optional,
## in the modern layout; MwSettings.shot_heights): held when a shot goes off,
## HIGH SHOT lifts it as the original's Up does, LOW SHOT keeps it on the ice
## as its Down, neither the original's middle height; the D-pad (or the
## stick) then aims left / right only (MwSimPuck.shot_aim). The original's
## lift follows the screen's Up / Down whichever net is attacked. Port verbs
## on no Genesis button: the STANDARD layout's triggers (MwInputMap); the
## GENESIS layout has no input for them.
const SHOT_HIGH := "shot_high"
const SHOT_LOW := "shot_low"
const SHOT_HEIGHTS: Array[String] = [SHOT_HIGH, SHOT_LOW]
## The sticks (owner: analogue input bindable, on the D-pad's direction
## verbs): a stick drives a set of four direction verbs (up,
## down, left, right) through a second binding of theirs, an axis direction
## each (MwSettings.stick_binding), besides the D-pad's key or button. The
## bindings menu binds a whole stick on one row: these names. By default the
## left stick (MwInputMap.default_stick); the skating stick is the one
## analogue control reads (MwLiveInput.raw_stick).
const STICKS := {"move_stick": MOVE, "ui_stick": NAV}

## Genesis button -> verb (or verbs), per context: the original's layout.
## "BACK" is the port's Menu Back (no Genesis button).
const PAD_TO_VERB := {
	Context.MENU: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "ui_accept", "A": "ui_delete", "B": "ui_keep", "BACK": "ui_back"},
	Context.TITLE: {"START": "ui_accept", "A": "ui_skip", "B": "ui_skip", "C": "ui_skip",
			"BACK": "ui_back"},
	Context.SETUP: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "ui_accept", "A": "ui_skip", "B": "ui_skip", "C": "ui_skip", "BACK": "ui_back"},
	Context.TEAM_INFO: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "ui_info_return", "A": "ui_next_page", "B": "ui_next_page", "C": "ui_next_page",
			"BACK": "ui_back"},
	Context.MATCHUP: {"START": "ui_accept", "A": "ui_skip", "B": "ui_skip", "C": "ui_skip",
			"BACK": "ui_back"},
	Context.PLAYOFFS: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "ui_accept", "A": "ui_new_playoffs", "B": "ui_starfield_stop",
			"C": "ui_starfield_turn", "BACK": "ui_back"},
	Context.PASSWORD: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "ui_password_done", "A": "ui_pick_letter", "B": "ui_erase_letter",
			"C": "ui_cancel", "BACK": "ui_back"},
	Context.PAUSE: {"UP": "ui_up", "DOWN": "ui_down", "START": "ui_resume", "A": "ui_pause_replay",
			"B": "ui_pause_timeout", "BACK": "ui_back"},
	Context.SCOREBOARD: {"START": "ui_accept", "A": "ui_view_stats", "B": "ui_view_special_plays",
			"C": "ui_view_replay", "BACK": "ui_back"},
	Context.STATS: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "ui_accept", "A": "ui_stats_switch", "B": "ui_starfield_stop",
			"C": "ui_starfield_turn", "BACK": "ui_back"},
	Context.SPECIAL_PLAYS: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "ui_plays_done", "A": "ui_nasty_play", "B": "ui_choose_play",
			"C": "ui_phony_play", "BACK": "ui_back"},
	Context.GAMEPLAY: {"UP": "move_up", "DOWN": "move_down", "LEFT": "move_left", "RIGHT": "move_right",
			"A": BUTTON_VERBS["A"], "B": BUTTON_VERBS["B"], "C": BUTTON_VERBS["C"], "START": "pause"},
	Context.FIGHT: {"A": "fight_block", "B": "fight_punch", "C": "fight_punch",
			"LEFT": "move_left", "RIGHT": "move_right", "START": "fight_pause"},
	Context.REPLAY: {"A": "replay_rewind", "B": "replay_slow", "C": "replay_play", "START": "replay_exit",
			"BACK": "ui_back"},
	Context.ZAMBONI: {"UP": "zamboni_whip", "DOWN": "zamboni_whip", "LEFT": "zamboni_whip", "RIGHT": "zamboni_whip"},
	# The port's own (plan 38, CREATE-A-TEAM): no Genesis button had these
	# meanings, so the editor's extra verbs sit on the 6-button pad's names
	# (X, Y, Z) and the view's on the port's own (VIEW_*): their inputs come
	# from MwInputMap's layouts all the same.
	Context.CREATE: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "ui_accept", "A": "ui_editor_copy", "B": "ui_editor_delete", "C": "ui_editor_next",
			"X": "ui_editor_previous", "BACK": "ui_back"},
	Context.RINK_EDIT: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "rink_done", "A": "rink_place", "B": "rink_remove", "C": "rink_mirror",
			"X": "rink_kind_previous", "Y": "rink_kind_next", "VIEW_LEFT": "rink_view_left",
			"VIEW_RIGHT": "rink_view_right", "VIEW_IN": "rink_view_in", "VIEW_OUT": "rink_view_out",
			"BACK": "ui_back"},
	# The text entry's scrolling (plan 38 follow-up), beside the password
	# entry's verbs: on keys that type nothing (Page Up / Down) and the
	# right stick; the text's cursor left / right on the triggers (owner,
	# 2026-10-12: LT / RT on a controller - the keyboard's arrows move it
	# already).
	Context.TEXT_ENTRY: {"SCROLL_UP": "ui_text_up", "SCROLL_DOWN": "ui_text_down",
			"CURSOR_LEFT": "ui_text_left", "CURSOR_RIGHT": "ui_text_right"},
}
## Plan 38: the contexts only this machine's own screens use (CREATE-A-TEAM:
## 130-138, never online - the text entry's scroll too); their own verbs
## are [method local_verbs].
const LOCAL_CONTEXTS: Array[int] = [Context.CREATE, Context.RINK_EDIT, Context.TEXT_ENTRY]
static var _local := {}
## Contexts where Menu Back does what Start does (owner, plan 22: Back works
## on every screen that can be left; where the original leaves on Start, Back
## does what Start does there).
const BACK_AS_START: Array[int] = [Context.TEAM_INFO, Context.PAUSE, Context.SCOREBOARD,
		Context.STATS, Context.SPECIAL_PLAYS, Context.REPLAY]
## The original's pad byte (`read_joypads` $1407E: S A C B R L D U).
const BITS := {"UP": 0x01, "DOWN": 0x02, "LEFT": 0x04, "RIGHT": 0x08, "B": 0x10, "C": 0x20, "A": 0x40, "START": 0x80}

## What the bindings menu calls each verb (the port's text).
const LABELS := {
	"ui_up": "UP", "ui_down": "DOWN", "ui_left": "LEFT", "ui_right": "RIGHT",
	"ui_accept": "ACCEPT", "ui_back": "BACK", "ui_skip": "SKIP", "ui_delete": "DELETE", "ui_keep": "KEEP",
	"move_up": "SKATE UP", "move_down": "SKATE DOWN", "move_left": "SKATE LEFT", "move_right": "SKATE RIGHT",
	"pass": "PASS", "release_puck": "LET PUCK GO", "change_player": "CHANGE PLAYER",
	"wrist_shot": "WRIST SHOT", "slap_shot": "SLAP SHOT", "check": "CHECK",
	"shot_high": "HIGH SHOT", "shot_low": "LOW SHOT",
	"punch": "PUNCH", "dive": "DIVE", "special_play": "SPECIAL PLAY", "pause": "PAUSE", "reclaim": "RECLAIM",
	"view_toggle": "2D / 3D", "move_stick": "SKATE STICK", "ui_stick": "STICK",
	"fight_punch": "PUNCH", "fight_block": "BLOCK", "fight_pause": "PAUSE",
	"replay_rewind": "REWIND", "replay_slow": "SLOW", "replay_play": "PLAY", "replay_exit": "EXIT",
	"ui_pause_replay": "REPLAY", "ui_pause_timeout": "TIMEOUT", "ui_resume": "RESUME",
	"ui_view_stats": "STATS", "ui_view_special_plays": "SPECIAL PLAYS", "ui_view_replay": "REPLAY",
	"ui_stats_switch": "PLAYERS / TEAM", "ui_starfield_stop": "STARS STOP", "ui_starfield_turn": "STARS TURN",
	"ui_nasty_play": "NASTY PLAY", "ui_choose_play": "CHOOSE PLAY", "ui_phony_play": "PHONY PLAY",
	"ui_plays_done": "DONE",
	"ui_next_page": "NEXT PAGE", "ui_info_return": "BIO / LEAVE",
	"ui_new_playoffs": "NEW PLAYOFFS", "ui_pick_letter": "PICK LETTER", "ui_erase_letter": "ERASE",
	"ui_cancel": "CANCEL", "ui_password_done": "DONE",
	"zamboni_whip": "ZAMBONI WHIP",
	"ui_editor_copy": "COPY / PICK", "ui_editor_delete": "DELETE / NEW", "ui_editor_next": "NEXT",
	"ui_editor_previous": "PREVIOUS",
	"rink_place": "PLACE", "rink_remove": "REMOVE", "rink_mirror": "MIRROR", "rink_kind_next": "NEXT KIND",
	"rink_kind_previous": "PREVIOUS KIND", "rink_done": "DONE", "rink_view_left": "TURN LEFT",
	"rink_view_right": "TURN RIGHT", "rink_view_in": "ZOOM IN", "rink_view_out": "ZOOM OUT",
	"ui_text_up": "TEXT UP", "ui_text_down": "TEXT DOWN", "ui_text_left": "CURSOR LEFT",
	"ui_text_right": "CURSOR RIGHT",
}
## The bindings menu's pages: title, verbs.
const PAGES: Array = [
	["MENUS", ["ui_up", "ui_down", "ui_left", "ui_right", "ui_stick", "ui_accept", "ui_back", "ui_skip",
			"ui_delete", "ui_keep"]],
	["GAMEPLAY", ["move_up", "move_down", "move_left", "move_right", "move_stick", "pass", "release_puck",
			"change_player", "wrist_shot", "slap_shot", "check", "shot_high", "shot_low", "punch", "dive",
			"special_play", "reclaim", "pause", "view_toggle"]],
	["FIGHT", ["fight_punch", "fight_block", "fight_pause"]],
	["PAUSE + REPLAY", ["ui_resume", "ui_pause_replay", "ui_pause_timeout", "replay_rewind", "replay_slow",
			"replay_play", "replay_exit"]],
	["SCOREBOARD + STATS", ["ui_view_stats", "ui_view_special_plays", "ui_view_replay",
			"ui_stats_switch", "ui_starfield_stop", "ui_starfield_turn", "zamboni_whip"]],
	["SPECIAL PLAYS", ["ui_nasty_play", "ui_choose_play", "ui_phony_play", "ui_plays_done"]],
	["SETUP SCREENS", ["ui_next_page", "ui_info_return", "ui_new_playoffs", "ui_pick_letter",
			"ui_erase_letter", "ui_cancel", "ui_password_done"]],
	["CREATE-A-TEAM", ["ui_editor_copy", "ui_editor_delete", "ui_editor_next", "ui_editor_previous",
			"ui_text_up", "ui_text_down", "ui_text_left", "ui_text_right"]],
	["RINK EDITOR", ["rink_place", "rink_remove", "rink_mirror", "rink_kind_next", "rink_kind_previous",
			"rink_view_left", "rink_view_right", "rink_view_in", "rink_view_out", "rink_done"]],
]


## True for a direction verb a stick can drive ([constant STICKS]).
static func is_direction(verb: String) -> bool:
	return verb in MOVE or verb in NAV


## The stick set (a [constant STICKS] name) [param verb] belongs to, or "".
static func stick_set(verb: String) -> String:
	for k in STICKS:
		if verb in STICKS[k]:
			return k
	return ""


## The verbs Genesis [param button] stands for in context [param ctx].
static func verbs_of(ctx: int, button: String) -> Array[String]:
	var v: Variant = PAD_TO_VERB[ctx].get(button, "")
	var out: Array[String] = []
	if v is Array:
		out.assign(v)
	elif v != "":
		out.append(v)
	return out


## Every verb of context [param ctx].
static func context_verbs(ctx: int) -> Array[String]:
	var out: Array[String] = []
	for button in PAD_TO_VERB[ctx]:
		for v in verbs_of(ctx, button):
			if not v in out:
				out.append(v)
	return out


## Plan 38: the verbs of [constant LOCAL_CONTEXTS] met in no other context
## (the editor's own: shared, any player's; not in the input stream).
static func local_verbs() -> Array[String]:
	if _local.is_empty():
		var others := {}
		for ctx in PAD_TO_VERB:
			if not ctx in LOCAL_CONTEXTS:
				for v in context_verbs(ctx):
					others[v] = true
		for ctx in LOCAL_CONTEXTS:
			for v in context_verbs(ctx):
				if not others.has(v):
					_local[v] = true
	var out: Array[String] = []
	out.assign(_local.keys())
	return out


## True for one of [method local_verbs].
static func is_local(verb: String) -> bool:
	if _local.is_empty():
		local_verbs()
	return _local.has(verb)


## Every verb, each once (menu verbs, then per-player ones; RECLAIM, the
## shot heights and the view switch last; plan 38's local verbs where their
## contexts come).
## Worked out once (constants only) and handed out as a copy: the input
## map, the glyphs and the controller selection ask for it per player and
## per verb (owner, 2026-10-12: the menus' stutters).
static func all_verbs() -> Array[String]:
	if _all.is_empty():
		for ctx in PAD_TO_VERB:
			for v in context_verbs(ctx):
				if not v in _all:
					_all.append(v)
		_all.append(RECLAIM)
		_all.append_array(SHOT_HEIGHTS)
		_all.append(VIEW_TOGGLE)
	return _all.duplicate()


static var _all: Array[String] = []


## The menu verbs (`ui_*`): shared, any player - the input stream's (not
## plan 38's local ones, [method local_verbs]).
static func menu_verbs() -> Array[String]:
	var out: Array[String] = []
	for v in all_verbs():
		if v.begins_with("ui_") and not is_local(v):
			out.append(v)
	return out


## Every per-player verb (the input stream's: not plan 38's local ones).
static func player_verbs() -> Array[String]:
	var out: Array[String] = []
	for v in all_verbs():
		if not v.begins_with("ui_") and v != VIEW_TOGGLE and not is_local(v):
			out.append(v)
	return out


## The Genesis buttons [param verb] was on, over every context (the view
## switch: "VIEW", player 1's; RECLAIM: "RECLAIM", on none; the shot
## heights: "SHOT_HIGH" / "SHOT_LOW", names for the keyboard layout's keys -
## no Genesis button had them).
static func genesis_buttons(verb: String) -> Array[String]:
	var out: Array[String] = []
	if verb == VIEW_TOGGLE:
		out.append("VIEW")
		return out
	if verb == RECLAIM:
		out.append("RECLAIM")
		return out
	if verb in SHOT_HEIGHTS:
		out.append(verb.to_upper())
		return out
	for ctx in PAD_TO_VERB:
		for button in PAD_TO_VERB[ctx]:
			if verb in verbs_of(ctx, button) and not button in out:
				out.append(button)
	return out


## The group (tap / hold / situation) [param verb] belongs to, or the verb.
static func meaning(verb: String) -> String:
	for g in GROUPS:
		if verb in g:
			return g[0]
	return verb


## The action name of [param verb] for [param player] (1-12); menu verbs and
## plan 38's local verbs are shared and keep their name.
static func action(player: int, verb: String) -> String:
	return verb if verb.begins_with("ui_") or is_local(verb) else player_key(player, verb)


## The per-player form of menu verb [param verb] (`p2_ui_left`).
static func menu_action(player: int, verb: String) -> String:
	return player_key(player, verb)


## Plan 40 (I3): player [param player]'s name of [param verb] ("p3_pass"):
## per-player actions, the bindings' keys, the input map's tables.
static func player_key(player: int, verb: String) -> String:
	return "p%d_%s" % [player, verb]


## [player, verb] of a per-player name ([method player_key]: "p3_pass" ->
## [3, "pass"]); [-1, [param a]] for a shared one ("ui_accept").
static func parse_action(a: String) -> Array:
	if a.begins_with("p"):
		var at := a.find("_")
		if at >= 2 and a.substr(1, at - 1).is_valid_int():
			return [int(a.substr(1, at - 1)), a.substr(at + 1)]
	return [-1, a]


## The action that tells player [param player]'s [param verb] apart: the
## per-player action of a menu verb, else [method action] (a local verb's
## shared one).
static func player_action(player: int, verb: String) -> String:
	return menu_action(player, verb) if verb.begins_with("ui_") and not is_local(verb) else action(player, verb)


## Every action the input stream carries (MwTickInput's layout: the shared
## menu verbs, then players 1-12's verbs and per-player menu verbs).
static func all_actions() -> Array[String]:
	var out: Array[String] = []
	out.append_array(menu_verbs())
	for p in range(1, PLAYERS + 1):
		for v in player_verbs():
			out.append(action(p, v))
		for v in menu_verbs():
			out.append(menu_action(p, v))
	return out


## Player [param player]'s pad byte in [param contexts] from [param
## actions] (held or newly pressed action names): each verb sets the bit of
## the Genesis button it was on; Menu Back sets Start's in [constant
## BACK_AS_START] contexts. Player 0: the shared menu verbs' unprefixed
## actions (plan 40, I2: an online game's options read the host's P1's so).
static func pad_byte(actions: Dictionary, player: int, contexts: Array) -> int:
	var bits := 0
	for ctx in contexts:
		var table: Dictionary = PAD_TO_VERB[ctx]
		for button in table:
			if not BITS.has(button):
				continue
			for v in verbs_of(ctx, button):
				if actions.has(v if player == 0 else player_action(player, v)):
					bits |= BITS[button]
		if ctx in BACK_AS_START and actions.has("ui_back" if player == 0 else menu_action(player, "ui_back")):
			bits |= BITS["START"]
	return bits


## The actions a Genesis pad's buttons press in [param contexts] (scripted
## input: comparisons, tests): [param mask] in [constant BITS], for player
## [param player]; menu verbs press their shared action and the player's.
static func pad_actions(player: int, mask: int, contexts: Array) -> Dictionary:
	var out := {}
	if mask == 0:
		return out
	for button in BITS:
		if mask & BITS[button] == 0:
			continue
		for ctx in contexts:
			for v in verbs_of(ctx, button):
				out[action(player, v)] = true
				if v.begins_with("ui_") and not is_local(v):
					out[menu_action(player, v)] = true
	return out


## Every action the devices drive: [method all_actions] (the stream's) and
## plan 38's local verbs (shared, named as the verbs; this machine's own
## screens read them, the stream drops them).
static func every_action() -> Array[String]:
	var out := all_actions()
	out.append_array(local_verbs())
	return out
