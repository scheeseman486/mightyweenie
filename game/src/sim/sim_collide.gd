class_name MwSimCollide
extends RefCounted
## Collisions of a player after his motion step (`$6D02`;
## docs/re/players.md, Collisions): team-mate bumps, opponents (dive trips,
## the fight trigger, bumps; only from team A's side), the puck (`$6FD6`),
## rink objects (`$726E`), the net frame (`$74E2`), in-ice hazards
## (`$7684`), the boards and rounded corners (`$8066`). Off-screen players
## only meet the boards - in an EXTENDED match (plan 44,
## [member MwRinkState.extended_play]) a player a human drives counts as on
## the screen wherever he is ([method counts_on_screen]), and a CPU's player
## off it still meets the opponents humans drive (the CPU's players
## otherwise as the original's). Also the momentum exchange `$15470` and
## the check / slash hit (`$6B5A`: never the screen's).

const RINK_OBJECTS := 0x1C6EE        ## handlers by kind (only the table's shape is used)
const NET_SIZES := 0x1C74A           ## by net style: half width, back y
const BATTLE_DAMAGE := 0x1C756       ## by Death Index (long)
const FIGHT_CHANCE := 0x1C6CE        ## by Death Index (/65536 per colliding pass)
const GLOVE_REACH := 0x1C6D8         ## by the goalie's BLOCK rating
const HAZARD_SIZES := 0x1C88E        ## by kind - 1: anim.l, half width, half height
const CORNER_BOTTOM := 0x1C81E       ## x limits from y 324
const CORNER_TOP := 0x1C77E          ## x limits from y 298
const BOARD_X := 0xB9                ## 185
const BOARD_Y := 0x174               ## 372
const CORNER_TOP_FROM := 0x12A       ## |y| from which the far corner's table applies (298)
const CORNER_BOTTOM_FROM := 0x144    ## y from which the near corner's applies (324)
const CORNER_MIN_X := 0x6C           ## the corners' narrowest x limit (108)

var sim: MwRinkSim
var rom: PackedByteArray
var s: MwRinkState

## True while `$6D02` runs: code called from here sees its stack frame
## where it expects the puck in A6 (the change of player, `$1856`).
var in_frame := false
## `$6D02`'s frame: the player, his radius, his pixel position after the step.
var _p: MwRinkState.Player
var _r := 0
var _x := 0
var _y := 0
var _z := 0
var _e := 0


func _init(sim_: MwRinkSim) -> void:
	sim = sim_
	rom = sim.rom
	s = sim.s


## `$6CB6`: a player's radius: 36 while diving / tripped / goalie-diving,
## skaters 10, goalies 10 + avg(overall) capped at 18 - averaged with the
## skulls of [param team], the team in A4 (the colliding player's: an
## opposing goalie gets the wrong team's).
func radius(p: MwRinkState.Player, team: MwRinkState.Team = null) -> int:
	if p.state >= 9 and p.state <= 0xB:
		return 0x24
	if p.position != 5:
		return 0xA
	var r := sim.avg(team if team != null else sim.team_of(p), rom[p.original + 8] & 0xF) + 0xA
	return mini(r, 0x12)


## `$5C3C`: [param actor] is on screen (its map point minus the camera within
## 320 x 240; [method MwRinkSim.on_screen]).
func on_screen(actor: MwRinkState.Actor) -> bool:
	return MwRinkSim.on_screen(s, actor)


## Whether `$6D02` meets the rink for [param p]: on the original's screen,
## or - plan 44, an EXTENDED match ([member MwRinkState.extended_play]) - a
## player a human drives, wherever he is (the EXTENDED views keep him in
## sight). The CPU's players: the original's screen (owner: the CPU left
## out, keeping the old behaviour), but for the opponents humans drive (the
## exception: CPU against player combat, [method _player]) - with EXTENDED
## CPU ([member MwRinkState.extended_cpu]) wherever they are too.
func counts_on_screen(p: MwRinkState.Player) -> bool:
	if s.extended_play and (p.flags & MwRinkState.Player.HUMAN or s.extended_cpu):
		return true
	return on_screen(p)


