class_name MwRinkRam
extends RefCounted
## The rink's simulation state <-> the original's RAM (comparison layer,
## plan 08; docs/compare.md, Simulation recordings). A snapshot is the RAM
## `$FFB050`-`$FFCA61` (harness/mw_harness/sim_record.py); the AI snapshots
## end at `$FFBDC1`. [method decode_into] fills an [MwRinkState] from one,
## [method encode] writes the state back over a copy of a snapshot (bytes
## the state does not model keep the template's values), so a whole pass is
## compared byte for byte ([method diff], [method describe]).
##
## This is the only place the simulation's fields meet RAM addresses
## (docs/re/players.md, docs/re/puck.md list them).

const BASE := 0xFFB050
const SIZE := 0xCA62 - 0xB050
const AI_SIZE := 0xBDC2 - 0xB050

const HOLD := 0xFFB056
const CLOCK_TEXT := 0xFFB060
const CLOCK_TIMER := 0xFFB066        ## +0 ref .l, +4 seconds .w, +6 rate .b, +7 flags .b
const CLOCK := 0xFFB06A
const PERIOD := 0xFFB076
const CLOCK_WIDGET := 0xFFB077
const PP_SECONDS := 0xFFB07C         ## the power-play timer object `$FFB078` +4
const RNG := 0xFFB096
const SETUP := 0xFFB0DE             ## the 10 setup bytes (MwMatchSetup)
const PAD_MODE := 0xFFB0E0
const STADIUM := 0xFFB0E4
const PENALTIES := 0xFFB0E5
const RESERVES := 0xFFB0E6
const DEATH_INDEX := 0xFFB0E7
const PLANE_B := 0xFFB0B2
const SCROLL_B := 0xFFB0D8           ## hscroll word; vscroll word at +4
const RINK := 0xFFB0E8
const PUCK := 0xFFB3C2
const TEAMS := [0xFFB402, 0xFFB8AC]
const PLAYERS := 0x6C
const PLAYER_SIZE := 0x76
const OBJECTS := RINK + 0x124
const OBJECT_SIZE := 0x2A
const HAZARDS := RINK + 0xFC
const FACEOFF := 0xFFBD56
const PASS_COUNT := 0xFFBD80
const IMPALE := 0xFFBD82
const BRIBE := 0xFFBD8E
const SPECIAL_ACTOR := 0xFFBD90
const REF := 0xFFBD92
const COOP := 0xFFBDB8
const PROJECTION := 0xFFBDBA
const DROP := 0xFFBE3C
const PLATES := 0xFFBE80
const SHARK_OSC := 0xFFC280         ## two oscillators of 12 bytes
const GOAL_MESSAGE := 0xFFC2B6
const REPLAY := 0xFFC2BE             ## the ring object; frames .w at +$10, start +$12, open +$14, playback +$15, pan +$16
const PENALTY_TICK := 0xFFC2D8
const PENALTY := 0xFFC2DC
const BOX_CLOCK := 0xFFC2F2
const FACEOFF_STEP := 0xFFC31C
const PASS_TICK := 0xFFC5FE
const FIRST_PASS := 0xFFC606
const REPLAY_ON := 0xFFC608
const CROWD_QUIET := 0xFFC644
const JAIL := 0xFFC2F4
const FACEOFF_SPOT := 0xFFC31D
const AI_OFF := 0xFFC31E
const STOPPAGE := 0xFFC3C8
const CREASE_Y := 0xFFC3E0
const PUCK_RULE := 0xFFC3E2
const PHASE := 0xFFC60A
const SUBPHASE := 0xFFC60C
const SCORING := 0xFFC640
const GOAL_POINTS := 0xFFC2B4
const FIGHT_BLOCK := 0xFFCA1C
# the match flow (MwRinkPhases)
const PLAY_MODE := 0xFFB0E1
const MINUTES := 0xFFB0E3
const PERIOD_ROW := 0xFFB0E2
const PAUSE := 0xFFB08E              ## team .w, attr .w, pad x 2 .w, timeout offered .w
const PLAYOFFS := 0xFFBD6A           ## 21 bytes (MwPlayoffs)
const GOAL_TICK := 0xFFC2B0
const GOAL_NET := 0xFFC2BA           ## net .w, its last frame .w
const PENALTY_STEP := 0xFFC2F0
const FACEOFF_TICK := 0xFFC2FA
const FACEOFF_TEXT := 0xFFC2FE
const DROP_PLANE := 0xFFC300
const DROP_OBJ := 0xFFC304
const SPEECH_BOX := 0xFFC32E
const TEXT_BOX := 0xFFC336
const BOX_FILL := 0xFFC3B4
const BOX_C3BC := 0xFFC3BC
const STOP_TICK := 0xFFC3DC
const RULE_TEAM_B := 0xFFC3E4
const RULE_CLOCK := 0xFFC3E6
const RULE_HOLD := 0xFFC3E8
const RULE_SPOT := 0xFFC3EA
const QUOTE := 0xFFC4FE
const PHASE_TICK := 0xFFC602
const QUOTE_PTR := 0xFFC60E
const COACH_NAME := 0xFFC612
const QUOTE_VALUE := 0xFFC616
const PORTRAIT := 0xFFC618
const SPEAKER := 0xFFC636
const PLAYOFF_RESULT := 0xFFC638
const GOAL_KIND := 0xFFC63A
const SCORER := 0xFFC63C
const TICK := 0xFFCA56
const PADS := 0xFFCA5A
## Bytes a pass comparison skips: the corner collision's scratch object
## (`$FFC298`), and what the VBlank interrupt changes while the segment runs
## and the sound effects' queue (`$FFCA30`-`$FFCA4D`), the tick.
const IGNORE := [[0xFFC298, 0xFFC2B0], [0xFFCA30, 0xFFCA4E], [0xFFCA56, 0xFFCA5A]]


# --- big-endian access -----------------------------------------------------------

static func u8(r: PackedByteArray, a: int) -> int:
	return r[a - BASE]


static func s8(r: PackedByteArray, a: int) -> int:
	var v := r[a - BASE]
	return v - 256 if v >= 128 else v


static func u16(r: PackedByteArray, a: int) -> int:
	var i := a - BASE
	return (r[i] << 8) | r[i + 1]


static func s16(r: PackedByteArray, a: int) -> int:
	var v := u16(r, a)
	return v - 0x10000 if v >= 0x8000 else v


static func u32(r: PackedByteArray, a: int) -> int:
	var i := a - BASE
	return (r[i] << 24) | (r[i + 1] << 16) | (r[i + 2] << 8) | r[i + 3]


static func s32(r: PackedByteArray, a: int) -> int:
	var v := u32(r, a)
	return v - 0x100000000 if v >= 0x80000000 else v


