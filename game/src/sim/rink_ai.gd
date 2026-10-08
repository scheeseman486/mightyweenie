class_name MwRinkAI
extends RefCounted
## The CPU players' AI: the think `$3BFE` (by phase) and the avoidance
## `$8820`, which the player dispatcher `$86A` ([method MwSimPlayers.update])
## runs for CPU players (every pass for the last carrier and the goalies,
## else when the think timer wraps; everyone, humans too, in phase 12).
## Research: docs/re/ai.md (the section numbers below),
## docs/re/control.md (intentions); checked think by think against the
## recordings (`tools/bin/sim-check --think`, `--ai`).
##
## Register conventions kept from the original: [member me] is a5 (the
## player), [member team] a4 (own team), [member other] a3 (the opponents);
## [member d4] is the low word of d4, -1 when the team attacks down (towards
## +y): every table point is written for a team attacking up (towards
## y = -329, own goal at +329) and mirrored through the origin by [method _m].
## Positions are rink pixels (24.8 positions asr 8, as words); comparisons
## are 16-bit, signed or unsigned as in the code ("u<" / "s<" in the notes).
## Actions are `+$70 = state; +$71 = 0; jsr $2050` ([method MwSimPlayers.enter]
## runs substate 0 at once, its draws included). RNG calls are the original's,
## in its order (the draw site is noted at each call).

# --- ROM tables (team attacking up; notes 18) ---------------------------------------------
const PHASES := 0x1C016          ## 13 longs: phase handlers; phases 13+ read on into ROLES
const ROLES := 0x1C04A           ## 5 longs: role routines (centre, wing, wing, defence, defence)
const ROLE_TABLE := 0x1C05E      ## 32 x 6 bytes: role by (position mask & $1F, position)
const FACEOFF_ROLL := 0x1C11E    ## (threshold, state) words: swipe, punch, nothing
const WING_BOXES := 0x1C12A      ## by zone: x lo, x hi, y lo, y hi (right wing)
const CENTRE_BOXES := 0x1CA72    ## by zone: x lo, x hi, y lo, y hi
const D_GOALIE_BOXES := 0x1BBCE  ## our goalie carries: by its record +7 hi eor (role - 3)
const D_RANGES := 0x1BBBA        ## our skater carries: y lo, y hi by zone
const ATTACK_POINTS := 0x1C8D6   ## the carrier's 4 points (x, y)
const CHASE_ODDS := 0x1C9F8      ## by avg(DEFENSE): "go for him" threshold
const GOON_ODDS := 0x1C164       ## by aggression (record +$E hi)
const GOON_RANGE := 0x1C17A      ## by aggression
const HAZARD_BOXES := 0x1C88E    ## by hazard kind - 1: long, half width, half height

# --- routine addresses the handler tables hold -------------------------------------------
const OPEN_PLAY := 0x3C38
const FACEOFF := 0x3CF6
const COAST := 0x3DAA
const FIGHT := 0x3D3C
const WASTE_GOALIE := 0x3E22
const WASTE_REF := 0x3DE4
const CENTRE := 0xAA66
const WING := 0x3ED0
const DEFENCE := 0x1520

const CARRIED := MwRinkState.Puck.CARRIED
const BY_TEAM_B := MwRinkState.Puck.BY_TEAM_B

var sim: MwRinkSim
var rom: PackedByteArray
var s: MwRinkState
var me: MwRinkState.Player            ## a5
var team: MwRinkState.Team            ## a4
var other: MwRinkState.Team           ## a3
var d4 := 0                           ## d4.lo: -1 attacks down
var team_b := 0                       ## d4.hi: -1 team B
# `$8820`'s working values: own position, the target's word angle, the limit
var _x := 0
var _y := 0
var _ta := 0
var _lim := 0


## `$86A`'s AI call for [param p]: the think `$3BFE`, then the avoidance
## `$8820` (which skips goalies itself).
func think(sim_: MwRinkSim, p: MwRinkState.Player, team_: MwRinkState.Team, other_: MwRinkState.Team) -> void:
	sim = sim_
	rom = sim_.rom
	s = sim_.s
	me = p
	team = team_
	other = other_
	ai_think()
	avoid()


## `$3BFE`: nothing while busy (+$70 != 0); d4 from the team's flags (+4
## bit 0 team B, bit 1 attacks down); the phase's handler (`$1C016`,
## the phase read live: a fight started earlier in the pass counts).
func ai_think() -> void:
	if me.state != 0:
		return
	team_b = -1 if team.flags4 & 1 else 0
	d4 = -1 if team.flags4 & 2 else 0
	_run(MwGfx.u32(rom, PHASES + MwRinkSim.s16(s.phase * 4)))


