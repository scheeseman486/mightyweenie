class_name MwFightSim
extends MwScreenSim
## Screen 18, the fight and its fight card (`$D868`; plan 11,
## docs/re/fight.md): a side-on boxing match
## over the scoreboard backdrop (`$9034`, the side view on) between the
## fighting player of each team (team A's always on the left). Both walk in
## (120 ticks), fight for 20 seconds of fight time (1200 ticks, the clock
## held while a fighter is down; Start on a human fighter's pad pauses),
## the message panel opens on the result (a knockout, a decision by punches
## landed, or a draw) for 90 ticks, the penalty calls are made (penalties
## on: `$A4AA` -7 for the winner, 1 for the loser, -7 for both after a
## draw), the screen fades and the fight card (`$E3A8`: punches thrown and
## landed, a joke row) shows for up to 480 ticks (A / B / C / Start newly
## pressed on any pad end it after 120); then the message scoreboard (17).
##
## A fighter ([Fighter], a `$5A`-byte object in the handler's frame:
## team A's at `$FFFF8C`, team B's at `$FFFF32`) has a private health of
## `$7800`, a rating from the player's FIGHTING and his team's skulls that
## sets his punch damage, walk speed and animation speed, and a state
## machine: stand, punch (B or C), block (A, held up to 30 ticks), hit,
## knocked down, down, out. The CPU's fighter (`$E15C`) punches with a
## per-pass chance near the other and wanders otherwise; it never blocks
## (it asks for a held A where the stand state wants a new one - kept).
##
## The handler keeps its state at a6 = `$FFFFF8`: -4 [member snapshot], -6
## [member state], -$A [member stamp], -$C [member fight_time], -$12
## [member panel], -$EE [member params], -$F0 [member result], -$F4
## [member winner], -$F8 [member winner_team], -$FA [member crowd]. The card
## loop's stamp ([member card_stamp]) sits at `$FFFEDE`, its ticks left
## ([member card_left]) in d4.
##
## What it leaves for the rink: the winner's team `+$49C` + 1 (fights won),
## `$FFC63A` 0 draw / 1 decision / 2 knockout, `$FFC63C` the winner's player
## (0 on a draw), the penalty calls, `$A682` after the card. The faceoff
## spot, rink health and the players' fighting flags (`+$74` bit 4) are not
## touched.
##
## Draws as [MwScoreboardSim] (its class description gives the formats):
## [member window_ops] (names, health bars, the panel, result and "PAUSE"
## texts, the card), [member plane_ops] (the score panel and the fight
## clock in the game clock's place), [member sprite_ops] (the fighters
## through plane B's camera, which `$9034` leaves at 0: screen pixels; the
## card passes repeat the last fight pass's sprites - the card's loop never
## touches the sprite table). Events: ["sound", id, handle], ["crowd",
## level], ["crowd_off"], ["fade_out", ticks], ["picture", address] /
## ["picture_free", address] (the fight's tile bank), ["palette", "screen"]
## (`$215E`), ["colour", index, value, ticks, at] (`$149B4`: CRAM colour
## [code]index[/code] to [code]value[/code], the code constant's ROM address
## [code]at[/code], 0 for black), ["sound_reset"] (`$13C04`). The pass that
## ends the fight also sets up the card: [member card_window_from] tells the
## scene where the card's window operations start (it paints them after the
## 16-tick fade).

const LOCALS := 0xFFFFF8             ## a6 of the handler's frame
const FIGHTER_AT := [0xFFFF8C, 0xFFFF32]   ## -$6C / -$C6: team A's, team B's fighter
const CARD_STAMP_AT := 0xFFFEDE      ## the card loop's stamp (its stack local)
const CARD_SOUND_AT := 0xFFC476      ## the KO / card sound's handle
const BANK := 0x2155A                ## the fight's tile bank (fighters, bars, card pieces)
const SIDES := [0x1D140, 0x1D146]    ## by side (team +4 bit 0): sprite attr, start x, walk-in velocity
const SPECIES_ANIMS := 0x1D130       ## by species: the fighter's animations by state (0-$10)
const SPECIES_2_ANIMS := 0x1D108     ## species 2's table: its victims sound `$1E`
const DAMAGE := 0x1D14C              ## by rating: a landed punch's damage
const WALK := 0x1D162                ## by rating: walk speed (8.8 px per tick)
const MOVES := 0x1D19C               ## by the held d-pad nibble: the walk routine
const MOVE_LEFT := 0xE10A
const MOVE_RIGHT := 0xE128
const HIT_SOUNDS := 0x1D194          ## by rng & 6: a landed punch's sound
const AI_BLOCK := 0x1D20A            ## by rating: the CPU's block chance (no effect)
const AI_PUNCH := 0x1D1F4            ## by rating: the CPU's punch chance
const ANIM_SPEED := 0x1D220          ## by rating: animation speed factor (/256)
const HURT_FX := 0x2154A             ## the second animation of a hit fighter
const KO_FX := 0x22894               ## ... of a knocked-down one
const DOWN_FX := 0x20BD2             ## ... of one down on the ice
const CARD_MAPS := 0x1D236           ## 7 x (map.l, copies.w, rows.w, VRAM step.w)
const CARD_LABELS := 0x1D27C         ## 4 x (x, y, string.l), then 4 joke rows of 2
const NAME_FONT := 0x22BEC
const TEXT_FONT := 0x22D66
const CARD_FONT := 0x1F958
const TIMER_FONT := 0x447F4
const DRAW_TEXT := 0x50CAB
const KO_TEXT := 0x50CB1
const WINS_TEXT := 0x50CBB
const PAUSE_TEXT := 0x50CC1
const BAR_FULL := 0x20F0             ## a full health cell (4 quarters)
const BAR_EMPTY := 0x20EC            ## an empty one (+1..+3: partial)
const ATTR := 0x60
const WINDOW_VRAM := 0xF000
const SPECIES_2_COLOUR := 0xDD66     ## `$DD64`'s `move.w #$444`: species 2's colour 10
const CARD_COLOUR := 0xE40E          ## `$E40C`'s `move.w #$AAA`: the card's colour `$39`

