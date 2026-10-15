class_name MwRinkCopy
extends RefCounted
## Plan 41 (online feel), work item 2 - the run-ahead's copy: the confirmed
## rink state copied into a shadow the run-ahead runs passes on
## ([MwNetRunAhead]; docs/net.md "Run-ahead"). Object to object, every
## script variable of every object reachable (as [MwNetGraph] walks them,
## its variable lists shared), one object met twice one copy (the rink's
## random stream is one stream; the control layer points back at the state),
## into objects kept from copy to copy (a source object copied before is
## copied into the same destination again: no allocation once the shadow
## exists). Packed arrays are duplicated (Godot 4 shares them by reference:
## a shadow's skater would move the confirmed one). Nodes, Resources,
## callables and Godot's own objects are shared, not copied - the game's
## state holds none it writes. A Godot RandomNumberGenerator gets its seed
## and state.
##
## [member skip] leaves variables out (the destination's set to null): the
## shadow has no full replay, no paint, no crowd or bench of its own - its
## passes step none of them (the confirmed game's would be stepped: never),
## and nothing the game decides reads them.

## Variables left out (set to null in the copy), by script.
var skip := {}
## Variables given a fresh value instead (the copy's own, empty), by script:
## the instant replay ring's 3D side-store (presentation, hundreds of frames'
## records - copying it cost more than all the rest).
var blank := {}
## Variables the destination keeps as it has them, by script (work item 3,
## the sound driver's model: its ROM, the samples made from it, its own
## output - as a resync snapshot leaves them, MwNetSnapshot.codec).
var keep := {}
## Copies made; the last one's objects copied, and of them the ones made
## new (a source object not met before: the first copy's all of them) -
## whoever keeps a destination object's sub-object (the shadow's sim keeps
## its puck) takes them up again when any are new.
var stats := {"copies": 0, "objects": 0, "made": 0}
var _root := 0            # the source root the pool is of (another root: the pool let go)
var _made := 0
var _pool := {}           # source instance id -> its destination (kept from copy to copy)
var _seen := {}           # this copy's: source instance id -> destination
var _copied := false      # a copy made (its objects the next one's pool)
var _plans := {}          # Script -> [its variables (StringName), their kinds (PackedByteArray), {name: fresh value},
						  #   its fill function (a GDScript, null: the plan walked), its variables left out or fresh]

## Plan 42 (speed, second round): each class's copy compiled once into a
## function of its own ([method _filler]) - its variables read and written
## by name in code, no plan walked, no get / set by name per variable; the
## walk of objects and containers and the variables left out or given a
## fresh value as before. Off (tests): the plan walked.
static var generated := true

## Plan 42 (speed): how each variable is copied, worked out once per class
## from its declared type ([method _plan_of]): a value as it is, a packed
## array duplicated, an object or container walked, left out, given a fresh
## value, kept as the destination has it.
enum Kind { PLAIN, PACKED, DEEP, SKIP, BLANK, KEEP }


func _init() -> void:
	skip[MwRinkState] = PackedStringArray(["full_replay", "splatter", "crowd_life", "bench_life"])
	blank[MwRinkState.ReplayRing] = {"side": {}}


## [param src] copied into [param dst] (the same class): [param dst] is
## the copy's root, kept by the caller.
func copy_into(dst: Object, src: Object) -> void:
	copy_roots([[dst, src]])


## Several roots in one copy ([param pairs]: [destination, source] each):
## an object met under two roots copied once. [method value] then copies
## more of the same copy's values.
func copy_roots(pairs: Array) -> void:
	var src: Object = pairs[0][1]
	if src.get_instance_id() != _root:
		_root = src.get_instance_id()
		_pool = {}
	elif _copied:
		# the pool: what the last copy met, its values' objects too (objects gone
		# from the source let go; plan 42: kept from the end of the last copy -
		# [method value]'s objects were made anew each copy)
		_pool = _seen
	_copied = true
	_seen = {}
	for pair: Array in pairs:
		_seen[(pair[1] as Object).get_instance_id()] = pair[0]
	_made = 0
	for pair: Array in pairs:
		_fill(pair[0], pair[1])
	stats["copies"] += 1
	stats["objects"] = _seen.size()
	stats["made"] = _made


## [param v] copied as part of the last copy (its objects the same ones;
## the next copy's pool has them).
func value(v: Variant) -> Variant:
	return _value(v)


func _fill(d: Object, source: Object) -> void:
	_fill_with(d, source, source.get_script())


## [method _fill] of [param source] of class [param script].
func _fill_with(d: Object, source: Object, script: Script) -> void:
	var plan: Variant = _plans.get(script)
	if plan == null:
		plan = _plan_of(script, source)
	var filler: Variant = plan[3]
	if filler != null and generated:
		filler.fill(self, d, source)
		for r: Array in plan[4]:
			var rest_name: StringName = r[0]
			if int(r[1]) == Kind.SKIP:
				d.set(rest_name, null)
			else:
				var f: Variant = (plan[2] as Dictionary)[rest_name]
				d.set(rest_name, f.duplicate() if f is Dictionary or f is Array else f)
		return
	var names: Array = plan[0]
	var kinds: PackedByteArray = plan[1]
	for i in names.size():
		var k := kinds[i]
		var name: StringName = names[i]
		if k == Kind.PLAIN:
			d.set(name, source.get(name))
		elif k == Kind.DEEP:
			d.set(name, _value(source.get(name)))
		elif k == Kind.PACKED:
			d.set(name, source.get(name).duplicate())
		elif k == Kind.SKIP:
			d.set(name, null)
		elif k == Kind.BLANK:
			var fresh: Variant = (plan[2] as Dictionary)[name]
			d.set(name, fresh.duplicate() if fresh is Dictionary or fresh is Array else fresh)