## The elapsed ticks on `$86A`'s stack (seen through `$6D02`'s frame).
func frame_e() -> int:
	return _e


# --- `$6D02` ------------------------------------------------------------------------------

## `$6D02`: player [param p]'s collisions after his motion step ([param e] elapsed
## ticks), [member in_frame] set while they run.
func player(p: MwRinkState.Player, e: int) -> void:
	in_frame = true
	_player(p, e)
	in_frame = false


func _player(p: MwRinkState.Player, e: int) -> void:
	_p = p
	_e = e
	_r = radius(p)
	var px := p.motion.pixels()
	_x = MwRinkSim.s16(px.x)
	_y = MwRinkSim.s16(px.y)
	_z = MwRinkSim.s16(px.z)
	var team := sim.team_of(p)
	if counts_on_screen(p):
		for q in team.players:
			if q.index > p.index:
				_mate(p, q)
		if p.team == 0:
			for q in s.teams[1].players:
				_opponent(p, q)
		_puck(p)
		if p.position != 5:
			_objects(p)
			_net(p)
			_hazards(p)
	elif s.extended_play and p.team == 0:
		# plan 44: a CPU's player off the screen still meets the opponents
		# humans drive, wherever they are (owner: CPUs and players still hit
		# each other outside the view)
		for q in s.teams[1].players:
			if q.flags & MwRinkState.Player.HUMAN:
				_opponent(p, q)
	_boards(p)


## The overlap test (`$6EBC`) on a start-of-pass distance [param d]: inside
## both radii + 4.
func _overlap(d: int, q: MwRinkState.Player) -> bool:
	var d1 := ((d - _r + 0x8000) & 0xFFFF) - 0x8000             # (s16 inline: plan 42)
	if d1 < 0:
		return true
	return ((d1 - radius(q, sim.team_of(_p)) - 4 + 0x8000) & 0xFFFF) - 0x8000 < 0


func _mate(p: MwRinkState.Player, q: MwRinkState.Player) -> void:
	if _overlap(p.mate_dist[q.index], q):
		_bump(p, q)


## `$6E40`: an opponent: a diver ahead trips us, else maybe a fight
## starts, then the bump. (The trip's penalty roll tests the diver through
## A0, which the tripped player's state handler has pointed at the sine
## table by then: it never rolls.)
func _opponent(p: MwRinkState.Player, q: MwRinkState.Player) -> void:
	var d := MwSimPlayers.to_opponent(p, q)
	if not _overlap(d.x, q):
		return
	if q.state == 9:
		var va := sim.velocity(p).y
		if absi(va - d.y) & 0xFFF0 == 0:
			sim.players.enter(p, 0xA)
		return
	_fight_test(p, q)
	_bump(p, q)


## `$6F3A`: a human and a CPU or human opponent, neither a goalie, both teams
## with 3+ skaters, in open play: a Death Index chance of a fight (phase 4).
func _fight_test(p: MwRinkState.Player, q: MwRinkState.Player) -> void:
	if s.fight_block != 0 or s.phase != 0 or (s.ai_off & 0xFF00) != 0:
		return
	if p.position == 5 or q.position == 5:
		return
	if not (p.flags & MwRinkState.Player.HUMAN or q.flags & MwRinkState.Player.HUMAN):
		return
	if _skaters(sim.other_team(p)) <= 2 or _skaters(sim.team_of(p)) <= 2:
		return
	var r := sim.rng_next() & 0xFFFF
	if r < MwGfx.u16(rom, FIGHT_CHANCE + 2 * s.death_index):
		p.flags |= MwRinkState.Player.FIGHTING
		q.flags |= MwRinkState.Player.FIGHTING
		s.phase = 4


## `$3B6C`: players on the ice minus goalies.
static func _skaters(team: MwRinkState.Team) -> int:
	var n := 0
	for q in team.players:
		if q.present and q.position != 5:
			n += 1
		elif q.present:
			pass
	return n


## `$6ED6`: a bump frees an impaled player and exchanges momentum.
func _bump(p: MwRinkState.Player, q: MwRinkState.Player) -> void:
	if q.state > 0x11 or p.state > 0x11:
		return
	if q.state == 0x11:
		_free(q)
	if p.state == 0x11:
		_free(p)
	collide(p, q, 0xC8, 0xC8, 0xC000)


