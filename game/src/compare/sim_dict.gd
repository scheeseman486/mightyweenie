class_name MwSimDict
extends RefCounted
## An [MwRinkState] as plain data (comparison layer, plan 08): every script
## variable of the state and the objects it owns, nested dictionaries and
## arrays of numbers, for the simulation fixtures (compare/fixtures/
## sim_passes.json; decoded fields only, no RAM images). References between
## objects (a punch's victim, the team's nearest skater, the puck's carrier
## and receiver, the camera's target, the special play's actor) are stored as the path of the object
## they point at ("teams/1/players/3", "referee").
##
## [method diff] lists the leaves that differ as {path: value}; [method
## patch] applies such a list to a state; [method leaves] flattens a
## dictionary (the fixtures store a state as values in the order of a path
## list).

## Properties holding a reference to an object owned elsewhere.
const REFS := ["victim", "nearest", "carrier", "receiver", "camera_target", "special_actor"]
## Computed properties (no storage), the replay ring's 32 KiB of data
## (`$FF0000`: outside the RAM snapshots; the ring's control fields stay)
## and its 3D side-store (plan 20: presentation), and the playoff run
## (MwPlayoffs: the session's, not the rink's).
const INTRINSIC := ["present", "ring_bytes", "side", "playoffs"]
## Plan 45 (M3): the most objects an owned array grows to from a form (an
## extended set-up's markers and a custom rink's hazard and object slots stay
## far below).
const GROW_MAX := 64
## What is left out, by name in every class: [constant INTRINSIC] and the
## rink state's port fields outside this form (plan 40, S1: MwRinkState
## .PORT_FIELDS - the control layer, the sticks, the paint ...: all but
## IN_DICT).
static var skipped: Array = _skip()


static func _skip() -> Array:
	var out := INTRINSIC.duplicate()
	for layer in [MwRinkState.Port.HASHED, MwRinkState.Port.CARRIED, MwRinkState.Port.LOCAL]:
		out.append_array(Array(MwRinkState.port_fields(layer)))
	return out


## [param s] as a dictionary.
static func to_dict(s: MwRinkState) -> Dictionary:
	var paths := {}
	_index(s, "", paths)
	return _encode(s, paths)


## A new state from [param d] (as [method to_dict] made it).
static func from_dict(d: Dictionary) -> MwRinkState:
	var s := MwRinkState.new()
	apply(s, d)
	return s


## Fill [param s] from [param d].
static func apply(s: MwRinkState, d: Dictionary) -> void:
	var refs: Array = []
	_decode(s, d, "", refs)
	_resolve(s, refs)


## The leaves of [param b] that differ from [param a]: {path: value}.
static func diff(a: Variant, b: Variant, path := "", out := {}) -> Dictionary:
	if a is Dictionary and b is Dictionary:
		for k in b:
			var text: String = k if path == "" else path + "/" + k
			diff(a.get(k), b[k], text, out)
	elif a is Array and b is Array and a.size() == b.size():
		for i in b.size():
			diff(a[i], b[i], "%s/%d" % [path, i], out)
	elif not _same(a, b):
		out[path] = b
	return out


## Apply leaf changes [param changes] ({path: value}) to [param s].
static func patch(s: MwRinkState, changes: Dictionary) -> void:
	var refs: Array = []
	for path in changes:
		var parts: PackedStringArray = (path as String).split("/")
		var owner: Variant = s
		var trail: Array = []                 # [container, key] up to the leaf's owner
		for i in parts.size() - 1:
			trail.append([owner, parts[i]])
			owner = _child(owner, parts[i])
		var key := parts[parts.size() - 1]
		if owner is Object and key in REFS:
			refs.append([owner, key, changes[path]])
			continue
		var value: Variant = changes[path]
		if owner is Object:
			(owner as Object).set(key, _cast((owner as Object).get(key), value))
		else:
			# a leaf in an array (packed arrays are values: write them back)
			var container: Variant = owner
			container[int(key)] = _cast(container[int(key)], value)
			for i in range(trail.size() - 1, -1, -1):
				var c: Variant = trail[i][0]
				var k: String = trail[i][1]
				if c is Object:
					(c as Object).set(k, container)
					break
				c[int(k)] = container
				container = c
	_resolve(s, refs)


## Every leaf of [param v] in order: {path: value}.
static func leaves(v: Variant, path := "", out := {}) -> Dictionary:
	if v is Dictionary:
		for k in v:
			leaves(v[k], k if path == "" else path + "/" + k, out)
	elif v is Array:
		for i in (v as Array).size():
			leaves(v[i], "%s/%d" % [path, i], out)
	else:
		out[path] = v
	return out


## Apply leaf changes to a dictionary made by [method to_dict] (in place).
static func patch_dict(d: Dictionary, changes: Dictionary) -> void:
	for path in changes:
		var parts: PackedStringArray = (path as String).split("/")
		var owner: Variant = d
		for i in parts.size() - 1:
			owner = owner[parts[i]] if owner is Dictionary else owner[int(parts[i])]
		var key := parts[parts.size() - 1]
		if owner is Dictionary:
			owner[key] = changes[path]
		else:
			owner[int(key)] = changes[path]


# --- internals ---------------------------------------------------------------------------------

## The script variables of [param o] that are kept (not [member skipped]),
## once per script (plan 35: the net hash reads a state every pass).
static func _props(o: Object) -> Array[String]:
	var script: Variant = o.get_script()
	if script != null and _prop_cache.has(script):
		return _prop_cache[script]
	var out: Array[String] = []
	for property in o.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and not (property["name"] in skipped):
			out.append(property["name"])
	if script != null:
		_prop_cache[script] = out
	return out


