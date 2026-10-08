@tool
class_name RomArchive
extends Resource
## The user's Mutant League Hockey ROM as a project resource.
##
## Holds metadata only - where the file is, its size and SHA-1. The bytes are
## read from the file when first needed and never saved (docs/architecture.md,
## Assets). The editor import plugin (addons/mw_rom) turns `res://rom/mlh.gen`
## into one of these; [MwRom] is the access point for game and tool code.

## The No-Intro "Mutant League Hockey (USA, Europe)" dump - the only known one.
const MLH_SHA1 := "84e203c5226bc1913a485804e59c6418e939bd3d"
const MLH_SIZE := 2 * 1024 * 1024

@export var source_path: String = ""
@export var size: int = 0
@export var sha1: String = ""

var _bytes := PackedByteArray()   # not exported: never serialised


## True when the file is the ROM the project was built against.
func is_mlh() -> bool:
	return sha1 == MLH_SHA1


## The ROM's bytes (read once from [member source_path]).
func bytes() -> PackedByteArray:
	if _bytes.is_empty() and source_path != "" and FileAccess.file_exists(source_path):
		_bytes = FileAccess.get_file_as_bytes(source_path)
	return _bytes


## Metadata for the ROM file at [param path] (no bytes kept).
static func describe(path: String) -> RomArchive:
	var a := RomArchive.new()
	a.source_path = path
	if not FileAccess.file_exists(path):
		return a
	var data := FileAccess.get_file_as_bytes(path)
	a.size = data.size()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(data)
	a.sha1 = ctx.finish().hex_encode()
	return a