## `jsr (a0)` into the handler at ROM address [param h]. Phase 13 reads the
## role table: 13 the centre, 14-15 the wing routine (phase 14, out of
## play: every CPU player, goalies too, notes 4), 16-17 the defence.
func _run(h: int) -> void:
	match h:
		OPEN_PLAY: _open_play()
		FACEOFF: _faceoff()
		COAST: _coast()
		FIGHT: _fight()
		WASTE_GOALIE: _waste_goalie()
		WASTE_REF: _waste_ref()
		CENTRE: _centre()
		WING: _wing()
		DEFENCE: _defence()
		_: push_warning("MwRinkAI: no AI routine at $%X (phase %d)" % [h, s.phase])


# --- phase 0 ---------------------------------------------------------------------------------

## `$3C38`: open play (notes 5): the goalie; nothing while `$C31E` is set;
## the role (+$6A, `$3EB0`, written on every skater think); then the first
## of carrier, pass receiver (puck +$3A, also a stale one), chaser (team
## +$4A0 while the puck is loose or the other team's) and a goon's hunt;
## else the role routine, the goon pick, a check and a punch.
func _open_play() -> void:
	if me.position == 5:
		_goalie()
		return
	if s.ai_off & 0xFF00:                  # tst.b $C31E (the word's high byte)
		return
	me.role = rom[ROLE_TABLE + (team.mask & 0x1F) * 6 + me.position]
	var pk := s.puck
	var carried := pk.flags & CARRIED != 0
	if carried and pk.carrier == me:
		_carrier()
	elif not carried and pk.receiver == me:
		_receiver()
	elif not _own_puck() and team.nearest == me:
		_chaser()
	elif me.flags2 & 4:
		_hunt()
	else:
		_run(MwGfx.u32(rom, ROLES + 4 * me.role))
		_goon()
		_check()
		sim.human._punch_search(me)        # `$4298`: may override the check (notes 12.2)


## The puck is carried by this team (+$3D bit 0, bit 1 = team B has it).
func _own_puck() -> bool:
	var pk := s.puck
	return pk.flags & CARRIED != 0 and (pk.flags & BY_TEAM_B != 0) == (team_b != 0)


# --- `$3FCA`: the goalie -----------------------------------------------------------------------

## `$3FCA` (notes 6): outside the crease back to the goal line; a loose
## puck heading into the goal (90 ticks ahead): save pose or dive; with the
## puck: a pass, then to the goal mouth; slashes at a close carrier;
## else the positioning `$40E6`.
func _goalie() -> void:
	var g := _px(me)
	if absi(g.x) >= 0x2D or not sim.puck.crease(me):
		sim.human._end_save_pose(me)
		_target(-4 if g.x < 0 else 4, _m(0x13F))
		return
	var pk := s.puck
	if not pk.flags & CARRIED:
		var to := sim.human.predict(0x5A)
		var at := _px(pk)
		var c := sim.human.goal_crossing(at.x, at.y, to.x, to.y, d4 != 0)   # `$422E`, own goal line
		if c.x != 0:
			sim.human.save_to(me, MwRinkSim.s16(c.y - g.x), d4 != 0)          # `$419A`
			_target(c.y, _m(0x13F))
			return
		sim.human._end_save_pose(me)
		_position()
		return
	sim.human._end_save_pose(me)
	if pk.carrier == me:
		_pass(team, other)                 # (no exploding-puck swap for the goalie)
		_target(0, _m(0x139))
		return
	# the slash paths return without a target (quirk 18)
	var nasty := me.flags2 & 2 != 0
	if nasty or me.puck_dist >= 0x6E:
		if _check():
			return
	if (pk.flags & BY_TEAM_B != 0) != (team_b != 0):
		if nasty or me.puck_dist <= 0x20:
			if _check():
				return
		if absi(_px(pk).y) > 0x149:
			if _check():
				return
	_position()


## `$40E6`: on the line from the goal mouth (y 319) towards the puck, or
## where it will be 8-24 ticks ahead when it is more than 67 px from the
## line (one roll), about 26 x / 20 y px out (22 / 16 during a shot); at
## the puck's own offset within 30 px.
func _position() -> void:
	var at := _px(s.puck)
	var d3 := _m(0x13F)
	var dy := absi(MwRinkSim.s16(at.y - d3))
	if dy > 0x43:
		at = sim.human.predict(0xC)
		dy = absi(MwRinkSim.s16(at.y - d3))
		var look := 8
		if dy >= 0x28:
			look = 24 if (sim.rng_next() & 0x842) == 0 else 16             # $413A
		elif not s.puck.flags & CARRIED:
			look = 16 if (sim.rng_next() & 0x180) == 0 else 24             # $412A
		at = sim.human.predict(look)
		dy = absi(MwRinkSim.s16(at.y - d3))
	var x := at.x
	var y := MwRinkSim.s16(dy)
	var d2 := MwTrig.distance(x, y) & 0xFFFF
	if d2 >= 0x1E:
		var k := 0x10 if s.puck.flags & MwRinkState.Puck.SHOT else 0x14
		y = _divs(y * k, d2 + 1)           # muls.w, divs.w (toward zero)
		x = _divs(x * (k + 6), d2 + 1)
	_target(x, MwRinkSim.s16(_m(MwRinkSim.s16(-y)) + d3))


