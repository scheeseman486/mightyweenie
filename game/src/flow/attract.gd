class_name MwAttract
extends RefCounted
## The attract demo's rules (docs/re/title.md, Attract demo), for the
## screens that take part: the main menu falls into the demo after 1800
## ticks without a new press; the matchup loads the demo setup and goes
## straight to the rink; the rink ends the demo on any input on any pad (or
## when the demo's period ends) and returns to the main menu with the
## setup restored.

## Main menu idle timeout ($708 at $138BE).
const IDLE_TICKS := 1800
## Plan 35: whether a menu left idle for [constant IDLE_TICKS] falls into the
## attract demo (on: the original). A match rule (MwSettings.MATCH_RULES),
## off online - a lobby's menus wait for their players.
static var idle_attract := true
## Stand-in for the end of the demo's first period until gameplay exists
## (plans 08-09): a demo without input measured 4210 ticks in the rink.
const DEMO_TICKS := 4210


## A new press of anything (resets the main menu's idle time).
static func any_press(input: MwInputFrame) -> bool:
	return input != null and not input.pressed.is_empty()


## Anything held or newly pressed (ends the demo: `rink_phase_step` ORs the
## four pads' words).
static func any_input(input: MwInputFrame) -> bool:
	return input != null and (not input.held.is_empty() or not input.pressed.is_empty())


## Whether [param idle] ticks without a new press start the attract demo
## ([constant IDLE_TICKS], when [member idle_attract] is on).
static func idle_out(idle: int) -> bool:
	return idle_attract and idle >= IDLE_TICKS