const HEALTH := 0x7800
const START_Y := 0xE0
const START_Z := 0x1F40
const STOP_X := 100                  ## the walk-in ends when team A's fighter reaches it
const FIGHT_TICKS := 0x4B0           ## 20 s of fight time
const REACH := 0x5A                  ## a punch lands within 90 px
const NEAR := 0x66                   ## the CPU fights within 102 px
const GAP := 0x4A                    ## the fighters stay 74 px apart
const LEFT_WALL := 0x3C
const RIGHT_WALL := 0x104
const RESULT_TICKS := 0x5A
const CROWD_START := 0x535
const CARD_TICKS := 0x1E0
const CARD_LOCK := 0x168             ## the pads count once fewer ticks than this are left
const BELL := 0x18
const KO_SOUND := 9
const BLOCK_SOUND := 0x16
const CARD_SOUND := 0x10

## Fighter states (+$3C).
const STAND := 0
const PUNCH := 4
const BLOCK := 8
const HIT := 0xC
const KNOCKED := 0x10
const DOWN := 0x14
const OUT := 0x18

## Screen states (-6).
const WALK_IN := 0
const FIGHTING := 1
const RESULT_PANEL := 2
const RESULT := 3
const CALLS := 4
const PAUSING := 6
const PAUSED := 7
const DONE := -1

## -6: the screen state (signed).
var state := 0
## -4: the tick of the last pass boundary.
var snapshot := 0
## -$A: the state's stamp (the walk-in's end, the fight clock's last
## count, the result, the resume).
var stamp := 0
## -$C: fight time (ticks of state 1).
var fight_time := 0
## -$12: the message panel.
var panel := MwMessagePanel.new()
## -$EE: the fighters' motion parameters (no gravity, no friction).
var params := MwMotion.Params.new(0, 0, 0, 0)
## Team A's (left) and team B's (right) fighter.
var fighters: Array[Fighter] = []
## -$F0: the result (0 draw, 1 decision, 2 knockout).
var result := 0
## -$F4: the winner (null on a draw).
var winner: Fighter = null
## -$F8: the winner's team + `$3A2` (a RAM address long; 0 on a draw).
var winner_team := 0
## -$FA: the crowd's level while the result shows.
var crowd := 0
## `$FFC476`: the KO sound's and then the card sound's handle.
var card_sound := 0
## The card's loop runs (the fight loop is over).
var card := false
## d4: the card's ticks left.
var card_left := 0
## The card loop's stamp (`$FFFEDE`).
var card_stamp := 0
## The card's joke row (0 bloody noses, 1 black eyes, 2 bruised egos, 3 broken nails).
var joke := 0
## In the pass that set the card up: the index in [member window_ops] where
## its operations start (the fight's last frame before); else -1.
var card_window_from := -1
## The rink's code the screen calls (the penalty calls, `$A682`).
var rink: MwRinkSim
var _known := {}                     ## locals set in this visit (the others are stale stack)
var _last_sprites: Array = []        ## the last fight pass's sprites (the card keeps them)
var _in_setup := false               ## tick reads see the set-up's tick


## A fighter (`$5A` bytes): a motion object (+0..+$17: x, y, z 24.8 with
## velocities and accelerations), its animation (+$18), the animation
## table by state (+$24), the player (+$28) and his record (+$2C), health
## (+$30), rating (+$32), damage (+$34), walk speed (+$36), sprite attr
## (+$38), pad (+$3A, the word offset into `$FFCA5A`; -1 a CPU fighter),
## state (+$3C), the CPU's remembered direction (+$3E), punches thrown
## (+$40) and landed (+$42), the second animation's y offset (+$44), stun
## (+$46), the animation position before the last advance (+$48), the
## second animation (+$4A; shown while playing), the state's stamp (+$56).
class Fighter:
	var motion := MwMotion.new()
	var anim := MwAnimState.new()
	var table := 0
	var player: MwRinkState.Player = null
	var record := 0
	var health := 0
	var rating := 0
	var damage := 0
	var speed := 0
	var attr := 0
	var pad := -1
	var state := 0
	var memory := 0
	var thrown := 0
	var landed := 0
	var fx_y := 0
	var stun := 0
	var last_position := 0
	var fx := MwAnimState.new()
	var stamp := 0
	## The object's RAM address (`$FFFF8C` / `$FFFF32`).
	var address := 0
	## Fields written in this visit ("fx", "fx_y", "last"): the others
	## are the frame's stale bytes.
	var known := {}

	## x in pixels (`asr.l #8`, the word).
	func x() -> int:
		return MwRinkSim.s16(MwRinkSim.asr(motion.pos[0], 8))

	## The record's species (byte +7, low nibble).
	func species(rom: PackedByteArray) -> int:
		return rom[record + 7] & 0xF

	## The object's address as the handler's longs hold it.
	func long() -> int:
		return 0xFFFF0000 | (address & 0xFFFF)

	## Its fields against the original's object.
	func compare(d: MwScoreboardSim.Diff, what: String) -> void:
		var a := address
		for k in 3:
			d.long("%s pos %d" % [what, k], a + 8 * k, motion.pos[k])
			d.word("%s vel %d" % [what, k], a + 8 * k + 4, motion.vel[k])
			d.word("%s acc %d" % [what, k], a + 8 * k + 6, motion.acc[k])
		d.anim(what + " anim", a + 0x18, anim, 0)
		d.long(what + " table", a + 0x24, table)
		d.long(what + " player", a + 0x28, MwScoreboardSim.player_long(player))
		d.long(what + " record", a + 0x2C, record)
		d.word(what + " health", a + 0x30, health)
		d.word(what + " rating", a + 0x32, rating)
		d.word(what + " damage", a + 0x34, damage)
		d.word(what + " speed", a + 0x36, speed)
		d.word(what + " attr", a + 0x38, attr)
		d.word(what + " pad", a + 0x3A, pad)
		d.word(what + " state", a + 0x3C, state)
		d.word(what + " memory", a + 0x3E, memory)
		d.word(what + " thrown", a + 0x40, thrown)
		d.word(what + " landed", a + 0x42, landed)
		if known.has("fx_y"):
			d.word(what + " fx y", a + 0x44, fx_y)
		d.word(what + " stun", a + 0x46, stun)
		if known.has("last"):
			d.word(what + " last position", a + 0x48, last_position)
		if known.has("fx"):
			d.anim(what + " fx", a + 0x4A, fx, 0)
		elif (d.m.u8(a + 0x50) & 0x80) != (fx.flags & 0x80):
			d.out.append([what + " fx shown", "%02X" % (fx.flags & 0x80), "%02X" % (d.m.u8(a + 0x50) & 0x80)])
		d.long(what + " stamp", a + 0x56, stamp)


