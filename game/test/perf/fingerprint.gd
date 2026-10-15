extends SceneTree
## The game's fingerprint (plan 45, from plan 42's scratch scripts): three
## played matches - P1-P4 on pads, P1 v CPU, CPU v CPU, 1500 passes each,
## random pads and pass lengths from fixed seeds - and for every pass:
##   play: the rink hash and the segment's events;
##   draw: the 3D drawer's draw pass (its sprite list, items, pieces, calls,
##     steps, marks, screen sprites);
##   models: the match models' snapshots (crowd, benches, paint).
## The same files before and after a change mean the game played, drew and
## stepped its models the same: the check for a change that must not change
## behaviour (a rename, an optimisation).
##   tools/bin/godot-headless -s res://test/perf/fingerprint.gd -- OUT_DIR [play,draw,models]
## Writes OUT_DIR/play.txt, draw.txt, models.txt (the kinds asked; all by default).

const MATCHES := [
	[3, 3, 7, 4, 2, 7, 4],        # stadium, team A, team B, pad mode, death index, seed, pads driven
	[1, 0, 12, 1, 4, 11, 1],
	[5, 9, 15, 0, 1, 23, 0],
]
const PASSES := 1500
const HELD := [0x01, 0x02, 0x04, 0x08, 0x05, 0x0A, 0x06, 0x09, 0]
const BUTTONS := [0, 0, 0, 0x10, 0x20, 0x40]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://fingerprint"
	var kinds := (args[1] if args.size() > 1 else "play,draw,models").split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	MwSettings.splatter = true
	for kind in kinds:
		var lines := PackedStringArray()
		var started := Time.get_ticks_msec()
		for m: Array in MATCHES:
			_match(kind, m, lines)
		var f := FileAccess.open(out_dir.path_join(kind + ".txt"), FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("fingerprint %s: %d lines in %d ms" % [kind, lines.size(), Time.get_ticks_msec() - started])
	quit()


## One match of [param kind]'s fingerprint, its lines added to [param lines].
func _match(kind: String, m: Array, lines: PackedStringArray) -> void:
	var rom := MwRom.data()
	var s := MwRinkState.new()
	s.rng = MlhRng.new(m[5])
	var sim := MwRinkSim.new(rom, s)
	sim.cpu = MwRinkAI.new()
	var update := MwRinkUpdate.new(sim)
	var phases := MwRinkPhases.new(update)
	var drawer: MwRinkDraw3D = null
	if kind == "draw":
		drawer = MwRinkDraw3D.new(rom)
		update.drawer = drawer
	MwRinkMatch.start(sim, m[0], m[1], m[2], m[3], false, m[4])
	s.period = 1
	s.period_minutes = 5
	s.clock = 300
	if kind == "models":
		MwRinkMatch.boot_icons(sim)               # (as the live game: the ref icons' animations)
	phases.enter(5)
	if kind == "models":
		MwMatchModels.make(s, null)
	var rng := RandomNumberGenerator.new()
	rng.seed = m[5]
	for i in PASSES:
		for pad in m[6]:
			if rng.randf() < 0.15:
				s.pads_held[pad] = HELD[rng.randi() % HELD.size()] | BUTTONS[rng.randi() % BUTTONS.size()]
		var e := 2 if rng.randf() < 0.9 else rng.randi_range(1, 4)
		var to := update.run_pass(e, phases, Callable(), Callable(), kind != "models")
		match kind:
			"play":
				lines.append("%d %d %s" % [i, MwNetHash.rink(s), str(_plain(sim.events, s)).sha1_text().left(10)])
			"draw":
				if to < 0:
					lines.append("%d %s %s %s %s %d %s %s" % [i, str(update.sprites).sha1_text().left(12),
							str(drawer.items).sha1_text().left(12), str(drawer.pieces).sha1_text().left(12),
							str([drawer.adds, drawer.calls, drawer.port_calls, drawer.inserted]).sha1_text().left(12),
							drawer.steps, str(drawer.marks).sha1_text().left(8),
							str([drawer.screen_sprites(), drawer.screen_sprites(true)]).sha1_text().left(12)])
			"models":
				if to == -1:
					update.draws([], MwRinkPhases.RULES_DRAWN, phases.overlays, phases.sprite_ops)
				var parts := MwMatchModels.frame_parts(s.crowd_life, s.bench_life, s.splatter, false)
				var paint: Dictionary = (parts.get(MwMatchModels.SPLAT, {}) as Dictionary).duplicate()
				if paint.has("atlas"):
					# the atlas by its content (its operations' log), not its instance id
					var log_ops: PackedFloat32Array = (paint["atlas"] as Object).get("_log")
					paint["atlas"] = [log_ops.size(), MwNetHash.digest_bytes(log_ops.to_byte_array())]
				lines.append("%d %s %s %s" % [i, str(parts.get(MwMatchModels.CROWD)).sha1_text().left(10),
						str(parts.get(MwMatchModels.BENCH)).sha1_text().left(10), str(paint).sha1_text().left(10)])
		if to >= 0:
			MwRinkMatch.rink_exit(sim, to)
			phases.enter(5)


## [param value] with its objects named (a team by its index, a player by
## team and index: instance ids differ from run to run).
static func _plain(value: Variant, s: MwRinkState) -> Variant:
	if value is Array:
		return (value as Array).map(func(x: Variant) -> Variant: return _plain(x, s))
	if value is MwRinkState.Team:
		return "team%d" % s.teams.find(value)
	if value is MwRinkState.Player:
		return "player%d.%d" % [(value as MwRinkState.Player).team, (value as MwRinkState.Player).index]
	if value is Object:
		return "object:%s" % MwNetGraph.key_of((value as Object).get_script())
	return value
