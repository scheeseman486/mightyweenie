class_name MwHumans
extends RefCounted
## Who plays (plan 34, sections 5-6): each team's players - the port's
## player numbers 1-12, in number order - and, later, their captains and
## owned positions. Chosen on the controller selection (110), kept for the
## session and in playoff saves; it replaces the original's pad mode byte.
##
## When the original could have had these players the pad mode is derived
## ([method pad_mode]) and the match is the original's: team A / team B
## players (1, 0) -> mode 0, (1, 1) -> 1, (2, 0) -> 2, (2, 1) -> 3,
## (2, 2) -> 4, (0, 0) -> 5 (CPU v CPU). The original's pad slots
## (`$1BFFE`: each mode's two slots a team) then hold the players in number
## order - team A's first in its first slot, and so on ([method
## pad_players]); the screens of a match read the original's pads 1-4, and
## the router hands each pad its player's inputs ([method remap]).
##
## Extended set-ups (anything else: a team with 3-6 players, team B only,
## 1 v 2; work item 8) play the port's way: every playing human is a pad of
## the match of their own - player n is match pad n - 1 ([method pad_index]),
## up to twelve - so nothing is remapped (the router leaves their inputs as
## they are, [method pad_players] is the identity) and the rink and the
## screens between plays read all twelve. Each team's match pads in number
## order ([method match_pads]) go to the match at the rink's entry
## ([member MwMatchSetup.extended], MwSelection.for_the_rink); the setup's pad mode
## byte holds the nearest original mode ([method nearest_mode]), whose two
## slot bytes a team keeps (the AI's gate byte reads one of them, a quirk:
## MwRinkAi._gate_byte).

const TEAM_MAX := 6
## (team A players, team B players) -> the original's pad mode.
const MODES := {Vector2i(1, 0): 0, Vector2i(1, 1): 1, Vector2i(2, 0): 2, Vector2i(2, 1): 3,
		Vector2i(2, 2): 4, Vector2i(0, 0): 5}
const MIDDLE := -1

## Each team's players, in number order.
var teams: Array = [[], []]

# --- work items 9-10 (section 7): owners, captains, line-ups ------------------------------------
## The positions, in the original's player +$69 order (`MwRinkState.Player.position`).
const POSITIONS: Array[String] = ["C", "LW", "RW", "LD", "RD", "G"]
const GOALIE := 5
## Each player's own position on their team (player -> 0-5, [constant
## POSITIONS]), set by character selection (111). Empty: nobody owns a
## position - the original's co-op (the pads switch as the original's do).
var positions := {}
## Each team's captain (a player number; 0: none - no captain mode, or not
## voted yet). The captaincy belongs to the player (section 7).
var captains := [0, 0]
## Each team's line-up as chosen before the match (character selection's
## picks and the captain's line-up panels): six roster slots by position
## (the team record's player index 0-23, [constant POSITIONS] order); empty:
## the original's starters (no change, no draw at the rink's entry).
var lineups: Array = [PackedInt32Array(), PackedInt32Array()]
## Players who left with QUIT GAME and haven't rejoined (the CPU drives
## their skater; their position stays theirs). Match state, not saved.
var out := {}


## True when players own positions (character selection happened).
func owners() -> bool:
	return not positions.is_empty()


## The player who owns position [param pos] on team [param t] (0: nobody).
func owner_of(t: int, pos: int) -> int:
	for p in teams[t]:
		if int(positions.get(p, -1)) == pos:
			return p
	return 0


## Team [param t]'s captain (0: none).
func captain_of(t: int) -> int:
	return int(captains[t])


## The team [param player] plays for: 0 (A), 1 (B), [constant MIDDLE] none.
func team_of(player: int) -> int:
	for t in 2:
		if player in teams[t]:
			return t
	return MIDDLE


## Puts [param player] on team [param t] ([constant MIDDLE]: off both),
## in number order. False when the team is full.
func set_team(player: int, t: int) -> bool:
	var was := team_of(player)
	if was == t:
		return true
	if t != MIDDLE and (teams[t] as Array).size() >= TEAM_MAX:
		return false
	if was != MIDDLE:
		(teams[was] as Array).erase(player)
		positions.erase(player)                  # a position and a captaincy are a team's
		if int(captains[was]) == player:
			captains[was] = 0
	if t != MIDDLE:
		var list: Array = teams[t]
		list.append(player)
		list.sort()
	return true


