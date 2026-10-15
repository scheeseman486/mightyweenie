class_name MwCustomTeams
extends RefCounted
## The custom team bank (plan 38): the teams in `user://teams/*.json` (one
## file a team, sorted by file name), their game ids (23, 24, ... after the
## original's 0-22) and the overlay that shows them to the game
## ([MwCustomOverlay], [method MwRom.data]). Also the ROM choices the
## editor offers (faces, ice palettes) and the lookups that are tables in
## the original (coach and star entries). Static: menus, sims and tests
## share one bank. With no custom team nothing here changes what the game
## reads.
## Short names: t a custom team (MwCustomTeam).

const DIR := "user://teams"
## Ice palettes offered as presets: the stadiums' (`$1BE36`, 4 distinct of
## 6) then the three beside them that no stadium uses.
const UNUSED_ICE := [0x2458, 0x2498, 0x24B8]
const PRESETS := 7
## Plan 45: the most bytes a saved view holds (its addresses stay below
## `$FF0000`: RAM to MwMenuRows) and the most team records (team ids are bytes).
const VIEW_MAX := 0xFF0000 - MwCustomOverlay.BASE
const VIEW_RECORDS := 0x100

## The folder the bank lives in (tests point it elsewhere).
static var dir := DIR
## The teams the game plays: the bank's switched on ([member
## MwCustomTeam.enabled]), game ids 23, 24 ... in this order.
static var teams: Array[MwCustomTeam] = []
## The bank's teams switched off in CREATE-A-TEAM's list (owner,
## 2026-10-11): kept in their files and the editor's list ([method all]),
## out of the game - no game id, no team row, not in the overlay or a start
## record - until switched on again ([method set_enabled]).
static var disabled: Array[MwCustomTeam] = []
## The editor's working copy (CREATE-A-TEAM's screens): seen by the game's
## readers under [method editing_id] - a saved team's own id when it is
## that team's copy, else one past the bank - and nowhere else (not in the
## menus' rows, [method count]); null when nothing is being edited.
static var editing: MwCustomTeam = null
static var _editing_slot := -1
static var _records := PackedInt32Array()
## Bumped on every rebuild (screens holding a bank view can tell).
static var version := 0
## Plan 38 with plan 35: this machine's own bank and working copy, put aside
## while a game's teams are in use instead ([method use_teams]: an online
## match, a replay of a start record); empty: none put aside.
static var _own := {}


## How many custom teams there are.
static func count() -> int:
	return teams.size()


## Every team id the game can read: the original's, the bank's and the
## editor's working copy (the crowd's colour rows, the palettes).
static func readable() -> int:
	return MwTeams.COUNT + _records.size()


## Whether game id [param id] is one of the bank's teams that are on ([member teams]).
static func is_custom(id: int) -> bool:
	return id >= MwTeams.COUNT and id < MwTeams.COUNT + teams.size()


## The custom team of game id [param id], or null.
static func team(id: int) -> MwCustomTeam:
	return teams[id - MwTeams.COUNT] if is_custom(id) else null


## The game id of [param t] (-1: not in the bank).
static func id_of_team(t: MwCustomTeam) -> int:
	var i := teams.find(t)
	return -1 if i < 0 else MwTeams.COUNT + i


## Custom team [param id]'s record address in the view (0: none).
static func record_of(id: int) -> int:
	var i := id - MwTeams.COUNT
	return _records[i] if i >= 0 and i < _records.size() else 0


## The custom team whose record is at [param record] (-1: none).
static func id_of(record: int) -> int:
	var i := _records.find(record)
	return -1 if i < 0 else MwTeams.COUNT + i


# --- the bank ---------------------------------------------------------------------------


