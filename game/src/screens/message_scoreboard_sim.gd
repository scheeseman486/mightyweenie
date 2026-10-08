class_name MwMessageScoreboardSim
extends MwScreenSim
## Screen 17, the message scoreboard (`$E612`; plan 11,
## docs/re/scoreboards.md): after a penalty (phase 2) or a fight (screen 18)
## every called player on the ice - team A's slots 0-5, then team B's - is
## announced in the message panel ("number name / N:00 PENALTY FOR / the
## penalty", 180 ticks), walks to his team's penalty box (`$A2A4` puts him
## in when the panel has closed) while his portrait talks (a fight's winner,
## `$FFC63C`, adds a quote of category 11), and his box entry starts
## showing; then the scoreboard menu opens by itself (Start 5, A 8, B 10,
## C 7, newly pressed on any pad). A new referee (phase 12) or a forfeit
## (13) shows the referee's face and a quote of category 13 instead, ignores
## the pads for 180 ticks and leaves on Start only (5; a forfeit: 15, the
## winner in `$FFC640`, or 16 in the playoffs after `$12854`).
##
## Start on the fouled human team's pad ([member pad]) skips the sequence:
## everyone left goes to the box at once. Returns from 7 / 8 / 10 redo the
## set-up in menu mode (state -1), the box as it was.
##
## The state machine ([member state], `$FFFFF2`, table `$1D2DC`): 0 next
## called player (`$E9D0`), 1 the panel opening, 2 the info for 180 ticks,
## 3 the panel closing while he starts walking (then into the box), 4-7
## the walk (up, to the box's door at x 189, along it, until level with
## his entry), 8 the referee's message, 9 waiting; -1 the menu.
##
## Locals at a6 = `$FFFFF8`: -6 [member state], -$5C [member lockout], -$C
## [member panel], -$E [member menu], -$56 [member music], -$4E [member
## referee], -$34 [member pad], -$3A [member current], -$36 [member side],
## -$32 [member portrait_on], -$30 [member portrait], -$12 [member stamp],
## -$3C / -$40 / -$42 [member entry] / its address / [member target_y],
## -$52 [member quote_at], -$5A [member name], -4 [member snapshot].
##
## Draws and events as [MwScoreboardSim] (its class description gives the
## formats).

const LOCALS := 0xFFFFF8
const SPEECH_RECT := 0x1D314         ## (2, 2, 36, 5)
const BOX_Y := [0x1D30C, 0x1D304]    ## the box entries' y by team (A: -52, -84, -116; B: 52, 84, 116)
const PENALTY_NAMES := 0x1CA3A       ## by the code (signed): the penalty's name
const MINUTES_TEXT := 0x50D1D        ## ":00 PENALTY FOR"
const NUMBER_FONT := 0x22D66
const TEXT_FONT := 0x447F4
const REF_STANDS := 0x213DC
const REF_POINTS := 0x213FC
const REF_WAVES := 0x2140C
const LOCKOUT := 180
const INFO_TICKS := 180
const BOX_DOOR := 0xBD               ## x 189: the walk turns along the box
const FRONT_X := 0xB9                ## |x| <= 185: drawn in front of the box (priority)
const WALK_SPEED := 0x100
const PORTRAIT_AT := Vector2i(0x8C, 0x3C)
const REFEREE_AT := Vector2i(0xA0, 0xD4)
const MENU := -1
## The screen dispatcher's A6 as 17's `link` saves it (`$FFFFF8`): the
## puck's RAM address, left by the rink (every recording), and the
## dispatcher's return address (`$FFFFFC`).
const SAVED_A6 := 0xFFFFB3C2
const DISPATCH_RETURN := 0x20AE

