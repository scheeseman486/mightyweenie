class_name MwSimPlayers
extends RefCounted
## Players in the rink pass (docs/re/players.md): the team update `$3836`,
## the per-player dispatcher `$86A`, the animation helpers, damage and
## health, players leaving the ice and their substitutes, the state machine
## `$2050` (21 states, table `$1BC66`) and skating `$63D8`. Collisions are
## [MwSimCollide], control [MwHumanControl] / [member MwRinkSim.cpu].

const PHASE_FACEOFF := 1
const PHASE_FIGHT := 4
const PHASE_START := 9
const PHASE_REF := 12

const HEALTH_FULL := 0x800000
const REGEN := 0x48D                 ## health regained per tick on the bench
const BONE_TICKS := 0x384            ## bones last 900 ticks
const STAMINA_DAMAGE := 0x1BA90      ## damage factor by STAMINA
const SKATE_PARAMS := [0x1C5D6, 0x1C5E8]   ## skater, goalie (`$63D8`)
const SPEED_ACCEL := 0x1C610         ## by SPEED: acceleration (6 + r)
const SPEED_TOP := 0x1C5FA           ## by SPEED: top speed
const DIVE_SPEED := 0x1C8AE          ## by SPEED: dive / goalie dive launch speed
const KNOCK_ANIMS := 0x1C8C4         ## by direction of the attacker: anim or -1 (tripped)
const PASS_ANIMS := 0x1C51C          ## by direction of the receiver
const CHECK_ANIMS := 0x1C6BC         ## by direction of the victim
const IMPALE_DAMAGE := 0x1C8CC       ## by Death Index
const UNDER_ICE_KINDS := 0x9C6A      ## by species: the under-ice silhouette's object kind
const WEAPON_REACH := 0x1C15A        ## by weapon
const PUNCH_DAMAGE := 0x9766         ## by Death Index (phase 0) / [0]
const WEAPON_DAMAGE := 0x975C        ## by Death Index
const CHECK_DAMAGE := 0x1C6C4        ## by Death Index

const REF_DOWN := 0x3F2FC            ## `$EFC8`: the referee knocked down
const REF_HURT := 0xF040             ## `$EFC8`: his animations by rng_range(1, 3) (index 0 unused)
var sim: MwRinkSim
var rom: PackedByteArray
var s: MwRinkState


func _init(sim_: MwRinkSim) -> void:
	sim = sim_
	rom = sim.rom
	s = sim.s


# --- `$3836`: a team's update --------------------------------------------------------

## Formation, every occupied slot's update, the markers and the bench's
## health regeneration.
func team_update(team: MwRinkState.Team, other: MwRinkState.Team, e: int) -> void:
	formation(team)
	for i in 6:
		var p := team.players[i]
		if not p.present:
			continue
		if sim.hooks:
			sim.hooks.before_player(sim, p)
		update(p, team, other, e)
		team.health[p.slot] |= 0x80000000          # on the ice this pass
		if p.flags & MwRinkState.Player.HUMAN:
			s.update_marker(rom, team, 1 if p.flags & MwRinkState.Player.SECOND_PAD else 0, p)
		elif s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == p:
			s.update_marker(rom, team, 0, p)
	var add := (e & 0xFFFF) * REGEN
	for i in range(23, -1, -1):
		var h := team.health[i]
		if h & 0x80000000 == 0 and h != 0:
			h = mini(h + add, HEALTH_FULL)
		team.health[i] = h & 0x7FFFFFFF


## `$3E7A`: the positions on the ice (team +$4A7) and the strength key
## `$1C05E`[mask * 6 + 5] (+$4A8).
func formation(team: MwRinkState.Team) -> void:
	var mask := 0
	for p in team.players:
		if p.present:
			mask |= 1 << (p.position & 7)
	team.mask = mask & 0xFF
	team.formation = rom[0x1C05E + 5 + (mask & 0x1F) * 6]


# --- `$86A`: one player ----------------------------------------------------------------

func update(p: MwRinkState.Player, team: MwRinkState.Team, other: MwRinkState.Team, e: int) -> void:
	if s.phase != PHASE_START:
		var gated := s.phase == PHASE_REF
		if not gated and p.flags & MwRinkState.Player.HUMAN:
			_tick(p, e)
			sim.human.buttons(p, team, e)
			step(p)
			skate(p, e)
		elif not gated and (s.puck.carrier == p or p.position == 5):
			# the last puck carrier (even with the puck loose) and goalies think every pass
			_tick(p, e)
			sim.cpu.think(sim, p, team, other)
			step(p)
			skate(p, e)
		else:
			# other CPU skaters (everyone in phase 12) every 12 ticks
			var r := p.think - e
			p.think = MwRinkSim.s8(r)
			if r <= 0:
				p.think = MwRinkSim.s8(p.think + 12)
				sim.cpu.think(sim, p, team, other)
				step(p)
				skate(p, 12)
	if p.flags & (MwRinkState.Player.BLACK_BONE | MwRinkState.Player.WHITE_BONE):
		sim.tick_at(7)
		if (s.tick - p.bone_tick) & 0xFFFF >= BONE_TICKS:
			p.flags &= ~(MwRinkState.Player.BLACK_BONE | MwRinkState.Player.WHITE_BONE)
	if p.position == 5:
		if in_crease(p):
			var x := p.motion.pos[0]
			var y := p.motion.pos[1]
			move(p, e)
			if not in_crease(p):           # a step out of the crease is undone (velocity kept)
				p.motion.pos[0] = x
				p.motion.pos[1] = y
		else:
			move(p, e)
	elif p.state == 0x11:
		p.anim.advance(e)                  # impaled: no motion
	else:
		move(p, e)
	if p.state != 0x14:
		sim.collide.player(p, e)


