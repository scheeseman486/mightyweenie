class_name MwScreens
extends RefCounted
## The original's screen IDs and our scenes (docs/re/screens.md, approved
## 2026-10-06). Several IDs share a scene and tell it apart by the entry
## variant; 9 runs inside 8 (pushed over it); 11's password entry is a scene
## pushed over the playoffs. `exits` lists the screens the original can go
## to next - tests check every transition seen on the original is in here.
## [constant PORT] adds the port's own screens (plan 21), with IDs past the
## original's; the exits to them (and Menu Back's) are the port's too.
## `contexts`: the verbs each screen reads (MwVerbs, plan 22: a context per
## screen family, so one input can mean one thing per screen).

const BOOT := -1

const TABLE := {
	-1: {"name": "boot", "scene": "boot", "entry": "", "contexts": [], "exits": [0]},
	0: {"name": "title", "scene": "title", "entry": "", "contexts": [MwVerbs.Context.TITLE], "exits": [1, 100]},
	1: {"name": "main menu", "scene": "main_menu", "entry": "", "contexts": [MwVerbs.Context.SETUP],
	"exits": [2, 3, 11, 100, 107, 109, 110]},
	2: {"name": "team description", "scene": "team_description", "entry": "", "contexts": [MwVerbs.Context.TEAM_INFO],
	"exits": [1, 100]},
	3: {"name": "matchup", "scene": "matchup", "entry": "", "contexts": [MwVerbs.Context.MATCHUP], "exits": [4, 1]},
	4: {"name": "rink", "scene": "rink", "entry": "period_start",
	"contexts": [MwVerbs.Context.GAMEPLAY, MwVerbs.Context.PAUSE],
	"exits": [1, 5, 7, 10, 12, 14, 15, 16, 17, 18, 19, 100]},
	5: {"name": "rink", "scene": "rink", "entry": "faceoff",
	"contexts": [MwVerbs.Context.GAMEPLAY, MwVerbs.Context.PAUSE],
	"exits": [1, 5, 7, 10, 12, 14, 15, 16, 17, 18, 19, 100]},
	6: {"name": "rink", "scene": "rink", "entry": "continue",
	"contexts": [MwVerbs.Context.GAMEPLAY, MwVerbs.Context.PAUSE],
	"exits": [1, 5, 7, 10, 12, 14, 15, 16, 17, 18, 19, 100]},
	7: {"name": "instant replay", "scene": "instant_replay", "entry": "", "contexts": [MwVerbs.Context.REPLAY],
	"exits": [6, 12, 13, 14, 15, 16, 17, 118]},
	8: {"name": "game stats", "scene": "game_stats", "entry": "", "contexts": [MwVerbs.Context.STATS],
	"exits": [9, 12, 13, 14, 15, 16, 17]},
	9: {"name": "player stats", "scene": "player_stats", "entry": "", "contexts": [MwVerbs.Context.STATS],
	"exits": [8]},
	10: {"name": "special plays", "scene": "special_plays", "entry": "", "contexts": [MwVerbs.Context.SPECIAL_PLAYS],
	"exits": [5, 12, 13, 14, 17]},
	11: {"name": "playoffs", "scene": "playoffs", "entry": "", "contexts": [MwVerbs.Context.PLAYOFFS],
	"exits": [1, 3, 107, 110]},
	12: {"name": "scoreboard", "scene": "scoreboard", "entry": "goal", "contexts": [MwVerbs.Context.SCOREBOARD],
	"exits": [5, 7, 8, 10, 15, 16]},
	13: {"name": "scoreboard", "scene": "scoreboard", "entry": "unused", "contexts": [MwVerbs.Context.SCOREBOARD],
	"exits": [4, 7, 8, 10]},
	14: {"name": "scoreboard", "scene": "scoreboard", "entry": "period_end",
	"contexts": [MwVerbs.Context.SCOREBOARD, MwVerbs.Context.ZAMBONI], "exits": [4, 7, 8, 10]},
	15: {"name": "scoreboard", "scene": "scoreboard", "entry": "game_over", "contexts": [MwVerbs.Context.SCOREBOARD],
	"exits": [1, 7, 8]},
	16: {"name": "scoreboard", "scene": "scoreboard", "entry": "playoff_game_over",
	"contexts": [MwVerbs.Context.SCOREBOARD], "exits": [11, 7, 8]},
	17: {"name": "scoreboard", "scene": "scoreboard", "entry": "message", "contexts": [MwVerbs.Context.SCOREBOARD],
	"exits": [5, 7, 8, 10, 15, 16]},
	18: {"name": "fight", "scene": "fight", "entry": "", "contexts": [MwVerbs.Context.FIGHT], "exits": [17]},
	19: {"name": "ref wasted", "scene": "ref_wasted", "entry": "", "contexts": [], "exits": [17]},
}