# --- `$8560`: the carrier ----------------------------------------------------------------------

## `$8560` (notes 7): shoot, else pass (an exploding puck swaps the teams:
## the "mate" is an opponent, the lane checked against the own team), else
## skate to the possession's attack point (`$1C8D6`, drawn once into +$2C;
## the wings' x mirrored for roles 1 and 3) and roll for a special play. A
## think that starts a shot or pass writes no target.
func _carrier() -> void:
	if _shoot():
		return
	var swap := s.puck.flags & MwRinkState.Puck.EXPLODING != 0
	if _pass(other if swap else team, team if swap else other):
		return
	var o := MwRinkSim.s16(me.ai_zone)
	if o < 0:
		o = sim.rng_next() & 0xC                                       # $8594
		me.ai_zone = o
	var x := MwGfx.s16(rom, ATTACK_POINTS + o)
	var y := MwGfx.s16(rom, ATTACK_POINTS + o + 2)
	if me.role == 1 or me.role == 3:
		x = MwRinkSim.s16(-x)
	_target(_m(x), _m(y))
	_special_roll()


## `$85D4`: a shot (state 5 slap / 6 wrist)? Unless ACCURACY (with the
## skulls) is 7+, a roll by the distance to the current target (the attack
## point: 1/4 far away, ~1 at it); not past the goal mouth line (-299); a
## lane roll against the distance to the net, doubled per opposing skater
## in the lane (the goalie not counted).
func _shoot() -> bool:
	var at := _px(me)
	var d := MwTrig.distance(MwRinkSim.s16(at.x - me.target_x), MwRinkSim.s16(at.y - me.target_y)) & 0xFFFF
	if sim.avg(team, rom[me.record + 0xC] & 0xF) < 7:
		var t := MwRinkSim.s16(d - 0xA4)
		var thr := 0x4000
		if t < 0:
			thr = ((((~t) & 0xFFFF) * 0xC000) / 0xA4 + 0x4000) & 0xFFFF   # mulu, divu
		if (sim.rng_next() & 0xFFFF) >= thr:                           # $862A
			return false
	if _m(at.y) <= -0x12B:
		return false
	var lane := _lane(0, _m(-0x149), other)
	var d1 := (lane.y << ((lane.z - lane.w) & 0x3F)) & 0xFFFF            # lsl.w (count mod 64)
	if (sim.rng_range(0, 0x149) & 0xFFFF) < d1:                        # $865E
		return false
	sim.players.enter(me, 6 if MwRinkSim.s16(sim.rng_next()) < 0 else 5)   # $866A
	return true


## `$8776`: the lane from the puck to ([param tx], [param ty]): (word angle,
## distance, the skaters of [param opps] no farther from the puck whose
## start-of-pass bearing from it is within 16 of the lane's - no wrap-around
## at 0/$FF -, 1 if the goalie is one of them).
func _lane(tx: int, ty: int, opps: MwRinkState.Team) -> Vector4i:
	var at := _px(s.puck)
	var ad := _dist_angle(MwRinkSim.s16(tx - at.x), MwRinkSim.s16(ty - at.y))
	var n := 0
	var g := 0
	for o in opps.players:
		if o.present and o.puck_dist <= ad.x:
			var d := MwRinkSim.s16(((o.puck_angle ^ 0x80) & 0xFF) - ad.y)
			if absi(d) < 0x10:
				n += 1
				if o.position == 5:
					g = 1
	return Vector4i(ad.y, ad.x, n, g)


## `$868E`: a pass (state 1)? On 1 think in 4; not from the slot in front of
## either net (skaters); a random slot of [param mates] (goalie: 0-9, 6-9 ->
## the defence slots 3 / 4) that is someone else, a skater, free; forward by
## more than 10 px outside the attacking zone, else within it; nobody of
## [param opps] in the lane. The receiver and its angle go to the puck.
func _pass(mates: MwRinkState.Team, opps: MwRinkState.Team) -> bool:
	if (sim.rng_next() & 0xFFFF) >= 0x4000:                            # $8690
		return false
	var g := me.position == 5
	var at := _px(me)
	if not g and at.x >= -0x38 and at.x <= 0x38 and (at.y > 0xF6 or at.y < -0xF6):
		return false
	var i := sim.rng_range(0, 9 if g else 5) & 0xFFFF                   # $86DA
	if i >= 6:
		i = (i & 1) + 3
	var mate := mates.players[i]
	if mate == me or not mate.present or mate.position == 5:
		return false
	var to := _px(mate)
	if mate.state != 0:
		return false
	if _m(at.y) > -0x6C:
		if _m(MwRinkSim.s16(at.y - to.y)) <= 0xA:
			return false
	elif _m(to.y) > -0x6C:
		return false
	var lane := _lane(to.x, to.y, opps)
	if lane.z != 0:
		return false
	s.puck.receiver_angle = lane.x & 0xFF
	s.puck.receiver = mate
	sim.players.enter(me, 1)
	return true


