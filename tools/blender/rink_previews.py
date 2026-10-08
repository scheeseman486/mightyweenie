"""Preview textures for looking at the 3D rink in Blender (plan 14).

Run with the repo's Python (it uses the harness's decoders):

    tools/bin/py tools/blender/rink_previews.py [--stadium N] [--team-a N] [--out DIR]

Writes RGBA PNGs of the three pictures the rink model is textured from, with
the same colour rules as the game's material (game/src/rink3d/rink3d_picture.gdshader):

* ``rink_floor.png``   the rink picture ``$24CFC``, opaque; colour 0 = the ice colour
* ``rink_boards.png``  the same picture for the boards: colour 0 transparent,
  the glass rows translucent
* ``signs.png``        ``picture_04a066`` (the boards with signs), glass rows translucent
* ``fence.png``        ``picture_03c264`` (the referee side's fence), colour 0 transparent

They go to ``out/plan3d/preview/`` (gitignored): they are ROM-derived and only
for previews. The ``.blend`` references them by relative path and never packs
them; the game decodes the pictures itself.
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "harness"))

from mw_harness import palettes  # noqa: E402
from mw_harness.gfx import color_rgb8  # noqa: E402

RINK_PICTURE = 0x24CFC
SIGNS_PICTURE = 0x4A066
FENCE_PICTURE = 0x3C264
RINK_SCREEN = 4

# Translucent glass: colour index (line 0) -> alpha; colours 0 and 5 take
# colour 5's tint. Same table as the game's material.
GLASS_ALPHA = {0: 0.12, 4: 0.5, 5: 0.22, 6: 0.32}
GLASS_ROWS = {RINK_PICTURE: [(40, 70), (808, 833)], SIGNS_PICTURE: [(9, 40)], FENCE_PICTURE: []}
# Rows where colour 3 is see-through too: the signs picture's backdrop above the
# glass, around the posts' pointed tips.
CLEAR_ROWS = {SIGNS_PICTURE: (0, 9)}
# Rows where the glass posts stay solid, and the row their columns are found on:
# edge (colour 10), a 1-2 px middle in glass colours, edge.
POST_ROWS = {RINK_PICTURE: (808, 834, 820), SIGNS_PICTURE: (9, 40, 20)}
POST_EDGE = 10


def post_columns(w: int, idx: bytearray, ref_row: int) -> set[int]:
    cols, last = set(), -100
    for c in range(w):
        if idx[ref_row * w + c] == POST_EDGE:
            cols.add(c)
            if 2 <= c - last <= 3:
                cols.update(range(last + 1, c))
            last = c
    return cols


def picture_indices(rom: bytes, a: int) -> tuple[int, int, bytearray]:
    """The picture's map as line * 16 + colour indices (0 where nothing is drawn)."""
    tiles, base, count, w, h = struct.unpack(">IHHHH", rom[a:a + 12])
    img = bytearray(w * 8 * h * 8)
    stride = w * 8
    for i in range(w * h):
        word = struct.unpack(">H", rom[a + 12 + 2 * i:a + 14 + 2 * i])[0]
        t = (word & 0x7FF) - base
        if t < 0 or t >= count:
            continue
        line = (word >> 13) & 3
        hf, vf = word & 0x800, word & 0x1000
        tb = rom[tiles + 32 * t:tiles + 32 * t + 32]
        cx, cy = (i % w) * 8, (i // w) * 8
        for py in range(8):
            for px in range(8):
                b = tb[py * 4 + px // 2]
                c = (b >> 4) if px % 2 == 0 else b & 15
                if c == 0:
                    continue
                x = 7 - px if hf else px
                y = 7 - py if vf else py
                img[(cy + y) * stride + cx + x] = line * 16 + c
    return w * 8, h * 8, img


def render(rom: bytes, a: int, pal: list[int], floor: bool) -> Image.Image:
    w, h, idx = picture_indices(rom, a)
    rgb = [color_rgb8(c) for c in pal]
    out = Image.new("RGBA", (w, h))
    px = out.load()
    rows = GLASS_ROWS[a]
    c0, c1 = CLEAR_ROWS.get(a, (0, 0))
    p0, p1, pref = POST_ROWS.get(a, (0, 0, 0))
    posts = post_columns(w, idx, pref) if a in POST_ROWS else set()
    for y in range(h):
        glass = not floor and any(r0 <= y < r1 for r0, r1 in rows)
        clear = not floor and c0 <= y < c1
        for x in range(w):
            i = idx[y * w + x]
            if glass and i in GLASS_ALPHA and not (p0 <= y < p1 and x in posts):
                c = rgb[5] if i in (0, 5) else rgb[i]
                px[x, y] = (*c, int(255 * GLASS_ALPHA[i]))
            elif i % 16 == 0 or (clear and i == 3):
                px[x, y] = (*rgb[0], 255) if floor else (0, 0, 0, 0)
            else:
                px[x, y] = (*rgb[i], 255)
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rom", default=str(ROOT / "game/rom/mlh.gen"))
    ap.add_argument("--stadium", type=int, default=0)
    ap.add_argument("--team-a", type=int, default=0)
    ap.add_argument("--out", default=str(ROOT / "out/plan3d/preview"))
    a = ap.parse_args()
    rom = Path(a.rom).read_bytes()
    pal = palettes.screen_palette(rom, RINK_SCREEN, a.team_a, a.stadium)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    render(rom, RINK_PICTURE, pal, True).save(out / "rink_floor.png")
    render(rom, RINK_PICTURE, pal, False).save(out / "rink_boards.png")
    render(rom, SIGNS_PICTURE, pal, False).save(out / "signs.png")
    render(rom, FENCE_PICTURE, pal, False).save(out / "fence.png")
    print(f"previews in {out}")


if __name__ == "__main__":
    main()