static func w8(r: PackedByteArray, a: int, v: int) -> void:
	if a - BASE < r.size():
		r[a - BASE] = v & 0xFF


static func w16(r: PackedByteArray, a: int, v: int) -> void:
	w8(r, a, v >> 8)
	w8(r, a + 1, v)


static func w32(r: PackedByteArray, a: int, v: int) -> void:
	w16(r, a, v >> 16)
	w16(r, a + 2, v)


# --- objects ------------------------------------------------------------------------

static func player_address(t: int, i: int) -> int:
	return TEAMS[t] + PLAYERS + PLAYER_SIZE * i


## The object a RAM word (low half of an address) points at, or null.
static func object_at(s: MwRinkState, word: int) -> MwRinkState.Actor:
	if word == 0:
		return null
	var a := 0xFF0000 | word
	if a == PUCK:
		return s.puck
	if a == REF:
		return s.referee
	for t in 2:
		var p0: int = TEAMS[t] + PLAYERS
		if a >= p0 and a < p0 + 6 * PLAYER_SIZE and (a - p0) % PLAYER_SIZE == 0:
			return s.teams[t].players[(a - p0) / PLAYER_SIZE]
	for i in 8:
		if a == OBJECTS + OBJECT_SIZE * i:
			return s.objects[i]
	push_warning("MwRinkRam: no object at $%06X" % a)
	return null


## The RAM word of an object (0 for null).
static func word_of(s: MwRinkState, o: MwRinkState.Actor) -> int:
	if o == null:
		return 0
	if o == s.puck:
		return PUCK & 0xFFFF
	if o == s.referee:
		return REF & 0xFFFF
	if o is MwRinkState.Player:
		var p := o as MwRinkState.Player
		return player_address(p.team, p.index) & 0xFFFF
	for i in 8:
		if o == s.objects[i]:
			return (OBJECTS + OBJECT_SIZE * i) & 0xFFFF
	return 0


static func _motion(r: PackedByteArray, a: int, m: MwMotion) -> void:
	m.pos = PackedInt32Array([s32(r, a), s32(r, a + 8), s32(r, a + 0x10)])
	m.vel = PackedInt32Array([s16(r, a + 4), s16(r, a + 0xC), s16(r, a + 0x14)])
	m.acc = PackedInt32Array([s16(r, a + 6), s16(r, a + 0xE), s16(r, a + 0x16)])


static func _put_motion(r: PackedByteArray, a: int, m: MwMotion) -> void:
	for k in 3:
		w32(r, a + 8 * k, m.pos[k])
		w16(r, a + 8 * k + 4, m.vel[k])
		w16(r, a + 8 * k + 6, m.acc[k])


static func _anim(rom: PackedByteArray, r: PackedByteArray, a: int) -> MwAnimState:
	return MwAnimState.from_fields(rom, [u32(r, a), u16(r, a + 4), u8(r, a + 6), u8(r, a + 7), u16(r, a + 8), u8(r, a + 0xA)])


static func _put_anim(r: PackedByteArray, a: int, n: MwAnimState) -> void:
	w32(r, a, n.address)
	w16(r, a + 4, n.speed)
	w8(r, a + 6, n.flags)
	w8(r, a + 7, n.variant)
	w16(r, a + 8, n.position)
	w8(r, a + 0xA, n.frame)


static func _params(r: PackedByteArray, a: int) -> MwMotion.Params:
	var p := MwMotion.Params.new(s16(r, a), s16(r, a + 2), s16(r, a + 4), s16(r, a + 6))
	for i in 8:
		p.ground[i] = u16(r, a + 8 + 2 * i)
		p.air[i] = u16(r, a + 0x18 + 2 * i)
	return p


static func _put_params(r: PackedByteArray, a: int, p: MwMotion.Params) -> void:
	w16(r, a, p.gravity)
	w16(r, a + 2, p.restitution)
	w16(r, a + 4, p.friction_ground)
	w16(r, a + 6, p.friction_air)
	for i in 8:
		w16(r, a + 8 + 2 * i, p.ground[i])
		w16(r, a + 0x18 + 2 * i, p.air[i])


# --- decode -------------------------------------------------------------------------

## A new state from snapshot [param r].
static func decode(rom: PackedByteArray, r: PackedByteArray) -> MwRinkState:
	var s := MwRinkState.new()
	decode_into(rom, s, r)
	return s


