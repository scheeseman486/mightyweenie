class_name MwHumanControl
extends RefCounted
## Human players' control (`skater_buttons` $19B8; docs/re/control.md):
## the pad bytes into the team's pad copies, the D-pad into the target
## point (`$17FC`), A/B/C through the per-pad tap / hold timers (`$FFB056`)
## and the situation tables (`$1BBDE` faceoff, `$1BBEE` with the puck,
## `$1BBFE` without, `$1BC0E` goalie; entries `$1BC1E`: hold ticks, tap and
## hold action as offsets from `$1B24`), the actions, the change of player
## (`$1856`) and the hand-over of control when a CPU team-mate picks up the
## puck (`$53F0`).
##
## Tap / hold verbs (docs/re/input.md): the input layer turns verbs into the
## original's pad bytes; a meaning whose verb is bound alone arrives in
## [member direct] and acts at once, without the timer.

const ACTIONS := 0x1B24
const ENTRIES := 0x1BC1E
const CTX_FACEOFF := 0x1BBDE
const CTX_CARRIER := 0x1BBEE
const CTX_FREE := 0x1BBFE
const CTX_GOALIE := 0x1BC0E
const DIRECTIONS := 0x1F618          ## held U D L R -> direction 0-7 (-1 none)
const SAVE_DIVES := 0x1C152          ## goalie dive save facings
const BUTTON_B := 0x10
const BUTTON_C := 0x20
const BUTTON_A := 0x40

## Meanings pressed this pass on inputs bound to them alone, per pad
## ("pass", "release_puck", "change_player", "wrist_shot", "slap_shot",
## "check", "punch", "dive", "special_play"); the input layer fills them.
var direct: Array = [[], [], [], []]

var sim: MwRinkSim
var rom: PackedByteArray
var s: MwRinkState
## What `$1856` reads as "the puck" through A6 when its caller's A6 is not
## the puck but a screen's stack frame (screen 17's `$A2A4` -> `$D2C`; see
## [method MwMessageScoreboardSim.frame_view]); null (the rink): the puck,
## or `$6D02`'s frame while the collision code runs.
var a6_view: A6View = null


## The fields `$1856` (with `$439C` and `$43C6`) reads through A6: the flags
## (+$3D: bit 0 carried, bit 1 by team B), x (+0 .l), vx (+4 .w), y (+8 .l)
## and vy (+$C .w) - signed. (A carried "puck" would take the velocity of
## the object its word +$24 names; a caller sets vx / vy to that.)
class A6View:
	var flags := 0
	var x := 0
	var vx := 0
	var y := 0
	var vy := 0


func _init(sim_: MwRinkSim) -> void:
	sim = sim_
	rom = sim.rom
	s = sim.s


## The pad of [param p]'s control slot (team +$66 / +$67).
func pad_of(p: MwRinkState.Player, team: MwRinkState.Team) -> int:
	return team.pads[1 if p.flags & MwRinkState.Player.SECOND_PAD else 0]


## The pad's held byte as read this pass (`$FFCA5A` + 2 pad).
func pad_held(p: MwRinkState.Player, team: MwRinkState.Team) -> int:
	var pad: int = pad_of(p, team)
	return s.pads_held[pad & 3] if pad != 0xFF else 0


## `$19A6`: the team's copy of [param p]'s pad (held << 8 | newly pressed).
func pad_word(p: MwRinkState.Player) -> int:
	var team := sim.team_of(p)
	var k := 1 if p.flags & MwRinkState.Player.SECOND_PAD else 0
	return (team.pad_held[k] << 8) | team.pad_new[k]


# --- `$19B8` ------------------------------------------------------------------------------------

