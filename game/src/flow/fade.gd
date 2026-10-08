class_name MwFade
extends RefCounted
## A tick-stepped fade of chosen canvas items towards black and back: the
## original's per-line palette fades (docs/re/title.md, Fade engine) done
## the traditional way, with the items' modulate. Used where only part of
## the screen fades (credit text over the starfield); full-screen fades are
## the router's [MwScreenFader]. Like the original, a fade starts from the
## current level and takes exactly its length.

## Canvas items whose modulate RGB follows [member level].
var items: Array[CanvasItem] = []
## 1 = full colour, 0 = black.
var level := 1.0
var length := 0
var progress := 0
var _from := 1.0
var _to := 1.0


## Ticks a fade of D1 takes in the original ($14946): D1, or 1 below 2.
static func ticks(d1: int) -> int:
	return d1 if d1 >= 2 else 1


func _init(canvas_items: Array[CanvasItem] = [], start_level := 1.0) -> void:
	items = canvas_items
	set_level(start_level)


func fade_out(fade_ticks: int) -> void:
	_start(0.0, fade_ticks)


func fade_in(fade_ticks: int) -> void:
	_start(1.0, fade_ticks)


func busy() -> bool:
	return progress < length


## Advance one tick.
func step() -> void:
	if not busy():
		return
	progress += 1
	_apply(lerpf(_from, _to, float(progress) / float(length)))


## Jump to [param l] at once (and stop any fade).
func set_level(l: float) -> void:
	length = 0
	progress = 0
	_apply(l)


## Also fade [param item] (it takes the current level now).
func add(item: CanvasItem) -> void:
	items.append(item)
	item.modulate = Color(level, level, level, item.modulate.a)


func _apply(l: float) -> void:
	level = l
	for it in items:
		if is_instance_valid(it):
			it.modulate = Color(l, l, l, it.modulate.a)


func _start(target: float, fade_ticks: int) -> void:
	_from = level
	_to = target
	length = maxi(fade_ticks, 1)
	progress = 0
