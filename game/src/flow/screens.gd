class_name MwScreens
extends RefCounted
## The original's screen IDs and our scenes (docs/re/screens.md, approved
## 2026-10-06). Several IDs share a scene and tell it apart by the entry
## variant; 9 runs inside 8 (pushed over it); 11's password entry is a scene
## pushed over the playoffs. `exits` lists the screens the original can go
## to next - tests check every transition seen on the original is in here.
## [constant PORT] adds the port's own screens (plan 21), with IDs past the
## original's; the exits to them (and Menu Back's) are the port's too.

const BOOT := -1

const TABLE := {
	-1: {"name": "boot", "scene": "boot", "entry": "", "contexts": [], "exits": [0]},
	0: {"name": "title", "scene": "title", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [1, 100]},
	1: {"name": "main menu", "scene": "main_menu", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [2, 3, 11, 100]},
	2: {"name": "team description", "scene": "team_description", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [1]},
	3: {"name": "matchup", "scene": "matchup", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [4, 1]},
	4: {"name": "rink", "scene": "rink", "entry": "period_start", "contexts": [MwVerbs.Context.GAMEPLAY], "exits": [1, 5, 7, 10, 12, 14, 15, 16, 17, 18, 19, 100]},
	5: {"name": "rink", "scene": "rink", "entry": "faceoff", "contexts": [MwVerbs.Context.GAMEPLAY], "exits": [1, 5, 7, 10, 12, 14, 15, 16, 17, 18, 19, 100]},
	6: {"name": "rink", "scene": "rink", "entry": "continue", "contexts": [MwVerbs.Context.GAMEPLAY], "exits": [1, 5, 7, 10, 12, 14, 15, 16, 17, 18, 19, 100]},
	7: {"name": "instant replay", "scene": "instant_replay", "entry": "", "contexts": [MwVerbs.Context.REPLAY], "exits": [6, 12, 13, 14, 15, 16, 17]},
	8: {"name": "game stats", "scene": "game_stats", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [9, 12, 13, 14, 15, 16, 17]},
	9: {"name": "player stats", "scene": "player_stats", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [8]},
	10: {"name": "special plays", "scene": "special_plays", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [5, 12, 13, 14, 17]},
	11: {"name": "playoffs", "scene": "playoffs", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [1, 3]},
	12: {"name": "scoreboard", "scene": "scoreboard", "entry": "goal", "contexts": [MwVerbs.Context.MENU], "exits": [5, 7, 8, 10, 15, 16]},
	13: {"name": "scoreboard", "scene": "scoreboard", "entry": "unused", "contexts": [MwVerbs.Context.MENU], "exits": [4, 7, 8, 10]},
	14: {"name": "scoreboard", "scene": "scoreboard", "entry": "period_end", "contexts": [MwVerbs.Context.MENU, MwVerbs.Context.ZAMBONI], "exits": [4, 7, 8, 10]},
	15: {"name": "scoreboard", "scene": "scoreboard", "entry": "game_over", "contexts": [MwVerbs.Context.MENU], "exits": [1, 7, 8]},
	16: {"name": "scoreboard", "scene": "scoreboard", "entry": "playoff_game_over", "contexts": [MwVerbs.Context.MENU], "exits": [11, 7, 8]},
	17: {"name": "scoreboard", "scene": "scoreboard", "entry": "message", "contexts": [MwVerbs.Context.MENU], "exits": [5, 7, 8, 10, 15, 16]},
	18: {"name": "fight", "scene": "fight", "entry": "", "contexts": [MwVerbs.Context.FIGHT, MwVerbs.Context.MENU], "exits": [17]},
	19: {"name": "ref wasted", "scene": "ref_wasted", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [17]},
}

## The port's own screens (plan 21; owner, 2026-10-08), one scene with an
## entry variant each: the front menu after the title (the owner's "Main
## Menu"; the original's main menu, 1, is the game setup), the options and
## the controller bindings. The front menu's exits include 0 (the credits
## roll, [MwTitleScreen] in credits mode) and 3 (the attract demo).
const PORT := {
	100: {"name": "front menu", "scene": "port_menu", "entry": "main", "contexts": [MwVerbs.Context.MENU], "exits": [0, 1, 3, 101]},
	101: {"name": "options", "scene": "port_menu", "entry": "options", "contexts": [MwVerbs.Context.MENU], "exits": [100, 102]},
	102: {"name": "controller bindings", "scene": "port_menu", "entry": "bindings", "contexts": [MwVerbs.Context.MENU], "exits": [101]},
}
const FRONT_MENU := 100
const OPTIONS := 101
const BINDINGS := 102

## Scenes pushed over a screen without an ID of their own.
const EXTRA := {
	"password": {"name": "password", "scene": "password", "entry": "", "contexts": [MwVerbs.Context.MENU], "exits": [1]},
}


static func has(id: Variant) -> bool:
	return TABLE.has(id) or PORT.has(id) or EXTRA.has(id)


static func info(id: Variant) -> Dictionary:
	return TABLE.get(id, PORT.get(id, EXTRA.get(id, {})))


## res:// path of the scene for screen [param id] (an ID or an EXTRA key).
static func scene_path(id: Variant) -> String:
	var s: String = info(id).get("scene", "")
	return "res://scenes/%s/%s.tscn" % [s, s] if s != "" else ""


static func contexts(id: Variant) -> Array:
	return info(id).get("contexts", [])


static func entry(id: Variant) -> String:
	return info(id).get("entry", "")


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