## The think timer's decrement on the every-pass paths (no effect).
func _tick(p: MwRinkState.Player, e: int) -> void:
	var r := p.think - e
	p.think = MwRinkSim.s8(r)
	if r <= 0:
		p.think = MwRinkSim.s8(p.think + 12)


## `$141AE`: motion step (player parameters) and animation.
func move(p: MwRinkState.Player, e: int) -> void:
	p.motion.step(s.player_params, e)
	p.anim.advance(e)


## `$9AE`: inside the goalie crease (x' = x - x / 4, y' = |y| - 322, length <= 55).
func in_crease(p: MwRinkState.Player) -> bool:
	var px := p.motion.pixels()
	var x := MwRinkSim.s16(px.x - MwRinkSim.asr(MwRinkSim.s16(px.x), 2))
	var y := MwRinkSim.s16(absi(MwRinkSim.s16(px.y)) - 0x142)
	if y >= 0:
		return false
	return MwTrig.distance(x, y) & 0xFFFF <= 0x37


# --- animation ---------------------------------------------------------------------------

## `$4ABE`: the animation record of [param id] for [param p]'s species.
func anim_record(p: MwRinkState.Player, id: int) -> int:
	return MwPlayerAnims.anim(rom, p.original, id)


## `$4A8A`: play animation [param id] from its start (variant kept).
func play(p: MwRinkState.Player, id: int) -> void:
	p.anim_id = id & 0xFF
	p.anim.set_record(rom, anim_record(p, id & 0xFF))
	p.anim.flags |= MwAnimState.PLAYING


## `$4AA6`: stopped (animation 0 at frame 0, id $FF).
func stop(p: MwRinkState.Player) -> void:
	p.anim_id = 0xFF
	p.anim.set_record(rom, anim_record(p, 0))


func playing(p: MwRinkState.Player) -> bool:
	return p.anim.flags & MwAnimState.PLAYING != 0


## Variant from a facing: ((a + $50) & $FF) >> 5 (0 up, 2 right, 4 down, 6 left).
static func variant_of(a: int) -> int:
	return ((a + 0x50) & 0xFF) >> 5


## Face angle [param a] (facing and variant).
func face(p: MwRinkState.Player, a: int) -> void:
	p.angle = a & 0xFF
	p.anim.variant = variant_of(a)


## `$C66`: [param p]'s own entry of the geometry: (speed, velocity angle).
static func own_motion(p: MwRinkState.Player) -> Vector2i:
	return Vector2i(p.mate_dist[p.index], p.mate_angle[p.index])


## `$C7C`: [param p]'s geometry entry for opponent [param o]: (distance, angle).
static func to_opponent(p: MwRinkState.Player, o: MwRinkState.Player) -> Vector2i:
	return Vector2i(p.opp_dist[o.index], p.opp_angle[o.index])


## `$6CA2`: the direction of [param angle] relative to [param facing]: 0
## ahead, 2 right ($40 side), 4 behind, 6 left (odd octants rounded up).
static func direction(angle: int, facing: int) -> int:
	var d := ((angle - facing) & 0xFF) >> 5
	if d & 1:
		d = (d + 1) & 7
	return d


## Enter state [param st] and run its first substate at once (`$2050`).
func enter(p: MwRinkState.Player, st: int) -> void:
	p.state = st & 0xFF
	p.substate = 0
	step(p)


## Back to skating: stopped animation, state 0.
func done(p: MwRinkState.Player) -> void:
	stop(p)
	enter(p, 0)


func _end_to_skate(p: MwRinkState.Player) -> void:
	if not playing(p):
		done(p)


# --- health ------------------------------------------------------------------------------

## `$BC8`: [param raw] damage, scaled by STAMINA (`$1BA90`; halved for
## enforcers' rating, halved again for goalies); health 0 -> state 18
## (killed). Returns the health left.
func damage(p: MwRinkState.Player, raw: int) -> int:
	var st := rom[p.record + 8] >> 4
	if p.flags & MwRinkState.Player.ENFORCER:
		st >>= 1
	var d := ((raw >> 8) & 0xFFFF) * MwGfx.u16(rom, STAMINA_DAMAGE + 2 * st)
	if p.position == 5:
		d >>= 1
	var team := sim.team_of(p)
	var h := team.health[p.slot]
	if h == 0:
		return 0
	var hs := h - 0x100000000 if h >= 0x80000000 else h
	var left := hs - d
	if left > 0:
		team.health[p.slot] = left
		return left
	enter(p, 0x12)
	team.health[p.slot] = 0
	return 0


## `$C1A`: a death: the team's deaths +1, then as `$C1E`.
func died(p: MwRinkState.Player) -> void:
	var team := sim.team_of(p)
	team.add_stat(0x49A, 1)
	off_ice_dead(p)


## `$C1E`: health 0, off the ice (`$D2C`), a substitute (`$F6A8`) who
## skates on from the bench (state 20), else the slot stays empty; in open
## play the forfeit check (`$F7C8`).
func off_ice_dead(p: MwRinkState.Player) -> void:
	var team := sim.team_of(p)
	team.health[p.slot] = 0
	off_ice(p)
	substitute(p)
	if p.present:
		enter(p, 0x14)                 # the substitute comes on from the bench
	if s.phase == 0 and forfeits(team):
		s.phase = 13
		s.scoring = 0xFFFF0000 | (MwRinkRam.TEAMS[p.team] & 0xFFFF)   # a sign-extended team address


## `$D2C`: off the ice: to the bench door (265, 10), control handed on,
## the puck dropped, out of the penalty box, the slot emptied.
func off_ice(p: MwRinkState.Player) -> void:
	p.motion.init(0x109, 0xA, 0)
	sim.human.lose_control(p)
	sim.puck.drop(p)
	if p.flags & MwRinkState.Player.IN_BOX:
		var team := sim.team_of(p)
		p.penalty = 0
		p.flags &= ~MwRinkState.Player.IN_BOX
		var n := (team.stat(0x3A0, 1) - 1) & 0xFF
		team.stats[0x3A0 - MwRinkState.Team.STATS_AT] = n
		if n == 0:
			team.stats[0x3A1 - MwRinkState.Team.STATS_AT] &= 8
	p.record = 0


