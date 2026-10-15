class_name MwReplayFile
extends RefCounted
## Saved replays (plan 34, owner: at a match's end the local player or host
## is asked whether to save its replay to disk, named by the date and context
## with no filename prompt; the running demos too).
## A file holds a match's whole recording (plan 28's [MwFullReplay]: every
## frame the original's replay ring closed, with its 3D frame) and the
## match's state at its end ([MwSimDict]: what screen 7 draws the frames
## over - the teams, their markers and plates, the hazards, the stadium),
## in the player's data folder ([member dir]).
##
## The file: [constant MAGIC]; the header's length (32 bits, big-endian)
## and the header (var_to_bytes of a small dictionary, uncompressed, so the
## list reads it alone - [method header_of]); the body's raw and compressed
## lengths and the body (var_to_bytes of {state, replay}, zstd). The header:
## format version, build, the ROM's SHA-1 (another ROM's file is refused),
## the time it was saved, the setup's 10 bytes, the mode ("exhibition",
## "playoffs" with the run's round byte, "demo"), the final score, the
## teams and stadium, the frames and ticks recorded, the 3D frames' format
## ([constant SIDE_FORMAT]: a file whose 3D frames another format wrote
## plays in 2D), for a demo whether KEEP took it out of the demos' limit,
## and the players (plan 34: MwHumans' record). Nothing in a file is the ROM's: indices, state values and the
## frames' words (frame addresses, positions) only.
##
## The arena's paint (plan 37): never its texels - the recording keeps the
## paint's seed (MwFullReplay.splat_seed; the attract demo's is
## MwSplatter.DEMO_SEED) and each 3D frame the inputs that painted it since
## the frame before, and the playback makes it again (MwSplatterReplay). A
## file from before (no seed) plays the ice's detail from a derived seed and
## no blood ([method open]'s "paint": "derived").
##
## Names (no prompt): the date, the time, the mode and the teams, e.g.
## `2026-10-09_2114_exhibition_<a>-v-<b>.mwreplay` (team names read from the
## ROM at run time, made file-safe); a second one in the same minute gets
## its seconds, a third a number. The list builds its lines from the
## headers, not the names.
##
## Demos (owner: each demo that runs is recorded and kept as its own
## replay): saved without a question when the demo ends, if they showed
## [constant DEMO_MIN_TICKS] of play; the newest [constant DEMOS_KEPT] are
## kept, the oldest deleted as a new one comes; [method keep] takes one out
## of that limit.

const MAGIC := "MWRP"
const VERSION := 1
## The 3D frames' format (MwReplay3D's dictionaries as MwFullReplay keeps
## them); a new layout bumps it, and older files then play in 2D.
const SIDE_FORMAT := 1
const EXT := ".mwreplay"
## A demo is kept if it recorded this much play (ticks: 10 s).
const DEMO_MIN_TICKS := 600
const DEMOS_KEPT := 10
const MODES := ["exhibition", "playoffs", "demo", "online"]
## Plan 45 (M3): the most a file's header may hold (bytes: a bank's whole custom view fits).
const HEADER_MAX := 1 << 24
## Plan 45 (M3): the most a file's body may unpack to (bytes), and to how many times its packed size
## (zstd): a file that says more is refused before anything is allocated for it.
const BODY_MAX := 512 << 20
const BODY_RATIO := 256

## Where the replays live (tests point it elsewhere).
static var dir := "user://replays"
## The clock (unix seconds) the names and headers use; tests set it (< 0:
## the system's).
static var clock := -1.0


## The time (unix seconds) the names and headers use: [member clock] when set, else the system's.
static func now() -> int:
	return int(clock) if clock >= 0.0 else MwFileStamp.now()


## The team (0-22, a custom team's id: plan 38) playing as [param t] in
## [param state] (from its record).
static func team_of(state: MwRinkState, t: int) -> int:
	return MwTeams.id_of(state.teams[t].record)


