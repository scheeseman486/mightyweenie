class_name MwTitleScreen
extends MwScreen
## Screen 0 (`screen_00_title`, $0FF0): the developer logo, the animated
## title and the legal/credit pages over the scrolling starfield, in that
## order, then the main menu (docs/re/title.md).
##
## The port's front menu (plan 21, [member MwSettings.front_menu]) takes the
## credits' place: after the title's fade-out the front menu (100) follows.
## The front menu enters this screen again with `{"credits": true}` (the
## credits roll alone, then back to the front menu) or `{"title": true}`
## (Menu Back: the title without the developer logo).
##
## Everything runs on the screen's passes (one per tick in menus) and the
## ticks they report, like the original's loops: [member t] counts ticks
## since entering. Full-screen fades use the router's fader; the credit
## text fades on its own ([MwFade]) over the starfield. Pictures, sprites,
## fonts, strings and palettes come from the ROM; the scene holds where
## they go. [signal milestone] reports the same milestones as
## compare/fixtures/title_timeline.json (the original's timeline).

## A milestone of the original's timeline (name as in the fixture) at tick [param at].
signal milestone(name: String, at: int)

enum Part { LOGO_LOAD, LOGO, LOGO_OUT, TITLE_LOAD, TITLE, TITLE_OUT, CREDITS_LOAD, CREDITS_IN,
		PAGE_DRAW, PAGE_IN, PAGE_HOLD, PAGE_OUT, CREDITS_OUT, DONE }

## Standard fade ($20).
const FADE := 32
## Credit page fades and the final ones ($1E).
const PAGE_FADE := 30
## Entry -> the logo's timing starts (instant fade-out, loading).
const LOGO_LOAD_TICKS := 4
const LOGO_TICKS := 180
## Logo faded out -> title shown (freeing and loading).
const TITLE_LOAD_TICKS := 1
## d7 = $834 at $106C.
const TITLE_TICKS := 2100
const BAND_TICKS := 7
## Title faded out -> credits start.
const CREDITS_LOAD_TICKS := 2
## Page start -> its fade-in (drawing; 1 tick on most pages).
const PAGE_DRAW_TICKS := 1
const PAGE_HOLD_TICKS := 120
## Credit page string lists (pointers), shown in order.
const PAGES := 0x1BB5C
const PAGE_COUNT := 19
## Rows and centring of `credits_draw_page` ($DD4).
const HEADING_ROW := 7
const BODY_ROW := 11
const BODY_STEP := 3
const COLUMNS := 40
const FONT_FIRST_PAGE := "font_0447f4"
const FONT_HEADING := "font_022bec"
const FONT_BODY := "font_022ee0"
## The last page's two sprite records (`credits_last_page_sprites` $FB4):
## x, y (sprite coordinates, +128), depth, attr XOR, frame address; the
## second at $1BB4E + the word at $1BB5A.
const LAST_PAGE_SPRITES := 0x1BB42
const LAST_PAGE_SECOND := 0x1BB4E
const LAST_PAGE_OFFSETS := 0x1BB5A
## Sparkles: `rng & $15A2 == 0` starts an idle one (`title_sparkles_spawn`).
const SPARKLE_MASK := 0x15A2

@onready var logo: RomTileMapLayer = $Logo
@onready var title: Node2D = $Title
@onready var bands: Array[RomTileMapLayer] = [$Title/Band0, $Title/Band1, $Title/Band2, $Title/Band3]
@onready var sparkles: Array[RomSprite] = [$Title/Sparkles/Sparkle0, $Title/Sparkles/Sparkle1, $Title/Sparkles/Sparkle2]
@onready var eyes: Array[RomSprite] = [$Title/EyeLeft, $Title/EyeRight]
@onready var drip: RomSprite = $Title/Drip
@onready var credits: Node2D = $Credits
@onready var starfield: RomStarfield = $Credits/Starfield
@onready var page_root: Node2D = $Credits/Page
@onready var credits_palette: RomPalette = $Credits/Starfield.palette

var part := Part.LOGO_LOAD
## Ticks since entering the screen.
var t := 0
## Title: ticks left (the original's d7).
var title_left := 0
## Title: which band is shown, and the tick the band timer counts from.
var band := 0
var band_since := 0
## Credits: the page being shown (0-18), and the fade of its text.
var page := -1
var text_fade := MwFade.new()

var _mark := 0
var _skipped := false
## The credits roll alone, for the front menu (plan 21).
var _credits_only := false
var _back_pressed := false


func _ready() -> void:
	fades_in_itself = true