## Fill [param s] from snapshot [param r] (an AI snapshot fills what it holds).
static func decode_into(rom: PackedByteArray, s: MwRinkState, r: PackedByteArray) -> void:
	var full := r.size() >= SIZE
	for p in 4:
		s.hold_bit[p] = u8(r, HOLD + 2 * p)
		s.hold_left[p] = s8(r, HOLD + 2 * p + 1)
	s.clock = u16(r, CLOCK)
	s.clock_text = r.slice(CLOCK_TEXT - BASE, CLOCK_TEXT - BASE + 6)
	s.clock_ref = u32(r, CLOCK_TIMER)
	s.clock_rate = u8(r, CLOCK_TIMER + 6)
	s.clock_flags = u8(r, CLOCK_TIMER + 7)
	s.period = u8(r, PERIOD)
	s.clock_widget = u8(r, CLOCK_WIDGET)
	s.pp_seconds = u16(r, PP_SECONDS)
	s.rng.state = u32(r, RNG)
	s.pad_mode = u8(r, PAD_MODE)
	s.stadium = u8(r, STADIUM)
	s.reserves = u8(r, RESERVES) != 0
	s.penalties = u8(r, PENALTIES)
	s.death_index = u8(r, DEATH_INDEX)
	s.camera.shown = Vector2i(s16(r, PLANE_B + 4), s16(r, PLANE_B + 6))
	s.plane_b_cell = Vector2i(u16(r, PLANE_B + 0x10), u16(r, PLANE_B + 0x12))
	s.scroll_b = Vector2i(u16(r, SCROLL_B), u16(r, SCROLL_B + 4))
	var c := s.camera
	c.speed = u16(r, RINK + 6)
	c.x = s32(r, RINK + 8)
	c.y = s32(r, RINK + 0xC)
	c.lead = s16(r, RINK + 0x10)
	c.shake = s16(r, RINK + 0x12)
	c.amp = s16(r, RINK + 0x14)
	c.shake_16 = s16(r, RINK + 0x16)
	s.player_params = _params(r, RINK + 0x64)
	s.puck_params = _params(r, RINK + 0x8C)
	for i in 2:
		var n := s.nets[i]
		var a: int = RINK + (0x18 if i == 0 else 0x3E)
		_motion(r, a, n.motion)
		n.anim = _anim(rom, r, a + 0x18)
		n.style = u8(r, a + 0x24)
		n.bottom = u8(r, a + 0x25) & 1 != 0
		var l := s.lamps[i]
		a = RINK + (0xB4 if i == 0 else 0xD8)
		_motion(r, a, l.motion)
		l.anim = _anim(rom, r, a + 0x18)
	for i in 4:
		var h := s.hazards[i]
		var a := HAZARDS + 10 * i
		h.x = s16(r, a)
		h.y = s16(r, a + 2)
		h.x4 = u32(r, a + 4)
		h.kind = u8(r, a + 8)
		h.flags = u8(r, a + 9)
	for i in 8:
		var o := s.objects[i]
		var a := OBJECTS + OBJECT_SIZE * i
		_motion(r, a, o.motion)
		o.anim = _anim(rom, r, a + 0x18)
		o.t24 = u16(r, a + 0x24)
		o.t26 = u16(r, a + 0x26)
		o.kind = u8(r, a + 0x28)
		o.flags = u8(r, a + 0x29)
	s.crowd = s16(r, RINK + 0x276)
	s.stadium_objects = u16(r, RINK + 0x274)
	# puck (references after the teams exist: same objects)
	for t in 2:
		var tm := s.teams[t]
		var b: int = TEAMS[t]
		tm.record = u32(r, b)
		tm.flags4 = u8(r, b + 4)
		tm.flags5 = u8(r, b + 5)
		for i in 24:
			tm.health[i] = u32(r, b + 6 + 4 * i)
		tm.pads = [u8(r, b + 0x66), u8(r, b + 0x67)]
		tm.pad_held = [u8(r, b + 0x68), u8(r, b + 0x6A)]
		tm.pad_new = [u8(r, b + 0x69), u8(r, b + 0x6B)]
		for i in 10:
			tm.x330[i] = u8(r, b + 0x330 + i)
		for k in 2:
			tm.arrows[k] = _anim(rom, r, b + (0x33A if k == 0 else 0x34E))
			var m := tm.markers[k]
			var a: int = b + (0x346 if k == 0 else 0x35A)
			m.x = s16(r, a)
			m.y = s16(r, a + 2)
			m.plate = u8(r, a + 4)
			m.number = u8(r, a + 5)
			m.position = u8(r, a + 6)
			m.health = u8(r, a + 7)
		for i in tm.stats.size():
			tm.stats[i] = u8(r, b + MwRinkState.Team.STATS_AT + i)
		tm.score = u16(r, b + 0x4A2)
		tm.attr = u8(r, b + 0x4A4)
		tm.special = u8(r, b + 0x4A5)
		tm.x4a6 = u8(r, b + 0x4A6)
		tm.mask = u8(r, b + 0x4A7)
		tm.formation = u8(r, b + 0x4A8)
		tm.x4a9 = u8(r, b + 0x4A9)
		for i in 6:
			decode_player(rom, s, r, t, i, false)
	for t in 2:
		var tm := s.teams[t]
		tm.nearest = object_at(s, u16(r, TEAMS[t] + 0x4A0)) as MwRinkState.Player
		for i in 6:
			var p := tm.players[i]
			p.victim = object_at(s, u16(r, player_address(t, i) + 0x3A))
	decode_puck(rom, s, r)
	s.camera_target = object_at(s, u16(r, RINK + 4))
	s.faceoff = _overlay(rom, r, FACEOFF)
	s.pass_count = u8(r, PASS_COUNT)
	s.impale = _anim(rom, r, IMPALE)
	s.bribe = u16(r, BRIBE)
	s.special_actor = object_at(s, u16(r, SPECIAL_ACTOR)) as MwRinkState.Player
	_motion(r, REF, s.referee.motion)
	s.referee.anim = _anim(rom, r, REF + 0x18)
	s.coop_toggle = u16(r, COOP)
	s.ref_flag = u8(r, REF + 0x24)
	if not full:
		return
	s.projection = u16(r, PROJECTION)
	s.drop_params = _params(r, DROP)
	s.be64 = u32(r, DROP + 0x28)
	for k in 4:
		s.plates[k] = _plate_values(rom, r, PLATES + 256 * k)
	s.penalty = _overlay(rom, r, PENALTY)
	s.stoppage = _overlay(rom, r, STOPPAGE)
	for i in 2:
		var o := s.shark_osc[i]
		var a := SHARK_OSC + 12 * i
		o.start = u32(r, a)
		o.base = s16(r, a + 4)
		o.amp = s16(r, a + 6)
		o.rate = u16(r, a + 8)
		o.phase = u16(r, a + 0xA)
	s.goal_message = u16(r, GOAL_MESSAGE)
	s.goal_message_step = u16(r, GOAL_MESSAGE + 2)
	var rp := s.replay
	rp.base = u32(r, REPLAY)
	rp.size = u16(r, REPLAY + 4)
	rp.callback = u32(r, REPLAY + 6)
	rp.write = u16(r, REPLAY + 0xA)
	rp.read = u16(r, REPLAY + 0xC)
	rp.used = u16(r, REPLAY + 0xE)
	rp.frames = u16(r, REPLAY + 0x10)
	rp.frame_start = u16(r, REPLAY + 0x12)
	rp.open = u8(r, REPLAY + 0x14)
	rp.playback = u8(r, REPLAY + 0x15)
	rp.pan = Vector2i(s16(r, REPLAY + 0x16), s16(r, REPLAY + 0x18))
	s.penalty_tick = u32(r, PENALTY_TICK)
	s.box_clock = u16(r, BOX_CLOCK)
	s.faceoff_step = u8(r, FACEOFF_STEP)
	s.pass_tick = u32(r, PASS_TICK)
	s.first_pass = u16(r, FIRST_PASS)
	s.replay_on = u16(r, REPLAY_ON)
	s.crowd_quiet = u16(r, CROWD_QUIET)
	s.jail_tick = u32(r, JAIL)
	s.jail_count = u16(r, JAIL + 4)
	s.faceoff_spot = u8(r, FACEOFF_SPOT)
	s.ai_off = u16(r, AI_OFF)
	s.crease_y = s16(r, CREASE_Y)
	s.puck_rule = u16(r, PUCK_RULE)
	s.phase = u16(r, PHASE)
	s.subphase = u16(r, SUBPHASE)
	s.scoring = u32(r, SCORING)
	s.goal_points = u16(r, GOAL_POINTS)
	s.fight_block = u16(r, FIGHT_BLOCK)
	s.tick = u32(r, TICK)
	_decode_flow(rom, s, r)
	for p in 4:
		s.pads_held[p] = u8(r, PADS + 2 * p)
		s.pads_new[p] = u8(r, PADS + 2 * p + 1)


