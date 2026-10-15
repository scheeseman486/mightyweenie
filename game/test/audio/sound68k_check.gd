extends SceneTree
## Differential check of [MwSound68k] against the reference model
## (`harness/mw_harness/sound68k.py`): replays the scenarios that
## `out/plan12/port68k/dump.py` recorded from the model - the API calls before
## each tick with their return values, the Z80's answers ($BD pending, the
## four voice statuses), the block copied, the voices freed, the skip reason,
## the sound RAM's SHA-1 every tick and its full image every 50 ticks - and
## compares all of it, tick by tick. Exit code 0 = everything identical.
##
##   tools/bin/godot-headless -s res://test/audio/sound68k_check.gd -- out/plan12/port68k/music.json [...]
##
## Paths are relative to the repository root; without one, the five groups
## dump.py writes (music, ids, api, fuzz, synthetic). The recordings are
## ROM-derived and stay in out/.

const DEFAULT := ["out/plan12/port68k/music.json", "out/plan12/port68k/ids.json",
		"out/plan12/port68k/api.json", "out/plan12/port68k/fuzz.json",
		"out/plan12/port68k/synthetic.json"]
const _SKIPS := ["", "z80", "lock"]     # MwSound68k.Skip -> the model's TickOutput.skipped
const _GAME_VARS_LEN := 0xFFCA4E - 0xFFCA2C


## The Z80 as the recording saw it: answers `$BD` pending and the voice
## statuses it is given, and records the 68000's status clears. Also used by
## test_sound_68k.gd.
class StubZ80 extends MwSoundZ80:
	var pending := false
	var status := PackedInt32Array([0, 0, 0, 0])
	var clears := PackedInt32Array()

	func batch_pending() -> bool:
		return pending

	func voice_status(k: int) -> int:
		return status[k]

	func clear_voice(k: int) -> void:
		clears.append(k)
		status[k] = 0


## A [StubZ80], whatever [MwSoundZ80]'s constructor takes (the ROM and an
## [MwSoundOut] in the contract; nothing while it is a stub).
static func make_stub(rom: PackedByteArray) -> StubZ80:
	var argc := 0
	for m: Dictionary in (MwSoundZ80 as Script).get_script_method_list():
		if m["name"] == "_init":
			argc = (m["args"] as Array).size() - (m["default_args"] as Array).size()
	var args := []
	if argc >= 1:
		args.append(rom)
	if argc >= 2:
		args.append(MwSoundOut.new())
	return (StubZ80 as GDScript).callv("new", args) as StubZ80


func _init() -> void:
	var paths := OS.get_cmdline_user_args()
	if paths.is_empty():
		paths = PackedStringArray(DEFAULT)
	var rom := MwRom.data()
	if rom.is_empty():
		print("no ROM (tools/bin/setup-rom)")
		quit(1)
		return
	var repo_root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var z80 := make_stub(rom)
	var failed := false
	for rel in paths:
		var path := rel if rel.is_absolute_path() else repo_root.path_join(rel)
		if not FileAccess.file_exists(path):
			print("%s: missing (tools/bin/py out/plan12/port68k/dump.py)" % rel)
			failed = true
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var n_sc := 0
		var ok_sc := 0
		var n_ticks := 0
		var bad_ticks := 0
		var stats := {calls = 0, returns = 0, blocks = 0, clears = 0, rams = 0, usec = 0, max_usec = 0}
		for sc: Dictionary in data["scenarios"]:
			var r := replay(rom, sc, stats, z80)
			n_sc += 1
			n_ticks += int(r["ticks"])
			bad_ticks += int(r["bad_ticks"])
			if int(r["bad_ticks"]) == 0 and (r["msgs"] as PackedStringArray).is_empty():
				ok_sc += 1
			else:
				for m in (r["msgs"] as PackedStringArray):
					print("  %s: %s" % [sc["name"], m])
		print(("%s: %d/%d scenarios identical, %d/%d ticks identical (%d calls, %d return values, %d blocks, %d voice "
				+ "clears, %d full RAM images); vblank %.1f us mean, %d us max")
				% [rel.get_file(), ok_sc, n_sc, n_ticks - bad_ticks, n_ticks, stats.calls, stats.returns,
				stats.blocks, stats.clears, stats.rams, float(stats.usec) / maxi(1, n_ticks), stats.max_usec])
		failed = failed or ok_sc != n_sc
	quit(1 if failed else 0)


