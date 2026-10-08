class_name MwRinkMatch
extends RefCounted
## A match on the rink as the original sets it up (docs/re/players.md,
## Set-up): the stadium (`rink_setup` $5572, plan 07), both teams (`$3698` /
## `$3700`: record, pads and markers, health, the first six roster players
## on the ice through `$7F8`), and each faceoff (`$AB2C`: the puck dropped
## at the spot, the camera there, both teams lined up by `$3A28` / `$B22`,
## the human picks, the tap / hold timers cleared).
##
## The period change (`$3960`, run by the period-end phase for both teams)
## switches ends and refreshes the teams; leaving the rink (`rink_exit`
## $FB38) ends the special plays' effects, takes the enforcers' weapons
## back and the dead off the ice.
##
## The rink entries ([method enter]: `$F884` screen 4, `$F8A4` screen 5,
## `$F8F0` screen 6) prepare the first pass: non-stadium rink objects
## dropped, the faceoff set-up, the forfeit test, the clock widget, the
## pass flags. At a CPU team's line-up the coach may change players
## (`$F4EE`, Reserves on) and arm a special play (`$F59E`).
##
## Not yet: playoff dead masks (`$12A4E`), the power-play widget (plan
## 10). The period-end step at an entry with the clock at 0 (`$FEBA`) is
## [method MwRinkPhases.enter]'s.

const TEAM_RECORDS := 0x18D8A        ## $9E bytes per team
const TEAM_SIZE := 0x9E
const PAD_MODES := 0x1BFFE           ## pad mode x 4 (+2 team B): the team's two pad slots
const ARROWS := 0x1C4D0              ## by pad: the off-screen arrow's animation
const LINEUPS := 0x1B904             ## by faceoff spot: 12 x (dx, dy, -, facing)
const SPOTS := 0x1CA9A
const PORTRAITS := 0x1CAE6           ## overlay animations: record.l, x.w, y.w (1: the faceoff portrait)
const PENALTY_ICON := 0x1CA58        ## `$A27C`'s overlay set-up: variant, depth, entry, attr (words)
const STOPPAGE_ICON := 0x1CF8E       ## `$C7F8`'s
const SPECIAL_ODDS := 0x1E9D8        ## by play 0-11: chance (/65536) the CPU arms it
const PHASE_FORFEIT := 13


## A new match: [param s] set up for stadium [param stadium], team ids
## [param team_a] / [param team_b], pad mode, Reserves and Death Index.
static func start(sim: MwRinkSim, stadium: int, team_a: int, team_b: int, pad_mode: int,
		reserves: bool, death_index: int) -> void:
	var s := sim.s
	var rom := sim.rom
	s.setup(rom, stadium)
	s.reserves = reserves
	s.death_index = death_index
	s.pad_mode = pad_mode
	s.crowd = 0x32
	team_setup(sim, 0, team_a)
	team_setup(sim, 1, team_b)
	s.bribe = 0
	s.puck.flags &= ~MwRinkState.Puck.EXPLODING


## `$B2B0` matchup_setup (screen 3: a new match from the menus, the attract
## demo's set-up aside): the clock (`$24F8`: period 0, the widget's bits
## cleared, the clock and power-play timers at rate 20 and 0 seconds;
## `$2524`: period 1, the clock full), the stadium (in the playoff modes the
## home team's: team A's when the series' bit 0 ([param series], `$FFBD7C`)
## is set, else team B's; written back to the setup), then [method start]
## (`$5572`, `$3698` x 2, the bribe, the exploding puck).
static func matchup_setup(sim: MwRinkSim, su: MwMatchSetup, series: int) -> void:
	var s := sim.s
	s.clock_widget = 0
	s.period = 0
	s.clock_rate = 0x14
	s.clock = 0
	s.clock_flags = (s.clock_flags | 2) & ~1
	s.pp_seconds = 0
	s.period_minutes = su.period_minutes
	s.period = 1                                    # `$2524`
	s.clock = (su.period_minutes * 60) & 0xFFFF
	if s.clock == 0:
		s.clock_flags |= 2
	else:
		s.clock_flags &= ~2
	s.clock_flags &= ~1
	if su.play_mode != 0:
		su.stadium = su.team_a if series & 1 else su.team_b
	start(sim, su.stadium, su.team_a, su.team_b, su.pads, su.reserves != 0, su.death_index)


