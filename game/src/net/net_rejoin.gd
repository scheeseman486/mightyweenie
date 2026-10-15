class_name MwNetRejoin
extends RefCounted
## A client's rejoin key on disk (plan 35 section 5): the host gives every
## machine 32 random bytes when it joins; the client keeps them in memory
## and here ([member path]: the address, port, match ID and key) until the
## match ends, so a crash or a restart can rejoin (JOIN GAME to the same
## address offers REJOIN). The key is a secret: never logged, the file
## readable by its owner only where the system allows, erased when the
## lobby closes, the match ends, the player exits or the machine is kicked.

## Where the key lives (tests point it elsewhere).
static var path := "user://net/rejoin.cfg"


## Keeps the rejoin key [param key] of match [param match_id] on the host at
## [param address] port [param port] in [member path], readable by its owner
## only where the system allows. Plan 45 (L3): at no moment readable by
## anyone else - its folder made its owner's alone first, and the file's
## permissions set on the fresh ".part" before the key is written into it
## (they used to be set after the file was in place). False, with a warning,
## when it couldn't be written.
static func save(address: String, port: int, match_id: int, key: PackedByteArray) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("rejoin", "address", address)
	cfg.set_value("rejoin", "port", port)
	cfg.set_value("rejoin", "match", match_id)
	cfg.set_value("rejoin", "key", key.hex_encode())
	MwUserFile.private_folder(path.get_base_dir())
	return MwUserFile.write_config(cfg, path, MwUserFile.PRIVATE)


## {address, port, match, key} or {} (none, or not a well-formed file).
static func read() -> Dictionary:
	var cfg := MwUserFile.read_config(path)      # plan 45: plain settings only
	if cfg == null:
		return {}
	var address: Variant = cfg.get_value("rejoin", "address", null)
	var port: Variant = cfg.get_value("rejoin", "port", null)
	var match_id: Variant = cfg.get_value("rejoin", "match", null)
	var hex: Variant = cfg.get_value("rejoin", "key", null)
	if not (address is String and port is int and match_id is int and hex is String):
		return {}
	if (hex as String).length() != 2 * MwNetProtocol.KEY_BYTES or not (hex as String).is_valid_hex_number() \
			or (hex as String)[0] in "+-":
		return {}
	var key: PackedByteArray = (hex as String).hex_decode()
	return {"address": address, "port": port, "match": match_id, "key": key}


## The key kept for this host (empty when none or another host's).
static func key_for(address: String, port: int) -> PackedByteArray:
	var d := read()
	if d.is_empty() or str(d["address"]).to_lower() != address.strip_edges().to_lower() or int(d["port"]) != port:
		return PackedByteArray()
	return d["key"]


## Erases the key's file (none: nothing to do).
static func clear() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