## Replays one recorded scenario through a new [MwSound68k] with the Z80 stub
## [param z80]; returns {ticks, bad_ticks, msgs} (the first few mismatches) and
## adds to [param stats].
static func replay(rom: PackedByteArray, sc: Dictionary, stats: Dictionary, z80: StubZ80) -> Dictionary:
	if sc.has("patches"):
		# synthetic scenarios: made-up instruments and sequences dump.py wrote
		# into its copy of the ROM (paths the game's own data never reaches)
		rom = rom.duplicate()
		for patch: Array in sc["patches"]:
			var bytes := String(patch[1]).hex_decode()
			for i in bytes.size():
				rom[int(patch[0]) + i] = bytes[i]
	var driver := MwSound68k.new(rom)
	driver.pal = bool(sc["pal"])
	var msgs := PackedStringArray()
	driver.reset()
	var diff := _first_diff(driver.ram_image(), String(sc["ram0"]).hex_decode())
	if diff != "":
		msgs.append("after reset: RAM differs at " + diff)
	var ticks: Array = sc["ticks"]
	var bad_ticks := 0
	var hasher := HashingContext.new()
	for i in ticks.size():
		var t: Dictionary = ticks[i]
		var bad := PackedStringArray()
		for c: Array in t["calls"]:
			stats.calls += 1
			var want: Variant = c[c.size() - 1]
			var got: Variant = _call(driver, c)
			if want == null:
				continue
			stats.returns += 1
			var same: bool = (got == want) if want is bool else (got is int and got == int(want))
			if not same:
				bad.append("%s%s returned %s, the model %s"
						% [c[0], str(c.slice(1, c.size() - 1)), str(got), str(want)])
		z80.pending = bool(t["pending"])
		var status: Array = t["status"]
		for k in 4:
			z80.status[k] = int(status[k])
		z80.clears.clear()
		var t0 := Time.get_ticks_usec()
		var block := driver.vblank(z80)
		var dt := Time.get_ticks_usec() - t0
		stats.usec += dt
		stats.max_usec = maxi(stats.max_usec, dt)
		var want_block := String(t["block"])
		if not want_block.is_empty():
			stats.blocks += 1
		if block.hex_encode() != want_block:
			bad.append("block differs (%s)" % _first_diff(block, want_block.hex_decode(), false))
		var want_clears := PackedInt32Array()
		for v: Variant in t["clears"]:
			want_clears.append(int(v))
		stats.clears += want_clears.size()
		if z80.clears != want_clears:
			bad.append("voices freed %s, the model %s" % [str(z80.clears), str(want_clears)])
		if _SKIPS[driver.skipped] != String(t["skip"]):
			bad.append("skip '%s', the model '%s'" % [_SKIPS[driver.skipped], t["skip"]])
		var ram := driver.ram_image()
		hasher.start(HashingContext.HASH_SHA1)
		hasher.update(ram)
		if hasher.finish().hex_encode() != String(t["sha1"]):
			bad.append("RAM hash differs")
		if t.has("ram"):
			stats.rams += 1
			diff = _first_diff(ram, String(t["ram"]).hex_decode())
			if diff != "":
				bad.append("RAM differs at " + diff)
		if not bad.is_empty():
			bad_ticks += 1
			if msgs.size() < 6:
				msgs.append("tick %d: %s" % [i, "; ".join(bad)])
	return {ticks = ticks.size(), bad_ticks = bad_ticks, msgs = msgs}


## One recorded call [name, args..., return] on [param driver]; returns its result
## (null for the routines without one).
static func _call(driver: MwSound68k, c: Array) -> Variant:
	var a := c.slice(1, c.size() - 1)
	match String(c[0]):
		"music_title":
			driver.music_title()
		"music_game":
			driver.music_game()
		"music_start":
			driver.music_start(int(a[0]))
		"music_fade_out":
			driver.music_fade_out(int(a[0]))
		"enter_match":
			driver.enter_match(int(a[0]))
		"sound_play":
			return driver.sound_play(int(a[0]))
		"random_sound":
			return driver.random_sound(int(a[0]))
		"positional":
			return driver.positional(int(a[0]), int(a[1]) != 0)
		"stop_positional":
			driver.stop_positional()
		"sound_busy":
			return driver.sound_busy(int(a[0]))
		"sound_stop":
			driver.sound_stop(int(a[0]))
		"crowd_level":
			driver.crowd_level(int(a[0]))
		"crowd_restart":
			driver.crowd_restart()
		"crowd_fade":
			driver.crowd_fade()
		"crowd_off":
			driver.crowd_off()
		"set_d5_high":
			driver.d5_high = int(a[0])
		var other:
			push_error("sound68k_check: unknown call " + str(other))
	return null


## "" when equal, else where the first difference is: a RAM address (for
## [method MwSound68k.ram_image] images) or a byte offset.
static func _first_diff(got: PackedByteArray, want: PackedByteArray, ram := true) -> String:
	if got == want:
		return ""
	var n := mini(got.size(), want.size())
	for i in n:
		if got[i] != want[i]:
			if not ram:
				return "byte $%02X: %02x, the model %02x" % [i, got[i], want[i]]
			var a := (0xFFCA2C + i) if i < _GAME_VARS_LEN else (0xFFE6A6 + i - _GAME_VARS_LEN)
			return "$%06X: %02x, the model %02x" % [a, got[i], want[i]]
	return "size %d, the model %d" % [got.size(), want.size()]
