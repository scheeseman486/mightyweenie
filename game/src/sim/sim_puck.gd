class_name MwSimPuck
extends RefCounted
## The puck in the rink pass (docs/re/puck.md): its update `$5E74` (the
## faceoff drop, the pick-up lock, held at the carrier's stick or the
## goalie's glove, loose physics) and environment `$7A50` (crease mark,
## corpses, nets and goals, in-ice hazards, boards and out of play,
## corners); possession (`$508E` stick contact and steals, `$5216` goalie
## catches, `$523A` / `$60DC` takes, `$CE4` drops, pokes, pick-up control
## switch `$53F0`, one-timers) and launches (shots `$478C`, passes `$4DBE` /
## `$4E94` / `$4E32` / `$4EDE`, the B-hold release `$1BBA`); the faceoff
## drop set-up `$5E14`.

const PUCK_ANIM := 0x3C8D4
const DROP_ANIM := 0x23086
const DROP_PARAMS := 0x1C58C         ## gravity, restitution, frictions of the falling puck
const DROP_STAGES := 0x1C594         ## z below which the drop sprite shrinks a stage
const FACEOFF_SPOTS := 0x1CA9A
const SPOT_PAIRS := 0x1CA9E          ## per quadrant: the two faceoff spots to choose from
const SHOT_POWER := 0x1C216          ## by avg(POWER)
const SLAP_SPREAD := 0x1C22C         ## by ACCURACY
const WRIST_SPREAD := 0x1C237
const AIM_X := 0x1C1D6               ## by held d-pad: x offset at the net
const AIM_LIFT := 0x1C1F6            ## by held d-pad: vz
const PASS_AIM := 0x1C4E0            ## by held d-pad: angle (-1 none)
const LEAD_SHIFT := 0x1C500          ## receiver's puck distance -> lead ticks (2^k)
const PASS_SPREAD := 0x4FB2          ## by (PASSING + OFFENSE + 20) / 4
const NET_SIZES := 0x1C74A
const HAZARD_SIZES := 0x1C88E
const GOAL_LINE := 0x149             ## 329

var sim: MwRinkSim
var rom: PackedByteArray
var s: MwRinkState
var pk: MwRinkState.Puck

## `$7A50`'s frame: the puck's pixel position after its step.
var _x := 0
var _y := 0
var _z := 0


func _init(sim_: MwRinkSim) -> void:
	sim = sim_
	rom = sim.rom
	s = sim.s
	pk = s.puck


# --- `$5E74`: the update --------------------------------------------------------------------

func update(e: int) -> void:
	if s.phase == 1:
		pk.motion.vel[0] = 0
		pk.motion.vel[1] = 0
		var spot := MwRinkSim.s8(s.faceoff_spot)
		pk.motion.pos[0] = MwGfx.s16(rom, FACEOFF_SPOTS + 4 * spot) * 256
		pk.motion.pos[1] = MwGfx.s16(rom, FACEOFF_SPOTS + 4 * spot + 2) * 256
	if s.phase == 0xE:
		return
	if s.phase == 3:
		pk.motion.vel[0] = 0
		pk.motion.vel[1] = 0
	if pk.anim.address != PUCK_ANIM:
		# the faceoff drop: falling (shrinking a stage per pass below each height), then the puck
		if pk.flags & MwRinkState.Puck.HIDDEN:
			return
		var z := MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[2], 8))
		var v := pk.anim.variant
		if z < MwGfx.s16(rom, DROP_STAGES + 2 * v):
			pk.anim.variant = (v + 1) & 0xFF
			if v + 1 >= 4:
				pk.anim.set_record(rom, PUCK_ANIM)
				pk.anim.variant = 0
			else:
				_drop_step(e)
				return
		else:
			_drop_step(e)
			return
	if pk.lock & 1:
		sim.tick_at(8)
		if (s.tick - pk.take_tick) & 0xFFFF >= 0x1E:
			pk.lock &= ~1
	if pk.flags & MwRinkState.Puck.CARRIED and pk.carrier != null and pk.carrier.position == 5 \
			and pk.carrier.anim_id >= 4 and pk.carrier.anim_id <= 7:
		# in the goalie's glove
		var g := pk.carrier
		var h := sim.hotspot(g.anim, 0)
		if g.anim_id >= 6:
			h.y = 0
		var gp := g.motion.pixels()
		_hold_at(gp.x + h.x, gp.y, gp.z - h.y, g)
		return
	if MwRinkSim.asr(pk.motion.pos[2], 8) == 0 and pk.motion.vel[2] < 0x100:
		pk.anim.flags &= ~MwAnimState.PLAYING
		pk.anim.position = 0
		pk.anim.frame = 0
	else:
		pk.anim.flags |= MwAnimState.PLAYING
	var px := pk.motion.pixels()
	pk.prev_x = MwRinkSim.s16(px.x)
	pk.prev_y = MwRinkSim.s16(px.y)
	if pk.flags & MwRinkState.Puck.CARRIED:
		var c := pk.carrier
		var st := stick(c)
		_hold_at(st.x, st.y, 0, c)
		return
	var t := e
	if pk.flags & MwRinkState.Puck.ROCKET and pk.flags & MwRinkState.Puck.SHOT \
			and bool(pk.flags & MwRinkState.Puck.ROCKET_B) == bool(pk.flags & MwRinkState.Puck.BY_TEAM_B):
		t = 2 * e
	pk.motion.step(s.puck_params, t)
	pk.anim.advance(t)
	if sim.velocity(pk).x & 0xFFFF <= 0x10:
		pk.flags &= ~(MwRinkState.Puck.SHOT | MwRinkState.Puck.PASS)
	environment()


