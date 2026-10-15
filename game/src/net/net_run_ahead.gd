class_name MwNetRunAhead
extends RefCounted
## Plan 41 (online feel), work item 2 - run-ahead on the rink: a client's
## picture of the rink drawn from the game's own passes run ahead of its
## confirmed state (docs/net.md "Run-ahead"). Presentation only: the
## confirmed state, its random numbers and hashes, the sound driver's
## answers are untouched - the passes run on a shadow copy ([MwRinkCopy])
## of the confirmed state.
##
## Each picture ([method run], from the rink scene's present): the
## confirmed rink state copied into [member shadow] with the phase handler's
## own fields - or the last picture's shadow carried on, while what it was
## fed still holds (a rollback only on a misprediction) - then the rink's pass ([method MwRinkUpdate.run_pass], the
## scene's pad reading, [method MwRink.read_pads]) run on it pass after pass
## from the last confirmed pass to [method MwNetMatch.ahead_tick] - where the
## host will merge this machine's input sent now. Each pass's input is made
## as the router makes it (the frame sampled after the pass before, the
## presses since): the stream's ticks while it has them, then the
## prediction ([method MwNetMatch.input_at]: this machine's players' states
## as sent, everyone else holding what they held, pressing nothing new). The
## CPU plays as it always does, so its players are foreseen exactly until a
## person's input differs. The shadow's last pass's draw makes the picture -
## made by the scene, on the positions dead reckoning eases from the last
## picture's point to the new one (MwNetReckoning, with no lead of its own;
## it carries on what the time [member budget_ms] left out): the run keeps
## only its draw's inputs (plan 42, MwRinkUpdate.defer_draws).
##
## Nothing of the shadow's pass is the game's event: its sound calls go to
## a sound driver's model of its own ([member audio], the game's copied in
## at each rollback - work item 3: the voices and songs the game waits on
## play out as they will) and are heard at once as a prediction, once a
## pass (MwSound.predicting, MwHeard: the game's own call later isn't heard
## again); it has no full replay, paint, crowd or benches of its own (they
## are the confirmed game's, lent to the picture: [method lend]), and a
## pass that leaves live play (a goal, a whistle, a pause) is the last it
## runs.
## Short names: m the online match (MwNetMatch).

## The debug switch: off, a client draws through dead reckoning alone.
## `--no-runahead` on the command line; F10 on the rink in a debug build
## online.
static var enabled := true
## The time a picture's run-ahead may take (ms): the copy and the passes
## (a picture comes with each of the rink's passes, 30 a second); the
## passes it leaves out are dead reckoning's, the next picture carries on
## from there. `--runahead-budget=MS` on the command line.
static var default_budget_ms := 8.0
var budget_ms := default_budget_ms
## Work item 4: a client that falls behind its stream (its game's ticks
## held past the buffer it aims for: [method MwNetMatch.lead] beyond
## [method MwNetMatch.buffer_target]) must never be kept behind by what it
## draws - the budget in force halves each picture it is more than
## [constant BEHIND_TICKS] behind (down to [constant MIN_BUDGET_MS]) and
## grows back a twentieth a picture once it isn't; [constant FAR_BEHIND_TICKS]
## behind it runs nothing (dead reckoning draws) until caught up.
const BEHIND_TICKS := 6
const FAR_BEHIND_TICKS := 30
const MIN_BUDGET_MS := 1.0
var budget_now := default_budget_ms
## How far it runs: the round trip's share past the newest confirmed tick
## (1.0: where the host will merge this machine's input; 0.5: the host's
## own now).
var reach := 1.0
## This machine's own switch (tests).
var on := true
## Off: every picture starts again from a copy of the confirmed state
## (tests: the carried-on shadow against the one started again).
var carry_on := true
var shadow := MwRinkState.new()
var sim: MwRinkSim
var update: MwRinkUpdate
var phases: MwRinkPhases
var copier := MwRinkCopy.new()
## Work item 3: the shadow's own sound driver's model (the game's copied in
## at each rollback: MwAudioCopy) - its passes call and ask it as the game
## calls and asks its own, so a wait on a voice or the goal song plays out
## as it will; their sounds are heard at once as a prediction (MwHeard).
## Null without the ROM, or with [member own_audio] off.
var audio: MwAudio = null
var audio_copier := MwAudioCopy.new()
## Off (tests): no driver of its own - its passes call none and ask none
## (the confirmed game's answers), heard nothing.
var own_audio := true
## Pictures run, passes run; pictures started again from a copy (and why:
## an input mispredicted - this machine's players' / anyone else's - or
## the confirmed state unlike the shadow's) and carried on; runs cut by the
## budget or by leaving live play; pictures with the budget cut for a
## client behind its stream, none run for one far behind; the shadow's sim
## made again; the time spent (us: all, the check that the shadow still
## holds, the copy, the feed, the passes, the draw; plan 42: the sound
## model's ticks, the marks, the next pass's input sampled).
var stats := {"runs": 0, "passes": 0, "rollbacks": 0, "carried": 0, "mispredicted": 0, "mis_own": 0,
		"mis_other": 0, "unlike": 0, "budget": 0, "slowed": 0, "behind": 0, "left_play": 0, "stacks": 0, "us": 0,
		"copy_us": 0,
		"check_us": 0, "feed_us": 0, "pass_us": 0, "sound_us": 0, "mark_us": 0, "sample_us": 0, "draw_us": 0}
