"""Asset discovery: trace what the original loads on each screen and build the
ROM catalogue (game/data/rom_catalogue.json, docs/re/graphics.md).

The ROM has no file-like containers; graphics are raw blocks that code points
at. :func:`trace` plays an input script on the original (live BlastEm) with
breakpoints on the loaders and records each call's arguments per screen;
:func:`catalogue` turns traces into entries (addresses, sizes, parameters -
no ROM content).
"""
from __future__ import annotations

import json
import re
import struct
import tempfile
from dataclasses import dataclass
from pathlib import Path

from .blastem_live import LiveBlastEm
from .gfx import Animation, Picture, Piece, frame_pieces
from .record import PLAYER_STATS, PLAYER_STATS_RETURN, SAFETY_TICKS, SCREEN_CALL, VBLANK
from .rom import Rom, default_rom_path
from .script import PAD_BITS, PLAYERS, Script, ScriptPlayer

#: Loader entry points (docs/re/graphics.md)
LOADERS = {
    0x14806: "dma_vram",       # DMA queue: A0 source, D0 bytes, D1 VRAM address
    0x147F8: "dma_vram_ram",   # same, source in RAM
    0x147EC: "dma_cram",
    0x147DE: "dma_vsram",
    0x1449C: "map_copy",       # A0 source, D0 row bytes, D1 VRAM, D2 dest stride, D3 src stride, D4 rows
    0x14B30: "map_fill",       # D3 value, D0 row bytes, D1 VRAM, D2 stride, D4 rows
    0x1498C: "palette_line",   # A0 16 colours, D2 palette line
    0x14388: "anim_set",       # A0 animation, A5 object
    0x1593E: "picture_load",   # A5 picture
}
CALLERS = {0x151DC: "sprite_cache", 0x15952: "picture", 0x144CE: "map_rows", 0x14EEE: "map_rows",
           0x157C8: "sprite_table"}
ROM_END = 0x200000
#: bump when trace() records something new (invalidates out/assets/ caches)
ASSETS_VERSION = 5
#: draw_frame: A5 = frame (pieces.w + 6-byte pieces), D0/D1 position, D2 depth, D3 flips
FRAME_DRAW = 0xA07E
#: add_sprite_piece: A5 = piece, D0/D1 position, D2 depth, D3 flips; draw_frame
#: calls it in a loop (returning to FRAME_PIECE_RETURN)
PIECE_DRAW = 0x156C6
#: draw_text: A0 = zero-terminated string, A5 = font, D1/D2 position (plane cells)
TEXT_PLANE = 0x14CAE
#: draw_text_sprites: A0 = string, A5 = font, A1 = camera
TEXT_SPRITES = 0xF3CC
FRAME_PIECE_RETURN = 0xA0EC


_POKE = re.compile(r"^#poke\s+@screen\s+(\d+)(?:\s+#(\d+))?\s+\+(\d+)\s+\$?([0-9a-fA-F]+)\.([bwl])\s*=\s*(\S+)")


@dataclass(frozen=True)
class Poke:
    """``#poke @screen S [#k] +T ADDR.size=VALUE`` in a tour script: a RAM
    write the tracer makes at that moment to reach a rare state quickly (e.g.
    forcing the goal phase). Script players treat the line as a comment."""
    screen: int
    visit: int
    offset: int
    address: int
    size: str
    value: int


def parse_pokes(text: str) -> list[Poke]:
    out = []
    for line in text.splitlines():
        m = _POKE.match(line.strip())
        if m:
            v = m.group(6)
            out.append(Poke(int(m.group(1)), int(m.group(2) or 1), int(m.group(3)), int(m.group(4), 16),
                            m.group(5), int(v[1:], 16) if v.startswith("$") else int(v, 0)))
    return out


