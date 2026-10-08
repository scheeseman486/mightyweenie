"""GPGX recordings of the screens between plays for the visual check (plan 11 item 6;
docs/compare.md, Screen visual check).

Drives the original in Genesis Plus GX (stable-retro, `mw_harness.emulator`) through a
scenario and records every visit of a screen between plays (7, 8 (+9), 10, 12-19): from
the frame before the screen's entry (`$FFB05E` changes; that frame's RAM is the entry
state) to the visit's last frame, per frame:

* `ram.bin`: N records of RAM `$FFB050`-`$FFCA61` (an MwRinkRam image) + `$FFE000`-`$FFFFFF`
  (the sound driver's channels `$FFEA22` / `$FFEB44`, the stack page `$FFFE00`-`$FFFFFF`);
* `entry_ram.bin`: the whole work RAM (64 KB) of record 0 (the replay ring included);
* `frames.npz`: the N frames as GPGX shows them (uint8 N x 224 x 320 x 3);
* `meta.json`: screen, previous screen, per frame [emulator frame, tick, screen id, PC,
  P1 buttons, P2 buttons, CRAM (64 words as hex), the long at (A7) (a wait's return address), A7];
* `entry.state`: the savestate after record 0 (re-run a visit to look at VRAM etc.).

Everything stays local under out/visual/rec/ (ROM-derived, gitignored).

Visits are numbered per scenario (rec/SCENARIO/NN_sSCREEN, rec/SCENARIO/index.json); a
visit closed by restoring a savestate (a branch) is "cut" in meta.json, else "left".

usage: tools/bin/py -m mw_harness.visual_rec SCENARIO [...]   (see SCENARIOS;
       tools/bin/visual-check runs our side and the comparison)
"""
from __future__ import annotations

import json
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

from .emulator import ReferenceEmulator
from .gpgx_state import OFF_CRAM, OFF_WORK_RAM, M68K_REGS_OFFSET, gpgx_cram_to_genesis
from .rom import REPO_ROOT

HERE = REPO_ROOT / "out" / "visual"
REC = HERE / "rec"
STATES = HERE / "states"
RECORDED = {7, 8, 10, 12, 13, 14, 15, 16, 17, 18, 19}
SID, TICK, PHASE, PERIOD, CLOCK = 0xFFB05E, 0xFFCA56, 0xFFC60A, 0xFFB076, 0xFFB06A
TEAM_A, TEAM_B = 0xFFB402, 0xFFB8AC
SCORE_A, SCORE_B = 0xFFB8A4, 0xFFBD4E
IMG_LO, IMG_HI = 0xB050, 0xCA62
HIGH_LO = 0xE000


def _ram(raw: bytes) -> bytes:
    """Work RAM in the 68000's byte order (GPGX keeps words little-endian)."""
    w = np.frombuffer(raw, dtype=np.uint8, count=0x10000, offset=OFF_WORK_RAM).reshape(-1, 2)
    return w[:, ::-1].tobytes()