func buttons(p: MwRinkState.Player, team: MwRinkState.Team, e: int) -> void:
	var k := 1 if p.flags & MwRinkState.Player.SECOND_PAD else 0
	var pad: int = pad_of(p, team) & 3
	team.pad_held[k] = s.pads_held[pad]
	var pressed := s.pads_new[pad]
	var kept := pressed & 0x8F
	s.pads_new[pad] = kept                 # the A/B/C presses are consumed
	team.pad_new[k] = kept
	var held: int = team.pad_held[k]
	var new_abc: int = pressed & 0x70
	var held_abc: int = held & 0x70
	p.flags &= ~MwRinkState.Player.BURST
	target(p, held)
	for m in direct[pad]:
		_direct(p, team, m)
	var acted := false
	if new_abc != 0:
		var ctx := _context(p)
		var i := new_abc >> 3
		s.hold_bit[pad] = rom[ctx + i]
		var entry := rom[ctx + i + 1]
		var t := MwGfx.u16(rom, ENTRIES + entry)
		s.hold_left[pad] = MwRinkSim.s8(t)
		if t & 0xFF == 0:
			_act(p, team, MwGfx.u16(rom, ENTRIES + entry + 2))
			acted = true
	elif s.hold_left[pad] != 0:
		var left := s.hold_left[pad]
		var bit := s.hold_bit[pad]
		var still: bool = held_abc & (1 << (bit & 7)) != 0
		acted = true
		if still:
			left -= e
			if left > 0:
				s.hold_left[pad] = MwRinkSim.s8(left)
				acted = false
			else:
				s.hold_left[pad] = 0
				_act(p, team, _entry_action(p, bit, 4))
		else:
			s.hold_left[pad] = 0
			_act(p, team, _entry_action(p, bit, 2))
	# (after an action the original skips this: `$1ABC` bra $1AD4)
	if not acted and p.position == 5 and not held_abc & BUTTON_A:
		_end_save_pose(p)


## The tap (+2) or hold (+4) action of the button watched as bit [param bit]
## in the situation now.
func _entry_action(p: MwRinkState.Player, bit: int, which: int) -> int:
	var ctx := _context(p)
	var i := 1 << ((bit - 3) & 7)
	var entry := rom[ctx + i + 1]
	return MwGfx.u16(rom, ENTRIES + entry + which)


## `$1ADE`: the situation table: goalie, faceoff (phases 1 and 9), with the
## puck, without.
func _context(p: MwRinkState.Player) -> int:
	if p.position == 5:
		return CTX_GOALIE
	if s.phase == 1 or s.phase == 9:
		return CTX_FACEOFF
	if s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == p:
		return CTX_CARRIER
	return CTX_FREE


## `$17FC`: the target point from the held D-pad: 100 px that way, or
## coasting 15 px ahead (goalies stop); none at a faceoff.
func target(p: MwRinkState.Player, held: int) -> void:
	var off := Vector2i.ZERO
	if s.phase != 1 and s.phase != 9:
		var dir := MwGfx.s8(rom, DIRECTIONS + (held & 0xF))
		if dir >= 0:
			off = sim.polar(dir << 5, 0x64)
		elif p.position != 5:
			off = sim.polar(p.angle, 0xF)
	var px := p.motion.pixels()
	p.target_x = MwRinkSim.s16(px.x + off.x)
	p.target_y = MwRinkSim.s16(px.y + off.y)


