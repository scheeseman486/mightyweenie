@tool
class_name MwRom
extends RefCounted
## Access to the ROM and the asset catalogue, for game code and editor tools.
##
## Everything here is static so `@tool` scripts in the editor can use it
## without autoloads. The ROM is the project copy `res://rom/mlh.gen`
## (gitignored; `tools/bin/setup-rom` puts it there). Exported builds carry
## no ROM (addons/mw_rom): they look for the player's file (see
## [method rom_candidates]). The catalogue (`res://data/rom_catalogue.json`,
## built by `mw_harness assets`) holds addresses and parameters only.

const ROM_PATH := "res://rom/mlh.gen"
const CATALOGUE_PATH := "res://data/rom_catalogue.json"
## File extensions an exported build tries as the player's ROM (raw dumps).
const ROM_EXTENSIONS := ["gen", "md", "bin"]

static var _archive: RomArchive
static var _catalogue: Dictionary
## Port only (plan 38): bytes every reader of [method data] sees past the
## ROM's end - the custom teams' records ([MwCustomOverlay]); empty: the ROM
## alone. The ROM's own bytes are never changed.
static var _overlay := PackedByteArray()
static var _with_overlay := PackedByteArray()
static var _with_for: RomArchive


## The ROM resource in use: the project copy (imported if the editor plugin
## imported it, otherwise described straight from the file), else the first
## of [method rom_candidates] that is the expected ROM (looked for once, until
## [method use]). Plan 45 (L5): an imported copy's bytes are read and hashed
## here, so its SHA-1 is that of the bytes in use (an import older than the
## file is not taken for the ROM).
static func archive() -> RomArchive:
	if _archive == null:
		if ResourceLoader.exists(ROM_PATH, "Resource"):
			_archive = load(ROM_PATH) as RomArchive
			if _archive != null:
				_archive.bytes()
		if _archive == null:
			_archive = RomArchive.describe(ProjectSettings.globalize_path(ROM_PATH))
		if not _archive.is_mlh():
			var found := find_rom()
			if found != null:
				_archive = found
	return _archive


## The folder the player keeps the game in: the executable's, or - run from
## an AppImage (owner's request, 2026-10-15) -
## the AppImage file's (its runtime's APPIMAGE variable): the executable then
## runs from a read-only mount that goes when the game ends.
static func game_dir() -> String:
	var appimage := OS.get_environment("APPIMAGE")
	if appimage != "":
		return appimage.get_base_dir()
	return OS.get_executable_path().get_base_dir()


## Where to look for the player's ROM when the project has none (exported
## builds): a `--rom=PATH` argument after `--`, then the `.gen` / `.md` /
## `.bin` files in the game's folder ([method game_dir]) and in the user
## data folder (where the Rom autoload copies the file the player chooses
## when none of these is it: rom_service.gd).
static func rom_candidates() -> PackedStringArray:
	var out := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			out.append(a.trim_prefix("--rom="))
	for dir in [game_dir(), OS.get_user_data_dir()]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.get_extension().to_lower() in ROM_EXTENSIONS:
				out.append(dir.path_join(f))
	return out


## The first of [method rom_candidates] with the expected size and SHA-1, or null.
static func find_rom() -> RomArchive:
	for path in rom_candidates():
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null or f.get_length() != RomArchive.MLH_SIZE:
			continue
		f.close()
		var candidate := RomArchive.describe(path)
		if candidate.is_mlh():
			return candidate
	return null


## Use another ROM file (tests, plan 11's picker). Pass null to reset.
static func use(archive_: RomArchive) -> void:
	_archive = archive_


## True when the expected ROM is present (plan 45: its bytes the ROM's size).
static func available() -> bool:
	return archive().is_mlh() and archive().bytes().size() == RomArchive.MLH_SIZE


## The ROM's bytes, with the custom teams' view after them when there are any.
static func data() -> PackedByteArray:
	var b := archive().bytes()
	if _overlay.is_empty() or b.is_empty():
		return b
	if _with_for != _archive or _with_overlay.size() != b.size() + _overlay.size():
		_with_overlay = b + _overlay
		_with_for = _archive
	return _with_overlay


## The bytes shown past the ROM's end now ([method set_overlay]).
static func overlay() -> PackedByteArray:
	return _overlay


## Show [param bytes] past the ROM's end ([method data]); empty: none.
static func set_overlay(bytes: PackedByteArray) -> void:
	_overlay = bytes
	_with_overlay = PackedByteArray()
	_with_for = null


## The catalogue as parsed JSON (numbers are floats: use [method num]).
static func catalogue() -> Dictionary:
	if _catalogue.is_empty():
		var text := FileAccess.get_file_as_string(CATALOGUE_PATH)
		if text == "":
			var res := load(CATALOGUE_PATH)
			if res is JSON:
				_catalogue = res.data
		else:
			_catalogue = JSON.parse_string(text)
	return _catalogue


## A catalogue entry ("picture_024cfc", "anim_04ceb2", ...) or {}.
static func entry(key: String) -> Dictionary:
	return catalogue().get("entries", {}).get(key, {})


## Keys of the catalogue entries of one kind, optionally used on [param screen].
static func keys(kind: String, screen := -1) -> PackedStringArray:
	var out := PackedStringArray()
	var entries: Dictionary = catalogue().get("entries", {})
	for k in entries:
		var asset: Dictionary = entries[k]
		if asset["kind"] == kind and (screen < 0 or has_screen(asset, screen)):
			out.append(k)
	out.sort()
	return out


## Catalogue entry [param asset]'s [param field] as an int (the JSON's numbers are floats).
static func num(asset: Dictionary, field: String) -> int:
	return int(asset[field])


## Whether catalogue entry [param asset] lists screen [param screen] among those it is used on.
static func has_screen(asset: Dictionary, screen: int) -> bool:
	for s in asset.get("screens", []):
		if int(s) == screen:
			return true
	return false
