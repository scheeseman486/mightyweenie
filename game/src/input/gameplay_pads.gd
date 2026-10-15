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

## The original's pad byte (MwVerbs.BITS) and the gameplay directions' bits
## (MwVerbs.PAD_TO_VERB's gameplay D-pad).
const BITS := MwVerbs.BITS
const MOVES := {"move_up": MwVerbs.BITS["UP"], "move_down": MwVerbs.BITS["DOWN"], "move_left": MwVerbs.BITS["LEFT"],
		"move_right": MwVerbs.BITS["RIGHT"]}


## Player [param player] (1-12)'s pad this pass: {held, new, direct, stick,
## height} (height: MwInputFrame.height, -1 the D-pad's).
## Plan 34: RECLAIM (MwVerbs.RECLAIM, a port verb on no Genesis button) is a
## direct meaning ("reclaim"), for the control layer (MwRinkControl).
static func read(input: MwInputFrame, player: int) -> Dictionary:
	var held := 0
	var new := 0
	var direct: Array[String] = []
	if input == null:
		return {"held": 0, "new": 0, "direct": direct, "stick": Vector2i.ZERO, "height": -1}
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
	if input.player_pressed(player, MwVerbs.RECLAIM):
		direct.append(MwVerbs.RECLAIM)
	return {"held": held, "new": new, "direct": direct, "stick": input.stick(player),
			"height": input.height(player)}


## Plan 42 (speed): [method read] for pads 1 to [param n] at once - the
## frame's held and pressed actions split by player once ([method _split])
## and each player's verbs looked up by name, not every verb's per-player
## action spelled out for every player (some 30 names a pad, 12 pads a
## pass). The same results as [method read] (test_gameplay_pads).
static func read_all(input: MwInputFrame, n: int) -> Array:
	var out := []
	if input == null:
		for pad in n:
			out.append(read(null, pad + 1))
		return out
	var held_of := _split(input.held)
	var pressed_of := _split(input.pressed)
	# (plan 42, second round: a pad that pressed nothing new - most pads, most
	# passes - holds only its held verbs' bits: no new, no direct meanings.
	# The verbs not per player count for every pad; a press of one, every pad
	# the long way.)
	if _bit_of.is_empty():
		_tables()
	var shared_held := 0
	var shared_press := false
	for v: String in _shared_bits:
		if input.held.has(v):
			shared_held |= int(_shared_bits[v])
		if input.pressed.has(v):
			shared_press = true
	for pad in n:
		var player := pad + 1
		var h: Dictionary = held_of.get(player, _EMPTY)
		var pr: Dictionary = pressed_of.get(player, _EMPTY)
		if shared_press or not pr.is_empty():
			out.append(_read_split(input, player, h, pr))
			continue
		var held := shared_held
		for v: String in h:
			held |= int(_bit_of.get(v, 0))
		var direct: Array[String] = []
		out.append({"held": held, "new": 0, "direct": direct, "stick": input.stick(player),
				"height": input.height(player)})
	return out


const _EMPTY := {}
static var _prefixed := {}      # verb -> whether its action is per player ("p3_pass"; not ui_ or local verbs)
static var _bit_of := {}        # a verb read whose action is per player -> its held bit (0: none, RECLAIM)
static var _shared_bits := {}   # a verb read whose action is not -> its held bit


## The verbs [method read] reads (the moves, pause, the buttons' verbs,
## RECLAIM) by their held bits, per player or not ([method _is_prefixed]).
static func _tables() -> void:
	var bits := {}
	for v: String in MOVES:
		bits[v] = int(MOVES[v])
	bits["pause"] = int(BITS["START"])
	for button: String in MwVerbs.BUTTON_VERBS:
		for v: String in MwVerbs.BUTTON_VERBS[button]:
			bits[v] = int(bits.get(v, 0)) | int(BITS[button])
	bits[MwVerbs.RECLAIM] = int(bits.get(MwVerbs.RECLAIM, 0))
	for v: String in bits:
		if _is_prefixed(v):
			_bit_of[v] = bits[v]
		else:
			_shared_bits[v] = bits[v]


## [param actions]' per-player actions ("p3_pass") by player: player ->
## {verb: true}.
static func _split(actions: Dictionary) -> Dictionary:
	var out := {}
	for a: String in actions:
		if a.length() < 4 or a.unicode_at(0) != 0x70:          # "p"
			continue
		var u := a.find("_", 1)
		if u < 2:
			continue
		var num := a.substr(1, u - 1)
		if not num.is_valid_int():
			continue
		var player := num.to_int()
		if not out.has(player):
			out[player] = {}
		(out[player] as Dictionary)[a.substr(u + 1)] = true
	return out


## Whether [param verb]'s action is a player's own (else the
## bare verb, MwVerbs.action) - then looked up in the split.
static func _is_prefixed(verb: String) -> bool:
	var v: Variant = _prefixed.get(verb)
	if v == null:
		v = MwVerbs.action(1, verb) != verb
		_prefixed[verb] = v
	return v


static func _has(frame_set: Dictionary, mine: Dictionary, verb: String) -> bool:
	return mine.has(verb) if _is_prefixed(verb) else frame_set.has(verb)


## [method read] of player [param player] from its split actions
## ([param h] held, [param pr] pressed).
static func _read_split(input: MwInputFrame, player: int, h: Dictionary, pr: Dictionary) -> Dictionary:
	var held := 0
	var new := 0
	var direct: Array[String] = []
	for v in MOVES:
		if _has(input.held, h, v):
			held |= MOVES[v]
			if _has(input.pressed, pr, v):
				new |= MOVES[v]
	if _has(input.held, h, "pause"):
		held |= BITS["START"]
		if _has(input.pressed, pr, "pause"):
			new |= BITS["START"]
	for button in MwVerbs.BUTTON_VERBS:
		var verbs: Array = MwVerbs.BUTTON_VERBS[button]
		var pressed: Array[String] = []
		for v in verbs:
			if _has(input.held, h, v):
				held |= BITS[button]
			if _has(input.pressed, pr, v):
				pressed.append(v)
		if pressed.size() == verbs.size():
			new |= BITS[button]
		else:
			direct.append_array(pressed)
	if _has(input.pressed, pr, MwVerbs.RECLAIM):
		direct.append(MwVerbs.RECLAIM)
	return {"held": held, "new": new, "direct": direct, "stick": input.stick(player),
			"height": input.height(player)}

