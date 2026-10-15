class_name MwPreloader
extends Node
## The start's background work (plan 27; owner: whatever stutters moves to
## the start). Every screen's scene is loaded on worker threads
## (ResourceLoader's threaded loading) and kept here, so the router's
## [code]load()[/code] finds it in memory, and every tile set a
## scene holds has its atlas prepared on a worker ([method RomTileSet.prepare]:
## read from the disk cache, MwCache, after the first run), so a screen's
## first visit no longer reads, parses or draws anything.
##
## The first screen's scene ([method start]'s [param first]) is asked for
## alone; the rest follow once it is in, in the order the screens can be
## reached from it ([method screen_order]), so they don't hold it up. A
## screen asked for before its scene is in waits for it as before (the
## router's [code]load()[/code] joins the thread's load).

## Every scene is in and every atlas prepared.
signal finished

## Scene path -> PackedScene, kept for the run.
var scenes := {}
## When the work finished (Time.get_ticks_msec), 0 until then.
var finished_msec := 0
## What took the main thread longest here: "<ms since start> <what> <ms>" for
## every step over 2 ms (the stutter tool prints it).
var slow_steps := PackedStringArray()

var _first := PackedStringArray()
var _rest := PackedStringArray()
var _loading := PackedStringArray()


## Starts loading [param first] (scene paths) now and [param rest] after it.
## The ROM, its catalogue, the glyphs and the cache's identity are read
## here, on the main thread, before any worker needs them.
func start(first: PackedStringArray, rest: PackedStringArray) -> void:
	if MwRom.available():
		MwRom.data()
		MwRom.catalogue()
		MwGlyphs.tiles()
	MwCache.prepare()
	_first = first
	_rest = rest
	_request(_first)
	set_process(true)


## Whether the work is done.
func done() -> bool:
	return finished_msec != 0


## The scene paths of the screens in the order they can be reached from
## [param from] (breadth first over MwScreens' exits), then any scene the
## exits don't reach.
static func screen_order(from: int) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {from: true}
	var queue: Array = [from]
	while not queue.is_empty():
		var id: int = queue.pop_front()
		var path := MwScreens.scene_path(id)
		if path != "" and not path in out:
			out.append(path)
		for e in MwScreens.exits(id):
			if not seen.has(e):
				seen[e] = true
				queue.append(e)
	for scene in MwScreens.scenes():
		var text := "res://scenes/%s/%s.tscn" % [scene, scene]
		if not text in out:
			out.append(text)
	return out


## The tile sets scene [param packed] holds (in its nodes' properties, and
## in the scenes it instances).
static func tile_sets_of(packed: PackedScene) -> Array[RomTileSet]:
	var out: Array[RomTileSet] = []
	_collect(packed, out)
	return out


static func _collect(packed: PackedScene, out: Array[RomTileSet]) -> void:
	var st := packed.get_state()
	for i in st.get_node_count():
		var inner := st.get_node_instance(i)
		if inner:
			_collect(inner, out)
		for j in st.get_node_property_count(i):
			var v: Variant = st.get_node_property_value(i, j)
			if v is RomTileSet and not out.has(v):
				out.append(v)


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS     # the pause menu doesn't hold it up
	set_process(not _loading.is_empty() or not _rest.is_empty())


func _process(_delta: float) -> void:
	for text in _loading.duplicate():
		var status := ResourceLoader.load_threaded_get_status(text)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_loading.remove_at(_loading.find(text))
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var t := Time.get_ticks_usec()
			var packed := ResourceLoader.load_threaded_get(text) as PackedScene
			_note("get " + text.get_file(), t)
			t = Time.get_ticks_usec()
			_loaded(text, packed)
			_note("prepare " + text.get_file(), t)
		else:
			push_warning("MwPreloader: %s did not load" % text)
	if not _loading.is_empty():
		return
	if not _rest.is_empty():
		var rest := _rest
		_rest = PackedStringArray()
		_request(rest)
		return
	if RomTileSet.preparing() == 0:
		finished_msec = Time.get_ticks_msec()
		set_process(false)
		finished.emit()


func _request(paths: PackedStringArray) -> void:
	for text in paths:
		if scenes.has(text) or _loading.has(text):
			continue
		if ResourceLoader.has_cached(text):
			_loaded(text, load(text) as PackedScene)
		elif ResourceLoader.load_threaded_request(text, "PackedScene") == OK:
			_loading.append(text)
		else:
			push_warning("MwPreloader: can't load %s" % text)


func _loaded(path: String, packed: PackedScene) -> void:
	if packed == null:
		return
	scenes[path] = packed
	for ts in tile_sets_of(packed):
		RomTileSet.prepare(ts.banks, ts.fonts)


func _note(what: String, since_usec: int) -> void:
	var ms := (Time.get_ticks_usec() - since_usec) / 1000.0
	if ms > 2.0:
		slow_steps.append("%d %s %.1f" % [Time.get_ticks_msec(), what, ms])
