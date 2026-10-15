#!/usr/bin/env python3
"""The style rulebook's checks (docs/style.md, plan 45) over GDScript files.

    tools/style/gdlint.py [--rules F1,N1,...] [--json] FILE_OR_DIR...

Prints one line a breach (`path:line: RULE message`) and a count per rule;
exits 1 if any breach was found. Plain Python 3, no dependencies: the
checks read the source as text (comments and strings told apart from code),
so they see what is written, not what Godot infers - a variable's type is
known when it is annotated or made with `Class.new(...)` / `as Class`.
GDScript's own analyser covers the rest (rule T6). Skips the vendored
addons (every addon but the project's own, OWN_ADDONS) and anything under
`.godot/`.
"""
import json
import os
import re
import sys

SKIP_DIRS = ("/.godot", "/.worktrees")
## The project's own addons (checked); every other addon is vendored (skipped).
OWN_ADDONS = ("mw_audio", "mw_rom")
VENDORED = re.compile(r"(^|/)addons/(?!(%s)(/|$))[^/]+(/|$)" % "|".join(OWN_ADDONS))
## C11: an attribution to the owner followed by a quoted phrase of two words or more.
OWNER_QUOTE = re.compile(r"\bowner(?:'s)?(?:,? (?:\d{4}-\d{2}-\d{2}|plan \d+))?(?: [a-z]+)?:\s*\"[^\"]*\s[^\"]*\"",
        re.I)
LINE_MAX = 120
TAB = 4

SNAKE = re.compile(r"^_?[a-z][a-z0-9]*(_[a-z0-9]+)*_?$")
UPPER = re.compile(r"^_?[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$")
PASCAL = re.compile(r"^_?[A-Z][A-Za-z0-9]*$")
ENGINE_CALLBACKS = {
    "_init", "_static_init", "_ready", "_enter_tree", "_exit_tree", "_process", "_physics_process",
    "_input", "_unhandled_input", "_unhandled_key_input", "_shortcut_input", "_notification", "_draw",
    "_gui_input", "_get_property_list", "_validate_property", "_get", "_set", "_to_string",
    "_initialize", "_finalize", "_get_configuration_warnings", "_property_can_revert",
    "_property_get_revert", "_iter_init", "_iter_next", "_iter_get", "_make_custom_tooltip",
    "_can_drop_data", "_drop_data", "_get_drag_data", "_has_point", "_structured_text_parser",
    "_get_minimum_size", "_integrate_forces", "_run", "_enable_plugin", "_disable_plugin",
    "_has_main_screen", "_make_visible", "_get_plugin_name", "_get_plugin_icon", "_handles",
    "_edit", "_get_import_options", "_get_importer_name", "_get_recognized_extensions",
    "_get_save_extension", "_get_resource_type", "_get_preset_count", "_get_preset_name",
    "_get_import_order", "_get_priority", "_import", "_get_option_visibility", "_get_visible_name",
    "_can_handle", "_parse_begin", "_parse_end", "_parse_category", "_parse_property",
    "_get_recognized_extensions", "_handles_type", "_load", "_get_resource_type", "_get_dependencies",
    "_mix", "_start", "_stop", "_get_playback_position", "_seek", "_is_playing", "_instantiate_playback",
}
## The short names that mean one thing everywhere (docs/style.md N4): name -> types.
GLOSSARY = {
    "s": {"MwRinkState"},
    "sim": {"MwRinkSim", "MwScreenSim", "MwScoreboardSim", "MwMessageScoreboardSim", "MwFightSim",
            "MwSpecialPlaysSim", "MwRefereeSim", "MwReplaySim", "MwStatsSim"},
    "rom": {"PackedByteArray"},
    "e": {"int"},
    "p": {"MwRinkState.Player", "Player", "int"},
    "q": {"MwRinkState.Player", "Player", "int"},
    "pk": {"MwRinkState.Puck"},
    "su": {"MwMatchSetup"},
}
## Godot's global functions a name must not shadow (N3).
GLOBAL_FUNCS = {
    "abs", "absf", "absi", "acos", "asin", "atan", "atan2", "bezier_derivative", "bezier_interpolate",
    "bytes_to_var", "ceil", "ceilf", "ceili", "clamp", "clampf", "clampi", "cos", "cosh", "cubic_interpolate",
    "db_to_linear", "deg_to_rad", "ease", "error_string", "exp", "floor", "floorf", "floori", "fmod", "fposmod",
    "hash", "instance_from_id", "inverse_lerp", "is_equal_approx", "is_finite", "is_inf", "is_nan", "is_same",
    "is_zero_approx", "lerp", "lerp_angle", "lerpf", "linear_to_db", "log", "max", "maxf", "maxi", "min", "minf",
    "mini", "move_toward", "nearest_po2", "pingpong", "posmod", "pow", "print", "printerr", "prints", "push_error",
    "push_warning", "rad_to_deg", "rand_from_seed", "randf", "randf_range", "randfn", "randi", "randi_range",
    "randomize", "remap", "round", "roundf", "roundi", "seed", "sign", "signf", "signi", "sin", "sinh",
    "smoothstep", "snapped", "sqrt", "step_decimals", "str", "str_to_var", "tan", "tanh", "type_convert",
    "type_string", "typeof", "var_to_bytes", "var_to_str", "weakref", "wrap", "wrapf", "wrapi", "range", "len",
    "load", "preload", "char", "convert", "inst_to_dict", "dict_to_inst", "get_stack", "print_stack",
    "print_debug", "is_instance_of", "is_instance_valid", "type_exists",
}
BAD_ABBREVIATIONS = {"idx", "lst", "arr"}
TODO = re.compile(r"\b(TODO|FIXME|XXX|HACK)\b")
CODE_COMMENT = re.compile(r"^#\s*(var\s+\w+\s*[:=]|func\s+\w+\s*\(|return\b\s*\S|if\s+.+:$|for\s+\w+\s+in\s+.+:$|"
                          r"elif\s+.+:$|while\s+.+:$|[a-z_][\w.]*\([^)]*\)\s*$|[a-z_][\w.]*\s*[-+*/]?=\s*\S)")


