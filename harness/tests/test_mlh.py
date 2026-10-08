"""Checks against the real ROM (skipped when rom/ is empty)."""
import hashlib

from mw_harness import ReferenceEmulator, Rom


def test_rom_identity(mlh_rom_path):
    rom = Rom.load(mlh_rom_path)
    assert rom.is_mlh
    assert rom.system == "SEGA GENESIS"
    assert rom.product_code == "GM T-50766 -00"
    assert rom.header_checksum == rom.computed_checksum() == 0x47EE
    assert rom.reset_pc == 0x200


def test_boot_is_deterministic(mlh_rom_path):
    """Two cold boots with identical (empty) input must match bit for bit."""
    runs = []
    for _ in range(2):
        with ReferenceEmulator(mlh_rom_path) as emu:
            emu.run(900)
            s = emu.state()
            runs.append((s.work_ram, s.vram, s.cram, emu.screen().tobytes()))
    assert runs[0] == runs[1]


def test_reaches_title_screen(mlh_rom_path):
    """By frame 900 the title screen palette is loaded and VRAM is populated.

    Golden values captured from the first harness run (2026-10-05); they pin
    harness behaviour, not game understanding.
    """
    with ReferenceEmulator(mlh_rom_path) as emu:
        emu.run(900)
        s = emu.state()
        screen = emu.screen().tobytes()
    assert [f"{c:04X}" for c in s.cram[:4]] == ["0000", "0CC0", "0880", "0660"]
    assert sum(1 for b in s.vram if b) > 20000
    assert hashlib.sha1(screen).hexdigest() == TITLE_SCREEN_SHA1


TITLE_SCREEN_SHA1 = "fdc38ef67830d769501a1200a7b71873d758dbad"