## Read every team file of [member dir] and show them to the game (while
## a game's teams are in use, [method use_teams], they become the bank put
## aside, shown once the game is over).
static func load_bank() -> void:
	var rom := MwRom.archive().bytes()
	if teams_in_use():
		var was := teams.duplicate()
		var held: Dictionary = _own
		_own = {}
		load_bank()
		held["teams"] = teams.duplicate()
		teams.assign(was)
		_own = held
		rebuild()
		return
	teams.clear()
	disabled.clear()
	var d := DirAccess.open(dir)
	if d != null and not rom.is_empty():
		for f in d.get_files():
			if f.ends_with(".json.part"):            # plan 45 (L4): a write a crash left
				MwUserFile.recover(dir.path_join(f.trim_suffix(".part")), func(tmp: String) -> bool:
					return _team_json(FileAccess.get_file_as_string(tmp)) != null)
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f: String in files:
			if f.get_extension() != "json":
				continue
			var t := read_file(rom, dir.path_join(f))
			if t != null:
				t.id = f.get_basename()
				(teams if t.enabled else disabled).append(t)
	rebuild()


## The team in the JSON file at [param path], or null.
static func read_file(rom: PackedByteArray, path: String) -> MwCustomTeam:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_warning("CREATE-A-TEAM: %s is not a team file" % path)
		return null
	return MwCustomTeam.from_dict(rom, data)


## [param text] as a team file's dictionary, or null when it isn't one (no
## complaint: a ".part" being looked at).
static func _team_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return json.data


## Write [param t] to its file (a new team gets one named after it) and
## show the bank again; a team of the same file is replaced. Returns the
## team's game id (plan 45: also when the file couldn't be written - the team
## is in the game until it quits, and a warning says so: [method write]).
static func save(t: MwCustomTeam) -> int:
	if teams_in_use():
		push_warning("CREATE-A-TEAM: a game's teams are in use - nothing saved")
		return -1
	var rom := MwRom.archive().bytes()
	t.validate(rom)
	if t.id == "":
		t.id = _new_id(t)
	write(t)
	_place(t)
	rebuild()
	return id_of_team(t)


## [param t] in the list its flag puts it in ([member teams] on, [member
## disabled] off), in place of the team of its file, by file name.
static func _place(t: MwCustomTeam) -> void:
	var to: Array[MwCustomTeam] = teams if t.enabled else disabled
	var other: Array[MwCustomTeam] = disabled if t.enabled else teams
	for i in range(other.size() - 1, -1, -1):
		if other[i] == t or other[i].id == t.id:
			other.remove_at(i)
	if not t in to:
		for i in to.size():
			if to[i].id == t.id:
				to.remove_at(i)
				break
		to.append(t)
		to.sort_custom(_by_file)


static func _by_file(first: MwCustomTeam, second: MwCustomTeam) -> bool:
	return first.id < second.id


## Every team of the bank, on and off, by file name (CREATE-A-TEAM's list).
static func all() -> Array[MwCustomTeam]:
	var out: Array[MwCustomTeam] = []
	out.append_array(teams)
	if disabled.is_empty():
		return out                             # (the game's order: nothing to merge)
	out.append_array(disabled)
	out.sort_custom(_by_file)
	return out


## Switch saved team [param t] on or off (CREATE-A-TEAM's list): its file
## keeps the flag; off it leaves the game until switched on again (the
## teams after it move down an id, as when one is deleted).
static func set_enabled(t: MwCustomTeam, on: bool) -> void:
	if teams_in_use():
		push_warning("CREATE-A-TEAM: a game's teams are in use - nothing switched")
		return
	if t.enabled == on:
		return
	var of: MwCustomTeam = teams[_editing_slot] if editing != null and _editing_slot >= 0 \
			and _editing_slot < teams.size() else null
	t.enabled = on
	write(t)
	_place(t)
	if editing != null:
		_editing_slot = teams.find(of) if of != null else -1
	rebuild()


## Edit [param t] (a working copy; [param of]: the saved team it is a copy
## of, null for a new one): the game's readers see it under
## [method editing_id] from now on.
static func edit(t: MwCustomTeam, of: MwCustomTeam = null) -> void:
	editing = t
	_editing_slot = teams.find(of) if of != null else -1
	rebuild()


