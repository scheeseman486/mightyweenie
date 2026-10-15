class_name MwRinkUpdate
extends RefCounted
## The rink pass outside the simulation segment, the puck rules and the
## phase handler (`$F962` minus `$F98A`-`$F9C8`, `$C84A`, `$FC58`;
## docs/re/rink.md, Between segments), node-free. A pass of the rink loop is
##
##   [method pass_start] (`$F962`-`$F984`: pass tick, pass counter,
##   penalties `$A66A`, the clock `$261C`), the pads, the segment
##   ([MwRinkSim]), [method after_segment] (`$F9C8`-`$FA8E`: faceoff
##   portrait, rink objects against the rink `$7868`, camera, `$56EA`'s
##   plane B / nets / crowd throws / rink objects / lamps / crowd / impale
##   animation, the replay frame's head, the penalty timers `$A5EC`), the
##   puck rules and phase handler ([method MwRinkPhases.pass_end]), then
##   [method draws] (`$FAA0`-`$FB16`: the draw pass and what it writes:
##   off-screen arrow variants, the impale record, the replay frame's sprite
##   records and trailer; the first pass's end).
##
## Random numbers are drawn as the original does (crowd throw roll every
## pass, a throw's four draws, an under-ice silhouette's turn), through
## [member sim] (its log included). Where the original reads the live tick
## counter (the VBlank interrupt moves it while the pass runs), [member
## hooks] may set [member MwRinkState.tick] first: `tick_at(update, tag)`
## with the TICK_* tags below. Without hooks the tick is the pass's.
## Integer arithmetic is the 68000's (16-bit words, byte angles).

## Where the live tick is read between segments (tags for [member hooks];
## the recorder's sites by address in [constant TICK_ADDRESSES]).
const TICK_SHARK := 9                ## `$1522C`: each oscillator of a shark's target (x, then y)
const TICK_PENALTY := 10             ## `$A7B8`: the penalty icon's timer (phase 0)
const TICK_ARROW := 11               ## `$4B5C`: a human goalie's blinking arrow (draw)
const TICK_CLOCK := 12               ## `$1702`, `$1714`, `$26B2`, `$26BE`: the game clock (pass start)
const TICK_ADDRESSES := {0x1522C: TICK_SHARK, 0xA79E: TICK_PENALTY, 0xA7B8: TICK_PENALTY, 0x4B5C: TICK_ARROW,
		0x1702: TICK_CLOCK, 0x1714: TICK_CLOCK, 0x26B2: TICK_CLOCK, 0x26BE: TICK_CLOCK}

const THROW_WEIGHTS := 0x1C574       ## 12 words: odds of kinds 12-23 (/65536; the last takes the rest)
const NET_SIZES := 0x1C74A           ## by net style: half width, back y
const HAZARD_SIZES := 0x1C88E        ## by kind - 1: frame.l, half width.w, half height.w
const FIRE_LOOP := 0x22B2A           ## a fire after its first burst (loops)
const DEMON_NET_GOAL := 0x21114      ## the Demon Net's swallow animation (left alone)
const DEMON_NET_IDLE := 0x21108
const PERIOD_SUFFIXES := 0x1BFDC     ## "00stndrd"
const MAP := 0x24CFC                 ## the rink picture (cells: width +8, height +$A)
const PLANE_ROWS := 32               ## plane B is 64 x 32 cells
const BOARD_X := MwSimCollide.BOARD_X
const BOARD_Y := MwSimCollide.BOARD_Y
const OSC_PERIOD := 0x8CA0           ## 36000 ticks

var rom: PackedByteArray
var sim: MwRinkSim
var s: MwRinkState
## Optional: `tick_at(update, tag)` before each live tick read (comparisons).
var hooks: Object = null
## The draw pass ([method draws]) and its last sprite list.
var drawer: MwRinkDraw
var sprites: Array = []
## A presentation's side-store for the replay (plan 20, MwReplay3D.frame):
## called with the state and the drawer for each replay frame [method
## draws] closes; what it returns is kept beside the frame
## (ReplayRing.side). Unset: nothing kept.
var replay_side := Callable()
## The ticks of the pass going on ([method pass_start]; the crowd's life steps by them).
var pass_e := MwPassClock.RINK_PASS_TICKS
## The pass start's window plane writes (`$261C`: the clock widget's texts),
## as [member MwRinkPhases.window_ops].
var window_ops: Array = []
## Presentation (plan 35 work item 5, MwNetReckoning): what this pass's draw
## pass was given ([method draws]: the phase handler's pieces, the puck
## rules' phase, overlays, sprites and the penalty icon as `$A5EC` saw it),
## so a presentation can draw the state again ([method redraw]); empty
## until the pass has drawn.
var _drawn_with: Array = []


func _init(sim_: MwRinkSim) -> void:
	sim = sim_
	rom = sim.rom
	s = sim.s
	drawer = MwRinkDraw.new(rom)
	drawer.on_tick = _tick.bind(TICK_ARROW)


