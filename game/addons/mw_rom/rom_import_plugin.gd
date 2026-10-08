@tool
extends EditorImportPlugin
## Imports a Genesis ROM (`.gen`) as a [RomArchive]: path, size and SHA-1
## only. The bytes stay in the file and are read when needed.


func _get_importer_name() -> String:
	return "mightyweenie.rom"


func _get_visible_name() -> String:
	return "Genesis ROM (metadata only)"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gen"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _can_import_threaded() -> bool:
	return false


func _import(source_file: String, save_path: String, _options: Dictionary,
		_platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var archive := RomArchive.describe(source_file)
	if archive.size == 0:
		return ERR_FILE_CANT_READ
	if not archive.is_mlh():
		push_warning("%s: SHA-1 %s is not Mutant League Hockey (USA, Europe)" % [source_file, archive.sha1])
	return ResourceSaver.save(archive, "%s.%s" % [save_path, _get_save_extension()])
