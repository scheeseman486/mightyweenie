extends SceneTree
## Differential checks of [MwSoundZ80] and [MwSoundSamples] (plan 12). Paths
## are relative to the repository root; the recordings are ROM-derived and stay
## in out/. Exit code 0 = everything identical.
##
##   tools/bin/godot-headless -s res://test/audio/soundz80_check.gd -- samples out/plan12/portz80/sample_hashes_gd.txt
##       every sample's descriptor, the MD5 of its decoded values and of its
##       stream's 16-bit PCM (compared with sound_samples.py by
##       out/plan12/portz80/sample_hashes.py)
##   ... -- replay out/plan12/portz80/busy.json
##       replays the 68000 traffic recorded by out/plan12/portz80/busy.py (the
##       Python 68k model in a closed loop with the Python mirror of this port):
##       per tick the voice clears and the batch in, the four statuses, the
##       positions and every [MwSoundOut] call out, compared
##   ... -- busy
##       [MwSound68k] and [MwSoundZ80] in a closed loop on the title screen
##       (title music, each voice id `$12-$3A` played at tick 90): the ticks
##       until sound_busy answers 0, against the GPGX measurements
##       (out/plan12/portz80/measured.json, written by busy.py)


## Records the calls as "ym,port,reg,value" ... strings.
class Recorder extends MwSoundOut:
	var calls := PackedStringArray()

	func ym_write(port: int, reg: int, value: int) -> void:
		calls.append("ym,%d,%d,%d" % [port, reg, value])

	func psg_write(value: int) -> void:
		calls.append("psg,%d" % value)

	func pcm_start(ch: int, sample: int, from_index: int) -> void:
		calls.append("start,%d,%d,%d" % [ch, sample, from_index])

	func pcm_stop(ch: int) -> void:
		calls.append("stop,%d" % ch)

	func pcm_rate(ch: int, step: int) -> void:
		calls.append("rate,%d,%d" % [ch, step])

	func pcm_volume(ch: int, volume: int) -> void:
		calls.append("volume,%d,%d" % [ch, volume])


## GPGX's busy lengths (out/plan12/notes_68k.md 4), written by busy.py.
const MEASURED_JSON := "out/plan12/portz80/measured.json"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var rom := MwRom.data()
	if rom.is_empty():
		print("no ROM (tools/bin/setup-rom)")
		quit(1)
		return
	var mode := args[0] if args.size() > 0 else "busy"
	var ok := false
	match mode:
		"samples":
			ok = _samples(rom, _abs(args[1] if args.size() > 1 else "out/plan12/portz80/sample_hashes_gd.txt"))
		"replay":
			ok = _replay(rom, _abs(args[1] if args.size() > 1 else "out/plan12/portz80/busy.json"))
		"busy":
			ok = _busy(rom, args.slice(1))
		_:
			print("modes: samples [file] | replay [json] | busy [wait=N] [holds=0|1]")
	quit(0 if ok else 1)


static func _abs(rel: String) -> String:
	if rel.is_absolute_path():
		return rel
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel).simplify_path()


static func _samples(rom: PackedByteArray, path: String) -> bool:
	var s := MwSoundSamples.new(rom)
	var lines := PackedStringArray()
	var t0 := Time.get_ticks_usec()
	for i in s.count():
		var d := s.desc(i)
		var v := s.decode(i)
		var w := s.stream(i)
		var copies := PackedStringArray()
		for c in d.copies:
			copies.append("%X" % c)
		var ids := PackedStringArray()
		for sid in d.sound_ids:
			ids.append("%X" % sid)
		var loop := "%d-%d" % [w.loop_begin, w.loop_end] if w.loop_mode == AudioStreamWAV.LOOP_FORWARD else "-"
		lines.append("%d inst %d kind %d codec %d len %d out %d copies %s ids %s loop %s rate %d dec %s pcm %s" % [
			i, d.instrument, d.kind, d.codec, d.length, d.output_samples(), ",".join(copies),
			",".join(ids), loop, w.mix_rate, _md5(v), _md5(w.data)])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("%d samples -> %s (%.0f ms to decode and build the streams)" % [s.count(), path, (Time.get_ticks_usec() - t0) / 1000.0])
	return s.count() > 0