func ported() -> bool:
	return true


# --- set-up ------------------------------------------------------------------------------------

## `$D868` up to its loop: the backdrop (`$9034`, the side view on), the
## fight bank, the stamp, fight time 0, no friction, the fighters (team A's
## then team B's, `$DC38`), the panel closed, the walk-in.
func enter(st: MwRinkState, screen_id: int, from_screen: int) -> void:
	super.enter(st, screen_id, from_screen)
	begin_pass()
	rink = MwRinkSim.new(rom, s)
	rink.live = live()
	_known.clear()
	_last_sprites.clear()
	card = false
	card_window_from = -1
	winner = null
	winner_team = 0
	result = 0
	MwScoreboardSim.backdrop(self)
	events.append(["picture", BANK])
	_in_setup = true
	snapshot = _now()
	fight_time = 0
	params = MwMotion.Params.new(0, 0, 0, 0)
	fighters.clear()
	for t in 2:
		var f := Fighter.new()
		f.address = FIGHTER_AT[t]
		fighters.append(f)
		_fighter_init(f, s.teams[t])
	panel.reset()
	state = WALK_IN
	_in_setup = false


## The tick a read in the set-up (the loop's first snapshot) or early in a
## pass (its boundary's) sees.
func _now() -> int:
	return MwScoreboardSim.setup_tick(self) if _in_setup else MwScoreboardSim.tick_early(self)


## `$DC38`: [param team]'s fighter: the first of slots 0-4 with a record
## and the fighting flag (`+$74` bit 4), else `rng_range(0, 4)` until the
## slot has one (`$DC66`); his pad (a human team: its first, or the second
## for a second-pad player; -1 CPU); team A's side or B's (`$1D140` /
## `$1D146`: attr, x, walk-in velocity) at (x, 224, 8000); health, the
## counts and the stun cleared; the rating (FIGHTING with the skulls,
## `$3BDE`) and what it sets; the species' animations (species 2: colour 10
## of the fighter's palette line `$444`); standing (`$DE24`).
func _fighter_init(f: Fighter, team: MwRinkState.Team) -> void:
	var p: MwRinkState.Player = null
	for i in 5:
		var q := team.players[i]
		if q.present and q.flags & MwRinkState.Player.FIGHTING:
			p = q
			break
	while p == null:
		var q := team.players[rng_range(0, 4) & 0xFFFF]
		if q.present:
			p = q
	f.pad = -1
	if team.flags4 & 4:
		var k := 1 if p.flags & MwRinkState.Player.SECOND_PAD else 0
		f.pad = (int(team.pads[k]) & 0xFF) * 2
	var side: int = SIDES[1 if team.flags4 & 1 else 0]
	f.health = HEALTH
	f.thrown = 0
	f.landed = 0
	f.stun = 0
	f.player = p
	f.record = p.record
	f.rating = rink.avg(team, rom[f.record + 9] >> 4)
	f.damage = MwGfx.u16(rom, DAMAGE + 2 * f.rating)
	f.speed = MwGfx.u16(rom, WALK + 2 * f.rating)
	f.attr = MwGfx.u16(rom, side)
	f.motion.init(MwGfx.s16(rom, side + 2), START_Y, START_Z)
	f.motion.vel[0] = MwGfx.s16(rom, side + 4)
	f.fx.flags &= ~MwAnimState.PLAYING
	f.memory = 0
	f.table = MwGfx.u32(rom, SPECIES_ANIMS + 4 * f.species(rom))
	if f.species(rom) == 2:
		events.append(["colour", ((f.attr & 0x60) >> 1) + 10, MwGfx.u16(rom, SPECIES_2_COLOUR), 0, SPECIES_2_COLOUR])
	_set_state(f, STAND)


# --- the pass ----------------------------------------------------------------------------------

