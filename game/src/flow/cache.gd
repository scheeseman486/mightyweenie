class_name MwCache
extends RefCounted
## What the port builds from the player's ROM at the start, kept between
## runs in the player's data folder ([constant ROOT]) and read back on the
## next run instead of built again (plan 27; owner): the tile sets' atlases,
## the input glyphs' cells, the 3D crowd's figures.
##
## An item has a name and the source files it was built from. Its file's
## key is [constant VERSION], the build - the executable's size and date (an
## exported build packs the game into it; run from an AppImage, the
## AppImage's: its executable's path is a new mount each run) - and, in a run from the project's
## sources, those files' dates: a new build or an edited source builds it
## again (an older file of that name is deleted). Values are what
## [method @GlobalScope.var_to_bytes] stores (no objects), zstd-compressed.
## A missing, stale or unreadable file reads as null: the caller builds and
## writes it. The ROM's data stays on the player's machine; none of this is
## in the repository.
##
## Safe from worker threads for different names; [method prepare] runs on
## the main thread first (the build's identity).

## Bump when what is cached changes shape (a new field, another layout).
const VERSION := 1
const ROOT := "user://cache"

## Off: every read misses and nothing is written. Off by default in
## headless runs (tests and checks build everything afresh).
static var enabled := DisplayServer.get_name() != "headless"
## The folder (tests point it elsewhere).
static var root := ROOT

static var _build_id := ""
static var _lock := Mutex.new()


## The build's identity, worked out once (best on the main thread before
## workers use the cache: it reads the ROM's identity).
static func prepare() -> void:
	_lock.lock()
	if _build_id == "":
		var exe := OS.get_environment("APPIMAGE")
		if exe == "":
			exe = OS.get_executable_path()
		var f := FileAccess.open(exe, FileAccess.READ)
		var size := f.get_length() if f else 0
		_build_id = "%d|%s|%d|%d|%s" % [VERSION, exe, size, FileAccess.get_modified_time(exe),
				MwRom.archive().sha1 if MwRom.available() else ""]
	_lock.unlock()


## The file of item [param name] for its [param sources] (res:// paths).
static func path_of(name: String, sources: PackedStringArray) -> String:
	prepare()
	_lock.lock()
	var id := _build_id
	_lock.unlock()
	if not OS.has_feature("template"):
		for text in sources:
			id += "|%s:%d" % [text, FileAccess.get_modified_time(text)]
	return "%s/%s-%s.bin" % [root, name, id.sha1_text().substr(0, 16)]


## Item [param name]'s value, or null (missing, stale, unreadable, off).
static func read(name: String, sources: PackedStringArray) -> Variant:
	if not enabled:
		return null
	var text := path_of(name, sources)
	if not FileAccess.file_exists(text):
		return null
	var f := FileAccess.open_compressed(text, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var b := f.get_buffer(f.get_length())
	f.close()
	if b.is_empty():
		return null
	return bytes_to_var(b)


## Keeps [param value] as item [param name] (an older file of the name goes;
## plan 45: nothing kept when the file doesn't read back whole).
static func write(name: String, sources: PackedStringArray, value: Variant) -> void:
	if not enabled:
		return
	var text := path_of(name, sources)
	DirAccess.make_dir_recursive_absolute(root)
	var d := DirAccess.open(root)
	if d:
		for old in d.get_files():
			if old.begins_with(name + "-") and old != text.get_file():
				d.remove(old)
	var tmp := text + ".part"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	var bytes := var_to_bytes(value)
	f.store_buffer(bytes)
	f.close()
	# plan 45 (M2): a full disk refuses buffered writes at the close, unreported - kept only when it reads
	# back whole (else it is built again next time, as a missing item)
	var back := FileAccess.open_compressed(tmp, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var whole := back != null and back.get_length() == bytes.size() and back.get_buffer(bytes.size()) == bytes
	if back != null:
		back.close()
	if not whole:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return
	MwUserFile.commit(tmp, text)


## Deletes every cached item.
static func clear() -> void:
	var d := DirAccess.open(root)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
