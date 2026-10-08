class_name MwRinkPhases
extends RefCounted
## The rink's match flow, node-free (docs/re/phases.md): the puck rules `$C84A` (icing, a goalie
## holding the puck) and the phase handler `$FC58` (table `$FC84`) that the
## rink pass runs after the rest of the update and before the draws:
##
## * 0 open play (`$FCC0`): the pause menu `$48FC`, the phase stamp, 0:00;
## * 1 faceoff (`$FD38`): the faceoff sequence `$AC1C` (period / score
##   panel, the portrait, the drop, the puck landing);
## * 2 penalty (`$FD4E`): entered with penalties on only (plan 10);
## * 3 goal (`$FDD2`): the goal sequence `$928C` (blink, lamp, panel), the
##   scoring coach's speech, sudden death in overtime;
## * 4 fight called (`$FE66`), 5 period end / game over (`$FE8C`), 8 icing
##   or a goalie hold (`$FFD6`, `$CA12`), 9 period start (`$FFEA`: panel,
##   coach speeches, the FACE OFF! drop), 10 game-over speeches (`$1008E`),
##   11 Waste the Goalie (`$100BE`), 12 Waste the Ref (`$10182`), 13
##   forfeit (`$101CE`), 14 FACE OFF banner (`$1020E`); 6 and 7 are `rts`.
##
## A pass ends with [method pass_end] (the puck rules, then the handler)
## and returns the screen the rink leaves for (the original's `bra $FB38`
## with d0; [method exit] does `$FB38`'s team clean-up; in the attract demo
## every exit is screen 1), [constant PAUSED] while the pause menu is open
## (live play: [method pause_press] answers it; the original's menu is a
## busy loop, the game stands still), or -1. The rink entries are
## [method enter] (`$F884` / `$F8A4` / `$F8F0` with the period-end check
## at 0:00, `$FEBA`).
##
## What the original reads from outside the CPU comes through [member
## hooks] when set (comparisons): `tick_at(update, tag)` (through the
## update: every "now" the handler reads, tags [constant TICK_ADDRESSES]),
## `voice_poll(phases, handle)` (the sound driver's "still playing?" for
## the coach's voice, `$13D9C`), `voice_handle(phases, id)` (the handle the
## driver gives a new voice) and `pause_result(phases)` (the button that
## closed the pause menu). Without hooks the tick is the pass's, voices
## last [constant VOICE_TICKS] (with the sound driver running: until it
## says they ended) and the pause waits for [method pause_press].
##
## Random numbers are drawn as the original: the quote pick (`$F420`), the
## coach's expression roll (`$102A6`), the mouth frames (`$B572`) and the
## song after the FACE OFF! drop (`$13CE2`). Sounds and speech are events
## in [member MwRinkSim.events] (["sound", id], ["speech", side, quote],
## ["sounds_off"], ["voice_stop", handle], ...); in live play
## ([member MwRinkSim.live]) the sound calls also reach the driver
## ([MwSound]) where the original makes them. What to draw is in
## [member window_ops] (window plane cells, in the original's order) and
## [member sprite_ops] (the handler's sprites) for the presentation, and
## [member overlays] for the draw pass ([method MwRinkUpdate.draws]).
## Integer arithmetic is the 68000's (16-bit words; "now - stamp" compares
## are word compares, signed or unsigned as the code has them).

## [method pass_end] / [method handler]: the pause menu is open.
const PAUSED := -2
## [method MwRinkUpdate.draws]' rules phase when the overlays come from
## here (the draw pass then leaves the puck rules' icon to [member overlays]).
const RULES_DRAWN := 0x7FFF

# --- where the handler reads the tick (recorder v3 sites; our tags) ----------------------------
const TICK_TIMER_START := 111        ## `$16F4` `$2542` clock start (faceoff state 8, every pass)
const TICK_UNPAUSE := 114            ## `$257E` `$2562` (pause resumed): clock stamp
const TICK_PENALTY_STAMP := 120      ## `$A728` penalty state 0
const TICK_PENALTY_WAIT := 121       ## `$A75C` penalty state 1: 240 ticks
const TICK_FACEOFF_0 := 122          ## `$AC74` faceoff state 0: stamp
const TICK_FACEOFF_PANEL := 123      ## `$ACC2` state 1: 90 ticks
const TICK_FACEOFF_2 := 124          ## `$AE14` state 2: stamp
const TICK_FACEOFF_3 := 125          ## `$AE3A` state 3: 60 ticks
const TICK_FACEOFF_5 := 126          ## `$AE90` state 5: stamp
const TICK_FACEOFF_6 := 127          ## `$AE9C` state 6: 30 ticks
const TICK_GOAL_0 := 128             ## `$9312` goal state 0: stamp
const TICK_GOAL_BLINK := 129         ## `$935E` state 1: 6 ticks
const TICK_GOAL_RESTAMP := 130       ## `$936A` state 1: stamp = now
const TICK_GOAL_3 := 131             ## `$9466` state 3: stamp
const TICK_GOAL_PANEL := 132         ## `$9494` state 4: 150 ticks
const TICK_STOP_0 := 133             ## `$CA4A` phase 8 state 0: stamp
const TICK_STOP_WAIT := 134          ## `$CAC4` phase 8 state 1: 180 ticks
const TICK_RESUME := 135             ## `$FD0E` phase 0, resumed: `$C5FE` = now
const TICK_PLAY := 136               ## `$FD1A` phase 0: `$C602` = now
const TICK_FIGHT := 137              ## `$FE74` phase 4: 180 ticks
const TICK_PERIOD_END := 138         ## `$FEA8` phase 5: 180 ticks
const TICK_WINNER := 139             ## `$FF1C` game over: stamp
const TICK_WINNER_PANEL := 140       ## `$FF3E` winner panel: 180 ticks
const TICK_GAME_OVER := 141          ## `$FF78` phase 10: stamp
const TICK_START_SPEECH := 142       ## `$1003C` phase 9: stamp after the speech set-up
const TICK_WASTE_GOALIE := 143       ## `$10122` phase 11: 480 ticks
const TICK_WASTE_GOALIE_END := 144   ## `$1017A` phase 11 end: stamp
const TICK_WASTE_REF := 145          ## `$101B6` phase 12: 180 ticks
const TICK_FORFEIT := 146            ## `$101F6` phase 13: 300 ticks
const TICK_BANNER := 147             ## `$1028A` phase 14: more than 180 ticks
const TICK_SPEECH := 148             ## `$10396` every speech pass: 600 ticks
const TICK_SETUP_START := 149        ## `$10546` period-start speech set-up
const TICK_SETUP_OVER := 150         ## `$1060A` game-over speech set-up
const TICK_SETUP_GOAL := 151         ## `$10726` goal speech set-up
const TICK_SETUP_PENALTY := 152      ## `$107C4` penalty speech set-up
const TICK_ADDRESSES := {0x16F4: TICK_TIMER_START, 0x257E: TICK_UNPAUSE, 0xA728: TICK_PENALTY_STAMP,
		0xA75C: TICK_PENALTY_WAIT, 0xAC74: TICK_FACEOFF_0, 0xACC2: TICK_FACEOFF_PANEL, 0xAE14: TICK_FACEOFF_2,
		0xAE3A: TICK_FACEOFF_3, 0xAE90: TICK_FACEOFF_5, 0xAE9C: TICK_FACEOFF_6, 0x9312: TICK_GOAL_0,
		0x935E: TICK_GOAL_BLINK, 0x936A: TICK_GOAL_RESTAMP, 0x9466: TICK_GOAL_3, 0x9494: TICK_GOAL_PANEL,
		0xCA4A: TICK_STOP_0, 0xCAC4: TICK_STOP_WAIT, 0xFD0E: TICK_RESUME, 0xFD1A: TICK_PLAY, 0xFE74: TICK_FIGHT,
		0xFEA8: TICK_PERIOD_END, 0xFF1C: TICK_WINNER, 0xFF3E: TICK_WINNER_PANEL, 0xFF78: TICK_GAME_OVER,
		0x1003C: TICK_START_SPEECH, 0x10122: TICK_WASTE_GOALIE, 0x1017A: TICK_WASTE_GOALIE_END,
		0x101B6: TICK_WASTE_REF, 0x101F6: TICK_FORFEIT, 0x1028A: TICK_BANNER, 0x10396: TICK_SPEECH,
		0x10546: TICK_SETUP_START, 0x1060A: TICK_SETUP_OVER, 0x10726: TICK_SETUP_GOAL, 0x107C4: TICK_SETUP_PENALTY}

## How long a coach's voice plays (ticks, by sound id), measured in the
## recorder v3 runs (out/plan09/ph_voice3.py: every voice's last poll that
## still saw it and the first that saw it done; $F: 33 voices, playing at
## 202, done at 203; $B: 8 voices, 206 / 208). Voices $C and $32 were never
## recorded: [constant VOICE_DEFAULT]. The sound driver (plan 12) decides
## these in the original (`$13D9C` -> `$189BE`).
const VOICE_TICKS := {0x0B: 207, 0x0F: 203}
const VOICE_DEFAULT := 203