func _tick(tag: int) -> void:
	if hooks:
		hooks.tick_at(self, tag)


# --- the pass ------------------------------------------------------------------------------

## Plan 40 (S2): one rink pass of [param e] ticks as live play runs it - the
## tick moved on, the pass start ([method pass_start]: the clock),
## [param pads] (called next: the pads and whatever else comes before the
## segment), the segment ([method MwRinkSim.run]), [param ran] (called
## after it), the rest of the update ([method after_segment]), the puck
## rules and the phase handler [param phases] ([method MwRinkPhases.pass_end])
## and, when the handler stays in play ([param draw]: false, the caller
## draws), the draw pass with its overlays and sprites ([method draws]; the
## match's models step there). Returns the handler's exit: -1 play goes on,
## [constant MwRinkPhases.PAUSED], [constant MwRinkPhases.TEAM_INFO] (no
## draw), a screen (left). Without [param phases] (the rink editor's TEST
## SKATE) no handler and a plain draw. The rink (MwRink), the instant
## replay's demo match, TEST SKATE and the tests' rig run their passes here.
func run_pass(e: int, phases: MwRinkPhases, pads := Callable(), ran := Callable(), draw := true) -> int:
	s.tick += e
	pass_start(e)
	if pads.is_valid():
		pads.call()
	sim.run(e)
	if ran.is_valid():
		ran.call()
	after_segment(e)
	var to := phases.pass_end(e) if phases != null else -1
	if to == -1 and draw:
		if phases != null:
			draws([], MwRinkPhases.RULES_DRAWN, phases.overlays, phases.sprite_ops)
		else:
			draws()
	return to


## `$F962`-`$F984`: the next pass begins [param e] ticks after the last
## one (the caller has moved [member MwRinkState.tick] on): its start tick
## (`$C5FE`), the pass counter (`$FFBD80`, read by nothing), the penalties'
## pass start (`$A66A`) and the clock (`$261C`). The pads are read next.
func pass_start(e: int) -> void:
	pass_e = e
	window_ops.clear()
	_drawn_with = []
	s.pass_tick = s.tick & 0xFFFFFFFF
	s.pass_count = (s.pass_count + 1) & 0xFF
	penalties_start()
	clock_pass()


## `$F9C8`-`$FA8E`: after the segment of a pass of [param e] ticks, up to
## the puck rules: the faceoff portrait's animation (`$AFAC`), rink objects
## against the rink (`$7868`), the camera (`$F9DA` target, `$56EA`), the
## rest of `$56EA` ([method rink_update]), the replay frame's head when
## recording (`$C608`: `$9D34`, `$5C66`, `$3B20` x 2) and the penalty
## timers (`$A5EC`).
func after_segment(e: int) -> void:
	if s.faceoff.shown():
		s.faceoff.anim.advance(e)
	objects_vs_rink()
	s.camera_pass(rom, e)
	rink_update(e)
	# `$148A8` waits for the DMA queue (a VBlank usually falls here) and
	# `$1568E` resets the sprite list (outside the state).
	if s.replay_on != 0:
		replay_head(e)
	penalties(e)


## `$FAA0`-`$FB16`: the draw pass ([MwRinkDraw]; the phase handler's
## overlays [param phase_overlays] ([overlay, with camera]), sprites
## [param phase_sprites] ([member MwRinkPhases.sprite_ops]) and pieces
## [param phase_adds], the phase the puck rules saw [param rules_phase] if
## it changed since - [constant MwRinkPhases.RULES_DRAWN] when the puck
## rules' icon is among the overlays) with what it writes: the off-screen
## arrows' variants, the impaled players' record, a replay record per
## sprite drawn while the frame is open, the frame's trailer (`$9D64`);
## the first pass of a visit ends (`$C606`; the palette fades in, the
## display goes on). Live play: `rink_draw`'s last call, the crowd's noise
## ([method crowd_sound]). Returns the sprite list.
func draws(phase_adds: Array = [], rules_phase := -1, phase_overlays: Array = [], phase_sprites: Array = []) -> Array:
	_drawn_with = [phase_adds, rules_phase, phase_overlays, phase_sprites, drawer.penalty_shown]
	sprites = drawer.build(s, phase_adds, rules_phase, phase_overlays, phase_sprites)
	crowd_sound()
	drawer.penalty_shown = -1
	var ring := s.replay
	var closing := ring.open != 0
	var start := ring.frame_start
	if closing:
		for c in drawer.calls:
			replay_sprite(int(c[0]), int(c[1]), int(c[2]), int(c[3]), int(c[4]))
		if replay_side.is_valid():
			ring.side[ring.frame_start] = replay_side.call(s, drawer)
		if s.extended:
			ring.side[ring.frame_start] = port_side(ring.side.get(ring.frame_start, {}))
	ring.close_frame()
	if closing and s.full_replay != null:
		s.full_replay.add(ring, start, ring.side.get(start, {}))     # plan 28: the whole match kept
	if s.first_pass != 0:
		s.first_pass = 0
	return sprites