func _drop_step(e: int) -> void:
	pk.motion.step(s.drop_params, e)
	pk.anim.advance(e)


## `$15402` at a point and the holder's velocity (acceleration and vz 0).
func _hold_at(x: int, y: int, z: int, holder: MwRinkState.Actor) -> void:
	pk.motion.init(x, y, z)
	pk.motion.vel[0] = holder.motion.vel[0]
	pk.motion.vel[1] = holder.motion.vel[1]


## `$4FFE`: [param p]'s stick: his position + hotspot 0 of his frame (px).
func stick(p: MwRinkState.Player) -> Vector2i:
	var h := sim.hotspot(p.anim, 0)
	var pp := p.motion.pixels()
	return Vector2i(MwRinkSim.s16(pp.x + h.x), MwRinkSim.s16(pp.y + h.y))


# --- `$7A50`: the environment -------------------------------------------------------------------

func environment() -> void:
	var px := pk.motion.pixels()
	_x = MwRinkSim.s16(px.x)
	_y = MwRinkSim.s16(px.y)
	_z = MwRinkSim.s16(px.z)
	if crease(pk):
		s.crease_y = _y
	_corpses()
	if _z <= 0x14:
		_nets()
	if _z <= 4:
		_hazards()
	var snd := 0
	var x := MwRinkSim.s16(absi(MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[0], 8))) + 4 - 0xB9)
	var y := MwRinkSim.s16(absi(MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[1], 8))) + 4 - 0x174)
	if x >= 0:
		if _z >= 0x20:
			_out_of_play()
			return
		x += 1
		if pk.motion.pos[0] >= 0:
			x = -x
		pk.motion.pos[0] += x * 256
		var v := MwRinkSim.s16(-MwRinkSim.asr(pk.motion.vel[0], 2))
		pk.motion.vel[0] = v
		if absi(v) >= 0x20:
			snd = 0x29
	if y >= 0:
		if (_z & 0xFFFF) >= 0x20:
			_out_of_play()
			return
		y += 1
		if pk.motion.pos[1] >= 0:
			y = -y
		pk.motion.pos[1] += y * 256
		var v := MwRinkSim.s16(-MwRinkSim.asr(pk.motion.vel[1], 2))
		pk.motion.vel[1] = v
		if absi(v) >= 0x20:
			snd = 0x29
	sim.collide.corner(pk, 4, 0x4000)
	if snd != 0:
		sim.positional(snd, pk)                   # `$7B54`


## `$426A`: inside the goal crease as the AI and pick-ups see it
## (x' = x - x / 4, |y| - 329, length <= 45).
func crease(o: MwRinkState.Actor) -> bool:
	var p := o.motion.pixels()
	var y := MwRinkSim.s16(absi(MwRinkSim.s16(p.y)) - GOAL_LINE)
	if y >= 0:
		return false
	var x := MwRinkSim.s16(p.x - MwRinkSim.asr(MwRinkSim.s16(p.x), 2))
	return MwTrig.distance(x, y) & 0xFFFF <= 0x2D


