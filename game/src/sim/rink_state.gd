class_name MwRinkState
extends RefCounted
## The rink's objects, node-free, with the original's fields (docs/re/rink.md,
## Objects): the camera, the two teams (on-ice players, off-screen arrows,
## markers), the puck, the two nets, four in-ice hazard slots, eight rink
## object slots, the goal lamps and the overlays. This is what the draw pass
## ([MwRinkDraw]) and the camera read; plan 08's simulation moves it.
##
## Filled by [method setup] (the stadium part of `rink_setup` $5572) or
## [method from_dict] (a pass recorded from the original,
## harness/mw_harness/rink_state.py). RAM addresses are kept only in the
## docs: references between objects (puck carrier, camera target) are
## object references here. Plan 08 adds every field the simulation segment
## (game/src/sim/rink_sim.gd) reads or writes; the comparison layer
## (game/src/compare/rink_ram.gd) maps them to the original's RAM.

## Phases (`$FFC60A`, docs/re/screens.md) the drawing and camera test.
const PHASE_PLAY := 0
const PHASE_FACEOFF := 1
const PHASE_GOAL := 3        ## the goal sequence (`$FDD2`): blink, lamp, panel
const PHASE_FIGHT := 4
const PHASE_START := 9
const PHASE_REF := 12
const PHASE_FACEOFF_BANNER := 14

## Plan 40 (S1): what each of the port's own fields of the rink's state
## (none of them the original's RAM) is to the comparison layer
## (MwSimDict), the online hash (MwNetHash) and the resync snapshot
## (MwNetSnapshot) - the one declaration they read, so a new field is
## decided once, here (test_port_fields: every field is the original's or
## listed):
## [b]IN_DICT[/b]: in MwSimDict's form (hashed with it, carried; the
## recordings don't have it - it defaults equal there);
## [b]HASHED[/b]: left out of MwSimDict, hashed by MwNetHash.port_layers,
## carried;
## [b]CARRIED[/b]: left out of MwSimDict, not hashed, carried (presentation
## every machine shows alike, or carried its own way);
## [b]LOCAL[/b]: left out of MwSimDict, not hashed, not carried (a
## machine's own presentation).
enum Port { IN_DICT, HASHED, CARRIED, LOCAL }
## The port's fields: top level by name, a nested class's as "Class.field"
## (those are all IN_DICT).
const PORT_FIELDS := {
	"pad_sticks": Port.HASHED, "pad_heights": Port.HASHED, "control": Port.HASHED, "pace": Port.HASHED,
	"crowd_life": Port.HASHED,            # (its noise level: the sound driver hears it)
	"bench_life": Port.CARRIED,
	"full_replay": Port.CARRIED,          # (as its frame count: MwNetSnapshot.codec)
	"splatter": Port.LOCAL,
	"extended": Port.IN_DICT, "spectated": Port.IN_DICT, "watch_held": Port.IN_DICT,
	"watch_new": Port.IN_DICT, "forfeit_manual": Port.IN_DICT,
	"extended_play": Port.IN_DICT, "extended_penalties": Port.IN_DICT, "extended_cpu": Port.IN_DICT,   # (plan 44)
	"Team.port_pads": Port.IN_DICT, "Team.port_turn": Port.IN_DICT, "Player.pad": Port.IN_DICT,
}


## The top-level port fields declared as [param layer] ([constant PORT_FIELDS]).
static func port_fields(layer: Port) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in PORT_FIELDS:
		if PORT_FIELDS[k] == layer and not k.contains("."):
			out.append(k)
	return out

const HAZARD_SLOTS := 4              ## +$FC: in-ice hazards
const OBJECT_SLOTS := 8              ## +$124: rink objects
const NET_ANIMS := 0x1B8F8           ## by net style: 0 Demon Net, 1 standard, 2 Battle Net
const NET_Y := 0x149                 ## nets at y -329 (top) / +329 (bottom)
const OBJECT_KINDS := 0x1C626        ## by kind - 1: animation.l, attr.w
const LAMPS := [0x1C52C, 0x1C524]    ## bottom, top: x.w, y.w (+ z, attr for the stands)
const LAMP_ANIM := 0x3EA6E
const IMPALE_ANIM := 0x3C042
## Kind numbers of rink objects (`$1C626`; docs/re/rink.md).
const KIND_SHARK := 1
const KIND_EXPLOSION := 3
const KIND_FIRE := 4
const KIND_SPIKES := 6
const KIND_BOMB := 7
const KIND_CORPSE := 11
const PUCK_ANIM := 0x3C8D4
const SHARK_OSC := 0x1C6B0           ## x, y: amplitude, rate, phase (words)
const QUOTE_SIZE := 0xA1             ## `$FFC4FE`-`$FFC59E`: the coach's quote


## A motion object and its animation object (+0 motion, +$18 animation).
class Actor:
	var motion := MwMotion.new()
	var anim := MwAnimState.new()


## An on-ice player (team + $6C + slot * $76; docs/re/players.md).
class Player extends Actor:
	var record := 0          ## +$32: the player record in the ROM (0 = slot empty / off the ice)
	var present: bool:       ## the slot is on the ice
		get:
			return record != 0
	var target_x := 0        ## +$24: where the skating steers to (rink px), from the control layer
	var target_y := 0        ## +$26
	var ai_x := 0            ## +$28: AI memory (a cached point; plan 09)
	var ai_y := 0            ## +$2A
	var ai_zone := 0xFFFF    ## +$2C: AI memory (zone index / poke counter, $FFFF none)
	var bone_tick := 0       ## +$2E: tick of the last bone pick-up (flags bits 6/7 last 900 ticks)
	var original := 0        ## +$36: the record the animations (species) and goalie radius come from
	var victim: Actor = null ## +$3A: punch / check target (a player, the referee)
	var init_roll := 0       ## +$3C: rng & $F at creation (no reader found)
	var x3d := 0             ## +$3D..+$3F: unknown, kept
	var x3e := 0
	var x3f := 0
	## Start-of-pass geometry (`$95C8`): distance (+$40) / angle (+$5A) to the
	## puck; to team-mate j (+$42 + 2j / +$5B + j; the own slot holds the own
	## speed and velocity angle); to opponent k (+$4E + 2k / +$61 + k).
	var puck_dist := 0
	var puck_angle := 0
	var mate_dist := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var mate_angle := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var opp_dist := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var opp_angle := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var index := 0           ## +$67: slot 0-5 on the ice (5 = goalie)
	var slot := 0            ## +$68: roster slot (team health index)
	var position := 0        ## +$69: 0 C, 1 LW, 2 RW, 3 LD, 4 RD, 5 G
	var role := 0            ## +$6A: AI role (plan 09)
	var think := 0           ## +$6B: think timer (signed byte; CPU skaters think when it wraps)
	var penalty := 0         ## +$6C: penalty box bookkeeping (plan 09)
	var weapon := -1         ## +$6D: weapon 0-4, -1 none
	var charges := 0         ## +$6E: weapon 3 (bombs) charges
	var anim_id := 0         ## +$6F: animation id ($FF = stopped)
	var state := 0           ## +$70: the state machine's state (docs/re/players.md)
	var substate := 0        ## +$71
	var attacker := 0        ## +$72: attacker's slot (knock-downs) / game clock stamp (injury)
	var angle := 0           ## +$73: facing, 0 right, $40 down
	var flags := 0           ## +$74: see the constants
	var flags2 := 0          ## +$75: bit 1 Nasty Goalie, 2 AI attack lock, 3 holds the Player Blast weapon
	var team := 0            ## which team (0 A, 1 B) - not in RAM, the object's address tells
	## Plan 34, an extended set-up (the port's; nothing in the original's
	## RAM): the match pad (0-11, MwHumans.pad_index) of the human driving
	## this player, beside +$74 bits 2 / 3 and meaningful while bit 2 (human)
	## is set - it moves with control as the second-pad bit does. -1 in the
	## original's set-ups, whose bits 2 / 3 and the team's two slots say it.
	var pad := -1

	const STATE_WEAPON := 4
	const STATE_IMPALED := 0x11
	const ENFORCER := 0x01
	const IN_BOX := 0x02
	const HUMAN := 0x04
	const SECOND_PAD := 0x08
	const FIGHTING := 0x10
	const BURST := 0x20
	const BLACK_BONE := 0x40
	const WHITE_BONE := 0x80

	func is_goalie() -> bool:
		return position == 5


