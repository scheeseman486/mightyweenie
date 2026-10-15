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

## The hashing reads a file of another size in pieces of this many bytes (a
## big file isn't held whole).
const HASH_CHUNK := 1 << 20

@export var source_path: String = ""
@export var size: int = 0
@export var sha1: String = ""

var _bytes := PackedByteArray()   # not exported: never serialised
var _checked := false             # plan 45: sha1 and size are those of the bytes read (once)


## True when the file is the ROM the project was built against.
func is_mlh() -> bool:
	return sha1 == MLH_SHA1


## The ROM's bytes: those [method describe] hashed, or read once from
## [member source_path]. Plan 45 (L5): bytes read here (an imported
## archive, whose SHA-1 is the import's) are hashed once and
## [member size] / [member sha1] become theirs - a file changed since the
## import is not taken for the ROM ([method is_mlh] says so).
func bytes() -> PackedByteArray:
	if _bytes.is_empty() and source_path != "" and FileAccess.file_exists(source_path):
		var data := FileAccess.get_file_as_bytes(source_path)
		if not _checked:
			_checked = true
			var was := sha1
			size = data.size()
			sha1 = _sha1(data)
			if was != "" and sha1 != was:
				push_warning("RomArchive: %s changed since it was imported (SHA-1 %s)" % [source_path, sha1])
		_bytes = data
	return _bytes


## Metadata for the ROM file at [param path]. Plan 45 (L5): a file of the
## ROM's size keeps the bytes it was hashed from (what [method bytes] gives:
## the hash is the bytes' in use; one read fewer); another size is hashed in
## pieces and keeps none.
static func describe(path: String) -> RomArchive:
	var archive := RomArchive.new()
	archive.source_path = path
	var f := FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
	if f == null:
		return archive
	archive.size = f.get_length()
	archive._checked = true
	if archive.size == MLH_SIZE:
		var data := f.get_buffer(archive.size)
		archive.size = data.size()
		archive.sha1 = _sha1(data)
		if archive.is_mlh():
			archive._bytes = data
		return archive
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(HASH_CHUNK))
	archive.sha1 = ctx.finish().hex_encode()
	return archive


## The SHA-1 of [param data] (hex).
static func _sha1(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(data)
	return ctx.finish().hex_encode()
