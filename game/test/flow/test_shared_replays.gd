extends "res://test/rom/rom_test_base.gd"
## Plan 45 (M3, L4): saved replays are files players share, so nothing in
## one is trusted - the header is read through MwPlain (a value of the wrong
## type is its default: the list can't break on it), the sizes it declares
## are capped before anything is allocated, its custom teams' view is shown
## only once the file has opened and only when it holds its teams, and a
## ".part" a crash left is taken up when whole, else cleared.

const DIR := "user://test/shared_replays"

var _dir := ""


func before_each() -> void:
	_dir = MwReplayFile.dir
	MwReplayFile.dir = DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


func after_each() -> void:
	MwReplayFile.dir = _dir
	MwCustomTeams.clear()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	MwGfx.put_u32(b, 0, v)
	return b


## A replay file as MwReplayFile writes it: [param header], then the body's
## lengths ([param raw] / [param packed_size] < 0: the body's own) and the body.
static func _file(header: Dictionary, body: Variant, raw := -1, packed_size := -1) -> PackedByteArray:
	var hb := var_to_bytes(header)
	var bytes := var_to_bytes(body)
	var packed := bytes.compress(FileAccess.COMPRESSION_ZSTD)
	var out := MwReplayFile.MAGIC.to_ascii_buffer()
	out.append_array(_u32(hb.size()))
	out.append_array(hb)
	out.append_array(_u32(raw if raw >= 0 else bytes.size()))
	out.append_array(_u32(packed_size if packed_size >= 0 else packed.size()))
	out.append_array(packed)
	return out


static func _put(file_name: String, bytes: PackedByteArray) -> String:
	var path := DIR.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


static func _readable_header() -> Dictionary:
	return {"version": MwReplayFile.VERSION, "rom_sha1": RomArchive.MLH_SHA1, "time": 100, "mode": "exhibition",
			"side_format": MwReplayFile.SIDE_FORMAT}


func test_a_header_of_the_wrong_types_reads_as_its_defaults() -> void:
	var path := _put("odd" + MwReplayFile.EXT, _file({"version": [1], "time": "soon", "score": "3-2",
			"names": 5, "kept": "yes", "mode": 7, "round": {}, "team_a": null, "custom_view": [1],
			"players": "p1"}, {}))
	_put("fine" + MwReplayFile.EXT, _file({"time": 50, "score": [3, 2], "names": ["A", "B"], "mode": "demo"}, {}))
	var h := MwReplayFile.header_of(path)
	assert_eq([h["version"], h["time"], h["score"], h["names"], h["kept"], h["mode"], h["round"], h["team_a"]],
			[0, 0, [0, 0], [], false, "7", -1, 0])
	assert_eq([h["custom_view"], h["players"]], [{}, {}])
	var listed := MwReplayFile.list()
	assert_eq(listed.size(), 2, "both listed, the list unbroken")
	assert_eq(listed[0]["header"]["names"], ["A", "B"], "newest first")
	assert_false(listed[1]["ok"], "the odd one: not this version's")


func test_declared_sizes_past_the_caps_are_refused() -> void:
	var body := {"state": {}, "replay": {}}
	var path := _put("huge" + MwReplayFile.EXT, _file(_readable_header(), body, MwReplayFile.BODY_MAX + 1))
	assert_eq(MwReplayFile.open(path), {}, "a body bigger than any match's")
	var packed := var_to_bytes(body).compress(FileAccess.COMPRESSION_ZSTD).size()
	path = _put("ratio" + MwReplayFile.EXT, _file(_readable_header(), body, MwReplayFile.BODY_RATIO * packed + 1))
	assert_eq(MwReplayFile.open(path), {}, "a tiny body that says it unpacks to more than any could")
	var long_header := MwReplayFile.MAGIC.to_ascii_buffer()
	long_header.append_array(_u32(MwReplayFile.HEADER_MAX + 1))
	long_header.resize(64)
	assert_eq(MwReplayFile.header_of(_put("long" + MwReplayFile.EXT, long_header)), {})


func test_a_view_that_doesnt_hold_its_teams_is_never_shown() -> void:
	var base := MwCustomOverlay.BASE
	var overlay := PackedByteArray()
	overlay.resize(MwTeams.SIZE)
	var before := MwRom.overlay()
	for records: PackedInt32Array in [PackedInt32Array([base + 0x1000]), PackedInt32Array([base - 2]),
			PackedInt32Array([base + 1]), PackedInt32Array()]:
		assert_false(MwCustomTeams.show_snapshot({"overlay": overlay, "records": records}), str(records))
	MwGfx.put_u32(overlay, MwTeams.NAME, base + MwTeams.SIZE + 0x100)        # a pointer past the view
	assert_false(MwCustomTeams.show_snapshot({"overlay": overlay, "records": PackedInt32Array([base])}))
	MwGfx.put_u32(overlay, MwTeams.NAME, 0x1000)
	MwGfx.put_u32(overlay, MwTeams.ROSTER + 4 * 23, base + MwTeams.SIZE)    # the roster's last, one past
	assert_false(MwCustomTeams.show_snapshot({"overlay": overlay, "records": PackedInt32Array([base])}))
	assert_eq(MwRom.overlay(), before, "nothing shown")
	MwGfx.put_u32(overlay, MwTeams.ROSTER + 4 * 23, 0x1000)
	assert_true(MwCustomTeams.show_snapshot({"overlay": overlay, "records": PackedInt32Array([base])}),
			"a view that holds its record")
	assert_eq(MwRom.overlay(), overlay)


func test_a_file_that_doesnt_open_leaves_the_banks_view() -> void:
	if not need_rom():
		return
	MwCustomTeams.teams.append(MwCustomTeam.from_original(MwRom.archive().bytes(), 9))
	MwCustomTeams.rebuild()
	var view := MwCustomTeams.snapshot()
	assert_false(view.is_empty())
	MwCustomTeams.clear()
	var h := _readable_header()
	h["custom_view"] = view
	var path := _put("no_frames" + MwReplayFile.EXT, _file(h, {"state": {}, "replay": {}}))
	assert_eq(MwReplayFile.open(path), {}, "no frames: not a replay this build plays")
	assert_eq(MwRom.overlay().size(), 0, "and the file's view was never shown (it used to stay as the bank's)")


func test_a_part_a_crash_left_is_taken_up_when_whole() -> void:
	var whole := _file(_readable_header(), {"state": {}, "replay": {}})
	_put("whole" + MwReplayFile.EXT + ".part", whole)
	_put("short" + MwReplayFile.EXT + ".part", whole.slice(0, whole.size() - 3))
	_put("kept" + MwReplayFile.EXT, whole)
	_put("kept" + MwReplayFile.EXT + ".part", whole)
	var listed := MwReplayFile.list()
	var names := listed.map(func(e: Dictionary) -> String: return str(e["path"]).get_file())
	names.sort()
	assert_eq(names, ["kept" + MwReplayFile.EXT, "whole" + MwReplayFile.EXT])
	assert_eq(Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool: return f.ends_with(".part")), [],
			"no .part left")
