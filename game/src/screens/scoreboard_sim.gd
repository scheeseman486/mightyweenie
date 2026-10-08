class_name MwScoreboardSim
extends MwScreenSim
## Screens 12-16, the scoreboards between plays (plan 11;
## docs/re/scoreboards.md): `$8CEE` (flag 1: 12 after a goal, 15 / 16 after
## the game) and `$8CF2` (flag 0: 13, 14 between periods) share the body
## `$8CF4`. Every pass redraws the score panel (`$8EF4`); the flag screens
## line up the event team (`$FFC640`) and animate it (`$9168` / `$91C4` /
## `$9216`: the scorer or random players celebrate, the others play rare
## random taunts - one `rng_next` per standing player per pass); 12 shows
## the scorer's comment (`$8B48` / `$8BEE` / `$8C96`: his portrait talking,
## a quote of category 10 in the speech box, his name); 14 drives Glynda the
## Zamboni ([Zamboni], `$F2B4` / `$F33A`). A new Start / A / B / C on any pad
## (or 600 ticks) opens the menu panel ([MwMessagePanel]); from the first
## menu pass Start / A / B / C leave (12: 5, 13 / 14: 4, 15: 1, 16: 11; A 8,
## B 10 on 12-14 only, C 7) after the 32-tick fade.
##
## Returns from 7 / 8 / 10 redo the whole set-up and show the menu at once
## (players re-rolled, 12's quote re-picked and erased on the first pass,
## the Zamboni restarted).
##
## The handler keeps its state in a stack frame at a6 = `$FFFFF8` ([member
## flag] -$32, [member menu] -$C, [member panel] -$A..-$6, [member music]
## -$36, [member snapshot] -4, [member stamp] -$3A, [member comment] -$2C,
## [member portrait] -$2A..-$B, [member quote_at] -$30, [member name] -$3E).
##
## Draws: [member window_ops] / [member plane_ops] as MwWindowPainter
## operations; [member sprite_ops] in screen pixels (the window plane is the
## camera: it does not scroll), in the original's order:
## * ["anim", record, variant, frame, x, y, depth, attr]: an animation
##   object's frame (`draw_anim_object` `$14444`; the players, the Zamboni,
##   its rider, the whip and the debris, the box entries and the referee on
##   17);
## * ["portrait", x, y, depth, attr, animation, variant, frame, size]: a
##   portrait object as [method MwRinkDraw.portrait] draws it (`$B61C`; size
##   0: no border);
## * ["piece", piece, x, y, attr, depth]: one sprite piece (`$156C6`, the
##   speech bubble's tail).
## Events: ["music", id, handle] (`$1B`), ["music_stop", handle], ["sound",
## id, handle] (the portrait's voices and expression sounds), ["voice_stop",
## handle], ["crowd", 50] (`$13E52`), ["crowd_off"] (`$13EFC`), ["fade_out",
## ticks] (the exit's fade, [constant MwScreenSim.FADE_OUT]).
##
## The parts 17 (and 19) share are static here: the portrait object
## ([Portrait], `$B51E`-`$B6D2`), the speech box and its quote (`$BD96`,
## `$BD9E`, `$BD82`, `$BB2E`, `$BD32`), the quote pick (`$F420`), the taunt
## roll (`$114CC`), the side-view projection (`$5AC2`) and the comparison
## helpers ([Mem], [Diff]).

const LOCALS := 0xFFFFF8             ## a6 of the scoreboards' frame
const START_SCREENS := 0x1C968       ## Start's screen by screen - 12 (5, 4, 4, 1, 11)
const PORTRAIT_AT := 0x1C972         ## the scorer's portrait: x, y, depth, attr (words)
const SPEECH_RECT := 0x1C97A         ## the comment's speech box: x, y, w, h (cells)
const TAUNTS := 0x114C2              ## `$114CC`: a skater's taunt animation by the roll 0-4
const CELEBRATE := 0x10              ## player state 16 (`$B136`, step table `$B132`): celebrate
const MUSIC := 0x1B
const MENU_TICKS := 600
const CROWD := 50
const TALK_QUIET := -400             ## the comment's talk is over below this timer (`$FE70`)
## Screen row below the boards' advertising (their last opaque row is 202):
## the lined-up players stand behind the boards, and a frame reaching lower
## (a stick blade, a skate in a taunt) shows a few stray pixels on the ice
## in the original. Ours cuts them there (owner: they look like a bug): the
## standing players' operations carry this row ([MwScreenDraw]).
const BOARDS_BOTTOM := 203
const NAME_FONT := 0x447F4
const SPEECH_FONT := 0x1F958
const BUBBLE_TAIL := 0x1FB02
const TAIL_AT := Vector2i(0xB8, 0x39)
const WINDOW := 0xFFFFB0CA           ## the window's plane object (the sprites' camera)
const QUOTES := 0x1D404
const NO_QUOTE := 0x50D2D
const STAR_PORTRAITS := 0x1CC2C      ## 6 x (player record.l, portrait data.l, quote set.w)
const SPECIES_PORTRAITS := 0x1CC68   ## by species: portrait data.l, quote set.w
const NO_PORTRAIT := 0x1CC20         ## a portrait of no record (the referee's face)
const TEAM_WORDS := [0xB402, 0xB8AC]

## -$32: 1 on 12 / 15 / 16 (the event team lined up), 0 on 13 / 14.
var flag := 0
## -$C: the menu is shown (a counter: `$8E42` adds 1).
var menu := 0
## -$A..-$6: the menu panel.
var panel := MwMessagePanel.new()
## -$36: the music's handle (-1: none).
var music := -1
## -4: the tick of the last pass boundary.
var snapshot := 0
## -$3A: the tick the 600 ticks count from.
var stamp := 0
## -$2C: 12's comment is on.
var comment := 0
## -$2A: 12's portrait object (the scorer's face).
var portrait := Portrait.new()
## -$30: the quote's address (`$FFC4FE`).
var quote_at := 0
## -$3E: the scorer's name (string address).
var name := 0
## 14: Glynda (`$FFC47A`-`$FFC4FD`).
var zamboni: Zamboni = null
## The rink's players / penalties code the screens call ([MwSimPlayers]).
var rink: MwRinkSim
var _comment_known := false          ## the comment's locals were set in this visit
var _touched := {}                   ## players whose animation object was set (+$23 cleared)