## The action at offset [param off] from `$1B24`.
func _act(p: MwRinkState.Player, team: MwRinkState.Team, off: int) -> void:
	match off:
		0x0:
			if p.state == 0 and sim.rng_next() & 0x2200:
				punch(p)
		0x18:
			if p.state == 0:
				sim.players.enter(p, 2)
		0x30:
			if p.state == 0:
				if team.flags4 & 0x80:
					sim.special.armed_force(p)
				else:
					punch(p)
		0x50:
			if p.state == 0 and not sim.special.fire(p):
				punch(p)
		0x66:
			if p.state == 0:
				sim.players.enter(p, 6)
		0x7E:
			if p.state == 0:
				sim.players.enter(p, 5)
		0x96:
			if p.state == 0:
				sim.puck.release(p)
		0xE8:
			if p.state == 0:
				sim.players.enter(p, 1)
		0x102:
			if p.state == 0:
				punch(p)
		0x110:
			if p.state == 0:
				sim.players.enter(p, 9)
		0x12A:
			change_player(p)
		0x136:
			if p.state == 0:
				check(p)
				p.flags |= MwRinkState.Player.BURST
		0x154:
			if s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == p:
				if p.state == 0:
					sim.players.enter(p, 1)
			else:
				change_player(p)
		0x188:
			if p.state == 0:
				if s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == p:
					sim.players.enter(p, 1)
				else:
					save(p)
		0x1E6:
			if p.state == 0:
				check(p)
				if p.state == 0:
					p.victim = null
					sim.players.enter(p, 0xD)
		_:
			push_warning("MwHumanControl: no action at $%X" % (ACTIONS + off))


## A meaning bound to its own input: its action at once where the
## situation offers it.
func _direct(p: MwRinkState.Player, team: MwRinkState.Team, meaning: String) -> void:
	var carrier := s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == p
	var faceoff := s.phase == 1 or s.phase == 9
	if p.position == 5:
		match meaning:
			"pass", "change_player":
				_act(p, team, 0x154)
			"check":
				_act(p, team, 0x1E6)
			"punch":
				_act(p, team, 0x188)
		return
	if faceoff:
		match meaning:
			"pass", "check", "wrist_shot", "slap_shot":
				_act(p, team, 0x18)
			"punch":
				_act(p, team, 0x0)
		return
	match meaning:
		"pass":
			if carrier:
				_act(p, team, 0xE8)
		"release_puck":
			if carrier:
				_act(p, team, 0x96)
		"change_player":
			if not carrier:
				_act(p, team, 0x12A)
		"wrist_shot":
			if carrier:
				_act(p, team, 0x66)
		"slap_shot":
			if carrier:
				_act(p, team, 0x7E)
		"check":
			if not carrier:
				_act(p, team, 0x136)
		"punch":
			_act(p, team, 0x30 if carrier else 0x102)
		"dive":
			if not carrier:
				_act(p, team, 0x110)
		"special_play":
			if carrier:
				_act(p, team, 0x50)


# --- actions (shared with the AI) ---------------------------------------------------------------

## `$1D36`: punch: at a target found by `$4298` (a weapon's reach), else a
## swing at the air (weapon 0-2, 4: state 4 and no target; bare: state 3,
## the old target kept).
func punch(p: MwRinkState.Player) -> void:
	_punch_search(p)
	if p.state == 3 or p.state == 4 or p.state != 0:
		return
	var st := 3
	if p.weapon >= 0 and p.weapon != 3:
		p.victim = null
		st = 4
	sim.players.enter(p, st)


## `$4298`: a skater's target within 36 px (a weapon's `$1C15A` reach)
## -> state 3 (4 with a weapon). Goalies don't punch.
func _punch_search(p: MwRinkState.Player) -> void:
	if p.position == 5:
		return
	if p.weapon >= 0:
		var reach := MwGfx.u16(rom, MwSimPlayers.WEAPON_REACH + 2 * p.weapon)
		if find_target(p, reach):
			sim.players.enter(p, 4)
	elif find_target(p, 0x24):
		sim.players.enter(p, 3)


## `$42E0`: a check within 40 px (goalie: a slash within 50) -> state 8 / 13.
func check(p: MwRinkState.Player) -> void:
	var reach := 0x32 if p.position == 5 else 0x28
	if find_target(p, reach):
		sim.players.enter(p, 0xD if p.position == 5 else 8)


