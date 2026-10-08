"""Crowd figures of the rink picture: numbers and review sheets (plan 15).

    tools/bin/py tools/crowd/crowd_build.py build   # game/assets/crowd/crowd.json + inventory
    tools/bin/py tools/crowd/crowd_build.py sheet   # out/crowd/sheet.png, map.png, coverage.png
    tools/bin/py tools/crowd/crowd_build.py review  # out/crowd/review/figures_review.png to mark up
    tools/bin/py tools/crowd/crowd_build.py marks [--apply] [--file PNG]   # read the owner's marks
    tools/bin/py tools/crowd/crowd_build.py paint [--into DIR]   # out/crowd/paint/: the views to draw, for GIMP

The hand definitions are ``tools/crowd/figures.json`` (numbers only; see its
``about``). ``build`` finds every figure's instances and writes them with the
definitions to ``game/assets/crowd/crowd.json``, which MwCrowd reads to cut
the figures from the ROM at load. Sheets go to ``out/crowd/`` and hold ROM
pixels: never commit them.

**Review by marks.** ``review`` draws every figure unscaled on one RGB
sheet: the figure's pixels in their own colours, the rest of its box and a
margin of MARGIN px tinted pink (dark pink for black up to light pink for
white: CONTEXT), earlier infill marks red. The owner paints with a hard
pencil (no antialiasing), keeping the sheet's size:

* yellow (#FFFF00) - the figure's too: the cut missed it (pink #FF00FF,
  the first rounds' colour, still reads as this);
* red (#FF0000) - the figure's, but not what the ROM shows there (a
  neighbour or a seat covers it): left out of the mask, painted later;
* green (#00FF00) - not the figure's: left out (see-through).

``marks`` compares the painted sheet with the untouched copy saved next to
it, turns each figure's changed pixels into runs of picture coordinates
(``add``, ``infill``, ``remove`` in figures.json; numbers only, no colours)
and with ``--apply`` writes them, grows a figure's box when a mark lies in
the margin, rebuilds crowd.json and draws a fresh review sheet.

**The owner's art.** ``paint`` draws the views the picture never shows
(characters' views still to make: their stand-ins show instead) and the
figures' gaps on one indexed sheet in the crowd's colours (``paint.png``,
team 0's: line 1 without 16 and 25, which repeat 31 and 20), each to paint
in a yellow-framed cell over its starting figure (blank for a new
drawing), beside the character's other view and the references its note
names. The owner paints on a layer of their own over it in GIMP (magenta
erases a starting pixel); ``layout.json`` says where each cell's figure
sits, for reading the layer back into patches (the owner's pixels only).
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "harness"))

import crowd_lib as cl  # noqa: E402

FIGURES = HERE / "figures.json"
OUT_JSON = ROOT / "game" / "assets" / "crowd" / "crowd.json"
OUT = ROOT / "out" / "crowd"
KEEP = ("from", "swap", "seeds", "walls", "patches", "lasso", "line", "background", "add", "remove", "infill",
        "exclude", "paint", "size", "note", "graft")
REVIEW = OUT / "review"
MARGIN = 4
MARKS = {"add": (255, 255, 0), "infill": (255, 0, 0), "remove": (0, 255, 0)}
LEGACY = [("add", (255, 0, 255))]          # rounds 1-2 marked "add" pink
CONTEXT = ((110, 20, 70), (255, 170, 220))  # pink tint of what isn't the figure: black, white


def palette_rgb(rom: bytes) -> np.ndarray:
    from mw_harness import palettes
    from mw_harness.gfx import color_rgb8
    return np.array([color_rgb8(c) for c in palettes.screen_palette(rom, 4, 0, 0)], np.uint8)


def compact(s: str) -> str:
    """JSON with short number lists on one line."""
    s = re.sub(r"\[\s+(-?\d+(?:\.\d+)?(?:,\s+-?\d+(?:\.\d+)?)*)\s+\]", lambda m: "[" + re.sub(r",\s+", ", ", m.group(1)) + "]", s)
    return re.sub(r"\[\s+(\[[^\[\]]*\](?:,\s+\[[^\[\]]*\])*)\s+\]", lambda m: "[" + re.sub(r",\s+", ", ", m.group(1)) + "]", s)


def build(rom: bytes) -> tuple:
    figs = cl.load_figures(FIGURES)
    pic, crowd, built, cover = cl.build(rom, figs)
    defs = {d["name"]: d for d in json.loads(FIGURES.read_text())["figures"]}
    out = []
    for b in built:
        d = defs[b.fig.name]
        e = {"name": b.fig.name, "view": b.fig.view, "box": list(b.fig.box)}
        e.update({k: d[k] for k in KEEP if k in d})
        e["swaps"] = [[list(p) for p in s] for s in b.swaps]
        e["instances"] = [[p.x, p.y, int(p.mirrored), int(p.team), p.swap] for p in b.placed]
        e["template_hash"] = cl.template_hash(b.template)
        out.append(e)
    inv = cl.inventory(crowd, cover)
    data = {
        "about": [
            "Crowd figures of the rink picture (plan 15). Written by tools/crowd/crowd_build.py from",
            "tools/crowd/figures.json; numbers only, the pixels come from the ROM at load (MwCrowd).",
            "picture: the rink picture's address ($24CFC). Coordinates are the picture's.",
            "instances: [x, y, mirrored, team_brown, swap], window top-left; a line-1 (crowd) instance",
            "is on the left half and also stands mirrored in the right half (x' = 512 - x - w); a",
            "figure on another line (the pen's referee) stands once, where given. team_brown: brown",
            "drawn as colour 25; swap: 0 or 1 + index into swaps (colour pairs [from, to]).",
            "inventory: the left half's crowd pixels by owner (figure, seat, background, scrap).",
            "template_hash: crowd_lib.template_hash of the figure's template (parity test).",
        ],
        "picture": cl.RINK_PICTURE,
        "half": cl.HALF,
        "top_centre": list(cl.TOP_CENTRE),
        "figures": out,
        "characters": json.loads(FIGURES.read_text()).get("characters", []),
        "inventory": inv,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(compact(json.dumps(data, indent=1)) + "\n")
    return pic, crowd, built, cover, inv


def report(built, inv) -> None:
    for b in built:
        n = len(b.placed)
        sw = sum(1 for p in b.placed if p.swap)
        print("%-16s %-5s x%-3d%s clash %d" % (b.fig.name, b.fig.view, n, (" (%d swapped)" % sw) if sw else "", b.clash))
    c = inv["crowd"]
    print("crowd px %d: figures %d (%.1f%%), seats %d, background %d, scraps %d (%.1f%%)" % (
        c, inv["figure"], 100 * inv["figure"] / c, inv["seat"], inv["background"], inv["scrap"], 100 * inv["scrap"] / c))


def sheet(rom: bytes, built, crowd, cover, scale: int = 6) -> None:
    """Contact sheet (templates; magenta = unsure), a map of the instances,
    and the coverage (figures dimmed; seats grey, scraps red)."""
    pal = palette_rgb(rom)
    tiles = []
    for b in built:
        t = b.template
        rgb = pal[np.clip(t, 0, 63)].copy()
        rgb[t == cl.EMPTY] = (40, 40, 70)
        rgb[t == cl.UNSURE] = (255, 0, 255)
        rgb[t == cl.INFILL] = MARKS["infill"]
        im = Image.fromarray(rgb).resize((t.shape[1] * scale, t.shape[0] * scale), Image.NEAREST)
        tile = Image.new("RGB", (max(im.width, 130), im.height + 30), (255, 255, 255))
        tile.paste(im, (0, 30))
        d = ImageDraw.Draw(tile)
        sw = sum(1 for p in b.placed if p.swap)
        d.text((2, 1), b.fig.name, fill=(0, 0, 0))
        d.text((2, 15), "%s x%d%s" % (b.fig.view, len(b.placed), (" (%d swapped)" % sw) if sw else ""), fill=(0, 0, 0))
        tiles.append(tile)
    width = 1500
    rows, row, w = [], [], 0
    for t in tiles:
        if row and w + t.width > width:
            rows.append(row)
            row, w = [], 0
        row.append(t)
        w += t.width + 8
    rows.append(row)
    out = Image.new("RGB", (width, sum(max(t.height for t in r) + 8 for r in rows)), (255, 255, 255))
    y = 0
    for r in rows:
        x = 0
        for t in r:
            out.paste(t, (x, y))
            x += t.width + 8
        y += max(t.height for t in r) + 8
    out.save(OUT / "sheet.png")
    # map: the crowd with each instance's box and number
    s = 3
    rgb = pal[np.clip(crowd, 0, 63)].copy()
    rgb[crowd < cl.LINE] = (0, 50, 0)
    im = Image.fromarray(rgb // 2).resize((crowd.shape[1] * s, crowd.shape[0] * s), Image.NEAREST)
    d = ImageDraw.Draw(im)
    for k, b in enumerate(built):
        if b.fig.line != 1:
            continue
        col = tuple(int(c) for c in np.random.default_rng(k + 7).integers(90, 256, 3))
        _, _, fw, fh = b.fig.box
        for p in b.placed:
            d.rectangle([p.x * s, p.y * s, (p.x + fw) * s - 1, (p.y + fh) * s - 1], outline=col)
            d.text((p.x * s + 2, p.y * s + 1), "%d%s" % (k, "m" if p.mirrored else ""), fill=col)
    im.save(OUT / "map.png")
    # coverage
    rgb = pal[np.clip(crowd, 0, 63)].copy()
    rgb[crowd < cl.LINE] = (0, 50, 0)
    done = cover > 0
    rgb[done] = rgb[done] // 4 + np.array([0, 0, 50], np.uint8)
    rest = (crowd >= cl.LINE) & ~done
    rgb[rest & np.isin(crowd, cl.SEAT)] = (120, 120, 120)
    rgb[rest & ~np.isin(crowd, cl.SEAT) & (crowd != 31) & (crowd != cl.LINE)] = (255, 0, 0)
    Image.fromarray(rgb).resize((crowd.shape[1] * s, crowd.shape[0] * s), Image.NEAREST).save(OUT / "coverage.png")


def review(rom: bytes, built, pic, where: Path = REVIEW) -> None:
    """The sheet to mark up (unscaled), its untouched copy and its layout."""
    pal = palette_rgb(rom)
    m, gap, head, width = MARGIN, 10, 13, 720
    measure = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    cells, x, y, row_h = [], gap, gap, 0
    built = [b for b in built if not b.fig.size]      # drawn views: not in the picture
    for b in built:
        fx, fy, w, h = b.fig.box
        cw, ch = w + 2 * m, h + 2 * m
        slot = max(cw, int(measure.textlength(b.fig.name)) + 4)
        if x + slot > width and x > gap:
            x, y, row_h = gap, y + row_h + gap, 0
        cells.append({"name": b.fig.name, "cell": [x, y + head, cw, ch], "origin": [fx - m, fy - m]})
        x += slot + gap
        row_h = max(row_h, ch + head)
    height = y + row_h + gap + 3 * 14 + gap
    out = Image.new("RGB", (width, height), (255, 255, 255))
    d = ImageDraw.Draw(out)
    for b, c in zip(built, cells):
        cx, cy, cw, ch = c["cell"]
        ox, oy = c["origin"]
        ctx = cl.window(pic, ox, oy, cw, ch)
        lum = (pal[np.clip(ctx, 0, 63)].astype(float) @ np.array([0.299, 0.587, 0.114]))[..., None] / 255
        dark, light = np.array(CONTEXT[0], float), np.array(CONTEXT[1], float)
        rgb = (dark + (light - dark) * lum).round().astype(np.uint8)
        rgb[ctx < 0] = (60, 60, 60)
        bx, by_ = b.origin
        t = b.template[by_:by_ + ch - 2 * m, bx:bx + cw - 2 * m]      # the box, paint over it
        inner = rgb[m:m + t.shape[0], m:m + t.shape[1]]
        fig_px = t >= 0
        inner[fig_px] = pal[t[fig_px]]
        unsure = t == cl.UNSURE
        inner[unsure] = pal[np.clip(ctx[m:m + t.shape[0], m:m + t.shape[1]][unsure], 0, 63)]
        inner[t == cl.INFILL] = MARKS["infill"]
        out.paste(Image.fromarray(rgb), (cx, cy))
        d.text((cx, cy - head), b.fig.name, fill=(0, 0, 0))
    ly = height - 3 * 14 - gap
    for k, (what, col) in enumerate(MARKS.items()):
        d.rectangle([gap, ly + 14 * k, gap + 10, ly + 14 * k + 10], fill=col)
        d.text((gap + 16, ly + 14 * k), {"add": "yellow: the figure's too", "infill": "red: the figure's, needs painting",
                                         "remove": "green: not the figure's"}[what], fill=(0, 0, 0))
    where.mkdir(parents=True, exist_ok=True)
    out.save(where / "figures_review.png")
    out.save(where / "figures_review_untouched.png")
    (where / "layout.json").write_text(json.dumps({"margin": m, "cells": cells}, indent=1))


def read_marks(painted: Path, where: Path = REVIEW) -> tuple[dict, dict]:
    """Per figure name: {add, infill, remove: set of picture (x, y)}, and
    counts of changed pixels that are no mark or lie outside the cells.
    ``where`` holds the sheet's layout and untouched copy."""
    lay = json.loads((where / "layout.json").read_text())
    a = np.asarray(Image.open(where / "figures_review_untouched.png").convert("RGB")).astype(int)
    b = np.asarray(Image.open(painted).convert("RGB")).astype(int)
    if a.shape != b.shape:
        raise SystemExit("the painted sheet is %s, the review sheet %s: keep its size" % (b.shape[:2], a.shape[:2]))
    changed = (a != b).any(axis=2)
    pairs = list(MARKS.items()) + LEGACY
    names, refs = [n for n, _ in pairs], np.array([c for _, c in pairs])
    dist = np.sqrt(((b[:, :, None, :] - refs[None, None]) ** 2).sum(axis=3))
    kind = np.where(dist.min(axis=2) <= 120, dist.argmin(axis=2), -1)
    marks, used = {}, np.zeros_like(changed)
    for c in lay["cells"]:
        cx, cy, cw, ch = c["cell"]
        ox, oy = c["origin"]
        sub = changed[cy:cy + ch, cx:cx + cw]
        used[cy:cy + ch, cx:cx + cw] = True
        got = {n: set() for n in MARKS}
        for r, q in zip(*np.nonzero(sub)):
            k = kind[cy + r, cx + q]
            if k >= 0:
                got[names[k]].add((int(ox + q), int(oy + r)))
        if any(got.values()):
            marks[c["name"]] = got
    odd = {"not a mark colour": int((changed & (kind < 0)).sum()), "outside the cells": int((changed & ~used).sum())}
    return marks, odd