def trace(script: Script, rom: Path | None = None, max_ticks: int | None = None,
          pokes: list[Poke] | None = None) -> list[dict]:
    """Play ``script`` on the original and log every loader call:
    ``{screen, tick, kind, a0, a5, d0-d4, caller}`` (raw arguments)."""
    rom = Path(rom) if rom else default_rom_path()
    player = ScriptPlayer(script)
    pending = list(pokes or [])
    bound = [0] * (PLAYERS + 1)
    events: list[dict] = []
    screen, tick = -1, 0

    def names(m: int) -> list[str]:
        return [n for n, b in PAD_BITS.items() if m & b]

    with LiveBlastEm(rom) as bl:
        # sprite frames drawn: logged inside BlastEm (no stop per object)
        bl.log_at(FRAME_DRAW, "frames", "a5", "[0xffb05e].w")
        # text: strings drawn into a plane (glyph tiles written at once by
        # $150C6/$148B0, cells by $14656) and strings drawn as sprites
        bl.log_at(TEXT_PLANE, "text_plane", "a5", "a0", "[0xffb05e].w")
        bl.log_at(TEXT_SPRITES, "text_sprites", "a5", "a0", "[0xffb05e].w")
        # single pieces drawn directly (not from a frame): logos, glyphs...
        bl.log_at(PIECE_DRAW, "pieces", "a5", "[a7].l", "[0xffb05e].w",
                  condition=f"[a7].l != 0x{FRAME_PIECE_RETURN:x}")
        for a in (VBLANK, SCREEN_CALL, PLAYER_STATS, PLAYER_STATS_RETURN, *LOADERS):
            bl.breakpoint(a)
        outer = -1
        while True:
            a = bl.cont()
            if a == VBLANK:
                tick = bl.read("[0xffca56].l")[0] + 1
                player.tick_start(tick)
                if player.ended or (max_ticks is not None and tick >= max_ticks):
                    break
                if max_ticks is None and tick >= SAFETY_TICKS:
                    raise RuntimeError(f"{script.name}: no END by tick {tick}")
                for pk in [p for p in pending if (p.screen, p.visit) in player.entries
                           and tick >= player.entries[(p.screen, p.visit)] + p.offset]:
                    bl.write(pk.address, pk.value, pk.size)
                    pending.remove(pk)
            elif a == SCREEN_CALL:
                screen, tick = bl.read("[0xffb05e].w", "[0xffca56].l")
                player.screen_entered(screen, tick)
            elif a == PLAYER_STATS:          # screen 9 runs inside screen 8
                outer, screen = screen, 9
                player.screen_entered(9, bl.read("[0xffca56].l")[0])
            elif a == PLAYER_STATS_RETURN:
                if screen == 9:
                    screen = outer
                    player.resume(outer, player.visits.get(outer, 1))
            else:
                a0, a5, d0, d1, d2, d3, d4, ret = bl.read("a0", "a5", "d0", "d1", "d2", "d3", "d4", "[a7].l")
                events.append({"screen": screen, "tick": tick, "kind": LOADERS[a], "a0": a0, "a5": a5,
                               "d0": d0 & 0xFFFF, "d1": d1 & 0xFFFF, "d2": d2 & 0xFFFF, "d3": d3 & 0xFFFF,
                               "d4": d4 & 0xFFFF, "caller": ret})
            for p in range(1, PLAYERS + 1):
                w = player.held(p)
                if w != bound[p]:
                    bl.press(p, *names(w & ~bound[p]))
                    bl.release(p, *names(bound[p] & ~w))
                    bound[p] = w
        with tempfile.TemporaryDirectory(prefix="mw-assets-") as tmp:
            logged = bl.array("frames", Path(tmp) / "frames.bin")
            singles = bl.array("pieces", Path(tmp) / "pieces.bin")
            texts = [("text_plane", bl.array("text_plane", Path(tmp) / "tp.bin")),
                     ("text_sprites", bl.array("text_sprites", Path(tmp) / "ts.bin"))]
    # distinct (screen, address) pairs; the screen ID is $FFB05E (9 shows as 8)
    seen = set()
    for a5, scr in zip(logged[0::2], logged[1::2]):
        if (scr, a5) not in seen:
            seen.add((scr, a5))
            events.append({"screen": scr, "tick": -1, "kind": "frame_draw", "a0": 0, "a5": a5,
                           "d0": 0, "d1": 0, "d2": 0, "d3": 0, "d4": 0, "caller": FRAME_DRAW})
    for kind, logged_text in texts:
        for font, string, scr in zip(logged_text[0::3], logged_text[1::3], logged_text[2::3]):
            if (kind, scr, font, string) not in seen:
                seen.add((kind, scr, font, string))
                events.append({"screen": scr, "tick": -1, "kind": kind, "a0": string, "a5": font,
                               "d0": 0, "d1": 0, "d2": 0, "d3": 0, "d4": 0, "caller": 0})
    for a5, ret, scr in zip(singles[0::3], singles[1::3], singles[2::3]):
        if (scr, a5, ret) not in seen:
            seen.add((scr, a5, ret))
            events.append({"screen": scr, "tick": -1, "kind": "piece_draw", "a0": 0, "a5": a5,
                           "d0": 0, "d1": 0, "d2": 0, "d3": 0, "d4": 0, "caller": ret})
    return events