## `$430E`: the nearest opponent within [param reach] and within $60 of the
## facing -> +$3A. A CPU skater first rolls against the Death Index
## (`rng < $4000 + DI x $1000`); no target (or a failed roll) aborts the
## action.
func find_target(p: MwRinkState.Player, reach: int) -> bool:
	if not p.flags & MwRinkState.Player.HUMAN and p.position != 5:
		var r := sim.rng_next() & 0xFFFF
		if r >= ((s.death_index << 12) + 0x4000) & 0xFFFF:
			return false
	var best := -1
	var d3 := reach & 0xFFFF
	for k in range(5, -1, -1):
		var d := p.opp_dist[k] & 0xFFFF
		if d3 < d:
			continue
		var rel := (p.opp_angle[k] - p.angle) & 0xFF
		if rel <= 0x60 or rel > 0xA0:
			d3 = d
			best = k
	if best < 0:
		return false
	p.victim = sim.other_team(p).players[best]
	return true


## `$1CAC` (goalie A without the puck): where the puck crosses the goal line
## 30 ticks ahead decides the save (`$419A`).
func save(p: MwRinkState.Player) -> void:
	var neg := MwRinkSim.asr(p.motion.pos[1], 8) < 0
	var pred := predict(30)
	var kp := s.puck.motion.pixels()
	var c := goal_crossing(MwRinkSim.s16(kp.x), MwRinkSim.s16(kp.y), pred.x, pred.y, neg)
	var dx := c.y if c.x != 0 else 0
	save_to(p, MwRinkSim.s16(dx - MwRinkSim.s16(p.motion.pixels().x)), neg)


## `$43C6`: the puck's point [param ticks] ahead (its carrier's velocity).
func predict(ticks: int) -> Vector2i:
	var pk := s.puck
	var v: MwRinkState.Actor = pk.carrier if pk.flags & MwRinkState.Puck.CARRIED and pk.carrier != null else pk
	var x := MwRinkSim.asr(MwRinkSim.s16(v.motion.vel[0]) * ticks + pk.motion.pos[0], 8)
	var y := MwRinkSim.asr(MwRinkSim.s16(v.motion.vel[1]) * ticks + pk.motion.pos[1], 8)
	return Vector2i(MwRinkSim.s16(x), MwRinkSim.s16(y))


## `$422E`: does (x0, y0) -> (x1, y1) cross the goal line of the end
## [param neg] (y < 0: top) within 34 px of the middle? (hit, crossing x).
func goal_crossing(x0: int, y0: int, x1: int, y1: int, neg: bool) -> Vector2i:
	var l := -MwSimPuck.GOAL_LINE if neg else MwSimPuck.GOAL_LINE
	var d1 := MwRinkSim.s16(y0 - l)
	var d3 := MwRinkSim.s16(y1 - l)
	if MwRinkSim.s16(l ^ d1) >= 0:
		return Vector2i(0, 0)
	var c := x1
	if d3 != 0:
		if MwRinkSim.s16(d3 ^ d1) >= 0:
			return Vector2i(0, 0)
		var num := MwRinkSim.s16(x1 - x0) * d1
		var den := MwRinkSim.s16(d1 - d3)
		var q := absi(num) / absi(den)
		if (num < 0) != (den < 0):
			q = -q
		c = MwRinkSim.s16(MwRinkSim.s16(q) + x0)
	return Vector2i(1 if absi(c) <= 0x22 else 0, c)


## `$419A`: a save pose by side (anim 5 / 4, +2 for a high puck), or a dive
## save (state 11) when the puck crosses far to the other side and is far.
func save_to(p: MwRinkState.Player, dx: int, neg: bool) -> void:
	var d4 := -1 if neg else 0
	var anim := 5
	var d := MwRinkSim.s16((dx ^ d4) - d4)
	if d < 0:
		anim = 4
	d = absi(d)
	var dive := false
	if d >= 0x2A:
		var gx := MwRinkSim.s16(p.motion.pos[0] >> 16)
		var px := MwRinkSim.s16(s.puck.motion.pos[0] >> 16)
		if (gx ^ px) < 0 and p.puck_dist >= 0x6E:
			dive = true
	if not dive:
		if MwRinkSim.s16(MwRinkSim.asr(s.puck.motion.pos[2], 8)) >= 0xC:
			anim += 2
		sim.players.play(p, anim)
		return
	var i := (((anim - 4) ^ d4) + 2) & 0xFFFF
	var a := MwGfx.s16(rom, SAVE_DIVES + 2 * i)
	sim.players.face(p, a)
	sim.players.enter(p, 0xB)