## -6: the state (signed; -1 the menu).
var state := 0
## -$5C: ticks the pads are ignored for (180 for a referee's message).
var lockout := 0
## -$C..-$8: the message panel.
var panel := MwMessagePanel.new()
## -$E: the menu is shown (a counter).
var menu := 0
## -$56: the music's handle (-1: none).
var music := -1
## -$4E: the referee's animation object (drawn at (160, 212)).
var referee := MwAnimState.new()
## -$34: 2 x the pad whose Start skips (the fouled human team's, else 0).
var pad := 0
## -$3A: the called player being handled (null: none).
var current: MwRinkState.Player = null
## -$36: 0 while team A's players are handled, -1 for team B's.
var side := 0
## -$32: the portrait is shown (a counter).
var portrait_on := 0
## -$30: the portrait object.
var portrait := MwScoreboardSim.Portrait.new()
## -$12: the tick the info's 180 ticks count from.
var stamp := 0
## -$3C: the box entry [member current] got (3: the box was full).
var entry := 0
## -$40: that entry's address (0: none).
var entry_at := 0
## -$42: |y| where his walk ends (`$1D304`[entry]).
var target_y := 0
## -$52: the quote's address.
var quote_at := 0
## -$5A: the name under the portrait (0: none).
var name := 0
## -4: the tick of the last pass boundary.
var snapshot := 0
## a3 / a4: the team being handled and the other (swapped for good when
## team B's players come, and by the referee's message).
var team_a3: MwRinkState.Team
var team_a4: MwRinkState.Team
## The rink's players / penalties code the screen calls.
var rink: MwRinkSim
var _known := {}                     ## locals set in this visit (the others are stale stack)
var _walked := {}                    ## players whose slot this visit moved


func ported() -> bool:
	return true


# --- set-up ------------------------------------------------------------------------------------

## `$E612`: the scorer forgotten unless after a fight; the set-up (`$9034`);
## state 0, or 8 with 180 ticks of lockout in phases 12 / 13; a return from
## 7 / 8 / 10 in menu mode with the menu shown; the referee standing; the
## skip pad (`$E994` for team A, then team B: a team with a human pad whose
## opponent's box stopped play).
func enter(st: MwRinkState, screen_id: int, from_screen: int) -> void:
	super.enter(st, screen_id, from_screen)
	begin_pass()
	rink = MwRinkSim.new(rom, s)
	rink.live = live()
	rink.human.a6_view = frame_view(rom)
	_known.clear()
	_walked.clear()
	if from != 18:
		s.scorer = 0
	MwScoreboardSim.backdrop(self)
	team_a3 = s.teams[0]
	team_a4 = s.teams[1]
	state = 0
	lockout = 0
	if (s.phase & 0xFFFF) >= 12:
		state = 8
		lockout = LOCKOUT
	current = null
	side = 0
	portrait_on = 0
	panel.reset()
	menu = 0
	music = -1
	if from >= 7 and from <= 10:
		state = MwRinkSim.s16(state - 1)
		_menu_show()
	referee = MwAnimState.from_record(rom, REF_STANDS)
	var d0 := _fouled_pad(team_a3, team_a4, 0)
	d0 = _fouled_pad(team_a4, team_a3, d0)
	pad = (d0 * 2) & 0xFFFF
	snapshot = MwScoreboardSim.setup_tick(self)


## What `$1856` (a human player sent to the box hands control on: `$A2A4`
## -> `$D2C` -> `$D1C`) reads as the puck through A6 = this handler's frame
## `$FFFFF8`: +0 the dispatcher's saved A6 (the puck's address, left there
## by the rink: [constant SAVED_A6]), +4 the return address's high word
## ([constant DISPATCH_RETURN]); past `$FFFFFF` the 24-bit address wraps to
## the ROM: +8 its long at 0 (the initial stack pointer), +$C its word at 4,
## +$3D its byte at `$35` (the flags: not carried). In this ROM: the point
## (-77, 0) a neutral-zone "puck" at rest.
static func frame_view(rom_: PackedByteArray) -> MwHumanControl.A6View:
	var v := MwHumanControl.A6View.new()
	v.x = SAVED_A6 - 0x100000000 if SAVED_A6 >= 0x80000000 else SAVED_A6
	v.vx = DISPATCH_RETURN >> 16
	var y := MwGfx.u32(rom_, 0)
	v.y = y - 0x100000000 if y >= 0x80000000 else y
	v.vy = MwGfx.s16(rom_, 4)
	v.flags = rom_[0x35]
	return v


## `$E994`: [param team]'s first pad when it has a human pad (+4 bit 2) and
## [param other]'s box stopped play (+$3A1 bit 0), else [param d0].
static func _fouled_pad(team: MwRinkState.Team, other: MwRinkState.Team, d0: int) -> int:
	if team.flags4 & 4 == 0:
		return d0
	if MwRinkPenalties.flags(other) & MwRinkPenalties.STOP == 0:
		return d0
	return int(team.pads[0]) & 0xFF


