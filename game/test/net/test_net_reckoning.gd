extends "res://test/net/net_test_base.gd"
## Plan 35 work item 5: dead reckoning (MwNetReckoning) - a client's rink
## drawn "now".
##
## * On a match state (no network): the lead's motion steps, a carried puck
##   with its carrier, the boards; the corrections - the error halved every
##   2 ticks, whole pixels in 2D, sub-pixel points in 3D, snaps beyond 24 px
##   and on jumps; this machine's skater steered by its held direction at
##   once; everything put back after the draw, and the pass's own list made
##   again exactly when nothing moves.
## * The rink scene with a stand-in match (offline routers, the same game
##   twice): the picture drawn "now", the game itself untouched pass for
##   pass, the debug switch; an offline rink has none.
## * Online (net_machines.gd: a host and clients on the loopback): a client
##   with dead reckoning and one without run the same game - every hash,
##   sound call and screen the same, each the host's; the drawn error
##   against the host's true positions at 50, 100 and 200 ms one-way, with
##   and without (printed).
## Short names: d the MwRinkDraw3D under test.

const Machines := preload("res://test/net/net_machines.gd")
const Bots := preload("res://test/support/bots.gd")

const RIGHT := 0x08
const LEFT := 0x04

var sim: MwRinkSim
var update: MwRinkUpdate
var phases: MwRinkPhases
var _host_node: Node


## The match and its passes (plan 40: test/support/rink_rig.gd).
const RinkRig := preload("res://test/support/rink_rig.gd")

var rig: RinkRig


## An online match as the reckoning reads it, without a network: the lead
## and this machine's players' states set by the test.
class StubMatch extends MwNetMatch:
	var lead_ticks := 12
	var states := {}

	func host_lead() -> int:
		return lead_ticks

	func local_states() -> Dictionary:
		return states


## Every test plays a game: pending without the ROM (plan 40's B4). Untyped
## like GutTest's.
func should_skip_script():
	return rom_or_skip()


## Plan 41: these tests are dead reckoning's own - the run-ahead (which
## draws through it first) is test_net_run_ahead's.
func before_each() -> void:
	super.before_each()
	MwNetRunAhead.enabled = false


func after_each() -> void:
	MwNetRunAhead.enabled = true
	MwNetReckoning.enabled = true
	MwSound.trace = Callable()
	if _host_node != null:
		_host_node.free()
		_host_node = null
	await wait_process_frames(1)               # the screens the routers let go


# --- a match state ---------------------------------------------------------------------------------

## P1 (pad 0, team A) v the CPU, lined up and played until the puck is in play.
func _match() -> MwRinkState:
	rig = RinkRig.new()
	var s := rig.make(MwRom.data())
	sim = rig.sim
	update = rig.update
	phases = rig.phases
	rig.enter(5)
	for i in 400:
		if s.phase == MwRinkState.PHASE_PLAY:
			break
		_play_pass()
	assert_eq(s.phase, MwRinkState.PHASE_PLAY, "the puck in play")
	return s


## One pass of 2 ticks (pad 0 holding [param held]) with its draw.
func _play_pass(held := 0) -> void:
	rig.run(1, RinkRig.held(sim.s, 0, held, 0))


func _human(s: MwRinkState) -> MwRinkState.Player:
	for p in s.teams[0].players:
		if p.present and p.flags & MwRinkState.Player.HUMAN:
			return p
	return null


## A present CPU skater of team B (not the goalie), and its actor key.
func _cpu(s: MwRinkState) -> Array:
	for i in 5:
		var p := s.teams[1].players[i]
		if p.present:
			return [p, "t1.p%d" % i]
	return []


## [param p] standing at ([param x], [param y]).
static func _stand(p: MwRinkState.Player, x: int, y: int) -> void:
	p.motion.init(x, y, 0)
	p.target_x = x
	p.target_y = y


func test_lead_zero_draws_the_confirmed_state_and_the_pass_list_again() -> void:
	var s := _match()
	_play_pass()
	var before := MwNetHash.rink(s)
	var rk := MwNetReckoning.new()
	rk.place(s, sim, 100, 0, {}, true)
	for key: String in rk.last:
		if key != "camera":
			assert_eq(rk.last[key]["drawn"], rk.last[key]["confirmed"], "%s where the state has it" % key)
	assert_eq(rk.last["camera"]["drawn"], rk.last["camera"]["confirmed"], "the camera too")
	var d := MwRinkDraw3D.new(MwRom.data())
	assert_eq(update.redraw(d), update.sprites, "the pass's own sprite list made again")
	rk.restore(s)
	assert_eq(MwNetHash.rink(s), before, "the state as it was")


