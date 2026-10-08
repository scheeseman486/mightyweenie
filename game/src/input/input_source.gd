class_name MwInputSource
extends RefCounted
## Where a pass's input comes from. [method sample] returns the actions held
## right now (action -> true); the router turns successive samples into
## [MwInputFrame]s. [method tick] runs every 60 Hz tick and [method taps]
## returns presses since the last sample that a sample alone would miss (a
## quick press and release between two passes) - the original keeps such
## "newly pressed" bits until a pass reads them. Subclasses: [MwLiveInput],
## [MwScriptedInput].


func sample(_contexts: Array) -> Dictionary:
	return {}


func tick() -> void:
	pass


## Actions newly pressed since the previous sample (cleared by reading).
func taps() -> Dictionary:
	return {}