def apply_marks(marks: dict, figures: Path) -> None:
    """Merge the marks into figures.json: a pixel keeps its latest mark."""
    data = json.loads(figures.read_text())
    by = {d["name"]: d for d in data["figures"]}
    for d in data["figures"]:
        got = marks.get(d["name"])
        if not got:
            continue
        f = cl.Figure.from_json(d)
        if f.base:                            # a made view: marks in its base's box
            f.box = tuple(by[f.base]["box"])
            x, y, w, h = f.box
            got = {n: {p for p in s if x <= p[0] < x + w and y <= p[1] < y + h} for n, s in got.items()}
        x, y, w, h = f.box
        have = {n: {(px, py) for px, py in zip(*np.nonzero(f.runs(n).T))} for n in MARKS}
        have = {n: {(x + px, y + py) for px, py in s} for n, s in have.items()}
        for n in MARKS:
            for other in MARKS:
                have[other] -= got[n] if other != n else set()
            have[n] |= got[n]
        pts = set().union(*have.values())
        if pts and not f.base:                # grow the box over marks in the margin
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            x0, y0 = min(x, min(xs)), min(y, min(ys))
            x1, y1 = max(x + w, max(xs) + 1), max(y + h, max(ys) + 1)
            d["box"] = [x0, y0, x1 - x0, y1 - y0]
            x, y, w, h = d["box"]
        for n in MARKS:
            m = np.zeros((h, w), bool)
            for px, py in have[n]:
                m[py - y, px - x] = True
            if m.any():
                d[n] = cl.to_runs(m, x, y)
            else:
                d.pop(n, None)
    figures.write_text(compact(json.dumps(data, indent=1)) + "\n")