## The working copy changed: validated and shown again.
static func edited() -> void:
	if editing != null:
		editing.validate(MwRom.archive().bytes())
		rebuild()


## Editing over (saved or not).
static func stop_editing() -> void:
	editing = null
	_editing_slot = -1
	rebuild()


## The game id the working copy is read under (-1: none).
static func editing_id() -> int:
	if editing == null:
		return -1
	return MwTeams.COUNT + (_editing_slot if _editing_slot >= 0 else teams.size())


## Remove [param t] and its file.
static func delete(t: MwCustomTeam) -> void:
	if teams_in_use():
		push_warning("CREATE-A-TEAM: a game's teams are in use - nothing deleted")
		return
	if t.id != "":
		DirAccess.remove_absolute(dir.path_join(t.id + ".json"))
	teams.erase(t)
	disabled.erase(t)
	rebuild()


## Forget every team (the files stay): the game reads the ROM alone again.
static func clear() -> void:
	teams.clear()
	disabled.clear()
	editing = null
	_editing_slot = -1
	_own = {}
	rebuild()


## A file name for a new team: its city and name, lower case, numbered when taken.
static func _new_id(t: MwCustomTeam) -> String:
	var base := ""
	for c in (t.city + "_" + t.name).to_lower():
		base += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while base.contains("__"):
		base = base.replace("__", "_")
	base = base.strip_edges().trim_prefix("_").trim_suffix("_")
	if base == "":
		base = "team"
	var id := base
	var n := 2
	while FileAccess.file_exists(dir.path_join(id + ".json")) or _taken(id):
		id = "%s_%d" % [base, n]
		n += 1
	return id


static func _taken(id: String) -> bool:
	for t in teams + disabled:
		if t.id == id:
			return true
	return false


## The view as it is now (plan 34's saved replays keep it with a match of
## a custom team: their records are addresses in it): {overlay, records};
## {} with no custom team.
static func snapshot() -> Dictionary:
	if _records.is_empty():
		return {}
	var rom := MwRom.data()
	return {"overlay": rom.slice(MwCustomOverlay.BASE), "records": _records.duplicate()}


## Shows a [method snapshot] instead of the bank's view (a saved replay
## playing) until [method rebuild]: the teams as they were in the match.
## Plan 45 (M3): false, and nothing shown, when [param d] isn't a view that
## holds its teams ([method view_holds]: a saved replay is a shared file).
static func show_snapshot(d: Dictionary) -> bool:
	var o: Variant = d.get("overlay")
	var r: Variant = d.get("records")
	if not o is PackedByteArray or not r is PackedInt32Array or not view_holds(o, r):
		return false
	_records = r
	MwRom.set_overlay(o)
	version += 1
	return true


## Plan 45 (M3): whether [param overlay] (a view's bytes, from
## [constant MwCustomOverlay.BASE] on) holds the team records at
## [param records]: each record word-aligned and whole inside it ([MwTeams]'
## `$9E` bytes; a view from before plan 38's name colours ends a record at
## `+$A2`), and its strings, coach, stadium, logo, panel colours and roster
## pointing below the view's end (the ROM's own addresses or the view's).
## The menus, the sims and the sound follow those pointers; an address past
## the view would be a script error on every pass.
static func view_holds(overlay: PackedByteArray, records: PackedInt32Array) -> bool:
	if overlay.is_empty() or overlay.size() > VIEW_MAX or records.is_empty() or records.size() > VIEW_RECORDS:
		return false
	var end := MwCustomOverlay.BASE + overlay.size()
	for r in records:
		var at := r - MwCustomOverlay.BASE
		if at < 0 or at & 1 or r + MwTeams.SIZE > end:
			return false
		for field: int in [MwTeams.CITY, MwTeams.NAME, MwTeams.COACH, MwTeams.STADIUM, MwTeams.LOGO, MwTeams.PANEL,
				MwTeams.BIO, MwTeams.QUOTE]:
			if MwGfx.u32(overlay, at + field) >= end:
				return false
		for slot in 24:                          # the roster: 4 lines x 6 player pointers
			if MwGfx.u32(overlay, at + MwTeams.ROSTER + 4 * slot) >= end:
				return false
	return true


