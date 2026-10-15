class_name MwPlayoffSave
extends RefCounted
## The port's playoff saves (plan 34, owner: SAVE GAME, LOAD GAME): eight
## slots and an autosave written after every game of a run, in the player's
## data folder ([member dir]). A save holds the run as it stood when the
## bracket opened after its last game ([member MwSession.run_checkpoint]):
## the game setup's 10 bytes and the run's 21 (MwPlayoffs.to_bytes) - more
## than a password carries - so a loaded run opens the same bracket and goes
## on exactly as it would have; also the password the original showed then,
## the date, and the ROM's SHA-1 (another ROM's save is refused). Nothing in
## a save is the ROM's: indices and state bytes only.
##
## Plan 38: a custom team's run (it plays in its playoff place's stead,
## [member MwPlayoffs.custom]) also keeps the team's file name - its game
## id depends on the bank - and loads only while that team is there.

const VERSION := 1
const SLOTS := 8
## A save's custom team when it can't be played ([method info]'s "why"):
## deleted, or switched off in CREATE-A-TEAM (owner, 2026-10-15).
const TEAM_GONE := -2
const TEAM_OFF := -3
## The autosave's slot number (listed first).
const AUTOSAVE := 0

## Where the saves live (tests point it elsewhere).
static var dir := "user://saves/playoffs"


## The file of slot [param slot] in [member dir] (the autosave's is [code]autosave.cfg[/code]).
static func path(slot: int) -> String:
	return dir.path_join("autosave.cfg" if slot == AUTOSAVE else "slot_%d.cfg" % slot)


## Slot numbers in the list's order: the autosave, then 1-8.
static func slots() -> Array[int]:
	var out: Array[int] = [AUTOSAVE]
	for i in range(1, SLOTS + 1):
		out.append(i)
	return out


## Whether slot [param slot] has a file.
static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))


## Writes [param session]'s run (its checkpoint) to [param slot]; false when
## there is no checkpoint yet or the file can't be written.
static func save(session: MwSession, slot: int) -> bool:
	if session.run_checkpoint.size() != 31:
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("save", "version", VERSION)
	cfg.set_value("save", "rom_sha1", MwFileStamp.rom_sha1())
	cfg.set_value("save", "time", MwFileStamp.now())
	cfg.set_value("save", "setup", session.run_checkpoint.slice(0, 10).hex_encode())
	cfg.set_value("save", "run", session.run_checkpoint.slice(10).hex_encode())
	cfg.set_value("save", "password", session.run_password)
	cfg.set_value("save", "humans", session.humans_record() if session.has_method("humans_record") else {})
	var custom := MwCustomTeams.team(session.playoffs.custom)
	if custom != null:
		cfg.set_value("save", "custom_team", custom.id)
	return MwUserFile.write_config(cfg, path(slot))


## Plan 38: the game id of the custom team [param cfg] names (-1: none;
## [constant TEAM_GONE]: no longer in the bank; [constant TEAM_OFF]: in it,
## switched off).
static func _custom(cfg: ConfigFile) -> int:
	var file := MwPlain.text(cfg.get_value("save", "custom_team", ""))
	if file == "":
		return -1
	for team in MwCustomTeams.teams:
		if team.id == file:
			return MwCustomTeams.id_of_team(team)
	for team in MwCustomTeams.disabled:
		if team.id == file:
			return TEAM_OFF
	return TEAM_GONE


## What the list shows of [param slot]: {} when empty or unreadable; else
## {time, team_a, team_b, round, best_of_3, series, password, ok, why} (ok:
## this ROM's, this version's, its custom team there and on; why: what
## stops a custom team's - "TEAM IS OFF", "TEAM DELETED" -, else ""). Plan 45 (L1): also {} when the run or the setup
## holds a value the original's password and menus never make ([method valid]).
static func info(slot: int) -> Dictionary:
	var cfg := _read(slot)
	if cfg == null:
		return {}
	var setup := _hex_bytes(cfg.get_value("save", "setup", ""), 10)
	var run := _hex_bytes(cfg.get_value("save", "run", ""), 21)
	if setup.size() != 10 or run.size() != 21:
		return {}
	var custom := _custom(cfg)
	if not valid(setup, run, MwPlain.text(cfg.get_value("save", "custom_team", "")) != ""):
		push_warning("MwPlayoffSave: %s holds a run the game can't make - ignored" % path(slot))
		return {}
	var playoffs := MwPlayoffs.new()
	playoffs.from_bytes(run)
	var sha := MwPlain.text(cfg.get_value("save", "rom_sha1", ""))
	return {"time": MwPlain.num(cfg.get_value("save", "time", 0)), "team_a": custom if custom >= 0 else setup[0],
			"team_b": setup[1],
			"round": playoffs.round, "best_of_3": playoffs.best_of_3, "series": playoffs.series,
			"password": MwPlain.text(cfg.get_value("save", "password", "")).substr(0, MwPlayoffs.PASSWORD_LEN),
			"ok": MwPlain.num(cfg.get_value("save", "version", 0)) == VERSION
					and MwFileStamp.rom_matches(sha) and custom >= -1,
			"why": "TEAM IS OFF" if custom == TEAM_OFF else "TEAM DELETED" if custom == TEAM_GONE else ""}