static func decode_puck(rom: PackedByteArray, s: MwRinkState, r: PackedByteArray) -> void:
	var pk := s.puck
	_motion(r, PUCK, pk.motion)
	pk.anim = _anim(rom, r, PUCK + 0x18)
	pk.take_tick = u32(r, PUCK + 0x26)
	pk.owner_log = u32(r, PUCK + 0x2A)
	pk.x2e = u32(r, PUCK + 0x2E)
	pk.ring = u8(r, PUCK + 0x32)
	pk.touches = u8(r, PUCK + 0x33)
	pk.prev_x = s16(r, PUCK + 0x34)
	pk.prev_y = s16(r, PUCK + 0x36)
	pk.release_y = s16(r, PUCK + 0x38)
	pk.receiver_angle = u8(r, PUCK + 0x3C)
	pk.flags = u8(r, PUCK + 0x3D)
	pk.lock = u8(r, PUCK + 0x3E)
	pk.x3f = u8(r, PUCK + 0x3F)
	pk.carrier = object_at(s, u16(r, PUCK + 0x24)) as MwRinkState.Player
	pk.receiver = object_at(s, u16(r, PUCK + 0x3A))


static func encode_puck(s: MwRinkState, r: PackedByteArray) -> void:
	var pk := s.puck
	_put_motion(r, PUCK, pk.motion)
	_put_anim(r, PUCK + 0x18, pk.anim)
	w16(r, PUCK + 0x24, word_of(s, pk.carrier))
	w32(r, PUCK + 0x26, pk.take_tick)
	w32(r, PUCK + 0x2A, pk.owner_log)
	w32(r, PUCK + 0x2E, pk.x2e)
	w8(r, PUCK + 0x32, pk.ring)
	w8(r, PUCK + 0x33, pk.touches)
	w16(r, PUCK + 0x34, pk.prev_x)
	w16(r, PUCK + 0x36, pk.prev_y)
	w16(r, PUCK + 0x38, pk.release_y)
	w16(r, PUCK + 0x3A, word_of(s, pk.receiver))
	w8(r, PUCK + 0x3C, pk.receiver_angle)
	w8(r, PUCK + 0x3D, pk.flags)
	w8(r, PUCK + 0x3E, pk.lock)
	w8(r, PUCK + 0x3F, pk.x3f)


## Player [param i] of team [param t] from [param r] (references too, unless
## [param refs] is false: then they wait for the whole state).
static func decode_player(rom: PackedByteArray, s: MwRinkState, r: PackedByteArray, t: int, i: int, refs := true) -> void:
	var p := s.teams[t].players[i]
	var a := player_address(t, i)
	_motion(r, a, p.motion)
	p.anim = _anim(rom, r, a + 0x18)
	p.target_x = s16(r, a + 0x24)
	p.target_y = s16(r, a + 0x26)
	p.ai_x = s16(r, a + 0x28)
	p.ai_y = s16(r, a + 0x2A)
	p.ai_zone = u16(r, a + 0x2C)
	p.bone_tick = u32(r, a + 0x2E)
	p.record = u32(r, a + 0x32)
	p.original = u32(r, a + 0x36)
	p.init_roll = u8(r, a + 0x3C)
	p.x3d = u8(r, a + 0x3D)
	p.x3e = u8(r, a + 0x3E)
	p.x3f = u8(r, a + 0x3F)
	p.puck_dist = u16(r, a + 0x40)
	p.puck_angle = u8(r, a + 0x5A)
	for j in 6:
		p.mate_dist[j] = u16(r, a + 0x42 + 2 * j)
		p.mate_angle[j] = u8(r, a + 0x5B + j)
		p.opp_dist[j] = u16(r, a + 0x4E + 2 * j)
		p.opp_angle[j] = u8(r, a + 0x61 + j)
	p.index = u8(r, a + 0x67)
	p.slot = u8(r, a + 0x68)
	p.position = u8(r, a + 0x69)
	p.role = u8(r, a + 0x6A)
	p.think = s8(r, a + 0x6B)
	p.penalty = u8(r, a + 0x6C)
	p.weapon = s8(r, a + 0x6D)
	p.charges = u8(r, a + 0x6E)
	p.anim_id = u8(r, a + 0x6F)
	p.state = u8(r, a + 0x70)
	p.substate = u8(r, a + 0x71)
	p.attacker = u8(r, a + 0x72)
	p.angle = u8(r, a + 0x73)
	p.flags = u8(r, a + 0x74)
	p.flags2 = u8(r, a + 0x75)
	p.team = t
	if refs:
		p.victim = object_at(s, u16(r, a + 0x3A))


static func _overlay(rom: PackedByteArray, r: PackedByteArray, a: int) -> MwRinkState.Overlay:
	var o := MwRinkState.Overlay.new()
	o.anim = _anim(rom, r, a)
	o.x = s16(r, a + 0xC)
	o.y = s16(r, a + 0xE)
	o.depth = u16(r, a + 0x10)
	o.attr = u8(r, a + 0x12)
	o.flags = u8(r, a + 0x13)
	return o


static func _put_overlay(r: PackedByteArray, a: int, o: MwRinkState.Overlay) -> void:
	_put_anim(r, a, o.anim)
	w16(r, a + 0xC, o.x)
	w16(r, a + 0xE, o.y)
	w16(r, a + 0x10, o.depth)
	w8(r, a + 0x12, o.attr)
	w8(r, a + 0x13, o.flags)


## What a plate's RAM tiles show (MwPlate.tiles in reverse; $FF = blank).
static func _plate_values(rom: PackedByteArray, r: PackedByteArray, a: int) -> Array:
	var data := r.slice(a - BASE, a - BASE + 256)
	return MwPlate.values(rom, data)


# --- encode -------------------------------------------------------------------------