func ported() -> bool:
	return true


# --- set-up ------------------------------------------------------------------------------------

## `$8CF4`: the set-up (`$9034`, the panel, 14's Zamboni and music, the
## players, 12's comment); a return from 7 / 8 / 10 shows the menu at once.
func enter(state: MwRinkState, screen_id: int, from_screen: int) -> void:
	super.enter(state, screen_id, from_screen)
	begin_pass()
	rink = MwRinkSim.new(rom, s)
	rink.live = live()
	flag = 1 if screen in [12, 15, 16] else 0
	_touched.clear()
	backdrop(self)
	zamboni = null
	if screen == 14:
		zamboni = Zamboni.new()
		zamboni.setup(self, WINDOW, 0xD8, 0xF000)
	panel.reset()
	menu = 0
	music = -1
	comment = 0
	_comment_known = false
	if from >= 7 and from <= 10:
		_menu_show()
	if screen >= 14 and screen <= 16:
		_music_on()
	if flag != 0:
		_line_up()
	snapshot = setup_tick(self)
	stamp = snapshot
	if screen == 12:
		_comment_setup()


## The tick the end of a set-up reads (the loop's first snapshot): the
## checks know it exactly (their hooks' `setup_end`), live play reads the
## counter ([method MwScreenSim.now]).
static func setup_tick(sim: MwScreenSim) -> int:
	return _hook_tick(sim, "setup_end")


## The tick a read early in a pass sees (before its sprite upload): the
## pass boundary's (hooks' `pass_start`).
static func tick_early(sim: MwScreenSim) -> int:
	return _hook_tick(sim, "pass_start")


## The tick a read after the pass's `dma_queue_wait` sees (the queued
## sprite upload waits for a VBlank; the loop's tick wait then ends at
## once): the next pass boundary's (hooks' `pass_end`).
static func tick_late(sim: MwScreenSim) -> int:
	return _hook_tick(sim, "pass_end")


static func _hook_tick(sim: MwScreenSim, method: String) -> int:
	if sim.hooks != null and sim.hooks.has_method(method):
		return int(sim.hooks.call(method, sim)) & 0xFFFFFFFF
	return sim.now()


## `$9034`'s state changes and drawing (shared by 12-19): the backdrop's
## operations, the scroll buffers `$FFB0D8` / `$FFB0DC` cleared, the side
## view on (`$FFBDBA`).
static func backdrop(sim: MwScreenSim) -> void:
	var ops := MwScoreboardBackdrop.setup_ops(sim.rom, sim.s, sim.screen)
	sim.window_ops.append_array(ops["window"])
	sim.plane_ops.append_array(ops["plane"])
	sim.s.scroll_b = Vector2i.ZERO
	sim.s.projection = 1


## `$910E` (with the exit's fade and, once it is over, the music's
## `sound_stop`: `$8EE0` / `$E97E`): the side view off. Returns [param to].
static func leave(sim: MwScreenSim, to: int, music_handle: int) -> int:
	sim.fade_out(FADE_OUT)
	sim.events.append(["music_stop", music_handle])
	sim.sound_call(func() -> void: MwSound.stop(music_handle))
	sim.s.projection = 0
	return to


## `$8E42`: the menu shown (the panel opening), the music started.
func _menu_show() -> void:
	menu = (menu + 1) & 0xFFFF
	panel.move(1)
	_music_on()


## `$8E4E`: the music `$1B` unless it is on (crowd off first).
func _music_on() -> void:
	if music >= 0:
		return
	crowd_off()                                 # `$8E54`
	music = play_music(self)


## `$13CEE` for the music (`$8E5C`, `$E8FE`): its handle (live: the
## driver's, as [method MwScreenSim.sound]); the event ["music", id, handle].
static func play_music(sim: MwScreenSim) -> int:
	var h: int
	if sim.live():
		h = MwScreenSim.handle_of(MwSound.play(MUSIC))
	else:
		sim._serial = (sim._serial + 1) & 0x3FFFFFFF
		h = sim._serial | 0x40000000
		if sim.hooks.has_method("voice_handle"):
			h = int(sim.hooks.call("voice_handle", sim, MUSIC))
	sim.events.append(["music", MUSIC, h])
	return h


## The event team (`$FFC640`), or null.
func event_team() -> MwRinkState.Team:
	return team_of_long(s, s.scoring)


## The team a RAM address long ([param v]: `$FFFFB402` / `$FFFFB8AC`) names, or null.
static func team_of_long(st: MwRinkState, v: int) -> MwRinkState.Team:
	for t in 2:
		if v & 0xFFFF == TEAM_WORDS[t]:
			return st.teams[t]
	return null


## A player slot's RAM address long (0 for null), as `$FFC63C` and the
## handlers' locals hold them.
static func player_long(p: MwRinkState.Player) -> int:
	if p == null:
		return 0
	return 0xFFFF0000 | (MwRinkRam.player_address(p.team, p.index) & 0xFFFF)


## The player slot at a RAM address long, or null.
static func player_at(st: MwRinkState, v: int) -> MwRinkState.Player:
	if v == 0:
		return null
	for t in 2:
		for p in st.teams[t].players:
			if player_long(p) == v & 0xFFFFFFFF:
				return p
	return null


## `$9168`: every slot of the event team with a record (+$36) set: a
## goalie rolls a taunt; 12: the scorer celebrates (state 16), the others
## roll; 15 / 16: a negative `rng_next` celebrates, else a taunt roll. Then
## the state is entered (+$70, +$71 = 0, `player_state_step` `$2050`).
## (A slot without a record gets the stale d0 as its state: the previous
## slot's last value; never seen in a recording.)
func _line_up() -> void:
	var team := event_team()
	if team == null:
		return
	var d0 := 0xFF if music < 0 else music & 0xFF
	for p in team.players:
		var st := d0 & 0xFF
		if p.original != 0:
			st = 0
			if p.position == 5:
				_taunt(p)
			elif screen == 12:
				if player_long(p) == s.scorer & 0xFFFFFFFF:
					st = CELEBRATE
				else:
					_taunt(p)
			elif rng_next() & 0x8000:
				st = CELEBRATE
			else:
				_taunt(p)
		p.state = st
		p.substate = 0
		if p.original != 0:
			_state_step(p)
			d0 = p.anim_id if st == CELEBRATE else 0
		else:
			d0 = st