## One pass: the fight loop's (`$D8D8`: the pads, the state's routine, the
## panel, the fight clock, the score panel, names and health bars, the
## fighters; once the state is -1 the fade and the card's set-up), or the
## card loop's (`$E432`). Returns 17 when the card ends, else -1.
func step(elapsed: int, held: Array, new: Array) -> int:
	var e := elapsed & 0xFFFF
	card_window_from = -1
	if card:
		return _card_pass(e, held, new)
	snapshot = _now()
	MwScoreboardSim.read_pads(s, held, new)
	match state:
		WALK_IN:
			_walk_in(e)
		FIGHTING:
			_fight(e)
		RESULT_PANEL:
			_result_panel(e)
		RESULT:
			_result()
		CALLS, 5:
			_calls()
		PAUSING:
			_pausing(e)
		PAUSED:
			_paused()
	panel.step(e, rom, window_ops)
	_clock_draw()
	plane_ops.append_array(MwScoreboardBackdrop.numbers(rom, s))
	for f in fighters:
		_name_draw(f)
		_bar_draw(f)
	for f in fighters:
		_fighter_draw(f)
	_last_sprites = sprite_ops.duplicate()
	if state == DONE:
		fade_out(16)                       # `$D948`, waited for before the card
		_card_setup()
	return -1


## The pad word of [param f] (held byte << 8 | newly pressed byte of its
## pad, `$FFCA5A`), or the CPU's (`$E15C`).
func _pad_word(f: Fighter, other: Fighter) -> int:
	if f.pad < 0:
		return _ai(f, other)
	var i := f.pad >> 1
	if i >= 4:
		push_warning("MwFightSim: pad offset %d" % f.pad)
		return 0
	return ((s.pads_held[i] & 0xFF) << 8) | (s.pads_new[i] & 0xFF)


## `$D9B8`, the walk-in: both fighters move and animate; team A's at x 100
## or more: both stop, the stamp, the bell (state 1).
func _walk_in(e: int) -> void:
	_motion_step(fighters[0], e)
	_motion_step(fighters[1], e)
	if fighters[0].x() < STOP_X:
		return
	fighters[0].motion.vel[0] = 0
	fighters[1].motion.vel[0] = 0
	stamp = _now()
	_known["stamp"] = true
	sound(BELL)
	state = FIGHTING


## `$D9F0`, the fight: team A's fighter, then B's (`$DD7E`); a knockout
## (the other out) wins, a fighter down holds the clock; Start on a human
## fighter's pad pauses (the panel opening, state 6); else the fight clock
## counts the ticks since the stamp, and at 1200 the bell and the decision
## by punches landed (equal: a draw).
func _fight(e: int) -> void:
	var a := fighters[0]
	var b := fighters[1]
	_fighter_step(a, b, e)
	_fighter_step(b, a, e)
	if b.state == OUT:
		_end(a, 2)
		return
	if b.state >= KNOCKED:
		return
	if a.state == OUT:
		_end(b, 2)
		return
	if a.state >= KNOCKED:
		return
	if _start_pressed():
		panel.move(1)
		state = PAUSING
		return
	var t := _now()
	fight_time = (fight_time + (t - stamp)) & 0xFFFF
	stamp = t
	if fight_time < FIGHT_TICKS:
		return
	sound(BELL)
	if a.landed > b.landed:
		_end(a, 1)
	elif a.landed < b.landed:
		_end(b, 1)
	else:
		_end(null, 0)


## `$DA92`-`$DAB8`: the fight's end - a winner's team `+$49C` + 1, `$FFC63C`
## his player, -$F4 / -$F8 him and his team (+$3A2); a draw clears them;
## `$FFC63A` and -$F0 the result; the panel opening (state 2).
func _end(f: Fighter, kind: int) -> void:
	if f == null:
		s.scorer = 0
		winner = null
		winner_team = 0
	else:
		var team := s.teams[f.player.team]
		team.add_stat(0x49C, 1)
		winner_team = 0xFFFF0000 | ((int(MwRinkRam.TEAMS[f.player.team]) + 0x3A2) & 0xFFFF)
		s.scorer = MwScoreboardSim.player_long(f.player)
		winner = f
	s.goal_kind = kind
	result = kind
	_known["result"] = true
	panel.move(1)
	state = RESULT_PANEL


## `$DBD8`: Start newly pressed on a human fighter's pad (team A's, then B's).
func _start_pressed() -> bool:
	for f in fighters:
		if f.pad < 0:
			continue
		var i := f.pad >> 1
		if i < 4 and s.pads_new[i] & 0x80:
			return true
	return false


## `$DABE`: the panel opening (stepped here too: twice as fast); open:
## the stamp, the crowd at 1333, the KO sound (handle in `$FFC476`) (state 3).
func _result_panel(e: int) -> void:
	panel.step(e, rom, window_ops)
	if panel.dir != 0:
		return
	stamp = _now()
	crowd = CROWD_START
	_known["crowd"] = true
	# `$DADA`: sound $1A for team B's win - dead, -$F8 holds the team + $3A2
	if winner_team == 0xFFFFB8AC:
		sound(0x1A)
	card_sound = 0
	_known["sound"] = true
	if result == 2:
		card_sound = sound(KO_SOUND)
	state = RESULT


## `$DB0A`: the result's text; the crowd 11 lower per pass (at most 1000
## heard); after 90 ticks the crowd at 50 (state 4).
func _result() -> void:
	_result_text()
	crowd = (crowd - 0xB) & 0xFFFF
	crowd_level(mini(crowd, 1000))               # `$DB24`
	if ((_now() - stamp) & 0xFFFF) < RESULT_TICKS:
		return
	crowd_level(50)                              # `$DB3E`
	state = CALLS