func test_the_lead_is_the_motion_step_and_a_carried_puck_goes_along() -> void:
	var s := _match()
	var cpu: Array = _cpu(s)
	var p: MwRinkState.Player = cpu[0]
	_stand(p, -40, 100)
	p.motion.vel = PackedInt32Array([0x300, -0x180, 0])
	p.motion.acc = PackedInt32Array([-0x10, 0, 0])
	var pk := s.puck
	pk.flags &= ~MwRinkState.Puck.CARRIED
	pk.motion.init(150, 0, 0)
	pk.motion.vel = PackedInt32Array([0x800, 0, 0])          # 8 px a tick towards the boards (x 185)
	var motion := p.motion.copy()
	for i in 5:
		motion.step(s.player_params, 2)
	var rk := MwNetReckoning.new()
	rk.place(s, sim, 100, 10, {}, false)
	assert_eq(rk.last[cpu[1]]["drawn"], motion.pixels(), "five passes of the motion step")
	assert_eq(rk.last["puck"]["drawn"].x, MwNetReckoning.BOARD.x, "a loose puck stops at the boards")
	rk.restore(s)
	# carried: the puck moves as its carrier does
	var player := _human(s)
	_stand(player, 0, 0)
	player.motion.vel = PackedInt32Array([0x200, 0x100, 0])
	pk.flags |= MwRinkState.Puck.CARRIED
	pk.carrier = player
	pk.motion.init(12, 3, 0)
	rk.place(s, sim, 200, 8, {}, false)
	var hd: Vector3i = rk.last["t0.p%d" % s.teams[0].players.find(player)]["drawn"]
	assert_ne(hd, Vector3i.ZERO, "the carrier moved on")
	assert_eq(rk.last["puck"]["drawn"], hd + Vector3i(12, 3, 0), "the puck with him")
	rk.restore(s)


## Plan 36: with TICK RATE APPROXIMATED the rink's passes are its pacer's
## (MwPassPacer), so the lead's predicted steps are the passes the pacer
## would make (MwPassPacer.predict) from the pass that left the confirmed
## state - not OVERCLOCKED's 2 ticks; the pacer itself untouched.
func test_paced_passes_are_the_predicted_steps() -> void:
	var s := _match()
	var cpu: Array = _cpu(s)
	var p: MwRinkState.Player = cpu[0]
	_stand(p, -40, 100)
	p.motion.vel = PackedInt32Array([0x300, -0x180, 0])
	p.motion.acc = PackedInt32Array([-0x10, 0, 0])
	var f := MwPassCost.FRAME_MCLK
	var w := {"before": f * 13 / 10, "rink_update": f / 20, "after": f * 11 / 10, "rows_words": 0, "words": 200}
	var pacer := MwPassPacer.new()
	while not pacer.vblank():
		pass
	pacer.begin(w)
	pacer.vblank()                               # a tick into the pass: the state a tick old
	var before := pacer.snapshot()
	var motion := p.motion.copy()
	var rk := MwNetReckoning.new()
	rk.pacer = pacer
	rk.pacer_work = w
	rk.place(s, sim, 100, 12, {}, false)
	var steps := pacer.predict(12, w)
	assert_eq(rk.last_steps, steps, "the pacer's passes")
	assert_eq(pacer.snapshot(), before, "the pacer untouched")
	assert_true(3 in steps or 4 in steps, "paced as the original, not every 2: %s" % str(steps))
	var total := 0
	for e in steps:
		motion.step(s.player_params, e)
		total += e
	assert_between(total - pacer.since_pass(), 12 - 9, 12, "up to the host's latest pass")
	assert_eq(rk.last[cpu[1]]["drawn"], motion.pixels(), "the motion step pass by pass")
	rk.restore(s)
	rk.pacer = null
	rk.place(s, sim, 200, 12, {}, false)
	assert_eq(rk.last_steps, PackedInt32Array([2, 2, 2, 2, 2, 2]), "OVERCLOCKED: passes of 2 ticks")
	rk.restore(s)