## Over the side boards above 32 px: out of play (phase 14), the next faceoff
## spot nearest in the puck's quadrant (`$AF12`).
func _out_of_play() -> void:
	s.subphase = 0
	s.phase = 0xE
	s.crowd = MwRinkSim.s16(s.crowd + 0xFA)
	var px := pk.motion.pixels()
	var x := MwRinkSim.s16(px.x)
	var y := MwRinkSim.s16(px.y)
	var a := SPOT_PAIRS
	var spot := 1
	if y >= 0:
		a += 0x10
		spot += 4
	if x >= 0:
		a += 8
		spot += 2
	var d1 := MwTrig.distance(MwRinkSim.s16(x - MwGfx.s16(rom, a)), MwRinkSim.s16(y - MwGfx.s16(rom, a + 2))) & 0xFFFF
	var d2 := MwTrig.distance(MwRinkSim.s16(x - MwGfx.s16(rom, a + 4)), MwRinkSim.s16(y - MwGfx.s16(rom, a + 6))) & 0xFFFF
	if MwRinkSim.s16(d2) <= MwRinkSim.s16(d1):
		spot += 1
	s.faceoff_spot = spot


## `$7B62`: a corpse (kind 11) at the puck's height bounces it back.
func _corpses() -> void:
	for o in s.objects:
		if o.kind != MwRinkState.KIND_CORPSE:
			continue
		var op := o.motion.pixels()
		if absi(MwRinkSim.s16(op.z - _z)) >= 0xA:
			continue
		var d := MwTrig.distance(MwRinkSim.s16(op.x - _x), MwRinkSim.s16(op.y - _y)) & 0xFFFF
		if MwRinkSim.s16(d - 4 + 2 - 0xA) < 0:
			bounce_back()


## `$7BC6` / `$801E`: back to where the puck was, popping up, reversed at
## 2 px per tick.
func bounce_back() -> void:
	var a := sim.velocity(pk).y ^ 0x80
	pk.motion.init(pk.prev_x, pk.prev_y, 1)
	var v := sim.polar(a, 0x200)
	pk.motion.vel[0] = MwRinkSim.s16(v.x)
	pk.motion.vel[1] = MwRinkSim.s16(v.y)
	pk.motion.vel[2] = 0x300


## `$8152`: does segment A -> B cross the line at ±[param line] (sign
## [param neg]) going outwards (A on the centre side)? (hit, crossing).
## The crossing must be within 28 px of the centre ([param mode] 0) or on
## the net's sides, 325-347 ([param mode] 1).
func _cross(ax: int, ay: int, bx: int, by: int, neg: bool, line: int, mode: int) -> Vector2i:
	var l := MwRinkSim.s16(-line if neg else line)
	var d1 := MwRinkSim.s16(ay - l)
	var d3 := MwRinkSim.s16(by - l)
	if MwRinkSim.s16(d1 ^ l) >= 0:
		return Vector2i(0, 0)
	var c := bx
	if d3 != 0:
		if MwRinkSim.s16(d3 ^ d1) >= 0:
			return Vector2i(0, 0)
		var num := MwRinkSim.s16(bx - ax) * d1
		var den := MwRinkSim.s16(d1 - d3)
		var q := absi(num) / absi(den)
		if (num < 0) != (den < 0):
			q = -q
		c = MwRinkSim.s16(MwRinkSim.s16(q) + ax)
	var v := absi(c)
	var hit := (v >= 0x145 and v <= 0x15B) if mode else v <= 0x1C
	return Vector2i(1 if hit else 0, c)


