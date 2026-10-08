"""mw_harness.title_timeline: milestone parsing and the committed fixture."""
import json

from mw_harness.title_timeline import FIXTURE, _timeline, dumps
from mw_harness.trace import MCLK_PER_FRAME_NTSC, Event


def ev(label, tick, *more):
    return Event(label, tick * MCLK_PER_FRAME_NTSC, [tick, *more])


def test_relative_ticks_pages_and_second_visit_ignored():
    events = [ev("logo_end", 3), ev("entry", 10), ev("logo_start", 14), ev("page", 20, 18),
              ev("page_fade_in", 21), ev("page_fade_out", 30), ev("page", 40, 17), ev("menu", 50),
              ev("entry", 60), ev("logo_start", 64)]
    t = _timeline(events)
    assert t["logo_start"] == 4 and t["menu"] == 40 and "logo_end" not in t
    assert t["pages"] == [[10, 11, 20], [30]]
    assert t["entry_frame"] == 10


def test_fixture_shape():
    d = json.loads(FIXTURE.read_text())
    assert dumps(d) == FIXTURE.read_text()
    run = d["no_input"]
    assert len(run["pages"]) == 19 and all(len(p) == 3 for p in run["pages"])
    order = ["entry", "logo_start", "logo_end", "title_start", "title_fade_in", "title_fade_out",
             "credits", "credits_end", "credits_done"]
    ticks = [run[k] for k in order]
    assert ticks == sorted(ticks) and run["menu"] == run["credits_done"]
    skip = d["skips"]["events"]
    assert skip["logo_end"] < run["logo_end"] and skip["menu"] < run["menu"]