## `$DB4A`: with penalties on, the calls (`$A4AA`): team A's fighter, then
## B's - the loser of a decided fight 1, the others -7 (state -1).
func _calls() -> void:
	if s.penalties != 0:
		for f in fighters:
			var code := -7
			if winner != null and f != winner:
				code = 1
			rink.penalty(code, f.player)
	state = DONE


## `$DBA4`: the pause's panel opening (stepped twice); open: state 7.
func _pausing(e: int) -> void:
	panel.step(e, rom, window_ops)
	if panel.dir == 0:
		state = PAUSED


## `$DBB8`: "PAUSE"; Start on a human fighter's pad: the stamp (the pause
## does not count), the panel closing (state 1).
func _paused() -> void:
	window_ops.append(["text", TEXT_FONT, 0x11, 9, ATTR, PAUSE_TEXT])
	if not _start_pressed():
		return
	stamp = _now()
	panel.move(-1)
	state = FIGHTING


# --- a fighter ---------------------------------------------------------------------------------

## `$DD7E`: [param f]'s pad word (or the CPU's), its state's routine
## (`$1D178`), the walk (`$E0A0`), motion and animation (`$DD9A`).
func _fighter_step(f: Fighter, o: Fighter, e: int) -> void:
	var w := _pad_word(f, o)
	match f.state:
		STAND:
			_stand(f, o, w)
		PUNCH:
			_punch(f, o, w)
		BLOCK:
			_block(f, w)
		HIT:
			if not f.anim.playing():
				_set_state(f, STAND)
		KNOCKED:
			_knocked(f)
		DOWN:
			if MwRinkSim.s16(_now() - f.stamp) >= 0x78:
				f.state = OUT
	_walk(f, o, w)
	_motion_step(f, e)


## `$DD9A`: the animation position noted (+$48), motion (`$141AE`, no
## friction) and animation, the second animation while it plays.
func _motion_step(f: Fighter, e: int) -> void:
	f.last_position = f.anim.position
	f.known["last"] = true
	f.motion.step(params, e)
	f.anim.advance(e)
	if f.fx.playing():
		f.fx.advance(e)


## `$DE24`: state [param st] - knocked down: the second animation `$22894`
## 70 px up; hit (not species 1): `$2154A` 70 px up; the state's animation
## from its start at the rated speed (`$143A0`: x `$1D220`[rating] / 256),
## playing; the stamp.
func _set_state(f: Fighter, st: int) -> void:
	f.state = st
	if st == KNOCKED or (st == HIT and f.species(rom) != 1):
		f.fx = MwAnimState.from_record(rom, KO_FX if st == KNOCKED else HURT_FX)
		f.fx.flags |= MwAnimState.PLAYING
		f.fx_y = 0x46
		f.known["fx"] = true
		f.known["fx_y"] = true
	var rec := MwGfx.u32(rom, f.table + st)
	f.anim = MwAnimState.from_record(rom, rec)
	f.anim.speed = ((MwGfx.u16(rom, rec) * MwGfx.u16(rom, ANIM_SPEED + 2 * f.rating)) >> 8) & 0xFFFF
	f.anim.flags |= MwAnimState.PLAYING
	f.stamp = _now()


## `$DECC`, standing: B or C newly pressed punches (the puncher drawn in
## front: z 8001, the other 8000); else A newly pressed blocks.
func _stand(f: Fighter, o: Fighter, w: int) -> void:
	if w & 0x30:
		f.motion.pos[2] = (START_Z + 1) << 8
		o.motion.pos[2] = START_Z << 8
		_set_state(f, PUNCH)
	elif w & 0x40:
		_set_state(f, BLOCK)


## `$DEFC`, punching: A newly pressed blocks instead; the animation over:
## standing; on the hit frame (position `$2xx`) every pass: entering it
## counts a punch thrown (unless the other is down), then within 90 px a
## blocking other blocks it (`$DFC4`), a standing or punching one is hit
## (`$DF5E`).
func _punch(f: Fighter, o: Fighter, w: int) -> void:
	if w & 0x40:
		_set_state(f, BLOCK)
		return
	if not f.anim.playing():
		_set_state(f, STAND)
		return
	var at := f.anim.position & 0xFF00
	if at != 0x200:
		return
	if at > (f.last_position & 0xFFFF) and o.state < KNOCKED:
		f.thrown = (f.thrown + 1) & 0xFFFF
	var dx := absi(f.motion.pos[0] - o.motion.pos[0])
	if (MwRinkSim.asr(dx, 8) & 0xFFFF) > REACH:
		return
	if o.state == BLOCK:
		_blocked(f, o)
	elif o.state <= PUNCH:
		_hit(f, o)


## `$DF5E`: a landed punch - a sound (`rng_next`: species 2's victims `$1E`,
## else `$1D194`[r & 6]), `rng_next` for the damage (x4 below `$800`),
## landed + 1, the other stunned 20 passes; his health down: hit, or at 0
## knocked down (the puncher's CPU memory cleared).
func _hit(f: Fighter, o: Fighter) -> void:
	var r := rng_next()
	if o.table == SPECIES_2_ANIMS:
		sound(0x1E)
	else:
		sound(MwGfx.u16(rom, HIT_SOUNDS + (r & 6)))
	var w := rng_next() & 0xFFFF
	f.landed = (f.landed + 1) & 0xFFFF
	o.stun = 0x14
	var d := f.damage
	if w < 0x800:
		d = (d << 2) & 0xFFFF
	o.health = (o.health - d) & 0xFFFF
	if MwRinkSim.s16(o.health) > 0:
		_set_state(o, HIT)
	else:
		_knock_down(f, o)