class Rec:
    """The emulator with visit recording around every step."""

    def __init__(self, tag: str, start: str | None = None):
        self.tag = tag
        self.e = ReferenceEmulator()
        self.visits = 0
        self.recording = True
        self.only: set[int] | None = None
        self.saved: list[str] = []
        self._cur = None          # the open visit
        self._prev = None         # the last frame's (raw, ram, img, info)
        self.ram = b"\0" * 0x10000
        self.last_sid = -1
        if start:
            self.load_named(start)
        self._sample()

    # --- RAM -------------------------------------------------------------------------------
    def u8(self, a: int) -> int:
        return self.ram[a & 0xFFFF]

    def u16(self, a: int) -> int:
        a &= 0xFFFF
        return (self.ram[a] << 8) | self.ram[a + 1]

    def u32(self, a: int) -> int:
        return (self.u16(a) << 16) | self.u16(a + 2)

    @property
    def sid(self) -> int:
        return self.u16(SID)

    @property
    def phase(self) -> int:
        return self.u16(PHASE)

    @property
    def frame(self) -> int:
        return self.e.frame

    def poke(self, addr: int, value: int, size: int = 1) -> None:
        self.e.poke(addr, value, size)
        self._sample()

    # --- states ----------------------------------------------------------------------------
    def save_named(self, name: str) -> None:
        (STATES / f"{name}.state").write_bytes(self.e.save())
        (STATES / f"{name}.frame").write_text(str(self.e.frame))

    def load_named(self, name: str) -> bool:
        p = STATES / f"{name}.state"
        if not p.exists():
            return False
        self.e.load(p.read_bytes(), int((STATES / f"{name}.frame").read_text()))
        self._sample()
        return True

    def save(self):
        return (self.e.save(), self.e.frame)

    def load(self, st) -> None:
        self._close()
        self.e.load(st[0], st[1])
        self._sample()
        self.last_sid = self.sid

    # --- stepping --------------------------------------------------------------------------
    def _sample(self):
        raw = self.e.save()
        self.ram = _ram(raw)
        return raw

    def step(self, p1=(), p2=()) -> None:
        prev = (self._raw_prev, self._ram_prev, self._img_prev, self._info_prev) if hasattr(self, "_raw_prev") else None
        self.e.step_players([list(p1), list(p2)])
        raw = self._sample()
        pc = struct.unpack_from("<I", raw, M68K_REGS_OFFSET + 64)[0]
        a7 = struct.unpack_from("<I", raw, M68K_REGS_OFFSET + 60)[0]
        img = self.e.screen().copy()
        cram = struct.unpack_from("<64H", raw, OFF_CRAM)
        info = [self.e.frame, self.u32(TICK), self.sid, pc, "+".join(p1), "+".join(p2),
                "".join("%03x" % gpgx_cram_to_genesis(c) for c in cram), self.u32(a7), a7]
        sid = self.sid
        if self.recording:
            if self._cur is not None and sid != self._cur["screen"]:
                self._close("left")
            if self._cur is None and sid in RECORDED and sid != self.last_sid and prev is not None \
                    and (self.only is None or sid in self.only):
                self._open(prev, sid)
            if self._cur is not None:
                self._add(raw, self.ram, img, info)
        else:
            self._close()
        self.last_sid = sid
        self._raw_prev, self._img_prev, self._info_prev = raw, img, info
        self._ram_prev = self.ram

    def _open(self, prev, sid: int) -> None:
        raw, ram, img, info = prev
        self._cur = {"screen": sid, "previous": ram[SID & 0xFFFF] << 8 | ram[(SID & 0xFFFF) + 1],
                     "entry_ram": ram, "entry_state": raw, "recs": [], "imgs": [], "info": []}
        self._add(raw, ram, img, info)

    def _add(self, raw, ram, img, info) -> None:
        c = self._cur
        c["recs"].append(ram[IMG_LO:IMG_HI] + ram[HIGH_LO:0x10000])
        c["imgs"].append(zlib.compress(img.tobytes(), 1))
        c["info"].append(info)

    def _close(self, ended: str = "cut") -> None:
        c = self._cur
        if c is None:
            return
        self._cur = None
        self.visits += 1
        name = f"{self.tag}/{self.visits:02d}_s{c['screen']}"
        self.saved.append(name)
        d = REC / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "ram.bin").write_bytes(b"".join(c["recs"]))
        (d / "entry_ram.bin").write_bytes(c["entry_ram"])
        (d / "entry.state").write_bytes(c["entry_state"])
        frames = np.stack([np.frombuffer(zlib.decompress(b), np.uint8).reshape(224, 320, 3) for b in c["imgs"]])
        np.savez_compressed(d / "frames.npz", frames=frames)
        del frames
        meta = {"name": name, "screen": c["screen"], "previous": c["previous"],
                "image": [IMG_LO | 0xFF0000, IMG_HI | 0xFF0000], "high": HIGH_LO | 0xFF0000,
                "record_size": len(c["recs"][0]), "ended": ended,
                "frames": c["info"]}
        (d / "meta.json").write_text(json.dumps(meta))
        print(f"  saved {name}: {len(c['recs'])} frames (screen {c['screen']} from {c['previous']})", flush=True)

    def finish(self) -> None:
        self._close()
        (REC / self.tag).mkdir(parents=True, exist_ok=True)
        (REC / self.tag / "index.json").write_text(json.dumps(self.saved, indent=0))

    # --- helpers ---------------------------------------------------------------------------
    def wait(self, n: int, p1=(), p2=()) -> None:
        for _ in range(n):
            self.step(p1, p2)

    def press(self, button: str, n: int = 4, after: int = 0, pad: int = 0) -> None:
        b = button.split("+")
        for _ in range(n):
            self.step(b if pad == 0 else (), b if pad == 1 else ())
        self.wait(after)

    def until(self, pred, limit: int, buttons=lambda r: ((), ())) -> bool:
        end = self.e.frame + limit
        while self.e.frame < end:
            if pred(self):
                return True
            p1, p2 = buttons(self)
            self.step(p1, p2)
        return pred(self)

    def info(self) -> str:
        return (f"frame {self.frame} tick {self.u32(TICK)} screen {self.sid} phase {self.phase} "
                f"period {self.u8(PERIOD)} clock {self.u16(CLOCK)} score {self.u16(SCORE_A)}-{self.u16(SCORE_B)}")