func test_corrections_halve_every_two_ticks_in_whole_pixels() -> void:
	var s := _match()
	var cpu: Array = _cpu(s)
	var p: MwRinkState.Player = cpu[0]
	var key: String = cpu[1]
	_stand(p, 20, 50)
	var rk := MwNetReckoning.new()
	rk.place(s, sim, 100, 0, {}, true)
	rk.restore(s)
	assert_eq(rk.last[key]["drawn"], Vector3i(20, 50, 0))
	p.motion.pos[0] += 10 * 256                 # the host says: 10 px further on
	var want := [25.0, 27.5, 28.75]
	var t := 100
	for x: float in want:
		t += 2
		rk.place(s, sim, t, 0, {}, true)
		rk.restore(s)
		assert_almost_eq((rk.last[key]["at"] as Vector3).x, x, 0.001, "half the error left after 2 ticks")
		assert_eq(rk.last[key]["drawn"].x, floori(x), "2D: the eased point's whole pixel")
	t += 4
	rk.place(s, sim, t, 0, {}, true)
	rk.restore(s)
	assert_almost_eq((rk.last[key]["at"] as Vector3).x, 30.0 - 1.25 / 4.0, 0.001, "a quarter after 4 ticks")
	assert_eq(MwNetHash.rink(s), MwNetHash.rink(s), "")


func test_snaps_beyond_24_px_and_on_jumps() -> void:
	var s := _match()
	var cpu: Array = _cpu(s)
	var p: MwRinkState.Player = cpu[0]
	var key: String = cpu[1]
	_stand(p, 0, 0)
	var rk := MwNetReckoning.new()
	var t := [100]
	var draw := func(continuous := true) -> float:
		t[0] += 2
		rk.place(s, sim, t[0], 0, {}, continuous)
		rk.restore(s)
		return (rk.last[key]["at"] as Vector3).x
	draw.call()
	p.motion.pos[0] += 20 * 256
	assert_almost_eq(draw.call(), 10.0, 0.001, "20 px: eased")
	p.motion.pos[0] += 30 * 256
	var snaps := int(rk.stats["snapped"])
	assert_eq(draw.call(), 50.0, "beyond 24 px: snapped")
	assert_eq(int(rk.stats["snapped"]), snaps + 1)
	p.motion.pos[0] += 10 * 256
	assert_eq(draw.call(false), 60.0, "a picture that doesn't follow the last (an entry, a view switched): snapped")
	p.motion.pos[0] += 10 * 256
	s.phase = MwRinkState.PHASE_FACEOFF
	var jumps := int(rk.stats["jumps"])
	assert_eq(draw.call(), 70.0, "the faceoff line-up: snapped")
	assert_eq(int(rk.stats["jumps"]), jumps + 1)
	p.motion.pos[0] += 10 * 256
	p.record = s.teams[1].players[(s.teams[1].players.find(p) + 1) % 5].record
	assert_eq(draw.call(), 80.0, "another player in the slot: snapped")
	s.phase = MwRinkState.PHASE_PLAY


func test_this_machines_skater_follows_its_held_direction_at_once() -> void:
	var s := _match()
	var player := _human(s)
	var key := "t0.p%d" % s.teams[0].players.find(player)
	_stand(player, 0, 100)
	player.state = 0
	var before := MwNetHash.rink(s)
	var x := {}
	var y := {}
	for held: int in [0, RIGHT, LEFT]:
		var rk := MwNetReckoning.new()
		rk.place(s, sim, 100, 12, {0: [held, Vector2i.ZERO]} if held != 0 else {}, true)
		x[held] = int(rk.last[key]["drawn"].x)
		assert_eq(bool(rk.last[key]["steered"]), held != 0)
		rk.restore(s)
	assert_eq(x[0], 0, "nothing held: where the confirmed state has him")
	assert_gt(x[RIGHT], 0, "right held: drawn on the right at once (%d px in 12 ticks from a stand)" % x[RIGHT])
	assert_lt(x[LEFT], 0, "left held: on the left (%d)" % x[LEFT])
	var rk2 := MwNetReckoning.new()
	rk2.place(s, sim, 100, 12, {0: [0, Vector2i(0, 256)]}, true)
	assert_gt(int(rk2.last[key]["drawn"].y), 100, "a stick held down: drawn lower")
	rk2.restore(s)
	assert_eq(MwNetHash.rink(s), before, "the confirmed skater untouched")


