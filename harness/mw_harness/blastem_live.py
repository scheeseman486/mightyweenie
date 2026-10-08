"""Drive BlastEm's debugger interactively (one breakpoint stop at a time).

:mod:`trace` sends a fixed command script; here Python decides at every stop
what to do next (read memory, press buttons), which is what scripts with
screen anchors need. BlastEm runs headless under a pseudo-terminal (its
debugger needs a tty) with a private config, by default with EA's 4-Way Play
attached (the project always behaves as if it is connected).

    with LiveBlastEm() as bl:
        vblank = bl.breakpoint(0x13F96)
        while bl.cont() != vblank: ...
        tick, = bl.read("[0xffca56].l")
        bl.press(1, "START"); bl.release(1, "START")

Speed: ~0.3-0.4 ms per command round trip; a stop + one read ~0.7 ms.
"""
from __future__ import annotations

import os
import pty
import re
import select
import subprocess
import tempfile
import termios
import time
from pathlib import Path

from .rom import default_rom_path
from .trace import BLASTEM, _config, blastem_env

_PROMPT = re.compile(rb"(?:^|\n)> ")
_BLOCK_PROMPT = re.compile(rb"(?:^|\n)>> ")      # inside a `command` block
_HIT = re.compile(rb"68K Breakpoint (\d+) hit")
_SET = re.compile(rb"68K Breakpoint (\d+) set at \$([0-9A-Fa-f]+)")
_VALUES = re.compile(rb"@V((?: -?\d+)*)\r?\n")


class BlastEmError(RuntimeError):
    pass


