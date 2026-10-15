class_name MwNetHash
extends RefCounted
## The hashes that prove two machines run the same game (plan 35, docs/net.md):
## the rink's state every pass ([method rink]: MwSimDict's form of it plus
## the port's layers MwSimDict leaves out - the control layer, the sticks,
## the crowd noise the driver is sent) and the session at every screen
## change ([method session]: its start record's form). Integer data only,
## serialised with Godot's own binary encoding and digested with SHA-256:
## the same bytes, and so the same hash, on every machine.


## Rink state [param s]'s hash.
static func rink(s: MwRinkState) -> int:
	return digest(rink_dict(s), false)


## What [method rink] hashes: MwSimDict's form of [param s] and the port's
## layers (plan 35 work item 4 keeps its bytes for desync dumps).
static func rink_dict(s: MwRinkState) -> Dictionary:
	var d := MwSimDict.to_dict(s)
	d["port"] = port_layers(s)
	return d


## The HASHED port fields (MwRinkState.PORT_FIELDS, plan 40) and their
## keys in [method port_layers] (test_port_fields: one each).
const PORT_KEYS := {"control": "control", "pad_sticks": "sticks", "pad_heights": "heights",
		"crowd_life": "crowd", "pace": "pace"}


## What of [param s] MwSimDict leaves out but the game's course reads:
## the control layer's seats (owners, captains, who is away, their menus),
## the pads' sticks and shot heights (MwSettings.shot_heights), the crowd's
## noise level (it reaches the sound driver, whose answers the game waits
## on), the rink's pass pacer (plan 36's TICK RATE: when the next passes
## come; none with OVERCLOCKED).
static func port_layers(s: MwRinkState) -> Dictionary:
	var out := {}
	var control := s.control
	if control != null:
		var seats := []
		for seat in control.seats:
			seats.append([seat.player, seat.team, seat.pad, seat.slot, seat.own, seat.out, seat.back,
					seat.last, seat.taps, seat.tap, _plain(seat.menu), seat.net])
		out["control"] = [seats, control.owned, control.extended, control.captain_mode, control.voted.duplicate(),
				control.captains.duplicate(), _plain(control.requests), _plain(control.net_status),
				Array(control.kicks),
				Array(control.leaving)]
	var sticks := []
	for v in s.pad_sticks:
		sticks.append([v.x, v.y])
	out["sticks"] = sticks
	out["heights"] = Array(s.pad_heights)
	if s.crowd_life != null:
		out["crowd"] = [s.crowd_life.crowd_seed, s.crowd_life.ticks,
				MwCrowdLife.sound_level(s.crowd_life.snapshot())]
	if not s.pace.is_empty():
		out["pace"] = Array(s.pace)          # plan 36: when the next passes come (TICK RATE)
	return out


## Session [param game_session]'s hash: its start record without the screen and tick
## (MwSession.to_record).
static func session(game_session: MwSession) -> int:
	var r := game_session.to_record()
	r.erase("screen")
	r.erase("tick")
	return digest(r)


## [param v]'s digest: its plain form (floats from JSON as ints, packed
## arrays as arrays, keys as strings in sorted order - unless [param plain]
## says it is already canonical) serialised and SHA-256'd, the first 63 bits.
static func digest(v: Variant, plain_ := true) -> int:
	return digest_bytes(var_to_bytes(_plain(v) if plain_ else v))


## The digest of bytes already serialised ([method digest]'s second half).
static func digest_bytes(b: PackedByteArray) -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	var h := ctx.finish()
	var x := 0
	for i in 8:
		x = (x << 8) | h[i]
	return x & 0x7FFFFFFFFFFFFFFF


## [param v] in the plain form the digests take (floats as ints, packed
## arrays as arrays, dictionaries with sorted string keys).
static func plain(v: Variant) -> Variant:
	return _plain(v)


static func _plain(v: Variant) -> Variant:
	if v is float:
		return int(v)
	if v is Array:
		var a := []
		for x in v:
			a.append(_plain(x))
		return a
	if v is PackedInt32Array or v is PackedByteArray or v is PackedInt64Array:
		return Array(v)
	if v is Dictionary:
		var keys := []
		for k in v:
			keys.append(str(k))
		keys.sort()                          # one order, whatever order it was built in (JSON sorts)
		var d := {}
		for k in keys:
			d[k] = _plain(v[k] if (v as Dictionary).has(k) else v[int(k)])
		return d
	return v
