extends MwBetweenPlays
## Screen 18, the fight and its card (plan 11; [MwFightSim]): plane B the
## scoreboard picture with the score panel and the fight clock; the window
## the message panel's picture, the fighters' names and health bars, the
## message panel with the result or "PAUSE", then the fight card (28 map
## rows of the fight's tile bank, its labels and counts); the fighters as
## sprites, kept over the card (the original's card never touches the
## sprite table). Between the fight and the card the screen fades out over
## 16 ticks (the original waits for it: no passes run), the card is
## painted with its palette changes, and it fades in.

const CARD_FADE_OUT := 16
const CARD_FADE_IN := 32

## The card's window operations and events, held while the fade covers the fight.
var _card_ops: Array = []
var _card_events: Array = []
## The 16-tick fade before the card runs.
var _covering := false


## The scoreboard's picture, the message panel's and the fight's tile bank
## (VRAM 1-245, 246-273, 1000-1084).
func _banks() -> PackedStringArray:
	var out := PackedStringArray()
	for a in MwScoreboardBackdrop.pictures(rom, screen_id):
		out.append("picture_%06x" % a)
	out.append("tilebank_%06x" % MwFightSim.BANK)
	return out


func _enter_screen(data: Dictionary) -> void:
	_card_ops = []
	_card_events = []
	_covering = false
	if palette:
		palette.steps = PackedStringArray(["screen_palette"])
	super._enter_screen(data)


## While the fade before the card runs no pass runs (the tick goes on);
## once covered the card is shown and fades in.
func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if _covering:
		if state:
			state.tick = (state.tick + elapsed) & 0xFFFFFFFF
		if fader != null and fader.busy():
			return
		_show_card()
		return
	super._screen_pass(elapsed, input)


## A pass's draws; the pass that ends the fight shows its last frame and
## starts the fade, the card waits for it (without a fader: at once).
func _draw_pass() -> void:
	var f := sim as MwFightSim
	if f == null or f.card_window_from < 0 or fader == null:
		super._draw_pass()
		return
	var cut := f.card_window_from
	painter_b.paint(sim.plane_ops, state)
	painter_w.paint(sim.window_ops.slice(0, cut), state)
	var list := drawer.list(state, sim.sprite_ops)
	sprites_low.show_list(list)
	sprites_high.show_list(list)
	var after := false
	_card_events = []
	for ev in sim.events:
		if not after and str(ev[0]) == "fade_out":
			after = true
			continue
		if after:
			_card_events.append(ev)
		else:
			_event(ev)
	_card_ops = sim.window_ops.slice(cut)
	_covering = true
	fader.fade_out(CARD_FADE_OUT)


## The card painted under the cover, its palette set, the fade-in (the
## sound calls the fight's last pass made after its fade-out first).
func _show_card() -> void:
	_covering = false
	sim.fade_over()
	painter_w.paint(_card_ops, state)
	for ev in _card_events:
		_event(ev)
	_card_ops = []
	_card_events = []
	if fader != null:
		fader.fade_in(CARD_FADE_IN)


## The sim's palette events: `$215E` the screen palette again, `$149B4`
## one colour (a code constant, or black).
func _event(ev: Array) -> void:
	match str(ev[0]):
		"palette":
			_set_steps(PackedStringArray(["screen_palette"]))
		"colour":
			var at := int(ev[4]) if ev.size() > 4 else 0
			var step := ("word %x %d" % [at, int(ev[1])]) if at != 0 else ("black %d" % int(ev[1]))
			var steps := palette.steps.duplicate()
			steps.append(step)
			_set_steps(steps)
		_:
			super._event(ev)


## New palette steps; the sprite layers take the rebuilt palette (the
## planes and the backdrop follow its change signal).
func _set_steps(steps: PackedStringArray) -> void:
	palette.steps = steps
	sprites_low.palette = palette
	sprites_high.palette = palette


## Run on its own: the demo match in phase 4 (the score panel without the
## game clock).
func _demo_state() -> MwRinkState:
	var s := super._demo_state()
	s.phase = 4
	return s
