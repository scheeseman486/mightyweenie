@tool
extends EditorExportPlugin
## Keeps the ROM out of exported builds: players supply their own (plan 11).


func _get_name() -> String:
	return "mightyweenie_no_rom"


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with("res://rom/"):
		skip()