## `$7C4E`: the net of the puck's half: through its back from behind,
## through the goal line (a goal; the Demon Net may bounce it), or its sides.
func _nets() -> void:
	if s.phase == 3:
		return
	var ay := absi(_y)
	var net := s.nets[1]
	if _y < 0:
		net = s.nets[0]
	var st := net.style & 0xFF
	if ay < 0x6C:
		return
	var hw := MwGfx.s16(rom, NET_SIZES + 4 * st)
	var back := MwGfx.s16(rom, NET_SIZES + 4 * st + 2)
	var neg := pk.prev_y < 0
	if absi(pk.prev_y) >= ay:
		var c := _cross(_x, _y, pk.prev_x, pk.prev_y, neg, back, 0)
		if c.x != 0:
			s.crease_y = MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[1], 8))
			_net_sound()
			pk.motion.pos[1] = (-(back + 5) if neg else back + 5) * 256
			var vy := pk.motion.vel[1]
			if MwRinkSim.s16(vy ^ (-1 if neg else 0)) < 0:
				vy = MwRinkSim.s16(-vy)
			pk.motion.vel[1] = MwRinkSim.asr(vy, 1)
			pk.motion.pos[0] = c.y * 256
			return
	else:
		var c := _cross(pk.prev_x, pk.prev_y, _x, _y, neg, GOAL_LINE, 0)
		if c.x != 0:
			s.crease_y = MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[1], 8))
			if st == 0 and net.anim.position >= 0x100:
				# the Demon Net's mouth is shut: bounced out
				_net_sound()
				pk.motion.pos[1] = (-0x144 if neg else 0x144) * 256
				pk.motion.pos[0] = c.y * 256
				if MwRinkSim.s16(pk.motion.vel[1] ^ (0 if neg else -1)) < 0:
					pk.motion.vel[1] = MwRinkSim.s16(-pk.motion.vel[1])
				pk.motion.vel[0] = MwRinkSim.asr(MwRinkSim.asr(pk.motion.vel[0], 1), 1)
				return
			_goal(neg)
			return
	# the sides
	var sneg := pk.prev_x < 0
	var c := _cross(_y, _x, pk.prev_y, pk.prev_x, sneg, hw, 1)
	if c.x == 0:
		return
	s.crease_y = MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[1], 8))
	_net_sound()
	pk.motion.pos[0] = (-(hw + 5) if sneg else hw + 5) * 256
	var vx := pk.motion.vel[0]
	if MwRinkSim.s16(vx ^ (-1 if sneg else 0)) < 0:
		vx = MwRinkSim.s16(-vx)
	pk.motion.vel[0] = MwRinkSim.asr(vx, 1)
	pk.motion.pos[1] = c.y * 256
	pk.motion.vel[1] = MwRinkSim.asr(pk.motion.vel[1], 1)


## The puck against a net's frame at speed $80 or more: `$13D58` sound $27
## (`$7CDC` the back, `$7D54` the sides, `$7DCA` the Demon Net's shut mouth).
func _net_sound() -> void:
	if sim.velocity(pk).x & 0xFFFF >= 0x80:
		sim.positional(0x27, pk)


## `$7E06`: a goal through the [param top] net's goal line: in open play
## phase 3, the scorer (the last carrier; an own goal counts as not real),
## 2 points from 221+ px, statistics, the score; always: the puck put in the
## net, stopped.
func _goal(top: bool) -> void:
	if s.phase == 0:
		s.phase = 3
		# the team attacking that end scores
		var down := s.teams[0] if s.teams[0].flags4 & 2 else s.teams[1]
		var up := s.teams[1] if down == s.teams[0] else s.teams[0]
		var scoring := up if top else down
		var conceding := down if top else up
		var scorer := pk.carrier
		# the scorer record's first long (its name pointer; a record 0 reads the ROM's reset vector)
		pk.owner_log = MwGfx.u32(rom, scorer.record & 0xFFFFFF) if scorer != null else 0
		var real := scorer != null and sim.team_of(scorer) == scoring
		if not real:
			pk.owner_log = 0
		if _power_play(scoring, conceding):
			scoring.add_stat(0x486, 1)
			if real:
				sim.events.append(["power_play_goal", conceding])
				sim.penalties.power_play_goal(conceding)          # `$A9AC`: a penalized player out
		var points := 1
		if real:
			var line := -GOAL_LINE if top else GOAL_LINE
			if absi(MwRinkSim.s16(line - pk.release_y)) >= 0xDD:
				points = 2
				scoring.add_stat(0x484, 1)
			if not pk.flags & MwRinkState.Puck.SHOT:
				pk.receiver = null
				sim.add_player_stat(scorer, 2, 1)
				scoring.add_stat(0x482, 1)
			sim.add_player_stat(scorer, 4, 1)
			sim.add_player_stat(scorer, 6, points)
		var g := conceding.goalie()
		if g.present:
			sim.add_player_stat(g, 4, 1)
			if not real:
				sim.add_player_stat(g, 2, 1)
		pk.flags &= ~(MwRinkState.Puck.PASS | MwRinkState.Puck.SHOT)
		scoring.score = (scoring.score + points) & 0xFFFF
		s.goal_points = points                 # `$9280`
		sim.events.append(["goal", scoring])
		s.scoring = 0xFFFF0000 | (MwRinkRam.TEAMS[s.teams.find(scoring)] & 0xFFFF)
		if scoring == s.teams[0]:
			s.crowd = MwRinkSim.s16(s.crowd + 0x3E8)
	pk.motion.vel[0] = 0
	pk.motion.vel[1] = 0
	pk.motion.vel[2] = 0
	var x := MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[0], 8))
	pk.motion.pos[0] = 0 if x == 0 else (0x800 if x > 0 else -0x800)
	pk.motion.pos[1] = -0x15100 if pk.motion.pos[1] < 0 else 0x15100