## `$6F22`: off the spike (`$5DCE` frees the spike in the same quadrant).
func _free(p: MwRinkState.Player) -> void:
	var px := p.motion.pixels()
	for rink_object in s.objects:
		if rink_object.kind == MwRinkState.KIND_SPIKES:
			var op := rink_object.motion.pixels()
			if MwRinkSim.s16(op.x ^ px.x) >= 0 and MwRinkSim.s16(op.y ^ px.y) >= 0:
				rink_object.t24 &= 0x00FF
				break
	sim.players.enter(p, 0)


## `$15470`: momentum exchange between [param actor] and [param other_actor] (masses
## [param ma], [param mb]; restitution word [param rest]): the relative
## velocity's normal component (doubled, scaled by 1/2 + rest/65536) split
## by the masses. Positions are not separated; separating objects are left.
func collide(actor: MwRinkState.Actor, other_actor: MwRinkState.Actor, ma: int, mb: int, rest: int) -> void:
	var th := MwTrig.angle_of(rom, MwRinkSim.s16(MwRinkSim.asr(other_actor.motion.pos[0] - actor.motion.pos[0], 8)),
			MwRinkSim.s16(MwRinkSim.asr(other_actor.motion.pos[1] - actor.motion.pos[1], 8)))
	var rvx := MwRinkSim.s16(actor.motion.vel[0] - other_actor.motion.vel[0])
	var rvy := MwRinkSim.s16(actor.motion.vel[1] - other_actor.motion.vel[1])
	var d := (MwTrig.angle_of(rom, rvx, rvy) - th) & 0xFF
	if d >= 0x40 and d < 0xC0:
		return
	var j := MwRinkSim.asr((MwTrig.distance(rvx, rvy) & 0xFFFF) * MwTrig.cos_(rom, d), 14)
	if rest != 0:
		j = ((j & 0xFFFF) * ((((rest & 0xFFFF) >> 1) + 0x8000) & 0xFFFF)) >> 16
	j = MwRinkSim.s16(j)
	if ma != 0:
		var d1 := j
		if mb != 0:
			d1 = (((d1 & 0xFFFF) * mb) / (ma + mb)) & 0xFFFF
		var v := sim.polar(th, d1)
		actor.motion.vel[0] = MwRinkSim.s16(actor.motion.vel[0] - v.x)
		actor.motion.vel[1] = MwRinkSim.s16(actor.motion.vel[1] - v.y)
	if mb != 0:
		var d1 := j
		if ma != 0:
			d1 = (((d1 & 0xFFFF) * ma) / (ma + mb)) & 0xFFFF
		var v := sim.polar(th, d1)
		other_actor.motion.vel[0] = MwRinkSim.s16(other_actor.motion.vel[0] + v.x)
		other_actor.motion.vel[1] = MwRinkSim.s16(other_actor.motion.vel[1] + v.y)


# --- `$6FD6`: the puck ------------------------------------------------------------------------

func _puck(p: MwRinkState.Player) -> void:
	var pk := s.puck
	var kp := pk.motion.pixels()
	if p.position == 5:
		if absi(MwRinkSim.s16(kp.y)) >= 0x150:
			return
		if pk.carrier != p:
			# the puck's path this pass (midpoint) within reach: catch or save
			var mx := MwRinkSim.s16(MwRinkSim.asr(MwRinkSim.s16(kp.x + pk.prev_x), 1) - _x)
			var my := MwRinkSim.s16(MwRinkSim.asr(MwRinkSim.s16(kp.y + pk.prev_y), 1) - _y)
			if MwRinkSim.s16((MwTrig.distance(mx, my) & 0xFFFF) - _r - 4) < 0:
				if MwRinkSim.s16(kp.z) > 8 or p.state >= 0xF:
					_save(p)
				else:
					_catch(p)
				return
		if p.anim_id >= 4 and p.anim_id <= 7:
			# a save pose: the glove (hotspot 0) within the BLOCK reach on every axis
			var h := sim.hotspot(p.anim, 0)
			var gx := _x + h.x
			var gy := _y
			var gz := _z - (h.y if p.anim_id >= 6 else 0)
			var blk := rom[p.record + 0xC]
			blk = (blk & 0xF) if (p.anim_id - 4) & 1 else (blk >> 4)
			var reach := MwGfx.u16(rom, GLOVE_REACH + 2 * blk)
			if absi(MwRinkSim.s16(kp.x - gx)) <= reach and absi(MwRinkSim.s16(kp.y - gy)) <= reach \
					and absi(MwRinkSim.s16(kp.z - gz)) <= reach:
				_catch(p)
				return
	var z := MwRinkSim.s16(kp.z)
	if z <= 8 and (p.position == 5 or z <= 5):
		sim.puck.contact(p)
		return
	# the body: start-of-pass distance within reach, the puck between feet and head
	if MwRinkSim.s16(p.puck_dist - _r - 4) >= 0:
		return
	if z < _z or MwRinkSim.s16(z - 0x24) >= _z:
		return
	if p.position == 5:
		_save(p)
		return
	_body(p)


