class_name MwSimSpecial
extends RefCounted
## Special plays (`special_play_fire` $1D78, table `$1D90`; docs/re/input.md:
## 1 exploding puck, 2 rocket puck, 3 Waste the Goalie, 4 Nasty Goalie,
## 5 Player Blast, 6 Confusion, 7 Armed Force, 8 Skunk, 9 Bribe the Ref,
## 10 Waste the Ref, 11 Jail Break) and the skunk's poot (`$1FDC`), fired
## by a human holding A with the puck ([MwHumanControl]) or by the CPU
## carrier's roll ([MwRinkAI], `$87D8`; docs/re/ai.md 7.4). Each play writes
## exactly what the original writes inside the simulation segment; the
## sequences some start (phases 11 / 12, the penalty box, the messages) are
## other systems': every fired play also raises the event
## ["special_play", play, player].
##
## Team +4 bit 7 is the skunk's (play 8, five poots in +$4A6; the A tap
## poots, `$1B54`); bit 6 is Armed Force's (play 7, weapons for all). The
## older name [method armed_force] is kept for the poot.

const SOUND_HORN := 2
const SOUND_POOT := 0x2E

var sim: MwRinkSim


func _init(sim_: MwRinkSim) -> void:
	sim = sim_


## `$1D78`: fire [param p]'s team's armed play (team +$4A5) - in phase 0
## only; with none (or outside phase 0) the skunk's poot when the team has
## it. Returns the original's Z flag inverted (the human's A hold `$1B74`
## punches, `$1D36`, when false). Quirk: a play that fired returns Z set
## too: the tail's `andi #4, ccr` keeps the Z of the horn's sound call
## (`$13CEE` ends with `subq.w #1, $FFCA38`, its busy count, back to 0), so
## the carrier also swings after every play; only the poot can return true.
func fire(p: MwRinkState.Player) -> bool:
	var s := sim.s
	var team := sim.team_of(p)
	var other := sim.other_team(p)
	var play := team.special if s.phase == 0 else 0
	match play:
		0:
			if team.flags4 & 0x80:
				return not _poot(p)
			return false
		1:                                 # `$1E9C` exploding puck
			s.puck.flags |= MwRinkState.Puck.EXPLODING
		2:                                 # `$1EAA` rocket puck (bit 4: team B's)
			s.puck.flags = (s.puck.flags | MwRinkState.Puck.ROCKET) & ~MwRinkState.Puck.ROCKET_B
			if team.flags4 & 1:
				s.puck.flags |= MwRinkState.Puck.ROCKET_B
		3:
			if not _waste_goalie(p, team, other):
				return false
		4:                                 # `$1DDA` Nasty Goalie
			team.goalie().flags2 |= 2
		5:                                 # `$1ED0` Player Blast: bombs (enforcers keep their weapon)
			if not p.flags & MwRinkState.Player.ENFORCER:
				p.weapon = 3
			p.charges = 5
			p.flags2 |= 8
		6:                                 # `$1EEE` Confusion
			other.flags4 |= 0x20
		7:
			_armed_force(team)
		8:                                 # `$1F8A` Skunk: five poots
			team.flags4 |= 0x80
			team.x4a6 = 5
		9:                                 # `$1F42` Bribe the Ref: `$FFBD8E` = the team (its RAM word)
			s.bribe = MwRinkRam.TEAMS[p.team] & 0xFFFF
		10:
			_waste_ref(p, team)
		11:
			if not _jail_break(team):
				return false
		_:
			push_warning("MwSimSpecial: special play %d (no handler)" % play)
			return false
	sim.events.append(["special_play", play, p])
	_used(team, play)
	return false


## The bribed referee in a penalty call (`$A4AA` up to `$A536`: Bribe the
## Ref's effect). No call at all with the clock at 0 or the offender off
## the ice. When the team that bribed him (`$FFBD8E`) commits it (not codes
## 4, -7, 1, not during its Waste the Goalie; team +$3A1 bit 3 set: no
## call) the other team's skater nearest the puck (`$174E` with `$17A0`: on
## the ice, below state $11, humans too, its goalie slot left out) takes a
## phantom penalty -11..-8 instead (`rng_range` at `$A52E`); nobody: no
## call. Returns [code, player] for the ruling (plan 10), [] for no call.
func bribed_call(code: int, p: MwRinkState.Player) -> Array:
	var s := sim.s
	if s.clock == 0 or not p.present:
		return []
	var team := sim.team_of(p)
	if team.flags5 & 2 or code == 4 or code == -7 or code == 1:
		return [code, p]
	if s.bribe == 0 or s.bribe != MwRinkRam.TEAMS[p.team] & 0xFFFF:
		return [code, p]
	if team.stat(0x3A1, 1) & 8:
		return []
	var other := sim.other_team(p)
	var framed: MwRinkState.Player = null
	var best := 0x7FFF
	for q in other.players:
		if q == other.goalie() or not q.present or q.state >= 0x11:
			continue
		if q.position == 5 and sim.human._zone(-1 if other.flags4 & 2 else 0) > 1:
			continue
		if best < q.puck_dist:
			continue
		best = q.puck_dist
		framed = q
	if framed == null:
		return []
	return [sim.rng_range(-11, -8), framed]                             # $A52E


