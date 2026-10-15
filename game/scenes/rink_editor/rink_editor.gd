class_name MwRinkEditor
extends MwScreen
## CREATE-A-TEAM's home rink editor (plan 38, screen 138; owner: 3D only,
## with input verbs of its own for placing objects). The working copy's
## rink ([member MwCustomTeams.editing]:
## the game reads it under [method MwCustomTeams.editing_id]) in the 3D
## view (the host's, [MwRink3DHost]) - set up as a match would set it up
## ([method MwRinkState.setup]) - with the editor's panels either side in
## the port menus' look:
##
## * HOME RINK: NAME (the text entry), COLOURS, NET (standard / Battle
##   Net), GRAVITY (the stadium's +8: players, the puck, everything that
##   flies), HAZARDS, TEST SKATE; the matchup's hazard words.
## * RINK COLOURS: a preset (the ROM's 7 ice palettes) and every colour by
##   its role, each edited by its Genesis levels.
## * PLACE HAZARDS ([constant MwVerbs.Context.RINK_EDIT]): a cursor on the
##   ice (the rink's off-screen arrow over it, the kind's figure under
##   it), place / remove / mirror, the kind; red keep-clear zones (the
##   faceoff line-ups, the bench door) where nothing goes.
## * TEST SKATE (owner, 2026-10-11: one player-controlled character roaming
##   the rink freely, kept very simple): the team's first player alone
##   on the rink, Player 1's, run by the match's own code - its skating,
##   the hazards, the boards, the gravity - with no clock, no phase handler
##   and no puck to play; the camera eases into the player's 3D view (the
##   match's: VIEW, F2-F8, a pad's Select; the controls turned with the
##   side-on and first-person cameras, MwLiveInput.turns) while the panels
##   slide off (left, right, up, down); DONE (Start / Enter) or Esc eases
##   back.
##
## The camera turns and zooms on the view verbs (the right stick). The rink
## shows as the match's 3D views show it, with what VISUALS has on: the
## reflections, the paint and the ice's detail (an MwSplatter of the
## visit's, stepped by the test skate), the flat shadows. Nothing here
## touches a match; the 3D view is left as it was found. The editor's
## music goes on (MwEditorMusic.keep_up).

const SOUND_MOVE := MwSoundIds.MOVE
const SOUND_REFUSED := MwSoundIds.REFUSED
const LIGHT := MwEditorDraw.LIGHT
const DARK := MwEditorDraw.DARK
const MENU := MwEditorDraw.MENU
const VIEW_STEPS := MwScreenPalettes.RINK
## The colours by role (line 0; docs: the ice palette's roles).
const ROLES := [["ICE", [0]], ["SHADES", [4, 5, 6]], ["BOARDS", [7, 8, 9, 10]], ["LINES", [11, 12, 13]],
		["TRIM", [14, 15]], ["WHITES", [1, 2]], ["OUTLINE", [3]]]
const KIND_NAMES := {"thin_ice": "THIN ICE", "pit": "PIT", "hole": "HOLE", "mine": "MINE", "shark": "SHARK",
		"fire": "FIRE", "spikes": "SPIKES"}
const KIND_TEXT := {"thin_ice": "BREAKS", "pit": "SWALLOWS", "hole": "SWALLOWS", "mine": "BLOWS UP",
		"shark": "BITES", "fire": "BURNS", "spikes": "IMPALE"}
## Panels' slide (TEST SKATE): cells off to the sides, rows up / down.
const SLIDE_CELLS := 14
const SLIDE_ROWS := 4
const GLIDE_TICKS := 45.0              ## the camera's glide in and out (ticks)
## TEST SKATE's puck height (rink px): hidden, it rides with the skater -
## the camera follows the puck in play (`$F9DA`) - above the nets' and the
## hazards' reach (20, 4) and below the glass's (32: out of play).
const SKATE_PUCK_Z := 26
## The ice's detail and the paint's seed (the visit's, as the crowd's 77).
const PAINT_SEED := 77
## Cursor speed (rink pixels per tick) and the camera's turn and zoom.
const CURSOR_SPEED := 2
const TURN_DEG := 2.0
const ZOOM_STEP := 0.015

@onready var plane: RomPlane = $Plane
@onready var palette: RomPalette = $Plane.palette
@onready var swatch_layer: Node2D = $Swatches
@onready var cursor_arrow: RomSprite = $Cursor

var rom: PackedByteArray
var team: MwCustomTeam
var id := -1
## rink, colours, colour, place, skate.
var page := "rink"
var rows: Array[Dictionary] = []
var row := 0
var swatch := 0
## The colour edited on the COLOUR panel: its index (0-15), the word on entry.
var colour_index := 0
var colour_undo := 0
var channel := 0
## PLACE HAZARDS: the cursor (rink pixels), the kind, mirrored.
var at := Vector2i(0, 200)
var kind := 0
var mirror := false
## The cursor's move not yet a whole pixel (the camera turned: the screen's
## directions are fractions of the rink's).
var _move_frac := Vector2.ZERO
## The camera: yaw, pitch (degrees), distance (metres), aimed at the ice's centre.
var yaw := 0.0
var pitch := 55.0
var dist := 52.0
var host: MwRink3DHost
var view: MwRinkView3D
var view_palette: RomPalette
var state: MwRinkState
var drawer: MwRinkDraw3D
## TEST SKATE's match (one skater, [method _new_skater]).
var sim: MwRinkSim
var update: MwRinkUpdate
## 0 the editor .. 1 the follow view (panels gone); its direction.
var glide := 0.0
var glide_dir := 0
var _from_transform := Transform3D()
var _from_fov := 50.0
var _panels := {}
var _zones: Array[Node3D] = []
var _dirty := false
var _repeat := MwHoldRepeat.new()
## The visit's paint (plan 37, VISUALS' PAINT on; null off): the ice's
## detail on every page, the test skate's skates and blood on it.
var _splat: MwSplatter = null
## TEST SKATE's prompt frame (under [member plane]); its view
## (MwRinkViews: a 3D one, the player's) and birds-eye layout; Player 1's
## presses since the last pass (a pass every 2 ticks).
var _skate_under: RomPlane
var _skate_view := MwRinkViews.FOLLOW
var _across := false
var _pad_new := 0
var _pad_direct: Array[String] = []


