class_name MwSession
extends RefCounted
## What lives across screens for one run of the game: the game setup, the
## original's two random streams and the attract demo flag
## (docs/re/title.md, Attract demo). The router hands it to every screen.
##
## Plan 35 (docs/net.md): the game is a pure function of a start record
## ([method to_record], [method from_record]) and the players' input stream.
## Every random number comes from the record: the original's two streams,
## and the port's own streams ([method port_stream]: the crowd's life, the
## 3D opening, the captain votes' draws, the original's "hardware" seeds),
## each derived from one session seed ([member seed]). Nothing reads
## [code]randi()[/code] but [method _entropy], once, for a session nobody
## gave a seed.

## Main random stream ($FFB096) and the second one ($FFCA18: starfield
## direction, main menu).
var rng: MlhRng
var rng_aux: MlhRng
## The setup the menus edit and the game reads.
var setup: MwMatchSetup
## True while the attract demo runs (`$FFCA1C`).
var attract := false
## Where the attract demo returns: the game setup (1, the original), or the
## port's front menu when it started the demo (plan 21).
var attract_return := 1
## The playoff run (`$FFBD6A`).
var playoffs := MwPlayoffs.new()
## State screens keep between visits (the main menu's row and stadium mode).
var screens := {}
## Plan 40 (I6): the menus' starfield where the last of the port's menus
## (and the game setup) left it, for the next one to go on from (a cut
## between them; RomStarfield.state - empty: none yet).
var menu_stars := []
## Plan 40 (S13): the teams [team A, team B] the players' line-ups
## ([member MwHumans.lineups]) were last chosen for (MwSelection.finish; the
## character selection keeps a line-up only for its team: empty, none yet).
var lineup_teams := []
## The rink's view (plan 20, MwRinkViews): the original's 2D (default) or
## one of the 3D cameras, picked with F1-F8 / a pad's Back on screens 4-6
## (MwRink).
var view := MwRinkViews.FLAT
## Plan 44: the group of views this machine's match plays in - 2D
## EXTENDED and 3D EXTENDED (true) or 2D and 3D - set with the match's
## first view by the matchup (MwSettings.extended_play: online always);
## player 1's VIEW switch stays in it (MwRinkViews.toggled).
var extended_views := false
## The birds-eye view's layout: the goals left and right (true) or top and
## bottom, as the 2D (F5 again switches).
var birds_eye_across := false
## The port's local play (plan 34): "exhibition" or "playoffs" - which
## variant of the game setup (screen 1) the front menu's flow shows; ""
## the original's game setup (the original's flow, `front_menu` off).
var local_mode := ""
## The port's playoffs (plan 34): a run is in progress - made by its first
## game's PLAY GAME, by a password or by a load; its teams can't change and
## the next PLAY GAME doesn't start a new one (the original's game setup
## Start always did, `$11D8E`).
var run_started := false
## Games played in the run since it was started or loaded (SAVE GAME shows
## only then).
var run_games := 0
## The run as it stood when the bracket last opened after a game: the
## setup's 10 bytes and the run's 21 ([MwPlayoffSave]: a save holds this,
## so a loaded run opens the same bracket and goes on exactly as it would
## have). Empty before the first game.
var run_checkpoint := PackedByteArray()
## The password the original showed after the last game (listed with saves).
var run_password := ""
## The port's game setup defaults taken ([method take_port_defaults]).
var port_defaults_taken := false
## Seeds were given (tests, comparisons): screens that reseed a stream from
## the hardware (the main menu's second stream) leave it alone.
var fixed_seeds := false
## Plan 34: who plays ([MwHumans]), chosen on the controller selection (110)
## and kept for the session (and in playoff saves).
var humans := MwHumans.new()
## The player on each of the original's pads 1-4 in a match
## ([method MwHumans.pad_players]; the router hands each pad its player's
## inputs on the original's screens). Pads 1-4 are players 1-4 until the
## controller selection sets it.
var pad_map := PackedInt32Array([1, 2, 3, 4])
## Where the controller selection goes on to (MwFlow.before_match).
var after_selection := 3

