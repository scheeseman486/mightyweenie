class_name MwTileLru
extends RefCounted
## A model of the original's sprite tile cache (`$150CE`, docs/re/graphics.md)
## for the rink's load model (plan 36, docs/re/timing.md "Pass load"): which
## tile runs a draw has to upload. An LRU of [constant CAPACITY] tiles keyed
## by a run's first tile word (the original's hash key), emptied at each
## rink visit (`rink_load` flushes the original's); RAM tiles (below
## [constant RAM_TILES]) upload on every use. It agrees with the original's
## misses on 99.2 % of its calls (the load recordings).
##
## O(1) a use, integers only: a doubly linked list through two arrays
## indexed by the key (the most recent first) and each key's tile count.

const CAPACITY := 672
const RAM_TILES := 0x800
const KEYS := 0x10000
const HEAD := KEYS               ## the list's sentinel

var used := 0                    ## tiles held
var _tiles := PackedInt32Array() # key -> its run's tiles (0: not held)
var _prev := PackedInt32Array()
var _next := PackedInt32Array()


func _init() -> void:
	_tiles.resize(KEYS)
	_prev.resize(KEYS + 1)
	_next.resize(KEYS + 1)
	reset()


## Empty (a new rink visit).
func reset() -> void:
	_tiles.fill(0)
	_prev[HEAD] = HEAD
	_next[HEAD] = HEAD
	used = 0


## A run of [param tiles] tiles starting at tile word [param key] drawn:
## the tiles it uploads (0 on a hit; the run's own count on a miss, as the
## first run cached under that key had it on a hit - the original's cache
## bug - and always for RAM tiles).
func use(key: int, tiles: int) -> int:
	if key < RAM_TILES:
		return tiles
	if _tiles[key] > 0:
		_unlink(key)
		_front(key)
		return 0
	while used + tiles > CAPACITY and _next[HEAD] != HEAD:
		var old := _prev[HEAD]       # the least recently used
		_unlink(old)
		used -= _tiles[old]
		_tiles[old] = 0
	_front(key)
	_tiles[key] = tiles
	used += tiles
	return tiles


## The keys held, the most recent first (checks).
func keys() -> PackedInt32Array:
	var out := PackedInt32Array()
	var k := _next[HEAD]
	while k != HEAD:
		out.append(k)
		k = _next[k]
	return out


func _unlink(k: int) -> void:
	_next[_prev[k]] = _next[k]
	_prev[_next[k]] = _prev[k]


func _front(k: int) -> void:
	_prev[k] = HEAD
	_next[k] = _next[HEAD]
	_prev[_next[HEAD]] = k
	_next[HEAD] = k