## The last run's: the router tick its shadow is at, the tick it aimed for,
## its time (us), whether it started again, its passes.
var last := {"at": -1, "aim": -1, "us": 0, "fresh": false, "passes": 0}
var _match: WeakRef = null
# the shadow's run, carried from picture to picture
var _root: MwRinkState = null            # the confirmed state it was copied from
var _base := -1                          # the router tick it was copied at
var _at := -1                            # the router tick it is at (-1: none: start again)
var _left := false                       # its last pass left live play (none run after)
var _known := -1                         # the stream's newest tick when it was last fed
var _feed: MwInputStream = null          # the ticks it was fed
var _si: MwStreamInput = null            # read as the router reads its input
var _frame: MwInputFrame = null          # the next pass's input
var _held := {}
var _marks := {}                         # pass end (router tick) -> _mark() of the shadow there
var _audio_at := -1                      # the router tick [member audio] is at
var _sound_state := {}                   # MwSound's own bookkeeping in the shadow (the carried goal song)


static func _static_init() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--no-runahead":
			enabled = false
		elif a.begins_with("--runahead-budget="):
			default_budget_ms = maxf(a.get_slice("=", 1).to_float(), 0.5)


func _init(net_match: MwNetMatch = null) -> void:
	_match = weakref(net_match) if net_match != null else null


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if sim != null:
		sim.dispose()                        # plan 45: the shadow's sim cycle
	if audio != null and is_instance_valid(audio):
		audio.free()


## Whether this machine runs ahead: the debug switch ([member enabled]) and its own
## ([member on]) both on.
func active() -> bool:
	return enabled and on


