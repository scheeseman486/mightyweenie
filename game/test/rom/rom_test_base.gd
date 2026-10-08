extends GutTest
## Shared setup for ROM tests: skip (pending) when the user's ROM isn't in
## the project (tools/bin/setup-rom).

var rom := PackedByteArray()


func before_all() -> void:
	MwRom.use(null)
	if MwRom.available():
		rom = MwRom.data()


func need_rom() -> bool:
	if rom.is_empty():
		pending("ROM not installed (tools/bin/setup-rom)")
		return false
	return true


static func repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel).simplify_path()
