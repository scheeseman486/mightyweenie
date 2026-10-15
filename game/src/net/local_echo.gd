class_name MwLocalEcho
extends RefCounted
## Plan 41 (online feel), work item 1 - client-side menus: what a client's
## screens use to show this machine's players' menu presses at once, before
## the host's stream brings them back (docs/net.md "Client-side menus").
##
## The game every machine runs reads each press when the host's tick
## carrying it is run - a round trip and the buffer after it was made. A
## screen with per-player menus ([method MwScreen.predict_local]) shows its
## own model with this machine's not-yet-run presses applied by its own
## per-player handlers: it keeps a copy of the model ([method keep]), runs
## the presses ([method frame] makes each one's input; [method run] keeps
## the sound driver out of it), draws, and puts the model back. The next
## confirmed passes run the same presses for real; a press the game refuses
## (a position another player took meanwhile) is shown, then taken back.

## The switch: off, a client's screens show only what its game has run.
## `--no-local-echo` on the command line turns it off.
static var enabled := true
## Work item 3: the presses being predicted, player -> verb -> each one's
## [counter, due tick] (MwNetMatch.unconfirmed) - the key a press's sounds
## are heard under, once, and when its game will make them ([method frame]).
static var press_ids := {}
static var _framed := {}            # this run's: "player:verb" -> presses framed


static func _static_init() -> void:
	if "--no-local-echo" in OS.get_cmdline_user_args():
		enabled = false


## Every [MwInputFrame] a press runs on: player [param player]'s menu verb
## [param verb] newly pressed, nothing else held or pressed. Inside
## [method run] (the screens frame their presses in the order pressed), the
## sounds its handler makes are keyed by the press (MwSound.predict_key).
static func frame(player: int, verb: String) -> MwInputFrame:
	var input := MwInputFrame.new()
	input.pressed[MwVerbs.menu_action(player, verb)] = true
	var k := "%d:%s" % [player, verb]
	var n := int(_framed.get(k, 0))
	_framed[k] = n + 1
	var list: Array = (press_ids.get(player, {}) as Dictionary).get(verb, [])
	var id: Array = list[n] if n < list.size() else [-1 - n, -1]
	MwSound.predict_key = "echo:%s:%d" % [k, int(id[0])]
	MwSound.predict_due = int(id[1])
	return input


## [param what] called as a prediction: no sound call reaches the game's
## driver (MwSound.quiet: the game waits on its answers); work item 3 - on
## an online client they are heard at once, once a press (MwSound.predicting,
## MwHeard).
static func run(what: Callable) -> void:
	MwSound.begin_swap(false)                # plan 45 (D8): put back by MwSound.reset_swaps if this stops
	MwSound.quiet = true
	MwSound.predicting = true
	MwSound.predict_key = "echo"
	MwSound.predict_due = -1
	_framed = {}
	if MwSound.heard != null:
		MwSound.heard.begin_run()
	what.call()
	MwSound.end_swap()


## A copy of [param v] deep enough to put a model back: dictionaries and
## arrays copied all the way down, packed arrays by value, objects kept.
static func keep(v: Variant) -> Variant:
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v


## [param presses] (player -> verbs) for these players only.
static func of(presses: Dictionary, players: Array) -> Dictionary:
	var out := {}
	for p in presses:
		if int(p) in players:
			out[p] = presses[p]
	return out