def _entry(entries: dict, key: str, base: dict, screen: int) -> dict:
    e = entries.setdefault(key, dict(base, screens=[]))
    if screen not in e["screens"]:
        e["screens"].append(screen)
        e["screens"].sort()
    return e


#: map_copy calls from the plane routine $14E0C (draw a rectangle of a map
#: into a scrolling, wrapping plane; the rink streams rows through it)
STREAM_CALLERS = {0x14EEE}
#: the map copier's own per-row DMA (already logged as map_copy)
MAP_COPY_ROW_DMA = 0x144CE
#: callers of the palette loader that build palettes on the stack
#: (docs/re/graphics.md, Palettes): caller -> builder routine
PALETTE_BUILDERS = {0x222A: "screen_palette", 0x2238: "screen_palette", 0x2246: "screen_palette",
                    0x2254: "screen_palette", 0x2356: "team_line", 0x238C: "ice_line",
                    0x23AE: "menu_line", 0x2412: "panel_line"}
NAME_TABLES = 0xC000          # VRAM at and above this holds name tables / sprite table


def _plausible(p: Picture, size: int) -> bool:
    """Descriptors with a map have sane dimensions after the tile header;
    tile-only descriptors (e.g. the fight's $2155A) have map words there."""
    return 1 <= p.width <= 128 and 1 <= p.height <= 256 and p.map_address + 2 * p.width * p.height <= size