## Plan 35: the session seed (32 bits, never 0) every port stream derives
## from ([method port_stream]); in the start record.
@warning_ignore("shadowed_global_identifier")   # a frozen name (docs/style.md N9): read by name elsewhere
var seed := 0
## Plan 35: the port's random streams made so far, by name ([method
## port_stream]); their states are in the start record.
var streams := {}
## Plan 35: the match rules the start record gave ([method
## MwSettings.match_rules]; empty: this machine's own settings).
var rules := {}
## Plan 38 with plan 35: the custom teams the start record gave ([method
## MwCustomTeams.record_teams]' form; empty: the custom teams in use on this
## machine). Putting them in use is the caller's ([method
## MwCustomTeams.use_teams]), as with [member rules]; a resync snapshot
## carries them with the session.
var custom_teams := {}
## Plan 35: each player's controller layout as the start record gave it
## (player -> MwInputMap.LAYOUTS name; empty: this machine's settings,
## [method layout_of]). The layout changes the game's logic (the GENESIS
## layout's double-B RECLAIM, the STANDARD layout's pause menu), so it is
## the player's, carried with them.
var layouts := {}
## Plan 35 (work item 3): this machine's online game - hosting or joining,
## the lobby, the match - while there is one ([MwNetService]: the online
## pages make it, the Router autoload polls it); null offline. Not in the
## start record: a machine's own.
var net: MwNetService = null
## Plan 35 work item 4: the online match's player table, from its start
## record (empty: a local game) - "players": the lobby's player numbers in
## the match, ascending; "machines": number (as a string) -> the machine
## they play on (0 the host's). Online, the host's P1 drives the menus any
## player drives offline, captains always, no replays watched (MwFlow.online).
var online := {}
## Plan 35 work item 4: this machine's id in the online match (0 the host;
## -1 a local game). Not in the record: every machine has its own.
var machine := -1
## Plan 35 work item 5: a client's dead reckoning while its match runs (the
## rink draws its actors "now" through it); null offline and on the host.
## Not in the record: presentation, every machine its own.
var reckoning: MwNetReckoning = null

var _saved: MwMatchSetup

## The port streams' names (plan 35, docs/net.md): the original's hardware
## seeds (its HV counter at boot, the main menu's reseed of the second
## stream, a password whose check seed is 0), each match's crowd (the
## crowd's and the benches' life), the 3D opening's own choices, the
## captain votes' draws, the organ pool's picks (plan 39, MwAudio.play_organ).
const STREAM_HARDWARE := "hardware"
const STREAM_CROWD := "crowd"
const STREAM_OPENING := "opening"
const STREAM_CAPTAINS := "captain_draws"
const STREAM_ORGAN := "organ"
## The start record's format ([method to_record]). 2 (plan 40, S13): the
## setup's extended pads and line-ups no longer carried - the players are,
## and the rink's entry works them out (MwSelection.for_the_rink); a format
## 1 record's are left unread.
const RECORD_FORMAT := 2
## Plan 40 (S4): what each field of the session is - the one table the
## start record, an online reset and the resync snapshot read
## (test_session_fields: every field in one list). [b]In the start
## record[/b] ([method to_record], [method from_record]; an online match's
## reset sets them all, [method reset_from_record]):
const RECORD_FIELDS := ["seed", "streams", "rng", "rng_aux", "fixed_seeds", "setup", "playoffs", "local_mode",
		"run_started", "run_games", "run_checkpoint", "run_password", "attract", "attract_return",
		"after_selection", "rules", "custom_teams", "humans", "pad_map", "layouts", "online"]
## [b]A machine's own[/b]: never in the record, kept through a reset and
## left alone by a resync snapshot (MwNetSnapshot's codec) - the online
## service, this machine's id, its views, a client's dead reckoning (the
## survey's B2: a snapshot once took it), whether its front menu gave the
## set-up the port's defaults ([method take_port_defaults]).
const OWN_FIELDS := ["net", "machine", "view", "birds_eye_across", "extended_views", "reckoning",
		"port_defaults_taken"]
## [b]Keepsakes[/b]: what screens keep between visits - not in the record
## (a game started from one starts them afresh: a reset clears them), but a
## resync snapshot carries them.
const KEEPSAKES := ["screens", "menu_stars", "lineup_teams", "_saved"]