## `$114CC` on [param p] (and his animation object noted as set).
func _taunt(p: MwRinkState.Player) -> void:
	taunt_roll(self, rink.players, p)
	_touched[p] = true


## `$2050` for the scoreboards' states (0 stands, 16 celebrates).
func _state_step(p: MwRinkState.Player) -> void:
	var before := p.anim_id
	var sub := p.substate
	rink.players.step(p)
	if p.anim_id != before or p.substate != sub:
		_touched[p] = true


## `$114CC`: the taunt roll - `rng_next & $7F` below 5 plays a taunt (a
## goalie: animation 8 or 9 by another `rng_next`; a skater: `$114C2`[r]),
## else the player stands (`player_stop`); then variant 4 (facing the
## camera).
static func taunt_roll(sim: MwScreenSim, players: MwSimPlayers, p: MwRinkState.Player) -> void:
	var r := sim.rng_next() & 0x7F
	if r < 5:
		var id := 0
		if p.position == 5:
			id = 8 + (sim.rng_next() & 1)
		else:
			id = MwGfx.u16(sim.rom, TAUNTS + 2 * r)
		players.play(p, id)
	else:
		players.stop(p)
	p.anim.variant = 4


# --- 12's comment ------------------------------------------------------------------------------

## `$8B48`: the scorer's comment (none for an own goal: the menu at once;
## none without a scorer): his name, his portrait (`$B51E`, size 0) and
## quote set, the quote (category 10 by the goal's situation), the portrait
## talking, the speech box drawn filled, the crowd off.
func _comment_setup() -> void:
	if s.goal_kind == 6:
		_menu_show()
		return
	comment = 0
	_comment_known = true
	if s.scorer == 0:
		return
	var p := player_at(s, s.scorer)
	if p == null:
		push_warning("MwScoreboardSim: no scorer at $%08X" % s.scorer)
		return
	name = MwGfx.u32(rom, p.original)
	var set := portrait.set_player(rom, p.original, 0)
	if set >= 9:
		set = 0
	var sit := s.goal_kind & 0xFFFF
	if sit >= 7:
		sit = 0
	var team := s.teams[0] if (s.scorer & 0xFFFFFFFF) < (0xFFFF0000 | TEAM_WORDS[1]) else s.teams[1]
	var other := s.teams[1] if team == s.teams[0] else s.teams[0]
	quote_at = quote_pick(self, set, 10, sit, team, other, p.original)
	portrait.start(rom, 0)
	speech_frame(self, rect_at(rom, SPEECH_RECT), true)
	comment = 1
	crowd_off()                                 # `$8BE4`


## `$8BEE`: a pass of the comment - the portrait (advanced while its talk
## timer is above -400), the speech box framed, the quote, the bubble's
## tail, the scorer's name centred on plane B's row 17.
func _comment_pass(e: int) -> void:
	if s.goal_kind == 6 or comment == 0:
		return
	if MwRinkSim.s16(portrait.timer) >= TALK_QUIET:
		portrait.advance(self, e)
	var attr := MwGfx.u16(rom, PORTRAIT_AT + 6)
	if (s.scorer & 0xFFFFFFFF) >= (0xFFFF0000 | TEAM_WORDS[1]):
		attr = 0x40
	portrait.draw(self, MwGfx.u16(rom, PORTRAIT_AT), MwGfx.u16(rom, PORTRAIT_AT + 2), MwGfx.u16(rom, PORTRAIT_AT + 4), attr)
	speech_frame(self, rect_at(rom, SPEECH_RECT), false)
	print_quote(self)
	bubble_tail(self)
	centred_name(self, name)


## The name at [param text] (a ROM string) centred on plane B's row 17
## (`$447F4`, attr `$60`; `$8C64` / `$E756`).
static func centred_name(sim: MwScreenSim, text: int) -> void:
	var w := MwRinkPhases.text_width(sim.rom, NAME_FONT, text)
	sim.plane_ops.append(["text", NAME_FONT, ((0x28 - w) & 0xFFFF) >> 1, 0x11, 0x60, text])


## Plane B's name row cleared (8, 17, 24 x 1 with `$6001`).
static func name_erase(sim: MwScreenSim) -> void:
	sim.plane_ops.append(["fill", 8, 0x11, 0x18, 1, 0x6001])


## `$8C96`: the comment's end once the menu shows: the speech box rubbed
## out, the name row cleared, the portrait stopped.
func _comment_end() -> void:
	if s.goal_kind == 6 or comment == 0:
		return
	speech_frame_erase(self, rect_at(rom, SPEECH_RECT))
	name_erase(self)
	portrait.stop(self)
	comment = 0


# --- the pass ----------------------------------------------------------------------------------

## `$8D6E`: one pass (see the class description). Returns the next screen
## once a menu choice is made, else -1.
func step(elapsed: int, held: Array, new: Array) -> int:
	var e := elapsed & 0xFFFF
	snapshot = (snapshot + e) & 0xFFFFFFFF
	plane_ops.append_array(MwScoreboardBackdrop.numbers(rom, s))
	if flag != 0:
		_players_step(e)
		_players_draw()
	if menu == 0:
		if screen == 12:
			_comment_pass(e)
	else:
		if screen == 12:
			_comment_end()
		panel.step(e, rom, window_ops)
		if panel.dir == 0:
			window_ops.append_array(MwScoreboardBackdrop.menu_texts(rom, screen, s.reserves))
	_music_pass()
	if screen == 14:
		zamboni.pass_step(self, e)
	read_pads(s, held, new)
	var w := pads_word(held, new)
	if screen == 14 and w & 0xF:
		zamboni.whip_press(rom)
	if menu != 0:
		return _menu_input(w)
	if w & 0xF0 or ((tick_late(self) - stamp) & 0xFFFF) >= MENU_TICKS:
		_menu_show()
	return -1