## The header for [param state]'s match as [param session] played it, in
## [param mode] (one of [constant MODES]).
static func header_for(session: MwSession, state: MwRinkState, mode: String) -> Dictionary:
	var su := session.setup if session != null else MwMatchSetup.new()
	var ticks := 0
	var fr := state.full_replay
	if fr != null:
		for i in fr.size():
			ticks += fr.ticks(i)
	return {
		"version": VERSION,
		"build": "%s / godot %s" % [str(ProjectSettings.get_setting("application/config/version", "dev")),
				str(Engine.get_version_info().get("string", ""))],
		"rom_sha1": MwFileStamp.rom_sha1(),
		"time": now(),
		"setup": su.to_bytes().hex_encode(),
		"mode": mode,
		"round": session.playoffs.round if session != null and mode == "playoffs" else -1,
		"score": [state.teams[0].score, state.teams[1].score],
		"team_a": team_of(state, 0),
		"team_b": team_of(state, 1),
		"stadium": state.stadium,
		"frames": fr.size() if fr != null else 0,
		"ticks": ticks,
		"side_format": SIDE_FORMAT,
		"kept": false,
		# plan 34: who played (MwHumans' record: each team's player numbers - their
		# colours are MwPlayerColours'); an extended set-up's markers are in the frames
		"players": session.humans_record() if session != null else {},
		# plan 38: a match of a custom team or at a custom rink keeps the custom
		# teams' view (its records are addresses in it) and the teams' names (the
		# bank may change since) - online the host's teams, in use for the match
		"custom_view": MwCustomTeams.snapshot() if maxi(maxi(team_of(state, 0), team_of(state, 1)),
				state.stadium) >= MwTeams.COUNT else {},
		"names": [_name(team_of(state, 0)), _name(team_of(state, 1))],
	}


## Team [param team]'s name as the list shows it.
static func _name(team: int) -> String:
	if not MwRom.available():
		return ""
	var rom := MwRom.data()
	return MwTeams.name_text(rom, team)


## Writes [param state]'s match (its whole recording) with [param header];
## returns the file's path ("" when nothing was recorded or it couldn't be
## written).
static func save(state: MwRinkState, header: Dictionary) -> String:
	if state.full_replay == null or state.full_replay.size() == 0:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := free_name(header)
	var body := var_to_bytes({"state": MwSimDict.to_dict(state), "replay": state.full_replay.to_data()})
	return path if _write(path, header, body) else ""


## Saves [param state]'s match as [param session] played it, mode
## [param mode]: [method header_for] then [method save].
static func save_match(session: MwSession, state: MwRinkState, mode: String) -> String:
	return save(state, header_for(session, state, mode))


## The attract demo that just ended (owner: each demo kept as its own
## replay): saved if it showed [constant DEMO_MIN_TICKS] of play, then the
## oldest demos beyond [constant DEMOS_KEPT] deleted. Returns the path ("":
## not kept).
static func save_demo(session: MwSession, state: MwRinkState) -> String:
	if state == null or state.full_replay == null:
		return ""
	var h := header_for(session, state, "demo")
	if int(h["ticks"]) < DEMO_MIN_TICKS:
		return ""
	var path := save(state, h)
	if path != "":
		prune_demos()
	return path


## Deletes the oldest demos not kept beyond the newest [constant DEMOS_KEPT].
static func prune_demos() -> void:
	var demos := list().filter(func(e: Dictionary) -> bool:
		return e["header"].get("mode") == "demo" and not e["header"].get("kept", false))
	for i in range(DEMOS_KEPT, demos.size()):
		delete(demos[i]["path"])