## `$E8EA`: the menu shown (the panel opening), then `$E8F6`.
func _menu_show() -> void:
	menu = (menu + 1) & 0xFFFF
	panel.move(1)
	_music()


## `$E8F6`: the crowd off, the music `$1B` (again, `$E8FE`).
func _music() -> void:
	crowd_off()
	music = MwScoreboardSim.play_music(self)


# --- the pass ----------------------------------------------------------------------------------

## `$E6C0`: one pass (see the class description). Returns the next screen
## once a choice is made, else -1.
func step(elapsed: int, held: Array, new: Array) -> int:
	var e := elapsed & 0xFFFF
	snapshot = (snapshot + e) & 0xFFFFFFFF
	panel.step(e, rom, window_ops)
	if state >= 0:
		_state_step(e)
	if menu == 0:
		if portrait_on == 0:
			crowd_level(MwScoreboardSim.CROWD)  # `$E6FC`
	else:
		if not playing(music):
			_music()
		if panel.dir == 0:
			window_ops.append_array(MwScoreboardBackdrop.menu_texts(rom, screen, s.reserves))
	if portrait_on != 0:
		portrait.advance(self, e)
		portrait.draw(self, PORTRAIT_AT.x, PORTRAIT_AT.y, 0, team_a3.attr)
		if name != 0:
			MwScoreboardSim.centred_name(self, name)
		if MwScoreboardSim.player_long(current) == s.scorer & 0xFFFFFFFF:
			MwScoreboardSim.speech_frame(self, MwScoreboardSim.rect_at(rom, SPEECH_RECT), false)
			MwScoreboardSim.print_quote(self)
			MwScoreboardSim.bubble_tail(self)
	box_display(self, e)
	referee.advance(e)
	sprite_ops.append(MwScoreboardSim.anim_op(referee, REFEREE_AT.x, REFEREE_AT.y, 0xFFFF, 0xA0))
	plane_ops.append_array(MwScoreboardBackdrop.numbers(rom, s))
	lockout = MwRinkSim.s16(lockout - e)
	if lockout >= 0:
		return -1
	lockout = 0
	MwScoreboardSim.read_pads(s, held, new)
	if state < 0:
		return _menu_input(new)
	var i := pad >> 1
	var b := int(new[i]) & 0xFF if i < 4 else 0
	if b & 0x80 == 0:
		return -1
	return _skip()


## `$E8DE`: menu mode - the menu shown first; then newly pressed buttons on
## any pad: Start 5, A 8, B 10, C 7.
func _menu_input(new: Array) -> int:
	if menu == 0:
		_menu_show()
		return -1
	var w := 0
	for p in 4:
		w |= int(new[p]) & 0xFF
	var to := -1
	if w & 0x80:
		to = 5
	elif w & 0x40:
		to = 8
	elif w & 0x10:
		to = 10
	elif w & 0x20:
		to = 7
	if to < 0:
		return -1
	return MwScoreboardSim.leave(self, to, music)


## `$E82A`: Start on the skip pad: the panel closing, the portrait stopped
## and its name erased, the frame rubbed out, the referee standing; the
## referee's message leaves (`$E93E`); a sequence sends the current player
## (if still called) and every called player left to the box at once, their
## entries shown; the menu opens on the next pass.
func _skip() -> int:
	panel.move(-1)
	if portrait_on != 0:
		portrait.stop(self)
		MwScoreboardSim.name_erase(self)
		portrait_on = 0
	MwScoreboardSim.speech_frame_erase(self, MwScoreboardSim.rect_at(rom, SPEECH_RECT))
	referee = MwAnimState.from_record(rom, REF_STANDS)
	if (state & 0xFFFF) >= 8:
		return _message_exit()
	while true:
		if current == null:
			push_warning("MwMessageScoreboardSim: a skip with no current player")
		elif current.flags & MwRinkState.Player.IN_BOX:
			_put_in_box(current)
		if entry < 3 and entry_at != 0:
			_show_entry()
		_next_called()
		panel.move(-1)
		if state < 0:
			break
	return -1