## `$4216`: a goalie's save pose ends when A is let go.
func _end_save_pose(p: MwRinkState.Player) -> void:
	if p.anim_id >= 4 and p.anim_id <= 7:
		sim.players.stop(p)


# --- who is controlled ------------------------------------------------------------------------------

## `$D1C`: a human player out of the action hands control on (`$1856`).
func lose_control(p: MwRinkState.Player) -> void:
	if p.flags & MwRinkState.Player.HUMAN:
		change_player(p)


## `$1856`: control to the team-mate best placed for the puck's point a few
## ticks ahead (16 when defending, 6 attacking; a bias towards the own end
## when attacking; off-screen players x4, goalies x16 more); no candidate:
## it stays.
##
## Called from the collision code (`$6D02`: killed, impaled, fallen
## through) it reads `$6D02`'s stack frame as the puck (A6): x = $FFFFB3C2
## >> 8 (the saved A6), y = the elapsed ticks << 8, vy = $385C (a return
## address), flags $C6 (not carried) - reproduced here. A caller whose A6
## is some other frame sets [member a6_view] (screen 17).
func change_player(p: MwRinkState.Player) -> void:
	var team := sim.team_of(p)
	var d4 := -1 if team.flags4 & 2 else 0
	var look := 0x10
	var d7 := 0
	var view := a6_view
	var frame := sim.collide.in_frame and view == null
	var zone: int
	var pk := s.puck
	var carried := pk.flags & MwRinkState.Puck.CARRIED != 0 and not frame
	var by_b := pk.flags & MwRinkState.Puck.BY_TEAM_B != 0
	if view != null:
		carried = view.flags & 1 != 0
		by_b = view.flags & 2 != 0
		zone = zone_of_long(view.y, d4)
	elif frame:
		zone = _zone_of(MwRinkSim.s16(sim.collide.frame_e() << 8), d4)
	else:
		zone = _zone(d4)
	if carried and (-1 if by_b else 0) == d4:
		if zone < 3:
			d4 = ~d4
			look = 6
			d7 = -1
	elif zone > 1:
		look = 6
		d7 = -1
	var at: Vector2i
	if view != null:
		at = Vector2i(MwRinkSim.s16(MwRinkSim.asr(MwRinkSim.s16(view.vx) * look + view.x, 8)),
				MwRinkSim.s16(MwRinkSim.asr(MwRinkSim.s16(view.vy) * look + view.y, 8)))
	elif frame:
		at = Vector2i(MwRinkSim.s16(MwRinkSim.asr(-0x4C3E, 8)),
				MwRinkSim.s16(MwRinkSim.asr(0x385C * look + (sim.collide.frame_e() << 16), 8)))
	else:
		at = predict(look)
	var best := 0x7FFF
	var pick := p
	for q in team.players:
		if not q.present or q.flags & MwRinkState.Player.HUMAN or q.state >= 0x11:
			continue
		if q.position == 5 and not sim.puck.crease(q):
			continue
		var qp := q.motion.pixels()
		var dy := MwRinkSim.s16(qp.y - at.y)
		var d := MwTrig.distance(MwRinkSim.s16(qp.x - at.x), dy) & 0xFFFF
		if MwRinkSim.s16((dy ^ d4) & d7) < 0:
			d = (d * 2) & 0xFFFF
		if not sim.collide.on_screen(q):
			d = (d << 2) & 0xFFFF
			if q.position == 5:
				d = (d << 2) & 0xFFFF
		if d <= best:
			best = d
			pick = q
	_switch(p, pick)