static var _prop_cache := {}


## Paths of the owned objects (references are not followed).
static func _index(v: Variant, path: String, paths: Dictionary) -> void:
	if v is Object:
		paths[(v as Object).get_instance_id()] = path
		for k in _props(v):
			if not (k in REFS):
				_index((v as Object).get(k), k if path == "" else path + "/" + k, paths)
	elif v is Array:
		for i in (v as Array).size():
			_index(v[i], "%s/%d" % [path, i], paths)


static func _encode(v: Variant, paths: Dictionary) -> Variant:
	if v is Object:
		var d := {}
		for k in _props(v):
			var x: Variant = (v as Object).get(k)
			if k in REFS:
				d[k] = null if x == null else paths.get((x as Object).get_instance_id(), "?")
			else:
				d[k] = _encode(x, paths)
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_encode(x, paths))
		return a
	if v is PackedInt32Array or v is PackedInt64Array or v is PackedByteArray:
		return Array(v)
	if v is Vector2i:
		return [v.x, v.y]
	return v


## Fills [param o] from [param d] (its part of a [method to_dict] form; plan
## 45, M3: a saved replay's body is a shared file, so any values): only the
## object's own script variables are set - not "script" (the class's
## GDScript, whose static variables a key could set), not an engine property
## - each from a value of a type it can take (others are left as they are),
## and an owned array of objects grows to at most [constant GROW_MAX].
static func _decode(o: Object, d: Dictionary, path: String, refs: Array) -> void:
	var settable := _script_variables(o)
	for k in d:
		if not k is String or not settable.has(k):
			continue
		var key: String = k
		var v: Variant = d[k]
		if key in REFS:
			if v == null or v is String:
				refs.append([o, key, v])
			continue
		var cur: Variant = o.get(key)
		if cur is Object:
			if v is Dictionary:
				_decode(cur, v, path + "/" + key, refs)
		elif cur is Array and not (cur as Array).is_empty() and cur[0] is Object:
			if not v is Array or (v as Array).size() > maxi(GROW_MAX, (cur as Array).size()):
				continue
			var src: Array = v
			while (cur as Array).size() < src.size():
				# plan 34: an extended set-up's teams have more markers and arrows
				(cur as Array).append((cur[0] as Object).get_script().new())
			for i in src.size():
				if src[i] is Dictionary:
					_decode(cur[i], src[i], "%s/%s/%d" % [path, key, i], refs)
		elif _fits(cur, v):
			o.set(key, _cast(cur, v))


## Plan 45: every script variable of [param o] (the skipped ones too: a form
## from before a field was skipped still sets it), as a set; once per script.
static func _script_variables(o: Object) -> Dictionary:
	var script: Variant = o.get_script()
	if script != null and _variables_cache.has(script):
		return _variables_cache[script]
	var out := {}
	for property in o.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[property["name"]] = true
	if script != null:
		_variables_cache[script] = out
	return out


static var _variables_cache := {}


## Plan 45: whether [method _cast] can make [param v] the type of [param like]
## (a number for a number or a flag, numbers for a packed array or a
## vector, a list for a list - for a typed one, of its type -, the same type
## for anything else; anything for a variable holding null, as before).
static func _fits(like: Variant, v: Variant) -> bool:
	if like == null:
		return true
	if like is int or like is bool or like is float:
		return v is int or v is float or v is bool
	if like is PackedInt32Array or like is PackedInt64Array or like is PackedByteArray or like is Vector2i:
		var values := MwPlain.array(v)
		if not (v is Array or v is PackedInt32Array or v is PackedInt64Array or v is PackedByteArray):
			return false
		for x: Variant in values:
			if not (x is int or x is float or x is bool):
				return false
		return values.size() >= 2 if like is Vector2i else true
	if like is Array:
		if not v is Array:
			return false
		var typed := (like as Array).get_typed_builtin()
		if typed == TYPE_NIL:
			return true
		for x: Variant in v:
			var t := TYPE_INT if x is float else typeof(x)          # (_cast makes a float an int)
			if t != typed and not (typed == TYPE_FLOAT and t == TYPE_INT):
				return false
		return true
	return typeof(like) == typeof(v)


## [param v] (from JSON: numbers are floats) as the type of [param like].
static func _cast(like: Variant, v: Variant) -> Variant:
	if like is int:
		return int(v)
	if like is bool:
		return bool(v)
	if like is PackedInt32Array:
		return PackedInt32Array(v)
	if like is PackedInt64Array:
		var values := PackedInt64Array()
		for x in v:
			values.append(int(x))
		return values
	if like is PackedByteArray:
		var b := PackedByteArray()
		for x in v:
			b.append(int(x))
		return b
	if like is Vector2i:
		return Vector2i(int(v[0]), int(v[1]))
	if like is Array:
		var a: Array = like.duplicate()
		a.clear()
		for x in v:
			a.append(_cast(0, x) if x is float else (_cast_array(x) if x is Array else x))
		return a
	return v


static func _cast_array(v: Array) -> Array:
	var a := []
	for x in v:
		a.append(int(x) if x is float else x)
	return a


static func _child(owner: Variant, key: String) -> Variant:
	if owner is Object:
		return (owner as Object).get(key)
	return owner[int(key)]


static func _resolve(s: MwRinkState, refs: Array) -> void:
	for r in refs:
		var o: Object = r[0]
		var path: Variant = r[2]
		var target: Variant = null
		if path != null:
			target = s
			for part in (path as String).split("/"):
				target = _child(target, part)
		o.set(r[1], target)


static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return int(a) == int(b) and float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b
