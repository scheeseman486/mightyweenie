class_name MwNetReckoning
extends RefCounted
## Dead reckoning (plan 35 section 4, work item 5; docs/net.md "Dead
## reckoning (work item 5)"): a client's picture of the rink drawn "now".
## Node-free, presentation only: it reads the confirmed rink state and
## writes nothing of it but the drawn positions it swaps in for one draw
## ([method apply] ... [method restore]); no clock, no random numbers.
##
## A client's game runs [method MwNetMatch.host_lead] ticks behind the host
## (the ticks it holds beyond the one it runs - the buffer - plus the
## stream's one-way trip, half the measured round trip). Each time the rink
## draws, this:
##
## * **Predicts** every player on the ice and the puck that many ticks on
##   with the game's own motion step (MwMotion: velocity, acceleration,
##   friction, gravity; no collisions, no AI), in the game's passes of 2
##   ticks - or, with TICK RATE APPROXIMATED (plan 36: [member pacer]), the
##   passes the rink's pacer would make, from the pass that left the
##   confirmed state to the host's latest; a carried puck goes with its
##   carrier, a loose one stays inside
##   the boards; an impaled player stays put. **This machine's own driven
##   skaters** are steered by the direction their player holds now (the
##   D-pad bits or the stick in [MwNetMatch]'s latest states): the
##   original's target (`$17FC`, MwHumanControl.target) and skating step
##   (`$63D8`, MwSimPlayers.skate) on a copy of the skater, in a shadow
##   state of their own - so a player's input shows at once. The camera
##   (MwRinkCamera) follows its target's predicted path the same way; its
##   shake stays the confirmed state's.
## * **Corrects** when the confirmed state moves on: the previous estimate
##   carried on to now (its motion stepped) is compared with the new one;
##   the difference becomes an offset that halves every
##   [constant HALF_TICKS] ticks (2 frames at 60 Hz), or snaps away beyond
##   [constant SNAP_PX] px and on a jump: a screen entered or a view switched
##   ([param continuous] false), the faceoff line-up (the phase going to
##   the faceoff or a period's start), a new player in a slot, a pause.
## * **Draws** whole pixels in 2D (the eased point's pixel, as the original
##   takes `asr #8`) and smooth sub-pixel points in 3D ([method
##   shift_items]); the markers and their plates move with their players.
##
## Events - sounds, goals, whistles, screen changes, the crowd, the
## benches, a camera shake - all stay the confirmed state's: nothing here
## runs the game's rules on the real state, so nothing is ever undone. The
## debug switch [member enabled] (and per machine [member on]) turns it
## off: the client then draws its confirmed state as it is.

## The debug switch: off, every client draws its confirmed state as it is.
## `--no-reckoning` on the command line turns it off; F9 on the rink
## flips it in a debug build online (MwRink).
static var enabled := true
## Snap instead of easing beyond this many pixels.
const SNAP_PX := 24.0
## The offset halves every this many ticks (frames at 60 Hz).
const HALF_TICKS := 2.0
## Never predict further than this (ticks: a second).
const MAX_LEAD := 60
## The game's pass (ticks): the predicted steps (OVERCLOCKED's; plan 36's
## paced passes: [member pacer]).
const PASS_TICKS := MwPassClock.RINK_PASS_TICKS
## The lead follows the match's measure by this share a picture (the
## buffer's and the round trip's ups and downs smoothed: a tick more or
## less is a skater's 2-3 px).
const LEAD_SMOOTHING := 0.25
## The boards (rink px): a loose puck's prediction stays inside them.
const BOARD := Vector2i(0xB9, 0x174)

