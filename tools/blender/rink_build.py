"""Builds the 3D rink (plan 14) in Blender from the ROM's physics tables.

Run inside Blender 5.x, from a shell::

    blender --background --python tools/blender/rink_build.py -- [--rom PATH] [--previews DIR]

or from a live Blender session (its Python console)::

    exec(open("<repo>/tools/blender/rink_build.py").read(),
         {"__name__": "__main__", "MW_ARGS": ["--rom", "<repo>/game/rom/mlh.gen"]})

The rink's shape comes from the physics (docs/re/puck.md, Boards and
corners): straight boards at |x| = 185 and |y| = 372 rink px, rounded corners
from the x-limit tables `$1C77E` (far end) and `$1C81E` (near end). Each corner
is drawn as a smooth superellipse fitted to its table (within a fraction of a
pixel of the staircase the puck bounces off). The board and glass layout and
the texture mapping are the owner-approved "version 0.5" (plans/all/14-3d-rink-
view.md, Board faces): every surface carries UV0 = coordinates in one of three
ROM pictures (the rink picture `$24CFC`, the side boards `picture_04a066`, the
referee-side fence `picture_03c264`), so the game can texture it from the ROM.

Objects (one material slot each, named ``mw_<object>``), in the collection
``MW_Rink``:

    floor        the ice and the flat surroundings (rink picture, opaque)
    wall         the solid boards: padding facing the rink, the dark grey wall outside (rink picture)
    glass        far end glass and the near-end glass panels (rink picture, translucent)
    signs        the left side's sign boards, outside the benches (picture_04a066)
    signs_glass  the glass above it (picture_04a066, translucent)
    fence        the referee side's spear fence and gate rail (picture_03c264)
    bench        the left side's bench walls and the bar between them: riveted grey tiles (rink picture)
    bench_glass  the glass on the bench walls (rink picture, translucent)

Units: 1 rink px = 0.05 Blender units (m). Blender axes: X = rink x, Y = -rink y
(north), Z = height. The glTF export turns that into Godot's X = x, Y = up,
Z = y (south).

Nothing ROM-derived is stored: geometry and UVs only. Preview materials load
the PNGs made by ``tools/blender/rink_previews.py`` (out/, gitignored) by
relative path; they are never packed (``rink_export.py`` checks).
"""
from __future__ import annotations

import math
import os
import struct
import sys

import bpy
import numpy as np

S = 0.05                       # metres per rink px
COLLECTION = "MW_Rink"

# --- physics (docs/re/puck.md) ---------------------------------------------------------
BOARD_X, BOARD_Y = 185, 372
CORNER_FAR, CORNER_FAR_FROM = 0x1C77E, 298     # x limits for |y| = 298..371 (y < 0)
CORNER_NEAR, CORNER_NEAR_FROM = 0x1C81E, 324   # x limits for y = 324..371
CORNER_SEGMENTS = 32

# --- ROM pictures the surfaces are mapped into ----------------------------------------
PICTURES = {"rink": 0x24CFC, "signs": 0x4A066, "fence": 0x3C264}

# --- board layout (rink px; plans/all/14-3d-rink-view.md, Board faces) ------------------
FAR_X = 104                    # the far end's straight boards end here
FAR_POST = 97.5                # its last bead post (map x 158.5 / 352.5)
FAR_PERIOD = 65                # the far face repeats every two 32.5 px bays (u 158..223)
THICK_END = FAR_POST + FAR_PERIOD   # thick-edged glass: two panels into each far curve
FAR_BASE_ROW = 89              # rows 88..40 above the base: pad 70-88, glass 40-69
PAD_TOP = 19                   # z of the padding's top (row 70); the glass sits on it
OUTER_ROWS = (844, 834)        # the boards' outer face: the dark grey wall under the near glass (rows 843..834)
OUTER_TILE = 191               # ... sampled where it runs straight: a post column, then cols 192..222 (it curves
                               # off at the corners, cols < 142; spectators' heads overlap it at 176..185, 229..236)