## [param seed_value] 0: seeded at random, as the original seeds from the
## VDP's HV counter at boot (then 32 warm-up steps); tests pass a seed.
## Plan 35: the "HV counter" is the port's hardware stream, from the session
## seed [param session_seed] - by default made from the given seeds (or,
## when none is given, from the one entropy draw, [method _entropy]).
func _init(seed_value := 0, aux_seed := 0, session_seed := 0) -> void:
	fixed_seeds = seed_value != 0
	if session_seed != 0:
		seed = session_seed & 0xFFFFFFFF
	elif seed_value != 0:
		seed = MwSeed.mix32(seed_value ^ MwSeed.mul32(aux_seed, 0x9E3779B9)) | 1
	else:
		seed = _entropy()
	playoffs.hardware = port_stream(STREAM_HARDWARE)
	rng = MlhRng.new(seed_value if seed_value != 0 else _hardware_seed())
	rng_aux = MlhRng.new(aux_seed if aux_seed != 0 else _hardware_seed())
	if seed_value == 0:
		rng.warm_up()
	if aux_seed == 0:
		rng_aux.warm_up()
	setup = MwMatchSetup.from_rom(MwRom.data(), MwMatchSetup.BOOT_DEFAULTS) if MwRom.available() \
			else MwMatchSetup.new()
	if MwRom.available():
		humans = MwHumans.from_pad_mode(MwRom.data(), setup.pads)
	else:
		humans.set_team(1, 0)


## The port's own game setup defaults (owner's request, 2026-10-15):
## PENALTIES on and RESERVES enabled, once a session - the first time the
## port's front menu shows, so a player's own choice stays for the rest of
## it (an online match takes the host's set-up from here). The original's
## flow (front menu off: the tests and the comparisons) and the attract
## demo keep the original's boot defaults (`$1C190`: both off).
func take_port_defaults() -> void:
	if port_defaults_taken:
		return
	port_defaults_taken = true
	setup.penalties = 1
	setup.reserves = 1


## Plan 40 (I5): the port's playoff run's bookkeeping (plan 34) in one
## place - [member run_started], [member run_games], [member run_checkpoint]
## (the password screen sets [member run_password], the password it shows).
## A run begun (its first game's
## PLAY GAME, a typed password): started, no game played yet.
func begin_run() -> void:
	run_started = true
	run_games = 0


## A game of the run played (back at the bracket after it).
func run_game_played() -> void:
	run_games += 1


## The run as the bracket stands now: the setup's 10 bytes and the run's 21
## (what a save holds).
func checkpoint_run() -> void:
	run_checkpoint = setup.to_bytes() + playoffs.to_bytes()


## A saved run taken up (MwPlayoffSave.load): begun, at [param checkpoint],
## its password [param password].
func load_run(checkpoint: PackedByteArray, password: String) -> void:
	begin_run()
	run_checkpoint = checkpoint
	run_password = password


## The run left (the game setup left, a new PLAYOFFS chosen): not started,
## no game played; its checkpoint and password stay until the next run's
## replace them.
func drop_run() -> void:
	run_started = false
	run_games = 0


## The run over (champion, eliminated, left for good): nothing of it kept.
func end_run() -> void:
	drop_run()
	run_checkpoint = PackedByteArray()
	run_password = ""


## The players as a save keeps them (MwPlayoffSave).
func humans_record() -> Dictionary:
	return humans.to_record()


## A save's players (none kept: as they are), and the pads they get on the
## original's screens ([member pad_map]) - a loaded run goes to its bracket
## before any controller selection.
func load_humans(record: Variant) -> void:
	if record is Dictionary and not (record as Dictionary).is_empty():
		humans = MwHumans.from_record(record)
		if MwRom.available():
			pad_map = humans.pad_players(MwRom.data())


## The port's player on the original's pad [param pad] (1-4), as the
## controller selection mapped it ([member pad_map]).
func player_on_pad(pad: int) -> int:
	if pad >= 1 and pad <= pad_map.size() and pad_map[pad - 1] > 0:
		return pad_map[pad - 1]
	return pad


