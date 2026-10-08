class_name MwSession
extends RefCounted
## What lives across screens for one run of the game: the game setup, the
## original's two random streams and the attract demo flag
## (docs/re/title.md, Attract demo). The router hands it to every screen.

## Main random stream ($FFB096) and the second one ($FFCA18: starfield
## direction, main menu).
var rng: MlhRng
var rng_aux: MlhRng
## The setup the menus edit and the game reads.
var setup: MwMatchSetup
## True while the attract demo runs (`$FFCA1C`).
var attract := false
## Where the attract demo returns: the game setup (1, the original), or the
## port's front menu when it started the demo (plan 21).
var attract_return := 1
## The playoff run (`$FFBD6A`).
var playoffs := MwPlayoffs.new()
## State screens keep between visits (the main menu's row and stadium mode).
var screens := {}
## The rink's view (plan 20, MwRinkViews): the original's 2D (default) or
## one of the 3D cameras, picked with F1-F8 / a pad's Back on screens 4-6
## (MwRink).
var view := MwRinkViews.FLAT
## The birds-eye view's layout: the goals left and right (true) or top and
## bottom, as the 2D (F5 again switches).
var birds_eye_across := false
## Seeds were given (tests, comparisons): screens that reseed a stream from
## the hardware (the main menu's second stream) leave it alone.
var fixed_seeds := false

var _saved: MwMatchSetup


## [param seed_value] 0: seeded at random, as the original seeds from the
## VDP's HV counter at boot (then 32 warm-up steps); tests pass a seed.
func _init(seed_value := 0, aux_seed := 0) -> void:
	fixed_seeds = seed_value != 0
	rng = MlhRng.new(seed_value if seed_value != 0 else _hardware_seed())
	rng_aux = MlhRng.new(aux_seed if aux_seed != 0 else _hardware_seed())
	if seed_value == 0:
		rng.warm_up()
	if aux_seed == 0:
		rng_aux.warm_up()
	setup = MwMatchSetup.from_rom(MwRom.data(), MwMatchSetup.BOOT_DEFAULTS) if MwRom.available() \
			else MwMatchSetup.new()


## `rng_seed` with D0 = 0 on the second stream (the main menu does it on
## entry): a fresh hardware seed, unless the session's seeds are fixed.
func reseed_aux() -> void:
	if fixed_seeds:
		return
	rng_aux = MlhRng.new(_hardware_seed())
	rng_aux.warm_up()


static func _hardware_seed() -> int:
	return (randi() & 0xFFFFFFFF) | 1


## `attract_setup_begin` ($459C): save the setup, load the demo setup and
## pick its teams, stadium and Death Index with the main stream.
func begin_attract() -> void:
	attract = true
	_saved = setup.copy()
	if MwRom.available():
		setup = MwMatchSetup.from_rom(MwRom.data(), MwMatchSetup.DEMO)
	else:
		setup.pads = MwMatchSetup.PADS_DEMO
	setup.team_a = rng.range_value(0, 22)
	setup.stadium = setup.team_a
	var b := rng.range_value(0, 22)
	while b == setup.team_a:
		b = rng.range_value(0, 22)
	setup.team_b = b
	setup.death_index = rng.range_value(0, 4)


## `attract_setup_end` ($45E4) and the main menu clearing the flag.
func end_attract() -> void:
	if _saved:
		setup = _saved
		_saved = null
	attract = false
	attract_return = 1