## Presentation (plan 35 work item 5): this pass's draw pass made again on
## the state as it is now with another drawer [param other_drawer] (a client's dead
## reckoning swaps its drawn positions in first): the same phase pieces,
## overlays, sprites and penalty icon as [method draws] had. Nothing of the
## pass's own draw is touched (its list, the replay records); the caller
## restores whatever the draw pass writes into the state (the arrows'
## variants, the impale record). Empty when the pass has not drawn
## ([method can_redraw]).
func redraw(other_drawer: MwRinkDraw) -> Array:
	if _drawn_with.is_empty():
		return []
	other_drawer.penalty_shown = int(_drawn_with[4])
	var out := other_drawer.build(s, _drawn_with[0], int(_drawn_with[1]), _drawn_with[2], _drawn_with[3])
	other_drawer.penalty_shown = -1
	return out


## Whether this pass has drawn ([method redraw] can draw it again).
func can_redraw() -> bool:
	return not _drawn_with.is_empty()


## Plan 42 (speed, second round): [method draws]' inputs kept for the draw
## made later by [method redraw] - not made now. For the run-ahead's shadow
## (MwNetRunAhead), whose picture the rink scene draws with [method redraw]
## anyway (on the dead reckoning's eased positions): its own draw would be
## made and thrown away. Of what [method draws] does besides the list, the
## shadow keeps the visit's first pass ended; its replay ring's frame stays
## open (as its passes between pictures leave it - nobody's), its crowd
## sound is none (its sim not live, its models lent only after) and its
## arrows' variants and impale record are the redraw's.
func defer_draws(phase_adds: Array = [], rules_phase := -1, phase_overlays: Array = [],
		phase_sprites: Array = []) -> void:
	_drawn_with = [phase_adds, rules_phase, phase_overlays, phase_sprites, drawer.penalty_shown]
	drawer.penalty_shown = -1
	if s.first_pass != 0:
		s.first_pass = 0


## Plan 34, an extended set-up: the frame's port side-record (in the replay
## ring's side-store with its 3D frame, [param side]; MwFullReplay keeps it
## too): the ring keeps the original's two markers a team, this every
## marker, plate and arrow the draw pass drew ([member MwRinkDraw.port_calls]:
## "marks", [x, y, depth, attr, frame] in sprite coordinates, as the ring's
## records) and the plates' values ("plates", MwRinkState.plates).
func port_side(side: Dictionary) -> Dictionary:
	side["marks"] = drawer.port_calls.duplicate(true)
	side["plates"] = s.plates.duplicate(true)
	return side


## `crowd_sound` `$B052` (the end of `rink_draw` `$591E`, every pass that
## draws): unless the crowd is quiet (`$FFC644`, a speech), `crowd_level`
## (`$13E52`, called at `$B064`) with the crowd's level capped at 1000
## (unsigned word). Live play only ([member MwRinkSim.live]).
## The match's models (plan 40: MwMatchModels - the crowd's life, plan 31,
## the benches, plan 32, the arena's paint, plan 37) step with the pass
## here, whatever runs it - nothing steps them while the passes stop (the
## pause) - and with ENHANCE AUDIO ([member MwCrowdLife.drives_sound]) the
## noise is the crowd's life's [method MwCrowdLife.sound_level] instead.
func crowd_sound() -> void:
	MwMatchModels.step(sim, pass_e)
	if not sim.live or s.crowd_quiet != 0:
		return
	MwSound.crowd_level(noise_level(s.crowd, s.crowd_life))


## The crowd noise's level for the game's crowd level [param crowd] (capped
## at 1000, an unsigned word) or, with ENHANCE AUDIO, the crowd's [param
## life]'s (also the match's opening's, plan 33).
static func noise_level(crowd: int, life: MwCrowdLife) -> int:
	if life != null and MwCrowdLife.drives_sound:
		return MwCrowdLife.sound_level(life.snapshot())
	return mini(crowd & 0xFFFF, 1000)


# --- `$7868`: rink objects against the rink -----------------------------------------------------

## `$7868`: every rink object against the nets and in-ice hazards (moving
## ones low enough: thrown items, bombs), the straight boards and the
## rounded corners (all but sharks, kind 2 and spikes, up to 30 px high).
## The pixel position is taken once at the start: the boards push back
## from it, the corners read the moved one.
func objects_vs_rink() -> void:
	for rink_object in s.objects:
		var k := rink_object.kind
		if k == 0:
			continue
		var moving := 1 if k >= 3 else 0          # the object's mass in `$15470`
		var px := rink_object.motion.pixels()
		var x := MwRinkSim.s16(px.x)
		var y := MwRinkSim.s16(px.y)
		var z := px.z & 0xFFFF                     # compared unsigned: below the ice is "high"
		if k == MwRinkState.KIND_SPIKES:
			continue
		if k < 3 or k == MwRinkState.KIND_BOMB or k >= 0xC:
			if moving == 0:
				continue                           # sharks, kind 2: nothing at all
			if z < 0x1E:
				_net_hit(rink_object, x, y, moving)
			if z < 0xA:
				_hazard_hit(rink_object, x, y)
		if z >= 0x1E:
			continue
		var d3 := 0x14 if rink_object.kind >= 8 and rink_object.kind <= 10 else 0xA
		var dx := MwRinkSim.s16(absi(x) + d3 - BOARD_X)
		if dx >= 0:
			dx += 1
			if rink_object.motion.pos[0] >= 0:
				dx = -dx
			rink_object.motion.pos[0] += dx << 8           # the velocity is left alone
		var dy := MwRinkSim.s16(absi(y) + d3 - BOARD_Y)
		if dy >= 0:
			dy += 1
			if rink_object.motion.pos[1] >= 0:
				dy = -dy
			rink_object.motion.pos[1] += dy << 8
		sim.collide.corner(rink_object, d3, 0x4000)


