class_name MwGameStart
extends RefCounted
## Plan 40 (S5): a game started from a start record, and the match context
## it runs in, in one place - every machine of an online match starts so
## (MwNetMatch), and so do the determinism proof's recording and replay
## (net_proof.gd) and the resync tests, so they check the game's own path,
## not a copy of it:
## * [method use_context] / [method own_context]: the record's custom teams
##   in use and its match rules in force (plans 38, 35), and this machine's
##   own again;
## * [method begin] then [method enter_first]: the session reset from the
##   record, its context, the sound at power-on, the router afresh on the
##   record's tick and clock - the caller attaching the input and whatever
##   watches the game between the two - and the record's first screen;
## * [method take_up]: a game taken up from a resync snapshot, its context
##   in force.


## [param session]'s match context in force: its custom teams in use (none
## when they aren't teams: false) and its match rules.
static func use_context(session: MwSession) -> bool:
	var ok := MwCustomTeams.use_teams(session.custom_teams)
	if not ok:
		MwCustomTeams.use_teams({})
	MwSettings.use_match_rules(session.rules)
	return ok


## This machine's own match rules and custom teams again.
static func own_context() -> void:
	MwSettings.own_match_rules()
	MwCustomTeams.own_teams()


## The game of start record [param record] afresh on [param router]:
## [param session] reset from it in place (a machine's own fields kept,
## MwSession.OWN_FIELDS), its context in force ([method use_context]), the
## sound driver at power-on, the router's screens gone and its tick the
## record's, its pass clock [param clock] (an online match's: streamed from
## its input stream). Then the caller attaches the input and its watchers
## and calls [method enter_first].
static func begin(router: MwRouter, session: MwSession, record: Dictionary, clock: MwPassClock) -> void:
	session.reset_from_record(record)
	use_context(session)
	MwSound.reset()
	if router.audio != null:
		router.audio.lock()                        # (a pumped one's thread kept out)
		router.audio.reset()                       # the driver at power-on on every machine
		router.audio.unlock()
	if router.model != null:
		router.model.reset()                       # (plan 41: a client's game's own, beside what is heard)
	router.reset_game(session, clock, MwSession.record_tick(record))


## The record's first screen under a covered fader, fading in unless it
## fades itself in.
static func enter_first(router: MwRouter, record: Dictionary) -> MwScreen:
	var id := MwSession.record_screen(record)
	var first: MwScreen = router.factory.call(id)
	first.screen_id = id
	router.fader.cover()
	router.adopt(first)
	if not first.fades_in_itself:
		router.fader.fade_in(router.fade_ticks)
	return first


## The game taken up from resync snapshot [param d] on [param router]
## (MwNetSnapshot.restore: [param session] filled in place, the router at
## the snapshot's tick on [param stream]) with its context in force. The
## entry to resume ({request, previous}) or {} with [param errors] saying
## why.
static func take_up(router: MwRouter, session: MwSession, d: Dictionary, stream: MwInputStream,
		errors: PackedStringArray) -> Dictionary:
	var entry := MwNetSnapshot.restore(router, session, d, stream, errors)
	if entry.is_empty():
		return {}
	if not MwCustomTeams.use_teams(session.custom_teams):
		errors.append("its custom teams aren't teams")
		return {}
	MwSettings.use_match_rules(session.rules)
	return entry