func _catch(p: MwRinkState.Player) -> void:
	sim.puck.catch(p)
	sim.add_player_stat(p, 0, 1)


## `$715C`: a goalie's body save: the stat, the crease mark, then as a body hit.
func _save(p: MwRinkState.Player) -> void:
	sim.add_player_stat(p, 0, 1)
	s.crease_y = MwRinkSim.s16(MwRinkSim.asr(s.puck.motion.pos[1], 8))
	_body(p)


## `$716E`: an exploding puck in flight from the other team kills; else the
## puck bounces off the body (`$15470` puck 10 : player 200).
func _body(p: MwRinkState.Player) -> void:
	var pk := s.puck
	if pk.flags & MwRinkState.Puck.EXPLODING and pk.flags & (MwRinkState.Puck.SHOT | MwRinkState.Puck.PASS):
		var owner := 1 if pk.flags & MwRinkState.Puck.BY_TEAM_B else 0
		if owner != p.team:
			pk.receiver = null
			pk.flags &= ~(MwRinkState.Puck.EXPLODING | MwRinkState.Puck.PASS | MwRinkState.Puck.SHOT
					| MwRinkState.Puck.CARRIED)
			pk.motion.vel[0] = 0
			pk.motion.vel[1] = 0
			sim.players.enter(p, 0x12)
			s.camera.shake = 0x1E
			s.camera.amp = 8
			s.crowd = MwRinkSim.s16(s.crowd + 0xFA)
			s.subphase = 0
			s.phase = 0xE
			return
	if p.position == 5:
		var d := 0x400 if p.motion.pos[1] < 0 else -0x400
		var y := p.motion.pos[1]
		pk.motion.pos[1] = (y & ~0xFFFF) | ((y + d) & 0xFFFF)      # add.w: no carry into the high word
		sim.positional(0x28, pk)                  # `$7250`, A5 the puck
	elif MwTrig.distance(pk.motion.vel[0], pk.motion.vel[1]) & 0xFFFF >= 0x100:
		sim.positional(0x1E if rom[p.original + 7] & 0xF == 2 else 0x20, pk)
	collide(pk, p, 0xA, 0xC8, 0x2000)


# --- `$726E`: rink objects ----------------------------------------------------------------------

func _objects(p: MwRinkState.Player) -> void:
	if s.phase == 1 or s.phase == 9:
		return
	for rink_object in s.objects:
		if rink_object.kind == 0:
			continue
		# (plan 42: the words inline - ((v + $8000) & $FFFF) - $8000 is MwRinkSim.s16(v))
		var op := rink_object.motion.pos
		var ox := ((op[0] >> 8) + 0x8000 & 0xFFFF) - 0x8000
		var oy := ((op[1] >> 8) + 0x8000 & 0xFFFF) - 0x8000
		var oz := ((op[2] >> 8) + 0x8000 & 0xFFFF) - 0x8000
		var d := ((MwRinkSim.dist16(((ox - _x + 0x8000) & 0xFFFF) - 0x8000, ((oy - _y + 0x8000) & 0xFFFF) - 0x8000)
				- _r + 0x8000) & 0xFFFF) - 0x8000
		if rink_object.kind == MwRinkState.KIND_CORPSE:
			d = ((d + 2 + 0x8000) & 0xFFFF) - 0x8000
		if rink_object.kind == MwRinkState.KIND_EXPLOSION:
			d = ((d - 0xA + 0x8000) & 0xFFFF) - 0x8000
		d = ((d - 0xA + 0x8000) & 0xFFFF) - 0x8000
		if d >= 0:
			continue
		_object(p, rink_object, ox, oy, oz)