def split_code(line):
    """[code with strings blanked, comment] of a line (strings keep their quotes)."""
    out = []
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\" and i + 1 < len(line):
                out.append("  ")
                i += 2
                continue
            if line.startswith(quote, i):
                out.append(quote)
                i += len(quote)
                quote = None
                continue
            out.append(" ")
        else:
            if line.startswith('"""', i):
                quote = '"""'
                out.append(quote)
                i += 3
                continue
            if c in "\"'":
                quote = c
            elif c == "#":
                return "".join(out), line[i:]
            out.append(c)
        i += 1
    return "".join(out), ""


def width(line):
    return len(line.expandtabs(TAB))


def snake_of(cls):
    """The file name (without .gd) for class [cls]: the name without `Mw` (`Rom` stays) in snake_case, a digit
    starting a word with the letters after it (`MwRinkCamera3D` -> rink_camera_3d, `MwSound68k` ->
    sound_68k); `Rink3D` is the module's one word (`MwRink3DHost` -> rink3d_host)."""
    base = re.sub(r"^Mw(?=[A-Z])", "", cls)
    s = re.sub(r"(?<=[a-z])(?=[A-Z0-9])|(?<=[0-9])(?=[A-Z][a-z])|(?<=[A-Z])(?=[A-Z][a-z])", "_", base).lower()
    return re.sub(r"^rink_3d", "rink3d", s)


