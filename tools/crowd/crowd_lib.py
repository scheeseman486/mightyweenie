"""The rink picture's crowd as separate figures (plan 15, docs/rink3d.md).

The crowd around the rink picture (``$24CFC``, palette line 1 outside the
boards) is a handful of figure drawings stamped many times, overlapping each
other and the seats. Each figure is defined by hand with a few numbers
(``tools/crowd/figures.json``) and everything else comes from the ROM:

* **source**: a box on the picture around one drawing of the figure;
* **cut**: how the figure is told from what surrounds it in the box, either
  ``seeds`` (pixels on its parts; the parts are the figure colours flooded
  from them, stopped by ``walls``; dark ``patches`` add dark areas such as
  black shoulder pads) or a ``lasso`` polygon (its parts are those mostly
  inside it). Either way the dark outline round the parts and the dark
  pixels they enclose are the figure's too;
* **instances**: everywhere the source's figure pixels appear again (at
  least ``match`` of those the picture shows, mirrored too), also with
  colours swapped (``recolours``: team-blue shorts drawn grey on some fans)
  and with either brown (``canonical``). Each instance is cut the same way
  in its own surroundings;
* **template**: per pixel, the colour most instances show there (one
  instance's hidden legs are another's visible ones). Where they tie it is
  unsure. Recoloured instances draw the template with their swap.

What no figure takes is a seat (the rims' and seat bodies' greys), the
background (black) or a scrap (a bit of a figure cut by the picture's edge
or the boards, too small to tell). Only the left half is used: the crowd is
mirrored about x = 256, but for the top-centre block (left out, owner).
``game/assets/crowd/crowd.json`` keeps the numbers; MwCrowd rebuilds the
masks and templates from the ROM.
"""
from __future__ import annotations

import json
import struct
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

RINK_PICTURE = 0x24CFC
WIDTH, HALF = 512, 256
LINE = 16                       # crowd colours are line 1: indices 16..31
DARK = (30, 31)                 # dark grey and black: background unless outline / inside
SEAT = (28, 29, 30)             # white, grey, dark grey: the seats' rims and bodies
EMPTY = -2                      # template: see-through (or never shown: a gap to paint)
UNSURE = -4                     # template: instances tie
INFILL = -5                     # template: the owner marked it to paint (no ROM pixel)
NOT_CROWD = -1                  # picture: rink, boards, left out, off the picture
TOP_CENTRE = (208, 0, 256, 48)  # x0, y0, x1, y1 (left half's part): not mirrored, left out (owner)
BROWN, TEAM_BROWN = 20, 25      # one brown, two indices (see canonical)
# team-blue shorts (18 light, 19 dark) drawn in greys on some fans
RECOLOURS = [((18, 29), (19, 30)), ((18, 21), (19, 22))]


# --- the picture ---------------------------------------------------------

def picture_indices(rom: bytes, address: int = RINK_PICTURE) -> np.ndarray:
    """The picture as line * 16 + colour (0 where nothing is drawn), H x W."""
    tiles, base, count, w, h = struct.unpack(">IHHHH", rom[address:address + 12])
    words = np.frombuffer(rom, ">u2", w * h, address + 12).reshape(h, w).astype(np.int32)
    out = np.zeros((h * 8, w * 8), np.int16)
    for ty in range(h):
        for tx in range(w):
            word = int(words[ty, tx])
            t = (word & 0x7FF) - base
            if t < 0 or t >= count:
                continue
            raw = np.frombuffer(rom, np.uint8, 32, tiles + 32 * t)
            px = np.empty(64, np.int16)
            px[0::2] = raw >> 4
            px[1::2] = raw & 15
            px = px.reshape(8, 8)
            if word & 0x800:
                px = px[:, ::-1]
            if word & 0x1000:
                px = px[::-1, :]
            line = (word >> 13) & 3
            out[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8] = np.where(px == 0, 0, px + line * 16)
    return out