## Build the view of the bank and hand it to [MwRom].
static func rebuild() -> void:
	var rom := MwRom.archive().bytes()
	var shown: Array[MwCustomTeam] = teams.duplicate()
	if editing != null:
		if _editing_slot >= 0 and _editing_slot < shown.size():
			shown[_editing_slot] = editing
		else:
			_editing_slot = -1
			shown.append(editing)
	if shown.is_empty() or rom.size() != MwCustomOverlay.BASE:
		_records = PackedInt32Array()
		MwRom.set_overlay(PackedByteArray())
	else:
		var v := MwCustomOverlay.build(rom, shown)
		_records = v["records"]
		MwRom.set_overlay(v["bytes"])
	version += 1


# --- a game's teams (plan 38 with plan 35) --------------------------------------------------

## The most custom teams a game carries (a start record, a snapshot): team
## ids are bytes (the setup's, `$FFB0DE`), and 23 + 200 stays clear of 255
## (MwMatchSetup.RANDOM).
const CARRY_MAX := 200
## An online match carries the host's first teams, at most this many (each
## about 1-2 KB deflated in START's record: docs/net.md).
const CARRY_ONLINE := 64
## Reading carried teams (untrusted: another machine's): each team's JSON
## must be plain data within MwPlain's bounds (MwPlain.plain_ok: plan 40, S6).


## The custom teams a start record carries (MwSession.to_record): {} with
## none; else {"teams": the custom teams in use, in id order (23, 24 ...),
## each as its JSON ([method MwCustomTeam.to_dict], without its stats, which
## the game never reads), "playoff": the custom team playing [param
## playoffs]' run in its place's stead (MwPlayoffs.custom, -1 none)}. The
## bank is part of what the game's course depends on - any of its teams can
## be picked on the game setup - so a game started from the record (an
## online match on every machine, a replay of a recording) reads the same
## teams on a machine whose bank differs ([method use_teams]). [param
## limit] (>= 0): the first that many teams only (an online match:
## [constant CARRY_ONLINE]).
static func record_teams(playoffs: MwPlayoffs, limit := -1) -> Dictionary:
	if teams.is_empty() or limit == 0:
		return {}
	var out := []
	for t in teams:
		if out.size() >= mini(CARRY_MAX, limit if limit > 0 else CARRY_MAX):
			break
		var d := t.to_dict()
		d["stats"] = null
		out.append(d)
	return {"teams": out, "playoff": playoffs.custom if playoffs != null else -1}


## [param carried] (a start record's or a snapshot's "custom_teams":
## [method record_teams]' form, from another machine) as teams, or null when
## it isn't that: not a dictionary, more than [constant CARRY_MAX] teams, a
## team that isn't plain data within the bounds (MwPlain.plain_ok). Every
## team that is goes through [method MwCustomTeam.from_dict] and its
## validation (a team in memory is always a valid one); nothing in it is
## executed or written. {} is no teams (an empty list); so is any team list
## without the ROM (no game to read them).
static func parse_carried(carried: Variant) -> Variant:
	var out: Array[MwCustomTeam] = []
	if not carried is Dictionary:
		return null
	var c: Dictionary = carried
	if c.is_empty():
		return out
	var list: Variant = c.get("teams")
	var playoff: Variant = c.get("playoff", -1)
	if not list is Array or (list as Array).size() > CARRY_MAX or not (playoff is int or playoff is float):
		return null
	for d: Variant in list:
		if not d is Dictionary or not MwPlain.plain_ok(d):
			return null
	var rom := MwRom.archive().bytes()
	if rom.size() != MwCustomOverlay.BASE:
		return out
	for d: Dictionary in list:
		var t := MwCustomTeam.from_dict(rom, d)
		t.stats = null
		out.append(t)
	return out


