"""Python reference of the original's playoffs: state, bracket, passwords.

docs/re/menus.md, Playoffs. The state is the 21 bytes at ``$FFBD6A``;
nothing here is ROM content except what is read from the ROM given (the
password alphabet, team strengths).

    bracket    ($11FC0)  the two conferences' eight teams from the seed
    results    ($1204A)  the winners of the seven matches of each side
    encode     ($12580)  state -> 13-character password
    decode     ($1266C)  password -> state (or None when refused)
    check      ($12776)  the check value of a password's other bits
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .rng import rng_next, rng_range

STATE_ADDR = 0xFFBD6A
ALPHABET = 0x66CD3        # 28 symbols
PASSWORD_LEN = 13
SEED_STEPS = 0x45
CHECK_STEPS = 0x27
TEAM_TABLE = 0x18D8A
TEAM_SIZE = 0x9E
NEW, SHOW_PASSWORD, CHAMPION, ELIMINATED, RANDOM_DEAD = 1, 2, 4, 8, 0x10
M32 = 0xFFFFFFFF


@dataclass
class State:
    rng: int = 0             # +$0 the playoffs' random stream
    dead_a: int = 0          # +$4
    dead_b: int = 0          # +$8 (or the check value)
    seed: int = 0            # +$C
    pair: int = 0            # +$E  A * 10 + B within the conference
    conference: int = 0      # +$F
    best_of_3: int = 0       # +$10
    flag_11: int = 0         # +$11
    series: int = 0          # +$12
    round: int = 0           # +$13
    flags: int = 0           # +$14

    @staticmethod
    def from_ram(b: bytes) -> "State":
        """From the 21 bytes at $FFBD6A."""
        u32 = lambda o: int.from_bytes(b[o:o + 4], "big")
        return State(u32(0), u32(4), u32(8), int.from_bytes(b[0xC:0xE], "big"), b[0xE], b[0xF], b[0x10],
                     b[0x11], b[0x12], b[0x13], b[0x14])

    def teams(self) -> tuple[int, int]:
        a, b = divmod(self.pair, 10)
        return (a + 10 * self.conference, b + 10 * self.conference)


def alphabet(rom: bytes) -> bytes:
    return rom[ALPHABET:ALPHABET + 28]


def check(d0: int, d1: int) -> int:
    """$12776: seed the stream with (d0 & $FFF) ^ d1, 39 steps, low 18 bits.
    (A zero seed would make the original seed from the hardware.)"""
    s = ((d0 & 0xFFF) ^ d1) & M32
    if s == 0:
        raise ValueError("check of a zero seed depends on the hardware")
    for _ in range(CHECK_STEPS):
        s = rng_next(s)
    return s & 0x3FFFF


def pack(st: State) -> tuple[int, int, int]:
    """$125F8: the state's bits as (d0, d1) and the check value (computed
    when RANDOM_DEAD, which puts it where team B's dead players would be)."""
    random_dead = bool(st.flags & RANDOM_DEAD)
    b = 0 if random_dead else st.dead_b
    d0 = ((((b << 2) | st.round) << 10) | (st.dead_a >> 8)) & M32
    d1 = st.dead_a & 0xFF
    for value, bits in ((st.series, 2), (st.flag_11, 1), (st.best_of_3, 1), (st.conference, 1), (st.pair, 7),
                        (st.seed, 12)):
        d1 = ((d1 << bits) | value) & M32
    c = 0
    if random_dead:
        c = check(d0, d1)
        d0 |= c << 12
    return d0, d1, c


def to_symbols(d0: int, d1: int, rom: bytes) -> bytes:
    """$12804: 13 base-28 digits, least significant first."""
    n = (d0 << 32) | d1
    abc = alphabet(rom)
    out = bytearray()
    for _ in range(PASSWORD_LEN):
        n, r = divmod(n, 28)
        out.append(abc[r])
    return bytes(out)


def from_symbols(pw: bytes, rom: bytes) -> tuple[int, int]:
    """$12820: back to (d0, d1); a symbol not in the alphabet counts $FFFF."""
    abc = alphabet(rom)
    n = 0
    for c in reversed(pw[:PASSWORD_LEN]):
        i = abc.find(bytes([c]))
        n = (n * 28 + (i if i >= 0 else 0xFFFF)) & ((1 << 64) - 1)
    return n >> 32, n & M32


def encode(st: State, rom: bytes) -> tuple[bytes, State]:
    """$12580 from the masks on: the password and the state as left
    (dead_b = the check value when RANDOM_DEAD)."""
    d0, d1, c = pack(st)
    out = State(**st.__dict__)
    if st.flags & RANDOM_DEAD:
        out.dead_b = c
    return to_symbols(d0, d1, rom), out