## Plan 34: how many players' pads the original's screens read where they
## read every pad (the matchup's skip, the bracket, the team description):
## the original's four, which the router hands the players the controller
## selection put on them ([member pad_map]; a player on none counts on no
## screen, as on the original) - or, in an extended set-up, all twelve
## (player n is pad n there and nothing is remapped:
## [method MwHumans.pad_index]), so players 5-12 count as players 1-4 do.
## Not in the attract demo (the original's pads). A spectated match
## ([method spectated]): all twelve - nobody plays, everyone watches.
func screen_pads() -> int:
	return MwVerbs.PLAYERS if not attract and (not humans.original() or spectated()) else 4


## A spectated match (the owner, 2026-10-10: a CPU v CPU match had no way
## to pause or quit): the port's CPU v CPU exhibition - the controller
## selection (110) left with every player in the middle (pad mode 5, plan
## 34 section 5: local only). Not the attract demo (the original's CPU v
## CPU, which any press ends), never online or in the playoffs (the
## controller selection refuses it there: MwControllerSelect.refusal).
## Every player's pad may skip what the original lets a pad skip, Start
## from any pad pauses (the spectators' pause menu: REPLAY, TEAM INFO, QUIT
## GAME - MwRinkPhases.SPECTATED_ITEMS) and nothing lets anyone control a
## team or a player (no special plays, no timeout: the CPU decides for both
## teams, as the original's CPU teams).
func spectated() -> bool:
	return not attract and online.is_empty() and local_mode != "playoffs" and humans.total() == 0


## `rng_seed` with D0 = 0 on the second stream (the main menu does it on
## entry): a fresh hardware seed, unless the session's seeds are fixed.
func reseed_aux() -> void:
	if fixed_seeds:
		return
	rng_aux = MlhRng.new(_hardware_seed())
	rng_aux.warm_up()


## The original's hardware seed (its HV counter): plan 35, the next value of
## the port's hardware stream.
func _hardware_seed() -> int:
	return hardware_seed()


## A seed as the original's hardware would give it (never 0), from the
## session's hardware stream ([constant STREAM_HARDWARE]).
func hardware_seed() -> int:
	return port_stream(STREAM_HARDWARE).next_state() | 1


## The only entropy in the game (plan 35): a session seed for a session
## nobody gave one (Godot seeds [code]randi()[/code] from the clock at
## start-up). Everything random derives from it through the record.
static func _entropy() -> int:
	return (randi() & 0xFFFFFFFF) | 1


## The port's random stream [param name] (plan 35): made on first use from
## the session seed and the name ([method stream_seed]) and kept
## ([member streams], in the start record). The original's algorithm
## ([MlhRng]), never one of the original's two streams.
func port_stream(name: String) -> MlhRng:
	var r: Variant = streams.get(name)
	if r is MlhRng:
		return r
	var stream_rng := MlhRng.new(stream_seed(seed, name))
	streams[name] = stream_rng
	return stream_rng


## A fresh 31-bit seed (never 0) from port stream [param name]: what
## Godot-side presentation models (RandomNumberGenerator.seed) take.
func port_seed(name: String) -> int:
	return (port_stream(name).next_state() & 0x7FFFFFFF) | 1


## Port stream [param name]'s first state for session seed [param session_seed]:
## FNV-1a over the name's bytes, mixed with the seed (MwSeed.mix32).
## Integer arithmetic only: the same on every machine.
static func stream_seed(session_seed: int, name: String) -> int:
	var h := 0x811C9DC5
	for b in name.to_utf8_buffer():
		h = MwSeed.mul32(h ^ b, 0x01000193)
	return MwSeed.mix32(h ^ MwSeed.mix32(session_seed)) | 1


## Player [param player]'s controller layout as the game's logic reads it
## (MwInputMap.LAYOUTS): the start record's ([member layouts]), else this
## machine's setting.
func layout_of(player: int) -> String:
	return str(layouts.get(player, MwSettings.layout(player)))


