"""Navigation models of the original's screens (plan 11).

Per screen: the RAM the state is read from, the states (detected from those
reads at any tick), the inputs each state takes (an :class:`Edge`: the
buttons, how long they are held, on which pad, where they lead) and the
exits. :mod:`tours` walks these models in the soak - inputs not taken yet
first, then the exit the run wants - so every option, page and control of
the screens between plays (and the menus around a match) is exercised.

Sources: docs/re/menus.md (plan 06: main menu, team description, matchup,
playoffs, passwords), docs/re/screens.md, plan 11's research notes
(docs/re/scoreboards.md, stats.md, special-plays.md, fight.md, referee.md, replay.md): scoreboards 12-17, the
instant replay 7, the stats 8 / 9, special plays 10, the fight 18 and the
referee 19. Locals of screen handlers sit at fixed RAM addresses because
their stack frame does (a6 = `$FFFFF8` for 12-19, `$FFFFF4` for 7): they
mean something only while ``$FFB05E`` holds that screen.

Edge kinds: ``stay`` (the screen goes on: a cursor move, a page, a wait),
``detour`` (to another screen that comes back: the scoreboard's stats,
special plays, instant replay - limited per gap between two rink visits)
and ``exit`` (leaves the screen, or ends a page: taken when the visit's
budget of actions is used up).

Nothing here is ROM content: addresses, counts and RAM layouts only; the
menu's tables are read from the ROM given.
"""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

BUTTONS = ("UP", "DOWN", "LEFT", "RIGHT", "B", "C", "A", "START")
DPAD = ("UP", "DOWN", "LEFT", "RIGHT")
#: Pads a person plays on per pad mode `$FFB0E0` (0-based; mode 5, CPU vs CPU,
#: still reads pad 1 on the screens between plays).
HUMAN_PADS = {0: (0,), 1: (0, 1), 2: (0, 1), 3: (0, 1, 2), 4: (0, 1, 2, 3), 5: (0,)}

#: Read at every decision, whatever the screen.
COMMON = {"scr": "[0xffb05e].w", "tick": "[0xffca56].l", "pads": "[0xffb0e0].b",
          "mode": "[0xffb0e1].b", "penalties": "[0xffb0e5].b", "reserves": "[0xffb0e6].b",
          "phase": "[0xffc60a].w"}


