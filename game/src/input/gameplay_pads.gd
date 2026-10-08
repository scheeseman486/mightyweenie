class_name MwGameplayPads
extends RefCounted
## Gameplay verbs -> the original's pad bytes (`read_joypads` $1407E: S A C
## B R L D U, held and newly pressed) for the simulation (MwHumanControl).
##
## A button's verbs (MwVerbs.BUTTON_VERBS: B pass / release_puck /
## change_player, ...) pressed together - the default bindings put them all
## on the original button - press that button: the original's tap / hold
## timing and situation tables decide. Verbs pressed without the rest of
## their button act at once ("direct" meanings): a separately bound
## slap_shot shoots a slap shot on its press. Held verbs hold the button
## (the original reads held C for one-timers, held A for a goalie's save
## pose, the D-pad for aims).

const BITS := {"UP": 0x01, "DOWN": 0x02, "LEFT": 0x04, "RIGHT": 0x08, "B": 0x10, "C": 0x20, "A": 0x40, "START": 0x80}
const MOVES := {"move_up": 0x01, "move_down": 0x02, "move_left": 0x04, "move_right": 0x08}


## Player [param player] (1-4)'s pad this pass: {held, new, direct}.
static func read(input: MwInputFrame, player: int) -> Dictionary:
	var held := 0
	var new := 0
	var direct: Array[String] = []
	if input == null:
		return {"held": 0, "new": 0, "direct": direct}
	for v in MOVES:
		if input.player_held(player, v):
			held |= MOVES[v]
			if input.player_pressed(player, v):
				new |= MOVES[v]
	if input.player_held(player, "pause"):
		held |= BITS["START"]
		if input.player_pressed(player, "pause"):
			new |= BITS["START"]
	for button in MwVerbs.BUTTON_VERBS:
		var verbs: Array = MwVerbs.BUTTON_VERBS[button]
		var pressed: Array[String] = []
		for v in verbs:
			if input.player_held(player, v):
				held |= BITS[button]
			if input.player_pressed(player, v):
				pressed.append(v)
		if pressed.size() == verbs.size():
			new |= BITS[button]
		else:
			direct.append_array(pressed)
	return {"held": held, "new": new, "direct": direct}