## `$795A`: the net at [param rink_object]'s end (bottom for y >= 0): inside its
## frame's box (|y| between 320 and back + 10, |x| below the half width +
## the visit's net slack, MwRinkState.net_slack: the word at `$A(a6)`) the
## object bounces off it (`$15470`, restitution $8000, the net does not move).
func _net_hit(rink_object: MwRinkState.RinkObject, x: int, y: int, moving: int) -> void:
	var net := s.nets[0] if y < 0 else s.nets[1]
	var ay := MwRinkSim.s16(absi(y))
	var ax := MwRinkSim.s16(absi(x))
	var st := net.style & 0xFF
	var hw := MwGfx.s16(rom, NET_SIZES + 4 * st)
	var back := MwGfx.s16(rom, NET_SIZES + 4 * st + 2)
	if MwRinkSim.s16(ay - (0xA + back)) >= 0:
		return
	if MwRinkSim.s16(-0xA + 0x149 - ay) >= 0:
		return
	if MwRinkSim.s16(ax - MwRinkSim.s16(s.net_slack + hw)) >= 0:
		return
	sim.collide.collide(rink_object, net, moving, 0, 0x8000)


## `$79BE`: the in-ice hazards (pits, holes, mines; thin ice is ignored)
## against [param rink_object] at ([param x], [param y]): inside a pit or hole the
## object is gone (kind 0; the loop goes on); a mine bounces it back at
## half speed, pushed out along the new velocity (no explosion).
func _hazard_hit(rink_object: MwRinkState.RinkObject, x: int, y: int) -> void:
	for hazard in s.hazards:
		if hazard.kind == 0 or hazard.kind == 1:
			continue
		var w := MwRinkSim.s16(MwGfx.u16(rom, HAZARD_SIZES + 8 * (hazard.kind - 1) + 4) - 6)
		var hh := MwRinkSim.s16(MwGfx.u16(rom, HAZARD_SIZES + 8 * (hazard.kind - 1) + 6) - 6)
		var dx := MwRinkSim.s16(absi(MwRinkSim.s16(hazard.x - x)) - 0xA - w)
		if dx >= 0:
			continue
		var dy := MwRinkSim.s16(absi(MwRinkSim.s16(hazard.y - y)) - 0xA - hh)
		if dy >= 0:
			continue
		if hazard.kind != 4:
			rink_object.kind = 0
			continue
		var motion := rink_object.motion
		var px := (dx - 2) << 8
		motion.vel[0] = MwRinkSim.asr(MwRinkSim.s16(-motion.vel[0]), 1)
		if motion.vel[0] >= 0:
			px = -px
		motion.pos[0] += px
		var py := (dy - 2) << 8
		motion.vel[1] = MwRinkSim.asr(MwRinkSim.s16(-motion.vel[1]), 1)
		if motion.vel[1] >= 0:
			py = -py
		motion.pos[1] += py


# --- `$56EA` after the camera ---------------------------------------------------------------

## `$56EA` after the camera: plane B's map rows and the scroll buffers,
## the nets, the crowd throw roll, the rink objects' hooks and motion (in
## phases 1 and 9 only corpses), the goal lamps, the crowd's level, the
## shared impale animation.
func rink_update(e: int) -> void:
	var sh := s.camera.shown
	# the map is as wide as the plane (column 0); rows: 2 above the screen
	var rows := MwGfx.u16(rom, MAP + 0xA) - PLANE_ROWS
	s.plane_b_cell = Vector2i(0, clampi((sh.y >> 3) - 2, 0, rows))
	s.scroll_b = Vector2i((-sh.x) & 0x1FF, sh.y & 0xFF)
	for net in s.nets:
		_net(net, e)
	crowd_throw()
	var setup := s.phase == MwRinkState.PHASE_FACEOFF or s.phase == MwRinkState.PHASE_START
	for rink_object in s.objects:
		if rink_object.kind == 0:
			continue
		if setup and rink_object.kind != MwRinkState.KIND_CORPSE:
			continue
		object_update(rink_object, e)
	for actor in s.lamps:                             # bottom, top (`$141AE`, player parameters)
		actor.motion.step(s.player_params, e)
		actor.anim.advance(e)
	crowd_decay(e)
	s.impale.advance(e)