func _object(p: MwRinkState.Player, rink_object: MwRinkState.RinkObject, ox: int, oy: int, oz: int) -> void:
	match rink_object.kind:
		1, 11:
			# shark / corpse: trips a skater on the ice
			if _z < 8 and p.position != 5 and p.state == 0:
				sim.players.enter(p, 0xA)
		3:
			# explosion: blown over, then the fire damage
			if p.weapon == 3:
				return
			var a := MwTrig.angle_of(rom, MwRinkSim.s16(ox - _x), MwRinkSim.s16(oy - _y))
			a = (a + 0xD0) & 0xFF
			p.angle = a
			p.anim.variant = (a >> 5) & 7
			if p.state != 0xA:
				sim.players.enter(p, 0xA)
			_burn(p)
		4:
			if _z < 0x1E:
				_burn(p)
		6:
			_spikes(p, rink_object)
		7, 12, 13, 14:
			if not _reach(oz):
				return
			collide(rink_object, p, 1, 0xA, 0)
			sim.positional(0, rink_object)                  # `$7418`, A5 the object
		15:
			if not _reach(oz):
				return
			s.bribe = MwRinkRam.TEAMS[p.team] & 0xFFFF
			_picked(rink_object)
		16:
			if not _reach(oz):
				return
			# `$742C`: $80 into the high word, the old health's high word into the low one
			var team := sim.team_of(p)
			team.health[p.slot] = 0x800000 | ((team.health[p.slot] >> 16) & 0xFFFF)
			_picked(rink_object)
		17, 18:
			if not _reach(oz):
				return
			if rink_object.kind == 17:
				p.flags = (p.flags & ~MwRinkState.Player.BLACK_BONE) | MwRinkState.Player.WHITE_BONE
				sim.tick_at(4)
			else:
				p.flags = (p.flags & ~MwRinkState.Player.WHITE_BONE) | MwRinkState.Player.BLACK_BONE
				sim.tick_at(5)
			p.bone_tick = s.tick
			_picked(rink_object)
		19, 20, 21, 22, 23:
			if not _reach(oz):
				return
			if p.flags & MwRinkState.Player.ENFORCER:
				return
			p.weapon = rink_object.kind - 19
			if p.weapon == 3:
				p.charges = 5
			sim.positional(0x27, rink_object)               # `$74D4`
			rink_object.kind = 0


## `$744C`: a pick-up needs the object 0-39 px above the player's feet.
func _reach(oz: int) -> bool:
	var d := MwRinkSim.s16(oz - _z)
	return d >= 0 and d < 0x28


func _picked(rink_object: MwRinkState.RinkObject) -> void:
	sim.positional(0, rink_object)                          # `$7418`
	rink_object.kind = 0


## `$7362`: fire / explosion damage, (4 + DI) * e << 12 per pass.
func _burn(p: MwRinkState.Player) -> void:
	if p.state == 0x12:
		return
	var d := ((4 + s.death_index) & 0xFF) * _e
	sim.players.damage(p, ((d << 16) & 0xFFFFFFFF) >> 4)


## `$7382`: impaled on a free spike at speed, while the team has 3+ skaters.
func _spikes(p: MwRinkState.Player, rink_object: MwRinkState.RinkObject) -> void:
	if _skaters(sim.team_of(p)) < 3:
		return
	if (rink_object.t24 >> 8) & 0xFF != 0:
		return
	if MwSimPlayers.own_motion(p).x & 0xFFFF <= 0x100:
		return
	if p.state == 0x11:
		return
	sim.players.enter(p, 0x11)
	rink_object.t24 = (rink_object.t24 & 0xFF) | ((((rink_object.t24 >> 8) + 1) & 0xFF) << 8)
	var op := rink_object.motion.pixels()
	p.motion.init(op.x, op.y, op.z)
	var a := 0 if MwRinkSim.s16(op.x) < 0 else 0x80
	p.angle = a
	p.anim.variant = MwSimPlayers.variant_of(a)


