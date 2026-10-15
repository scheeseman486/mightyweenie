"""Plan 36: the pass load model's timeline and the load probes' layout
(no recordings needed; the fit itself runs on local recordings:
``mw_harness load-fit --check``)."""
from mw_harness import load_fit as lf
from mw_harness import load_record as lr

F = lf.FRAME / lf.CPU          # 68000 cycles per frame


def _run(parts, t0=0.0, first=False, st=None):
    st = st if st is not None else [0, 0]
    return lf.run_pass(t0 * lf.CPU, 0, parts, st, hfun=lambda w: 29246, first=first)


def test_a_pass_spans_the_vblanks_its_work_crosses():
    assert _run((2.5 * F, 0.0, 0.0, (0, 0)), t0=4178.0)[1] == 2
    assert _run((1000.0, 0.0, 0.0, (0, 0)), t0=4178.0)[1] == 1, "the tick wait"


def test_the_dma_wait_holds_queued_rows():
    p = (0.2 * F, 5000.0, 0.98 * F, (0, 0))
    assert _run(p, t0=4178.0)[1] == 1
    assert _run((p[0], p[1], p[2], (64, 0)), t0=4178.0)[1] == 2


def test_the_fade_in_follows_the_first_pass():
    st = [0, 0]
    _run((0.5 * F, 0.0, 0.0, (0, 0)), first=True, st=st)
    assert st[1] == lf.FADE_VBLANKS - 1, "one VBlank (the tick wait) already in it"


def test_handler_cost():
    assert lf.handler(0, False, 0.0) == lf.H_BASE + lf.H_QUEUE + lf.H_FADE[0]
    assert round(lf.handler(1000, False, 0.0) - lf.handler(0, False, 0.0), 3) == 5806.0


def test_words_queued():
    sec = [12, 6, 12, 1, 8, 40]
    f = {"rows": 1, **{s: [0] * 6 for s in lf.DRAW_SECTIONS}, "draw_team_a": sec}
    assert lf.words(f) == (64, 16 * 8 + 4 * 12)
    f["rows"] = 34
    assert lf.words(f)[0] == 2048


def test_sound_probes_follow_the_port_counters():
    # MwSound68k.Work's order: the probes' tags 70-90 in order
    assert lf.SOUND_TAGS == sorted(lr.SOUND_PROBES)
    assert len(lr.SOUND_PROBES) == 21
    names = [lr.SOUND_PROBES[t][1] for t in lf.SOUND_TAGS]
    assert names[0] == "snd_channel" and names[-1] == "snd_driver"