## `read_joypads` as the state keeps it (`$FFCA5A`: held, newly pressed).
static func read_pads(st: MwRinkState, held: Array, new: Array) -> void:
	for p in 4:
		st.pads_held[p] = int(held[p]) & 0xFF
		st.pads_new[p] = int(new[p]) & 0xFF


## `$91C4`: every lined-up player's animation advanced; a stopped one not
## celebrating rolls a taunt (`$114CC`); his state's step (`$2050`).
func _players_step(e: int) -> void:
	var team := event_team()
	if team == null:
		return
	for p in team.players:
		if p.original == 0:
			continue
		p.anim.advance(e)
		if not p.anim.playing() and p.state != CELEBRATE:
			_taunt(p)
		_state_step(p)


## `$9216`: the lined-up players at (50 + 45 * position, 188), depth 0, the
## team's attr; celebrating ones 24 px lower, depth 1, in front.
func _players_draw() -> void:
	var team := event_team()
	if team == null:
		return
	for p in team.players:
		if p.original == 0:
			continue
		var x := 0x32 + 0x2D * (p.position & 0xFF)
		var y := 0xBC
		var depth := 0
		var attr := team.attr & 0xFF
		var op := anim_op(p.anim, x, y, depth, attr)
		if p.state == CELEBRATE:
			y += 0x18
			depth = 1
			attr |= 0x80
			op = anim_op(p.anim, x, y, depth, attr)
		else:
			op.append(BOARDS_BOTTOM)            # behind the boards: nothing below them
		sprite_ops.append(op)


## `$8E68`: the music again when it ended; without music the crowd on,
## unless 12's comment is still talking (timer above -400).
func _music_pass() -> void:
	if music >= 0:
		if not playing(music):
			music = play_music(self)
		return
	if comment != 0 and MwRinkSim.s16(portrait.timer) > TALK_QUIET:
		return
	crowd_level(CROWD)                          # `$8E8C`


## `$8E94`: the menu's buttons (newly pressed on any pad, [param w]):
## Start (`$1C968`), A 8, B 10 (12-14 only), C 7; then the fade and the
## teardown.
func _menu_input(w: int) -> int:
	var to := -1
	if w & 0x80:
		to = MwGfx.u16(rom, START_SCREENS + 2 * (screen - 12))
	elif w & 0x40:
		to = 8
	elif screen < 15 and w & 0x10:
		to = 10
	elif w & 0x20:
		to = 7
	if to < 0:
		return -1
	return leave(self, to, music)


# --- shared: the speech box, quotes, sprites ------------------------------------------------------

## A rectangle (x, y, w, h words) from the ROM.
static func rect_at(rom_: PackedByteArray, a: int) -> PackedInt32Array:
	return PackedInt32Array([MwGfx.s16(rom_, a), MwGfx.s16(rom_, a + 2), MwGfx.s16(rom_, a + 4), MwGfx.s16(rom_, a + 6)])


## `$BD96` ([param filled]: the box framed and filled, the text box
## `$FFC336` made in it and homed) / `$BD9E` (framed only): `$FFC3B4`,
## `$FFC3BC` and the rect `$FFC32E` noted, the frame drawn (`$BA98`).
static func speech_frame(sim: MwScreenSim, rect: PackedInt32Array, filled: bool) -> void:
	var st := sim.s
	st.box_fill = 1 if filled else 0
	st.box_c3bc = 0
	for i in 4:
		st.speech_box[i] = rect[i]
	sim.window_ops.append(["box", rect[0], rect[1], rect[2], rect[3], filled])
	if not filled:
		return
	var tb := st.text_box
	tb.plane = WINDOW
	tb.font = SPEECH_FONT
	tb.x = rect[0]
	tb.y = rect[1]
	tb.w = rect[2]
	tb.h = rect[3]
	tb.spacing = 0
	tb.cursor_x = 0
	tb.cursor_y = 0


## `$BD82`: the frame rubbed out (one cell around the rect, `$8000`).
static func speech_frame_erase(sim: MwScreenSim, rect: PackedInt32Array) -> void:
	sim.window_ops.append(["fill", rect[0] - 1, rect[1] - 1, rect[2] + 2, rect[3] + 2, 0x8000])


## `$BB2E`: the quote (`$FFC4FE`) written into the text box from its
## corner, attr `$E0` (`$15860`: word wrap; the cursor ends where the text
## did) - as [method MwRinkPhases._print_quote].
static func print_quote(sim: MwScreenSim) -> void:
	var rom_ := sim.rom
	var st := sim.s
	var tb := st.text_box
	tb.cursor_x = 0
	tb.cursor_y = 0
	sim.window_ops.append(["quote", tb.font, tb.x, tb.y, 0xE0, st.quote.slice(0, maxi(st.quote.find(0), 0)), tb.w, tb.h])
	var f := tb.font
	var line := MwGfx.u16(rom_, f) + tb.spacing
	var x := MwRinkSim.s16(tb.cursor_x)
	var i := 0
	var q := st.quote
	while i < q.size() and q[i] != 0:
		var ch := q[i]
		if ch < 0x21 or ch > 0x7E:
			if ch == 0x20:
				x = MwRinkSim.s16(x + MwGfx.u16(rom_, f + 2))
			elif ch == 0x0A:
				tb.cursor_y = (tb.cursor_y + line) & 0xFFFF
				x = 0
			i += 1
			continue
		var width := 0
		var j := i
		while j < q.size() and q[j] >= 0x21 and q[j] <= 0x7E:
			width += MwRinkPhases.glyph_width(rom_, f, q[j])
			j += 1
		if MwRinkSim.s16(x + width) > MwRinkSim.s16(tb.w) and x != 0:
			tb.cursor_y = (tb.cursor_y + line) & 0xFFFF
			x = 0
		if (tb.cursor_y & 0xFFFF) >= (tb.h & 0xFFFF):
			break
		x = MwRinkSim.s16(x + width)
		i = j
	tb.cursor_x = x & 0xFFFF


