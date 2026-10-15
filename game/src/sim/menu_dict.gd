class_name MwMenuDict
extends RefCounted
## Plan 40 (M4): the in-match menus' verbs on their dictionary (the pause
## menu's, MwRinkPhases.menu_press; a player's own menu, MwRinkControl):
## {items, sel, confirm, sure, ask, target} - the shape stays (online, a
## seat's menu is hashed: MwNetHash). The callers keep what the answers do.

## A YES/NO question's verbs ([method confirm_verbs]).
enum { NONE, BACK, MOVED, YES, NO }


## The question's verbs [param v] on menu [param m]: Back or Start closes it
## (BACK); Up or Down moves between YES and NO (MOVED); Select answers (YES
## with "sure" 0, else NO); anything else NONE.
static func confirm_verbs(m: Dictionary, v: Dictionary) -> int:
	if v.get("back", false) or v.get("resume", false):   # first: Start is Menu Accept too
		m["confirm"] = false
		return BACK
	if v.get("up", false) or v.get("down", false):
		m["sure"] = 1 - int(m["sure"])
		return MOVED
	if v.get("select", false):
		return YES if int(m["sure"]) == 0 else NO
	return NONE


## Up or Down in [param v] move menu [param m]'s selection round its items;
## true when they did.
static func move(m: Dictionary, v: Dictionary) -> bool:
	if not (v.get("up", false) or v.get("down", false)):
		return false
	m["sel"] = posmod(int(m["sel"]) + (-1 if v.get("up", false) else 1), (m["items"] as Array).size())
	return true