func _enter_screen(_data: Dictionary) -> void:
	resume_fresh = true                    # plan 40, S12: the text entry's time isn't caught up
	if not MwRom.available():
		return
	team = MwCustomTeams.editing
	if team == null:
		exit_to(MwScreens.EDIT_TEAM, {}, false)
		return
	rom = MwRom.data()
	MwEditorMusic.enter()               # the editor's music (MwEditorMusic)
	id = MwCustomTeams.editing_id()
	palette.team_a = id
	palette.stadium = id
	for p in ["left", "right", "top", "bottom"]:
		var n := Node2D.new()
		n.name = p.capitalize()
		add_child(n)
		var under := plane.duplicate() as RomPlane
		var text := plane.duplicate() as RomPlane
		var half := plane.duplicate() as RomPlane     # plan 40 (M1): items centred to the half cell
		half.position = Vector2(4, 0)
		n.add_child(under)
		n.add_child(text)
		n.add_child(half)
		_panels[p] = {"node": n, "under": under, "text": text, "half": half}
	(_panels["top"]["text"] as RomPlane).palette = MwGlyphs.plate_palette(palette)   # the title's grey plate (M2)
	move_child(swatch_layer, get_child_count() - 1)
	move_child(cursor_arrow, get_child_count() - 1)
	plane.visible = false
	_skate_under = plane.duplicate() as RomPlane
	_skate_under.name = "SkateUnder"
	add_child(_skate_under)
	move_child(_skate_under, plane.get_index())
	_skate_under.visible = false
	if MwSettings.splatter:
		_splat = MwSplatter.new(PAINT_SEED)
	view_palette = RomPalette.make(4, PackedStringArray(VIEW_STEPS), id, id)
	view_palette.team_b = id
	host = MwRink3DHost.of(get_tree())
	view = host.borrow(self, view_palette)
	if view != null:
		host.show_for(self, true)
		view.set_camera_mode(MwRinkCamera3D.Mode.FREE)
	_setup_state()
	cursor_arrow.anim = "%X" % MwGfx.u32(rom, MwRinkMatch.ARROWS + 4 * MwPortMenu.ARROW_PAD)
	cursor_arrow.attr_xor = MwPortMenu.ARROW_XOR
	cursor_arrow.variant = MwPortMenu.ARROW_DOWN
	cursor_arrow.visible = false
	_open("rink")


func _exit_tree() -> void:
	if sim != null:
		sim.dispose()                        # plan 45 (a skate left with the editor)
	_clear_zones()
	MwLiveInput.turns = PackedInt32Array()
	if host != null:
		host.release(self)


## The rink as a match sets it up (its hazards and objects, nets, gravity),
## and in PLACE HAZARDS the kind under the cursor.
func _setup_state() -> void:
	rom = MwRom.data()
	state = MwRinkState.new()
	state.rng = MlhRng.new(1)
	state.setup(rom, id)
	state.phase = MwRinkState.PHASE_PLAY          # (set-up phases hide the rink objects: sharks, fires, spikes)
	state.crowd_life = MwCrowdLife.new(77)
	state.splatter = _splat
	if page == "place":
		_ghost()
	drawer = MwRinkDraw3D.new(rom)
	drawer.build(state, [])
	if view != null:
		view.present(state, drawer, {}, false)


## The kind being placed, at the cursor (not placed: shown).
func _ghost() -> void:
	var k: String = MwCustomRink.KIND_ORDER[kind]
	var info: Array = MwCustomRink.KINDS[k]
	var point := _spot()
	if bool(info[0]):
		var rink_object := MwRinkState.RinkObject.new()
		state.objects.append(rink_object)
		state.spawn(rom, rink_object, point.x, point.y, int(info[1]), 0x08 if _mirrored() else 0)
	else:
		var hazard := MwRinkState.Hazard.new()
		hazard.x = point.x
		hazard.y = point.y
		hazard.kind = int(info[1])
		state.hazards.append(hazard)


## Where the kind goes for the cursor: there, or for spikes the nearer side
## board ([method MwCustomRink.on_boards]).
func _spot() -> Vector2i:
	if MwCustomRink.KIND_ORDER[kind] == "spikes":
		return MwCustomRink.on_boards(at.x, at.y)
	return at


## Mirrored: the MIRROR verb's, or spikes' by their side (facing the ice).
func _mirrored() -> bool:
	return _spot().x > 0 if MwCustomRink.KIND_ORDER[kind] == "spikes" else mirror