# --- ROM -------------------------------------------------------------------------------------
const PAUSE_PADS := 0x1C24C          ## by pad mode: pads that may pause (1, 2, 2, 3, 4, 0)
const PAUSE_SPLIT := 0x1C258         ## by pad mode: pads below it pause for team A
const QUOTES := 0x1D404              ## [category][situation][set] -> value.w, count.w, strings
const NO_QUOTE := 0x50D2D            ## the "nothing to say" line (a set without quotes)
const COACHES := 0x1CD26             ## 20 x (coach record.l, portrait data.l, quote set.w)
const COACH_DEFAULT := 0x1CCA2       ## the portrait data of a coach not in the list
const SPEECH_BOX_AT := 0x1EA02       ## (3, 3, 34, 6)
const SPEECH_FONT := 0x1F958
const NAME_FONT := 0x22EE0
const TITLE_FONT := 0x22BEC
const BIG_FONT := 0x246FA
const CLOCK_FONT := 0x447F4
const BUBBLE_TAIL := 0x1FB02
const PORTRAIT_BORDERS := 0x1CDF6
const SPOTS := 0x1CA9A               ## faceoff spots (x, y)
const SPOT_PAIRS := 0x1CA9E          ## the two circles of each quadrant
const DEMON_NET_GOAL := 0x21114
const REF_ANIM := 0x213DC
const WINDOW := 0xFFFFB0CA           ## the window's plane object
# texts (strings in the ROM)
const T_FACE := 0x50706
const T_OFF := 0x5070B
const T_PERIOD := 0x50710
const T_START_OF_PERIOD := 0x50718
const T_HE_SCORES := 0x50729
const T_HAT_TRICK := 0x50734
const T_GOAL_SCORED_BY := 0x5074A
const T_BAR := 0x5075A
const T_OVERTIME := 0x50781
const T_EMPTY := 0x50789
const T_PAUSE := 0x5059B
const T_REPLAY := 0x505A1
const T_TIMEOUT := 0x505AC
const T_ICING := 0x50B5B
const T_STOP_FACE_OFF := 0x50B61
const T_PENALTY := 0x506F3
const T_BANNER := 0x6251D
const T_BANNER_2 := 0x62525
const T_NONE := 0x6252D
const T_FIGHT := 0x6252E
const T_FORFEIT := 0x62535

const TEAM_WORDS := [0xB402, 0xB8AC] ## the teams' RAM address words (`$C640` etc. hold them sign-extended)

var sim: MwRinkSim
var up: MwRinkUpdate
var s: MwRinkState
var rom: PackedByteArray
## Optional comparison hooks (see the class description).
var hooks: Object = null
## The pause menu is open (live play: [method pause_press]).
var paused := false
## This pass's window plane operations, in the original's order (cells;
## texts stay on the window until filled over or the rink is left):
## ["text", font, x, y, attr, string] (`$14CAE`; string: a ROM address or
## bytes; y the baseline row), ["text_after", font, y, attr, string] (the
## next text right after the last one), ["glyph", font, x, y, attr, char]
## (`$14C26`), ["fill", x, y, w, h, cell] (`$146EA`, `$14B30`), ["box", x,
## y, w, h, filled] (the speech box's frame, `$BA98`; filled: colour 9
## inside), ["quote", font, x, y, attr, bytes, w, h] (the text box's
## word-wrapped print, `$15860`, from the box's corner), ["widget",
## power-play form, period, seconds] (the clock widget, `$25AA`).
## The rink scene paints them (`src/rink/window_painter.gd`).
var window_ops: Array = []
## This pass's sprites drawn by the handler (screen pixels), for the draw
## pass ([method MwRinkDraw.build]): ["sprite_text", font, x, y, attr,
## depth, string] (`draw_text_sprites` `$F3CC`), ["portrait", x, y, depth,
## attr, animation, variant, frame, size] (the coach portrait `$B70C` as it
## was when drawn: a second speech's set-up may follow in the same pass),
## ["piece", piece, x, y, attr, depth] (`add_sprite_piece` `$156C6`).
var sprite_ops: Array = []
## The overlays drawn this pass ([overlay, with camera]): the stoppage icon.
var overlays: Array = []
## Live voices: handle -> the tick the voice ends.
var _voice_end := {}
var _serial := 0


func _init(update: MwRinkUpdate) -> void:
	up = update
	sim = update.sim
	s = sim.s
	rom = sim.rom


# --- the pass ----------------------------------------------------------------------------------

## The end of a pass of [param e] ticks after the update (`$A5EC`): the
## puck rules, then the phase handler. Returns the screen to leave for,
## [constant PAUSED] or -1.
func pass_end(e: int) -> int:
	window_ops.clear()
	sprite_ops.clear()
	overlays.clear()
	puck_rules(e)
	return handler(e)


## `$FC58`: in the attract demo any pad held or pressed ends the demo
## (`$FB38` with d0 still the elapsed ticks: every exit there is screen
## 1); then the phase's handler (`$FC84`, d0 = [param e]).
func handler(e: int) -> int:
	if s.fight_block != 0:
		var any := 0
		for p in 4:
			any |= s.pads_held[p] | s.pads_new[p]
		if any != 0:
			return exit(e & 0xFFFF)
	match s.phase:
		0:
			return _phase_play()
		1:
			return _phase_faceoff(e)
		2:
			return _phase_penalty(e)
		3:
			return _phase_goal(e)
		4:
			return _phase_fight()
		5:
			return _phase_period_end()
		8:
			return _phase_stoppage(e)
		9:
			return _phase_start(e)
		10:
			return _phase_game_over(e)
		11:
			return _phase_waste_goalie()
		12:
			return _phase_waste_ref(e)
		13:
			return _phase_forfeit()
		14:
			return _phase_banner()
	return -1                                    # 6, 7: rts


## `$FB38` (and `rink_exit`'s team clean-up, [method MwRinkMatch.rink_exit]):
## the rink is left for screen [param screen]; in the attract demo (`$FFCA1C`)
## `$45E4` restores the setup and every exit is the main menu (1).
func exit(screen: int) -> int:
	paused = false
	MwRinkMatch.rink_exit(sim, screen)
	_sounds_off(screen)                         # `$FBB4`
	if s.fight_block != 0:
		return 1
	return screen


## `$FB2E`: game over: screen 15, or 16 after a playoff game.
func _game_over_exit() -> int:
	return exit(16 if s.play_mode != 0 else 15)


## A rink entry ([method MwRinkMatch.enter]: 4 a period starts, 5 a
## faceoff, 6 play goes on after the pause menu's replay) and, with the
## clock at 0:00 (a goal or penalty then), the period-end step `$FEBA`
## at once. Returns the screen the rink leaves for at once, or -1.
func enter(screen: int) -> int:
	paused = false
	window_ops.clear()
	sprite_ops.clear()
	overlays.clear()
	var to := MwRinkMatch.enter(sim, screen)
	window_ops.append(["fill", 0, 0, 64, 32, 0x8000])     # `$F7F0` rink_load: the window cleared
	if to < 0 and s.clock_widget & 2:
		window_ops.append(["widget", s.clock_widget & 1 != 0, s.period & 0xFF, s.clock & 0xFFFF, s.pp_seconds & 0xFFFF])   # `$25AA`
	if to >= 0:
		_sounds_off(to)                         # `$FBB4` (`rink_exit` at the line-up)
		return 1 if s.fight_block != 0 else to
	if s.clock == 0:
		to = _period_decision()
		if to >= 0:
			return to
	return -1


func _now(tag: int) -> int:
	up._tick(tag)
	return s.tick & 0xFFFFFFFF


## "now - stamp" as the word the original compares.
func _since(tag: int, stamp: int) -> int:
	return (_now(tag) - stamp) & 0xFFFF


## `sound_play` `$13CEE`: the event ["sound", id]; live play: the
## driver's handle ([method MwSound.play]), else 0.
func _sound(id: int) -> int:
	sim.events.append(["sound", id & 0xFFFF])
	if sim.live:
		return MwSound.play(id & 0xFFFF)
	return 0


## `$13C04` (music fade with the caller's [param d0], crowd off, the
## driver reset): the event ["sounds_off"]. `rink_exit` passes its screen
## (`$3BA6` / `$107D0` may have replaced it by then; no music plays in the
## rink, so the fade never reads it).
func _sounds_off(d0: int) -> void:
	sim.events.append(["sounds_off"])
	if sim.live:
		MwSound.enter_match(d0 & 0xFFFF)


static func _team_long(t: int) -> int:
	return 0xFFFF0000 | int(TEAM_WORDS[t])


func _team_index(team: MwRinkState.Team) -> int:
	return 0 if team == s.teams[0] else 1


# --- the clock (`$2524`..`$26F6`) ---------------------------------------------------------------

## `$2542` (`$16E6`): the clock runs unless it has expired; stamped now.
func _clock_start() -> void:
	if s.clock_flags & 2:
		return
	s.clock_flags |= 1
	s.clock_ref = _now(TICK_TIMER_START)


## `$2552`: the clock stops.
func _clock_stop() -> void:
	s.clock_flags &= ~1


## `$2562`: the pause over: unpaused, the clock's stamp now if it runs.
func _unpause() -> void:
	if not s.clock_widget & 4:
		return
	s.clock_widget &= ~4
	if s.clock_flags & 1:
		s.clock_ref = _now(TICK_UNPAUSE)


## `$26F6`: the clock widget erased (its window cells), if shown.
func _widget_erase() -> void:
	if not s.clock_widget & 2:
		return
	s.clock_widget &= ~2
	if s.clock_widget & 1:
		window_ops.append(["fill", 2, 19, 9, 8, 0x8000])
	else:
		window_ops.append(["fill", 2, 22, 9, 5, 0x8000])