# --- scenario building blocks ----------------------------------------------------------------

def to_menu(r: Rec) -> None:
    """Power on to the main menu (no input: title, credits), cached as states/menu."""
    if r.load_named("menu"):
        return
    r.recording = False
    r.until(lambda r: r.sid == 1 and r.frame > 6400, 9000)
    r.wait(30)
    r.save_named("menu")
    r.recording = True


def menu_rows(r: Rec, moves: list[str]) -> None:
    """Main menu presses (each 4 frames + 30 idle), e.g. ["DOWN"] * 5 + ["RIGHT"]."""
    for m in moves:
        r.press(m, 4, 30)


# --- scenarios ----------------------------------------------------------------------------------

def sc_goal(r: Rec) -> None:
    """A goal (out/explore/tour_b.py's inputs from power-on) -> 12: the scorer's comment, B
    shows the menu; branches from the menu (savestate): A -> 8 (scroll, B/C starfield, A -> 9
    pages, team switch, Start -> 8, Start) -> 12 (return); B -> 10 (cursor, B) -> 12; C -> 7
    (frozen, C play, held B slow, held A rewind, Start) -> 12; Start -> 5."""
    inp = {}
    for f in range(6500, 6506):
        inp[f] = "START"
    for f in range(10100, 10104):
        inp[f] = "START"
    for f in range(10250, 10254):
        inp[f] = "A"
    def btn(r):
        b = [inp[r.frame]] if r.frame in inp else []
        if r.sid in (13, 14, 15, 16, 17, 19) and r.frame % 600 < 5 and r.frame > 10300:
            b.append("START")
        return (b, [])
    ok = r.until(lambda r: r.sid == 12, 20000, btn)
    print("goal?", ok, r.info(), flush=True)
    if not ok:
        return
    # 12 entered: the comment, then B shows the menu
    r.wait(420)
    r.press("B", 4, 120)
    menu = r.save()
    # A: game stats
    r.press("A", 4)
    r.until(lambda r: r.sid == 8, 400)
    r.wait(120)
    for b in ("DOWN", "DOWN", "DOWN", "UP"):
        r.press(b, 3, 40)
    r.press("B", 3, 60)        # starfield stops
    r.press("C", 3, 60)        # re-aimed
    r.press("A", 3, 150)       # 9
    for b in ("DOWN", "DOWN", "UP", "A", "DOWN"):
        r.press(b, 3, 90)
    r.press("START", 3, 150)   # back to 8
    r.press("START", 3)
    r.until(lambda r: r.sid == 12, 400)
    r.wait(200)
    r.finish()
    # B: special plays
    r.load(menu)
    r.press("B", 4)
    r.until(lambda r: r.sid == 10, 400)
    r.wait(150)
    for b in ("DOWN", "DOWN", "UP"):
        r.press(b, 3, 40)
    r.press("B", 3, 60)
    r.until(lambda r: r.sid == 12, 600)
    r.wait(150)
    r.finish()
    # C: instant replay
    r.load(menu)
    r.press("C", 4)
    r.until(lambda r: r.sid == 7, 400)
    r.wait(120)                # frozen on the oldest frame
    r.press("C", 3, 150)       # play
    r.press("B", 90)           # held: slow
    r.press("A", 90)           # held: rewind
    r.wait(30)
    r.press("START", 4)
    r.until(lambda r: r.sid == 12, 600)
    r.wait(150)
    r.press("START", 4)
    r.until(lambda r: r.sid != 12, 400)
    r.finish()