# --- pages --------------------------------------------------------------------------------------
func _open(text: String, r := 0) -> void:
	page = text
	rows.clear()
	match text:
		"rink":
			for a in [["name", "NAME"], ["colours", "COLOURS"], ["net", "NET"], ["gravity", "GRAVITY"],
					["hazards", "HAZARDS"]]:
				rows.append({"action": a[0], "label": a[1]})
			rows.append({"action": "skate", "label": "TEST SKATE", "item": true})
			pitch = 55.0
			dist = 52.0
		"colours":
			rows.append({"action": "preset", "label": "PRESET"})
			for i in ROLES.size():
				rows.append({"action": "role", "label": ROLES[i][0], "index": i})
		"colour":
			for i in 3:
				rows.append({"action": "channel", "label": ["RED", "GREEN", "BLUE"][i], "index": i})
		"place":
			pitch = 72.0
			dist = 46.0
	row = clampi(r, 0, maxi(rows.size() - 1, 0))
	if text == "place":
		_show_zones()
	else:
		_clear_zones()
	_setup_state()
	_draw()


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty() or team == null:
		return
	MwEditorMusic.keep_up()
	if page == "skate" or glide_dir != 0:
		_skate_pass(elapsed, input)
	_glide(elapsed)
	if input == null:
		return
	_turn(input, elapsed)
	match page:
		"place":
			_place_pass(input, elapsed)
		"skate":
			# DONE (Start / Enter): the face buttons and Back are the skater's
			if glide_dir >= 0 and input.is_pressed("rink_done"):
				_leave_skate()
		_:
			_menu_pass(input, elapsed)


## TEST SKATE: Esc (the permanent Menu Back key, on no gameplay verb) eases
## back; the match's views - VIEW, F2-F8, a pad's Select ([method _view_picked]).
func _unhandled_input(event: InputEvent) -> void:
	if page != "skate" or glide_dir < 0 or rom.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == MwInputMap.BACK_KEY:
		get_viewport().set_input_as_handled()
		_leave_skate()
		return
	var v := _view_picked(event)
	if v >= 0:
		get_viewport().set_input_as_handled()
		if v == MwRinkViews.BIRDS_EYE and _skate_view == v:
			_across = not _across
		_skate_view = v
		if session:
			MwRinkViews.select(session, v)      # the player's choice, as in a match
		_update_turns()


## The view [param event] picks in TEST SKATE (-1 none): the match's
## (MwRinkViews.picked), but never 2D - the editor is 3D only (owner): VIEW
## goes between the follow camera and 3D EXTENDED, Select steps past 2D,
## F1 does nothing.
func _view_picked(event: InputEvent) -> int:
	var v := MwRinkViews.picked(event, _skate_view, true)
	if v != MwRinkViews.FLAT:
		return v
	if event.is_action_pressed(MwInputMap.VIEW_TOGGLE, false, true):
		return MwRinkViews.EXTENDED if _skate_view == MwRinkViews.FOLLOW else MwRinkViews.FOLLOW
	if event.is_action_pressed(MwInputMap.VIEW_NEXT, false, true):
		return MwRinkViews.next(v)
	return -1


## The view verbs: turn the camera around the rink, zoom it.
func _turn(input: MwInputFrame, elapsed: int) -> void:
	var t := 0.0
	if input.held.has("rink_view_left"):
		t -= 1.0
	if input.held.has("rink_view_right"):
		t += 1.0
	yaw = fposmod(yaw + t * TURN_DEG * elapsed, 360.0)
	if input.held.has("rink_view_in"):
		dist = maxf(dist * (1.0 - ZOOM_STEP * elapsed), 18.0)
	if input.held.has("rink_view_out"):
		dist = minf(dist * (1.0 + ZOOM_STEP * elapsed), 110.0)


func _menu_pass(input: MwInputFrame, elapsed := 1) -> void:
	if not rows.is_empty():
		var n := _repeat.step(input, elapsed, str(rows[row]["action"]) in ["gravity", "channel"])
		if n != 0:
			_change(n, true)
			return
	if input.is_pressed("ui_back"):
		_back()
	elif input.is_pressed("ui_up"):
		_move(-1)
	elif input.is_pressed("ui_down"):
		_move(1)
	elif input.is_pressed("ui_left"):
		_change(-1)
	elif input.is_pressed("ui_right"):
		_change(1)
	elif input.is_pressed("ui_accept"):
		_accept()
	elif input.is_pressed("ui_editor_next") and page == "colours":
		_preset(1)
	elif input.is_pressed("ui_editor_previous") and page == "colours":
		_preset(-1)
	elif input.is_pressed("ui_editor_delete") and page == "colour":
		_set_colour(colour_index, colour_undo)


func _move(d: int) -> void:
	if rows.is_empty():
		return
	row = posmod(row + d, rows.size())
	swatch = 0
	MwSound.play(SOUND_MOVE)
	_draw()


func _back() -> void:
	MwSound.play(SOUND_MOVE)
	match page:
		"rink":
			if session:
				var st: Dictionary = session.screens.get(MwScreens.EDIT_TEAM, {})
				st["dirty"] = bool(st.get("dirty", false)) or _dirty
				session.screens[MwScreens.EDIT_TEAM] = st
			exit_to(MwScreens.EDIT_TEAM)
		"colours":
			_open("rink", 1)
		"colour":
			_open("colours", 1 + _role_of(colour_index))
		"place":
			_open("rink", 4)