## This machine's switch (tests run machines with and without).
var on := true
## Counters: presents with a prediction, actors snapped (beyond
## [constant SNAP_PX]), whole pictures snapped (jumps), steered skaters.
var stats := {"presents": 0, "snapped": 0, "jumps": 0, "steered": 0}
## The last present: actor key ("t<team>.p<slot>", "puck") -> {confirmed:
## Vector3i px, drawn: Vector3i px as the 2D picture drew it, at: Vector3 px
## (the eased point, sub-pixel), steered: bool}; "camera" -> {confirmed:
## Vector2i, drawn: Vector2i}. For measurements.
var last := {}
## The router tick and the lead (ticks) of the last present.
var last_tick := -1
var last_lead := 0
## Plan 36: the rink's pass pacer while TICK RATE paces live play
## (APPROXIMATED; ORIGINAL plays as it online) and the latest pass's work
## ([method MwPassPacer.begin]'s) - set by the rink before each picture;
## null: the passes are OVERCLOCKED's [constant PASS_TICKS]. The predicted
## steps are then the passes the pacer would make ([method
## MwPassPacer.predict]): the state as its pass left it
## ([method MwPassPacer.since_pass] ago) to the latest pass the host has
## made by now - the picture the host itself shows.
var pacer: MwPassPacer = null
var pacer_work := {}
## The elapsed ticks of the last present's predicted passes (checks).
var last_steps := PackedInt32Array()

var _match: WeakRef = null
var _tracks := {}        # actor key -> Track
var _cam := {}           # the camera's track: {e: Vector2 estimate, v: per tick, o: offset}
var _at := -1            # the predicted tick of the last present
var _lead := 0.0         # the lead, smoothed
var _phase := -1
var _saved := {}         # what [method apply] swapped out ([method restore] puts it back)
var _frac := {}          # 3D: subject name -> the sub-pixel part of its drawn point
var _shadow: MwRinkState = null
## Plan 41 work item 2: the run-ahead the rink draws through first (a
## client's), this easing its picture ([method apply_ahead]).
var run_ahead: MwNetRunAhead = null
var _smooth := true          # place() smooths the lead (off: the run-ahead's remainder as it is)
var _shadow_sim: MwRinkSim = null


## One actor's correction: the estimate's motion at [member at] (its
## predicted tick) and the offset drawn on top of it.
class Track:
	var record := 0
	var motion: MwMotion
	var offset := Vector3.ZERO
	var at := 0
	var params: MwMotion.Params


## A client's reckoning, reading [param net_match] (weakly: the lead, the
## router's tick, this machine's players' latest states) when the rink
## draws. Null [param net_match] (tests): [method place] is called directly.
func _init(net_match: MwNetMatch = null) -> void:
	_match = weakref(net_match) if net_match != null else null
	if net_match != null:
		run_ahead = MwNetRunAhead.new(net_match)


## Plan 45: the shadow's sim disposed as the reckoning goes (its cycle would keep it).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _shadow_sim != null:
		_shadow_sim.dispose()


static func _static_init() -> void:
	if "--no-reckoning" in OS.get_cmdline_user_args():
		enabled = false


## On (the debug switch and this machine's).
func active() -> bool:
	return enabled and on


## The next picture snaps (a screen entered, a view switched: the rink
## draws one that doesn't follow the last).
func snap_next() -> void:
	_at = -1
	_cam = {}


## Before the rink draws [param s] (its simulation [param sim]): the drawn
## positions put in place of the confirmed ones (players, puck, markers,
## camera; this machine's steered skaters' facing and animation too) - for
## the draw only: [method restore] puts the confirmed state back. False
## (nothing swapped) when off, while the game stands still ([param still]:
## a pause; the next picture snaps), or without the match.
## [param continuous]: this picture follows the one drawn before (false: a
## screen entered, a view switched - snap). [param three]: the 3D view
## (sub-pixel points: [method shift_items]).
func apply(s: MwRinkState, sim: MwRinkSim, continuous: bool, three: bool, still := false) -> bool:
	var net_match: MwNetMatch = _match.get_ref() if _match != null else null
	if not active() or net_match == null or net_match.phase != MwNetMatch.Phase.PLAYING or s == null or sim == null:
		_tracks = {}
		snap_next()
		return false
	if still:
		snap_next()                      # the picture after the pause snaps
		return false
	place(s, sim, net_match.router.tick, net_match.host_lead(), steering(s, net_match.local_states()), continuous,
			three)
	return true