class File:
    def __init__(self, path, rel):
        self.path = path
        self.rel = rel
        self.text = open(path, encoding="utf-8").read()
        self.lines = self.text.split("\n")
        self.split = [split_code(l) for l in self.lines]
        self.is_test = rel.startswith("game/test/") or "/test/" in rel
        self.breaches = []
        self.short_names = set()
        for l in self.lines[:400]:
            if l.strip() and not l.startswith(("##", "class_name", "extends", "@")):
                break             # the class doc is over
            m = re.match(r"^##\s*Short names:\s*(.*)", l)
            if m:
                for part in m.group(1).split(","):
                    w = part.strip().split(" ")
                    if w and w[0]:
                        self.short_names.add(w[0])

    def add(self, line, rule, msg):
        self.breaches.append((self.rel, line, rule, msg))


def type_of(decl_rest):
    """The declared type of `NAME<decl_rest>`: annotation, `Class.new(`, `as Class`; '' unknown."""
    m = re.match(r"\s*:\s*([A-Za-z_][\w.]*(?:\[[\w.]+\])?)", decl_rest)
    if m:
        return m.group(1)
    m = re.match(r"\s*:=\s*([A-Z][\w.]*)\.new\(", decl_rest)
    if m:
        return m.group(1)
    m = re.search(r"\bas\s+([A-Z][\w.]*)\s*$", decl_rest.strip())
    if m:
        return m.group(1)
    m = re.match(r"\s*:=\s*(\"|str\()", decl_rest)
    if m:
        return "String"
    m = re.match(r"\s*:=\s*-?(0x[0-9A-Fa-f]+|\d+)\s*$", decl_rest)
    if m:
        return "int"
    return ""


def is_project_class(t):
    return bool(re.match(r"^(Mw|Rom)[A-Z]", t)) or t == "MlhRng"