# the paint sheet: crowd indices offered (line 1 but 16 and 25: the same
# colours as 31 and 20, which the templates use), then the sheet's own
PAINTABLE = [31, 30, 29, 22, 21, 28, 27, 18, 19, 17, 26, 20, 24, 23]
ERASE = (255, 0, 255)                     # magenta on the paint layer: the starting pixel goes
GUIDES = {"page": (236, 236, 236), "cell": (64, 118, 104), "text": (24, 24, 64), "frame": (255, 210, 0),
          "infill": (255, 0, 0)}
TOUCH_UPS = {"back_shorts_a": "the goblin ears off"}   # made views to touch up (characters' notes)
PAINT = OUT / "paint"
PAINT_MARGIN = 6


def paint_rows(built, data: dict) -> list[list[dict]]:
    """The sheet's rows. Per character with a view still to make, or made
    by the owner's paint: its other view, the references the note names,
    then the view (``target``): painted over ``start`` (a figure as it is
    shown), or drawn on an empty canvas ``size``. Then the touch-ups and
    the figures with gaps (infill) or paint of their own."""
    by = {b.fig.name: b for b in built}
    defs = {d["name"]: d for d in data["figures"]}
    rows, listed = [], set()

    def cell(target, start, size, note, label=None) -> dict:
        listed.add(target)
        return {"kind": "paint", "target": target, "start": start, "size": size, "note": note,
                "exists": target in by, "label": label or target}

    for c in data.get("characters", []):
        for side, other in (("front", "back"), ("back", "front")):
            v = c.get(side)
            if isinstance(v, dict):
                size = list(by[v["new"]].template.shape[::-1]) if v.get("new") else None
                target = cell("%s_%s" % (side, c["name"]), v.get("paint"), size, v.get("note", ""))
            elif isinstance(v, str) and defs.get(v, {}).get("paint") is not None and v not in TOUCH_UPS:
                d = defs[v]
                target = cell(v, d.get("from"), d.get("size"), d.get("note", ""))
            else:
                continue
            row = [{"kind": "ref", "figure": c[other], "label": c[other]}] if isinstance(c.get(other), str) else []
            row += [{"kind": "ref", "figure": n, "label": n} for n in sorted(by)
                    if n in target["note"] and n != target["start"] and n != c.get(other)]
            rows.append(row + [target])
    for name, note in TOUCH_UPS.items():
        rows.append([cell(name, name, None, note)])
    gaps = [b.fig.name for b in built if b.fig.name not in listed and not b.fig.base and not b.fig.size
            and ((b.unpainted == cl.INFILL).any() or b.fig.paint)]
    if gaps:
        rows.append([cell(n, n, None, "fill the red (the picture never shows it)" if k == len(gaps) - 1 else "")
                     for k, n in enumerate(gaps)])
    return rows