## `$F7C8`: fewer than 2 skaters, or no goalie (unless a Demon Net guards
## the top end for a team attacking down - `$7A6`).
func forfeits(team: MwRinkState.Team) -> bool:
	var n := 0
	var goalies := 0
	for q in team.players:
		if q.present:
			n += 1
			if q.position == 5:
				goalies += 1
	if n - goalies < 2:
		return true
	if goalies == 0:
		return not (team.flags4 & 2 and s.nets[0].style == 0)
	return false


## `$F6A8`: the best available roster player for [param p]'s position takes
## the slot (`$F72C`; `$7F8` creates him), keeping human control and the
## Player Blast weapon.
func substitute(p: MwRinkState.Player) -> void:
	var team := sim.team_of(p)
	var pos := p.position
	var pick := _best_substitute(team, pos)
	if pick.y == 0:
		return
	var human := p.flags & MwRinkState.Player.HUMAN
	var second := p.flags & MwRinkState.Player.SECOND_PAD
	var charges := p.charges
	var blast := p.flags2 & 8
	create(p, team, pos, pick.x, pos, pick.y)
	if blast:
		p.flags2 |= 8
		p.charges = charges
		if not p.flags & MwRinkState.Player.ENFORCER:
			p.weapon = 3
	if second:
		p.flags |= MwRinkState.Player.SECOND_PAD
	if human:
		p.flags |= MwRinkState.Player.HUMAN


## `$F72C`: (roster slot, record) of the best substitute for position
## [param pos] (record 0: none). Score = the position's rating (`$1121E`)
## x min(health / 65536, 64), doubled for a player of that position; not
## in the penalty box, alive, not already on the ice.
func _best_substitute(team: MwRinkState.Team, pos: int) -> Vector2i:
	var best := 0
	var slot := 0
	var rec := 0
	var d5 := 0
	for i in 24:
		var ok := (d5 == 5) if pos == 5 else (d5 != 5)
		if ok and not _in_box(team, i):
			var r := MwGfx.u32(rom, team.record + 0x18 + 4 * i)
			var on := false
			for k in 5:
				if team.players[k].original == r:
					on = true
			if not on:
				var score := _position_rating(r, pos)
				var h := team.health[i]
				if h != 0:
					var hw := MwRinkSim.s16(h >> 16)
					if hw >= 0x40:
						hw = 0x40
					score = (score * (hw & 0xFFFF)) & 0xFFFF
					if d5 == pos:
						score = (score * 2) & 0xFFFF
					if MwRinkSim.s16(score) > MwRinkSim.s16(best):
						best = score
						slot = i
						rec = r
		d5 += 1
		if d5 >= 6:
			d5 = 0
	return Vector2i(slot, rec)


## `$A212`: roster slot [param i] sits in one of the 3 penalty box entries.
func _in_box(team: MwRinkState.Team, i: int) -> bool:
	for k in 3:
		var at := 0x362 + 0x14 * k
		if team.stat(at + 0x10, 1) != 0 and team.stat(at + 0xE, 1) == i:
			return true
	return false


## `$1121E`: how well record [param r] plays position [param pos] (a byte sum
## of weighted ratings; `$11044`-`$1113A`).
func _position_rating(r: int, pos: int) -> int:
	var b := func(off: int, high: bool) -> int: return (rom[r + off] >> 4) if high else (rom[r + off] & 0xF)
	var d := 0
	match pos:
		0:
			d = 4 * b.call(8, false) + 4 * b.call(9, false) + 2 * b.call(0xA, false) + 2 * b.call(0xC, false) + 2 * b.call(0xB, true)
		1, 2:
			if (rom[r + 7] >> 4) == pos - 1:
				d = 0x14
			d += 4 * b.call(8, false) + 4 * b.call(9, false) + b.call(0xA, false) + b.call(0xC, false) + 2 * b.call(0xB, true)
		3, 4:
			if (rom[r + 7] >> 4) == pos - 3:
				d = 0x14
			d += 4 * b.call(8, false) + 2 * b.call(9, false) + 2 * b.call(0xA, true) + 2 * b.call(0xD, false) + 2 * b.call(0xB, false)
		5:
			if rom[r + 7] & 0xF == 4:
				d = 4 * b.call(8, false)
	return d & 0xFF


## `$7F8`: a player object for record [param record] (0: the slot stays
## empty) in on-ice slot [param index], roster slot [param slot], position
## [param pos]: not targeting anyone, AI memory cleared, a random nibble,
## the staggered think timer, flags cleared, the enforcer's weapon.
func create(p: MwRinkState.Player, team: MwRinkState.Team, pos: int, slot: int, index: int, record: int) -> void:
	p.record = record
	p.original = record
	if record == 0:
		return
	p.index = index & 0xFF
	p.slot = slot & 0xFF
	p.position = pos & 0xFF
	p.victim = null
	p.ai_zone = 0xFFFF
	p.init_roll = sim.rng_next() & 0xF
	p.think = MwRinkSim.s8(2 * index + (1 if team == s.teams[1] else 0))
	p.flags = 0
	p.flags2 = 0
	if rom[record + 0xD] >> 4 == 0:
		p.weapon = -1
	else:
		p.flags |= MwRinkState.Player.ENFORCER
		p.weapon = rom[record + 0xE] & 0xF


# --- `$2050`: the state machine ------------------------------------------------------------