## A game's custom teams in use instead of this machine's bank and its
## editor's working copy, which are put aside ([method own_teams] brings
## them back): [param carried] as [method record_teams] gives it ({}: none -
## the game reads the ROM alone). Every machine of an online match plays the
## host's (MwNetMatch: from START's record, or from a resync snapshot); a
## replay of a start record plays the record's. They have ids of their own
## ("game_0" ...) and are never written to this machine's files ([method
## write], [method save] and [method delete] do nothing meanwhile). False
## (and nothing changed) when [param carried] isn't teams ([method
## parse_carried]).
static func use_teams(carried: Variant) -> bool:
	var list: Variant = parse_carried(carried)
	if list == null:
		return false
	if _own.is_empty():
		_own = {"teams": teams.duplicate(), "editing": editing, "slot": _editing_slot}
	teams.clear()
	editing = null
	_editing_slot = -1
	for t: MwCustomTeam in list:
		t.id = "game_%d" % teams.size()
		teams.append(t)
	rebuild()
	return true


## Whether a game's teams are in use ([method use_teams]).
static func teams_in_use() -> bool:
	return not _own.is_empty()


## This machine's own bank and working copy back after [method use_teams]
## (nothing when none was put aside: safe to call at any end).
static func own_teams() -> void:
	if _own.is_empty():
		return
	teams.assign(_own["teams"])
	editing = _own["editing"]
	_editing_slot = int(_own["slot"])
	_own = {}
	rebuild()


## The bank's whole state (tests: one process playing several machines
## swaps each machine's in around its frames, test/net/net_machines.gd).
static func save_state() -> Dictionary:
	return {"teams": teams.duplicate(), "disabled": disabled.duplicate(), "editing": editing, "slot": _editing_slot,
			"records": _records, "own": _own, "overlay": MwRom.overlay()}


## ... and back ([method save_state]'s); caches made from another view are
## stale ([member version] moves on when the view differs).
static func load_state(d: Dictionary) -> void:
	teams.assign(d["teams"])
	disabled.assign(d.get("disabled", []))
	editing = d["editing"]
	_editing_slot = int(d["slot"])
	_records = d["records"]
	_own = d["own"]
	if MwRom.overlay() != d["overlay"]:
		MwRom.set_overlay(d["overlay"])
		version += 1


# --- the menus' order and the playoffs ----------------------------------------------------


## [param t]'s file written (the view unchanged). Plan 45 (M2): false, with
## a warning, when it couldn't be written whole (the old file stays); true
## when there was nothing to write.
static func write(t: MwCustomTeam) -> bool:
	if t.id == "" or teams_in_use():
		return true                            # (a game's teams - another machine's - are never written)
	return MwUserFile.write_text(dir.path_join(t.id + ".json"), JSON.stringify(t.to_dict(), "\t", false) + "\n")