static func _md5(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(b)
	return h.finish().hex_encode()


static func _replay(rom: PackedByteArray, path: String) -> bool:
	if not FileAccess.file_exists(path):
		print("%s: missing (tools/bin/py out/plan12/portz80/busy.py --json)" % path)
		return false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var rec := Recorder.new()
	var cases_ok := 0
	var ticks := 0
	var bad := 0
	var n_calls := 0
	var usec := 0
	var max_usec := 0
	for c: Dictionary in data["cases"]:
		var z := MwSoundZ80.new(rom, rec)
		z.bus_wait_t = int(data["wait"])
		z.bus_holds = bool(data["holds"])
		z.extra_hold_t = int(data["extra"])
		var msgs := PackedStringArray()
		var t := 0
		for tk: Dictionary in c["ticks"]:
			rec.calls.clear()
			var t0 := Time.get_ticks_usec()
			for v: Variant in tk["clears"]:
				z.clear_voice(int(v))
			var had: bool = tk["block"] != null
			if had:
				z.apply_batch(String(tk["block"]).hex_decode())
			z.advance(had)
			var dt := Time.get_ticks_usec() - t0
			usec += dt
			max_usec = maxi(max_usec, dt)
			var want := PackedStringArray()
			for e: Array in tk["out"]:
				want.append(",".join(e.map(func(x: Variant) -> String: return str(x) if x is String else str(int(x)))))
			n_calls += want.size()
			var st := PackedInt32Array()
			var pos := PackedInt32Array()
			for k in 4:
				st.append(z.voice_status(k))
				pos.append(z.position(k))
			var want_st := PackedInt32Array(Array(tk["status"]).map(func(x: Variant) -> int: return int(x)))
			var want_pos := PackedInt32Array(Array(tk["pos"]).map(func(x: Variant) -> int: return int(x)))
			if st != want_st or pos != want_pos or rec.calls != want:
				bad += 1
				if msgs.size() < 3:
					msgs.append("tick %d: status %s/%s pos %s/%s calls %s/%s" % [t, st, want_st, pos, want_pos,
						rec.calls, want])
			t += 1
			ticks += 1
		if msgs.is_empty():
			cases_ok += 1
		else:
			for m in msgs:
				print("  %s: %s" % [c["name"], m])
	print("%s: %d/%d cases identical, %d/%d ticks identical (%d MwSoundOut calls); %.1f us per tick mean, %d us max"
			% [path.get_file(), cases_ok, (data["cases"] as Array).size(), ticks - bad, ticks, n_calls,
			float(usec) / maxi(1, ticks), max_usec])
	return cases_ok == (data["cases"] as Array).size()


static func _busy(rom: PackedByteArray, opts: PackedStringArray) -> bool:
	var measured := {}
	if FileAccess.file_exists(_abs(MEASURED_JSON)):
		measured = JSON.parse_string(FileAccess.get_file_as_string(_abs(MEASURED_JSON)))
	var exact := 0
	var near := 0
	var n := 0
	var rows := PackedStringArray()
	for sid in range(0x12, 0x3B):
		var z := MwSoundZ80.new(rom)
		for o in opts:
			if o.begins_with("wait="):
				z.bus_wait_t = int(o.trim_prefix("wait="))
			elif o.begins_with("holds="):
				z.bus_holds = o.trim_prefix("holds=") == "1"
		var s := MwSound68k.new(rom)
		s.reset()
		z.reset()
		s.music_title()
		for i in 90:
			_tick(s, z)
		var h := s.sound_play(sid)
		var busy := -1
		for f in 400:
			_tick(s, z)
			if not s.sound_busy(h):
				busy = f + 1
				break
		var want := int(measured.get(str(sid), -1))
		var row := "$%02X busy %s measured %s" % [sid, busy if busy >= 0 else "-", want if want >= 0 else "-"]
		if busy >= 0 and want >= 0:
			n += 1
			exact += int(busy == want)
			near += int(absi(busy - want) <= 1)
			row += " %+d" % (busy - want)
		rows.append(row)
	print("\n".join(rows))
	print("busy lengths, MwSound68k + MwSoundZ80 (%s): %d ids, %d exact, %d within 1 tick" % [" ".join(opts), n, exact, near])
	return near == n and n > 0


static func _tick(s: MwSound68k, z: MwSoundZ80) -> void:
	var batch := s.vblank(z)
	if not batch.is_empty():
		z.apply_batch(batch)
	z.advance(not batch.is_empty())
