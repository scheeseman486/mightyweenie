class_name MwVerbs
extends RefCounted
## The approved input verbs (docs/re/input.md) and how the original's
## Genesis buttons map to them in each context.
##
## Names follow the manual (docs/re/manual.md): A punches (or uses a
## weapon; held: dive, or fire a special play), B passes (held: releases
## the puck; without it: changes player), C shoots (wrist shot, held: slap
## shot; without the puck: check / speed burst; the goalie slashes). Each
## meaning is its own verb (owner, 2026-10-06); the defaults put a button's
## verbs on the original button, where the original's tap / hold timing
## tells them apart (MwGameplayPads, MwHumanControl).
## Per-player verbs are actions named `p1_pass` ... `p4_zamboni_whip`; menu
## verbs are shared (`ui_accept`, ...): any player drives menus, as in the
## original. A screen that, like the original's main menu, tells the players
## apart reads the per-player menu actions `p1_ui_left` ... (plan 06). Screens read verbs, never buttons; the pad tables here serve the
## default bindings and scripted input (comparisons, tests).

const PLAYERS := 4

## Input contexts: which verbs a screen listens to.
enum Context { MENU, GAMEPLAY, FIGHT, REPLAY, ZAMBONI }

const MOVE: Array[String] = ["move_up", "move_down", "move_left", "move_right"]
const GAMEPLAY: Array[String] = ["move_up", "move_down", "move_left", "move_right",
		"pass", "release_puck", "change_player", "wrist_shot", "slap_shot", "check",
		"punch", "dive", "special_play", "pause"]
## The gameplay verbs on the original's A / B / C (tap, hold, other situation).
const BUTTON_VERBS := {
	"B": ["pass", "release_puck", "change_player"],
	"C": ["wrist_shot", "slap_shot", "check"],
	"A": ["punch", "dive", "special_play"],
}
const FIGHT: Array[String] = ["fight_punch", "fight_block"]
const REPLAY: Array[String] = ["replay_rewind", "replay_slow", "replay_play", "replay_exit"]
const ZAMBONI: Array[String] = ["zamboni_whip"]
## `ui_back` is the port's Menu Back (plan 21): not a Genesis button; the
## menus step back with it (MwSettings.BUTTONS "BACK").
const MENU: Array[String] = ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept",
		"ui_option_a", "ui_option_b", "ui_option_c", "ui_back"]

## Genesis button -> verb (or verbs), per context (the original's controls).
const PAD_TO_VERB := {
	Context.MENU: {"UP": "ui_up", "DOWN": "ui_down", "LEFT": "ui_left", "RIGHT": "ui_right",
			"START": "ui_accept", "A": "ui_option_a", "B": "ui_option_b", "C": "ui_option_c",
			"BACK": "ui_back"},
	Context.GAMEPLAY: {"UP": "move_up", "DOWN": "move_down", "LEFT": "move_left", "RIGHT": "move_right",
			"A": BUTTON_VERBS["A"], "B": BUTTON_VERBS["B"], "C": BUTTON_VERBS["C"], "START": "pause"},
	Context.FIGHT: {"A": "fight_block", "B": "fight_punch", "C": "fight_punch",
			"LEFT": "move_left", "RIGHT": "move_right"},
	Context.REPLAY: {"A": "replay_rewind", "B": "replay_slow", "C": "replay_play", "START": "replay_exit"},
	Context.ZAMBONI: {"UP": "zamboni_whip", "DOWN": "zamboni_whip", "LEFT": "zamboni_whip", "RIGHT": "zamboni_whip"},
}


## The verbs Genesis [param button] stands for in context [param ctx].
static func verbs_of(ctx: int, button: String) -> Array[String]:
	var v: Variant = PAD_TO_VERB[ctx].get(button, "")
	var out: Array[String] = []
	if v is Array:
		out.assign(v)
	elif v != "":
		out.append(v)
	return out


## Every per-player verb.
static func player_verbs() -> Array[String]:
	var out: Array[String] = []
	out.append_array(GAMEPLAY)
	out.append_array(FIGHT)
	out.append_array(REPLAY)
	out.append_array(ZAMBONI)
	return out


## The action name of [param verb] for [param player] (1-4); menu verbs are
## shared and keep their name.
static func action(player: int, verb: String) -> String:
	return verb if verb.begins_with("ui_") else "p%d_%s" % [player, verb]


## The per-player form of menu verb [param verb] (`p2_ui_left`).
static func menu_action(player: int, verb: String) -> String:
	return "p%d_%s" % [player, verb]


## Every action the game defines.
static func all_actions() -> Array[String]:
	var out: Array[String] = []
	out.append_array(MENU)
	for p in range(1, PLAYERS + 1):
		for v in player_verbs():
			out.append(action(p, v))
		for v in MENU:
			out.append(menu_action(p, v))
	return out