func _enter_screen(data: Dictionary) -> void:
	logo.visible = false
	title.visible = false
	credits.visible = false
	if fader:
		fader.cover()             # the instant fade-out (D1 = 1)
	if data.get("credits", false):
		_credits_only = true
		part = Part.CREDITS_LOAD
	elif data.get("title", false):
		MwSound.music_title()     # kept if it plays
		part = Part.TITLE_LOAD


func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	t += elapsed
	var pressed := _pressed(input)
	match part:
		Part.LOGO_LOAD:
			if t >= LOGO_LOAD_TICKS:
				logo.visible = true
				_fade_in(FADE)            # line 2 -> $3BF7A
				_mark = t
				part = Part.LOGO
				milestone.emit("logo_start", t)
		Part.LOGO:
			if pressed or t - _mark >= LOGO_TICKS:
				_fade_out(FADE)
				part = Part.LOGO_OUT
				milestone.emit("logo_end", t)
		Part.LOGO_OUT:
			if not _fading():
				logo.visible = false
				_mark = t
				part = Part.TITLE_LOAD
				MwSound.music_title()     # `$1052`: the title music, after the logo's fade
		Part.TITLE_LOAD:
			if t - _mark >= TITLE_LOAD_TICKS:
				_title_start()
				_title_pass(1, false)     # the first pass counts 1 tick
		Part.TITLE:
			_title_pass(elapsed, pressed)
		Part.TITLE_OUT:
			_title_animate(elapsed)       # the loop keeps animating while fading
			if not _fading():
				title.visible = false
				_mark = t
				part = Part.CREDITS_LOAD
				if MwSettings.front_menu:
					part = Part.DONE      # the port's front menu instead of the credits
					exit_to(MwScreens.FRONT_MENU, {}, false)
		Part.CREDITS_LOAD:
			if t - _mark >= CREDITS_LOAD_TICKS:
				_credits_start()
		_:
			_back_pressed = input != null and input.is_pressed("ui_back")
			_credits_pass(elapsed, pressed)


## Any new press of Start, A, B or C (any pad: menu verbs are shared).
static func _pressed(input: MwInputFrame) -> bool:
	if input == null:
		return false
	for a in ["ui_accept", "ui_option_a", "ui_option_b", "ui_option_c"]:
		if input.is_pressed(a):
			return true
	return false


# --- title -------------------------------------------------------------------------------------
func _title_start() -> void:
	title.visible = true
	part = Part.TITLE
	title_left = TITLE_TICKS
	band = 0
	band_since = t
	_show_band()
	drip.restart()
	for e in eyes:
		e.restart()
	for s in sparkles:
		s.visible = false
	milestone.emit("title_start", t)
	_fade_in(FADE)                    # lines 0/1 -> $36C64 / $36C84
	milestone.emit("title_fade_in", t)


func _title_pass(elapsed: int, pressed: bool) -> void:
	_title_animate(elapsed)
	title_left -= elapsed
	if pressed or title_left <= 0:
		_fade_out(FADE)
		part = Part.TITLE_OUT
		milestone.emit("title_fade_out", t)


## One pass of the title loop's drawing work ($108E-$10BC, $10F6).
func _title_animate(elapsed: int) -> void:
	var rng: MlhRng = session.rng if session else null
	if rng:
		rng.next_state()
	_spawn_sparkles(rng)
	drip.advance(elapsed)
	for e in eyes:
		e.advance(elapsed)
	for s in sparkles:
		if s.visible:
			s.advance(elapsed)
			s.visible = s.is_running()
	_step_band()
	if rng:
		rng.next_state()


## `title_sparkles_spawn` ($134C): each idle sparkle may start.
func _spawn_sparkles(rng: MlhRng) -> void:
	if rng == null:
		return
	for s in sparkles:
		if s.visible:
			continue
		if rng.next_state() & SPARKLE_MASK == 0:
			s.position = Vector2(sparkle_position(rng))
			s.restart()
			s.visible = true


## `title_sparkle_position` ($130E): y in 24-104, x in 24-296, x re-rolled
## while the sparkle would sit over the middle of the logo.
static func sparkle_position(rng: MlhRng) -> Vector2i:
	var y := rng.range_value(24, 104)
	var x := rng.range_value(24, 296)
	while y > 27 and x >= 76 and x <= 209:
		x = rng.range_value(24, 296)
	return Vector2i(x, y)


## `title_band_step` ($1194): next band once 7 ticks have passed (the
## remainder is kept; one band per pass at most).
func _step_band() -> void:
	var d := t - band_since
	if d >= BAND_TICKS:
		band_since = t - (d - BAND_TICKS)
		band = (band + 1) % bands.size()
		_show_band()


func _show_band() -> void:
	for i in bands.size():
		bands[i].visible = i == band


# --- credits -----------------------------------------------------------------------------------
func _credits_start() -> void:
	credits.visible = true
	part = Part.CREDITS_IN
	if session:
		starfield.start(session.rng_aux)
	_fade_in(FADE)                    # screen_palette: the starfield fades in
	milestone.emit("credits", t)


