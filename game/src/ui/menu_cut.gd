class_name MwMenuCut
extends RefCounted
## The cuts between the port's starfield screens (owner, 2026-10-10: no
## fade of the whole screen, only of what changes between menus, such as the
## menu text; the starfield's movement, the logo and the raised brick wall up
## top kept the same between menus; 2026-10-11: the starfield fades or cuts
## only towards a screen without one, and the stars keep moving). Leaving for
## another of [constant SCREENS], the page's own layers fade out over
## [constant FADE_TICKS] ([member page]: a CanvasGroup, the page as one
## picture), then a cut, and the next page's fade in over as many; the
## starfield goes on where it was ([member MwSession.menu_stars]); the logo
## and the game setup's hanging top stay put - each fades only where one
## page shows it and the other doesn't.
## Plan 40 (M5): the port menus' (MwPortMenu), CREATE-A-TEAM's list and
## editor and the text entry over them (pushed and popped by cuts too).
## A screen with no starfield (the game, the rink editor) is still a fade.

const FADE_TICKS := 10
## The screens the starfield goes on between: the front menu's pages, the
## replays, the online pages (MwOnlineMenu), CREATE-A-TEAM's list (130), its
## editor (132) and the text entry (131). (The game setup from LOCAL PLAY
## has its own way in: MwPortMenu._local_play.)
const SCREENS: Array[int] = [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 118, 119, 120, 121, 122,
		130, 131, 132]

## The page's own layers, as one ([member CanvasItem.self_modulate] - its
## modulate would reach the layers' own tints), the logo's layer and the
## top's (null: none).
var page: CanvasItem
var logo: CanvasItem
var top: CanvasItem
## The stars carried on, and the session they are carried in (null: none).
var starfield: RomStarfield
var session: MwSession
## The layers' opacity - "page", "logo", "top" - and where each is going.
var alpha := {"page": 1.0, "logo": 1.0, "top": 1.0}
var alpha_to := {"page": 1.0, "logo": 1.0, "top": 1.0}

var _go := Callable()
var _gone := false


func _init(page_: CanvasItem, starfield_: RomStarfield, session_: MwSession, logo_: CanvasItem = null,
		top_: CanvasItem = null) -> void:
	page = page_
	starfield = starfield_
	session = session_
	logo = logo_
	top = top_


## Whether a screen leaves for [param id] by a cut.
static func cuts_to(id: int) -> bool:
	return id in SCREENS


## The layers on entry: by a cut ([param cut]) the page fades in, the logo
## and the top from what the page before showed ([param data]'s "logo",
## "top") to what this one shows; otherwise (a fade, the first screen) as
## this page has them. A screen popped back to enters again.
func enter(cut: bool, data: Dictionary, shows_logo: bool, shows_top := false) -> void:
	_go = Callable()
	_gone = false
	alpha_to = {"page": 1.0, "logo": 1.0 if shows_logo else 0.0, "top": 1.0 if shows_top else 0.0}
	alpha = alpha_to.duplicate()
	if cut:
		alpha["page"] = 0.0
		alpha["logo"] = 1.0 if data.get("logo", true) else 0.0
		alpha["top"] = 1.0 if data.get("top", true) else 0.0
	apply()


## The stars where the screen before left them ([method leave] kept them in
## the session).
func restore_stars() -> void:
	if session != null and starfield != null:
		starfield.restore(session.menu_stars)


## Leaving by a cut: the page fades out, then (the stars kept in the
## session) [param go] is called with the next screen's data - "menu_cut",
## and whether the logo and the top showed. False when already leaving.
func leave(go: Callable) -> bool:
	if leaving():
		return false
	_go = go
	alpha_to["page"] = 0.0
	return true


## On its way out (fading or gone): the screen answers nothing more.
func leaving() -> bool:
	return _go.is_valid() or _gone


## One pass, [param elapsed] ticks on (every pass, first): the fades; while
## leaving the stars move on and, the page faded, the cut. True while
## leaving.
func step(elapsed: int) -> bool:
	var moving := false
	for k: String in alpha:
		var a: float = alpha[k]
		var to: float = alpha_to[k]
		if a != to:
			var d := float(elapsed) / FADE_TICKS
			alpha[k] = minf(a + d, to) if to > a else maxf(a - d, to)
			moving = true
	if moving:
		apply()
	if not leaving():
		return false
	if starfield != null:
		for i in elapsed:
			starfield.step()
	if _go.is_valid() and alpha["page"] <= 0.0:
		var g := _go
		_go = Callable()
		_gone = true
		if session != null and starfield != null:
			session.menu_stars = starfield.state()
		g.call({"menu_cut": true, "logo": alpha["logo"] > 0.5, "top": alpha["top"] > 0.5})
	return true


## The opacities onto the layers.
func apply() -> void:
	if page != null:
		page.self_modulate.a = alpha["page"]
	if logo != null:
		logo.modulate.a = alpha["logo"]
	if top != null:
		top.modulate.a = alpha["top"]