## `$A242`: a power-play goal: the conceding team has more players in the
## penalty box (team +$39F) than the scoring team.
func _power_play(scoring: MwRinkState.Team, conceding: MwRinkState.Team) -> bool:
	return scoring.stat(0x39F, 1) < conceding.stat(0x39F, 1)


## `$7FA0`: pits and holes let a fast puck hop over; slower, or a mine:
## bounced back.
func _hazards() -> void:
	for h in s.hazards:
		if h.kind == 0 or h.kind == 1:
			continue
		var w := MwRinkSim.s16(MwGfx.u16(rom, HAZARD_SIZES + 8 * (h.kind - 1) + 4) - 6)
		var hh := MwRinkSim.s16(MwGfx.u16(rom, HAZARD_SIZES + 8 * (h.kind - 1) + 6) - 6)
		if MwRinkSim.s16(absi(MwRinkSim.s16(h.x - _x)) - 4 - w) >= 0:
			continue
		if MwRinkSim.s16(absi(MwRinkSim.s16(h.y - _y)) - 4 - hh) >= 0:
			continue
		if h.kind != 4:
			var sp := MwTrig.distance(pk.motion.vel[0], pk.motion.vel[1]) & 0xFFFF
			if sp > 0x100:
				pk.motion.vel[2] = MwRinkSim.s16(sp)
				sim.positional(0x27, pk)          # `$8014`
				continue
		bounce_back()


# --- possession ----------------------------------------------------------------------------------

## `$CE4`: [param p] lets go of the puck if he carries it: the puck keeps
## his velocity; the y of the drop is kept for the 2-point rule.
func drop(p: MwRinkState.Player) -> void:
	if not pk.flags & MwRinkState.Puck.CARRIED or pk.carrier != p:
		return
	pk.flags &= ~MwRinkState.Puck.CARRIED
	pk.release_y = MwRinkSim.s16(MwRinkSim.asr(p.motion.pos[1], 8))
	pk.motion.vel[0] = p.motion.vel[0]
	pk.motion.vel[1] = p.motion.vel[1]


## `$508E`: [param p]'s stick meets a low puck: take a loose puck, steal
## from an opponent (rating roll; a success pokes it loose), goalies in
## their crease take it.
func contact(p: MwRinkState.Player) -> void:
	if s.phase != 0 or not p.present:
		return
	var team := sim.team_of(p)
	if p.state != 0xB:
		if p.state != 0:
			return
		if team.nearest != p and p.position != 5:
			return
	if p.position == 5:
		if not crease(p):
			return
		if p.puck_dist > 0x18:
			return
	elif not _stick_reach(p):
		return
	if p.position != 5 and pk.lock & 1:
		return
	if pk.flags & MwRinkState.Puck.CARRIED:
		_challenge(p)
		return
	_take(p)


## `$5020`: the puck within the stick's reach: |puck - stick| + (start-of-
## pass distance to the puck) - |player - stick| between 0 and 14 (20 for
## the pass receiver).
func _stick_reach(p: MwRinkState.Player) -> bool:
	var st := stick(p)
	var pp := p.motion.pixels()
	var d4 := MwTrig.distance(MwRinkSim.s16(pp.x - st.x), MwRinkSim.s16(pp.y - st.y)) & 0xFFFF
	var kp := pk.motion.pixels()
	var d := MwTrig.distance(MwRinkSim.s16(kp.x - st.x), MwRinkSim.s16(kp.y - st.y)) & 0xFFFF
	d = (d + p.puck_dist - d4) & 0xFFFF
	var limit := 0xE + (6 if pk.receiver == p else 0)
	return d <= limit


## `$50FC`: the puck is (or was, for a shot) the [param p]'s opponent's:
## a goalie takes it from him; a skater rolls `rng_range(0, 6c + p - 1) < p`
## (c = avg(carrier's OFFENSE), p = avg(own DEFENSE)) to poke it loose.
func _challenge(p: MwRinkState.Player) -> void:
	var c := pk.carrier
	if c == p or c == null or c.position == 5:
		return
	var puck_a := not pk.flags & MwRinkState.Puck.BY_TEAM_B
	var team_a := sim.team_of(p).flags4 & 1 == 0
	if puck_a == team_a:
		return
	if p.position == 5:
		drop(c)
		_take(p)
		return
	var cv := sim.avg(sim.team_of(c), rom[c.record + 0xB] >> 4)
	var pv := sim.avg(sim.team_of(p), rom[p.record + 0xB] & 0xF)
	var n := (6 * cv + pv) & 0xFFFF
	if n == 0:
		return
	if sim.rng_range(0, n - 1) >= MwRinkSim.s16(pv):
		return
	_poke(p, c)