## A marker set (team + $346 / + $35A): ground point and the values the
## info plate shows.
class Marker:
	var x := 0
	var y := 0
	var plate := 0           ## +4: plate slot (tiles $5F4 + 8 * slot)
	var number := 0xFF       ## +5
	var position := 0xFF     ## +6
	var health := 0xFF       ## +7 (0-32 with Reserves, $FF none)


## A team object (docs/re/rink.md, Objects): flags, roster health, pads, its six on-ice
## [MwRinkState.Player] slots (5 the goalie), arrows, [MwRinkState.Marker]s, statistics
## and score.
class Team:
	var record := 0          ## +0: the team record in the ROM
	var flags4 := 0          ## +4: bit 1 attacks downwards (y+), 2 has a pad, 5 confused, 7 armed force
	var flags5 := 0          ## +5: bit 1 Waste the Goalie running
	var health := PackedInt64Array()   ## +6: 24 roster slots, 0..$800000 (bit 31: on the ice this pass)
	var pads := [0xFF, 0xFF] ## +$66, +$67: pad of control slot 0 / 1 ($FF none)
	var pad_held := [0, 0]   ## +$68, +$6A: the controlled players' pads, held (`$19B8`)
	var pad_new := [0, 0]    ## +$69, +$6B: newly pressed (& $8F)
	## Plan 34, an extended set-up: the team's pad slots - its players' match
	## pads in number order (up to six; MwHumans.match_pads) - beside the
	## original's two slot bytes, which keep the nearest original mode's
	## values (the AI reads one as its gate byte). [member pad_held] /
	## [member pad_new] then hold a copy per slot. Empty in the original's
	## set-ups (and for a team without players).
	var port_pads := PackedInt32Array()
	## Plan 34: which of [member port_pads] takes control at the next pick-up
	## by a CPU team-mate (the original's co-op alternation, `$FFBDB8`, for
	## more than two players).
	var port_turn := 0
	var players: Array[Player] = []
	var x330 := PackedByteArray()      ## +$330..+$339 (+$336: under-the-ice bits); raw
	var arrows: Array[MwAnimState] = []   ## +$33A, +$34E
	var markers: Array[Marker] = []       ## +$346, +$35A
	## +$362..+$49F: statistics (raw bytes; [method stat] / [method add_stat]
	## by team offset: +$3A2 + 8 * roster slot player entries, +$482 shots,
	## +$48E faceoffs won, +$490 / +$492 checks, +$496 / +$498 passes,
	## +$49A deaths, +$49E fell through; plan 09 names the rest).
	var stats := PackedByteArray()
	var nearest: Player = null         ## +$4A0: nearest eligible skater to the puck (`$95C8`)
	var score := 0                     ## +$4A2
	var attr := 0                      ## +$4A4: sprite attr ($20 line 1, $40 line 2)
	var special := 0                   ## +$4A5: armed special play (plan 09)
	var x4a6 := 0
	var mask := 0                      ## +$4A7: positions on the ice (`$3E7A`)
	var formation := 0                 ## +$4A8: `$1C05E` strength key
	var x4a9 := 0

	const STATS_AT := 0x362

	func goalie() -> Player:
		return players[5]

	## The control slot of human [param p] (the team's pad copy, its marker
	## and arrow): the second-pad bit in the original's set-ups; in an
	## extended one the slot of its [member Player.pad] in [member port_pads].
	func control_slot(p: Player) -> int:
		if port_pads.is_empty():
			return 1 if p.flags & Player.SECOND_PAD else 0
		return maxi(port_pads.find(p.pad), 0)

	## The marker [param p] shows: a human's its control slot's; the CPU
	## carrier's the first (the original's) - in an extended set-up one of
	## its own after the players' ([method MwRinkState.extend]).
	func marker_of(p: Player) -> int:
		if p.flags & Player.HUMAN:
			return control_slot(p)
		return port_pads.size()

	func stat(off: int, size := 2) -> int:
		var v := 0
		for i in size:
			v = (v << 8) | stats[off - STATS_AT + i]
		return v

	func add_stat(off: int, n: int, size := 2) -> void:
		var v := (stat(off, size) + n) & ((1 << (8 * size)) - 1)
		for i in size:
			stats[off - STATS_AT + size - 1 - i] = (v >> (8 * i)) & 0xFF


## The puck (`$FFB3C2`; docs/re/rink.md, Objects): an [MwRinkState.Actor] with its
## carrier, pass receiver and state flags (the constants below).
class Puck extends Actor:
	var carrier: Player = null   ## +$24: the carrier while +$3D bit 0, else the last carrier
	var take_tick := 0           ## +$26: tick of the last take / poke / release / drop set-up
	var owner_log := 0           ## +$2A (long): previous carrier (high word); at a goal the scorer's name
	var x2e := 0                 ## +$2E..+$31: never written (the ring bug), kept
	var ring := 0                ## +$32: ring index (always 0)
	var touches := 0             ## +$33: takes since the faceoff (0..4)
	var prev_x := 0              ## +$34: px at the start of the last loose update
	var prev_y := 0              ## +$36
	var release_y := 0           ## +$38: y at the last drop / pass release (2-point rule)
	var receiver: Actor = null   ## +$3A: pass receiver
	var receiver_angle := 0      ## +$3C
	var flags := 0               ## +$3D: see the constants
	var lock := 0                ## +$3E: bit 0: skaters cannot touch (30 ticks after a poke / release)
	var x3f := 0

	const CARRIED := 0x01
	const BY_TEAM_B := 0x02
	const ROCKET := 0x04
	const EXPLODING := 0x08
	const ROCKET_B := 0x10
	const HIDDEN := 0x20
	const SHOT := 0x40
	const PASS := 0x80

	func carried_by() -> Player:
		return carrier if flags & CARRIED else null