def scripted(r: Rec, setup: dict, pokes=(), actions=(), stop=None, limit: int = 30000) -> None:
    """The way plan 11's BlastEm experiments did it: the setup bytes poked at the main
    menu, Start; pokes (screen, visit, ticks after its entry, [(addr, value, size)]); actions
    (screen, visit, ticks after its entry, pad 1-2, button, frames held); stop (screen, visit,
    ticks): the end. Visits count screen entries."""
    to_menu(r)
    for a, v in setup.items():
        r.poke(a, v, 1)
    r.press("START", 6)
    visits: dict[int, int] = {}
    entry_tick = 0
    last = r.sid
    done_p, done_a = set(), set()
    held: list[tuple[int, str, int]] = []      # (pad, button, frames left)
    end = r.frame + limit
    while r.frame < end:
        sid = r.sid
        if sid != last:
            visits[sid] = visits.get(sid, 0) + 1
            entry_tick = r.u32(TICK)
            last = sid
        v = visits.get(sid, 0)
        t = r.u32(TICK) - entry_tick
        if stop and (sid, v) == stop[:2] and t >= stop[2]:
            break
        for i, (ps, pv, after, writes) in enumerate(pokes):
            if i not in done_p and (ps, pv) == (sid, v) and t >= after:
                done_p.add(i)
                for wa, wv, sz in writes:
                    r.poke(wa, wv, sz)
                print(f"  poke at frame {r.frame} (screen {sid} visit {v} +{t}): {[(hex(a), hex(b)) for a, b, _ in writes]}", flush=True)
        for i, (as_, av, at, pad, btn, n) in enumerate(actions):
            if i not in done_a and (as_, av) == (sid, v) and t >= at:
                done_a.add(i)
                held.append((pad, btn, n))
                print(f"  {btn} on pad {pad} at frame {r.frame} (screen {sid} visit {v} +{t})", flush=True)
        p1 = [b for p, b, n in held if p == 1]
        p2 = [b for p, b, n in held if p == 2]
        held = [(p, b, n - 1) for p, b, n in held if n > 1]
        r.step(p1, p2)
    print("  end:", r.info(), flush=True)


#: the main menu's setup bytes (`$FFB0DE`..): team A 0, team B 7, pad mode 0, stadium 0,
#: penalties off, Death Index 2 (exp.py's BASE)
BASE = {0xFFB0E0: 0, 0xFFB0DE: 0, 0xFFB0DF: 7, 0xFFB0E4: 0, 0xFFB0E5: 0, 0xFFB0E7: 2}
PHASE_POKE = lambda ph: [(0xFFC60C, 0, 2), (0xFFC60A, ph, 2)]


def sc_period(r: Rec) -> None:
    """Period ends (clock poked to 2 s, penalties on) -> 14: the Zamboni, D-pad whips (in the
    intro and the menu), 600 ticks -> the menu, A -> 8 -> Start -> 14 (return), Start -> 4;
    period 2 -> 14 -> B (the menu), C -> 7 -> 14 -> Start; period 3 with team B ahead -> 15 game over:
    B shows the menu, Start -> 1."""
    scripted(r, {**BASE, 0xFFB0E5: 1},
             pokes=[(4, 1, 900, [(0xFFB06A, 2, 2)]), (4, 2, 300, [(0xFFB06A, 2, 2)]),
                    (4, 3, 300, [(0xFFB06A, 2, 2), (SCORE_B, 2, 2)])],
             actions=[(14, 1, 200, 1, "RIGHT", 4), (14, 1, 212, 1, "UP", 4), (14, 1, 224, 1, "LEFT", 4),
                      (14, 1, 400, 2, "DOWN", 4), (14, 1, 700, 1, "RIGHT", 4), (14, 1, 900, 1, "A", 6),
                      (8, 1, 150, 1, "START", 6), (14, 2, 300, 1, "START", 6),
                      (14, 3, 400, 1, "B", 6), (14, 3, 500, 1, "C", 6), (7, 1, 200, 1, "START", 6),
                      (14, 4, 200, 1, "START", 6),
                      (15, 1, 300, 1, "B", 6), (15, 1, 450, 1, "START", 6)],
             stop=(1, 2, 10), limit=40000)