## `$519A`: knocked loose between the two (mean of their velocity angles,
## their mean speed, at least 1 px per tick), popping up; skaters can't
## touch it for 30 ticks.
func _poke(p: MwRinkState.Player, c: MwRinkState.Player) -> void:
	sim.tick_at(2)
	drop(c)
	var cm := MwSimPlayers.own_motion(c)
	var ca := cm.y if cm.x != 0 else c.angle
	var pm := MwSimPlayers.own_motion(p)
	var pa := pm.y if pm.x != 0 else p.angle
	var a := _mean_angle(pa, ca)
	var sp := MwRinkSim.asr(MwRinkSim.s16(pm.x + cm.x), 1) & 0xFFFF
	if sp < 0x100:
		sp = 0x100
	var v := sim.polar(a, sp)
	pk.motion.vel[0] = MwRinkSim.s16(v.x)
	pk.motion.vel[1] = MwRinkSim.s16(v.y)
	pk.motion.vel[2] = 0x180
	pk.take_tick = s.tick
	pk.lock |= 1
	s.crowd = MwRinkSim.s16(s.crowd + 0x42)


## `$1436C`: the mean of two byte angles (the short way round).
static func _mean_angle(a: int, b: int) -> int:
	a &= 0xFF
	b &= 0xFF
	var m := (a + b) >> 1
	var d := b - a
	var flip := (d & 0xFF) ^ (0xFF if d < 0 else 0)
	return (m ^ (flip & 0x80)) & 0xFFFF


## `$5216`: a goalie in his crease catches the puck (not from himself).
func catch(p: MwRinkState.Player) -> void:
	if p.position == 5 and not crease(p):
		return
	if pk.flags & MwRinkState.Puck.CARRIED and pk.carrier == p:
		return
	_take(p)


## `$523A`: [param p] gets a loose puck: a shot from the own team passes him
## by, from the other team it may be knocked; a pass may be fumbled (rng
## 0-40 < 4 avg(OFFENSE)) or blow up (exploding puck); then possession, the
## control switch and the one-timer.
func _take(p: MwRinkState.Player) -> void:
	var team := sim.team_of(p)
	var owner := s.teams[1] if pk.flags & MwRinkState.Puck.BY_TEAM_B else s.teams[0]
	if pk.flags & MwRinkState.Puck.SHOT:
		pk.flags &= ~MwRinkState.Puck.SHOT
		if owner == team:
			return
		_challenge(p)
		return
	if pk.flags & MwRinkState.Puck.PASS:
		if pk.receiver == null:
			owner.add_stat(0x498, 1)
		pk.flags &= ~MwRinkState.Puck.PASS
		if owner == team and team.stat(0x498) > team.stat(0x496):
			team.add_stat(0x496, 1)
		if pk.flags & MwRinkState.Puck.EXPLODING and owner != team:
			_explode(p)
			return
		if p.position != 5:
			var r := sim.rng_range(0, 0x28)
			var o := sim.avg(team, rom[p.record + 0xB] >> 4)
			if (r & 0xFFFF) >= ((o << 2) & 0xFFFF):
				return
	if owner != team:
		if pk.flags & MwRinkState.Puck.EXPLODING:
			_explode(p)
			return
		pk.flags ^= MwRinkState.Puck.BY_TEAM_B
	var who := p
	if not p.flags & MwRinkState.Player.HUMAN:
		var h := sim.human.pickup_switch(p, team)
		if h != null and h != p:
			sim.human.hand_over(h, p)
		elif h == null:
			possess(p)
			return
	possess(p)
	if who.position == 5:
		return
	if sim.human.pad_word(who) & 0x2000:
		sim.players.enter(who, 7)


## `$529A`: an exploding puck blows up on an opponent: he is killed, the
## puck stops, out of play (phase 14), faceoff at centre ice.
func _explode(p: MwRinkState.Player) -> void:
	pk.receiver = null
	pk.flags &= ~MwRinkState.Puck.EXPLODING
	sim.players.enter(p, 0x12)
	pk.motion.vel[0] = 0
	pk.motion.vel[1] = 0
	s.phase = 0xE
	s.camera.shake = 0x1E
	s.camera.amp = 8
	s.crowd = MwRinkSim.s16(s.crowd + 0xFA)
	s.faceoff_spot = 0