## `$87D8`: one roll per carrier think: the skunk's poot (team +4 bit 7
## and rng < $400, `$1FDC`), else the team's armed special play (rng <
## $1000, `$1D78`) - gated by the byte at PLAYER +$4A5 (quirk 6: the code
## reads a5 where it meant a4; the play itself is the team's).
func _special_roll() -> void:
	var r := sim.rng_next() & 0xFFFF                                   # $87DA
	if team.flags4 & 0x80 and r < 0x400:
		sim.special.armed_force(me)
		return
	if _gate_byte() != 0 and r < 0x1000:
		var _z := sim.special.fire(me)


## The byte at player +$4A5, RAM past the player: for team A slot s, team
## B's second pad (+$67, slot 0) or team B player s-1's substate (+$71);
## for team B slot s `$FFBDBD + $76 s`: RAM after the referee no code
## uses (zero in every recording) for slots 0-1, then the info plates'
## tiles (`$FFBE80`: plate 0 bytes $29, $9F, plate 1 bytes $15, $8B).
func _gate_byte() -> int:
	var b := s.teams[1]
	if me.team == 0:
		if me.index == 0:
			var pad: int = b.pads[1]
			return pad & 0xFF
		return b.players[me.index - 1].substate
	var a := 0xBDBD + 0x76 * me.index - 0xBE80
	if a < 0:
		return 0
	var v: Array = s.plates[a >> 8]
	var number: int = v[0]
	var position: int = v[1]
	var health: int = v[2]
	return MwPlate.tiles(rom, number, position, health)[a & 0xFF]


## `$8810`: the pass receiver: to the puck 8 ticks ahead.
func _receiver() -> void:
	_target_at(sim.human.predict(8))


# --- `$A16C`: the chaser -----------------------------------------------------------------------

## `$A16C` (notes 9): the team's nearest skater when the puck is loose or
## the opponents': at the loose puck; at the red line when their goalie has
## it; else every so often (counter +$2C, -240 after a DEFENSE-weighted
## roll) straight at the carrier, otherwise halfway between him and the own
## goal line.
func _chaser() -> void:
	var de := sim.avg(team, rom[me.record + 0xB] & 0xF)
	var pk := s.puck
	if not pk.flags & CARRIED:
		_target_at(sim.human.predict(8))
		return
	if pk.carrier.position == 5:
		_target(_px(me).x, 0)
		return
	var n := MwRinkSim.s16(me.ai_zone + 1)
	if n < 0:
		me.ai_zone = n & 0xFFFF
		_target_at(sim.human.predict(8))
		return
	if (sim.rng_next() & 0xFFFF) < MwGfx.u16(rom, CHASE_ODDS + 2 * de):   # $A1CA
		me.ai_zone = 0xFF10
		_target_at(sim.human.predict(8))
		return
	me.ai_zone = 0xFFFF
	var t := sim.human.predict(8)
	_target(MwRinkSim.asr(t.x, 1), MwRinkSim.asr(MwRinkSim.s16(t.y + _m(0x12B)), 1))


# --- goons: `$43F4` pick, `$44BC` hunt -----------------------------------------------------

## `$43F4` (notes 10.1): with the puck in the attacking end, an enforcer
## rolls (aggression) to pick a victim among the opposing skaters in range
## and in the cone (rel < $40 or >= $80), scored by a roll and the victim's
## rating nibble (+8 lo) weighted by record +$F hi -> +$3A, +$75 bit 2.
func _goon() -> void:
	if _zone() < 3:
		return
	if not me.flags & MwRinkState.Player.ENFORCER:
		return
	var r := sim.rng_next() & 0xFFFF                                   # $440E
	var agg := rom[me.record + 0xE] >> 4
	if r >= MwGfx.u16(rom, GOON_ODDS + 2 * agg):
		return
	var reach := MwGfx.u16(rom, GOON_RANGE + 2 * agg)
	var weight := rom[me.record + 0xF] >> 4
	var best := 0
	var victim: MwRinkState.Player = null
	for k in range(4, -1, -1):
		if reach < me.opp_dist[k]:
			continue
		var rel := (me.opp_angle[k] - me.angle) & 0xFF
		if not (rel < 0x40 or rel >= 0x80):
			continue
		var score := (sim.rng_range(0, 10) & 0xFFFF) * ((10 - weight) & 0xFFFF) & 0xFFFF   # $446C
		var o := other.players[k]
		if not o.present:
			continue
		# quirk 4: move.b into a register holding k * $76 keeps its high byte
		var d1 := ((k * 0x76) & 0xFF00) | (rom[o.record + 8] & 0xF)
		score = (score + d1 * weight) & 0xFFFF
		if score <= best:
			continue
		best = score
		victim = o
	if victim != null:
		me.victim = victim
		me.flags2 |= 4