## The replays, newest first: [{path, header, ok}] (ok: this ROM's and a
## version this build reads; the header [method plain_header]'s). Plan 45
## (L4): a ".part" a crash left is taken up when it is a whole file whose
## replay is missing, else deleted (MwUserFile.recover).
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(EXT + ".part"):
			MwUserFile.recover(dir.path_join(f.trim_suffix(".part")), func(tmp: String) -> bool: return _whole(tmp))
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(EXT):
			continue
		var text := dir.path_join(f)
		var h := header_of(text)
		if h.is_empty():
			continue
		out.append({"path": text, "header": h, "ok": readable(h)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int(a["header"].get("time", 0))
		var tb := int(b["header"].get("time", 0))
		return ta > tb if ta != tb else str(a["path"]) > str(b["path"]))
	return out


## True when this build plays a file with header [param h].
static func readable(h: Dictionary) -> bool:
	return MwPlain.num(h.get("version", 0)) == VERSION \
			and MwFileStamp.rom_matches(MwPlain.text(h.get("rom_sha1", "")))


## [param path]'s header ({} not a replay), as [method plain_header] reads it.
static func header_of(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var h := _header(f) if f != null else {}
	return plain_header(h) if not h.is_empty() else {}


## The header at the start of [param f] as the file has it (left after it;
## {} not a replay; plan 45: nor one whose header says it is longer than
## [constant HEADER_MAX]).
static func _header(f: FileAccess) -> Dictionary:
	f.big_endian = true
	if f.get_length() < 8 or f.get_buffer(4).get_string_from_ascii() != MAGIC:
		return {}
	var n := f.get_32()
	if n <= 0 or n > HEADER_MAX or n > f.get_length() - f.get_position():
		return {}
	var h: Variant = bytes_to_var(f.get_buffer(n))
	return h if h is Dictionary else {}


## Plan 45 (M3): [param h] (a file's header: files are shared, so any values)
## as the header the game reads - every field through [MwPlain], a value of
## the wrong type its default: the numbers, the texts, the score two numbers,
## the names two texts or none, the players and the custom view dictionaries
## (the view is checked when the file opens: MwCustomTeams.show_snapshot).
static func plain_header(h: Dictionary) -> Dictionary:
	var score := MwPlain.ints(h.get("score"))
	var names := MwPlain.array(h.get("names"))
	return {
		"version": MwPlain.num(h.get("version")),
		"build": MwPlain.text(h.get("build")),
		"rom_sha1": MwPlain.text(h.get("rom_sha1")),
		"time": MwPlain.num(h.get("time")),
		"setup": MwPlain.text(h.get("setup")),
		"mode": MwPlain.text(h.get("mode")).substr(0, 32),
		"round": MwPlain.num(h.get("round"), -1),
		"score": [score[0], score[1]] if score.size() == 2 else [0, 0],
		"team_a": MwPlain.num(h.get("team_a")),
		"team_b": MwPlain.num(h.get("team_b")),
		"stadium": MwPlain.num(h.get("stadium")),
		"frames": MwPlain.num(h.get("frames")),
		"ticks": MwPlain.num(h.get("ticks")),
		"side_format": MwPlain.num(h.get("side_format")),
		"kept": MwPlain.flag(h.get("kept")),
		"players": MwPlain.dict(h.get("players")),
		"custom_view": MwPlain.dict(h.get("custom_view")),
		"names": [MwPlain.text(names[0]), MwPlain.text(names[1])] if names.size() == 2 else [],
	}


## Plan 45 (L4): whether the file at [param path] is a whole replay: its
## header, then the body's lengths and a body as long as they say.
static func _whole(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or _header(f).is_empty() or f.get_length() - f.get_position() < 8:
		return false
	f.get_32()
	return f.get_32() == f.get_length() - f.get_position()


## [param path]'s match: {header ([method plain_header]'s), state
## (MwRinkState, its full_replay the file's frames), sides (false: its 3D
## frames dropped, it plays in 2D), paint ("recorded": the paint's seed and
## inputs kept, made again as it was; "derived": an older file without them -
## the ice's detail from a derived seed, no blood, and a line in the log says
## so; "none": 2D, or played with the paint off), view (true: the file's
## custom teams' view is shown now - the caller shows the bank's again with
## MwCustomTeams.rebuild when the replay is over)}; {} when it isn't one this
## build plays (another ROM's, another version's, damaged, a custom view
## that doesn't hold its records) - nothing then changed.
static func open(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var raw_header := _header(f)
	if raw_header.is_empty():
		return {}
	var h := plain_header(raw_header)
	if not readable(h) or f.get_length() - f.get_position() < 8:
		return {}
	var raw := f.get_32()
	var n := f.get_32()
	# plan 45 (M3): the sizes the file says capped before anything is allocated for them
	if raw <= 0 or n <= 0 or n > f.get_length() - f.get_position() or raw > BODY_MAX or raw > BODY_RATIO * n:
		return {}
	var packed := f.get_buffer(n)
	var body: Variant = bytes_to_var(packed.decompress(raw, FileAccess.COMPRESSION_ZSTD))
	if not (body is Dictionary) or not (body.get("state") is Dictionary) or not (body.get("replay") is Dictionary):
		return {}
	var sides: bool = h["side_format"] == SIDE_FORMAT
	var state := MwSimDict.from_dict(body["state"])
	state.full_replay = MwFullReplay.from_data(body["replay"], sides)
	if state.full_replay.size() == 0:
		return {}
	var paint := "none"
	if sides and MwSplatterReplay.painted(state.full_replay):
		paint = "recorded" if state.full_replay.splat_seed >= 0 else "derived"
		if paint == "derived":
			print(("MwReplayFile: %s keeps no paint seed (a file from before): the ice's detail from a derived seed "
					+ "(%d), no blood")
					% [path.get_file(), MwSplatterReplay.derived_seed(state.full_replay)])
	# plan 38: the custom teams as they were (until the screen leaves); plan 45 (M3): shown only once
	# everything else has opened, and only a view that holds its records
	var view: Dictionary = h["custom_view"]
	if not view.is_empty() and not MwCustomTeams.show_snapshot(view):
		push_warning("MwReplayFile: %s keeps a custom teams' view that doesn't hold its teams - refused"
				% path.get_file())
		return {}
	return {"header": h, "state": state, "sides": sides, "paint": paint, "view": not view.is_empty()}


## Deletes the replay file at [param path] (nothing when there is none).
static func delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## KEEP: [param path] (a demo) out of the demos' limit - its header
## rewritten. False when it isn't a demo or can't be rewritten.
static func keep(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var h := _header(f)
	if MwPlain.text(h.get("mode")) != "demo":
		return false
	var rest := f.get_buffer(f.get_length() - f.get_position())
	f.close()
	h["kept"] = true
	return _write_raw(path, h, rest)


## A name for [param header]'s replay that no file has yet.
static func free_name(header: Dictionary) -> String:
	var t := MwPortMenu.local_time(int(header.get("time", now())))
	var day := "%04d-%02d-%02d" % [t.year, t.month, t.day]
	var tail := "_%s_%s-v-%s%s" % [str(header.get("mode", "match")), _safe(int(header.get("team_a", 0))),
			_safe(int(header.get("team_b", 0))), EXT]
	var text := dir.path_join("%s_%02d%02d%s" % [day, t.hour, t.minute, tail])
	if not FileAccess.file_exists(text):
		return text
	text = dir.path_join("%s_%02d%02d%02d%s" % [day, t.hour, t.minute, t.second, tail])
	var n := 2
	while FileAccess.file_exists(text):
		text = dir.path_join("%s_%02d%02d%02d-%d%s" % [day, t.hour, t.minute, t.second, n, tail])
		n += 1
	return text


## Team [param team]'s name (the ROM's, at run time) as a file name takes it:
## lower case letters and digits, "-" for the rest.
static func _safe(team: int) -> String:
	if not MwRom.available() or team < 0 or team >= MwCustomTeams.readable():
		return "team%d" % team
	var rom := MwRom.data()
	var text := MwTeams.name_text(rom, team).to_lower()
	var out := ""
	for c in text:
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
	return out.strip_edges().trim_prefix("-").trim_suffix("-")


static func _write(path: String, header: Dictionary, body: PackedByteArray) -> bool:
	var rest := PackedByteArray()
	var packed := body.compress(FileAccess.COMPRESSION_ZSTD)
	rest.resize(8)
	rest.encode_u32(0, body.size())
	rest.encode_u32(4, packed.size())
	_big_endian(rest, 0)
	_big_endian(rest, 4)
	rest.append_array(packed)
	return _write_raw(path, header, rest)


## The magic and the header, then [param rest] (the body's lengths and the
## body) as it is; plan 45 (M2): through MwUserFile.write_atomic, which
## commits the file only once it reads back whole (KEEP rewrites a replay in
## place: a full disk no longer loses it).
static func _write_raw(path: String, header: Dictionary, rest: PackedByteArray) -> bool:
	var hb := var_to_bytes(header)
	var bytes := MAGIC.to_ascii_buffer()
	var length := PackedByteArray()
	length.resize(4)
	MwGfx.put_u32(length, 0, hb.size())
	bytes.append_array(length)
	bytes.append_array(hb)
	bytes.append_array(rest)
	return MwUserFile.write_atomic(path, bytes)


## The 32-bit value at [param at] (little-endian, as encode_u32 writes it) turned big-endian.
static func _big_endian(b: PackedByteArray, at: int) -> void:
	MwGfx.put_u32(b, at, b.decode_u32(at))
