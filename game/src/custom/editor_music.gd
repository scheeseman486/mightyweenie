class_name MwEditorMusic
extends RefCounted
## CREATE-A-TEAM's music (plan 38): the team description's crowd sequence
## going on between the editor's screens (the list and its pages, the text
## entry, the rink editor), stopped once the editor is left. Plan 40 (I6):
## its own place - it was a scene's static (MwCreateTeam) the other screens
## reached into.

## The editor's music: the team description's crowd sequence.
const MUSIC := MwTeamDescription.SOUND_CROWD
## The editor's screens: its music goes on between them.
const EDITOR_SCREENS: Array[int] = [MwScreens.CREATE_A_TEAM, MwScreens.TEXT_ENTRY, MwScreens.EDIT_TEAM,
		MwScreens.HOME_RINK]

## The editor's music plays ([method enter] to [method leave]).
static var on := false
static var _handle := MwSound.NONE


## Entering one of the editor's screens: from outside the editor, the
## menus' music stops (`$C768`, as the team description's entry); its
## crowd sequence comes from the passes ([method keep_up]).
static func enter() -> void:
	if on:
		return
	on = true
	_handle = MwSound.NONE
	MwSound.music_fade_out(1)


## Every pass of the editor's screens: the crowd sequence keeps going
## (`$C7C2`: played again whenever it isn't playing). Nothing while the
## editor's music is off.
static func keep_up() -> void:
	if on and not MwSound.busy(_handle):
		_handle = MwSound.play(MUSIC)


## The editor left for a screen of its own ([param to]) or another: the
## music stops for another (the front menu's comes back as it enters).
static func leave(to: int) -> void:
	if not on or to in EDITOR_SCREENS:
		return
	on = false
	MwSound.stop(_handle)
	_handle = MwSound.NONE
