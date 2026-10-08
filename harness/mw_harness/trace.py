"""Loop-precise event traces from BlastEm's scripted debugger.

The stable-retro harness only observes the machine once per vblank, but the
game's main loop is not locked to vblank. This module runs BlastEm headless
with a generated debugger script: breakpoints ("probes") print expressions
every time the 68000 reaches an address, so we get one record per loop
iteration (or per call, per interrupt...).

    from mw_harness.trace import Probe, run_trace
    events = run_trace([Probe(0x13F96, "vblank", ["[0xffca56].l"])], frames=900)

Each :class:`Event` carries the probe label, the 68000 master-clock ``cycle``
(-> ``frame`` = cycle // 896040 on NTSC) and the printed values.

How it works / requirements (Linux):
* BlastEm only runs its debugger on a terminal, so it is wrapped in
  ``script`` (util-linux) to get a pty.
* SDL runs with the ``dummy`` video driver + software renderer and a private
  config (``gl off``), so no display is needed and the user's BlastEm
  settings are never touched.
* ``m68k_divider`` (default 7 = stock NTSC 7.67 MHz) can be lowered to
  emulate an overclocked 68000 - used to find per-iteration game logic.

Debugger expression syntax: ``[addr].b/.w/.l`` reads memory, ``d0``-``d7``,
``a0``-``a7``, ``pc``, ``sr``, ``cycle``. BlastEm is GPL-3 and used as a tool only.
"""
from __future__ import annotations

import os
import re
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from .rom import REPO_ROOT, default_rom_path

BLASTEM = REPO_ROOT / "tools" / "blastem" / "blastem"
MCLK_PER_FRAME_NTSC = 3420 * 262  # master clocks per NTSC frame (896040)
BUTTON_BINDINGS = {b: f"gamepads.{{p}}.{b.lower()}" for b in
                   ["A", "B", "C", "X", "Y", "Z", "START", "MODE", "UP", "DOWN", "LEFT", "RIGHT"]}


@dataclass
class Probe:
    """A breakpoint that prints ``exprs`` (BlastEm syntax) and continues."""

    address: int
    label: str
    exprs: list[str] = field(default_factory=list)


@dataclass
class Event:
    label: str
    cycle: int
    values: list[int]

    @property
    def frame(self) -> int:
        return self.cycle // MCLK_PER_FRAME_NTSC


def _config(tmp: Path, m68k_divider: int, pad: str, four_way: bool = False) -> Path:
    """Private BlastEm config under ``tmp`` (used as $HOME). ``four_way``
    plugs EA's 4-Way Play into both ports with four ``pad`` controllers."""
    src = (BLASTEM.parent / "default.cfg").read_text()
    src = re.sub(r"(?m)^(\tgl) on", r"\1 off", src)
    src = re.sub(r"(?m)^(\tsync_source) audio", r"\1 video", src)
    src = re.sub(r"(?m)^(\tm68k_divider) \d+", rf"\1 {m68k_divider}", src)
    devices = "devices {\n\t\t1 gamepad6.1\n\t\t2 gamepad6.2"
    tap = "ea_multitap {\n\t\t1 gamepad6.1\n\t\t2 gamepad6.2\n\t\t3 gamepad6.3\n\t\t4 gamepad6.4"
    assert devices in src and tap in src, "unexpected BlastEm default.cfg layout"
    if four_way:
        src = src.replace(devices, "devices {\n\t\t1 ea_multitap_port_a\n\t\t2 ea_multitap_port_b")
    else:
        src = src.replace(devices, f"devices {{\n\t\t1 {pad}.1\n\t\t2 {pad}.2")
    src = src.replace(tap, "ea_multitap {\n" + "\n".join(f"\t\t{i} {pad}.{i}" for i in range(1, 5)))
    cfg_dir = tmp / ".config" / "blastem"  # BlastEm reads $HOME/.config/blastem
    cfg_dir.mkdir(parents=True)
    (cfg_dir / "blastem.cfg").write_text(src)
    return tmp


def blastem_env(tmp: Path) -> dict:
    """Environment for a headless BlastEm with its config under ``tmp``."""
    return dict(os.environ, HOME=str(tmp), XDG_CONFIG_HOME=str(tmp / ".config"),
                XDG_DATA_HOME=str(tmp / ".local/share"), SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy",
                SDL_RENDER_DRIVER="software")


def build_script(probes: list[Probe], frames: int, inputs=None, player: int = 1) -> str:
    """Debugger commands: probes, then input-driven frame stepping, then quit."""
    lines = []
    for i, p in enumerate(probes):
        fmt = " ".join(["%d"] * (len(p.exprs) + 1))
        args = " ".join(["cycle", *p.exprs])
        lines += [f"breakpoint 0x{p.address:x}", f"command {i}",
                  f'printf "@{p.label} {fmt}\\n" {args}', "continue", "end"]
    # Step to each input change, toggling bindings in between.
    held: set[str] = set()
    frame = 0
    changes = sorted({f for e in (inputs.events if inputs else []) for f in (e[0], e[1] + 1)} | {frames})
    for f in changes:
        f = min(f, frames)
        if f > frame:
            lines.append(f"frames {f - frame}")
            frame = f
        want = set(inputs.buttons_at(frame)) if inputs and frame < frames else set()
        for b in sorted(want - held):
            # NB: the command is "binddown" (BlastEm's help says "bindown") and
            # the binding name must be quoted, or it is parsed as an expression.
            lines.append(f'binddown "{BUTTON_BINDINGS[b.upper()].format(p=player)}"')
        for b in sorted(held - want):
            lines.append(f'bindup "{BUTTON_BINDINGS[b.upper()].format(p=player)}"')
        held = want
        if frame >= frames:
            break
    lines += ['printf "@END %d\\n" cycle', "quit"]
    return "\n".join(lines) + "\n"


def run_trace(probes: list[Probe], frames: int, inputs=None, rom: Path | None = None,
              m68k_divider: int = 7, pad: str = "gamepad3", timeout: float = 170.0) -> list[Event]:
    rom = Path(rom) if rom else default_rom_path()
    script = build_script(probes, frames, inputs)
    with tempfile.TemporaryDirectory(prefix="mw-trace-") as tmpd:
        tmp = _config(Path(tmpd), m68k_divider, pad)
        env = blastem_env(tmp)
        cmd = f"'{BLASTEM}' -d '{rom}'"
        proc = subprocess.run(["script", "-q", "-e", "-c", cmd, "/dev/null"], input=script.encode(),
                              capture_output=True, env=env, timeout=timeout)
    out = proc.stdout.decode(errors="replace")
    # Lines may start with debugger prompts ("> "); the echoed script also
    # contains "@END", so match only a printed record.
    if not re.search(r"^(?:>+ )*@END -?\d+", out, re.M):
        raise RuntimeError("BlastEm trace did not finish:\n" + out[-2000:])
    events = []
    wraps, last = 0, 0
    for m in re.finditer(r"^(?:>+ )*@(\S+) ([-\d ]+)\r?$", out, re.M):
        if m.group(1) == "END":
            continue
        nums = [int(x) for x in m.group(2).split()]
        # printf %d shows 32-bit signed values; the cycle counter is 64-bit
        # and monotonic, so unwrap it. Other values are made unsigned 32-bit.
        cyc = nums[0] & 0xFFFFFFFF
        if cyc < last:
            wraps += 1
        last = cyc
        events.append(Event(m.group(1), cyc + (wraps << 32), [v & 0xFFFFFFFF for v in nums[1:]]))
    return events
