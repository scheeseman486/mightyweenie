"""Recorder v3 of the simulation recordings (`mw_harness.sim_record`): the
tick sites and logs, the run specs and the v3 pad drivers on synthetic RAM.
No BlastEm needed (the ROM test skips without the ROM)."""
import inspect
import random
from pathlib import Path

from mw_harness import sim_record as sr
from mw_harness.rom import Rom

V2_SITES = {0x6136: 1, 0x51F4: 2, 0x1BF0: 3, 0x747A: 4, 0x749C: 5, 0x5E6A: 6, 0x922: 7, 0x5F16: 8}
V2_LOGS = ["ent", "col", "pk", "pen", "snd", "chg", "rn", "rr", "sk"]


def test_tick_sites_keep_v2_tags_and_are_unique():
    assert {a: t for a, t in sr.TICK_SITES.items() if t <= 8} == V2_SITES
    tags = list(sr.TICK_SITES.values())
    assert len(set(tags)) == len(tags) and sorted(tags) == list(range(1, len(tags) + 1))
    assert 0xF966 not in sr.TICK_SITES       # the elapsed wait loop: derived, never logged


def test_tick_sites_read_the_tick(mlh_rom_path):
    rom = Rom.load(mlh_rom_path).data
    for a in sr.TICK_SITES:
        op = rom[a:a + 6]
        # move.l / cmp.l $ca56.w, ...  or  btst #4, $ca59.w
        assert op[2:4] == b"\xca\x56" and op[:2] in (b"\x20\x38", b"\x2a\xb8") or op == b"\x08\x38\x00\x04\xca\x59", hex(a)


def test_logs():
    assert list(sr.LOGS)[:len(V2_LOGS)] == V2_LOGS
    assert {"ph", "sd", "vc"} <= set(sr.LOGS)
    addr, exprs, cond = sr.LOGS["sd"]
    assert addr == 0x13CEE and "0x13d7a" in cond     # $13D58's own call is in "snd"
    assert sr.TICK_LOG not in sr.LOGS


def test_run_specs_fit_record():
    sig = inspect.signature(sr.record)
    for name, spec in sr.RUNS3.items():
        spec = dict(spec)
        setup, passes = spec.pop("setup"), spec.pop("passes")
        spec.pop("base", None)                  # a v4 run's seed source (record_run)
        sig.bind(name, setup, passes, Path("x"), **spec)
        assert passes <= 6000 and spec.get("driver", "chase") in sr.DRIVERS
        assert name not in sr.RUNS
    assert sr.RUNS3["attract"]["setup"] == {}


# --- drivers on synthetic RAM ---------------------------------------------------

TEAM_A = sr.TEAMS[0]
GOALIE = TEAM_A + 0x6C + 0x76 * 5
CENTRE = TEAM_A + 0x6C


def ram(**fields) -> sr.Snap:
    data = bytearray(sr.SNAP[1])
    s = sr.Snap(data)

    def put(a, v, n):
        data[a - s.base:a - s.base + n] = (v & ((1 << 8 * n) - 1)).to_bytes(n, "big")
    put(TEAM_A + 0x66, 0, 1)                  # pad 0 on slot 0
    put(TEAM_A + 0x67, 0xFF, 1)
    put(sr.TEAMS[1] + 0x66, 0xFFFF, 2)
    for p, role in ((CENTRE, 0), (GOALIE, 5)):
        put(p + 0x32, 1, 2)                   # on the ice
        put(p + 0x69, role, 1)
    who = fields.get("human", GOALIE)
    put(who + 0x74, 4, 1)                     # human, the team's first pad
    if fields.get("carrier"):
        put(sr.PUCK + 0x3D, 1, 1)
        put(sr.PUCK + 0x24, fields["carrier"] & 0xFFFF, 2)
    put(sr.PHASE, fields.get("phase", 0), 2)
    put(CENTRE + 8, fields.get("y", 0) << 8, 4)
    return s


def test_goalie_driver_stands_still_with_the_puck():
    d = sr.GoalieDriver(0, random.Random(3))
    s = ram(carrier=GOALIE)
    outs = [d.step(s) for _ in range(59)]
    assert outs == [set()] * 59               # at least 60 passes without input


def test_goalie_driver_plans_aim_press_follow():
    d = sr.GoalieDriver(0, random.Random(1))
    s = ram(human=CENTRE, carrier=CENTRE, y=100)    # team A attacks up (+4 bit 1 clear): own half y > 0
    seq = []
    for _ in range(200):
        seq.append(d.step(s))
        if d.plan is not None:
            break
    assert d.plan is not None
    plan = [seq[-1]] + [d.step(s) for _ in range(d.plan[2])]
    pressed = [i for i, o in enumerate(plan) if o & {"B", "C"}]
    assert pressed and pressed[0] == 3 and all(o - {"B", "C"} == plan[0] for o in plan)


def test_pause_driver_taps_start_alone_then_lets_go():
    d = sr.PauseDriver(0, random.Random(2))
    s = ram(human=CENTRE, carrier=CENTRE)      # team A carries: B - TIMEOUT would be offered
    outs = [d.step(s) for _ in range(300)]
    i = outs.index({"START"})
    assert outs[i + 1] == set() and "START" not in outs[i + 2]
    assert d.choose(True) == "B"
    assert [d.choose(False) for _ in range(4)] == ["A", "START", "A", "START"]
    assert [d.choose(True) for _ in range(3)] == ["B", "B", "A"]     # B not ahead of A / Start


def test_match_driver_listens_without_buttons():
    d = sr.MatchDriver(0, random.Random(5))
    d.listen = True
    s = ram(human=CENTRE, phase=9)
    for _ in range(50):
        assert not d.step(s) & {"A", "B", "C", "START"}
    d.step(ram(human=CENTRE, phase=0))
    assert d.listen is None
