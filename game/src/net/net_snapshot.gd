class_name MwNetSnapshot
extends RefCounted
## A resync snapshot (plan 35 section 5, work item 6): everything a machine
## needs to take up an online match's game exactly where the host's is, at
## a safe point - a screen change ([signal MwRouter.entering]: the screens
## left are gone, the next one not made yet; every faceoff line-up is one,
## the rink entered at a period start or a faceoff). The host takes it
## ([method capture]); a machine that rejoined, whose game parted from the
## host's or whose stream has a gap that can't be filled loads it
## ([method restore], then [method MwRouter.resume_entry]) and follows the
## stream from that tick.
##
## What it holds:
## * the session - all of it but a machine's own ([constant SESSION_OWN]):
##   the start record's part (seeds and every stream's state, the setup,
##   the playoffs, the rules, the player table, the online table) and what
##   screens keep between visits - the rink's state (MwRinkState: every
##   field, the control layer with owners, captains and who is away, the
##   crowd's and the benches' life, the instant replay's ring with its
##   32 KB) - as one object graph ([MwNetGraph]: shared objects stay
##   shared). The whole match's recording isn't sent: a rejoiner's FULL
##   GAME replay starts at its return ([member MwFullReplay.before] keeps
##   the count the flow asks for). Nor is the arena's paint (plan 37,
##   MwRinkState.splatter: presentation, its atlas a megabyte and growing):
##   a machine taken up starts the paint afresh from the match's seed (the
##   rink's entry makes it: the ice's detail as everyone's, the blood so far
##   not there);
## * the screen being entered, its entry data (the matchup hands the rink
##   its crowd; the 3D opening's paint left out, as above) and the screen
##   left;
## * the sound driver's model (MwSound68k's memory, the Z80 side's channels,
##   the extra voices' model, the FM effect) and the sound API's own
##   bookkeeping (the carried goal song) - the answers the game waits on;
## * the router: its tick, visits, history, the last sample's held actions,
##   the pass clock's visits, the fade (MwRouter.snapshot_state); the input
##   stream's press counters as last seen (MwStreamInput.seen).
##
## On the wire ([method to_bytes]): var_to_bytes, zstd, its length first -
## about 40 KB in a match (the replay ring and the driver's memory are most
## of it), in MwNetChunks' chunks. [method from_bytes] checks the form
## before anything is used; a snapshot whose objects don't decode is
## refused whole ([method restore]'s errors).
## Short names: g the snapshot codec (MwNetGraph).

const FORMAT := 1
## The largest snapshot unpacked.
const MAX_RAW := 16 << 20
## The session's own to each machine (plan 40, S4: MwSession.OWN_FIELDS):
## the online pages' service, its id, its views, a client's dead reckoning.
const SESSION_OWN := MwSession.OWN_FIELDS
## The sound driver's model besides its 68000 side, Z80 side and register
## mirror: the extra voices, the voices fading in, the FM effect, its tick
## and serials.
const AUDIO_FIELDS := ["_extras", "_fade_ins", "extras_peak", "fm_sfx", "_tick", "_serial"]
## What every key must be ([method from_bytes]).
const SHAPE := {"format": TYPE_INT, "tick": TYPE_INT, "base": TYPE_INT, "screen": TYPE_INT,
		"previous": TYPE_INT, "fade": TYPE_BOOL, "ticks": TYPE_INT, "session": TYPE_ARRAY,
		"data": TYPE_ARRAY, "audio": TYPE_DICTIONARY, "sound": TYPE_DICTIONARY, "router": TYPE_DICTIONARY,
		"seen": TYPE_PACKED_BYTE_ARRAY}


## The object graph codec a snapshot uses: what each class leaves out (a
## machine's own, presentation - the 3D replay side-store -, the ROM and
## what is made from it, computed properties), the whole match's recording
## as its frame count.
static func codec() -> MwNetGraph:
	var g := MwNetGraph.new()
	g.skip = {
		"MwSession": SESSION_OWN,
		"MwRinkState": Array(MwRinkState.port_fields(MwRinkState.Port.LOCAL)),   # the paint (plan 37): a machine's own
		"MwRinkState.Player": ["present"],
		"MwRinkState.ReplayRing": ["side"],
		"MwSound68k": ["rom", "trace"],
		"MwSoundZ80": ["out", "samples", "rom"],
		"MwAudioOut": ["chips"],
	}
	g.custom = {"MwFullReplay": [
		func(r: MwFullReplay) -> Variant: return r.recorded(),
		func(n: Variant) -> Object:
			var r := MwFullReplay.new()
			r.before = maxi(int(n), 0) if n is int else 0
			return r]}
	return g