def paint_frames(by: dict, c: dict) -> tuple[np.ndarray, np.ndarray, tuple[int, int]]:
    """A paint cell's starting figure (what its paint starts from), its
    view as shown now and where that lies from the start's top-left."""
    if c["exists"]:
        b = by[c["target"]]
        start = b.unpainted
        left, top, _, _ = cl.paint_canvas(start.shape[1], start.shape[0], b.fig.paint)
        return start, b.template, (-left, -top)
    start = by[c["start"]].template if c["start"] else np.full(c["size"][::-1], cl.EMPTY, np.int16)
    return start, start, (0, 0)


def paint_sheet(rom: bytes, built, where: Path = PAINT) -> None:
    """``paint.png`` (indexed: PAINTABLE, ERASE, GUIDES; every figure as it
    is shown now) and ``layout.json``: every cell's place and, for a cell to
    paint, where its starting figure's top-left lies on the sheet."""
    pal = palette_rgb(rom)
    by = {b.fig.name: b for b in built}
    data = json.loads(FIGURES.read_text())
    rows = paint_rows(built, data)
    colours = [tuple(int(c) for c in pal[i]) for i in PAINTABLE] + [ERASE] + list(GUIDES.values())
    index = {i: k for k, i in enumerate(PAINTABLE)}
    g = {n: len(PAINTABLE) + 1 + k for k, n in enumerate(GUIDES)}
    gap, head, foot = 8, 12, 12
    intro = ["Paint on the layer 'paint', in the yellow cells only, with the crowd's colours (below).",
             "Your pixels replace the figure's; magenta erases one. Red: a gap to fill. Grey-green: empty.",
             "Grey cells are references. Every view faces right like the picture's (front: front-right)."]
    measure = ImageDraw.Draw(Image.new("P", (1, 1)))
    placed, y, width = [], gap + 14 * len(intro) + gap, 0
    for row in rows:
        x, row_h = gap, 0
        for c in row:
            e = dict(c)
            if c["kind"] == "ref":
                h, w = by[c["figure"]].template.shape
                m = 2
                e.update(cell=[x, y + head, w + 2 * m, h + 2 * m], at=[x + m, y + head + m])
            else:
                start, shown, (sx, sy) = paint_frames(by, c)
                x0, y0 = min(0, sx), min(0, sy)
                x1, y1 = max(start.shape[1], sx + shown.shape[1]), max(start.shape[0], sy + shown.shape[0])
                m = PAINT_MARGIN
                ox, oy = x + m - x0, y + head + m - y0
                e.update(cell=[x, y + head, x1 - x0 + 2 * m, y1 - y0 + 2 * m], origin=[ox, oy],
                         at=[ox + sx, oy + sy], start_hash=cl.template_hash(start), start_size=list(start.shape[::-1]))
            cw, ch = e["cell"][2:]
            placed.append(e)
            note_w = int(measure.textlength(c.get("note", ""))) if c["kind"] == "paint" else 0
            width = max(width, x + note_w + gap)
            x += max(cw, int(measure.textlength(c["label"])) + 4) + gap
            row_h = max(row_h, head + ch + (foot if c["kind"] == "paint" else 0))
        width = max(width, x)
        y += row_h + gap
    # every crowd figure as it is now, to look at (owner): the picture's and
    # the made ones, fronts then backs (line 1: the pen's referee is not in
    # these colours)
    wrap = max(width, 480)
    section_y = y
    y += 16
    for view in ("front", "back"):
        x, row_h = gap, 0
        for b in [b for b in built if b.fig.line == 1 and b.fig.view == view]:
            h, w = b.template.shape
            slot = max(w + 4, int(measure.textlength(b.fig.name)) + 4)
            if x + slot > wrap and x > gap:
                x, y, row_h = gap, y + row_h + gap, 0
            placed.append({"kind": "ref", "figure": b.fig.name, "label": b.fig.name, "every": True,
                           "cell": [x, y + head, w + 4, h + 4], "at": [x + 2, y + head + 2]})
            x += slot + gap
            row_h = max(row_h, head + h + 4)
        y += row_h + gap
    width = max(width, wrap)
    swatch_y = y
    height = swatch_y + 12 + 14 + gap
    width = max(width, gap + 17 * 22, int(max(measure.textlength(t) for t in intro)) + 2 * gap)
    out = Image.new("P", (width, height), g["page"])
    out.putpalette([v for c in colours for v in c] + [0, 0, 0] * (256 - len(colours)))
    d = ImageDraw.Draw(out)
    d.fontmode = "1"
    for k, t in enumerate(intro):
        d.text((gap, gap + 14 * k), t, fill=g["text"])
    d.line([gap, section_y, width - gap, section_y], fill=g["text"])
    d.text((gap, section_y + 3), "Every crowd figure as it is now (references):", fill=g["text"])
    for e in placed:
        cx, cy, cw, ch = e["cell"]
        d.rectangle([cx, cy, cx + cw - 1, cy + ch - 1], fill=g["cell"])
        if e["kind"] == "paint":
            d.rectangle([cx - 1, cy - 1, cx + cw, cy + ch], outline=g["frame"])
            d.text((cx, cy + ch + 1), e["note"], fill=g["text"])
        d.text((cx, cy - head), e["label"], fill=g["text"])
        t = by[e["figure"]].template if e["kind"] == "ref" else paint_frames(by, e)[1]
        ax, ay = e["at"]
        for (r, q), v in np.ndenumerate(t):
            if v >= 0:
                k = index.get(int(cl.canonical(np.array([v]))[0]))
                if k is None:
                    raise SystemExit("%s: colour %d not offered" % (e["label"], v))
                out.putpixel((ax + q, ay + r), k)
            elif v == cl.INFILL:
                out.putpixel((ax + q, ay + r), g["infill"])
    for k, i in enumerate(PAINTABLE + [None]):
        sx = gap + 22 * k
        d.rectangle([sx, swatch_y, sx + 15, swatch_y + 11], fill=index[i] if i is not None else len(PAINTABLE))
        d.text((sx, swatch_y + 13), str(i) if i is not None else "erase", fill=g["text"])
    where.mkdir(parents=True, exist_ok=True)
    out.save(where / "paint.png")
    (where / "layout.json").write_text(json.dumps({
        "about": "paint.png's cells (crowd_build.py paint): cell [x, y, w, h]; at: the sheet pixel of the "
                 "shown figure's top-left; origin (cells to paint): of its starting figure's, which the paint "
                 "is read against; colours: the sheet's colour k is crowd index paintable[k], then erase, "
                 "then the guides",
        "paintable": PAINTABLE, "erase": len(PAINTABLE), "guides": g, "cells": placed}, indent=1))
    print("paint sheet %dx%d, %d cells to paint -> %s" % (width, height, sum(e["kind"] == "paint" for e in placed), where))