## Plan 41: after the run-ahead ([param s] its shadow, at router tick
## [param at]): the shadow's actors eased from the last picture's points
## (the corrections, [method place] with no lead of its own) and, when its
## time budget left the passes to [param aim] out, carried on to it by the
## motion step with this machine's skaters steered; the drawn points
## swapped in as [method apply] does ([method restore] after the draw).
func apply_ahead(s: MwRinkState, sim: MwRinkSim, at: int, aim: int, continuous: bool, three: bool) -> bool:
	var net_match: MwNetMatch = _match.get_ref() if _match != null else null
	if not active() or net_match == null or net_match.phase != MwNetMatch.Phase.PLAYING or s == null or sim == null:
		snap_next()
		return false
	var rest := maxi(aim - at, 0)
	var saved_pacer := pacer
	pacer = null                            # (the passes left out: the game's 2 ticks each)
	_smooth = false
	place(s, sim, at, rest, steering(s, net_match.local_states()) if rest > 0 else {}, continuous, three)
	_smooth = true
	pacer = saved_pacer
	return true


## The pads to steer (pad index -> [held pad bits, stick]) from this
## machine's players' latest wire states [param states] (number ->
## MwNetInput state): each player in [param s]'s control layer, in the game
## (not out, not away, no menu of their own open), on their seat's pad -
## the D-pad bits (MwNetInput's first four verbs are move_up, move_down,
## move_left, move_right: the original's U D L R) and the stick decoded as
## the stream's readers decode it (MwStick).
static func steering(s: MwRinkState, states: Dictionary) -> Dictionary:
	var out := {}
	if s.control == null:
		return out
	for seat in s.control.seats:
		if not states.has(seat.player) or seat.away() or seat.pad < 0:
			continue
		var st: PackedByteArray = states[seat.player]
		var code := (st[MwNetInput.STICK] << 8) | st[MwNetInput.STICK + 1] if st[MwNetInput.STICK + 1] != 0 \
				else MwStick.NONE
		out[seat.pad] = [st[0] & 0x0F, MwStick.decode(code)]
	return out


