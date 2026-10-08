"""Tour drivers (plan 11): the pads on the screens between plays, walking
:mod:`screen_models`.

A :class:`Tour` is called once per tick (the recorder's VBlank stop) on
every screen outside the rink with that screen's reads (:meth:`Tour.exprs`)
and answers the buttons each pad holds. At each decision it detects the
screen's state and takes one of its inputs: inputs not taken yet in this
run first (then the least taken over earlier runs: ``bias``; ties at
random), until the visit's budget of actions is used up; then the exit.
Detours (the scoreboard's stats, special plays and instant replay) are
limited per gap between two rink visits. The main menu is goal-directed
(:class:`MenuGoal`: the run's setup through the rows, excursions to the team
description and the password screen first); the password screen types the
run's password plans.

Deterministic for a given seed, bias and emulation: a recording made later
from the same run takes the same inputs. ``Tour.log`` holds what was taken
(tick, screen, state, input), ``Tour.counts`` the counts by
``screen:state:input``.
"""
from __future__ import annotations

import random
from collections import Counter
from dataclasses import dataclass

from . import screen_models as sm
from .screen_models import Edge, R, HUMAN_PADS

#: no decision for this long on a screen: Start on pad 1 (a state the models miss)
STALL_TICKS = 900
#: the fight styles of :attr:`Tour.fight_styles` and their weights
FIGHT_STYLES = ("mixed", "idle", "forward")
FIGHT_STYLE_WEIGHTS = (2, 1, 1)
#: an input that leaves the screen waits for the fade-out (32 ticks) and the next screen
LEAVE_WAIT = 50
#: a sticky input (watching) gives up after this long in one state
STICKY_TICKS = 1500


@dataclass
class _Action:
    edge: Edge
    pad: int
    t: int = 0

    @property
    def total(self) -> int:
        e = self.edge
        if not e.buttons:
            return max(e.wait, 1)
        wait = max(e.wait, LEAVE_WAIT) if e.kind in ("exit", "detour") and not e.track else e.wait
        return e.repeat * e.hold + (e.repeat - 1) * e.gap + wait

    def pressed(self) -> bool:
        e = self.edge
        if not e.buttons:
            return False
        period = e.hold + e.gap
        return self.t < e.repeat * period - e.gap and self.t % period < e.hold


class MenuGoal:
    """The main menu's plan: excursions first ("browse": random moves,
    "team_description", "password_cancel"), then every row of ``target``
    (row -> value, in :data:`screen_models.MENU_SETUP_ORDER`), then Start on
    pad 1. A row that does not reach its value (a playoff rule) is left as it
    is after its count + 3 presses."""

    def __init__(self, target: dict[int, int], rows: sm.MenuRows, excursions=(), browse: int = 8):
        self.target = dict(target)
        self.rows = rows
        self.excursions = list(excursions)
        self.browse_left = browse
        self.tries: Counter = Counter()
        self.started = False

    def want(self) -> dict[int, int]:
        """The rows the menu is driven to now (an excursion's play mode first)."""
        if self.excursions and self.excursions[0] in ("team_description", "password_cancel"):
            return {3: 4 if self.excursions[0] == "team_description" else 3}
        return self.target

    def step(self, r: R, tour: "Tour") -> Edge | None:
        rows = self.rows
        setup = sm.menu_setup(r)
        row = rows.row_of(r.row)
        if row is None:                         # nothing highlighted: select one
            return Edge("select", ("DOWN",), wait=10)
        if self.excursions and self.excursions[0] == "browse":
            if self.browse_left <= 0:
                self.excursions.pop(0)
            else:
                self.browse_left -= 1
                rng = tour.rng
                b = rng.choice(["UP", "DOWN", "LEFT", "RIGHT", "LEFT", "RIGHT"])
                avoid = 2 not in self.target    # pad mode 5 (CPU vs CPU) cannot be set back by the menu
                if b in ("LEFT", "RIGHT") and avoid and row == 2:
                    b = "DOWN"
                if b in ("UP", "DOWN") and avoid and (rows.up if b == "UP" else rows.down)[row] == 2:
                    b = "LEFT" if row != 2 else "DOWN"
                pad = "p1"
                if b in ("LEFT", "RIGHT") and rng.random() < 0.2:
                    pad = "p3"                    # another pad edits team B (`$C7CA`)
                return Edge(f"browse_{b.lower()}{'_p3' if pad == 'p3' else ''}", (b,), wait=10, pad=pad)
        want = self.want()
        for target_row in sm.MENU_SETUP_ORDER:
            if target_row not in want or setup[target_row] == want[target_row]:
                continue
            if self.tries[target_row] > rows.counts[target_row] + 3:
                continue                        # cannot be reached (a playoff rule): left as it is
            if row != target_row:
                b = rows.path(row, target_row)[0]
                return Edge(f"row_{b.lower()}", (b,), wait=10)
            self.tries[target_row] += 1
            b = rows.step(row, setup[row], want[target_row])
            return Edge(f"value_{b.lower()}", (b,), wait=10)
        if self.excursions:
            self.excursions.pop(0)
            self.tries.clear()
            return Edge("start_excursion", ("START",), wait=60, kind="exit")
        self.started = True
        tour.menu_setup = setup
        return Edge("START", ("START",), wait=60, kind="exit")


