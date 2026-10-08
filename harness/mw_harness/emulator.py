"""Headless reference emulator (Genesis Plus GX through stable-retro)."""
from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

import numpy as np

from .gpgx_state import OFF_WORK_RAM, MDState, parse_state
from .rom import default_rom_path


class Buttons:
    """Genesis pad bits in stable-retro's button order for the Genesis core."""

    ORDER = ["B", "A", "MODE", "START", "UP", "DOWN", "LEFT", "RIGHT", "C", "Y", "X", "Z"]

    @classmethod
    def mask(cls, names: str | list[str] | None) -> np.ndarray:
        """``Buttons.mask("A+START")`` or ``Buttons.mask(["UP", "C"])``."""
        m = np.zeros(len(cls.ORDER), dtype=np.uint8)
        if not names:
            return m
        if isinstance(names, str):
            names = [n for n in names.replace(",", "+").split("+") if n]
        for n in names:
            m[cls.ORDER.index(n.strip().upper())] = 1
        return m


class ReferenceEmulator:
    """Deterministic, frame-stepped original game.

    >>> emu = ReferenceEmulator()       # or: with ReferenceEmulator() as emu:
    >>> emu.run(300)                    # boot 300 frames with no input
    >>> emu.step(buttons="START")       # one frame holding START
    >>> s = emu.state()                 # MDState: RAM/VRAM/CRAM/... (big-endian)
    >>> s.ram_u8(0xFFB05E)              # e.g. RetroAchievements' "screen ID"
    """

    FRAME_RATE = 60  # NTSC Genesis vblank rate = the game's tick rate (tick_counter $FFCA56)

    # stable-retro allows ONE emulator per process. Use ``with`` or close().

    def __init__(self, rom_path: Path | str | None = None):
        import stable_retro  # imported lazily: heavy, and only needed here

        src = Path(rom_path) if rom_path else default_rom_path()
        # stable-retro picks the core from the extension and only accepts .md
        # for Genesis, so stage a copy when given e.g. a .bin.
        if src.suffix.lower() != ".md":
            self._tmp = tempfile.TemporaryDirectory(prefix="mw-rom-")
            staged = Path(self._tmp.name) / (src.stem + ".md")
            shutil.copyfile(src, staged)
            src = staged
        self.rom_path = src
        self._emu = stable_retro.RetroEmulator(str(src))
        self.frame = 0

    def close(self) -> None:
        """Release the core so another ReferenceEmulator can be created."""
        import gc

        if getattr(self, "_emu", None) is not None:
            self._emu = None
            gc.collect()

    def __enter__(self) -> "ReferenceEmulator":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    # --- stepping -----------------------------------------------------------
    def step(self, buttons: str | list[str] | None = None, player: int = 0) -> None:
        """Advance exactly one video frame (1/60 s) with ``buttons`` held."""
        self._emu.set_button_mask(Buttons.mask(buttons), player)
        self._emu.step()
        self.frame += 1

    def step_players(self, buttons: list[list[str]]) -> None:
        """One frame with per-player buttons (``[P1 names, P2 names]``; GPGX
        has two pads here)."""
        for player, names in enumerate(buttons[:2]):
            self._emu.set_button_mask(Buttons.mask(names), player)
        self._emu.step()
        self.frame += 1

    def run(self, frames: int, buttons: str | list[str] | None = None) -> None:
        for _ in range(frames):
            self.step(buttons)

    def run_script(self, script: "InputScript", frames: int) -> None:
        for _ in range(frames):
            self.step(script.buttons_at(self.frame))

    # --- observation ----------------------------------------------------------
    def state(self, with_cpu: bool = True) -> MDState:
        return parse_state(self._emu.get_state(), with_cpu=with_cpu)

    def screen(self) -> np.ndarray:
        """Current frame as an (H, W, 3) uint8 array."""
        return self._emu.get_screen()

    def audio(self) -> np.ndarray:
        """Audio samples produced by the last step (int16, stereo)."""
        return self._emu.get_audio()

    # --- save states ------------------------------------------------------------
    def save(self) -> bytes:
        return self._emu.get_state()

    def load(self, blob: bytes, frame: int | None = None) -> None:
        self._emu.set_state(blob)
        if frame is not None:
            self.frame = frame

    def poke(self, addr: int, value: int, size: int = 1) -> None:
        """Write work RAM (big-endian value of 1, 2 or 4 bytes) through a savestate.

        For reaching rare states quickly in RE scenarios (e.g. the game clock).
        GPGX keeps work RAM as little-endian words, so byte addresses are
        swapped within each word.
        """
        blob = bytearray(self.save())
        data = value.to_bytes(size, "big")
        for i, byte in enumerate(data):
            a = ((addr & 0xFFFF) + i) ^ 1
            blob[OFF_WORK_RAM + a] = byte
        self.load(bytes(blob))


class InputScript:
    """Frame-indexed controller input.

    Text form, one event per token/line: ``<first>[-<last>]:<BUTTONS>`` with
    buttons joined by ``+``. Frames are inclusive, counted from power-on.

        300-303:START
        420:A+B
    """

    def __init__(self, events: list[tuple[int, int, str]] | None = None):
        self.events = events or []

    @classmethod
    def parse(cls, text: str) -> "InputScript":
        events = []
        for tok in text.replace(",", " ").split():
            span, _, btns = tok.partition(":")
            first, _, last = span.partition("-")
            events.append((int(first), int(last or first), btns))
        return cls(events)

    def buttons_at(self, frame: int) -> list[str]:
        held: list[str] = []
        for first, last, btns in self.events:
            if first <= frame <= last:
                held += [b for b in btns.split("+") if b]
        return held