func _credits_pass(elapsed: int, pressed: bool) -> void:
	for i in elapsed:
		starfield.step()              # VBlank task
		text_fade.step()
		if session:
			session.rng.next_state()  # the waits call rng_main_next every tick
	if part == Part.DONE:
		return
	if _credits_only and (pressed or (_back_pressed and part != Part.CREDITS_OUT)) and not _skipped:
		_skipped = true               # the front menu's credits: back to it
		part = Part.DONE
		exit_to(MwScreens.FRONT_MENU)
		return
	if pressed and part != Part.CREDITS_OUT and not _skipped:
		# Skip: the original starts a music fade and a 30-tick fade-out but
		# enters the main menu at once; the menu's own palette replaces the
		# fade's targets after a few ticks of loading with the display off
		# (GPGX), so the menu shows without going black: no fade here.
		_skipped = true
		MwSound.music_fade_out(30)    # `$F78` (the skip leaves the loop for it too)
		milestone.emit("credits_end", t)
		part = Part.DONE
		exit_to(1, {}, false)
		return
	match part:
		Part.CREDITS_IN:
			if not _fading():
				_page_start(0)
		Part.PAGE_DRAW:
			if t - _mark >= PAGE_DRAW_TICKS:
				text_fade.fade_in(PAGE_FADE)
				part = Part.PAGE_IN
				milestone.emit("page_fade_in", t)
		Part.PAGE_IN:
			if not text_fade.busy():
				_mark = t
				part = Part.PAGE_HOLD
		Part.PAGE_HOLD:
			if t - _mark >= PAGE_HOLD_TICKS:
				text_fade.fade_out(PAGE_FADE)
				part = Part.PAGE_OUT
				milestone.emit("page_fade_out", t)
		Part.PAGE_OUT:
			if not text_fade.busy():
				_clear_page()
				if page + 1 < PAGE_COUNT:
					_page_start(page + 1)
				else:
					if not _credits_only:
						MwSound.music_fade_out(30)    # `$F78` (the front menu's title music goes on)
					_fade_out(PAGE_FADE)
					part = Part.CREDITS_OUT
					milestone.emit("credits_end", t)
		Part.CREDITS_OUT:
			if not _fading():
				part = Part.DONE
				milestone.emit("credits_done", t)
				exit_to(MwScreens.FRONT_MENU if _credits_only else 1, {}, false)


## Draw page [param index] (`credits_draw_page`), black until it fades in.
func _page_start(index: int) -> void:
	page = index
	_mark = t
	part = Part.PAGE_DRAW
	milestone.emit("page", t)
	text_fade = MwFade.new()
	text_fade.set_level(0.0)
	if not MwRom.available():
		return
	var rom := MwRom.data()
	var strings := MwGfx.string_list(rom, MwGfx.u32(rom, PAGES + 4 * index))
	for i in strings.size():
		var line := RomText.new()
		line.font = FONT_FIRST_PAGE if index == 0 else (FONT_HEADING if i == 0 else FONT_BODY)
		line.string_address = strings[i]
		line.center_in = COLUMNS
		line.cell = Vector2i(0, HEADING_ROW if i == 0 else BODY_ROW + BODY_STEP * (i - 1))
		line.palette = credits_palette
		page_root.add_child(line)
		text_fade.add(line)
	if index == PAGE_COUNT - 1:
		for s in last_page_sprites(rom):
			page_root.add_child(s)
			text_fade.add(s)


## The last page's sprites ($FB4), from the original's records.
func last_page_sprites(rom: PackedByteArray) -> Array[RomSprite]:
	var out: Array[RomSprite] = []
	for a in [LAST_PAGE_SPRITES, LAST_PAGE_SECOND + MwGfx.u16(rom, LAST_PAGE_OFFSETS)]:
		var s := RomSprite.new()
		s.frame_addresses = PackedInt32Array([MwGfx.u32(rom, a + 8)])
		s.attr_xor = MwGfx.u16(rom, a + 6)
		s.palette = credits_palette
		s.position = Vector2(MwGfx.s16(rom, a) - 128, MwGfx.s16(rom, a + 2) - 128)
		out.append(s)
	return out


func _clear_page() -> void:
	for c in page_root.get_children():
		page_root.remove_child(c)
		c.free()


# --- full-screen fades (the router's fader; none in tests without one) -----------------------
func _fade_in(ticks: int) -> void:
	if fader:
		fader.fade_in(ticks)


func _fade_out(ticks: int) -> void:
	if fader:
		fader.fade_out(ticks)


func _fading() -> bool:
	return fader != null and fader.busy()