## `$DFC4`: a blocked punch - the block's sound, the other stunned 10
## passes, a sixteenth of the damage (at 0: knocked down).
func _blocked(f: Fighter, o: Fighter) -> void:
	sound(BLOCK_SOUND)
	o.stun = 0xA
	o.health = (o.health - (f.damage >> 4)) & 0xFFFF
	if MwRinkSim.s16(o.health) <= 0:
		_knock_down(f, o)


## `$DFB0`: [param o]'s health 0, [param f]'s CPU memory cleared, [param o]
## knocked down.
func _knock_down(f: Fighter, o: Fighter) -> void:
	o.health = 0
	f.memory = 0
	_set_state(o, KNOCKED)


## `$DFE0`, blocking: A released, or 30 ticks: standing.
func _block(f: Fighter, w: int) -> void:
	if w & 0x4000 and ((_now() - f.stamp) & 0xFFFF) < 0x1E:
		return
	_set_state(f, STAND)


## `$E01A`, knocked down: falling until y 304; there the second animation
## ends (species other than 1: `$20BD2` at y - 224), the stamp, down
## (state `$14`, its animation kept).
func _knocked(f: Fighter) -> void:
	var y := MwRinkSim.s16(MwRinkSim.asr(f.motion.pos[1], 8))
	if y < 0x130:
		return
	f.fx.flags &= ~MwAnimState.PLAYING
	if f.species(rom) != 1:
		f.fx = MwAnimState.from_record(rom, DOWN_FX)
		f.fx.flags |= MwAnimState.PLAYING
		f.fx_y = (y - START_Y) & 0xFFFF
		f.known["fx"] = true
		f.known["fx_y"] = true
	f.stamp = _now()
	f.state = DOWN


## `$E0A0`, the walk: knocked down: drifting away 32/256 px per tick and
## falling (y acceleration 4); down or out: still. Else the held d-pad
## (`$1D19C`: left or right, alone or with up / down) - while stunned
## "away from the other" - walks at the rated speed, the left one between
## x 60 and 74 px from the other, the right one up to x 260; stunned, the
## speed x stun / 8 and the stun one pass less.
func _walk(f: Fighter, o: Fighter, w: int) -> void:
	var held := (w >> 8) & 0xFF
	var ox := o.x()
	var x := f.x()
	if f.state == KNOCKED:
		f.motion.vel[0] = -0x20 if x < ox else 0x20
		f.motion.acc[1] = 4
		return
	if f.state > KNOCKED:
		f.motion.vel[0] = 0
		f.motion.vel[1] = 0
		f.motion.acc[1] = 0
		return
	if f.stun != 0:
		held = (held & 0xF3) | 4
		if x >= ox:
			held ^= 0xC
	var v := 0
	match MwGfx.u32(rom, MOVES + 4 * (held & 0xF)):
		MOVE_LEFT:
			var limit := LEFT_WALL
			if x >= ox:
				limit = maxi(limit, MwRinkSim.s16(ox + GAP))
			if x > limit:
				v = -f.speed
		MOVE_RIGHT:
			var limit := RIGHT_WALL
			if x <= ox:
				limit = mini(limit, MwRinkSim.s16(ox - GAP))
			if x < limit:
				v = f.speed
	if f.stun != 0:
		v = MwRinkSim.asr(MwRinkSim.s16(v * f.stun), 3)
		f.stun = (f.stun - 1) & 0xFFFF
	f.motion.vel[0] = MwRinkSim.s16(v)


## `$E15C`, the CPU's pad word: nothing (and no draw) while the other is
## down; else one `rng_next` r and by its own state - standing: far (over
## 102 px) it keeps walking its remembered way, turning it (or picking one)
## when r < `$1000`; near, the other punching and r < `$1D20A`[rating]: a
## held A (which the stand state ignores - the CPU never blocks), else the
## other not hit or down and r < `$1D1F4`[rating]: a punch (C), else its
## way; punching: towards the other while over 90 px away; blocking: away
## from him within 102 px (held A while he punches); else nothing.
func _ai(f: Fighter, o: Fighter) -> int:
	if o.state >= KNOCKED:
		return 0
	var r := rng_next() & 0xFFFF
	var dx := MwRinkSim.asr(f.motion.pos[0], 8) - MwRinkSim.asr(o.motion.pos[0], 8)
	var d := absi(dx) & 0xFFFF
	var r2 := 2 * f.rating
	match f.state:
		STAND:
			if d > NEAR:
				if r >= 0x1000:
					return f.memory
				var m := f.memory
				if m != 0:
					m = 0 if r >= 0xC000 else m ^ 0xC00
				else:
					m = 0x400 if r >= 0x800 else 0x800
				f.memory = m
				return m
			if o.state == PUNCH and r < MwGfx.u16(rom, AI_BLOCK + r2):
				return 0x4000
			if o.state <= BLOCK and r < MwGfx.u16(rom, AI_PUNCH + r2):
				return 0x20
			return f.memory
		PUNCH:
			var m := 0
			if d > REACH:
				m = 0x800 if dx < 0 else 0x400
			f.memory = m
			return m
		BLOCK:
			var m := 0x400 if dx < 0 else 0x800
			if d > NEAR:
				m = 0
			f.memory = m
			return (0x4000 if o.state == PUNCH else 0) | m
	return 0


# --- draws -------------------------------------------------------------------------------------

## `$DC08`: the fight time left, ceil((1200 - t) / 60) as m:ss at (17, 14)
## on plane B (`$F37A`), where the game clock goes.
func _clock_draw() -> void:
	var left := MwRinkSim.s16(FIGHT_TICKS - fight_time + 0x3B)
	MwScoreboardBackdrop._mss(plane_ops, maxi(left, 0) / 60, 0x11, 0xE)