NEAR_DECO_X = 12               # ... except at the near centre (x -12..12), drawn as is: the dome on its bracket
# The near end as the rink picture draws it (seen from the original's angle): the boards' outer
# wall stands NEAR_T px outside the physics boundary (its bottom edge on rows 843 / y 383 along
# the straight, about as far out round the curves), NEAR_WALL px tall (rows 843..834 unstretched),
# and the glass stands on it. The padding stays on the boundary (one-sided: unseen from outside);
# between them a dark trough. Round each near curve the offset goes back to 0 between the end of
# the glass taper and the side boards.
NEAR_T, NEAR_WALL = 11, 10
TROUGH_TEXEL, TROUGH_Z = (200.5, 845.5), 0.1   # dark grey (colour 3, under the near wall), a hair above the floor
FAR_TOP = 49                   # z of the far glass top (row 40)
PANEL = 32                     # near-end glass panel width (posts at x 0, +-32, ...)
NEAR_TILE = 127                # u of a near glass post column (panels 127..159)
GLASS_FULL, GLASS_STEP_1, GLASS_STEP_2, GLASS_HALF = 25, 21, 16, 13
NEAR_FULL_TO, NEAR_STEP_1_TO, NEAR_STEP_2_TO, NEAR_GAP_TO = 128, 160, 192, 256   # arc px from the near centre
# The pens, centred on the centre line and on the 8 px grid (the picture draws their walls' bases
# about 4 px further south: kick strips at y -156, -35, 44 and 164, the bar at 3).
BENCH = (-160, 160)            # the two pens each side (the benches left, the referee's box right): y of their end walls
BENCH_GAP = (-40, 40)          # between the pens the box opens out to the picture's edge (y of those walls)
BENCH_BACK_X = -216            # the pens' back walls (left; the right side mirrors them)
BENCH_EDGE_X = -256            # the picture's left edge
BENCH_WALLS = [                # the left pens' walls (rink px)
    ((-BOARD_X, BENCH[0]), (BENCH_BACK_X, BENCH[0])), ((BENCH_BACK_X, BENCH[0]), (BENCH_BACK_X, BENCH_GAP[0])),
    ((BENCH_BACK_X, BENCH_GAP[0]), (BENCH_EDGE_X, BENCH_GAP[0])),
    ((BENCH_EDGE_X, BENCH_GAP[1]), (BENCH_BACK_X, BENCH_GAP[1])),
    ((BENCH_BACK_X, BENCH_GAP[1]), (BENCH_BACK_X, BENCH[1])), ((BENCH_BACK_X, BENCH[1]), (-BOARD_X, BENCH[1])),
]
BENCH_DIVIDER = ((-BOARD_X, 0), (BENCH_EDGE_X, 0))   # the low riveted bar between the pens (rows 448..463, no kick strip)
RIVET_ROWS = (464, 448)        # the riveted grey tile seen flat in the rink picture (rows 463..448, 32 px wide):
RIVET_SEAM = (29, 3)           # a panel (cols 0-28, the circle in its middle) then a 3 px seam (cols 29-31)
RIVET_TOP = 16
KICK_ROWS, KICK_U, KICK_TOP = 306, 48.5, 2   # the yellow kick strip at the bottom of the pens' walls (rows 305..304)
BENCH_FLOOR_TEXEL = (48.5, 321.5)   # a pen-floor texel (colour 31, black): the pens' floor is painted flat with it
SIGN_BANNERS = {"eat": (0, 101), "mutant": (101, 199), "toxicon": (199, 281)}   # picture_04a066 columns
SIGNS_UPPER = ("eat", "mutant")         # left side, bench -> far curve (reading order from the ice)
SIGNS_LOWER = ("mutant", "toxicon")     # left side, near curve -> bench: starts on the near curve to fit
SIGN_FILLER_U = 0.5            # a black sign-border column, for the space the banners leave
# The signs picture's glass: 3 px posts with pointed tips at cols 30, 62, 94, 126, then a 4 px one at 158,
# then 191, 223, 255, 287 (319/0 is the picture's seam), 29 px of glass between them. A run is the first
# post (cols 30-32) then panes, each 29 px of glass and the 3 px post after it, starting at these columns
# (cycled); the pane ending on the 4 px post is left out, so every post is a thin one.
SIGN_FIRST_POST = (30, 33)
SIGN_PANES = [33, 65, 97, 162, 194, 226, 258]
UPPER_SHORT_PANES = 2          # left side, upper: two short panes (as on the right side) after the thick glass
LOWER_GAP_PANES = 1            # left side, lower: one pane-wide gap without glass after the near taper
FENCE = [(-128, -32), (32, 128)]   # referee side, centred on the centre line
GATE = (-32, 32)
FENCE_TOP = 50                 # fence rows 50..1 (kick 49-50)
SIGNS_BASE_ROW, SIGNS_GLASS_ROW, SIGNS_TOP = 59, 40, 56   # rows 58..40 signs + base (z 0..19), 39..9 glass,
                                                          # 8..3 the posts' pointed tips (z 51..56)
NEAR_ICE_FROM = 331            # behind the near goal line the floor borrows the far end's ice
APRON_Z = 0.0                  # the surroundings (the picture outside the boards) lie level with the ice


# --- ROM helpers -----------------------------------------------------------------------
def u16(rom: bytes, a: int) -> int:
    return struct.unpack(">H", rom[a:a + 2])[0]


def picture_size(rom: bytes, a: int) -> tuple[int, int]:
    """Width and height in pixels from the picture header (`tiles.l, base.w, count.w, w.w, h.w`)."""
    return u16(rom, a + 8) * 8, u16(rom, a + 10) * 8


def corner_rows(rom: bytes, table: int, first: int) -> np.ndarray:
    """(X, Y) of the boundary per row, |y| = first..371, where the table is inside the boards."""
    pts = []
    for y in range(first, BOARD_Y):
        x = min(BOARD_X, u16(rom, table + 2 * (y - first + 1)))
        if x < BOARD_X:
            pts.append((x, y))
    return np.array(pts, float)


def fit_superellipse(pts: np.ndarray) -> tuple[float, int, int]:
    """|dx/a|^n + |dy/b|^n = 1 centred at (185 - a, 372 - b), least squares over the rows."""
    best = None
    bs = np.arange(30, 120)
    for n in np.arange(1.2, 3.001, 0.05):
        for a in range(40, 150):
            cx = BOARD_X - a
            cy = BOARD_Y - bs[None, :]
            dx = np.clip((pts[:, 0:1] - cx) / a, 0, None)
            dy = np.clip((pts[:, 1:2] - cy) / bs[None, :], 0, None)
            ok = ((pts[:, 0:1] > cx) & (pts[:, 1:2] > cy)).mean(axis=0) >= 0.9
            r = (dx ** n + dy ** n) ** (1 / n)
            rad = np.hypot(pts[:, 0:1] - cx, pts[:, 1:2] - cy)
            err = np.mean(((r - 1) * rad / np.maximum(r, 1e-6)) ** 2, axis=0)
            err[~ok] = np.inf
            i = int(np.argmin(err))
            if best is None or err[i] < best[0]:
                best = (float(err[i]), float(n), a, int(bs[i]))
    return best[1], best[2], best[3]


