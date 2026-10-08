class_name MwRinkPenalties
extends RefCounted
## Penalties with penalties on (`$FFB0E5` = 1; docs/re/penalties.md, plan
## 10): the referee's ruling on a call (`$A4AA` from `$A536`), the decision
## to stop play (`$A66A`, `$A7C2`, `$A852`), the penalty box's countdowns,
## releases and order (`$A5EC`, `$A3A0`, `$A40A`), the power play (`$A888`,
## `$2824`), a power-play goal freeing a player (`$A9AC`) and sending the
## called players to the box (`$A2A4`, done by the penalty scoreboard,
## screen 17). The bribed referee's part of a call is
## [method MwSimSpecial.bribed_call].
##
## The box lives in the team object as the original keeps it (team +$362,
## [member MwRinkState.Team.stats]): three entries of $14 bytes (+$C the
## seconds left, +$E roster slot, +$F slot on the ice, +$10 the code, 0 =
## free, +$11 position, +$12 a byte of the player's record, +$13 the rank by
## time left; +0..+$B a copy of his animation object for the box display),
## then +$3D (team +$39F) players in the box, +$3E (+$3A0) calls not yet
## served, +$3F (+$3A1) flags.
##
## Codes: positive "major" calls (2 a kill, 3 Waste the Goalie's actor, 1 and
## 4), negative "minor" ones (-2 goalie check, -3 check, -4 weapon, -5 dive,
## -6 ..., -7 always, -8..-11 the bribed referee's phantoms). Minor calls on
## the screen wait (delayed: play stops when the offending team gets the
## puck); the others stop play at once.

const BOX := 0x362                   ## team offset of the box's first entry
const ENTRY := 0x14
const COUNT := 0x39F                 ## players in the box
const PENDING := 0x3A0               ## calls not yet served
const FLAGS := 0x3A1
const STOP := 0x01                   ## stop play now (`$A7C2`; phase 2)
const DELAYED := 0x02                ## a minor call waiting for the offenders to get the puck
const NOW := 0x04                    ## a call that stops play
const PHANTOM := 0x08                ## the bribed referee's phantom served (no more of them)
const POWER_PLAYS := 0x488           ## team stat: power plays (`$A888`)
const PENALTIES := 0x48A             ## team stat: penalties served
const MINUTES := 0x48C               ## team stat: penalty minutes
const TIMES := 0xA476                ## `$A482`: seconds by `$FFB0E2` - minor [3], major [3]
const RANKS := 0xA404                ## `$A40A`: the entries' +$13 offsets

var sim: MwRinkSim


func _init(sim_: MwRinkSim) -> void:
	sim = sim_


# --- the box -----------------------------------------------------------------------------------

static func byte(team: MwRinkState.Team, off: int) -> int:
	return team.stats[off - MwRinkState.Team.STATS_AT]


static func set_byte(team: MwRinkState.Team, off: int, v: int) -> void:
	team.stats[off - MwRinkState.Team.STATS_AT] = v & 0xFF


static func word(team: MwRinkState.Team, off: int) -> int:
	return team.stat(off, 2)


static func set_word(team: MwRinkState.Team, off: int, v: int) -> void:
	set_byte(team, off, v >> 8)
	set_byte(team, off + 1, v)


## Team offset of box entry [param i] (0..2).
static func entry(i: int) -> int:
	return BOX + ENTRY * i


static func count(team: MwRinkState.Team) -> int:
	return byte(team, COUNT)


static func flags(team: MwRinkState.Team) -> int:
	return byte(team, FLAGS)


static func set_flags(team: MwRinkState.Team, v: int) -> void:
	set_byte(team, FLAGS, v)


## `$A482`: the seconds a call of [param code] costs at period length row
## [param row] (`$FFB0E2`): 0 none; minor (< 0) and major from `$A476`.
static func seconds_for(rom: PackedByteArray, code: int, row: int) -> int:
	if code & 0xFF == 0:
		return 0
	var i := 2 * row + (0 if code & 0x80 else 6)
	return MwGfx.u16(rom, TIMES + i)


# --- the call `$A536` ----------------------------------------------------------------------

## The ruling on a call of [param code] against [param p] (after the bribed
## referee's part): no call with the box and the calls already at 3 or
## more, fewer than 3 skaters on the ice, [param p] already called, a
## goalie, or penalties off; codes -7, 1 and 4 count in any phase; the
## others only in open play, 3 always stops play, the rest only when the
## offender is on the screen (`$5C3C`), minor ones delayed. A call shows the
## penalty icon unless it is one of -7, 1, 4. Returns whether it counted.
func rule(code: int, p: MwRinkState.Player) -> bool:
	var s := sim.s
	var team := sim.team_of(p)
	if (byte(team, PENDING) + byte(team, COUNT)) & 0xFF > 3:
		return false
	if MwSimCollide._skaters(team) < 3:
		return false
	if p.flags & MwRinkState.Player.IN_BOX or p.position == 5 or s.penalties != 1:
		return false
	var c := MwRinkSim.s16(code)
	if c != -7 and c != 1 and c != 4:
		if s.phase != 0:
			return false
		var bit := NOW
		if c != 3:
			if not sim.collide.on_screen(p):
				return false
			if MwRinkSim.s8(c & 0xFF) < 0:
				bit = DELAYED
		set_flags(team, flags(team) | bit)
		s.penalty.flags |= 0x80
	set_byte(team, PENDING, byte(team, PENDING) + 1)
	p.flags |= MwRinkState.Player.IN_BOX
	p.penalty = c & 0xFF
	return true