## `$25AA` ([method MwRinkMatch.draw_clock_widget]): the clock widget
## drawn, in its power-play form if a power play is on.
func _draw_widget() -> void:
	var pp := s.clock_widget & 1 != 0
	MwRinkMatch.draw_clock_widget(sim)
	window_ops.append(["widget", pp, s.period & 0xFF, s.clock & 0xFFFF, s.pp_seconds & 0xFFFF])


## `$2524`: the next period, the clock full (`$16C0`: stopped, expired at 0).
func _next_period_clock() -> void:
	s.period = (s.period + 1) & 0xFF
	s.clock = (s.period_minutes * 60) & 0xFFFF
	if s.clock == 0:
		s.clock_flags |= 2
	else:
		s.clock_flags &= ~2
	s.clock_flags &= ~1


## `$A888` (faceoff state 2): the power-play state from the penalty boxes
## ([method MwRinkPenalties.power_play]).
func _power_play_state() -> void:
	var was := s.clock_widget & 1
	sim.penalties.power_play()
	if s.clock_widget & 1 and not was:
		sim.events.append(["power_play"])


# --- open play (phase 0) and the pause menu ------------------------------------------------------

## `$FCC0`: the pause menu, then (not left) the replay recording on, the
## phase stamp, and at 0:00 the period's end (sound $1D, phase 5).
func _phase_play() -> int:
	var r := _pause_menu()
	if r == PAUSED:
		return PAUSED
	return _play_on(r)


## `$FCC0` after the pause menu returned [param r] (0 not paused, 1
## Start: resume, 2 A: the instant replay, 3 B: a timeout).
func _play_on(r: int) -> int:
	match r:
		3:
			return exit(10)
		2:
			return exit(7)
		1:
			_unpause()
			if s.clock_widget & 2:
				_draw_widget()
			s.pass_tick = _now(TICK_RESUME)          # the paused time is not elapsed
	s.replay_on = 0xFF00 | (s.replay_on & 0xFF)   # `st.b $C608`
	s.phase_tick = _now(TICK_PLAY)
	if s.clock == 0:
		_sound(0x1D)
		s.phase = 5
		s.subphase = 0
	return -1


## `$48FC`: the first pad (highest first) of the pad mode's (`$1C24C`) with
## Start newly pressed opens the pause menu for its team (`$1C258`): sounds
## off, the window cleared, the clock paused, "PAUSE" / "A - REPLAY" and,
## when the team carries the puck and has its timeout left, "B -
## TIMEOUT". Only that pad answers (Start resumes, A the instant replay, B
## the timeout). Returns 0 (no pause), the answer (hooks) or [constant
## PAUSED] (live: [method pause_press]).
func _pause_menu() -> int:
	var mode := s.pad_mode & 0xFF
	var n := MwGfx.u16(rom, PAUSE_PADS + 2 * mode)
	var pad := -1
	for i in range(n - 1, -1, -1):
		if s.pads_new[i] & 0x80:
			pad = i
			break
	if pad < 0:
		return 0
	s.pause_pad = 2 * pad
	var t := 0 if pad < MwGfx.u16(rom, PAUSE_SPLIT + 2 * mode) else 1
	var team := s.teams[t]
	s.pause_team = TEAM_WORDS[t]
	s.pause_attr = (team.attr & 0xFF) | 0x80
	_sounds_off(s.pause_attr)                   # `$4958`: d0 = the menu's attr
	window_ops.append(["fill", 0, 0, 40, 28, 0x8000])
	s.clock_widget |= 4
	window_ops.append(["text", BIG_FONT, 12, 3, s.pause_attr, T_PAUSE])
	window_ops.append(["text", BIG_FONT, 7, 8, s.pause_attr, T_REPLAY])
	s.pause_offer = 0
	var pk := s.puck
	if pk.flags & MwRinkState.Puck.CARRIED:
		var d := -1 if pk.flags & MwRinkState.Puck.BY_TEAM_B else 0
		if team.flags4 & 1:
			d += 1
		if d == 0 and team.flags4 & 0x10:
			s.pause_offer = 1
			window_ops.append(["text", BIG_FONT, 7, 12, s.pause_attr, T_TIMEOUT])
	if hooks != null and hooks.has_method("pause_result"):
		return _pause_answer(int(hooks.call("pause_result", self)))
	paused = true
	return PAUSED


## Live play: the pausing pad's newly pressed buttons [param pressed] (pad
## byte: Start $80, A $40, B $10) while the menu is open. Returns
## [constant PAUSED] (still open), the screen to leave for, or -1 (play
## resumes: the pass goes on to its draws).
func pause_press(pressed: int) -> int:
	if not paused:
		return -1
	window_ops.clear()
	sprite_ops.clear()
	overlays.clear()
	var r := 0
	if pressed & 0x80:
		r = 1
	elif pressed & 0x40:
		r = 2
	elif pressed & 0x10 and s.pause_offer != 0:
		r = 3
	else:
		return PAUSED
	return _play_on(_pause_answer(r))


## The pause menu's answer [param r]: A plays a sound; B (offered) stops
## the clock, takes the faceoff to the circle nearest the puck (`$AF12`)
## and uses the team's timeout (`$3AD2`); the window cleared.
func _pause_answer(r: int) -> int:
	paused = false
	if r == 2:
		_sound(0x26)
	elif r == 3:
		_clock_stop()
		var p := s.puck.motion.pixels()
		s.faceoff_spot = nearest_spot(rom, MwRinkSim.s16(p.x), MwRinkSim.s16(p.y))
		_timeout(s.teams[0] if s.pause_team == TEAM_WORDS[0] else s.teams[1])
		_sound(0x26)
	window_ops.append(["fill", 0, 0, 40, 28, 0x8000])
	return r


## `$3AD2`: [param team]'s timeout used (+4 bit 4 cleared), everyone's
## health full (`$3B08`: $80 in the high word, the low word d0's high word
## left by `$AF12`'s distances: 0), the impaled freed (`$3ADE`).
func _timeout(team: MwRinkState.Team) -> void:
	team.flags4 &= ~0x10
	for i in 24:
		if team.health[i] != 0:
			team.health[i] = 0x800000
	for p in team.players:
		if p.state == 0x11:
			sim.collide._free(p)


## `$AF1C`: the faceoff circle of the quadrant of ([param x], [param y])
## (`$1CA9E`: two per quadrant) - the second when it is not farther.
static func nearest_spot(rom_: PackedByteArray, x: int, y: int) -> int:
	var a := SPOT_PAIRS
	var spot := 1
	if y >= 0:
		a += 0x10
		spot += 4
	if x >= 0:
		a += 8
		spot += 2
	var d1 := MwTrig.distance(MwRinkSim.s16(x - MwGfx.s16(rom_, a)), MwRinkSim.s16(y - MwGfx.s16(rom_, a + 2))) & 0xFFFF
	var d2 := MwTrig.distance(MwRinkSim.s16(x - MwGfx.s16(rom_, a + 4)), MwRinkSim.s16(y - MwGfx.s16(rom_, a + 6))) & 0xFFFF
	if MwRinkSim.s16(d2) <= MwRinkSim.s16(d1):
		spot += 1
	return spot


# --- the faceoff (phases 1 and 9) ---------------------------------------------------------------

## `$FD38`: the faceoff sequence; when the puck has landed the replay ring
## is emptied (`$9CE8`) and play begins.
func _phase_faceoff(e: int) -> int:
	if faceoff_step(e) >= 0:
		return -1
	s.replay.reset()
	s.phase = 0
	return -1


## `$AC1C`: one step of the faceoff sequence (`$FFC31C`; at most one state
## per call, states 0-1 together); returns the state (sign-extended byte,
## -1 when done).
func faceoff_step(e: int) -> int:
	match MwRinkSim.s8(s.faceoff_step):
		0:
			s.faceoff_text = ((0x30 + s.period) & 0xFF) << 8      # '0' + period, 0
			s.faceoff_tick = _now(TICK_FACEOFF_0)
			s.faceoff_step = 1
			_faceoff_panel()
		1:
			_faceoff_panel()
		2:
			# `$AE10`: the portrait shown, the power-play state, the clock widget up
			s.faceoff_tick = _now(TICK_FACEOFF_2)
			s.faceoff.flags |= 0x80
			_power_play_state()
			_draw_widget()
			s.faceoff_step = 3
		3:
			if MwRinkSim.s16(_since(TICK_FACEOFF_3, s.faceoff_tick)) >= 0x3C:
				s.faceoff_step = 4
				s.faceoff.anim.flags |= MwAnimState.PLAYING
		4:
			# the referee's arm is down: the drop (`$AE68`)
			if MwRinkSim.s16(s.faceoff.anim.position) >= 0x380:
				MwRinkMatch.drop(sim)
				s.faceoff_step = 5
		5:
			if MwRinkSim.s16(s.faceoff.anim.position) >= 0x480:
				s.faceoff_step = 6
				s.faceoff.anim.flags &= ~MwAnimState.PLAYING
				s.faceoff_tick = _now(TICK_FACEOFF_5)
		6:
			if MwRinkSim.s16(_since(TICK_FACEOFF_6, s.faceoff_tick)) >= 0x1E:
				s.faceoff_step = 7
				s.faceoff.anim.flags |= MwAnimState.PLAYING
		7:
			# the animation stops itself (ping-pong back to its start)
			if not s.faceoff.anim.playing():
				s.faceoff.flags &= ~0x80
				s.faceoff_step = 8
		8:
			# `$AED4`: the clock runs (stamped every pass) until the puck lands
			_clock_start()
			if s.puck.motion.pos[2] == 0:
				_rules_reset(MwGfx.s16(rom, SPOTS + 4 * s.faceoff_spot + 2))
				s.crowd = MwRinkSim.s16(s.crowd + 0xFA)
				s.faceoff_step = 0xFF
	return MwRinkSim.s8(s.faceoff_step)