## A net (rink state +`$18` top, +`$3E` bottom): an [MwRinkState.Actor] with its style
## (0 Demon Net, 1 standard, 2 Battle Net) and its end ([member bottom]).
class Net extends Actor:
	var style := 1               ## +$24
	var bottom := false          ## +$25 bit 0


## An in-ice hazard slot (rink state +`$FC`): its point, kind and flags.
class Hazard:
	var x := 0
	var y := 0
	var x4 := 0                  ## +4..+7: unknown, kept
	var kind := 0                ## +8: 0 none, 1 thin ice, 2 pit, 3 hole, 4 mine
	var flags := 0               ## +9


## A rink object slot (rink state +`$124`; [method MwRinkState.spawn]): an
## [MwRinkState.Actor] with its kind (0 free; the [code]KIND_*[/code] constants),
## flags and two per-kind words.
class RinkObject extends Actor:
	var kind := 0                ## +$28 (0 free)
	var flags := 0               ## +$29: bit 3 mirrored
	var t24 := 0                 ## +$24 / +$26: per kind (RAM words; spikes: the impaled player)
	var t26 := 0


## A screen or map overlay (faceoff portrait $FFBD56, ref icons $FFC2DC /
## $FFC3C8): an animation at a point with its own depth and attr.
class Overlay:
	var anim := MwAnimState.new()
	var x := 0                   ## +$C
	var y := 0                   ## +$E
	var depth := 0               ## +$10
	var attr := 0                ## +$12
	var flags := 0               ## +$13: bit 7 shown, bit 0 small border

	func shown() -> bool:
		return (flags & 0x80) != 0


## A sine oscillator (`$1522C`; the shark's target `$FFC280` / `$FFC28C`):
## value = base + amp * sin(2 pi * ((tick - start) mod 36000) * rate /
## 36000 / 256 + phase), integer as the original.
class Oscillator:
	var start := 0               ## +0 .l: tick of the set-up
	var base := 0                ## +4 .w
	var amp := 0                 ## +6 .w
	var rate := 0                ## +8 .w: byte-angle turns per 36000 ticks
	var phase := 0               ## +$A .w


## The instant replay's byte ring (`$FFC2BE`, a `$144E0` ring object over
## the 32 KiB at `$FF0000`; docs/re/rink.md, Replay recording): one frame
## per recorded pass (header word = elapsed | length << 3, the camera, the
## hazards, the markers, a record per sprite drawn, the header again as a
## trailer). When it is full the oldest frame is dropped (`$9D14`). Plan 11
## plays it back.
class ReplayRing:
	const BASE := 0xFFFF0000
	const SIZE := 0x8000
	const DROP_OLDEST := 0x9D14      ## the "make room" callback `$9D34` sets
	const READ_WORD := 0x14548       ## `$144E0`'s default callback
	var base := 0                    ## +0 .l
	var size := 0                    ## +4 .w
	var callback := 0                ## +6 .l: what makes room when full
	var write := 0                   ## +$A .w: write offset
	var read := 0                    ## +$C .w: read offset (oldest frame)
	var used := 0                    ## +$E .w: bytes held
	var frames := 0                  ## `$FFC2CE` .w: frames held
	var frame_start := 0             ## `$FFC2D0` .w: write offset where the open frame starts
	var open := 0                    ## `$FFC2D2` .b: a frame is open ($FF)
	var playback := 0                ## `$FFC2D3` .b: the replay screen (7) is playing it
	var pan := Vector2i.ZERO         ## `$FFC2D4` / `$FFC2D6` .w: playback camera pan
	## The data at `$FF0000` (outside the comparison snapshots; MwSimDict
	## leaves it out of the fixtures).
	var ring_bytes := PackedByteArray()
	## The 3D view's side-store (plan 20, MwReplay3D): what it needs of each
	## frame the ring holds, by the frame's start offset - the ring keeps
	## only screen points. Filled by the rink pass's draws when a
	## presentation asks for it (MwRinkUpdate.replay_side), kept in step
	## with the frames here (dropped, abandoned, reset). Presentation only,
	## outside the comparisons (MwSimDict.skipped).
	var side := {}

	func _init() -> void:
		ring_bytes.resize(SIZE)

	## `$9CE8`: an empty ring (`$144E0` base, size, callback; offsets 0),
	## no frames, no frame open, not playing, no pan.
	func reset() -> void:
		base = BASE
		size = SIZE
		callback = DROP_OLDEST
		write = 0
		read = 0
		used = 0
		frames = 0
		open = 0
		playback = 0
		pan = Vector2i.ZERO
		side.clear()

	## `$1450C`: one word in; while the ring is full the callback makes room.
	func put_word(v: int) -> void:
		while used >= size:
			if callback == DROP_OLDEST:
				drop_oldest()
			else:
				take_word()
			if size == 0:
				return
		ring_bytes[write] = (v >> 8) & 0xFF
		ring_bytes[(write + 1) % SIZE] = v & 0xFF
		var w := write + 2
		if w >= size:
			w -= size
		write = w & 0xFFFF
		used = (used + 2) & 0xFFFF

	## `$14506`: a long (high word first).
	func put_long(v: int) -> void:
		put_word((v >> 16) & 0xFFFF)
		put_word(v & 0xFFFF)

	## `$14548`: the oldest word out (0 when empty: d0 keeps the caller's value).
	func take_word() -> int:
		if used == 0:
			return 0
		var v := (ring_bytes[read] << 8) | ring_bytes[(read + 1) % SIZE]
		var r := read + 2
		if r >= size:
			r -= size
		read = r
		used = (used - 2) & 0xFFFF
		return v

	## `$14570`: skip [param n] bytes; skipping all that is held (or more)
	## empties the ring, write offset included (`$144F8`).
	func skip(n: int) -> void:
		if n >= used:
			write = 0
			read = 0
			used = 0
			return
		used -= n
		var r := read + n
		while r >= size:
			r -= size
		read = r

	## `$9D14`: the oldest frame dropped: its header's length (bits 3-15,
	## even) skipped after the header word.
	func drop_oldest() -> void:
		side.erase(read)
		var h := take_word()
		skip((h >> 3) & 0xFFFE)
		frames = (frames - 1) & 0xFFFF

	## `$9D34`: a frame opened (an open one abandoned first) with the
	## header word min([param e], 15).
	func open_frame(e: int) -> void:
		if open != 0:
			abandon_frame()
		frame_start = write
		put_word(mini(e & 0xFFFF, 0xF))
		open = 0xFF

	## `$9D64`: the open frame closed: its length (mod the ring) << 3 ORed
	## into the header, the header repeated as a trailer, one frame more.
	func close_frame() -> void:
		if open == 0:
			return
		var n := (write - frame_start) & 0xFFFF
		if write < frame_start:
			n = (n + 0x8000) & 0xFFFF
		var h := ((n << 3) & 0xFFFF) | ((ring_bytes[frame_start] << 8) | ring_bytes[(frame_start + 1) % SIZE])
		ring_bytes[frame_start] = (h >> 8) & 0xFF
		ring_bytes[(frame_start + 1) % SIZE] = h & 0xFF
		put_word(h)
		frames = (frames + 1) & 0xFFFF
		open = 0

	## `$9DA4`: the open frame given up (the write offset back at its start).
	func abandon_frame() -> void:
		if open == 0:
			return
		side.erase(frame_start)
		var n := (write - frame_start) & 0xFFFF
		if write < frame_start:
			n = (n + 0x8000) & 0xFFFF
		write = frame_start
		used = (used - n) & 0xFFFF
		open = 0


