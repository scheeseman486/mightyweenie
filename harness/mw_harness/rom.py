"""ROM loading and identification."""
from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass
from pathlib import Path

#: No-Intro "Mutant League Hockey (USA, Europe)" - the only known dump.
MLH_SHA1 = "84e203c5226bc1913a485804e59c6418e939bd3d"
MLH_SIZE = 2 * 1024 * 1024
REPO_ROOT = Path(__file__).resolve().parents[2]


def default_rom_path() -> Path:
    """Where the project expects the user-supplied ROM (gitignored)."""
    return REPO_ROOT / "rom" / "Mutant League Hockey (USA, Europe).md"


@dataclass(frozen=True)
class Rom:
    """A Genesis cartridge image with big-endian accessors (68000 byte order)."""

    path: Path
    data: bytes

    @classmethod
    def load(cls, path: Path | str | None = None) -> "Rom":
        p = Path(path) if path else default_rom_path()
        return cls(p, p.read_bytes())

    @property
    def sha1(self) -> str:
        return hashlib.sha1(self.data).hexdigest()

    @property
    def is_mlh(self) -> bool:
        return self.sha1 == MLH_SHA1

    # --- header ($100-$1FF) ---------------------------------------------
    def ascii(self, start: int, end: int) -> str:
        return self.data[start:end].decode("ascii", "replace").rstrip()

    @property
    def system(self) -> str:
        return self.ascii(0x100, 0x110)

    @property
    def product_code(self) -> str:
        return self.ascii(0x180, 0x18E)

    @property
    def header_checksum(self) -> int:
        return self.u16(0x18E)

    def computed_checksum(self) -> int:
        """Standard Genesis checksum: 16-bit sum of words from $200 to end."""
        words = struct.unpack(f">{(len(self.data) - 0x200) // 2}H", self.data[0x200:])
        return sum(words) & 0xFFFF

    @property
    def reset_sp(self) -> int:
        return self.u32(0)

    @property
    def reset_pc(self) -> int:
        return self.u32(4)

    # --- big-endian reads -------------------------------------------------
    def u8(self, addr: int) -> int:
        return self.data[addr]

    def u16(self, addr: int) -> int:
        return struct.unpack_from(">H", self.data, addr)[0]

    def u32(self, addr: int) -> int:
        return struct.unpack_from(">I", self.data, addr)[0]
