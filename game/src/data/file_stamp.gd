class_name MwFileStamp
extends RefCounted
## Plan 40 (S6): what a player's file says of the game that wrote it and
## when - the ROM it was played on and the time - read and written alike by
## the playoff saves and the replays (MwPlayoffSave, MwReplayFile; the
## online handshake's own: MwNetHost.build_id, rom_sha1).


## The ROM's SHA-1 ("" without one).
static func rom_sha1() -> String:
	return RomArchive.MLH_SHA1 if MwRom.available() else ""


## Whether a file stamped [param sha] was played on this ROM (always without one).
static func rom_matches(sha: String) -> bool:
	return not MwRom.available() or sha == RomArchive.MLH_SHA1


## The time (unix seconds).
static func now() -> int:
	return int(Time.get_unix_time_from_system())
