"""Playoff vectors: what the original does with given playoff states.

Runs scenarios on the original (GPGX, frame-based input from boot) and
records the playoff state (`$FFBD6A`), the setup's teams and the bracket
(`$FFC770`: A's side eight teams + seven winners, the other side's) at a
frame: a new run (seed from the main stream), a password typed into the
Continue Playoffs screen, a password shown (state poked while the screen
loads), A pressed on a new bracket (new seed). Passwords are kept as symbol
indices (0-27), not text. ``compare/fixtures/playoffs.json``; the Python
reference (``playoffs.py``) and MwPlayoffs are tested against it.

    tools/bin/py -m mw_harness playoff-vectors [NAME ...] [--update]
"""
from __future__ import annotations

import json

from .playoffs import State, alphabet, encode, PASSWORD_LEN
from .rom import REPO_ROOT

FIXTURE = REPO_ROOT / "compare" / "fixtures" / "playoffs.json"
MENU = "6509-6515:DOWN 6549-6555:DOWN"           # main menu: to the play mode row
RIGHT = ["6589-6595:RIGHT", "6609-6615:RIGHT", "6629-6635:RIGHT"]
START = "6669-6675:START"


def _typing(symbols: list[int], frame: int) -> tuple[list[str], int]:
    ev, cur = [], 0
    def press(b: str) -> None:
        nonlocal frame
        ev.append(f"{frame}-{frame + 3}:{b}")
        frame += 8
    for t in symbols:
        r0, c0 = divmod(cur, 7)
        r1, c1 = divmod(t, 7)
        while c0 != c1:
            press("RIGHT"); c0 = (c0 + 1) % 7
        while r0 != r1:
            press("DOWN"); r0 = (r0 + 1) % 4
        cur = t
        press("A")
    press("START")
    return ev, frame


def _password_state(rom: bytes) -> list[tuple[str, State]]:
    return [("typed_best_of_3", State(seed=0xABC, pair=28, conference=1, best_of_3=1, series=2, round=1,
                                      dead_a=0x2A5A5, dead_b=0x1F00F)),
            ("typed_single", State(seed=0x3E7, pair=94, round=2, dead_a=0x00F0F, flags=0x10))]


def scenarios(rom: bytes) -> dict:
    out = {"new_run": {"input": " ".join([MENU, RIGHT[0], START]), "at": 6800},
           "reroll": {"input": " ".join([MENU, RIGHT[0], START, "6800-6803:A"]), "at": 6900},
           "shown": {"input": " ".join([MENU] + RIGHT + [START]), "at": 6800,
                     "poke": "000000000000000000000000012325000000000002"}}
    abc = alphabet(rom)
    for name, st in _password_state(rom):
        pw, _ = encode(st, rom)
        syms = [abc.index(c) for c in pw]
        ev, end = _typing(syms, 6800)
        out[name] = {"input": " ".join([MENU] + RIGHT + [START] + ev), "at": end + 80, "typed": syms}
    return out


def run(sc: dict) -> dict:
    from .emulator import ReferenceEmulator, InputScript

    emu = ReferenceEmulator(None)
    script = InputScript.parse(sc["input"])
    poked = "poke" not in sc
    while emu.frame < sc["at"]:
        emu.step(script.buttons_at(emu.frame))
        if not poked and emu.state(with_cpu=False).ram_u16(0xFFB05E) == 11:
            for i, b in enumerate(bytes.fromhex(sc["poke"])):
                emu.poke(0xFFBD6A + i, b)
            poked = True
    s = emu.state(with_cpu=False)
    pw = [s.ram_u8(0xFFC7B8 + i) for i in range(PASSWORD_LEN)]
    return {"screen": s.ram_u16(0xFFB05E),
            "state": bytes(s.ram_u8(0xFFBD6A + i) for i in range(21)).hex(),
            "teams": [s.ram_u8(0xFFB0DE), s.ram_u8(0xFFB0DF)],
            "bracket": [s.ram_u16(0xFFC770 + 2 * i) for i in range(30)],
            "password_bytes": pw}


def main(update: bool = False, names=None) -> None:
    from .rom import Rom, default_rom_path

    rom = Rom.load(default_rom_path()).data
    abc = alphabet(rom)
    old = json.loads(FIXTURE.read_text())["cases"] if FIXTURE.exists() else {}
    for name, sc in scenarios(rom).items():
        if names and name not in names:
            continue
        r = run(sc)
        pw = r.pop("password_bytes")
        r["password"] = [abc.index(bytes([c])) for c in pw] if all(bytes([c]) in abc for c in pw) else None
        old[name] = {k: v for k, v in sc.items() if k != "input"} | {"input": sc["input"]} | r
        print(name, r["state"], r["teams"])
    data = {"format": "mw-playoffs/1",
            "comment": "The original's playoff state ($FFBD6A), teams and bracket ($FFC770) after each "
                       "scenario (GPGX, frame input from boot); passwords as symbol indices "
                       "(mw_harness playoff-vectors). No ROM content.",
            "cases": dict(sorted(old.items()))}
    text = "{\n" + ",\n".join(f" {json.dumps(k)}: {json.dumps(v)}" for k, v in data.items()) + "\n}\n"
    if update:
        FIXTURE.write_text(text)
        print(f"wrote {FIXTURE.relative_to(REPO_ROOT)}")