## The window text box object (`$FFC336`, `$15800`; the team descriptions'
## reused by the coach speech): where `$15860` lays text out with word
## wrap, its cursor left where the last text ended.
class TextBox:
	var plane := 0               ## +0 .l: the plane object (the window, `$FFFFB0CA`)
	var font := 0                ## +4 .l: the font (`$1F958`)
	var x := 0                   ## +8 .w: the box in cells
	var y := 0                   ## +$A
	var w := 0                   ## +$C
	var h := 0                   ## +$E
	var spacing := 0             ## +$10: extra rows between lines
	var cursor_x := 0            ## +$12 (cells from the box's corner)
	var cursor_y := 0            ## +$14


## The coach speech's portrait object (`$FFC618`, `$20` bytes; `$B542`
## `$B572` `$B656` `$B6D2`): its animation (+0, talking or an expression),
## the coach's portrait data (+$C: talking anim.l, expression anim.l, voice
## sound.w, then (frame, sound) pairs to `$FFFF`), the talk timer and the
## sound driver's handle of the voice playing.
class Portrait:
	var anim := MwAnimState.new()    ## +0..+$A
	var x0b := 0                 ## +$B (cleared by `$14388`)
	var data := 0                ## +$C .l
	var x10 := 0                 ## +$10 .w (cleared by `$B6D2`, read by nothing found)
	var mode := 0                ## +$12 .w: 0 talking, 1 an expression
	var timer := 0               ## +$14 .w: talk timer (negative: wait)
	var size := 0                ## +$16 .w: portrait size (0: not drawn)
	var handle := 0              ## +$18 .l: the voice's sound handle (0: none)
	var voices := 0              ## +$1C .w: voices left in this talk cycle
	var x1e := 0                 ## +$1E .w