## `$44BC` (notes 10.2): hunting +$3A while the puck is out of the own end:
## at him; with a weapon, a swing (state 4) when within its reach and in
## the cone. Dropped (+$3A = 0, bit 2 cleared) in the own end, without a
## victim on the ice (the referee's +$32 is unused RAM, zero: dropped too),
## beyond 200 px or without a weapon.
func _hunt() -> void:
	if _zone() <= 1:
		_unhunt()
		return
	var v := me.victim as MwRinkState.Player
	if v == null or not v.present:
		_unhunt()
		return
	_target_at(_px(v))
	var d := me.opp_dist[v.index]
	if d > 0xC8 or me.weapon < 0:
		_unhunt()
		return
	if d > MwGfx.u16(rom, MwSimPlayers.WEAPON_REACH + 2 * me.weapon):
		return
	var rel := (me.opp_angle[v.index] - me.angle) & 0xFF
	if rel < 0x40 or rel >= 0x80:
		sim.players.enter(me, 4)


## `$44BC`'s CLEAR: no victim, +$75 bit 2 off.
func _unhunt() -> void:
	me.victim = null
	me.flags2 &= ~4


# --- role routines (`$1C04A`; notes 11) ------------------------------------------------------

## `$AA66`: the centre (role 0). With the puck: a random point of the zone's
## box (`$1CA72`, y drawn first, x not mirrored), kept while the zone stays
## the same (rng >= $600 per think). Without: halfway across, at 162 or,
## with the puck in the own end, halfway to 189.
func _centre() -> void:
	if _own_puck():
		var z := _zone()
		var c := MwRinkSim.s16(me.ai_zone)
		if c >= 0 and c == z:
			if (sim.rng_next() & 0xFFFF) >= 0x600:                     # $AA9A
				_target(me.ai_x, me.ai_y)
				return
		me.ai_zone = z & 0xFFFF
		var b := CENTRE_BOXES + 8 * z
		var y := sim.rng_range(MwGfx.s16(rom, b + 4), MwGfx.s16(rom, b + 6))   # $AABE
		var x := sim.rng_range(MwGfx.s16(rom, b), MwGfx.s16(rom, b + 2))       # $AACA
		me.ai_x = x
		me.ai_y = _m(y)
		_target(me.ai_x, me.ai_y)
		return
	var z := _zone()
	var d1 := 0xA2
	var pk := _px(s.puck)
	if z <= 1:
		d1 = MwRinkSim.asr(MwRinkSim.s16(_m(pk.y) + 0xBD), 1)
	me.ai_zone = 0xFFFF
	_target(MwRinkSim.asr(pk.x, 1), _m(d1))


## `$3ED0`: the wings (roles 1 LW, 2 RW; everyone in phase 14). With the
## puck: a random point of the box of the zone the puck will be in 64
## ticks ahead (`$1C12A`, y drawn first, x mirrored for the left wing),
## kept like the centre's. Without: the puck's x, or the own lane (138) when
## it is on the other side; its y, held at the own blue line (197) / goal
## line in the own end.
func _wing() -> void:
	if _own_puck():
		var z := _zone(6)
		var c := MwRinkSim.s16(me.ai_zone)
		if c >= 0 and c == z:
			if (sim.rng_next() & 0xFFFF) >= 0x600:                     # $3F06
				_target(me.ai_x, me.ai_y)
				return
		me.ai_zone = z & 0xFFFF
		var b := WING_BOXES + 8 * z
		var y := sim.rng_range(MwGfx.s16(rom, b + 4), MwGfx.s16(rom, b + 6))   # $3F2A
		var x := sim.rng_range(MwGfx.s16(rom, b), MwGfx.s16(rom, b + 2))       # $3F36
		if me.role == 1:
			x = MwRinkSim.s16(-x)
		me.ai_x = _m(x)
		me.ai_y = _m(y)
		_target(me.ai_x, me.ai_y)
		return
	var pk := _px(s.puck)
	var x := pk.x
	var y := pk.y
	var d := _m(pk.x)
	if me.role == 1:
		d = MwRinkSim.s16(-d)
	if d < 0:
		x = _m(-0x8A if me.role == 1 else 0x8A)
	var z := _zone()
	if z <= 1:
		y = _m(0xC5 if z == 1 else 0x149)
	_target(x, y)


