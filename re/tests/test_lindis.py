"""re/lindis.py: PC-relative movem targets (capstone resolves them 2 bytes early)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lindis import fix_movem_pc  # noqa: E402


def test_movem_d16_pc_target_is_relative_to_the_displacement_word():
    # $130E: movem.w $130A(pc), d0-d1 (4cba 0003 fff8): $1312 - 8
    assert fix_movem_pc(0x130E, bytes.fromhex("4cba0003fff8"), "$1308(pc), d0-d1") == "$130a(pc), d0-d1"


def test_movem_long_and_other_instructions():
    assert fix_movem_pc(0x1000, bytes.fromhex("4cfa00030010"), "$1012(pc), d0-d1") == "$1014(pc), d0-d1"
    assert fix_movem_pc(0x1000, bytes.fromhex("41fa0010"), "$1012(pc), a0") == "$1012(pc), a0"