class Corner:
    def __init__(self, n: float, a: int, b: int):
        self.n, self.a, self.b = n, a, b
        self.cx, self.cy = BOARD_X - a, BOARD_Y - b

    def xlim(self, y: float) -> float:
        """The boards' x at |y| (185 above the corner)."""
        if y <= self.cy:
            return float(BOARD_X)
        t = min(1.0, (y - self.cy) / self.b)
        return self.cx + self.a * max(0.0, 1 - t ** self.n) ** (1 / self.n)

    def polyline(self) -> list[tuple[float, float]]:
        """From (185, cy) to (cx, 372), equal arc steps."""
        dense = []
        for i in range(2001):
            t = (math.pi / 2) * i / 2000
            c, s = math.cos(t), math.sin(t)
            dense.append((self.cx + self.a * c ** (2 / self.n), self.cy + self.b * s ** (2 / self.n)))
        acc = [0.0]
        for i in range(1, len(dense)):
            acc.append(acc[-1] + math.dist(dense[i - 1], dense[i]))
        out, j = [], 0
        for k in range(CORNER_SEGMENTS + 1):
            target = acc[-1] * k / CORNER_SEGMENTS
            while j < len(acc) - 2 and acc[j + 1] < target:
                j += 1
            u = (target - acc[j]) / max(acc[j + 1] - acc[j], 1e-9)
            p, q = dense[j], dense[j + 1]
            out.append((p[0] + (q[0] - p[0]) * u, p[1] + (q[1] - p[1]) * u))
        return out


# --- geometry buffers -------------------------------------------------------------------
class Mesh:
    def __init__(self, picture: tuple[int, int]):
        self.w, self.h = picture
        self.verts: list[tuple] = []
        self.uvs: list[tuple] = []
        self.faces: list[list[int]] = []

    def quad(self, pts: list[tuple[float, float, float]], uvs: list[tuple[float, float]]) -> None:
        """A quad: rink (x, y, z) px corners, UVs in the picture's pixels (v down)."""
        base = len(self.verts)
        for (x, y, z), (u, v) in zip(pts, uvs):
            self.verts.append((x * S, -y * S, z * S))
            self.uvs.append((u / self.w, 1.0 - v / self.h))
        self.faces.append([base, base + 1, base + 2, base + 3])

    def poly(self, pts: list[tuple[float, float]], uv) -> None:
        base = len(self.verts)
        for x, y in pts:
            self.verts.append((x * S, -y * S, 0.0))
            u, v = uv(x, y)
            self.uvs.append((u / self.w, 1.0 - v / self.h))
        self.faces.append(list(range(base, base + len(pts))))