func test_the_draw_puts_everything_back() -> void:
	var s := _match()
	for i in 20:
		_play_pass(RIGHT)
	var before := MwNetHash.rink(s)
	var rk := MwNetReckoning.new()
	var d := MwRinkDraw3D.new(MwRom.data())
	for three: bool in [false, true]:
		rk.place(s, sim, 300, 15, {0: [LEFT, Vector2i.ZERO]}, false, three)
		assert_ne(MwNetHash.rink(s), before, "the drawn positions in for the draw")
		update.redraw(d)
		rk.restore(s)
		assert_eq(MwNetHash.rink(s), before, "and the confirmed state back (3D: %s)" % three)


## Plan 45 (D8): a draw stopped between the swap and its restore (a script
## error) - the rink's next pass or picture puts the confirmed state back;
## a restore given another state puts back the one swapped into.
func test_a_swap_no_restore_closed_is_put_back() -> void:
	var s := _match()
	for i in 20:
		_play_pass(RIGHT)
	var before := MwNetHash.rink(s)
	var rk := MwNetReckoning.new()
	assert_false(rk.restore_left(), "nothing swapped")
	rk.place(s, sim, 300, 15, {0: [LEFT, Vector2i.ZERO]}, false)
	assert_ne(MwNetHash.rink(s), before, "the drawn positions in")
	assert_true(rk.restore_left(), "left in: found")
	assert_push_error("eased positions were left")
	assert_eq(MwNetHash.rink(s), before, "the confirmed state back")
	assert_false(rk.restore_left(), "once")
	rk.place(s, sim, 300, 15, {0: [LEFT, Vector2i.ZERO]}, false)
	rk.restore(MwRinkState.new())
	assert_push_error("not the state swapped into")
	assert_eq(MwNetHash.rink(s), before, "put back into the state it was swapped into")


func test_3d_draws_sub_pixel_points() -> void:
	var s := _match()
	var cpu: Array = _cpu(s)
	var p: MwRinkState.Player = cpu[0]
	_stand(p, 10, -30)
	p.motion.pos[0] += 128                      # 10.5 px
	var rk := MwNetReckoning.new()
	rk.place(s, sim, 100, 0, {}, true, true)
	var d := MwRinkDraw3D.new(MwRom.data())
	update.redraw(d)
	rk.shift_items(d.items)
	rk.restore(s)
	var subject := "%s.%X/body" % [cpu[1], p.record]
	var found := false
	for it: Dictionary in d.items:
		if it["key"] == subject:
			found = true
			assert_almost_eq((it["at"] as Vector3).x, 10.5, 0.001, "its point, sub-pixel")
	assert_true(found, "the body drawn")


# --- the rink scene ----------------------------------------------------------------------------------

func _router(session: MwSession) -> MwRouter:
	if _host_node == null:
		_host_node = Node.new()
		add_child(_host_node)
	var holder := Node.new()
	_host_node.add_child(holder)
	var fader := MwScreenFader.new()
	holder.add_child(fader)
	var router := MwRouter.new(holder, fader)
	router.session = session
	return router


static func _session() -> MwSession:
	var session := MwSession.new(5, 6)
	session.setup.team_a = 3
	session.setup.team_b = 7
	session.setup.stadium = 3
	return session


## A move held (wire state) for the stand-in's local player 1.
static func _holding(bits: int) -> PackedByteArray:
	var st := MwNetInput.blank()
	st[0] = bits
	return st


