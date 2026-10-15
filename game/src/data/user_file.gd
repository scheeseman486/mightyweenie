class_name MwUserFile
extends RefCounted
## Plan 40 (S6): the player's files written whole or not at all - to a
## ".part" beside the file, then moved over it, so a crash, a full disk or
## a power cut midway leaves the old file (the survey found two of six kinds
## doing it). The settings, the playoff saves, the custom teams, the online
## rejoin key, known hosts and the saved replays write through
## [method write_atomic] / [method write_config]; the asset cache writes its
## own ".part" and [method commit]s it.
##
## Plan 45: a write is committed only once the ".part" reads back as what
## was meant (a full disk fails at the file's close, unreported); a ".part"
## a crash left is taken up or cleared by the next read ([method recover]);
## and every player's [code].cfg[/code] is read through
## [method read_config] (the engine's text parser builds objects and nests
## without a limit).

## The most a player's [code].cfg[/code] file may hold (bytes; a bigger one is refused).
const CONFIG_MAX := 1 << 20
## The deepest a [code].cfg[/code] value may nest (brackets, braces, parentheses): the engine's
## parser recurses without a limit (about 20 000 levels overflow its stack).
const CONFIG_DEPTH := 16
## The constructors a [code].cfg[/code] value may call: plain values only. ConfigFile also builds
## [code]Object(...)[/code], loads [code]Resource("...")[/code] / [code]ExtResource(...)[/code] by
## path (running a script's [code]_init[/code]) and loads a typed container's class.
const CONFIG_CONSTRUCTORS := ["Vector2", "Vector2i", "Rect2", "Rect2i", "Vector3", "Vector3i", "Vector4",
		"Vector4i", "Transform2D", "Plane", "Quaternion", "AABB", "Basis", "Transform3D", "Projection", "Color",
		"NodePath", "PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array",
		"PackedFloat64Array", "PackedStringArray", "PackedVector2Array", "PackedVector3Array", "PackedColorArray",
		"PackedVector4Array"]
## The element types a typed container ([code]Array[...][/code], [code]Dictionary[...][/code]) in a
## [code].cfg[/code] value may name: the built-in value types.
const CONFIG_TYPES := ["bool", "int", "float", "String", "StringName", "NodePath", "Vector2", "Vector2i", "Rect2",
		"Rect2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Transform2D", "Plane", "Quaternion", "AABB", "Basis",
		"Transform3D", "Projection", "Color", "Array", "Dictionary", "PackedByteArray", "PackedInt32Array",
		"PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray", "PackedVector2Array",
		"PackedVector3Array", "PackedColorArray", "PackedVector4Array"]
## A private file's permissions (the owner's alone: read and write).
const PRIVATE := FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
## A private folder's permissions (the owner's alone: read, write and search).
const PRIVATE_FOLDER := PRIVATE | FileAccess.UNIX_EXECUTE_OWNER

const _QUOTE := 0x22
const _BACKSLASH := 0x5C
const _SEMICOLON := 0x3B
const _NEWLINE := 0x0A


# --- writing ----------------------------------------------------------------------------------