class Rink:
    def __init__(self, rom: bytes):
        self.rom = rom
        self.pic = {k: picture_size(rom, a) for k, a in PICTURES.items()}
        self.far = Corner(*fit_superellipse(corner_rows(rom, CORNER_FAR, CORNER_FAR_FROM)))
        self.near = Corner(*fit_superellipse(corner_rows(rom, CORNER_NEAR, CORNER_NEAR_FROM)))
        self.loop = self._loop()
        self.cum = [0.0]
        for i in range(1, len(self.loop) + 1):
            self.cum.append(self.cum[-1] + math.dist(self.loop[i - 1], self.loop[i % len(self.loop)]))
        self.total = self.cum[-1]
        # the near curve meets the side boards this far round from the near end's centre
        self.near_end_e = self.total / 2 - self.s_of_y(self.near.cy)
        self.meshes = {
            "floor": Mesh(self.pic["rink"]), "wall": Mesh(self.pic["rink"]), "glass": Mesh(self.pic["rink"]),
            "near_wall": Mesh(self.pic["rink"]),
            "signs": Mesh(self.pic["signs"]), "signs_glass": Mesh(self.pic["signs"]), "fence": Mesh(self.pic["fence"]),
            "bench": Mesh(self.pic["rink"]), "bench_glass": Mesh(self.pic["rink"]),
        }

    # The boundary, clockwise in rink coordinates (x right, y south) from the far centre.
    def _loop(self) -> list[tuple[float, float]]:
        right = [(0.0, -BOARD_Y)]
        right += [(x, -y) for x, y in reversed(self.far.polyline())]
        right += self.near.polyline()
        right.append((0.0, BOARD_Y))
        return right + [(-x, y) for x, y in reversed(right[1:-1])]

    def at(self, s: float) -> tuple[float, float]:
        """The boundary point at arc length s (0 = far centre, clockwise)."""
        s = min(max(s, 0.0), self.total)
        pts = self.loop + [self.loop[0]]
        for i in range(len(pts) - 1):
            if self.cum[i] <= s <= self.cum[i + 1]:
                t = (s - self.cum[i]) / max(self.cum[i + 1] - self.cum[i], 1e-9)
                return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
        return pts[-1]

    def s_of_y(self, y: float) -> float:
        """Arc length of the right straight side's point at y."""
        i = next(i for i, p in enumerate(self.loop) if abs(p[0] - BOARD_X) < 1e-6 and abs(p[1] - self.far.cy * -1) < 1e-6)
        return self.cum[i] + (y + self.far.cy)

    # --- walls --------------------------------------------------------------------------
    def strip(self, mesh: str, s0: float, s1: float, z0: float, z1: float, vf, uf, tile=None,
              outer: bool = False, pos=None) -> None:
        """Wall between arc lengths s0..s1 and heights z0..z1; v = vf(z), u = uf(s) (linear).
        With [tile] = (base, period) u wraps into base..base+period (cut at the seams).
        Faces the rink (the loop runs clockwise, so a quad wound a0 b0 b1 a1 faces inwards);
        [outer] = the face looking out of the rink instead (the solid boards are one-sided).
        [pos] = where along s it stands (default: on the boundary)."""
        if s1 - s0 < 1e-6 or z1 - z0 < 1e-6:
            return
        pos = pos or self.at
        for c0, c1, u0, u1 in self.segments(s0, s1, uf, tile):
            (xa, ya), (xb, yb) = pos(c0), pos(c1)
            if outer:
                self.meshes[mesh].quad([(xb, yb, z0), (xa, ya, z0), (xa, ya, z1), (xb, yb, z1)],
                                       [(u1, vf(z0)), (u0, vf(z0)), (u0, vf(z1)), (u1, vf(z1))])
            else:
                self.meshes[mesh].quad([(xa, ya, z0), (xb, yb, z0), (xb, yb, z1), (xa, ya, z1)],
                                       [(u0, vf(z0)), (u1, vf(z0)), (u1, vf(z1)), (u0, vf(z1))])

    def segments(self, s0: float, s1: float, uf, tile=None) -> list:
        """Cuts of s0..s1 for a wall: the loop's vertices, every <= 6 px, the near offset's
        taper ends and [tile]'s seams; (c0, c1, u0, u1) each, u wrapped into the tile."""
        cuts = {s0, s1}
        for c in self.near_cuts():
            if s0 < c < s1:
                cuts.add(c)
        for c in self.cum:
            if s0 < c < s1:
                cuts.add(c)
        n = int((s1 - s0) // 6)
        for j in range(1, n + 1):
            cuts.add(s0 + (s1 - s0) * j / (n + 1))
        if tile:
            base, per = tile
            ua, ub = uf(s0), uf(s1)
            if abs(ub - ua) > 1e-9:
                lo, hi = sorted((ua, ub))
                m = math.floor((lo - base) / per) + 1
                while base + m * per < hi - 1e-6:
                    cuts.add(s0 + (s1 - s0) * (base + m * per - ua) / (ub - ua))
                    m += 1
        cuts = sorted(cuts)
        out = []
        for c0, c1 in zip(cuts[:-1], cuts[1:]):
            u0, u1 = uf(c0), uf(c1)
            if tile:
                base, per = tile
                um = (u0 + u1) / 2
                sh = base + ((um - base) % per) - um
                u0, u1 = u0 + sh, u1 + sh
            out.append((c0, c1, u0, u1))
        return out

    # --- the near end's outer wall, outside the boundary ---------------------------------
    def near_cuts(self) -> list:
        nc = self.total / 2
        return [nc - self.near_end_e, nc - NEAR_STEP_2_TO, nc + NEAR_STEP_2_TO, nc + self.near_end_e]

    def near_t(self, s: float) -> float:
        """How far outside the boundary the boards' outer wall stands at s (rink px)."""
        e = abs(s - self.total / 2)
        if e <= NEAR_STEP_2_TO:
            return float(NEAR_T)
        if e >= self.near_end_e:
            return 0.0
        return NEAR_T * (self.near_end_e - e) / (self.near_end_e - NEAR_STEP_2_TO)

    def out_at(self, s: float) -> tuple[float, float]:
        """The outer wall's foot at s: the boundary moved out along its normal by near_t(s)."""
        x, y = self.at(s)
        t = self.near_t(s)
        if t == 0:
            return x, y
        (x0, y0), (x1, y1) = self.at(s - 1), self.at(s + 1)
        n = math.hypot(x1 - x0, y1 - y0)
        return x + (y1 - y0) / n * t, y - (x1 - x0) / n * t

    def out_height(self, s: float) -> float:
        """The outer wall's height at s: NEAR_WALL out at the near end, PAD_TOP on the boundary."""
        return PAD_TOP - (PAD_TOP - NEAR_WALL) * self.near_t(s) / NEAR_T

    def outer(self, s0: float, s1: float, uf=None, tiled: bool = True) -> None:
        """The boards' outer face: the dark grey wall (rows 843..834, unstretched at the near end
        where it stands outside the boundary, stretched over the pad's height elsewhere);
        [uf] lines its posts up with the glass (default: posts every 32 px from s 0)."""
        if s1 - s0 < 1e-6:
            return
        uf = uf or (lambda s: OUTER_TILE + s)
        bottom, top = OUTER_ROWS
        for c0, c1, u0, u1 in self.segments(s0, s1, uf, (OUTER_TILE, PANEL) if tiled else None):
            (xa, ya), (xb, yb) = self.out_at(c0), self.out_at(c1)
            ha, hb = self.out_height(c0), self.out_height(c1)
            mesh = "near_wall" if self.near_t((c0 + c1) / 2) > 0 else "wall"   # drawn after the sprites
            self.meshes[mesh].quad([(xb, yb, 0), (xa, ya, 0), (xa, ya, ha), (xb, yb, hb)],
                                     [(u1, bottom), (u0, bottom), (u0, top), (u1, top)])

    def near_trough(self) -> None:
        """The floor between the near end's padding and its outer wall: dark."""
        nc = self.total / 2
        t = TROUGH_TEXEL
        for c0, c1, _, _ in self.segments(nc - self.near_end_e, nc + self.near_end_e, lambda s: 0.0):
            (xa, ya), (xb, yb) = self.at(c0), self.at(c1)
            (oa, pa), (ob, pb) = self.out_at(c0), self.out_at(c1)
            self.meshes["floor"].quad([(xa, ya, TROUGH_Z), (xb, yb, TROUGH_Z), (ob, pb, TROUGH_Z), (oa, pa, TROUGH_Z)],
                                      [t, t, t, t])

    def solid(self, mesh: str, s0: float, s1: float, vf, uf, tile=None, outer_uf=None) -> None:
        """The solid boards (z 0..PAD_TOP): [vf]/[uf] on the face towards the rink, the dark
        grey wall outside (one-sided faces)."""
        self.strip(mesh, s0, s1, 0, PAD_TOP, vf, uf, tile)
        self.outer(s0, s1, outer_uf)

    def free_wall(self, mesh: str, p0: tuple, p1: tuple, z0: float, z1: float, vf, uf, tile=None,
                  both: bool = True) -> None:
        """A wall off the boundary, p0 -> p1 (rink px); u = uf(distance from p0); both faces."""
        length = math.dist(p0, p1)
        cuts = {0.0, length}
        if tile:
            base, per = tile
            ua, ub = uf(0.0), uf(length)
            lo, hi = sorted((ua, ub))
            m = math.floor((lo - base) / per) + 1
            while base + m * per < hi - 1e-6:
                cuts.add((base + m * per - ua) / (ub - ua) * length)
                m += 1
        cuts = sorted(cuts)
        for c0, c1 in zip(cuts[:-1], cuts[1:]):
            u0, u1 = uf(c0), uf(c1)
            if tile:
                base, per = tile
                um = (u0 + u1) / 2
                sh = base + ((um - base) % per) - um
                u0, u1 = u0 + sh, u1 + sh
            a = (p0[0] + (p1[0] - p0[0]) * c0 / length, p0[1] + (p1[1] - p0[1]) * c0 / length)
            b = (p0[0] + (p1[0] - p0[0]) * c1 / length, p0[1] + (p1[1] - p0[1]) * c1 / length)
            self.meshes[mesh].quad([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)],
                                   [(u0, vf(z0)), (u1, vf(z0)), (u1, vf(z1)), (u0, vf(z1))])
            if both:
                self.meshes[mesh].quad([(b[0], b[1], z0), (a[0], a[1], z0), (a[0], a[1], z1), (b[0], b[1], z1)],
                                       [(u1, vf(z0)), (u0, vf(z0)), (u0, vf(z1)), (u1, vf(z1))])

    def benches(self, right: bool) -> None:
        """The two pens on a side (the benches left, the referee's box right, mirrored): walls
        with the yellow kick strip at the bottom, the riveted grey tile (the rink picture draws
        it flat on the bar between the benches) and near-end glass on top; on the left the low
        riveted bar between them (no kick strip in the picture). One face each: the bench
        materials are two-sided."""
        base = KICK_TOP + RIVET_TOP
        top = base + GLASS_STEP_1
        seam_u, seam_w = RIVET_SEAM

        def fit(p0, p1) -> float:
            """Whole panels with a seam at each end (and the glass's posts on the seams): the
            scale from wall length to texture columns."""
            length = math.dist(p0, p1)
            n = max(1, round((length - seam_w) / PANEL))
            return (n * PANEL + seam_w) / length

        walls = [((-a[0], a[1]), (-b[0], b[1])) for a, b in BENCH_WALLS] if right else BENCH_WALLS
        for p0, p1 in walls:
            k = fit(p0, p1)
            self.free_wall("bench", p0, p1, 0, KICK_TOP, lambda z: KICK_ROWS - z, lambda l: KICK_U, both=False)
            self.free_wall("bench", p0, p1, KICK_TOP, base, lambda z: RIVET_ROWS[0] - (z - KICK_TOP),
                           lambda l, k=k: seam_u + l * k, (0, PANEL), both=False)
            self.free_wall("bench_glass", p0, p1, base, top - 2, lambda z: 833 - (z - base),
                           lambda l, k=k: NEAR_TILE - 1 + l * k, (NEAR_TILE, PANEL), both=False)
            self.free_wall("bench_glass", p0, p1, top - 2, top, lambda z: 810 - (z - (top - 2)),
                           lambda l, k=k: NEAR_TILE - 1 + l * k, (NEAR_TILE, PANEL), both=False)
        if not right:
            k = fit(*BENCH_DIVIDER)
            self.free_wall("bench", BENCH_DIVIDER[0], BENCH_DIVIDER[1], 0, RIVET_TOP, lambda z: RIVET_ROWS[0] - z,
                           lambda l, k=k: seam_u + l * k, (0, PANEL), both=False)

    @staticmethod
    def banners_width(names) -> float:
        return sum(SIGN_BANNERS[n][1] - SIGN_BANNERS[n][0] for n in names)

    def sign_boards(self, s0: float, s1: float, names) -> None:
        """Boards with whole banners from picture_04a066 (in [names] order along s, centred, any
        space left a black border), the grey wall outside. The glass is sign_glass()."""
        vf = lambda z: SIGNS_BASE_ROW - z  # noqa: E731
        s = s0 + max(0.0, (s1 - s0) - self.banners_width(names)) / 2
        self.strip("signs", s0, s, 0, PAD_TOP, vf, lambda _: SIGN_FILLER_U)
        for n in names:
            u0, u1 = SIGN_BANNERS[n]
            e = min(s + (u1 - u0), s1)
            self.strip("signs", s, e, 0, PAD_TOP, vf, lambda t, a=s, u=u0: u + (t - a))
            s = e
        self.strip("signs", s, s1, 0, PAD_TOP, vf, lambda _: SIGN_FILLER_U)
        self.outer(s0, s1)

    def sign_glass(self, s0: float, s1: float) -> None:
        """The signs picture's glass on the boards between s0 and s1: whole panes only, thin
        posts only, a whole post (pole and pointed tip, nothing past it) at each end; stretched
        to fit."""
        vf = lambda z: SIGNS_BASE_ROW - z  # noqa: E731
        p0, p1 = SIGN_FIRST_POST
        n = max(1, round((s1 - s0 - (p1 - p0)) / PANEL))
        k = (n * PANEL + p1 - p0) / (s1 - s0)          # picture columns per rink px
        a = s0 + (p1 - p0) / k
        self.strip("signs_glass", s0, a, PAD_TOP, SIGNS_TOP, vf, lambda t: p0 + (t - s0) * k)
        for j in range(n):
            u = SIGN_PANES[j % len(SIGN_PANES)]
            b = s1 if j == n - 1 else a + PANEL / k
            self.strip("signs_glass", a, b, PAD_TOP, SIGNS_TOP, vf, lambda t, a=a, u=u: u + (t - a) * k)
            a = b

    def panels(self, s0: float, s1: float, glass: int, anchor: float, k: float) -> None:
        """Solid boards (padding inside, the grey wall outside) with near-end glass panels on
        top (posts every 32 px * k from anchor). The outer face's centre (x -NEAR_DECO_X..
        NEAR_DECO_X at the near end) shows the picture as drawn, its decoration included."""
        self.panel_boards(s0, s1, anchor, k)
        self.panel_glass(s0, s1, glass, anchor, k)

    def panel_boards(self, s0: float, s1: float, anchor: float, k: float) -> None:
        """The padding (posts every 32.5 px * k from anchor) and the outer face for panels()."""
        self.strip("wall", s0, s1, 0, PAD_TOP, lambda z: FAR_BASE_ROW - z,
                   lambda s: 158 + (s - anchor) * k * 32.5 / 32, (158, FAR_PERIOD))
        uf = lambda s: OUTER_TILE + (s - anchor) * k  # noqa: E731
        c0, c1 = self.total / 2 - NEAR_DECO_X, self.total / 2 + NEAR_DECO_X
        self.outer(s0, min(s1, c0), uf)
        self.outer(max(s0, c1), s1, uf)
        self.outer(max(s0, c0), min(s1, c1), lambda s: 256 + self.at(s)[0], tiled=False)

    def panel_glass(self, s0: float, s1: float, glass: int, anchor: float, k: float) -> None:
        """Near-end glass panels [glass] px tall (posts every 32 px * k from anchor): on the
        padding, or at the near end on the outer wall."""
        if glass > 0:
            base = self.out_height((s0 + s1) / 2)
            top = base + glass
            self.strip("glass", s0, s1, base, top - 2, lambda z: 833 - (z - base),
                       lambda s: NEAR_TILE + (s - anchor) * k, (NEAR_TILE, PANEL), pos=self.out_at)
            self.strip("glass", s0, s1, top - 2, top, lambda z: 810 - (z - (top - 2)),
                       lambda s: NEAR_TILE + (s - anchor) * k, (NEAR_TILE, PANEL), pos=self.out_at)

    def panel_run(self, s0: float, s1: float, glass: int, from_end: bool) -> None:
        n = max(1, round((s1 - s0) / PANEL))
        self.panels(s0, s1, glass, s1 if from_end else s0, n * PANEL / (s1 - s0))

    def fence_section(self, y0: float, y1: float) -> None:
        a, b = self.s_of_y(y0), self.s_of_y(y1)
        v = lambda z: FENCE_TOP + 1 - z  # noqa: E731
        self.strip("fence", a, a + 16, 0, FENCE_TOP, v, lambda s: s - a)                       # pillar
        self.strip("fence", a + 16, b - 16, 0, FENCE_TOP, v, lambda s: 16 + s - (a + 16), (16, 16))   # bays
        self.strip("fence", b - 16, b, 0, FENCE_TOP, v, lambda s: 128 + s - (b - 16))          # pillar

    def side(self, right: bool) -> None:
        S_ = (lambda d: d) if right else (lambda d: self.total - d)

        def span(d0, d1):
            a, b = S_(d0), S_(d1)
            return min(a, b), max(a, b)

        # far end: its own face, exact (oblique), pad then glass
        a, b = span(0, FAR_X)
        self.solid("wall", a, b, lambda z: FAR_BASE_ROW - z, lambda s: 256 + self.at(s)[0])
        self.strip("glass", a, b, PAD_TOP, FAR_TOP, lambda z: FAR_BASE_ROW - z, lambda s: 256 + self.at(s)[0])
        # thick glass two panels into the curve, continuing the far face
        a, b = span(FAR_X, THICK_END)
        if right:
            uf = lambda s: (256 + FAR_X) + (s - FAR_X)  # noqa: E731
        else:
            uf = lambda s: (256 - FAR_X) - ((self.total - FAR_X) - s)  # noqa: E731
        self.solid("wall", a, b, lambda z: FAR_BASE_ROW - z, uf, (158, FAR_PERIOD))
        self.strip("glass", a, b, PAD_TOP, FAR_TOP, lambda z: FAR_BASE_ROW - z, uf, (158, FAR_PERIOD))
        # the referee side: half-height panels, the fence and the gate; the bench side: signs,
        # low padded boards in front of the benches, signs
        box = (FENCE[0][0], FENCE[1][1]) if right else BENCH
        d0, d1 = self.s_of_y(box[0]), self.s_of_y(box[1])
        nc = self.total / 2
        e2d = lambda e: nc - e  # noqa: E731
        if right:
            a, b = span(THICK_END, d0)
            self.panel_run(a, b, GLASS_HALF, from_end=False)
            self.fence_section(*FENCE[0])
            g0, g1 = self.s_of_y(GATE[0]), self.s_of_y(GATE[1])
            self.strip("fence", g0, g1, 0, 4, lambda z: FENCE_TOP + 1 - z, lambda s: 8 + s - g0, (8, 16))
            self.fence_section(*FENCE[1])
            a, b = span(d1, e2d(NEAR_GAP_TO))
            self.panel_run(a, b, GLASS_HALF, from_end=True)
            self.benches(True)
            near = ((NEAR_STEP_2_TO, NEAR_GAP_TO, 0), (NEAR_STEP_1_TO, NEAR_STEP_2_TO, GLASS_STEP_2))
        else:
            # upper: banners from the thick glass to the bench; two short panes, then the signs' glass
            self.sign_boards(*span(THICK_END, d0), SIGNS_UPPER)
            short = THICK_END + UPPER_SHORT_PANES * PANEL
            a, b = span(THICK_END, short)
            self.panel_glass(a, b, GLASS_HALF, b, 1.0)
            self.sign_glass(*span(short, d0))
            a, b = span(d0, d1)
            self.solid("wall", a, b, lambda z: FAR_BASE_ROW - z, lambda s: 158 + s - a, (158, FAR_PERIOD))
            # lower: the banners run from the bench onto the near curve (under the end of the
            # taper's second step); the signs' glass stops a gap short of that step
            d2 = d1 + self.banners_width(SIGNS_LOWER)
            self.sign_boards(*span(d1, d2), SIGNS_LOWER)
            self.sign_glass(*span(d1, e2d(NEAR_STEP_2_TO + LOWER_GAP_PANES * PANEL)))
            self.benches(False)
            a, b = span(e2d(NEAR_STEP_2_TO), e2d(NEAR_STEP_1_TO))
            self.panel_glass(a, b, GLASS_STEP_2, nc, 1.0)
            self.panel_boards(*span(d2, e2d(NEAR_STEP_1_TO)), nc, 1.0)
            near = ()
        # near curve: (the right side: two gaps, the second taper step,) the first step, full
        # panels to the centre
        for e0, e1, g in near + ((NEAR_FULL_TO, NEAR_STEP_1_TO, GLASS_STEP_1), (0, NEAR_FULL_TO, GLASS_FULL)):
            a, b = span(e2d(e1), e2d(e0))
            self.panels(a, b, g, nc, 1.0)

    # --- floor --------------------------------------------------------------------------
    def floor(self) -> None:
        m = self.meshes["floor"]
        oblique = lambda x, y: (x + 256, y + 461)  # noqa: E731
        xc = self.near.xlim(NEAR_ICE_FROM)
        i = max(i for i, p in enumerate(self.loop) if p[0] > 0 and p[1] < NEAR_ICE_FROM)
        upper = [p for p in self.loop[:i + 1] if p[1] < NEAR_ICE_FROM] + [(xc, NEAR_ICE_FROM), (-xc, NEAR_ICE_FROM)] \
            + [p for p in self.loop[i + 1:] if p[1] < NEAR_ICE_FROM]
        m.poly(list(reversed(upper)), oblique)
        # behind the near goal line: the far end's ice, mirrored, rows scaled so the corner edges meet
        cols = 40
        for r in range(int(BOARD_Y - NEAR_ICE_FROM)):
            ya, yb = NEAR_ICE_FROM + r, NEAR_ICE_FROM + r + 1
            xa, xb = self.near.xlim(ya), self.near.xlim(yb)
            for j in range(cols):
                t0, t1 = -1 + 2 * j / cols, -1 + 2 * (j + 1) / cols
                pts = [(t1 * xa, ya), (t0 * xa, ya), (t0 * xb, yb), (t1 * xb, yb)]
                uvs = [(x * self.far.xlim(y) / self.near.xlim(y) + 256, -y + 461) for x, y in pts]
                m.quad([(x, y, 0.0) for x, y in pts], uvs)
        self.apron(oblique)

    def apron(self, oblique) -> None:
        """The surroundings: the rest of the picture, outside the boards only (bands between the
        ice's edge vertices, so nothing lies under the ice to show through it), the pens' floor
        (both sides) painted flat black."""
        m = self.meshes["floor"]
        w, h = self.pic["rink"]
        x0, x1, y0, y1 = -256, w - 256, -461, h - 461
        black = BENCH_FLOOR_TEXEL

        def band(ya, yb, la, lb, ra, rb, uv=None):
            """x from la..ra at ya to lb..rb at yb."""
            if yb - ya < 1e-9:
                return
            pts = [(lb, yb, APRON_Z), (rb, yb, APRON_Z), (ra, ya, APRON_Z), (la, ya, APRON_Z)]
            m.quad(pts, [uv or oblique(x, y) for x, y, _ in pts])

        band(y0, -BOARD_Y, x0, x0, x1, x1)
        band(BOARD_Y, y1, x0, x0, x1, x1)
        # the right half of the ice's edge, top to bottom, as the ice polygons have it
        half = self.loop[:self.loop.index((0.0, BOARD_Y)) + 1]
        edge = [p for p in half if p[1] < NEAR_ICE_FROM] + \
            [(self.near.xlim(y), float(y)) for y in range(NEAR_ICE_FROM, BOARD_Y + 1)]
        cuts = sorted({BENCH[0], BENCH[1], BENCH_GAP[0], BENCH_GAP[1]})
        for (xa, ya), (xb, yb) in zip(edge, edge[1:]):
            if yb - ya < 1e-9:
                continue
            ys = [ya] + [c for c in cuts if ya < c < yb] + [yb]
            for ta, tb in zip(ys, ys[1:]):
                ea = xa + (xb - xa) * (ta - ya) / (yb - ya)
                eb = xa + (xb - xa) * (tb - ya) / (yb - ya)
                bk = -BENCH_BACK_X
                if BENCH_GAP[0] <= ta and tb <= BENCH_GAP[1]:
                    band(ta, tb, ea, eb, x1, x1, black)
                    band(ta, tb, x0, x0, -ea, -eb, black)
                elif BENCH[0] <= ta and tb <= BENCH[1]:
                    band(ta, tb, ea, eb, bk, bk, black)
                    band(ta, tb, bk, bk, x1, x1)
                    band(ta, tb, x0, x0, -bk, -bk)
                    band(ta, tb, -bk, -bk, -ea, -eb, black)
                else:
                    band(ta, tb, ea, eb, x1, x1)
                    band(ta, tb, x0, x0, -ea, -eb)

    def build(self) -> None:
        self.floor()
        self.near_trough()
        self.side(True)
        self.side(False)