## The prediction and its correction for [param s] at router tick
## [param tick], [param lead] ticks behind the host, [param steer] (pad
## index -> [held bits, stick]: [method steering]) this machine's pads;
## the drawn positions swapped in ([method restore] puts the confirmed
## back). See [method apply].
func place(s: MwRinkState, sim: MwRinkSim, tick: int, lead: int, steer: Dictionary, continuous: bool,
		three := false) -> void:
	var jump := not continuous or _at < 0 \
			or (s.phase != _phase and s.phase in [MwRinkState.PHASE_FACEOFF, MwRinkState.PHASE_START])
	if jump or not _smooth:
		if jump:
			stats["jumps"] += 1
		_lead = float(lead)
	else:
		_lead += (lead - _lead) * LEAD_SMOOTHING
	var k := clampi(roundi(_lead), 0, MAX_LEAD)
	var t := tick + k
	var dt := 0 if jump else maxi(t - _at, 0)
	stats["presents"] += 1
	# the estimates: every actor's motion copied, then the lead's passes
	var est := {}            # key -> MwMotion
	var params := {}         # key -> MwMotion.Params
	var steered := {}        # key -> [the skater's copy, held, stick, pad]
	var fixed := {}          # key -> true: not moved (impaled)
	var goalies := {}        # key -> the goalie's copy (the crease rule reads it)
	var players := {}        # key -> the real player
	for ti in s.teams.size():
		var team := s.teams[ti]
		for pi in team.players.size():
			var p := team.players[pi]
			if not p.present:
				continue
			var key := MwRinkDraw3D.actor_key(ti, pi)
			players[key] = p
			params[key] = s.player_params
			var pad := sim.human.pad_index(p, team) if p.flags & MwRinkState.Player.HUMAN else -1
			if pad >= 0 and steer.has(pad) and p.state != MwRinkState.Player.STATE_IMPALED:
				var player := copy_player(p)
				steered[key] = [player, int(steer[pad][0]), steer[pad][1], pad]
				est[key] = player.motion
				stats["steered"] += 1
			elif p.is_goalie():
				goalies[key] = copy_player(p)
				est[key] = (goalies[key] as MwRinkState.Player).motion
			else:
				est[key] = p.motion.copy()
				if p.state == MwRinkState.Player.STATE_IMPALED:
					fixed[key] = true
	var pk := s.puck
	var carrier := pk.carried_by()
	var carrier_key := _key_of(s, carrier) if carrier != null else ""
	var loose := pk.flags & MwRinkState.Puck.HIDDEN == 0 and carrier_key == ""
	if loose:
		est["puck"] = pk.motion.copy()
		params["puck"] = s.puck_params
	# the camera: its target's predicted path, its shake left out (added back below)
	var cam := s.camera.copy()
	var shake := cam.amp if cam.shake > 0 else 0
	cam.shake = 0
	cam.amp = 0
	cam.shown.x -= shake
	var cam_lead: Variant = null
	if pk.flags & MwRinkState.Puck.CARRIED:
		var ct := s.teams[1] if pk.flags & MwRinkState.Puck.BY_TEAM_B else s.teams[0]
		cam_lead = MwRinkCamera.LEAD if ct.flags4 & 2 else -MwRinkCamera.LEAD
	var target_key := _key_of(s, s.camera_target)
	var target: MwMotion = s.camera_target.motion if s.camera_target != null else null
	var cam_before := Vector2(cam.shown)
	var last_e := 1
	if not steered.is_empty():
		_shadow_for(s, sim, steered)
	# the lead's passes, and the tick the estimates are at (the pacer's: the
	# confirmed state's pass plus the predicted passes; else the lead's end)
	var steps := pass_steps(k)
	var t_est := t
	if pacer != null:
		t_est = tick - pacer.since_pass()
		for e in steps:
			t_est += e
	last_steps = steps
	for e in steps:
		for key: String in est:
			if steered.has(key):
				var st: Array = steered[key]
				_steer(st[0], st[1], e)
			elif goalies.has(key):
				sim.players.goalie_move(goalies[key], e, false)    # the player update's (`$86A`)
			elif not fixed.has(key):
				(est[key] as MwMotion).step(params[key], e)
		if loose:
			_inside(est["puck"])
		cam_before = Vector2(cam.shown)
		cam.update(sim.rom, e, est.get(target_key, target) if target_key != "" else target, cam_lead)
		last_e = e
	if carrier_key != "":
		# a carried puck goes with its carrier
		est["puck"] = _carried(pk.motion, players[carrier_key].motion, est[carrier_key])
		params["puck"] = s.puck_params
	# the corrections, and what is drawn
	var drawn := {}
	var tracks := {}
	for key: String in est:
		var track := Track.new()
		var p: MwRinkState.Player = players.get(key)
		track.record = p.record if p != null else 0
		track.motion = est[key]
		track.params = params[key]
		track.at = t_est
		var e3 := px_of(track.motion)
		var old: Track = _tracks.get(key)
		if not jump and old != null and old.record == track.record:
			var carried := old.motion.copy()
			carried.step(old.params, maxi(t_est - old.at, 0))     # the old estimate carried on to the new one's tick
			var err := px_of(carried) + old.offset - e3
			if err.length() > SNAP_PX:
				stats["snapped"] += 1
			else:
				track.offset = err * pow(0.5, dt / HALF_TICKS)
		tracks[key] = track
		drawn[key] = e3 + track.offset
	_tracks = tracks
	var ce := Vector2(cam.shown)
	var cv := (ce - cam_before) / float(last_e)
	var co := Vector2.ZERO
	if not jump and not _cam.is_empty():
		var carry := maxi(t_est - int(_cam["at"]), 0)
		var err2: Vector2 = (_cam["e"] as Vector2) + (_cam["v"] as Vector2) * carry + (_cam["o"] as Vector2) - ce
		if err2.length() <= SNAP_PX:
			co = err2 * pow(0.5, dt / HALF_TICKS)
	_cam = {"e": ce, "v": cv, "o": co, "at": t_est}
	_at = t
	_phase = s.phase
	last_tick = tick
	last_lead = k
	_swap(s, sim.rom, players, steered, drawn, ce + co, shake, three)