## `$AC7C` (state 1): the period / score panel every pass ("PERIOD n" or,
## with the clock full, "START OF PERIOD n"; "OVERTIME" from period 4);
## after 90 ticks the panel goes and the FACE OFF! drop is set up (180 px
## up, falling), from plane B as shown.
func _faceoff_panel() -> void:
	if (s.period & 0xFF) >= 4:
		_panel(1, T_EMPTY, T_OVERTIME)
	else:
		var digits := PackedByteArray([(s.faceoff_text >> 8) & 0xFF, s.faceoff_text & 0xFF])
		var full := (MwRinkSim.s8(s.period_minutes) * 0x3C) & 0xFFFF
		_panel(1, T_START_OF_PERIOD if full == (s.clock & 0xFFFF) else T_PERIOD, digits)
	if MwRinkSim.s16(_since(TICK_FACEOFF_PANEL, s.faceoff_tick)) < 0x5A:
		return
	s.faceoff_step = 2
	s.faceoff_text = 0
	_panel_erase()
	s.drop.init(0, 0, 0xB4)
	s.drop.vel[2] = -1
	s.drop_plane = s.camera.shown


## `$ABDC` (phase 9): the faceoff sequence's states 0-1 (the panel); true
## once state 2 is reached.
func _faceoff_panel_done(e: int) -> bool:
	if s.faceoff_step == 2:
		return true
	return faceoff_step(e) == 2


## `$C810(y)` (the puck landed): the puck rules start over from the spot.
func _rules_reset(y: int) -> void:
	s.crease_y = MwRinkSim.s16(y)
	s.rule_team_b = 0
	s.puck_rule = 0
	s.rule_hold = 0
	s.rule_clock = s.clock & 0xFFFF


## `$AD08` (phase 9 sub 2): the FACE OFF! letters fall with the puck's
## motion parameters and bounce; at the first bounce a thud (once, x.l as
## the flag); while bouncing up plane B shakes sideways (twice the upward
## speed in px, at most 48, the sign alternating by the pass counter y.l),
## falling it shows the saved x. Settled (upward speed below 1 px): drawn
## at rest and done.
##
## Quirk (kept): the settled branch means to hold for 40 more passes by
## counting `$FFC2FE` up, but adds the word at 2(a7) - the low word of the
## pushed pointer `$FFFFC304` - so the first settled pass is always the
## last (the counter ends at `$C304`).
func _drop_step(e: int) -> bool:
	var o := s.drop
	var old_vz := o.vel[2]
	o.step(s.puck_params, e)
	var settled := false
	if old_vz < 0:
		if o.vel[2] < 0:
			return _drop_draw()
		if o.vel[2] < 0x100:
			settled = true
		elif o.pos[0] == 0:
			o.pos[0] = 1
			_sound(0x15)
	if not settled:
		var vz := o.vel[2]
		if vz < 0:
			_plane_b(s.drop_plane.x, s.camera.shown.y)
			return _drop_draw()
		var d := MwRinkSim.asr(vz, 8)
		if d == 0:
			settled = true
		else:
			d = mini(absi(d), 0x18) * 2
			if o.pos[1] & 1 == 0:
				d = -d
			_plane_b(MwRinkSim.s16(s.drop_plane.x + d), s.camera.shown.y)
			return _drop_draw()
	o.pos[2] = 0x200
	_drop_text(4)
	s.faceoff_text = (s.faceoff_text + 0xC304) & 0xFFFF       # the bug
	if s.faceoff_text >= 0x28:
		return true
	return _drop_draw()


## `$ADC2`: the pass counter (y.l) + 1, the letters at the height.
func _drop_draw() -> bool:
	var o := s.drop
	o.pos[1] = (o.pos[1] + 1) & 0xFFFFFFFF
	if o.pos[1] >= 0x80000000:
		o.pos[1] -= 0x100000000
	_drop_text(MwRinkSim.s16(MwRinkSim.asr(o.pos[2], 8)))
	return false


## `$ADDC`: "FACE" at (64 - dz, 100) and "OFF!" at (160 + dz, 100), screen
## pixels, big font, depth $FFFF, attr $A0.
func _drop_text(dz: int) -> void:
	sprite_ops.append(["sprite_text", BIG_FONT, MwRinkSim.s16(0x40 - dz), 0x64, 0xA0, 0xFFFF, T_FACE])
	sprite_ops.append(["sprite_text", BIG_FONT, MwRinkSim.s16(0xA0 + dz), 0x64, 0xA0, 0xFFFF, T_OFF])


## `$14CEE` on plane B: shown at ([param x], [param y]) (the map is as wide
## as the plane: the cells stay), the scroll buffers.
func _plane_b(x: int, y: int) -> void:
	s.camera.shown = Vector2i(MwRinkSim.s16(x), MwRinkSim.s16(y))
	s.scroll_b = Vector2i((-x) & 0x1FF, y & 0xFF)


## `$FFEA`: the period start: the panel (faceoff states 0-1); then the
## replay off and the coach speech(es) (team A's, team B's if it has a pad;
## none in the attract demo or from the second overtime on); then the FACE
## OFF! drop, a song (`$13CE2`: 5 + rng & 3) and the faceoff goes on at
## state 2 (phase 1).
func _phase_start(e: int) -> int:
	match s.subphase:
		0:
			if not _faceoff_panel_done(e):
				return -1
			s.replay_on = 0
			if (s.period & 0xFF) > 4 or s.fight_block != 0:
				s.subphase = 2
				return -1
			s.speaker = 0
			_setup_period_start(s.teams[0], s.teams[1])
			s.phase_tick = _now(TICK_START_SPEECH)
			s.subphase = 1
		1:
			if speech(e):
				return -1
			if s.speaker == 0 and s.teams[1].flags4 & 4:
				s.speaker = 1
				_setup_period_start(s.teams[1], s.teams[0])
				return -1
			s.subphase = 2
		2:
			if not _drop_step(e):
				return -1
			_random_sound(sim.rng_next())             # `$1007C`
			s.subphase = 0
			s.phase = 1
	return -1


# --- the goal (phase 3) -----------------------------------------------------------------------

## `$FDD2`: the goal sequence; then the replay off, in overtime the game's
## end (sudden death), else the scoring coach's speech (a human team's,
## not in the attract demo) and the goal scoreboard (12).
func _phase_goal(e: int) -> int:
	if s.subphase == 0:
		if goal_step(e) >= 0:
			return -1
		s.replay_on = 0
		if MwRinkSim.s8(s.period) > 3:
			return _game_end()
		if s.fight_block == 0 and _setup_goal():
			s.subphase = 1
			return -1
		return _goal_exit()
	if speech(e):
		return -1
	return _goal_exit()


## `$FE1C`: after a goal into a Demon Net (the top net, puck y < 0) the
## team attacking down gets the stadium's net back and a goalie (`$7D2`,
## `$F6A8`); the goal scoreboard.
func _goal_exit() -> int:
	if s.puck.motion.pos[1] < 0 and s.nets[0].style == 0:
		var team := s.teams[0] if s.teams[0].flags4 & 2 else s.teams[1]
		team.flags4 &= ~0x08
		MwRinkMatch.set_top_net(sim, rom[MwRinkState.stadium_record(rom, s.stadium) + 5])
		sim.players.substitute(team.players[5])
	return exit(12)


## `$928C`: one step of the goal sequence (`$FFC2B6`); returns the state
## (signed word, -1 when done).
func goal_step(_e: int) -> int:
	match s.goal_message:
		0:
			# the horn; a Demon Net swallows a top-net goal; the clock stops
			s.goal_net = 0
			_sound(4)
			if s.puck.motion.pos[1] < 0 and s.nets[0].style == 0:
				s.goal_net = 0xB100
				s.goal_net_frame = 0
				sim.events.append(["demon_net"])
				if sim.live:
					MwSound.crowd_fade()                  # `$92E2`
				var n := s.nets[0]
				n.anim = MwAnimState.from_record(rom, DEMON_NET_GOAL)
				n.anim.flags |= MwAnimState.PLAYING
			s.goal_message_step = 1
			_clock_stop()
			s.goal_tick = _now(TICK_GOAL_0)
			s.goal_message = 1
		1:
			# 30 steps of "HE SCORES!" / "HAT TRICK!" blinking, a step when 6
			# ticks passed (re-stamped now: pass-quantised)
			_demon_net_sounds()
			if _since(TICK_GOAL_BLINK, s.goal_tick) >= 6:
				s.goal_tick = _now(TICK_GOAL_RESTAMP)
				s.goal_message_step = (s.goal_message_step + 1) & 0xFFFF
				if s.goal_message_step >= 0x1F:
					s.goal_message = 2
					window_ops.append(["fill", 6, 4, 28, 3, 0x8000])
				elif s.goal_message_step & 1:
					window_ops.append(["fill", 6, 4, 28, 3, 0x8000])
				else:
					window_ops.append(["text", BIG_FONT, 6, 4, 0xA0, T_HAT_TRICK if _scorer_goals() == 3 else T_HE_SCORES])
		2:
			# the scored end's lamp pops; the visitors' goal sound; the clock widget goes
			_demon_net_sounds()
			var lamp := s.lamps[1] if s.puck.motion.pos[1] < 0 else s.lamps[0]
			lamp.anim.flags |= MwAnimState.PLAYING
			lamp.motion.vel[2] = 0x1E0
			if s.scoring == _team_long(1):
				_sound(0x1A)
			s.goal_message = 3
			_widget_erase()
		3:
			_demon_net_sounds()
			if not (s.puck.motion.pos[1] < 0 and s.nets[0].style == 0 and s.nets[0].anim.playing()):
				_sound(9)
				_goal_panel()
				s.goal_message = 4
				s.goal_tick = _now(TICK_GOAL_3)
		4:
			_goal_panel()
			if MwRinkSim.s16(_since(TICK_GOAL_PANEL, s.goal_tick)) >= 0x96:
				s.goal_message = 5
		5:
			s.faceoff_spot = 0
			_panel_erase()
			s.goal_message = 0xFFFF
	return MwRinkSim.s16(s.goal_message)