## `$E93E`: the referee's message left on Start: a new referee goes on (5);
## a forfeit: the other team wins (`$FFC640`), 15 - or in the playoffs the
## playoff game's end (`$12854`, its result not kept) and 16.
func _message_exit() -> int:
	var to := 5
	if s.phase != 12:
		s.scoring = 0xFFFF0000 | MwScoreboardSim.TEAM_WORDS[s.teams.find(team_a4)]
		to = 15
		if s.play_mode != 0:
			s.playoffs.game_over(team_a4 == s.teams[0], true)
			to = 16
	return MwScoreboardSim.leave(self, to, music)


# --- the states --------------------------------------------------------------------------------

## `$E9B8`: the state's routine (table `$1D2DC`).
func _state_step(e: int) -> void:
	match state:
		0:
			_next_called()
		1:
			_panel_opened()
		2:
			_info()
		3:
			_to_box(e)
		4:
			_walk_up(e)
		5:
			_walk_to_door(e)
		6:
			_talk_again(e)
		7:
			_walk_along(e)
		8:
			_referee_message()


## `$E9D0`: the next called player (+$74 bit 1) on the ice after
## [member current] - team A's slots, then team B's (a3 / a4 swapped, side
## -1): the panel opens for him (state + 1); none left: the menu (-1).
func _next_called() -> void:
	var p := current
	var i := 0
	if p == null:
		i = 0
	else:
		i = _next_slot(p)
		if i < 0:
			return
	while true:
		var q := team_a3.players[i]
		if q.present and q.flags & MwRinkState.Player.IN_BOX:
			current = q
			panel.move(1)
			state = MwRinkSim.s16(state + 1)
			return
		i = _next_slot(q)
		if i < 0:
			return


## The slot after [param p] in a3's team (its +$67 = 5: team B's first, or
## the end of the sequence: -1).
func _next_slot(p: MwRinkState.Player) -> int:
	if p.index == 5:
		if team_a3 == s.teams[1]:
			state = MENU
			return -1
		var t := team_a3
		team_a3 = team_a4
		team_a4 = t
		side = MwRinkSim.s16(side - 1)
		return 0
	return team_a3.players.find(p) + 1


## `$EA20`: the panel open: the info's stamp, the referee pointing (state 2).
func _panel_opened() -> void:
	if panel.dir != 0:
		return
	stamp = MwScoreboardSim.tick_early(self)
	_known["stamp"] = true
	referee = MwAnimState.from_record(rom, REF_POINTS)
	referee.flags |= MwAnimState.PLAYING
	state += 1


## `$EA4C`: the info (`$ED16`) every pass; after 180 ticks the panel
## closes and he stands at (175, +-180), walking (animation 0), facing
## left (A, variant 6) / right (B, 2) (state 3).
func _info() -> void:
	_info_text()
	if ((MwScoreboardSim.tick_early(self) - stamp) & 0xFFFF) < INFO_TICKS:
		return
	panel.move(-1)
	var p := current
	p.motion.init(0xAF, -0xB4 if side != 0 else 0xB4, 0)
	rink.players.play(p, 0)
	p.anim.variant = 2 if side != 0 else 6
	_walked[p] = true
	state += 1


## `$ED16`: the panel's text (window, attr `$60`): his number (two digits)
## and name in `$22D66` centred on row 8; the penalty's minutes (one digit,
## `$A482` / 60) at (12, 11) and ":00 PENALTY FOR" after them; the
## penalty's name (`$1CA3A`) centred on row 12.
func _info_text() -> void:
	var p := current
	var nm := MwGfx.u32(rom, p.record)
	var x := ((0x28 - (MwRinkPhases.text_width(rom, NUMBER_FONT, nm) + 3)) & 0xFFFF) >> 1
	var num := rom[p.record + 4]
	var tens := 0x30 + (num / 10) % 256
	var ones := 0x30 + num % 10
	window_ops.append(["glyph", NUMBER_FONT, x, 8, 0x60, tens])
	x += MwRinkPhases.glyph_width(rom, NUMBER_FONT, tens)
	window_ops.append(["glyph", NUMBER_FONT, x, 8, 0x60, ones])
	x += MwRinkPhases.glyph_width(rom, NUMBER_FONT, ones)
	window_ops.append(["text", NUMBER_FONT, x + 1, 8, 0x60, nm])
	var code := MwRinkSim.s8(p.penalty)
	var minutes := MwRinkPenalties.seconds_for(rom, code, s.period_row) / 60
	window_ops.append(["glyph", TEXT_FONT, 0xC, 0xB, 0x60, (0x30 + minutes) & 0xFF])
	window_ops.append(["text_after", TEXT_FONT, 0xB, 0x60, MINUTES_TEXT])
	var pn := MwGfx.u32(rom, PENALTY_NAMES + 4 * code)
	var w := MwRinkPhases.text_width(rom, TEXT_FONT, pn)
	window_ops.append(["text", TEXT_FONT, ((0x28 - w) & 0xFFFF) >> 1, 0xC, 0x60, pn])