func _change(d: int, repeat := false) -> void:
	var r := rows[row]
	var custom_rink := team.rink
	match str(r["action"]):
		"net":
			custom_rink.net = 2 if custom_rink.net == 1 else 1
		"gravity":
			custom_rink.gravity = clampi(custom_rink.gravity - 2 * d, MwCustomRink.GRAVITY_MIN,
					MwCustomRink.GRAVITY_MAX)
		"colours", "preset":
			_preset(d)
			return
		"role":
			var n: int = ROLES[r["index"]][1].size()
			swatch = posmod(swatch + d, n)
			MwSound.play(SOUND_MOVE)
			_draw()
			return
		"channel":
			var lv := MwEditorDraw.levels(_colours()[colour_index])
			lv[r["index"]] = clampi(int(lv[r["index"]]) + d, 0, 7)
			_set_colour(colour_index, MwEditorDraw.word(lv))
			return
		_:
			return
	if not repeat or _repeat.sound_due():
		MwSound.play(SOUND_MOVE)
	_edited()


func _accept() -> void:
	var r := rows[row]
	MwSound.play(SOUND_MOVE)
	match str(r["action"]):
		"name":
			push(MwScreens.TEXT_ENTRY, {"field": MwCreateTeam.team_text("rink_name", "RINK NAME", team.rink.name,
					MwCustomRink.NAME_MAX)})
		"colours":
			_open("colours")
		"hazards":
			_open("place")
		"skate":
			_start_skate()
		"role":
			colour_index = int(ROLES[r["index"]][1][swatch])
			colour_undo = _colours()[colour_index]
			_open("colour")
		"channel":
			_open("colours", 1 + _role_of(colour_index))


func _resume_screen(r := {}) -> void:
	if bool(r.get("done", false)) and str(r.get("key", "")) == "rink_name":
		team.rink.name = str(r.get("text", ""))
		_edited()
	_draw()


## The rink changed: kept valid, shown to the game again, set up again.
func _edited() -> void:
	_dirty = true
	MwCustomTeams.edited()
	rom = MwRom.data()
	view_palette.refresh()                      # the 3D rink's colours follow at once (owner)
	_setup_state()
	_draw()


func _colours() -> PackedInt32Array:
	return team.rink.palette(MwRom.archive().bytes())


func _set_colour(i: int, w: int) -> void:
	var c := _colours().duplicate()
	c[i] = w & 0x0EEE
	team.rink.colours = c
	MwSound.play(SOUND_MOVE)
	_edited()


## The next preset (the edits dropped: the preset's colours).
func _preset(d: int) -> void:
	team.rink.preset = posmod(team.rink.preset + d, MwCustomTeams.PRESETS)
	team.rink.colours = PackedInt32Array()
	MwSound.play(SOUND_MOVE)
	_edited()


func _role_of(i: int) -> int:
	for k in ROLES.size():
		if i in ROLES[k][1]:
			return k
	return 0


# --- placing --------------------------------------------------------------------------------------
func _place_pass(input: MwInputFrame, elapsed: int) -> void:
	if input.is_pressed("ui_back") or input.is_pressed("rink_done"):
		_back()
		return
	var d := Vector2i.ZERO
	var pressed := Vector2i.ZERO
	for v in [["ui_left", Vector2i.LEFT], ["ui_right", Vector2i.RIGHT], ["ui_up", Vector2i.UP],
			["ui_down", Vector2i.DOWN]]:
		if input.held.has(v[0]):
			d += v[1]
		if input.is_pressed(v[0]):
			pressed += v[1]
	if d != Vector2i.ZERO:
		# the cursor moves on the screen's axes, turned with the camera: the
		# rink's x and y take their parts of it, the fractions kept for the
		# next pass (a slightly turned camera still moves the cursor the way
		# the press points, not along the rink's nearest axis)
		var f := screen_to_rink(Vector2(d)) * CURSOR_SPEED * elapsed + _move_frac
		var step := Vector2i(roundi(f.x), roundi(f.y))
		_move_frac = f - Vector2(step)
		if MwCustomRink.KIND_ORDER[kind] == "spikes":
			# along the side board it is on (the rink's y part of the move);
			# a fresh press pointing across the rink (its x part the larger),
			# towards the other side board on the screen, jumps to that board -
			# held, it stays (owner, 2026-10-12: the spikes' place went wrong
			# with the camera turned, a slant of the press jumping them over)
			var side := 1 if at.x > 0 else -1
			if pressed != Vector2i.ZERO:
				var g := screen_to_rink(Vector2(pressed))
				if absf(g.x) > absf(g.y) and signf(g.x) == -side:
					side = -side
			_move_frac.x = 0.0
			at = MwCustomRink.on_boards(side, at.y + step.y)
		else:
			at = MwCustomRink.on_ice(at.x + step.x, at.y + step.y)     # (in the corners, inside the boards' curve)
		_setup_state()
		_draw()
	else:
		_move_frac = Vector2.ZERO
	if input.is_pressed("rink_place"):
		_place()
	elif input.is_pressed("rink_remove"):
		_remove()
	elif input.is_pressed("rink_mirror"):
		if MwCustomRink.KIND_ORDER[kind] == "spikes":
			at = MwCustomRink.on_boards(-_spot().x, at.y)     # spikes: the other side board
		else:
			mirror = not mirror
		MwSound.play(SOUND_MOVE)
		_setup_state()
		_draw()
	elif input.is_pressed("rink_kind_next") or input.is_pressed("rink_kind_previous"):
		kind = posmod(kind + (1 if input.is_pressed("rink_kind_next") else -1), MwCustomRink.KIND_ORDER.size())
		if MwCustomRink.KIND_ORDER[kind] == "spikes":
			at = _spot()
		MwSound.play(SOUND_MOVE)
		_setup_state()
		_draw()


