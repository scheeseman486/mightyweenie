"""Check the catalogue and the reference decoders against the original.

:func:`snapshot` plays a tour script on Genesis Plus GX (frame-stepped,
deterministic) up to a moment given relative to a screen visit and returns
the console state (VRAM, CRAM, VSRAM, registers). The ``explain_*`` functions
rebuild what the catalogue says that screen loads and report how much of
VRAM, CRAM and the name tables it accounts for. Used by
``harness/tests/test_gfx_original.py``.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field

from . import palettes
from .assets import parse_pokes
from .gfx import Animation, Picture, Piece, font_glyphs, frame_pieces
from .gpgx_state import MDState
from .script import PAD_BITS, Script, ScriptPlayer

BOOT_FRAMES = 300   # GPGX frames before the tick counter means anything
TAP_FRAMES = 6


def _names(mask: int) -> list[str]:
    return [n for n, b in PAD_BITS.items() if mask & b]


def snapshot(script_text: str, screen: int, visit: int, offset: int, rom=None,
             max_frames: int = 60_000, image: list | None = None) -> MDState:
    """State ``offset`` ticks after the ``visit``-th entry of ``screen``
    (appends the frame, an (H, W, 3) array, to ``image`` if given)."""
    from .emulator import ReferenceEmulator

    script = Script.parse(script_text, "snapshot")
    pokes = parse_pokes(script_text)
    player = ScriptPlayer(script)
    visits: dict[int, int] = {}
    cur = None
    with ReferenceEmulator(rom) as emu:
        while emu.frame < max_frames:
            emu.step_players([_names(player.held(1)), _names(player.held(2))])
            s = emu.state(with_cpu=False)
            tick, sid = s.ram_u32(0xFFCA56), s.ram_u16(0xFFB05E)
            if emu.frame > BOOT_FRAMES and tick > 0 and (cur is None or sid != cur[0]):
                visits[sid] = visits.get(sid, 0) + 1
                cur = (sid, visits[sid])
                player.screen_entered(sid, tick)
            if cur == (screen, visit) and tick >= player.entries[cur] + offset:
                if image is not None:
                    image.append(emu.screen())
                return s
            for pk in [p for p in pokes if (p.screen, p.visit) in player.entries
                       and tick >= player.entries[(p.screen, p.visit)] + p.offset]:
                emu.poke(pk.address, pk.value, {"b": 1, "w": 2, "l": 4}[pk.size])
                pokes.remove(pk)
            player.tick_start(tick + 1)
            if cur is not None and tick % TAP_FRAMES == 0:
                # no pass boundaries here: release taps after a few frames,
                # long enough for the slowest menu loop (~4 ticks per pass)
                player.boundary(cur[0], cur[1], 0, tick + 1)
    raise RuntimeError(f"screen {screen} #{visit} +{offset} not reached in {max_frames} frames")


# --- VRAM ------------------------------------------------------------------
@dataclass
class Coverage:
    total: int = 0                   # non-blank tiles below the name tables
    slot: int = 0                    # == what this screen's catalogue puts in that slot
    stale: int = 0                   # == what another screen's catalogue puts there (VRAM isn't cleared)
    sprite: int = 0                  # == a tile of a catalogued sprite piece
    missing: list[int] = field(default_factory=list)   # VRAM tile numbers
    loaded: dict[str, float] = field(default_factory=dict)  # entry -> share of its tiles in place

    @property
    def ratio(self) -> float:
        return (self.slot + self.stale + self.sprite) / self.total if self.total else 1.0


def entries_for(cat: dict, screen: int, kinds: tuple[str, ...]) -> list[dict]:
    return [e for e in cat["entries"].values() if e["kind"] in kinds and screen in e["screens"]]


def sprite_tiles(rom: bytes, cat: dict) -> set[bytes]:
    """Every tile of every catalogued frame and piece. Not per screen: the
    sprite cache keeps tiles from earlier screens until it needs the slots."""
    addresses: list[int] = []
    for e in cat["entries"].values():
        if e["kind"] == "anim":
            an = Animation.parse(rom, e["address"])
            addresses += an.frame_addresses(rom)
    for frames in cat["frames"].values():
        addresses += frames
    pieces = [p for a in addresses for p in frame_pieces(rom, a)]
    for g in cat["pieces"].values():
        pieces += [Piece.parse(rom, a) for a in g["pieces"]]
    for e in cat["entries"].values():
        if e["kind"] == "font":
            pieces += [Piece.parse(rom, a) for a in font_glyphs(rom, e["address"])]
    out = set()
    for p in pieces:
        if p.rom_address is not None:
            for t in range(p.width * p.height):
                out.add(rom[p.rom_address + 32 * t: p.rom_address + 32 * t + 32])
    return out


def _tile_slots(rom: bytes, entries: list[dict]) -> dict[int, set[bytes]]:
    slots: dict[int, set[bytes]] = {}
    for e in entries:
        src, base = (e["tiles"], e["vram_base"]) if "vram_base" in e else (e["address"], e["vram"] // 32)
        for i in range(e["count"]):
            slots.setdefault(base + i, set()).add(rom[src + 32 * i: src + 32 * i + 32])
    return slots


def displayed_planes(state: MDState) -> list[str]:
    """Which name tables the VDP shows: the window covers plane A where it
    is set (when it covers the whole screen, as in the rink, A is hidden)."""
    r = state.vdp_regs
    wh, wv = r[0x11], r[0x12]
    if wh == 0 and wv == 0:
        return ["A", "B"]
    full_v = not (wv & 0x80) and (wv & 0x1F) * 8 >= 224
    full_h = not (wh & 0x80) and (wh & 0x1F) * 16 >= 320
    return ["B", "W"] if full_v and full_h else ["A", "B", "W"]


def referenced_tiles(state: MDState) -> set[int]:
    """Tile numbers the screen can show: every cell of the displayed planes
    and the tiles of on-screen sprites."""
    bases = plane_bases(state)
    out: set[int] = set()
    for name in displayed_planes(state):
        for row in plane_rows(state.vram, bases[name], 64, 32):
            out.update(w & 0x7FF for w in row)
    for s in sat_entries(state):
        if -32 < s["x"] < 320 and -32 < s["y"] < 224:
            out.update(range(s["tile"], s["tile"] + s["w"] * s["h"]))
    return out


def explain_vram(rom: bytes, cat: dict, screen: int, vram: bytes, limit: int = 0xC000,
                 only: set[int] | None = None) -> Coverage:
    """Account for every non-blank tile below ``limit`` (or just the tile
    numbers in ``only``, e.g. :func:`referenced_tiles`): the tile this
    screen's catalogue loads into that slot, one another screen loads there
    (left over), or any catalogued sprite tile (the sprite cache). Also the
    share of each of this screen's tile entries found in place."""
    kinds = ("picture", "tilebank", "tiles")
    mine = entries_for(cat, screen, kinds)
    expected = _tile_slots(rom, mine)
    others = _tile_slots(rom, [e for e in cat["entries"].values() if e["kind"] in kinds])
    sprites = sprite_tiles(rom, cat)
    cov = Coverage()
    for t in range(limit // 32):
        data = vram[32 * t: 32 * t + 32]
        if not any(data) or (only is not None and t not in only):
            continue
        cov.total += 1
        if data in expected.get(t, ()):
            cov.slot += 1
        elif data in sprites:
            cov.sprite += 1
        elif data in others.get(t, ()):
            cov.stale += 1
        else:
            cov.missing.append(t)
    for e in mine:
        src, base = (e["tiles"], e["vram_base"]) if "vram_base" in e else (e["address"], e["vram"] // 32)
        same = sum(vram[32 * (base + i): 32 * (base + i) + 32] == rom[src + 32 * i: src + 32 * i + 32]
                   for i in range(e["count"]))
        cov.loaded[f"{e['kind']}_{e['address']:06x}"] = same / e["count"]
    return cov


# --- name tables -------------------------------------------------------------
def plane_rows(vram: bytes, base: int, width: int, rows: int) -> list[tuple[int, ...]]:
    return [struct.unpack_from(f">{width}H", vram, base + 2 * width * r) for r in range(rows)]


def expected_cells(rom: bytes, cat: dict, screen: int, plane_width: int = 64
                   ) -> tuple[dict[int, set[int]], set[tuple[int, ...]]]:
    """Name-table words the catalogue places on ``screen``: VRAM address ->
    possible words (rectangles copied from pictures and maps), plus the plane
    rows that pictures drawn through the wrapping plane routine can produce
    (a picture row repeated across the plane, at any horizontal offset)."""
    cells: dict[int, set[int]] = {}

    def put(vram: int, stride: int, rows: int, cols: int, word_at) -> None:
        for r in range(rows):
            for c in range(cols):
                cells.setdefault(vram + r * stride + 2 * c, set()).add(word_at(r, c))

    tiled: set[tuple[int, ...]] = set()
    for e in entries_for(cat, screen, ("picture",)):
        words = Picture.parse(rom, e["address"]).map_words(rom)
        w = e["width"]
        for pl in e["placements"]:
            if pl["screen"] == screen:
                # read the ROM directly: some copies run past the map's last
                # row (the scoreboard copies 17 rows of a 16-row picture)
                put(pl["vram"], pl["stride"], pl["rows"], pl["cols"], lambda r, c, pl=pl: struct.unpack_from(
                    ">H", rom, e["map"] + 2 * ((pl["y"] + r) * w + pl["x"] + c))[0])
        if screen in e["plane"]:
            for r in range(e["height"]):
                row = words[r * w:(r + 1) * w]
                tiled.update(tuple(row[(c + ox) % w] for c in range(plane_width)) for ox in range(w))
    for e in entries_for(cat, screen, ("map",)):
        for u in e["uses"]:
            if u["screen"] == screen:
                put(u["vram"], u["stride"], e["rows"], e["cols"], lambda r, c, e=e: struct.unpack_from(
                    ">H", rom, e["address"] + r * e["src_stride"] + 2 * c)[0])
    return cells, tiled


def plane_bases(state: MDState) -> dict[str, int]:
    r = state.vdp_regs
    return {"A": (r[2] & 0x38) << 10, "B": (r[4] & 7) << 13, "W": (r[3] & 0x3C) << 10}


def _plane_rows_any_screen(rom: bytes, cat: dict, plane_width: int) -> set[tuple[int, ...]]:
    rows: set[tuple[int, ...]] = set()
    for e in cat["entries"].values():
        if e["kind"] == "picture" and e["plane"]:
            words = Picture.parse(rom, e["address"]).map_words(rom)
            w = e["width"]
            for r in range(e["height"]):
                row = words[r * w:(r + 1) * w]
                rows.update(tuple(row[(c + ox) % w] for c in range(plane_width)) for ox in range(w))
    return rows


def explain_plane(rom: bytes, cat: dict, screen: int, vram: bytes, base: int, width: int = 64,
                  rows: int = 32) -> tuple[int, int]:
    """(explained, content) cells of the plane at ``base``. Content = cells
    other than the plane's most common word (its background fill); explained
    = the catalogue puts that word at that address, or the cell's row is a
    picture row laid across the plane by the plane routine - on this screen
    or left over from an earlier one (the scoreboards keep the rink's rows
    below their panel)."""
    cells, tiled = expected_cells(rom, cat, screen, width)
    tiled |= _plane_rows_any_screen(rom, cat, width)
    grid = plane_rows(vram, base, width, rows)
    counts: dict[int, int] = {}
    for row in grid:
        for w in row:
            counts[w] = counts.get(w, 0) + 1
    background = max(counts, key=counts.get)
    explained = content = 0
    for r, row in enumerate(grid):
        whole = row in tiled
        for c, w in enumerate(row):
            if w == background:
                continue
            content += 1
            if whole or w in cells.get(base + 2 * (r * width + c), ()):
                explained += 1
    return explained, content


def check_placements(rom: bytes, cat: dict, screen: int, vram: bytes) -> tuple[int, int]:
    """(matching, total) name-table cells that this screen's catalogued
    rectangles (picture placements, map uses) cover: does the original show
    those words there? Cells drawn over later (text) count as mismatches."""
    cells, _ = expected_cells(rom, cat, screen)
    ok = sum(struct.unpack_from(">H", vram, a)[0] in words for a, words in cells.items())
    return ok, len(cells)


# --- sprites -----------------------------------------------------------------
def sat_entries(state: MDState) -> list[dict]:
    """The VDP sprite list (linked), from the SAT in VRAM."""
    base = (state.vdp_regs[5] & 0x7F) << 9
    out, link, seen = [], 0, set()
    while link not in seen and len(out) < 80:
        seen.add(link)
        y, sl, attr, x = struct.unpack_from(">4H", state.vram, base + 8 * link)
        size = sl >> 8
        out.append({"y": (y & 0x3FF) - 128, "x": (x & 0x1FF) - 128, "w": ((size >> 2) & 3) + 1,
                    "h": (size & 3) + 1, "tile": attr & 0x7FF, "hflip": bool(attr & 0x800),
                    "vflip": bool(attr & 0x1000), "line": (attr >> 13) & 3})
        link = sl & 0x7F
        if link == 0:
            break
    return out


def explain_sprites(rom: bytes, cat: dict, state: MDState) -> tuple[int, int]:
    """(catalogued, total) on-screen sprites whose VRAM tiles, read
    column-major, equal the ROM tiles of a catalogued piece (any screen's:
    frames are shared). This checks the piece format: tile word = ROM
    address / 32, ``w*h`` tiles in column order."""
    addresses: list[int] = []
    for e in cat["entries"].values():
        if e["kind"] == "anim":
            an = Animation.parse(rom, e["address"])
            addresses += an.frame_addresses(rom)
    for frames in cat["frames"].values():
        addresses += frames
    pieces = [p for a in addresses for p in frame_pieces(rom, a)]
    for g in cat["pieces"].values():
        pieces += [Piece.parse(rom, a) for a in g["pieces"]]
    for e in cat["entries"].values():
        if e["kind"] == "font":
            pieces += [Piece.parse(rom, a) for a in font_glyphs(rom, e["address"])]
    blocks = {rom[p.rom_address: p.rom_address + 32 * p.width * p.height]
              for p in pieces if p.rom_address is not None}
    catalogued = total = 0
    for s in sat_entries(state):
        if not (-32 < s["x"] < 320 and -32 < s["y"] < 224):
            continue
        data = state.vram[32 * s["tile"]: 32 * (s["tile"] + s["w"] * s["h"])]
        if not any(data):
            continue
        total += 1
        catalogued += data in blocks
    return catalogued, total


# --- CRAM ----------------------------------------------------------------------
def setup(state: MDState) -> dict:
    """Menu choices the palette builders read."""
    return {"team_a": state.ram_u8(0xFFB0DE), "team_b": state.ram_u8(0xFFB0DF),
            "stadium": state.ram_u8(0xFFB0E4)}


def expected_cram(rom: bytes, screen: int, recipe: list, state: MDState) -> list[list[int]]:
    """The 64 colours a screen fades to, composed from a recipe of builder
    steps applied in order (teams/stadium read from the state). Returns the
    candidates: ``["menu_line", "any"]`` yields one per menu line (the main
    menu cycles line 3)."""
    s = setup(state)
    out = [[0] * 64]
    for step in recipe:
        kind, args = step[0], step[1:]
        nxt = []
        for cram in out:
            cram = list(cram)
            if kind == "screen_palette":
                cram = palettes.screen_palette(rom, screen, s["team_a"], s["stadium"])
            elif kind == "rom":                       # ["rom", "0xADDR", line]
                line = args[1]
                cram[16 * line:16 * line + 16] = palettes._w(rom, int(args[0], 16), 16)
            elif kind == "team_line":                 # ["team_line", "a"|"b", line, style]
                team = s["team_" + args[0]]
                cram[16 * args[1]:16 * args[1] + 16] = palettes.team_line(rom, screen, team, s["stadium"], args[2])
            elif kind == "ice_line":
                cram[0:16] = palettes.ice_line(rom, s["stadium"])
            elif kind == "black":                     # ["black", index]: $149B2 sets one colour to 0
                cram[args[0]] = 0
            elif kind == "panel_line":                # ["panel_line", "a"|"b", line]
                ptr = struct.unpack_from(">I", rom, palettes.team_record(s["team_" + args[0]]) + 0x7C)[0]
                cram[16 * args[1]:16 * args[1] + 16] = palettes.panel_line(rom, screen, ptr)
            elif kind == "menu_line":                 # ["menu_line", index | "any"]
                for i in (range(3) if args[0] == "any" else [args[0]]):
                    c = list(cram)
                    c[48:64] = palettes.menu_line(rom, i)
                    nxt.append(c)
                continue
            else:
                raise ValueError(kind)
            nxt.append(cram)
        out = nxt
    return out


def cram_mismatches(rom: bytes, screen: int, checkpoint: dict, state: MDState) -> list[int]:
    """Colour indices that differ from the best-matching candidate, leaving
    out ``cram_ignore`` and lines not in ``cram_lines`` (default: all)."""
    lines = checkpoint.get("cram_lines", [0, 1, 2, 3])
    idx = [i for i in range(64) if i // 16 in lines and i not in checkpoint.get("cram_ignore", [])]
    best = None
    for cand in expected_cram(rom, screen, checkpoint["cram"], state):
        bad = [i for i in idx if cand[i] != state.cram[i]]
        if best is None or len(bad) < len(best):
            best = bad
    return best


# --- fixture ---------------------------------------------------------------------
THRESHOLD_KEYS = ("loaded", "tiles_min", "shown_min", "placed_min", "sprites_min")


def measure(rom: bytes, cat: dict, cp: dict, script_text: str) -> dict:
    """Run one checkpoint and return its measured values."""
    screen, visit, offset = cp["at"]
    state = snapshot(script_text, screen, visit, offset)
    screen = cp.get("screen", screen)
    cov = explain_vram(rom, cat, screen, state.vram)
    shown = explain_vram(rom, cat, screen, state.vram, only=referenced_tiles(state))
    return {"loaded": cov.loaded, "tiles": cov.ratio, "shown": shown.ratio,
            "placed": check_placements(rom, cat, screen, state.vram),
            "sprites": explain_sprites(rom, cat, state),
            "cram_mismatches": cram_mismatches(rom, screen, cp, state)}


def thresholds(m: dict) -> dict:
    """Regression thresholds a little below measured values."""
    import math

    def below(x: float, margin: float) -> float:
        return math.floor((x - margin) * 100) / 100

    out = {"loaded": sorted(k for k, v in m["loaded"].items() if v >= 0.95),
           "tiles_min": below(m["tiles"], 0.01), "shown_min": below(m["shown"], 0.01)}
    ok, total = m["placed"]
    if total and ok / total >= 0.5:
        out["placed_min"] = below(ok / total, 0.02)
    ok, total = m["sprites"]
    if total:
        out["sprites_min"] = below(ok / total, 0.05)
    return out