def sc_fight(r: Rec) -> None:
    """A fight poked (phase 4, penalties on) -> 18: walk-in, fighting (P1 punches with A),
    the result, the card -> 17: both fighters to the box, the winner's quote, the menu; A -> 8
    -> 17 (return); Start -> 5."""
    scripted(r, {**BASE, 0xFFB0E5: 1},
             pokes=[(4, 1, 900, PHASE_POKE(4))],
             actions=[(18, 1, 120, 1, "A", 6), (18, 1, 160, 1, "A", 6), (18, 1, 200, 1, "A", 6),
                      (18, 1, 260, 1, "A", 6), (18, 1, 330, 1, "A", 6), (18, 1, 400, 1, "A", 6),
                      (17, 1, 2000, 1, "A", 6), (8, 1, 120, 1, "START", 6), (17, 2, 100, 1, "START", 6)],
             stop=(5, 1, 20))


def sc_penalty(r: Rec) -> None:
    """A minor call poked on team A's slot 2 (pad mode 1: P1 v P2) -> 17: the panel, the
    info, the walk to the box, the portrait; P2 (the fouled team) skips; the menu; A -> 8 ->
    17 (return, box entries kept); Start -> 5 -> a goal poked -> 12 with the box display."""
    scripted(r, {**BASE, 0xFFB0E0: 1, 0xFFB0E5: 1},
             pokes=[(4, 1, 1500, [(0xFFB55A + 0x74, 2, 1), (0xFFB55A + 0x6C, 0xFD, 1), (0xFFB7A2, 1, 1),
                                  (0xFFB7A3, 1, 1), (0xFFC2F0, 0, 2)] + PHASE_POKE(2)),
                    (5, 1, 300, PHASE_POKE(3))],
             actions=[(17, 1, 300, 1, "START", 6), (17, 1, 400, 2, "START", 6), (17, 1, 500, 1, "A", 6),
                      (8, 1, 120, 1, "START", 6), (17, 2, 100, 1, "START", 6),
                      (12, 1, 700, 1, "START", 6)],
             stop=(5, 2, 20))


def sc_penalty2(r: Rec) -> None:
    """As sc_penalty, nobody skips: the walk to the box ends, the portrait, the menu comes by
    itself; Start -> 5."""
    scripted(r, {**BASE, 0xFFB0E0: 1, 0xFFB0E5: 1},
             pokes=[(4, 1, 1500, [(0xFFB55A + 0x74, 2, 1), (0xFFB55A + 0x6C, 0xFD, 1), (0xFFB7A2, 1, 1),
                                  (0xFFB7A3, 1, 1), (0xFFC2F0, 0, 2)] + PHASE_POKE(2))],
             actions=[(17, 1, 900, 1, "START", 6)],
             stop=(5, 1, 20))


def sc_pause(r: Rec) -> None:
    """Open play: Start pauses, A -> 7 from the rink (frozen, C play, held B slow, held A
    rewind, Start -> 6)."""
    scripted(r, BASE,
             actions=[(5, 1, 400, 1, "START", 4), (5, 1, 460, 1, "A", 4),
                      (7, 1, 150, 1, "C", 4), (7, 1, 300, 1, "B", 60), (7, 1, 420, 1, "A", 60),
                      (7, 1, 560, 1, "START", 4)],
             stop=(5, 2, 20))


def sc_reserves(r: Rec) -> None:
    """Reserves on: a goal poked -> 12 -> B (menu), B -> 10 with Reserves: the special plays
    page, B -> the positions (Reserves) page, Up x3, A -> the substitution list (coach
    portrait), Down, A (a substitution), Start -> positions, Start -> done -> 12 -> Start -> 5."""
    scripted(r, {**BASE, 0xFFB0E6: 1},
             pokes=[(4, 1, 900, PHASE_POKE(3))],
             actions=[(12, 1, 300, 1, "B", 6), (12, 1, 420, 1, "B", 6),
                      (10, 1, 150, 1, "DOWN", 4), (10, 1, 200, 1, "B", 4), (10, 1, 300, 1, "UP", 4),
                      (10, 1, 350, 1, "UP", 4), (10, 1, 400, 1, "UP", 4), (10, 1, 450, 1, "A", 4),
                      (10, 1, 650, 1, "DOWN", 4), (10, 1, 750, 1, "A", 4), (10, 1, 900, 1, "START", 4),
                      (10, 1, 1000, 1, "START", 4),
                      (12, 2, 200, 1, "START", 6)],
             stop=(5, 1, 20))