def check(f, rules):
    lines, split = f.lines, f.split
    want = lambda r: rules is None or r in rules
    # --- F: header ---------------------------------------------------------------------
    first_code = [i for i, (c, _) in enumerate(split) if c.strip() and not c.strip().startswith("@")]
    cls = None
    m = re.search(r"^class_name\s+(\w+)", f.text, re.M)
    if m:
        cls = m.group(1)
    if want("F1"):
        head = [lines[i].strip() for i in first_code[:2]]
        ok = (head and head[0].startswith("class_name") and len(head) > 1 and head[1].startswith("extends")) or \
             (head and head[0].startswith("extends"))
        ext = next((i for i in first_code if lines[i].startswith("extends")), None)
        if not ok:
            f.add(1, "F1", "class_name, then extends, first")
        elif ext is not None:
            j = ext + 1
            while j < len(lines) and lines[j].startswith("@"):
                j += 1
            if j >= len(lines) or not lines[j].startswith("##"):
                f.add(ext + 1, "F1", "the class's ## doc goes right after extends")
    if cls and want("F2"):
        if not (re.match(r"^(Mw|Rom)[A-Z][A-Za-z0-9]*$", cls) or cls == "MlhRng"):
            f.add(1, "F2", "class %s: Mw (or Rom) + PascalCase" % cls)
    if cls and want("F3") and not f.rel.startswith("game/scenes/") and not f.is_test:
        want_name = snake_of(cls) + ".gd"
        if cls != "MlhRng" and os.path.basename(f.path) != want_name:
            f.add(1, "F3", "class %s lives in %s" % (cls, want_name))
    # --- C11: no one's messages quoted word for word ---------------------------------------------
    if want("C11"):
        i = 0
        while i < len(lines):
            if not split[i][1]:
                i += 1
                continue
            j = i
            while j + 1 < len(lines) and split[j + 1][1] and not split[j + 1][0].strip():
                j += 1
            block = " ".join(split[k][1].lstrip("#").strip() for k in range(i, j + 1))
            if OWNER_QUOTE.search(block):
                f.add(i + 1, "C11", "the owner's words quoted: say what was decided in the code's own words")
            i = j + 1
    # --- walk the declarations -------------------------------------------------------------
    func_line = None          # the current top-level function's line
    func_params = []
    in_func_indent = None
    blank_run = 0
    prev_code_line = ""
    depth = 0                 # bracket depth carried over lines (continuations)
    in_class = False          # inside an inner class's body (its indent-1 vars are members)
    for i, raw in enumerate(lines):
        n = i + 1
        code, comment = split[i]
        stripped = code.strip()
        cont = depth > 0
        if stripped and not cont and not code.startswith("\t"):
            in_class = bool(re.match(r"class\s+\w+", stripped))
        depth += code.count("(") + code.count("[") + code.count("{") - code.count(")") - code.count("]") - code.count("}")
        depth = max(depth, 0)
        # L1: indentation and whitespace
        if want("L1"):
            lead = raw[:len(raw) - len(raw.lstrip())]
            if " " in lead and not cont and raw.strip() and not raw.strip().startswith("#"):
                f.add(n, "L1", "indent with tabs")
            if raw != raw.rstrip():
                f.add(n, "L1", "trailing whitespace")
        if want("L2") and width(raw) > LINE_MAX:
            f.add(n, "L2", "line is %d columns (max %d)" % (width(raw), LINE_MAX))
        # C6
        if want("C6") and comment:
            body = comment.lstrip("#").strip()
            if TODO.search(comment) and not re.search(r"plan \d+|owner", comment):
                f.add(n, "C6", "TODO/FIXME without a plan or the owner's question")
            if not comment.startswith("##") and not stripped and CODE_COMMENT.match("# " + body) \
                    and not re.match(r"^#\s*-{3}", comment):
                f.add(n, "C6", "commented-out code? (%s)" % body[:50])
        if not stripped:
            if not raw.strip():
                blank_run += 1
            continue
        indent = len(code) - len(code.lstrip("\t"))
        if cont:
            continue
        # functions
        fm = re.match(r"^(\t*)(static\s+)?func\s+(\w+)\s*\(", code)
        if fm:
            name = fm.group(3)
            top = len(fm.group(1)) == 0
            # params: up to the closing bracket (may span lines)
            sig = code[fm.end():]
            k = i
            d = 1
            buf = ""
            pos = 0
            while True:
                while pos < len(sig) and d > 0:
                    c = sig[pos]
                    if c in "([{":
                        d += 1
                    elif c in ")]}":
                        d -= 1
                    if d > 0:
                        buf += c
                    pos += 1
                if d == 0 or k + 1 >= len(lines):
                    rest = sig[pos:]
                    break
                k += 1
                sig = split[k][0]
                pos = 0
                buf += " "
            params = []
            dd = 0
            cur = ""
            for c in buf:
                if c in "([{":
                    dd += 1
                if c in ")]}":
                    dd -= 1
                if c == "," and dd == 0:
                    params.append(cur)
                    cur = ""
                else:
                    cur += c
            if cur.strip():
                params.append(cur)
            names = []
            for prm in params:
                pm = re.match(r"\s*(\w+)\s*(.*)$", prm)
                if not pm:
                    continue
                pn, prest = pm.group(1), pm.group(2)
                names.append(pn)
                if want("N1") and not SNAKE.match(pn):
                    f.add(n, "N1", "parameter %s: snake_case" % pn)
                gut_params = pn == "params" and "use_parameters(" in prest
                if want("T1") and not prest.strip().startswith(":") and name != "should_skip_script" and not gut_params:
                    f.add(n, "T1", "parameter %s has no type" % pn)
                _check_name(f, n, pn, type_of(prest), "parameter", want)
            if want("N1") and not SNAKE.match(name):
                f.add(n, "N1", "function %s: snake_case" % name)
            if want("T1") and "->" not in rest and name != "should_skip_script" and not name.startswith("test_") \
                    and not (f.is_test and name in ("before_each", "after_each", "before_all", "after_all")):
                f.add(n, "T1", "function %s has no return type" % name)
            if top:
                func_line, func_params = n, names
                # L3: two blank lines before a top-level function (one after a section marker)
                if want("L3"):
                    j = i - 1
                    while j >= 0 and (lines[j].startswith("##") or lines[j].startswith("@")):
                        j -= 1
                    blanks = 0
                    while j >= 0 and not lines[j].strip():
                        blanks += 1
                        j -= 1
                    marker = j >= 0 and re.match(r"^#\s*-{3}", lines[j])
                    if j >= 0 and not lines[j].startswith(("class_name", "extends")) and \
                            blanks != (1 if marker else 2) and not lines[j].startswith("#"):
                        f.add(n, "L3", "%d blank lines before func %s (want %d)" % (blanks, name, 1 if marker else 2))
                # C1 + C3: the doc above
                doc = []
                j = i - 1
                while j >= 0 and lines[j].startswith("@"):
                    j -= 1
                while j >= 0 and lines[j].startswith("##"):
                    doc.insert(0, lines[j])
                    j -= 1
                public = not name.startswith("_") and name not in ENGINE_CALLBACKS
                if want("C1") and public and not doc and not f.is_test and not f.rel.startswith("game/addons/"):
                    f.add(n, "C1", "public function %s has no ## doc" % name)
                if want("C3"):
                    for dl in doc:
                        for pref in re.findall(r"\[param (\w+)\]", dl):
                            if pref not in names and "_" + pref not in names and pref + "_" not in names:
                                f.add(n, "C3", "doc names [param %s], not a parameter of %s" % (pref, name))
            continue
        # declarations
        vm = re.match(r"^(\t*)((?:@\w+(?:\([^)]*\))?\s+)*)(static\s+)?var\s+(\w+)(.*)$", code)
        if vm:
            name, rest = vm.group(4), vm.group(5)
            member = len(vm.group(1)) == 0 or (in_class and len(vm.group(1)) == 1)
            if want("N1") and not SNAKE.match(name):
                f.add(n, "N1", "variable %s: snake_case" % name)
            if want("T1") and not re.match(r"\s*(:|$)", rest) and "=" in rest and not rest.strip().startswith(":"):
                f.add(n, "T1", "variable %s has no type (use := or : Type =)" % name)
            if want("T1") and re.match(r"\s*$", rest):
                f.add(n, "T1", "variable %s has no type" % name)
            if not member:
                _check_name(f, n, name, type_of(rest), "variable", want)
            elif want("C1") and False:
                pass
            continue
        fr = re.match(r"^\t*for\s+(\w+)\s*(:\s*[\w.]+)?\s+in\b", code)
        if fr:
            _check_name(f, n, fr.group(1), (fr.group(2) or ":").lstrip(":").strip(), "loop variable", want)
            continue
        cm = re.match(r"^(\t*)(static\s+)?const\s+(\w+)(.*)$", code)
        if cm:
            name, rest = cm.group(3), cm.group(4)
            pre = re.match(r"\s*:?=\s*(preload|load)\(", rest)
            if want("N1"):
                if pre or re.match(r"\s*:?=\s*[A-Z]\w*(\.[A-Z]\w*)*\s*$", rest):
                    if not (PASCAL.match(name) or UPPER.match(name)):
                        f.add(n, "N1", "constant %s: PascalCase (a script) or CONSTANT_CASE" % name)
                elif not UPPER.match(name):
                    f.add(n, "N1", "constant %s: CONSTANT_CASE" % name)
            continue
        sm = re.match(r"^\t*signal\s+(\w+)", code)
        if sm:
            if want("N1") and not SNAKE.match(sm.group(1)):
                f.add(n, "N1", "signal %s: snake_case" % sm.group(1))
            if want("C1") and not f.is_test:
                j = i - 1
                if not (lines[j].startswith("##") if j >= 0 else False) and "##" not in comment:
                    f.add(n, "C1", "signal %s has no ## doc" % sm.group(1))
            continue
        em = re.match(r"^\t*enum\s+(\w+)?\s*\{([^}]*)\}?", code)
        if em:
            if em.group(1) and want("N1") and not PASCAL.match(em.group(1)):
                f.add(n, "N1", "enum %s: PascalCase" % em.group(1))
            for member in re.findall(r"(\w+)\s*(?:=\s*[^,]+)?(?:,|$)", em.group(2) or ""):
                if member and want("N1") and not UPPER.match(member):
                    f.add(n, "N1", "enum member %s: CONSTANT_CASE" % member)
            continue
        km = re.match(r"^\t*class\s+(\w+)", code)
        if km:
            if want("N1") and not PASCAL.match(km.group(1)):
                f.add(n, "N1", "inner class %s: PascalCase" % km.group(1))
            if want("C1") and not f.is_test:
                j = i - 1
                after = lines[i + 1] if i + 1 < len(lines) else ""
                k = i + 1
                while k < len(lines) and re.match(r"^\t*extends\b", lines[k]):
                    k += 1
                inside = lines[k].strip().startswith("##") if k < len(lines) else False
                if not (j >= 0 and lines[j].strip().startswith("##")) and not inside and "##" not in comment:
                    f.add(n, "C1", "inner class %s has no ## doc" % km.group(1))
            continue
        if ";" in stripped and want("L5") and not stripped.startswith("#"):
            f.add(n, "L5", "one statement a line")
    if want("L1") and not f.text.endswith("\n"):
        f.add(len(lines), "L1", "no newline at the end of the file")