class LiveBlastEm:
    def __init__(self, rom: Path | str | None = None, m68k_divider: int = 7, four_way: bool = True,
                 pad: str = "gamepad3", timeout: float = 20.0):
        self.rom = Path(rom) if rom else default_rom_path()
        self.timeout = timeout
        self._tmp = tempfile.TemporaryDirectory(prefix="mw-live-")
        tmp = _config(Path(self._tmp.name), m68k_divider, pad, four_way=four_way)
        master, slave = pty.openpty()
        attrs = termios.tcgetattr(slave)
        attrs[3] &= ~termios.ECHO               # don't echo our commands back
        termios.tcsetattr(slave, termios.TCSANOW, attrs)
        self._proc = subprocess.Popen([str(BLASTEM), "-d", str(self.rom)], stdin=slave, stdout=slave,
                                      stderr=slave, env=blastem_env(tmp), close_fds=True)
        os.close(slave)
        self._fd = master
        self._buf = b""
        self.breakpoints: dict[int, int] = {}   # id -> address
        self.banner = self._until_prompt()
        self.stops = 0

    # --- low level -------------------------------------------------------
    def _until_prompt(self, prompt: re.Pattern = _PROMPT) -> bytes:
        end = time.monotonic() + self.timeout
        while True:
            m = prompt.search(self._buf)
            if m:
                out, self._buf = self._buf[:m.end()], self._buf[m.end():]
                return out
            left = end - time.monotonic()
            r, _, _ = select.select([self._fd], [], [], max(0.0, left))
            if not r:
                raise BlastEmError("BlastEm did not answer:\n" + self._buf[-800:].decode(errors="replace"))
            try:
                chunk = os.read(self._fd, 65536)
            except OSError as e:   # the child exited
                raise BlastEmError("BlastEm exited:\n" + self._buf[-800:].decode(errors="replace")) from e
            self._buf += chunk

    def command(self, cmd: str) -> bytes:
        os.write(self._fd, (cmd + "\n").encode())
        return self._until_prompt()

    # --- debugger --------------------------------------------------------
    def breakpoint(self, address: int) -> int:
        out = self.command(f"breakpoint 0x{address:x}")
        m = _SET.search(out)
        if not m:
            raise BlastEmError(f"breakpoint at {address:#x} not set: {out!r}")
        bp = int(m.group(1))
        self.breakpoints[bp] = address
        return address

    def cont(self) -> int:
        """Continue until the next breakpoint; returns its address."""
        out = self.command("continue")
        hits = list(_HIT.finditer(out))   # the last one stopped; others ran a command block
        if not hits:
            raise BlastEmError(f"expected a breakpoint stop, got {out[-300:]!r}")
        self.stops += 1
        return self.breakpoints[int(hits[-1].group(1))]

    def read(self, *exprs: str) -> list[int]:
        """Evaluate BlastEm expressions ("[0xffca56].l", "d0", "pc") at this stop.
        Values come back as unsigned 32-bit."""
        fmt = " ".join(["%d"] * len(exprs))
        out = self.command(f'printf "@V {fmt}\\n" ' + " ".join(exprs))
        m = _VALUES.search(out)
        if not m:
            raise BlastEmError(f"printf failed: {out!r}")
        return [int(v) & 0xFFFFFFFF for v in m.group(1).split()]

    def log_at(self, address: int, array: str, *exprs: str, condition: str | None = None) -> None:
        """A breakpoint that appends ``exprs`` to debugger array ``array`` and
        continues by itself (no round trip per hit); fetch with :meth:`array`.
        ``condition``: a BlastEm expression; other hits are skipped."""
        self.command(f"array {array}")
        self.breakpoint(address)
        bp = max(k for k, v in self.breakpoints.items() if v == address)
        if condition:
            self.command(f"condition {bp} {condition}")
        os.write(self._fd, f"command {bp}\n".encode())
        self._until_prompt(_BLOCK_PROMPT)
        for e in exprs:
            os.write(self._fd, f"append {array} {e}\n".encode())
            self._until_prompt(_BLOCK_PROMPT)
        os.write(self._fd, b"continue\n")
        self._until_prompt(_BLOCK_PROMPT)
        self.command("end")
        self.logged = getattr(self, "logged", set()) | {bp}

    def on_hit(self, address: int, lines: list[str], condition: str | None = None) -> None:
        """A breakpoint that runs debugger ``lines`` and continues by itself
        (``append`` to arrays, ...): no round trip per hit."""
        self.breakpoint(address)
        bp = max(k for k, v in self.breakpoints.items() if v == address)
        if condition:
            self.command(f"condition {bp} {condition}")
        os.write(self._fd, f"command {bp}\n".encode())
        self._until_prompt(_BLOCK_PROMPT)
        for line in [*lines, "continue"]:
            os.write(self._fd, f"{line}\n".encode())
            self._until_prompt(_BLOCK_PROMPT)
        self.command("end")
        self.logged = getattr(self, "logged", set()) | {bp}

    def array(self, name: str, path: Path) -> list[int]:
        """Save debugger array ``name`` to ``path`` and return its values (32-bit)."""
        self.command(f'save/l "{path}" {name}')
        data = Path(path).read_bytes()
        return [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data) - 3, 4)]

    def write(self, address: int, value: int, size: str = "w") -> None:
        """Write memory at this stop (``size`` b/w/l); RE pokes only."""
        self.command(f"set [0x{address:x}].{size} {value}")

    def set_buttons(self, player: int, names: list[str], down: bool) -> None:
        verb = "binddown" if down else "bindup"
        for n in names:
            # quoted, or the binding name is parsed as an expression
            self.command(f'{verb} "gamepads.{player}.{n.lower()}"')

    def press(self, player: int, *names: str) -> None:
        self.set_buttons(player, list(names), True)

    def release(self, player: int, *names: str) -> None:
        self.set_buttons(player, list(names), False)

    # --- lifetime --------------------------------------------------------
    def close(self) -> None:
        if self._proc.poll() is None:
            try:
                os.write(self._fd, b"quit\n")
                self._proc.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                self._proc.kill()
                self._proc.wait()
        try:
            os.close(self._fd)
        except OSError:
            pass
        self._tmp.cleanup()

    def __enter__(self) -> "LiveBlastEm":
        return self

    def __exit__(self, *exc) -> None:
        self.close()