## `$BD32` at (184, 57): the speech bubble's tail (`$1FB02`, attr `$E0`, depth 0).
static func bubble_tail(sim: MwScreenSim) -> void:
	sim.sprite_ops.append(["piece", BUBBLE_TAIL, TAIL_AT.x, TAIL_AT.y, 0xE0, 0])


## `$F420`: quote set [param set] of [param category] for [param situation]
## expanded into `$FFC4FE` (one string: that one; several: `rng_range(0, n
## - 1)`; none: `$50D2D`): `[` [param team]'s city, a space and name, `{`
## its name, `}` [param other]'s name, `@` the string at the record
## [param who] (12: the scorer's; elsewhere a5 holds no record, -1, and no
## quote of categories 11 or 13 has an `@`). Returns the buffer's address
## (the value word is not kept).
static func quote_pick(sim: MwScreenSim, set: int, category: int, situation: int,
		team: MwRinkState.Team, other: MwRinkState.Team, who: int) -> int:
	var rom_ := sim.rom
	var t := MwGfx.u32(rom_, QUOTES + 4 * (category & 0xFFFF))
	t = MwGfx.u32(rom_, t + 4 * (situation & 0xFFFF))
	t = MwGfx.u32(rom_, t + 4 * (set & 0xFFFF))
	var count := MwGfx.u16(rom_, t + 2)
	var src := NO_QUOTE
	if count == 1:
		src = MwGfx.u32(rom_, t + 4)
	elif count > 1:
		src = MwGfx.u32(rom_, t + 4 + 4 * (sim.rng_range(0, count - 1) & 0xFFFF))
	var q := sim.s.quote
	var out := 0
	while true:
		var ch := rom_[src]
		src += 1
		match ch:
			0x40:
				if who < 0:
					push_warning("MwScoreboardSim: quote code @ without a record")
				else:
					out = _copy(rom_, q, out, MwGfx.u32(rom_, who))
			0x5B:
				out = _copy(rom_, q, out, MwGfx.u32(rom_, team.record))
				_put(q, out, 0x20)
				out += 1
				out = _copy(rom_, q, out, MwGfx.u32(rom_, team.record + 4))
			0x7B:
				out = _copy(rom_, q, out, MwGfx.u32(rom_, team.record + 4))
			0x7D:
				out = _copy(rom_, q, out, MwGfx.u32(rom_, other.record + 4))
			_:
				_put(q, out, ch)
				out += 1
				if ch == 0:
					break
	return 0xFFFFC4FE


static func _copy(rom_: PackedByteArray, q: PackedByteArray, at: int, src: int) -> int:
	while rom_[src] != 0:
		_put(q, at, rom_[src])
		at += 1
		src += 1
	_put(q, at, 0)
	return at


static func _put(q: PackedByteArray, at: int, v: int) -> void:
	if at < q.size():
		q[at] = v & 0xFF


## An animation object's frame as a sprite operation (screen pixels).
static func anim_op(a: MwAnimState, x: int, y: int, depth: int, attr: int) -> Array:
	return ["anim", a.address, a.variant, a.frame, MwRinkSim.s16(x), MwRinkSim.s16(y), depth & 0xFFFF, attr & 0xFF]


## `$5AC2`: rink point -> map point and depth; with the side view
## (`$FFBDBA`, the scoreboards) x' = y + 160, y' = 377 - |x| - z.
static func project(st: MwRinkState, x: int, y: int, z: int) -> Vector3i:
	if st.projection != 0:
		var my := MwRinkSim.s16(-absi(MwRinkSim.s16(x)) + 0x179 - z)
		return Vector3i(MwRinkSim.s16(y + 0xA0), my, MwRinkSim.s16(my + z))
	var my2 := MwRinkSim.s16(y + 0x1CD - z)
	return Vector3i(MwRinkSim.s16(x + 0x100), my2, MwRinkSim.s16(my2 + z))


## `$14472`: hotspot [param n] of [param a]'s frame, negated by the flips
## of [param attr] (bit 3 H, bit 4 V) XOR the variant's (`$1563E`, `$A142`).
static func hotspot(rom_: PackedByteArray, a: MwAnimState, n: int, attr: int) -> Vector2i:
	var f := a.frame_address(rom_)
	var flips := ((attr >> 3) & 3) ^ f.y
	var at := f.x + 2 + 6 * MwGfx.u16(rom_, f.x) + 2 * n
	var hx := MwGfx.s8(rom_, at)
	var hy := MwGfx.s8(rom_, at + 1)
	return Vector2i(-hx if flips & 1 else hx, -hy if flips & 2 else hy)


# --- the portrait object ---------------------------------------------------------------------------

