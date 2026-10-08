class_name MwRinkSim
extends RefCounted
## The rink pass's simulation segment (`$F98A`-`$F9C8`; docs/re/players.md,
## docs/re/puck.md), node-free: the geometry snapshot (`$95C8`), the team
## order draw, both teams' updates (`$3836`: every player's control, state,
## skating, motion, collisions; health) and the puck's update (`$5E74`).
## It runs on an [MwRinkState] once per gameplay pass with the pass's elapsed
## ticks, after the pads have been read into the state.
##
## Parts: [MwSimPlayers] (players), [MwSimPuck] (puck), [MwHumanControl]
## (pads -> intentions). CPU players' decisions come from [member cpu]: the
## AI ([MwRinkAI]), or recorded thinks in the checks ([MwReplayControl]).
## Integer arithmetic is the 68000's (16-bit words, byte angles 0 = +x,
## $40 = +y; positions 24.8, velocities 1/256 px per tick).

var rom: PackedByteArray
var s: MwRinkState
var players: MwSimPlayers
var collide: MwSimCollide
var puck: MwSimPuck
var human: MwHumanControl
var special: MwSimSpecial
var penalties: MwRinkPenalties
## CPU decisions: an object with `think(sim, player, team, other)` (called
## where the original calls `$3BFE` + `$8820`).
var cpu: Object
## Optional observer for comparisons: `before_player(sim, player)` and
## `before_puck(sim)` (e.g. to set the tick the original read there).
var hooks: Object = null
## Things the segment asks of other systems: [kind, ...] with kind "sound"
## (id; "music" for `$8B40`'s jingle), "penalty" (code, team) - played /
## ruled on by plans 09-12.
var events: Array = []
## Live play (plan 12): the segment's sound calls also reach the sound
## driver ([MwSound]) where the original makes them; off in the checks and
## tests, which only see [member events]. Set by the rink scene and by the
## screens that run the rink's code in live play.
var live := false


func _init(rom_: PackedByteArray, state: MwRinkState) -> void:
	rom = rom_
	s = state
	players = MwSimPlayers.new(self)
	collide = MwSimCollide.new(self)
	puck = MwSimPuck.new(self)
	human = MwHumanControl.new(self)
	special = MwSimSpecial.new(self)
	penalties = MwRinkPenalties.new(self)
	cpu = MwRinkAI.new()


## One pass of the segment with [param e] elapsed ticks.
func run(e: int) -> void:
	events.clear()
	geometry()
	var a := s.teams[0]
	var b := s.teams[1]
	if rng_next() & 0x40:
		var t := a
		a = b
		b = t
	players.team_update(a, b, e)
	players.team_update(b, a, e)
	if hooks:
		hooks.before_puck(self)
	puck.update(e)


# --- `$95C8`: the geometry snapshot --------------------------------------------------

## Distances and angles of every player to the puck, the team-mates and the
## opponents (own slot: own speed and velocity angle), and each team's
## nearest eligible skater to the puck. Empty slots get (0, $7FFF) towards
## others but still measure the puck from their stale position.
func geometry() -> void:
	for t in 2:
		var team := s.teams[t]
		var best := 0xFFFF
		for i in 6:
			var p := team.players[i]
			for j in range(i, 6):
				if j == i:
					var pk := s.puck.motion.pixels()
					var da := dist_angle_to(p, pk.x, pk.y)
					p.puck_angle = da.y
					p.puck_dist = da.x
					if _nearest_eligible(p) and da.x < best:
						team.nearest = p
						best = da.x
					var v := dist_angle(p.motion.vel[0], p.motion.vel[1])
					p.mate_angle[i] = v.y
					p.mate_dist[i] = v.x
					continue
				var q := team.players[j]
				var d := Vector2i(0x7FFF, 0)
				if p.present and q.present:
					var qp := q.motion.pixels()
					d = dist_angle_to(p, qp.x, qp.y)
				p.mate_angle[j] = d.y
				p.mate_dist[j] = d.x
				q.mate_angle[i] = d.y ^ 0x80
				q.mate_dist[i] = d.x
	for i in 6:
		var p := s.teams[0].players[i]
		for k in 6:
			var q := s.teams[1].players[k]
			var d := Vector2i(0x7FFF, 0)
			if p.present and q.present:
				var qp := q.motion.pixels()
				d = dist_angle_to(p, qp.x, qp.y)
			p.opp_angle[k] = d.y
			p.opp_dist[k] = d.x
			q.opp_angle[i] = d.y ^ 0x80
			q.opp_dist[i] = d.x