def password_digits(d0: int, d1: int) -> list[int]:
    """The 13 alphabet indices of a password (`$12804`: base 28, least
    significant first)."""
    n = (d0 << 32) | d1
    out = []
    for _ in range(sm.PASSWORD_LEN):
        n, r = divmod(n, 28)
        out.append(r)
    return out


class Tour:
    """The pads on the screens between plays (see the module doc).
    ``passwords``: plans for the password screen visits, in order: each
    {"attempts": [{"digits": [13 alphabet indices] (fewer: refused as
    short), "valid": bool, "mistake": i (one symbol too many after the
    i-th, taken back with B), "cancel": bool (C: back to the main menu)}]}."""

    def __init__(self, rng: random.Random, *, goal: MenuGoal | None = None,
                 passwords: list[dict] | None = None, bias: dict[str, int] | None = None,
                 detours: tuple[int, int] = (0, 2), fight_styles: bool = False, pages_both: bool = False):
        self.rng = rng
        #: each fight visit picks a style for the people's fighters (mixed /
        #: idle / forward: :func:`screen_models.fight_policy`); off: always mixed
        self.fight_styles = fight_styles
        self.fight_style = "mixed"
        #: screen 10 with two pages: each visit picks the page played first
        #: (A or B), and a page's done state has a budget of its own (Down
        #: goes back, Start stays); off: A first, done pages only finish
        self.pages_both = pages_both
        self.page_first = "A"
        self.goal = goal
        self.passwords = list(passwords or [])
        self.bias = bias or {}
        self.detour_range = tuple(detours)
        self.counts: Counter = Counter()
        self.log: list[list] = []
        self.menu_setup: list[int] | None = None   # the setup bytes when the menu's Start was pressed
        self.screen: int | None = None
        self.prev = -1
        self.model: sm.Screen | None = None
        self.detours = rng.randint(*self.detour_range)
        self._reset_visit()

    # --- the recorder's calls -------------------------------------------------------------

    def exprs(self) -> list[str]:
        """BlastEm expressions to read at each tick (common, then the screen's)."""
        reads = {**sm.COMMON, **(self.model.reads if self.model else {})}
        return [reads[n] for n in self._names()]

    def enter(self, screen: int, prev: int = -1) -> None:
        """``$FFB05E`` became ``screen`` (the dispatcher called it)."""
        self.screen = screen
        self.prev = prev
        self.model = sm.model(screen)
        self._reset_visit()
        self.fight_style = "mixed"
        if self.fight_styles and screen == 18:
            self.fight_style = self.rng.choices(FIGHT_STYLES, FIGHT_STYLE_WEIGHTS)[0]
        self.page_first = "A"
        if self.pages_both and screen == 10:
            self.page_first = self.rng.choice("AB")

    def rink(self) -> None:
        """A rink visit starts: a new gap, a new allowance of detours."""
        self.screen = None
        self.model = None
        self.detours = self.rng.randint(*self.detour_range)
        self._reset_visit()

    def tick(self, values: list[int]) -> list[set[str]]:
        """One tick: the buttons each of the 4 pads holds now."""
        held: list[set[str]] = [set(), set(), set(), set()]
        if self.model is None:
            return held
        self.t += 1
        if self.action is not None:
            self.action.t += 1
            if self.action.t < self.action.total:
                return self._held(held)
            self.action = None
        if self.t < self.model.enter_delay:
            return held
        r = R(dict(zip(self._names(), values)), tour=self)
        if self.track is None and self.model.start_track:
            self.track = self.model.start_track(r)
        r.track = self.track
        state = self.model.state(r)
        edge = self._choose(state, r) if state is not None else None
        if edge is None:
            if self.t - self.last_decision <= STALL_TICKS:
                return held
            edge = Edge("stall_start", ("START",), wait=30)
            self._note(sm.State("?", lambda r: True), edge, r)
        self.last_decision = self.t
        self.action = _Action(edge, self._pad(edge.pad, r))
        if edge.track is not None:
            self.track = edge.track
        return self._held(held)

    # --- choices -------------------------------------------------------------------------

    def visit_taken(self, label: str) -> bool:
        return label in self.visit_labels

    def _choose(self, state: sm.State, r: R) -> Edge | None:
        key = (self.screen, state.id)
        if self.sticky is not None and self.sticky[0] == key and self.t - self.sticky[2] < STICKY_TICKS:
            return self.sticky[1]
        self.sticky = None
        e = state.choose(state, r) if state.choose is not None else self._pick(state, r)
        if e is None:
            return None
        self._note(state, e, r)
        if e.sticky:
            self.sticky = (key, e, self.t)
        return e

    def _pick(self, state: sm.State, r: R) -> Edge | None:
        cands = [e for e in state.edges if e.when is None or e.when(r)]
        if not cands:
            return None
        group = state.group
        if self.pages_both and state.id.endswith(".done"):
            group = state.id                    # its own budget: back / stay before finishing
        if group not in self.left:
            self.left[group] = self.rng.randint(*self.model.budget)
        stay = [e for e in cands if e.kind == "stay"]
        detour = [e for e in cands if e.kind == "detour"] if self.detours > 0 else []
        exits = [e for e in cands if e.kind == "exit"]
        if self.left[group] > 0 and (stay or detour):
            pool = stay + detour
        elif exits:
            pool = exits
        else:
            pool = stay or [e for e in cands if e.kind == "detour"]
        e = min(pool, key=lambda e: (self.counts[self._key(state, e)], self.bias.get(self._key(state, e), 0),
                                     self.rng.random()))
        if e.kind == "detour":
            self.detours -= 1
        elif e.kind == "stay":
            self.left[group] -= 1 if e.buttons else 0.25     # waits cost less
        return e

    def _key(self, state: sm.State, e: Edge) -> str:
        return f"{self.screen}:{state.id}:{e.label}"

    def _note(self, state: sm.State, e: Edge, r: R) -> None:
        self.counts[self._key(state, e)] += 1
        self.visit_labels.add(e.label)
        self.log.append([r.get("tick"), self.screen, state.id, e.label])

    def _pad(self, name: str, r: R) -> int:
        if name in ("p1", "p2", "p3", "p4"):
            return int(name[1]) - 1
        if self.model and self.model.pad:
            p = self.model.pad(name, r)
            if p is not None:
                return p
        if name == "any":
            return self.rng.choice(HUMAN_PADS.get(r.get("pads"), (0,)))
        if name == "other":
            return 1
        return 0

    # --- the main menu and the password screen ---------------------------------------------

    def menu_step(self, r: R) -> Edge | None:
        if self.goal is None:
            return Edge("START", ("START",), wait=60, kind="exit")
        return self.goal.step(r, self)

    def password_step(self, r: R) -> Edge | None:
        if self.pw_queue is None:
            self.pw_queue = self._password_queue()
        if not self.pw_queue:
            return None
        return self.pw_queue.pop(0)

    def _password_queue(self) -> list[Edge]:
        """The presses of the next password plan: each attempt deletes what
        is typed (B), moves the cursor to each symbol (D-pad) and adds it
        (A), sometimes types one too many and takes it back, then Start;
        a valid one ends on the bracket, "cancel" leaves with C."""
        if not self.passwords:
            return [Edge("pw_start", ("START",), wait=90, track="bracket")]
        plan = self.passwords.pop(0)
        out: list[Edge] = []
        cursor = 0
        typed = 0

        def press(b: str, wait: int = 6) -> Edge:
            return Edge(f"pw_{b.lower()}", (b,), hold=4, wait=wait)

        for att in plan["attempts"]:
            out += [press("B")] * typed
            typed = 0
            for i, d in enumerate(att["digits"]):
                out += [press(m) for m in sm.password_moves(cursor, d)]
                cursor = d
                out.append(press("A"))
                typed += 1
                if att.get("mistake") == i:
                    out += [press("A"), press("B")]
            if att.get("cancel"):
                out.append(Edge("pw_cancel", ("C",), wait=90, kind="exit"))
                return out
            if att.get("valid"):
                out.append(Edge("pw_start_valid", ("START",), wait=90, track="bracket"))
                return out
            out.append(Edge("pw_start_refused", ("START",), wait=20))
        return out

    # --- internals ------------------------------------------------------------------------

    def _names(self) -> list[str]:
        return [*sm.COMMON, *(self.model.reads if self.model else {})]

    def _reset_visit(self) -> None:
        self.t = 0
        self.last_decision = 0
        self.action: _Action | None = None
        self.track: str | None = None
        self.left: dict[str, float] = {}
        self.sticky = None
        self.visit_labels: set[str] = set()
        self.pw_queue: list[Edge] | None = None

    def _held(self, held: list[set[str]]) -> list[set[str]]:
        a = self.action
        if a is not None and a.pressed():
            held[a.pad] = set(a.edge.buttons)
        return held