func test_the_rink_draws_now_and_the_game_is_untouched() -> void:
	var online := _router(_session())
	var router := _router(_session())
	var stand_in := StubMatch.new()
	stand_in.router = online
	online.session.reckoning = MwNetReckoning.new(stand_in)
	online.go(5, {}, false)
	router.go(5, {}, false)
	stand_in.states = {1: _holding(RIGHT)}         # P1 holds right on this machine only
	var moved := 0
	var steered := 0
	var differs := 0
	var offline_own := 0
	for i in 900:
		online.step()
		router.step()
		var ra := online.current() as MwRink
		var rb := router.current() as MwRink
		if ra == null or rb == null:
			break                                  # the rink left (a fight)
		assert_eq(MwNetHash.rink(ra.state), MwNetHash.rink(rb.state), "tick %d: the same game" % online.tick)
		if i == 600:
			MwNetReckoning.enabled = false         # the debug switch
		if rb._reckoning() != null or (rb.update.can_redraw() and rb._drawn()[0] != rb.update.sprites):
			offline_own += 1                       # offline: the pass's own list, always
		var rk := online.session.reckoning
		if rk.last_tick != online.tick:
			continue
		for key: String in rk.last:
			if key != "camera" and rk.last[key]["drawn"] != rk.last[key]["confirmed"]:
				moved += 1
				if rk.last[key]["steered"]:
					steered += 1
		if ra.drawer.sprites() != ra.update.sprites:
			differs += 1                           # the picture shown: the reckoning's own draw
	gut.p("the rink with a stand-in match: %s, %d actors drawn ahead (%d steered), %d pictures of its own" % [
			str(online.session.reckoning.stats), moved, steered, differs])
	assert_gt(int(online.session.reckoning.stats["presents"]), 100, "the rink drew through the reckoning")
	assert_gt(moved, 100, "actors drawn ahead of the confirmed state")
	assert_gt(steered, 20, "P1's skater drawn where P1 holds him (the game never saw it)")
	assert_gt(differs, 50, "a picture of its own")
	assert_eq(offline_own, 0, "offline: the pass's own list every time")
	assert_null(router.session.reckoning, "offline: none")
	var n := int(online.session.reckoning.stats["presents"])
	for i in 60:
		online.step()
	assert_eq(int(online.session.reckoning.stats["presents"]), n, "switched off: the confirmed state as it is")


func test_f9_and_f10_flip_the_switches_online_in_a_debug_build() -> void:
	var router := _router(_session())
	router.go(5, {}, false)
	for i in 4:
		router.step()
	var ra := router.current() as MwRink
	var f9 := InputEventKey.new()
	f9.keycode = KEY_F9
	f9.pressed = true
	var f10 := InputEventKey.new()
	f10.keycode = KEY_F10
	f10.pressed = true
	assert_false(ra._reckoning_key(f9, KEY_F9), "offline: no switch")
	router.session.online = {"players": [1], "machines": {"1": 1}}
	assert_eq(ra._reckoning_key(f9, KEY_F9), OS.is_debug_build(), "online: F9 (a debug build)")
	assert_false(ra._reckoning_key(f9, KEY_F10), "F9 isn't F10")
	if OS.is_debug_build():
		ra._unhandled_input(f9)
		assert_false(MwNetReckoning.enabled, "off")
		ra._unhandled_input(f9)
		assert_true(MwNetReckoning.enabled, "on again")
		# plan 41: F10, the run-ahead's
		var was := MwNetRunAhead.enabled
		ra._unhandled_input(f10)
		assert_ne(MwNetRunAhead.enabled, was, "F10: the run-ahead switched")
		ra._unhandled_input(f10)
		assert_eq(MwNetRunAhead.enabled, was, "and back")
	router.session.online = {}


func test_the_3d_view_draws_now_at_sub_pixel_points() -> void:
	var online := _router(_session())
	var router := _router(_session())
	online.session.view = MwRinkViews.FOLLOW
	var stand_in := StubMatch.new()
	stand_in.router = online
	stand_in.states = {1: _holding(LEFT)}
	online.session.reckoning = MwNetReckoning.new(stand_in)
	online.go(5, {}, false)
	router.go(5, {}, false)
	var view := MwRink3DHost.of(get_tree()).view()
	var fractional := 0
	var shown := 0
	for i in 700:
		online.step()
		router.step()
		var ra := online.current() as MwRink
		var rb := router.current() as MwRink
		if ra == null or rb == null:
			break
		assert_eq(MwNetHash.rink(ra.state), MwNetHash.rink(rb.state), "tick %d: the same game in 3D" % online.tick)
		if online.session.reckoning.last_tick != online.tick or not MwRink3DHost.of(get_tree()).shown_for(ra):
			continue
		shown += 1
		view.blend_to(0.5, 1.0 / 60.0)            # a rendered frame between passes
		for it: Dictionary in view._items:
			var at: Vector3 = it["at"]
			if String(it["key"]).ends_with("/body") and String(it["key"]).begins_with("t") \
					and (at.x != floorf(at.x) or at.y != floorf(at.y)):
				fractional += 1
	assert_gt(shown, 100, "the 3D view drew through the reckoning")
	assert_gt(fractional, 100, "players at sub-pixel points")


