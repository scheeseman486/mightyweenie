class_name MwLineup
extends RefCounted
## One team's line-up before a match (plan 34 section 7): who plays each
## position - C, LW, RW, LD, RD, G, the original's player +$69 order - as
## roster slots (0-23: the team record's player list, +$18). Character
## selection (111) and the captain's line-up panels change it; the rink's
## entry makes the changes ([method apply]).
##
## * **The original's starters** ([member original]): the six the rink's
##   entry puts on the ice, as plan 33's rehearsal of it shows them
##   ([method starters_of], MwMatchRehearsal).
## * **Candidates** for a position ([method candidates]): the original's
##   Reserves page's (`$11628`): first the position's player of each line
##   (the roster's slots pos, pos + 6, ...), then - the port's - every other
##   skater, best rating for the position first (`$1121E`, the rating
##   out-of-position play uses; the page offers only the best one, `$11158`).
##   Goalies only in goal and only goalies there; never a dead player (a
##   playoff run's, [method dead_mask]); never the Demon Net (owner,
##   2026-10-09: never choosable before the game starts, in any mode - it is
##   no roster player, so no list here can hold it; the in-game Reserves page
##   still offers it, as the original's).
## * **Changing** a position ([method place], [method step]): a character
##   who plays another position swaps with it, unless that position is
##   locked (refused).
##
## Node-free; the ROM's player records are read at run time.

const POSITIONS := 6
const GOALIE := 5
const LINES := 4
## Sounds: a move (`$25`), refused (`$2E`).
const SOUND_MOVE := MwSoundIds.MOVE
const SOUND_REFUSED := MwSoundIds.REFUSED

var rom: PackedByteArray
## The team (0-22).
var team := 0
## The roster slots a playoff run has dead (bits 0-23).
var dead := 0
## The original's starters by position (the rink entry's six).
var original := PackedInt32Array()
## The line-up now, by position.
var slots := PackedInt32Array()


## Team [param team_]'s line-up starting from the original's starters
## [param starters] (by position), the run's dead roster slots
## [param dead_]; a dead starter is replaced by his position's first
## live candidate (the playoffs: "dead players replaced").
func _init(rom_: PackedByteArray, team_: int, starters: PackedInt32Array, dead_ := 0) -> void:
	rom = rom_
	team = team_
	dead = dead_
	original = starters.duplicate()
	if original.size() != POSITIONS:
		original = PackedInt32Array([0, 1, 2, 3, 4, 5])
	slots = defaults()


## The line-up before anyone changes it: the original's starters, a dead
## one replaced by his position's first live candidate not playing.
func defaults() -> PackedInt32Array:
	var out := original.duplicate()
	for pos in POSITIONS:
		if alive(out[pos]):
			continue
		for c in candidates(pos):
			if not c in out:
				out[pos] = c
				break
	return out


## The player record of roster slot [param slot] (0: none).
func record(slot: int) -> int:
	if slot < 0 or slot >= 24 or rom.is_empty():
		return 0
	return MwTeams.player(rom, team, slot)


## The player's jersey number (record +4).
func number(slot: int) -> int:
	var r := record(slot)
	return rom[r + 4] if r != 0 else 0


## True when roster slot [param slot] holds a player who isn't dead (a playoff run's,
## [member dead]).
func alive(slot: int) -> bool:
	return record(slot) != 0 and dead & (1 << slot) == 0


## The roster's goalies: each line's last slot.
static func is_goalie_slot(slot: int) -> bool:
	return slot % POSITIONS == GOALIE