## Team ids in the team rows' order: the original's (`$1C1A4`), each custom
## team after its [member MwCustomTeam.menu_after] team (-1: first).
static func menu_order(rom: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	for t in teams:
		if t.menu_after < 0:
			out.append(id_of_team(t))
	for i in MwTeams.COUNT:
		var team_id := rom[MwTeams.MENU_ORDER + i]
		out.append(team_id)
		for t in teams:
			if t.menu_after == team_id:
				out.append(id_of_team(t))
	return out


## The conference place (0-19) an original team plays the playoffs in:
## itself, 20 -> 9 and 21-22 -> 0 (`$12F34`).
static func conference_place(team_: int) -> int:
	if team_ < 20:
		return team_
	return 9 if team_ == 20 else 0


# --- the ROM's choices ----------------------------------------------------------------------


## The 7 coach faces: the portrait data of the coach table (`$1CD26`) in
## order of first use.
static func coach_faces(rom: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in 20:
		var d := MwGfx.u32(rom, MwPortrait.COACHES + 10 * i + 4)
		if not d in out:
			out.append(d)
	return out


## The 11 player faces as [portrait data, quote set]: the 6 stars'
## (`$1CC2C`), the 4 species' (`$1CC68`: skeleton, robot, troll, goalie) and
## the referee's (`$1CC20`, no quote set of its own: -1, his species').
static func player_faces(rom: PackedByteArray) -> Array:
	var out := []
	for i in 6:
		var e := MwPortrait.STARS + 10 * i
		out.append([MwGfx.u32(rom, e + 4), MwGfx.u16(rom, e + 8)])
	for species in range(1, 5):
		var e := MwPortrait.BY_SPECIES + 6 * species
		out.append([MwGfx.u32(rom, e), MwGfx.u16(rom, e + 4)])
	out.append([MwPortrait.DEFAULT, -1])
	return out


## The face index of an original player (his star face; -1 his species').
static func face_of_record(rom: PackedByteArray, record: int) -> int:
	var e := MwPortrait.star_entry(rom, record)
	if e == 0:
		return -1
	return (e - MwPortrait.STARS) / 10


## The coach table entry (record.l, portrait data.l, quote set.w) of coach
## record [param coach]: a custom coach's own, else `$1CD26`'s (20), else 0.
static func coach_entry(rom: PackedByteArray, coach: int) -> int:
	if MwCustomOverlay.is_custom(coach):
		return coach + MwCustomOverlay.COACH_ENTRY
	for i in 20:
		var e := MwPortrait.COACHES + 10 * i
		if MwGfx.u32(rom, e) == coach:
			return e
	return 0


## True when team [param id]'s coach has colours of his own (a custom coach's).
static func has_coach_colours(rom: PackedByteArray, id: int) -> bool:
	return id >= MwTeams.COUNT and not MwCustomOverlay.coach_colours(rom, MwTeams.coach(rom, id)).is_empty()


## [param steps] (a palette recipe, its "coach_line" steps dropped) with the
## lines the coaches of [param team_a] / [param team_b] are drawn on when
## they have colours of their own: line [param from][0] / [1] copied to
## [constant MwRinkDraw.COACH_LINE] / + 1 with their colours (RomPalette
## "coach_line"; plan 34's port lines). Nothing added for the original's.
static func coach_lines(rom: PackedByteArray, steps: PackedStringArray, team_a: int, team_b: int,
		from: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for text in steps:
		if not text.begins_with("coach_line"):
			out.append(text)
	for k in 2:
		if has_coach_colours(rom, [team_a, team_b][k]):
			out.append("coach_line %s %d %d" % ["ab"[k], int(from[k]), MwRinkDraw.COACH_LINE + k])
	return out


## [param base] (a palette with the teams set) plus team [param id]'s
## coach's own colours on [param line] - [param which] "a" / "b" names his
## team in [param base]; null when the coach has none (every original coach).
static func coach_palette(rom: PackedByteArray, base: RomPalette, id: int, which: String, line: int) -> RomPalette:
	if base == null or id < 0 or MwCustomOverlay.coach_colours(rom, MwTeams.coach(rom, id)).is_empty():
		return null
	return RomPalette.derived(base, PackedStringArray(["coach_colours %s %d" % [which, line]]))


## The 7 ice palettes offered as presets (addresses of 16 colours).
static func ice_presets(rom: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in 6:
		var a := MwGfx.u32(rom, MwPalettes.ICE_PALETTES + 4 * i)
		if not a in out:
			out.append(a)
	for a: int in UNUSED_ICE:
		out.append(a)
	return out


## The 16 colour words of ice preset [param i] ([method ice_presets]; clamped to them), read
## from [param rom].
static func ice_preset(rom: PackedByteArray, i: int) -> PackedInt32Array:
	return MwGfx.words(rom, ice_presets(rom)[clampi(i, 0, PRESETS - 1)], 16)
