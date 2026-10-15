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
var _gx := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])     # geometry(): positions (px)
var _gy := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])


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


## One pass of the segment with [param e] elapsed ticks. Plan 34: the
## port's control layer first ([member MwRinkState.control]: seats, own
## menus, QUIT GAME / REJOIN, RECLAIM - in player-number order).
func run(e: int) -> void:
	events.clear()
	if s.control != null:
		s.control.pass_start(self)
	geometry()
	var first := s.teams[0]
	var second := s.teams[1]
	if rng_next() & 0x40:
		var team := first
		first = second
		second = team
	players.team_update(first, second, e)
	players.team_update(second, first, e)
	if hooks:
		hooks.before_puck(self)
	puck.update(e)


## Plan 45: breaks this sim's reference cycles - its parts and the CPU's AI
## keep the sim, the sim keeps them, and RefCounted objects in a cycle are
## never freed: the sim, and through it its state (a whole match: its full
## replay, its paint), would outlive their owner. The owner calls it when the
## sim is done ([method MwRink._exit_tree], [method MwScreenSim.dispose], the
## run-ahead's and the reckoning's shadows, the rehearsal, TEST SKATE); the
## sim can't run after it.
func dispose() -> void:
	players = null
	collide = null
	puck = null
	human = null
	special = null
	penalties = null
	cpu = null
	hooks = null
	events = []


# --- `$95C8`: the geometry snapshot --------------------------------------------------

## Distances and angles of every player to the puck, the team-mates and the
## opponents (own slot: own speed and velocity angle), and each team's
## nearest eligible skater to the puck. Empty slots get (0, $7FFF) towards
## others but still measure the puck from their stale position.
## Plan 42 (speed): each position read once ([member _gx] / [member _gy]),
## the distance and angle worked out inline ([method dist16], MwTrig) - the
## same numbers in the same order as [method dist_angle_to] gives them.
func geometry() -> void:
	var puck_at := s.puck.motion.pixels()
	for t in 2:
		var ps := s.teams[t].players
		for i in 6:
			var pos := ps[i].motion.pos
			_gx[t * 6 + i] = pos[0] >> 8              # (MwMotion.asr: 32-bit words, >> is arithmetic)
			_gy[t * 6 + i] = pos[1] >> 8
	for t in 2:
		var team := s.teams[t]
		var best := 0xFFFF
		for i in 6:
			var p := team.players[i]
			var x := _gx[t * 6 + i]
			var y := _gy[t * 6 + i]
			var dx := ((puck_at.x - x + 0x8000) & 0xFFFF) - 0x8000          # (s16 inline)
			var dy := ((puck_at.y - y + 0x8000) & 0xFFFF) - 0x8000
			var dist := dist16(dx, dy)
			p.puck_angle = MwTrig.angle_of(rom, dx, dy)
			p.puck_dist = dist
			if _nearest_eligible(p) and dist < best:
				team.nearest = p
				best = dist
			var vx := ((p.motion.vel[0] + 0x8000) & 0xFFFF) - 0x8000
			var vy := ((p.motion.vel[1] + 0x8000) & 0xFFFF) - 0x8000
			p.mate_angle[i] = MwTrig.angle_of(rom, vx, vy)
			p.mate_dist[i] = dist16(vx, vy)
			for j in range(i + 1, 6):
				var q := team.players[j]
				var da := 0
				var dd := 0x7FFF
				if p.present and q.present:
					var qx := ((_gx[t * 6 + j] - x + 0x8000) & 0xFFFF) - 0x8000
					var qy := ((_gy[t * 6 + j] - y + 0x8000) & 0xFFFF) - 0x8000
					dd = dist16(qx, qy)
					da = MwTrig.angle_of(rom, qx, qy)
				p.mate_angle[j] = da
				p.mate_dist[j] = dd
				q.mate_angle[i] = da ^ 0x80
				q.mate_dist[i] = dd
	for i in 6:
		var p := s.teams[0].players[i]
		var x := _gx[i]
		var y := _gy[i]
		for k in 6:
			var q := s.teams[1].players[k]
			var da := 0
			var dd := 0x7FFF
			if p.present and q.present:
				var qx := ((_gx[6 + k] - x + 0x8000) & 0xFFFF) - 0x8000
				var qy := ((_gy[6 + k] - y + 0x8000) & 0xFFFF) - 0x8000
				dd = dist16(qx, qy)
				da = MwTrig.angle_of(rom, qx, qy)
			p.opp_angle[k] = da
			p.opp_dist[k] = dd
			q.opp_angle[i] = da ^ 0x80
			q.opp_dist[i] = dd


## [method MwTrig.distance] of (dx, dy) as [method dist_angle] keeps it (a word).
static func dist16(dx: int, dy: int) -> int:
	var a := absi(dx)
	var b := absi(dy)
	if a < b:
		var t := a
		a = b
		b = t
	return ((2 * a + b - (b >> 3)) >> 1) & 0xFFFF


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


## `$1545A`: (distance, angle) from [param actor]'s position (px) to ([param x], [param y]).
func dist_angle_to(actor: MwRinkState.Actor, x: int, y: int) -> Vector2i:
	var point := actor.motion.pixels()
	return dist_angle(x - point.x, y - point.y)


## `$14248`: the vector of [param length] at byte angle [param a].
func polar(a: int, length: int) -> Vector2i:
	return MwTrig.polar(rom, a & 0xFF, s16(length))


## `$1544A`: (speed, angle) of [param actor]'s velocity.
func velocity(actor: MwRinkState.Actor) -> Vector2i:
	return dist_angle(actor.motion.vel[0], actor.motion.vel[1])