# --- Blender objects ----------------------------------------------------------------------
PREVIEWS = {"floor": "rink_floor.png", "wall": "rink_boards.png", "near_wall": "rink_boards.png", "glass": "rink_boards.png",
            "signs": "signs.png", "signs_glass": "signs.png", "fence": "fence.png",
            "bench": "rink_boards.png", "bench_glass": "rink_boards.png"}
# as the game's shaders: the boards' faces are one-sided (the padding faces the rink, the grey
# wall the other way, back to back), the glass is translucent (blended), the rest cut out
ONE_SIDED = {"wall", "near_wall", "signs"}
BLENDED = {"glass", "signs_glass", "bench_glass"}


def material(name: str, preview: str | None, one_sided: bool = False, blended: bool = False) -> bpy.types.Material:
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    if preview and os.path.exists(preview):
        img = bpy.data.images.load(preview, check_existing=True)
        img.reload()
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.interpolation = "Closest"
        tex.extension = "REPEAT"
        em = nt.nodes.new("ShaderNodeEmission")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(tex.outputs["Color"], em.inputs["Color"])
        nt.links.new(tex.outputs["Alpha"], mix.inputs[0])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    else:
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (0.5, 0.5, 0.6, 1)
        nt.links.new(em.outputs[0], out.inputs["Surface"])
    mat.use_backface_culling = one_sided    # glTF doubleSided = not one_sided
    try:
        mat.surface_render_method = "BLENDED" if blended else "DITHERED"
    except (AttributeError, TypeError):
        pass
    return mat


