"""The catalogue and the reference decoders against the original.

For each checkpoint (compare/fixtures/gfx_checkpoints.json: a tour script
and a moment relative to a screen visit) Genesis Plus GX plays the script
and the test compares the console's VRAM/CRAM with what the catalogue says
that screen loads (mw_harness.gfxcheck):

* ``loaded``: these tile entries sit at their VRAM base, tile for tile;
* ``shown_min``: share of the non-blank tiles the screen can show (cells of
  the displayed planes, on-screen sprites) that the catalogue accounts for:
  this screen's entries, entries left over from earlier screens, sprite and
  font pieces. Below ~0.98 where a screen draws sprite frames the tours
  never saw (players' frames depend on the game being played; Genesis Plus
  GX plays a different game than BlastEm after the faceoff);
* ``tiles_min``: the same over all of VRAM below the name tables (stale
  tiles included; the developer logo keeps the EA intro's tiles, which its
  own code builds and the catalogue doesn't cover);
* ``placed_min``: share of the name-table cells covered by this screen's
  catalogued rectangles that hold the expected words;
* ``sprites_min``: share of on-screen hardware sprites whose tiles equal a
  catalogued piece (validates the piece format);
* ``cram``: the palette builders reproduce CRAM exactly (``cram_lines`` /
  ``cram_ignore`` leave out colours animated by code).
"""
import json
from pathlib import Path

import pytest

from mw_harness import gfxcheck
from mw_harness.rom import Rom

ROOT = Path(__file__).resolve().parents[2]
CHECKPOINTS = json.loads((ROOT / "compare/fixtures/gfx_checkpoints.json").read_text())


@pytest.fixture(scope="module")
def setup(mlh_rom_path):
    pytest.importorskip("stable_retro")
    return Rom.load(mlh_rom_path).data, json.loads((ROOT / "game/data/rom_catalogue.json").read_text())


@pytest.mark.parametrize("cp", CHECKPOINTS, ids=lambda c: c["name"])
def test_checkpoint(setup, cp):
    rom, cat = setup
    screen, visit, offset = cp["at"]
    state = gfxcheck.snapshot((ROOT / "compare/scripts" / f"{cp['script']}.mwi").read_text(), screen, visit, offset)
    screen = cp.get("screen", screen)
    cov = gfxcheck.explain_vram(rom, cat, screen, state.vram)
    for key in cp["loaded"]:
        assert cov.loaded.get(key, 0) >= 0.95, (key, cov.loaded)
    assert cov.ratio >= cp["tiles_min"], (cov.ratio, [hex(t) for t in cov.missing[:20]])
    shown = gfxcheck.explain_vram(rom, cat, screen, state.vram, only=gfxcheck.referenced_tiles(state))
    assert shown.ratio >= cp["shown_min"], (shown.ratio, [hex(t) for t in shown.missing[:20]])
    if "placed_min" in cp:
        ok, total = gfxcheck.check_placements(rom, cat, screen, state.vram)
        assert ok / total >= cp["placed_min"], (ok, total)
    if "sprites_min" in cp:
        ok, total = gfxcheck.explain_sprites(rom, cat, state)
        assert total and ok / total >= cp["sprites_min"], (ok, total)
    assert gfxcheck.cram_mismatches(rom, screen, cp, state) == []