## The scoreboards' portrait object (a `$20`-byte local: 12 at -$2A(a6) =
## `$FFFFCE`, 17 at -$30(a6) = `$FFFFC8`) - the coach portrait's layout
## ([MwRinkState.Portrait]) with the player routines: `$B51E` / `$B522`
## (a player's face, or the referee's for no record), `$B542` (talk or pull
## a face), `$B572` (a pass), `$B61C` (drawn), `$B656` (stopped).
class Portrait extends MwRinkState.Portrait:
	## `$B522` (`$B51E` takes the slot and passes its +$36): the portrait
	## data for player record [param record] - a star's (`$1CC2C`), else
	## his species' (`$1CC68`); none (0): the referee's face `$1CC20` - at
	## size [param size_] (0: no border), the voice handle 0, stopped.
	## Returns the quote set of the face (0 for none).
	func set_player(rom_: PackedByteArray, record_: int, size_: int) -> int:
		size = size_ & 0xFFFF
		var set := 0
		if record_ == 0:
			data = NO_PORTRAIT
		else:
			var found := false
			for i in 6:
				var a := STAR_PORTRAITS + 10 * i
				if MwGfx.u32(rom_, a) == record_:
					data = MwGfx.u32(rom_, a + 4)
					set = MwGfx.u16(rom_, a + 8)
					found = true
					break
			if not found:
				var k := 6 * (rom_[record_ + 7] & 0xF)
				data = MwGfx.u32(rom_, SPECIES_PORTRAITS + k)
				set = MwGfx.u16(rom_, SPECIES_PORTRAITS + k + 4)
		x10 = 0
		handle = 0
		anim.flags &= ~MwAnimState.PLAYING
		return set

	## `$B542`: talking (0) or pulling a face (1; 2+ as 1): that animation
	## (`anim_set`) from its start, playing, the timer at -40, two voices.
	func start(rom_: PackedByteArray, mode_: int) -> void:
		mode = 1 if (mode_ & 0xFFFF) >= 2 else mode_
		anim = MwAnimState.from_record(rom_, MwGfx.u32(rom_, data + 4 * mode))
		x0b = 0
		anim.flags |= MwAnimState.PLAYING
		timer = 0xFFD8
		voices = 2

	## `$B572`: a pass of [param e] ticks. Pulling a face: the expression
	## animates, a new frame plays the sound listed for the frame left.
	## Talking (while playing): every 8 ticks (the timer counts up from -40)
	## the voice is polled (`$13D9C`): still on, or a new one (two per
	## cycle, then a 480-tick pause, the mouth shut); the mouth alternates a
	## random frame (`rng_range(0, frames - 1)`) and frame 0.
	func advance(sim: MwScreenSim, e: int) -> void:
		var rom_ := sim.rom
		if mode != 0:
			var old := anim.frame
			anim.advance(e)
			if old == anim.frame:
				return
			var a := data + 0xA
			while true:
				var w := MwGfx.u16(rom_, a)
				if old < w:
					return
				if old == w:
					sim.sound(MwGfx.u16(rom_, a + 2))
					return
				a += 4
			return
		if not anim.playing():
			return
		var t := MwRinkSim.s16(e + timer)
		if t < 0:
			timer = t & 0xFFFF
			return
		t = MwRinkSim.s16(t - 8)
		if not sim.playing(handle):
			if voices == 0:
				timer = 0xFE20
				voices = 2
				anim.frame = 0
				return
			voices = (voices - 1) & 0xFFFF
			handle = sim.sound(MwGfx.u16(rom_, data + 8))
		if anim.frame != 0:
			anim.frame = 0
		else:
			anim.frame = sim.rng_range(0, rom_[anim.address + 3] - 1) & 0xFF
		timer = t & 0xFFFF

	## `$B656`: stopped, its voice too (`$B660`).
	func stop(sim: MwScreenSim) -> void:
		anim.flags &= ~MwAnimState.PLAYING
		sim.voice_stop(handle)
		handle = 0

	## `$B61C` on the window: drawn at ([param x], [param y]) (its border
	## first when it has a size).
	func draw(sim: MwScreenSim, x: int, y: int, depth: int, attr: int) -> void:
		sim.sprite_ops.append(["portrait", x, y, depth & 0xFFFF, attr & 0xFF, anim.address, anim.variant, anim.frame, size])

	## Its fields against the object at [param at] in the original's RAM
	## (the voice handle: zero or not).
	func compare(d: Diff, at: int, what: String) -> void:
		d.anim(what + " anim", at, anim, x0b)
		d.long(what + " data", at + 0xC, data)
		d.word(what + " +$10", at + 0x10, x10)
		d.word(what + " mode", at + 0x12, mode)
		d.word(what + " timer", at + 0x14, timer)
		d.word(what + " size", at + 0x16, size)
		d.flag(what + " voice", at + 0x18, handle != 0)
		d.word(what + " voices", at + 0x1C, voices)


# --- Glynda the Zamboni (14) ---------------------------------------------------------------------