## `$70E`: a net's pass: a Demon Net (style 0) not swallowing a goal opens
## its mouth (starts playing) while the puck is in the top third (y <=
## -265) and carried or moving, else goes back to its idle start if it
## was playing; then motion (puck parameters) and animation.
func _net(net: MwRinkState.Net, e: int) -> void:
	if net.style == 0 and net.anim.address != DEMON_NET_GOAL:
		var pk := s.puck
		var idle := true
		if pk.motion.pos[1] <= -0x10900:
			idle = pk.flags & MwRinkState.Puck.CARRIED == 0 and pk.motion.vel[0] == 0 and pk.motion.vel[1] == 0
		if idle:
			if net.anim.playing():
				net.anim = MwAnimState.from_record(rom, DEMON_NET_IDLE)   # `$14388`: variant 0
				net.anim.flags |= MwAnimState.PLAYING
		elif not net.anim.playing():
			net.anim.flags |= MwAnimState.PLAYING
	net.motion.step(s.puck_params, e)
	net.anim.advance(e)


## `$5B12`: the crowd throws something with chance level / 32001 (the roll
## is drawn every pass); into the first free object slot (none: no throw)
## goes an item drawn from `$1C574` (kinds 12, 15-21, 23; never 13, 14,
## 22) from behind a side board at a random y (odd: the left one), flying
## in (`$6A06`).
func crowd_throw() -> void:
	var v := sim.rng_range(0, 0x7D00) & 0xFFFF
	if v >= (s.crowd & 0xFFFF):
		return
	var slot: MwRinkState.RinkObject = null
	for rink_object in s.objects:
		if rink_object.kind == 0:
			slot = rink_object
			break
	if slot == null:
		return
	var r := sim.rng_next() & 0xFFFF
	var index := 11
	for i in 12:
		var w := MwGfx.u16(rom, THROW_WEIGHTS + 2 * i)
		if r < w:
			index = i
			break
		r -= w
	var y := sim.rng_range(-0x1C4, 0x1C4)
	var x := -0xE1 if y & 1 else 0xE1
	sim.spawn(slot, x, y, 0xC + index, 0)


## `$6734`: rink object [param rink_object]'s update hook (`$67B2` + 2), then, if it
## is still there, its motion (puck parameters) and animation (`$141AE`).
## Spikes never move nor animate (their hook drops the return address).
func object_update(rink_object: MwRinkState.RinkObject, e: int) -> void:
	var k := rink_object.kind
	match k:
		MwRinkState.KIND_SHARK:
			_shark(rink_object)
		MwRinkState.KIND_EXPLOSION:
			if not rink_object.anim.playing():
				rink_object.kind = 0
		MwRinkState.KIND_FIRE:
			# after the first burst (+$24 high byte 0), loop `$22B2A` for good
			if (rink_object.t24 >> 8) & 0xFF == 0 and not rink_object.anim.playing():
				rink_object.anim = MwAnimState.from_record(rom, FIRE_LOOP)
				rink_object.anim.flags |= MwAnimState.PLAYING
				rink_object.t24 = (rink_object.t24 + 0x100) & 0xFFFF
		MwRinkState.KIND_SPIKES:
			return
		MwRinkState.KIND_BOMB:
			if rink_object.motion.pos[2] == 0:
				var point := rink_object.motion.pixels()
				sim.spawn(rink_object, MwRinkSim.s16(point.x), MwRinkSim.s16(point.y), MwRinkState.KIND_EXPLOSION, 0)
		8, 9, 10:
			_under_ice(rink_object, e)
		0xC:
			_fire_starter(rink_object, e)
		13, 14, 16, 17, 18:
			_speed_anim(rink_object)
		19, 20, 21, 22, 23:
			_speed_anim(rink_object)
			rink_object.t24 = MwRinkSim.asr(rink_object.motion.pos[2], 8) & 0xFFFF   # the weapon's height (px)
	if rink_object.kind == 0:
		return
	rink_object.motion.step(s.puck_params, e)
	rink_object.anim.advance(e)


## `$68AE`: a shark swims (speed $80, then friction) towards the point the
## two global oscillators give now; its variant shows the direction.
func _shark(rink_object: MwRinkState.RinkObject) -> void:
	var point := rink_object.motion.pixels()
	_tick(TICK_SHARK)
	var tx := oscillator(s.shark_osc[0])
	_tick(TICK_SHARK)
	var ty := oscillator(s.shark_osc[1])
	var a := MwTrig.angle_of(rom, MwRinkSim.s16(tx - MwRinkSim.s16(point.x)),
			MwRinkSim.s16(ty - MwRinkSim.s16(point.y)))
	var v := sim.polar(a, 0x80)
	rink_object.motion.vel[0] = MwRinkSim.s16(v.x)
	rink_object.motion.vel[1] = MwRinkSim.s16(v.y)
	rink_object.anim.variant = ((a + 0x50) & 0xFF) >> 5