## The rink scene [param rink]'s state run ahead into [member shadow];
## returns the router tick the shadow is at (-1: nothing run - off, no
## match, paused, no pass yet, nothing to run ahead). The phase handler's
## overlays and the draw are the shadow's last pass's ([member update]'s
## draw inputs, kept: the scene draws them, MwRinkUpdate.redraw, with its
## drawer placing them in the world).
##
## The shadow goes on from where the last picture left it while that run
## still holds ([method _goes_on]: the confirmed state reached one of its
## passes in the same place, and every input it was fed is still what the
## stream has or predicts) - a picture then costs the passes since the last
## one; otherwise it starts again from a copy of the confirmed state (a
## rollback). The budget cuts a run short: the next picture carries on
## from there.
func run(rink: MwRink, contexts: Array) -> int:
	take_back_left()                         # plan 45 (D8): never the confirmed match's models stepped here
	var m: MwNetMatch = _match.get_ref() if _match != null else null
	if not active() or m == null or m.phase != MwNetMatch.Phase.PLAYING or m.client == null:
		_at = -1
		return -1
	if rink.phases == null or rink.phases.paused or rink.state == null or not rink.update.can_redraw():
		_at = -1
		return -1
	var router := m.router
	var behind := m.lead() - m.buffer_target()
	if behind > FAR_BEHIND_TICKS:
		stats["behind"] += 1
		budget_now = MIN_BUDGET_MS
		_at = -1
		return -1
	if behind > BEHIND_TICKS:
		budget_now = maxf(budget_now * 0.5, MIN_BUDGET_MS)
		stats["slowed"] += 1
	else:
		budget_now = minf(budget_now + budget_ms / 20.0, budget_ms)
	var from := router.clock.last_pass_tick()
	var aim := m.ahead_tick(reach)
	var pacer := rink.pass_pacer()
	var steps: PackedInt32Array
	if pacer != null:
		# TICK RATE APPROXIMATED / ORIGINAL: the passes the pacer would make, the
		# first counted from the last pass (MwPassPacer.predict)
		steps = pacer.predict(maxi(aim - router.tick, 0), rink._work)
	else:
		steps = PackedInt32Array()
		var t := from
		while t + MwPassClock.RINK_PASS_TICKS <= aim:
			steps.append(MwPassClock.RINK_PASS_TICKS)
			t += MwPassClock.RINK_PASS_TICKS
	if from < 0 or steps.is_empty():
		_at = -1
		return -1
	# the passes' ends (router ticks)
	var ends := PackedInt32Array()
	var end := from
	for e in steps:
		end += e
		ends.append(end)
	var t0 := Time.get_ticks_usec()
	var fresh := not _goes_on(rink, m, from, ends)
	var tc := Time.get_ticks_usec()
	stats["check_us"] += tc - t0
	if fresh:
		copier.copy_into(shadow, rink.state)
		_ensure(rink, int(copier.stats["made"]) > 0)
		_copy_phases(rink.phases)
		_root = rink.state
		_feed = MwInputStream.new()
		_feed.first_tick = from
		_si = MwStreamInput.new(_feed)
		_base = from
		_at = from
		_left = false
		_marks = {from: _mark(shadow, phases)}
		if audio != null and MwSound.driver != null:
			# work item 3: the game's sound driver with it, at the router's tick
			audio_copier.copy_into(audio, MwSound.driver)
			audio.forget_owed()
			_audio_at = router.tick
			_sound_state = MwSound.snapshot_state()
		stats["rollbacks"] += 1
	else:
		_feed.truncate(_at)                    # (past the shadow: fed again, as predicted now)
		stats["carried"] += 1
	var t1 := Time.get_ticks_usec()
	# the passes' input: the stream's ticks, then the prediction, sampled as the router samples
	for k in range(_feed.last_tick() + 1, end + 1):
		var ti := m.input_at(k)
		if ti == null:
			_at = -1
			return -1
		_feed.append(ti)
	_known = m.stream.last_tick()
	if fresh:
		# the first pass's input: the router's next frame once it sampled it
		# after the last pass - inside that pass (its picture), sampled here as
		# the router will
		_si.take_up(m.input.seen(), from)
		if router.sampled_tick() >= from:
			_frame = router.pending_frame()
			_held = router.last_held()
		else:
			var first := _sample(_si, contexts, router.last_held(), router.remaps(), rink.session)
			_frame = first[0]
			_held = first[1]
	var t_feed := Time.get_ticks_usec()
	# the sound: its own driver's model (work item 3) - the game's calls and
	# questions there, heard at once as a prediction (MwHeard) - else none
	MwSound.begin_swap()                     # plan 45: put back by MwSound.reset_swaps if this stops
	var own_sound := audio != null
	if own_sound:
		MwSound.driver = audio
		MwSound.restore_state(_sound_state)
		MwSound.quiet = false
		MwSound.predicting = true
		if MwSound.heard != null:
			MwSound.heard.begin_run()
	else:
		MwSound.quiet = true
	sim.live = own_sound
	var ran := 0
	var t_pass := 0
	var t_sound := 0
	var t_mark := 0
	var t_sample := 0
	var prev := _at
	for b in ends:
		if b <= _at:
			continue
		if _left:
			break
		if ran > 0 and (Time.get_ticks_usec() - t0) / 1000.0 > minf(budget_now, budget_ms):
			stats["budget"] += 1
			break
		var e := b - prev
		if shadow.control != null:
			shadow.control.set_net(_frame.away)
		var input := _frame
		var ts := Time.get_ticks_usec()
		if own_sound:
			if _audio_at < b:
				# each tick's driver work before the pass, as the router - owed, run
				# when the pass calls or asks the driver (plan 42: most passes don't)
				audio.owed += b - _audio_at
				_audio_at = b
			MwSound.predict_key = "ahead:%d" % b
			MwSound.predict_due = b
		var tp := Time.get_ticks_usec()
		t_sound += tp - ts
		var to := update.run_pass(e, phases, func() -> void: MwRink.read_pads(shadow, sim, input), Callable(), false)
		var tm := Time.get_ticks_usec()
		t_pass += tm - tp
		_at = b
		prev = b
		ran += 1
		_marks[b] = _mark(shadow, phases)
		var tsa := Time.get_ticks_usec()
		t_mark += tsa - tm
		if to >= 0 or phases.paused:
			# a goal, a whistle, a pause: the last pass it runs (until it starts again)
			_left = true
			stats["left_play"] += 1
			break
		for i in e:
			_si.tick()
		var next := _sample(_si, contexts, _held, router.remaps(), rink.session)
		_frame = next[0]
		_held = next[1]
		t_sample += Time.get_ticks_usec() - tsa
	var t_draw := Time.get_ticks_usec()
	if ran > 0 or fresh:
		# plan 42 (second round): the draw's inputs kept - the scene draws the
		# shadow's picture itself (MwRinkUpdate.redraw: on the eased positions,
		# MwRink._drawn); made here as well it was made twice a picture
		update.defer_draws(rink._phase_adds, MwRinkPhases.RULES_DRAWN, phases.overlays, phases.sprite_ops)
	if own_sound:
		_sound_state = MwSound.snapshot_state()
	MwSound.end_swap()
	var t_end := Time.get_ticks_usec()
	stats["copy_us"] += t1 - tc
	stats["feed_us"] += t_feed - t1
	stats["pass_us"] += t_pass
	stats["sound_us"] += t_sound
	stats["mark_us"] += t_mark
	stats["sample_us"] += t_sample
	stats["draw_us"] += t_end - t_draw
	var us := t_end - t0
	stats["runs"] += 1
	stats["passes"] += ran
	stats["us"] += us
	last = {"at": _at, "aim": aim, "us": us, "fresh": fresh, "passes": ran}
	return _at


