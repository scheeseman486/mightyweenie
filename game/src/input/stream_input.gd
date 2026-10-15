class_name MwStreamInput
extends MwInputSource
## The router's input from an input stream (plan 35, docs/net.md): the
## game sees only what [member stream] holds for the router's tick, so a
## game is a pure function of its start record and its stream. The router
## steps a tick only when the stream has it (MwPassClock's stream mode).
##
## * Playing a stream (a recording, or online the host's merged stream):
##   [method sample] gives the tick's held actions, [method taps] the
##   actions whose press counters moved since the last call (a press is
##   never lost, only late), [method sticks] the tick's stick codes decoded
##   (MwStick), [method heights] its shot heights (MwTickInput.heights).
## * Recording: with a [member source] (the player's devices, bots) each
##   tick first captures what the source gives - its sample in the screen's
##   contexts at the tick's start, its presses, its stick codes, its shot
##   heights - as the stream's next tick, and the game plays that. Plan 40
##   (S7, one input tick): captured as the network captures a machine's
##   players - every player's state and the shared menu verbs' through
##   MwNetInput.capture - so offline and online play the same form.
## * Live ([method live]: offline play): a capture that keeps only the
##   last ticks; the actions of this machine's own screens that the stream
##   never carries (MwVerbs.local_verbs: CREATE-A-TEAM's, the rink
##   editor's) pass straight through.

var stream: MwInputStream
## Record mode: the source captured into [member stream] each tick (null:
## play the stream as it is).
var source: MwInputSource = null
## The router (its tick and screen for the capture).
var router: MwRouter

var _tick := 0
var _seen := PackedByteArray()      # the press counters at the last taps()
var _ran := PackedByteArray()       # ... at the one before: the presses the screens' passes have had
## Live ([method live]): only the last ticks kept (a capture to play, not a
## recording).
var keep_all := true
var _local_held := {}               # the local verbs held at the last capture (live)
var _local_taps := {}               # ... pressed since the last taps()


## Plan 40 (S7): offline play's input - [param source] (the devices)
## captured each tick through the wire's form, played at once, not kept.
static func live(source_: MwInputSource) -> MwStreamInput:
	var stream_input := MwStreamInput.new(null, source_)
	stream_input.keep_all = false
	return stream_input


func _init(stream_: MwInputStream = null, source_: MwInputSource = null) -> void:
	stream = stream_ if stream_ != null else MwInputStream.new()
	source = source_


## Uses this as [param router_]'s input; a recording starts at the router's
## next tick.
func attach(router_: MwRouter) -> void:
	router = router_
	router.input = self
	if source != null and stream.ticks.is_empty():
		stream.first_tick = router.tick + 1


## Plan 35 work item 6: the press counters as the last [method taps] saw
## them (a resync snapshot carries them: the next taps compare with them).
func seen() -> PackedByteArray:
	return _seen.duplicate()


## Plan 41: the press counters of the presses the screens' passes have run
## - [method seen] less those the router's next pass has taken but not yet
## run (its frame, sampled after the last pass). A client online shows its
## own presses past these at once (MwNetMatch.unconfirmed).
func ran() -> PackedByteArray:
	return _ran.duplicate() if _ran.size() == _seen.size() else _seen.duplicate()


## A game taken up from a resync snapshot: the counters seen [param
## counters], the router's tick [param at] (whose input the stream holds).
func take_up(counters: PackedByteArray, at: int) -> void:
	_seen = counters.duplicate()
	_ran = _seen.duplicate()
	_tick = at


## Moves to the router's tick (without a router, the next); recording, captures the source's
## input for it unless the stream has it already.
func tick() -> void:
	_tick = router.tick if router != null else _tick + 1
	if source != null and not stream.has_tick(_tick):
		_capture()


## The source's input for this tick, as the stream's next entry: every
## player's state and the shared menu verbs' captured as the network
## captures them (MwNetInput.sample_of / capture).
func _capture() -> void:
	var before := stream.at(_tick - 1)
	if not keep_all:
		# live: only the tick before (the counters go on from it) and this one
		if before == null and not stream.ticks.is_empty():
			before = stream.ticks[-1]           # (the router's tick moved under a live capture)
		stream.ticks.clear()
		stream.first_tick = _tick
		if before != null:
			stream.first_tick = _tick - 1
			stream.ticks.append(before)
	var prev: Array = before.states() if before != null else [MwNetInput.blank(), MwNetInput.blank_tick()]
	var source_sample := MwNetInput.sample_of(source, router.contexts() if router != null else [])
	var shared := MwNetInput.capture(prev[0], MwNetInput.SHARED, source_sample)
	var players := []
	for n in range(1, MwNetInput.PLAYERS + 1):
		players.append(MwNetInput.capture(MwNetInput.player(prev[1], n), n, source_sample))
	stream.append(MwTickInput.from_states(shared, MwNetInput.make_tick(players)))
	if not keep_all:
		_local_held = {}
		for a: String in source_sample["held"]:
			if MwVerbs.is_local(a):
				_local_held[a] = true
		for a: String in source_sample["taps"]:
			if MwVerbs.is_local(a):
				_local_taps[a] = true


## The actions held at the stream's tick, with the local verbs held at the last live capture.
func sample(_contexts: Array) -> Dictionary:
	var ti := stream.at(_tick)
	var out := ti.held_actions() if ti != null else {}
	if not _local_held.is_empty():
		out.merge(_local_held)
	return out


## The actions whose press counters moved since the last call (a press is never lost, only
## late) and the local verbs pressed since; the counters are noted for the next call.
func taps() -> Dictionary:
	var out := _local_taps
	_local_taps = {}
	var ti := stream.at(_tick)
	if ti == null:
		return out
	if _seen.size() != ti.counts.size():
		_seen = MwTickInput.after(null).counts     # every counter starts at 0 with the stream
	_ran = _seen
	if ti.counts != _seen:
		var names := MwTickInput.actions()
		for i in ti.counts.size():
			if ti.counts[i] != _seen[i]:
				out[names[i]] = true
		_seen = ti.counts.duplicate()
	return out


## The tick's stick codes decoded ([method MwStick.decode]), players 1-12; empty when every
## one is [constant MwStick.NONE].
func sticks() -> Array:
	var ti := stream.at(_tick)
	if ti == null:
		return []
	var any := false
	for c in ti.sticks:
		if c != MwStick.NONE:
			any = true
			break
	if not any:
		return []
	var out := []
	for c in ti.sticks:
		out.append(MwStick.decode(c))
	return out


## The tick's shot heights (players 1-12: -1 the D-pad's, 0 none, 1 high,
## 2 low), or empty when every one is the D-pad's (as a source without
## them gives).
func heights() -> Array:
	var ti := stream.at(_tick)
	if ti == null or ti.heights.count(0) == ti.heights.size():
		return []
	var out := []
	for c in ti.heights:
		out.append(MwTickInput.height_of(c))
	return out


## The tick's stick codes as the stream holds them ([MwStick] codes, players 1-12); empty
## without the tick.
func stick_codes() -> PackedInt32Array:
	var ti := stream.at(_tick)
	return ti.sticks.duplicate() if ti != null else PackedInt32Array()


## Plan 40 (S7): the tick ([MwTickInput]: every player's state as the wire
## has it) the router's frame reads a player's own input from.
func tick_input() -> MwTickInput:
	return stream.at(_tick)


## The tick's network statuses (plan 35 work item 4: the host's word on
## which machines are silent, dropped or kicked).
func away() -> Dictionary:
	var ti := stream.at(_tick)
	return ti.away() if ti != null else {}
