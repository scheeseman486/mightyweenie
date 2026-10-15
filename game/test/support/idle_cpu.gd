extends RefCounted
## Plan 40 (T4): CPU players that stay put - for the tests about human
## control, the rules and the screens (the AI has its own checks:
## `tools/bin/sim-check --think`, `--ai`). MwRinkSim.cpu is called without a
## null check, so a test without the AI needs one; the tests had 15 copies.


func think(_sim: MwRinkSim, _p: MwRinkState.Player, _team: MwRinkState.Team, _other: MwRinkState.Team) -> void:
	pass