## Plan 42 (speed, second round): the copies' first-time work done now - each
## class's copy compiled (MwRinkCopy, ~2 ms a class), the sound model made
## and copied once - so the first rollback of a match is no hitch: as the
## rink is entered (MwRink, under the screen's fade). Nothing runs: the next
## picture starts from a copy as always.
func warm(rink: MwRink) -> void:
	var m: MwNetMatch = _match.get_ref() if _match != null else null
	if not active() or m == null or m.client == null or rink.state == null or rink.phases == null:
		return
	copier.copy_into(shadow, rink.state)
	_ensure(rink, true)
	if audio != null and MwSound.driver != null:
		audio_copier.copy_into(audio, MwSound.driver)
		audio.forget_owed()
	_at = -1


## Whether the last run's shadow still holds for a picture whose confirmed
## state is at [param from] and whose passes end at [param ends]: the same
## rink, the confirmed state at one of the shadow's passes' ends and alike
## there ([method _mark]: positions, the random stream, the clock - caught
## up the same way), the passes since on the same ends, and every tick fed
## since the stream's newest when it was fed the same as the stream has it
## now or predicts it now ([method MwNetMatch.input_at]). Not when
## [member carry_on] is off (tests: every picture a rollback).
func _goes_on(rink: MwRink, m: MwNetMatch, from: int, ends: PackedInt32Array) -> bool:
	if not carry_on or _at < 0 or sim == null or _root != rink.state:
		return false
	if from < _base or from > _at or not _marks.has(from):
		return false
	if int(_marks[from]) != _mark(rink.state, rink.phases):
		stats["unlike"] += 1
		return false
	for b: int in _marks:
		if b > from and b <= _at and not ends.has(b):
			return false
	for k in range(maxi(_known + 1, _base), _at + 1):
		var ti := _feed.at(k)
		var now := m.input_at(k)
		if ti == now and ti != null:
			continue                           # (plan 42: the very tick fed - MwNetMatch.input_at's own)
		if ti == null or not ti.equals(now):
			stats["mispredicted"] += 1
			if ti != null and now != null:
				var a: PackedByteArray = ti.states()[1]
				var b: PackedByteArray = now.states()[1]
				for n in range(1, MwTickInput.PLAYERS + 1):
					if MwNetInput.player(a, n) != MwNetInput.player(b, n):
						stats["mis_own" if m.local_states().has(n) else "mis_other"] += 1
			return false
	# the confirmed state is at a pass of the shadow's: the ones before let go
	for b: int in _marks.keys():
		if b < from:
			_marks.erase(b)
	return true