## A direction on the screen ([param d]: x right, y down) as one on the rink
## (px: x east, y south), turned with the camera's [member yaw].
func screen_to_rink(d: Vector2) -> Vector2:
	return d.rotated(-deg_to_rad(yaw))


## The kind at the cursor, unless a keep-clear zone or the most hazards a rink holds says no.
func _place() -> void:
	var k: String = MwCustomRink.KIND_ORDER[kind]
	var point := _spot()
	if MwCustomRink.blocked(k, point.x, point.y) or team.rink.hazards.size() >= MwCustomRink.HAZARDS_MAX:
		MwSound.play(SOUND_REFUSED)
		return
	team.rink.hazards.append({"kind": k, "x": point.x, "y": point.y, "mirror": _mirrored()})
	MwSound.play(SOUND_MOVE)
	_edited()


## The hazard nearest the cursor (within 32 px) taken away.
func _remove() -> void:
	var best := -1
	var best_d := 32.0 * 32.0
	for i in team.rink.hazards.size():
		var h: Dictionary = team.rink.hazards[i]
		var dd := Vector2(int(h["x"]) - at.x, int(h["y"]) - at.y).length_squared()
		if dd <= best_d:
			best = i
			best_d = dd
	if best < 0:
		MwSound.play(SOUND_REFUSED)
		return
	team.rink.hazards.remove_at(best)
	MwSound.play(SOUND_MOVE)
	_edited()


## The keep-clear zones on the ice, translucent red.
func _show_zones() -> void:
	_clear_zones()
	if view == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.0, 0.0, 0.6)
	for r: Rect2i in MwCustomRink.ZONES:
		var m := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(r.size) * MwRink3D.METRES_PER_PX
		m.mesh = pm
		m.material_override = mat
		m.position = MwRink3D.world(r.get_center().x, r.get_center().y, 0.6)
		view.world.add_child(m)
		_zones.append(m)


func _clear_zones() -> void:
	for z in _zones:
		if is_instance_valid(z):
			z.queue_free()
	_zones.clear()


# --- TEST SKATE -------------------------------------------------------------------------------------
var _skate_ticks := 0


## TEST SKATE: one skater, Player 1's ([method _new_skater]), in the
## player's 3D view; the camera eases into it while the panels slide off.
func _start_skate() -> void:
	_skate_view = session.view if session != null and MwRinkViews.opens_3d(session.view) \
			else MwRinkViews.group(MwSettings.camera_extended())[1]       # (plan 44: the options' group's 3D)
	_across = session.birds_eye_across if session != null else false
	_new_skater()
	_from_camera()
	page = "skate"
	glide_dir = 1
	_skate_ticks = 0
	_pad_new = 0
	_pad_direct.clear()
	_clear_zones()
	_draw()


## The skater on the rink afresh (the start, and after he is gone: dead,
## swallowed): a match set up as the original sets one up (`$5572`: the
## rink, both teams; pad mode 0, Player 1 on team A) with every slot but
## team A's first emptied, him lined up at centre ice (`$3A28`: Player 1's)
## and play on - no clock (its widget off), no phase handler, the puck
## hidden and out of reach ([method _hold_puck]).
func _new_skater() -> void:
	var s := MwRinkState.new()
	s.rng = MlhRng.new(1)
	if sim != null:
		sim.dispose()                        # plan 45: the last skate's sim let go of
	sim = MwRinkSim.new(rom, s)
	sim.cpu = MwRinkAI.new()
	update = MwRinkUpdate.new(sim)
	MwReplay3D.use(update)
	MwRinkMatch.start(sim, id, id, id, 0, false, 2)
	for t in 2:
		for p in s.teams[t].players:
			if t != 0 or p.index != 0:
				p.record = 0
	var x := MwGfx.s16(rom, MwRinkMatch.SPOTS)
	var y := MwGfx.s16(rom, MwRinkMatch.SPOTS + 2)
	s.camera.place(rom, x, y - 0x38)
	MwRinkMatch.lineup(sim, s.teams[0], x, y)
	s.phase = MwRinkState.PHASE_PLAY
	s.crowd_life = MwCrowdLife.new(77)
	s.splatter = _splat
	state = s
	drawer = update.drawer as MwRinkDraw3D
	_hold_puck()
	update.draws()
	if view != null:
		view.present(s, drawer, {}, false)


## The skater: team A's player Player 1 drives (null once gone).
func _skater() -> MwRinkState.Player:
	for p in sim.s.teams[0].players:
		if p.present and p.flags & MwRinkState.Player.HUMAN:
			return p
	return null


## The puck, hidden, rides with the skater (the camera follows it), where
## nothing can take it: locked as after a poke (`$519A`, renewed each pass)
## and [constant SKATE_PUCK_Z] up.
func _hold_puck() -> void:
	var s := sim.s
	var pk := s.puck
	pk.flags = MwRinkState.Puck.HIDDEN
	pk.lock |= 1
	pk.take_tick = s.tick
	var p := _skater()
	if p != null:
		var skater_pos := p.motion.pixels()
		pk.motion.init(skater_pos.x, skater_pos.y, SKATE_PUCK_Z)