# --- `$74E2`: the net frame ---------------------------------------------------------------------

func _net(p: MwRinkState.Player) -> void:
	var ay := absi(_y)
	var net := s.nets[0] if _y < 0 else s.nets[1]
	var ax := absi(_x)
	var st := net.style & 0xFF
	var hw := MwGfx.s16(rom, NET_SIZES + 4 * st)
	var back := MwGfx.s16(rom, NET_SIZES + 4 * st + 2)
	var side := MwRinkSim.s16(_r + hw - ax)
	if side < 0:
		return
	var b := MwRinkSim.s16(_r + back - ay)
	if b < 0:
		return
	var check_side := true
	if MwRinkSim.s16(b - 0xA) < 0:
		# the back skin: moving towards centre ice -> bounced back
		var vy := p.motion.vel[1]
		if MwRinkSim.s16(_y ^ vy) >= 0:
			return
		vy = MwRinkSim.asr(MwRinkSim.s16(-vy), 2)
		p.motion.vel[1] = vy
		if absi(vy) >= 0x30:
			sim.positional(0x23, p)               # `$757E`
		var pk := s.puck
		if pk.flags & MwRinkState.Puck.CARRIED:
			sim.puck.drop(p)
			if not pk.flags & MwRinkState.Puck.CARRIED:
				var d2 := 0x15D00 if pk.motion.pos[1] >= 0 else -0x15D00
				var v := pk.motion.vel[1]
				if (pk.motion.pos[1] ^ v) < 0:
					pk.motion.vel[1] = MwRinkSim.asr(MwRinkSim.s16(-v), 1)
				pk.motion.pos[1] = d2
		if st == 2:
			_battle_net(p)
			return
	else:
		var f := MwRinkSim.s16(-_r + 0x149 - ay)
		if f >= 0:
			return
		if MwRinkSim.s16(f + 0xA) >= 0:
			# the front skin: moving outwards -> bounced back
			var vy := p.motion.vel[1]
			if MwRinkSim.s16(_y ^ vy) >= 0:
				vy = MwRinkSim.asr(MwRinkSim.s16(-vy), 2)
				p.motion.vel[1] = vy
				if absi(vy) >= 0x30:
					sim.positional(0x23, p)       # `$75FA`
				sim.puck.drop(p)
	if check_side and MwRinkSim.s16(side - 0xA) < 0:
		var vx := p.motion.vel[0]
		if MwRinkSim.s16(_x ^ vx) < 0:
			vx = MwRinkSim.asr(MwRinkSim.s16(-vx), 2)
			p.motion.vel[0] = vx
			if absi(vx) >= 0x30:
				sim.positional(0x23, p)           # `$7636`
			sim.puck.drop(p)
			if st == 2:
				_battle_net(p)


## `$765C`: the Battle Net hurts at speed.
func _battle_net(p: MwRinkState.Player) -> void:
	if MwSimPlayers.own_motion(p).x & 0xFFFF <= 0x100:
		return
	sim.players.damage(p, MwGfx.u32(rom, BATTLE_DAMAGE + 4 * s.death_index))


# --- `$7684`: in-ice hazards ---------------------------------------------------------------------

