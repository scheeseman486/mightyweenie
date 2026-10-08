"""Compare our frames (game/test/screens/visual_check.gd) with the original's (mw_harness.visual_rec) at
Genesis colour levels (plan 11 item 6; the plan 06/07 method: both sides reduced to the
VDP's levels, half steps kept for shadow/highlight).

Per pass of a visit: the original's frame that shows it (visual_check's "shows": the frame
after the VBlank that sends the pass's sprite list) and its neighbours (planes written
directly show a frame earlier than the sprites, the next pass's writes can show early);
the number of differing pixels at the expected frame and the best neighbour; frames of
the original's palette fades (CRAM not settled) are skipped. Writes OUT/cmp.json and,
with --sheet PASS[,PASS..] or --worst N, side-by-side sheets OUT/sheet_PASS.png (ours |
original | differences in red), and prints a summary.

usage: tools/bin/py -m mw_harness.visual_cmp REC_DIR OUT_DIR [--sheet 3,40] [--worst 3] [--rows]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def levels_gpgx(img: np.ndarray) -> np.ndarray:
    """GPGX's RGB565-expanded output -> half levels 0..14 (R/B 0..232, G 0..236)."""
    f = img.astype(np.float32)
    out = np.empty_like(f)
    out[..., 0] = np.rint(f[..., 0] * 14 / 232)
    out[..., 1] = np.rint(f[..., 1] * 14 / 236)
    out[..., 2] = np.rint(f[..., 2] * 14 / 232)
    return out.astype(np.int16)


def levels_ours(img: np.ndarray) -> np.ndarray:
    """Ours: a 3-bit level n is round(255 n / 7) -> half levels 0..14."""
    return np.rint(img.astype(np.float32) * 14 / 255).astype(np.int16)


def diff_mask(ours: np.ndarray, theirs: np.ndarray) -> np.ndarray:
    return (levels_ours(ours) != levels_gpgx(theirs)).any(axis=2)


def row_map(mask: np.ndarray) -> str:
    return "".join("#" if mask[y * 8:y * 8 + 8].any() else "." for y in range(28))


def settled(frames_meta: list, k: int, span: int = 4) -> bool:
    """The palette is not fading at record k (CRAM equal span records before and after)."""
    c = frames_meta[k][6]
    lo, hi = max(k - span, 0), min(k + span, len(frames_meta) - 1)
    return frames_meta[lo][6] == c and frames_meta[hi][6] == c


def sheet(ours: np.ndarray, theirs: np.ndarray, mask: np.ndarray, path: Path) -> None:
    d = theirs.copy()
    d[...] = (d * 0.35).astype(np.uint8)
    d[mask] = (255, 0, 0)
    gap = np.full((224, 4, 3), 255, np.uint8)
    Image.fromarray(np.hstack([ours, gap, theirs, gap, d])).resize((2 * 968, 2 * 224), Image.NEAREST).save(path)


def main() -> None:
    args = sys.argv[1:]
    rec, out = Path(args[0]), Path(args[1])
    sheets = set()
    worst = 0
    if "--sheet" in args:
        sheets = {int(x) for x in args[args.index("--sheet") + 1].split(",")}
    if "--worst" in args:
        worst = int(args[args.index("--worst") + 1])
    meta = json.loads((rec / "meta.json").read_text())
    fm = meta["frames"]
    gp = np.load(rec / "frames.npz")["frames"]
    passes = json.loads((out / "passes.json").read_text())["passes"]
    n = len(fm)
    results = []
    for i, p in enumerate(passes):
        png = out / f"p{i:04d}.png"
        # a recording cut while the screen still ran (a branch restored): the last pass, which
        # did not leave, has no frame showing it
        if not png.exists() or (i > 0 and i == len(passes) - 1 and p["next"] < 0 and p["to"] < 0):
            continue
        want = min(max(p["shows"], 0), n - 1)
        ours = np.asarray(Image.open(png).convert("RGB"))
        lo, hi = p.get("window", [want, want])
        cands = sorted({min(max(k, 0), n - 1) for k in range(min(lo, want - 1), max(hi, want) + 2)})
        masks = {k: diff_mask(ours, gp[k]) for k in cands}
        diffs = {k: int(m.sum()) for k, m in masks.items()}
        best = min(diffs, key=lambda k: (diffs[k], abs(k - want)))
        # mixed: a pixel differs only if it differs in every frame of the pass's window
        # (the original's planes run a pass ahead of its sprites)
        win = [k for k in cands if lo <= k <= max(hi, lo)] or [want]
        mixed = np.logical_and.reduce([masks[k] for k in win])
        r = {"pass": i, "frame": want, "diff": diffs[want], "best": best, "best_diff": diffs[best],
             "mixed": int(mixed.sum()), "window": [win[0], win[-1]],
             "fade": not settled(fm, want), "sim_diffs": p["ndiff"], "exact": p["exact"]}
        results.append(r)
        if i in sheets:
            m = diff_mask(ours, gp[want])
            sheet(ours, gp[want], m, out / f"sheet_{i:04d}.png")
    (out / "cmp.json").write_text(json.dumps(results))
    ok = [r for r in results if not r["fade"]]
    zero = [r for r in ok if r["diff"] == 0]
    zb = [r for r in ok if r["best_diff"] == 0]
    zm = [r for r in ok if r["best_diff"] == 0 or r["mixed"] == 0]
    print(f"{rec.parent.name}/{rec.name}: {len(results)} passes, {len(ok)} outside fades: {len(zero)} identical at the expected"
          f" frame, {len(zb)} at a frame of its window, {len(zm)} pixel by pixel over the window;"
          f" sim differences in {sum(1 for r in ok if r['sim_diffs'])}")
    if worst:
        for r in sorted(ok, key=lambda r: (-min(r["best_diff"], r["mixed"]), -r["best_diff"]))[:worst]:
            m = diff_mask(np.asarray(Image.open(out / f"p{r['pass']:04d}.png").convert("RGB")), gp[r["best"]])
            print(f"  pass {r['pass']:4d} frame {r['best']:4d}: {r['best_diff']:6d} px (mixed {r['mixed']}) rows {row_map(m)}")
            sheet(np.asarray(Image.open(out / f"p{r['pass']:04d}.png").convert("RGB")), gp[r["best"]], m,
                  out / f"sheet_{r['pass']:04d}.png")
    if "--rows" in args:
        last = None
        for r in ok:
            m = diff_mask(np.asarray(Image.open(out / f"p{r['pass']:04d}.png").convert("RGB")), gp[r["best"]])
            key = (r["best_diff"] > 0, row_map(m))
            if key != last:
                print(f"  pass {r['pass']:4d} frame {r['best']:4d} (want {r['frame']}): {r['best_diff']:6d} px rows {row_map(m)}")
            last = key


if __name__ == "__main__":
    main()