## `$3698` + `$3700`: team [param t] with team record [param id].
static func team_setup(sim: MwRinkSim, t: int, id: int) -> void:
	var s := sim.s
	var rom := sim.rom
	var team := s.teams[t]
	team.record = TEAM_RECORDS + TEAM_SIZE * id
	team.score = 0
	team.flags4 = 0
	team.flags5 = 0
	for i in 3:
		team.x330[i] = rom[team.record + 0x14 + i]
		team.x330[3 + i] = 9 + i
	team.special = 0
	for i in 4:
		team.x330[6 + i] = 0                # +$336: nobody under the ice
	team.flags4 |= 0x18
	team.stats.fill(0)                      # penalty box (`$A252`) and statistics (`$CB16`)
	s.ai_off = 0
	team.attr = 0x20
	var mode := s.pad_mode * 4
	if t == 1:
		team.attr = 0x40
		team.flags4 |= 0x03                 # team B, attacking down
		mode += 2
	team.pads = [rom[PAD_MODES + mode], rom[PAD_MODES + mode + 1]]
	team.pad_held = [0, 0]
	team.pad_new = [0, 0]
	if team.pads[0] != 0xFF or team.pads[1] != 0xFF:
		team.flags4 |= 0x04
	s.init_marker(team, 0, team.pads[0] & 3)
	s.init_marker(team, 1, team.pads[1] & 3)
	for k in 2:
		team.arrows[k] = MwAnimState.from_record(rom, MwGfx.u32(rom, ARROWS + 4 * (team.pads[k] & 3)))
	for i in 24:
		team.health[i] = 0x800000
	for i in 6:
		var p := team.players[i]
		p.team = t
		sim.players.create(p, team, i, i, i, MwGfx.u32(rom, team.record + 0x18 + 4 * i))
	team.add_stat(0x49A, -team.stat(0x49A))


## `$3960` for team A, then team B: the period is over.
static func period_end(sim: MwRinkSim) -> void:
	for team in sim.s.teams:
		period_change(sim, team)


## `$3960`: [param team] between periods: no special play armed, the
## impaled freed (`$3ADE`), those under the ice back to full health and,
## like everyone sitting out alive and not in the penalty box, back on the
## ice (`$39BC`), every living player's health full again (`$3B08`: $80
## in the high word, a register's leftover in the low one), the
## Demon Net undone (`$7A6`: the top net of the team attacking down back in
## the stadium's style, `$7D2`, and a new goalie, `$F6A8`), then the team
## switches ends.
static func period_change(sim: MwRinkSim, team: MwRinkState.Team) -> void:
	var s := sim.s
	var rom := sim.rom
	team.special = 0
	for p in team.players:
		if p.state == 0x11:
			sim.collide._free(p)
	team.add_stat(0x49E, -team.stat(0x49E))
	var under := (team.x330[6] << 24) | (team.x330[7] << 16) | (team.x330[8] << 8) | team.x330[9]
	for i in 24:
		if under & (1 << i):
			team.health[i] = 0x800000
	for i in 4:
		team.x330[6 + i] = 0
	# The refill value is $0080 in the high word and, in the low word, the
	# high word d0 last held (`move.w #$80,d0 / swap d0`): $0080 from
	# `$39BC`'s own set-up, or the health of the last empty slot it checked.
	var d0_hi := 0x0080
	for p in team.players:
		if not p.present:
			var h := team.health[p.slot]
			d0_hi = (h >> 16) & 0xFFFF
			if h != 0 and not sim.players._in_box(team, p.slot):
				p.record = p.original
	for i in 24:
		if team.health[i] != 0:
			team.health[i] = 0x800000 | d0_hi
	team.flags4 |= 0x10
	if team.flags4 & 2 and s.nets[0].style == 0:
		team.flags4 &= ~0x08
		var n := s.nets[0]
		n.style = rom[MwRinkState.stadium_record(rom, s.stadium) + 5]
		n.anim = MwAnimState.from_record(rom, MwGfx.u32(rom, MwRinkState.NET_ANIMS + 4 * n.style), 1)
		sim.players.substitute(team.players[5])
	team.flags4 ^= 0x02