def _check_name(f, n, name, typ, what, want):
    if want("N3") and name in GLOBAL_FUNCS:
        f.add(n, "N3", "%s %s shadows the global function %s()" % (what, name, name))
    if want("N3") and name.endswith("_") and what != "parameter":
        f.add(n, "N3", "%s %s: a trailing _ is for a parameter that sets the member of its name" % (what, name))
    if want("N8") and name in BAD_ABBREVIATIONS:
        f.add(n, "N8", "%s %s: not one of the established abbreviations" % (what, name))
    if not want("N4") and not want("N5"):
        return
    bare = name.lstrip("_")
    if bare in GLOSSARY and bare not in f.short_names:
        if typ and typ not in GLOSSARY[bare] and want("N4"):
            f.add(n, "N4", "%s %s is %s: %s means %s" % (what, name, typ, bare, " / ".join(sorted(GLOSSARY[bare]))))
        return
    if want("N5") and len(bare) == 1 and bare not in f.short_names and typ and is_project_class(typ):
        f.add(n, "N5", "%s %s holds a %s: name it for its class or role" % (what, name, typ))


def walk(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
            continue
        for dp, dn, fn in os.walk(p):
            here = dp.replace(os.sep, "/") + "/"
            if any(s in here for s in SKIP_DIRS) or VENDORED.search(here):
                continue
            dn.sort()
            for name in sorted(fn):
                if name.endswith(".gd"):
                    yield os.path.join(dp, name)


def main(argv):
    rules = None
    as_json = False
    paths = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--rules":
            rules = set(argv[i + 1].split(","))
            i += 2
            continue
        if a == "--json":
            as_json = True
        else:
            paths.append(a)
        i += 1
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    found = []
    for path in walk(paths or [os.path.join(root, "game")]):
        rel = os.path.relpath(os.path.abspath(path), root).replace(os.sep, "/")
        if any(s.strip("/") in rel for s in SKIP_DIRS) or VENDORED.search(rel):
            continue
        f = File(path, rel)
        check(f, rules)
        found += f.breaches
    if as_json:
        json.dump([{"file": a, "line": b, "rule": c, "message": d} for a, b, c, d in found], sys.stdout, indent=0)
    else:
        for a, b, c, d in found:
            print("%s:%d: %s %s" % (a, b, c, d))
        counts = {}
        for _, _, c, _ in found:
            counts[c] = counts.get(c, 0) + 1
        print("style-check: %d breaches%s" % (len(found), "" if not counts else " (" + ", ".join(
            "%s %d" % kv for kv in sorted(counts.items())) + ")"))
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