func _hazards(p: MwRinkState.Player) -> void:
	if p.motion.pos[2] != 0:
		return
	for hazard in s.hazards:
		if hazard.kind == 0:
			continue
		if p.flags & MwRinkState.Player.HUMAN:
			# 8 ticks ahead, the D-pad released: jump it
			var sx := _x
			var sy := _y
			_x = MwRinkSim.s16(MwRinkSim.asr(p.motion.pos[0] + p.motion.vel[0] * 8, 8))
			_y = MwRinkSim.s16(MwRinkSim.asr(p.motion.pos[1] + p.motion.vel[1] * 8, 8))
			var ahead := _inside(hazard) != 0
			var jump := ahead and (sim.human.pad_word(p) & 0xF00) == 0
			if jump:
				sim.players.enter(p, 0xC)
			_x = sx
			_y = sy
			if jump:
				continue
		var k := _inside(hazard)
		if k == 0:
			continue
		match k:
			1:
				hazard.kind = 2
				_fall(p, hazard)
			2, 3:
				var v := sim.velocity(p)
				if v.x & 0xFFFF >= 0x100:
					_fall(p, hazard)
				else:
					_bounce(p, v)
			4:
				var v := MwSimPlayers.own_motion(p)
				if v.x & 0xFFFF > 0x100:
					sim.players.enter(p, 0x12)
					sim.positional(0x2B, p)       # `$7800`
					s.camera.shake = 0x1E
					s.camera.amp = 8
					hazard.kind = 2
				else:
					_bounce(p, v)


## `$7752`: the frame's point inside hazard [param hazard]'s box grown by the
## radius (half sizes from `$1C88E` minus 15): its kind, else 0.
func _inside(hazard: MwRinkState.Hazard) -> int:
	var w := MwRinkSim.s16(MwGfx.u16(rom, HAZARD_SIZES + 8 * (hazard.kind - 1) + 4) - 0xF)
	var hh := MwRinkSim.s16(MwGfx.u16(rom, HAZARD_SIZES + 8 * (hazard.kind - 1) + 6) - 0xF)
	if MwRinkSim.s16(absi(MwRinkSim.s16(hazard.x - _x)) - _r - w) >= 0:
		return 0
	if MwRinkSim.s16(absi(MwRinkSim.s16(hazard.y - _y)) - _r - hh) >= 0:
		return 0
	return hazard.kind


## `$77AC`: into the hole at its centre (state 19).
func _fall(p: MwRinkState.Player, hazard: MwRinkState.Hazard) -> void:
	if p.state != 0x13:
		p.motion.init(hazard.x, hazard.y, 0)
		sim.players.enter(p, 0x13)


## `$7820`: bounced back at the same speed.
func _bounce(p: MwRinkState.Player, v: Vector2i) -> void:
	var w := sim.polar(v.y ^ 0x80, v.x)
	p.motion.vel[0] = MwRinkSim.s16(w.x)
	p.motion.vel[1] = MwRinkSim.s16(w.y)


# --- the boards ------------------------------------------------------------------------------

## `$6D86`: straight boards (position pushed back in, that velocity
## stopped) and the rounded corners.
func _boards(p: MwRinkState.Player) -> void:
	if p.state == 0x11:
		return
	var snd := 0
	var d3 := _r - 3
	var pos := p.motion.pos
	# (plan 42: the words inline - ((v + $8000) & $FFFF) - $8000 is MwRinkSim.s16(v))
	var x := ((absi((((pos[0] >> 8) + 0x8000) & 0xFFFF) - 0x8000) + d3 + 0x8000) & 0xFFFF) - 0x8000
	var y := ((absi((((pos[1] >> 8) + 0x8000) & 0xFFFF) - 0x8000) + d3 + 0x8000) & 0xFFFF) - 0x8000
	x = ((x - BOARD_X + 0x8000) & 0xFFFF) - 0x8000
	if x >= 0:
		x += 1
		if p.motion.pos[0] >= 0:
			x = -x
		p.motion.pos[0] += x * 256
		if absi(p.motion.vel[0]) >= 0xC0:
			snd = 0x23
		p.motion.vel[0] = 0
	y = ((y - BOARD_Y + 0x8000) & 0xFFFF) - 0x8000
	if y >= 0:
		y += 1
		if p.motion.pos[1] >= 0:
			y = -y
		p.motion.pos[1] += y * 256
		if absi(p.motion.vel[1]) >= 0xC0:
			snd = 0x23
		p.motion.vel[1] = 0
	corner(p, d3, 0x4000)
	if snd != 0:
		sim.positional(snd, p)                    # `$6E18`


