class_name MwInstantReplay
extends RefCounted
## Screen 7's playback of the replay ring (`$9DD0`, docs/re/replay.md): the
## ring (MwRinkState.ReplayRing, written by the rink pass) shown frame by
## frame from its oldest frame. One pad controls it (the first of pads 1-4
## that newly pressed A in the pause menu, or C on a scoreboard): C plays
## at the recorded speed (each frame shown for its recorded pass length e),
## held B slowly (2e), held A rewinds (max(e / 2, 1)), Start leaves; the
## D-pad does nothing. Node-free: [method step] once per tick. The screen
## around it (set-up, draws, exit, comparisons): [MwReplaySim].
##
## A frame drawn changes the rink state for good: plane B (`$FFB0B2` +4 /
## +6 / +$10 / +$12) and its scroll buffers (`$FFB0D8` / `$FFB0DC`, from
## the frame's camera point), the team markers and info plates (from its
## marker words) - what play continues with after the replay (entry 6) or
## the next rink visit sees. The ring itself is left as it was (its read
## offset and byte count are put back at the exit), and no random number
## is drawn.
##
## Positions (the locals of `$9DD0`): [member cursor] counts the frames
## before the read offset. After a forward step the read offset is at the
## frame after the one shown, after a rewind step at the one shown, so the
## first step after a change of direction shows the current frame again.

const NEW_A := 0x40
const NEW_B := 0x10
const NEW_C := 0x20
const START := 0x80
## In the pad word (held << 8 | newly pressed): A and B held.
const HELD_A := NEW_A
const HELD_B := NEW_B

var s: MwRinkState
var rom: PackedByteArray
var ring: MwRinkState.ReplayRing
## The controlling pad (0-3; `-$14(a6)` / 2).
var pad := 0
var play := false            ## `-$12(a6)` (`st.b`: the word reads $FF00)
var wait := 0                ## `-$C(a6)`: ticks before the next frame (signed word)
var cursor := 0              ## `-$A(a6)`: frames before the read offset
var frame_end := 0           ## `-$E(a6)`: the trailer offset of the frame at the read offset
var saved_read := 0          ## `-6(a6)`
var saved_used := 0          ## `-8(a6)`
## The frame on screen ([method draw_frame]): {"camera": Vector2i, "hazards":
## [[kind, flags] x 4], "sprites": [[x, y, depth, attr, frame], ...]
## (sprite coordinates: screen + $80), "at": the frame's start offset in the
## ring (its 3D side-store key, MwReplay3D)}.
var shown := {}
## Frames drawn so far (the first is the oldest, at [method start]).
var drawn := 0


func _init(state: MwRinkState, rom_: PackedByteArray = PackedByteArray()) -> void:
	s = state
	ring = state.replay
	rom = rom_ if not rom_.is_empty() else MwRom.data()


## The controlling pad (`$9DD0`): the first of pads 1-4 whose newly pressed
## byte has A (from the rink: [param from_screen] < 12) or C (from a
## scoreboard); pad 1 when none. [param pads_new]: the 4 bytes as the last
## read left them (the pause menu's or the scoreboard's; plan 34, an
## extended set-up: its twelve match pads').
static func control_pad(from_screen: int, pads_new: Variant) -> int:
	var bit := NEW_A if (from_screen & 0xFFFF) < 12 else NEW_C
	for p in mini(pads_new.size(), MwVerbs.PLAYERS):
		if int(pads_new[p]) & bit:
			return p
	return 0


## `$9DD0`'s set-up: the pan cleared, the read offset and byte count saved,
## the oldest frame drawn (the display still off), cursor 1, frozen, the
## next frame peeked (its e is the first wait).
func start(control: int) -> void:
	pad = control
	ring.pan = Vector2i.ZERO
	saved_read = ring.read
	saved_used = ring.used
	_peek()
	draw_frame()
	cursor = 1
	play = false
	_peek()