## The controller selection's Left / Right ([param dir] -1 / +1) for
## [param player]: the middle to team A (left) or team B (right), a team
## back to the middle. False when it can't move (a full team, the edge).
func move(player: int, dir: int) -> bool:
	var t := team_of(player)
	match t:
		MIDDLE:
			return set_team(player, 0 if dir < 0 else 1)
		0:
			return dir > 0 and set_team(player, MIDDLE)
		_:
			return dir < 0 and set_team(player, MIDDLE)


## How many players team [param t] has.
func count(t: int) -> int:
	return (teams[t] as Array).size()


## How many players the two teams have together.
func total() -> int:
	return count(0) + count(1)


## The original's pad mode these players fit (0-5), -1 for an extended
## set-up (a team with 3-6 players, team B only, 1 v 2).
func pad_mode() -> int:
	return int(MODES.get(Vector2i(count(0), count(1)), -1))


## True when the original could have had these players ([method pad_mode] 0-5).
func original() -> bool:
	return pad_mode() >= 0


## The pad mode the setup's byte holds (`$FFB0E0`): [method pad_mode] when
## the original could have had these players, else the nearest of the
## original's: each team's players capped at the original's (team A two;
## team B two when team A has two, else one), and a count the original has
## no mode for (team B only) mode 4 (2 v 2). It keeps whether team B has
## players (the password's swap test, `$12580`, reads the mode for that:
## MwPlayoffs.make_password).
func nearest_mode() -> int:
	var mode := pad_mode()
	if mode >= 0:
		return mode
	var a := mini(count(0), 2)
	return MODES.get(Vector2i(a, mini(count(1), 2 if a == 2 else 1)), 4)


## The match pad (0-11) of [param player] in an extended set-up: player n's
## inputs are pad n - 1's (`p<n>_*`), so a player is the same pad on every
## screen; -1 when [param player] isn't playing.
func pad_index(player: int) -> int:
	return player - 1 if team_of(player) != MIDDLE else -1


## Each team's match pads in number order ([method pad_index]): what an
## extended set-up's teams hold as their pad slots (MwRinkState.Team
## port_pads; up to six). Empty for the set-ups the original could have
## had, whose pads are the pad mode's.
func match_pads() -> Array:
	if original():
		return []
	var team_pads := []
	for t in 2:
		var pads := PackedInt32Array()
		for p: int in teams[t]:
			pads.append(pad_index(p))
		team_pads.append(pads)
	return team_pads


## Writes these players into [param setup] for a match: the pad mode byte
## ([method nearest_mode]). (An extended set-up's match pads, [method
## match_pads], reach the rink at its entry: MwSelection.for_the_rink.)
func apply_to(setup: MwMatchSetup) -> void:
	setup.pads = nearest_mode()


## The player on each of the original's pads 1-4 (index 0-3; 0 none) in
## the derived pad mode: team A's players in its slots, then team B's
## (`$1BFFE`, read from the ROM). A pad no slot uses goes to its own number's
## player when that player isn't playing (the original's idle pads), else to
## nobody. Extended set-ups: pads 1-4 are players 1-4 - each player is their
## own match pad ([method pad_index]), nothing is remapped.
func pad_players(rom: PackedByteArray) -> PackedInt32Array:
	var players := PackedInt32Array([0, 0, 0, 0])
	var mode := pad_mode()
	if mode < 0:
		return PackedInt32Array([1, 2, 3, 4])
	for t in 2:
		for i in 2:
			var slot: int = rom[MwRinkMatch.PAD_MODES + 4 * mode + 2 * t + i]
			if slot != 0xFF and i < count(t):
				players[slot & 3] = teams[t][i]
	for pad in 4:
		if players[pad] == 0 and team_of(pad + 1) == MIDDLE and not (pad + 1) in players:
			players[pad] = pad + 1
	return players


## The players of the original's pad mode [param mode]: pad k's slot to
## player k + 1 (the original's own set-ups).
static func from_pad_mode(rom: PackedByteArray, mode: int) -> MwHumans:
	var humans := MwHumans.new()
	if mode < 0 or mode > 5:
		return humans
	for t in 2:
		for i in 2:
			var slot: int = rom[MwRinkMatch.PAD_MODES + 4 * mode + 2 * t + i]
			if slot != 0xFF:
				humans.set_team((slot & 3) + 1, t)
	return humans