# --- online ------------------------------------------------------------------------------------------

## A start record from the matchup (fixed seeds: the same game every run):
## [param teams] (number -> team), each team's first player its captain.
static func _record(w: Machines, teams: Dictionary, seed_value: int) -> Dictionary:
	var host_session := MwSession.from_record(MwNetMatch.host_record(MwSession.new(11, 12), w.host.lobby))
	var session := MwSession.new(seed_value, seed_value + 1)
	for k in ["setup", "local_mode", "after_selection", "online", "rules", "layouts"]:
		session.set(k, host_session.get(k))
	var caps := []
	for t in 2:
		for p: int in teams:
			if int(teams[p]) == t:
				caps.append(p)
				break
	for p: int in teams:
		session.humans.set_team(p, int(teams[p]))
	session.humans.captains = caps
	session.humans.apply_to(session.setup)
	session.pad_map = session.humans.pad_players(MwRom.data())
	return session.to_record(3, 0)


## A host (P1) and clients ([param client_locals]) under [param conditions],
## gameplay bots on every player, started from the matchup; every machine
## on the rink.
func _world(seed_value: int, conditions: Dictionary, client_locals: Array, teams: Dictionary) -> Machines:
	var w := Machines.new(self, seed_value, conditions, client_locals)
	for peer in w.machines:
		peer.bot.expected = teams.size()
		for p in peer.bot.players:
			peer.bot.teams[p] = teams[p]
			peer.bot.game_bots[p] = Bots.GameBot.new(p, seed_value)
	w.start(_record(w, teams, seed_value))
	var on_rink := func() -> bool:
		for machine in w.machines:
			if machine.router.current_id() not in [4, 5, 6]:
				return false
		return true
	assert_true(w.run_until(on_rink, 6000), "every machine on the rink")
	return w


func test_online_the_picture_alone_changes() -> void:
	var w := _world(41, {"delay": 100, "jitter": 10, "loss": 0.05}, [1, 1], {1: 0, 2: 1, 3: 1})
	var on := w.machines[1]
	var off := w.machines[2]
	off.net_match.reckoning.on = false
	assert_null(w.machines[0].net_match.reckoning, "the host draws its own game")
	assert_null(w.machines[0].session.reckoning)
	var by_driver := {}
	var sounds := {on.id: [], off.id: []}
	var screens := {on.id: [], off.id: []}
	for m in [on, off]:
		by_driver[m._statics["driver"]] = m
		var mm: Machines.Machine = m
		m.router.screen_entered.connect(func(id: int, _v: int, tick: int, _p: int) -> void:
			(screens[mm.id] as Array).append([mm.net_match.stream_tick(tick), id]))
	MwSound.trace = func(fn: String, args: Array, result: Variant) -> void:
		var m: Machines.Machine = by_driver.get(MwSound.driver)
		if m != null and m.net_match != null:
			(sounds[m.id] as Array).append([m.net_match.stream_tick(m.router.tick), fn, str(args), str(result)])
	var moved := 0
	var seen := -1
	for i in 700:
		w.frame()
		var on_reckoning := on.net_match.reckoning
		if on_reckoning.last_tick != seen:
			seen = on_reckoning.last_tick
			for key: String in on_reckoning.last:
				if key != "camera" and on_reckoning.last[key]["drawn"] != on_reckoning.last[key]["confirmed"]:
					moved += 1
	MwSound.trace = Callable()
	var c := w.compare_hashes()
	assert_true(c["ok"], "every client's hash the host's - %s" % c["why"])
	assert_gt(int(c["compared"]), 400, "hashes compared")
	for m in [on, off]:
		assert_eq(m.net_match.mismatches.size(), 0, "%s found no mismatch" % m.name)
	# on and off: the same game, the same events
	var ha := {}
	for on_hash: Array in on.net_match.hashes:
		ha[int(on_hash[0]) * 4 + int(on_hash[1])] = on_hash
	var same := 0
	for off_hash: Array in off.net_match.hashes:
		var k := int(off_hash[0]) * 4 + int(off_hash[1])
		if ha.has(k):
			assert_eq(ha[k], off_hash, "the same hash with and without")
			same += 1
	assert_gt(same, 250, "hashes of both compared")
	var upto := mini(on.net_match.stream_tick(on.router.tick), off.net_match.stream_tick(off.router.tick))
	var cut := func(a: Array) -> Array: return a.filter(func(x: Array) -> bool: return int(x[0]) <= upto)
	var sa: Array = cut.call(sounds[on.id])
	assert_gt(sa.size(), 50, "sound calls made")
	assert_eq(sa, cut.call(sounds[off.id]), "the same sound calls at the same ticks")
	assert_eq(cut.call(screens[on.id]), cut.call(screens[off.id]), "the same screens at the same ticks")
	var rk := on.net_match.reckoning
	assert_gt(int(rk.stats["presents"]), 250, "the client with it drew through it")
	assert_gt(int(rk.stats["steered"]), 100, "its player's skater steered")
	assert_gt(moved, 500, "actors drawn ahead")
	var entries := 0
	for id in [4, 5, 6]:
		entries += int(on.bot.visits.get(id, 0))
	assert_gte(int(rk.stats["jumps"]), entries, "every rink entry snapped (%d entries)" % entries)
	assert_eq(int(off.net_match.reckoning.stats["presents"]), 0, "the client without it drew its confirmed state")
	gut.p("on / off: %d hashes the same, %d sound calls the same, %d rink entries; %s" % [same, sa.size(), entries,
			str(rk.stats)])
	w.free_all()