## [param template] (a snapshot) with every field of [param s] written in.
static func encode(s: MwRinkState, template: PackedByteArray) -> PackedByteArray:
	var r := template.duplicate()
	var full := r.size() >= SIZE
	for p in 4:
		w8(r, HOLD + 2 * p, s.hold_bit[p])
		w8(r, HOLD + 2 * p + 1, s.hold_left[p])
	w16(r, CLOCK, s.clock)
	for i in 6:
		w8(r, CLOCK_TEXT + i, s.clock_text[i])
	w32(r, CLOCK_TIMER, s.clock_ref)
	w8(r, CLOCK_TIMER + 6, s.clock_rate)
	w8(r, CLOCK_TIMER + 7, s.clock_flags)
	w8(r, PERIOD, s.period)
	w8(r, CLOCK_WIDGET, s.clock_widget)
	w16(r, PP_SECONDS, s.pp_seconds)
	w32(r, RNG, s.rng.state)
	w8(r, DEATH_INDEX, s.death_index)
	w8(r, PENALTIES, s.penalties)
	w16(r, PLANE_B + 4, s.camera.shown.x)
	w16(r, PLANE_B + 6, s.camera.shown.y)
	w16(r, PLANE_B + 0x10, s.plane_b_cell.x)
	w16(r, PLANE_B + 0x12, s.plane_b_cell.y)
	w16(r, SCROLL_B, s.scroll_b.x)
	w16(r, SCROLL_B + 4, s.scroll_b.y)
	var c := s.camera
	w16(r, RINK + 4, word_of(s, s.camera_target))
	w16(r, RINK + 6, c.speed)
	w32(r, RINK + 8, c.x)
	w32(r, RINK + 0xC, c.y)
	w16(r, RINK + 0x10, c.lead)
	w16(r, RINK + 0x12, c.shake)
	w16(r, RINK + 0x14, c.amp)
	w16(r, RINK + 0x16, c.shake_16)
	_put_params(r, RINK + 0x64, s.player_params)
	_put_params(r, RINK + 0x8C, s.puck_params)
	for i in 2:
		var n := s.nets[i]
		var a: int = RINK + (0x18 if i == 0 else 0x3E)
		_put_motion(r, a, n.motion)
		_put_anim(r, a + 0x18, n.anim)
		w8(r, a + 0x24, n.style)
		w8(r, a + 0x25, (u8(r, a + 0x25) & ~1) | (1 if n.bottom else 0))
		var l := s.lamps[i]
		a = RINK + (0xB4 if i == 0 else 0xD8)
		_put_motion(r, a, l.motion)
		_put_anim(r, a + 0x18, l.anim)
	for i in 4:
		var h := s.hazards[i]
		var a := HAZARDS + 10 * i
		w16(r, a, h.x)
		w16(r, a + 2, h.y)
		w32(r, a + 4, h.x4)
		w8(r, a + 8, h.kind)
		w8(r, a + 9, h.flags)
	for i in 8:
		var o := s.objects[i]
		var a := OBJECTS + OBJECT_SIZE * i
		_put_motion(r, a, o.motion)
		_put_anim(r, a + 0x18, o.anim)
		w16(r, a + 0x24, o.t24)
		w16(r, a + 0x26, o.t26)
		w8(r, a + 0x28, o.kind)
		w8(r, a + 0x29, o.flags)
	w16(r, RINK + 0x276, s.crowd)
	w16(r, RINK + 0x274, s.stadium_objects)
	encode_puck(s, r)
	for t in 2:
		var tm := s.teams[t]
		var b: int = TEAMS[t]
		w32(r, b, tm.record)
		w8(r, b + 4, tm.flags4)
		w8(r, b + 5, tm.flags5)
		for i in 24:
			w32(r, b + 6 + 4 * i, tm.health[i])
		w8(r, b + 0x66, tm.pads[0])
		w8(r, b + 0x67, tm.pads[1])
		w8(r, b + 0x68, tm.pad_held[0])
		w8(r, b + 0x6A, tm.pad_held[1])
		w8(r, b + 0x69, tm.pad_new[0])
		w8(r, b + 0x6B, tm.pad_new[1])
		for i in 10:
			w8(r, b + 0x330 + i, tm.x330[i])
		for k in 2:
			_put_anim(r, b + (0x33A if k == 0 else 0x34E), tm.arrows[k])
			var m := tm.markers[k]
			var a: int = b + (0x346 if k == 0 else 0x35A)
			w16(r, a, m.x)
			w16(r, a + 2, m.y)
			w8(r, a + 4, m.plate)
			w8(r, a + 5, m.number)
			w8(r, a + 6, m.position)
			w8(r, a + 7, m.health)
		for i in tm.stats.size():
			w8(r, b + MwRinkState.Team.STATS_AT + i, tm.stats[i])
		w16(r, b + 0x4A0, word_of(s, tm.nearest))
		w16(r, b + 0x4A2, tm.score)
		w8(r, b + 0x4A4, tm.attr)
		w8(r, b + 0x4A5, tm.special)
		w8(r, b + 0x4A6, tm.x4a6)
		w8(r, b + 0x4A7, tm.mask)
		w8(r, b + 0x4A8, tm.formation)
		w8(r, b + 0x4A9, tm.x4a9)
		for i in 6:
			encode_player(s, r, t, i)
	_put_overlay(r, FACEOFF, s.faceoff)
	w8(r, PASS_COUNT, s.pass_count)
	_put_anim(r, IMPALE, s.impale)
	w16(r, BRIBE, s.bribe)
	w16(r, SPECIAL_ACTOR, word_of(s, s.special_actor))
	_put_motion(r, REF, s.referee.motion)
	_put_anim(r, REF + 0x18, s.referee.anim)
	w16(r, COOP, s.coop_toggle)
	w8(r, REF + 0x24, s.ref_flag)
	if not full:
		return r
	_put_params(r, DROP, s.drop_params)
	w32(r, DROP + 0x28, s.be64)
	_put_plates(s, r)
	_put_overlay(r, PENALTY, s.penalty)
	_put_overlay(r, STOPPAGE, s.stoppage)
	for i in 2:
		var o := s.shark_osc[i]
		var a := SHARK_OSC + 12 * i
		w32(r, a, o.start)
		w16(r, a + 4, o.base)
		w16(r, a + 6, o.amp)
		w16(r, a + 8, o.rate)
		w16(r, a + 0xA, o.phase)
	w16(r, GOAL_MESSAGE, s.goal_message)
	w16(r, GOAL_MESSAGE + 2, s.goal_message_step)
	var rp := s.replay
	w32(r, REPLAY, rp.base)
	w16(r, REPLAY + 4, rp.size)
	w32(r, REPLAY + 6, rp.callback)
	w16(r, REPLAY + 0xA, rp.write)
	w16(r, REPLAY + 0xC, rp.read)
	w16(r, REPLAY + 0xE, rp.used)
	w16(r, REPLAY + 0x10, rp.frames)
	w16(r, REPLAY + 0x12, rp.frame_start)
	w8(r, REPLAY + 0x14, rp.open)
	w8(r, REPLAY + 0x15, rp.playback)
	w16(r, REPLAY + 0x16, rp.pan.x)
	w16(r, REPLAY + 0x18, rp.pan.y)
	w32(r, PENALTY_TICK, s.penalty_tick)
	w16(r, BOX_CLOCK, s.box_clock)
	w8(r, FACEOFF_STEP, s.faceoff_step)
	w32(r, PASS_TICK, s.pass_tick)
	w16(r, FIRST_PASS, s.first_pass)
	w16(r, REPLAY_ON, s.replay_on)
	w16(r, CROWD_QUIET, s.crowd_quiet)
	w32(r, JAIL, s.jail_tick)
	w16(r, JAIL + 4, s.jail_count)
	w8(r, FACEOFF_SPOT, s.faceoff_spot)
	w16(r, AI_OFF, s.ai_off)
	w16(r, CREASE_Y, s.crease_y)
	w16(r, PUCK_RULE, s.puck_rule)
	w16(r, PHASE, s.phase)
	w16(r, SUBPHASE, s.subphase)
	w32(r, SCORING, s.scoring)
	w16(r, GOAL_POINTS, s.goal_points)
	w16(r, FIGHT_BLOCK, s.fight_block)
	for p in 4:
		w8(r, PADS + 2 * p, s.pads_held[p])
		w8(r, PADS + 2 * p + 1, s.pads_new[p])
	_encode_flow(s, r)
	return r


