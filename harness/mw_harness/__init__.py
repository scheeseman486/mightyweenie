"""mightyweenie reference harness.

Runs the original Mutant League Hockey ROM headless in Genesis Plus GX (via
stable-retro) so the Godot reimplementation can be checked against it:
step frames with scripted controller input, then read back 68k work RAM,
Z80 RAM, VRAM, CRAM, VSRAM, VDP registers and 68k CPU registers.

The emulator is a *test tool only* (Genesis Plus GX is non-commercial
licensed); nothing in the shipped game links to it.
"""
from .rom import Rom, MLH_SHA1, default_rom_path
from .gpgx_state import MDState, parse_state
from .emulator import ReferenceEmulator, Buttons

__all__ = ["Rom", "MLH_SHA1", "default_rom_path", "MDState", "parse_state",
           "ReferenceEmulator", "Buttons"]