func _from_camera() -> void:
	if view != null:
		_from_transform = view.camera.transform
		_from_fov = view.camera.fov


## TEST SKATE's passes (2 ticks each, the rink's): Player 1's pad
## (MwGameplayPads, its presses kept between passes), the match's pass
## (MwRinkUpdate.run_pass, the rink's own without a phase handler: the
## segment, the camera, the draw, the crowd and the paint); a skater gone
## comes back at centre ice.
func _skate_pass(elapsed: int, input: MwInputFrame) -> void:
	if sim == null:
		return
	var r := MwGameplayPads.read(input if page == "skate" and glide_dir >= 0 else null, 1)
	_pad_new |= int(r["new"])
	_pad_direct.append_array(r["direct"])
	_skate_ticks += elapsed
	var e := MwPassClock.RINK_PASS_TICKS
	while _skate_ticks >= e:
		_skate_ticks -= e
		var s := sim.s
		update.run_pass(e, null, _skate_pads.bind(r), _hold_puck)
		if s.phase != MwRinkState.PHASE_PLAY or _skater() == null:
			_new_skater()
		elif view != null:
			view.present(s, drawer, {}, true)
		if view != null:
			view.pass_shown(e, -1, view.auto_blend)   # rendered frames blend towards this pass
	_update_turns()


## A skate pass's pad: Player 1's, its presses since the pass before.
func _skate_pads(r: Dictionary) -> void:
	var s := sim.s
	s.pads_held[0] = int(r["held"])
	s.pads_new[0] = _pad_new
	s.pad_sticks[0] = r["stick"]
	s.pad_heights[0] = int(r["height"])
	sim.human.direct[0] = _pad_direct.duplicate()
	_pad_new = 0
	_pad_direct.clear()


## The pads' turns for the skate's view (MwLiveInput.turns, as the rink's):
## the side-on cameras a quarter, first person by the camera's heading; none
## off the skate.
func _update_turns() -> void:
	var turns := PackedInt32Array()
	if page == "skate" and glide_dir >= 0:
		var t := MwRinkViews.turn(_skate_view, _across)
		if _skate_view == MwRinkViews.FIRST_PERSON and view != null:
			t = view.camera.turn_eighths()
		turns.resize(MwVerbs.PLAYERS)
		turns.fill(t)
	MwLiveInput.turns = turns


## DONE: the camera eases back to the editor's.
func _leave_skate() -> void:
	MwSound.play(SOUND_MOVE)
	glide_dir = -1
	_from_camera()
	_update_turns()


func _end_skate() -> void:
	if sim != null:
		sim.dispose()                        # plan 45: its cycle would keep the skate's state
	sim = null
	update = null
	page = "rink"
	MwLiveInput.turns = PackedInt32Array()
	_setup_state()
	_draw()


# --- the camera, the panels' slide, the cursor --------------------------------------------------------
## The editor's camera: around the ice's centre at [member yaw], [member pitch], [member dist].
func _editor_transform() -> Transform3D:
	var centre := MwRink3D.world(0, 30 if page != "place" else 0, 0)
	var pitch_radians := deg_to_rad(pitch)
	var back := Vector3(0, sin(pitch_radians), cos(pitch_radians)).rotated(Vector3.UP, deg_to_rad(yaw)) * dist
	var eye := centre + back
	return Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)


## The glide in or out on the tick (the camera shows it, [method _process]).
func _glide(elapsed: int) -> void:
	if glide_dir > 0:
		glide = minf(glide + elapsed / GLIDE_TICKS, 1.0)
		if glide >= 1.0:
			glide_dir = 0
	elif glide_dir < 0:
		glide = maxf(glide - elapsed / GLIDE_TICKS, 0.0)
		if glide <= 0.0:
			glide_dir = 0
			_end_skate()


## Presentation only: the camera placed for the frame - the editor's, the
## glide's, the follow camera - the panels slid by the glide, the cursor.
func _process(delta: float) -> void:
	if view == null or team == null or rom.is_empty():
		return
	var cam := view.camera
	var mode := MwRinkViews.camera_mode(_skate_view, _across)
	view.auto_blend = page == "skate" and glide_dir == 0      # the match's blending between passes
	if glide_dir > 0:
		# the glide into the view (MwRinkCamera3D.blend_view, the match's opening's:
		# the heading the short way round, no roll); its frame as the view places it now
		view.set_camera_mode(mode)
		view.blend_to(1.0, delta)
		var to := cam.transform
		var to_fov := cam.fov
		var eased := smoothstep(0.0, 1.0, glide)
		view.set_camera_mode(MwRinkCamera3D.Mode.FREE)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.transform = MwRinkCamera3D.blend_view(_from_transform, to, eased)
		cam.fov = lerpf(_from_fov, to_fov, eased)
		view.blend_to(1.0, 0.0)
	elif glide_dir < 0:
		var eased := smoothstep(0.0, 1.0, glide)
		view.set_camera_mode(MwRinkCamera3D.Mode.FREE)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.transform = MwRinkCamera3D.blend_view(_editor_transform(), _from_transform, eased)
		cam.fov = lerpf(50.0, _from_fov, eased)
		view.blend_to(1.0, 0.0)
	elif page == "skate":
		view.set_camera_mode(mode)            # (the view blends itself: auto_blend)
	else:
		view.set_camera_mode(MwRinkCamera3D.Mode.FREE)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.near = 0.1
		cam.far = 400.0
		cam.fov = 50.0
		cam.transform = _editor_transform()
		view.blend_to(1.0, delta)
	_slide()
	_place_cursor()