## `$1F9E`: the play leaves the team's list (+$330..+$337: the highest index
## holding it, `dbeq`; none: index -1, i.e. team +$32F = the goalie's +$75)
## and the armed slot (+$4A5); the horn.
func _used(team: MwRinkState.Team, play: int) -> void:
	var i := 7
	while i >= 0 and team.x330[i] != play:
		i -= 1
	if i >= 0:
		team.x330[i] = 0
	else:
		team.goalie().flags2 = 0
	team.special = 0
	sim.sound(SOUND_HORN)


## `$1DEC`: Waste the Goalie (needs the other goalie on the ice, else
## nothing fires): that team's human control passes to its goalie (`$53F0`
## picks the human as on a pick-up; pad and Player Blast bombs go along),
## the carrier lets go (`$CE4`), team +5 bit 1, phase 11 with `$FFBD90` =
## the player.
func _waste_goalie(p: MwRinkState.Player, team: MwRinkState.Team, other: MwRinkState.Team) -> bool:
	var g := other.goalie()
	if not g.present:
		return false
	var h := sim.human.pickup_switch(g, other)
	if h != null:
		g.flags &= ~MwRinkState.Player.SECOND_PAD
		g.flags |= MwRinkState.Player.HUMAN
		g.flags2 &= ~8
		h.flags &= ~MwRinkState.Player.HUMAN
		if h.flags & MwRinkState.Player.SECOND_PAD:
			g.flags |= MwRinkState.Player.SECOND_PAD
		var blast := h.flags2 & 8
		h.flags2 &= ~8
		if blast:
			g.flags2 |= 8
			g.charges = h.charges
	team.flags5 |= 2
	sim.puck.drop(p)
	sim.s.phase = 0xB
	sim.s.special_actor = p
	return true


## `$1E7A`: Waste the Ref: team +5 bit 0, the carrier lets go, phase 12
## with `$FFBD90` = the player, the bribe forgotten.
func _waste_ref(p: MwRinkState.Player, team: MwRinkState.Team) -> void:
	team.flags5 |= 1
	sim.puck.drop(p)
	sim.s.phase = 0xC
	sim.s.special_actor = p
	sim.s.bribe = 0


## `$1EFC`: Armed Force: team +4 bit 6, and a random weapon (`rng & 3`, 3 ->
## 4: no bombs) for every skater of the team without one (one draw each).
func _armed_force(team: MwRinkState.Team) -> void:
	team.flags4 |= 0x40
	for i in 5:
		var q := team.players[i]
		if q.present and q.weapon < 0:
			var w := sim.rng_next() & 3                                # $1F1E
			if w == 3:
				w = 4
			q.weapon = w


## `$1F4A`: Jail Break (needs someone in the box: team +$39F, else nothing
## fires): the three box entries (team +$362 + $14 i) in use get their +$C
## word = 5, 3, 1 (plan 10 lets them out), and `$A9F2` counts the message
## (`$FFC2F8` + 1, `$FFC2F4` = the tick).
func _jail_break(team: MwRinkState.Team) -> bool:
	if team.stat(0x39F, 1) == 0:
		return false
	for i in 3:
		var e := 0x362 + 0x14 * i
		if team.stat(e + 0x10, 1) != 0:
			var v := 2 * (2 - i) + 1
			team.stats[e + 0xC - MwRinkState.Team.STATS_AT] = (v >> 8) & 0xFF
			team.stats[e + 0xD - MwRinkState.Team.STATS_AT] = v & 0xFF
	sim.s.jail_count = (sim.s.jail_count + 1) & 0xFFFF
	sim.s.jail_tick = sim.s.tick
	return true


## `$1FDC`: the skunk's poot (team +4 bit 7; also the A tap `$1B54` and the
## CPU carrier's roll): one of the five charges (+$4A6; the last clears the
## bit), and every opposing skater within 60 px is blown away (along the
## start-of-pass bearing, at $300 - 3 x distance) and loses half his
## health (`$BC8`).
func armed_force(p: MwRinkState.Player) -> void:
	_poot(p)


## [method armed_force] returning the original's Z flag: set when the last
## opposing skater slot (4) was blown away and is left without health (the
## Z of `$BC8`'s store); the human's A hold then punches too.
func _poot(p: MwRinkState.Player) -> bool:
	var team := sim.team_of(p)
	var other := sim.other_team(p)
	sim.sound(SOUND_POOT)
	team.x4a6 = (team.x4a6 - 1) & 0xFF
	if team.x4a6 == 0:
		team.flags4 &= ~0x80
	var z := false
	for i in 5:
		var o := other.players[i]
		z = false
		if not o.present:
			continue
		var d := p.opp_dist[o.index]
		if d > 0x3C:
			continue
		sim.players._launch(o, p.opp_angle[o.index], 0x300 - 3 * d)
		var h := other.health[o.slot]
		var raw := MwRinkSim.asr(h - 0x100000000 if h >= 0x80000000 else h, 1)   # $BB4, asr.l #1
		z = sim.players.damage(o, raw) == 0
	return z