## `$439C`: the puck's zone for a team (d4 = attacks down): 0-1 own end, 2
## neutral (|y| < 108), 3-4 attacking end (0 / 4 past the goal lines).
func _zone(d4: int) -> int:
	return _zone_of(MwRinkSim.s16(MwRinkSim.asr(s.puck.motion.pos[1], 8)), d4)


## `$439C` on a y long (24.8, signed) as it is: -|y >> 8| compared as a
## word (`neg.w`), the side from the long's high word.
static func zone_of_long(yl: int, d4: int) -> int:
	var d1 := MwRinkSim.asr(yl, 8)
	var w := MwRinkSim.s16(d1) if d1 < 0 else MwRinkSim.s16(-d1)
	var d0 := 0
	if w <= -0x6C:
		d0 = -1
		if w <= -0x149:
			d0 = -2
	var hi := MwRinkSim.s16(MwRinkSim.asr(d1, 16)) ^ d4
	return MwRinkSim.s16((d0 ^ hi) - hi) + 2


func _zone_of(y: int, d4: int) -> int:
	var ny := -absi(y)
	var d0 := 0
	if ny <= -0x6C:
		d0 = -1
		if ny <= -0x149:
			d0 = -2
	var sgn := (-1 if y < 0 else 0) ^ d4
	if sgn != 0:
		d0 = -d0
	return d0 + 2


## Control (and the Player Blast weapon) from [param from] to [param to].
func _switch(from: MwRinkState.Player, to: MwRinkState.Player) -> void:
	from.flags &= ~MwRinkState.Player.HUMAN
	var blast := from.flags2 & 8
	from.flags2 &= ~8
	var second := from.flags & MwRinkState.Player.SECOND_PAD
	to.flags &= ~MwRinkState.Player.SECOND_PAD
	to.flags |= MwRinkState.Player.HUMAN
	to.flags2 &= ~8
	if second:
		to.flags |= MwRinkState.Player.SECOND_PAD
	if blast:
		to.flags2 |= 8
		to.charges = from.charges
		if not to.flags & MwRinkState.Player.ENFORCER:
			to.weapon = 3


## `$53F0`: when a CPU player of a team with a pad picks up the puck, the
## human to take control from: the passer if a human of this team passed it,
## else (two pads: alternating) the human of that pad slot. null: none.
func pickup_switch(p: MwRinkState.Player, team: MwRinkState.Team) -> MwRinkState.Player:
	if not team.flags4 & 4:
		return null
	var last := s.puck.carrier
	if last != null and last.flags & MwRinkState.Player.HUMAN and last.team == p.team:
		return last
	var d1 := 0
	if team.pads[0] != 0xFF and team.pads[1] != 0xFF:
		# `$FFBDB8` (team B) / `$FFBDB9` (team A) bit 0, toggled per pick-up
		var mask := 0x100 if team.flags4 & 1 else 0x001
		d1 = 0xFF if s.coop_toggle & mask else 0
		s.coop_toggle ^= mask
	for q in team.players:
		if q.present and q.flags & MwRinkState.Player.HUMAN:
			var sec := 0xFF if q.flags & MwRinkState.Player.SECOND_PAD else 0
			if sec == d1:
				return q
	return null


## The hand-over on a pick-up (`$5352`): the CPU picker becomes the human.
func hand_over(from: MwRinkState.Player, to: MwRinkState.Player) -> void:
	to.flags &= ~MwRinkState.Player.SECOND_PAD
	to.flags |= MwRinkState.Player.HUMAN
	to.flags2 &= ~8
	from.flags &= ~MwRinkState.Player.HUMAN
	if from.flags & MwRinkState.Player.SECOND_PAD:
		to.flags |= MwRinkState.Player.SECOND_PAD
	var blast := from.flags2 & 8
	from.flags2 &= ~8
	if blast:
		to.flags2 |= 8
		to.charges = from.charges
		if not to.flags & MwRinkState.Player.ENFORCER:
			to.weapon = 3
