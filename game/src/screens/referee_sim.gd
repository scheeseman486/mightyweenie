class_name MwRefereeSim
extends MwScreenSim
## Screen 19, the referee cutscene after Waste the Ref (`$13A72`; plan 11,
## docs/re/referee.md): not a canned
## animation - the rink keeps simulating the referee and both teams'
## players (the team updates `$3836` with the phase-12 AI, which sends every
## skater, humans included, after the referee) in the scoreboards' side view
## (`$9034`, `$FFBDBA` = 1) until the referee has taken his 5 hits (a
## player's punch, `$982E` / `$EFC8`: 4 hurt animations, then the fall) or
## 900 ticks have passed (a forced fall), his fall animation has ended and
## 120 more ticks have passed (the crowd fading from 1000 towards 50). No
## pad is read and nothing skips it; the puck, the camera, the puck rules
## and the clock do not run. It clears the playing_team team's `+5` bit 0 once
## the referee is down and leaves for the message scoreboard (17, its "new
## referee" message).
##
## The handler's locals at a6 = `$FFFFF8`: -4 [member snapshot], -8
## [member stamp], -$A [member playing_team] (the team whose `+5` bit 0 is set,
## else team B), -$C [member other], -$E [member crowd].
##
## Draws as [MwScoreboardSim] (its class description gives the formats),
## all through the side view (`$5AC2`) with plane B's camera (0: screen
## pixels): the penalty boxes' occupants ([method
## MwMessageScoreboardSim.box_display]), the referee, the other team's
## players, then the playing_team team's (`$38E0` in phase 12: no arrows or
## markers; a player's body, his shadow when airborne as ["frame", frame,
## x, y, depth, attr], a weapon swing, the impaled overlay), the score
## panel ([member plane_ops]). Events: ["crowd", level] each pass, the
## players' and the referee's ["sound", id] (from [member
## MwRinkSim.events]), ["fade_out", 32].

const LOCALS := 0xFFFFF8
const REF_STANDS := 0x213DC          ## the referee's standing animation (`$EF84`)
const CROWD := 1000
const CROWD_DROP := 950              ## the crowd falls by this much over the last 120 ticks
const FALL_TICKS := 900              ## with hits left after this long: the forced fall
const AFTER_TICKS := 120             ## after the fall animation

## -4: the tick of the last pass boundary.
var snapshot := 0
## -8: the stamp the 900 ticks (from the set-up) and then the last 120
## (from the fall animation's last pass) count from.
var stamp := 0
## -$A: the team that played Waste the Ref (team A if its `+5` bit 0 is
## set, else team B).
var playing_team: MwRinkState.Team
## -$C: the other team.
var other: MwRinkState.Team
## -$E: the crowd's level.
var crowd := CROWD
## The rink's simulation the screen runs (team updates, the referee's hits).
var rink: MwRinkSim


func ported() -> bool:
	return true


## `$13A72` up to its loop: the backdrop (`$9034`, the side view on), the
## playing_team team and the other, the crowd at 1000, the stamps.
func enter(st: MwRinkState, screen_id: int, from_screen: int) -> void:
	super.enter(st, screen_id, from_screen)
	begin_pass()
	rink = MwRinkSim.new(rom, s)
	rink.live = live()                     # the players' and the referee's sounds (plan 12)
	MwScoreboardSim.backdrop(self)
	playing_team = s.teams[0] if s.teams[0].flags5 & 1 else s.teams[1]
	other = s.teams[1] if playing_team == s.teams[0] else s.teams[0]
	crowd = CROWD
	snapshot = MwScoreboardSim.setup_tick(self)
	stamp = snapshot


## `$13AC2`, a pass: the crowd's level, the box occupants (`$EDD8`), the
## referee (`$EF84`) and his sprite (`$EFB4`), the geometry snapshot
## (`$95C8`), the playing_team team's update then the other's (`$3836`), their
## sprites (the other's first, `$38E0`), the score panel (`$8EF4`). Then,
## with hits left: after 900 ticks the forced fall (`$EFC8` with none
## left); else the playing_team team's `+5` bit 0 cleared, and once the fall
## animation is over the crowd fades over 120 ticks and the screen leaves
## for 17 (after the 32-tick fade, `$910E`).
func step(elapsed: int, _held: Array, _new: Array) -> int:
	var e := elapsed & 0xFFFF
	snapshot = MwScoreboardSim.tick_early(self)
	rink.events.clear()
	crowd_level(crowd)                     # `$13AE0`
	MwMessageScoreboardSim.box_display(self, e)
	_referee_update(e)
	_referee_draw()
	rink.geometry()
	rink.players.team_update(playing_team, other, e)
	rink.players.team_update(other, playing_team, e)
	events.append_array(rink.events)
	_team_draw(other)
	_team_draw(playing_team)
	plane_ops.append_array(MwScoreboardBackdrop.numbers(rom, s))
	var t := MwScoreboardSim.tick_late(self)
	if s.ref_flag != 0:
		if ((t - stamp) & 0xFFFF) >= FALL_TICKS:
			s.ref_flag = 0
			var n := rink.events.size()
			rink.players._referee_hit(e)
			events.append_array(rink.events.slice(n))
		return -1
	playing_team.flags5 &= ~1
	if s.referee.anim.playing():
		stamp = t
		return -1
	var dt := (t - stamp) & 0xFFFF
	crowd = (CROWD - (CROWD_DROP * dt) / AFTER_TICKS) & 0xFFFF
	if dt < AFTER_TICKS:
		return -1
	fade_out(FADE_OUT)
	s.projection = 0
	return 17