## `attract_setup_begin` ($459C): save the setup, load the demo setup and
## pick its teams, stadium and Death Index with the main stream - among the
## original's 23 only, custom teams or not (owner, 2026-10-11).
func begin_attract() -> void:
	attract = true
	_saved = setup.copy()
	if MwRom.available():
		setup = MwMatchSetup.from_rom(MwRom.data(), MwMatchSetup.DEMO)
	else:
		setup.pads = MwMatchSetup.PADS_DEMO
	setup.team_a = rng.range_value(0, 22)
	setup.stadium = setup.team_a
	var b := rng.range_value(0, 22)
	while b == setup.team_a:
		b = rng.range_value(0, 22)
	setup.team_b = b
	setup.death_index = rng.range_value(0, 4)


## `attract_setup_end` ($45E4) and the main menu clearing the flag.
func end_attract() -> void:
	if _saved:
		setup = _saved
		_saved = null
	attract = false
	attract_return = 1


# --- plan 35: the start record ------------------------------------------------------------------

## The start record (plan 35, docs/net.md): everything the game's course
## depends on besides the players' inputs - the session seed and every
## random stream's state (the original's two, the port's), the setup's 10
## bytes, the playoffs' 21 bytes
## and bracket, the run's bookkeeping, the match rules ([method
## MwSettings.match_rules]: this session's, or this machine's settings),
## the player table (MwHumans' record, who is out, the pad map, each
## player's controller layout), plan 38's custom teams when there are
## any ("custom_teams": [method MwCustomTeams.record_teams]), the screen
## the game starts on ([param screen]) and the tick it starts at ([param
## tick]). Plain data (ints,
## strings, arrays, string-keyed dictionaries): JSON or the network carry it
## as it is. What screens keep between visits ([member screens]) is not in
## it: a game started from a record starts them afresh.
func to_record(screen := 1, tick := 0) -> Dictionary:
	var st := {}
	for k in streams:
		st[k] = (streams[k] as MlhRng).state
	var lay := {}
	for p in range(1, MwVerbs.PLAYERS + 1):
		lay[str(p)] = layout_of(p)
	var sides := []
	for side in playoffs.sides:
		sides.append(Array(side))
	return {
		"format": RECORD_FORMAT,
		"seed": seed,
		"rng": rng.state,
		"rng_aux": rng_aux.state,
		"fixed_seeds": fixed_seeds,
		"streams": st,
		"setup": Array(setup.to_bytes()),
		"playoffs": Array(playoffs.to_bytes()),
		"bracket": sides,
		"local_mode": local_mode,
		"run_started": run_started,
		"run_games": run_games,
		"run_checkpoint": Array(run_checkpoint),
		"run_password": run_password,
		"attract": attract,
		"attract_return": attract_return,
		"after_selection": after_selection,
		"rules": rules.duplicate() if not rules.is_empty() else MwSettings.match_rules(),
		"players": {"humans": humans.to_record(), "out": _sorted(humans.out.keys()), "pad_map": Array(pad_map),
				"layouts": lay},
		"online": online.duplicate(true),
		"screen": screen,
		"tick": tick,
	}.merged(_custom_record())


## Plan 38: the record's "custom_teams" - the session's own teams (a game
## started from a record), else the custom teams in use on this machine,
## with the playoffs' custom team as it is now - only when there are any: a
## record without custom teams is as before.
func _custom_record() -> Dictionary:
	var c := custom_teams if not custom_teams.is_empty() else MwCustomTeams.record_teams(playoffs)
	if c.is_empty():
		return {}
	var out := c.duplicate(true)
	out["playoff"] = playoffs.custom
	return {"custom_teams": out}