def s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def s32(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


class R:
    """One decision's reads (by name), the visit's tracked page and the tour."""

    def __init__(self, values: dict[str, int], track: str | None = None, tour=None):
        self.__dict__.update(values)
        self.track = track
        self.tour = tour

    def get(self, name: str, default: int = 0) -> int:
        return self.__dict__.get(name, default)


@dataclass(frozen=True)
class Edge:
    """An input in a state. ``buttons`` are pressed together on ``pad`` for
    ``hold`` ticks (``repeat`` times, ``gap`` ticks apart), then the tour
    waits ``wait`` ticks before its next decision (no buttons: a plain wait).
    ``pad``: ``p1``-``p4``, ``control`` (the screen's controlling pad),
    ``other`` (a pad that is not it), ``page`` (screen 10's acting page),
    ``fighter`` (a human fighter's), ``any`` (a person's pad at random).
    ``when``: only offered when true. ``track``: the page the visit is on
    afterwards (screens whose page is not in RAM). ``sticky``: once chosen,
    repeated without counting while the state lasts (watching something to
    its end)."""
    label: str
    buttons: tuple[str, ...] = ()
    hold: int = 6
    wait: int = 8
    pad: str = "p1"
    kind: str = "stay"
    next: str = ""
    when: Callable[[R], bool] | None = None
    repeat: int = 1
    gap: int = 6
    track: str | None = None
    sticky: bool = False
    effect: str = ""


@dataclass(frozen=True)
class State:
    id: str
    detect: Callable[[R], bool]
    edges: tuple[Edge, ...] = ()
    #: a policy instead of the edges: (state, r) -> Edge or None (the tour's rng, goal...)
    choose: Callable | None = None
    note: str = ""

    @property
    def group(self) -> str:
        """Budgets are per group (screen 10's pages: ``A.`` / ``B.``)."""
        return self.id.split(".")[0] if "." in self.id else ""


@dataclass(frozen=True)
class Screen:
    ids: tuple[int, ...]
    name: str
    reads: dict[str, str]
    states: tuple[State, ...]
    exits: tuple = ()
    #: ticks after the screen is called before the first input (loading, fade in)
    enter_delay: int = 30
    #: actions per visit (per group) before the exits: (low, high)
    budget: tuple[int, int] = (2, 6)
    #: the visit's first tracked page (screens without a page in RAM)
    start_track: Callable[[R], str] | None = None
    #: pad names -> pad (0-3) for this screen (control, page, fighter)
    pad: Callable[[str, R], int | None] | None = None
    note: str = ""

    def state(self, r: R) -> State | None:
        for s in self.states:
            if s.detect(r):
                return s
        return None


def _w(addr: int) -> str:
    return f"[0x{addr:x}].w"


def _b(addr: int) -> str:
    return f"[0x{addr:x}].b"


def _l(addr: int) -> str:
    return f"[0x{addr:x}].l"


# --- scoreboards 12-17 (`$8CF4`, `$E612`; a6 = $FFFFF8) ---------------------------------

SB_MENU = 0xFFFFEC        # 12-16: -$C menu shown
SB_PANEL = 0xFFFFF2       # 12-16: panel size 6..26 (17: its state)
MSG_STATE = 0xFFFFF2      # 17: -6 state 0-9, -1 menu mode
MSG_LOCK = 0xFFFF9C       # 17: -$5C input lockout (180 with phase >= 12)
MSG_PAD = 0xFFFFC4        # 17: -$34 2 * the pad whose Start skips
MSG_SHOWN = 0xFFFFEA      # 17: -$E menu shown
ZAMBONI_WHIPS = 0xFFC4F4  # 14: whip cracks queued


def _special_plays_ok(r: R) -> bool:
    """Screen 10's pages need people's pads: in pad mode 5 (CPU vs CPU, the
    attract demo's) its page table reads past its end and no page ever
    finishes - the original never goes there without a person."""
    return r.pads != 5


def _scoreboard_menu(screen: int) -> tuple[Edge, ...]:
    exit_to = {12: 5, 13: 4, 14: 4, 15: 1, 16: 11}[screen]
    edges = [Edge("START", ("START",), kind="exit", next=f"screen {exit_to}"),
             Edge("A", ("A",), kind="detour", next="screen 8"),
             Edge("C", ("C",), kind="detour", next="screen 7")]
    if screen < 15:
        edges.append(Edge("B", ("B",), kind="detour", next="screen 10", when=_special_plays_ok))
    else:
        edges.append(Edge("B_nothing", ("B",), next="menu", effect="no special plays after the game"))
    if screen == 14:
        edges += _whips()
    return tuple(edges)


def _whips() -> list[Edge]:
    return [Edge("whip", ("UP",), next="same", effect="the rider cracks his whip ($F224)"),
            Edge("whip3", ("LEFT",), hold=3, repeat=3, gap=4, wait=20, next="same",
                 effect="three cracks queued ($FFC4F4)")]


def _scoreboard(screen: int) -> Screen:
    intro = [Edge("any", ("C",), next="menu", effect="any new Start/A/B/C shows the menu"),
             Edge("wait600", wait=620, next="menu", effect="the menu after 600 ticks")]
    if screen == 14:
        intro += _whips()
    names = {12: "goal scoreboard", 13: "scoreboard 13 (unused)", 14: "period scoreboard (Zamboni)",
             15: "game over", 16: "playoff game over"}
    return Screen(
        (screen,), names[screen], {"menu": _w(SB_MENU), "panel": _w(SB_PANEL), "whips": _w(ZAMBONI_WHIPS)},
        (State("intro", lambda r: r.menu == 0, tuple(intro),
               note="12: the scorer's comment; 14: the Zamboni; 15/16: celebrations"),
         State("menu", lambda r: r.menu != 0, _scoreboard_menu(screen))),
        exits={12: (5, 7, 8, 10), 13: (4, 7, 8, 10), 14: (4, 7, 8, 10), 15: (1, 7, 8), 16: (11, 7, 8)}[screen],
        budget=(1, 3) if screen != 14 else (2, 5),
        note="returns from 7/8/10 come back with the menu shown")


def _msg_pad(name: str, r: R) -> int | None:
    control = (r.mpad & 0xFFFF) // 2
    if name == "control":
        return control if control < 4 else 0
    if name == "other":
        return 1 if control == 0 else 0
    return None


SCOREBOARD_17 = Screen(
    (17,), "message scoreboard",
    {"st": _w(MSG_STATE), "lock": _w(MSG_LOCK), "mpad": _w(MSG_PAD), "shown": _w(MSG_SHOWN)},
    (State("sequence", lambda r: 0 <= s16(r.st) <= 7,
           (Edge("watch", wait=60, sticky=True, next="menu", effect="the called players walk to the box"),
            Edge("skip", ("START",), pad="control", next="menu", effect="the rest go to the box at once"),
            Edge("other_start", ("START",), pad="other", next="sequence", effect="ignored: not the skip pad")),
           note="penalty / fight result: per called player the panel, the walk, $A2A4"),
     State("menu", lambda r: s16(r.st) == -1,
           (Edge("START", ("START",), kind="exit", next="screen 5"),
            Edge("A", ("A",), kind="detour", next="screen 8"),
            Edge("B", ("B",), kind="detour", next="screen 10", when=_special_plays_ok),
            Edge("C", ("C",), kind="detour", next="screen 7"))),
     State("message", lambda r: s16(r.st) in (8, 9),
           (Edge("wait", wait=60, next="message", effect="the 180-tick lockout"),
            Edge("start_locked", ("START",), pad="control", when=lambda r: 0 < s16(r.lock),
                 next="message", effect="input not read during the lockout"),
            Edge("START", ("START",), pad="control", kind="exit", when=lambda r: s16(r.lock) <= 0,
                 next="screen 5 (new referee) / 15, 16 (forfeit)")),
           note="new referee (phase 12) or forfeit (phase 13): no menu")),
    exits=(5, 7, 8, 10, 15, 16), budget=(1, 3), pad=_msg_pad)


# --- instant replay 7 (`$FBFA` / `$9DD0`; a6 = $FFFFF4) ----------------------------------

REPLAY_PAD = 0xFFFFE0     # -$14: 2 * the controlling pad
REPLAY_PLAY = 0xFFFFE2    # -$12.b: playing
REPLAY_CURSOR = 0xFFFFEA  # -$A: frames before the read offset
RING_FRAMES = 0xFFC2CE


def _replay_pad(name: str, r: R) -> int | None:
    control = (r.rpad & 0xFFFF) // 2
    if name == "control":
        return control if control < 4 else 0
    if name == "other":
        return 1 if control == 0 else 0
    return None


_REPLAY_COMMON = (Edge("rewind", ("A",), hold=60, pad="control", next="frozen", effect="held A: one frame back per max(e/2, 1) ticks"),
                  Edge("slow", ("B",), hold=90, pad="control", next="frozen", effect="held B: one frame per 2e ticks"),
                  Edge("START", ("START",), pad="control", kind="exit", next="screen 6 / the scoreboard"))

INSTANT_REPLAY = Screen(
    (7,), "instant replay",
    {"play": _b(REPLAY_PLAY), "cursor": _w(REPLAY_CURSOR), "frames": _w(RING_FRAMES), "rpad": _w(REPLAY_PAD)},
    (State("frozen", lambda r: r.play == 0,
           (*_REPLAY_COMMON,
            Edge("play", ("C",), pad="control", next="playing"),
            Edge("tap_b", ("B",), hold=3, pad="control", next="frozen", effect="freeze frame: the shown frame again"),
            Edge("tap_a", ("A",), hold=3, pad="control", next="frozen"),
            Edge("dpad", ("RIGHT",), hold=20, pad="control", next="frozen", effect="nothing (the pan is dead code)"),
            Edge("other_pad", ("C",), pad="other", next="frozen", effect="ignored: one pad only"),
            Edge("start_held_b", ("B", "START"), hold=10, pad="control", next="frozen",
                 effect="Start ignored while B is held"))),
     State("playing", lambda r: r.play != 0 and r.cursor < r.frames,
           (*_REPLAY_COMMON,
            Edge("watch", wait=30, sticky=True, next="at_end"),
            Edge("C_again", ("C",), pad="control", next="playing"))),
     State("at_end", lambda r: r.play != 0 and r.cursor >= r.frames,
           (*_REPLAY_COMMON,))),
    exits=(6, 12, 13, 14, 15, 16, 17), budget=(2, 6), enter_delay=20, pad=_replay_pad,
    note="the controlling pad: A in the pause menu / C on the scoreboard")


# --- game stats 8 and player stats 9 (`$CB56`, `$D168`) -------------------------------------

STATS_SCROLL = 0xFFB0DA   # plane A vscroll: 8 -80..-16, 9 0
STATS_STEP = 0xFFC3FC     # 8: scroll counter (pads not read while != 0)
STATS_PAGE = 0xFFC400     # 9: page 0-4
STARFIELD_ON = 0xFFC405

_STAR = (Edge("B", ("B",), next="same", effect="starfield stops / restarts"),
         Edge("C", ("C",), next="same", effect="starfield turns (when running)"))

STATS = Screen(
    (8,), "game stats / player stats",
    {"vs": _w(STATS_SCROLL), "step": _w(STATS_STEP), "page": _w(STATS_PAGE), "star": _b(STARFIELD_ON)},
    (State("scrolling", lambda r: r.vs != 0 and r.step != 0, (Edge("wait", wait=4),)),
     State("stats", lambda r: r.vs != 0,
           (Edge("down", ("DOWN",), hold=4, wait=20, next="stats"),
            Edge("up", ("UP",), hold=4, wait=20, next="stats"),
            Edge("right", ("RIGHT",), hold=4, wait=20, next="stats"),
            Edge("left", ("LEFT",), hold=4, wait=20, next="stats"),
            Edge("hold_down", ("DOWN",), hold=50, wait=20, next="stats", effect="held: step after step"),
            Edge("A_held_dpad", ("DOWN", "A"), hold=4, wait=20, next="stats", effect="A ignored while the D-pad is held"),
            *_STAR,
            Edge("A", ("A",), wait=40, next="player", effect="player stats (screen 9, inside 8)"),
            Edge("START", ("START",), kind="exit", next="the scoreboard"))),
     State("player", lambda r: r.vs == 0,
           (Edge("down", ("DOWN",), wait=12, next="player", effect="next page"),
            Edge("up", ("UP",), wait=12, next="player", effect="previous page"),
            Edge("A", ("A",), wait=12, next="player", effect="the other team"),
            Edge("left", ("LEFT",), next="player", effect="nothing"),
            *_STAR,
            Edge("START", ("START",), kind="exit", wait=50, next="stats (set up again)")))),
    exits=(12, 13, 14, 15, 16, 17), budget=(3, 9))


# --- special plays 10 (`$11A18`; page objects A $FFC64C, B $FFC6DC) -------------------------

PAGE = {"A": 0xFFC64C, "B": 0xFFC6DC}
PAGE_HANDLERS = {"plays": (0x117B4, 0x1180C), "positions": (0x11896, 0x118CA),
                 "subst": (0x1161E, 0x1174A), "done": (0x11914, 0x1192C), "idle": (0x1145A, 0x11520)}
#: page B's pad per pad mode (none in 0 / 2: the idle page)
PAGE_B_PAD = {1: 1, 3: 2, 4: 2}


def _page(r: R, p: str) -> str:
    h = r.get(f"h{p}") & 0xFFFFFF
    return next((k for k, v in PAGE_HANDLERS.items() if h in v), "?")


def _acting(r: R) -> str | None:
    """The page the tour plays: A until done; then B (when it has a pad) once
    the tour has finished with A's done page. With the tour's
    ``page_first`` "B" (:attr:`tours.Tour.pages_both`), B first: B until
    done and the tour finished with B's done page (then A)."""
    tour = getattr(r, "tour", None)
    if getattr(tour, "page_first", "A") == "B" and r.pads in PAGE_B_PAD:
        if r.get("dB") == 0 or (r.track != "A" and r.get("dA") == 0):
            return "B"
        return "A" if r.get("dA") == 0 else None
    if r.get("dA") == 0:
        return "A"
    if r.pads in PAGE_B_PAD and r.get("dB") == 0:
        return "B" if r.track == "B" else "A"
    return None


def _special_pad(name: str, r: R) -> int | None:
    if name == "page":
        return 0 if _acting(r) == "A" else PAGE_B_PAD.get(r.pads, 0)
    return None


def _page_states(p: str) -> list[State]:
    # passes take 3-8 ticks here: presses are held over a whole pass
    PEdge = lambda *a, **k: Edge(*a, **{"hold": 10, **k})
    act = lambda r, p=p: _acting(r) == p
    cur = lambda r, p=p: r.get(f"c{p}")
    plays = State(f"{p}.plays", lambda r, p=p: act(r) and _page(r, p) == "plays",
                  (PEdge("up", ("UP",), pad="page", wait=12), PEdge("down", ("DOWN",), pad="page", wait=12),
                   PEdge("left", ("LEFT",), pad="page", wait=12), PEdge("right", ("RIGHT",), pad="page", wait=12),
                   PEdge("nasty", ("A",), pad="page", kind="exit", wait=20, next="positions / done",
                         effect="team +$4A5 = the period's nasty play"),
                   PEdge("special", ("B",), pad="page", kind="exit", wait=20, next="positions / done",
                         effect="team +$4A5 = the highlighted special play"),
                   PEdge("phony", ("C",), pad="page", kind="exit", wait=20, next="positions / done",
                         effect="team +$4A5 = 0"),
                   PEdge("START", ("START",), pad="page", kind="exit", wait=20, next="positions / done",
                         effect="nothing armed")))
    positions = State(f"{p}.positions", lambda r, p=p: act(r) and _page(r, p) == "positions",
                      (PEdge("up", ("UP",), pad="page", wait=12), PEdge("down", ("DOWN",), pad="page", wait=12),
                       PEdge("left", ("LEFT",), pad="page", wait=12), PEdge("right", ("RIGHT",), pad="page", wait=12),
                       PEdge("choose", ("A",), pad="page", wait=30, when=lambda r, c=cur: c(r) <= 5,
                             next="subst", effect="the position's substitution list"),
                       PEdge("choose_c", ("C",), pad="page", wait=30, when=lambda r, c=cur: c(r) <= 5, next="subst"),
                       PEdge("plays", ("B",), pad="page", wait=20, when=lambda r, c=cur: c(r) == 7, next="plays"),
                       PEdge("START", ("START",), pad="page", kind="exit", wait=20, next="done")),
                      note="Reserves on: the manual's Reserves screen")
    subst = State(f"{p}.subst", lambda r, p=p: act(r) and _page(r, p) == "subst",
                  (PEdge("up", ("UP",), pad="page", wait=16), PEdge("down", ("DOWN",), pad="page", wait=16),
                   PEdge("left", ("LEFT",), pad="page", wait=16), PEdge("right", ("RIGHT",), pad="page", wait=16),
                   PEdge("change", ("A",), pad="page", wait=30,
                         effect="the highlighted player in (refused: in the box, dead, under the ice)"),
                   PEdge("change_b", ("B",), pad="page", wait=30),
                   PEdge("START", ("START",), pad="page", kind="exit", wait=20, next="positions")))
    done = State(f"{p}.done", lambda r, p=p: act(r) and _page(r, p) == "done",
                 (PEdge("back", ("DOWN",), pad="page", wait=20, next="positions / plays"),
                  PEdge("stay", ("START",), pad="page", wait=12, next="done"),
                  PEdge("finished", kind="exit", wait=4, track="B" if p == "A" else "A",
                        next="page B" if p == "A" else "page A")))
    return [plays, positions, subst, done]


SPECIAL_PLAYS = Screen(
    (10,), "special plays",
    {**{f"h{p}": _l(a + 0x10) for p, a in PAGE.items()}, **{f"c{p}": _w(a + 6) for p, a in PAGE.items()},
     **{f"s{p}": _w(a + 2) for p, a in PAGE.items()}, **{f"d{p}": _w(a + 0x60) for p, a in PAGE.items()}},
    (*_page_states("A"), *_page_states("B"),
     State("wait", lambda r: True, (Edge("wait", wait=6),))),
    exits=(5, 12, 13, 14, 17), budget=(2, 8), enter_delay=40, pad=_special_pad,
    note="page A: P1 (P2 too in modes 2-4); page B: P2 (mode 1), P3 (3), P3 | P4 (4), else idle")


# --- fight 18 (`$D868`; fighters A $FFFF8C, B $FFFF32) ----------------------------------------

FIGHT_STATE = 0xFFFFF2
FIGHTER = {"A": 0xFFFF8C, "B": 0xFFFF32}


def _humans(r: R) -> list[str]:
    return [f for f in "AB" if r.get(f"p{f}") & 0xFFFF != 0xFFFF]


def _fight_pad(name: str, r: R) -> int | None:
    if name == "fighter":
        f = getattr(r, "fighter", None) or (_humans(r) or ["A"])[0]
        v = r.get(f"p{f}") & 0xFFFF
        return v // 2 if v != 0xFFFF else 0
    if name == "any":
        return 0
    return None


FIGHT_EDGES = (Edge("punch_b", ("B",), hold=4, wait=8, pad="fighter"),
               Edge("punch_c", ("C",), hold=4, wait=8, pad="fighter"),
               Edge("block", ("A",), hold=20, wait=4, pad="fighter", effect="held up to 30 ticks"),
               Edge("block_long", ("A",), hold=45, wait=4, pad="fighter", effect="dropped after 30 ticks"),
               Edge("toward", ("RIGHT",), hold=14, wait=2, pad="fighter", effect="walk (mirrored for B)"),
               Edge("away", ("LEFT",), hold=14, wait=2, pad="fighter"),
               Edge("up", ("UP",), hold=10, wait=2, pad="fighter", effect="nothing"),
               Edge("pause", ("START",), pad="fighter", next="paused"))
#: the "idle" fight style's input: nothing (see :func:`fight_policy`)
FIGHT_IDLE = Edge("idle", wait=30, pad="fighter", effect="nothing pressed")


def fight_policy(state: State, r: R):
    """A person's fight: walk in, punch when close, block a punch sometimes,
    back off, pause once in a while (every input of the fight state).

    The tour's ``fight_style`` (plan 11's later runs, :attr:`tours.Tour.fight_styles`)
    can make it "idle" (nothing pressed: the CPU knocks him out) or
    "forward" (walk in and punch, never block or back off: a knockout of
    the CPU, or of each other)."""
    tour = r.tour
    rng = tour.rng
    style = getattr(tour, "fight_style", "mixed")
    humans = _humans(r)
    f = rng.choice(humans)
    r.fighter = f
    other = "B" if f == "A" else "A"
    me, him = s32(r.get(f"x{f}")) >> 8, s32(r.get(f"x{other}")) >> 8
    d = abs(me - him)
    edges = {e.label: e for e in FIGHT_EDGES}
    toward = "RIGHT" if him > me else "LEFT"
    away = "LEFT" if toward == "RIGHT" else "RIGHT"
    if style == "idle":
        return FIGHT_IDLE
    roll = rng.random()
    if roll < 0.01 and not tour.visit_taken("pause"):
        return edges["pause"]
    if style == "forward":
        pick = "toward" if d > 60 else ("punch_b" if roll < 0.5 else "punch_c")
    elif d > 95:
        pick = "toward" if roll < 0.85 else rng.choice(["away", "up"])
    elif r.get(f"f{other}") == 4 and roll < 0.35:
        pick = rng.choice(["block", "block", "block_long"])
    else:
        pick = rng.choices(["punch_b", "punch_c", "away", "toward", "block"], [5, 5, 1.5, 1, 1])[0]
    e = edges[pick]
    if pick in ("toward", "away"):
        e = Edge(pick, (toward if pick == "toward" else away,), hold=e.hold, wait=e.wait, pad="fighter")
    return e


FIGHT = Screen(
    (18,), "fight",
    {"st": _w(FIGHT_STATE), **{f"p{f}": _w(a + 0x3A) for f, a in FIGHTER.items()},
     **{f"f{f}": _w(a + 0x3C) for f, a in FIGHTER.items()}, **{f"x{f}": _l(a) for f, a in FIGHTER.items()}},
    (State("walk_in", lambda r: r.st == 0, (Edge("wait", wait=10),)),
     State("fighting", lambda r: r.st == 1 and bool(_humans(r)), FIGHT_EDGES, choose=fight_policy,
           note="per human fighter: B/C punch, A block, Left/Right walk, Start pause"),
     State("cpu_fight", lambda r: r.st == 1, (Edge("wait", wait=30),)),
     State("pausing", lambda r: r.st == 6, (Edge("wait", wait=4),)),
     State("paused", lambda r: r.st == 7,
           (Edge("resume", ("START",), pad="fighter", next="fighting"),
            Edge("A_paused", ("A",), pad="fighter", next="paused", effect="nothing"))),
     State("result", lambda r: r.st in (2, 3, 4, 5), (Edge("wait", wait=10),)),
     State("card", lambda r: s16(r.st) == -1,
           (Edge("watch", wait=40, sticky=True, kind="exit", next="screen 17 (480 ticks)"),
            Edge("press", ("A",), pad="any", kind="exit", wait=30, next="screen 17 (after 120 ticks)")))),
    exits=(17,), budget=(1, 2), enter_delay=10, pad=_fight_pad)


# --- referee cutscene 19 (`$13A72`): no input ---------------------------------------------------

REFEREE = Screen((19,), "referee cutscene", {}, (State("cutscene", lambda r: True, (Edge("wait", wait=30),)),),
                 exits=(17,), budget=(0, 0))


# --- team description 2 (`$C75A`): pages tracked (vscroll $FFB0A0: 0 / $A0) ----------------------

TD_VSCROLL = 0xFFB0A0


def _td(page: str, edges) -> State:
    return State(page, lambda r, p=page: r.vs in (0, 0xA0) and r.track == p, tuple(edges))


TEAM_DESCRIPTION = Screen(
    (2,), "team description",
    {"vs": _w(TD_VSCROLL), "side": _w(0xFFC322), "cursor": _w(0xFFC324), "line": _w(0xFFC326)},
    (State("moving", lambda r: r.vs not in (0, 0xA0), (Edge("wait", wait=6),)),
     _td("bio", (Edge("other_team", ("RIGHT",), wait=60, next="bio"),
                 Edge("coach", ("A",), wait=120, track="coach", next="coach"),
                 Edge("coach_c", ("C",), wait=120, track="coach", next="coach"),
                 Edge("START", ("START",), kind="exit", next="screen 1"))),
     _td("coach", (Edge("other_team", ("LEFT",), wait=120, next="coach"),
                   Edge("roster", ("B",), wait=60, track="roster", next="roster"),
                   Edge("START", ("START",), kind="exit", wait=60, track="bio", next="bio"))),
     _td("roster", (Edge("down", ("DOWN",), wait=14), Edge("up", ("UP",), wait=14),
                    Edge("right", ("RIGHT",), wait=14), Edge("left", ("LEFT",), wait=14),
                    Edge("player", ("A",), wait=120, track="player", next="player"),
                    Edge("START", ("START",), kind="exit", wait=60, track="bio", next="bio"))),
     _td("player", (Edge("next_player", ("DOWN",), wait=120, next="player"),
                    Edge("roster", ("C",), wait=60, track="roster", next="roster"),
                    Edge("START", ("START",), kind="exit", wait=60, track="bio", next="bio")))),
    exits=(1,), budget=(4, 12), enter_delay=60, start_track=lambda r: "bio")


# --- matchup 3 (`$B172`) ------------------------------------------------------------------------

MATCHUP = Screen(
    (3,), "matchup", {},
    (State("show", lambda r: True,
           (Edge("watch", wait=40, sticky=True, kind="exit", next="screen 4 after 300 ticks"),
            Edge("press", ("START",), kind="exit", wait=40, next="screen 4"))),),
    exits=(4,), budget=(0, 0), enter_delay=20)


# --- playoffs 11 (`$11AE4`): the bracket, the password screen, the champion ---------------------

PLAYOFF_FLAGS = 0xFFBD7E   # run +$14: 1 new run, 2 show the password, 4 champion, 8 eliminated
ALPHABET = 0x66CD3         # 28 password symbols in a 7 x 4 grid (cursor = index)
PASSWORD_LEN = 13


def password_moves(src: int, dst: int) -> list[str]:
    """D-pad presses taking the password cursor from ``src`` to ``dst``
    (7 columns x 4 rows, wrapping in a row and in a column; `$12454`)."""
    out = []
    sc, sr_ = src % 7, src // 7
    dc, dr = dst % 7, dst // 7
    right = (dc - sc) % 7
    out += ["RIGHT"] * right if right <= 3 else ["LEFT"] * (7 - right)
    down = (dr - sr_) % 4
    out += ["DOWN"] * down if down <= 2 else ["UP"] * (4 - down)
    return out


def _playoffs_start(r: R) -> str:
    f = r.get("flags")
    if f & 4:
        return "champion"
    if f & 8:
        return "eliminated"         # straight back to the main menu
    if f & 2:
        return "show"               # after a game: the new password
    if f & 1:
        return "bracket"            # a new run
    return "password"               # Continue Playoffs: enter one


PLAYOFFS = Screen(
    (11,), "playoffs",
    {"flags": _b(PLAYOFF_FLAGS)},
    (State("password", lambda r: r.track == "password", choose=lambda s, r: r.tour.password_step(r),
           note="typed by the tour's password plan: wrong ones first, then (sometimes) a valid one"),
     State("show", lambda r: r.track == "show",
           (Edge("A_nothing", ("A",), next="show", effect="only Start leaves the shown password"),
            Edge("START", ("START",), kind="exit", wait=90, track="bracket", next="bracket"))),
     State("bracket", lambda r: r.track == "bracket",
           (Edge("left", ("LEFT",), wait=30), Edge("right", ("RIGHT",), wait=30),
            Edge("redraw", ("A",), wait=60, when=lambda r: bool(r.get("flags") & 1), effect="a new run: new seed"),
            Edge("START", ("START",), kind="exit", next="screen 3"))),
     State("champion", lambda r: r.track == "champion",
           (Edge("B", ("B",)), Edge("C", ("C",)), Edge("START", ("START",), kind="exit", next="screen 1"))),
     State("other", lambda r: True, (Edge("wait", wait=10),))),
    exits=(1, 3), budget=(1, 4), enter_delay=40, start_track=_playoffs_start)


# --- main menu 1 (`$136DE`): goal-directed (tours.MenuGoal) ---------------------------------

MENU_ROW = 0xFFC7C6        # .l: the highlighted row's record (0 none)
MENU_ROWS = 0x1F4FA        # 10 row record pointers (row 5 none; row 6 in RAM $FFC7D0)
MENU_UP = 0x139A8          # next row for Up / Down, by row (byte tables)
MENU_DOWN = 0x139B2
TEAM_MENU_POS = 0x1C1BB    # team -> menu position
TEAM_MENU_ORDER = 0x1C1A4  # menu position -> team
STADIUM_TEMPLATE = 0x1F46A
SETUP = 0xFFB0DE           # 10 setup bytes, row r = SETUP + r
MENU_SETUP_ORDER = (3, 2, 0, 1, 4, 6, 7, 8, 9)   # rows set in this order (play mode first)


@dataclass
class MenuRows:
    """The main menu's row tables, from the ROM (``rom.u8`` / ``rom.u32``)."""
    records: list[int]
    counts: list[int]
    up: list[int]
    down: list[int]
    team_pos: list[int]
    team_order: list[int]

    @staticmethod
    def from_rom(rom) -> "MenuRows":
        recs, counts = [], []
        for i in range(10):
            a = rom.u32(MENU_ROWS + 4 * i) & 0xFFFFFF
            recs.append(a)
            if a == 0:
                counts.append(0)
            else:
                counts.append(rom.u8((STADIUM_TEMPLATE if a >= 0xFF0000 else a) + 6))
        return MenuRows(recs, counts, [rom.u8(MENU_UP + i) for i in range(10)],
                        [rom.u8(MENU_DOWN + i) for i in range(10)],
                        [rom.u8(TEAM_MENU_POS + i) for i in range(23)],
                        [rom.u8(TEAM_MENU_ORDER + i) for i in range(23)])

    def row_of(self, record: int) -> int | None:
        record &= 0xFFFFFF
        return self.records.index(record) if record and record in self.records else None

    def path(self, src: int, dst: int) -> list[str]:
        """Up / Down presses from row ``src`` to row ``dst`` (shortest)."""
        seen = {src: []}
        todo = [src]
        while todo:
            r = todo.pop(0)
            if r == dst:
                return seen[r]
            for b, table in (("UP", self.up), ("DOWN", self.down)):
                n = table[r]
                if n not in seen:
                    seen[n] = seen[r] + [b]
                    todo.append(n)
        raise ValueError(f"row {dst} not reachable from {src}")

    def position(self, row: int, value: int) -> int:
        return self.team_pos[value] if row < 2 else value

    def step(self, row: int, value: int, target: int) -> str | None:
        """Left or Right towards ``target`` (shortest way round), None if there."""
        if value == target:
            return None
        n = self.counts[row]
        d = (self.position(row, target) - self.position(row, value)) % n
        return "RIGHT" if d <= n - d else "LEFT"


MENU_READS = {"row": _l(MENU_ROW), "saved": _l(0xFFC7CA), "s0": _l(SETUP), "s1": _l(SETUP + 4),
              "s2": _w(SETUP + 8), "stadium_mode": _b(0xFFC7F6)}


def menu_setup(r: R) -> list[int]:
    """The 10 setup bytes from the main menu's reads."""
    b = r.s0.to_bytes(4, "big") + r.s1.to_bytes(4, "big") + (r.s2 & 0xFFFF).to_bytes(2, "big")
    return list(b)


MAIN_MENU = Screen(
    (1,), "main menu", MENU_READS,
    (State("menu", lambda r: True, choose=lambda s, r: r.tour.menu_step(r),
           note="rows set to the run's setup (play mode first), excursions, Start"),),
    exits=(2, 3, 11), budget=(0, 0), enter_delay=40)


MODELS: dict[int, Screen] = {}
for _m in (MAIN_MENU, TEAM_DESCRIPTION, MATCHUP, INSTANT_REPLAY, STATS, SPECIAL_PLAYS, PLAYOFFS,
           *(_scoreboard(s) for s in (12, 13, 14, 15, 16)), SCOREBOARD_17, FIGHT, REFEREE):
    for _s in _m.ids:
        MODELS[_s] = _m


def model(screen: int) -> Screen | None:
    return MODELS.get(screen)


def edge_keys() -> list[str]:
    """Every fixed edge of the models as ``screen:state:label`` (policies'
    edges - the menu, passwords, fight moves - are added as they are taken)."""
    out = []
    for scr, m in sorted(MODELS.items()):
        for s in m.states:
            for e in s.edges:
                out.append(f"{scr}:{s.id}:{e.label}")
    return out