## Class [param script]'s copy plan (its object [param source] shows its
## variables, MwNetGraph.props, and their declared types): typed values
## (ints, floats, strings, vectors) as they are, packed arrays duplicated,
## objects, arrays, dictionaries and untyped variables walked ([method
## _value]); [member skip], [member blank], [member keep] as they say.
func _plan_of(script: Script, source: Object) -> Array:
	var left := PackedStringArray()
	var fresh := {}
	var own := PackedStringArray()
	for k: Script in skip:
		if script == k:
			left = skip[k]
	for k: Script in blank:
		if script == k:
			fresh = blank[k]
	for k: Script in keep:
		if script == k:
			own = keep[k]
	var props := MwNetGraph.props(source)
	var types: Dictionary = MwNetGraph._types.get(script, {})
	var names := []
	var kinds := PackedByteArray()
	var fresh_of := {}
	var rest := []
	for text: String in props:
		var kind := Kind.DEEP
		if text in own:
			kind = Kind.KEEP
		elif text in left:
			kind = Kind.SKIP
		elif fresh.has(text):
			kind = Kind.BLANK
			fresh_of[StringName(text)] = fresh[text]
		else:
			kind = _kind_of(int(types.get(text, TYPE_NIL)))
		if kind == Kind.KEEP:
			continue
		names.append(StringName(text))
		kinds.append(kind)
		if kind == Kind.SKIP or kind == Kind.BLANK:
			rest.append([StringName(text), kind])
	var plan := [names, kinds, fresh_of, _filler(names, kinds, types), rest]
	_plans[script] = plan
	return plan


## The fill function of a class whose variables [param names] are copied as
## [param kinds] say ([param types]: their declared types): a script of one
## static [code]fill(copy, d, s)[/code] - a value as it is, a packed array
## duplicated, an object or container walked ([method _object], [method
## _value]); left out and fresh values are [method _fill]'s. Null if it
## doesn't compile (the plan is walked then). Compiled once a process for a
## class and its copy (~2 ms each: [method MwNetRunAhead.warm] has them
## made as the rink is entered).
static func _filler(names: Array, kinds: PackedByteArray, types: Dictionary) -> Variant:
	var sig := kinds.hex_encode()
	for n: StringName in names:
		sig += "|%s:%d" % [n, int(types.get(str(n), TYPE_NIL))]
	if _fillers.has(sig):
		return _fillers[sig]
	var src := "extends RefCounted\n\n\nstatic func fill(c: MwRinkCopy, d: Object, s: Object) -> void:\n"
	var lines := 0
	for i in names.size():
		var n := str(names[i])
		match kinds[i]:
			Kind.PLAIN:
				src += "\td.%s = s.%s\n" % [n, n]
			Kind.PACKED:
				src += "\td.%s = s.%s.duplicate()\n" % [n, n]
			Kind.DEEP:
				var t := int(types.get(n, TYPE_NIL))
				src += ("\td.%s = c._object(s.%s)\n" if t == TYPE_OBJECT else "\td.%s = c._value(s.%s)\n") % [n, n]
			_:
				continue
		lines += 1
	if lines == 0:
		src += "\tpass\n"
	var gs := GDScript.new()
	gs.source_code = src
	var made: Variant = gs if gs.reload() == OK else null
	_fillers[sig] = made
	return made


static var _fillers := {}        # a class's variables and kinds -> its compiled fill function (null: none)


## How a variable declared of type [param t] is copied (TYPE_NIL: untyped).
static func _kind_of(t: int) -> int:
	match t:
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I, \
				TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_RECT2, TYPE_RECT2I, TYPE_COLOR, \
				TYPE_NODE_PATH, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return Kind.PLAIN
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
				TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
				TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return Kind.PACKED
	return Kind.DEEP


func _value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_OBJECT:
			return _object(v)
		TYPE_ARRAY:
			var a: Array = v
			var out := a.duplicate(false)
			for i in out.size():
				var t := typeof(out[i])
				if t == TYPE_OBJECT or t == TYPE_ARRAY or t == TYPE_DICTIONARY:
					out[i] = _value(out[i])
			return out
		TYPE_DICTIONARY:
			var dict: Dictionary = v
			var out := dict.duplicate(false)
			for k: Variant in out:
				var t := typeof(out[k])
				if t == TYPE_OBJECT or t == TYPE_ARRAY or t == TYPE_DICTIONARY:
					out[k] = _value(out[k])
			return out
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
				TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
				TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return v.duplicate()               # (Godot 4 hands packed arrays on by reference)
	return v                                   # values


func _object(o: Object) -> Object:
	if o == null or not is_instance_valid(o):
		return null
	var id := o.get_instance_id()
	var met: Variant = _seen.get(id)
	if met != null:
		return met
	if o is RandomNumberGenerator:
		var r: RandomNumberGenerator = _pool.get(id)
		if r == null:
			r = RandomNumberGenerator.new()
			_made += 1
		r.seed = (o as RandomNumberGenerator).seed
		r.state = (o as RandomNumberGenerator).state
		_seen[id] = r
		return r
	var script: Script = o.get_script()
	if script == null or not o is RefCounted or o is Resource:
		return o                               # shared (not the game's state)
	var d: Object = _pool.get(id)
	if d == null or d.get_script() != script:
		d = script.new()
		_made += 1
	_seen[id] = d
	_fill_with(d, o, script)
	return d