## The candidates for position [param pos], in order (roster slots).
func candidates(pos: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for line in LINES:
		var slot := POSITIONS * line + pos
		if alive(slot):
			out.append(slot)
	if pos == GOALIE:
		return out
	var others: Array[int] = []
	for slot in 24:
		if not is_goalie_slot(slot) and slot % POSITIONS != pos and alive(slot):
			others.append(slot)
	var score := {}
	for slot in others:
		score[slot] = rating(slot, pos)
	others.sort_custom(func(a: int, b: int) -> bool:
		return score[a] > score[b] or (score[a] == score[b] and a < b))
	out.append_array(PackedInt32Array(others))
	return out


## How well roster slot [param slot] plays position [param pos]: the
## original's position rating (`$1121E`).
func rating(slot: int, pos: int) -> int:
	var r := record(slot)
	if r == 0:
		return 0
	return MwSimPlayers.position_rating(rom, r, pos)


## Puts roster slot [param slot] at [param pos]; one playing another position
## swaps with it, unless that position is in [param locked] (false: refused).
func place(pos: int, slot: int, locked: Array = []) -> bool:
	if slots[pos] == slot:
		return true
	if not slot in candidates(pos):
		return false
	var j := slots.find(slot)
	if j >= 0:
		if j in locked:
			return false
		slots[j] = slots[pos]
	slots[pos] = slot
	return true


## Left / Right on position [param pos] ([param dir] -1 / +1): its next
## candidate in. A candidate locked at another position ([param locked]) is
## refused and passed over. Returns the sound: [constant SOUND_MOVE], or
## [constant SOUND_REFUSED] when a candidate was refused or there is no
## other.
func step(pos: int, dir: int, locked: Array = []) -> int:
	var list := candidates(pos)
	var i := list.find(slots[pos])
	var refused := false
	for n in list.size():
		i = posmod(i + dir, list.size())
		if list[i] == slots[pos]:
			break
		if place(pos, list[i], locked):
			return SOUND_REFUSED if refused else SOUND_MOVE
		refused = true
	return SOUND_REFUSED


## True when the line-up is not the original's starters (the rink's entry
## then makes changes).
func changed() -> bool:
	return slots != original


## The six on-ice roster slots by position of team [param t] in a rehearsal
## of the rink's entry (MwMatchRehearsal: the original's starters).
static func starters_of(rehearsal: MwMatchRehearsal, t: int) -> PackedInt32Array:
	var out := PackedInt32Array([0, 1, 2, 3, 4, 5])
	if rehearsal == null:
		return out
	var rink_team := rehearsal.state.teams[t]
	for k in POSITIONS:
		var p := rink_team.players[k]
		if p.record != 0:
			out[k] = p.slot
	return out


## The roster slots dead for team [param t] in the session's playoff run
## (`$12A4E`'s masks: team A's, team B's when a best of 3 keeps them; drawn
## at random at the game's start otherwise, so none known here); 0 outside
## the port's playoffs.
static func dead_mask(session: MwSession, t: int) -> int:
	if session == null or not MwFlow.port_playoffs(session):
		return 0
	var playoffs := session.playoffs
	if t == 0:
		return playoffs.dead[0] & 0x3FFFF
	return 0 if playoffs.flags & MwPlayoffs.RANDOM_DEAD else playoffs.dead[1] & 0x3FFFF


## The rink's entry for a new match (MwRink.enter_match, plan 34): the
## line-ups chosen before it ([param lineups]: per team six roster slots by
## position, or empty for the original's) made as the Reserves page's line
## changes (`$11242` -> `player_create` `$7F8`: the slot's position, his
## roster slot, one `rng_next` & $F), card by card in position order, right
## after the team set-up made the first six and before the opening faceoff.
## A card whose player is already there changes nothing and draws nothing,
## so a line-up left as the original's leaves the match the original's.
static func apply(sim: MwRinkSim, lineups: Array) -> void:
	for t in mini(lineups.size(), 2):
		var l := PackedInt32Array(lineups[t])
		if l.size() != POSITIONS:
			continue
		var rink_team := sim.s.teams[t]
		for k in POSITIONS:
			var slot := l[k]
			if slot < 0 or slot >= 24:
				continue
			var rec := MwTeams.roster_record(sim.rom, rink_team.record, slot)
			var p := rink_team.players[k]
			if rec == 0 or (p.record == rec and p.slot == slot):
				continue
			sim.players.create(p, rink_team, k, slot, k, rec)