## [param v]'s low byte as a signed byte (-128..127).
static func s8(v: int) -> int:
	v &= 0xFF
	return v - 0x100 if v >= 0x80 else v


## [param v]'s low word as a signed word (-32768..32767).
static func s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## Plan 40 (D8): [method s8], [method s16] and this are the one set of sign
## helpers on values (the motion, the AI, the text layout use them; MwGfx's
## read the ROM, the driver model's mask addresses as a 68000).
static func s32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


## [param v] shifted right [param n] bits, arithmetic (the 68000's `asr`).
static func asr(v: int, n: int) -> int:
	return v >> n                  # (at run time `>>` on an int is arithmetic: MwMotion.asr)


## A rating nibble of [param p]'s player record: byte [param off], high or low.
func rating(p: MwRinkState.Player, off: int, high: bool) -> int:
	var b := rom[p.record + off]
	return b >> 4 if high else b & 0xF


## `$3BDE`: a rating averaged with the team's skulls ((r + `$3BF6`[team
## record +$B]) / 2).
func avg(team: MwRinkState.Team, r: int) -> int:
	return ((r + rom[0x3BF6 + rom[team.record + MwTeams.SKULLS]]) & 0xFF) >> 1


## [param p]'s team.
func team_of(p: MwRinkState.Player) -> MwRinkState.Team:
	return s.teams[p.team]


## The team [param p] plays against.
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


## `$13D58`: sound [param id] tied to [param actor] (the original's A5), played
## only while [param actor] is on screen ([method on_screen], `$5C3C`; live:
## [method MwSound.positional]); the event ["sound", id] as [method sound].
func positional(id: int, actor: MwRinkState.Actor) -> void:
	events.append(["sound", id])
	if live:
		MwSound.positional(id, on_screen(s, actor))


## `$5C3C`: [param actor] is on screen - its map point (`$5AC2`: the rink's
## projection, or the scoreboards' side view with [member
## MwRinkState.projection]) minus the camera (`$FFB0F0` / `$FFB0F4`, whole
## pixels) within 320 x 240 (`$155A2`'s outcode 0; signed words).
static func on_screen(state: MwRinkState, actor: MwRinkState.Actor) -> bool:
	var px := actor.motion.pixels()
	var mx: int
	var my: int
	if state.projection != 0:
		mx = s16(-absi(s16(px.x)) + 0x179)
		my = s16(px.y + 0xA0)
		var t := mx
		mx = my
		my = s16(t - px.z)
	else:
		mx = s16(px.x + 0x100)
		my = s16(px.y + 0x1CD - px.z)
	var sx := s16(mx - (state.camera.x >> 8))
	var sy := s16(my - (state.camera.y >> 8))
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
	for slot in s.objects:
		if slot.kind == 0:
			return slot
	for rink_object in s.objects:
		if rink_object.kind >= 0xC:
			rink_object.kind = 0
			return rink_object
	return null


## `$66EE` with the kind's spawn hook (`$67B2`): bombs fly (animation
## playing), under-ice silhouettes drift (random variant and direction,
## timers 15 / 30), explosions and fires burn (playing, sound $2B), a
## shark sets its target oscillators, a thrown item (kinds 12-23, `$6A06`)
## flies at a random point of its quarter of the ice.
func spawn(rink_object: MwRinkState.RinkObject, x: int, y: int, kind: int, flags: int) -> void:
	s.spawn(rom, rink_object, x, y, kind, flags)
	match kind:
		MwRinkState.KIND_EXPLOSION, MwRinkState.KIND_FIRE:
			positional(0x2B, rink_object)                       # `$690A`
			rink_object.anim.flags |= MwAnimState.PLAYING
		MwRinkState.KIND_BOMB:
			rink_object.anim.flags |= MwAnimState.PLAYING
		8, 9, 10:
			rink_object.anim.variant = rng_next() & 7
			var v := polar(rng_next(), 0x20)
			rink_object.motion.vel[0] = s16(v.x)
			rink_object.motion.vel[1] = s16(v.y)
			rink_object.t24 = 0xF
			rink_object.t26 = 0x1E
		_:
			if kind >= 0xC:
				_thrown(rink_object)


## `$6A06`: a thrown item's flight: a random target (|y| <= 329, |x| <=
## 155) on its own side of both centre lines (the signs of the spawn
## point's x and y), velocity $500 towards it, vz $280 up, animation playing.
func _thrown(rink_object: MwRinkState.RinkObject) -> void:
	var ty := rng_range(0, 0x149)
	if rink_object.motion.pos[1] < 0:
		ty = -ty
	var tx := rng_range(0, 0x9B)
	if rink_object.motion.pos[0] < 0:
		tx = -tx
	var point := rink_object.motion.pixels()
	var a := MwTrig.angle_of(rom, s16(tx - point.x), s16(ty - point.y))
	var v := polar(a, 0x500)
	rink_object.motion.vel[0] = s16(v.x)
	rink_object.motion.vel[1] = s16(v.y)
	rink_object.motion.vel[2] = 0x280
	rink_object.anim.flags |= MwAnimState.PLAYING


## `$14472`: hotspot [param n] of [param anim]'s current frame (flips applied).
func hotspot(anim: MwAnimState, n: int) -> Vector2i:
	var f := anim.frame_address(rom)
	var at := f.x + 2 + 6 * MwGfx.u16(rom, f.x) + 2 * n
	var hx := MwGfx.s8(rom, at)
	var hy := MwGfx.s8(rom, at + 1)
	return Vector2i(-hx if f.y & 1 else hx, -hy if f.y & 2 else hy)