## The match flow's fields (MwRinkPhases: phase handler, pause menu, coach
## speech, faceoff and goal sequences, puck rules) from [param r].
static func _decode_flow(rom: PackedByteArray, s: MwRinkState, r: PackedByteArray) -> void:
	s.play_mode = u8(r, PLAY_MODE)
	s.period_minutes = u8(r, MINUTES)
	s.period_row = u8(r, PERIOD_ROW)
	s.pause_team = u16(r, PAUSE)
	s.pause_attr = u16(r, PAUSE + 2)
	s.pause_pad = u16(r, PAUSE + 4)
	s.pause_offer = u16(r, PAUSE + 6)
	var po := s.playoffs
	po.rng.state = u32(r, PLAYOFFS)
	po.dead = PackedInt32Array([u32(r, PLAYOFFS + 4), u32(r, PLAYOFFS + 8)])
	po.seed = u16(r, PLAYOFFS + 0xC)
	po.pair = u8(r, PLAYOFFS + 0xE)
	po.conference = u8(r, PLAYOFFS + 0xF)
	po.best_of_3 = u8(r, PLAYOFFS + 0x10)
	po.flag_11 = u8(r, PLAYOFFS + 0x11)
	po.series = u8(r, PLAYOFFS + 0x12)
	po.round = u8(r, PLAYOFFS + 0x13)
	po.flags = u8(r, PLAYOFFS + 0x14)
	s.ref_attr = u8(r, REF + 0x25)
	s.goal_tick = u32(r, GOAL_TICK)
	s.goal_net = u16(r, GOAL_NET)
	s.goal_net_frame = u16(r, GOAL_NET + 2)
	s.penalty_step = u16(r, PENALTY_STEP)
	s.faceoff_tick = u32(r, FACEOFF_TICK)
	s.faceoff_text = u16(r, FACEOFF_TEXT)
	s.drop_plane = Vector2i(s16(r, DROP_PLANE), s16(r, DROP_PLANE + 2))
	_motion(r, DROP_OBJ, s.drop)
	for i in 4:
		s.speech_box[i] = s16(r, SPEECH_BOX + 2 * i)
	var tb := s.text_box
	tb.plane = u32(r, TEXT_BOX)
	tb.font = u32(r, TEXT_BOX + 4)
	tb.x = s16(r, TEXT_BOX + 8)
	tb.y = s16(r, TEXT_BOX + 0xA)
	tb.w = s16(r, TEXT_BOX + 0xC)
	tb.h = s16(r, TEXT_BOX + 0xE)
	tb.spacing = s16(r, TEXT_BOX + 0x10)
	tb.cursor_x = s16(r, TEXT_BOX + 0x12)
	tb.cursor_y = s16(r, TEXT_BOX + 0x14)
	s.box_fill = u16(r, BOX_FILL)
	s.box_c3bc = u16(r, BOX_C3BC)
	s.stop_tick = u32(r, STOP_TICK)
	s.rule_team_b = u8(r, RULE_TEAM_B)
	s.rule_clock = u16(r, RULE_CLOCK)
	s.rule_hold = u16(r, RULE_HOLD)
	s.rule_spot = Vector2i(s16(r, RULE_SPOT), s16(r, RULE_SPOT + 2))
	s.quote = r.slice(QUOTE - BASE, QUOTE - BASE + MwRinkState.QUOTE_SIZE)
	s.phase_tick = u32(r, PHASE_TICK)
	s.quote_ptr = u32(r, QUOTE_PTR)
	s.coach_name = u32(r, COACH_NAME)
	s.quote_value = u16(r, QUOTE_VALUE)
	var pt := s.portrait
	pt.anim = _anim(rom, r, PORTRAIT)
	pt.x0b = u8(r, PORTRAIT + 0xB)
	pt.data = u32(r, PORTRAIT + 0xC)
	pt.x10 = u16(r, PORTRAIT + 0x10)
	pt.mode = u16(r, PORTRAIT + 0x12)
	pt.timer = u16(r, PORTRAIT + 0x14)
	pt.size = u16(r, PORTRAIT + 0x16)
	pt.handle = u32(r, PORTRAIT + 0x18)
	pt.voices = u16(r, PORTRAIT + 0x1C)
	pt.x1e = u16(r, PORTRAIT + 0x1E)
	s.speaker = u16(r, SPEAKER)
	s.playoff_result = u16(r, PLAYOFF_RESULT)
	s.goal_kind = u16(r, GOAL_KIND)
	s.scorer = u32(r, SCORER)