## `$8066`: the rounded corners (and the straight boards' ends) as a wall
## point 32 px out along the table's normal, met with `$15470` (velocity
## only). [param d3] = the object's margin.
func corner(actor: MwRinkState.Actor, d3: int, rest: int) -> void:
	var pos := actor.motion.pos
	# (plan 42: the words inline - ((v + $8000) & $FFFF) - $8000 is MwRinkSim.s16(v))
	var x := ((absi((((pos[0] >> 8) + 0x8000) & 0xFFFF) - 0x8000) + d3 + 0x8000) & 0xFFFF) - 0x8000
	var y0 := (((pos[1] >> 8) + 0x8000) & 0xFFFF) - 0x8000
	var y: int
	var lo: int
	var tab: int
	if y0 >= 0:
		y = ((y0 + d3 + 0x8000) & 0xFFFF) - 0x8000
		lo = CORNER_BOTTOM_FROM
		tab = CORNER_BOTTOM
	else:
		y = ((-y0 + d3 + 0x8000) & 0xFFFF) - 0x8000
		lo = CORNER_TOP_FROM
		tab = CORNER_TOP
	if x < CORNER_MIN_X:
		if y < BOARD_Y:
			return
		y += 1
	elif y >= BOARD_Y:
		y += 1
	elif y < lo:
		if x < BOARD_X:
			return
		x += 1
	else:
		var i := 2 * (y - lo)
		if x < MwGfx.s16(rom, tab + i + 2):
			return
		var d1 := MwRinkSim.s16(MwGfx.s16(rom, tab + i) - MwGfx.s16(rom, tab + i + 4))
		var a := MwTrig.angle_of(rom, 2, d1)
		var v := sim.polar(a, 0x20)
		x = MwRinkSim.s16(x + v.x)
		y = MwRinkSim.s16(y + v.y)
	if actor == s.puck and MwRinkSim.s16(actor.motion.pos[2] >> 16) >= 0x2000:
		s.subphase = 0
		s.phase = 0xE
		return
	x = MwRinkSim.s16(x - d3)
	y = MwRinkSim.s16(y - d3)
	if actor.motion.pos[0] < 0:
		x = -x
	if actor.motion.pos[1] < 0:
		y = -y
	var wall := MwRinkState.Actor.new()
	wall.motion.init(x, y, 0)
	collide(actor, wall, 1, 0, rest)


# --- `$6B5A`: a check / slash lands -----------------------------------------------------------------

## At frame 2.5 of a check or slash: the victim (state < 15) within 40 px
## takes (avg(CHECKING) + weight - victim weight) x `$1C6C4`[DI] << 2 (open
## play: white bone x2, Nasty Goalie x4, counted as a hard check or not;
## else x3/8); still standing -> knocked down (state 14, white bone: 15)
## and a penalty roll. Then the next substate.
func check_hit(p: MwRinkState.Player) -> void:
	var victim := p.victim as MwRinkState.Player
	if victim != null and victim.state < 0xF and MwSimPlayers.to_opponent(p, victim).x <= 0x28:
		var team := sim.team_of(p)
		var d := (sim.avg(team, rom[p.record + 0xD] & 0xF) + rom[p.record + 6] - rom[victim.record + 6]) & 0xFF
		d = MwRinkSim.s8(d)
		if d >= 0:
			d = d * MwGfx.u16(rom, MwSimPlayers.CHECK_DAMAGE + 2 * s.death_index) << 2
			if s.phase == 0:
				if p.flags & MwRinkState.Player.WHITE_BONE:
					d *= 2
				if p.flags2 & 2:
					d *= 4
				d &= 0xFFFFFFFF
				team.add_stat(0x490 if d >= 0x3D70A else 0x492, 1)
			else:
				d = (((d >> 1) + d) & 0xFFFFFFFF) >> 2
			sim.players.damage(victim, d)
			if victim.state == 0:
				victim.attacker = p.index
				sim.players.enter(victim, 0xF if p.flags & MwRinkState.Player.WHITE_BONE else 0xE)
				var r := sim.rng_next() & 0xFFFF
				var code := -3
				var limit := 0xFFF
				if victim.position == 5:
					code = -2
					limit = 0x1999
				elif victim.state == 0xA:
					code = -6
					limit = 0x1FFF
				if r <= limit:
					sim.penalty(code, p)
	p.substate += 1