## `$EF84`: standing again when an animation is over and hits are left
## (`$213DC` set, not playing_team); else his motion (the players' parameters)
## and animation.
func _referee_update(e: int) -> void:
	var r := s.referee
	if not r.anim.playing() and s.ref_flag != 0:
		r.anim = MwAnimState.from_record(rom, REF_STANDS)
		return
	r.motion.step(s.player_params, e)
	r.anim.advance(e)


## `$EFB4`: the referee through the side view with his attr (+$25).
func _referee_draw() -> void:
	var px := s.referee.motion.pixels()
	var m := MwScoreboardSim.project(s, px.x, px.y, px.z)
	sprite_ops.append(MwScoreboardSim.anim_op(s.referee.anim, m.x, m.y, m.z, s.ref_attr))


## `$38E0` in phase 12: each player on the ice (`$9DC`), no arrows or markers.
func _team_draw(team: MwRinkState.Team) -> void:
	for p in team.players:
		if p.present:
			_player_draw(p, team.attr & 0xFF)


## `$9DC` through the side view: the body (in front of the boxes within
## |x| 185), his shadow when airborne, a weapon swing (state 4, the
## weapon's animation at the body's hotspot 1, frames 0-3; a bomb not past
## its throw), the impaled overlay (state `$11`, species other than 1).
func _player_draw(p: MwRinkState.Player, team_attr: int) -> void:
	var attr := team_attr
	var px := p.motion.pixels()
	if s.projection != 0 and absi(px.x) <= 0xB9:
		attr |= 0x80
	var m := MwScoreboardSim.project(s, px.x, px.y, px.z)
	sprite_ops.append(MwScoreboardSim.anim_op(p.anim, m.x, m.y, m.z, attr))
	if px.z != 0:
		var sh := MwScoreboardSim.project(s, px.x, px.y, 0)
		sprite_ops.append(["frame", MwRinkDraw.SHADOW, sh.x, sh.y, MwRinkDraw.DEPTH_SHADOW, 0x60])
	if p.state == MwRinkState.Player.STATE_WEAPON and p.weapon >= 0 \
			and not (p.weapon == 3 and p.anim.position >= 0x200):
		var hot := MwScoreboardSim.hotspot(rom, p.anim, 1, 0)
		var anim := MwGfx.u32(rom, MwRinkDraw.WEAPON_ANIMS + 4 * p.weapon)
		sprite_ops.append(["anim", anim, p.anim.variant, mini(p.anim.frame, 3), MwRinkSim.s16(m.x + hot.x),
				MwRinkSim.s16(m.y + hot.y), m.z & 0xFFFF, attr])
	if p.state == MwRinkState.Player.STATE_IMPALED:
		var species := rom[p.record + 7] & 0x0F
		if species != 1:
			var imp := s.impale
			var a := MwRinkDraw.IMPALE_ANIM_2 if species == 2 else MwRinkDraw.IMPALE_ANIM
			sprite_ops.append(["anim", a, imp.variant, imp.frame, m.x, m.y, m.z & 0xFFFF,
					(attr | 8) if px.x < 0 else attr])


# --- comparisons ---------------------------------------------------------------------------------

func compare(ram: PackedByteArray, stack: PackedByteArray) -> Array:
	var d := MwScoreboardSim.Diff.new(MwScoreboardSim.Mem.new(ram, stack))
	var a6 := LOCALS
	d.long("snapshot -4", a6 - 4, snapshot)
	d.long("stamp -8", a6 - 8, stamp)
	d.word("playing_team -$A", a6 - 0xA, MwScoreboardSim.TEAM_WORDS[s.teams.find(playing_team)])
	d.word("other -$C", a6 - 0xC, MwScoreboardSim.TEAM_WORDS[s.teams.find(other)])
	d.word("crowd -$E", a6 - 0xE, crowd)
	var ours := MwRinkRam.encode(s, ram)
	# both teams (players, the box display's entries, the stats, +5), the referee
	d.ram_range(ours, MwRinkRam.TEAMS[0], MwRinkRam.TEAMS[1] + 0x4AA)
	d.ram_range(ours, MwRinkRam.REF, MwRinkRam.REF + 0x26)
	MwScoreboardSim.compare_setup(d, ours)
	return d.out