## One tick of the loop (`$9E64`): [param held] / [param new] are the
## controlling pad's bytes, [param elapsed] the ticks since the last loop
## (normally 1). The tests in this order: new A, held A, held B, new C,
## new Start, the play flag. True when Start leaves ([method leave] done).
func step(elapsed: int, held: int, new: int) -> bool:
	var n := frame_count()
	if new & NEW_A:
		wait = 1                                        # `$9EE0`: the first step at once
	if new & NEW_A or held & HELD_A:
		# `$9EE6`: rewind
		play = false
		if cursor == 0 or not _count_down(elapsed):
			return false
		_back()                                         # the read offset at the frame shown ...
		_peek()
		draw_frame()                                    # ... drawn again (or the one before it)
		_back()                                         # and the read offset back at it
		wait = maxi(wait >> 1, 1)                      # `lsr.w`, 0 -> 1
		cursor -= 1
		return false
	if held & HELD_B:
		# `$9F22`: slow motion
		play = false
		if cursor >= n or not _count_down(elapsed):
			return false
		draw_frame()
		cursor += 1
		if cursor < n:
			_peek()
			wait = (wait << 1) & 0xFFFF                 # `lsl.w`: 2e
		return false
	if new & NEW_C:
		play = true
	elif new & START:
		leave()
		return true
	if not play:
		return false
	# `$9EB2`: playing
	if cursor >= n or not _count_down(elapsed):
		return false
	draw_frame()
	cursor += 1
	if cursor < n:
		_peek()
	return false


## The wait counted down by [param elapsed]: true when it reached 0 or
## below (`sub.w`, `beq` / `bpl`).
func _count_down(elapsed: int) -> bool:
	wait = MwRinkSim.s16(wait - elapsed)
	return wait <= 0


## `$9F5E`: the read offset and byte count put back (the ring as it was).
func leave() -> void:
	ring.read = saved_read
	ring.used = saved_used


## `$9FEA`: the header of the frame at the read offset: its e is the wait,
## its length gives the frame's end (the trailer's offset).
func _peek() -> void:
	var h := _word_at(ring.read)
	wait = h & 0xF
	frame_end = (ring.read + ((h & 0xFFF0) >> 3)) % MwRinkState.ReplayRing.SIZE


## `$A01A`: the read offset back to the previous frame (from its trailer's
## length), the byte count up by as much.
func _back() -> void:
	var t := (ring.read - 2 + MwRinkState.ReplayRing.SIZE) % MwRinkState.ReplayRing.SIZE
	var n := (_word_at(t) & 0xFFF0) >> 3
	ring.read = (t - n + MwRinkState.ReplayRing.SIZE) % MwRinkState.ReplayRing.SIZE
	ring.used = (ring.used + n + 2) & 0xFFFF


## `$9F82`: the frame at the read offset: the header; the camera point
## (`$5CE4`: plane B shown there, its scroll buffers); the hazards' kinds
## and flags (drawn at their live positions, the live slots left as they
## were); the markers and their plates (`$3B46`, `$6298`; a team's second
## marker if it has a pad now); the sprite records up to the frame's end
## (`$A0FE`); the trailer. The sprite list, its upload and the widget's
## texts are [MwReplaySim]'s draws.
##
## The sprite records are read until the read offset reaches the frame's
## end; the original would spin for ever on an empty ring whose stale word
## at the read offset is >= 16 (`$14548` takes nothing when no byte is
## held): here the loop stops when the ring is empty.
func draw_frame() -> void:
	var at := ring.read
	_decode(ring.take_word, func() -> bool: return ring.read != frame_end and ring.used > 0)
	ring.take_word()                                   # the trailer
	shown["at"] = at
	_port_side()
	drawn += 1


## Plan 34, an extended set-up: the frame's port side-record
## (MwRinkUpdate.port_side) - every player's marker, plate and arrow as
## drawn ([member shown]'s "marks", [x, y, depth, attr, frame]) and the
## plates' values then, written into the state as the ring's markers write
## theirs.
func _port_side() -> void:
	if not s.extended:
		return
	var side := frame_3d()
	shown["marks"] = side.get("marks", [])
	var plates: Array = side.get("plates", [])
	for i in mini(plates.size(), s.plates.size()):
		s.plates[i] = (plates[i] as Array).duplicate()