## Plan 36 online: the host's TICK RATE ORIGINAL plays as APPROXIMATED; a
## client with dead reckoning and one without: every hash the host's (the
## pacer's state in them, MwRinkState.pace), and the reckoning's predicted
## steps the rink pacer's passes (MwPassPacer.predict), not 2 ticks each.
func test_online_paced_passes_predicted_alike() -> void:
	var was := MwSettings.tick_rate
	MwSettings.tick_rate = "ORIGINAL"
	var w := _world(45, {"delay": 100, "jitter": 10, "loss": 0.05}, [1, 1], {1: 0, 2: 1, 3: 1})
	var on := w.machines[1]
	var off := w.machines[2]
	off.net_match.reckoning.on = false
	var paced := 0
	var odd := 0
	var seen := -1
	for i in 600:
		w.frame()
		var rk := on.net_match.reckoning
		if rk.last_tick != seen and rk.pacer != null:
			seen = rk.last_tick
			paced += 1
			for e in rk.last_steps:
				if e != 2:
					odd += 1
					break
	var c := w.compare_hashes()
	assert_true(c["ok"], "every client's hash the host's - %s" % c["why"])
	assert_gt(int(c["compared"]), 300, "hashes compared")
	for m in [on, off]:
		assert_eq(m.net_match.mismatches.size(), 0, "%s found no mismatch" % m.name)
	var state: MwRinkState = w.machines[0].rink()
	assert_false(state.pace.is_empty(), "the pacer's state in the rink's hash")
	assert_gt(paced, 100, "pictures predicted through the pacer")
	assert_gt(odd, paced / 4, "passes of other lengths than 2 (%d of %d)" % [odd, paced])
	gut.p("paced: %d hashes compared, %d pictures through the pacer, %d with passes not of 2 ticks" % [
			c["compared"], paced, odd])
	w.free_all()
	MwSettings.tick_rate = was


