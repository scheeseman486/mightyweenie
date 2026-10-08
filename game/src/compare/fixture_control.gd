class_name MwFixtureControl
extends RefCounted
## CPU thinks and tick reads for one pass of the simulation fixtures
## (compare/fixtures/sim_passes.json; MwReplayControl's job without the
## recording): each recorded think as the state fields it changed, the tick
## the original read at each player's update, at each tick site and at the
## puck update.

var _paths: Array = []
var _thinks: Array = []      ## [team, index, [[path index, value], ...]]
var _ent: Array = []
var _ent_at := 0
var _tk: Array = []
var _tk_at := 0
var _pk: Variant = null
## What did not line up ("T0 P2: no recorded think", ...).
var notes: Array[String] = []


## [param paths]: the fixture's path list; [param entry]: one of its passes.
func _init(paths: Array, entry: Dictionary) -> void:
	_paths = paths
	_thinks = (entry.get("thinks", []) as Array).duplicate()
	_ent = entry.get("ent", [])
	_tk = entry.get("tk", [])
	_pk = entry.get("pk")


## Leaf changes [param pairs] ([[path index, value], ...]) as {path: value}.
static func changes(paths: Array, pairs: Array) -> Dictionary:
	var out := {}
	for c in pairs:
		out[paths[int(c[0])]] = c[1]
	return out


func think(sim: MwRinkSim, p: MwRinkState.Player, _team: MwRinkState.Team, _other: MwRinkState.Team) -> void:
	for i in _thinks.size():
		var t: Array = _thinks[i]
		if int(t[0]) == p.team and int(t[1]) == p.index:
			_thinks.remove_at(i)
			MwSimDict.patch(sim.s, changes(_paths, t[2]))
			return
	notes.append("T%d P%d: no recorded think" % [p.team, p.index])


func before_player(sim: MwRinkSim, p: MwRinkState.Player) -> void:
	if _ent_at < _ent.size():
		sim.s.tick = int(_ent[_ent_at])
		_ent_at += 1
	else:
		notes.append("T%d P%d: no entry tick" % [p.team, p.index])


func tick_at(sim: MwRinkSim, tag: int) -> void:
	while _tk_at < _tk.size():
		var e: Array = _tk[_tk_at]
		_tk_at += 1
		if int(e[0]) == tag:
			sim.s.tick = int(e[1])
			return
	notes.append("tick site %d: none recorded" % tag)


func before_puck(sim: MwRinkSim) -> void:
	if _pk != null:
		sim.s.tick = int(_pk)