def sc_twopads(r: Rec) -> None:
    """Pad mode 1 (P1 v P2), penalties on: a goal poked -> 12 -> B (menu), B -> 10 with two
    pages (P1: Down, B; P2: Up, C), both done -> 12 -> A -> 8 -> A -> 9 (Down x2, A: team B)
    -> Start -> 8 -> Start -> 12 -> Start -> 5."""
    scripted(r, {**BASE, 0xFFB0E0: 1, 0xFFB0E5: 1},
             pokes=[(4, 1, 900, PHASE_POKE(3))],
             actions=[(12, 1, 300, 1, "B", 6), (12, 1, 420, 1, "B", 6),
                      (10, 1, 150, 1, "DOWN", 4), (10, 1, 220, 2, "UP", 4), (10, 1, 300, 1, "B", 4),
                      (10, 1, 400, 2, "C", 4),
                      (12, 2, 150, 1, "A", 6), (8, 1, 150, 1, "A", 4), (8, 1, 300, 1, "DOWN", 4),
                      (8, 1, 400, 1, "DOWN", 4), (8, 1, 500, 1, "A", 4), (8, 1, 650, 1, "START", 4),
                      (8, 1, 900, 1, "START", 4), (12, 3, 150, 1, "START", 6)],
             stop=(5, 1, 20))


def sc_ref(r: Rec) -> None:
    """Waste the Ref poked (phase 12) -> 19 -> 17 new referee: Start in the lockout ignored,
    A does nothing, Start -> 5."""
    scripted(r, BASE, pokes=[(4, 1, 900, PHASE_POKE(12))],
             actions=[(17, 1, 100, 1, "START", 6), (17, 1, 150, 1, "A", 6), (17, 1, 400, 1, "A", 6),
                      (17, 1, 500, 1, "START", 6)],
             stop=(5, 1, 20))


def sc_forfeit(r: Rec) -> None:
    """A forfeit poked (phase 13, team B) -> 17 -> Start -> 15 (B: menu, Start -> 1)."""
    scripted(r, BASE, pokes=[(4, 1, 900, [(0xFFC60C, 0, 2), (0xFFC640, 0xFFFFB8AC, 4), (0xFFC60A, 13, 2)])],
             actions=[(17, 1, 400, 1, "START", 6), (15, 1, 300, 1, "B", 6), (15, 1, 400, 1, "START", 6)],
             stop=(1, 2, 20))


def sc_playoff(r: Rec) -> None:
    """A playoff game (play mode 1) ended by pokes (clock 2 s each period, team A ahead) -> 16:
    the comment-less intro, Start shows the menu, Start -> 11."""
    scripted(r, {**BASE, 0xFFB0E1: 1},
             pokes=[(4, 1, 900, [(0xFFB06A, 2, 2)]), (4, 2, 300, [(0xFFB06A, 2, 2)]),
                    (4, 3, 300, [(0xFFB06A, 2, 2), (SCORE_A, 2, 2)])],
             actions=[(11, 1, 200, 1, "START", 6), (11, 1, 400, 1, "START", 6),
                      (14, 1, 100, 1, "START", 6), (14, 1, 200, 1, "START", 6),
                      (14, 2, 100, 1, "START", 6), (14, 2, 200, 1, "START", 6),
                      (16, 1, 300, 1, "START", 6), (16, 1, 420, 1, "START", 6)],
             stop=(11, 2, 60), limit=40000)


SCENARIOS = {"goal": sc_goal, "period": sc_period, "fight": sc_fight, "penalty": sc_penalty, "penalty2": sc_penalty2, "ref": sc_ref,
             "forfeit": sc_forfeit, "playoff": sc_playoff,
             "pause": sc_pause, "reserves": sc_reserves, "twopads": sc_twopads}



def main() -> None:
    for name in sys.argv[1:]:
        r = Rec(name)
        SCENARIOS[name](r)
        r.finish()
        print(name, "done:", r.info(), flush=True)
        r.e.close()


if __name__ == "__main__":
    main()