## `$96B0`: not a goalie, state below $11, not carrying the puck.
func _nearest_eligible(p: MwRinkState.Player) -> bool:
	if p.position == 5 or p.state >= 0x11:
		return false
	return not (s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == p)


# --- shared arithmetic ---------------------------------------------------------------

## Comparison aid: when set, every draw is logged as [state before, caller].
var rng_log: Array = []
var log_rng := false


## `$4BC6`: the next main-stream value (32 bits; callers take bytes or words).
func rng_next() -> int:
	if log_rng:
		var st := get_stack()
		rng_log.append([s.rng.state, "%s:%d" % [st[1]["function"], st[1]["line"]] if st.size() > 1 else "?"])
	return s.rng.next_state()


## `$4BD6`: uniform in [lo, hi] (a signed word).
func rng_range(lo: int, hi: int) -> int:
	if log_rng:
		var st := get_stack()
		rng_log.append([s.rng.state, "range %s:%d" % [st[1]["function"], st[1]["line"]] if st.size() > 1 else "range"])
	var span := (hi - lo + 1) & 0xFFFF
	var v := s.rng.next_state() & 0xFFFF
	return s16(((v * span) >> 16) + lo)


## `$1427C`: (distance, angle) of the vector ([param dx], [param dy]) (words).
func dist_angle(dx: int, dy: int) -> Vector2i:
	dx = s16(dx)
	dy = s16(dy)
	return Vector2i(MwTrig.distance(dx, dy) & 0xFFFF, MwTrig.angle_of(rom, dx, dy))


## `$1545A`: (distance, angle) from [param o]'s position (px) to ([param x], [param y]).
func dist_angle_to(o: MwRinkState.Actor, x: int, y: int) -> Vector2i:
	var p := o.motion.pixels()
	return dist_angle(x - p.x, y - p.y)


## `$14248`: the vector of [param length] at byte angle [param a].
func polar(a: int, length: int) -> Vector2i:
	return MwTrig.polar(rom, a & 0xFF, s16(length))


## `$1544A`: (speed, angle) of [param o]'s velocity.
func velocity(o: MwRinkState.Actor) -> Vector2i:
	return dist_angle(o.motion.vel[0], o.motion.vel[1])


static func s8(v: int) -> int:
	v &= 0xFF
	return v - 0x100 if v >= 0x80 else v


static func s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


static func asr(v: int, n: int) -> int:
	return v >> n if v >= 0 else ~((~v) >> n)


## A rating nibble of [param p]'s player record: byte [param off], high or low.
func rating(p: MwRinkState.Player, off: int, high: bool) -> int:
	var b := rom[p.record + off]
	return b >> 4 if high else b & 0xF


## `$3BDE`: a rating averaged with the team's skulls ((r + `$3BF6`[team
## record +$B]) / 2).
func avg(team: MwRinkState.Team, r: int) -> int:
	return ((r + rom[0x3BF6 + rom[team.record + 0xB]]) & 0xFF) >> 1


func team_of(p: MwRinkState.Player) -> MwRinkState.Team:
	return s.teams[p.team]


func other_team(p: MwRinkState.Player) -> MwRinkState.Team:
	return s.teams[1 - p.team]


## The comparison layer's hook where the original reads the tick counter
## (the VBlank interrupt advances it while the segment runs; tags as
## harness/mw_harness/sim_record.py TICK_SITES).
func tick_at(tag: int) -> void:
	if hooks:
		hooks.tick_at(self, tag)


## `sound_play` `$13CEE`: sound [param id] (live: [method MwSound.play]);
## the event [[param kind], id].
func sound(id: int, kind := "sound") -> void:
	events.append([kind, id])
	if live:
		MwSound.play(id)


## `$13D58`: sound [param id] tied to [param o] (the original's A5), played
## only while [param o] is on screen ([method on_screen], `$5C3C`; live:
## [method MwSound.positional]); the event ["sound", id] as [method sound].
func positional(id: int, o: MwRinkState.Actor) -> void:
	events.append(["sound", id])
	if live:
		MwSound.positional(id, on_screen(s, o))