def decode(pw: bytes, rom: bytes) -> State | None:
    """$1266C: the state a password gives, None when the original refuses it."""
    return decode_bits(*from_symbols(pw, rom))


def decode_bits(d0: int, d1: int) -> State | None:
    """:func:`decode` from the password's bits."""
    try:
        c = check(d0, d1)
    except ValueError:            # a zero seed: the hardware's (never typed in practice)
        return None
    st = State()
    st.seed = d1 & 0xFFF
    st.pair = (d1 >> 12) & 0x7F
    st.conference = (d1 >> 19) & 1
    st.best_of_3 = (d1 >> 20) & 1
    st.flag_11 = (d1 >> 21) & 1
    st.series = (d1 >> 22) & 3
    st.dead_a = ((d0 & 0x3FF) << 8) | ((d1 >> 24) & 0xFF)
    st.round = (d0 >> 10) & 3
    st.dead_b = (d0 >> 12) & 0x3FFFF
    if (d0 >> 30) & 3 or st.seed == 0:
        return None
    if not st.best_of_3:
        if st.round == 3 or st.series != 0 or st.dead_b != c:
            return None
    elif st.series == 0 and st.dead_b != c:
        return None
    a, b = divmod(st.pair, 10)
    if st.pair >= 100 or a == b:
        return None
    return st


def reseed(seed: int) -> int:
    """$11FA6: the playoff stream from a seed."""
    s = seed & M32
    for _ in range(SEED_STEPS):
        s = rng_next(s)
    return s


def bracket(rng: int, team_a: int, team_b: int) -> tuple[list[int], list[int], int]:
    """$11FC0: [A's conference: A, B, six more], [the other conference's
    eight], the stream after. Teams are drawn with rng_range until unused."""
    lo, hi, other = (0, 9, 10) if team_a <= 9 else (10, 19, -10)
    used = 1 << team_a
    first = [team_a]
    t = team_b
    while used >> t & 1:
        rng, t = rng_range(rng, lo, hi)
    used |= 1 << t
    first.append(t)
    while len(first) < 8:
        rng, t = rng_range(rng, lo, hi)
        if not used >> t & 1:
            used |= 1 << t
            first.append(t)
    lo, hi, used, second = lo + other, hi + other, 0, []
    while len(second) < 8:
        rng, t = rng_range(rng, lo, hi)
        if not used >> t & 1:
            used |= 1 << t
            second.append(t)
    return first, second, rng


def strength(rom: bytes, team: int) -> int:
    """Team record +$B (signed): the skulls."""
    v = rom[TEAM_TABLE + team * TEAM_SIZE + 0xB]
    return v - 256 if v >= 128 else v


def match(rng: int, rom: bytes, t1: int, t2: int) -> tuple[int, int]:
    """$120A2: (stream, winner): t2 wins when rng_range(1, 8(s1+1) + 8(s2+1)) <= 8(s2+1)."""
    w1 = (strength(rom, t1) + 1) * 8
    w2 = (strength(rom, t2) + 1) * 8
    rng, r = rng_range(rng, 1, (w1 + w2) & 0xFFFF)
    return rng, (t2 if r <= (w2 & 0xFFFF) else t1)


def results(rng: int, rom: bytes, first: list[int], second: list[int], flag_11: int = 0) -> tuple[list[int], list[int], int]:
    """$1204A: the seven winners of each side (quarter-finals, semi-finals,
    final), matches read from the list as it grows. On A's side only the
    other matches are played (mask $3A): A advances (B instead in the first
    match when flag_11)."""
    out = []
    for side, (teams, mask) in enumerate(((first, 0x3A), (second, 0xFF))):
        lst = list(teams)
        for i in range(7):
            d3 = 6 - i
            t1, t2 = lst[2 * i], lst[2 * i + 1]
            pick = 0
            if mask >> d3 & 1:
                rng, w = match(rng, rom, t1, t2)
                pick = 0 if w == t1 else 1
            if d3 == 6 and side == 0 and flag_11:
                pick = 1
            lst.append(t2 if pick else t1)
        out.append(lst[8:])
    return out[0], out[1], rng


def opponents(first_results: list[int], second_results: list[int], first: list[int], round_: int) -> tuple[int, int]:
    """$11B4E: team A and B of the round ($1F1C0): first round A/B; then the
    winners in A's path; the cup: A's side champion vs the other side's."""
    if round_ == 3:
        return first[0], first[1]
    if round_ == 0:
        return first_results[0], first_results[1]
    if round_ == 1:
        return first_results[4], first_results[5]
    return first_results[6], second_results[6]