## The panels off to their sides by the camera's glide (0 in place .. 1 gone).
func _slide() -> void:
	var eased := smoothstep(0.0, 1.0, glide)
	if _panels.is_empty():
		return
	(_panels["left"]["node"] as Node2D).position.x = -8 * SLIDE_CELLS * eased
	(_panels["right"]["node"] as Node2D).position.x = 8 * SLIDE_CELLS * eased
	(_panels["top"]["node"] as Node2D).position.y = -8 * SLIDE_ROWS * eased
	(_panels["bottom"]["node"] as Node2D).position.y = 8 * SLIDE_ROWS * eased
	swatch_layer.position.x = -8 * SLIDE_CELLS * eased


## PLACE HAZARDS' cursor: the off-screen arrow over the point on the ice.
func _place_cursor() -> void:
	cursor_arrow.visible = page == "place"
	if page != "place":
		return
	var point := view.camera.unproject_position(view.world.to_global(MwRink3D.world(at.x, at.y, 0)))
	var k := host.view_size.x / maxf(host.viewport.size.x, 1.0)
	cursor_arrow.position = (point * k).round() - Vector2(0, 14)


# --- drawing --------------------------------------------------------------------------------------
func _p(panel: String, which: String) -> RomPlane:
	return _panels[panel][which]


func _draw() -> void:
	if _panels.is_empty():
		return
	for p in _panels:
		_p(p, "under").clear()
		_p(p, "text").clear()
		_p(p, "half").clear()
	for c in swatch_layer.get_children():
		c.queue_free()
	plane.clear()
	plane.visible = page == "skate"
	_skate_under.clear()
	_skate_under.visible = plane.visible
	match page:
		"rink":
			_draw_rink()
		"colours", "colour":
			_draw_colours()
		"place":
			_draw_place()
		"skate":
			# on the planes that stay (the panels slide off), framed as the panels' hints
			MwGlyphs.black_frame(_skate_under, rom, 1, 26, 38, 1)
			MwPrompts.verbs(plane, rom, [[MwVerbs.VIEW_TOGGLE, "VIEW"], ["rink_done", "BACK TO THE EDITOR"]],
					26, MENU)


## The page's title as the port menus' (plan 40, M2, owner): on the grey
## plate, centred to the half cell.
func _title(text: String) -> void:
	MwGlyphs.plate_title(_p("top", "text"), rom, LIGHT, MwEditorDraw.ascii(text), 1, MENU)


func _hints(parts: Array) -> void:
	var bottom_text := _p("bottom", "text")
	MwGlyphs.black_frame(_p("bottom", "under"), rom, 1, 26, 38, 1)
	MwPrompts.verbs(bottom_text, rom, parts, 26, MENU)


func _draw_rink() -> void:
	_title("HOME RINK")
	var l := _p("left", "text")
	MwGlyphs.black_frame(_p("left", "under"), rom, 1, 4, 12, 17)
	var custom_rink := team.rink
	var values := {"name": custom_rink.name, "colours": "PRESET %d%s"
			% [custom_rink.preset + 1, "" if custom_rink.colours.is_empty() else " +"],
			"net": "BATTLE NET" if custom_rink.net == 2 else "STANDARD",
			"gravity": "%d%%" % roundi(100.0 * custom_rink.gravity / MwCustomRink.GRAVITY_DEFAULT),
			"hazards": "%d PLACED" % custom_rink.hazards.size()}
	for i in rows.size():
		var y := 4 + 3 * i
		var sel := i == row
		if rows[i].get("item", false):
			MwEditorDraw.item(l, _p("left", "half"), rom, rows[i]["label"], 1, y, 12, sel, MENU)
			continue
		MwEditorDraw.row(l, rom, rows[i]["label"], values.get(rows[i]["action"], ""), 1, y, 12, sel, MENU, null, 2)
	# the matchup's words for the hazards
	var rt := _p("right", "text")
	var words := []
	var mask := custom_rink.mask()
	for b in 8:
		if mask & (1 << b):
			words.append(MwGfx.rom_string(rom, MwGfx.u32(rom,
					MwMatchup.HAZARD_NAMES + 4 * b)).get_string_from_ascii().to_upper())
	MwGlyphs.black_frame(_p("right", "under"), rom, 27, 4, 12, 2 + maxi(words.size(), 1))
	MwEditorDraw.text(rt, rom, LIGHT, "MATCHUP:", 27, 4, MENU)
	if words.is_empty():
		MwEditorDraw.text(rt, rom, LIGHT, "NO HAZARDS", 28, 6, MENU)
	for i in words.size():
		MwEditorDraw.text(rt, rom, LIGHT, words[i], 28, 6 + i, MENU)
	_hints([["ui_left", "CHANGE"], ["ui_accept", "EDIT"], ["rink_view_left", "TURN"], ["ui_back", "BACK"]])