static func _encode_flow(s: MwRinkState, r: PackedByteArray) -> void:
	w8(r, PLAY_MODE, s.play_mode)
	w8(r, MINUTES, s.period_minutes)
	w8(r, PERIOD_ROW, s.period_row)
	w16(r, PAUSE, s.pause_team)
	w16(r, PAUSE + 2, s.pause_attr)
	w16(r, PAUSE + 4, s.pause_pad)
	w16(r, PAUSE + 6, s.pause_offer)
	var po := s.playoffs
	w32(r, PLAYOFFS, po.rng.state)
	w32(r, PLAYOFFS + 4, po.dead[0])
	w32(r, PLAYOFFS + 8, po.dead[1])
	w16(r, PLAYOFFS + 0xC, po.seed)
	w8(r, PLAYOFFS + 0xE, po.pair)
	w8(r, PLAYOFFS + 0xF, po.conference)
	w8(r, PLAYOFFS + 0x10, po.best_of_3)
	w8(r, PLAYOFFS + 0x11, po.flag_11)
	w8(r, PLAYOFFS + 0x12, po.series)
	w8(r, PLAYOFFS + 0x13, po.round)
	w8(r, PLAYOFFS + 0x14, po.flags)
	w8(r, REF + 0x25, s.ref_attr)
	w32(r, GOAL_TICK, s.goal_tick)
	w16(r, GOAL_NET, s.goal_net)
	w16(r, GOAL_NET + 2, s.goal_net_frame)
	w16(r, PENALTY_STEP, s.penalty_step)
	w32(r, FACEOFF_TICK, s.faceoff_tick)
	w16(r, FACEOFF_TEXT, s.faceoff_text)
	w16(r, DROP_PLANE, s.drop_plane.x)
	w16(r, DROP_PLANE + 2, s.drop_plane.y)
	_put_motion(r, DROP_OBJ, s.drop)
	for i in 4:
		w16(r, SPEECH_BOX + 2 * i, s.speech_box[i])
	var tb := s.text_box
	w32(r, TEXT_BOX, tb.plane)
	w32(r, TEXT_BOX + 4, tb.font)
	w16(r, TEXT_BOX + 8, tb.x)
	w16(r, TEXT_BOX + 0xA, tb.y)
	w16(r, TEXT_BOX + 0xC, tb.w)
	w16(r, TEXT_BOX + 0xE, tb.h)
	w16(r, TEXT_BOX + 0x10, tb.spacing)
	w16(r, TEXT_BOX + 0x12, tb.cursor_x)
	w16(r, TEXT_BOX + 0x14, tb.cursor_y)
	w16(r, BOX_FILL, s.box_fill)
	w16(r, BOX_C3BC, s.box_c3bc)
	w32(r, STOP_TICK, s.stop_tick)
	w8(r, RULE_TEAM_B, s.rule_team_b)
	w16(r, RULE_CLOCK, s.rule_clock)
	w16(r, RULE_HOLD, s.rule_hold)
	w16(r, RULE_SPOT, s.rule_spot.x)
	w16(r, RULE_SPOT + 2, s.rule_spot.y)
	for i in MwRinkState.QUOTE_SIZE:
		w8(r, QUOTE + i, s.quote[i])
	w32(r, PHASE_TICK, s.phase_tick)
	w32(r, QUOTE_PTR, s.quote_ptr)
	w32(r, COACH_NAME, s.coach_name)
	w16(r, QUOTE_VALUE, s.quote_value)
	var pt := s.portrait
	_put_anim(r, PORTRAIT, pt.anim)
	w8(r, PORTRAIT + 0xB, pt.x0b)
	w32(r, PORTRAIT + 0xC, pt.data)
	w16(r, PORTRAIT + 0x10, pt.x10)
	w16(r, PORTRAIT + 0x12, pt.mode)
	w16(r, PORTRAIT + 0x14, pt.timer)
	w16(r, PORTRAIT + 0x16, pt.size)
	w32(r, PORTRAIT + 0x18, pt.handle)
	w16(r, PORTRAIT + 0x1C, pt.voices)
	w16(r, PORTRAIT + 0x1E, pt.x1e)
	w16(r, SPEAKER, s.speaker)
	w16(r, PLAYOFF_RESULT, s.playoff_result)
	w16(r, GOAL_KIND, s.goal_kind)
	w32(r, SCORER, s.scorer)


## Player [param i] of team [param t] into [param r].
static func encode_player(s: MwRinkState, r: PackedByteArray, t: int, i: int) -> void:
	var p := s.teams[t].players[i]
	var a := player_address(t, i)
	_put_motion(r, a, p.motion)
	_put_anim(r, a + 0x18, p.anim)
	w16(r, a + 0x24, p.target_x)
	w16(r, a + 0x26, p.target_y)
	w16(r, a + 0x28, p.ai_x)
	w16(r, a + 0x2A, p.ai_y)
	w16(r, a + 0x2C, p.ai_zone)
	w32(r, a + 0x2E, p.bone_tick)
	w32(r, a + 0x32, p.record)
	w32(r, a + 0x36, p.original)
	w16(r, a + 0x3A, word_of(s, p.victim))
	w8(r, a + 0x3C, p.init_roll)
	w8(r, a + 0x3D, p.x3d)
	w8(r, a + 0x3E, p.x3e)
	w8(r, a + 0x3F, p.x3f)
	w16(r, a + 0x40, p.puck_dist)
	w8(r, a + 0x5A, p.puck_angle)
	for j in 6:
		w16(r, a + 0x42 + 2 * j, p.mate_dist[j])
		w8(r, a + 0x5B + j, p.mate_angle[j])
		w16(r, a + 0x4E + 2 * j, p.opp_dist[j])
		w8(r, a + 0x61 + j, p.opp_angle[j])
	w8(r, a + 0x67, p.index)
	w8(r, a + 0x68, p.slot)
	w8(r, a + 0x69, p.position)
	w8(r, a + 0x6A, p.role)
	w8(r, a + 0x6B, p.think)
	w8(r, a + 0x6C, p.penalty)
	w8(r, a + 0x6D, p.weapon)
	w8(r, a + 0x6E, p.charges)
	w8(r, a + 0x6F, p.anim_id)
	w8(r, a + 0x70, p.state)
	w8(r, a + 0x71, p.substate)
	w8(r, a + 0x72, p.attacker)
	w8(r, a + 0x73, p.angle)
	w8(r, a + 0x74, p.flags)
	w8(r, a + 0x75, p.flags2)


## Plates are written only where their values changed from the template's:
## the tiles of a plate the state did not touch stay byte for byte.
static func _put_plates(s: MwRinkState, r: PackedByteArray) -> void:
	var rom := MwRom.data()
	for k in 4:
		var v: Array = s.plates[k]
		var a := PLATES + 256 * k
		var was := MwPlate.values(rom, r.slice(a - BASE, a - BASE + 256))
		if was == v:
			continue
		var b := MwPlate.tiles(rom, v[0], v[1], v[2])
		for i in 256:
			r[a - BASE + i] = b[i]


# --- patching (replayed CPU thinks) ------------------------------------------------------

## Apply to [param s] what changed between AI snapshots [param pre] and
## [param post]: the players and the puck that changed, the RNG; anything
## else falls back to a whole encode / decode.
static func patch(rom: PackedByteArray, s: MwRinkState, pre: PackedByteArray, post: PackedByteArray) -> void:
	if pre == post:
		return
	var check := pre.duplicate()
	var touched: Array = []
	for t in 2:
		for i in 6:
			var a := player_address(t, i) - BASE
			var b := a + PLAYER_SIZE
			if pre.slice(a, b) != post.slice(a, b):
				touched.append([t, i])
				for j in range(a, b):
					check[j] = post[j]
	var pa := PUCK - BASE
	var puck := pre.slice(pa, pa + 0x40) != post.slice(pa, pa + 0x40)
	if puck:
		for j in range(pa, pa + 0x40):
			check[j] = post[j]
	var ra := RNG - BASE
	for j in range(ra, ra + 4):
		check[j] = post[j]
	if check != post:
		var ours := encode(s, pre)
		for j in pre.size():
			if pre[j] != post[j]:
				ours[j] = post[j]
		decode_into(rom, s, ours)
		return
	var buf := pre.duplicate()
	for ti in touched:
		encode_player(s, buf, ti[0], ti[1])
		var a := player_address(ti[0], ti[1]) - BASE
		for j in range(a, a + PLAYER_SIZE):
			if pre[j] != post[j]:
				buf[j] = post[j]
		decode_player(rom, s, buf, ti[0], ti[1])
	if puck:
		encode_puck(s, buf)
		for j in range(pa, pa + 0x40):
			if pre[j] != post[j]:
				buf[j] = post[j]
		decode_puck(rom, s, buf)
	s.rng.state = u32(post, RNG)