def find_graft(sheet: np.ndarray, block: np.ndarray, cells: list, by: dict, skip: dict) -> list | None:
    """Where on the sheet (RGB) the owner took ``block`` (a rect copied from
    it): [figure, x, y] from the figure's box's top-left, the figure being
    the one a cell shows there (a reference, or a cell's view as shown);
    None if it is no copy of a figure's rect."""
    h, w = block.shape[:2]
    H, W = sheet.shape[:2]
    for e in sorted(cells, key=lambda c: c["kind"] != "ref"):
        if e is skip:
            continue
        name = e["figure"] if e["kind"] == "ref" else (e["target"] if e["exists"] else e["start"])
        if not name:
            continue
        cx, cy, cw, ch = e["cell"]
        ax, ay = e["at"]
        ox, oy = by[name].origin
        for y in range(max(cy - h + 1, 0), min(cy + ch, H - h + 1)):
            for x in range(max(cx - w + 1, 0), min(cx + cw, W - w + 1)):
                if (sheet[y:y + h, x:x + w] == block).all():
                    return [name, x - ax - ox, y - ay - oy]
    return None


def read_paint(built, layer: Path, where: Path, graft: Path | None = None) -> tuple[dict, dict]:
    """The owner's paint layer (an image the sheet's size, transparent but
    for the paint) read against the sheet in ``where``: per cell to paint,
    its view's new paint runs [x, y, length, colour] from the starting
    figure's top-left (its view as shown with the layer over it, against
    the start). ``graft``: a layer of rects the owner copied from the sheet
    onto cells (combinations), under the paint: each becomes the view's
    graft [figure, x, y, w, h, at x, at y] (by reference, no pixels). Also
    counts of pixels ignored (outside the cells, or not a crowd colour)."""
    lay = json.loads((where / "layout.json").read_text())
    by = {b.fig.name: b for b in built}
    sheet_rgb = np.asarray(Image.open(where / "paint.png").convert("RGB")).astype(int)
    g_rgba = np.asarray(Image.open(graft).convert("RGBA")).astype(int) if graft else None
    im = Image.open(layer)
    if im.mode != "P":
        raise SystemExit("%s: export the paint layer as an indexed PNG" % layer)
    k = np.asarray(im).astype(int)
    alpha = np.asarray(im.convert("RGBA"))[..., 3] > 0
    sheet_pal = Image.open(where / "paint.png").getpalette()[:3 * (len(PAINTABLE) + 1)]
    layer_pal = im.getpalette()
    colour = {}            # layer index -> crowd index (EMPTY: erase), by RGB
    for i in np.unique(k[alpha]).tolist():
        rgb = tuple(layer_pal[3 * i:3 * i + 3])
        for j in range(len(PAINTABLE) + 1):
            if tuple(sheet_pal[3 * j:3 * j + 3]) == rgb:
                colour[i] = PAINTABLE[j] if j < len(PAINTABLE) else cl.EMPTY
                break
    used = np.zeros_like(alpha)
    out = {}
    for e in lay["cells"]:
        if e["kind"] != "paint":
            continue
        cx, cy, cw, ch = e["cell"]
        used[cy:cy + ch, cx:cx + cw] = True
        start, shown, (sx, sy) = paint_frames(by, e)
        if cl.template_hash(start) != e["start_hash"]:
            raise SystemExit("%s: its starting figure changed since the sheet was drawn" % e["target"])
        ox, oy = e["origin"]
        x0, y0 = cx - ox, cy - oy                     # the cell from the start's top-left
        f = np.full((ch, cw), cl.EMPTY, np.int16)    # the view now, over the cell
        f[sy - y0:sy - y0 + shown.shape[0], sx - x0:sx - x0 + shown.shape[1]] = shown
        st = np.full((ch, cw), cl.EMPTY, np.int16)
        st[-y0:-y0 + start.shape[0], -x0:-x0 + start.shape[1]] = start
        grafts = None
        if g_rgba is not None and (g_rgba[cy:cy + ch, cx:cx + cw, 3] > 0).any():
            gy, gx = np.nonzero(g_rgba[cy:cy + ch, cx:cx + cw, 3] > 0)
            ry0, rx0, ry1, rx1 = gy.min(), gx.min(), gy.max() + 1, gx.max() + 1
            block = g_rgba[cy + ry0:cy + ry1, cx + rx0:cx + rx1, :3]
            if not (g_rgba[cy + ry0:cy + ry1, cx + rx0:cx + rx1, 3] > 0).all():
                raise SystemExit("%s: the copied rect is not whole" % e["target"])
            src = find_graft(sheet_rgb, block, lay["cells"], by, e)
            if src is None:
                raise SystemExit("%s: the copied rect is no figure's on the sheet" % e["target"])
            gw, gh = rx1 - rx0, ry1 - ry0
            grafts = [[src[0], int(src[1]), int(src[2]), int(gw), int(gh), int(rx0 + x0), int(ry0 + y0)]]
            # the start with the graft: what the paint is read against; the view now shows it too
            for name, gx_, gy_, w_, h_, ax_, ay_ in grafts:
                r = cl.graft_rect(by[name], gx_, gy_, w_, h_)
                st[ay_ - y0:ay_ - y0 + h_, ax_ - x0:ax_ - x0 + w_] = r
                f[ay_ - y0:ay_ - y0 + h_, ax_ - x0:ax_ - x0 + w_] = r
        sub, on = k[cy:cy + ch, cx:cx + cw], alpha[cy:cy + ch, cx:cx + cw]
        for (r, q) in zip(*np.nonzero(on)):
            if int(sub[r, q]) in colour:
                f[r, q] = colour[int(sub[r, q])]
        runs = []
        for r in range(ch):
            q = 0
            while q < cw:
                if f[r, q] == st[r, q]:
                    q += 1
                    continue
                n = 1
                while q + n < cw and f[r, q + n] == f[r, q] and f[r, q + n] != st[r, q + n]:
                    n += 1
                runs.append([int(q + x0), int(r + y0), n, int(f[r, q])])
                q += n
        out[e["target"]] = dict(e, paint=runs, graft=grafts, view=f, frame=(x0, y0), anchor=start_anchor(by, e))
    bad = alpha & ~np.isin(k, list(colour))
    return out, {"outside the cells": int((alpha & ~used).sum()), "not a crowd colour": int(bad.sum())}