## `$1520`: the defence (roles 3 LD, 4 RD). Our goalie carries: a random
## point of a box by the goalie's record +7 (`$1BBCE`, kept on rng >= $600
## with no zone test); our skater carries (zone < 3): across from the puck
## and a new random depth every think (and the puck's +$2C = $FFFF: a5 is
## the puck there, quirk 7); else the back-check line: the deepest opponent
## (plus half his velocity towards us) + 54 px, 274 past 235.
func _defence() -> void:
	var own := _own_puck()
	var z := _zone() if own else 0
	if own and z < 3:
		var c := s.puck.carrier
		if c.position == 5:
			if MwRinkSim.s16(me.ai_zone) >= 0:
				if (sim.rng_next() & 0xFFFF) >= 0x600:                 # $156A
					_target(me.ai_x, me.ai_y)
					return
			var i := MwRinkSim.s8((rom[c.record + 7] >> 4) ^ ((me.role - 3) & 0xFF))
			var b := D_GOALIE_BOXES + 8 * i
			var y := sim.rng_range(MwGfx.s16(rom, b + 4), MwGfx.s16(rom, b + 6))   # $159A
			var x := sim.rng_range(MwGfx.s16(rom, b), MwGfx.s16(rom, b + 2))       # $15A6
			if me.role == 3:
				x = MwRinkSim.s16(-x)
			me.ai_x = _m(x)
			me.ai_y = _m(y)
			me.ai_zone = 0
			_target(me.ai_x, me.ai_y)
			return
		s.puck.owner_log |= 0xFFFF         # puck +$2C.w (sic)
		var pk := _px(s.puck)
		var x := pk.x
		var d := _m(pk.x)
		if me.role == 3:
			d = MwRinkSim.s16(-d)
		if d < 0:
			x = MwRinkSim.asr(MwRinkSim.s16(-x), 1)
		z = _zone()
		var y := sim.rng_range(MwGfx.s16(rom, D_RANGES + 4 * z), MwGfx.s16(rom, D_RANGES + 4 * z + 2))   # $1610
		_target(x, _m(y))
		return
	me.ai_zone = 0xFFFF
	var d3 := -0x174
	for o in other.players:
		if o.present:
			var y := _px(o).y
			var vy := MwRinkSim.s16(o.motion.vel[1])
			if MwRinkSim.s16(d4 ^ vy) >= 0:    # skating towards our goal: + vy / 2 (1/256 px units)
				y = MwRinkSim.s16(y + MwRinkSim.asr(vy, 1))
			y = _m(y)
			if y > d3:
				d3 = y
	d3 = MwRinkSim.s16(d3 + 0x36)
	if d3 > 0xEB:
		d3 = 0x112
	var d := _m(_px(s.puck).x)
	if me.role == 3:
		d = MwRinkSim.s16(-d)
	var x := 0
	if d >= 0:
		x = -0x5C if me.role == 3 else 0x5C
	_target(_m(x), _m(d3))


# --- actions ---------------------------------------------------------------------------------

## `$42E0`: a check within 40 px (goalie: a slash within 50) -> state 8
## (13). false: `$430E` found nobody (or a CPU skater's Death Index roll
## failed) and aborted the action.
func _check() -> bool:
	var g := me.position == 5
	if not sim.human.find_target(me, 0x32 if g else 0x28):
		return false
	sim.players.enter(me, 0xD if g else 8)
	return true


## `$453E` (phases 11, 12): a punch (state 3, 36 px) or a weapon swing
## (state 4, `$1C15A` reach) at [param o] at angle [param a], distance
## [param d] when within reach and in the cone (rel < $40 or >= $80).
func _attack(o: MwRinkState.Actor, a: int, d: int) -> void:
	var st := 4
	var reach := 0x24
	if me.weapon < 0:
		st = 3
	else:
		reach = MwGfx.u16(rom, MwSimPlayers.WEAPON_REACH + 2 * me.weapon)
	if (d & 0xFFFF) > reach:
		return
	var rel := (a - me.angle) & 0xFF
	if rel < 0x40 or rel >= 0x80:
		me.victim = o
		sim.players.enter(me, st)


# --- other phases (notes 13) -----------------------------------------------------------------

## `$3CF6` (phases 1, 9): the team's nearest skater rolls (`$1C11E`):
## swipe (state 2, 3/16), punch (3, 6/16) or nothing (7/16), +$3A = the
## other team's nearest either way; then `$508E` (returns at once outside
## phase 0) and everyone coasts.
func _faceoff() -> void:
	if team.nearest != me:
		_coast()
		return
	if me.state == 0:
		var r := sim.rng_next() & 0xFFFF                               # $3D04
		var e := FACEOFF_ROLL
		while r >= MwGfx.u16(rom, e):
			r = (r - MwGfx.u16(rom, e)) & 0xFFFF
			e += 4
		me.victim = other.nearest
		sim.players.enter(me, MwGfx.u16(rom, e + 2) & 0xFF)
	sim.puck.contact(me)
	_coast()


## `$3DAA` (phases 2, 3, 5-8, 10; the faceoff's others): 15 px ahead along
## the start-of-pass velocity (the facing when standing); goalies stay.
func _coast() -> void:
	var t := _px(me)
	if me.position != 5:
		var m := MwSimPlayers.own_motion(me)
		var a := m.y if m.x != 0 else me.angle
		t += sim.polar(a, 0xF)
	_target(t.x, t.y)