## `$931C`: the swallowing Demon Net's sounds (frames $E and $3C).
func _demon_net_sounds() -> void:
	if s.goal_net == 0:
		return
	var f := (s.nets[0].anim.position & 0xFFFF) >> 8
	if f == s.goal_net_frame:
		return
	s.goal_net_frame = f
	if f == 0xE:
		_sound(0x2F)
	elif f == 0x3C:
		_sound(0x30)


## `$CB2A` +4: the goals of the last carrier (`$FFB3E6`) this game (team B
## if his address is team B's or above; no carrier reads the ROM).
func _scorer_goals() -> int:
	var c := s.puck.carrier
	if c == null:
		return s.teams[0].stat(0x3A2 + 8 * rom[0x68] + 4)
	return s.teams[c.team].stat(0x3A2 + 8 * c.slot + 4)


## `$946E`: the goal panel ("GOAL SCORED BY" and the scorer's name, none
## for an own goal: the puck's +$2A).
func _goal_panel() -> void:
	var name := s.puck.owner_log & 0xFFFFFFFF
	_panel(0, T_GOAL_SCORED_BY if name != 0 else 0, name)


## `$94C0(mode, a0, a1)`: the panel - title [param a0] and [param a1]
## (on one line at a faceoff, mode 1; two lines for a goal, mode 0), the
## bar, both teams' names and scores.
func _panel(mode: int, a0: Variant, a1: Variant) -> void:
	if mode == 0:
		window_ops.append(["text", TITLE_FONT, 2, 13, 0xE0, a0])
		window_ops.append(["text", NAME_FONT, 2, 15, 0xE0, a1])
	else:
		window_ops.append(["text", TITLE_FONT, 2, 15, 0xE0, a0])
		window_ops.append(["text_after", NAME_FONT, 15, 0xE0, a1])
	window_ops.append(["text", BIG_FONT, 1, 15, 0xA0, T_BAR])
	for t in 2:
		var team := s.teams[t]
		var row := 0x13 if t == 0 else 0x17
		window_ops.append(["text", BIG_FONT, 1, row, 0xA0, MwGfx.u32(rom, team.record + 4)])
		var g := MwRinkSim.s16(team.score)
		if g >= 10:
			window_ops.append(["glyph", BIG_FONT, 0x21, row, 0xA0, (0x30 + (g & 0xFFFF) / 10) & 0xFF])
			g = (g & 0xFFFF) % 10
		window_ops.append(["glyph", BIG_FONT, 0x24, row, 0xA0, (0x30 + g) & 0xFF])


## `$95AC`: the panel's rows (13-26) cleared.
func _panel_erase() -> void:
	window_ops.append(["fill", 0, 13, 40, 14, 0x8000])


# --- fight, period end, game over (phases 4, 5, 10) -----------------------------------------------

## `$FE66`: "FIGHT!", the clock stopped; 180 ticks after the last open-play
## pass the fight screen (18).
func _phase_fight() -> int:
	window_ops.append(["text", BIG_FONT, 11, 8, 0xA0, T_FIGHT])
	_clock_stop()
	if _since(TICK_FIGHT, s.phase_tick) >= 0xB4:
		return exit(18)
	return -1


## `$FE8C`: 180 ticks after the last open-play pass the period's end
## (`$FEBA`); sub 1: the game-over panel.
func _phase_period_end() -> int:
	if s.subphase == 0:
		if _since(TICK_PERIOD_END, s.phase_tick) < 0xB4:
			return -1
		s.replay_on = 0
		return _period_decision()
	return _winner_panel()


## `$FEBA`: periods 1-2 end into the next (screen 14); from period 3 a tie
## goes on too (overtime), a winner ends the game ([method _game_end]).
func _period_decision() -> int:
	if MwRinkSim.s8(s.period) < 3:
		return _next_period()
	return _game_end()


## `$FEC6`: the game's end, unless tied (another period): the winner
## (`$C640`), a playoff game's result (`$12854`), everyone lets go of the
## puck and loses human control (`$FFA8`), the clock widget erased; then
## the winner panel.
func _game_end() -> int:
	s.phase = 5
	s.subphase = 0
	var a := s.teams[0].score & 0xFFFF
	var b := s.teams[1].score & 0xFFFF
	if a == b:
		return _next_period()
	s.scoring = _team_long(0 if a > b else 1)
	var result := -1
	if s.play_mode != 0:
		result = int(s.playoffs.game_over(a >= b))
	s.playoff_result = result & 0xFFFF
	for team in s.teams:
		for p in team.players:
			if p.present:
				sim.puck.drop(p)
				p.flags &= ~MwRinkState.Player.HUMAN
	s.phase_tick = _now(TICK_WINNER)
	_widget_erase()
	s.subphase = 1
	return _winner_panel()


## `$FF2A`: the panel with both scores (no titles) for 180 ticks; then
## the game-over speech (team A's coach, `$1054C`), the period change for
## both teams (`$3960`), phase 10.
func _winner_panel() -> int:
	_panel(1, T_NONE, T_NONE)
	if _since(TICK_WINNER_PANEL, s.phase_tick) < 0xB4:
		return -1
	_panel_erase()
	s.speaker = 0
	_setup_game_over(s.teams[0], s.teams[1])
	MwRinkMatch.period_end(sim)
	s.phase_tick = _now(TICK_GAME_OVER)
	s.phase = 10
	return -1


## `$FF84`: the period change for both teams (`$3960`), the next period
## (`$2524`), the period scoreboard (14).
func _next_period() -> int:
	MwRinkMatch.period_end(sim)
	_next_period_clock()
	return exit(14)


## `$1008E`: the game-over speech(es) - team B's coach too when it has a
## pad - then game over (`$FB2E`: 15, 16 in the playoffs).
func _phase_game_over(e: int) -> int:
	if speech(e):
		return -1
	if s.speaker == 0 and s.teams[1].flags4 & 4:
		s.speaker = 1
		_setup_game_over(s.teams[1], s.teams[0])
		return -1
	return _game_over_exit()


# --- stoppages (phases 8, 13, 14) ----------------------------------------------------------------

## `$FFD6`: the stoppage (`$CA12`); then the faceoff (5).
func _phase_stoppage(e: int) -> int:
	if _stoppage(e) != 0:
		return -1
	return exit(5)


## `$CA12`: state 0 (with state 1 at once): the stoppage icon shown, the
## crowd up, the whistle, the clock stopped; state 1: "ICING" or "FACE
## OFF" (a goalie hold) for 180 ticks; state 2: the icon hidden, the
## faceoff at the deep circle of the stoppage's end (`$AF1C` at y +-372).
func _stoppage(e: int) -> int:
	if s.puck_rule == 0:
		s.stoppage.flags |= 0x80
		s.crowd = MwRinkSim.s16(s.crowd + 0xFA)
		s.stop_tick = _now(TICK_STOP_0)
		s.puck_rule = 1
		_sound(0x1C)
		_clock_stop()
	if s.puck_rule == 1:
		_icon(e)
		if s.rule_hold != 0:
			window_ops.append(["text", BIG_FONT, 4, 3, 0xA0, T_STOP_FACE_OFF])
		else:
			window_ops.append(["text", BIG_FONT, 7, 3, 0xA0, T_ICING])
		if MwRinkSim.s16(_since(TICK_STOP_WAIT, s.stop_tick)) >= 0xB4:
			s.puck_rule += 1
		return s.puck_rule
	s.stoppage.flags &= ~0x80
	s.faceoff_spot = nearest_spot(rom, s.rule_spot.x, 0x174 if s.rule_spot.y >= 0 else -0x174)
	s.puck_rule = 0
	return 0


## `$AFAC` + `$AFBC` for the stoppage icon: advanced while shown, drawn in
## screen space.
func _icon(e: int) -> void:
	if s.stoppage.shown():
		s.stoppage.anim.advance(e)
		overlays.append([s.stoppage, false])


## `$101CE`: "FORFEIT!", the clock stopped; 300 ticks, then 17.
func _phase_forfeit() -> int:
	_clock_stop()
	window_ops.append(["text", BIG_FONT, 8, 4, 0xA0, T_FORFEIT])
	if _since(TICK_FORFEIT, s.phase_tick) >= 0x12C:
		return exit(17)
	return -1