## A session made from start record [param r] ([method to_record]; JSON's
## floats taken as ints). Its match rules are in [member rules]; putting them
## into effect is the caller's ([method MwSettings.use_match_rules]), so a
## record can be read without touching this machine's settings.
static func from_record(r: Dictionary) -> MwSession:
	# plan 40 (S6, the survey's B7): a host's record read through MwPlain - a
	# value of the wrong type is its default, never a script error
	var session := MwSession.new(1, 1, MwPlain.num(r.get("seed"), 1))
	session.rng.state = MwPlain.num(r.get("rng"), 1) & 0xFFFFFFFF
	session.rng_aux.state = MwPlain.num(r.get("rng_aux"), 1) & 0xFFFFFFFF
	session.fixed_seeds = MwPlain.flag(r.get("fixed_seeds"))
	session.streams = {}
	var st := MwPlain.dict(r.get("streams"))
	for k in st:
		session.streams[str(k)] = MlhRng.new(MwPlain.num(st[k], 1))
	var sb := MwPlain.bytes(r.get("setup"))
	if sb.size() == MwMatchSetup.FIELDS.size():
		session.setup = MwMatchSetup.from_bytes(sb)
	session.playoffs.from_bytes(MwPlain.bytes(r.get("playoffs")))
	session.playoffs.hardware = session.port_stream(STREAM_HARDWARE)
	var sides := MwPlain.array(r.get("bracket"))
	for i in mini(sides.size(), 2):
		session.playoffs.sides[i] = MwPlain.ints(sides[i])
	session.local_mode = MwPlain.text(r.get("local_mode"))
	session.run_started = MwPlain.flag(r.get("run_started"))
	session.run_games = MwPlain.num(r.get("run_games"))
	session.run_checkpoint = MwPlain.bytes(r.get("run_checkpoint"))
	session.run_password = MwPlain.text(r.get("run_password"))
	session.attract = MwPlain.flag(r.get("attract"))
	session.attract_return = MwPlain.num(r.get("attract_return"), 1)
	session.after_selection = MwPlain.num(r.get("after_selection"), 3)
	session.rules = MwPlain.dict(r.get("rules")).duplicate()
	var ct := MwPlain.dict(r.get("custom_teams"))
	if not ct.is_empty():
		session.custom_teams = ct.duplicate(true)
		session.playoffs.custom = MwPlain.num(ct.get("playoff"), -1)
	var pl := MwPlain.dict(r.get("players"))
	session.humans = MwHumans.from_record(MwPlain.dict(MwPlain.ints_from_json(pl.get("humans"))))
	for p in MwPlain.array(pl.get("out")):
		session.humans.out[MwPlain.num(p)] = true
	session.pad_map = MwPlain.ints(pl.get("pad_map", [1, 2, 3, 4]))
	session.layouts = {}
	var lay := MwPlain.dict(pl.get("layouts"))
	for k in lay:
		session.layouts[MwPlain.num(k)] = MwPlain.text(lay[k])
	var on := MwPlain.dict(r.get("online"))
	if not on.is_empty():
		var players := []
		for p in MwPlain.array(on.get("players")):
			players.append(MwPlain.num(p))
		players.sort()
		var machines := {}
		var ms := MwPlain.dict(on.get("machines"))
		for k in ms:
			machines[str(MwPlain.num(k))] = MwPlain.num(ms[k])
		session.online = {"players": players, "machines": machines}
		if on.has("stamped"):
			# plan 43: the host merges input at its stamps
			session.online["stamped"] = 1 if MwPlain.flag(on.get("stamped")) else 0
	return session


## Plan 35 work item 4: this session reset from start record [param r] in
## place, as every machine of an online match starts its game - everything
## the record holds ([method from_record]), the screens' keepsakes gone;
## what is this machine's own stays (the view, [member machine], and
## whatever the online pages keep here).
func reset_from_record(r: Dictionary) -> void:
	var session := from_record(r)
	for k: String in RECORD_FIELDS:
		set(k, session.get(k))
	if screens.get("rink") is MwRinkState:
		(screens["rink"] as MwRinkState).retire()   # plan 45: the last match's state let go of
	screens = {}
	menu_stars = []
	lineup_teams = []
	_saved = null


## Plan 35 work item 4: the machine player [param player] plays on in the
## online match (-1: not in it, or a local game).
func machine_of(player: int) -> int:
	var ms: Dictionary = online.get("machines", {})
	return int(ms.get(str(player), -1))


## Plan 35 work item 4: the online match's players (empty: a local game).
func online_players() -> Array:
	return online.get("players", [])


## The record's first screen and tick ([method to_record]).
static func record_screen(r: Dictionary) -> int:
	return int(r.get("screen", 1))


## The record [param r]'s tick: the one its game starts at ([method to_record]).
static func record_tick(r: Dictionary) -> int:
	return int(r.get("tick", 0))


static func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out