## Plan 45 (L1): whether a save's [param setup] (10 bytes) and [param run] (21:
## MwPlayoffs.to_bytes) are a run the game can make - each run field within
## the width the original's password gives it (`$1266C`: a 12-bit seed, a
## pair of two different places 0-9, the conference, best of 3 and `+$11` 0-1,
## the series and the round 0-3, 18 dead players a team) and its flags the
## five it sets; the setup bytes within the game setup's rows (docs/re/
## screens.md: pads 0-4, play modes 0-4, period 0-2, penalties and reserves
## 0-1, the Death Index 0-4; the period's minutes byte is the clock's, any
## value playable), the teams a run's (conference places 0-19) and its
## stadium one of the original's ([param custom]: the save names a custom
## team, whose id at the save - team A's and its rink's - may be any team
## id). A save past these would put the bracket and the screens in states
## the original never reaches.
static func valid(setup: PackedByteArray, run: PackedByteArray, custom: bool) -> bool:
	if setup.size() != 10 or run.size() != 21:
		return false
	var playoffs := MwPlayoffs.new()
	playoffs.from_bytes(run)
	@warning_ignore("integer_division")
	var a := playoffs.pair / 10
	var widths := playoffs.seed <= 0xFFF and playoffs.pair < 100 and a != playoffs.pair % 10 \
			and playoffs.conference <= 1 and playoffs.best_of_3 <= 1 and playoffs.flag_11 <= 1 \
			and playoffs.series <= 3 and playoffs.round <= 3 \
			and playoffs.dead[0] >= 0 and playoffs.dead[0] < 1 << 18 \
			and playoffs.dead[1] >= 0 and playoffs.dead[1] < 1 << 18 \
			and playoffs.flags & ~(MwPlayoffs.NEW | MwPlayoffs.SHOW_PASSWORD | MwPlayoffs.CHAMPION
					| MwPlayoffs.ELIMINATED | MwPlayoffs.RANDOM_DEAD) == 0
	var su := MwMatchSetup.from_bytes(setup)
	var rows := su.team_a < (MwMatchSetup.RANDOM if custom else 20) and su.team_b < 20 \
			and su.stadium < (MwMatchSetup.RANDOM if custom else MwTeams.COUNT) \
			and su.pads <= 4 and su.play_mode <= 4 and su.period_index <= 2 and su.penalties <= 1 \
			and su.reserves <= 1 and su.death_index <= 4
	return widths and rows


## [param v] (a save's hex text) as [param count] bytes; empty when it isn't that.
static func _hex_bytes(v: Variant, count: int) -> PackedByteArray:
	var text := MwPlain.text(v)
	if text.length() != 2 * count or not text.is_valid_hex_number() or text[0] in "+-":
		return PackedByteArray()
	return text.hex_decode()


## Loads [param slot] into [param session]: the setup and the run as they
## were, the port's playoffs in progress with no game played since; false
## when the slot is empty, another ROM's or another version's.
static func load_into(session: MwSession, slot: int) -> bool:
	var i := info(slot)
	if i.is_empty() or not i["ok"]:
		return false
	var cfg := _read(slot)
	if cfg == null:
		return false
	var setup := MwMatchSetup.from_bytes(_hex_bytes(cfg.get_value("save", "setup", ""), 10))
	var run := _hex_bytes(cfg.get_value("save", "run", ""), 21)
	var custom := _custom(cfg)
	if custom >= 0:
		setup.team_a = custom                 # plan 38: the custom team, under its id now
		if setup.stadium >= MwTeams.COUNT:
			setup.stadium = custom            # its rink (no other custom team plays a run)
	session.setup = setup
	session.playoffs.from_bytes(run)
	session.playoffs.custom = custom if custom >= 0 else -1
	session.local_mode = "playoffs"
	session.load_run(setup.to_bytes() + run, i["password"])
	if session.has_method("load_humans"):
		session.load_humans(cfg.get_value("save", "humans", {}))
	return true


## Deletes slot [param slot]'s file, if it has one.
static func delete(slot: int) -> void:
	if exists(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(slot)))


## Slot [param slot]'s file (null: none, or not plain settings - plan 45, MwUserFile.read_config).
static func _read(slot: int) -> ConfigFile:
	return MwUserFile.read_config(path(slot))
