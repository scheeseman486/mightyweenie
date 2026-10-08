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


func attach(router: MwRouter) -> void:
	router.tick_started.connect(player.tick_start)
	router.screen_entered.connect(func(id: int, _visit: int, tick: int, _prev: int) -> void: player.screen_entered(id, tick))
	router.screen_resumed.connect(func(id: int, visit: int, _tick: int) -> void: player.resume(id, visit))
	router.pass_ended.connect(func(b: Dictionary) -> void:
		player.boundary(int(b.screen), int(b.visit), int(b.pass), int(b.tick)))


func sample(contexts: Array) -> Dictionary:
	var out := {}
	for p in range(1, MwVerbs.PLAYERS + 1):
		var mask := player.held(p)
		if mask == 0:
			continue
		for button in MwInputScript.PAD_BITS:
			if mask & MwInputScript.PAD_BITS[button]:
				for ctx in contexts:
					for verb in MwVerbs.verbs_of(ctx, button):
						out[MwVerbs.action(p, verb)] = true
						if ctx == MwVerbs.Context.MENU:
							out[MwVerbs.menu_action(p, verb)] = true
	return out