## The Zamboni of the period break (14; `$F050`-`$F338`, RAM
## `$FFC47A`-`$FFC4FD`): it drives back and forth across the screen for
## ever (target 480 / -160, its sprite flipped at each turn) moving 7 / 0 /
## 0 / 19 px on its animation's frames; its rider grabs the 4 random pieces
## of debris as he reaches them; D-pad presses queue whip cracks.
class Zamboni:
	const RAM := 0xFFC47A
	const STEPS := 0xF116                ## px per new frame (4 bytes)
	const DEBRIS := 0x1D3E4              ## 8 debris animations
	const BODY := 0x4CC94
	const RIDER := 0x4CDE8
	const GRAB := 0x4CD74
	const WHIP := 0x4CEB2
	const GONE := 0x280                  ## a debris x once picked up (and the sentinel)
	var e := 0                           ## $C47A: the pass's ticks
	var x := 0                           ## $C47C
	var y := 0                           ## $C47E
	var depth := 0                       ## $C480
	var attr := 0                        ## $C482 (bit 3: flipped)
	var camera := 0                      ## $C484 (.l)
	var target := 0                      ## $C488
	var body := MwAnimState.new()        ## $C48A
	var rider := MwAnimState.new()       ## $C496
	var whip := MwAnimState.new()        ## $C4A2
	var debris: Array[MwAnimState] = []  ## $C4AE + $C * i
	var debris_y := PackedInt32Array([0, 0, 0, 0])            ## $C4DE
	var debris_x := PackedInt32Array([0, 0, 0, 0, GONE])      ## $C4E6 (+ the sentinel $C4EE)
	var next := 0                        ## $C4F0: the next debris x (pointer $FFFFC4E6 + 2 * next)
	var cracks := 0                      ## $C4F4: whip cracks queued
	var last_frame := 0                  ## $C4F6
	var grabbing := 0                    ## $C4F8
	var rider_x := 0                     ## $C4FA
	var whip_late := 0                   ## $C4FC: the whip past frame 8 (never read)

	## `$F2B4` ([param camera_] the window, [param y_], [param depth_]):
	## heading for 480 from x -92, the three animations playing, the debris.
	func setup(sim: MwScreenSim, camera_: int, y_: int, depth_: int) -> void:
		var rom_ := sim.rom
		target = 0x1E0
		x = -0x5C
		attr = 0xA0
		y = y_
		depth = depth_
		camera = camera_
		cracks = 0
		whip_late = 0
		e = 0
		last_frame = 0
		grabbing = 0
		rider_x = -0x5C
		body = MwAnimState.from_record(rom_, BODY)
		body.flags |= MwAnimState.PLAYING
		rider = MwAnimState.from_record(rom_, RIDER)
		rider.flags |= MwAnimState.PLAYING
		whip = MwAnimState.from_record(rom_, WHIP)
		whip.flags |= MwAnimState.PLAYING
		_debris(sim)

	## `$F050`: 4 pieces of debris, `rng_next` each: x = (r >> 10) + 32 +
	## 80 i, y = (x & 7) + y - 8, the animation `$1D3E4`[(r & $1C) / 4].
	func _debris(sim: MwScreenSim) -> void:
		debris.clear()
		for i in 4:
			var r := sim.rng_next() & 0xFFFF
			var dx := (r >> 10) + 0x20 + 0x50 * i
			debris_x[i] = dx
			debris_y[i] = MwRinkSim.s16((dx & 7) + y - 8)
			debris.append(MwAnimState.from_record(sim.rom, MwGfx.u32(sim.rom, DEBRIS + (r & 0x1C))))
		debris_x[4] = GONE
		next = 0

	## `$F33A`: a pass - the turn at the target, the pick-up, the Zamboni
	## and its rider, the whip, the debris.
	func pass_step(sim: MwScreenSim, e_: int) -> void:
		e = e_ & 0xFFFF
		if ((target - x + 0xC) & 0xFFFF) <= 0x18:
			target = -0xA0 if target >= 0 else 0x1E0
			attr ^= 8
		_pick_up(sim.rom)
		_drive(sim)
		_whip(sim)
		for i in 4:
			if debris_x[i] < 0x140:
				sim.sprite_ops.append(MwScoreboardSim.anim_op(debris[i], debris_x[i], debris_y[i], depth, attr))

	## `$F24E`: a grab done (the rider's animation over): that debris gone,
	## the rider riding again; a debris within 64 px ahead: grab it.
	func _pick_up(rom_: PackedByteArray) -> void:
		if grabbing != 0:
			if rider.playing():
				return
			grabbing = 0
			debris_x[next] = GONE
			next = mini(next + 1, 4)
			rider = MwAnimState.from_record(rom_, RIDER)
			rider.flags |= MwAnimState.PLAYING
		if MwRinkSim.s16(debris_x[next] - rider_x) > 0x40:
			return
		rider = MwAnimState.from_record(rom_, GRAB)
		rider.flags |= MwAnimState.PLAYING
		grabbing = 1

	## `$F11A`: the Zamboni's animation; a new frame moves it (`$F116`,
	## backwards while heading left); drawn, its rider at its hotspot 0.
	func _drive(sim: MwScreenSim) -> void:
		var rom_ := sim.rom
		body.advance(e)
		var f := body.frame
		if f != last_frame:
			last_frame = f
			var d: int = rom_[STEPS + f]
			if MwRinkSim.s16(target) < 0:
				d = -d
			x = MwRinkSim.s16(x + d)
		sim.sprite_ops.append(MwScoreboardSim.anim_op(body, x, y, depth, attr))
		rider.advance(e)
		var h := MwScoreboardSim.hotspot(rom_, body, 0, attr)
		rider_x = MwRinkSim.s16(h.x + x)
		sim.sprite_ops.append(MwScoreboardSim.anim_op(rider, rider_x, h.y + y, depth + 1, attr))

	## `$F1A0`: a crack done: the next queued one starts; the whip drawn
	## (idle too) at the Zamboni's hotspot 1.
	func _whip(sim: MwScreenSim) -> void:
		var rom_ := sim.rom
		var go := cracks != 0
		if go and not whip.playing():
			cracks = (cracks - 1) & 0xFFFF
			if cracks == 0:
				go = false
			else:
				whip = MwAnimState.from_record(rom_, WHIP)
				whip.flags |= MwAnimState.PLAYING
				whip_late = 0
		if go:
			whip.advance(e)
			if whip.position >= 0x800 and whip_late == 0:
				whip_late = 1
		var h := MwScoreboardSim.hotspot(rom_, body, 1, attr)
		sim.sprite_ops.append(MwScoreboardSim.anim_op(whip, h.x + x, h.y + y, depth + 2, attr))

	## `$F224`: a D-pad press: the whip starts if idle; one crack more.
	func whip_press(rom_: PackedByteArray) -> void:
		if cracks == 0:
			whip = MwAnimState.from_record(rom_, WHIP)
			whip.flags |= MwAnimState.PLAYING
			whip_late = 0
		cracks = (cracks + 1) & 0xFFFF

	## Its RAM against the original's.
	func compare(d: Diff) -> void:
		d.word("zamboni e", RAM, e)
		d.word("zamboni x", RAM + 2, x)
		d.word("zamboni y", RAM + 4, y)
		d.word("zamboni depth", RAM + 6, depth)
		d.word("zamboni attr", RAM + 8, attr)
		d.long("zamboni camera", RAM + 0xA, camera)
		d.word("zamboni target", RAM + 0xE, target)
		d.anim("zamboni body", RAM + 0x10, body, 0)
		d.anim("zamboni rider", RAM + 0x1C, rider, 0)
		d.anim("zamboni whip", RAM + 0x28, whip, 0)
		for i in 4:
			if i < debris.size():
				d.anim("debris %d" % i, RAM + 0x34 + 0xC * i, debris[i], 0)
			d.word("debris %d y" % i, RAM + 0x64 + 2 * i, debris_y[i])
		for i in 5:
			d.word("debris %d x" % i, RAM + 0x6C + 2 * i, debris_x[i])
		d.long("zamboni next", RAM + 0x76, 0xFFFFC4E6 + 2 * next)
		d.word("zamboni cracks", RAM + 0x7A, cracks)
		d.word("zamboni last frame", RAM + 0x7C, last_frame)
		d.word("zamboni grabbing", RAM + 0x7E, grabbing)
		d.word("zamboni rider x", RAM + 0x80, rider_x)
		d.word("zamboni whip late", RAM + 0x82, whip_late)


# --- comparisons ---------------------------------------------------------------------------------

