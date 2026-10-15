class_name MwNetGraph
extends RefCounted
## An object graph as plain data and back (plan 35 section 5, work item 6):
## what a resync snapshot ([MwNetSnapshot]) carries of the session - the
## rink's state with its control layer, crowd, benches and replay ring, the
## playoffs, the players - and of the sound driver's model: every script
## variable of every object reachable, arrays and dictionaries inside out,
## and which objects are one and the same (the rink's random stream *is*
## the session's main stream, the rink's playoffs the session's), so that a
## machine takes up another's game exactly. Node-free; the result is plain
## Variant data that var_to_bytes carries bit for bit (floats included).
##
## The form: a value is either plain (null, bool, int, float, strings,
## vectors, colours, packed arrays: as it is) or an Array whose first item
## is a [enum Tag]:
## [codeblock]
##   [ARRAY, item ...]                                  an untyped Array
##   [TYPED, builtin type, class name, script key, item ...]   a typed Array
##   [DICT, key, value, key, value ...]                 a Dictionary, in its order
##   [OBJECT, id, class key, name, value, name, value ...]   an object's script variables
##   [REF, id]                                          an object met before
##   [RNG, seed, state]                                 a RandomNumberGenerator
##   [CUSTOM, id, class key, data]                      a class with its own form ([member custom])
## [/codeblock]
## A class key is a script's global class name, or an inner class's path
## from it ("MwRinkState.Player", [method key_of]). What isn't the game's
## is left out: Nodes, Resources, callables and signals (a property holding
## one isn't written, so the receiving object keeps its own), and the
## variables [member skip] names per class.
##
## Decoding makes the objects anew ([method decode]) - only RefCounted
## classes under res://src/ outside the net code, as a snapshot from a
## host can name no other - or fills ones the caller has
## ([method decode_into]: the session itself, the sound driver's parts).
## Roots must be decoded in the order they were encoded (an object met
## first in one root is a REF in the next). What went wrong is in
## [member errors] (nothing is ever assumed: a malformed form decodes to
## nulls and errors, never a crash).

enum Tag { ARRAY, TYPED, DICT, OBJECT, REF, RNG, CUSTOM }

## Script variables left out, by class key (a machine's own, presentation,
## the ROM, computed properties).
var skip := {}
## Classes with a form of their own, by class key: [encode: Callable(object)
## -> Variant, decode: Callable(Variant) -> Object].
var custom := {}
var errors := PackedStringArray()

var _ids := {}               # encoding: instance id -> id
var _objects := {}           # decoding: id -> Object
var _next := 0

static var _key_of := {}     # Script -> class key ("" not found)
static var _by_key := {}     # class key -> Script
static var _paths := {}      # global class name -> script path
static var _props := {}      # Script -> its script variables' names
static var _types := {}      # Script -> {name: declared type (TYPE_NIL: untyped)}
static var _walked := {}     # outer scripts whose inner classes have keys


# --- encoding ---------------------------------------------------------------------------------------

## [param v] in the plain form (see the class notes).
func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_OBJECT:
			return _encode_object(v)
		TYPE_ARRAY:
			var a: Array = v
			var out := []
			if a.is_typed():
				var element_script: Variant = a.get_typed_script()
				out = [Tag.TYPED, a.get_typed_builtin(), str(a.get_typed_class_name()),
						key_of(element_script) if element_script is Script else ""]
			else:
				out = [Tag.ARRAY]
			for x in a:
				out.append(encode(x) if carried(x) else null)
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var out := [Tag.DICT]
			for k in d:
				if carried(k) and carried(d[k]):
					out.append(encode(k))
					out.append(encode(d[k]))
			return out
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return null
	return v


## Whether [param v] is the game's to carry: not a Node, a Resource, an
## object without a script (but Godot's random number generator), a
## callable or a signal.
static func carried(v: Variant) -> bool:
	match typeof(v):
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_OBJECT:
			var o: Object = v
			if o == null or not is_instance_valid(o):
				return true                          # null
			if o is RandomNumberGenerator:
				return true
			return o is RefCounted and not o is Resource and o.get_script() != null
	return true


func _encode_object(o: Object) -> Variant:
	if o == null or not is_instance_valid(o):
		return null
	if o is RandomNumberGenerator:
		return [Tag.RNG, (o as RandomNumberGenerator).seed, (o as RandomNumberGenerator).state]
	if not carried(o):
		return null
	var iid := o.get_instance_id()
	if _ids.has(iid):
		return [Tag.REF, _ids[iid]]
	var key := key_of(o.get_script())
	if key == "":
		errors.append("no class key for %s" % str(o))
		return null
	var n := _next
	_next += 1
	_ids[iid] = n
	if custom.has(key):
		return [Tag.CUSTOM, n, key, encode((custom[key][0] as Callable).call(o))]
	var out := [Tag.OBJECT, n, key]
	var left: Array = skip.get(key, [])
	for text: String in props(o):
		if text in left:
			continue
		var x: Variant = o.get(text)
		if not carried(x):
			continue
		out.append(text)
		out.append(encode(x))
	return out