## The predicted passes' elapsed ticks for a lead of [param k] ticks: the
## game's passes of [constant PASS_TICKS] (the last one shorter) covering
## it, or with a [member pacer] the passes it would make in those ticks.
func pass_steps(k: int) -> PackedInt32Array:
	if pacer != null:
		return pacer.predict(k, pacer_work)
	var out := PackedInt32Array()
	var left := k
	while left > 0:
		var e := mini(PASS_TICKS, left)
		out.append(e)
		left -= e
	return out


## The rink state back as it was before [method apply] / [method place]
## (positions, markers, camera, the steered skaters' facing and animation,
## the arrows' variants and the impale record the draw pass writes).
func restore(s: MwRinkState) -> void:
	if _saved.is_empty():
		return
	if _saved.get("state") != s:
		push_error("MwNetReckoning.restore: not the state swapped into - put back there")
		s = _saved["state"]
	for p: MwRinkState.Player in _saved["players"]:
		p.motion.pos = _saved["players"][p]
	for p: MwRinkState.Player in _saved["anims"]:
		var a: Array = _saved["anims"][p]
		_anim_from(p.anim, a[0])
		p.angle = a[1]
	for marker: MwRinkState.Marker in _saved["markers"]:
		var v: Vector2i = _saved["markers"][marker]
		marker.x = v.x
		marker.y = v.y
	for anim: MwAnimState in _saved["arrows"]:
		anim.variant = _saved["arrows"][anim]
	s.puck.motion.pos = _saved["puck"]
	s.camera.shown = _saved["shown"]
	s.impale.address = _saved["impale"]
	_saved = {}


## Plan 45 (docs/style.md D8): whatever [method apply] or [method
## apply_ahead] swapped into a state and no [method restore] put back - the
## draw between them stopped by a script error - put back now. The rink
## calls it before each confirmed pass and each picture, so the confirmed
## game never goes on from the eased positions (a desync, a resync loop).
## True when something was left.
func restore_left() -> bool:
	if _saved.is_empty():
		return false
	push_error("MwNetReckoning: a picture's eased positions were left in the state - put back")
	restore(_saved["state"])
	return true


## 3D: [param items] (MwRinkDraw3D.items of the draw made between [method
## apply] and [method restore]) moved to their actors' sub-pixel points -
## the 2D picture's whole pixels plus the eased point's fraction (upright
## frames also in height).
func shift_items(items: Array) -> void:
	if _frac.is_empty():
		return
	for it: Dictionary in items:
		var item_place: int = it.get("place", MwRinkDraw3D.SCREEN)
		if item_place == MwRinkDraw3D.SCREEN or item_place == MwRinkDraw3D.MAP:
			continue
		var subject: String = String(it.get("key", "")).get_slice("/", 0)
		if not _frac.has(subject):
			continue
		var f: Vector3 = _frac[subject]
		it["at"] = (it["at"] as Vector3) + Vector3(f.x, f.y, f.z if item_place == MwRinkDraw3D.UPRIGHT else 0.0)


