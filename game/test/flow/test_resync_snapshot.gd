extends "res://test/rom/rom_test_base.gd"
## Plan 35 work item 6: a game taken up from a resync snapshot goes on as
## the game it was taken from - offline, one process, no network. A local
## match with bots is recorded (start record, input stream, hashes: test/
## screens/net_proof.gd); replayed from the record, it takes snapshots at
## screen changes (MwRouter.entering: the matchup, the rink's faceoff
## line-ups, the screens between plays); each snapshot, through its bytes,
## is taken up by a fresh machine (its own router, session and sound driver
## model, nothing shared) that follows the same stream from there: every
## hash it makes equals the recording's from that tick on. And the pieces:
## the object graph codec (shared objects, typed arrays, random number
## generators, floats, what is left out, what may be made), malformed
## snapshots refused.

const Proof := preload("res://test/screens/net_proof.gd")
const TICKS := 3000
## Ticks a machine that took the game up follows the stream for.
const FOLLOW := 900

var _rec: MwNetRecording


func before_all() -> void:
	super.before_all()
	if not rom.is_empty():
		_rec = Proof.record(self, {"seed": 7, "humans": "1.2", "teams": "3,8"}, TICKS)


func after_all() -> void:
	MwGameStart.own_context()
	MwSound.driver = null
	MwSound.reset()
	MwSettings.start_view = -1


## One machine's game for these tests: a router under a node of its own,
## the sound driver's model, the hashes it makes (MwNetRecording.watch).
class Game extends RefCounted:
	var host: Node
	var router: MwRouter
	var input: MwStreamInput
	var seen := MwNetRecording.new()

	func _init(parent: Node, pass_clock: MwPassClock = null) -> void:
		host = Node.new()
		parent.add_child(host)
		var fader := MwScreenFader.new()
		host.add_child(fader)
		router = MwRouter.new(host, fader, pass_clock)
		router.session = MwSession.new(1, 1)
		MwSound.reset()
		host.add_child(router.use_driver_model(MwRom.data()))

	func free_all() -> void:
		router.stack.clear()
		if MwSound.driver == router.audio:
			MwSound.driver = null
		host.get_parent().remove_child(host)
		host.free()


## The recording replayed from its record; at each screen change [param
## want] accepts ([param want].call(screen, tick) -> bool) a snapshot is
## taken, until [param limit]: [[tick, screen, bytes] ...] (the replay's own
## hashes checked against the recording's on the way).
func _replay_taking(want: Callable, limit: int) -> Array:
	var game := Game.new(self)
	MwSettings.start_view = -1
	MwGameStart.begin(game.router, game.router.session, _rec.record, MwPassClock.streamed(_rec.stream))   # plan 40 (S5)
	game.input = MwStreamInput.new(_rec.stream)
	game.input.attach(game.router)
	game.seen.watch(game.router)
	var taken := []
	game.router.entering.connect(func(req: Dictionary, prev: int) -> void:
		if want.call(int(req.id), game.router.tick):
			var d := MwNetSnapshot.capture(game.router, req, prev, 1, game.input)
			assert_false(d.has("errors"), "nothing left out: %s" % str(d.get("errors", [])))
			taken.append([game.router.tick, int(req.id), MwNetSnapshot.to_bytes(d)]))
	MwGameStart.enter_first(game.router, _rec.record)
	while taken.size() < limit and game.router.step():
		pass
	assert_eq(_first_difference(game.seen.hashes, _rec.hashes, false), "", "the replay is the recording so far")
	game.free_all()
	MwGameStart.own_context()
	return taken


## A fresh machine takes the game up from snapshot [param bytes] (router
## tick [param at]) and follows the recording's stream for [constant
## FOLLOW] ticks: its hashes.
func _take_up(bytes: PackedByteArray, at: int) -> Array:
	var game := Game.new(self)
	var d := MwNetSnapshot.from_bytes(bytes)
	assert_false(d.is_empty(), "the snapshot reads back")
	if d.is_empty():
		game.free_all()
		return []
	var stream := MwInputStream.new()
	var errors := PackedStringArray()
	var entry := MwGameStart.take_up(game.router, game.router.session, d, stream, errors)   # plan 40 (S5)
	assert_eq(errors, PackedStringArray(), "taken up whole")
	assert_false(entry.is_empty())
	if entry.is_empty():
		game.free_all()
		return []
	MwSettings.start_view = -1
	for t in range(at, mini(at + FOLLOW, _rec.stream.last_tick()) + 1):
		stream.append(_rec.stream.at(t))
	game.input = MwStreamInput.new(stream)
	game.input.attach(game.router)
	game.input.take_up(d["seen"], at)
	game.seen.watch(game.router)
	game.router.resume_entry(entry["request"], int(entry["previous"]))
	while game.router.step():
		pass
	var out := game.seen.hashes
	game.free_all()
	MwGameStart.own_context()
	return out


func test_a_game_taken_up_from_a_snapshot_goes_on_the_same() -> void:
	if not need_rom():
		return
	var screens := []
	var taken := _replay_taking(func(id: int, _t: int) -> bool:
		screens.append(id)
		# the matchup's first entry, the rink's first period start and first
		# faceoff after a stoppage, a screen between plays
		if id == 3 and not 3 in screens.slice(0, -1):
			return true
		if id in [4, 5] and not id in screens.slice(0, -1):
			return true
		if id >= 7 and id <= 18:
			return true
		return false, 3)
	gut.p("screen changes: %s; snapshots at %s" % [str(screens), str(taken.map(func(e: Array) -> String:
			return "%d (screen %d, %d bytes)" % [e[0], e[1], (e[2] as PackedByteArray).size()]))])
	assert_true(taken.any(func(e: Array) -> bool: return int(e[1]) in [4, 5]), "a snapshot at a faceoff line-up")
	assert_true(taken.any(func(e: Array) -> bool: return not int(e[1]) in [4, 5, 6]), "a snapshot at another screen")
	for snapshot: Array in taken:
		var at := int(snapshot[0])
		var mine := _take_up(snapshot[2], at)
		var theirs := _rec.hashes.filter(func(h: Array) -> bool: return int(h[0]) >= at and int(h[0]) <= at + FOLLOW)
		assert_gt(theirs.size(), 20, "hashes after tick %d" % at)
		assert_eq(_first_difference(mine, theirs), "",
				"taken up at tick %d (screen %d): every hash the recording's" % [at, snapshot[1]])


## The first difference between hash lists [param mine] and [param theirs]
## ("" none; with [param whole], as many too).
static func _first_difference(mine: Array, theirs: Array, whole := true) -> String:
	for i in mini(mine.size(), theirs.size()):
		if str(mine[i]) != str(theirs[i]):
			return "hash %d: %s, the recording's %s" % [i, str(mine[i]), str(theirs[i])]
	if whole and mine.size() != theirs.size():
		return "%d hashes, the recording %d" % [mine.size(), theirs.size()]
	return ""