## Run [param p]'s current substate. Handlers test animation positions
## (8.8 frames) and the playing bit; they get no elapsed time.
func step(p: MwRinkState.Player) -> void:
	var sub := p.substate
	var pos := p.anim.position
	match p.state:
		0:
			pass
		1:
			match sub:
				0: _pass_start(p)
				1:
					if MwRinkSim.s16(pos) >= 0x180:
						p.substate += 1
						if s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == p:
							sim.puck.pass_release(p)
						else:
							p.anim.flags &= ~MwAnimState.PLAYING
				2: _end_to_skate(p)
		2:
			match sub:
				0:
					play(p, 9)
					sim.positional(0x27, p)       # `$4FCA`
					p.substate += 1
				1: _end_to_skate(p)
		3:
			match sub:
				0: _punch_start(p, 10)
				1: _punch_hit(p)
				2: _end_to_skate(p)
		4:
			match sub:
				0: _weapon_start(p)
				1: _weapon_hit(p)
				2:
					if not playing(p):
						if p.weapon == 2:
							sim.positional(0x2D, p)   # `$9AC4`
						_end_to_skate(p)
		5:
			match sub:
				0: _shot_start(p)
				1:
					if MwRinkSim.s16(pos) >= 0x280:
						p.substate += 1
						if s.puck.carrier != p:
							p.anim.position = 0x900
							p.substate = 3
				2: _shot_release(p, 0x580)
				3: _end_to_skate(p)
				4: _shot_release(p, 0x300)
				5: _end_to_skate(p)
		6, 7:
			match sub:
				0: _shot_start(p)
				1: _shot_release(p, 0x580)
				2: _end_to_skate(p)
				3: _shot_release(p, 0x300)
				4: _end_to_skate(p)
		8:
			match sub:
				0: _check_start(p)
				1:
					if MwRinkSim.s16(pos) >= 0x280:
						sim.collide.check_hit(p)
				2: _end_to_skate(p)
		9, 10:
			match sub:
				0: _dive_start(p)
				1:
					if MwRinkSim.s16(pos) >= 0x480:
						p.anim.flags &= ~MwAnimState.PLAYING
						p.substate += 1
				2:
					if MwRinkSim.asr(p.motion.pos[2], 8) == 0:
						p.anim.flags |= MwAnimState.PLAYING
						sim.positional(0x23, p)   # `$82C8`
						p.substate += 1
				3:
					if MwRinkSim.s16(own_motion(p).x) <= 0x200:
						play(p, 0x1B)
						p.substate += 1
				4: _end_to_skate(p)
		11:
			match sub:
				0:
					play(p, 1)
					p.motion.vel[2] = 0x140
					_launch(p, p.angle, _dive_speed(p))
					p.substate += 1
				1:
					if MwRinkSim.s16(sim.velocity(p).x) <= 0x200:
						play(p, 2)
						p.substate += 1
				2: _end_to_skate(p)
		12:
			match sub:
				0:
					sim.puck.drop(p)
					play(p, 0xB)
					_face_velocity(p)
					p.substate += 1
				1:
					if MwRinkSim.s16(pos) >= 0x380:
						p.motion.vel[2] = 0x240
						var v := own_motion(p).x
						v = (v + MwRinkSim.asr(MwRinkSim.s16(v), 3)) & 0xFFFF
						if v <= 0x180:
							v = 0x180
						_launch(p, p.angle, v)
						p.substate += 1
				2:
					if MwRinkSim.s16(pos) >= 0x480:
						p.anim.flags &= ~MwAnimState.PLAYING
						p.substate += 1
				3:
					if MwRinkSim.asr(p.motion.pos[2], 8) == 0:
						p.anim.flags |= MwAnimState.PLAYING
						p.substate += 1
				4: _end_to_skate(p)
		13:
			match sub:
				0:
					play(p, 9)
					p.anim.variant = 4 if p.motion.pos[1] < 0 else 0
					p.substate += 1
				1:
					if MwRinkSim.s16(pos) >= 0x280:
						sim.collide.check_hit(p)
				2:
					if not playing(p):
						stop(p)
						p.anim.variant = variant_of(p.angle)
						enter(p, 0)
		14:
			match sub:
				0: _knocked_down(p)
				1:
					if not playing(p):
						p.anim.set_mode(rom, 2)
						p.anim.flags |= MwAnimState.PLAYING
						p.substate += 1
				2: _end_to_skate(p)
				3:
					# (the original runs `$143AC` here on the player object itself, +6 = ax's high byte)
					if not playing(p):
						var hi := ((p.motion.acc[0] & 0xFFFF) >> 8) & 0xFF
						hi = (((2 ^ hi) & 0x47) ^ hi) | 0x80
						p.motion.acc[0] = MwRinkSim.s16((hi << 8) | (p.motion.acc[0] & 0xFF))
						p.substate += 1
				4: enter(p, 0)
				5:
					if not playing(p):
						play(p, 0x1B)
						p.substate = 2
		15:
			match sub:
				0: _injured(p)
				1:
					if pos >= 0x500:
						play(p, 0x15)
						p.substate += 1
						p.attacker = s.clock & 0xFF
				2: _injury_wait(p, 0x1B)
				3: _end_to_skate(p)
				4:
					p.substate += 1
					p.attacker = s.clock & 0xFF
				5: _injury_wait(p, 2)
				6: _end_to_skate(p)
		16:
			match sub:
				0:
					play(p, 0x17 + sim.rng_range(0, 2))
					p.substate += 1
				1:
					if not playing(p):
						enter(p, 0x10)
		17:
			match sub:
				0: _impaled(p)
				1: pass
		18:
			match sub:
				0: _killed(p)
				1: _corpse(p)
		19:
			match sub:
				0: _fall_through(p)
				1:
					if not playing(p):
						p.substate += 1
				2: _under_ice(p)
		20:
			match sub:
				0:
					p.motion.init(0x109, 0xA, 0)
					p.angle = 0x80
					p.motion.vel[0] = -0x180
					p.target_x = 0
					p.target_y = 0
					p.anim.variant = 6
					play(p, 0)
					p.substate += 1
				1:
					if p.motion.pos[0] <= 0xB200:
						enter(p, 0)