## `$EAA6`: while the panel closes he walks; closed: into the box
## (`$A2A4`, his position kept), his entry's |y| noted, his name and
## portrait (a fight's winner: a quote of category 11 and the speech box
## filled), the portrait talking, the crowd off (state 4). Either way the
## walk's step follows (`$EB6A`).
func _to_box(e: int) -> void:
	if panel.dir == 0:
		var p := current
		var at := p.motion.pixels()
		_put_in_box(p)
		target_y = MwGfx.s16(rom, BOX_Y[1] + 2 * entry)
		_known["target"] = true
		p.motion.init(MwRinkSim.s16(at.x), MwRinkSim.s16(at.y), MwRinkSim.s16(at.z))
		name = MwGfx.u32(rom, p.original)
		_known["name"] = true
		var set := portrait.set_player(rom, p.original, 0)
		_known["portrait"] = true
		var winner := MwScoreboardSim.player_long(p) == s.scorer & 0xFFFFFFFF
		if winner:
			if set >= 9:
				set = 0
			var sit := s.goal_kind & 0xFFFF
			if sit >= 2:
				sit = 0
			quote_at = MwScoreboardSim.quote_pick(self, set, 11, sit, team_a3, team_a4, -1)
			_known["quote"] = true
		portrait.start(rom, 0)
		portrait_on = 1
		crowd_off()                             # `$EB42`
		if winner:
			MwScoreboardSim.speech_frame(self, MwScoreboardSim.rect_at(rom, SPEECH_RECT), true)
		state += 1
	_walk_up(e)


## `$A2A4` on [param p] (a3's team): the entry and its address noted.
func _put_in_box(p: MwRinkState.Player) -> void:
	entry = rink.penalties.put_in_box(p)
	entry_at = 0
	if entry < 3:
		entry_at = 0xFFFF0000 | ((int(MwRinkRam.TEAMS[p.team]) + MwRinkPenalties.entry(entry)) & 0xFFFF)
	_known["entry"] = true
	_walked[p] = true


## The entry at [member entry_at] shown (+6 bit 7: its animation plays).
func _show_entry() -> void:
	for t in 2:
		for i in 3:
			var a := (int(MwRinkRam.TEAMS[t]) + MwRinkPenalties.entry(i)) & 0xFFFF
			if a == entry_at & 0xFFFF:
				var team := s.teams[t]
				var o := MwRinkPenalties.entry(i) + 6
				MwRinkPenalties.set_byte(team, o, MwRinkPenalties.byte(team, o) | 0x80)


## `$EB6A`: walking up (angle `$C0` / down `$40` for team B); level with
## the box (|y| <= 14): the referee waves, the portrait pulls a face (state 5).
func _walk_up(e: int) -> void:
	_walk(e, 0x40 if side != 0 else 0xC0)
	if absi(MwRinkSim.s16(MwRinkSim.asr(current.motion.pos[1], 8))) > 0xE:
		return
	referee = MwAnimState.from_record(rom, REF_WAVES)
	referee.flags |= MwAnimState.PLAYING
	portrait.start(rom, 1)
	state += 1


## `$EBBA`: walking to the box's door (angle `$E0` / `$20`) until x >= 189 (state 6).
func _walk_to_door(e: int) -> void:
	_walk(e, 0x20 if side != 0 else 0xE0)
	if MwRinkSim.s16(MwRinkSim.asr(current.motion.pos[0], 8)) >= BOX_DOOR:
		state += 1