## `$E278`: the fighter's name on the window's row 2 (`$22BEC`): team A's
## from column 2, team B's ending at column 38.
func _name_draw(f: Fighter) -> void:
	var nm := MwGfx.u32(rom, f.record)
	var x := 2 if f == fighters[0] else 0x26
	if x >= 0x14:
		x -= MwRinkPhases.text_width(rom, NAME_FONT, nm)
	window_ops.append(["text", NAME_FONT, x, 2, ATTR, nm])


## `$E2AE`: the health bar on the window's row 4, (health + `$1FF`) >> 9
## quarters of 15 cells: full cells, a partial one, empty ones - team A's
## from column 2 rightwards, team B's from column 38 leftwards, flipped.
func _bar_draw(f: Fighter) -> void:
	var v := ((f.health + 0x1FF) & 0xFFFF) >> 9
	var x := 2 if f == fighters[0] else 0x26
	x = _bar_cells(x, v >> 2, BAR_FULL)
	if v & 3:
		x = _bar_cells(x, 1, BAR_EMPTY + (v & 3))
	_bar_cells(x, (0x3C - v) >> 2, BAR_EMPTY)


## `$E2EE`: [param n] cells of [param tile] from column [param x] (right of
## the middle: leftwards, h-flipped); returns the next column.
func _bar_cells(x: int, n: int, tile: int) -> int:
	if n <= 0:
		return x
	if x >= 0x14:
		x -= n
		tile |= 0x800
		window_ops.append(["fill", x, 4, n, 1, tile])
		return x
	window_ops.append(["fill", x, 4, n, 1, tile])
	return x + n


## `$E31C`: the result in `$22D66` on the window - "DRAW!" at (17, 9); a
## decision: the winner's name centred on row 8, "WINS!" at (17, 10);
## "KNOCKOUT!" at (15, 9).
func _result_text() -> void:
	match result:
		0:
			window_ops.append(["text", TEXT_FONT, 0x11, 9, ATTR, DRAW_TEXT])
		1:
			var nm := MwGfx.u32(rom, winner.record)
			var w := MwRinkPhases.text_width(rom, TEXT_FONT, nm)
			window_ops.append(["text", TEXT_FONT, ((0x28 - w) & 0xFFFF) >> 1, 8, ATTR, nm])
			window_ops.append(["text", TEXT_FONT, 0x11, 0xA, ATTR, WINS_TEXT])
		2:
			window_ops.append(["text", TEXT_FONT, 0xF, 9, ATTR, KO_TEXT])


## `$DDC6`: the fighter's animation at (x, y), depth z, its attr (plane
## B's camera, no projection); its second animation while shown at (x, y -
## +$44).
func _fighter_draw(f: Fighter) -> void:
	var p := f.motion.pixels()
	sprite_ops.append(MwScoreboardSim.anim_op(f.anim, p.x, p.y, p.z, f.attr))
	if f.fx.playing():
		sprite_ops.append(MwScoreboardSim.anim_op(f.fx, p.x, p.y - f.fx_y, p.z, f.attr))


# --- the card ----------------------------------------------------------------------------------

## `$E3A8` up to its loop (after the fight loop's 16-tick fade): the
## card's background over the window (`$E4A2`: 28 map rows from the fight
## bank), its labels (`$1D27C`), a joke row (`rng_range(0, 3)`), per fighter
## (team A's at column 20, B's at 31) the joke's count, his name, punches
## thrown and landed; the screen palette with colour `$39` fading to `$AAA`,
## colour 0 black; 480 ticks.
func _card_setup() -> void:
	card_window_from = window_ops.size()
	var vram := WINDOW_VRAM
	for i in 7:
		var a := CARD_MAPS + 10 * i
		for k in MwGfx.u16(rom, a + 4):
			window_ops.append(["map", MwGfx.u32(rom, a), 0x28, 0x28, MwGfx.u16(rom, a + 6), 0,
					(vram - WINDOW_VRAM) / 0x80])
			vram += MwGfx.u16(rom, a + 8)
	for i in 4:
		_card_label(CARD_LABELS + 8 * i)
	joke = rng_range(0, 3) & 0xFFFF
	_card_label(CARD_LABELS + 0x20 + 0x10 * joke)
	_card_label(CARD_LABELS + 0x28 + 0x10 * joke)
	_card_column(fighters[0], fighters[1], 0x14)
	_card_column(fighters[1], fighters[0], 0x1F)
	events.append(["palette", "screen"])
	events.append(["colour", 0x39, MwGfx.u16(rom, CARD_COLOUR), 0x20, CARD_COLOUR])
	events.append(["colour", 0, 0, 0, 0])
	card = true
	card_left = CARD_TICKS
	sprite_ops = _last_sprites.duplicate()


## `$E5FA`: a label (x, y, string.l at [param a]) in `$1F958` on the window.
func _card_label(a: int) -> void:
	window_ops.append(["text", CARD_FONT, MwGfx.u16(rom, a), MwGfx.u16(rom, a + 2), ATTR, MwGfx.u32(rom, a + 4)])


## `$E4EA`: [param f]'s column at [param x]: the joke's count (row 18,
## `$E510`), his name (`$E59C`), punches thrown (row 12) and landed (row 15).
func _card_column(f: Fighter, o: Fighter, x: int) -> void:
	var v := 0
	match joke:
		0:
			v = 1 if f.health < 0x3C00 else 0
		1:
			v = (1 if o.landed >= 4 else 0) + (1 if o.landed >= 8 else 0)
		2:
			v = 1 if winner != null and f != winner else 0
		3:
			v = rng_range(0, mini(f.landed, 0xA)) & 0xFFFF
	_card_number(v, x, 0x12)
	_card_name(f, x)
	_card_number(f.thrown, x, 0xC)
	_card_number(f.landed, x, 0xF)