## `$1020E`: the FACE OFF banner (the puck went out of play): rows 0-13
## cleared and the clock stopped once, "FACE OFF" (`$6251D` at (9, 4))
## until more than 180 ticks passed, then the faceoff the simulation chose
## (5).
func _phase_banner() -> int:
	if s.subphase == 0:
		window_ops.append(["fill", 0, 0, 40, 14, 0x8000])
		_clock_stop()
		s.subphase = 1
	window_ops.append(["text", BIG_FONT, 9, 4, 0xA0, T_BANNER])
	# the second line (`$62525` at (9, 6), an empty string) is set up but
	# never drawn: `$10280` jumps past its draw_text
	if _since(TICK_BANNER, s.phase_tick) > 0xB4:
		s.subphase = 0
		return exit(5)
	return -1


# --- special plays (phases 11, 12) and the penalty (phase 2) ---------------------------------------

## `$100BE` (Waste the Goalie: the team with +5 bit 1 hunts the other's
## goalie; the clock keeps running): at 0:00 the sound $1D once; the
## goalie gone or dead, or 480 ticks over (he dies: state $12), the sound
## 9; then play on (phase 0), a penalty call on the actor (`$A4AA(3)`:
## nothing with penalties off but the bribed referee's roll), the play
## over, the phase stamp.
func _phase_waste_goalie() -> int:
	var team := s.teams[0]
	var victim := s.teams[1]
	if not team.flags5 & 2:
		team = s.teams[1]
		victim = s.teams[0]
	if s.subphase == 2:
		s.subphase = 0
		s.phase = 0
		if s.special_actor != null:
			sim.penalty(3, s.special_actor)
		team.flags5 &= ~2
		s.phase_tick = _now(TICK_WASTE_GOALIE_END)
		return -1
	if s.subphase == 0 and s.clock == 0:
		_sound(0x1D)
		s.subphase = 1
	var g := victim.players[5]
	if g.present and g.state != 0x12:
		if _since(TICK_WASTE_GOALIE, s.phase_tick) < 0x1E0:
			return -1
		sim.players.enter(g, 0x12)
	_sound(9)
	s.subphase = 2
	return -1


## `$10182` (Waste the Ref): the clock stopped; the referee on the ice
## every pass (`$EF5E` at (165, 0), attr $A0, his animation from the start
## each pass, `$EF84` his motion) and drawn (`$EFB4`: [member sprite_ops]
## ["referee", attr], with the camera); 180 ticks, then the referee
## screen (19).
func _phase_waste_ref(e: int) -> int:
	_clock_stop()
	var r := s.referee
	s.ref_flag = 5
	s.ref_attr = 0xA0
	r.motion.init(0xA5, 0, 0)
	r.anim = MwAnimState.from_record(rom, REF_ANIM)
	if r.anim.playing():
		r.motion.step(s.player_params, e)
		r.anim.advance(e)
	elif s.ref_flag != 0:
		r.anim = MwAnimState.from_record(rom, REF_ANIM)
	sim.events.append(["referee"])
	sprite_ops.append(["referee", s.ref_attr])
	if _since(TICK_WASTE_REF, s.phase_tick) >= 0xB4:
		return exit(19)
	return -1


## `$FD4E` (penalties on only: `$A66A` sets it, plan 10): at 0:00 the
## period's end at once; else the call (`$A6C2`: the whistle, "PENALTY"
## for 240 ticks); then the replay off and the penalized human teams'
## coaches (`$10732`, team A first); then the penalty box screen (17).
func _phase_penalty(e: int) -> int:
	if s.subphase == 0:
		if s.clock == 0:
			s.subphase = 0
			s.phase = 5
			s.penalty.flags &= ~0x80
			return _phase_period_end()
		if _penalty_call() >= 0:
			return -1
		s.subphase = 1
		s.replay_on = 0
		s.speaker = 0
		if _setup_penalty(s.teams[0], s.teams[1]):
			return -1
		return _penalty_next()
	if speech(e):
		return -1
	return _penalty_next()


## `$FDA8`: team B's coach after team A's, then 17.
func _penalty_next() -> int:
	while s.speaker == 0:
		s.speaker = 1
		if _setup_penalty(s.teams[1], s.teams[0]):
			return -1
	return exit(17)


## `$A6C2` (`$FFC2F0`): 0: the crowd up, the whistle (the visitors' sound
## $1A is dead code: it tests phase 0 inside phase 2), the clock stopped,
## the penalty icon shown and stamped; 1: "PENALTY" until 240 ticks, the
## icon hidden; 2: done (-1).
func _penalty_call() -> int:
	match s.penalty_step:
		0:
			s.crowd = MwRinkSim.s16(s.crowd + 0x14D)
			_sound(0x1C)
			if s.teams[0].stat(0x3A0, 1) == 0 and s.phase == 0:
				_sound(0x1A)
			_clock_stop()
			s.penalty_tick = _now(TICK_PENALTY_STAMP)
			s.penalty.flags |= 0x80
			s.penalty_step = 1
			_penalty_text()
		1:
			_penalty_text()
		2:
			s.penalty_step = 0
	return MwRinkSim.s16(s.penalty_step - 1)


func _penalty_text() -> void:
	window_ops.append(["text", BIG_FONT, 4, 3, 0xA0, T_PENALTY])
	if MwRinkSim.s16(_since(TICK_PENALTY_WAIT, s.penalty_tick)) >= 0xF0:
		s.penalty_step = 2
		s.penalty.flags &= ~0x80


# --- the puck rules `$C84A` ---------------------------------------------------------------------

## `$C84A` (open play only, before the phase handler): a goalie holding
## the puck 15 clock seconds stops play (phase 8, "FACE OFF"); icing: the
## puck crossing the opponents' goal line from at least 329 px away
## (from its own half) untouched shows the stoppage icon (pending); a
## team-mate or any goalie touching it waves it off, an opposing skater
## stops play (phase 8, "ICING"); a short-handed team and the one that
## bribed the referee may ice.
##
## Quirk (kept): a loose puck whose y equals the noted y exactly takes the
## "touched" branch and, the carrier flag being unchanged, waves the icing
## off.
func puck_rules(e: int) -> void:
	if s.phase != 0:
		return
	var pk := s.puck
	var c := pk.carried_by()
	if c != null and c.position == 5:
		if ((s.rule_clock - s.clock) & 0xFFFF) >= 0xF:
			# `$C9C6`: the goalie hold
			var p := pk.motion.pixels()
			s.rule_hold = 0xFFFF
			s.rule_spot = Vector2i(MwRinkSim.s16(p.x), MwRinkSim.s16(p.y))
			s.phase = 8
			s.puck_rule = 0
			return
	else:
		s.rule_clock = s.clock & 0xFFFF
	var icing := s.teams[1] if s.rule_team_b != 0 else s.teams[0]     # the last carrier's team
	var other := s.teams[0] if icing == s.teams[1] else s.teams[1]
	var was_b := s.rule_team_b
	var y := MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[1], 8))
	var r := 0
	var check := s.puck_rule != 0
	if not check:
		if absi(y) >= 0x149 and absi(MwRinkSim.s16(s.crease_y - y)) >= 0x149:
			if icing.flags4 & 2:
				check = y >= 0
			else:
				check = y < 0
	var note := true
	if check:
		_note_carrier()
		if icing.stat(0x39F, 1) > other.stat(0x39F, 1) or s.bribe == TEAM_WORDS[_team_index(icing)]:
			s.crease_y = y                       # allowed: short-handed, or the referee bribed
		elif y != s.crease_y:
			r = 1
			note = false
		elif was_b != s.rule_team_b:
			var t := pk.carrier
			var pos := t.position if t != null else rom[0x69]
			if pos != 5:
				r = 2
				note = false
	if note:
		_note_carrier()
	match r:
		0:
			if s.puck_rule != 0:
				s.stoppage.flags &= ~0x80
				s.stoppage.anim.flags &= ~MwAnimState.PLAYING
				s.puck_rule = 0
		1:
			if s.puck_rule == 0:
				s.stoppage.flags |= 0x80
				s.stoppage.anim.flags |= MwAnimState.PLAYING
				_icon(e)
				var p := pk.motion.pixels()
				s.rule_spot = Vector2i(MwRinkSim.s16(p.x), MwRinkSim.s16(-p.y))
				s.puck_rule = 1
			else:
				_icon(e)
		2:
			s.phase = 8
			s.puck_rule = 0


## `$C82A`: a carried puck's y and carrier's team are noted.
func _note_carrier() -> void:
	var pk := s.puck
	if not pk.flags & MwRinkState.Puck.CARRIED:
		return
	s.crease_y = MwRinkSim.s16(MwRinkSim.asr(pk.motion.pos[1], 8))
	s.rule_team_b = 0xFF if pk.flags & MwRinkState.Puck.BY_TEAM_B else 0


# --- coach speeches -----------------------------------------------------------------------------