## `$EBE0`: the face over: talking again (state 7); then `$EBF8`'s step
## (with no ticks after a restart: `$B542` leaves d0 = 0, the elapsed).
func _talk_again(e: int) -> void:
	if not portrait.anim.playing():
		portrait.start(rom, 0)
		state += 1
		e = 0
	_walk_along(e)


## `$EBF8`: walking along the box (`$C0` / `$40`) until level with his
## entry: the entry shown, the frame rubbed out, the portrait stopped and
## its name erased (state 0: the next player).
func _walk_along(e: int) -> void:
	_walk(e, 0x40 if side != 0 else 0xC0)
	if absi(MwRinkSim.s16(MwRinkSim.asr(current.motion.pos[1], 8))) < target_y:
		return
	if entry < 3 and entry_at != 0:
		_show_entry()
	MwScoreboardSim.speech_frame_erase(self, MwScoreboardSim.rect_at(rom, SPEECH_RECT))
	portrait.stop(self)
	MwScoreboardSim.name_erase(self)
	portrait_on = 0
	state = 0


## `$ECD0`: a step of the walk at [param angle] (speed `$100`: `$1543A`,
## `$141AE` with the players' motion parameters), drawn through the side
## view (`draw_actor`, `$5AC2`) with the team's attr, in front of the box
## while |x| <= 185.
func _walk(e: int, angle: int) -> void:
	var p := current
	var v := rink.polar(angle, WALK_SPEED)
	p.motion.vel[0] = MwRinkSim.s16(v.x)
	p.motion.vel[1] = MwRinkSim.s16(v.y)
	rink.players.move(p, e)
	_walked[p] = true
	var x := MwRinkSim.s16(MwRinkSim.asr(p.motion.pos[0], 8))
	var attr := 0x80 if MwRinkSim.s16(absi(x)) <= FRONT_X else 0
	attr |= team_a3.attr & 0xFF
	var m := p.motion.pixels()
	var pt := MwScoreboardSim.project(s, m.x, m.y, m.z)
	sprite_ops.append(MwScoreboardSim.anim_op(p.anim, pt.x, pt.y, pt.z, attr))


## `$EC76`: the referee's message: no player, no name; the face of no
## record (the referee's) pulling a face; a quote of category 13 (0 a new
## referee, 1 a forfeit) about `$FFC640`'s team (a3 set to it); the speech
## box filled; the portrait on (state 9).
func _referee_message() -> void:
	current = null
	name = 0
	_known["name"] = true
	portrait.set_player(rom, 0, 0)
	_known["portrait"] = true
	portrait.start(rom, 1)
	if (0xFFFF0000 | MwScoreboardSim.TEAM_WORDS[s.teams.find(team_a3)]) != s.scoring & 0xFFFFFFFF:
		var t := team_a3
		team_a3 = team_a4
		team_a4 = t
	quote_at = MwScoreboardSim.quote_pick(self, 0, 13, MwRinkSim.s16(s.phase - 12), team_a3, team_a4, -1)
	_known["quote"] = true
	MwScoreboardSim.speech_frame(self, MwScoreboardSim.rect_at(rom, SPEECH_RECT), true)
	portrait_on = (portrait_on + 1) & 0xFFFF
	state += 1


# --- the box display ---------------------------------------------------------------------------

## `$EDD8`, the penalty boxes' occupants (screens 17 and 19): for team A's
## box, then team B's, each entry (0-2) with a code (+$10) whose animation
## copy plays (+6 bit 7) is advanced [param elapsed] ticks and drawn at the
## box's next y (`$1D30C`: -52, -84, -116 for team A, `$1D304`: 52, 84, 116
## for team B - the y moves on per entry drawn) at x 189 through the side
## view (`$5AC2`) with the team's attr. Call it once per pass (after the
## state's routine, before the score panel, as 17 and 19 do):
## `MwMessageScoreboardSim.box_display(self, e)` from any [MwScreenSim];
## the sprites go to [member MwScreenSim.sprite_ops], the entries' animation
## (team +$362 + $14 i, +0..+$A) is written back to the team's stats.
static func box_display(sim: MwScreenSim, elapsed: int) -> void:
	for t in 2:
		var team := sim.s.teams[t]
		var k := 0
		for i in 3:
			var at := MwRinkPenalties.entry(i)
			if MwRinkPenalties.byte(team, at + 0x10) == 0 or MwRinkPenalties.byte(team, at + 6) & 0x80 == 0:
				continue
			var a := entry_anim(sim.rom, team, i)
			a.advance(elapsed)
			set_entry_anim(team, i, a)
			var y := MwGfx.s16(sim.rom, int(BOX_Y[t]) + 2 * k)
			k += 1
			var p := MwScoreboardSim.project(sim.s, BOX_DOOR, y, 0)
			sim.sprite_ops.append(MwScoreboardSim.anim_op(a, p.x, p.y, p.z, team.attr))