# --- stopping play `$A66A` -------------------------------------------------------------------

## `$A66A` after the Jail Break banner (penalties on): in open play, whether
## a call stops play now ([method _decide]); a box marked to stop: phase 2.
func pass_start() -> void:
	var s := sim.s
	if s.penalties != 1 or s.phase != 0:
		return
	_decide()
	if flags(s.teams[0]) & STOP or flags(s.teams[1]) & STOP:
		if s.phase == 4:
			s.penalty_step = 0
		s.phase = 2


## `$A7C2`: a call that stops play now (team A's first) marks its box and
## the other's too if it has one, cancelling both teams' waiting minor
## calls ([method _cancel_minors]); else a waiting minor call stops play
## once the offending team carries the puck, cancelling the other team's.
func _decide() -> void:
	var s := sim.s
	var own := s.teams[0]
	var other := s.teams[1]
	for k in 2:
		if flags(own) & NOW:
			set_flags(own, flags(own) | STOP)
			_cancel_minors(own)
			_cancel_minors(other)
			if flags(other) & NOW:
				set_flags(other, flags(other) | STOP)
			return
		var t := own
		own = other
		other = t
	var pk := s.puck
	for k in 2:
		if flags(own) & DELAYED and pk.flags & MwRinkState.Puck.CARRIED:
			if (not pk.flags & MwRinkState.Puck.BY_TEAM_B) == (not own.flags4 & 1):
				set_flags(own, flags(own) | STOP)
				_cancel_minors(other)
				return
		var t := own
		own = other
		other = t


## `$A852`: a box with a waiting minor call drops its mark and every minor
## call of the team's six (called, code < 0): uncalled, the calls count
## down.
func _cancel_minors(team: MwRinkState.Team) -> void:
	if not flags(team) & DELAYED:
		return
	set_flags(team, flags(team) & ~DELAYED)
	for p in team.players:
		if p.flags & MwRinkState.Player.IN_BOX and MwRinkSim.s8(p.penalty) < 0:
			p.flags &= ~MwRinkState.Player.IN_BOX
			p.penalty = 0
			set_byte(team, PENDING, byte(team, PENDING) - 1)


# --- the box per clock second `$A5EC` ------------------------------------------------------------

## `$A5EC`'s part once the clock moved by [param d] seconds since the last
## count: each team's box counts down (team A first), players at 0 or less
## come out ([method release]), the box re-ranked; then the power play.
func count_down(d: int) -> void:
	for team in sim.s.teams:
		if count(team) == 0:
			continue
		for i in 3:
			var at := entry(i)
			if byte(team, at + 0x10) == 0:
				continue
			var left := MwRinkSim.s16(word(team, at + 0xC) - d)
			set_word(team, at + 0xC, left)
			if left <= 0:
				release(team, i)
		rank(team)
	power_play()


## `$A3A0`: entry [param i] of [param team]'s box frees its player: the
## entry cleared, the count down, a player object made again in his slot
## on the ice (`$7F8` from the entry's position, roster slot and slot, with
## the record the slot's object has now) who skates on (state 20).
func release(team: MwRinkState.Team, i: int) -> void:
	var at := entry(i)
	set_word(team, at + 0xC, 0)
	set_byte(team, at + 0x10, 0)
	set_byte(team, COUNT, count(team) - 1)
	var p := team.players[byte(team, at + 0xF)]
	sim.players.create(p, team, byte(team, at + 0x11), byte(team, at + 0xE), byte(team, at + 0xF), p.original)
	sim.players.enter(p, 0x14)


## `$A40A`: the entries ranked by seconds left (+$13: 0 the soonest out; a
## free entry, 0 seconds, counts as $FFFF): the original's three-step
## compare-and-swap, equal times swapping.
func rank(team: MwRinkState.Team) -> void:
	var v: Array[Vector2i] = []
	for i in 3:
		var t := word(team, entry(i) + 0xC)
		v.append(Vector2i(i, (t - 1) & 0xFFFF if t == 0 else t))
	for pair in [[0, 1], [1, 2], [0, 1]]:
		if not v[pair[0]].y < v[pair[1]].y:
			var x := v[pair[0]]
			v[pair[0]] = v[pair[1]]
			v[pair[1]] = x
	for r in 3:
		var off := MwGfx.u16(sim.rom, RANKS + 2 * v[r].x)       # $13, $27, $3B
		set_byte(team, BOX + off, r)


