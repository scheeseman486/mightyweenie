"""Screen navigation models and tour drivers (plan 11, `mw_harness.screen_models`,
`mw_harness.tours`): the models against the code's facts, the tour's choices
on synthetic reads, the main menu's goal on a simulated menu, passwords.
No BlastEm needed; the ROM tests skip without the ROM."""
import random

import pytest

from mw_harness import screen_models as sm
from mw_harness import soak, tours
from mw_harness.playoffs import decode, decode_bits
from mw_harness.rom import Rom


def test_models_are_consistent():
    for scr, m in sm.MODELS.items():
        ids = [s.id for s in m.states]
        assert len(ids) == len(set(ids)), scr
        for s in m.states:
            labels = [e.label for e in s.edges]
            assert len(labels) == len(set(labels)), (scr, s.id)
            for e in s.edges:
                assert e.kind in ("stay", "detour", "exit"), (scr, s.id, e.label)
                assert set(e.buttons) <= set(sm.BUTTONS), (scr, s.id, e.label)
                assert e.hold > 0 and e.wait >= 0 and e.repeat >= 1
                if e.kind == "detour":
                    assert int(e.next.split()[1]) in m.exits, (scr, s.id, e.label)
        for name in m.reads:
            assert name not in sm.COMMON, (scr, name)


def test_scoreboard_menus_follow_the_code(mlh_rom_path):
    rom = Rom.load(mlh_rom_path)
    for scr in (12, 13, 14, 15, 16):
        menu = next(s for s in sm.model(scr).states if s.id == "menu")
        start = next(e for e in menu.edges if e.label == "START")
        assert start.next == f"screen {rom.u16(0x1C968 + 2 * (scr - 12))}"     # `$8E94`'s table
        assert any(e.label == "B" for e in menu.edges) == (scr < 15)          # no special plays after the game
        assert sm.model(scr).exits[0] == rom.u16(0x1C968 + 2 * (scr - 12))


def test_state_detection():
    def r(**kw):
        return sm.R({**{k: 0 for k in sm.COMMON}, **kw})
    sb = sm.model(12)
    assert sb.state(r(menu=0)).id == "intro" and sb.state(r(menu=1)).id == "menu"
    m17 = sm.model(17)
    assert m17.state(r(st=3)).id == "sequence"
    assert m17.state(r(st=0xFFFF)).id == "menu"
    assert m17.state(r(st=8)).id == "message"
    rp = sm.model(7)
    assert rp.state(r(play=0, cursor=1, frames=40)).id == "frozen"
    assert rp.state(r(play=0xFF, cursor=10, frames=40)).id == "playing"
    assert rp.state(r(play=0xFF, cursor=40, frames=40)).id == "at_end"
    st = sm.model(8)
    assert st.state(r(vs=0xFFB0, step=0)).id == "stats"
    assert st.state(r(vs=0xFFC0, step=2)).id == "scrolling"
    assert st.state(r(vs=0, step=0)).id == "player"
    fight = sm.model(18)
    assert fight.state(r(st=1, pA=0, pB=0xFFFF)).id == "fighting"
    assert fight.state(r(st=1, pA=0xFFFF, pB=0xFFFF)).id == "cpu_fight"
    assert fight.state(r(st=0xFFFF)).id == "card"


def test_special_plays_pages_by_pad_mode():
    sp = sm.model(10)
    plays, done = sm.PAGE_HANDLERS["plays"][1], sm.PAGE_HANDLERS["done"][1]
    def r(pads, dA, dB, hA, hB, track=None):
        x = sm.R({**{k: 0 for k in sm.COMMON}, "pads": pads, "dA": dA, "dB": dB, "hA": hA, "hB": hB})
        x.track = track
        return x
    assert sp.state(r(0, 0, 1, plays, 0x11520)).id == "A.plays"
    assert sp.state(r(1, 1, 0, done, plays)).id == "A.done"           # A's done page first
    assert sp.state(r(1, 1, 0, done, plays, track="B")).id == "B.plays"
    assert sm._special_pad("page", r(1, 1, 0, done, plays, track="B")) == 1
    assert sm._special_pad("page", r(4, 1, 0, done, plays, track="B")) == 2
    assert sp.state(r(0, 1, 1, done, 0x11520)).id == "wait"


def _reads(tour, **kw):
    return [kw.get(n, 0) for n in tour._names()]


def test_tour_takes_untaken_inputs_first_then_the_exit():
    t = tours.Tour(random.Random(3), detours=(1, 1))
    t.enter(12, 5)
    taken = []
    for _ in range(3000):
        t.tick(_reads(t, scr=12, menu=1))
        if t.log and (not taken or t.log[-1] is not taken[-1]):
            taken.append(t.log[-1])
        if t.log and t.log[-1][3] == "START":
            break
    labels = [x[3] for x in taken]
    assert labels[-1] == "START"
    assert labels.count("A") + labels.count("B") + labels.count("C") == 1     # one detour per gap
    t.rink()
    assert t.model is None and t.tick([]) == [set(), set(), set(), set()]


def test_tour_presses_and_releases():
    t = tours.Tour(random.Random(1))
    t.enter(17, 4)
    held_log = []
    for _ in range(200):
        held_log.append(t.tick(_reads(t, scr=17, st=0xFFFF, mpad=2)))
    pressed = [i for i, h in enumerate(held_log) if any(h)]
    assert pressed and pressed[0] >= sm.model(17).enter_delay - 1
    first = held_log[pressed[0]]
    assert sum(bool(h) for h in first) == 1
    run = 0
    for h in held_log[pressed[0]:]:
        if not any(h):
            break
        run += 1
    assert run == 6                                     # the edge's hold