## `$60DC`: [param p] has the puck (first touch after a faceoff: a faceoff
## won), the previous carrier noted, touches counted.
func possess(p: MwRinkState.Player) -> void:
	sim.tick_at(1)
	if pk.touches == 0:
		sim.team_of(p).add_stat(0x48E, 1)
	var prev := MwRinkRam.word_of(s, pk.carrier)
	pk.owner_log = (pk.owner_log & 0xFFFF) | (prev << 16)
	pk.ring = 0
	if pk.touches < 4:
		pk.touches += 1
	pk.carrier = p
	p.ai_zone = 0xFFFF
	sim.positional(0x27, pk)                      # `$612C`, A5 the puck
	pk.take_tick = s.tick
	pk.flags |= MwRinkState.Puck.CARRIED


# --- launches ------------------------------------------------------------------------------------

## `$478C`: the shot: power (`$1C216`[avg(POWER)], slap x1.5), spread by
## ACCURACY, aimed at the attacked net (a human's held d-pad picks the
## corner and lift, the CPU's a random nibble), statistics.
func shoot(p: MwRinkState.Player) -> void:
	drop(p)
	s.crowd = MwRinkSim.s16(s.crowd + 0xC8)
	var team := sim.team_of(p)
	var power := MwGfx.u16(rom, SHOT_POWER + 2 * sim.avg(team, rom[p.record + 0xC] >> 4))
	var acc := rom[p.record + 0xC] & 0xF
	var spread: int
	if p.state == 5:
		power = (power + MwRinkSim.asr(MwRinkSim.s16(power), 1)) & 0xFFFF
		spread = rom[SLAP_SPREAD + acc]
		sim.positional(0x24, p)                   # `$47F4`, A5 the shooter
	else:
		spread = rom[WRIST_SPREAD + acc]
		sim.positional(0x25, p)                   # `$47DA`
	var r := sim.rng_range(-spread, 0)
	r = MwRinkSim.s16(r + sim.rng_range(0, spread))
	pk.flags |= MwRinkState.Puck.SHOT
	var k: int
	if p.flags & MwRinkState.Player.HUMAN:
		k = sim.human.pad_held(p, team)
	else:
		k = sim.rng_next()
	k &= 0xF
	var me := p.motion.pixels()
	var net := s.nets[1] if team.flags4 & 2 else s.nets[0]
	var np := net.motion.pixels()
	pk.motion.vel[2] = MwGfx.s16(rom, AIM_LIFT + 2 * k)
	var ax := MwRinkSim.s16(np.x + MwGfx.s16(rom, AIM_X + 2 * k))
	var a := MwTrig.angle_of(rom, MwRinkSim.s16(ax - me.x), MwRinkSim.s16(np.y - me.y))
	a = MwRinkSim.s16(a + r)
	var v := sim.polar(a, power)
	pk.motion.vel[0] = MwRinkSim.s16(v.x)
	pk.motion.vel[1] = MwRinkSim.s16(v.y)
	var vz := pk.motion.vel[2]
	pk.motion.vel[2] = sim.rng_range(vz, vz + 0x80)
	team.add_stat(0x482, 1)
	sim.add_player_stat(p, 2, 1)
	var g := sim.other_team(p).goalie()
	if g.present:
		sim.add_player_stat(g, 2, 1)


## `$4DBE`: the pass's aim: the facing; a human's held d-pad (a goalie can't
## aim at his own end) and his receiver (`$4E94`: the team-mate - an
## opponent for an exploding puck - closest to the aim within 32 units, as
## seen from the puck). A CPU passer keeps the AI's receiver. Returns the aim.
func aim_pass(p: MwRinkState.Player) -> int:
	var aim := p.angle
	if not p.flags & MwRinkState.Player.HUMAN:
		return aim
	var d := sim.human.pad_held(p, sim.team_of(p)) & 0xF
	if p.position == 5:
		d &= ~(1 << (0 if p.motion.pos[1] < 0 else 1))
	var t := MwGfx.s16(rom, PASS_AIM + 2 * d)
	if t >= 0:
		aim = t
	var team := sim.team_of(p)
	if pk.flags & MwRinkState.Puck.EXPLODING:
		team = sim.other_team(p)
	var best := 0x7FFF
	var r: MwRinkState.Player = null
	for q in team.players:
		if q == p or not q.present:
			continue
		var dev := absi(((q.puck_angle ^ 0x80) & 0xFF) - aim)
		if dev > 0x20 or dev > best:
			continue
		best = dev
		r = q
	pk.receiver = r
	return aim