## Launch [param p] along [param a] at [param speed] (`$1543A` on its velocity).
func _launch(p: MwRinkState.Player, a: int, speed: int) -> void:
	var v := sim.polar(a, speed)
	p.motion.vel[0] = MwRinkSim.s16(v.x)
	p.motion.vel[1] = MwRinkSim.s16(v.y)


func _dive_speed(p: MwRinkState.Player) -> int:
	return MwGfx.u16(rom, DIVE_SPEED + 2 * (rom[p.record + 0xA] & 0xF))


## Face the start-of-pass velocity (the facing when standing still).
func _face_velocity(p: MwRinkState.Player) -> void:
	var m := own_motion(p)
	var a := m.y if m.x != 0 else p.angle
	face(p, a)


## State 1 s0 (`$4CD6`): goalies release at once (anim 9); skaters aim and
## pick the receiver (`$4DBE`), animation by the receiver's side.
func _pass_start(p: MwRinkState.Player) -> void:
	if p.position == 5:
		p.substate = 2
		sim.puck.pass_release(p)
		play(p, 9)
		return
	var anim := 8
	sim.puck.aim_pass(p)
	var r := s.puck.receiver
	var side := -1
	if r != null:
		var rp := r.motion.pixels()
		var me := p.motion.pixels()
		var a := MwTrig.angle_of(rom, MwRinkSim.s16(rp.x - me.x), MwRinkSim.s16(rp.y - me.y))
		side = MwGfx.s16(rom, PASS_ANIMS + direction(a, p.angle))      # byte offset = direction
	if side < 0:
		anim = 8 - (1 if MwRinkSim.s16(sim.rng_next()) >= 0 else 0)
	else:
		anim = side
	p.substate += 1
	play(p, anim)


## States 3 / 4 s0 (`$97C2` / `$977C`): face the target, the swing animation.
func _punch_start(p: MwRinkState.Player, anim: int) -> void:
	_face_target(p)
	play(p, anim)
	p.substate += 1


func _weapon_start(p: MwRinkState.Player) -> void:
	if s.phase == PHASE_FACEOFF:
		p.state = 3
		_punch_start(p, 10)
		return
	if p.weapon == 2:
		sim.positional(0x2C, p)                   # `$978E`
	if p.victim == s.referee and p.weapon == 3:
		enter(p, 3)
		return
	_punch_start(p, 0x20)


## `$97D6`: face the target (+$3A); its distance (no target: $50).
func _face_target(p: MwRinkState.Player) -> int:
	var t := p.victim
	if t == null:
		return 0x50
	var da: Vector2i
	if t == s.referee:
		var rp := t.motion.pixels()
		da = sim.dist_angle_to(p, rp.x, rp.y)
	else:
		da = to_opponent(p, t as MwRinkState.Player)
	p.angle = da.y
	var v := (da.y + 0x50) & 0xFF
	if s.projection != 0:
		v = (v - 0x40) & 0xFF
	p.anim.variant = v >> 5
	return da.x


## State 3 s1 (`$9996`): at frame 2 a punch lands on a target within 36 px.
func _punch_hit(p: MwRinkState.Player) -> void:
	var dist := _face_target(p)
	if MwRinkSim.s16(p.anim.position) < 0x200:
		return
	if dist > 0x24 or p.victim == null:
		p.substate += 1
		return
	if p.victim == s.referee:
		_hit_referee(p)
		return
	var team := sim.team_of(p)
	var d := sim.avg(team, rom[p.record + 9] >> 4)
	var di := s.death_index if s.phase == 0 else 0
	d = d * MwGfx.u16(rom, PUNCH_DAMAGE + 2 * di) << 3
	var st := 0xF if p.flags & MwRinkState.Player.WHITE_BONE else 0xE
	_hit(p, d, st)


## State 4 s1 (`$9852`): at frame 3 the weapon lands within its reach
## (`$1C15A`); weapon 3 throws a bomb at frame 2 instead.
func _weapon_hit(p: MwRinkState.Player) -> void:
	var dist := _face_target(p)
	if p.weapon == 3:
		_throw_bomb(p, dist)
		return
	if MwRinkSim.s16(p.anim.position) < 0x300:
		return
	if dist > MwGfx.u16(rom, WEAPON_REACH + 2 * (p.weapon & 0xFF)) or p.victim == null:
		p.substate += 1
		return
	if p.victim == s.referee:
		_hit_referee(p)
		return
	var team := sim.team_of(p)
	var d := (2 * sim.avg(team, rom[p.record + 9] >> 4)) & 0xFF
	if rom[p.record + 0xD] >> 4 != 0:
		d = (d + (rom[p.record + 0xF] & 0xF)) & 0xFF
	d = MwRinkSim.s8(d) & 0xFFFF
	d = d * MwGfx.u16(rom, WEAPON_DAMAGE + 2 * s.death_index) << 2
	_hit(p, d, 0xF)


## The shared end of punches and weapon hits (`$99FC`): outside open play
## x3/8 (nothing on a goalie), the attacker's white bone x2; the victim
## falls (state [param st]) unless already down; penalty rolls.
func _hit(p: MwRinkState.Player, d: int, st: int) -> void:
	var v := p.victim as MwRinkState.Player
	if s.phase != 0:
		d = ((d >> 1) + d) >> 2
		if v.position == 5:
			d = 0
	if p.flags & MwRinkState.Player.WHITE_BONE:
		d *= 2
	var alive := damage(v, d) != 0
	if not alive:
		if (sim.rng_next() & 0xFFFF) < 0x51E:
			sim.penalty(2, p)
		p.substate += 1
		return
	if v.state < 0xF:
		v.attacker = p.index
		enter(v, st)
	if p.state == 4:
		if (sim.rng_next() & 0xFFFF) <= 0x51E:
			sim.penalty(-4, p)
	p.substate += 1


