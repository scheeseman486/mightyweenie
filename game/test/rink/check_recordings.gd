extends SceneTree
## Our draw pass and camera against every pass of rink recordings of the
## original (`mw_harness rink-dump` -> out/rink/dec/NAME.json; docs/compare.md,
## Rink recordings). Run with `tools/bin/rink-check [NAME ...]`.
##
## Draw: MwRinkDrawCheck per pass (where the phase handler changed the
## phase, the puck rules saw the phase before). Camera: from the previous pass's camera,
## with this pass's target and elapsed ticks (skipped: the first pass of a
## screen entry, shake starts - the simulation's -, the FACE OFF! drop,
## which moves plane B itself, and passes whose phase changed: the phase
## handler runs after the camera and may move its target; the target choice
## is checked against the phase before and after the pass).


func _init() -> void:
	var names := OS.get_cmdline_user_args()
	if names.is_empty():
		names = PackedStringArray(["demo_s4", "human_s9", "demo_s10", "human_s14", "demo_s3", "demo_s22"])
	var rom := MwRom.data()
	var failed := false
	for name in names:
		var path := ProjectSettings.globalize_path("res://").path_join("../out/rink/dec/%s.json" % name).simplify_path()
		if not FileAccess.file_exists(path):
			print("%s: no %s (mw_harness rink-dump %s)" % [name, path, name])
			failed = true
			continue
		var ps: Array = (JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary)["passes"]
		var draw_bad := 0
		var cam_bad := 0
		var cam_n := 0
		for i in ps.size():
			var p: Dictionary = ps[i]
			var m := MwRinkDrawCheck.compare(rom, p)
			if not m.is_empty() and i > 0:
				var before_phase := int(ps[i - 1]["state"]["phase"])
				if before_phase != int(p["state"]["phase"]):
					m = MwRinkDrawCheck.compare(rom, p, before_phase)
			if not m.is_empty():
				draw_bad += 1
				if draw_bad <= 3:
					print("  %s: %s" % [p["name"], "; ".join(m)])
			if i == 0 or int(p["visit"]) != int(ps[i - 1]["visit"]):
				continue
			var r := _camera(rom, ps[i - 1], p)
			if r == "":
				continue
			cam_n += 1
			if r != "ok":
				cam_bad += 1
				if cam_bad <= 3:
					print("  %s camera: %s" % [p["name"], r])
		print("%s: draw %d/%d passes identical, camera %d/%d" % [name, ps.size() - draw_bad, ps.size(), cam_n - cam_bad, cam_n])
		failed = failed or draw_bad > 0 or cam_bad > 0
	quit(1 if failed else 0)


## "ok", a mismatch, or "" for a pass the recording cannot check.
static func _camera(rom: PackedByteArray, before_d: Dictionary, now_d: Dictionary) -> String:
	var before := MwRinkState.from_dict(rom, before_d["state"])
	var now := MwRinkState.from_dict(rom, now_d["state"])
	if now.camera.shake > before.camera.shake:
		return ""
	if now.phase == MwRinkState.PHASE_START and now.subphase == 2:
		return ""
	var recorded := now.camera_target
	var ok_target := false
	for ph in [before.phase, now.phase]:
		now.camera_target = before.camera_target
		var keep := now.phase
		now.phase = ph
		now.choose_camera_target()
		now.phase = keep
		ok_target = ok_target or now.camera_target == recorded
	if not ok_target:
		return "target"
	if before.phase != now.phase:
		return ""             # the phase handler may have moved the target after the camera ran
	var want := [now.camera.x, now.camera.y, now.camera.speed, now.camera.lead, now.camera.shown]
	var c := now.camera
	c.x = before.camera.x
	c.y = before.camera.y
	c.speed = before.camera.speed
	c.lead = before.camera.lead
	c.shake = before.camera.shake
	c.amp = before.camera.amp
	var lead: Variant = null
	if now.puck.flags & MwRinkState.Puck.CARRIED:
		var t := now.teams[1] if now.puck.flags & MwRinkState.Puck.BY_TEAM_B else now.teams[0]
		lead = MwRinkCamera.LEAD if t.flags4 & 2 else -MwRinkCamera.LEAD
	c.update(rom, int(now_d["e"]), recorded.motion if recorded else null, lead)
	var got := [c.x, c.y, c.speed, c.lead, c.shown]
	return "ok" if got == want else "got %s want %s" % [got, want]