def start_anchor(by: dict, e: dict) -> tuple[int, int]:
    """Where the box's top-left lies in a paint cell's start: the base's
    origin for a made view (its start is the base as shown), else 0, 0."""
    if e["exists"]:
        b = by[e["target"]]
        return tuple(by[b.fig.base].origin) if b.fig.base else (0, 0)
    return tuple(by[e["start"]].origin) if e["start"] else (0, 0)


def diff_runs(view: np.ndarray, at: tuple[int, int], start: np.ndarray, start_at: tuple[int, int]) -> list:
    """Paint runs [x, y, length, colour] from the start's top-left: where
    ``view`` (its top-left at ``at``) differs from ``start`` (at
    ``start_at``, see-through round it)."""
    x0, y0 = min(at[0], start_at[0]), min(at[1], start_at[1])
    x1 = max(at[0] + view.shape[1], start_at[0] + start.shape[1])
    y1 = max(at[1] + view.shape[0], start_at[1] + start.shape[0])
    st = np.full((y1 - y0, x1 - x0), cl.EMPTY, np.int16)
    st[start_at[1] - y0:start_at[1] - y0 + start.shape[0], start_at[0] - x0:start_at[0] - x0 + start.shape[1]] = start
    f = st.copy()
    f[at[1] - y0:at[1] - y0 + view.shape[0], at[0] - x0:at[0] - x0 + view.shape[1]] = view
    runs = []
    for r in range(f.shape[0]):
        q = 0
        while q < f.shape[1]:
            if f[r, q] == st[r, q]:
                q += 1
                continue
            n = 1
            while q + n < f.shape[1] and f[r, q + n] == f[r, q] and f[r, q + n] != st[r, q + n]:
                n += 1
            runs.append([int(q + x0 - start_at[0]), int(r + y0 - start_at[1]), n, int(f[r, q])])
            q += n
    return runs