def catalogue(traces: list[list[dict]], rom_bytes: bytes) -> dict:
    """Merge traces into catalogue entries (addresses, sizes, parameters).

    * ``picture`` - a tile bank descriptor read by ``$1593E`` (tiles, VRAM
      base, count) with a name-table map after it (width, height); maps are
      drawn by copying rectangles of it (``placements``) or through the
      wrapping plane routine ``$14E0C`` (``plane``: the screens that do; the
      rink streams rows through it as it scrolls).
    * ``tilebank`` - a descriptor without a map.
    * ``map`` - a rectangle of name-table words in ROM outside any picture.
    * ``tiles`` - tiles DMA'd from ROM outside pictures and sprites.
    * ``palette`` - 16 colours loaded from ROM as they are.
    * ``anim`` - an animation record (frames of sprite pieces; piece tiles are
      streamed from ROM by the sprite cache).
    ``palette_builders`` lists which screens compose palettes on the stack.
    """
    size = len(rom_bytes)
    entries: dict[str, dict] = {}
    pictures: dict[int, Picture] = {}
    builders: dict[str, set] = {}
    frames: dict[int, set] = {}
    singles: dict[str, dict] = {}
    sprite_sources: set[int] = set()
    for events in traces:
        for e in events:
            if e["kind"] == "picture_load" and e["a5"] < ROM_END:
                pictures[e["a5"]] = Picture.parse(rom_bytes, e["a5"])
    mapped = {a: p for a, p in pictures.items() if _plausible(p, size)}

    def owner(addr: int) -> Picture | None:
        return next((p for p in mapped.values()
                     if p.map_address <= addr < p.map_address + 2 * p.width * p.height), None)

    def place(p: Picture, e: dict, cols: int, rows: int, dst_stride: int) -> None:
        ent = entries[f"picture_{p.address:06x}"]
        if e["caller"] in STREAM_CALLERS:
            if e["screen"] not in ent["plane"]:
                ent["plane"].append(e["screen"])
                ent["plane"].sort()
            return
        off = (e["a0"] - p.map_address) // 2
        pl = {"screen": e["screen"], "x": off % p.width, "y": off // p.width, "cols": cols, "rows": rows,
              "vram": e["d1"], "stride": dst_stride}
        if pl not in ent["placements"]:
            ent["placements"].append(pl)

    for events in traces:
        for e in events:
            k, s = e["kind"], e["screen"]
            if k == "picture_load" and e["a5"] < ROM_END:
                p = pictures[e["a5"]]
                base = {"address": p.address, "tiles": p.tiles, "vram_base": p.vram_base, "count": p.count}
                if p.address in mapped:
                    _entry(entries, f"picture_{p.address:06x}", dict(
                        kind="picture", **base, width=p.width, height=p.height, map=p.map_address,
                        placements=[], plane=[]), s)
                else:
                    _entry(entries, f"tilebank_{p.address:06x}", dict(kind="tilebank", **base), s)
    for events in traces:
        for e in events:
            k, s = e["kind"], e["screen"]
            if k == "palette_line":
                if e["a0"] < ROM_END:
                    ent = _entry(entries, f"palette_{e['a0']:06x}",
                                 {"kind": "palette", "address": e["a0"], "colors": 16, "lines": []}, s)
                    if e["d2"] not in ent["lines"]:
                        ent["lines"].append(e["d2"])
                        ent["lines"].sort()
                else:
                    b = PALETTE_BUILDERS.get(e["caller"], f"builder_{e['caller']:06x}")
                    builders.setdefault(b, set()).add(s)
            elif k == "anim_set" and e["a0"] < ROM_END:
                an = Animation.parse(rom_bytes, e["a0"])
                _entry(entries, f"anim_{an.address:06x}", {
                    "kind": "anim", "address": an.address, "frames": an.count, "variants": len(an.variants),
                    "frame_data": an.frames_address, "speed": an.speed, "flags": an.flags}, s)
            elif k == "map_copy" and e["a0"] < ROM_END:
                p = owner(e["a0"])
                if p is not None:
                    place(p, e, e["d0"] // 2, e["d4"], e["d2"])
                else:
                    ent = _entry(entries, f"map_{e['a0']:06x}", {
                        "kind": "map", "address": e["a0"], "cols": e["d0"] // 2, "rows": e["d4"],
                        "src_stride": e["d3"], "uses": []}, s)
                    use = {"screen": s, "vram": e["d1"], "stride": e["d2"]}
                    if use not in ent["uses"]:
                        ent["uses"].append(use)
            elif k == "frame_draw" and e["a5"] < ROM_END:
                frames.setdefault(e["a5"], set()).add(s)
            elif k in ("text_plane", "text_sprites") and e["a5"] < ROM_END:
                f = _entry(entries, f"font_{e['a5']:06x}", {
                    "kind": "font", "address": e["a5"], "glyphs": struct.unpack_from(">H", rom_bytes, e["a5"] + 6)[0],
                    "drawn": [], "strings": []}, s)
                how = "plane" if k == "text_plane" else "sprites"
                if how not in f["drawn"]:
                    f["drawn"].append(how)
                    f["drawn"].sort()
                if e["a0"] < ROM_END and e["a0"] not in f["strings"]:
                    f["strings"].append(e["a0"])
                    f["strings"].sort()
            elif k == "piece_draw" and e["a5"] < ROM_END:
                g = singles.setdefault(f"{e['caller']:06x}", {"caller": e["caller"], "pieces": [], "screens": []})
                if e["a5"] not in g["pieces"]:
                    g["pieces"].append(e["a5"])
                    g["pieces"].sort()
                if s not in g["screens"]:
                    g["screens"].append(s)
                    g["screens"].sort()
            elif k == "dma_vram" and e["a0"] < ROM_END and e["caller"] != MAP_COPY_ROW_DMA:
                who = CALLERS.get(e["caller"])
                if who == "sprite_cache":
                    sprite_sources.add(e["a0"])
                elif who in ("picture", "sprite_table"):
                    pass
                elif e["d1"] >= NAME_TABLES:           # a map row DMA'd straight to a plane
                    p = owner(e["a0"])
                    if p is not None:
                        place(p, e, e["d0"] // 2, 1, 0)
                    else:
                        ent = _entry(entries, f"map_{e['a0']:06x}", {
                            "kind": "map", "address": e["a0"], "cols": e["d0"] // 2, "rows": 1,
                            "src_stride": e["d0"], "uses": []}, s)
                        use = {"screen": s, "vram": e["d1"], "stride": 0}
                        if use not in ent["uses"]:
                            ent["uses"].append(use)
                else:
                    _entry(entries, f"tiles_{e['a0']:06x}", {
                        "kind": "tiles", "address": e["a0"], "count": e["d0"] // 32, "vram": e["d1"],
                        "caller": e["caller"]}, s)
    for ent in entries.values():
        for key in ("placements", "uses"):
            if key in ent:
                ent[key].sort(key=lambda d: tuple(d.values()))
    # frames drawn outside catalogued animations (players pick frames from
    # their own tables - plan 08), grouped by the screens that draw them
    in_anims = set()
    for ent in entries.values():
        if ent["kind"] == "anim":
            an = Animation.parse(rom_bytes, ent["address"])
            in_anims.update(an.frame_addresses(rom_bytes))
    groups: dict[str, list[int]] = {}
    for a, scr in sorted(frames.items()):
        if a not in in_anims:
            groups.setdefault(",".join(map(str, sorted(scr))), []).append(a)
    # sprite tiles the cache streamed that no catalogued frame explains
    pieces = set()
    drawn = [pc for a in in_anims | set(frames) for pc in frame_pieces(rom_bytes, a)]
    drawn += [Piece.parse(rom_bytes, a) for g in singles.values() for a in g["pieces"]]
    for pc in drawn:
        if pc.rom_address is not None:
            pieces.update(pc.rom_address + 32 * t for t in range(pc.width * pc.height))
    unexplained = sorted(a for a in sprite_sources if a not in pieces)
    return {"entries": dict(sorted(entries.items())),
            "frames": dict(sorted(groups.items(), key=lambda kv: [int(x) for x in kv[0].split(",")])),
            "pieces": dict(sorted(singles.items())),
            "palette_builders": {k: sorted(v) for k, v in sorted(builders.items())},
            "sprite_sources": {"total": len(sprite_sources), "unexplained": len(unexplained)},
            "_unexplained_sprite_sources": unexplained}


def write_catalogue(cat: dict, rom: Rom, out: Path, scripts: list[str]) -> None:
    """One entry per line (diff-friendly). Addresses stay plain integers."""
    doc = {"format": "mw-rom-catalogue/1", "rom_sha1": rom.sha1,
           "comment": "Addresses, sizes and parameters of the original's graphics, found by tracing "
                      "(mw_harness assets). No ROM content. docs/re/graphics.md",
           "scripts": scripts, **{k: v for k, v in cat.items() if not k.startswith("_")}}
    lines = ["{"]
    keys = list(doc)
    for i, k in enumerate(keys):
        v = doc[k]
        end = "," if i < len(keys) - 1 else ""
        if isinstance(v, dict) and v and all(isinstance(x, (dict, list)) for x in v.values()):
            lines.append(f" {json.dumps(k)}: {{")
            items = list(v.items())
            for j, (kk, vv) in enumerate(items):
                sep = "," if j < len(items) - 1 else ""
                lines.append(f"  {json.dumps(kk)}: {json.dumps(vv, separators=(',', ':'))}{sep}")
            lines.append(f" }}{end}")
        else:
            lines.append(f" {json.dumps(k)}: {json.dumps(v)}{end}")
    lines.append("}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