## `$3D3C` (phase 4): fighters at the first fighting opponent; the others
## gather 24 px short of him and may check. With no fighting opponent the
## loop ends on "slot 6" (quirk 16, [method _slot6]).
func _fight() -> void:
	var f := Vector2i.ZERO
	var found := false
	for o in other.players:
		if o.present and o.flags & MwRinkState.Player.FIGHTING:
			f = _px(o)
			found = true
			break
	if not found:
		f = _slot6(other)
	if me.flags & MwRinkState.Player.FIGHTING:
		_target(f.x, f.y)
		return
	var at := _px(me)
	var ad := _dist_angle(MwRinkSim.s16(f.x - at.x), MwRinkSim.s16(f.y - at.y))   # `$1545A`
	var v := sim.polar(ad.y, MwRinkSim.s16(ad.x - 0x18))
	_target(at.x + v.x, at.y + v.y)
	_check()


## What `$3D3C` reads as the position of the player slot after the last
## (team +$330): x from +$330..$333, y from +$338..$33B (+$338, +$339 and the
## high word of the first arrow's animation address).
static func _slot6(t: MwRinkState.Team) -> Vector2i:
	var x := (t.x330[0] << 24) | (t.x330[1] << 16) | (t.x330[2] << 8) | t.x330[3]
	var y := (t.x330[8] << 24) | (t.x330[9] << 16) | ((t.arrows[0].address >> 16) & 0xFFFF)
	return Vector2i(MwRinkSim.s16(MwRinkSim.asr(_s32(x), 8)), MwRinkSim.s16(MwRinkSim.asr(_s32(y), 8)))


## `$3E22` (phase 11, Waste the Goalie): the side playing it (team +5
## bit 1) goes for the other goalie (`$453E`) and its goalie coasts; the
## other side's skaters coast and its goalie may slash.
func _waste_goalie() -> void:
	var on := team.flags5 & 2 != 0
	if me.position == 5:
		if on:
			_coast()
		else:
			_check()
		return
	if not on:
		_coast()
		return
	var g := other.players[5]
	if not g.present:
		_coast()
		return
	_target_at(_px(g))
	_attack(g, me.opp_angle[g.index], me.opp_dist[g.index])


## `$3DE4` (phase 12, Waste the Ref): the side playing it (team +5 bit 0)
## goes for the referee (by position, `$1545A`); goalies and the other side
## coast.
func _waste_ref() -> void:
	if me.position == 5 or not team.flags5 & 1:
		_coast()
		return
	var r := _px(s.referee)
	_target_at(r)
	var at := _px(me)
	var ad := _dist_angle(MwRinkSim.s16(r.x - at.x), MwRinkSim.s16(r.y - at.y))
	_attack(s.referee, ad.y, ad.x)


# --- `$8820`: avoidance ----------------------------------------------------------------------

## `$8820` (notes 14): not in phases 1 / 9, busy or for goalies. The first
## obstacle on the path to the target - within min(distance, 100) px and 8
## (word angles, no wrap-around) of its bearing - turns the target 90
## degrees, 100 px out (away from the centre line inside |x| < 92, towards
## it outside) and halves the velocity: an in-ice hazard (its box's edge
## midpoints; close enough: a jump instead, state 12), an opponent (the
## carrier only), a team-mate (the own slot is the own velocity: quirk 3),
## a rink object, the net of this half.
func avoid() -> void:
	if s.phase == 9 or s.phase == 1 or me.state != 0 or me.position == 5:
		return
	var at := _px(me)
	_x = at.x
	_y = at.y
	var t := _dist_angle(MwRinkSim.s16(me.target_x - _x), MwRinkSim.s16(me.target_y - _y))
	_ta = t.y
	_lim = mini(t.x, 0x64)
	var hit := false
	for h in s.hazards:
		if h.kind == 0:
			continue
		var b := HAZARD_BOXES + 8 * (h.kind - 1)
		var w := MwGfx.s16(rom, b + 4)
		var hh := MwGfx.s16(rom, b + 6)
		var hx := MwRinkSim.s16(h.x)
		var hy := MwRinkSim.s16(h.y)
		if _on_path_at(hx - w, hy) or _on_path_at(hx, hy - hh) or _on_path_at(hx, hy + hh) or _on_path_at(hx + w, hy):
			var dc := MwTrig.distance(MwRinkSim.s16(hx - _x), MwRinkSim.s16(hy - _y))
			if MwRinkSim.s16(MwTrig.distance(w, hh) + 0x18) < MwRinkSim.s16(dc):
				hit = true
			else:
				sim.players.enter(me, 0xC)                                # jump
				return
			break
	if not hit and s.puck.flags & CARRIED and s.puck.carrier == me:
		for o in other.players:
			if _on_path(me.opp_angle[o.index], me.opp_dist[o.index]):
				hit = true
				break
	if not hit:
		for q in team.players:
			if _on_path(me.mate_angle[q.index], me.mate_dist[q.index]):
				hit = true
				break
	if not hit:
		for o in s.objects:
			if o.kind != 0 and (o.kind < 0xF or o.kind == 0x12):
				var op := _px(o)
				if _on_path_at(op.x, op.y):
					hit = true
					break
	if not hit:
		var n := _px(s.nets[1] if _y >= 0 else s.nets[0])
		hit = _on_path_at(n.x, n.y)
	if not hit:
		return
	var side := 0xFF if absi(_x) >= 0x5C else 0
	if _ta & 0x80:
		side ^= 0xFF
	var a := _ta + 0x40 if (MwRinkSim.s8(side) ^ _x) < 0 else _ta - 0x40
	var v := sim.polar(a, 0x64)
	_target(_x + v.x, _y + v.y)
	me.motion.vel[0] = MwRinkSim.asr(MwRinkSim.s16(me.motion.vel[0]), 1)
	me.motion.vel[1] = MwRinkSim.asr(MwRinkSim.s16(me.motion.vel[1]), 1)