## [param actions] (a pass's held or newly pressed actions) as the
## original's pads see them: player [code]pad_map[k][/code]'s actions as pad
## k + 1's (`p7_pass` -> `p1_pass`), players on no pad dropped; the shared
## menu verbs and the views as they are.
static func remap(actions: Dictionary, pad_map: PackedInt32Array) -> Dictionary:
	var pad_actions := {}
	for a: String in actions:
		var pv := MwVerbs.parse_action(a)
		if int(pv[0]) < 0:
			pad_actions[a] = actions[a]                # shared
			continue
		var k := pad_map.find(int(pv[0]))
		if k >= 0:
			pad_actions[MwVerbs.player_key(k + 1, pv[1])] = actions[a]
	return pad_actions


## Plan 40 (S13): a pass's input as the original's pads see it, from the
## one player -> pad table [param pad_map]: the held and newly pressed
## actions ([method remap]), the analogue sticks and the shot heights
## ([MwInputFrame.sticks], [MwInputFrame.heights]: players 1-12's, player 1
## first; [method by_pad]: a pad no player is on has no stick, ZERO, and
## the D-pad's height, -1). Returns [held, pressed, sticks, heights].
static func remapped(pad_map: PackedInt32Array, held: Dictionary, pressed: Dictionary, sticks: Array,
		heights: Array) -> Array:
	return [MwHumans.remap(held, pad_map), MwHumans.remap(pressed, pad_map), by_pad(sticks, pad_map, Vector2i.ZERO),
			by_pad(heights, pad_map, -1)]


## Players' values [param values] (player 1 first) by the original's pads:
## pad k + 1's is player [code]pad_map[k][/code]'s, [param none] for a pad
## no player is on (or one past the values). Empty: empty.
static func by_pad(values: Array, pad_map: PackedInt32Array, none: Variant) -> Array:
	if values.is_empty():
		return values
	var pad_values := []
	for k in values.size():
		var player := pad_map[k] if k < pad_map.size() else 0
		pad_values.append(values[player - 1] if player >= 1 and player <= values.size() else none)
	return pad_values


## True when [param pad_map] changes nothing (pads 1-4 are players 1-4).
static func identity(pad_map: PackedInt32Array) -> bool:
	return pad_map.is_empty() or pad_map == PackedInt32Array([1, 2, 3, 4])


## The players as saves keep them: the teams, owned positions, captains and
## line-ups (not who is out: match state).
func to_record() -> Dictionary:
	var pos := {}
	var owned := positions.keys()
	owned.sort()                               # plan 35: one order whatever order they picked in
	for p in owned:
		pos[str(p)] = positions[p]
	return {"a": (teams[0] as Array).duplicate(), "b": (teams[1] as Array).duplicate(),
			"positions": pos, "captains": captains.duplicate(),
			"lineups": [Array(lineups[0]), Array(lineups[1])]}


## The players a save's record [param d] holds ([method to_record]), read through [MwPlain]: a
## value of the wrong type is its default; a player number out of range, an owner or captain off
## the teams and a line-up not six long are left out.
static func from_record(d: Dictionary) -> MwHumans:
	# plan 40 (S6, the survey's B7): read through MwPlain - a host's record's
	# value of the wrong type is its default, never a script error
	var humans := MwHumans.new()
	for k in ["a", "b"]:
		for p in MwPlain.array(d.get(k)):
			var n := MwPlain.num(p)
			if n >= 1 and n <= MwVerbs.PLAYERS:
				humans.set_team(n, 0 if k == "a" else 1)
	var pos := MwPlain.dict(d.get("positions"))
	for k in pos:
		var n := MwPlain.num(k)
		if humans.team_of(n) != MIDDLE:
			humans.positions[n] = clampi(MwPlain.num(pos[k]), 0, GOALIE)
	var caps := MwPlain.array(d.get("captains", [0, 0]))
	for t in 2:
		var c := MwPlain.num(caps[t]) if t < caps.size() else 0
		humans.captains[t] = c if c in humans.teams[t] else 0
	var lu := MwPlain.array(d.get("lineups"))
	for t in mini(lu.size(), 2):
		var row := MwPlain.ints(lu[t])
		humans.lineups[t] = row if row.size() == POSITIONS.size() else PackedInt32Array()
	return humans


## A copy of these players as a save keeps them (without who is [member out]).
func copy() -> MwHumans:
	return from_record(to_record())
