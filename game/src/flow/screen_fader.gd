class_name MwScreenFader
extends CanvasLayer
## Full-screen fades the traditional way: a cover on top of the screen,
## stepped once per 60 Hz tick by the router (not by wall-clock tweens), so a
## fade takes exactly its length in ticks: the original's fade of D1 ticks
## (MwFade.ticks), 32 for the standard `$20` (docs/re/title.md, Fade engine).
## Like the original, a fade starts from where the screen is (a fade-out
## during a fade-in starts from the partly covered screen).
##
## The cover shows the screen behind it as the original's fade does
## (`screen_fade.gdshader`): every colour channel steps through the 3-bit
## levels with the original's arithmetic ([method faded_level]), so dim
## colours reach black early and the screen is black for the fade's last
## ticks instead of very dim. [method coverage] is the fade's share done
## (0 the screen, 1 covered), for the router and the tests.

const DEFAULT_TICKS := 32
## The cover's ends ([member _from_kind], [member _to_kind]).
const SCREEN := 0
const COVER := 1
const MID := 2       ## start only: an earlier fade stopped part way
const DONE := 65536  ## progress of a finished fade
const SHADER := preload("res://src/flow/screen_fade.gdshader")

## An enhancement, off by default (owner, 2026-10-08; docs/architecture.md,
## Fidelity): the colours interpolated smoothly to the end of the fade
## instead of the original's 3-bit steps. Same timing either way.
static var smooth_fades := false

var rect := ColorRect.new()
var length := 0       # ticks of the current fade
var progress := 0     # ticks done
var direction := 0    # +1 out, -1 in, 0 idle
var _from := 0.0      # coverage at the fade's start
var _cov := 0.0
var _mat := ShaderMaterial.new()
var _from_kind := COVER
var _to_kind := COVER
var _mid_from := SCREEN
var _mid_p := 0
var _p := DONE


func _init() -> void:
	layer = 100
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)     # covers the 320x224 viewport
	_mat.shader = SHADER
	rect.material = _mat
	add_child(rect)
	_set_idle(0.0)


## Fade to [param color] over [param ticks], from the current coverage.
func fade_out(ticks := DEFAULT_TICKS, color := Color.BLACK) -> void:
	rect.color = color
	_start(ticks, 1)


## Fade back to the screen over [param ticks], from the current coverage.
func fade_in(ticks := DEFAULT_TICKS) -> void:
	_start(ticks, -1)


## Fully covered at once (e.g. before the first screen fades in).
func cover(color := Color.BLACK) -> void:
	rect.color = color
	_set_idle(1.0)


## Fully visible at once.
func uncover() -> void:
	_set_idle(0.0)


func busy() -> bool:
	return direction != 0


## The share of the fade done: 0 = screen fully visible, 1 = fully covered.
func coverage() -> float:
	return _cov


## Advance one tick.
func step() -> void:
	if direction == 0:
		return
	progress += 1
	_cov = lerpf(_from, 1.0 if direction > 0 else 0.0, float(progress) / float(length))
	if progress >= length:
		_set_idle(1.0 if direction > 0 else 0.0)
		return
	_p = progress_at(progress, length)
	_apply()


## The original's fade progress (16-bit fraction) after [param k] of
## [param ticks] ticks (`$14946`: step = $10000 / D1, the remainder as the
## start; done, [constant DONE], on the carry after exactly D1 ticks).
static func progress_at(k: int, ticks: int) -> int:
	if ticks < 2:
		return DONE
	var step_ := 0x10000 / ticks
	var p := 0x10000 % ticks + k * step_
	return mini(p, DONE)


## A colour channel's level (0-7) during a fade from level [param a] to
## [param b] at progress [param p] (`fade_vblank` `$149F6` with `$14A60`:
## the difference times the progress, rounded half up, in 3 bits).
static func faded_level(a: int, b: int, p: int) -> int:
	if p >= DONE:
		return b
	var n := absi(b - a)
	var d := ((2 * n * p + 0x10000) & 0xE0000) >> 17
	return a + d if b >= a else a - d


## The level shown now for a channel whose level on the screen is [param
## screen] (the shader's arithmetic, for the tests).
func level_shown(screen: int) -> int:
	var c := rect.color
	var cover_ := roundi(c.r * 7.0)
	var a := screen if _from_kind == SCREEN else cover_
	if _from_kind == MID:
		a = faded_level(screen, cover_, _mid_p) if _mid_from == SCREEN else faded_level(cover_, screen, _mid_p)
	var b := screen if _to_kind == SCREEN else cover_
	return faded_level(a, b, _p)


func _start(ticks: int, dir: int) -> void:
	# where the screen is: a running fade stops part way (its level is the start)
	if direction != 0:
		if _from_kind == MID:
			_mid_from = SCREEN if direction > 0 else COVER   # deeper nesting: from its own start
		else:
			_mid_from = _from_kind
		_mid_p = _p
		_from_kind = MID
	else:
		_from_kind = COVER if _cov >= 1.0 else SCREEN
	_to_kind = COVER if dir > 0 else SCREEN
	length = maxi(ticks, 1)
	progress = 0
	direction = dir
	_from = _cov
	_p = progress_at(0, length) if length >= 2 else 0
	_apply()


func _set_idle(cov: float) -> void:
	direction = 0
	_cov = cov
	_from_kind = COVER if cov >= 1.0 else SCREEN
	_to_kind = _from_kind
	_p = DONE
	_apply()


func _apply() -> void:
	# nothing to draw on an uncovered screen (no screen copy either)
	rect.visible = not (direction == 0 and _cov <= 0.0)
	var c := rect.color
	_mat.set_shader_parameter("cover", Vector3(roundf(c.r * 7.0), roundf(c.g * 7.0), roundf(c.b * 7.0)))
	_mat.set_shader_parameter("from_kind", _from_kind)
	_mat.set_shader_parameter("to_kind", _to_kind)
	_mat.set_shader_parameter("mid_from", _mid_from)
	_mat.set_shader_parameter("mid_p", float(_mid_p))
	_mat.set_shader_parameter("p", float(_p))
	_mat.set_shader_parameter("smooth_fade", smooth_fades)