## `$982E`: a punch on the referee (Waste the Ref, plan 09: `$EFC8`).
func _hit_referee(p: MwRinkState.Player) -> void:
	if s.ref_flag != 0:
		var r := sim.rng_next()
		# `smi.b d0` over the word: the high byte stays the draw's
		var d0 := (r & 0xFF00) | (0xFF if MwRinkSim.s16(r) < 0 else 0)
		sim.events.append(["ref_hit", d0 & 0xFF])
		_referee_hit(d0)
	p.substate += 1


## `$EFC8`: a hit on the referee (not while his animation plays): one hit
## less (+$24); the last one knocks him down (sounds $2A and 9, animation
## `$3F2FC`, attr $A0), the others hurt (sound $20, his attr +8 unless
## [param d0] is 0, one of three animations `$F040` by `rng_range(1, 3)`);
## the animation starts playing.
func _referee_hit(d0: int) -> void:
	var r := s.referee
	if r.anim.flags & MwAnimState.PLAYING:
		return
	s.ref_flag = MwRinkSim.s8(s.ref_flag - 1) & 0xFF
	var anim: int
	if MwRinkSim.s8(s.ref_flag) <= 0:
		s.ref_flag = 0
		sim.sound(0x2A)
		sim.sound(9)
		anim = REF_DOWN
		s.ref_attr = 0xA0
	else:
		sim.sound(0x20)
		if d0 & 0xFFFF == 0:
			s.ref_attr |= 8
		var i := sim.rng_range(1, 3) & 0xFFFF
		anim = MwGfx.u32(rom, REF_HURT + 4 * i)
	r.anim.set_record(rom, anim)
	r.anim.flags |= MwAnimState.PLAYING


## Weapon 3 (`$98D2`): at frame 2, a bomb (rink object 7) thrown 40 px up
## towards where the target will be in 16 ticks; 5 charges.
func _throw_bomb(p: MwRinkState.Player, dist: int) -> void:
	if MwRinkSim.s16(p.anim.position) < 0x200:
		return
	var a := p.angle
	var t := p.victim
	if t != null:
		var tx := MwRinkSim.asr(t.motion.pos[0] + t.motion.vel[0] * 16, 8)
		var ty := MwRinkSim.asr(t.motion.pos[1] + t.motion.vel[1] * 16, 8)
		var da := sim.dist_angle_to(p, tx, ty)
		a = da.y
		dist = da.x
	var o := sim.free_object()
	if o == null:
		p.substate += 1
		return
	p.charges = (p.charges - 1) & 0xFF
	if p.charges == 0:
		p.flags2 &= ~8
		p.weapon = -1
		if p.flags & MwRinkState.Player.ENFORCER:
			p.weapon = rom[p.original + 0xE] & 0xF
	var px := p.motion.pixels()
	sim.spawn(o, px.x, px.y, MwRinkState.KIND_BOMB, 0)
	o.motion.pos[2] = ((px.z + 0x28) & 0xFFFF) << 8
	var v := sim.polar(a, (dist << 4) & 0xFFFF)
	o.motion.vel[0] = MwRinkSim.s16(v.x)
	o.motion.vel[1] = MwRinkSim.s16(v.y)
	o.motion.vel[2] = 0xC0
	p.substate += 1


## States 5-7 s0 (`$465A`): the shot animation by facing octant and the
## attacked end: side shots 3 / 4 (wind-up), front / back 5 / 6; wrist
## shots and one-timers start late (`$500` / `$200`).
func _shot_start(p: MwRinkState.Player) -> void:
	var o := p.angle & 0xE0
	var down := sim.team_of(p).flags4 & 2 != 0
	var side: bool
	var anim: int
	if o & 0x60 == 0:
		side = true
		anim = (4 if o == 0 else 3) if not down else (3 if o == 0 else 4)
	else:
		var front: bool = (o & 0x80 == 0) if not down else (o & 0x80 != 0)
		# not down: bit 7 set -> side ($469C); down: bit 7 clear -> side
		side = not front
		if side:
			anim = 4 if o & 0x40 else 3
		else:
			anim = 6 if o & 0x40 else 5
	play(p, anim)
	if side:
		p.substate += 1
		if p.state != 5:
			p.anim.position = 0x500
	else:
		p.substate = 4
		if p.state != 5:
			p.anim.position = 0x200
			p.substate = 3


## Release the shot at animation position [param at] (`$4726` / `$472E`).
func _shot_release(p: MwRinkState.Player, at: int) -> void:
	if p.anim.position < at:
		return
	p.substate += 1
	if s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == p:
		sim.puck.shoot(p)
	else:
		p.anim.flags &= ~MwAnimState.PLAYING


## State 8 s0 (`$6B10`): the check's animation by the victim's side
## (`$1C6BC`; behind: no check); no victim: a cross check at the air.
func _check_start(p: MwRinkState.Player) -> void:
	if p.victim == null:
		p.substate = 2
		play(p, 0xF)
		return
	var v := p.victim as MwRinkState.Player
	var a := to_opponent(p, v).y if v != null else 0
	var anim := MwGfx.s16(rom, CHECK_ANIMS + direction(a, p.angle))
	if anim < 0:
		done(p)
		return
	p.substate += 1
	play(p, anim)