## `$8A50`: an obstacle at word angle [param a], distance [param d] is on
## the path: nearer than the limit, within 8 of the target's bearing.
func _on_path(a: int, d: int) -> bool:
	if d >= _lim:
		return false
	if absi(MwRinkSim.s16(a - _ta)) >= 8:
		return false
	_lim = d
	return true


## `$8A20`: the same for the point ([param ox], [param oy]) (current
## positions; `$14290`'s word angle).
func _on_path_at(ox: int, oy: int) -> bool:
	var dx := MwRinkSim.s16(ox - _x)
	var dy := MwRinkSim.s16(oy - _y)
	var d := MwTrig.distance(dx, dy) & 0xFFFF
	if d >= _lim:
		return false
	return _on_path(_angle_w(dx, dy), d)


# --- helpers ---------------------------------------------------------------------------------

## `$439C` (no [param shift]) / `$437E`: the zone of the puck's y (plus the
## carrier's, else the puck's, vy << shift: 64 ticks ahead for 6) for this
## team: 0 own end past the goal line, 1 own end, 2 neutral (|y| < 108),
## 3 attacking end, 4 past the attacked goal line. The sum is a long.
func _zone(shift := -1) -> int:
	var pk := s.puck
	var d1 := 0
	if shift >= 0:
		var v: MwRinkState.Actor = pk.carrier if pk.flags & CARRIED else pk
		d1 = _s32(MwRinkSim.s16(v.motion.vel[1]) << shift)
	var y := MwRinkSim.asr(_s32(d1 + pk.motion.pos[1]), 8)
	var w := MwRinkSim.s16(y) if y < 0 else MwRinkSim.s16(-y)     # -|y| as a word
	var d0 := 0
	if w <= -0x6C:
		d0 = -1
		if w <= -0x149:
			d0 = -2
	var sg := (-1 if y < 0 else 0) ^ d4
	return MwRinkSim.s16(((d0 ^ sg) - sg) + 2)


## M(v): the table value [param v] for this team's end (negated when it
## attacks down), as a word.
func _m(v: int) -> int:
	return MwRinkSim.s16((v ^ d4) - d4)


## The target point +$24 / +$26 (words).
func _target(x: int, y: int) -> void:
	me.target_x = MwRinkSim.s16(x)
	me.target_y = MwRinkSim.s16(y)


func _target_at(t: Vector2i) -> void:
	_target(t.x, t.y)


## px(o): an object's position in pixels (x.l, y.l asr 8 as words).
static func _px(o: MwRinkState.Actor) -> Vector2i:
	return Vector2i(MwRinkSim.s16(MwRinkSim.asr(o.motion.pos[0], 8)), MwRinkSim.s16(MwRinkSim.asr(o.motion.pos[1], 8)))


## `$1427C` with `$14290`'s word angle: (distance, angle 0..$100).
func _dist_angle(dx: int, dy: int) -> Vector2i:
	return Vector2i(MwTrig.distance(dx, dy) & 0xFFFF, _angle_w(dx, dy))


## `$14290` as the AI compares it: a word, $100 (not 0) in the octant
## dx >= 0 > dy, |dx| > |dy| when the table search gives 0 (quirk 1);
## [method MwTrig.angle_of] masks it to a byte.
func _angle_w(dx: int, dy: int) -> int:
	var a := MwTrig.angle_of(rom, dx, dy)
	return 0x100 if a == 0 and dy < 0 else a


## `divs.w`: the quotient toward zero, as a word.
static func _divs(a: int, b: int) -> int:
	var q := absi(a) / absi(b)
	return MwRinkSim.s16(-q if (a < 0) != (b < 0) else q)


## A 32-bit register value, signed.
static func _s32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v