def test_tour_sticky_watch_is_counted_once():
    t = tours.Tour(random.Random(0))
    t.counts["17:sequence:skip"] = 1                    # watch first
    t.counts["17:sequence:other_start"] = 1
    t.enter(17, 4)
    for _ in range(600):
        t.tick(_reads(t, scr=17, st=4, mpad=0))
    assert t.counts["17:sequence:watch"] == 1 and t.log[-1][3] == "watch"


def test_password_moves_follow_the_cursor_rules():
    def move(c, b):          # `$12454`
        if b == "LEFT":
            return c + (6 if c % 7 == 0 else -1)
        if b == "RIGHT":
            return c + (-6 if c % 7 == 6 else 1)
        if b == "UP":
            return c + (21 if c < 7 else -7)
        return c + (-21 if c > 20 else 7)
    for a in range(28):
        for b in range(28):
            c = a
            moves = sm.password_moves(a, b)
            for m in moves:
                c = move(c, m)
            assert c == b and len(moves) <= 5


def test_valid_passwords_are_taken(mlh_rom_path):
    rom = Rom.load(mlh_rom_path)
    data = bytes(rom.u8(i) for i in range(sm.ALPHABET + 28))
    alphabet = data[sm.ALPHABET:]
    r = random.Random(5)
    for _ in range(40):
        digits = soak.valid_password(r)
        assert decode(bytes(alphabet[d] for d in digits), data) is not None
        wrong = soak._wrong_password(r, 13)
        n = 0
        for d in reversed(wrong):
            n = n * 28 + d
        assert decode_bits(n >> 32, n & 0xFFFFFFFF) is None



class FakeMenu:
    """The main menu's rows as the code moves them (`$139A8` / `$139B2`,
    Left / Right in the menu's order, the period's minutes, the stadium
    following team A unless chosen)."""

    def __init__(self, rows: sm.MenuRows, setup: list[int]):
        self.rows, self.setup, self.row, self.chosen = rows, list(setup), 0, False

    def press(self, b: str) -> None:
        r = self.row
        if b in ("UP", "DOWN"):
            self.row = (self.rows.up if b == "UP" else self.rows.down)[r]
            return
        n = self.rows.counts[r]
        pos = self.rows.position(r, self.setup[r]) + (1 if b == "RIGHT" else -1)
        pos %= n
        self.setup[r] = self.rows.team_order[pos] if r < 2 else pos
        if r == 4:
            self.setup[5] = (3, 5, 8)[self.setup[4]]
        if r == 6:
            self.chosen = True
        if r == 0 and not self.chosen:
            self.setup[6] = self.setup[0]

    def reads(self, tour) -> list[int]:
        s = bytes(self.setup)
        vals = {"scr": 1, "row": self.rows.records[self.row], "s0": int.from_bytes(s[0:4], "big"),
                "s1": int.from_bytes(s[4:8], "big"), "s2": int.from_bytes(s[8:10], "big")}
        return [vals.get(n, 0) for n in tour._names()]


def test_menu_goal_sets_every_row(mlh_rom_path):
    rows = sm.MenuRows.from_rom(Rom.load(mlh_rom_path))
    assert rows.counts == [23, 23, 5, 5, 3, 0, 23, 2, 2, 5]
    for seed in range(1000, 1060):
        cfg = soak.config(seed)
        if cfg["menu"][3] != 0:
            continue
        menu = FakeMenu(rows, [22, 5, 0, 0, 0, 3, 22, 0, 0, 0])
        t = tours.Tour(random.Random(seed), goal=tours.MenuGoal(cfg["menu"], rows, ["browse"], browse=6))
        t.enter(1, 0)
        last = None
        for _ in range(5000):
            want = t.tick(menu.reads(t))
            if t.action is not None and t.action is not last and t.action.t == 0:
                last = t.action
                if t.action.edge.label == "START":
                    break
                if t.action.pad == 0:
                    menu.press(t.action.edge.buttons[0])
        assert last.edge.label == "START", seed
        for row, v in cfg["menu"].items():
            assert menu.setup[row] == v, (seed, row)


def test_soak_plan11_configs():
    for seed in range(soak.GEN2, soak.GEN2 + 300):
        c = soak.config(seed)
        assert c == soak.config(seed) and c["gen"] == 2
        m = c["menu"]
        assert set(m) <= set(sm.MENU_SETUP_ORDER) and m[3] in (0, 1, 2, 3)
        if 2 not in m:                                  # CPU vs CPU: the pad mode poked
            assert c["setup"] == {0xFFB0E0: 5} and m[3] == 0
        if m[3] in (1, 2):                              # one conference, the home stadium
            assert m[0] < 20 and m[0] // 10 == m[1] // 10 and m[0] != m[1] and 6 not in m
        if m[3] == 0:
            assert m[0] != m[1]
        assert c["stop_screens"] == ((1,) if m[3] == 0 else (3, 1))
        if m[3] == 3:
            assert c["passwords"][-1]["attempts"][-1]["valid"]
        soak.describe(c)
        args = soak.record_args(c)
        assert args["tour"]["menu"] == m