## States 9 / 10 s0 (`$824E`): drop the puck, the dive animation from
## frame 3.5, face the velocity, take off (vz $140, `$1C8AE` by SPEED).
func _dive_start(p: MwRinkState.Player) -> void:
	sim.puck.drop(p)
	play(p, 0xC)
	_face_velocity(p)
	p.anim.position = 0x380
	p.motion.vel[2] = 0x140
	_launch(p, p.angle, _dive_speed(p))
	p.substate += 1


## State 14 s0 (`$8388`): knocked down by the attacker in slot +$72 (at a
## faceoff: a random side): sideways falls, knocked back (launched away),
## or from behind -> tripped (state 10).
func _knocked_down(p: MwRinkState.Player) -> void:
	var species := rom[p.record + 7] & 0xF
	sim.positional(0x1E if species == 2 else 0x20, p)   # `$839E`
	if p.position == 5:
		p.substate = 3
		play(p, 8)
		s.crowd = MwRinkSim.s16(s.crowd + 0x42)
		return
	p.substate += 1
	var dir: int
	var a := 0
	if s.phase == PHASE_FACEOFF or s.phase == PHASE_START:
		dir = (sim.rng_next() & 4) | 2
	else:
		var att := sim.other_team(p).players[p.attacker % 6]
		a = to_opponent(p, att).y
		dir = direction(a, p.angle)
	var anim := MwGfx.s16(rom, KNOCK_ANIMS + dir)
	if anim < 0:
		p.attacker = 0
		enter(p, 0xA)
		return
	if anim == 0x13:
		p.motion.vel[2] = MwRinkSim.s16(p.motion.vel[2] + 0xC0)
		_launch(p, a + 0x80, 0x180)
		p.substate = 5
	play(p, anim)
	sim.puck.drop(p)
	s.crowd = MwRinkSim.s16(s.crowd + 0x42)


## State 15 s0 (`$9B00`): injured (white bone hit). At a faceoff just
## knocked down. Writhes for 10 game-clock seconds.
func _injured(p: MwRinkState.Player) -> void:
	if s.phase == PHASE_FACEOFF or s.phase == PHASE_START:
		enter(p, 0xE)
		return
	sim.puck.drop(p)
	sim.human.lose_control(p)
	sim.positional(0x21, p)                       # `$9B30`
	if p.position == 5:
		if p.anim_id == 0xA:
			p.attacker = s.clock & 0xFF
			p.substate = 5
			return
		p.substate = 4
		play(p, 0xA)
		s.crowd = MwRinkSim.s16(s.crowd + 0x7D)
		return
	if p.anim_id == 0x15 or p.anim_id == 0x13:
		p.attacker = s.clock & 0xFF
		p.substate = 2
		return
	p.substate += 1
	play(p, 0x13)
	s.crowd = MwRinkSim.s16(s.crowd + 0x7D)


## `$9BCA`: after 10 game-clock seconds, animation [param anim].
func _injury_wait(p: MwRinkState.Player, anim: int) -> void:
	if ((p.attacker - s.clock) & 0xFF) >= 0xA:
		play(p, anim)
		p.substate += 1


## State 17 s0 (`$851A`): impaled on spikes: the puck dropped, control
## handed on, `$1C8CC`[DI] << 16 damage; alive: anim 26, held (s1 = rts).
func _impaled(p: MwRinkState.Player) -> void:
	sim.puck.drop(p)
	sim.human.lose_control(p)
	sim.positional(0x23, p)                       # `$8528`
	damage(p, MwGfx.u16(rom, IMPALE_DAMAGE + 2 * s.death_index) << 16)
	if p.state == 0x11:
		play(p, 0x1A)
		p.substate += 1


## State 18 s0 (`$8A74`): killed: the puck dropped, control handed on,
## the crowd roars, stops dead, the death animation (goalie 3, else 33).
func _killed(p: MwRinkState.Player) -> void:
	sim.puck.drop(p)
	sim.human.lose_control(p)
	s.crowd = MwRinkSim.s16(s.crowd + 0xFA)
	sim.positional(0x2B, p)                       # `$8A90`
	p.motion.vel[0] = 0
	p.motion.vel[1] = 0
	p.anim.variant = 0
	play(p, 3 if p.position == 5 else 0x21)
	p.substate += 1


## State 18 s1 (`$8ACA`): when the animation ends, a corpse (rink object
## 11 in the team's palette, the last frame's animation object) stays and
## the player leaves (`$C1A`); team A's death plays a jingle.
func _corpse(p: MwRinkState.Player) -> void:
	if playing(p):
		return
	var o := sim.free_object()
	if o != null:
		var px := p.motion.pixels()
		sim.spawn(o, px.x, px.y, MwRinkState.KIND_CORPSE, 0x20 if p.team == 0 else 0x40)
		o.anim = p.anim.copy()
	enter(p, 0)
	died(p)
	if p.team == 0:
		sim.sound(0x1A, "music")                  # `$8B40` (A5 below team B's address)


## State 19 s0 (`$9C18`): fell through the ice.
func _fall_through(p: MwRinkState.Player) -> void:
	s.crowd = MwRinkSim.s16(s.crowd + 0xA6)
	sim.puck.drop(p)
	sim.human.lose_control(p)
	var px := p.motion.pixels()
	p.motion.init(px.x, px.y, px.z)
	play(p, 0x22)
	sim.positional(0x2A, p)                       # `$9C48`
	p.substate += 1


## State 19 s2 (`$9C78`): under the ice until the period ends (an
## under-ice silhouette object by species, the team's +$336 bit, +$49E).
func _under_ice(p: MwRinkState.Player) -> void:
	var o := sim.free_object()
	if o != null:
		var px := p.motion.pixels()
		var species := rom[p.record + 7] & 0xF
		sim.spawn(o, px.x, px.y, MwGfx.u16(rom, UNDER_ICE_KINDS + 2 * species) & 0xFF, 0)
	var team := sim.team_of(p)
	var bits := (team.x330[6] << 24) | (team.x330[7] << 16) | (team.x330[8] << 8) | team.x330[9]
	bits |= 1 << (p.slot & 31)
	for i in 4:
		team.x330[6 + i] = (bits >> (24 - 8 * i)) & 0xFF
	team.add_stat(0x49E, 1)
	enter(p, 0)
	off_ice_dead(p)