## The original's memory at a pass boundary: an [MwRinkRam] image
## (`$FFB050`-`$FFCA61`) and the stack page (`$FFFE00`-`$FFFFFF`).
class Mem:
	var ram: PackedByteArray
	var stack: PackedByteArray

	func _init(ram_: PackedByteArray, stack_: PackedByteArray) -> void:
		ram = ram_
		stack = stack_

	func u8(a: int) -> int:
		a &= 0xFFFFFF
		if a >= 0xFFFE00:
			return stack[a - 0xFFFE00]
		return ram[a - MwRinkRam.BASE]

	func u16(a: int) -> int:
		return (u8(a) << 8) | u8(a + 1)

	func u32(a: int) -> int:
		return (u16(a) << 16) | u16(a + 2)


## Differences between modelled fields and the original's memory:
## [what, ours, theirs] (hex).
class Diff:
	var out: Array = []
	var m: Mem

	func _init(m_: Mem) -> void:
		m = m_

	func _note(what: String, ours: int, theirs: int, digits: int) -> void:
		if ours != theirs:
			out.append([what, ("%0" + str(digits) + "X") % ours, ("%0" + str(digits) + "X") % theirs])

	func byte(what: String, a: int, v: int) -> void:
		_note(what, v & 0xFF, m.u8(a), 2)

	func word(what: String, a: int, v: int) -> void:
		_note(what, v & 0xFFFF, m.u16(a), 4)

	func long(what: String, a: int, v: int) -> void:
		_note(what, v & 0xFFFFFFFF, m.u32(a), 8)

	## A handle's presence: [param on] against the long at [param a] being
	## non-zero.
	func flag(what: String, a: int, on: bool) -> void:
		var theirs := m.u32(a) != 0
		if on != theirs:
			out.append([what, "on" if on else "0", "%08X" % m.u32(a)])

	## A music handle's sign: [param on] against the long at [param a] being
	## non-negative.
	func handle(what: String, a: int, on: bool) -> void:
		var theirs := m.u32(a) & 0x80000000 == 0
		if on != theirs:
			out.append([what, "on" if on else "-1", "%08X" % m.u32(a)])

	## An animation object (`$C` bytes: record, speed, flags, variant,
	## position, frame, [param b] the byte after them; -1 not compared).
	func anim(what: String, a: int, n: MwAnimState, b := -1) -> void:
		long(what + " record", a, n.address)
		word(what + " speed", a + 4, n.speed)
		byte(what + " flags", a + 6, n.flags)
		byte(what + " variant", a + 7, n.variant)
		word(what + " position", a + 8, n.position)
		byte(what + " frame", a + 0xA, n.frame)
		if b >= 0:
			byte(what + " +$B", a + 0xB, b)

	## Bytes [param lo]..[param hi] of [param ours] (an encoded RAM image)
	## against the original's, by [method MwRinkRam.describe].
	func ram_range(ours: PackedByteArray, lo: int, hi: int) -> void:
		for a in range(lo, hi):
			var i := a - MwRinkRam.BASE
			if ours[i] != m.ram[i]:
				out.append([MwRinkRam.describe(a), "%02X" % ours[i], "%02X" % m.ram[i]])


## The speech box's state left for the rink (`$FFC32E`, `$FFC336`,
## `$FFC3B4`, `$FFC3BC`, the quote `$FFC4FE`), from an encoded image.
static func compare_speech(d: Diff, ours: PackedByteArray) -> void:
	d.ram_range(ours, MwRinkRam.SPEECH_BOX, MwRinkRam.SPEECH_BOX + 8)
	d.ram_range(ours, MwRinkRam.TEXT_BOX, MwRinkRam.TEXT_BOX + 0x16)
	d.ram_range(ours, MwRinkRam.BOX_FILL, MwRinkRam.BOX_FILL + 2)
	d.ram_range(ours, MwRinkRam.BOX_C3BC, MwRinkRam.BOX_C3BC + 2)
	d.ram_range(ours, MwRinkRam.QUOTE, MwRinkRam.QUOTE + MwRinkState.QUOTE_SIZE)


## What the set-up `$9034` leaves: the side view, plane B's scroll buffers.
static func compare_setup(d: Diff, ours: PackedByteArray) -> void:
	d.ram_range(ours, MwRinkRam.PROJECTION, MwRinkRam.PROJECTION + 2)
	d.ram_range(ours, MwRinkRam.SCROLL_B, MwRinkRam.SCROLL_B + 2)
	d.ram_range(ours, MwRinkRam.SCROLL_B + 4, MwRinkRam.SCROLL_B + 6)


## Bytes +$23 of the animation objects of [param players] (cleared by
## `anim_set` / `$1438E`).
static func compare_anim_pad(d: Diff, players: Array) -> void:
	for p in players:
		var pl := p as MwRinkState.Player
		d.byte("T%d P%d +$23" % [pl.team, pl.index], MwRinkRam.player_address(pl.team, pl.index) + 0x23, 0)


func compare(ram: PackedByteArray, stack: PackedByteArray) -> Array:
	var d := Diff.new(Mem.new(ram, stack))
	var a6 := LOCALS
	d.long("snapshot -4", a6 - 4, snapshot)
	d.word("panel dir", a6 - 0xA, panel.dir)
	d.word("panel remainder", a6 - 8, panel.remainder)
	d.word("panel size", a6 - 6, panel.size)
	d.word("menu -$C", a6 - 0xC, menu)
	d.word("flag -$32", a6 - 0x32, flag)
	d.handle("music -$36", a6 - 0x36, music >= 0)
	d.long("stamp -$3A", a6 - 0x3A, stamp)
	if screen == 12 and _comment_known:
		d.word("comment -$2C", a6 - 0x2C, comment)
		if s.scorer != 0:
			portrait.compare(d, a6 - 0x2A, "portrait")
			d.long("quote -$30", a6 - 0x30, quote_at)
			d.long("name -$3E", a6 - 0x3E, name)
	var ours := MwRinkRam.encode(s, ram)
	# the teams (players, their animation fields, the box) and what the set-up leaves
	d.ram_range(ours, MwRinkRam.TEAMS[0], MwRinkRam.TEAMS[1] + 0x4AA)
	compare_anim_pad(d, _touched.keys())
	compare_setup(d, ours)
	compare_speech(d, ours)
	if zamboni != null:
		zamboni.compare(d)
	return d.out