# --- decoding ---------------------------------------------------------------------------------------

## The value [param encoded] stands for (objects made anew).
func decode(encoded: Variant) -> Variant:
	if not encoded is Array:
		return encoded
	var a: Array = encoded
	if a.is_empty() or not a[0] is int:
		return _bad("not a tagged value")
	match int(a[0]):
		Tag.ARRAY:
			var out := []
			for i in range(1, a.size()):
				out.append(decode(a[i]))
			return out
		Tag.TYPED:
			if a.size() < 4 or not a[1] is int or not a[2] is String or not a[3] is String:
				return _bad("a typed array's head")
			var items := []
			for i in range(4, a.size()):
				items.append(decode(a[i]))
			return _typed(items, int(a[1]), str(a[2]), str(a[3]))
		Tag.DICT:
			if a.size() % 2 != 1:
				return _bad("a dictionary's pairs")
			var d := {}
			for i in range(1, a.size(), 2):
				d[decode(a[i])] = decode(a[i + 1])
			return d
		Tag.OBJECT:
			if a.size() < 3 or a.size() % 2 != 1 or not a[1] is int or not a[2] is String:
				return _bad("an object's head")
			if _objects.has(int(a[1])):
				return _bad("object %d twice" % int(a[1]))
			var gd_script := script_of(str(a[2]))
			if gd_script == null:
				return _bad("class %s may not be made" % str(a[2]))
			var o: Object = gd_script.new()
			if o == null:
				return _bad("class %s not made" % str(a[2]))
			_objects[int(a[1])] = o
			_fill(o, a)
			return o
		Tag.REF:
			if a.size() != 2 or not a[1] is int or not _objects.has(int(a[1])):
				return _bad("a reference to nothing")
			return _objects[int(a[1])]
		Tag.RNG:
			if a.size() != 3 or not a[1] is int or not a[2] is int:
				return _bad("a random number generator")
			var r := RandomNumberGenerator.new()
			r.seed = int(a[1])
			r.state = int(a[2])
			return r
		Tag.CUSTOM:
			if a.size() != 4 or not a[1] is int or not a[2] is String or not custom.has(str(a[2])):
				return _bad("a custom object")
			var o: Variant = (custom[str(a[2])][1] as Callable).call(decode(a[3]))
			if not o is Object:
				return _bad("custom %s not made" % str(a[2]))
			_objects[int(a[1])] = o
			return o
	return _bad("tag %s" % str(a[0]))


## Fills [param target] (an object of the same class) from [param encoded] (an
## OBJECT entry) instead of making one: the roots a caller keeps (the
## session, the sound driver's parts). False when [param encoded] isn't one of
## its class.
func decode_into(target: Object, encoded: Variant) -> bool:
	if target == null or not encoded is Array:
		errors.append("decode_into: nothing")
		return false
	var a: Array = encoded
	if a.size() < 3 or a.size() % 2 != 1 or not (a[0] is int and int(a[0]) == Tag.OBJECT) \
			or not a[1] is int or not a[2] is String or str(a[2]) != key_of(target.get_script()) \
			or _objects.has(int(a[1])):
		errors.append("decode_into: not a %s" % key_of(target.get_script()))
		return false
	_objects[int(a[1])] = target
	_fill(target, a)
	return true


## Sets [param o]'s script variables from OBJECT entry [param a]'s pairs.
func _fill(o: Object, a: Array) -> void:
	var names := props(o)
	for i in range(3, a.size(), 2):
		if not a[i] is String or not (a[i] as String) in names:
			errors.append("%s has no %s" % [key_of(o.get_script()), str(a[i])])
			continue
		assign(o, a[i], decode(a[i + 1]))


## Sets [param o]'s [param name] to [param v]: an untyped array made into
## the variable's typed one; a value of another type than the variable's
## refused (noted in [member errors]).
func assign(o: Object, name: String, v: Variant) -> void:
	props(o)                                       # its declared types known
	var cur: Variant = o.get(name)
	if cur is Array and (cur as Array).is_typed() and v is Array and not (v as Array).is_typed():
		var c: Array = cur
		v = _typed(v, c.get_typed_builtin(), str(c.get_typed_class_name()),
				key_of(c.get_typed_script()) if c.get_typed_script() is Script else "")
	var declared := int((_types.get(o.get_script(), {}) as Dictionary).get(name, TYPE_NIL))
	if declared != TYPE_NIL and v != null and typeof(v) != declared:
		errors.append("%s.%s: %s for %s" % [key_of(o.get_script()), name, type_string(typeof(v)),
				type_string(declared)])
		return
	if cur is Array and v is Array and (cur as Array).is_typed() and not (v as Array).is_same_typed(cur):
		errors.append("%s.%s: an array of another type" % [key_of(o.get_script()), name])
		return
	o.set(name, v)