## The host's snapshot at a safe point: [param router]'s game as it is at
## [signal MwRouter.entering] ([param request] about to be entered from
## [param previous]); [param base] the router tick of stream tick 0;
## [param input] the router's MwStreamInput. Its "errors" (the codec's)
## name anything that couldn't be carried.
static func capture(router: MwRouter, request: Dictionary, previous: int, base: int,
		input: MwStreamInput) -> Dictionary:
	var g := codec()
	var d := {
		"format": FORMAT,
		"tick": router.tick,
		"base": base,
		"screen": int(request.get("id", -1)),
		"previous": previous,
		"fade": bool(request.get("fade", true)),
		"ticks": int(request.get("ticks", -1)),
		"session": g.encode(router.session),          # (the order the codec decodes them in)
		"data": g.encode(carried_data(request.get("data", {}))),
		"audio": audio_state(g, router.game_audio()),
		"sound": MwSound.snapshot_state(),
		"router": router.snapshot_state(),
		"seen": input.seen() if input != null else PackedByteArray(),
	}
	if not g.errors.is_empty():
		d["errors"] = g.errors
	return d


## Entry data [param data] as a snapshot carries it: the 3D opening's paint
## (plan 37, "splatter": MwSplatter, presentation) left out - the rink's
## entry makes a machine's own afresh.
static func carried_data(data: Variant) -> Variant:
	if data is Dictionary and (data as Dictionary).has("splatter"):
		var d := (data as Dictionary).duplicate()
		d.erase("splatter")
		return d
	return data


## The snapshot as it travels: its unpacked length (32 bits), then
## var_to_bytes of it, zstd.
static func to_bytes(d: Dictionary) -> PackedByteArray:
	return MwNetBytes.pack_var(d, FileAccess.COMPRESSION_ZSTD)


## [method to_bytes]'s bytes back ({} when they aren't a snapshot of this
## format: every key there with its type; nothing decoded into objects).
static func from_bytes(b: PackedByteArray) -> Dictionary:
	var v: Variant = MwNetBytes.unpack_var(b, MAX_RAW, FileAccess.COMPRESSION_ZSTD)
	if not v is Dictionary:
		return {}
	var d: Dictionary = v
	for k: String in SHAPE:
		if typeof(d.get(k)) != int(SHAPE[k]):
			return {}
	if int(d["format"]) != FORMAT:
		return {}
	return d


## Takes the game up from snapshot [param d] on [param router]: the router
## afresh at the snapshot's tick in the stream mode on [param stream] (the
## screens it had are gone first - their exits done), then [param
## session] filled in place (a machine's own kept: [constant SESSION_OWN]),
## the entry's data, the sound driver's model and the sound API's
## bookkeeping, the router's visits, history, last sample and fade. The
## caller puts the session's match rules in force, attaches the input
## (MwStreamInput.take_up with [code]d["seen"][/code]) and enters the screen
## once the stream holds the tick ([method MwRouter.resume_entry]).
## Returns {request, previous} for that, or {} with [param errors] saying
## why (the game is then in no state to run: the caller asks for another).
static func restore(router: MwRouter, session: MwSession, d: Dictionary, stream: MwInputStream,
		errors: PackedStringArray) -> Dictionary:
	var t := int(d["tick"])
	stream.first_tick = t
	router.reset_game(session, MwPassClock.streamed(stream), t)
	var g := codec()
	g.decode_into(session, d["session"])
	var data: Variant = g.decode(d["data"])
	restore_audio(g, router.game_audio(), d["audio"])
	if router.model != null and router.audio != null:
		# plan 41: an online client's heard driver from the game's model (one again)
		router.audio.lock()                        # (its pump's thread kept out meanwhile)
		router.audio.before_restore()
		MwAudioCopy.new().copy_into(router.audio, router.model)
		router.audio.after_restore()
		router.audio.unlock()
		if MwSound.heard != null:
			MwSound.heard.synced()
	errors.append_array(g.errors)
	if not data is Dictionary:
		errors.append("the entry's data")
	if not errors.is_empty():
		return {}
	MwSound.restore_state(d["sound"])
	router.restore_state(d["router"])
	return {"request": {"op": "go", "id": int(d["screen"]), "data": data, "fade": bool(d["fade"]),
			"ticks": int(d["ticks"])}, "previous": int(d["previous"])}


## The sound driver's model [param audio] as the snapshot carries it ({}: none).
static func audio_state(g: MwNetGraph, audio: MwAudio) -> Dictionary:
	if audio == null:
		return {}
	var d := {"s68k": g.encode(audio.s68k), "z80": g.encode(audio.z80), "out": g.encode(audio.out)}
	for f: String in AUDIO_FIELDS:
		d[f] = g.encode(audio.get(f))
	return d


## The driver's model from [param d] into [param audio] (its parts filled in
## place: the ROM and what is made from it, the chips, stay this
## machine's). A snapshot without one (a host without the model: never in
## a game) leaves the driver at power-on.
static func restore_audio(g: MwNetGraph, audio: MwAudio, d: Dictionary) -> void:
	if audio == null:
		return
	if d.is_empty():
		audio.reset()
		return
	audio.before_restore()
	for part: String in ["s68k", "z80", "out"]:
		g.decode_into(audio.get(part), d.get(part))
	for f: String in AUDIO_FIELDS:
		if d.has(f):
			g.assign(audio, f, g.decode(d[f]))
	audio.after_restore()