var phase := PHASE_START
var subphase := 0
## The 60 Hz tick counter (`$FFCA56`; the goalie arrow blinks with bit 4).
var tick := 0
## The main random stream (`$FFB096`).
var rng := MlhRng.new()
## The pads as `read_joypads` left them (`$FFCA5A` + 2p: held, newly
## pressed; `$19B8` consumes the A/B/C presses), and the tap / hold timers
## per pad (`$FFB056` + 2p: the watched button bit, ticks left).
var pads_held := PackedInt32Array([0, 0, 0, 0])
var pads_new := PackedInt32Array([0, 0, 0, 0])
var hold_bit := PackedInt32Array([0, 0, 0, 0])
var hold_left := PackedInt32Array([0, 0, 0, 0])
## The pads' analogue sticks (the port's, plan 22: MwInputFrame.stick; each
## axis -256..256, x right, y down; ZERO: none - the D-pad as the original).
var pad_sticks: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
## The pads' shot heights (the port's: MwSettings.shot_heights,
## MwInputFrame.height): 0 none (the middle height), 1 high, 2 low - the
## lift table's entries for no direction, Up, Down -; -1 the D-pad lifts
## the shot (the original).
var pad_heights := PackedInt32Array([-1, -1, -1, -1])
var pad_mode := 0                    ## `$FFB0E0`
## Plan 34: an extended set-up (MwHumans: more players than the original's
## pad modes allow) - the port's code paths for the players, twelve match
## pads ([member pads_held] ... one per player 1-12: MwHumans.pad_index),
## a pad slot per player a team ([member Team.port_pads]) and a marker,
## arrow and info plate each ([method extend]). False: the original's.
var extended := false
## Plan 44: an EXTENDED match (the options' 2D EXTENDED / 3D EXTENDED;
## online always; MwSettings.extended_play, MwMatchSetup.extended_play):
## the players humans drive count as on the original's screen wherever
## they are - `$6D02` meets their team-mates, opponents, the puck, rink
## objects, the nets and hazards (MwSimCollide.counts_on_screen), as the
## EXTENDED views keep them in sight; the CPU's players keep the original's
## rule (owner) but for their bodies against the opponents humans drive (the
## owner's one exception). False: the original's (off its screen, the boards
## alone).
var extended_play := false
## Plan 44: EXTENDED PENALTIES (an EXTENDED match's option,
## MwMatchSetup.extended_penalties): the referee stops play for an offender
## anywhere on the rink (MwRinkPenalties.rule), not only on the original's
## screen. False: the original's.
var extended_penalties := false
## Plan 44: EXTENDED CPU (an EXTENDED match's option,
## MwMatchSetup.extended_cpu): the CPU's players count as on the original's
## screen wherever they are too - every player meets the whole rink
## (MwSimCollide.counts_on_screen). False: the original's for them.
var extended_cpu := false
## Plan 34 (section 7): the port's control layer - the players' seats,
## owned positions, captains, own menus, QUIT GAME and REJOIN
## ([MwRinkControl], run at each rink pass's start). Null: none (the
## comparisons, the rehearsal, the attract demo) - the original's rules alone.
var control: MwRinkControl = null
## Port only: a spectated match (MwSession.spectated: the port's CPU v CPU
## exhibition, nobody on a team; not the attract demo) - every player's
## Start pauses (the spectators' pause menu, MwRinkPhases) and any player's
## Start / A / B / C skips a coach's speech. [member watch_held] /
## [member watch_new]: players 1-12's pad bytes this pass (held, newly
## pressed: the rink scene reads them from every player's verbs, MwRink);
## they reach nothing else - the pads the simulation reads stay the pad
## mode's (5: none drives a skater).
var spectated := false
var watch_held := PackedInt32Array()
var watch_new := PackedInt32Array()
var death_index := 0                 ## `$FFB0E7` (0-4)
var clock := 0                       ## `$FFB06A`: game clock seconds left
## The game clock's timer object (`$FFB066`, `$16B0`..`$1736`) and widget
## (docs/re/rink.md, HUD): reference tick, ticks per clock second (20),
## flags (bit 0 running, bit 1 expired), the period (`$FFB076`: 1-3, 4+
## overtime), the widget flags (`$FFB077`: bit 0 power play, 1 shown - the
## clock only counts then -, 2 paused, 3 drawn in power-play form) and the
## text `$261C` last made (`$FFB060`: "MM:SS" and a 0).
var clock_ref := 0                   ## `$FFB066` (long)
var clock_rate := 20                 ## `$FFB06C`
var clock_flags := 0                 ## `$FFB06D`
var period := 1                      ## `$FFB076`
var clock_widget := 0                ## `$FFB077`
var clock_text := PackedByteArray([0, 0, 0, 0, 0, 0])   ## `$FFB060`-`$FFB065`
## Plane B (`$FFB0B2`; the camera's [member MwRinkCamera.shown] is its +4 /
## +6): the first map column / row it holds (+$10, +$12), and the scroll
## buffers the VBlank uploads (`$FFB0D8` hscroll = -x & $1FF, `$FFB0DC`
## vscroll = y & $FF).
var plane_b_cell := Vector2i.ZERO
var scroll_b := Vector2i.ZERO
## Rink state +$274: how many of the 8 object slots the stadium's own
## objects use (the entries clear thrown items and fires beyond them).
var stadium_objects := 0
## `$FFC280`, `$FFC28C`: the shark's target oscillators (x, y), set when a
## shark is spawned (both sharks of a stadium share them).
var shark_osc: Array[Oscillator] = []
## The instant replay's recording (`$FFC2BE`).
var replay := ReplayRing.new()
## The whole match's replay (plan 28, MwFullReplay; null: not kept).
var full_replay: MwFullReplay = null
## The crowd's life (plan 31, MwCrowdLife: the 3D crowd's movement and,
## with ENHANCE AUDIO, its noise; null: none - the original's noise).
var crowd_life: MwCrowdLife = null
## The benches' life (plan 32, MwBenchLife: the 3D benches' and boxes'
## figures; null: none).
var bench_life: MwBenchLife = null
## Blood and oil on the 3D arena (plan 37, MwSplatter: the paint atlas and the
## particles in flight; null: none).
var splatter: MwSplatter = null
## Plan 36 with plan 35: the rink's pass pacer's state after the latest
## pass (MwPassPacer.snapshot: TICK RATE APPROXIMATED or ORIGINAL; empty:
## OVERCLOCKED's fixed passes). It decides when the next passes come, so
## the rink's hash takes it (MwNetHash.port_layers): two machines whose
## pacing parted differ at that pass. Not the original's (MwSimDict skips
## it); the pacer itself is the rink scene's, made anew at each rink entry.
var pace := PackedInt32Array()
## `$FFC608` (word): the phase handler turns the replay recording on (phase
## 0) and off (stoppages, entries).
var replay_on := 0
## `$FFC2D8` (long): tick the penalty ref icon was last checked at (`$A782`,
## phase 0) or the rink was entered.
var penalty_tick := 0
## `$FFC2F2` (word): the clock value the penalty timers last counted from.
var box_clock := 0
## `$FFB07C` (word, +4 of the power-play timer object `$FFB078`): the
## power-play clock's seconds (`$2824`, from the penalty box: `$A888`).
var pp_seconds := 0
## `$FFC5FE` (long): the tick the pass started at (elapsed = the next minus it).
var pass_tick := 0
## `$FFC606` (word): 1 until the first pass of a rink visit has drawn.
var first_pass := 0
## `$7868`'s net slack for the visit (the high word of the a5 the entry
## pushed at `$F8F6`, on the stack, not in the snapshots): -1 after entries
## 4 and 5 (a5 = a team), +1 after entry 6 (a5 = `$0001E9F0`, left by the
## instant replay's `$F844`; plan 11).
var net_slack := -1
## `$FFC644` (word): crowd noise off (the phase handler; entries clear it).
var crowd_quiet := 0
## `$FFC2B6` / `$FFC2B8` (words): the goal message's state and step
## (`$928C`, phase 3; entries clear both).
var goal_message := 0
var goal_message_step := 0
## `$FFC31C` (byte): the faceoff sequence's state (`$AC1C`; `$AB2C` clears it).
var faceoff_step := 0
var crowd := 50                      ## rink state +$276: the crowd level
var faceoff_spot := 0                ## `$FFC31D`
var ai_off := 0                      ## `$FFC31E` (never set in recordings)
var fight_block := 0                 ## `$FFCA1C`
var crease_y := 0                    ## `$FFC3E0`: puck y at the last crease / net / goalie touch
var scoring := 0                     ## `$FFC640` (long): the scoring team of the last goal
var goal_points := 0                 ## `$FFC2B4`: the last goal's points (1, 2), for the goal message
var bribe := 0                       ## `$FFBD8E`: bribed referee's team (plan 09)
## `$FFBD90`: the skater whose special play started the phase 11 / 12
## sequence (Waste the Goalie / Ref, [MwSimSpecial]).
var special_actor: Player = null
var jail_tick := 0                   ## `$FFC2F4` (long): tick of the last Jail Break (`$A9F2`)
var jail_count := 0                  ## `$FFC2F8` (word): Jail Break message pending (`$A9F2` +1)
var coop_toggle := 0                 ## `$FFBDB8` (word): co-op pad alternation on pick-ups
var ref_flag := 0                    ## referee +$24 (byte): the referee is on the ice (Waste the Ref)
var pass_count := 0                  ## `$FFBD80` (byte): +1 per rink pass
## The faceoff drop's motion parameters (`$FFBE3C`, from `$1C58C`) and the
## long after them (`$FFBE64`, cleared at the drop).
var drop_params := MwMotion.Params.new(-24, 0, 16, 16)
var be64 := 0
var player_params := MwMotion.Params.new(-24, 0, 3, 0)   ## rink state +$64 (`$FFB14C`)
var puck_params := MwMotion.Params.new(-24, 0x80, 3, 3)  ## rink state +$8C (`$FFB174`)
var reserves := false
var penalties := 0                   ## `$FFB0E5`: penalties on (1)
var stadium := 0
## `$FFBDBA`: the scoreboards' side view (never set in the rink).
var projection := 0
var camera := MwRinkCamera.new()
## What the camera follows (null: hold still).
var camera_target: Actor = null
var teams: Array[Team] = []
var puck := Puck.new()
var nets: Array[Net] = []            ## top (+$18), bottom (+$3E)
var lamps: Array[Actor] = []         ## bottom (+$B4), top (+$D8)
var hazards: Array[Hazard] = []      ## +$FC, 4 slots
var objects: Array[RinkObject] = []  ## +$124, 8 slots
var faceoff := Overlay.new()         ## $FFBD56 (the faceoff portrait)
var penalty := Overlay.new()         ## $FFC2DC (ref icon after a whistle)
var stoppage := Overlay.new()        ## $FFC3C8 (ref icon while the puck is dead)
## `$FFC3E2`: the puck rules' state (`$C84A`, plan 09). In open play the
## stoppage icon is drawn while it is non-zero (the rule is pending); the
## icon's shown bit can stay set after a stoppage without it being drawn.
var puck_rule := 0
var impale := MwAnimState.new()      ## $FFBD82 (shared by impaled players)
var referee := Actor.new()           ## $FFBD92 (Waste the Ref only)
## What the 4 info plates' RAM tiles show ($FFBE80 + 256 * slot): [number,
## position, health], $FF = never drawn. Slots are shared (a CPU team's
## markers all use slot 3), so a plate shows the last values written to it.
var plates: Array = [[0xFF, 0xFF, 0xFF], [0xFF, 0xFF, 0xFF], [0xFF, 0xFF, 0xFF], [0xFF, 0xFF, 0xFF]]
## Plan 34, extended set-ups: plates 0-11 are players 1-12's (a player's
## match pad), 12 and 13 the CPU carriers' of teams A and B (the original
## gives a CPU team's markers slot 3, a player's in these set-ups).
const PLATES_EXTENDED := 14
const CARRIER_PLATE := 12

