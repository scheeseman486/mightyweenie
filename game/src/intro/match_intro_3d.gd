class_name MwMatchIntro3D
extends RefCounted
## The match's opening in 3D (plan 33, docs/rink3d.md, The match's opening):
## what the matchup (screen 3, MwMatchup) shows in a 3D view, through the
## Router's 3D view (MwRink3DHost) - the rink as the match will start it
## (MwMatchRehearsal: its nets, lamps and hazards), the crowd lively and
## chanting with the matchup's crowd sound (MwCrowdLife, MwChant), the
## players coming out and showing off (MwIntroCast), filmed by the cinematic
## camera's director for the intro (MwIntroDirector3D); a press lines them up
## and the camera glides to the match's view, and [method done] when the rink
## can take over without a cut. Presentation only: the session is read, never
## written (its random numbers above all); the intro's choices come from a
## seed of its own, which the match's crowd keeps ([member life]).
## Plan 35: with no view (null: this machine draws the opening in 2D) the
## model runs alone - the cast, the director's clock, the crowd - so
## [method done] comes at the same tick on every machine.

## How lively the crowd is while it chants (MwCrowdLife's level: the game's
## crowd level after a shot).
const LIFE_LEVEL := 300

var rehearsal: MwMatchRehearsal
var cast: MwIntroCast
var director: MwIntroDirector3D
var chant: MwChant
## The crowd's life, handed to the rink at the end (its seed the match's).
var life: MwCrowdLife
## The arena's paint (plan 37, from the crowd's seed; null: off): the ice's
## splotches already there in the opening, handed to the rink with the life.
var splat: MwSplatter
var view: MwRinkView3D
## Ticks since the intro began.
var ticks := 0
var _bars := 0                  # times the chant has started
var _old_director: MwRinkDirector3D
var _match_mode := 0
var _presented := false
var _scenery: Array = []


## The intro of the match [param session] is about to start (its setup, its
## main random stream as it is now, its playoffs), seen through [param view_]
## (the borrowed view, [param view_size] its picture), ending on the camera
## of [param match_mode] (MwRinkCamera3D.Mode, the match's view); its own
## choices from [param seed_].
func _init(rom: PackedByteArray, session: MwSession, view_: MwRinkView3D, match_mode: int, view_size: Vector2,
		seed_: int) -> void:
	rehearsal = MwMatchRehearsal.run(rom, MwSelection.for_the_rink(session, session.setup.copy()),
			session.rng.state, session.playoffs)
	life = MwCrowdLife.new(seed_)
	if MwSettings.splatter:
		splat = MwSplatter.new(MwSplatter.seed_for(session.attract, life.crowd_seed))
	cast = MwIntroCast.new(rom, rehearsal, life.crowd_seed)
	cast.settled = _settled(rom)
	chant = MwChant.new(rom)
	director = MwIntroDirector3D.new(seed_)
	director.cast = cast
	director.aspect = view_size.x / maxf(view_size.y, 1.0)
	var shown := Vector2(rehearsal.state.camera.shown)
	_match_mode = match_mode
	director.final = MwIntroDirector3D.match_view(match_mode, shown,
			MwRinkShot3D.make(rehearsal.state, rehearsal.draw.items, shown), view_size)
	_scenery = rehearsal.scenery()
	if view_ == null:
		return                                  # plan 35: the model only (drawn in 2D)
	view_.sprite_layers(view_.layers_now())
	view_.sprites.prepare(rehearsal.draw.items)     # the match's first frame made now, under the fade in
	view = view_
	_old_director = view_.camera.director
	view_.camera.director = director
	view_.set_camera_mode(MwRinkCamera3D.Mode.CINEMATIC)


## Each player in his place as the rink's first frame shows him (MwIntroCast
## .settled): a starter's frames from the rehearsal's draw (his subject's:
## body, shadow, markers), a reserve's bench figure from its benches.
func _settled(rom: PackedByteArray) -> Dictionary:
	var out := {}
	for st: Dictionary in rehearsal.starters():
		var subject := String(st["key"]).trim_suffix("body")      # "t<team>.p<n>.<record>/"
		var its := []
		for it: Dictionary in rehearsal.draw.items:
			if String(it.get("key", "")).begins_with(subject) and int(it["place"]) != MwRinkDraw3D.SCREEN:
				its.append(it)
		out[Vector2i(st["team"], st["slot"])] = its
	for it: Dictionary in MwBench3D.items(rehearsal.bench, rom):
		var parts := String(it["key"]).trim_prefix("bench.t").split("/")[0].split(".s")
		if parts.size() == 2:
			out[Vector2i(int(parts[0]), int(parts[1]))] = [it]
	return out


## The view given back (no chant): the cinematic camera's own director, or
## for a cinematic match a fresh one, whose first shot the line-up ended on
## (MwIntroDirector3D.match_view).
func detach() -> void:
	if view == null:
		return
	var cinematic := _match_mode == MwRinkCamera3D.Mode.CINEMATIC
	view.camera.director = MwRinkDirector3D.new() if cinematic else _old_director
	view.stands.chant(-1.0)
	view = null


## A pass of [param e] ticks: the players, the crowd, the frame shown.
func step(e: int) -> void:
	ticks += e
	director.clock = seconds()
	cast.step(e)
	life.step(e, LIFE_LEVEL, Vector2i.ZERO, false)
	if view == null:
		return
	var f := {"items": _scenery + cast.items(), "shot": null, "shown": Vector2(rehearsal.state.camera.shown),
			"clock": seconds(), "chant": chant, "chant_first": _bars <= 1}
	f.merge(MwMatchModels.frame_parts(life, null, splat, false))
	view.present_frame(f, {}, _presented)
	_presented = true
	view.pass_shown(e)


## The chant's sound started (again) now.
func chant_started() -> void:
	chant.start(seconds())
	_bars += 1


## The intro's clock (s).
func seconds() -> float:
	return ticks / float(MwRouter.TICK_HZ)


## The press: the players to their places, the camera to the match's view,
## the chant's bar the last.
func line_up() -> void:
	cast.line_up()
	director.begin_hand_over()
	chant.last = true


## The crowd noise's level as the match will start it (MwRinkUpdate
## .noise_level: the game's crowd level, or this crowd's life's).
func noise_level() -> int:
	return MwRinkUpdate.noise_level(rehearsal.state.crowd, life)


## Everyone in place and the camera the match's: the rink can take over.
func done() -> bool:
	return cast.lined_up() and director.handed_over()
