"""Verify every savestate offset in mw_harness.gpgx_state against the core.

A synthetic ROM writes known values to work RAM, Z80 RAM, VRAM, CRAM, VSRAM,
VDP registers and the 68k data/address registers; we then decode the state
and check each one. If a stable-retro/GPGX upgrade moves anything, this is
the test that tells you which offset to fix.
"""
import synthrom

from mw_harness import ReferenceEmulator
from mw_harness.gpgx_state import STATE_VERSION


import pytest


@pytest.fixture
def run_synth(tmp_path):
    """Boot the synthetic ROM; the emulator is closed after the test."""
    emus = []

    def run(frames=10):
        rom = tmp_path / "synth.md"
        rom.write_bytes(synthrom.build())
        emus.append(ReferenceEmulator(rom))
        emus[-1].run(frames)
        return emus[-1]

    yield run
    for e in emus:
        e.close()


def test_version_string(run_synth):
    assert run_synth().save()[:16] == STATE_VERSION


def test_work_ram(run_synth):
    s = run_synth().state()
    for addr, val in synthrom.WORK_RAM.items():
        assert s.ram_u16(addr) == val, hex(addr)


def test_vdp_memories(run_synth):
    s = run_synth().state()
    assert [s.vram_u16(i * 2) for i in range(len(synthrom.VRAM))] == synthrom.VRAM
    assert list(s.cram[:len(synthrom.CRAM)]) == synthrom.CRAM
    assert list(s.vsram[:len(synthrom.VSRAM)]) == synthrom.VSRAM
    for reg, val in synthrom.VDP_REG_WRITES.items():
        assert s.vdp_regs[reg] == val, f"VDP reg {reg:#x}"


def test_z80_ram(run_synth):
    s = run_synth().state()
    for addr, val in synthrom.Z80_RAM.items():
        assert s.z80_ram[addr] == val


def test_m68k_registers(run_synth):
    s = run_synth().state()
    assert [s.m68k[f"D{i}"] for i in range(8)] == synthrom.DREGS
    assert [s.m68k[f"A{i}"] for i in range(7)] == synthrom.AREGS
    assert s.m68k["PC"] == synthrom.LOOP_PC


def test_palette_conversion():
    from mw_harness.gpgx_state import genesis_color_to_rgb8, gpgx_cram_to_genesis
    assert gpgx_cram_to_genesis(0x1FF) == 0x0EEE
    assert genesis_color_to_rgb8(0x0EEE) == (252, 252, 252)
    assert genesis_color_to_rgb8(0x0A42) == (36, 72, 180)


def test_savestate_roundtrip_is_deterministic(run_synth):
    emu = run_synth(frames=5)
    blob = emu.save()
    emu.run(5)
    a = emu.state().fingerprint()
    emu.load(blob)
    emu.run(5)
    assert emu.state().fingerprint() == a