# --- the match flow (MwRinkPhases, plan 09; docs/re/phases.md) ---------------------------------
## `$FFC602` (long): the phase stamp - every open-play pass, the coach
## speech set-ups, the game over; the stoppages' timers count from it.
var phase_tick := 0
var play_mode := 0                   ## `$FFB0E1`: 0 a regular game, 1-2 the playoffs
var period_minutes := 5              ## `$FFB0E3`: a period's length (minutes)
## `$FFB0E2`: the menu's period length row (0 3:00, 1 5:00, 2 8:00; penalty lengths)
var period_row := 1
## The pause menu (`$48FC`): `$FFB092` the pad that paused x 2, `$FFB08E`
## its team (the team's address word), `$FFB090` the texts' attr (the
## team's palette line, priority), `$FFB094` "B - TIMEOUT" offered.
var pause_pad := 0
var pause_team := 0
var pause_attr := 0
var pause_offer := 0
## Port only (plan 26; nothing in the original's RAM): this match's forfeit
## came from the port's pause menu (FORFEIT, then YES:
## [method MwRinkPhases._forfeit]), not from the original's rule (too few
## players left, `$F7C8`). Screen 17's referee then says one of the port's
## own lines ([constant MwQuotes.MANUAL_FORFEIT]) instead of the ROM's
## forfeit set. A new match gets a new state, so it never carries over.
var forfeit_manual := false
## The goal sequence (`$928C`): `$FFC2B0` stamp (long), `$FFC2BA` the Demon
## Net that swallowed the puck (its address word, 0 none) and `$FFC2BC`
## the swallow animation's last frame seen.
var goal_tick := 0
var goal_net := 0
var goal_net_frame := 0
## The faceoff sequence (`$AC1C`): `$FFC2FA` stamp (long); `$FFC2FE`
## (word): the panel's period digit ('0' + period, 0) in states 0-1, then
## the FACE OFF! drop's settle counter (`$AD08`'s bug adds `$C304` to it);
## `$FFC300` / `$FFC302`: plane B as shown when the drop began; `$FFC304`:
## the FACE OFF! drop's motion object (x.l: the first bounce's thud played,
## y.l: pass counter, z: the drop height).
var faceoff_tick := 0
var faceoff_text := 0
var drop_plane := Vector2i.ZERO
var drop := MwMotion.new()
## The coach speech: `$FFC32E` the speech box (x, y, w, h cells), `$FFC336`
## the text box, `$FFC3B4` the box is filled (set-up) / framed only (every
## pass), `$FFC3BC` (cleared with it), `$FFC4FE` the quote (161 bytes, the
## codes expanded), `$FFC60E` its address (long), `$FFC612` the coach's
## name (string address), `$FFC616` the quote's value word (2-3: the
## coach pulls faces), `$FFC618` the portrait, `$FFC636` the speaking side
## (0 team A's coach), `$FFC638` the playoff game's result (`$12854`, -1 a
## regular game), `$FFC63A` the goal's situation (0-6), `$FFC63C` the
## scorer (player address, 0 none).
var speech_box := PackedInt32Array([0, 0, 0, 0])
var text_box := TextBox.new()
var box_fill := 0
var box_c3bc := 0
var quote := PackedByteArray()
var quote_ptr := 0
var coach_name := 0
var quote_value := 0
var portrait := Portrait.new()
var speaker := 0
var playoff_result := 0
var goal_kind := 0
var scorer := 0
## The puck rules (`$C84A`, phase 8 `$CA12`): `$FFC3DC` phase 8's stamp
## (long), `$FFC3E4` (byte) $FF when the last carrier noted was team B's,
## `$FFC3E6` the clock when no goalie held the puck, `$FFC3E8` $FFFF a
## goalie hold (else icing), `$FFC3EA` / `$FFC3EC` the stoppage point
## (icing: x, -y; a goalie hold: x, y).
var stop_tick := 0
var rule_team_b := 0
var rule_clock := 0
var rule_hold := 0
var rule_spot := Vector2i.ZERO
## `$FFC2F0` (word): the penalty sequence's step (`$A6C2`, phase 2).
var penalty_step := 0
## Referee +$25 (byte): his sprite attr (Waste the Ref, `$EF5E`).
var ref_attr := 0
## The playoff run (`$FFBD6A`; [MwPlayoffs]): a playoff game's end
## (`$12854`) advances it. Not in the simulation fixtures (MwSimDict).
var playoffs := MwPlayoffs.new()


func _init() -> void:
	quote.resize(QUOTE_SIZE)
	for t in 2:
		var team := Team.new()
		team.attr = 0x20 if t == 0 else 0x40
		team.health.resize(24)
		team.x330.resize(10)
		team.stats.resize(0x4A0 - Team.STATS_AT)
		for i in 6:
			var p := Player.new()
			p.team = t
			p.index = i
			team.players.append(p)
		for i in 2:
			team.arrows.append(MwAnimState.new())
			team.markers.append(Marker.new())
		teams.append(team)
	for i in 2:
		var net := Net.new()
		net.bottom = i == 1
		nets.append(net)
		lamps.append(Actor.new())
	_slots(HAZARD_SLOTS, OBJECT_SLOTS)
	for i in 2:
		shark_osc.append(Oscillator.new())


## [param h] in-ice hazard slots and [param o] rink object slots (the
## original's 4 and 8; more for a custom rink, plan 38).
func _slots(h: int, o: int) -> void:
	while hazards.size() < h:
		hazards.append(Hazard.new())
	hazards.resize(h)
	while objects.size() < o:
		objects.append(RinkObject.new())
	objects.resize(o)


## The stadium record of stadium [param stadium_number] (`docs/re/rinks.md`).
static func stadium_record(rom: PackedByteArray, stadium_number: int) -> int:
	return MwGfx.u32(rom, MwTeams.record(stadium_number) + 0x10)


## The stadium part of `rink_setup` ($5572): camera at centre ice, both
## nets in the stadium's style, its in-ice hazards and rink objects
## (spawned as `$66EE` does: motion at the point, the kind's animation; fire
## starts playing, spikes stand 16 px up), the goal lamps, the shared impale
## animation playing.
func setup(rom: PackedByteArray, stadium_: int) -> void:
	stadium = stadium_
	var rec := stadium_record(rom, stadium)
	camera_target = null
	camera.place(rom, 0, 0)
	camera.shake = 0
	camera.amp = 0
	camera.shake_16 = 0
	for i in 2:
		var net := nets[i]
		net.style = rom[rec + 5]
		net.bottom = i == 1
		net.anim = MwAnimState.from_record(rom, MwGfx.u32(rom, NET_ANIMS + 4 * net.style), 0 if net.bottom else 1)
		net.motion.init(0, NET_Y if net.bottom else -NET_Y, 0)
	# `$5594`: the stadium's gravity (+8; -24 in all the original's) for players and the puck
	player_params = MwMotion.Params.new(MwGfx.s8(rom, rec + 8), 0, 3, 0)
	puck_params = MwMotion.Params.new(MwGfx.s8(rom, rec + 8), 0x80, 3, 3)
	# Port only (plan 38): a custom rink with more than the original's 4
	# in-ice hazards gets slots for them, and with more rink objects than
	# the original's 4 as many slots again beside the 4 spare for thrown
	# items, corpses and bombs; the original's stadiums keep 4 and 8.
	_slots(maxi(HAZARD_SLOTS, rom[rec + 9]), maxi(OBJECT_SLOTS, rom[rec + 0xA] + 4))
	var a := rec + 0xC
	for i in hazards.size():
		var hazard := hazards[i]
		hazard.kind = 0
		if i < rom[rec + 9]:
			hazard.x = MwGfx.s16(rom, a)
			hazard.y = MwGfx.s16(rom, a + 2)
			hazard.kind = rom[a + 4]
			hazard.flags = rom[a + 5]
			a += 6
	stadium_objects = rom[rec + 0xA]
	for i in objects.size():
		objects[i].kind = 0
		if i < rom[rec + 0xA]:
			spawn(rom, objects[i], MwGfx.s16(rom, a), MwGfx.s16(rom, a + 2), rom[a + 4], rom[a + 5])
			a += 6
	for i in 2:
		var actor := lamps[i]
		var p: int = LAMPS[i]
		actor.motion.init(MwGfx.s16(rom, p), MwGfx.s16(rom, p + 2), 0)
		actor.anim = MwAnimState.from_record(rom, LAMP_ANIM)
	impale = MwAnimState.from_record(rom, IMPALE_ANIM)
	impale.flags |= MwAnimState.PLAYING
	puck.anim = MwAnimState.from_record(rom, PUCK_ANIM)
	puck.flags = Puck.HIDDEN