def crowd_area(pic: np.ndarray) -> np.ndarray:
    """The left half's crowd: line-1 pixels reached from the picture's edge
    through line-1 pixels (so not the pens' floors), without the top centre.
    Returns the picture with NOT_CROWD elsewhere (H x HALF)."""
    left = pic[:, :HALF]
    line1 = left >= LINE
    reach = np.zeros_like(line1)
    stack = [(y, 0) for y in range(left.shape[0]) if line1[y, 0]]
    stack += [(0, x) for x in range(HALF) if line1[0, x]]
    stack += [(left.shape[0] - 1, x) for x in range(HALF) if line1[-1, x]]
    while stack:
        y, x = stack.pop()
        if reach[y, x] or not line1[y, x]:
            continue
        reach[y, x] = True
        for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= yy < left.shape[0] and 0 <= xx < HALF and not reach[yy, xx] and line1[yy, xx]:
                stack.append((yy, xx))
    x0, y0, x1, y1 = TOP_CENTRE
    reach[y0:y1, x0:x1] = False
    return np.where(reach, left, NOT_CROWD).astype(np.int16)


def window(a: np.ndarray, x: int, y: int, w: int, h: int, mirrored: bool = False) -> np.ndarray:
    """a[y:y+h, x:x+w] padded with NOT_CROWD, mirrored left-right if asked."""
    out = np.full((h, w), NOT_CROWD, a.dtype)
    sx0, sy0 = max(x, 0), max(y, 0)
    sx1, sy1 = min(x + w, a.shape[1]), min(y + h, a.shape[0])
    if sx1 > sx0 and sy1 > sy0:
        out[sy0 - y:sy1 - y, sx0 - x:sx1 - x] = a[sy0:sy1, sx0:sx1]
    return out[:, ::-1] if mirrored else out


# --- colours -------------------------------------------------------------

def canonical(a: np.ndarray) -> np.ndarray:
    """``a`` with TEAM_BROWN drawn as BROWN. The crowd's line has two
    browns that are the same colour with the default team: 20 (fixed) and
    25 (team A's skin shade, recoloured per team by palettes.screen_palette).
    The picture draws the same figure with either, by region (the side
    stands' lowest row and most of the near end use 25). Figures are matched
    and stored with 20; each instance says which brown it is drawn with."""
    return np.where(a == TEAM_BROWN, BROWN, a)


def team_brown(view: np.ndarray, template: np.ndarray) -> bool:
    """Whether an instance (its window ``view``) draws the template's brown
    pixels mostly with TEAM_BROWN."""
    b = template == BROWN
    return int((b & (view == TEAM_BROWN)).sum()) > int((b & (view == BROWN)).sum())


def recolour(a: np.ndarray, swap) -> np.ndarray:
    """``a`` with colours swapped: ``swap`` = ((from, to), ...)."""
    out = a.copy()
    for k, v in swap:
        out[a == k] = v
    return out


