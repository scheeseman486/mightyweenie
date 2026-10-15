class_name MwInputScript
extends RefCounted
## Input scripts v1 (.mwi): the GDScript twin of harness/mw_harness/script.py.
##
## Format and timing rules: docs/compare.md. Both parsers are checked against
## compare/fixtures/scripts_parse.json. Each event is a Dictionary with the keys
## line, anchor ("screen"/"tick"), screen, visit, unit ("tick"/"pass"), start,
## end (null for a single anchor), player (0 for END), buttons (pad bits),
## mode ("tap"/"hold"/"end") and repeat.

## Genesis pad bits as the game stores them (S A C B R L D U).
const PAD_BITS := {
	"UP": 0x01, "DOWN": 0x02, "LEFT": 0x04, "RIGHT": 0x08,
	"B": 0x10, "C": 0x20, "A": 0x40, "START": 0x80,
}
const BUTTON_ORDER := ["UP", "DOWN", "LEFT", "RIGHT", "B", "C", "A", "START"]

var events: Array[Dictionary] = []
var name := ""
## Empty when the text parsed; otherwise "line N: ...".
var error := ""


## Parses [param text] into a script named [param script_name]: its events, or at the first bad
## line none and [member error] set.
static func parse(text: String, script_name := "") -> MwInputScript:
	var input_script := MwInputScript.new()
	input_script.name = script_name
	var no := 0
	for raw in text.split("\n"):
		no += 1
		var line := _strip_comment(raw.strip_edges())
		if line.is_empty():
			continue
		var event := _parse_line(line, no)
		if event.has("error"):
			input_script.error = event.error
			input_script.events.clear()
			return input_script
		input_script.events.append(event)
	return input_script


## Parses the script file at [param path], named for the file without its extension.
static func load_file(path: String) -> MwInputScript:
	return parse(FileAccess.get_file_as_string(path), path.get_file().get_basename())


## The script's [member events] as text, a line each ([method event_to_text]).
func to_text() -> String:
	var out := ""
	for event in events:
		out += event_to_text(event) + "\n"
	return out


## One of [member events] as a script line: its anchor, then END or the player, buttons and
## mode.
static func event_to_text(event: Dictionary) -> String:
	var when := ""
	if event.anchor == "tick":
		when = "@tick %d" % event.start + ("" if event.end == null else "..%d" % event.end)
	else:
		when = "@screen %d" % event.screen + ("" if event.visit == 1 else " #%d" % event.visit)
		if event.unit == "pass":
			when += " @pass %d" % event.start + ("" if event.end == null else "..%d" % event.end)
		else:
			when += " +%d" % event.start + ("" if event.end == null else "..+%d" % event.end)
	if event.mode == "end":
		return when + " END"
	var names: PackedStringArray = []
	for n in BUTTON_ORDER:
		if event.buttons & PAD_BITS[n]:
			names.append(n)
	var what := "P%d %s" % [event.player, "+".join(names)]
	if event.mode == "hold":
		what += " hold"
	elif event.repeat > 1:
		what += " x%d" % event.repeat
	return when + " " + what


# A comment starts at "#" at the beginning of a line or at "#" followed by
# whitespace or the end of the line ("#2" is a visit number).
static func _strip_comment(line: String) -> String:
	if line.begins_with("#"):
		return ""
	for i in line.length():
		if line[i] == "#" and (i == 0 or line[i - 1] in [" ", "\t"]) \
				and (i + 1 == line.length() or line[i + 1] in [" ", "\t"]):
			return line.substr(0, i).strip_edges()
	return line


static func _err(no: int, msg: String) -> Dictionary:
	return {"error": "line %d: %s" % [no, msg]}


static func _num(tok: String) -> Variant:
	return int(tok) if tok.is_valid_int() else null


static func _parse_line(line: String, no: int) -> Dictionary:
	var toks: PackedStringArray = []
	for t in line.split(" ", false):
		for u in t.split("\t", false):
			toks.append(u)
	var event := {"line": no, "anchor": "", "screen": -1, "visit": 1, "unit": "tick",
		"start": 0, "end": null, "player": 0, "buttons": 0, "mode": "tap", "repeat": 1}
	var i := 0
	if toks[0] == "@tick":
		if toks.size() < 2:
			return _err(no, "expected a tick")
		event.anchor = "tick"
		var r := _range(toks[1], false)
		if r.is_empty():
			return _err(no, "expected tick")
		event.start = r[0]
		event.end = r[1]
		i = 2
	elif toks[0] == "@screen":
		event.anchor = "screen"
		if toks.size() < 2 or _num(toks[1]) == null:
			return _err(no, "expected screen ID")
		event.screen = int(toks[1])
		i = 2
		if i < toks.size() and toks[i].begins_with("#"):
			if _num(toks[i].substr(1)) == null:
				return _err(no, "expected visit")
			event.visit = int(toks[i].substr(1))
			i += 1
		if i + 1 < toks.size() and toks[i] == "@pass":
			event.unit = "pass"
			var r := _range(toks[i + 1], false)
			if r.is_empty():
				return _err(no, "expected pass")
			event.start = r[0]
			event.end = r[1]
			i += 2
		elif i < toks.size() and toks[i].begins_with("+"):
			var r := _range(toks[i], true)
			if r.is_empty():
				return _err(no, "expected +ticks")
			event.start = r[0]
			event.end = r[1]
			i += 1
		else:
			return _err(no, "expected +ticks or @pass after the screen")
	else:
		return _err(no, "a line starts with @screen or @tick")
	if event.end != null and int(event.end) <= int(event.start) - (1 if event.unit == "pass" else 0):
		return _err(no, "empty range")
	var rest := toks.slice(i)
	if rest.is_empty():
		return _err(no, "missing action")
	if rest[0] == "END":
		if rest.size() != 1 or event.end != null:
			return _err(no, "END takes a single anchor")
		event.mode = "end"
		return event
	if rest.size() < 2 or not (rest[0].length() == 2 and rest[0][0] == "P" and rest[0][1] in ["1", "2", "3", "4"]):
		return _err(no, "expected P1-P4 and buttons")
	event.player = int(rest[0].substr(1))
	for n in rest[1].split("+"):
		if not PAD_BITS.has(n):
			return _err(no, "unknown button '%s'" % n)
		event.buttons |= PAD_BITS[n]
	event.mode = "hold" if event.end != null else "tap"
	for tok in rest.slice(2):
		if tok == "tap" or tok == "hold":
			event.mode = tok
		elif tok.begins_with("x") and _num(tok.substr(1)) != null and int(tok.substr(1)) >= 1:
			event.repeat = int(tok.substr(1))
		else:
			return _err(no, "unknown word '%s'" % tok)
	if event.mode == "hold" and event.end == null:
		return _err(no, "hold needs a range")
	if event.mode == "tap" and event.end != null:
		return _err(no, "a range is a hold")
	if event.repeat > 1 and event.mode != "tap":
		return _err(no, "xN repeats taps only")
	return event


# "a" or "a..b"; with plus=true both need a leading "+". [] when malformed.
static func _range(tok: String, plus: bool) -> Array:
	var parts := tok.split("..")
	if parts.size() > 2:
		return []
	var vals := []
	for text in parts:
		if plus:
			if not text.begins_with("+"):
				return []
			text = text.substr(1)
		if _num(text) == null:
			return []
		vals.append(int(text))
	return [vals[0], vals[1] if vals.size() == 2 else null]