## `$66EE`: a rink object of [param kind] at ([param x], [param y]), with
## the visible part of the kind's spawn hook (`$67B2`): a shark sets the
## target oscillators (`$686C`), fire starts playing, spikes stand 16 px
## up. ([method MwRinkSim.spawn] adds the hooks' sounds and draws.)
func spawn(rom: PackedByteArray, rink_object: RinkObject, x: int, y: int, kind: int, flags: int) -> void:
	rink_object.kind = kind
	rink_object.flags = flags
	rink_object.t24 = 0
	rink_object.t26 = 0
	rink_object.motion.init(x, y, 0)
	if kind == 0:
		return
	rink_object.anim = MwAnimState.from_record(rom, MwGfx.u32(rom, OBJECT_KINDS + 6 * (kind - 1)))
	match kind:
		KIND_FIRE, KIND_EXPLOSION:
			if kind == KIND_FIRE:
				rink_object.anim.flags |= MwAnimState.PLAYING
		KIND_SPIKES:
			rink_object.motion.pos[2] = 0x1000
		KIND_SHARK:
			shark_oscillators(rom, x, y)


## `$686C`: the shark's target oscillators around its spawn point
## ([param x], [param y]), started now (`$1C6B0`: x amplitude 500, rate $31,
## phase $40; y amplitude 500, rate $F0, phase 0). Global: a second shark
## overwrites the first one's.
func shark_oscillators(rom: PackedByteArray, x: int, y: int) -> void:
	for i in 2:
		var oscillator := shark_osc[i]
		var t := SHARK_OSC + 6 * i
		oscillator.start = tick & 0xFFFFFFFF
		oscillator.base = MwRinkSim.s16(x if i == 0 else y)
		oscillator.amp = MwGfx.s16(rom, t)
		oscillator.rate = MwGfx.u16(rom, t + 2)
		oscillator.phase = MwGfx.u16(rom, t + 4)


## Plan 34: makes this an extended set-up's state for the teams' match pads
## [param pads] (MwMatchSetup.extended: team A's, team B's, in number
## order): twelve pads and their tap / hold timers and sticks, fourteen info
## plates, each team's pad slots ([member Team.port_pads]) with a pad copy,
## marker (plate = the player's pad) and off-screen arrow each (players 1-4
## the original's pad's arrow, 5-12 pad 1's: drawn in their colour,
## MwRinkDraw), the CPU carrier's marker after them (plate
## [constant CARRIER_PLATE] + team); at least the original's two markers
## and arrows a team, which the replay ring keeps. The has-a-pad bit (team
## +4 bit 2) says whether the team has players. Run by the team set-up
## (MwRinkMatch.team_setup) after the original's.
func extend(rom: PackedByteArray, t: int, pads: PackedInt32Array) -> void:
	if not extended:
		extended = true
		pads_held.resize(MwVerbs.PLAYERS)
		pads_new.resize(MwVerbs.PLAYERS)
		hold_bit.resize(MwVerbs.PLAYERS)
		hold_left.resize(MwVerbs.PLAYERS)
		while pad_sticks.size() < MwVerbs.PLAYERS:
			pad_sticks.append(Vector2i.ZERO)
		while pad_heights.size() < MwVerbs.PLAYERS:
			pad_heights.append(-1)
		while plates.size() < PLATES_EXTENDED:
			plates.append([0xFF, 0xFF, 0xFF])
	var team := teams[t]
	team.port_pads = pads.duplicate()
	team.port_turn = 0
	team.flags4 = (team.flags4 | 4) if not pads.is_empty() else (team.flags4 & ~4)
	var n := pads.size()
	team.pad_held.resize(maxi(n, 2))
	team.pad_held.fill(0)
	team.pad_new.resize(maxi(n, 2))
	team.pad_new.fill(0)
	while team.markers.size() < maxi(n + 1, 2):
		team.markers.append(Marker.new())
	while team.arrows.size() < maxi(n, 2):
		team.arrows.append(MwAnimState.new())
	for k in n:
		init_marker(team, k, pads[k])
		var arrow := MwGfx.u32(rom, MwRinkMatch.ARROWS + 4 * (pads[k] if pads[k] < 4 else 0))
		team.arrows[k] = MwAnimState.from_record(rom, arrow)
	init_marker(team, n, CARRIER_PLATE + t)


## Plan 34: whether [param team] has players to decide for it - the
## original's "has a pad" (+4 bit 2), unless all its players are gone
## ([method MwRinkControl.anyone_in]: left with QUIT GAME, or online their
## machine away): then the CPU team's decisions (line changes, special
## plays, speeches, the fight) until someone is back. The bit itself stays
## (the replay ring's frames read it).
func has_players(team: Team) -> bool:
	if team.flags4 & 4 == 0:
		return false
	return control == null or control.anyone_in(teams.find(team))


## `$6146`: marker [param k] of team [param marker_team] on plate slot [param slot]
## (pad & 3; 3 for a CPU team), its values and plate cleared.
func init_marker(marker_team: Team, k: int, slot: int) -> void:
	var marker := marker_team.markers[k]
	marker.plate = slot
	marker.number = 0xFF
	marker.position = 0xFF
	marker.health = 0xFF
	plates[slot] = [0xFF, 0xFF, 0xFF]


## `$6166` (the team update, for a human player's marker or the CPU
## carrier's): redraw what changed on the plate, then follow the player.
func update_marker(rom: PackedByteArray, marker_team: Team, k: int, p: Player) -> void:
	var marker := marker_team.markers[k]
	var plate: Array = plates[marker.plate]
	if reserves:
		var h := ((marker_team.health[p.slot] >> 16) & 0xFF) >> 2
		if h != marker.health:
			marker.health = h
			plate[2] = h
	var number := rom[p.record + 4]
	if number != marker.number:
		marker.number = number
		plate[0] = number
	if p.position != marker.position:
		marker.position = p.position
		plate[1] = p.position
	var px := p.motion.pixels()
	marker.x = px.x
	marker.y = px.y