## The drawn points into [param s] (the confirmed saved for [method restore]).
func _swap(s: MwRinkState, rom: PackedByteArray, players: Dictionary, steered: Dictionary, drawn: Dictionary,
		cam: Vector2, shake: int, three: bool) -> void:
	_saved = {"players": {}, "anims": {}, "markers": {}, "arrows": {}, "puck": s.puck.motion.pos.duplicate(),
			"shown": s.camera.shown, "impale": s.impale.address, "state": s}
	_frac = {}
	last = {}
	var moved := {}          # player -> its whole-pixel move
	for key: String in drawn:
		var d: Vector3 = drawn[key]
		var actor: MwRinkState.Actor = players[key] if players.has(key) else s.puck
		var conf := actor.motion.pixels()
		var whole := Vector3i(floori(d.x), floori(d.y), maxi(floori(d.z), 0))
		if actor != s.puck:
			_saved["players"][actor] = actor.motion.pos.duplicate()
			moved[actor] = whole - conf
		actor.motion.pos = PackedInt32Array([whole.x * 256, whole.y * 256, whole.z * 256])
		if three:
			actor.motion.pos = PackedInt32Array([floori(d.x * 256.0), floori(d.y * 256.0),
					maxi(floori(d.z * 256.0), 0)])
			var subject := "puck" if actor == s.puck else _subject_of(key, (actor as MwRinkState.Player).record)
			_frac[subject] = Vector3(d.x - whole.x, d.y - whole.y, maxf(d.z, 0.0) - whole.z)
		last[key] = {"confirmed": conf, "drawn": whole, "at": d, "steered": steered.has(key)}
	for key: String in steered:
		var p: MwRinkState.Player = players[key]
		var player: MwRinkState.Player = steered[key][0]
		_saved["anims"][p] = [_anim_fields(p.anim), p.angle]
		_anim_from(p.anim, _anim_fields(player.anim))
		p.angle = player.angle
	# the markers (and their plates, the owners' rings) follow their players
	for team in s.teams:
		for marker in team.markers:
			_saved["markers"][marker] = Vector2i(marker.x, marker.y)
		for anim in team.arrows:
			_saved["arrows"][anim] = anim.variant
		var owner := {}
		for p in team.players:
			if not p.present:
				continue
			if p.flags & MwRinkState.Player.HUMAN:
				owner[team.control_slot(p)] = p
			elif s.puck.carried_by() == p:
				owner[team.marker_of(p)] = p
		for i: int in owner:
			if i < team.markers.size() and moved.has(owner[i]):
				var dv: Vector3i = moved[owner[i]]
				team.markers[i].x += dv.x
				team.markers[i].y += dv.y
	var shown := MwRinkCamera.clamp_to(Vector2i(floori(cam.x) + shake, floori(cam.y)),
			MwRinkCamera.limits(rom))
	last["camera"] = {"confirmed": s.camera.shown, "drawn": shown}
	s.camera.shown = shown


## One predicted pass of [param e] ticks of skater copy [param player] steered
## by the held pad bits [param held]: the pass start's own geometry entry
## (speed, velocity angle: `$95C8`), the target from the D-pad or the
## stick (`$17FC`), the skating step (`$63D8`), the motion step and the
## animation - on the copy, in the shadow state.
func _steer(player: MwRinkState.Player, held: int, e: int) -> void:
	var v := _shadow_sim.dist_angle(player.motion.vel[0], player.motion.vel[1])
	player.mate_dist[player.index] = v.x
	player.mate_angle[player.index] = v.y
	player.flags &= ~MwRinkState.Player.BURST
	_shadow_sim.human.target(player, held)
	_shadow_sim.players.skate(player, e)
	if player.is_goalie():
		_shadow_sim.players.goalie_move(player, e)
	else:
		player.motion.step(_shadow.player_params, e)
		player.anim.advance(e)


## The shadow state the steered skaters skate in: what the skating step
## reads of [param s] (its phase, set-up, teams and puck - read only - and
## the motion parameters) with this machine's sticks on its pads.
func _shadow_for(s: MwRinkState, sim: MwRinkSim, steered: Dictionary) -> void:
	if _shadow == null:
		_shadow = MwRinkState.new()
		_shadow_sim = MwRinkSim.new(sim.rom, _shadow)
	_shadow.phase = s.phase
	_shadow.extended = s.extended
	_shadow.teams = s.teams
	_shadow.puck = s.puck
	_shadow.player_params = s.player_params
	var sticks: Array[Vector2i] = []
	sticks.resize(s.pad_sticks.size())
	for st: Array in steered.values():
		var pad: int = st[3]
		if pad < sticks.size():
			sticks[pad] = st[2]
	_shadow.pad_sticks = sticks


