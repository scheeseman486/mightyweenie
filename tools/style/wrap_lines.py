#!/usr/bin/env python3
"""Wraps GDScript lines longer than the rulebook's 120 columns (docs/style.md L2; plan 45).

    tools/style/wrap_lines.py FILE...

A code line breaks after a comma inside brackets, else before an operator inside brackets (`and`, `or`,
`+`, `-`, `*`, `/`, `if`, `else`), the rest indented two tabs more than the statement (a continuation
line keeps its own indent); outside brackets, before such an operator with a trailing `\\`. A trailing
comment that doesn't fit moves to its own line above the statement. A comment or doc line breaks at a
space (not inside a [tag]). Lines holding a lambda (`func(`) are left alone and reported.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gdlint import LINE_MAX, split_code, width  # noqa: E402

OPS = (" and ", " or ", " + ", " - ", " * ", " / ", " if ", " else ", " % ")


def depth_before(code, at, start_depth):
    d = start_depth
    for c in code[:at]:
        if c in "([{":
            d += 1
        elif c in ")]}":
            d -= 1
    return d


## Break points by preference: a comma inside brackets, then the lowest-precedence operators first.
CLASSES = [(", ",), (" or ", " and "), (" + ", " - "), (" if ", " else "), (" | ", " & ", " ^ "),
           (" * ", " / ", " % "), (" == ", " != ", " < ", " > ", " <= ", " >= "), ("(",)]


def wrap_code(line, start_depth, cont_indent, joined=False):
    """[lines] for one code line (no trailing comment), or None if it can't be wrapped. [joined]: every
    break is a `\\` line join (safe anywhere between tokens: a lambda's line, a lambda's block)."""
    out = []
    rest = line
    while width(rest) > LINE_MAX:
        code, _ = split_code(rest)
        lead = len(rest) - len(rest.lstrip("\t"))
        cands = []                # (depth, class, -position, position, inside brackets)
        for k, ops in enumerate(CLASSES):
            for op in ops:
                for m in re.finditer(re.escape(op), code):
                    at = m.end() if op in (", ", "(") else m.start() + 1
                    if op == "(" and (at >= len(code) or code[at] == ")"):
                        continue
                    d = depth_before(code, at, start_depth)
                    if op in (", ", "(") and d < 1 and not joined:
                        continue
                    if width(rest[:at].rstrip()) > LINE_MAX - (0 if d >= 1 else 2):
                        continue
                    cands.append((max(d, 1) if op in (", ", "(") else d, k, -at, at, d >= 1 and not joined))
        # the shallowest break of the best class that keeps at least half the line; else any
        half = (LINE_MAX - width(rest[:lead])) // 2
        good = [c for c in cands if width(rest[:c[3]]) >= half] or cands
        best = None
        kind = None
        if good:
            pick = min(good)
            best, kind = pick[3], ("in" if pick[4] else "out")
        if best is None or best < lead + 8:
            return None
        head = rest[:best].rstrip()
        tail = rest[best:].lstrip(" ")
        if kind == "out":
            head += " \\"
        out.append(head)
        start_depth = depth_before(split_code(rest)[0], best, start_depth)
        rest = cont_indent + tail
    out.append(rest)
    return out


def wrap_comment(line):
    m = re.match(r"^(\t*)(##?\s*)(.*)$", line)
    ind, prefix, text = m.group(1), m.group(2), m.group(3)
    out = []
    while width(ind + prefix + text) > LINE_MAX:
        room = LINE_MAX - width(ind + prefix)
        cut = -1
        depth = 0
        for i, c in enumerate(text[:room + 1]):
            if c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
            elif c == " " and depth == 0 and i <= room:
                cut = i
        if cut <= 0:
            break
        out.append(ind + prefix + text[:cut].rstrip())
        text = text[cut + 1:]
    out.append(ind + prefix + text)
    return out


def process(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    out = []
    depth = 0
    left = []
    block = -1                # a lambda's block opened inside brackets: its header's indent (-1: none)
    backslash = False
    for n, line in enumerate(lines, 1):
        code, comment = split_code(line)
        prev_backslash = backslash
        backslash = code.rstrip().endswith("\\")
        start = depth
        depth = max(0, depth + sum(code.count(c) for c in "([{") - sum(code.count(c) for c in ")]}"))
        ind = line[:len(line) - len(line.lstrip("\t"))]
        if code.strip() and block >= 0 and len(ind) <= block:
            block = -1
        in_block = block >= 0
        if code.rstrip().endswith(":") and depth > 0 and block < 0:
            block = len(ind)      # the lines after it, indented deeper, are a block, not a continuation
        if width(line) <= LINE_MAX:
            out.append(line)
            continue
        joined = in_block or "func(" in code or "func (" in code
        if not code.strip():
            pieces = wrap_comment(line)
            prefix = re.match(r"^(\t*##?\s*)", line).group(1)
            nxt = lines[n] if n < len(lines) else ""
            nxt_prefix = re.match(r"^(\t*##?\s*)", nxt)
            if len(pieces) > 1 and nxt_prefix and nxt_prefix.group(1) == prefix and nxt.strip(" #\t"):
                # reflow: the last piece joins the next line of the same comment (wrapped in its turn)
                lines[n] = prefix + pieces[-1][len(prefix):] + " " + nxt[len(prefix):]
                pieces = pieces[:-1]
            out.extend(pieces)
            continue
        cont = ind if ((start > 0 and not joined) or prev_backslash) else ind + "\t\t"
        pre = []
        body = line
        if comment:
            body = line[:len(line) - len(comment)].rstrip()
            pre = wrap_comment(ind + comment.strip()) if not start > 0 else []
            if start > 0 and not joined:   # inside an open bracket: keep the comment on the last piece
                pre = []
                body = line
        wrapped = wrap_code(body, start, cont, joined) if width(body) > LINE_MAX else [body]
        if wrapped is None:
            left.append("%s:%d no break point" % (path, n))
            out.append(line)
            continue
        out.extend(pre + wrapped)
    open(path, "w", encoding="utf-8").write("\n".join(out))
    return left


def main(argv):
    left = []
    for p in argv:
        left += process(p)
    for l in left:
        print("LEFT", l)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
