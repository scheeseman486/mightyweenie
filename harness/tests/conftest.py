import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))          # synthrom
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # mw_harness

from mw_harness.rom import default_rom_path  # noqa: E402


@pytest.fixture(scope="session")
def mlh_rom_path():
    p = default_rom_path()
    if not p.exists():
        pytest.skip(f"ROM not installed at {p} (see rom/README.md)")
    return p