## The drawn error against the host's true positions (px) on one client
## ([param delay] ms one-way, 10 ms jitter, [param frames] frames on the
## rink, the game of [param seed_value]): with dead reckoning (what it drew)
## and without (its confirmed state), every picture both machines show in
## play - players, this machine's skater, the puck - and the players'
## second difference a picture (drawn, confirmed, the host's own: how
## smoothly they move).
func _measure(delay: int, frames: int, seed_value := 42) -> Dictionary:
	var w := _world(seed_value, {"delay": delay, "jitter": 10}, [1], {1: 0, 2: 1})
	var host_machine := w.machines[0]
	var machine := w.machines[1]
	var out := {"players": [[], []], "local": [[], []], "puck": [[], []], "lead": [], "jerk": [[], [], []]}
	var hist := {}           # actor key -> the last two pictures' [tick, drawn, confirmed, the host's]
	var seen := -1
	for i in frames:
		w.frame()
		var rk := machine.net_match.reckoning
		if rk.last_tick == seen or rk.last_tick != machine.router.tick - (machine.router.tick - rk.last_tick):
			continue
		seen = rk.last_tick
		var hs := host_machine.rink()
		var cs := machine.rink()
		if host_machine.router.current_id() not in [4, 5, 6] or machine.router.current_id() not in [4, 5, 6] \
				or hs == null \
				or cs == null or hs.phase != MwRinkState.PHASE_PLAY or cs.phase != MwRinkState.PHASE_PLAY:
			continue
		(out["lead"] as Array).append(host_machine.router.tick - (rk.last_tick + rk.last_lead))
		for key: String in rk.last:
			if key == "camera":
				continue
			var picture: Dictionary = rk.last[key]
			var actor: MwRinkState.Actor = hs.puck
			if key != "puck":
				var ti := int(key.substr(1, 1))
				var pi := int(key.substr(4))
				actor = hs.teams[ti].players[pi]
				if (actor as MwRinkState.Player).record != cs.teams[ti].players[pi].record:
					continue
			elif hs.puck.flags & MwRinkState.Puck.HIDDEN:
				continue
			var at := Vector3(actor.motion.pixels())
			var which := "puck" if key == "puck" else ("local" if picture["steered"] else "players")
			(out[which][0] as Array).append((Vector3(picture["drawn"]) - at).length())
			(out[which][1] as Array).append((Vector3(picture["confirmed"]) - at).length())
			# smoothness: each picture's second difference, drawn / confirmed / the host's own
			var now := [rk.last_tick, Vector3(picture["drawn"]), Vector3(picture["confirmed"]), at]
			var hk: Array = hist.get(key, [])
			if key != "puck" and hk.size() == 2 and int(hk[1][0]) == rk.last_tick - 2 \
					and int(hk[0][0]) == rk.last_tick - 4:
				for j in 3:
					(out["jerk"][j] as Array).append((now[j + 1] - 2 * hk[1][j + 1] + hk[0][j + 1]).length())
			hk.append(now)
			if hk.size() > 2:
				hk.pop_front()
			hist[key] = hk
	assert_true(w.compare_hashes()["ok"], "%d ms: every hash the host's" % delay)
	w.free_all()
	return out


func test_drawn_error_against_the_host() -> void:
	gut.p("drawn error against the host (px): mean / 95th percentile, with dead reckoning | without")
	for delay: int in [50, 100, 200]:
		var r := _measure(delay, 600)
		var line := "%3d ms one-way:" % delay
		for which: String in ["players", "local", "puck"]:
			var on: Array = r[which][0]
			var off: Array = r[which][1]
			line += "  %s %.1f / %.1f | %.1f / %.1f (n %d)" \
					% [which, _mean(on), _p95(on), _mean(off), _p95(off), on.size()]
			if which != "local":
				assert_lt(_mean(on), _mean(off), "%d ms, %s: nearer the host with it" % [delay, which])
		gut.p(line + "  lead off by %.2f ticks (mean)" % _mean(r["lead"]))
		var jerk: Array = r["jerk"]
		gut.p(("        players' second difference a picture (px): drawn %.2f, confirmed %.2f, the host's own %.2f (n "
				+ "%d)") % [
				_mean(jerk[0]), _mean(jerk[1]), _mean(jerk[2]), (jerk[0] as Array).size()])
		assert_gt((r["players"][0] as Array).size(), 800, "%d ms: pictures measured" % delay)


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for x in a:
		t += float(x)
	return t / a.size()


static func _p95(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[mini(b.size() - 1, int(b.size() * 0.95))])


## Plan 40 (the survey's B2): a resync's snapshot never takes a client's dead
## reckoning away - the host's session has none (null), and the snapshot's
## codec leaves a machine's own fields alone (MwNetSnapshot.SESSION_OWN).
func test_a_resync_keeps_the_clients_reckoning() -> void:
	var host := MwSession.new(7, 1)
	var client := MwSession.new(7, 1)
	var rk := MwNetReckoning.new()
	client.reckoning = rk
	var graph := MwNetSnapshot.codec()
	var encoded: Variant = graph.encode(host)
	assert_true(graph.errors.is_empty(), str(graph.errors))
	assert_true(MwNetSnapshot.codec().decode_into(client, encoded), "taken up")
	assert_eq(client.reckoning, rk, "still the client's")
	assert_true("reckoning" in MwNetSnapshot.SESSION_OWN)
