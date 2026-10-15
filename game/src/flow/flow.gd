class_name MwFlow
extends RefCounted
## The port's way through its menus to a match (plan 34): which screen comes
## after which. Screens ask here instead of naming the next one, so the
## steps between the game options and the matchup (controller selection,
## character selection, the captain vote, the line-ups) live in one place.
##
## Online (plan 35 work item 4, [method online]): every machine runs the
## same exhibition from the start record and the stream - the game options
## (the host's P1 drives them), the controller selection (every player of
## the lobby), the selection steps (captains always), the match, back to the
## game options; Back from the game options takes everyone to the lobby
## ([constant ONLINE_LOBBY], where MwNetMatch hands the router back).

## Plan 35's port pages (work item 3's): ONLINE MULTIPLAYER and the LOBBY.
const ONLINE_MENU := 119
const ONLINE_LOBBY := 122


## True in an online match (plan 35: the start record's player table).
static func online(session: MwSession) -> bool:
	return session != null and not session.online.is_empty()


## After the game options' PLAY GAME: [param new_run] - the playoffs' first
## game (the new run's bracket comes first, as the original's Start led to
## it). Exhibitions and a run's next game go on to the match.
static func after_options(session: MwSession, new_run: bool) -> int:
	return 11 if new_run else before_match(session)


## The steps before a match (plan 34): the controller selection (110), then
## the character selection, the captain vote, the line-ups (MwSelection);
## then the matchup. A player still out (QUIT GAME) when the last game
## ended starts the selection in the middle (MwRinkControl.out_to_middle).
static func before_match(session: MwSession) -> int:
	if session != null:
		session.after_selection = 3
		MwRinkControl.out_to_middle(session.humans)
	return MwScreens.CONTROLLER_SELECT


## Where the controller selection goes on to: the selection steps that apply
## (character selection 111, the captain vote 112, the line-up panels 113;
## MwSelection), else the match ([member MwSession.after_selection]).
static func after_controllers(session: MwSession) -> int:
	return MwSelection.begin(session) if session != null else 3


## True in the port's playoffs (plan 34: the front menu's flow).
static func port_playoffs(session: MwSession) -> bool:
	return session != null and session.local_mode == "playoffs" and MwSettings.front_menu


## After the bracket's Start: back to the game options after a game (SAVE
## GAME offered there, then the next game), else on to the match.
static func after_bracket(session: MwSession, after_game: bool) -> int:
	return 1 if after_game else before_match(session)


## After LOAD GAME took a save: the bracket of the loaded run (without the
## password screen).
static func after_load(_session: MwSession) -> int:
	return 11


## The run is over (champion, eliminated, or left): LOCAL PLAY.
static func end_run(session: MwSession) -> int:
	session.end_run()
	return MwScreens.LOCAL_PLAY