def settle(rom: bytes, got: dict, figures: Path, rounds: int = 4) -> None:
    """After write_paint: every view read keeps exactly what the owner saw
    in its cell, even where its start changed in the same round (a base
    painted too: back_shorts_a's ears off under back_spiky): its paint is
    read again against the new start, until nothing moves."""
    for _ in range(rounds):
        _, _, built, _ = cl.build(rom, cl.load_figures(figures))
        by = {b.fig.name: b for b in built}
        data = json.loads(figures.read_text())
        defs = {d["name"]: d for d in data["figures"]}
        moved = 0
        for t, e in got.items():
            if t not in by or t not in defs:
                continue
            b = by[t]
            ax, ay = start_anchor(by, dict(e, exists=True))
            oax, oay = e["anchor"]
            fx, fy = e["frame"]
            runs = diff_runs(e["view"], (0, 0), b.unpainted, (-fx + oax - ax, -fy + oay - ay))
            if runs != b.fig.paint:
                moved += 1
                if runs:
                    defs[t]["paint"] = runs
                else:
                    defs[t].pop("paint", None)
        if not moved:
            return
        figures.write_text(compact(json.dumps(data, indent=1)) + "\n")
        print("settled %d view(s) on their changed starts" % moved)
    raise SystemExit("the views did not settle")