## `$102A6`: a speech pass: crowd noise off, the portrait talks (`$B572`),
## while talking a coach whose quote value is 2-3 pulls a face 3 times in
## 64 (rng_next < $C00, every pass); an expression over, back to talking;
## the portrait, box, quote, bubble tail and coach name drawn. The speech
## ends after 600 ticks, or on Start / A / B / C held or pressed on a pad
## of the speaking team (in a goal speech the other team's, if it has a
## pad; a CPU team cannot skip). Returns true while it goes on; at the end
## the box and name are erased, the portrait stops, its voice too.
func speech(e: int) -> bool:
	sim.events.append(["crowd_off"])
	if sim.live:
		MwSound.crowd_off()                     # `$102A8`
	s.crowd_quiet = 1
	var p := s.portrait
	_portrait_step(e)
	if p.anim.playing():
		if p.mode == 0 and (s.quote_value & 0xFFFF) >= 2 and (s.quote_value & 0xFFFF) <= 3:
			if (sim.rng_next() & 0xFFFF) < 0xC00:
				_talk_mode(1)
	else:
		_talk_mode(0)
	sprite_ops.append(["portrait", 0xE8 if s.speaker != 0 else 0x20, 0x64, 0x8000, 0xA0,
			p.anim.address, p.anim.variant, p.anim.frame, p.size])
	_box(false)
	_print_quote()
	if s.speaker != 0:
		sprite_ops.append(["piece", BUBBLE_TAIL, 0xF0, 0x49, 0xE8, 0xFFFF])
	else:
		sprite_ops.append(["piece", BUBBLE_TAIL, 0x50, 0x49, 0xE0, 0xFFFF])
	var name_x := 3
	if s.speaker != 0:
		name_x = 0x25 - _text_width(NAME_FONT, s.coach_name)
	window_ops.append(["text", NAME_FONT, name_x, 0x17, 0xE0, s.coach_name])
	var done := _since(TICK_SPEECH, s.phase_tick) >= 0x258
	if not done:
		var skipper := s.teams[1] if s.speaker != 0 else s.teams[0]
		var other := s.teams[0] if skipper == s.teams[1] else s.teams[1]
		if s.phase == 3 and other.flags4 & 4:
			skipper = other
		done = _skips(skipper)
	if not done:
		return true
	window_ops.append(["fill", 2, 2, 36, 8, 0x8000])            # `$BD82`
	_portrait_stop()
	s.crowd_quiet = 0
	window_ops.append(["fill", 0, 23, 40, 2, 0x8000])
	return false


## The skip test: [param team]'s first pad slot (none: no skip), then its
## second; Start / A / C / B held or newly pressed (word & $F0F0).
func _skips(team: MwRinkState.Team) -> bool:
	for k in 2:
		var pad: int = team.pads[k]
		if pad & 0x80:
			return false
		var w := ((s.pads_held[pad & 3] & 0xFF) << 8) | (s.pads_new[pad & 3] & 0xFF)
		if w & 0xF0F0:
			return true
	return false


## `$B572`: the portrait's pass. Pulling a face (mode 1): the expression
## animates, a frame change plays the sound listed for the frame left.
## Talking (mode 0, while playing): a step every 8 ticks (the timer
## counts up from -40; at most one step per pass); a step polls the voice
## (`$13D9C`): still playing, or a new one started (two per cycle; after
## them a 480-tick pause, the mouth shut) - the mouth alternates a random
## frame (`rng_range(0, frames - 1)`) and frame 0.
func _portrait_step(e: int) -> void:
	var p := s.portrait
	if p.mode != 0:
		var old := p.anim.frame
		p.anim.advance(e)
		if old == p.anim.frame:
			return
		var a := p.data + 0xA
		while true:
			var w := MwGfx.u16(rom, a)
			if old < w:
				return
			if old == w:
				_sound(MwGfx.u16(rom, a + 2))
				return
			a += 4
		return
	if not p.anim.playing():
		return
	var t := MwRinkSim.s16(e + p.timer)
	if t < 0:
		p.timer = t & 0xFFFF
		return
	t = MwRinkSim.s16(t - 8)
	if not _voice_playing(p.handle):
		if p.voices == 0:
			p.timer = 0xFE20                       # -480: the pause, mouth shut
			p.voices = 2
			p.anim.frame = 0
			return
		p.voices = (p.voices - 1) & 0xFFFF
		p.handle = _start_voice(MwGfx.u16(rom, p.data + 8))
	if p.anim.frame != 0:
		p.anim.frame = 0
	else:
		p.anim.frame = sim.rng_range(0, rom[p.anim.address + 3] - 1) & 0xFF
	p.timer = t & 0xFFFF


## `$B542`: the portrait talking (0) or pulling a face (1): that
## animation from its start, playing, the timer at -40, two voices.
func _talk_mode(mode: int) -> void:
	var p := s.portrait
	if mode >= 2:
		mode = 1
	p.mode = mode
	p.anim = MwAnimState.from_record(rom, MwGfx.u32(rom, p.data + 4 * mode))
	p.x0b = 0
	p.anim.flags |= MwAnimState.PLAYING
	p.timer = 0xFFD8
	p.voices = 2


## `$B656`: the portrait stopped, its voice too.
func _portrait_stop() -> void:
	var p := s.portrait
	p.anim.flags &= ~MwAnimState.PLAYING
	sim.events.append(["voice_stop", p.handle])
	if sim.live:
		MwSound.stop(p.handle)                  # `$B660`
	_voice_end.erase(p.handle)
	p.handle = 0


## `$B6D2`: the portrait for coach record [param coach] (`$1CD26`: 20
## coaches, else the default `$1CCA2` and the set the word at ROM 4
## holds); size 1. Returns the coach's quote set.
func _portrait_for(coach: int) -> int:
	var p := s.portrait
	p.size = 1
	p.x10 = 0
	for i in 20:
		var a := COACHES + 10 * i
		if MwGfx.u32(rom, a) == coach:
			p.data = MwGfx.u32(rom, a + 4)
			return MwGfx.u16(rom, a + 8)
	p.data = COACH_DEFAULT
	return MwGfx.u16(rom, 4)


## The voice handle's "still playing?" (`$13D9C` at `$B5C4`): the hooks'
## answer, the driver's in live play, else [constant VOICE_TICKS].
func _voice_playing(handle: int) -> bool:
	if hooks != null and hooks.has_method("voice_poll"):
		return int(hooks.call("voice_poll", self, handle)) != 0
	if _driver():
		return MwSound.busy(handle)
	if not _voice_end.has(handle):
		return false
	if (s.tick & 0xFFFFFFFF) < int(_voice_end[handle]):
		return true
	_voice_end.erase(handle)
	return false


## A coach voice (sequence [param id]) started (`$13CEE` at `$B5EE`): its
## handle - the hooks', the driver's in live play, else our own.
func _start_voice(id: int) -> int:
	var h := _sound(id)
	if hooks != null and hooks.has_method("voice_handle"):
		h = int(hooks.call("voice_handle", self, id))
	elif not _driver():
		_serial = (_serial + 1) & 0x7FFFFFFF
		h = _serial | 0x80000000
	if not _driver():
		_voice_end[h] = (s.tick & 0xFFFFFFFF) + int(VOICE_TICKS.get(id, VOICE_DEFAULT))
	return h


## The set-ups' common part (`$10474`, `$1054C`, `$10610`, `$10732`): the
## clock widget and the penalty icon hidden, the coach's name, his portrait
## talking. Returns the coach's quote set.
func _setup_coach(team: MwRinkState.Team) -> int:
	_widget_erase()
	s.penalty.flags &= ~0x80
	var coach := MwGfx.u32(rom, team.record + 0xC)
	s.coach_name = MwGfx.u32(rom, coach)
	var set := _portrait_for(coach)
	_talk_mode(0)
	return set


## The set-ups' end: the quote (`$F420`), the box (`$BD96`), the stamp.
func _setup_quote(set: int, category: int, situation: int, team: MwRinkState.Team, other: MwRinkState.Team, tag: int) -> void:
	_quote(set, category, situation, team, other)
	_box(true)
	s.phase_tick = _now(tag)
	sim.events.append(["speech", s.speaker, s.quote.slice(0, s.quote.find(0))])


## `$10474`: a period start's speech by [param team]'s coach: period 1
## (category 0, 1 in the playoffs) by the skulls (team record +$B)
## compared, periods 2-3 (2) by the score, overtime (3) situation 0.
func _setup_period_start(team: MwRinkState.Team, other: MwRinkState.Team) -> void:
	var set := _setup_coach(team)
	var cat := 0
	var sit := 0
	var p := s.period & 0xFF
	if p >= 4:
		cat = 3
	elif p >= 2:
		cat = 2
		var d := MwRinkSim.s16(team.score - other.score)
		if d >= 3:
			sit = 0
		elif d >= 1:
			sit = 1
		elif d == 0:
			sit = 2
		elif d >= -2:
			sit = 3
		else:
			sit = 4
	else:
		var d := MwRinkSim.s8(rom[team.record + 0xB] - rom[other.record + 0xB])
		if d >= 2:
			sit = 0
		elif d >= -1:
			sit = 1
		elif d >= -2:
			sit = 2
		else:
			sit = 3
		cat = 1 if s.play_mode != 0 else 0
	_setup_quote(set, cat, sit, team, other, TICK_SETUP_START)


## `$1054C`: a game-over speech by [param team]'s coach: a regular game
## (category 4) by the score (tie 3, the other team scoreless 0, lost by
## 3+ 1, by 1-2 2, won by 3+ 4, by 1-2 5); the playoffs (5) by the result
## `$12854` (team A's as is; team B's: 0 -> 3 or 4, 3+ -> 0, else 4).
func _setup_game_over(team: MwRinkState.Team, other: MwRinkState.Team) -> void:
	var set := _setup_coach(team)
	var cat := 4
	var sit := s.playoff_result & 0xFFFF
	if MwRinkSim.s16(s.playoff_result) < 0:
		var o := other.score & 0xFFFF
		if o == (team.score & 0xFFFF):
			sit = 3
		elif o == 0:
			sit = 0
		else:
			var d := MwRinkSim.s16(o - team.score)
			if d >= 3:
				sit = 1
			elif d >= 0:
				sit = 2
			elif d <= -3:
				sit = 4
			else:
				sit = 5
	else:
		cat = 5
		if team == s.teams[1]:
			if sit == 0:
				sit = 3 if s.playoffs.best_of_3 != 0 and s.playoffs.series != 0 else 4
			elif sit >= 3:
				sit = 0
			else:
				sit = 4
	_setup_quote(set, cat, sit, team, other, TICK_SETUP_OVER)