func _draw_colours() -> void:
	_title("RINK COLOURS")
	var l := _p("left", "text")
	MwGlyphs.black_frame(_p("left", "under"), rom, 1, 4, 12, 17)
	var cols := _colours()
	var list: Array = rows if page == "colours" else []
	if page == "colour":
		list = [{"action": "preset", "label": "PRESET"}]
		for i in ROLES.size():
			list.append({"action": "role", "label": ROLES[i][0], "index": i})
	var sel_row := row if page == "colours" else 1 + _role_of(colour_index)
	for i in list.size():
		var y := 4 if i == 0 else 7 + 2 * (i - 1)
		var sel := i == sel_row
		if i == 0:
			var v := "%d%s" % [team.rink.preset + 1, "" if team.rink.colours.is_empty() else " + EDITS"]
			MwEditorDraw.row(l, rom, list[i]["label"], v, 1, y, 12, sel, MENU, null, 2)
		else:
			MwMenuRow.frame(l, rom, 1, y, 12, sel)
			MwEditorDraw.text(l, rom, MwMenuRow.font(sel), list[i]["label"], 1, y, MENU)
			var indices: Array = ROLES[list[i]["index"]][1]
			var words := PackedInt32Array()
			for k in indices:
				words.append(cols[k])
			var mark := swatch if sel and page == "colours" else (indices.find(colour_index) if sel else -1)
			MwEditorDraw.swatches(swatch_layer, words, 13, y, mark)
	if page == "colour":
		var rt := _p("right", "text")
		MwGlyphs.black_frame(_p("right", "under"), rom, 27, 4, 12, 11)
		var role: Array = ROLES[_role_of(colour_index)]
		var colour_name: String = role[0] + (" %d" % (role[1].find(colour_index) + 1) if role[1].size() > 1 else "")
		MwEditorDraw.text(rt, rom, LIGHT, colour_name, 27, 4, MENU)
		var big := ColorRect.new()
		big.color = MwGfx.color(cols[colour_index])
		big.size = Vector2(96, 15)
		big.position = Vector2(27 * 8, 6 * 8)
		swatch_layer.add_child(big)
		var lv := MwEditorDraw.levels(cols[colour_index])
		for i in 3:
			var y := 10 + 2 * i
			MwEditorDraw.row(rt, rom, rows[i]["label"], "%d OF 7" % int(lv[i]), 27, y, 12, i == row, MENU)
		_hints([["ui_left", "CHANGE"], ["ui_editor_delete", "UNDO"], ["ui_accept", "DONE"]])
	else:
		_hints([["ui_editor_previous", ""], ["ui_editor_next", "PRESET"], ["ui_accept", "EDIT"], ["ui_back", "BACK"]])


func _draw_place() -> void:
	_title("PLACE HAZARDS")
	var l := _p("left", "text")
	var n_kinds := MwCustomRink.KIND_ORDER.size()
	# the kinds, then (owner: off the rink) what the red means and a refusal
	MwGlyphs.black_frame(_p("left", "under"), rom, 1, 4, 12, 2 * n_kinds + 6)
	for i in n_kinds:
		var y := 4 + 2 * i
		var sel := i == kind
		if sel:
			MwPlanePainter.frame(l, rom, 1, y, 12, 1, true)
		MwEditorDraw.text(l, rom, DARK if sel else LIGHT, KIND_NAMES[MwCustomRink.KIND_ORDER[i]], 2, y, MENU)
	MwEditorDraw.text(l, rom, LIGHT, "RED ZONES:", 2, 4 + 2 * n_kinds + 1, MENU)
	MwEditorDraw.text(l, rom, LIGHT, "KEEP CLEAR", 2, 4 + 2 * n_kinds + 2, MENU)
	var rt := _p("right", "text")
	MwGlyphs.black_frame(_p("right", "under"), rom, 27, 4, 12, 18)
	var k: String = MwCustomRink.KIND_ORDER[kind]
	MwEditorDraw.text(rt, rom, LIGHT, KIND_NAMES[k], 27, 4, MENU)
	MwEditorDraw.text(rt, rom, LIGHT, KIND_TEXT[k], 27, 5, MENU)
	MwEditorDraw.text(rt, rom, LIGHT, "PLACED", 27, 7, MENU)
	var n := str(team.rink.hazards.size())
	MwEditorDraw.text(rt, rom, LIGHT, n, 39 - MwEditorDraw.width(rom, LIGHT, n), 7, MENU)
	var keys := [[9, "ui_up", "MOVE"], [11, "rink_place", "PLACE"], [13, "rink_remove", "REMOVE"],
			[15, "rink_mirror", "OTHER SIDE" if k == "spikes" else ("MIRROR" if not mirror else "MIRRORED")],
			[17, "rink_kind_next", "KIND"],
			[19, "rink_view_left", "VIEW"], [21, "rink_done", "DONE"]]
	for e in keys:
		MwGlyphs.put_cells(rt, MwGlyphs.verb_cells(e[1]), 27, MwPrompts.row(rom, LIGHT, e[0]))
		MwEditorDraw.text(rt, rom, LIGHT, e[2], 39 - MwEditorDraw.width(rom, LIGHT, e[2]), e[0], MENU)
	var sp := _spot()
	if MwCustomRink.blocked(k, sp.x, sp.y):
		MwEditorDraw.text(l, rom, LIGHT, "NOT HERE!", 2, 4 + 2 * n_kinds + 4, MENU)
