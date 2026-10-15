class_name MwNetRecording
extends RefCounted
## A game as the network would carry it, kept in a file (plan 35, docs/net.md:
## the offline proof, `tools/bin/net-determinism`): its start record
## (MwSession.to_record), its input stream (MwInputStream) and the hashes
## the machine that played it saw (MwNetHash: the rink every pass, the
## session at every screen change). Replayed from the record and the stream
## in a fresh process, a game must give the same hashes.

const FORMAT := 1
## [member hashes]' kinds.
const PASS := 0
const SCREEN := 1

var record := {}
var stream := MwInputStream.new()
## [tick, kind, screen, hash] in the order they came.
var hashes: Array = []


## Hashes [param router]'s game as it runs: the rink's state after every
## pass of the rink and the screens between plays (4-17, while the session
## has a rink state), the session at every screen entered.
func watch(router: MwRouter) -> void:
	router.pass_ended.connect(func(b: Dictionary) -> void:
		var id := int(b.screen)
		var st: Variant = router.session.screens.get("rink") if router.session != null else null
		if st is MwRinkState and id >= 4 and id <= 17:
			hashes.append([router.tick, PASS, id, MwNetHash.rink(st)]))
	router.screen_entered.connect(func(id: int, _visit: int, tick: int, _prev: int) -> void:
		hashes.append([tick, SCREEN, id, MwNetHash.session(router.session)]))


## Writes the recording ([member record], [member stream], [member hashes]) to [param path]:
## OK, or the error opening it.
func save(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var({"format": FORMAT, "record": record, "stream": stream.to_bytes(), "hashes": hashes})
	f.close()
	return OK


## The recording in [param path], or null.
static func open(path: String) -> MwNetRecording:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d: Variant = f.get_var()
	f.close()
	if not d is Dictionary or int((d as Dictionary).get("format", 0)) != FORMAT:
		return null
	var recording := MwNetRecording.new()
	recording.record = d["record"]
	recording.stream = MwInputStream.from_bytes(d["stream"])
	recording.hashes = d["hashes"]
	return recording if recording.stream != null else null


## The first difference between [param mine] (a replay's hashes) and these,
## as text ("" when every hash is equal and as many).
func first_difference(mine: Array) -> String:
	for i in mini(hashes.size(), mine.size()):
		if str(hashes[i]) != str(mine[i]):
			return "hash %d: recorded %s, replayed %s" % [i, str(hashes[i]), str(mine[i])]
	if hashes.size() != mine.size():
		return "%d hashes recorded, %d replayed" % [hashes.size(), mine.size()]
	return ""
