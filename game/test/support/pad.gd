extends MwInputSource
## Plan 40 (T3): the screen tests' pad - the actions held this tick, as the
## router samples them (MwInputSource.sample). The tests had 15 copies of it.

var held := {}


func sample(_contexts: Array) -> Dictionary:
	return held.duplicate()