## `$1522C`: [param sine]'s value at the live tick (`divu` overflow kept as
## the 68000 leaves it: the dividend unchanged).
func oscillator(sine: MwRinkState.Oscillator) -> int:
	var t := (s.tick - sine.start) & 0xFFFFFFFF
	var r: int
	if t / OSC_PERIOD > 0xFFFF:
		r = (t >> 16) & 0xFFFF                 # overflow: swap of the unchanged dividend
	else:
		r = t % OSC_PERIOD
	var d0 := (((r * (sine.rate & 0xFFFF)) & 0xFFFFFFFF) << 8) & 0xFFFFFFFF
	var q := d0 / OSC_PERIOD
	if q > 0xFFFF:
		q = d0 & 0xFFFF
	var a := (q + sine.phase) & 0xFFFF
	return MwRinkSim.s16(MwRinkSim.asr(MwTrig.sin_(rom, a & 0xFF) * MwRinkSim.s16(sine.amp), 15) + sine.base)


## `$69D8`: a player under the ice drifts at speed $20; after his first 30
## ticks (+$26 counts down and is never reset) he turns 16 (1/16 turn)
## left or right at random every pass.
func _under_ice(rink_object: MwRinkState.RinkObject, e: int) -> void:
	rink_object.t26 = (rink_object.t26 - e) & 0xFFFF
	if rink_object.t26 & 0x8000 == 0:
		return
	var a := sim.velocity(rink_object).y
	var r := sim.rng_next()
	var d := -0x10 if r & 0x40 else 0x10
	var v := sim.polar((a + d) & 0xFF, 0x20)
	rink_object.motion.vel[0] = MwRinkSim.s16(v.x)
	rink_object.motion.vel[1] = MwRinkSim.s16(v.y)


## `$6A6A`: a fire starter rolls (animated by its speed) until it stops,
## then (+$26 high byte 1) waits 90 ticks and becomes a fire (`$66EE` kind
## 4: sound, playing) - the only way fires spread.
func _fire_starter(rink_object: MwRinkState.RinkObject, e: int) -> void:
	if (rink_object.t26 >> 8) & 0xFF == 0:
		_speed_anim(rink_object)
		if not rink_object.anim.playing():
			rink_object.t24 = 0x5A
			rink_object.t26 = (rink_object.t26 + 0x100) & 0xFFFF
		return
	rink_object.t24 = (rink_object.t24 - e) & 0xFFFF
	if rink_object.t24 & 0x8000:
		var point := rink_object.motion.pixels()
		sim.spawn(rink_object, MwRinkSim.s16(point.x), MwRinkSim.s16(point.y), MwRinkState.KIND_FIRE, 0)


## `$6ACE`: a thrown item's animation runs at its speed: stopped when it
## does not move, else the record's speed x min(speed, $140) / $140.
func _speed_anim(rink_object: MwRinkState.RinkObject) -> void:
	var sp := sim.velocity(rink_object).x & 0xFFFF
	var q := ((mini(sp, 0x140) << 8) / 0x140) & 0xFFFF
	if q == 0:
		rink_object.anim.flags &= ~MwAnimState.PLAYING
	else:
		rink_object.anim.flags |= MwAnimState.PLAYING
		rink_object.anim.speed = ((MwGfx.u16(rom, rink_object.anim.address) * q) >> 8) & 0xFFFF


## `$B01E`: the crowd calms down: capped at 1250 first, then -5 per tick
## (from 525 up) or -4, never below 50.
func crowd_decay(e: int) -> void:
	var level := s.crowd & 0xFFFF
	if level > 0x4E2:
		level = 0x4E2
	var step := 5 if MwRinkSim.s16(level) >= 0x20D else 4
	level = MwRinkSim.s16(level - ((step * e) & 0xFFFF))
	if level < 0x32:
		level = 0x32
	s.crowd = level


# --- the replay recording (`$C608` != 0) ---------------------------------------------------------

## `$9D34`, `$5C66`, `$3B20` x 2: a frame opened with the pass's elapsed
## ticks, the camera point as shown (camera px + the shake amplitude,
## clamped), the four hazards (flags & $F8 | kind), each team's first
## marker and, for a team with pads, its second: x, y, number << 9 |
## position << 6 | health & $3F.
func replay_head(e: int) -> void:
	var ring := s.replay
	ring.open_frame(e)
	var camera := s.camera
	var cx := MwRinkSim.s16(((camera.x & 0xFFFFFFFF) >> 8) + camera.amp)
	var cy := MwRinkSim.s16((camera.y & 0xFFFFFFFF) >> 8)
	var sh := MwRinkCamera.clamp_to(Vector2i(cx, cy), MwRinkCamera.limits(rom))
	ring.put_long(((sh.x & 0xFFFF) << 16) | (sh.y & 0xFFFF))
	for i in 2:
		var first_hazard := s.hazards[2 * i]
		var hazard := s.hazards[2 * i + 1]
		ring.put_word((((first_hazard.flags & 0xF8) | first_hazard.kind) << 8) | ((hazard.flags & 0xF8) | hazard.kind))
	for team in s.teams:
		_replay_marker(team.markers[0])
		if team.flags4 & 4:
			_replay_marker(team.markers[1])


