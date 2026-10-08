class_name MwNets3D
extends Node3D
## The goal nets with a 3D model (plan 17, MwNet3D) in the 3D view: each
## pass's net drawings of those styles are taken out of the sprites and a
## model stands at each net's point instead (the sim's nets can move). The
## calibration camera keeps the drawings (it checks the 3D view against the
## original's pixels). Presentation only.

var palette: RomPalette:
	set(v):
		palette = v
		for n: MwNet3D in _nets.values():
			n.palette = v

var _nets := {}          # item key -> MwNet3D
var _warm: Array[MwNet3D] = []


## Takes the nets with a model out of [param items] (MwRinkDraw3D items, as
## the view shows them) and stands their models; returns the other items.
## [param drawings]: keep every net's drawing (the calibration camera), no
## models shown.
func take(items: Array, drawings := false) -> Array:
	var rom := MwRom.data() if MwRom.available() else PackedByteArray()
	var rest: Array = []
	var shown := {}
	for it: Dictionary in items:
		var style := MwNet3D.model_style(rom, int(it["net"]["anim"])) if it.has("net") and not rom.is_empty() else -1
		if drawings or style < 0:
			rest.append(it)
			continue
		var key: String = it.get("key", "net")
		var n: MwNet3D = _nets.get(key)
		if n != null and n.style != style:          # a style change (the Demon Net's stand-in goes, ...)
			n.queue_free()
			n = null
		if n == null:
			n = MwNet3D.new()
			n.style = style
			n.name = key.replace("/", "_")
			n.palette = palette
			add_child(n)
			_nets[key] = n
		n.place(it["at"], int(it["net"]["mouth"]))
		shown[key] = true
	for key: String in _nets:
		_nets[key].visible = shown.has(key)
	return rest


## The models standing now: {item key: MwNet3D}.
func shown() -> Dictionary:
	var out := {}
	for key: String in _nets:
		if _nets[key].visible:
			out[key] = _nets[key]
	return out


## Stands a model of every style at centre ice (on) for the 3D host's
## warm-up render (plan 20, MwRink3DHost), or takes them away (off).
func warm_up(on: bool) -> void:
	for n in _warm:
		n.queue_free()
	_warm.clear()
	if not on:
		return
	for style: int in MwNet3D.MODELS:
		var n := MwNet3D.new()
		n.style = style
		n.name = "Warm%d" % style
		n.palette = palette
		add_child(n)
		n.place(Vector3(0, 40, 0), 1)
		_warm.append(n)