## `rink_exit` ($FB38): the rink is left for screen [param screen]; for
## any but the instant replay (7), per team: the goalie's Nasty Goalie, the
## confused / armed force flags and Waste the Goalie end, weapons go back
## to the enforcers' own (`$3BA6`), the dead and those under the ice leave
## for good (`$107D0`), the penalty box's pending marks clear (`$A950`).
static func rink_exit(sim: MwRinkSim, screen: int) -> void:
	var s := sim.s
	if screen != 7:
		for team in s.teams:
			team.players[5].flags2 &= ~0x02
			team.flags4 &= ~0xE0
			team.flags5 &= ~0x02
			reset_weapons(sim, team)
			_bodies_off(sim, team)
			_box_marks(sim, team)
	# sound off (`$13C04`), then `$9DA4`: a replay frame left open is given up
	s.replay.abandon_frame()


## `$3BA6`: the skaters drop what they picked up; enforcers keep their own
## weapon (record +$E, low nibble), the others none; nobody holds the
## Player Blast.
static func reset_weapons(sim: MwRinkSim, team: MwRinkState.Team) -> void:
	for i in 5:
		var p := team.players[i]
		p.flags2 &= ~0x08
		if p.flags & MwRinkState.Player.ENFORCER:
			p.weapon = sim.rom[p.original + 0xE] & 0xF
		else:
			p.weapon = -1


## `$107D0`: a corpse (state $12) is a death (`$C1A`); a player under the
## ice (state $13) is marked (team +$336, +$49E) and taken off (`$C1E`).
static func _bodies_off(sim: MwRinkSim, team: MwRinkState.Team) -> void:
	for p in team.players:
		if not p.present:
			continue
		if p.state == 0x12:
			sim.players.died(p)
		elif p.state == 0x13:
			var bits := (team.x330[6] << 24) | (team.x330[7] << 16) | (team.x330[8] << 8) | team.x330[9]
			bits |= 1 << (p.slot & 31)
			for i in 4:
				team.x330[6 + i] = (bits >> (24 - 8 * i)) & 0xFF
			team.add_stat(0x49E, 1)
			sim.players.off_ice_dead(p)


## `$A950` (not while a penalty is being called): the box's pending marks
## (+$3A1 bits 0-2) cleared; if players were sent (+$3A0), their in-box
## flags and penalty bytes too; the penalty icon hidden.
static func _box_marks(sim: MwRinkSim, team: MwRinkState.Team) -> void:
	var s := sim.s
	if s.phase == 2:
		return
	team.stats[0x3A1 - MwRinkState.Team.STATS_AT] &= ~0x07
	if team.stat(0x3A0, 1) != 0:
		for i in 5:
			var p := team.players[i]
			if p.flags & MwRinkState.Player.IN_BOX:
				p.flags &= ~MwRinkState.Player.IN_BOX
				p.penalty = 0
		team.stats[0x3A0 - MwRinkState.Team.STATS_AT] = 0
	s.penalty.flags &= ~0x80


## `$AB2C`: a faceoff at spot [param spot] (`$1CA9A`: 0 centre, 1-8 the
## circles): the clock widget erased, the puck up above it, hidden until
## the faceoff drops it ([method drop]); the faceoff portrait set up above
## the spot (`$AF62`, hidden until the faceoff shows it); the camera on it;
## both teams lined up; the crowd quiet.
static func faceoff(sim: MwRinkSim, spot: int) -> void:
	var s := sim.s
	var rom := sim.rom
	s.clock_widget &= ~2                     # `$26F6` (its window cells cleared)
	s.faceoff_spot = spot
	var x := MwGfx.s16(rom, SPOTS + 4 * spot)
	var y := MwGfx.s16(rom, SPOTS + 4 * spot + 2)
	sim.puck.faceoff_drop(x, y)
	_portrait(sim, x, y)
	s.camera_target = null
	s.camera.place(rom, x, y - 0x38)
	lineup(sim, s.teams[0], x, y)
	lineup(sim, s.teams[1], x, y)
	s.crowd = 0x32
	for p in 4:                              # `$1738`: the tap / hold timers
		s.hold_bit[p] = 0
		s.hold_left[p] = 0
	s.faceoff_step = 0