def to_blender(rink: Rink, previews: str | None) -> bpy.types.Collection:
    col = bpy.data.collections.get(COLLECTION)
    if col is None:
        col = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(col)
    for o in list(col.objects):
        if o.type == "MESH":
            me = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if me.users == 0:
                bpy.data.meshes.remove(me)
    for name, m in rink.meshes.items():
        me = bpy.data.meshes.new(name)
        me.from_pydata(m.verts, [], m.faces)
        me.update()
        uv = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            poly.use_smooth = name != "floor"
            for li, vi in zip(poly.loop_indices, poly.vertices):
                uv.data[li].uv = m.uvs[vi]
        pv = os.path.join(previews, PREVIEWS[name]) if previews else None
        me.materials.append(material("mw_" + name, pv, name in ONE_SIDED, name in BLENDED))
        ob = bpy.data.objects.new(name, me)
        col.objects.link(ob)
    return col


def main(argv: list[str]) -> Rink:
    import argparse
    here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else None
    root = os.path.abspath(os.path.join(here, "..", "..")) if here else os.getcwd()
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", default=os.path.join(root, "game", "rom", "mlh.gen"))
    ap.add_argument("--previews", default=os.path.join(root, "out", "plan3d", "preview"))
    a = ap.parse_args(argv)
    with open(a.rom, "rb") as f:
        rom = f.read()
    rink = Rink(rom)
    rink.build()
    to_blender(rink, a.previews)
    print("rink built: far corner n %.2f a %d b %d, near corner n %.2f a %d b %d" % (
        rink.far.n, rink.far.a, rink.far.b, rink.near.n, rink.near.a, rink.near.b))
    print("faces: " + ", ".join("%s %d" % (k, len(m.faces)) for k, m in rink.meshes.items()))
    return rink


if __name__ == "__main__":
    args = globals().get("MW_ARGS")
    if args is None:
        args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    main(args)
