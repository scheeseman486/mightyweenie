extends SceneTree
## Plan 12's live sound check, headless: [code]live_match.gd[/code]'s whole
## match (the router, the real scenes, its menu bot on the pads) with the
## sound driver attached - an [MwAudio] ticked before each router step as the
## Router autoload does, [member MwSound.driver] set - so every call of the
## driver's API the game makes in live play runs, with the driver's answers
## (handles, "still playing?"). Each call is logged with its tick and screen
## ([member MwSound.trace]); the counts by call are printed at the end.
##
##   tools/bin/godot-headless -s res://test/screens/live_sound.gd -- [options]
##     live_match.gd's options (--pads, --minutes, --teams, --seed, --ticks, ...)
##     --log PATH     every call as "tick screen call args -> result" (default: none)
##     --render N     1: the chips render each tick's audio (default), 0: the driver only
##     --mode N       the play mode (0 exhibition, default; 1 the playoffs)
##     --screen N     the first screen (default 1, the main menu; 0: the title)
##     --bot N        0: no pad input at all (the attract demo runs), 1: the menu bot (default)
##     --wav PATH     the rendered audio as a 16-bit stereo WAV at the chips' rate
##                    (~12.8 MB a minute; with --render 1)
##     --free N       enhancement switches: 1 MwAudio.free_music_samples, 2 free_effects, 3 both
##
## Exits 0 when the match got back to the main menu (or the playoffs) through
## a game-over scoreboard, else 1. Needs the ROM; without the mw_audio
## extension the driver runs unheard.

const LiveMatch := preload("res://test/screens/live_match.gd")

var _started := false
var _router: MwRouter
var _counts := {}
var _by_screen := {}
var _log: FileAccess
var _peak := 0.0
var _peaks := {}
var _wav: FileAccess
var _wav_bytes := 0


func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	var args := _args()
	var host := Node.new()
	root.add_child(host)
	var free := int(args.get("free", "0"))
	MwAudio.free_music_samples = free & 1 != 0
	MwAudio.free_effects = free & 2 != 0
	var audio := MwAudio.new()
	host.add_child(audio)
	audio.setup(MwRom.data(), false)
	MwSound.driver = audio
	var render := int(args.get("render", "1")) != 0 and audio.chips != null
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	_router = router
	router.session = MwSession.new(int(args.get("seed", "1")), 1)
	var su := router.session.setup
	su.pads = int(args.get("pads", "5"))
	su.period_minutes = int(args.get("minutes", "1"))
	su.penalties = int(args.get("penalties", "1"))
	var teams := str(args.get("teams", "0,5")).split(",")
	su.team_a = int(teams[0])
	su.team_b = int(teams[1])
	su.play_mode = int(args.get("mode", "0"))
	var bot := LiveMatch.MenuBot.new()
	bot.router = router
	bot.detours = int(args.get("detours", "6"))
	bot.cpu = su.pads == 5
	router.screen_entered.connect(bot.on_entered)
	router.screen_resumed.connect(bot.on_resumed)
	if int(args.get("bot", "1")) != 0:
		router.input = bot
	router.screen_entered.connect(func(id: int, _visit: int, tick: int, prev: int) -> void:
		var e := router.current().entry if router.current() else ""
		print("%7d  %2d <- %2d  %s" % [tick, id, prev, e]))
	var path := str(args.get("log", ""))
	if path != "":
		_log = FileAccess.open(path, FileAccess.WRITE)
	MwSound.trace = _on_call
	var wav := str(args.get("wav", ""))
	if wav != "" and render:
		_wav = _wav_open(wav, int(round(float(audio.chips.call("sample_rate")))))
	var first := int(args.get("screen", "1"))
	var menu := (load(MwScreens.scene_path(first)) as PackedScene).instantiate() as MwScreen
	menu.screen_id = first
	fader.cover()
	router.adopt(menu)
	var limit := int(args.get("ticks", "200000"))
	var started := Time.get_ticks_msec()
	var game_over := false
	var done := false
	var n := 0
	while n < limit:
		_audio_tick(audio, render, n)
		router.step()
		n += 1
		var id := router.current_id()
		if id in [15, 16]:
			game_over = true
		if game_over and id in [1, 11] and n > 1000:
			done = true
			break
	MwSound.trace = Callable()
	MwSound.driver = null
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	print("ticks %d in %.1f s (%.0f ticks/s), chips %s" % [n, secs, n / maxf(secs, 0.001),
			"rendered" if render else ("not rendered" if audio.chips != null else "missing")])
	var keys := _counts.keys()
	keys.sort()
	var total := 0
	for k in keys:
		total += int(_counts[k])
		print("  %-15s %6d   %s" % [k, int(_counts[k]), str(_by_screen[k])])
	print("calls: %d" % total)
	if render:
		print("peak level by screen (sampled): %s" % str(_peaks))
	if free != 0:
		print("extra voices: at most %d at once" % audio.extras_peak)
	print("RESULT %s" % ("ok" if done else "tick limit, on screen %d" % router.current_id()))
	if _log:
		_log.close()
	if _wav:
		_wav_close()
		print("wav: %s (%.1f s)" % [wav, _wav_bytes / 4.0 / float(audio.chips.call("sample_rate"))])
	quit(0 if done else 1)
	return true


## The Router autoload's order: the VBlank's driver work, then the router's
## tick. Every 30th tick the rendered frames' peak is noted by screen.
func _audio_tick(audio: MwAudio, render: bool, n: int) -> void:
	audio.step_driver()
	if not render:
		return
	var frames: PackedVector2Array = audio.chips.call("render", audio.frames_this_tick())
	if _wav:
		var pcm := PackedByteArray()
		pcm.resize(frames.size() * 4)
		for f in frames.size():
			pcm.encode_s16(4 * f, clampi(int(frames[f].x * 32767.0), -32768, 32767))
			pcm.encode_s16(4 * f + 2, clampi(int(frames[f].y * 32767.0), -32768, 32767))
		_wav.store_buffer(pcm)
		_wav_bytes += pcm.size()
	if n % 30 != 0:
		return
	var p := 0.0
	for f in frames:
		p = maxf(p, maxf(absf(f.x), absf(f.y)))
	var id := _router.current_id()
	_peaks[id] = snappedf(maxf(float(_peaks.get(id, 0.0)), p), 0.001)


## A WAV file (PCM 16-bit stereo at [param rate]); sizes patched at [method _wav_close].
func _wav_open(path: String, rate: int) -> FileAccess:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return null
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(0)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(rate)
	f.store_32(rate * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(0)
	return f


func _wav_close() -> void:
	_wav.seek(4)
	_wav.store_32(36 + _wav_bytes)
	_wav.seek(40)
	_wav.store_32(_wav_bytes)
	_wav.close()


func _on_call(what: String, args: Array, result: Variant) -> void:
	_counts[what] = int(_counts.get(what, 0)) + 1
	var id := _router.current_id()
	var per: Dictionary = _by_screen.get(what, {})
	per[id] = int(per.get(id, 0)) + 1
	_by_screen[what] = per
	if _log:
		var a := PackedStringArray()
		for v in args:
			a.append(("$%X" % (v & 0xFFFFFFFF)) if v is int else str(v))
		var r := "" if result == null else (" -> $%X" % (result & 0xFFFFFFFF) if result is int else " -> %s" % str(result))
		_log.store_line("%7d %2d %s(%s)%s" % [_router.tick, id, what, ", ".join(a), r])


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	return out