def write_paint(got: dict, figures: Path, done: set = frozenset()) -> None:
    """Write the paint into figures.json: a view's paint replaces its last
    (a graft read replaces its grafts); a view new to it (a character's
    view still to make) becomes a figure, made from its start or drawn on
    its canvas. A view the owner calls ``done`` becomes the character's
    view; a character with both views loses its stand-in."""
    data = json.loads(figures.read_text())
    defs = {d["name"]: d for d in data["figures"]}
    for target, e in got.items():
        d = defs.get(target)
        if d is None:
            if not e["paint"] and not e.get("graft"):
                continue
            side = target.split("_", 1)[0]
            d = {"name": target, "view": side}
            if e["start"]:
                d["from"] = e["start"]
            else:
                d["size"] = e["size"]
            if e.get("note"):
                d["note"] = e["note"]
            data["figures"].append(d)
            defs[target] = d
        if e.get("graft"):
            d["graft"] = e["graft"]
        if target in done:
            side = target.split("_", 1)[0]
            for c in data.get("characters", []):
                if "%s_%s" % (side, c["name"]) == target and isinstance(c.get(side), dict):
                    c[side] = target
                    if isinstance(c.get("front"), str) and isinstance(c.get("back"), str):
                        c.pop("standin", None)
        if e["paint"]:
            d["paint"] = e["paint"]
        else:
            d.pop("paint", None)
    figures.write_text(compact(json.dumps(data, indent=1)) + "\n")


def main() -> None:
    global FIGURES, OUT_JSON
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("command", choices=["build", "sheet", "review", "marks", "paint"])
    ap.add_argument("--read", default=None, help="paint: the owner's paint layer (indexed PNG, the sheet's size) "
                    "to read against the sheet in --into; with --apply written to figures.json, then a new sheet")
    ap.add_argument("--graft", default=None, help="paint --read: a layer of rects copied from the sheet (combinations)")
    ap.add_argument("--done", default="", help="paint --apply: the views the owner calls done (comma separated): "
                    "they become their characters' views")
    ap.add_argument("--rom", default=str(ROOT / "game/rom/mlh.gen"))
    ap.add_argument("--file", default=str(REVIEW / "figures_review.png"), help="marks: the painted sheet")
    ap.add_argument("--sheet", default=None, help="marks: the sheet's folder (layout, untouched copy); "
                    "default: the painted sheet's folder if it has a layout, else out/crowd/review")
    ap.add_argument("--into", default=None, help="review / paint: the folder to draw the sheet in "
                    "(default out/crowd/review, out/crowd/paint)")
    ap.add_argument("--apply", action="store_true", help="marks: write them to figures.json and rebuild")
    ap.add_argument("--figures", default=str(FIGURES), help="the definitions (for trying marks on a copy)")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    rom = Path(a.rom).read_bytes()
    if Path(a.figures).resolve() != FIGURES.resolve():   # a trial on a copy: keep crowd.json
        FIGURES, OUT_JSON = Path(a.figures), OUT / "crowd_trial.json"
    if a.command == "paint" and a.read:
        where = Path(a.into or PAINT)
        _, _, built0, _ = cl.build(rom, cl.load_figures(FIGURES))
        got, odd = read_paint(built0, Path(a.read), where, Path(a.graft) if a.graft else None)
        for name, e in got.items():
            print("%-16s %d runs, %d px%s%s" % (name, len(e["paint"]), sum(r[2] for r in e["paint"]),
                                                "" if e["exists"] else " (new)",
                                                " graft %s" % e["graft"] if e.get("graft") else ""))
        print("ignored:", odd)
        if not a.apply:
            return
        write_paint(got, FIGURES, {n for n in a.done.split(",") if n})
        settle(rom, got, FIGURES)
        kept = where / "read"
        kept.mkdir(exist_ok=True)
        shutil.copyfile(a.read, kept / ("paint_layer_%s.png" % time.strftime("%Y%m%d-%H%M%S")))
        n = int(where.name[5:]) + 1 if where.name.startswith("round") else 2   # PAINT itself: round 1
        a.into = str(PAINT / ("round%d" % n))
    if a.command == "marks":
        painted = Path(a.file)
        where = Path(a.sheet) if a.sheet else (painted.parent if (painted.parent / "layout.json").exists() else REVIEW)
        marks, odd = read_marks(painted, where)
        for name, got in marks.items():
            print("%-16s %s" % (name, ", ".join("%s %d" % (n, len(s)) for n, s in got.items() if s)))
        print("ignored:", odd)
        if not a.apply:
            return
        apply_marks(marks, FIGURES)
        kept = (where if OUT_JSON.name == "crowd.json" else OUT / "review_trial") / "marked"   # kept with its round
        kept.mkdir(exist_ok=True)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        shutil.copyfile(a.file, kept / ("figures_review_%s.png" % stamp))
        shutil.copyfile(where / "figures_review_untouched.png", kept / ("figures_review_%s_untouched.png" % stamp))
    pic, crowd, built, cover, inv = build(rom)
    np.save(OUT / "cover.npy", cover)
    report(built, inv)
    if a.command == "sheet":
        sheet(rom, built, crowd, cover)
    if a.command in ("review", "marks"):
        review(rom, built, pic, Path(a.into or REVIEW) if OUT_JSON.name == "crowd.json" else OUT / "review_trial")
    if a.command == "paint":
        paint_sheet(rom, built, Path(a.into or PAINT))


if __name__ == "__main__":
    main()
