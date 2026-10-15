extends Node
## Autoload "Rom": the ROM in use at run time. Game code reads graphics
## through [MwRom] (static, also usable by @tool scripts); this node reports
## a missing or unexpected ROM once at start-up.
##
## An exported build looks for the player's ROM where [method
## MwRom.rom_candidates] says (a [code]--rom=PATH[/code] argument, the
## game's folder - the executable's, or the AppImage's -, the user data
## folder). When none is there, the operating system's own file dialog asks
## for it (owner's request, 2026-10-15; the engine's own dialog where the
## system has none): the game waits, paused, under it. A file that is the
## ROM is copied into the user data folder as [constant COPY_NAME] - found
## there from then on - and the game starts again with it; one that isn't
## says why and asks again; cancelled, a message says where the ROM can go
## and the game quits.

## The ROM is missing or not the expected one, [param reason] says which (also pushed as an
## error); emitted at start-up.
signal rom_missing(reason: String)

## The chosen ROM's copy in the user data folder.
const COPY_NAME := "mlh.gen"
## The message boxes' and the dialog's titles.
const TITLE := "mightyweenie"
const ASK := "Select your Mutant League Hockey (USA, Europe) ROM"
## The dialog's file filter (the native dialog's form): the ROM's extensions
## (MwRom.ROM_EXTENSIONS; the file's size and SHA-1 decide, not its name).
const FILTERS := ["*.gen, *.md, *.bin ; Mega Drive / Genesis ROM"]

var _dialog: FileDialog


func _ready() -> void:
	var archive := MwRom.archive()
	if OS.has_feature("template") and not archive.is_mlh():
		_report("no Mutant League Hockey ROM found")
		get_tree().paused = true                 # nothing starts under the dialog (the router, the boot)
		_ask.call_deferred()
	elif archive.size == 0:
		_report("no ROM at %s - run tools/bin/setup-rom" % MwRom.ROM_PATH)
	elif not archive.is_mlh():
		_report("%s is not Mutant League Hockey (USA, Europe): SHA-1 %s" % [archive.source_path, archive.sha1])


## The engine's dialog's size where the system has none: a window of its
## own, at the desktop's scale (the game's picture is 320 x 224 scaled up).
const DIALOG_SIZE := Vector2i(900, 600)


## The file dialog that asks for the ROM: the system's own where it has one
## (else the engine's, in a window of its own), a file of the file system,
## the ROM's extensions first, starting in [param folder]; it answers while
## the game is paused.
static func rom_dialog(folder: String) -> FileDialog:
	var d := FileDialog.new()
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	d.use_native_dialog = true
	d.force_native = true
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.title = ASK
	d.filters = PackedStringArray(FILTERS)
	d.current_dir = folder
	return d


## The ROM file at [param path] taken as the player's: "" when it is the
## expected ROM (its size first - a large file isn't read - then its SHA-1)
## and is in [param folder] as [constant COPY_NAME] (copied there, the copy
## checked); else why not, for the player.
static func take_rom(path: String, folder: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "That file can't be read."
	var size := f.get_length()
	f.close()
	if size != RomArchive.MLH_SIZE:
		return "That file isn't the Mutant League Hockey (USA, Europe) ROM: it is %d bytes, the ROM %d." % [size,
				RomArchive.MLH_SIZE]
	var chosen := RomArchive.describe(path)
	if not chosen.is_mlh():
		return ("That file isn't the Mutant League Hockey (USA, Europe) ROM (its SHA-1 is %s; a raw, unzipped "
				+ ".gen / .md / .bin dump is needed).") % chosen.sha1
	var to := folder.path_join(COPY_NAME)
	if path.simplify_path() != to.simplify_path():
		DirAccess.make_dir_recursive_absolute(folder)
		var err := DirAccess.copy_absolute(path, to)
		if err != OK:
			return "The ROM couldn't be copied to %s (%s)." % [folder, error_string(err)]
	if not RomArchive.describe(to).is_mlh():
		return "The ROM's copy in %s isn't whole." % folder
	return ""


func _ask() -> void:
	if _dialog == null:
		_dialog = rom_dialog(MwRom.game_dir())
		_dialog.file_selected.connect(_chosen)
		_dialog.canceled.connect(_cancelled)
		get_tree().root.add_child(_dialog)
	_dialog.popup_centered(DIALOG_SIZE)


## A file chosen: the ROM - copied, the game started again with it (an
## AppImage started again itself: its executable's mount goes with this
## run); else why not, and the dialog again.
func _chosen(path: String) -> void:
	var why := take_rom(path, OS.get_user_data_dir())
	if why != "":
		OS.alert(why + "\n\nChoose your ROM file again.", TITLE)
		_ask.call_deferred()
		return
	var args := OS.get_cmdline_args()
	var user := OS.get_cmdline_user_args()
	if not user.is_empty():
		args.append("--")
		args.append_array(user)                 # (--join and the like go on; a --rom= is found again or not)
	var appimage := OS.get_environment("APPIMAGE")
	if appimage != "":
		OS.create_process(appimage, args)
	else:
		OS.set_restart_on_exit(true, args)
	get_tree().quit()


## The dialog cancelled: where the ROM can go, and the game quits.
func _cancelled() -> void:
	OS.alert("Mutant League Hockey (USA, Europe) ROM not found.\n\n"
		+ "Start the game again and choose your ROM file (.gen, .md or .bin, unzipped), or put it next to "
		+ "the game:\n" + MwRom.game_dir() + "\n\n"
		+ "or start the game with:  -- --rom=PATH", TITLE)
	get_tree().quit(1)


func _report(reason: String) -> void:
	push_error("Rom: " + reason)
	rom_missing.emit(reason)