## A carried puck's estimate: its confirmed motion moved as its carrier's
## estimate [param est] moved from the carrier's confirmed [param carrier]
## (the carrier's velocity, so it carries on with him).
static func _carried(puck: MwMotion, carrier: MwMotion, est: MwMotion) -> MwMotion:
	var puck_estimate := puck.copy()
	for i in 3:
		puck_estimate.pos[i] += est.pos[i] - carrier.pos[i]
	puck_estimate.vel = est.vel.duplicate()
	puck_estimate.acc = est.acc.duplicate()
	puck_estimate.pos[2] = maxi(puck_estimate.pos[2], 0)
	return puck_estimate


## A loose puck's estimate kept inside the boards (no bounce: it stops there).
static func _inside(estimate: MwMotion) -> void:
	for i in 2:
		var lim := (BOARD.x if i == 0 else BOARD.y) << 8
		if absi(estimate.pos[i]) > lim:
			estimate.pos[i] = clampi(estimate.pos[i], -lim, lim)
			estimate.vel[i] = 0
			estimate.acc[i] = 0


## The actor key of [param actor] in [param s] ("" for none or another object).
static func _key_of(s: MwRinkState, actor: MwRinkState.Actor) -> String:
	if actor == null:
		return ""
	if actor == s.puck:
		return "puck"
	for ti in s.teams.size():
		var i := s.teams[ti].players.find(actor)
		if i >= 0:
			return MwRinkDraw3D.actor_key(ti, i)
	return ""


## "[param key].[param record] in hex" ([method _swap]'s subjects), spelled
## once a pair (plan 42).
func _subject_of(key: String, record: int) -> String:
	var by: Dictionary = _subjects.get(key, {})
	if by.is_empty():
		_subjects[key] = by
	var name: String = by.get(record, "")
	if name == "":
		name = "%s.%X" % [key, record]
		by[record] = name
	return name


var _subjects := {}       # actor key -> {record: subject} (plan 42)


## [param estimate]'s position in pixels, sub-pixel (24.8 / 256).
static func px_of(estimate: MwMotion) -> Vector3:
	return Vector3(estimate.pos[0], estimate.pos[1], estimate.pos[2]) / 256.0


## A copy of skater [param p] with what the target and skating steps read
## and write (its motion and animation copied too).
static func copy_player(p: MwRinkState.Player) -> MwRinkState.Player:
	var player := MwRinkState.Player.new()
	player.motion = p.motion.copy()
	player.anim = p.anim.copy()
	# (plan 42: each field by name in code, not by get / set)
	player.record = p.record
	player.target_x = p.target_x
	player.target_y = p.target_y
	player.original = p.original
	player.index = p.index
	player.slot = p.slot
	player.position = p.position
	player.role = p.role
	player.state = p.state
	player.substate = p.substate
	player.angle = p.angle
	player.flags = p.flags
	player.flags2 = p.flags2
	player.team = p.team
	player.pad = p.pad
	player.anim_id = p.anim_id
	player.weapon = p.weapon
	player.puck_dist = p.puck_dist
	player.puck_angle = p.puck_angle
	player.mate_dist = p.mate_dist.duplicate()
	player.mate_angle = p.mate_angle.duplicate()
	return player


static func _anim_fields(anim: MwAnimState) -> Array:
	return [anim.address, anim.variant, anim.speed, anim.flags, anim.count, anim.position, anim.frame]


static func _anim_from(anim: MwAnimState, f: Array) -> void:
	anim.address = f[0]
	anim.variant = f[1]
	anim.speed = f[2]
	anim.flags = f[3]
	anim.count = f[4]
	anim.position = f[5]
	anim.frame = f[6]

