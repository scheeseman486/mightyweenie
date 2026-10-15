class_name MwViewLayers
extends RefCounted
## Plan 40 (R2): the 3D view's layers, decided once a frame
## ([method MwRinkView3D.blend_to]) from the VISUALS page's settings and the
## camera's mode, and handed to the sprites, the model, the nets and the
## stands - none of them reads MwSettings for a layer. The calibration
## camera shows the original: none of the port's layers.

## The calibration camera: the original's 2D order, nothing of the port's.
var original := false
## The ice as a mirror (MwSettings.reflections; plan 37).
var reflections := false
## The flat shadows (MwSettings.flat_shadows; owner, 2026-10-09).
var flat_shadows := false
## The paint on the model (a match with a paint model; plan 37).
var paint := false
## The paint's layers on the model: ABACABB MODE's blood (MwSettings.blood)
## and DETAILED ICE (MwSettings.ice_detail); whether the paint shows at all
## is [member paint].
var blood := false
var ice_detail := false
## The figures on the benches and in the boxes (the view's
## [member MwRinkView3D.benches]; plan 32).
var benches := false
## The paint's particles in flight (ABACABB MODE; plan 37).
var particles := false
## The crowd makes way for the play (MwSettings.crowd_duck; the main 3D
## cameras only, [method MwRinkView3D.ducks]).
var crowd_duck := false


## The layers camera mode [param mode] shows with the settings as they are
## ([param has_paint]: the match has a paint model; [param benches_on]: the
## view shows the benches' figures).
static func of(mode: MwRinkCamera3D.Mode, has_paint: bool, benches_on: bool) -> MwViewLayers:
	var layers := MwViewLayers.new()
	layers.original = mode == MwRinkCamera3D.Mode.CALIBRATION
	layers.reflections = MwSettings.reflections and not layers.original
	layers.flat_shadows = MwSettings.flat_shadows and not layers.original
	layers.paint = has_paint and not layers.original
	layers.blood = MwSettings.blood
	layers.ice_detail = MwSettings.ice_detail
	layers.benches = benches_on and not layers.original
	layers.particles = MwSettings.blood and not layers.original
	layers.crowd_duck = MwSettings.crowd_duck and MwRinkView3D.ducks(mode)
	return layers