## [param items] as a typed array ([param builtin], [param class_name_],
## the script of [param script_key]).
func _typed(items: Array, builtin: int, class_name_: String, script_key: String) -> Array:
	if builtin < 0 or builtin >= TYPE_MAX:
		_bad("a typed array's type")
		return []
	var class_script: Variant = null
	if script_key != "":
		class_script = script_of(script_key)
		if class_script == null:
			_bad("a typed array of %s" % script_key)
			return []
	elif builtin == TYPE_OBJECT and class_name_ != "" and not ClassDB.class_exists(class_name_):
		_bad("a typed array of %s" % class_name_)
		return []
	for x in items:
		if x == null and builtin != TYPE_OBJECT:
			_bad("a null in a typed array of values")    # (plan 40: the engine refused it noisily)
			return []
		if x != null and typeof(x) != builtin:
			_bad("an item of another type in a typed array")
			return []
		if class_script != null and x != null and not _is_of(x, class_script):
			_bad("an object of another class in a typed array")
			return []
	return Array(items, builtin, StringName(class_name_), class_script)


static func _is_of(o: Object, class_script: Script) -> bool:
	var t: Script = o.get_script()
	while t != null:
		if t == class_script:
			return true
		t = t.get_base_script()
	return false


func _bad(why: String) -> Variant:
	errors.append(why)
	return null


# --- classes ----------------------------------------------------------------------------------------

## [param o]'s script variables (its class's and its bases'), in their order.
static func props(o: Object) -> Array:
	var class_script: Variant = o.get_script()
	if _props.has(class_script):
		return _props[class_script]
	var out := []
	var types := {}
	for property in o.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(str(property["name"]))
			types[str(property["name"])] = TYPE_NIL if int(property["usage"]) & PROPERTY_USAGE_NIL_IS_VARIANT \
					else int(property["type"])
	_props[class_script] = out
	_types[class_script] = types
	return out


## [param class_script]'s class key: its global class name, or for an inner class
## "Outer.Inner" ("" when it is neither).
static func key_of(class_script: Variant) -> String:
	if not class_script is Script:
		return ""
	if _key_of.has(class_script):
		return _key_of[class_script]
	var g := str((class_script as Script).get_global_name())
	if g != "":
		_key_of[class_script] = g
		_by_key[g] = class_script
		return g
	# an inner class: its outer script is loaded (an object of it exists)
	for name: String in _global_paths():
		var path: String = _paths[name]
		if path.begins_with("res://src/") and ResourceLoader.has_cached(path):
			var outer := load(path) as GDScript
			if outer != null and not _walked.has(outer):
				_walk(outer, name)
	if not _key_of.has(class_script):
		_key_of[class_script] = ""
	return _key_of[class_script]


## The script of class key [param key] (null: none, or not one a snapshot
## may make - a RefCounted class under res://src/, not the net code's).
static func script_of(key: String) -> GDScript:
	var parts := key.split(".")
	var path := str(_global_paths().get(parts[0], ""))
	if not path.begins_with("res://src/") or path.begins_with("res://src/net/"):
		return null
	if not _by_key.has(key):
		var outer := load(path) as GDScript
		if outer == null:
			return null
		if not _walked.has(outer):
			_walk(outer, parts[0])
	var class_script: Variant = _by_key.get(key)
	if not class_script is GDScript or (class_script as GDScript).get_instance_base_type() != &"RefCounted":
		return null
	return class_script


static func _global_paths() -> Dictionary:
	if _paths.is_empty():
		for c in ProjectSettings.get_global_class_list():
			_paths[str(c["class"])] = str(c["path"])
	return _paths


## Keys for [param gd_script] and its inner classes (constants that are scripts
## without a file of their own; a preloaded script is someone else's).
static func _walk(gd_script: GDScript, key: String) -> void:
	_walked[gd_script] = true
	_key_of[gd_script] = key
	_by_key[key] = gd_script
	var consts := gd_script.get_script_constant_map()
	for k in consts:
		var v: Variant = consts[k]
		if v is GDScript and (v as GDScript).resource_path == "" and not _key_of.has(v):
			_walk(v, key + "." + str(k))