## `$625C`: one marker (the number's top bit falls off the word).
func _replay_marker(marker: MwRinkState.Marker) -> void:
	var ring := s.replay
	ring.put_word(marker.x & 0xFFFF)
	ring.put_word(marker.y & 0xFFFF)
	ring.put_word((((((marker.number & 0xFF) << 3) | (marker.position & 0xFF)) << 6) | (marker.health & 0x3F)) & 0xFFFF)


## `$A07E`'s record of a `draw_frame` at sprite point ([param x], [param
## y]) while a frame is open: when playing back always, else only for
## points within x $40..$200, y $40..$1A0: (x & $FF) << 24 | (y >> 1 &
## $FF) << 16 | depth, then the frame address (low word, high byte) with y
## bit 0, x bit 8 and attr >> 2 in the last byte.
func replay_sprite(x: int, y: int, depth: int, attr: int, frame: int) -> void:
	var ring := s.replay
	if ring.open == 0:
		return
	x = MwRinkSim.s16(x)
	y = MwRinkSim.s16(y)
	if ring.playback == 0 and (y < 0x40 or y > 0x1A0 or x < 0x40 or x > 0x200):
		return
	var low := ((y & 1) << 7) | ((((x & 0xFFFF) >> 8) & 1) << 6) | ((attr & 0xFF) >> 2)
	ring.put_long(((x & 0xFF) << 24) | ((((y & 0xFFFF) >> 1) & 0xFF) << 16) | (depth & 0xFFFF))
	ring.put_long(((frame & 0xFFFF) << 16) | (((frame >> 16) & 0xFF) << 8) | low)


# --- penalties (penalties off: plan 10 ports the rest) -----------------------------------------------

## `$A66A` (pass start): nothing unless penalties are on (`$FFB0E5` == 1).
func penalties_start() -> void:
	if s.penalties != 1:
		return
	_jail_banner()
	sim.penalties.pass_start()


## `$A5EC`: the Jail Break banner (`$AA02`), the penalty icon's timer
## (`$A782`), the icon's animation, and once per clock second (`$C2F2`):
## the box countdowns and the power-play widget state (`$A888`).
func penalties(e: int) -> void:
	_jail_banner()
	if s.phase == MwRinkState.PHASE_PLAY:
		# `$A782`: a shown icon goes after 240 ticks; the stamp follows the tick
		var hide := true
		if s.penalty.shown():
			_tick(TICK_PENALTY)
			hide = ((s.tick - s.penalty_tick) & 0xFFFF) >= 0xF0
			if hide:
				s.penalty.flags &= ~0x80
		if hide:
			_tick(TICK_PENALTY)
			s.penalty_tick = s.tick & 0xFFFFFFFF
	if s.penalty.shown():
		s.penalty.anim.advance(e)
	drawer.penalty_shown = 1 if s.penalty.shown() else 0     # `$AFBC` draws it here
	var d := MwRinkSim.s16(s.box_clock - s.clock)
	if d == 0:
		return
	s.box_clock = s.clock & 0xFFFF
	sim.penalties.count_down(d)


## `$AA02`: the Jail Break message (`$FFC2F8`) goes after 120 ticks.
func _jail_banner() -> void:
	if s.jail_count == 0:
		return
	if MwRinkSim.s16((s.tick - s.jail_tick) & 0xFFFF) >= 0x78:
		s.jail_count = 0


# --- the clock `$261C` -----------------------------------------------------------------------

## `$261C`: while the widget is shown and not paused (and the AI is on),
## the game clock ticks (`$16FA`: a clock second per [member
## MwRinkState.clock_rate] ticks, the reference resynced when a pass is a
## second or more late) and its text is made ("MM:SS", over the period's)
## and drawn ([member window_ops]: the period at (5, 25), then the time at
## (4, 24)). A power play (widget bit 0) shows the power-play form (bit 3
## once drawn): first the power-play clock ([member MwRinkState.pp_seconds])
## at (4, 22), then the period with "[]" at (4, 21); when its clock reaches
## 0, or the power play ends, the widget is redrawn in the other form (in
## that pass the clock does not tick).
func clock_pass() -> void:
	if (s.ai_off >> 8) & 0xFF != 0:
		return
	var w := s.clock_widget
	if w & 4 or not w & 2:
		return
	if w & 1:
		if s.pp_seconds == 0:
			_widget_erase()
			s.clock_widget &= ~1
			_widget_draw()
			return
		if not w & 8:
			s.clock_widget &= ~1
			_widget_erase()
			s.clock_widget |= 1
			_widget_draw()
			return
		_pp_time_text()
		window_ops.append(["text", MwClockHud.FONT, MwClockHud.PP_CLOCK_AT.x, MwClockHud.PP_CLOCK_AT.y,
				MwClockHud.ATTR, s.clock_text.slice(0, s.clock_text.find(0))])
	elif w & 8:
		# `$26F6` (erasing the power-play form's cells) + `$25AA`: the widget back in its normal form
		s.clock_widget |= 1
		_widget_erase()
		s.clock_widget &= ~1
		_widget_draw()
		return
	_period_texts()
	if _tick_clock():
		_tick(TICK_CLOCK)
		if MwRinkSim.s16((s.tick - s.clock_ref) & 0xFFFF) >= 0x3C:
			_tick(TICK_CLOCK)
			s.clock_ref = s.tick & 0xFFFFFFFF
	time_text(s)
	window_ops.append(["text", MwClockHud.FONT, MwClockHud.CLOCK_AT.x, MwClockHud.CLOCK_AT.y, MwClockHud.ATTR,
			s.clock_text.slice(0, s.clock_text.find(0))])