## Box entry [param i]'s animation copy (+0..+$A) of [param team].
static func entry_anim(rom_: PackedByteArray, team: MwRinkState.Team, i: int) -> MwAnimState:
	var at := MwRinkPenalties.entry(i)
	var b := func(o: int) -> int: return MwRinkPenalties.byte(team, at + o)
	return MwAnimState.from_fields(rom_, [(b.call(0) << 24) | (b.call(1) << 16) | (b.call(2) << 8) | b.call(3),
			(b.call(4) << 8) | b.call(5), b.call(6), b.call(7), (b.call(8) << 8) | b.call(9), b.call(0xA)])


## Box entry [param i]'s animation copy written back (+4..+$A: speed,
## flags, variant, position, frame; the record stays).
static func set_entry_anim(team: MwRinkState.Team, i: int, a: MwAnimState) -> void:
	var at := MwRinkPenalties.entry(i)
	MwRinkPenalties.set_word(team, at + 4, a.speed)
	MwRinkPenalties.set_byte(team, at + 6, a.flags)
	MwRinkPenalties.set_byte(team, at + 7, a.variant)
	MwRinkPenalties.set_word(team, at + 8, a.position)
	MwRinkPenalties.set_byte(team, at + 0xA, a.frame)


# --- comparisons ---------------------------------------------------------------------------------

func compare(ram: PackedByteArray, stack: PackedByteArray) -> Array:
	var d := MwScoreboardSim.Diff.new(MwScoreboardSim.Mem.new(ram, stack))
	var a6 := LOCALS
	d.long("snapshot -4", a6 - 4, snapshot)
	d.word("state -6", a6 - 6, state)
	d.word("lockout -$5C", a6 - 0x5C, lockout)
	d.word("panel dir", a6 - 0xC, panel.dir)
	d.word("panel remainder", a6 - 0xA, panel.remainder)
	d.word("panel size", a6 - 8, panel.size)
	d.word("menu -$E", a6 - 0xE, menu)
	d.handle("music -$56", a6 - 0x56, music >= 0)
	d.anim("referee", a6 - 0x4E, referee, 0)
	d.word("pad -$34", a6 - 0x34, pad)
	d.long("current -$3A", a6 - 0x3A, MwScoreboardSim.player_long(current))
	d.word("side -$36", a6 - 0x36, side)
	d.word("portrait on -$32", a6 - 0x32, portrait_on)
	if _known.has("stamp"):
		d.long("stamp -$12", a6 - 0x12, stamp)
	if _known.has("entry"):
		d.word("entry -$3C", a6 - 0x3C, entry)
		d.long("entry address -$40", a6 - 0x40, entry_at)
	if _known.has("target"):
		d.word("target y -$42", a6 - 0x42, target_y)
	if _known.has("quote"):
		d.long("quote -$52", a6 - 0x52, quote_at)
	if _known.has("name"):
		d.long("name -$5A", a6 - 0x5A, name)
	if _known.has("portrait"):
		portrait.compare(d, a6 - 0x30, "portrait")
	var ours := MwRinkRam.encode(s, ram)
	# the teams: the walked players' slots, the box entries, the stats
	d.ram_range(ours, MwRinkRam.TEAMS[0], MwRinkRam.TEAMS[1] + 0x4AA)
	MwScoreboardSim.compare_anim_pad(d, _walked.keys())
	MwScoreboardSim.compare_setup(d, ours)
	MwScoreboardSim.compare_speech(d, ours)
	d.ram_range(ours, MwRinkRam.SCORER, MwRinkRam.SCORER + 4)
	d.ram_range(ours, MwRinkRam.SCORING, MwRinkRam.SCORING + 4)
	d.ram_range(ours, MwRinkRam.PLAYOFFS, MwRinkRam.PLAYOFFS + 0x15)
	return d.out
