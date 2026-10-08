extends Node
## Autoload "Rom": the ROM in use at run time. Game code reads graphics
## through [MwRom] (static, also usable by @tool scripts); this node reports
## a missing or unexpected ROM once at start-up. An exported build without
## the player's ROM says where to put it in a message box and quits.

signal rom_missing(reason: String)


func _ready() -> void:
	var a := MwRom.archive()
	if OS.has_feature("template") and not a.is_mlh():
		_report("no Mutant League Hockey ROM found")
		OS.alert("Mutant League Hockey (USA, Europe) ROM not found.\n\n"
			+ "Put your ROM file (.gen, .md or .bin) next to the game's executable:\n"
			+ OS.get_executable_path().get_base_dir() + "\n\n"
			+ "or start the game with:  -- --rom=PATH", "mightyweenie")
		get_tree().quit.call_deferred(1)
	elif a.size == 0:
		_report("no ROM at %s - run tools/bin/setup-rom" % MwRom.ROM_PATH)
	elif not a.is_mlh():
		_report("%s is not Mutant League Hockey (USA, Europe): SHA-1 %s" % [a.source_path, a.sha1])


func _report(reason: String) -> void:
	push_error("Rom: " + reason)
	rom_missing.emit(reason)