## `$AF74`: overlay [param o] set up from entry [param entry] of `$1CAE6`
## (animation record, x, y): its animation (variant [param variant]), that
## position (screen pixels for the ref icons), [param depth], [param attr],
## hidden; entries from 4 on have the small border.
static func overlay_setup(rom: PackedByteArray, o: MwRinkState.Overlay, variant: int, depth: int,
		entry: int, attr: int) -> void:
	var a := PORTRAITS + 8 * entry
	o.x = MwGfx.s16(rom, a + 4)
	o.y = MwGfx.s16(rom, a + 6)
	o.flags = 1 if entry >= 4 else 0
	o.depth = depth & 0xFFFF
	o.attr = attr & 0xFF
	o.anim = MwAnimState.from_record(rom, MwGfx.u32(rom, a), variant)


## The ref icons' set-ups, once at power-on (`boot_init` `$20C0`): the
## penalty icon (`$A27C`, its animation playing) and the stoppage icon
## (`$C7F8`), both entry 4 (the ref, (240, 16), depth $FFFF, attr $A0, small
## border). The overlays keep them from then on: entries, set-ups and the
## puck rules only show and hide them. The live game does this for a
## session's first match and hands them on to the next ones (MwRink).
static func boot_icons(sim: MwRinkSim) -> void:
	var rom := sim.rom
	for pair: Array in [[sim.s.penalty, PENALTY_ICON], [sim.s.stoppage, STOPPAGE_ICON]]:
		var at: int = pair[1]
		overlay_setup(rom, pair[0], MwGfx.s16(rom, at), MwGfx.s16(rom, at + 2), MwGfx.s16(rom, at + 4),
				MwGfx.s16(rom, at + 6))
	sim.s.penalty.anim.flags |= MwAnimState.PLAYING        # `$A290`


## `$AF62` (from `$AB2C`): the faceoff portrait `$1CAE6[1]` at the map
## point of (x - 28, y - 64, 96) (`$5AC2`), depth $FFFE, attr $E0, flags 0.
static func _portrait(sim: MwRinkSim, x: int, y: int) -> void:
	var o := sim.s.faceoff
	o.x = MwRinkSim.s16(x - 0x1C + 0x100)
	o.y = MwRinkSim.s16(y - 0x40 + 0x1CD - 0x60)
	o.flags = 0
	o.depth = 0xFFFE
	o.attr = 0xE0
	o.anim = MwAnimState.from_record(sim.rom, MwGfx.u32(sim.rom, PORTRAITS + 8), 0)


# --- the rink entries ---------------------------------------------------------------------

## The rink entry for screen [param screen] (4 `$F884`: a period starts,
## 5 `$F8A4`: a faceoff, 6 `$F8F0`: play goes on after the pause menu's
## replay) and the common part `$F8F6`, up to the first pass. Returns the
## screen the rink leaves for at once (17 when a team forfeits at the
## line-up: [method rink_exit] done), else -1.
static func enter(sim: MwRinkSim, screen: int) -> int:
	var s := sim.s
	match screen:
		4:
			s.box_clock = s.clock & 0xFFFF       # `$A29A`
			_drop_objects(s, true)                # `$5A48`
			s.faceoff_spot = 0                    # `$ABCE`
			s.phase = MwRinkState.PHASE_START
		5:
			s.phase = MwRinkState.PHASE_FACEOFF
		_:
			s.phase = MwRinkState.PHASE_PLAY
	if screen == 4 or screen == 5:
		_drop_objects(s, false)                   # `$5A82`
		faceoff(sim, s.faceoff_spot)
		for t in 2:                               # `$F7C8` team A, then team B
			if sim.players.forfeits(s.teams[t]):
				s.phase = PHASE_FORFEIT
				s.scoring = 0xFFFF0000 | (MwRinkRam.TEAMS[t] & 0xFFFF)   # the team's (sign-extended) address
				rink_exit(sim, 17)
				return 17
	# `$F8F6` (V-int on, the high word of a5 pushed: the net slack of `$7868`)
	s.net_slack = 1 if screen == 6 else -1
	s.subphase = 0
	# `$F7F0` rink_load: plane B back at the map's corner (the scroll
	# buffers keep their values until the first pass), window cleared
	s.camera.shown = Vector2i.ZERO
	s.plane_b_cell = Vector2i.ZERO
	s.goal_message = 0                            # `$9276`
	s.goal_message_step = 0
	if s.clock_widget & 2:
		draw_clock_widget(sim)                    # `$25AA` (only screen 6 still has it)
	if s.clock_widget & 4:                        # `$2562`: unpause
		s.clock_widget &= ~4
		if s.clock_flags & 1:
			s.clock_ref = s.tick & 0xFFFFFFFF
	s.faceoff.flags &= ~0x80                      # the portrait hidden
	s.penalty_tick = s.tick & 0xFFFFFFFF          # `$AA58`
	s.crowd_quiet = 0
	s.first_pass = 1
	s.replay_on = 0
	# (clock 0: `$FEBA(1)`, the period-end step: MwRinkPhases.enter)
	s.pass_tick = s.tick & 0xFFFFFFFF
	return -1