## The port's own screens (plan 21; owner, 2026-10-08), one scene with an
## entry variant each: the front menu after the title (the owner's main
## menu; the original's main menu, 1, is the game setup), the options and
## the controller bindings. The front menu's exits include 0 (the credits
## roll, [MwTitleScreen] in credits mode), 2 (team descriptions) and 3 (the
## attract demo). Plan 34 (owner: the menu overhaul): START GAME -> PLAY MODE
## -> LOCAL PLAY (EXHIBITION and PLAYOFFS -> the game setup's port variants,
## continue playoffs -> LOAD GAME / PASSWORD); OPTIONS split into VISUALS,
## GAMEPLAY MODIFIERS and CONTROLS; REPLAYS. 110, the controller selection:
## the game setup's scene (its top: the teams' panels and the logo) with
## the players' columns below - every match of the port's flow comes
## through it (MwFlow.before_match). 111-113, the selection steps after it
## (MwSelection, work items 9-10): character selection (its gate, the
## captain vote and the line-up panels on the same screen), the captain vote
## without it, the line-up panels alone over the starfield - one scene, an
## entry each, fading out to the matchup. Plan 35 (work item 3): PLAY
## MODE's ONLINE MULTIPLAYER -> 119, the online pages (one scene, an entry
## each: ONLINE MULTIPLAYER, HOST GAME, JOIN GAME, LOBBY; MwOnlineMenu), and
## 123, the on-screen keyboard (pushed over a page with a text field, the
## password screen's style and verbs; a MwTextInputScreen).
##
## CREATE-A-TEAM (plan 38): 130 the team list, 131 the text entry (pushed
## over the screen whose name or text it edits; a MwTextInputScreen in
## CREATE-A-TEAM's look), 132 the team editor (its
## pages: info, colours, coach, plays, roster, players, a colour), 138 the
## home rink's 3D editor (its TEST SKATE: Player 1's gameplay verbs, turned
## with the view as the rink's). IDs from 130, clear of plan 34's and plan 35's;
## local screens only (never online: their verbs are not in the input
## stream, MwVerbs.LOCAL_CONTEXTS).
const PORT := {
	100: {"name": "front menu", "scene": "port_menu", "entry": "main", "contexts": [MwVerbs.Context.MENU],
	"exits": [0, 2, 3, 101, 106, 118, 130]},
	101: {"name": "options", "scene": "port_menu", "entry": "options", "contexts": [MwVerbs.Context.MENU],
	"exits": [100, 103, 104, 105]},
	102: {"name": "controller bindings", "scene": "port_menu", "entry": "bindings", "contexts": [MwVerbs.Context.MENU],
	"exits": [105]},
	103: {"name": "visuals", "scene": "port_menu", "entry": "visuals", "contexts": [MwVerbs.Context.MENU],
	"exits": [101]},
	104: {"name": "gameplay modifiers", "scene": "port_menu", "entry": "modifiers", "contexts": [MwVerbs.Context.MENU],
	"exits": [101]},
	105: {"name": "controls", "scene": "port_menu", "entry": "controls", "contexts": [MwVerbs.Context.MENU],
	"exits": [101, 102]},
	106: {"name": "play mode", "scene": "port_menu", "entry": "play_mode", "contexts": [MwVerbs.Context.MENU],
	"exits": [100, 107, 119]},
	107: {"name": "local play", "scene": "port_menu", "entry": "local_play", "contexts": [MwVerbs.Context.MENU],
	"exits": [1, 106, 108]},
	108: {"name": "continue playoffs", "scene": "port_menu", "entry": "continue", "contexts": [MwVerbs.Context.MENU],
	"exits": [11, 107, 109]},
	109: {"name": "saved games", "scene": "port_menu", "entry": "saved_games", "contexts": [MwVerbs.Context.MENU],
	"exits": [1, 11, 108]},
	110: {"name": "controller selection", "scene": "main_menu", "entry": "controllers",
	"contexts": [MwVerbs.Context.MENU], "exits": [1, 3, 111, 112, 113]},
	111: {"name": "character selection", "scene": "character_select", "entry": "characters",
	"contexts": [MwVerbs.Context.MENU], "exits": [3, 110]},
	112: {"name": "captain vote", "scene": "character_select", "entry": "vote", "contexts": [MwVerbs.Context.MENU],
	"exits": [3, 110]},
	113: {"name": "line-ups", "scene": "character_select", "entry": "lineups", "contexts": [MwVerbs.Context.MENU],
	"exits": [3, 110]},
	118: {"name": "replays", "scene": "port_menu", "entry": "replays", "contexts": [MwVerbs.Context.MENU],
	"exits": [7, 100]},
	119: {"name": "online multiplayer", "scene": "online", "entry": "online", "contexts": [MwVerbs.Context.MENU],
	"exits": [106, 120, 121]},
	120: {"name": "host game", "scene": "online", "entry": "host", "contexts": [MwVerbs.Context.MENU],
	"exits": [119, 122]},
	121: {"name": "join game", "scene": "online", "entry": "join", "contexts": [MwVerbs.Context.MENU],
	"exits": [119, 122]},
	122: {"name": "lobby", "scene": "online", "entry": "lobby", "contexts": [MwVerbs.Context.MENU],
	"exits": [119, 120, 121]},
	123: {"name": "on-screen keyboard", "scene": "keyboard", "entry": "", "contexts": [MwVerbs.Context.PASSWORD],
	"exits": []},
	130: {"name": "create-a-team", "scene": "create_team", "entry": "list", "contexts": [MwVerbs.Context.CREATE],
	"exits": [100, 132]},
	131: {"name": "text entry", "scene": "text_entry", "entry": "",
	"contexts": [MwVerbs.Context.PASSWORD, MwVerbs.Context.TEXT_ENTRY], "exits": []},
	132: {"name": "edit team", "scene": "create_team", "entry": "team", "contexts": [MwVerbs.Context.CREATE],
	"exits": [130, 138]},
	138: {"name": "home rink", "scene": "rink_editor", "entry": "",
	"contexts": [MwVerbs.Context.CREATE, MwVerbs.Context.RINK_EDIT, MwVerbs.Context.GAMEPLAY], "exits": [132]},
}
const FRONT_MENU := 100
const OPTIONS := 101
const BINDINGS := 102
const VISUALS := 103
const MODIFIERS := 104
const CONTROLS := 105
const PLAY_MODE := 106
const LOCAL_PLAY := 107
const CONTINUE := 108
const SAVED_GAMES := 109
const CONTROLLER_SELECT := 110
const CHARACTER_SELECT := 111
const CAPTAIN_VOTE := 112
const LINEUPS := 113
const REPLAYS := 118
const ONLINE := 119
const HOST_GAME := 120
const JOIN_GAME := 121
const LOBBY := 122
const KEYBOARD := 123
const CREATE_A_TEAM := 130
const TEXT_ENTRY := 131
const EDIT_TEAM := 132
const HOME_RINK := 138

