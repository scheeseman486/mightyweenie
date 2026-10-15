class_name MwScriptedInput
extends MwInputSource
## Input from an input script (docs/compare.md): the script player's
## Genesis pad masks for players 1-4, turned into verbs with the current
## screen's contexts (MwVerbs.PAD_TO_VERB). Connect it to a router with
## [method attach] so the script sees ticks, screen entries and pass
## boundaries exactly like in plan 02's comparison runs.

var player: MwScriptPlayer


func _init(script_player: MwScriptPlayer) -> void:
	player = script_player


## Hooks [member player] to [param router]: its ticks, screen entries and resumes and pass
## boundaries reach the script as in plan 02's comparison runs.
func attach(router: MwRouter) -> void:
	router.tick_started.connect(player.tick_start)
	router.screen_entered.connect(func(id: int, _visit: int, at: int, _prev: int) -> void: player.screen_entered(id, \
			at))
	router.screen_resumed.connect(func(id: int, visit: int, _tick: int) -> void: player.resume(id, visit))
	router.pass_ended.connect(func(b: Dictionary) -> void:
		player.boundary(int(b.screen), int(b.visit), int(b.pass), int(b.tick)))


## The actions held now: each player's pad mask from [member player] as the verbs it means
## in [param contexts] ([method MwVerbs.pad_actions]).
func sample(contexts: Array) -> Dictionary:
	var out := {}
	for p in range(1, MwVerbs.PLAYERS + 1):
		out.merge(MwVerbs.pad_actions(p, player.held(p), contexts))
	return out
