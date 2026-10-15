#!/usr/bin/env python3
"""Renames GDScript locals, loop variables and parameters within their scope (plan 45, docs/style.md N4/N5).

    tools/style/rename_locals.py RENAMES.json [--dry-run]

RENAMES.json: [{"file": "game/src/x.gd", "line": 12, "name": "s", "new": "text"}, ...] - `line` is the
declaration's line (1-based): a `var NAME`, a `for NAME in`, or a function's signature for a parameter
(also a lambda's, `func(NAME ...)` on that line).

A declaration's scope, read from the indentation (continuation lines inside brackets don't end a block):
* a parameter: its function, from the signature to the function's end, and the `[param NAME]`
  references in the doc comment just above it;
* a `var`: from its line to the end of its block;
* a loop variable: its loop's body.

In the scope every identifier token NAME becomes NEW - not after a `.`, `$`, `%` or `^`, not in a string or
a comment, not as the key of a `{key = value}` dictionary. A rename is refused (and reported) when NEW is
already an identifier anywhere in the scope, a name the file declares, a global function, or a keyword;
the file is left as it was for that one. Prints what it did; exit 1 if anything was refused.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gdlint import GLOBAL_FUNCS, split_code  # noqa: E402

KEYWORDS = {
    "if", "elif", "else", "for", "while", "match", "when", "break", "continue", "pass", "return", "class",
    "class_name", "extends", "is", "in", "as", "self", "super", "signal", "func", "static", "const", "enum",
    "var", "breakpoint", "preload", "await", "yield", "assert", "void", "PI", "TAU", "INF", "NAN", "and", "or",
    "not", "true", "false", "null", "int", "float", "bool", "String", "Array", "Dictionary", "Variant", "Object",
    "trait", "namespace",
}
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
## --relaxed: a new name may be one a sibling block uses (the scope and the enclosing blocks are checked).
RELAXED = False


def indent_of(line):
    return len(line) - len(line.lstrip("\t"))


class Source:
    def __init__(self, path):
        self.path = path
        self.lines = open(path, encoding="utf-8").read().split("\n")
        self.refresh()

    def refresh(self):
        self.code = [split_code(l)[0] for l in self.lines]
        # continuation: a line that starts inside open brackets
        self.cont = []
        depth = 0
        for c in self.code:
            self.cont.append(depth > 0)
            depth += c.count("(") + c.count("[") + c.count("{") - c.count(")") - c.count("]") - c.count("}")
            depth = max(depth, 0)

    def is_code(self, i):
        return bool(self.code[i].strip()) and not self.cont[i]

    def block_end(self, start, min_indent):
        """The first line after [start] whose code is indented less than [min_indent] (or the end)."""
        i = start + 1
        while i < len(self.lines):
            if self.is_code(i) and indent_of(self.code[i]) < min_indent:
                return i
            i += 1
        return len(self.lines)

    def declared_names(self):
        """The names the file declares as members: its functions, variables, constants, signals, enums and
        inner classes, and the members of its inner classes (locals of functions are not members)."""
        names = set()
        in_class = False
        for c in self.code:
            if not c.strip():
                continue
            ind = indent_of(c)
            if ind == 0:
                in_class = bool(re.match(r"class\s+\w+", c))
            if ind == 0 or (in_class and ind == 1):
                for m in re.finditer(r"\b(?:func|var|const|signal|class|enum)\s+(\w+)", c):
                    names.add(m.group(1))
                m = re.match(r"\s*enum\s*\w*\s*\{([^}]*)", c)
                if m:
                    names.update(re.findall(r"\w+", m.group(1)))
        return names


def scope_of(src, line, name):
    """[first, end, doc_first] of the declaration of [name] on 0-based [line]; None if not found."""
    code = src.code[line]
    ind = indent_of(code)
    if re.search(r"\bfunc\b[^(]*\(", code) and re.search(r"[(,]\s*%s\b" % re.escape(name), _signature(src, line)):
        m = re.search(r"\bfunc\b", code)
        lam = not re.match(r"^\t*(static\s+)?func\s+\w+", code)
        if lam:
            # a lambda: a one-line body, or the lines after it indented deeper than the line it starts on
            end = src.block_end(line, ind + 1)
            return line, end, None
        end = src.block_end(line, ind + 1)
        doc = line
        while doc > 0 and (src.lines[doc - 1].lstrip("\t").startswith("##") or src.lines[doc - 1].lstrip("\t").startswith("@")):
            doc -= 1
        return line, end, doc
    if re.match(r"^\t*for\s+%s\b" % re.escape(name), code):
        return line, src.block_end(line, ind + 1), None
    if re.search(r"\bvar\s+%s\b" % re.escape(name), code):
        return line, src.block_end(line, ind), None
    return None


def function_of(src, line):
    """[first, end) of the function (or the top-level code) around 0-based [line]: a new name must not
    appear anywhere in it (a local may not shadow one in an enclosing block)."""
    lo = line
    while lo > 0 and not re.match(r"^\t?(static\s+)?func\s", src.code[lo]):
        lo -= 1
    ind = indent_of(src.code[lo])
    return lo, src.block_end(lo, ind + 1)


def _signature(src, line):
    out = src.code[line]
    j = line
    while out.count("(") > out.count(")") and j + 1 < len(src.lines):
        j += 1
        out += " " + src.code[j]
    return out


def tokens(src, first, end, name):
    """[(line, col)] of the identifier [name] in code lines [first, end)."""
    out = []
    for i in range(first, end):
        code = src.code[i]
        for m in IDENT.finditer(code):
            if m.group(0) != name:
                continue
            a = m.start()
            if a > 0 and (code[a - 1].isdigit() or code[a - 1] == "."):
                if re.search(r"(^|[^\w.])[0-9][0-9_]*\.?[0-9_]*$", code[:a]):
                    continue      # an exponent (1e-4) or a suffix inside a number
            if code[:a].rstrip(" ").endswith("."):
                continue          # a member of something else
            if a > 0 and code[a - 1] in "$^&":
                continue          # a node path, a NodePath or StringName literal
            if a > 0 and code[a - 1] == "%" and not re.search(r"[\w)\]\"'] *%$", code[:a]):
                continue          # a scene-unique node (%Name), not the % operator
            after = code[m.end():]
            if re.match(r"\s*=(?!=)", after) and _in_braces(code, a) and not code[:a].rstrip().endswith(("var", "for")):
                continue          # a {key = value} key
            out.append((i, a))
    return out


def _in_braces(code, at):
    depth = 0
    for c in code[:at]:
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
    return depth > 0


def apply(src, line, name, new, declared):
    found = scope_of(src, line, name)
    if found is None:
        return "declaration of %s not found on line %d" % (name, line + 1)
    first, end, doc = found
    if new in KEYWORDS or new in GLOBAL_FUNCS:
        return "%s is a keyword or a global function" % new
    if new in declared:
        return "%s is declared in the file" % new
    lo, hi = function_of(src, line)
    if not RELAXED:
        for i in range(lo, hi):
            if re.search(r"(?<![.$^&\w])%s\b" % re.escape(new), src.code[i]):
                return "%s is already used in the function (line %d)" % (new, i + 1)
    else:
        # sibling blocks may reuse a name: only the scope itself, and a declaration of NEW in an
        # enclosing block (or the signature) before it, would clash
        for i in range(first, end):
            if re.search(r"(?<![.$^&\w])%s\b" % re.escape(new), src.code[i]):
                return "%s is already used in the scope (line %d)" % (new, i + 1)
        ind = indent_of(src.code[line])
        for i in range(lo, line):
            c = src.code[i]
            if indent_of(c) < ind and re.search(r"\b(var|for)\s+%s\b|func\b.*[(,]\s*%s\b" % (re.escape(new), re.escape(new)), c):
                return "%s is declared in an enclosing block (line %d)" % (new, i + 1)
    toks = tokens(src, first, end, name)
    if not toks:
        return "no %s in the scope" % name
    for i, a in sorted(toks, reverse=True):
        l = src.lines[i]
        src.lines[i] = l[:a] + new + l[a + len(name):]
    if doc is not None:
        for i in range(doc, first):
            src.lines[i] = src.lines[i].replace("[param %s]" % name, "[param %s]" % new)
    src.refresh()
    return None


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    renames = json.load(open(argv[0]))
    dry = "--dry-run" in argv
    global RELAXED
    RELAXED = "--relaxed" in argv
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    by_file = {}
    for r in renames:
        by_file.setdefault(r["file"], []).append(r)
    refused = 0
    done = 0
    for rel, items in sorted(by_file.items()):
        path = os.path.join(root, rel)
        src = Source(path)
        declared = src.declared_names()
        # bottom-up, so a rename never moves a later declaration's line (renames keep line numbers anyway)
        for r in sorted(items, key=lambda r: -r["line"]):
            why = apply(src, r["line"] - 1, r["name"], r["new"], declared)
            if why:
                refused += 1
                print("REFUSED %s:%d %s -> %s: %s" % (rel, r["line"], r["name"], r["new"], why))
            else:
                done += 1
        if not dry:
            open(path, "w", encoding="utf-8").write("\n".join(src.lines))
    print("renamed %d, refused %d" % (done, refused))
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