## The frames there are to play (the ring's).
func frame_count() -> int:
	return ring.frames


## The 3D view's frame (MwReplay3D) of the frame on screen ({} none);
## without the arena's paint unless the replays show it
## (MwSplatterReplay.shown: REPLAY BLOOD).
func frame_3d() -> Dictionary:
	var f := MwReplay3D.at(ring, int(shown.get("at", -1)))
	if f.has("splat") and not MwSplatterReplay.shown():
		f = f.duplicate()                       # (the ring's own is kept as recorded)
		f.erase("splat")
	return f


## A frame's words from its header up to its trailer, [param next] giving
## the next word and [param more] whether a sprite record follows: the
## camera point, the hazards, the markers, the sprite records (see
## [method draw_frame]) - into [member shown] (but its "at").
func _decode(next: Callable, more: Callable) -> void:
	next.call()                                        # the header
	var hi: int = next.call()
	var lo: int = next.call()
	var cam := Vector2i(MwRinkSim.s16(hi), MwRinkSim.s16(lo))
	_plane_b(cam)
	var hazards := []
	for i in 2:
		var w: int = next.call()
		for b in [(w >> 8) & 0xFF, w & 0xFF]:
			hazards.append([b & 7, b & 0xF8])
	for team in s.teams:
		_marker(team.markers[0], next)
		if team.flags4 & 4:
			_marker(team.markers[1], next)
	var sprites := []
	var guard := 0
	while more.call() and guard < 4096:
		guard += 1
		var l0: int = (int(next.call()) << 16) | int(next.call())
		var l1: int = (int(next.call()) << 16) | int(next.call())
		var x := ((l0 >> 24) & 0xFF) | (((l1 >> 6) & 1) << 8)
		var y := (((l0 >> 16) & 0xFF) << 1) | ((l1 >> 7) & 1)
		var bank := (l1 >> 8) & 0xFF
		var frame := (((0xFF00 | bank) if bank & 0x80 else bank) << 16) | ((l1 >> 16) & 0xFFFF)
		# (minus the pan `$C2D4` / `$C2D6`: always 0)
		sprites.append([x, y, l0 & 0xFFFF, (l1 & 0x3F) << 2, frame & 0xFFFFFF])
	shown = {"camera": cam, "hazards": hazards, "sprites": sprites}


## `$14CEE` / `$14CDE` on plane B (the incremental and the whole-plane
## redraw leave the same state): shown at [param cam], its first map row 2
## cells above, the scroll buffers.
func _plane_b(cam: Vector2i) -> void:
	s.camera.shown = cam
	var rows := MwGfx.u16(rom, MwRinkUpdate.MAP + 0xA) - MwRinkUpdate.PLANE_ROWS
	s.plane_b_cell = Vector2i(0, clampi((cam.y >> 3) - 2, 0, rows))
	s.scroll_b = Vector2i((-cam.x) & 0x1FF, cam.y & 0xFF)


## `$6298`: a marker's x, y, number, position and health from its words,
## then its plate (the health bar only with Reserves).
func _marker(marker: MwRinkState.Marker, next: Callable) -> void:
	marker.x = MwRinkSim.s16(next.call())
	marker.y = MwRinkSim.s16(next.call())
	var w: int = next.call()
	marker.number = (w >> 9) & 0x7F
	marker.position = (w >> 6) & 7
	marker.health = w & 0x3F
	var plate: Array = s.plates[marker.plate if s.extended else marker.plate & 3]     # (plan 34: fourteen)
	if s.reserves:
		plate[2] = marker.health
	plate[0] = marker.number
	plate[1] = marker.position


func _word_at(at: int) -> int:
	var b := ring.ring_bytes
	return (b[at % MwRinkState.ReplayRing.SIZE] << 8) | b[(at + 1) % MwRinkState.ReplayRing.SIZE]