## `$5C3C`: [param o] is on screen - its map point (`$5AC2`: the rink's
## projection, or the scoreboards' side view with [member
## MwRinkState.projection]) minus the camera (`$FFB0F0` / `$FFB0F4`, whole
## pixels) within 320 x 240 (`$155A2`'s outcode 0; signed words).
static func on_screen(st: MwRinkState, o: MwRinkState.Actor) -> bool:
	var px := o.motion.pixels()
	var mx: int
	var my: int
	if st.projection != 0:
		mx = s16(-absi(s16(px.x)) + 0x179)
		my = s16(px.y + 0xA0)
		var t := mx
		mx = my
		my = s16(t - px.z)
	else:
		mx = s16(px.x + 0x100)
		my = s16(px.y + 0x1CD - px.z)
	var sx := s16(mx - (st.camera.x >> 8))
	var sy := s16(my - (st.camera.y >> 8))
	return sx >= 0 and sx < 0x140 and sy >= 0 and sy < 0xF0


## `$A4AA`: a penalty call (code: 2 kill, -2 goalie check, -3 check, -4
## weapon, -5 dive, -6 from behind) on [param p]; a bribed referee may pin
## a phantom one on the other team instead (its roll included:
## [method MwSimSpecial.bribed_call]). The ruling (`$A536`..) is plan 10's.
func penalty(code: int, p: MwRinkState.Player) -> void:
	var c := special.bribed_call(code, p)
	if not c.is_empty():
		events.append(["penalty", c[0], c[1]])
		penalties.rule(c[0], c[1])


## `$CB2A`: [param p]'s statistics entry (team +$3A2 + 8 x roster slot):
## word [param off] += [param n].
func add_player_stat(p: MwRinkState.Player, off: int, n: int) -> void:
	team_of(p).add_stat(0x3A2 + 8 * p.slot + off, n)


## `$5BA6`: a free rink object slot (else the first thrown item, removed); null: none.
func free_object() -> MwRinkState.RinkObject:
	for o in s.objects:
		if o.kind == 0:
			return o
	for o in s.objects:
		if o.kind >= 0xC:
			o.kind = 0
			return o
	return null


## `$66EE` with the kind's spawn hook (`$67B2`): bombs fly (animation
## playing), under-ice silhouettes drift (random variant and direction,
## timers 15 / 30), explosions and fires burn (playing, sound $2B), a
## shark sets its target oscillators, a thrown item (kinds 12-23, `$6A06`)
## flies at a random point of its quarter of the ice.
func spawn(o: MwRinkState.RinkObject, x: int, y: int, kind: int, flags: int) -> void:
	s.spawn(rom, o, x, y, kind, flags)
	match kind:
		MwRinkState.KIND_EXPLOSION, MwRinkState.KIND_FIRE:
			positional(0x2B, o)                       # `$690A`
			o.anim.flags |= MwAnimState.PLAYING
		MwRinkState.KIND_BOMB:
			o.anim.flags |= MwAnimState.PLAYING
		8, 9, 10:
			o.anim.variant = rng_next() & 7
			var v := polar(rng_next(), 0x20)
			o.motion.vel[0] = s16(v.x)
			o.motion.vel[1] = s16(v.y)
			o.t24 = 0xF
			o.t26 = 0x1E
		_:
			if kind >= 0xC:
				_thrown(o)


## `$6A06`: a thrown item's flight: a random target (|y| <= 329, |x| <=
## 155) on its own side of both centre lines (the signs of the spawn
## point's x and y), velocity $500 towards it, vz $280 up, animation playing.
func _thrown(o: MwRinkState.RinkObject) -> void:
	var ty := rng_range(0, 0x149)
	if o.motion.pos[1] < 0:
		ty = -ty
	var tx := rng_range(0, 0x9B)
	if o.motion.pos[0] < 0:
		tx = -tx
	var p := o.motion.pixels()
	var a := MwTrig.angle_of(rom, s16(tx - p.x), s16(ty - p.y))
	var v := polar(a, 0x500)
	o.motion.vel[0] = s16(v.x)
	o.motion.vel[1] = s16(v.y)
	o.motion.vel[2] = 0x280
	o.anim.flags |= MwAnimState.PLAYING


## `$14472`: hotspot [param n] of [param a]'s current frame (flips applied).
func hotspot(a: MwAnimState, n: int) -> Vector2i:
	var f := a.frame_address(rom)
	var at := f.x + 2 + 6 * MwGfx.u16(rom, f.x) + 2 * n
	var hx := MwGfx.s8(rom, at)
	var hy := MwGfx.s8(rom, at + 1)
	return Vector2i(-hx if f.y & 1 else hx, -hy if f.y & 2 else hy)