## `$2748` drawn: the period at (5, 25); in the power-play form also "[]"
## at (4, 21) (written over the text buffer's first bytes).
func _period_texts() -> void:
	period_text(rom, s)
	window_ops.append(["text", MwClockHud.FONT, MwClockHud.PERIOD_AT.x, MwClockHud.PERIOD_AT.y, MwClockHud.ATTR,
			s.clock_text.slice(0, s.clock_text.find(0))])
	if s.clock_widget & 1:
		s.clock_text[0] = 0x5B
		s.clock_text[1] = 0x5D
		s.clock_text[2] = 0
		window_ops.append(["text", MwClockHud.FONT, MwClockHud.PP_LABEL_AT.x, MwClockHud.PP_LABEL_AT.y,
				MwClockHud.ATTR, PackedByteArray([0x5B, 0x5D])])


## `$27D8` on the power-play timer (`$FFB078`): its "MM:SS" in the text buffer.
func _pp_time_text() -> void:
	var v := s.pp_seconds & 0xFFFF
	var m := v / 60
	var sec := v % 60
	s.clock_text = PackedByteArray([(0x30 + m / 10) & 0xFF, 0x30 + m % 10, 0x3A, 0x30 + sec / 10, 0x30 + sec % 10, 0])


## `$26F6`: the widget's cells blanked (the power-play form's when bit 0),
## if shown; no longer shown.
func _widget_erase() -> void:
	if not s.clock_widget & 2:
		return
	s.clock_widget &= ~2
	if s.clock_widget & 1:
		window_ops.append(["fill", MwClockHud.AT_POWERPLAY.x, MwClockHud.AT_POWERPLAY.y, 9, 8, MwClockHud.BLANK])
	else:
		window_ops.append(["fill", MwClockHud.AT.x, MwClockHud.AT.y, 9, 5, MwClockHud.BLANK])


## `$25AA`: the widget drawn in the form bit 0 asks for (its texts: the
## power-play clock first, the period, "[]", the game clock).
func _widget_draw() -> void:
	MwRinkMatch.draw_clock_widget(sim)
	window_ops.append(["widget", s.clock_widget & 1 != 0, s.period & 0xFF, s.clock & 0xFFFF, s.pp_seconds & 0xFFFF])


## `$16FA`: true while the clock runs and has not just expired. The tick
## is read twice (a VBlank between the reads makes the new stamp one later).
func _tick_clock() -> bool:
	if not s.clock_flags & 1:
		return false
	_tick(TICK_CLOCK)
	var d := MwRinkSim.s16(((s.tick - s.clock_ref) & 0xFFFF) - s.clock_rate)
	if d < 0:
		return true
	_tick(TICK_CLOCK)
	s.clock_ref = (s.tick - d) & 0xFFFFFFFF
	s.clock = (s.clock - 1) & 0xFFFF
	if MwRinkSim.s16(s.clock) > 0:
		return true
	s.clock_flags = (s.clock_flags | 2) & ~1
	return false


## `$2748`: the period ("1st".."3rd", "OT1".."OT6", capped at "OT9").
static func period_text(rom_bytes: PackedByteArray, state: MwRinkState) -> void:
	var p := state.period & 0xFF
	var t := state.clock_text
	if p >= 4:
		t[0] = 0x4F
		t[1] = 0x54
		t[2] = mini((p + 0x2D) & 0xFF, 0x39)
	else:
		t[0] = (0x30 + p) & 0xFF
		t[1] = rom_bytes[PERIOD_SUFFIXES + 2 * p]
		t[2] = rom_bytes[PERIOD_SUFFIXES + 2 * p + 1]
	t[3] = 0
	state.clock_text = t


## `$27D8`: "MM:SS" and a 0 (seconds are never negative here).
static func time_text(state: MwRinkState) -> void:
	var v := state.clock & 0xFFFF
	var m := v / 60
	var sec := v % 60
	state.clock_text = PackedByteArray([(0x30 + m / 10) & 0xFF, 0x30 + m % 10, 0x3A, 0x30 + sec / 10, 0x30 + sec % 10,
			0])