# --- `$63D8`: skating -----------------------------------------------------------------------

## Steer towards the target point: turn the facing (8 angle units per
## tick), choose the skating / turning / hockey stop animation, write the
## acceleration (none when arrived or coasting, braking when arrived, else
## towards the target until the top speed). [param e] is the pass's ticks
## (12 for CPU skaters that think every 12 ticks).
func skate(p: MwRinkState.Player, e: int) -> void:
	if s.phase == PHASE_START or s.phase == PHASE_FACEOFF:
		return
	var goalie := p.position == 5
	var P: int = SKATE_PARAMS[1 if goalie else 0]
	var team := sim.team_of(p)
	if p.state != 0 or MwRinkSim.asr(p.motion.pos[2], 8) != 0:
		p.motion.acc[0] = 0
		p.motion.acc[1] = 0
		_goalie_variant(p)
		return
	var newvar := 0xFF
	var own := own_motion(p)
	var speed := own.x & 0xFFFF
	var vang := own.y if speed != 0 else p.angle
	var desired := p.angle
	var t := sim.dist_angle_to(p, p.target_x, p.target_y)
	var td := t.x
	if td != 0:
		var ta := t.y
		if not goalie and team.flags4 & 0x20:
			ta ^= 0x80
			if not p.flags & MwRinkState.Player.HUMAN:
				ta = sim.rng_next() & 0xFF
		desired = ta
	var anim: int
	var acc := Vector2i.ZERO
	if speed > MwGfx.u16(rom, P + 0xE) and ((desired - vang) & 0xFF) >= 0x70 and ((desired - vang) & 0xFF) <= 0x90:
		# reversing at speed: hockey stop
		p.angle = desired
		newvar = variant_of(desired)
		anim = 0x1F
		acc = sim.polar(vang ^ 0x80, MwGfx.u16(rom, P + 0x10))
	else:
		var base := p.puck_angle if p.puck_dist != 0 else p.angle
		var d0 := desired
		if s.phase != PHASE_FIGHT and not team.flags5 & 2 and not p.flags2 & 4 and td < MwGfx.u16(rom, P + 6) \
				and not p.flags & MwRinkState.Player.HUMAN and s.puck.carrier != p:
			# a CPU player near its target faces the puck
			var d1 := (d0 - base) & 0xFF
			if d1 & 0x80:
				d1 = (-d1) & 0xFF
			if d1 > 0x40:
				d0 = base
		if goalie and d0 & 0x7F and (((d0 ^ MwRinkSim.asr(p.motion.pos[1], 24)) & 0x80) == 0):
			d0 = (-d0) & 0xFF          # a goalie faces away from his net
		anim = rom[P + 1]
		var old := p.angle
		var a := old
		var reached := false
		for i in 8 * e:
			if a == d0:
				reached = true
				break
			a = (a + (-1 if MwRinkSim.s8(d0 - a) < 0 else 1)) & 0xFF
		if not reached:
			anim = p.anim_id
		p.angle = a
		if a != old:
			var v: int
			var tn: int
			if MwRinkSim.s8(a - old) < 0:
				v = ((a + 0x58) & 0xFF) >> 5
				tn = MwGfx.u16(rom, P + 4)
			else:
				v = ((a + 0x48) & 0xFF) >> 5
				tn = MwGfx.u16(rom, P + 2)
			if v != p.anim.variant:
				anim = tn & 0xFF
				newvar = v
		if td <= MwGfx.u16(rom, P + 0xA):
			anim = 0xFF
			var c := MwGfx.u16(rom, P + 0xC)
			var b := (speed >> 2) if speed < 4 * c else c
			acc = sim.polar(vang ^ 0x80, b)
		elif td <= MwGfx.u16(rom, P + 8):
			acc = Vector2i.ZERO
		else:
			var r := rom[p.record + 0xA] & 0xF
			var a8 := MwGfx.u16(rom, SPEED_ACCEL + 2 * r)
			var top := MwGfx.u16(rom, SPEED_TOP + 2 * r)
			if goalie:
				a8 = (a8 << 1) & 0xFFFF
				top -= top >> 2
			else:
				if p.flags & MwRinkState.Player.BLACK_BONE:
					top >>= 1
				if p.flags & MwRinkState.Player.BURST:
					top = (top + (top >> 1)) & 0xFFFF
					var room := MwRinkSim.s16(top - speed)
					if room >= 0:
						a8 = (room / e) & 0xFFFF
			acc = Vector2i.ZERO if top <= speed else sim.polar(desired, a8)
	p.motion.acc[0] = MwRinkSim.s16(acc.x)
	p.motion.acc[1] = MwRinkSim.s16(acc.y)
	if newvar & 0x80 == 0:
		p.anim.variant = newvar
	if goalie and p.anim_id >= 4 and p.anim_id <= 7:
		pass                                 # the save pose stays
	elif speed < 0x40 or anim & 0x80:
		stop(p)
	elif anim != p.anim_id:
		play(p, anim)
	_goalie_variant(p)


## `$66B6`: a moving goalie's variant from his facing, mirrored by his end.
func _goalie_variant(p: MwRinkState.Player) -> void:
	if p.position != 5 or p.anim_id == 0:
		return
	var d0 := MwRinkSim.s8(p.angle)
	var yhi := MwRinkSim.s16(MwRinkSim.asr(p.motion.pos[1], 16))
	if (d0 ^ yhi) >= 0:
		d0 = ~d0
	p.anim.variant = ((d0 + 0x60) & 0xFF) >> 5