## `$5A48` ([param period] true: screen 4) / `$5A82`: rink objects beyond
## the stadium's own: at a period start explosions, fires, kind 5, bombs,
## under-ice players, corpses and thrown items go (spikes, sharks, kind 2
## stay); at a faceoff fires and under-ice players and corpses go
## (thrown items and bombs stay).
static func _drop_objects(s: MwRinkState, period: bool) -> void:
	for i in 8:
		if i < s.stadium_objects:
			continue
		var o := s.objects[i]
		var k := o.kind
		if period:
			if k > 6 or (k >= 3 and k != 6):
				o.kind = 0
		elif k == MwRinkState.KIND_FIRE or (k >= 8 and k <= 0xB):
			o.kind = 0


## `$25AA`: the clock widget drawn (window cells; the power-play form is
## plan 10's): shown, the period and time text made.
static func draw_clock_widget(sim: MwRinkSim) -> void:
	var s := sim.s
	if s.clock_widget & 1:
		s.clock_widget |= 8                       # power-play form (its texts: plan 10)
	else:
		s.clock_widget &= ~8
	s.clock_widget |= 2
	MwRinkUpdate.period_text(sim.rom, s)
	MwRinkUpdate.time_text(s)


## `$AE68`: the faceoff drops the puck (it falls from 112 px).
static func drop(sim: MwRinkSim) -> void:
	sim.s.puck.flags &= ~MwRinkState.Puck.HIDDEN


## `$3A28`: free the impaled, place every player on the ice (`$B22`), the
## first one is the team's nearest to the puck, and the team's pads take
## the first players in order (a random draw picks the pad slot).
static func lineup(sim: MwRinkSim, team: MwRinkState.Team, x: int, y: int) -> void:
	for p in team.players:
		if p.state == 0x11:
			sim.collide._free(p)
	if not team.flags4 & 4:
		cpu_line_changes(sim, team)
		cpu_special_play(sim, team)
	var free := 0
	if team.pads[0] != 0xFF:
		free |= 1
	if team.pads[1] != 0xFF:
		free |= 2
	var n := 0
	for p in team.players:
		if not p.present:
			continue
		if n == 0:
			team.nearest = p
		place(sim, p, team, x, y, n)
		n += 1
		p.flags &= ~MwRinkState.Player.HUMAN
		if free != 0:
			var k := sim.rng_next() & 1
			if not free & (1 << k):
				k ^= 1
			p.flags |= MwRinkState.Player.HUMAN
			p.flags &= ~MwRinkState.Player.SECOND_PAD
			if k:
				p.flags |= MwRinkState.Player.SECOND_PAD
			free &= ~(1 << k)


## `$B22`: [param p] at his line-up point for the spot (goalies at their
## crease: their entry is absolute), facing as the table says, standing.
static func place(sim: MwRinkSim, p: MwRinkState.Player, team: MwRinkState.Team, x: int, y: int, n: int) -> void:
	var rom := sim.rom
	var i := n
	if p.position == 5:
		x = 0
		y = 0
		i = 5
	if team.flags4 & 2:
		i += 6
	var t := MwGfx.u32(rom, LINEUPS + 4 * MwRinkSim.s8(sim.s.faceoff_spot))
	p.angle = rom[t + 6 * i + 5]
	x = MwRinkSim.s16(x + MwGfx.s16(rom, t + 6 * i))
	y = MwRinkSim.s16(y + MwGfx.s16(rom, t + 6 * i + 2))
	p.target_x = x
	p.target_y = y
	p.motion.init(x, y, 0)
	p.anim.variant = MwSimPlayers.variant_of(p.angle)
	sim.players.stop(p)
	sim.players.enter(p, 0)


# --- a CPU team's line-up --------------------------------------------------------------------