## `$A888`: with equal boxes no power play (it ending: the power-play clock
## 0, `$2824`); else the team with fewer players in the box has one (a new
## one counts in its +$488) and the power-play clock shows the seconds of
## the other box's entry ranked (difference - 1): when the boxes are even
## again.
func power_play() -> void:
	var s := sim.s
	var few := s.teams[0]
	var many := s.teams[1]
	var a := count(few)
	var b := count(many)
	if a == b:
		if s.clock_widget & 1:
			s.clock_widget &= ~1
			s.pp_seconds = 0
		return
	if not b > a:
		few = s.teams[1]
		many = s.teams[0]
		var t := a
		a = b
		b = t
	var r := (b - a - 1) & 0xFF
	var i := 0
	while byte(many, entry(i) + 0x13) != r:
		i += 1
	var seconds := word(many, entry(i) + 0xC)
	if not s.clock_widget & 1:
		few.add_stat(POWER_PLAYS, 1)
	s.clock_widget |= 1
	s.pp_seconds = seconds


## `$A9AC` (a goal on the power play, `$7C4E`): the box's entry with the
## fewest seconds left (the first of equals) frees its player, the box
## re-ranked, the power play updated.
func power_play_goal(team: MwRinkState.Team) -> void:
	var best := 0x7FFF
	var pick := -1
	for i in 3:
		var at := entry(i)
		if byte(team, at + 0x10) != 0 and best > word(team, at + 0xC):
			best = word(team, at + 0xC)
			pick = i
	if best == 0x7FFF:
		return
	release(team, pick)
	rank(team)
	power_play()


# --- to the box `$A2A4` (screen 17) ------------------------------------------------------------

## `$A2A4` (the penalty scoreboard, screen 17, for each called player): one
## more penalty; with a free entry in the box, the player's call there (the
## seconds `$A482`, his slots, position and code; a phantom served marks the
## box unless team +$334 is set), the team's penalty minutes and his
## (`$CB30`; whole minutes), then off the ice (`$D2C`: the call itself is cleared there);
## the box re-ranked. Returns the entry used (3: the box was full). The
## entry starts with a copy of his animation object for the box display:
## animation $1C (`$4A8A`) from its start, stopped (+6 bit 7), variant 4.
func put_in_box(p: MwRinkState.Player) -> int:
	var team := sim.team_of(p)
	team.add_stat(PENALTIES, 1)
	if count(team) == 3:
		return 3
	if MwRinkSim.s8(p.penalty) <= -8 and team.x330[4] == 0:
		set_flags(team, flags(team) | PHANTOM)
	var i := 0
	while i < 2 and byte(team, entry(i) + 0x10) != 0:
		i += 1
	var at := entry(i)
	var a := p.anim.copy()
	a.set_record(sim.rom, sim.players.anim_record(p, 0x1C))
	a.flags = (a.flags | MwAnimState.PLAYING) & ~0x80
	a.variant = 4
	var b := PackedByteArray([(a.address >> 24) & 0xFF, (a.address >> 16) & 0xFF, (a.address >> 8) & 0xFF,
			a.address & 0xFF, (a.speed >> 8) & 0xFF, a.speed & 0xFF, a.flags & 0xFF, a.variant & 0xFF,
			(a.position >> 8) & 0xFF, a.position & 0xFF, a.frame & 0xFF, 0])
	for k in 12:
		set_byte(team, at + k, b[k])
	set_byte(team, at + 0x12, sim.rom[(p.record & 0xFFFFFF) + 4] if p.record != 0 else 0)
	set_byte(team, at + 0xE, p.slot)
	set_byte(team, at + 0xF, p.index)
	set_byte(team, at + 0x11, p.position)
	set_byte(team, at + 0x10, p.penalty)
	var secs := seconds_for(sim.rom, p.penalty, sim.s.period_row)
	set_word(team, at + 0xC, secs)
	team.add_stat(MINUTES, secs / 60)
	sim.add_player_stat(p, 0, secs / 60)       # `$CB30`: his penalty minutes (first word of his entry)
	sim.players.off_ice(p)
	set_byte(team, COUNT, count(team) + 1)
	rank(team)
	return i


## The penalty scoreboard's effect on the teams (screen 17, `$E9D0` and
## `$E898`): every called player on the ice, team A's slots 0-5 then team
## B's, goes to the box ([method put_in_box]); a box entry shows him (its
## animation copy playing, +6 bit 7).
func serve_calls() -> void:
	for team in sim.s.teams:
		for p in team.players:
			if not p.present or not p.flags & MwRinkState.Player.IN_BOX:
				continue
			var i := put_in_box(p)
			if i < 3:
				set_byte(team, entry(i) + 6, byte(team, entry(i) + 6) | 0x80)
