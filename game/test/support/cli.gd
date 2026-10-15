extends RefCounted
## Plan 40 (T9): what the check runners (SceneTree scripts: live_match,
## picture_check, net_determinism ...) share - their command line, the repo
## folder.


## The arguments after `--` as {"name": value} for every "--name value"
## pair (anything else skipped).
static func args() -> Dictionary:
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


## [param rel] (a path in the repository) as an absolute path.
static func repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel).simplify_path()
