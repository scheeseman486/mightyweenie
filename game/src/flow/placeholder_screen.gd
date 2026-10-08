class_name MwPlaceholderScreen
extends MwScreen
## Stand-in for a screen not built yet (plans 05-09): shows its name, ID and
## entry variant and leaves along the original's exits on the approved verbs,
## so the whole flow can be walked. Exits are data in the scene:
##
## * `exits`: action -> target. A target is a screen ID, "back" (the previous
##   screen, through `back_remap`), "pop", "push:<id or extra>", or a
##   dictionary {screen ID: target} when the scene serves several IDs.
## * `auto_exit_ticks` / `auto_exit`: leave by itself after that many ticks.
## * `attract_role`: the screen's part in the attract demo (MwAttract) - the
##   main menu's idle timeout, the matchup passing through, the rink playing
##   the demo (a stand-in until gameplay exists).

@export var exits := {}
## previous screen -> where "back" goes instead (e.g. special plays after a
## timeout in the rink return to the faceoff, 5).
@export var back_remap := {}
@export var auto_exit_ticks := 0
@export var auto_exit: Variant = null
@export var label_position := Vector2(8, 8)
## Show the name / exits label (screens that draw something real hide it).
@export var show_label := true
@export_enum("None", "Main menu", "Matchup", "Rink") var attract_role := 0

enum Attract { NONE, MAIN_MENU, MATCHUP, RINK }

var _label: Label
var _ticks := 0
var _idle := 0


func _enter_screen(_data: Dictionary) -> void:
	if attract_role == Attract.MAIN_MENU and session:
		session.end_attract()          # the main menu clears the flag
	_label = Label.new()
	_label.visible = show_label
	_label.position = label_position
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 8)
	add_child(_label)
	_label.text = describe()


func describe() -> String:
	var info := MwScreens.info(screen_id)
	var lines := ["%s  #%d %s" % [str(info.get("name", "?")).to_upper(), screen_id, entry],
			"visit %d, from %d" % [visit, previous]]
	if session and session.attract:
		var su := session.setup
		lines.append("ATTRACT DEMO: team %d vs %d, stadium %d, death index %d, pads %d - any input ends it"
				% [su.team_a, su.team_b, su.stadium, su.death_index, su.pads])
	for a in exits:
		var t: Variant = _target(exits[a])
		if t != null:
			lines.append("%s -> %s" % [a, str(t)])
	if auto_exit_ticks > 0:
		lines.append("after %d ticks -> %s" % [auto_exit_ticks, str(_target(auto_exit))])
	return "\n".join(lines)


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	_ticks += elapsed
	if _attract_pass(elapsed, input):
		return
	for a in exits:
		if input.is_pressed(a):
			var t: Variant = _target(exits[a])
			if t != null:
				_follow(t)
				return
	if auto_exit_ticks > 0 and _ticks >= auto_exit_ticks:
		_follow(_target(auto_exit))


## The attract demo's part of the pass; true when it decided the pass.
func _attract_pass(elapsed: int, input: MwInputFrame) -> bool:
	if session == null:
		return false
	match attract_role:
		Attract.MAIN_MENU:
			_idle = 0 if MwAttract.any_press(input) else _idle + elapsed
			if _idle >= MwAttract.IDLE_TICKS:
				session.attract = true     # as if Start was pressed
				exit_to(3)
				return true
		Attract.MATCHUP:
			if session.attract:
				session.begin_attract()    # demo setup; nothing shown
				exit_to(4, {}, false)
				return true
		Attract.RINK:
			if session.attract:
				if MwAttract.any_input(input) or _ticks >= MwAttract.DEMO_TICKS:
					session.end_attract()
					exit_to(1)
				return true
	return false


func _target(t: Variant) -> Variant:
	if t is Dictionary:
		return t.get(screen_id, t.get(str(screen_id), null))
	return t


func _follow(t: Variant) -> void:
	if t == null:
		return
	if t is String:
		var s: String = t
		if s == "back":
			exit_to(int(back_remap.get(previous, previous)))
		elif s == "pop":
			pop()
		elif s.begins_with("push:"):
			var what := s.substr(5)
			push(int(what) if what.is_valid_int() else what)
	else:
		exit_to(int(t), {}, screen_id != MwScreens.BOOT)