## A cheap likeness of a rink state after a pass (not its hash: the
## positions and velocities of everything that moves, the random stream,
## the clock, the phase, the pause) - the confirmed state's at a pass's end
## against the shadow's at the same end.
static func _mark(s: MwRinkState, ph: MwRinkPhases) -> int:
	var a := [s.rng.state if s.rng != null else 0, s.tick, s.phase, s.clock, ph.paused, ph.goal_song,
			s.puck.motion.pos, s.puck.motion.vel, s.puck.flags]
	for team in s.teams:
		for p in team.players:
			if p.present:
				a.append(p.motion.pos)
				a.append(p.motion.vel)
	return hash(a)


## The confirmed game's presentation-only models lent to the shadow for
## its picture (the crowd, the benches, the paint), and taken back.
func lend(confirmed: MwRinkState) -> void:
	shadow.crowd_life = confirmed.crowd_life
	shadow.bench_life = confirmed.bench_life
	shadow.splatter = confirmed.splatter


## [method lend]'s models taken back from the shadow (it holds none after).
func take_back() -> void:
	shadow.crowd_life = null
	shadow.bench_life = null
	shadow.splatter = null


## Plan 45 (docs/style.md D8): models [method lend] left in the shadow - the
## picture between it and [method take_back] stopped by a script error -
## taken back before the shadow runs a pass (its passes would step the
## confirmed match's crowd, whose life is hashed: a desync). True when
## something was left.
func take_back_left() -> bool:
	if shadow.crowd_life == null and shadow.bench_life == null and shadow.splatter == null:
		return false
	push_error("MwNetRunAhead: the match's models were left lent to the shadow - taken back")
	take_back()
	return true


## The shadow's own sim, update and phase handler, the scene's drawer:
## made after the copy, and made again when it made objects new ([param
## anew]) - the sim's parts keep the state's own (its puck, its replay
## ring), a copy's new object one they'd never see.
func _ensure(rink: MwRink, anew: bool) -> void:
	if sim == null or anew:
		stats["stacks"] += 1
		if sim != null:
			sim.dispose()                    # plan 45: the old stack let go of (its cycle)
		sim = MwRinkSim.new(rink.sim.rom, shadow)
		sim.cpu = MwRinkAI.new()
		update = MwRinkUpdate.new(sim)
		phases = MwRinkPhases.new(update)
	if audio == null and own_audio and MwSound.driver != null and MwRom.available():
		audio = MwAudio.new()
		audio.name = "RunAheadSound"
		audio.setup(MwRom.data(), false, false)
	update.drawer = rink.drawer


## The phase handler's own fields (beside the state): its pause, its menu,
## the goal song's handle, its voices and serial; the port's rules.
func _copy_phases(confirmed: MwRinkPhases) -> void:
	phases.paused = confirmed.paused
	phases.online = confirmed.online
	phases.port_menu = confirmed.port_menu
	phases.menu = confirmed.menu.duplicate(true)
	phases.goal_song = confirmed.goal_song
	phases.set("_voice_end", (confirmed.get("_voice_end") as Dictionary).duplicate(true))
	phases.set("_serial", confirmed.get("_serial"))


## The next pass's input as the router samples it after a pass (its
## [code]_sample[/code]): [frame, the actions held].
static func _sample(si: MwStreamInput, contexts: Array, last_held: Dictionary, remaps: bool,
		session: MwSession) -> Array:
	var held := si.sample(contexts)
	var taps := si.taps()
	var sticks := si.sticks()
	var heights := si.heights()
	if remaps and session != null:
		var rm := MwHumans.remapped(session.pad_map, held, taps, sticks, heights)
		held = rm[0]
		taps = rm[1]
		sticks = rm[2]
		heights = rm[3]
	var input := MwInputFrame.make(held, last_held)
	input.pressed.merge(taps)
	input.sticks = sticks
	input.heights = heights
	input.away = si.away()
	input.tick = si.tick_input()
	if remaps and session != null:
		input.pad_map = session.pad_map
	return [input, held]
