class_name MwReplayControl
extends RefCounted
## CPU thinks replayed from a simulation recording (comparison layer, plan
## 08): where the original runs the AI (`$3BFE`) and the avoidance (`$8820`)
## for a CPU player, apply what they changed in the original's RAM (the
## bytes that differ between the snapshots before and after them: the
## player's target, state starts, velocity halving, the puck's receiver, the
## RNG...). Also the hooks MwRinkSim calls before each player and before the
## puck: the tick the original read there (the VBlank interrupt moves it
## during the segment), and a record of where our state first differs from
## the original's at a player's start (`$86A` entry log).

const ENT_A5 := 0
const ENT_TICK := 11

var rom: PackedByteArray
var rec: MwSimRecording
var k := 0
var _ent: Array = []
var _ent_at := 0
var _thinks: Array = []      ## [a5, pre index, post index]
var _pk: Array = []
var _tk: Array = []
var _tk_at := 0
## Notes on where we first went wrong: "T0 P2 at entry: x ..." (first few).
var notes: Array[String] = []


func _init(rom_: PackedByteArray, rec_: MwSimRecording, k_: int) -> void:
	rom = rom_
	rec = rec_
	k = k_
	_ent = rec.log_entries("ent", k)
	_pk = rec.log_entries("pk", k)
	_tk = rec.log_entries("tk", k)
	var ai: Array = rec.passes[k]["ai"]
	var i := 0
	while i + 1 < ai.size():
		_thinks.append([int(ai[i][1]), int(ai[i][2]), int(ai[i + 1][2])])
		i += 2


## The original's think for [param p] this pass, applied to the state.
func think(sim: MwRinkSim, p: MwRinkState.Player, _team: MwRinkState.Team, _other: MwRinkState.Team) -> void:
	var a := MwRinkRam.player_address(p.team, p.index)
	for i in _thinks.size():
		var t: Array = _thinks[i]
		if t[0] != a:
			continue
		_thinks.remove_at(i)
		MwRinkRam.patch(rom, sim.s, rec.ai(t[1]), rec.ai(t[2]))
		return
	_note("T%d P%d: no recorded think" % [p.team, p.index])


## MwRinkSim's hook before player [param p]: the tick the original read there (the `$86A`
## entry log), and a note where our state first differs from the original's.
func before_player(sim: MwRinkSim, p: MwRinkState.Player) -> void:
	if _ent_at >= _ent.size():
		_note("T%d P%d: no entry log" % [p.team, p.index])
		return
	var entry: Array = _ent[_ent_at]
	_ent_at += 1
	var a := MwRinkRam.player_address(p.team, p.index)
	if int(entry[ENT_A5]) & 0xFFFFFF != a:
		_note("entry %d: original updates $%06X, we T%d P%d"
				% [_ent_at - 1, int(entry[ENT_A5]) & 0xFFFFFF, p.team, p.index])
		return
	sim.s.tick = int(entry[ENT_TICK])
	var motion := p.motion
	var got := [motion.pos[0], _w2(motion.vel[0], motion.acc[0]), motion.pos[1], _w2(motion.vel[1], motion.acc[1]),
			motion.pos[2], _w2(motion.vel[2], motion.acc[2]),
			((p.anim.position & 0xFFFF) << 16) | (p.anim.frame << 8) | 0,
			(p.state << 24) | (p.substate << 16) | (p.attacker << 8) | p.angle, sim.s.rng.state]
	var want := [entry[2], entry[3], entry[4], entry[5], entry[6], entry[7], entry[8], entry[9], entry[10]]
	var what := ["x", "vx|ax", "y", "vy|ay", "z", "vz|az", "anim pos", "state", "rng"]
	for i in got.size():
		var g := int(got[i]) & 0xFFFFFFFF
		var w := int(want[i]) & 0xFFFFFFFF
		if i == 6:
			g &= 0xFFFFFF00
			w &= 0xFFFFFF00
		if g != w:
			_note("T%d P%d at entry: %s ours %08X want %08X" % [p.team, p.index, what[i], g, w])
			break


## The tick the original read at site [param tag] (the "tk" log, in order).
func tick_at(sim: MwRinkSim, tag: int) -> void:
	while _tk_at < _tk.size():
		var tick_read: Array = _tk[_tk_at]
		_tk_at += 1
		if int(tick_read[0]) == tag:
			sim.s.tick = int(tick_read[1])
			return
		_note("tick site %d expected, the original read at %d" % [tag, int(tick_read[0])])
	_note("tick site %d: none recorded" % tag)


## MwRinkSim's hook before the puck: the tick the original read there (the "pk" log).
func before_puck(sim: MwRinkSim) -> void:
	if not _pk.is_empty():
		sim.s.tick = int(_pk[0][1])


static func _w2(hi: int, lo: int) -> int:
	return ((hi & 0xFFFF) << 16) | (lo & 0xFFFF)


func _note(t: String) -> void:
	if notes.size() < 4:
		notes.append(t)