# --- comparison ---------------------------------------------------------------------

## Addresses where [param a] and [param b] differ (outside [constant IGNORE]).
static func diff(a: PackedByteArray, b: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := mini(a.size(), b.size())
	if a.slice(0, n) == b.slice(0, n):
		return out
	for i in n:
		if a[i] != b[i]:
			var addr := BASE + i
			var skip := false
			for g in IGNORE:
				if addr >= g[0] and addr < g[1]:
					skip = true
					break
			if not skip:
				out.append(addr)
	return out


## A name for RAM address [param a] ("T0 P3 +$70 state").
static func describe(a: int) -> String:
	for t in 2:
		var b: int = TEAMS[t]
		if a >= b and a < b + 0x4AA:
			var o := a - b
			if o >= PLAYERS and o < PLAYERS + 6 * PLAYER_SIZE:
				var po := (o - PLAYERS) % PLAYER_SIZE
				return "T%d P%d +$%02X %s" % [t, (o - PLAYERS) / PLAYER_SIZE, po, _player_field(po)]
			return "T%d +$%03X" % [t, o]
	if a >= PUCK and a < PUCK + 0x40:
		return "puck +$%02X" % (a - PUCK)
	if a >= OBJECTS and a < OBJECTS + 8 * OBJECT_SIZE:
		return "object %d +$%02X" % [(a - OBJECTS) / OBJECT_SIZE, (a - OBJECTS) % OBJECT_SIZE]
	if a >= HAZARDS and a < HAZARDS + 40:
		return "hazard %d +%d" % [(a - HAZARDS) / 10, (a - HAZARDS) % 10]
	if a >= RINK and a < RINK + 0x2DA:
		return "rink +$%03X" % (a - RINK)
	if a >= PLATES and a < PLATES + 0x400:
		return "plate %d" % ((a - PLATES) / 256)
	# the fields between segments (MwRinkUpdate)
	var named := [[CLOCK_TEXT, 6, "clock text"], [CLOCK_TIMER, 8, "clock timer"], [PERIOD, 1, "period"],
			[CLOCK_WIDGET, 1, "clock widget"], [PP_SECONDS, 2, "power-play seconds"], [PLANE_B, 0x18, "plane B"], [SCROLL_B, 6, "scroll B"],
			[SHARK_OSC, 24, "shark target"], [GOAL_MESSAGE, 4, "goal message"], [REPLAY, 0x1A, "replay ring"],
			[PENALTY_TICK, 4, "penalty icon stamp"], [BOX_CLOCK, 2, "box clock"], [PASS_TICK, 4, "pass tick"],
			[FIRST_PASS, 2, "first pass"], [REPLAY_ON, 2, "replay on"], [CROWD_QUIET, 2, "crowd quiet"],
			[PLAY_MODE, 1, "play mode"], [MINUTES, 1, "period minutes"], [PAUSE, 8, "pause menu"],
			[PLAYOFFS, 0x15, "playoffs"], [GOAL_TICK, 4, "goal stamp"], [GOAL_POINTS, 2, "goal points"],
			[GOAL_NET, 4, "goal Demon Net"], [PENALTY_STEP, 2, "penalty step"], [FACEOFF_TICK, 4, "faceoff stamp"],
			[FACEOFF_TEXT, 2, "faceoff text"], [DROP_PLANE, 4, "drop plane B"], [DROP_OBJ, 0x18, "FACE OFF! drop"],
			[FACEOFF_STEP, 1, "faceoff step"], [FACEOFF_SPOT, 1, "faceoff spot"], [SPEECH_BOX, 8, "speech box"],
			[TEXT_BOX, 0x16, "text box"], [BOX_FILL, 2, "box fill"], [BOX_C3BC, 2, "box $C3BC"],
			[STOPPAGE, 0x14, "stoppage icon"], [STOP_TICK, 4, "stoppage stamp"], [CREASE_Y, 2, "puck rule y"],
			[PUCK_RULE, 2, "puck rule"], [RULE_TEAM_B, 1, "puck rule team B"], [RULE_CLOCK, 2, "puck rule clock"],
			[RULE_HOLD, 2, "puck rule hold"], [RULE_SPOT, 4, "puck rule spot"], [QUOTE, MwRinkState.QUOTE_SIZE, "quote"],
			[PHASE_TICK, 4, "phase stamp"], [PHASE, 2, "phase"], [SUBPHASE, 2, "subphase"], [QUOTE_PTR, 4, "quote address"],
			[COACH_NAME, 4, "coach name"], [QUOTE_VALUE, 2, "quote value"], [PORTRAIT, 0x20, "coach portrait"],
			[SPEAKER, 2, "speaking side"], [PLAYOFF_RESULT, 2, "playoff result"], [GOAL_KIND, 2, "goal situation"],
			[SCORER, 4, "scorer"], [SCORING, 4, "event team"], [PENALTY, 0x14, "penalty icon"]]
	for n in named:
		if a >= int(n[0]) and a < int(n[0]) + int(n[1]):
			return "%s +$%02X" % [n[2], a - int(n[0])]
	return "$%06X" % a


static func _player_field(o: int) -> String:
	if o < 0x18:
		return ["x", "x", "x", "x", "vx", "vx", "ax", "ax", "y", "y", "y", "y", "vy", "vy", "ay", "ay",
				"z", "z", "z", "z", "vz", "vz", "az", "az"][o]
	if o < 0x24:
		return "anim"
	var names := {0x24: "target", 0x28: "ai", 0x2E: "bone_tick", 0x32: "record", 0x36: "original",
			0x3A: "victim", 0x3C: "init_roll", 0x40: "puck_dist", 0x42: "mate_dist", 0x4E: "opp_dist",
			0x5A: "puck_angle", 0x5B: "mate_angle", 0x61: "opp_angle", 0x67: "index", 0x68: "slot",
			0x69: "position", 0x6A: "role", 0x6B: "think", 0x6C: "penalty", 0x6D: "weapon", 0x6E: "charges",
			0x6F: "anim_id", 0x70: "state", 0x71: "substate", 0x72: "attacker", 0x73: "angle",
			0x74: "flags", 0x75: "flags2"}
	var best := ""
	for k in names:
		if k <= o:
			best = names[k]
	return best