## Scenes pushed over a screen without an ID of their own.
const EXTRA := {
	"password": {"name": "password", "scene": "password", "entry": "", "contexts": [MwVerbs.Context.PASSWORD],
	"exits": [1, 108]},
}


## Whether [param id] (a screen ID or an [constant EXTRA] key) is a known screen.
static func has(id: Variant) -> bool:
	return TABLE.has(id) or PORT.has(id) or EXTRA.has(id)


## Screen [param id]'s row ({name, scene, entry, contexts, exits}) in [constant TABLE],
## [constant PORT] or [constant EXTRA]; empty for an unknown one.
static func info(id: Variant) -> Dictionary:
	return TABLE.get(id, PORT.get(id, EXTRA.get(id, {})))


## res:// path of the scene for screen [param id] (an ID or an EXTRA key).
static func scene_path(id: Variant) -> String:
	var text: String = info(id).get("scene", "")
	return "res://scenes/%s/%s.tscn" % [text, text] if text != "" else ""


## The verb contexts ([enum MwVerbs.Context]) screen [param id] reads.
static func contexts(id: Variant) -> Array:
	return info(id).get("contexts", [])


## Screen [param id]'s entry variant ("" for none).
static func entry(id: Variant) -> String:
	return info(id).get("entry", "")


## The screens the flow can go to from screen [param id] (the original's and the port's).
static func exits(id: Variant) -> Array:
	return info(id).get("exits", [])


## Every distinct scene name.
static func scenes() -> PackedStringArray:
	var out := PackedStringArray()
	for t in [TABLE, PORT, EXTRA]:
		for k in t:
			if not t[k]["scene"] in out:
				out.append(t[k]["scene"])
	return out
