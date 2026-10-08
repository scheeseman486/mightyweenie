"""Reference decoders for the original's graphics (docs/re/graphics.md).

Everything here reads the user's ROM and returns numbers; nothing is saved.
The GDScript decoders in game/src/rom/ mirror these and are checked against
them by hash (compare/fixtures/gfx_hashes.json).

Formats:
* **Tile**: 8x8, 4 bits per pixel, 32 bytes, rows top to bottom, two pixels
  per byte with the left pixel in the high nibble.
* **Colour**: Genesis word ``0000BBB0GGG0RRR0``; palette lines of 16; colour 0
  of each line is transparent for sprites and the top planes.
* **Name-table entry** (map cell): bit 15 priority, 14-13 palette line,
  12 vertical flip, 11 horizontal flip, 10-0 tile number in VRAM.
* **Picture** (e.g. ``$24CFC``, the rink): ``tiles.l, vram_base.w, count.w,
  width.w, height.w`` then ``width*height`` name-table words; the tile data
  (``count * 32`` bytes) is DMA'd to tile ``vram_base``, so map entries use
  VRAM tile numbers.
* **Animation** (e.g. ``$4CEB2``): ``speed.w, flags.b, count.b, frames.l``,
  a table of variant words (``list_offset << 2 | flips``; one variant =
  ``$0028``) and per variant ``count`` frame offsets (words, relative to
  ``frames``); see :class:`Animation`.
* **Frame**: ``pieces.w`` then per piece ``x.b, y.b, size.b, attr.b, tile.w``
  (6 bytes). ``size``: bits 3-2 width-1, bits 1-0 height-1 (cells). ``tile``
  >= $800 is a ROM address / 32 (the sprite cache DMAs it to VRAM, ``$15104``);
  below $800 it is a RAM address / 32. A piece's tiles are column-major.
"""
from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass


def tile_indices(data: bytes) -> bytes:
    """One 32-byte tile -> 64 colour indices (row-major)."""
    out = bytearray(64)
    for i, b in enumerate(data[:32]):
        out[i * 2] = b >> 4
        out[i * 2 + 1] = b & 15
    return bytes(out)


def tiles(rom: bytes, address: int, count: int) -> list[bytes]:
    return [tile_indices(rom[address + 32 * i: address + 32 * i + 32]) for i in range(count)]


