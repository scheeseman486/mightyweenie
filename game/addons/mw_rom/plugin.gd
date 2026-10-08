@tool
extends EditorPlugin
## ROM import (metadata only), export exclusion and the ROM browser dock
## (docs/architecture.md, Assets; docs/re/graphics.md).

var _import: EditorImportPlugin
var _export: EditorExportPlugin
var _dock: Control


func _enter_tree() -> void:
	_import = preload("rom_import_plugin.gd").new()
	add_import_plugin(_import)
	_export = preload("rom_export_plugin.gd").new()
	add_export_plugin(_export)
	_dock = preload("rom_dock.gd").new()
	_dock.name = "ROM"
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock)


func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	_dock.queue_free()
	remove_export_plugin(_export)
	remove_import_plugin(_import)