## `$10610`: the goal's speech (category 7) by the scoring team's coach if
## it has a pad. The scoring team by the goal's end (team A if puck y >= 0
## equals "team A attacks down"; else team B, `$C636` = 1); a last carrier
## not of that team makes it an own goal (6: the speaking side toggled, his
## team's coach speaks, scorer 0). Else a Demon Net goal 5, a hat trick 3,
## a power-play goal 2, a 2-point goal 1, else 0. `$C63A`, `$C640`, `$C63C`
## are noted. Returns whether a speech started.
func _setup_goal() -> bool:
	_widget_erase()
	s.penalty.flags &= ~0x80
	s.speaker = 0
	var team := s.teams[0]
	var other := s.teams[1]
	var bottom := s.puck.motion.pos[1] >= 0
	if bottom != (s.teams[0].flags4 & 2 != 0):
		team = s.teams[1]
		other = s.teams[0]
		s.speaker = 1
	var c := s.puck.carrier
	var c_long := 0 if c == null else (0xFFFF0000 | MwRinkRam.word_of(s, c))
	var sit := 6
	var speaking := team
	if c == null or ((c_long - _team_long(_team_index(team))) & 0xFFFF) >= 0x4AA:
		speaking = other                          # an own goal
		s.speaker ^= 1
	elif not bottom and s.nets[0].style == 0:
		sit = 5
	else:
		var goals := team.stat(0x3A2 + 8 * c.slot + 4)
		if goals == 3:
			sit = 3
		elif s.clock_widget & 1:
			sit = 2
		elif (s.goal_points & 0xFFFF) >= 2:
			sit = 1
		else:
			sit = 0
	s.goal_kind = sit
	s.scoring = _team_long(_team_index(speaking))
	s.scorer = c_long
	if sit == 6:
		s.scoring = _team_long(_team_index(team))
		s.scorer = 0
	if not speaking.flags4 & 4:
		return false
	var coach := MwGfx.u32(rom, speaking.record + 0xC)
	s.coach_name = MwGfx.u32(rom, coach)
	var set := _portrait_for(coach)
	_talk_mode(0)
	var them := s.teams[1] if speaking == s.teams[0] else s.teams[0]
	_setup_quote(set, 7, sit, speaking, them, TICK_SETUP_GOAL)
	return true


## `$10732`: a penalty's speech (category 6) by [param team]'s coach if it
## has a pad and a player of it is in the box (+$74 bit 1).
func _setup_penalty(team: MwRinkState.Team, other: MwRinkState.Team) -> bool:
	s.penalty.flags &= ~0x80
	if not team.flags4 & 4:
		return false
	var any := false
	for p in team.players:
		if p.present and p.flags & MwRinkState.Player.IN_BOX:
			any = true
			break
	if not any:
		return false
	var set := _setup_coach(team)
	_setup_quote(set, 6, 0, team, other, TICK_SETUP_PENALTY)
	return true


## `$F420`: a quote of [param category] / [param situation] for quote set
## [param set] (`$1D404`): its value word (`$C616`) and one of its strings
## (none: `$50D2D`; several: `rng_range(0, count - 1)`) copied into
## `$FFC4FE` with the codes expanded: `[` the team's city and name, `{` the
## team's name, `}` the other team's, `@` a5's string (unused by the
## rink's categories; category 9's pick by a counter is the screens').
func _quote(set: int, category: int, situation: int, team: MwRinkState.Team, other: MwRinkState.Team) -> void:
	var t := MwGfx.u32(rom, QUOTES + 4 * category)
	t = MwGfx.u32(rom, t + 4 * situation)
	t = MwGfx.u32(rom, t + 4 * set)
	s.quote_value = MwGfx.u16(rom, t)
	var count := MwGfx.u16(rom, t + 2)
	var src := NO_QUOTE
	if count == 1:
		src = MwGfx.u32(rom, t + 4)
	elif count > 1:
		src = MwGfx.u32(rom, t + 4 + 4 * (sim.rng_range(0, count - 1) & 0xFFFF))
	var out := 0
	while true:
		var ch := rom[src]
		src += 1
		match ch:
			0x5B:                               # '[': city, a space, then the name
				out = _copy(out, MwGfx.u32(rom, team.record))
				_put(out, 0x20)
				out += 1
				out = _copy(out, MwGfx.u32(rom, team.record + 4))
			0x7B:
				out = _copy(out, MwGfx.u32(rom, team.record + 4))
			0x7D:
				out = _copy(out, MwGfx.u32(rom, other.record + 4))
			0x40:
				push_warning("MwRinkPhases: quote code @ (category 9 only)")
			_:
				_put(out, ch)
				out += 1
				if ch == 0:
					break
	s.quote_ptr = 0xFFFFC4FE


## A string copied without its terminator; returns the next offset.
func _copy(at: int, src: int) -> int:
	while rom[src] != 0:
		_put(at, rom[src])
		at += 1
		src += 1
	_put(at, 0)
	return at


func _put(at: int, v: int) -> void:
	if at < s.quote.size():
		s.quote[at] = v & 0xFF


## `$BD96` ([param filled]: the set-up; the speech box framed, filled with
## colour 9 and the text box made in it) / `$BD9E` (every pass: framed).
func _box(filled: bool) -> void:
	s.box_fill = 1 if filled else 0
	s.box_c3bc = 0
	for i in 4:
		s.speech_box[i] = MwGfx.s16(rom, SPEECH_BOX_AT + 2 * i)
	window_ops.append(["box", s.speech_box[0], s.speech_box[1], s.speech_box[2], s.speech_box[3], filled])
	if not filled:
		return
	var tb := s.text_box
	tb.plane = WINDOW
	tb.font = SPEECH_FONT
	tb.x = s.speech_box[0]
	tb.y = s.speech_box[1]
	tb.w = s.speech_box[2]
	tb.h = s.speech_box[3]
	tb.spacing = 0
	tb.cursor_x = 0
	tb.cursor_y = 0


## `$BB2E`: the quote printed into the text box from its corner (`$15860`:
## word wrap; the cursor ends where the text did).
func _print_quote() -> void:
	var tb := s.text_box
	tb.cursor_x = 0
	tb.cursor_y = 0
	window_ops.append(["quote", tb.font, tb.x, tb.y, 0xE0, s.quote.slice(0, maxi(s.quote.find(0), 0)), tb.w, tb.h])
	var f := tb.font
	var line := MwGfx.u16(rom, f) + tb.spacing
	var x := MwRinkSim.s16(tb.cursor_x)
	var i := 0
	var q := s.quote
	while i < q.size() and q[i] != 0:
		var ch := q[i]
		if ch < 0x21 or ch > 0x7E:
			if ch == 0x20:
				x = MwRinkSim.s16(x + MwGfx.u16(rom, f + 2))
			elif ch == 0x0A:
				tb.cursor_y = (tb.cursor_y + line) & 0xFFFF
				x = 0
			i += 1
			continue
		var width := 0
		var j := i
		while j < q.size() and q[j] >= 0x21 and q[j] <= 0x7E:
			width += glyph_width(rom, f, q[j])
			j += 1
		if MwRinkSim.s16(x + width) > MwRinkSim.s16(tb.w) and x != 0:
			tb.cursor_y = (tb.cursor_y + line) & 0xFFFF
			x = 0
		if (tb.cursor_y & 0xFFFF) >= (tb.h & 0xFFFF):
			break
		x = MwRinkSim.s16(x + width)
		i = j
	tb.cursor_x = x & 0xFFFF


## `$14BE6`: a printable character's width in [param font]'s cells (0 if
## the font has no glyph for it).
static func glyph_width(rom_: PackedByteArray, font: int, ch: int) -> int:
	var idx := MwGfx.s8(rom_, font + MwGfx.u16(rom_, font + 4) + ch - 0x21)
	if (idx & 0xFFFF) >= MwGfx.u16(rom_, font + 6):
		return 0
	return ((rom_[font + 8 + 6 * idx + 2] >> 2) & 3) + 1


## `$14C14`: a string's width in cells (spaces by the font's width).
func _text_width(font: int, src: int) -> int:
	return text_width(rom, font, src)


## `$14C14` for the string at ROM [param src].
static func text_width(rom: PackedByteArray, font: int, src: int) -> int:
	var w := 0
	while rom[src] != 0:
		var ch := rom[src]
		if ch == 0x20:
			w += MwGfx.u16(rom, font + 2)
		elif ch >= 0x21 and ch <= 0x7E:
			w += glyph_width(rom, font, ch)
		src += 1
	return w


## Live play with the sound driver running: its answers replace the
## measured voice lengths.
func _driver() -> bool:
	return sim.live and MwSound.driver != null


## `$13CE2` at the phase start (`$1007C`): one of the jingles 5-8 from
## [param r], the `rng_next` the original draws inside the call; the event
## ["sound", id].
func _random_sound(r: int) -> void:
	sim.events.append(["sound", 5 + (r & 3)])
	if sim.live:
		MwSound.random_sound(r)