## `$F4EE` (Reserves on): the CPU coach's line changes, slots 0-5: a player
## in the penalty box stays; one with health $400000 or more (half) stays
## 3 times in 4 (`rng`); the others (empty slots too) go off (`$D2C`) and
## the best available player for the position comes on (`$F6A8`). A
## goalie's change may also swap the Demon Net: a team attacking down with
## the Demon Net in its own (top) net puts the stadium's net back and a
## goalie in 1 time in 4 (else the net stays and the slot empty); one with
## the Demon Net available (+4 bit 3) puts it in instead of a goalie 1
## time in 4.
static func cpu_line_changes(sim: MwRinkSim, team: MwRinkState.Team) -> void:
	var s := sim.s
	if not s.reserves:
		return
	for p in team.players:
		if p.original != 0:
			if sim.players._in_box(team, p.slot):
				continue
			if (team.health[p.slot] & 0xFFFFFFFF) >= 0x400000:
				if sim.rng_next() & 0xFFFF >= 0x4000:
					continue
		sim.players.off_ice(p)
		if p.position == 5:
			if team.flags4 & 2 and s.nets[0].style == 0:        # `$7A6`: the Demon Net guards it
				if sim.rng_next() & 0xFFFF >= 0x4000:
					continue
				set_top_net(sim, sim.rom[MwRinkState.stadium_record(sim.rom, s.stadium) + 5])   # `$7D2`
			elif team.flags4 & 2 and team.flags4 & 8:
				if sim.rng_next() & 0xFFFF < 0x4000:
					set_top_net(sim, 0)                         # `$7C0`: the Demon Net, no goalie
					continue
		sim.players.substitute(p)


## `$6C8` for the top net: style [param style] (0 Demon Net), its
## animation (variant 1), back in place.
static func set_top_net(sim: MwRinkSim, style: int) -> void:
	var n := sim.s.nets[0]
	n.style = style & 0xFF
	n.bottom = false
	n.anim = MwAnimState.from_record(sim.rom, MwGfx.u32(sim.rom, MwRinkState.NET_ANIMS + 4 * n.style), 1)
	n.motion.init(0, -MwRinkState.NET_Y, 0)


## `$F59E` (not in the attract demo): the CPU coach may arm a special play
## (team +$4A5; it keeps its value otherwise). With 3 players in the box
## and this period's play (team +$330 + period - 1) being 11, that one;
## with a box entry 8+ ticks (?) over and the referee bribed by the other
## team, 10; else a random pick (`rng & 3`: 0 this period's play, 1-3 plays
## 9, 10, 11 from +$333) armed with the play's odds `$1E9D8` (`rng`), not
## 9 (Bribe the Ref) when this team bribed him, not 10 (Phony Penalty?)
## unless the other team did, not 11 unless 2 or more are in the box.
static func cpu_special_play(sim: MwRinkSim, team: MwRinkState.Team) -> void:
	var s := sim.s
	if s.fight_block != 0:                    # `$FFCA1C`: the attract demo
		return
	var me: int = MwRinkRam.TEAMS[s.teams.find(team)] & 0xFFFF
	var n := 0
	var over := 0
	for i in 3:
		var t := team.stat(0x372 + 0x14 * i, 1)
		if t != 0:
			n += 1
			if MwRinkSim.s8(t) <= -8:
				over += 1
	var per := MwRinkSim.s8(s.period) - 1
	if n >= 3 and (per & 0xFFFF) < 3 and team.x330[per] == 0xB:
		team.special = 0xB
		return
	if over != 0 and s.bribe != 0 and s.bribe != me:
		team.special = 0xA
		return
	var r := sim.rng_next() & 3
	var c: int
	if r != 0:
		c = team.x330[2 + r]                  # +$333..+$335
	else:
		if (per & 0xFFFF) >= 3:
			return
		c = team.x330[per]
	c = MwRinkSim.s8(c)
	match c:
		0:
			return
		9:
			if s.bribe == me:
				return
		0xA:
			if s.bribe == 0 or s.bribe == me:
				return
		0xB:
			if team.stat(0x39F, 1) < 2:
				return
	if c < 0 or c > 0xB:
		return                                # (the jump table has 12 entries)
	if sim.rng_next() & 0xFFFF < MwGfx.u16(sim.rom, SPECIAL_ODDS + 2 * c):
		team.special = c