## `$4E32`: the pass leaves the stick: to the receiver (`$4EDE`), else
## straight along the aim at 6 px per tick (goalies 3.5).
func pass_release(p: MwRinkState.Player) -> void:
	if pk.carrier != p:
		return
	pk.flags &= ~MwRinkState.Puck.CARRIED
	pk.flags |= MwRinkState.Puck.PASS
	var aim := aim_pass(p)
	var r := pk.receiver as MwRinkState.Player
	if r != null:
		_lead_pass(r, p)
		sim.team_of(p).add_stat(0x498, 1)
	else:
		var v := sim.polar(aim, 0x380 if p.position == 5 else 0x600)
		pk.motion.vel[0] = MwRinkSim.s16(v.x)
		pk.motion.vel[1] = MwRinkSim.s16(v.y)
	pk.release_y = MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[1], 8))


## `$4EDE`: lead the receiver by 2^k ticks (k from his distance to the
## puck, +1 when he faces away), at the speed that gets there, spread by the
## passer's PASSING + OFFENSE.
func _lead_pass(r: MwRinkState.Player, passer: MwRinkState.Player) -> void:
	sim.positional(0x26, r)                       # `$4EE6`, A5 the receiver
	var at := LEAD_SHIFT
	while r.puck_dist > MwGfx.u16(rom, at):
		at += 4
	var k := MwGfx.u16(rom, at + 2)
	var a := (r.puck_angle + 0x60) & 0xFF
	if sim.team_of(passer).flags4 & 2:
		a = (a + 0x80) & 0xFF
	if a <= 0x40:
		k += 1
	var tx := r.motion.pos[0] + (r.motion.vel[0] << k)
	var ty := r.motion.pos[1] + (r.motion.vel[1] << k)
	var dx := MwRinkSim.asr(tx - pk.motion.pos[0], 8)
	var dy := MwRinkSim.asr(ty - pk.motion.pos[1], 8)
	var da := sim.dist_angle(dx, dy)
	var sh := (8 - k) & 63
	var speed := (da.x << sh) & 0xFFFF if sh < 16 else 0
	var spread := MwGfx.s8(rom, PASS_SPREAD + MwRinkSim.asr((rom[passer.record + 0xA] >> 4) + (rom[passer.record + 0xB] >> 4) + 0x14, 2))
	var ang := (da.y + sim.rng_range(-spread, spread)) & 0xFF
	if passer.position == 5 and speed >= 0x380:
		speed = 0x380
	var v := sim.polar(ang, speed)
	pk.motion.vel[0] = MwRinkSim.s16(v.x)
	pk.motion.vel[1] = MwRinkSim.s16(v.y)


## `$1BBA`: the B-hold release: the puck left moving along the carrier's
## velocity at its speed - 2 px (reversed when slower: left for a trailer).
func release(p: MwRinkState.Player) -> void:
	sim.tick_at(3)
	drop(p)
	var m := MwSimPlayers.own_motion(p)
	var a := m.y if m.x != 0 else p.angle
	var sp := MwRinkSim.s16(m.x - 0x80)
	if sp < 0:
		sp = -sp
		a = (a + 0x80) & 0xFF
	var v := sim.polar(a, sp)
	pk.motion.vel[0] = MwRinkSim.s16(v.x)
	pk.motion.vel[1] = MwRinkSim.s16(v.y)
	pk.take_tick = s.tick
	pk.lock |= 1
	pk.flags |= MwRinkState.Puck.PASS
	pk.receiver = null


# --- the faceoff ---------------------------------------------------------------------------------

## `$5E14`: the puck 112 px above ([param x], [param y]), hidden until the
## faceoff sequence drops it (`$AE68` clears the bit), falling with
## `$1C58C`'s parameters as the shrinking drop sprite.
func faceoff_drop(x: int, y: int) -> void:
	pk.motion.init(x, y, 0x70)
	pk.flags = MwRinkState.Puck.HIDDEN
	pk.lock = 0
	pk.ring = 0
	pk.touches = 0
	var w := []
	for i in 4:
		w.append(MwGfx.s16(rom, DROP_PARAMS + 2 * i))
	s.drop_params = MwMotion.Params.new(w[0], w[1], w[2], w[3])
	pk.anim = MwAnimState.from_record(rom, DROP_ANIM, 0)
	s.be64 = 0
	pk.take_tick = s.tick