## `$F39E` in `$1F958`: [param v] as two cells at ([param x], [param y])
## (below 10 a space first).
func _card_number(v: int, x: int, y: int) -> void:
	if v < 10:
		window_ops.append(["glyph", CARD_FONT, x, y, ATTR, 0x20])
		window_ops.append(["glyph_after", CARD_FONT, y, ATTR, 0x30 + v])
	else:
		window_ops.append(["glyph", CARD_FONT, x, y, ATTR, 0x30 + (v / 10) % 256])
		window_ops.append(["glyph_after", CARD_FONT, y, ATTR, 0x30 + v % 10])


## `$E59C`: the name centred by characters on column [param x] + 1, row 7;
## over 10 characters it splits at the last space within the first 11
## (the rest on row 8).
func _card_name(f: Fighter, x: int) -> void:
	var nm := MwGfx.rom_string(rom, MwGfx.u32(rom, f.record))
	var first := nm
	if nm.size() > 10:
		var k := 10
		while k >= 0 and (k >= nm.size() or nm[k] != 0x20):
			k -= 1
		if k >= 0:
			first = nm.slice(0, k)
			var rest := nm.slice(k + 1)
			window_ops.append(["text", CARD_FONT, ((2 * (x + 1) - rest.size()) & 0xFFFF) >> 1, 8, ATTR, rest])
	window_ops.append(["text", CARD_FONT, ((2 * (x + 1) - first.size()) & 0xFFFF) >> 1, 7, ATTR, first])


## `$E432`, a card pass: the ticks counted down (none left: the end); the
## stamp; the card's sound `$10` again whenever the last one stopped; with
## fewer than 360 ticks left the pads (A / B / C / Start newly pressed on
## any pad end it).
func _card_pass(e: int, held: Array, new: Array) -> int:
	sprite_ops = _last_sprites.duplicate()
	card_left = MwRinkSim.s16(card_left - e)
	if card_left < 0:
		return _leave()
	card_stamp = _now()
	_known["card_stamp"] = true
	if not playing(card_sound):
		card_sound = sound(CARD_SOUND)
		_known["sound"] = true
	if card_left >= CARD_LOCK:
		return -1
	MwScoreboardSim.read_pads(s, held, new)
	if pads_word(held, new) & 0xF0:
		return _leave()
	return -1


## The card's end and the teardown: the 32-tick fade, the sound reset
## (`$13C04`), the crowd off, the bank freed, the side view off (`$910E`),
## `$A682` (a box marked to stop play: phase 2).
func _leave() -> int:
	fade_out(FADE_OUT)
	events.append(["sound_reset"])
	sound_call(func() -> void: MwSound.enter_match(0xFFFF))   # `$E496`: d0 = `$14ABE`'s $FFFF
	crowd_off()                                  # `$D95C`
	events.append(["picture_free", BANK])
	s.projection = 0
	_after_fight()
	return 17


## `$A682`: the referee's decision on the boxes (`$A7C2`); one marked to
## stop play: phase 2 (from phase 4 the penalty sequence's step reset).
func _after_fight() -> void:
	rink.penalties._decide()
	var stop := MwRinkPenalties.STOP
	if MwRinkPenalties.flags(s.teams[0]) & stop or MwRinkPenalties.flags(s.teams[1]) & stop:
		if s.phase == 4:
			s.penalty_step = 0
		s.phase = 2


# --- comparisons ---------------------------------------------------------------------------------

func compare(ram: PackedByteArray, stack: PackedByteArray) -> Array:
	var d := MwScoreboardSim.Diff.new(MwScoreboardSim.Mem.new(ram, stack))
	var a6 := LOCALS
	d.long("snapshot -4", a6 - 4, snapshot)
	d.word("state -6", a6 - 6, state)
	if _known.has("stamp"):
		d.long("stamp -$A", a6 - 0xA, stamp)
	d.word("fight time -$C", a6 - 0xC, fight_time)
	d.word("panel dir", a6 - 0x12, panel.dir)
	d.word("panel remainder", a6 - 0x10, panel.remainder)
	d.word("panel size", a6 - 0xE, panel.size)
	if _known.has("result"):
		d.word("result -$F0", a6 - 0xF0, result)
		d.long("winner -$F4", a6 - 0xF4, winner.long() if winner != null else 0)
		d.long("winner team -$F8", a6 - 0xF8, winner_team)
	if _known.has("crowd"):
		d.word("crowd -$FA", a6 - 0xFA, crowd)
	if _known.has("sound"):
		d.flag("sound $C476", CARD_SOUND_AT, card_sound != 0)
	if _known.has("card_stamp"):
		d.long("card stamp", CARD_STAMP_AT, card_stamp)
	fighters[0].compare(d, "A")
	fighters[1].compare(d, "B")
	var ours := MwRinkRam.encode(s, ram)
	# the teams (the calls, fights won), the result, what the set-up leaves
	d.ram_range(ours, MwRinkRam.TEAMS[0], MwRinkRam.TEAMS[1] + 0x4AA)
	d.ram_range(ours, MwRinkRam.GOAL_KIND, MwRinkRam.GOAL_KIND + 2)
	d.ram_range(ours, MwRinkRam.SCORER, MwRinkRam.SCORER + 4)
	d.ram_range(ours, MwRinkRam.PHASE, MwRinkRam.PHASE + 2)
	MwScoreboardSim.compare_setup(d, ours)
	return d.out
