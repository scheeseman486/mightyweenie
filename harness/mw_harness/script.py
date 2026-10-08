"""Input scripts v1 (``.mwi``) and the rules for when presses happen.

The format and the timing rules are specified in docs/compare.md; the Godot
side (game/src/compare/) implements the same rules, and both are checked
against compare/fixtures/player_timeline.json.

    script = Script.parse(Path("compare/scripts/coop_start.mwi").read_text())
    player = ScriptPlayer(script)
    player.screen_entered(1, tick=6005)     # the side reports what happens...
    player.tick_start(6006)
    player.boundary(1, 1, 0, 6006)
    player.held(1)                          # ...and asks what is pressed
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

#: Genesis pad bits as the game stores them (S A C B R L D U).
PAD_BITS = {"UP": 0x01, "DOWN": 0x02, "LEFT": 0x04, "RIGHT": 0x08,
            "B": 0x10, "C": 0x20, "A": 0x40, "START": 0x80}
TAP_CAP_TICKS = 16      # a tap is released after this many ticks at the latest
PLAYERS = 4


class ScriptError(ValueError):
    pass


@dataclass(frozen=True)
class Event:
    """One script line."""

    line: int
    anchor: str          # "screen" | "tick"
    screen: int          # screen ID (anchor "screen")
    visit: int           # 1 = first entry
    unit: str            # "tick" (offset from the entry / absolute tick) | "pass"
    start: int
    end: int | None      # tick: release tick offset (exclusive); pass: last pass held (inclusive)
    player: int          # 1-4; 0 for END
    buttons: int         # PAD_BITS mask
    mode: str            # "tap" | "hold" | "end"
    repeat: int = 1

    def to_text(self) -> str:
        if self.anchor == "tick":
            when = f"@tick {self.start}" + (f"..{self.end}" if self.end is not None else "")
        else:
            when = f"@screen {self.screen}" + (f" #{self.visit}" if self.visit != 1 else "")
            if self.unit == "pass":
                when += f" @pass {self.start}" + (f"..{self.end}" if self.end is not None else "")
            else:
                when += f" +{self.start}" + (f"..+{self.end}" if self.end is not None else "")
        if self.mode == "end":
            return f"{when} END"
        names = "+".join(n for n, b in PAD_BITS.items() if self.buttons & b)
        what = f"P{self.player} {names}"
        if self.mode == "hold":
            what += " hold"
        elif self.repeat > 1:
            what += f" x{self.repeat}"
        return f"{when} {what}"


_COMMENT = re.compile(r"(^|\s)#(\s|$).*")


@dataclass
class Script:
    events: list[Event] = field(default_factory=list)
    name: str = ""

    @classmethod
    def parse(cls, text: str, name: str = "") -> "Script":
        events = []
        for no, raw in enumerate(text.splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            line = _COMMENT.sub("", line).strip()
            if line:
                events.append(_parse_line(line, no))
        return cls(events, name)

    def to_text(self) -> str:
        return "".join(e.to_text() + "\n" for e in self.events)


def _int(tok: str, no: int, what: str) -> int:
    try:
        return int(tok)
    except ValueError:
        raise ScriptError(f"line {no}: expected {what}, got {tok!r}") from None


def _parse_line(line: str, no: int) -> Event:
    toks = line.split()
    i = 0
    if toks[0] == "@tick":
        anchor, screen, visit, unit = "tick", -1, 1, "tick"
        a, _, b = toks[1].partition("..")
        start, end = _int(a, no, "tick"), (_int(b, no, "tick") if b else None)
        i = 2
    elif toks[0] == "@screen":
        anchor, unit = "screen", "tick"
        screen = _int(toks[1], no, "screen ID")
        visit, i = 1, 2
        if i < len(toks) and toks[i].startswith("#"):
            visit = _int(toks[i][1:], no, "visit")
            i += 1
        if i < len(toks) and toks[i] == "@pass":
            unit = "pass"
            a, _, b = toks[i + 1].partition("..")
            start, end = _int(a, no, "pass"), (_int(b, no, "pass") if b else None)
            i += 2
        elif i < len(toks) and toks[i].startswith("+"):
            a, _, b = toks[i].partition("..")
            start = _int(a[1:], no, "+ticks")
            if b and not b.startswith("+"):
                raise ScriptError(f"line {no}: range end must be +ticks")
            end = _int(b[1:], no, "+ticks") if b else None
            i += 1
        else:
            raise ScriptError(f"line {no}: expected +ticks or @pass after the screen")
    else:
        raise ScriptError(f"line {no}: a line starts with @screen or @tick")
    if end is not None and end <= start - (1 if unit == "pass" else 0):
        raise ScriptError(f"line {no}: empty range")
    rest = toks[i:]
    if not rest:
        raise ScriptError(f"line {no}: missing action")
    if rest[0] == "END":
        if len(rest) != 1 or end is not None:
            raise ScriptError(f"line {no}: END takes a single anchor")
        return Event(no, anchor, screen, visit, unit, start, None, 0, 0, "end")
    m = re.fullmatch(r"P([1-4])", rest[0])
    if not m or len(rest) < 2:
        raise ScriptError(f"line {no}: expected P1-P4 and buttons")
    player, mask = int(m.group(1)), 0
    for name in rest[1].split("+"):
        if name not in PAD_BITS:
            raise ScriptError(f"line {no}: unknown button {name!r}")
        mask |= PAD_BITS[name]
    mode, repeat = ("hold" if end is not None else "tap"), 1
    for tok in rest[2:]:
        if tok in ("tap", "hold"):
            mode = tok
        elif re.fullmatch(r"x[1-9]\d*", tok):
            repeat = int(tok[1:])
        else:
            raise ScriptError(f"line {no}: unknown word {tok!r}")
    if mode == "hold" and end is None:
        raise ScriptError(f"line {no}: hold needs a range")
    if mode == "tap" and end is not None:
        raise ScriptError(f"line {no}: a range is a hold")
    if repeat > 1 and mode != "tap":
        raise ScriptError(f"line {no}: xN repeats taps only")
    return Event(no, anchor, screen, visit, unit, start, end, player, mask, mode, repeat)


@dataclass
class _Press:
    event: Event
    player: int
    mask: int
    press_tick: int
    release_tick: int | None = None             # tick holds: release at this tick start
    release_after: tuple[int, int, int] | None = None  # pass holds: (screen, visit, last pass)
    read: bool = False                          # taps: a pass has started since the press
    taps_left: int = 0


class ScriptPlayer:
    """Applies a script as events are reported; see docs/compare.md.

    Call :meth:`screen_entered`, :meth:`tick_start` and :meth:`boundary` in the
    order things happen; read :meth:`held` whenever needed. ``log`` keeps every
    press/release as (moment, player, mask, "down"/"up") for parity checks.
    """

    def __init__(self, script: Script):
        self.script = script
        self.visits: dict[int, int] = {}
        self.entries: dict[tuple[int, int], int] = {}
        self.current: tuple[int, int] | None = None
        self.tick = 0
        self._tick_due: list[tuple[int, Event]] = []     # (due tick, event)
        self._pass_due: list[tuple[tuple[int, int, int], Event]] = []
        self._next_taps: list[tuple[int, _Press]] = []   # repeats: (due tick, press)
        self.active: list[_Press] = []
        self.ended_at: int | None = None
        self.log: list[tuple[str, int, int, str]] = []
        for e in script.events:
            if e.anchor == "tick":
                self._tick_due.append((e.start, e))

    # --- what is pressed -------------------------------------------------
    def held(self, player: int) -> int:
        m = 0
        for p in self.active:
            if p.player == player:
                m |= p.mask
        return m

    def held_all(self) -> list[int]:
        return [self.held(p) for p in range(1, PLAYERS + 1)]

    @property
    def ended(self) -> bool:
        return self.ended_at is not None

    # --- notifications ---------------------------------------------------
    def screen_entered(self, screen: int, tick: int) -> None:
        """A screen visit starts (the original: run_screens calls the handler)."""
        self.tick = tick
        visit = self.visits.get(screen, 0) + 1
        self.visits[screen] = visit
        self.entries[(screen, visit)] = tick
        if self.current is not None:   # pass-anchored holds end with their visit
            self._release(lambda p: p.release_after is not None and p.release_after[:2] == self.current,
                          f"screen {screen}")
        self.current = (screen, visit)
        for e in self.script.events:
            if e.anchor == "screen" and (e.screen, e.visit) == (screen, visit):
                if e.unit == "tick":
                    self._tick_due.append((tick + e.start, e))
                else:
                    self._pass_due.append(((screen, visit, e.start), e))
        self._apply_tick_due(tick, f"screen {screen}")

    def resume(self, screen: int, visit: int) -> None:
        """A visit continues after a sub-screen (player stats -> game stats)."""
        self.current = (screen, visit)

    def tick_start(self, tick: int) -> None:
        self.tick = tick
        moment = f"tick {tick}"
        self._release(lambda p: p.release_tick is not None and p.release_tick <= tick, moment)
        self._release(lambda p: p.event.mode == "tap" and tick - p.press_tick >= TAP_CAP_TICKS, moment)
        self._apply_tick_due(tick, moment)

    def boundary(self, screen: int, visit: int, pass_index: int, tick: int) -> None:
        self.tick = tick
        moment = f"pass {screen}/{visit}/{pass_index}"
        self._release(lambda p: p.event.mode == "tap" and p.read, moment)
        self._release(lambda p: p.release_after is not None and p.release_after[:2] == (screen, visit)
                      and pass_index > p.release_after[2], moment)
        for key, e in list(self._pass_due):
            if key == (screen, visit, pass_index):
                self._pass_due.remove((key, e))
                self._start(e, tick, moment)
        for p in self.active:
            if p.event.mode == "tap":
                p.read = True

    # --- internals -------------------------------------------------------
    def _apply_tick_due(self, tick: int, moment: str) -> None:
        for item in sorted(self._tick_due, key=lambda x: (x[0], x[1].line)):
            due, e = item
            if due <= tick:
                self._tick_due.remove(item)
                self._start(e, tick, moment)
        for item in list(self._next_taps):
            due, prev = item
            if due <= tick:
                self._next_taps.remove(item)
                self._press(prev.event, tick, moment, taps_left=prev.taps_left)

    def _start(self, e: Event, tick: int, moment: str) -> None:
        if e.mode == "end":
            if self.ended_at is None:
                self.ended_at = tick
                self.log.append((moment, 0, 0, "end"))
            return
        self._press(e, tick, moment, taps_left=e.repeat - 1)

    def _press(self, e: Event, tick: int, moment: str, taps_left: int) -> None:
        p = _Press(e, e.player, e.buttons, tick, taps_left=taps_left)
        if e.mode == "hold":
            if e.unit == "pass":
                p.release_after = (e.screen, e.visit, e.end)
            elif e.anchor == "tick":
                p.release_tick = e.end
            else:
                p.release_tick = self.entries[(e.screen, e.visit)] + e.end
        before = self.held(e.player)
        self.active.append(p)
        if self.held(e.player) != before:
            self.log.append((moment, e.player, self.held(e.player), "down"))

    def _release(self, pred, moment: str) -> None:
        for p in [p for p in self.active if pred(p)]:
            before = self.held(p.player)
            self.active.remove(p)
            if self.held(p.player) != before:
                self.log.append((moment, p.player, self.held(p.player), "up"))
            if p.event.mode == "tap" and p.taps_left > 0:
                nxt = _Press(p.event, p.player, p.mask, self.tick, taps_left=p.taps_left - 1)
                self._next_taps.append((self.tick + 1, nxt))