## `$F9DA`: what the camera follows this pass (phases 9 and 1 keep the
## previous choice, normally none after the faceoff set-up).
func choose_camera_target() -> void:
	if phase == PHASE_START or phase == PHASE_FACEOFF:
		return
	if phase == PHASE_FIGHT:
		# `$1045C`: the first fighting skater of team A (else its goalie)
		camera_target = teams[0].goalie()
		for i in 5:
			if teams[0].players[i].flags & Player.FIGHTING:
				camera_target = teams[0].players[i]
				break
	elif teams[0].flags5 & 2:
		camera_target = teams[1].goalie()
	elif teams[1].flags5 & 2:
		camera_target = teams[0].goalie()
	elif phase == PHASE_REF:
		camera_target = referee
	else:
		var player := puck.carried_by()
		if player != null:
			camera_target = player
		else:
			camera_target = puck


## The camera's pass (`$F9DA` + `$56EA`): target choice, look-ahead from
## the carrier's team, update.
func camera_pass(rom: PackedByteArray, elapsed: int) -> Vector2i:
	choose_camera_target()
	var lead: Variant = null
	if puck.flags & Puck.CARRIED:
		var carrier_team := teams[1] if puck.flags & Puck.BY_TEAM_B else teams[0]
		lead = MwRinkCamera.LEAD if carrier_team.flags4 & 2 else -MwRinkCamera.LEAD
	return camera.update(rom, elapsed, camera_target.motion if camera_target else null, lead)


## Plan 45: a match's state the game is done with (a new match took its
## place): its reference cycles broken - the control layer keeps the state it
## worked on, two players can be each other's victims - so the state, its full
## replay and its paint are freed once nothing else holds them. The state
## isn't played after it.
func retire() -> void:
	if control != null:
		control.release()
	for team in teams:
		for p in team.players:
			p.victim = null


# --- recorded passes ---------------------------------------------------------------

static func _motion(motion_object: MwMotion, f: Array) -> void:
	motion_object.pos = PackedInt32Array([int(f[0]), int(f[1]), int(f[2])])
	motion_object.vel = PackedInt32Array([int(f[3]), int(f[4]), int(f[5])])
	motion_object.acc = PackedInt32Array([int(f[6]), int(f[7]), int(f[8])])


func _actor(rom: PackedByteArray, actor: Actor, d: Dictionary) -> void:
	_motion(actor.motion, d["motion"])
	actor.anim = MwAnimState.from_fields(rom, d["anim"])


func _ref(d: Variant) -> Actor:
	if d == null:
		return null
	match String(d["kind"]):
		"puck": return puck
		"ref": return referee
		"player": return teams[int(d["team"])].players[int(d["slot"])]
	return null


func _overlay(rom: PackedByteArray, overlay: Overlay, d: Dictionary) -> void:
	overlay.anim = MwAnimState.from_fields(rom, d["anim"])
	overlay.x = int(d["x"])
	overlay.y = int(d["y"])
	overlay.depth = int(d["depth"])
	overlay.attr = int(d["attr"])
	overlay.flags = int(d["flags"])


## A pass recorded from the original (the fields of
## harness/mw_harness/rink_state.py `decode`).
static func from_dict(rom: PackedByteArray, d: Dictionary) -> MwRinkState:
	var s := MwRinkState.new()
	s.phase = int(d["phase"])
	s.subphase = int(d["subphase"])
	s.tick = int(d["tick"])
	s.reserves = int(d["reserves"]) != 0
	s.stadium = int(d["stadium"])
	s.projection = int(d["projection"])
	var rule: Variant = d.get("puck_rule")
	s.puck_rule = int(rule) if rule != null else 0
	var c: Dictionary = d["camera"]
	s.camera.x = int(c["x"])
	s.camera.y = int(c["y"])
	s.camera.speed = int(c["speed"])
	s.camera.lead = int(c["lead"])
	s.camera.shake = int(c["shake"])
	s.camera.amp = int(c["amp"])
	s.camera.shake_16 = int(c["shake_16"])
	s.camera.shown = Vector2i(int(c["shown"][0]), int(c["shown"][1]))
	for t in 2:
		var td: Dictionary = d["teams"][t]
		var team := s.teams[t]
		team.flags4 = int(td["flags4"])
		team.flags5 = int(td["flags5"])
		team.attr = int(td["attr"])
		team.pads = [int(td["pads"][0]), int(td["pads"][1])]
		for i in 24:
			team.health[i] = int(td["health"][i])
		for i in 6:
			var pd: Dictionary = td["players"][i]
			var p := team.players[i]
			s._actor(rom, p, pd)
			p.record = int(pd["record"])
			p.slot = int(pd["slot"])
			p.position = int(pd["position"])
			p.weapon = int(pd["weapon"])
			p.anim_id = int(pd["anim_id"])
			p.state = int(pd["state"])
			p.substate = int(pd["substate"])
			p.angle = int(pd["angle"])
			p.flags = int(pd["flags"])
		for i in 2:
			team.arrows[i] = MwAnimState.from_fields(rom, td["arrows"][i])
			var md: Array = td["markers"][i]
			var marker := team.markers[i]
			marker.x = int(md[0])
			marker.y = int(md[1])
			marker.plate = int(md[2])
			marker.number = int(md[3])
			marker.position = int(md[4])
			marker.health = int(md[5])
	var puck_fields: Dictionary = d["puck"]
	s._actor(rom, s.puck, puck_fields)
	s.puck.flags = int(puck_fields["flags"])
	s.puck.carrier = s._ref(puck_fields["carrier"]) as Player
	for i in 2:
		var nd: Dictionary = d["nets"][i]
		s._actor(rom, s.nets[i], nd)
		s.nets[i].style = int(nd["style"])
		s.nets[i].bottom = int(nd["bottom"]) & 1 != 0
		s._actor(rom, s.lamps[i], d["lamps"][i])
	for i in 4:
		var hd: Array = d["hazards"][i]
		var hazard := s.hazards[i]
		hazard.x = int(hd[0])
		hazard.y = int(hd[1])
		hazard.kind = int(hd[2])
		hazard.flags = int(hd[3])
	for i in 8:
		var od: Dictionary = d["objects"][i]
		var rink_object := s.objects[i]
		s._actor(rom, rink_object, od)
		rink_object.kind = int(od["kind"])
		rink_object.flags = int(od["flags"])
		rink_object.t24 = int(od["t24"])
		rink_object.t26 = int(od["t26"])
	var ov: Dictionary = d["overlays"]
	s._overlay(rom, s.faceoff, ov["faceoff"])
	s._overlay(rom, s.penalty, ov["penalty"])
	s._overlay(rom, s.stoppage, ov["stoppage"])
	s.impale = MwAnimState.from_fields(rom, d["impale"])
	if d.get("plates") != null:
		for i in 4:
			s.plates[i] = (d["plates"][i] as Array).map(func(v: Variant) -> int: return int(v))
	s._actor(rom, s.referee, d["ref"])
	s.camera_target = s._ref(c["target"])
	return s