## [param bytes] as the file [param path] (its folder made): false, with a
## warning, when it couldn't be written whole (the old file, if any, stays).
## [param perms] (>= 0, e.g. [constant PRIVATE]): the file's Unix permissions,
## set on the fresh ".part" before anything is written into it (plan 45: a
## secret is never in a file others may read).
static func write_atomic(path: String, bytes: PackedByteArray, perms := -1) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var tmp := path + ".part"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))     # plan 45: a fresh file, made now
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("MwUserFile: %s could not be written (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	if perms >= 0:
		FileAccess.set_unix_permissions(tmp, perms)
	f.store_buffer(bytes)
	f.close()
	return commit_checked(tmp, path, bytes)


## [param cfg] as the file [param path] ([method write_atomic], [param perms]
## too; the same text ConfigFile.save writes).
static func write_config(cfg: ConfigFile, path: String, perms := -1) -> bool:
	return write_atomic(path, cfg.encode_to_text().to_utf8_buffer(), perms)


## [param text] as the file [param path] (UTF-8; [method write_atomic]).
static func write_text(path: String, text: String) -> bool:
	return write_atomic(path, text.to_utf8_buffer())


## Plan 45: the written [param tmp] moved over [param path] only when it reads
## back as [param bytes] - the engine's writes are buffered, so a full disk or
## a quota refuses them at the file's close, which reports nothing (a 3 000-byte
## write under a 2 KiB limit left 2 048 bytes and no error). Otherwise
## [param tmp] is deleted, the old file stays and the result is false (with a
## warning).
static func commit_checked(tmp: String, path: String, bytes: PackedByteArray) -> bool:
	var ok := FileAccess.get_file_as_bytes(tmp) == bytes
	if not ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		push_warning("MwUserFile: %s could not be written whole (a full disk?) - the old file kept" % path)
		return false
	if not commit(tmp, path):
		push_warning("MwUserFile: %s could not be put in place" % path)
		return false
	return true


## The written [param tmp] moved over [param path] (where a rename doesn't
## replace a file, the old one is removed first: [method recover] takes up a
## ".part" a crash left between the two).
static func commit(tmp: String, path: String) -> bool:
	var from := ProjectSettings.globalize_path(tmp)
	var to := ProjectSettings.globalize_path(path)
	if DirAccess.rename_absolute(from, to) == OK:
		return true
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(to)
	return DirAccess.rename_absolute(from, to) == OK


## Plan 45 (L3): the folder [param dir] made and made its owner's alone (a
## secret's folder: nobody else can open a file in it, not even while one is
## being written). False where the system has no such permissions.
static func private_folder(dir: String) -> bool:
	var at := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(at)
	return FileAccess.set_unix_permissions(at, PRIVATE_FOLDER) == OK


## Plan 45 (L4): a ".part" a write left beside [param path] (a crash midway;
## or where a rename doesn't replace a file, between [method commit]'s remove
## and its rename): taken as the file when [param path] is missing and
## [param whole] (called with the ".part"'s path) says it is a whole file;
## deleted otherwise (the file there is the last whole one). The readers call
## it before they read.
static func recover(path: String, whole: Callable) -> void:
	var tmp := path + ".part"
	if not FileAccess.file_exists(tmp):
		return
	if not FileAccess.file_exists(path) and whole.call(tmp):
		if commit(tmp, path):
			push_warning("MwUserFile: %s taken up from the write a crash left" % path)
		return                                     # (one that can't be put in place waits for the next read)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


# --- reading the player's .cfg files ------------------------------------------------------------

## Plan 45 (M1): the player's [code].cfg[/code] file [param path] as a
## ConfigFile, or null when it is missing, unreadable or not plain settings
## (bigger than [constant CONFIG_MAX], a constructor outside
## [constant CONFIG_CONSTRUCTORS], a typed container of a class, nested deeper
## than [constant CONFIG_DEPTH]: [method plain_config]) - the caller then
## takes its defaults, as for a missing file. Every [code].cfg[/code] the game
## reads comes through here (docs/style.md S2); a ".part" a crash left is
## taken up or cleared first ([method recover]).
static func read_config(path: String) -> ConfigFile:
	recover(path, func(tmp: String) -> bool: return _config_text(tmp, false) != "")
	if not FileAccess.file_exists(path):
		return null
	var text := _config_text(path, true)
	if text == "":
		return null
	var cfg := ConfigFile.new()
	return cfg if cfg.parse(text) == OK else null


## [param path]'s text when it is plain settings ([method plain_config]), else
## "" ([param warn]: with a warning saying why).
static func _config_text(path: String, warn: bool) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	if f.get_length() > CONFIG_MAX:
		if warn:
			push_warning("MwUserFile: %s is bigger than settings are (%d bytes) - ignored" % [path, f.get_length()])
		return ""
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if not plain_config(bytes):
		if warn:
			push_warning("MwUserFile: %s is not plain settings - ignored" % path)
		return ""
	return bytes.get_string_from_utf8()


## Plan 45 (M1): whether [param bytes] (a [code].cfg[/code] file's UTF-8 text)
## holds plain settings only - sections, keys and values the engine's text
## parser reads without building an object, loading a resource or a class,
## or nesting deeper than [constant CONFIG_DEPTH]. It reads the text as the
## parser does (verified on 4.7.1): a [code][section][/code] runs to its
## [code]][/code], a key to its [code]=[/code], a value's strings take
## [code]\\[/code] escapes, [code];[/code] starts a comment, and an identifier
## followed (across spaces, lines and comments) by [code]([/code] is a
## constructor, by [code][[/code] a typed container. What the parser could
## read another way than this does is refused (a quote or [code];[/code] in a
## section or a key; [code]#[/code], [code]'[/code] or [code]=[/code] in a
## value): the engine never writes them.
static func plain_config(bytes: PackedByteArray) -> bool:
	var i := 0
	var n := bytes.size()
	while i < n:
		var c := bytes[i]
		if _space(c) or c == _NEWLINE:
			i += 1
		elif c == _SEMICOLON:
			i = _line_end(bytes, i)
		elif c == 0x5B:                                    # [section]: to its ] on the line
			i += 1
			while i < n and bytes[i] != 0x5D:
				if bytes[i] in [_QUOTE, _SEMICOLON, _NEWLINE]:
					return false
				i += 1
			if i >= n:
				return false
			i += 1
		else:                                              # a key, to its =, then its value
			while i < n and bytes[i] != 0x3D:
				if bytes[i] in [_QUOTE, _SEMICOLON, _NEWLINE, 0x23, 0x5B, 0x5D, 0x7B, 0x7D, 0x28, 0x29]:
					return false
				i += 1
			if i >= n:
				return false
			i = _plain_value(bytes, i + 1)
			if i < 0:
				return false
	return true


## The value from [param from] (just after its key's [code]=[/code]): where
## it ends (its line's end once it has a token and every bracket is closed),
## or -1 when it isn't a plain one.
static func _plain_value(bytes: PackedByteArray, from: int) -> int:
	var n := bytes.size()
	var depth := 0
	var started := false
	var i := from
	while i < n:
		var c := bytes[i]
		if c == _NEWLINE and depth == 0 and started:
			return i
		if _space(c) or c == _NEWLINE:
			i += 1
		elif c == _SEMICOLON:
			i = _line_end(bytes, i)
		elif c == _QUOTE:
			i = _string_end(bytes, i)
			if i < 0:
				return -1
			started = true
		elif c in [0x5B, 0x7B, 0x28]:                      # [ { (
			depth += 1
			if depth > CONFIG_DEPTH:
				return -1
			started = true
			i += 1
		elif c in [0x5D, 0x7D, 0x29]:                      # ] } )
			depth -= 1
			if depth < 0:
				return -1
			i += 1
		elif c in [0x23, 0x27, 0x3D]:                      # # (a colour code) ' =
			return -1
		elif _word_start(c):
			var end := i
			while end < n and (_word_start(bytes[end]) or (bytes[end] >= 0x30 and bytes[end] <= 0x39)):
				end += 1
			if not _plain_word(bytes, bytes.slice(i, end).get_string_from_ascii(), end):
				return -1
			i = end
			started = true
		else:
			started = true
			i += 1
	return i if depth == 0 else -1


## Whether identifier [param word] (in a value, the text going on at [param at])
## is plain: a constructor from [constant CONFIG_CONSTRUCTORS], a typed
## container of [constant CONFIG_TYPES] only, or a word the parser reads as a
## value (true, null, inf ...: anything else it refuses).
static func _plain_word(bytes: PackedByteArray, word: String, at: int) -> bool:
	var i := _next_token(bytes, at)
	if i >= bytes.size():
		return true
	if bytes[i] == 0x28:                                   # (
		return word in CONFIG_CONSTRUCTORS
	if bytes[i] == 0x5B and word in ["Array", "Dictionary"]:
		var end := i + 1
		while end < bytes.size() and bytes[end] != 0x5D:
			end += 1
		if end >= bytes.size():
			return false
		for t in bytes.slice(i + 1, end).get_string_from_ascii().split(",", false):
			if not t.strip_edges() in CONFIG_TYPES:
				return false
	return true


## Where the next token after [param at] starts (spaces, lines and comments skipped, as the parser does).
static func _next_token(bytes: PackedByteArray, at: int) -> int:
	var i := at
	while i < bytes.size():
		if bytes[i] == _SEMICOLON:
			i = _line_end(bytes, i)
		elif _space(bytes[i]) or bytes[i] == _NEWLINE:
			i += 1
		else:
			break
	return i


## Just past the string opening at [param at] ([code]\\[/code] escapes the next character); -1 unclosed.
static func _string_end(bytes: PackedByteArray, at: int) -> int:
	var i := at + 1
	while i < bytes.size():
		if bytes[i] == _BACKSLASH:
			i += 2
		elif bytes[i] == _QUOTE:
			return i + 1
		else:
			i += 1
	return -1


## Where the line of [param at] ends (its newline, or the end).
static func _line_end(bytes: PackedByteArray, at: int) -> int:
	var i := at
	while i < bytes.size() and bytes[i] != _NEWLINE:
		i += 1
	return i


static func _space(c: int) -> bool:
	return c == 0x20 or c == 0x09 or c == 0x0D


static func _word_start(c: int) -> bool:
	return (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) or c == 0x5F
