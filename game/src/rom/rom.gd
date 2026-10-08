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


## The ROM resource in use: the project copy (imported if the editor plugin
## imported it, otherwise described straight from the file), else the first
## of [method rom_candidates] that is the expected ROM.
static func archive() -> RomArchive:
	if _archive == null:
		if ResourceLoader.exists(ROM_PATH, "Resource"):
			_archive = load(ROM_PATH) as RomArchive
		if _archive == null:
			_archive = RomArchive.describe(ProjectSettings.globalize_path(ROM_PATH))
		if not _archive.is_mlh():
			var found := find_rom()
			if found != null:
				_archive = found
	return _archive


## Where to look for the player's ROM when the project has none (exported
## builds): a `--rom=PATH` argument after `--`, then the `.gen` / `.md` /
## `.bin` files in the executable's folder and in the user data folder.
static func rom_candidates() -> PackedStringArray:
	var out := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			out.append(a.trim_prefix("--rom="))
	for dir in [OS.get_executable_path().get_base_dir(), OS.get_user_data_dir()]:
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
		var a := RomArchive.describe(path)
		if a.is_mlh():
			return a
	return null


## Use another ROM file (tests, plan 11's picker). Pass null to reset.
static func use(archive_: RomArchive) -> void:
	_archive = archive_


## True when the expected ROM is present.
static func available() -> bool:
	return archive().is_mlh() and not archive().bytes().is_empty()


static func data() -> PackedByteArray:
	return archive().bytes()


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
		var e: Dictionary = entries[k]
		if e["kind"] == kind and (screen < 0 or has_screen(e, screen)):
			out.append(k)
	out.sort()
	return out


static func num(e: Dictionary, field: String) -> int:
	return int(e[field])


static func has_screen(e: Dictionary, screen: int) -> bool:
	for s in e.get("screens", []):
		if int(s) == screen:
			return true
	return false