def figure_colours(a: np.ndarray) -> np.ndarray:
    """Pixels that can belong to a figure's parts: crowd colours but black,
    dark grey only next to another dark grey or a lighter colour (not the
    background's lone dither dots)."""
    crowd = a >= LINE
    light = crowd & ~np.isin(a, DARK)
    grey = a == 30
    p_light = np.pad(light, 1)
    p_grey = np.pad(grey, 1)
    h, w = a.shape
    near = np.zeros_like(grey)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        near |= p_light[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] | p_grey[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
    return light | (grey & near)


# --- cutting a figure from its surroundings --------------------------------

def flood(allowed: np.ndarray, seeds) -> np.ndarray:
    """4-connected region of ``allowed`` reached from ``seeds`` (row, col)."""
    out = np.zeros_like(allowed)
    h, w = allowed.shape
    stack = [s for s in seeds if 0 <= s[0] < h and 0 <= s[1] < w and allowed[s[0], s[1]]]
    for s in stack:
        out[s[0], s[1]] = True
    while stack:
        y, x = stack.pop()
        for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= yy < h and 0 <= xx < w and allowed[yy, xx] and not out[yy, xx]:
                out[yy, xx] = True
                stack.append((yy, xx))
    return out


def ring(parts: np.ndarray) -> np.ndarray:
    """Pixels 8-next to ``parts`` (and ``parts``)."""
    h, w = parts.shape
    p = np.pad(parts, 1)
    near = np.zeros_like(parts)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            near |= p[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
    return near


def outline(parts: np.ndarray, a: np.ndarray) -> np.ndarray:
    """Black / dark grey pixels 8-next to ``parts``, and dark pixels the
    outside can't reach without crossing parts or that outline (inside)."""
    h, w = parts.shape
    near = ring(parts)
    dark = np.isin(a, DARK)
    keep = parts | (dark & near)
    outside = flood(~keep, [(y, x) for y in range(h) for x in (0, w - 1)] + [(y, x) for x in range(w) for y in (0, h - 1)])
    return (dark & near) | (dark & ~outside & ~parts)


def rule_mask(view: np.ndarray, seeds, walls=(), patches=()) -> np.ndarray:
    """A figure's mask in one view (template-aligned h x w): its parts
    (``seeds``, not through ``walls``) with their outline, plus dark
    ``patches`` (row, col, radius): the pixel there and the dark pixels
    within ``radius`` connected to it through dark pixels (black shoulder
    pads, a dark cap: dark areas the outline rule can't tell from the
    background)."""
    allowed = figure_colours(view)
    for y, x in walls:
        if 0 <= y < allowed.shape[0] and 0 <= x < allowed.shape[1]:
            allowed[y, x] = False
    parts = flood(allowed, seeds)
    mask = parts | outline(parts, view)
    h, w = view.shape
    dark = np.isin(view, DARK)
    rows, cols = np.arange(h)[:, None], np.arange(w)[None, :]
    for y, x, r in patches:
        if not (0 <= y < h and 0 <= x < w) or view[y, x] < LINE:
            continue
        near = (abs(rows - y) <= r) & (abs(cols - x) <= r)
        mask |= flood((dark & near) | ((rows == y) & (cols == x)), [(y, x)])
    return mask


def inside(poly, w: int, h: int, x0: int = 0, y0: int = 0) -> np.ndarray:
    """h x w: pixels (top-left x0, y0) whose centres are inside the polygon
    ``poly`` [(x, y), ...] (even-odd rule)."""
    ys, xs = np.mgrid[0:h, 0:w]
    px, py = xs + x0 + 0.5, ys + y0 + 0.5
    res = np.zeros((h, w), bool)
    n = len(poly)
    for i in range(n):
        xa, ya = poly[i]
        xb, yb = poly[(i + 1) % n]
        if ya == yb:
            continue
        cross = ((ya > py) != (yb > py))
        xi = xa + (py - ya) * (xb - xa) / (yb - ya)
        res ^= cross & (px < xi)
    return res


def lasso_mask(view: np.ndarray, region: np.ndarray, whole: float = 0.7, none: float = 0.3) -> np.ndarray:
    """A figure's mask in one view from a rough lasso ``region`` (h x w): its
    parts (4-connected figure colours) mostly inside the lasso (at least
    ``whole`` of their pixels) whole, those partly inside (between ``none``
    and ``whole``) cut at the lasso, plus the outline of all that and the
    dark pixels it encloses."""
    col = figure_colours(view)
    parts = np.zeros_like(col)
    seen = np.zeros_like(col)
    for y, x in zip(*np.nonzero(col & region)):
        if seen[y, x]:
            continue
        part = flood(col, [(y, x)])
        seen |= part
        frac = (part & region).sum() / part.sum()
        if frac >= whole:
            parts |= part
        elif frac >= none:
            parts |= part & region
    return parts | outline(parts, view)


# --- finding a figure's instances ------------------------------------------

def match(crowd: np.ndarray, key: np.ndarray, at_least: float = 0.85, visible: float = 0.5,
          edge_visible: float = 0.12, edge_least: int = 16, edge_same: float = 0.92) -> list[tuple[int, int, bool]]:
    """Where ``key`` (h x w indices; below LINE = don't care; dark pixels
    count for nothing) appears in ``crowd``, mirrored too, the browns as one
    (canonical): windows (top-left x, y, mirrored; they may stick out of the
    picture) where at least ``visible`` of the key's pixels fall on crowd
    pixels and at least ``at_least`` of those are equal. Pixels off the
    picture or on the boards are hidden, not wrong.

    A figure cut by the picture's edge or the boards shows less: a window
    also counts when what it shows (at least ``edge_visible`` of the key and
    ``edge_least`` pixels) agrees with the key (``edge_same``) and what it
    shows plus what is hidden reach ``visible``."""
    h, w = key.shape
    padded = canonical(np.pad(crowd, ((h - 1, h - 1), (w - 1, w - 1)), constant_values=NOT_CROWD))
    v = sliding_window_view(padded, (h, w))
    on = v >= LINE
    hidden = ~on
    found, seen_at = [], set()
    for mirrored in (False, True):
        k = canonical(key[:, ::-1] if mirrored else key)
        care = (k >= LINE) & ~np.isin(k, DARK)
        n = int(care.sum())
        if n == 0:
            continue
        seen = (on & care).sum(axis=(2, 3))
        same = ((v == k) & care).sum(axis=(2, 3))
        gone = (hidden & care).sum(axis=(2, 3))
        ok = (seen >= visible * n) & (same >= at_least * np.maximum(seen, 1))
        ok |= ((gone > 0) & (seen >= max(edge_least, edge_visible * n)) & (same >= edge_same * seen)
               & (seen + gone >= visible * n))
        for y, x in zip(*np.nonzero(ok)):
            at = (int(x) - (w - 1), int(y) - (h - 1))
            if at not in seen_at:        # a symmetric key matches both ways at one spot: keep one
                seen_at.add(at)
                found.append((at[0], at[1], mirrored))
    return sorted(found, key=lambda i: (i[1], i[0], i[2]))


# --- figures -------------------------------------------------------------

@dataclass
class Figure:
    """A hand definition (figures.json); coordinates are the picture's."""
    name: str
    view: str                                   # "front" or "back"
    box: tuple[int, int, int, int]              # source: x, y, w, h
    seeds: list = field(default_factory=list)   # [x, y]
    walls: list = field(default_factory=list)   # [x, y]
    patches: list = field(default_factory=list)  # [x, y, radius]
    lasso: list = field(default_factory=list)   # [x, y] polygon
    match: float = 0.85
    recolours: list = field(default_factory=list)  # [[[from, to], ...], ...]
    line: int = 1                               # palette line (the pen's referee: 0)
    background: list = field(default_factory=list)  # line-0 figures: colours not theirs
    at: list = field(default_factory=list)      # fixed instances [x, y] (not matched)
    # the owner's marks on the review sheet, as runs [x, y, length] along rows:
    add: list = field(default_factory=list)     # the figure's too (the cut missed them)
    remove: list = field(default_factory=list)  # not the figure's (see-through)
    infill: list = field(default_factory=list)  # the figure's, but no ROM pixel: painted
    # a view the picture never shows, made from another figure ("from"):
    # its template with colours swapped and the marks above (in its box)
    base: str = ""
    swap: list = field(default_factory=list)    # [[from, to], ...]
    # matches that are another figure's (a window cut by an edge that two
    # figures' visible parts fit equally): [x, y] window top-left
    exclude: list = field(default_factory=list)
    # the owner's art (crowd_build.py paint): runs [x, y, length, colour]
    # from the top-left of the template it starts from (colour EMPTY: an
    # erase); x, y may lie outside it (the canvas grows: paint_canvas)
    paint: list = field(default_factory=list)
    # a view drawn from nothing (no "from", never in the picture): its
    # canvas [w, h]
    size: list = field(default_factory=list)
    # a made view's rects of other figures (the owner's combinations):
    # [figure, x, y, w, h, at x, at y] - the figure's rect (from its box's
    # top-left, as shown) replaces the rect at (at x, at y) from the start's
    # top-left, see-through included; before the paint
    graft: list = field(default_factory=list)

    @staticmethod
    def from_json(d: dict) -> "Figure":
        return Figure(d["name"], d["view"], tuple(d.get("box", (0, 0, 0, 0))), d.get("seeds", []),
                      d.get("walls", []), d.get("patches", []), d.get("lasso", []), d.get("match", 0.85),
                      d.get("recolours", []), d.get("line", 1), d.get("background", []), d.get("at", []),
                      d.get("add", []), d.get("remove", []), d.get("infill", []), d.get("from", ""),
                      d.get("swap", []), d.get("exclude", []), d.get("paint", []), d.get("size", []), d.get("graft", []))

    def runs(self, which: str) -> np.ndarray:
        """Box-sized mask of the owner's marks ``which`` (add, remove, infill)."""
        x, y, w, h = self.box
        out = np.zeros((h, w), bool)
        for rx, ry, n in getattr(self, which):
            if 0 <= ry - y < h:
                out[ry - y, max(rx - x, 0):max(rx - x + n, 0)] = True
        return out

    def marked(self, mask: np.ndarray) -> np.ndarray:
        """``mask`` with the owner's marks: plus add, minus remove and infill."""
        return (mask | self.runs("add")) & ~self.runs("remove") & ~self.runs("infill")

    def rel(self, p) -> tuple[int, int]:
        """A picture point as (row, col) in the box."""
        return (p[1] - self.box[1], p[0] - self.box[0])

    def region(self) -> np.ndarray:
        x, y, w, h = self.box
        return inside(self.lasso, w, h, x, y)

    def cut(self, view: np.ndarray, like: np.ndarray | None = None) -> np.ndarray:
        """The figure's mask in ``view`` (box-sized, template-aligned). For
        an instance, ``like`` is the source's figure (recoloured as the
        instance is): the hand seeds it shows and every figure pixel it shows
        as the source does seed the flood (the hand seeds may be hidden)."""
        if self.line != 1:              # outlined in its first background colour
            allowed = (view >= 0) & ~np.isin(view, self.background)
            if self.lasso:
                allowed &= self.region()
            parts = flood(allowed, [self.rel(p) for p in self.seeds])
            return self.marked(parts | (ring(parts) & (view == self.background[0])))
        if self.lasso:
            return self.marked(lasso_mask(view, self.region()))
        seeds = [self.rel(p) for p in self.seeds]
        pads = [self.rel(p[:2]) + (p[2],) for p in self.patches]
        if like is not None:
            seeds = [s for s in seeds if view[s] == like[s]]
            pads = [p for p in pads if view[p[:2]] == like[p[:2]]]
            seeds += list(zip(*np.nonzero((like >= LINE) & ~np.isin(like, DARK) & (view == like))))
        return self.marked(rule_mask(view, seeds, [self.rel(p) for p in self.walls], pads))


@dataclass
class Placed:
    """An instance: window top-left on the picture, its colours, its mask."""
    x: int
    y: int
    mirrored: bool
    team: bool = False          # brown drawn as TEAM_BROWN
    swap: int = 0               # 0, or 1 + index into the figure's swaps
    score: float = 0.0
    mask: np.ndarray | None = None   # template-aligned

    def footprint(self) -> set[tuple[int, int]]:
        m = self.mask[:, ::-1] if self.mirrored else self.mask
        ys, xs = np.nonzero(m)
        return set(zip((ys + self.y).tolist(), (xs + self.x).tolist()))


@dataclass
class Built:
    fig: Figure
    source: np.ndarray                  # canonical colours, box-sized
    swaps: list                         # recolours tried, in instance order
    placed: list[Placed]
    template: np.ndarray | None = None  # with the owner's paint (the view shown)
    clash: int = 0
    unpainted: np.ndarray | None = None  # before the paint (what the paint starts from)
    origin: tuple[int, int] = (0, 0)    # where the box's top-left lies in template


def load_figures(path: Path) -> list[Figure]:
    return [Figure.from_json(d) for d in json.loads(Path(path).read_text())["figures"]]


def build_figure(crowd: np.ndarray, pic: np.ndarray, fig: Figure) -> Built:
    """Source, instances and their masks of one figure."""
    x, y, w, h = fig.box
    if fig.line != 1:                     # drawn once, on another line: take it as it is
        src = window(pic, x, y, w, h)
        placed = [Placed(ax, ay, False, mask=fig.cut(window(pic, ax, ay, w, h)), score=1.0) for ax, ay in fig.at]
        return Built(fig, src, [], placed)
    src = canonical(window(crowd, x, y, w, h))
    mask = fig.cut(src)
    t0 = np.where(mask, src, EMPTY).astype(np.int16)
    key = np.where(figure_colours(t0) & mask, t0, NOT_CROWD).astype(np.int16)
    swaps = [tuple(map(tuple, r)) for r in fig.recolours]
    swaps += [r for r in RECOLOURS if r not in swaps and any((key == a).any() for a, _ in r)]
    tries = [()] + swaps

    def fit(px, py, m, k):
        v = canonical(window(crowd, px, py, w, h, m))
        care = (k >= LINE) & ~np.isin(k, DARK) & (v >= LINE)
        return (float((v[care] == k[care]).mean()) if care.any() else 0.0, int(care.sum()))

    best: dict[tuple[int, int, bool], tuple] = {}
    for si, swap in enumerate(tries):
        k = recolour(key, swap)
        for px, py, m in match(crowd, k, fig.match, edge_same=min(0.95, fig.match + 0.07)):
            if [px, py] in fig.exclude:
                continue
            f = fit(px, py, m, k)
            if (px, py, m) not in best or f > best[(px, py, m)][0]:   # the swap that explains more
                best[(px, py, m)] = (f, si)
    placed = []
    for (px, py, m), (f, si) in sorted(best.items(), key=lambda kv: (kv[0][1], kv[0][0], kv[0][2])):
        like = recolour(t0, tries[si])
        raw = window(crowd, px, py, w, h, m)
        view = canonical(raw)
        placed.append(Placed(px, py, m, team_brown(raw, t0), si, f[0], fig.cut(view, like)))
    return Built(fig, t0, swaps, placed)


def one_per_spot(built: list[Built], overlap: float = 0.7) -> None:
    """Where instances of two figures cover mostly the same pixels (at least
    ``overlap`` of the smaller), keep the better match (the bigger mask if
    the scores are within 0.02)."""
    spots = [(bi, k, p.footprint()) for bi, b in enumerate(built) for k, p in enumerate(b.placed)]
    drop = set()
    for i in range(len(spots)):
        for j in range(i + 1, len(spots)):
            (ba, ka, fa), (bb, kb, fb) = spots[i], spots[j]
            if ba == bb or not fa or not fb:
                continue
            if len(fa & fb) >= overlap * min(len(fa), len(fb)):
                sa, sb = built[ba].placed[ka].score, built[bb].placed[kb].score
                if abs(sa - sb) > 0.02:
                    drop.add((bb, kb) if sa > sb else (ba, ka))
                else:
                    drop.add((bb, kb) if len(fa) >= len(fb) else (ba, ka))
    for bi, b in enumerate(built):
        b.placed = [p for k, p in enumerate(b.placed) if (bi, k) not in drop]


def specks(a: np.ndarray, smallest: int = 8) -> np.ndarray:
    """Pixels of ``a`` in 8-connected bits smaller than ``smallest``: what a
    single instance's cut took from a neighbour, away from the figure."""
    out = np.zeros_like(a)
    seen = np.zeros_like(a)
    h, w = a.shape
    for y, x in zip(*np.nonzero(a)):
        if seen[y, x]:
            continue
        part, stack = [(y, x)], [(y, x)]
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and a[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        part.append((ny, nx))
                        stack.append((ny, nx))
        if len(part) < smallest:
            for py, px in part:
                out[py, px] = True
    return out


def make_template(b: Built, crowd: np.ndarray, pic: np.ndarray) -> None:
    """Per pixel the colour most unswapped instances show (ties: the
    source's colour if it is one of them, else UNSURE)."""
    x, y, w, h = b.fig.box
    vals = np.full((len(b.placed), h, w), NOT_CROWD, np.int16)
    for k, p in enumerate(b.placed):
        if p.swap == 0:
            v = window(pic, p.x, p.y, w, h, p.mirrored) if b.fig.line != 1 else canonical(window(crowd, p.x, p.y, w, h, p.mirrored))
            vals[k][p.mask] = v[p.mask]
    counts = np.stack([(vals == c).sum(axis=0) for c in range(64)])
    top = counts.max(axis=0)
    tied = (counts == top[None]).sum(axis=0) > 1
    shown = top > 0
    t = np.full((h, w), EMPTY, np.int16)
    t[shown & ~tied] = counts.argmax(axis=0)[shown & ~tied]
    src = b.source
    src_top = (src >= 0) & (np.take_along_axis(counts, np.clip(src, 0, 63)[None].astype(np.int64), 0)[0] == top)
    t[shown & tied & src_top] = src[shown & tied & src_top]
    t[shown & tied & ~src_top] = UNSURE
    t[specks(t != EMPTY)] = EMPTY
    t[b.fig.runs("infill")] = INFILL
    b.unpainted = t
    b.template, b.origin = apply_paint(t, b.fig.paint)
    b.clash = int((shown & ((counts > 0).sum(axis=0) > 1)).sum())


def to_runs(mask: np.ndarray, x0: int, y0: int) -> list[list[int]]:
    """A mask (top-left at x0, y0 on the picture) as runs [x, y, length]."""
    out = []
    for r in range(mask.shape[0]):
        row = np.concatenate([[False], mask[r], [False]]).astype(np.int8)
        d = np.diff(row)
        for a, b in zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]):
            out.append([int(x0 + a), int(y0 + r), int(b - a)])
    return out


def paint_canvas(w: int, h: int, paint: list) -> tuple[int, int, int, int]:
    """Where a w x h template lies once painted: (left, top, w', h'). The
    canvas grows to take paint outside it: as much on both sides (a figure
    stands on its bottom centre), up, and down."""
    if not paint:
        return 0, 0, w, h
    x0, x1 = min(r[0] for r in paint), max(r[0] + r[2] - 1 for r in paint)
    y0, y1 = min(r[1] for r in paint), max(r[1] for r in paint)
    side, top, bottom = max(0, -x0, x1 - (w - 1)), max(0, -y0), max(0, y1 - (h - 1))
    return side, top, w + 2 * side, h + top + bottom


def apply_paint(t: np.ndarray, paint: list) -> tuple[np.ndarray, tuple[int, int]]:
    """``t`` with the owner's paint runs, on its grown canvas, and where
    ``t``'s top-left lies on it."""
    h, w = t.shape
    left, top, nw, nh = paint_canvas(w, h, paint)
    out = np.full((nh, nw), EMPTY, np.int16)
    out[top:top + h, left:left + w] = t
    for x, y, n, v in paint:
        out[y + top, x + left:x + left + n] = v
    return out, (left, top)


def graft_rect(src: Built, x: int, y: int, w: int, h: int) -> np.ndarray:
    """``src``'s view as shown, the rect (x, y, w, h) from its box's
    top-left (EMPTY outside it)."""
    out = np.full((h, w), EMPTY, np.int16)
    ox, oy = src.origin
    th, tw = src.template.shape
    for r in range(h):
        for q in range(w):
            ty, tx = oy + y + r, ox + x + q
            if 0 <= ty < th and 0 <= tx < tw:
                out[r, q] = src.template[ty, tx]
    return out


def derive(base: Built, fig: Figure, by_name: dict | None = None) -> Built:
    """A view made from ``base`` (its view as shown): colours swapped
    (``fig.swap``), the marks (remove: see-through; infill: to paint; add:
    the base source's ROM pixel; in the base's box), other figures' rects
    (``fig.graft``) and the owner's paint. It has no instances: the
    picture never shows it."""
    fig.box = base.fig.box
    _, _, bw, bh = fig.box
    ox, oy = base.origin
    sw = [tuple(p) for p in fig.swap]
    t = recolour(base.template, sw)

    def placed(m: np.ndarray, fill=False) -> np.ndarray:
        out = np.full(t.shape, fill, m.dtype)
        out[oy:oy + bh, ox:ox + bw] = m
        return out
    add = placed(fig.runs("add") & (base.source >= 0))
    t[add] = placed(recolour(base.source, sw), EMPTY)[add]
    t[placed(fig.runs("remove"))] = EMPTY
    t[placed(fig.runs("infill"))] = INFILL
    for name, x, y, w, h, ax, ay in fig.graft:
        t[ay:ay + h, ax:ax + w] = graft_rect(by_name[name], x, y, w, h)
    b = Built(fig, base.source, [], [], None, 0, t)
    b.template, (left, top) = apply_paint(t, fig.paint)
    b.origin = (ox + left, oy + top)
    return b


def drawn(fig: Figure) -> Built:
    """A view drawn from nothing: the owner's paint on a ``fig.size``
    canvas (its box: the canvas)."""
    w, h = fig.size
    fig.box = (0, 0, w, h)
    t = np.full((h, w), EMPTY, np.int16)
    b = Built(fig, t.copy(), [], [], None, 0, t)
    b.template, b.origin = apply_paint(t, fig.paint)
    return b


def template_hash(t: np.ndarray) -> int:
    """A checksum of a template for the parity test (row-major,
    h = h * 31 + value + 8, 32 bits)."""
    hv = 0
    for v in t.ravel().tolist():
        hv = (hv * 31 + v + 8) & 0xFFFFFFFF
    return hv


def build(rom: bytes, figs: list[Figure]) -> tuple[np.ndarray, np.ndarray, list[Built], np.ndarray]:
    """picture, crowd (left half), built figures, cover (H x HALF: figure
    number + 1 where an instance's mask takes the pixel, else 0)."""
    pic = picture_indices(rom)
    crowd = crowd_area(pic)
    built = [build_figure(crowd, pic, f) for f in figs if not f.base and not f.size]
    one_per_spot([b for b in built if b.fig.line == 1])
    for b in built:
        make_template(b, crowd, pic)
    by_name = {b.fig.name: b for b in built}
    for f in figs:                    # in order: a made view may start from one made before it
        if f.base or f.size:
            b = derive(by_name[f.base], f, by_name) if f.base else drawn(f)
            built.append(b)
            by_name[f.name] = b
    built.sort(key=lambda b: [f.name for f in figs].index(b.fig.name))
    cover = np.zeros(crowd.shape, np.int32)
    for k, b in enumerate(built):
        if b.fig.line != 1:
            continue
        for p in b.placed:
            for yy, xx in p.footprint():
                if 0 <= yy < crowd.shape[0] and 0 <= xx < crowd.shape[1] and crowd[yy, xx] >= LINE:
                    cover[yy, xx] = k + 1
    return pic, crowd, built, cover


def inventory(crowd: np.ndarray, cover: np.ndarray) -> dict:
    """Every crowd pixel: a figure's, a seat's, the background's or a scrap."""
    on = crowd >= LINE
    fig = on & (cover > 0)
    rest = on & ~fig
    seat = rest & np.isin(crowd, SEAT)
    background = rest & ((crowd == 31) | (crowd == LINE))
    scrap = rest & ~seat & ~background
    return {"crowd": int(on.sum()), "figure": int(fig.sum()), "seat": int(seat.sum()),
            "background": int(background.sum()), "scrap": int(scrap.sum())}
