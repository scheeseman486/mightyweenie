class_name MwSelection
extends RefCounted
## The selection steps between the controller selection (110) and the match
## (plan 34 section 7; owner, 2026-10-09: the players choose their
## characters, the captain may change them or skip), each only when it
## applies:
##
## 1. **Character selection** (111, [method character_select]): more than 4
##    players on teams; with CHARACTER SELECT at 3+ ON A TEAM
##    ([member MwSettings.character_select]) also a team with 3 or 4 players
##    when there are 4 or fewer in all. Each player picks a position (their
##    own: [member MwHumans.positions]) and, with line-ups on, the character
##    to play it. Otherwise nobody owns a position - the original's co-op.
## 2. **The captain vote** ([method captain_mode]: a local playoff game with
##    at least CAPTAIN MODE's number of players on teams; never a local
##    exhibition; online always - plan 35): on 111 after the picks, or its own screen (112) without
##    character selection. A team with one player has them as captain; a
##    captain still on the team keeps it (the captaincy is the player's).
## 3. **The line-up panels** ([method lineups_on]: Reserves on and LINE-UP
##    SELECT on): the captain - or the team's one player, or all its players
##    - reviews the line-up, changes it or keeps it (DONE). Over 111 or 112,
##    or over the starfield of their own (113) when neither came before.
##    Back on a panel that isn't READY: the controller selection again.
## 4. The match ([member MwSession.after_selection]): [method finish] gives
##    the setup the line-ups to make at the rink's entry
##    ([member MwMatchSetup.lineups], [method MwLineup.apply]).
##
## 111, 112 and 113 are one scene ([MwCharacterSelect]): it runs the steps
## that apply from its entry on and fades out to the match.
## Short names: h the players' set-up (MwHumans).

## The entry steps by screen.
const STEPS := {MwScreens.CHARACTER_SELECT: "characters", MwScreens.CAPTAIN_VOTE: "vote",
		MwScreens.LINEUPS: "lineups"}


## True when [param h]'s players pick their positions and characters (111).
static func character_select(h: MwHumans) -> bool:
	if h.total() > 4:
		return true
	if MwSettings.character_select != MwSettings.CHARACTER_SELECTS[1]:
		return false
	return h.count(0) >= 3 or h.count(1) >= 3         # 3 or 4 on a team, 4 or fewer in all


## True when the match has captains: a local playoff game with at least
## CAPTAIN MODE's number of players on teams (5, or 2 at 2+ PLAYERS); a
## local exhibition never (online play, plan 35, always).
static func captain_mode(session: MwSession) -> bool:
	if MwFlow.online(session):
		return true                                    # plan 35 (owner): online, captains always
	if session == null or not MwFlow.port_playoffs(session):
		return false
	var least := 2 if MwSettings.captain_mode == MwSettings.CAPTAIN_MODES[1] else 5
	return session.humans.total() >= least


## True when the line-ups are chosen before the match: Reserves on and
## LINE-UP SELECT on.
static func lineups_on(session: MwSession) -> bool:
	return session != null and session.setup.reserves != 0 and MwSettings.lineup_select


## The teams that vote for a captain: in captain mode, those with two or
## more players and no captain among them.
static func voting_teams(session: MwSession) -> Array[int]:
	var out: Array[int] = []
	if not captain_mode(session):
		return out
	var h := session.humans
	for t in 2:
		if h.count(t) >= 2 and not h.captain_of(t) in h.teams[t]:
			out.append(t)
	return out


## The teams with a line-up panel: line-ups on, the teams with players.
static func panel_teams(session: MwSession) -> Array[int]:
	var out: Array[int] = []
	if not lineups_on(session):
		return out
	for t in 2:
		if session.humans.count(t) > 0:
			out.append(t)
	return out


## The controller selection is done: the players' positions, captains and
## line-ups made to fit what applies (no character selection: nobody owns a
## position; no captain mode: no captains, a team's one player its captain
## in it; line-ups off: the original's starters), and the first step's
## screen - 111, 112, 113 - or, when none applies, [method finish]'s.
static func begin(session: MwSession) -> int:
	var h := session.humans
	var picks := character_select(h)
	if not picks:
		h.positions.clear()
	if captain_mode(session):
		for t in 2:
			if h.count(t) == 1:
				h.captains[t] = h.teams[t][0]
			elif not h.captain_of(t) in h.teams[t]:
				h.captains[t] = 0
	else:
		h.captains = [0, 0]
	if not lineups_on(session):
		h.lineups = [PackedInt32Array(), PackedInt32Array()]
	for t in 2:
		if h.count(t) == 0:
			h.lineups[t] = PackedInt32Array()         # a team without players: the original's
	if picks:
		return MwScreens.CHARACTER_SELECT
	if not voting_teams(session).is_empty():
		return MwScreens.CAPTAIN_VOTE
	if not panel_teams(session).is_empty():
		return MwScreens.LINEUPS
	return finish(session)


## The steps are over: the teams the line-ups were chosen for remembered;
## returns where the match goes on ([member MwSession.after_selection]: the
## matchup). (The line-ups themselves stay the players' own until the rink's
## entry: [method for_the_rink].)
static func finish(session: MwSession) -> int:
	session.lineup_teams = [session.setup.team_a, session.setup.team_b]
	return session.after_selection


## The line-ups the rink's entry makes (MwLineup.apply): the players'
## ([member MwHumans.lineups]) when line-ups are on and a team's is whole,
## else none (the original's starters).
static func chosen_lineups(session: MwSession) -> Array:
	if not lineups_on(session):
		return []
	var h := session.humans
	if h.lineups[0].size() == MwHumans.POSITIONS.size() or h.lineups[1].size() == MwHumans.POSITIONS.size():
		return [h.lineups[0].duplicate(), h.lineups[1].duplicate()]
	return []


## Plan 40 (S13, owner: a clean-up): the match's setup as the rink's
## entry - and its rehearsals, the match's opening's and the character
## selection's - plays it: [param su] (the session's own by default) given
## the players' match pads (an extended set-up's, MwHumans.match_pads) and
## the line-ups chosen ([method chosen_lineups]). The players hold both;
## they are worked out from them here, at the rink's door, and carried
## nowhere else (the start record has the players). Returns [param su].
static func for_the_rink(session: MwSession, su: MwMatchSetup = null) -> MwMatchSetup:
	if su == null:
		su = session.setup
	su.extended = session.humans.match_pads()
	su.lineups = chosen_lineups(session)
	return su