def color_rgb8(word: int) -> tuple[int, int, int]:
    """Genesis colour word -> 8-bit RGB (3-bit channels scaled by 255/7)."""
    r, g, b = (word >> 1) & 7, (word >> 5) & 7, (word >> 9) & 7
    return (r * 255 // 7, g * 255 // 7, b * 255 // 7)


def palette_words(rom: bytes, address: int, count: int = 16) -> list[int]:
    return list(struct.unpack_from(f">{count}H", rom, address))


@dataclass(frozen=True)
class Cell:
    tile: int
    hflip: bool
    vflip: bool
    line: int
    priority: bool

    @classmethod
    def from_word(cls, w: int) -> "Cell":
        return cls(w & 0x7FF, bool(w & 0x800), bool(w & 0x1000), (w >> 13) & 3, bool(w & 0x8000))


@dataclass(frozen=True)
class Picture:
    address: int
    tiles: int
    vram_base: int
    count: int
    width: int
    height: int

    @property
    def map_address(self) -> int:
        return self.address + 12

    @classmethod
    def parse(cls, rom: bytes, address: int) -> "Picture":
        t, base, count, w, h = struct.unpack_from(">IHHHH", rom, address)
        return cls(address, t, base, count, w, h)

    def map_words(self, rom: bytes) -> list[int]:
        return list(struct.unpack_from(f">{self.width * self.height}H", rom, self.map_address))

    def tile_bytes(self, rom: bytes) -> bytes:
        return rom[self.tiles: self.tiles + 32 * self.count]


@dataclass(frozen=True)
class Piece:
    x: int
    y: int
    width: int      # cells
    height: int
    attr: int
    tile: int       # tile word: ROM (>= $800) or RAM address / 32

    @classmethod
    def parse(cls, rom: bytes, address: int) -> "Piece":
        x, y, size, attr, tile = struct.unpack_from(">bbBBH", rom, address)
        return cls(x, y, ((size >> 2) & 3) + 1, (size & 3) + 1, attr, tile)

    @property
    def hflip(self) -> bool:
        return bool(self.attr & 0x08)

    @property
    def vflip(self) -> bool:
        return bool(self.attr & 0x10)

    @property
    def line(self) -> int:
        return (self.attr >> 5) & 3

    @property
    def rom_address(self) -> int | None:
        return self.tile << 5 if self.tile >= 0x800 else None


@dataclass(frozen=True)
class Animation:
    """``speed.w, flags.b, count.b, frames.l`` then one word per variant
    (direction): ``list_offset << 2 | flips`` - the variant's ``count`` frame
    offsets (words, relative to ``frames``) are at ``address + list_offset``;
    flips (bit 0 horizontal, bit 1 vertical) mirror the whole frame. The
    variant table ends where the first list starts (one variant: ``$0028``,
    list at +10). Variants share lists: a left-facing frame is the
    right-facing one flipped. Played by ``$143CA``, drawn by ``$15666``."""
    address: int
    speed: int
    flags: int
    count: int
    frames_address: int
    variants: tuple[tuple[int, int], ...]     # (list address, flips)

    @classmethod
    def parse(cls, rom: bytes, address: int) -> "Animation":
        speed, flags, count, frames = struct.unpack_from(">HBBI", rom, address)
        variants, end, pos = [], None, address + 8
        while end is None or pos < end:
            (w,) = struct.unpack_from(">H", rom, pos)
            lst = address + (w >> 2)
            variants.append((lst, w & 3))
            end = lst if end is None else min(end, lst)
            pos += 2
        return cls(address, speed, flags, count, frames, tuple(variants))

    def offsets_of(self, rom: bytes, variant: int = 0) -> tuple[int, ...]:
        return struct.unpack_from(f">{self.count}H", rom, self.variants[variant][0])

    @property
    def offsets(self) -> tuple[int, ...]:     # variant 0 (needs the ROM: see offsets_of)
        raise AttributeError("use offsets_of(rom, variant)")

    def frame_addresses(self, rom: bytes) -> list[int]:
        """Every distinct frame the animation can show (all variants)."""
        seen: list[int] = []
        for v in range(len(self.variants)):
            for o in self.offsets_of(rom, v):
                if self.frames_address + o not in seen:
                    seen.append(self.frames_address + o)
        return seen

    def frame(self, rom: bytes, index: int, variant: int = 0) -> tuple[list[Piece], int]:
        """(pieces, flips) of frame ``index`` in ``variant``."""
        return frame_pieces(rom, self.frames_address + self.offsets_of(rom, variant)[index]), \
            self.variants[variant][1]


def frame_pieces(rom: bytes, address: int) -> list[Piece]:
    (n,) = struct.unpack_from(">H", rom, address)
    return [Piece.parse(rom, address + 2 + 6 * i) for i in range(n)]


# --- composition (indexed images: value = line * 16 + colour index; colour 0
# of any line is transparent and stays 0) -----------------------------------
def blit_tile(img: bytearray, stride: int, px: int, py: int, t: bytes, line: int,
              hflip: bool, vflip: bool, transparent0: bool = True) -> None:
    for r in range(8):
        sr = 7 - r if vflip else r
        for c in range(8):
            sc = 7 - c if hflip else c
            v = t[sr * 8 + sc]
            if v == 0 and transparent0:
                continue
            img[(py + r) * stride + px + c] = line * 16 + v


def picture_image(rom: bytes, pic: Picture) -> tuple[int, int, bytes]:
    """The picture's whole map as an indexed image. Colour 0 of every line is
    transparent on the Genesis (the backdrop colour shows through), so those
    pixels are 0 whatever their line."""
    w, h = pic.width * 8, pic.height * 8
    img = bytearray(w * h)
    ts = tiles(rom, pic.tiles, pic.count)
    for i, word in enumerate(pic.map_words(rom)):
        c = Cell.from_word(word)
        k = c.tile - pic.vram_base
        t = ts[k] if 0 <= k < len(ts) else bytes(64)
        blit_tile(img, w, (i % pic.width) * 8, (i // pic.width) * 8, t, c.line, c.hflip, c.vflip)
    return w, h, bytes(img)


def frame_bounds(pieces: list[Piece]) -> tuple[int, int, int, int]:
    if not pieces:
        return 0, 0, 0, 0
    x0 = min(p.x for p in pieces)
    y0 = min(p.y for p in pieces)
    x1 = max(p.x + 8 * p.width for p in pieces)
    y1 = max(p.y + 8 * p.height for p in pieces)
    return x0, y0, x1, y1


def flip_pieces(pieces: list[Piece], flips: int) -> list[Piece]:
    """Mirror a whole frame (``$156C6``: x' = -(x + width), piece flip bits
    toggled; the same vertically)."""
    out = []
    for p in pieces:
        x, y, attr = p.x, p.y, p.attr
        if flips & 1:
            x, attr = -x - 8 * p.width, attr ^ 0x08
        if flips & 2:
            y, attr = -y - 8 * p.height, attr ^ 0x10
        out.append(Piece(x, y, p.width, p.height, attr, p.tile))
    return out


def frame_image(rom: bytes, pieces: list[Piece], flips: int = 0) -> tuple[int, int, int, int, bytes]:
    """Compose a frame: (origin_x, origin_y, width, height, indexed pixels).
    Pieces are drawn in list order, later pieces on top: ``add_sprite_piece``
    ($156C6) puts a piece in front of earlier ones of the same depth, and a
    frame's pieces share one depth (docs/re/rink.md, Sprite list; plan 03
    had it the other way round, which no catalogued frame shows)."""
    pieces = flip_pieces(pieces, flips) if flips else pieces
    x0, y0, x1, y1 = frame_bounds(pieces)
    w, h = x1 - x0, y1 - y0
    img = bytearray(w * h)
    for p in pieces:
        base = p.rom_address
        if base is None:
            continue
        for cx in range(p.width):
            for cy in range(p.height):
                t = tile_indices(rom[base + 32 * (cx * p.height + cy): base + 32 * (cx * p.height + cy) + 32])
                dx = (p.width - 1 - cx) if p.hflip else cx
                dy = (p.height - 1 - cy) if p.vflip else cy
                blit_tile(img, w, p.x - x0 + dx * 8, p.y - y0 + dy * 8, t, p.line, p.hflip, p.vflip)
    return -x0, -y0, w, h, bytes(img)


def digest(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


# --- hashes shared with the GDScript decoders (compare/fixtures/gfx_hashes.json)
def palette_rgb(rom: bytes, address: int, count: int = 16) -> bytes:
    return b"".join(bytes(color_rgb8(w)) for w in palette_words(rom, address, count))


def frame_record(rom: bytes, address: int, flips: int = 0) -> bytes:
    """A composed frame as hashed: origin x/y (signed), width, height
    (big-endian words) then the indexed pixels."""
    ox, oy, w, h, px = frame_image(rom, frame_pieces(rom, address), flips)
    return struct.pack(">hhHH", ox, oy, w, h) + px


def catalogue_hashes(rom: bytes, cat: dict) -> dict[str, str]:
    """SHA-1 of what each catalogue entry decodes to (no content, just
    digests): tile banks as colour indices, pictures as indexed images,
    palettes as RGB, animations and frame groups as composed frames."""
    out: dict[str, str] = {}
    for key, e in cat["entries"].items():
        k = e["kind"]
        if k in ("picture", "tilebank"):
            out[key + "/tiles"] = digest(b"".join(tiles(rom, e["tiles"], e["count"])))
            if k == "picture":
                w, h, px = picture_image(rom, Picture.parse(rom, e["address"]))
                out[key + "/image"] = digest(struct.pack(">HH", w, h) + px)
        elif k == "palette":
            out[key] = digest(palette_rgb(rom, e["address"]))
        elif k == "anim":
            an = Animation.parse(rom, e["address"])
            out[key] = digest(b"".join(frame_record(rom, an.frames_address + o, an.variants[v][1])
                                       for v in range(len(an.variants)) for o in an.offsets_of(rom, v)))
        elif k == "font":
            cmap = font_char_map(rom, e["address"])
            out[key] = digest(b"".join(frame_record_piece(rom, a) for a in font_glyphs(rom, e["address"]))
                              + "".join(f"{c}{g:02x}" for c, g in sorted(cmap.items())).encode())
        elif k == "map":
            out[key] = digest(b"".join(struct.pack(">H", w) for r in range(e["rows"])
                                       for w in struct.unpack_from(f">{e['cols']}H", rom,
                                                                   e["address"] + r * e["src_stride"])))
    for group, frames in cat.get("frames", {}).items():
        out[f"frames/{group}"] = digest(b"".join(frame_record(rom, a) for a in frames))
    for caller, g in cat.get("pieces", {}).items():
        out[f"pieces/{caller}"] = digest(b"".join(frame_record_piece(rom, a) for a in g["pieces"]))
    for key, e in cat["entries"].items():
        if e["kind"] == "font":
            for a in e.get("strings", []):
                out[f"text/{key}/{a:06x}"] = digest(text_record(rom, e["address"], rom_string(rom, a)))
    return dict(sorted(out.items()))


def font_glyphs(rom: bytes, address: int) -> list[int]:
    """Glyph piece addresses of a font record: ``+2`` space width, ``+4``
    offset of the character map (ASCII ``!``-``~`` -> glyph index, bytes at
    ``address + offset - $21 + char``), ``+6`` glyph count, ``+8`` the glyphs
    (6-byte pieces). Drawn by ``$14CAE`` (into a plane) and ``$F3CC`` (as
    sprites)."""
    (count,) = struct.unpack_from(">H", rom, address + 6)
    return [address + 8 + 6 * i for i in range(count)]


def font_char_map(rom: bytes, address: int) -> dict[str, int]:
    """Character -> glyph index for ``!``-``~`` (missing characters omitted)."""
    (offset, count) = struct.unpack_from(">HH", rom, address + 4)
    out = {}
    for c in range(0x21, 0x7F):
        g = struct.unpack_from(">b", rom, address + offset - 0x21 + c)[0]
        if 0 <= g < count:
            out[chr(c)] = g
    return out


def frame_record_piece(rom: bytes, address: int) -> bytes:
    """A single piece composed like a one-piece frame."""
    ox, oy, w, h, px = frame_image(rom, [Piece.parse(rom, address)])
    return struct.pack(">hhHH", ox, oy, w, h) + px


# --- text (draw_text $14CAE, draw_glyph $14C26) -----------------------------
def rom_string(rom: bytes, address: int) -> bytes:
    """The 0-terminated string at ``address`` (without the 0)."""
    return rom[address:rom.index(b"\0", address)]


def font_glyph(rom: bytes, font: int, ch: int) -> int | None:
    """Glyph index of character code ``ch`` (``!``-``~`` only)."""
    if not 0x21 <= ch <= 0x7E:
        return None
    (offset, count) = struct.unpack_from(">HH", rom, font + 4)
    g = struct.unpack_from(">b", rom, font + offset - 0x21 + ch)[0]
    return g if 0 <= g < count else None


def char_width(rom: bytes, font: int, ch: int) -> int:
    """``$14BCE``: cells a character advances (space: font +2; none: 0)."""
    if ch == 0x20:
        return struct.unpack_from(">H", rom, font + 2)[0]
    g = font_glyph(rom, font, ch)
    return 0 if g is None else ((rom[font + 8 + 6 * g + 2] >> 2) & 3) + 1


def text_width(rom: bytes, font: int, text: bytes) -> int:
    """``$14C14``: width of a string in cells."""
    return sum(char_width(rom, font, c) for c in text)


def text_glyphs(rom: bytes, font: int, text: bytes, x: int = 0, y: int = 0) -> list[tuple[int, int, int, int, int]]:
    """Where ``draw_text`` puts each glyph of ``text`` drawn at cell (x, y):
    (cell x, top cell y, width, height, ROM address of its first tile).
    Glyphs sit on the baseline: top = y + font +0 - height. Their tiles are
    column-major in the ROM (like sprite pieces); the piece's attr is not
    used (the caller's palette line applies)."""
    (baseline, space) = struct.unpack_from(">hH", rom, font)
    out = []
    for c in text:
        if c == 0x20:
            x += space
            continue
        g = font_glyph(rom, font, c)
        if g is None:
            continue
        piece = Piece.parse(rom, font + 8 + 6 * g)
        out.append((x, y + baseline - piece.height, piece.width, piece.height, piece.tile * 32))
        x += piece.width
    return out


def text_image(rom: bytes, font: int, text: bytes, line: int = 0) -> tuple[int, int, int, bytes]:
    """A string as an indexed image: (top row relative to the text's row,
    width, height in pixels, pixels). Width = the string's width in cells."""
    glyphs = text_glyphs(rom, font, text)
    if not glyphs:
        return 0, 8 * text_width(rom, font, text), 0, b""
    top = min(g[1] for g in glyphs)
    w = 8 * text_width(rom, font, text)
    h = 8 * (max(g[1] + g[3] for g in glyphs) - top)
    img = bytearray(w * h)
    for gx, gy, gw, gh, base in glyphs:
        for cx in range(gw):
            for cy in range(gh):
                a = base + 32 * (cx * gh + cy)
                blit_tile(img, w, 8 * (gx + cx), 8 * (gy - top + cy), tile_indices(rom[a:a + 32]), line, False, False)
    return top, w, h, bytes(img)


def text_record(rom: bytes, font: int, text: bytes) -> bytes:
    """A string as hashed: top (signed), width, height (words), pixels."""
    top, w, h, px = text_image(rom, font, text)
    return struct.pack(">hHH", top, w, h) + px


def string_list(rom: bytes, address: int) -> list[int]:
    """A credit page's strings (``$DD4``): the heading (may be empty), then
    body lines up to an empty string. Returns their addresses."""
    out = [address]
    a = rom.index(b"\0", address) + 1
    while rom[a] != 0:
        out.append(a)
        a = rom.index(b"\0", a) + 1
    return out
