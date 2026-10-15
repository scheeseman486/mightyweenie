extends GutHookScript
## Before every GUT run (.gutconfig.json's pre_run_script): every file the
## game writes for the player goes to a test folder of its own under
## [constant ROOT], emptied first, so a run (an attract demo played to its
## end, a match saved, a team saved, an option changed, an online test)
## never touches the player's own (plan 40, T5). A test that points one
## elsewhere puts back the value it found (never the game's constant). The
## load cache (MwCache.root) stays: derived data, keyed by version.

const ROOT := "user://test"
const DIRS := {"replays": "user://test/replays", "saves": "user://test/saves", "teams": "user://test/teams",
		"net": "user://test/net"}


func run() -> void:
	for d in DIRS.values():
		_empty(d)
	MwReplayFile.dir = DIRS["replays"]
	MwPlayoffSave.dir = DIRS["saves"]
	MwCustomTeams.dir = DIRS["teams"]
	MwNetIdentity.dir = DIRS["net"]
	MwNetKnownHosts.path = DIRS["net"].path_join("known_hosts.cfg")
	MwNetRejoin.path = DIRS["net"].path_join("rejoin.cfg")
	MwSettings.path = ROOT.path_join("settings.cfg")
	if FileAccess.file_exists(MwSettings.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))


static func _empty(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
