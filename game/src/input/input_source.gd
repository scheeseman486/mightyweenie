class_name MwInputSource
extends RefCounted
## Where a pass's input comes from. [method sample] returns the actions held
## right now (action -> true); the router turns successive samples into
## [MwInputFrame]s. [method tick] runs every 60 Hz tick and [method taps]
## returns presses since the last sample that a sample alone would miss (a
## quick press and release between two passes) - the original keeps such
## "newly pressed" bits until a pass reads them. [method sticks]: the
## analogue sticks at the latest sample (plan 22); [method heights]: the
## shot heights held then (MwSettings.shot_heights). Subclasses:
## [MwLiveInput], [MwScriptedInput].


## The actions held right now (action -> true) under [param _contexts], the input contexts of
## the screen on top ([method MwRouter.contexts]). This default: none.
func sample(_contexts: Array) -> Dictionary:
	return {}


## Called every 60 Hz tick, between samples (a live source notes the presses [method taps]
## gives). This default: nothing.
func tick() -> void:
	pass


## Actions newly pressed since the previous sample (cleared by reading).
func taps() -> Dictionary:
	return {}


## Players 1-4's analogue sticks at the latest sample (Vector2i, each axis
## -256..256, x right, y down; ZERO: none - the D-pad as the original), or
## empty: no sticks at all (scripted input).
func sticks() -> Array:
	return []


## Players 1-12's shot heights at the latest sample (MwSettings.shot_heights:
## 0 none - the middle height -, 1 HIGH SHOT, 2 LOW SHOT - the original's
## lift entries for no direction, Up and Down -; -1 a player whose D-pad
## lifts the shot, as the original's), or empty: the D-pad's for everyone
## (the option off, scripted input). Plan 35: the input stream carries them
## (MwTickInput.heights), as the player's machine sampled them.
func heights() -> Array:
	return []


## Plan 35: the sticks of the latest sample as [MwStick] codes, players 1-12
## (empty: none). A source that quantises its sticks gives the codes it
## decoded them from; this default encodes [method sticks].
func stick_codes() -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in sticks():
		out.append(MwStick.encode(v))
	return out


## Plan 40 (S7): the tick as the wire has it (every player's state:
## MwTickInput.states) when the source plays a stream; null otherwise.
func tick_input() -> MwTickInput:
	return null


## Plan 35: the players whose machine is away online (player -> status,
## MwTickInput.LAGGING ...) at the latest sample; empty offline.
func away() -> Dictionary:
	return {}
