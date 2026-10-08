"""Reference model of the 68000 half of Mutant League Hockey's sound driver.

The original splits sound between the 68000 and the Z80 (plan 12,
``docs/re/sound.md``): the 68000 runs a MIDI-like sequencer and a channel
allocator once per VBlank and hands the Z80 a block of per-channel "change
records"; the Z80 turns those into YM2612 / PSG writes and plays the PCM
samples. This module re-implements the 68000 half tick by tick so that its
RAM structures and its writes to Z80 RAM can be compared with the original
running in an emulator (``out/plan12/check68k.py``), and so that the Godot
port has an executable specification to test against.

The model keeps the original's state in a 64 KiB image of work RAM
(``$FF0000-$FFFFFF``, only the sound areas are used) with the same byte
layout, because the original reuses fields with different widths and the
quirks that follow from that (stale fields, caches compared by word or by
long) are part of its behaviour. Every routine is named after the original's
address. Nothing here is game content: sequences, instruments and tables are
read from the user's ROM at run time.

Entry points (the game's API, ``$13BE0-$13FFF``):

=========================  ======================================================
``reset()``                ``$13C18`` (boot ``$13BE0``): driver + data upload, state cleared
``enter_match()``          ``$13C04``: fade + crowd off, then ``reset()``
``music_start(seq)``       ``$13C66`` / ``$13C6E`` (``MUSIC_TITLE`` / ``MUSIC_GAME``)
``music_fade_out(ticks)``  ``$13CAC``
``sound_play(id)``         ``$13CEE``: sequence (id < $12) or sample voice
``random_sound(rng)``      ``$13CE2``: id 5 + (rng & 3)
``positional_sound(id)``   ``$13D58`` (the on-screen test is the caller's)
``stop_positional()``      ``$13D92``
``sound_busy(handle)``     ``$13D9C``
``sound_stop(handle)``     ``$13DC2``
``crowd_level(level)``     ``$13E52``; ``crowd_restart()`` ``$13EB6``,
                           ``crowd_fade()`` ``$13EEA``, ``crowd_off()`` ``$13EFC``
``vblank()``               ``$13DE8``: the 60 Hz task; returns the tick's Z80 writes
=========================  ======================================================
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

from .rom import Rom

# --- ROM -----------------------------------------------------------------------
Z80_DRIVER = 0x15C90          # length word + Z80 code, uploaded to Z80 RAM $0000
Z80_DATA_LEN = 0x1FFB70       # length word of the FM patch block that follows
Z80_DATA = 0x1FFB72           # FM patches (26 bytes each), uploaded after the driver
INSTRUMENTS = 0x1FF010        # 256 word offsets (from here) to instrument records
SAMPLES = 0x1C0000            # sample offsets in instruments are relative to this
SEQUENCES = 0x1F57E           # sound ids 0..$11: sequence pointers (long)
VOICE_IDS = 0x1F5C6           # sound ids $12..$4C: instrument index (word, <0 none)
MUSIC_TITLE = 0x1CDC00        # $13C66
MUSIC_GAME = 0x1CE2D0         # $13C6E
CHANNEL_RECORDS = 0x4CECE     # 14 words: channel -> its record's offset from $FFE6B0
ALLOC_CLASSES = 0x16930       # 5 x 8 bytes: first struct offset, first mask bit, count-1
NOTE_FOLD = 0x169D6           # MIDI notes $6C-$7F folded to $60-$6B (indexed -$6C)
FM_FREQ = 0x169EA             # 96 longs: linear F-number (block 0 units), C0..B7
FM_VOLUME = 0x16B6A           # volume 0..$7F -> attenuation $7F..0 (zeros beyond)
PSG_PERIOD = 0x16BEA          # words: PSG tone period by note index
PSG_VOLUME = 0x16CAA          # volume 0..$7F -> PSG attenuation $F..0
SINE = 0x1F628                # 65 words: quarter sine wave, 0..$7FFF
TEMPO_NTSC = 0x17F06          # 256 longs: BPM -> 24ths of a beat per tick (16.16), 60 Hz
TEMPO_PAL = 0x18306           # the same for 50 Hz

# --- work RAM ------------------------------------------------------------------
RECORDS = 0xFFE6B0            # change records copied to Z80 $0038 ($85 bytes)
RECORDS_LEN = 0x85
BANK_SHADOW = 0xFFE734        # last sample bank written (byte, inside the copied block)
DIRTY = 0xFFE735              # records changed this tick (byte)
PROGRAMS = 0xFFE736           # 16 bytes: program per MIDI channel (note-on instrument)
VOLUMES = 0xFFE746            # 16 bytes: CC7 volume per MIDI channel ($7F at upload)
BENDS = 0xFFE756              # 16 words: pitch bend per MIDI channel (-64..63)
TRACK_VOLUME = 0xFFE776       # word: volume of the track sending the current note
NOTE_VOLUME = 0xFFE778        # word: channel volume * track volume >> 7
PARSER_HANDLER = 0xFFE77A     # long: handler of the current MIDI status
PARSER_COUNT = 0xFFE77E       # word: data bytes received (0 = expecting status)
PARSER_LENGTH = 0xFFE780      # word: data bytes the current status takes
NOTE_SERIAL = 0xFFE782        # word: +1 per allocated note
MIDI_CHANNEL = 0xFFE784       # byte: channel of the current status
MIDI_DATA = 0xFFE785          # 2 bytes: the current message's data bytes
LOCK = 0xFFE789               # byte: a voice routine is changing state (VBlank skips)
VOICE_HANDLE = 0xFFE78A       # long: last voice handle
CHANNELS = 0xFFE78E           # 14 channel structs of $42 bytes
CHANNEL_SIZE = 0x42
N_CHANNELS = 14
SFX_CHANNELS = 0xFFEA22       # the last four: PCM voices (records at $FFE704 + 12 n)
SEQ_HANDLE = 0xFFEB2A         # long: last sequence handle
QUEUE_HEAD = 0xFFEB2E         # long: first pending note-off
QUEUE_TAIL = 0xFFEB32         # long: where the next note-off goes
QUEUE_END = 0xFFEB36          # long: end of the ring ($FFF384)
NOTES_ON = 0xFFEB3A           # word: note-ons allowed (cleared for a muted class)
MUSIC_ENABLE = 0xFFEB3C       # word: 1 (the setters $18764.. are never called)
SFX_ENABLE = 0xFFEB3E         # word: 1 (likewise)
SEQ_LOCK = 0xFFEB40           # byte: $80 while a sequence starts / stops
QUEUE_COUNT = 0xFFEB41        # byte: pending note-offs (max 64)
QUEUE_PEAK = 0xFFEB42         # byte: highest count seen
TRACKS_ACTIVE = 0xFFEB43      # byte: tracks playing
TRACKS = 0xFFEB44             # 32 track structs of $2A bytes
TRACK_SIZE = 0x2A
N_TRACKS = 32
QUEUE = 0xFFF084              # 64 note-offs of 12 bytes
QUEUE_ENTRY = 12
QUEUE_SIZE = 0x300
TRACK_PROGRAMS = 0xFFF384     # 16 bytes: program last sent per MIDI channel
SAMPLE_BASE = 0xFFE6AA        # long: SAMPLES ($15B46)
INSTRUMENT_BASE = 0xFFE6A6    # long: INSTRUMENTS ($15B4C)
DRIVER_LENGTH = 0xFFE6AE      # word: Z80 driver length = Z80 address of the patches

# game side ($13BE0-$13FFF)
MUSIC_HANDLE = 0xFFCA2C       # long: -1 none
MUSIC_SEQ = 0xFFCA30          # long: 0 none
MUSIC_REPEAT = 0xFFCA34       # word ($FFxx via st.b): restart the music when it ends
MUSIC_FADE = 0xFFCA36         # word: ticks left before the music stops
API_DEPTH = 0xFFCA38          # word: an API call is running (VBlank skips crowd/timeout)
CROWD_HANDLE = 0xFFCA3A       # long: crowd voice handle, -1 none
CROWD_RATE = 0xFFCA3E         # word: current crowd playback rate
CROWD_VOL = 0xFFCA40          # word: current crowd volume
CROWD_RATE_TARGET = 0xFFCA42
CROWD_VOL_TARGET = 0xFFCA44
CROWD_ON = 0xFFCA46           # word ($FFxx via st.b)
POSITIONAL = 0xFFCA48         # long: handle of the last $13D58 sound
POSITIONAL_AGE = 0xFFCA4C     # word: ticks since it started (stopped at 60)

#: the RAM the model owns (half-open ranges), for comparisons
GAME_VARS = (0xFFCA2C, 0xFFCA4E)
DRIVER_VARS = (0xFFE6A6, 0xFFF394)

# channel struct fields
CH_INSTR = 0x00         # long: instrument record (-1 none)
CH_PATCH = 0x04         # long: instrument whose FM patch the Z80 has (-1 none)
CH_RECORD = 0x08        # long: its change record
CH_CACHE = 0x0C         # long (FM) / word (PCM, PSG): last output pitch; PCM voices: handle
CH_SERIAL = 0x10        # word: note serial (note-off takes the oldest)
CH_BEND_KEY = 0x12      # word: note index (x2 / x4) the bend delta was computed for
CH_BEND = 0x14          # word: the MIDI channel's bend at note-on / last bend
CH_BANKS = 0x16         # long: bank mask of a PCM voice
CH_BEND_DELTA = 0x1A    # word (PCM, PSG) / long (FM)
CH_INDEX = 0x1E         # byte: 0..13
CH_MIDI = 0x1F          # byte: MIDI channel
CH_STATE = 0x20         # byte: $FF free, 0 music note, 1 voice (sound_play / crowd)
CH_PRIORITY = 0x21      # byte
CH_RELEASE = 0x22       # byte: FM release ticks left
CH_NOTE = 0x23          # byte: MIDI note
CH_KEY = 0x24           # byte: note index into the pitch tables
CH_PHASE = 0x25         # byte: 0 off, 1 sounding, 2 FM releasing
CH_PENV_STATE = 0x26    # bytes: modulator states (0, 2, 4, ...)
CH_VENV_STATE = 0x27
CH_ARP_STATE = 0x28
CH_VIB_STATE = 0x29
CH_VOLUME = 0x2A        # word: velocity * note volume >> 7
CH_PENV = 0x2C          # word: pitch envelope value
CH_PENV_TIMER = 0x2E
CH_VENV = 0x30          # word: volume envelope value
CH_VENV_TIMER = 0x32
CH_ARP = 0x34           # word: arpeggio offset (note index)
CH_ARP_TIMER = 0x36
CH_ARP_STEP_TIMER = 0x38
CH_ARP_POS = 0x3A
CH_VIB = 0x3C           # word: vibrato value
CH_VIB_TIMER = 0x3E
CH_VIB_PHASE = 0x40

# track struct fields
TR_STATE = 0x00         # byte: 0 playing, 1 free, $FF paused (pause: unused $1881C)
TR_CHANNEL = 0x01       # byte: MIDI channel
TR_LOOP_COUNT = 0x02
TR_INDEX = 0x03         # byte: track number in its sequence
TR_TEMPO = 0x04         # long: 16.16 clocks per tick
TR_FRACTION = 0x08      # word: fractional clock
TR_VOLUME = 0x0A        # word: $80 = full
TR_VOLUME_TARGET = 0x0C
TR_FADE_STEP = 0x0E
TR_LOOP = 0x10          # long: loop start
TR_START = 0x14         # long: first event (after the initial delta)
TR_POS = 0x18           # long: next event
TR_WAIT = 0x1C          # long: clocks to wait - 1
TR_FIRST_WAIT = 0x20    # long
TR_HANDLE = 0x24        # long: sequence handle
TR_PROGRAM = 0x28       # byte: program
TR_SLOT = 0x29          # byte: 0..31

# instrument types (byte 0) = allocation classes
PCM, FM, PSG, PCM_PITCHED, NOISE = 0, 1, 2, 3, 4

# Z80 RAM
Z80_RECORDS = 0x0038
Z80_PENDING = 0x00BD
Z80_VOICE_STATUS = (0x00BE, 0x00CE, 0x00DE, 0x00EE)


def _ptr(a: int) -> int:
    """A RAM address as the original stores it: ``lea $xxxx.w`` sign-extends,
    so pointers into $FF8000-$FFFFFF read $FFFFxxxx."""
    return a | 0xFF000000


def _s8(v: int) -> int:
    v &= 0xFF
    return v - 0x100 if v & 0x80 else v


def _s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def _s32(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


class Z80Link:
    """What the 68000 sees of the Z80. The default is an ideal Z80: it always
    takes a block before the next tick and never reports a voice as finished.
    The checks substitute the emulator's answers; the port its PCM player."""

    def pending(self) -> bool:
        """Z80 RAM $00BD != 0 at the start of the tick (block not taken yet)."""
        return False

    def voice_done(self, voice: int) -> bool:
        """The status byte of PCM voice 0..3 ($BE/$CE/$DE/$EE) has bit 7 set."""
        return False


@dataclass
class TickOutput:
    """What one tick (``$17B20``) did to the Z80 side."""

    skipped: str = ""                       # "z80" ($BD set) or "lock" ($E789 set)
    block: bytes | None = None              # $85 bytes written to Z80 $0038 (then $BD = 1)
    voice_clears: list[int] = field(default_factory=list)   # voices whose status was cleared

    def z80_writes(self) -> list[tuple[int, bytes]]:
        out: list[tuple[int, bytes]] = []
        if self.block is not None:
            out += [(Z80_RECORDS, self.block), (Z80_PENDING, b"\x01")]
        out += [(Z80_VOICE_STATUS[v], b"\x00") for v in self.voice_clears]
        return out


class Sound68k:
    """The 68000 side of the sound driver, stepped by :meth:`vblank`."""

    def __init__(self, rom: Rom, pal: bool = False, z80: Z80Link | None = None,
                 ram: bytes | None = None):
        self.rom = rom.data
        self.pal = pal
        self.z80 = z80 or Z80Link()
        self.mem = bytearray(ram if ram is not None else bytes(0x10000))
        #: called with (kind, *args) for MIDI messages and allocations (tests, tracing)
        self.trace: Callable[..., None] | None = None
        #: bits 8-15 of the caller's d5 in music_fade_out (see there)
        self.d5_high = 0

    # ---- memory -----------------------------------------------------------
    def r8(self, a: int) -> int:
        return self.mem[a & 0xFFFF]

    def r16(self, a: int) -> int:
        a &= 0xFFFF
        return (self.mem[a] << 8) | self.mem[a + 1]

    def r32(self, a: int) -> int:
        return (self.r16(a) << 16) | self.r16(a + 2)

    def w8(self, a: int, v: int) -> None:
        self.mem[a & 0xFFFF] = v & 0xFF

    def w16(self, a: int, v: int) -> None:
        a &= 0xFFFF
        self.mem[a] = (v >> 8) & 0xFF
        self.mem[a + 1] = v & 0xFF

    def w32(self, a: int, v: int) -> None:
        self.w16(a, v >> 16)
        self.w16(a + 2, v)

    def rom8(self, a: int) -> int:
        return self.rom[a & 0xFFFFFF]

    def rom16(self, a: int) -> int:
        a &= 0xFFFFFF
        return (self.rom[a] << 8) | self.rom[a + 1]

    def rom32(self, a: int) -> int:
        return (self.rom16(a) << 16) | self.rom16(a + 2)

    def _vlq(self, a: int) -> tuple[int, int]:
        """``$17EE4``: MIDI variable-length number at ROM ``a`` -> (value, next)."""
        v = 0
        while True:
            b = self.rom8(a)
            a += 1
            v = ((v << 7) | (b & 0x7F)) & 0xFFFFFFFF
            if not b & 0x80:
                return v, a

    def instrument(self, index: int) -> int:
        """ROM address of instrument ``index`` (table at ``$E6A6``)."""
        base = self.r32(INSTRUMENT_BASE)
        return base + self.rom16(base + 2 * (index & 0x7FFF))

    def channel(self, n: int) -> int:
        return CHANNELS + n * CHANNEL_SIZE

    # ---- set-up -------------------------------------------------------------
    def reset(self) -> None:
        """``$13C18`` (also ``$13BE0`` at boot): game-side state cleared, the
        Z80 driver and the FM patches uploaded, all driver state reset."""
        self.w32(MUSIC_HANDLE, 0xFFFFFFFF)
        self.w32(MUSIC_SEQ, 0)
        self.w16(MUSIC_REPEAT, 0)
        self.w16(MUSIC_FADE, 0)
        self.w16(API_DEPTH, 0)
        self.w32(CROWD_HANDLE, 0xFFFFFFFF)
        self.w16(CROWD_ON, 0)
        self.w32(POSITIONAL, 0xFFFFFFFF)
        self.w16(POSITIONAL_AGE, 0)
        # $16922 = $168BE (clears $FFE6B0-$FFE735, uploads the driver), $18706, $15C14
        for a in range(RECORDS, RECORDS + 0x86):
            self.w8(a, 0)
        self.w16(DRIVER_LENGTH, self.rom16(Z80_DRIVER))
        self._seq_init()
        self._channels_init()
        # $15B4C: the FM patches to Z80 RAM after the driver
        self.w32(INSTRUMENT_BASE, INSTRUMENTS)
        for n in range(N_CHANNELS):
            self.w32(self.channel(n) + CH_PATCH, 0xFFFFFFFF)
        for c in range(16):
            self.w8(VOLUMES + c, 0x7F)
        self.w32(SAMPLE_BASE, SAMPLES)      # $15B46

    def enter_match(self, d0: int = 0) -> None:
        """``$13C04`` (match, play-offs, fight): music fade (its d0 is the
        caller's, so the tracks get stale fade fields), crowd off, reset."""
        self.music_fade_out(d0)
        self.crowd_off()
        self.reset()

    def z80_upload(self) -> list[tuple[int, bytes]]:
        """The Z80 RAM a reset writes: driver at $0000, patches after it."""
        n = self.rom16(Z80_DRIVER)
        m = self.rom16(Z80_DATA_LEN)
        return [(0, self.rom[Z80_DRIVER + 2:Z80_DRIVER + 2 + n]),
                (n, self.rom[Z80_DATA:Z80_DATA + m])]

    def _seq_init(self) -> None:
        """``$18706``: tracks free (only state and slot written), queue empty."""
        self.w8(QUEUE_COUNT, 0)
        self.w8(TRACKS_ACTIVE, 0)
        self.w8(QUEUE_PEAK, 0)
        self.w32(QUEUE_HEAD, _ptr(QUEUE))
        self.w32(QUEUE_TAIL, _ptr(QUEUE))
        self.w32(QUEUE_END, _ptr(QUEUE + QUEUE_SIZE))
        self.w32(SEQ_HANDLE, 0)
        for i in range(N_TRACKS):
            t = TRACKS + i * TRACK_SIZE
            self.w8(t + TR_STATE, 1)
            self.w8(t + TR_SLOT, i)
        self.w16(MUSIC_ENABLE, 1)
        self.w16(SFX_ENABLE, 1)
        self.w8(SEQ_LOCK, 0)

    def _records_unchanged(self) -> None:
        """``$15BA8``: every record's flag/value bytes back to $FF ("no change")."""
        for o in (0, 4, 0xA, 0xE, 0x14, 0x18, 0x1E, 0x22, 0x28, 0x2C, 0x32, 0x36,
                  0x3C, 0x42, 0x48, 0x4E, 0x54, 0x58, 0x60, 0x64, 0x6C, 0x70, 0x78, 0x7C):
            self.w32(RECORDS + o, 0xFFFFFFFF)
        self.w8(DIRTY, 0)

    def _channels_init(self) -> None:
        """``$15C14``."""
        self.w32(VOICE_HANDLE, 0)
        self.w16(NOTE_SERIAL, 0)
        self.w16(TRACK_VOLUME, 0x80)
        self._records_unchanged()
        for n in range(N_CHANNELS):
            c = self.channel(n)
            self.w8(c + CH_STATE, 0xFF)
            self.w8(c + CH_INDEX, n)
            self.w32(c + CH_INSTR, 0xFFFFFFFF)
            self.w32(c + CH_PATCH, 0xFFFFFFFF)
            rec = RECORDS + self.rom16(CHANNEL_RECORDS + 2 * n)
            self.w32(c + CH_RECORD, _ptr(rec))
            self.w16(rec, 0)          # "changed, key off"
        for c in range(16):
            self.w16(BENDS + 2 * c, 0)
        self.w8(LOCK, 0)
        self.w16(NOTES_ON, 1)
        self.w8(DIRTY, 1)
        self.w16(PARSER_COUNT, 0)

    # ---- game API ($13C66 ..) ----------------------------------------------------
    def music_start(self, seq: int) -> None:
        """``$13C66`` / ``$13C6E``: play sequence ``seq`` (ROM address) and repeat
        it; nothing restarts if it is already the current music."""
        if self.r32(MUSIC_SEQ) != seq:
            if self.r32(MUSIC_SEQ) != 0:
                self.seq_stop(self.r32(MUSIC_HANDLE))
            self.w32(MUSIC_SEQ, seq)
            self.w32(MUSIC_HANDLE, self.seq_start(seq))
        self.w8(MUSIC_REPEAT, 0xFF)          # st.b: the word's high byte
        self.w16(MUSIC_FADE, 0)

    def music_fade_out(self, ticks: int) -> None:
        """``$13CAC``: stop the music after ``ticks`` (0 = 1) ticks. It also asks
        the sequencer for a fade to 0 with step ($100 + ticks) / 2 / ticks, but
        ``$1896C`` moves only that step's (negated) low byte into d5 before
        storing the word: the high byte is the caller's d5 bits 8-15
        (``self.d5_high``). With $FF the step is -4..-1 and the track volume
        rises; otherwise it is >= $F8 and the volume is 0 at the next clock
        (new notes muted, sounding ones play on). The music stops when the
        count ends either way."""
        if self.r32(MUSIC_SEQ) == 0:
            return
        ticks &= 0xFFFF
        if ticks == 0:
            ticks = 1
        self.w16(MUSIC_FADE, ticks)
        q = (((0x100 + ticks) & 0xFFFF) >> 1) // ticks
        self.seq_fade(self.r32(MUSIC_HANDLE), -1, 0, -q, self.d5_high << 8)

    def sound_play(self, sound_id: int) -> int:
        """``$13CEE``: stops the last positional sound, then starts ``sound_id``:
        ids 0..$11 are sequences (handle with bit 31 set), $12..$4C sample
        voices (instrument from ``$1F5C6``, rate $100, volume $100 -> $80).
        Returns the handle (-1 when the voice could not start; for ids the
        tables don't cover, garbage as in the original)."""
        self._api(+1)
        self.sound_stop(self.r32(POSITIONAL))
        d0 = sound_id & 0xFFFF
        if d0 < 0x12:
            seq = self.rom32(SEQUENCES + 4 * d0)
            handle = self.seq_start(seq) | 0x80000000 if seq else 4 * d0
        elif d0 - 0x12 < 0x3B:
            index = self.rom16(VOICE_IDS + 2 * (d0 - 0x12))
            handle = index if index & 0x8000 else self.voice_start(index, 0x100, 0x100)
        else:
            handle = d0 - 0x12
        self._api(-1)
        return handle & 0xFFFFFFFF

    def random_sound(self, rng: int) -> int:
        """``$13CE2``: sound 5 + (rng_next() & 3)."""
        return self.sound_play(5 + (rng & 3))

    def positional_sound(self, sound_id: int, on_screen: bool = True) -> None:
        """``$13D58`` (the rink's objects): when the object is on screen
        (``$5C3C``), stop the last positional sound, start this one, restart
        its 60-tick limit and the crowd if it stopped."""
        self._api(+1)
        if on_screen:
            self.sound_stop(self.r32(POSITIONAL))
            self.w32(POSITIONAL, self.sound_play(sound_id))
            self.w16(POSITIONAL_AGE, 0)
            self.crowd_restart()
        self._api(-1)

    def stop_positional(self) -> None:
        """``$13D92``."""
        self.sound_stop(self.r32(POSITIONAL))

    def sound_busy(self, handle: int) -> bool:
        """``$13D9C``."""
        if handle & 0x80000000:
            return self.seq_busy(handle & 0x7FFFFFFF)
        return self.voice_busy(handle)

    def sound_stop(self, handle: int) -> None:
        """``$13DC2``."""
        self._api(+1)
        if handle & 0x80000000:
            self.seq_stop(handle & 0x7FFFFFFF)
        else:
            self.voice_stop(handle)
        self._api(-1)

    def crowd_level(self, level: int) -> None:
        """``$13E52``: crowd noise (instrument $50, a looped sample on the
        fourth PCM voice) at ``level`` 0..1000: started if needed (rate $E0,
        volume $40), then rate and volume glide (``$13F1C``) towards
        $C0 + q and $80 + 2q, q = level * $80 / 1000."""
        self._api(+1)
        h = self.r32(CROWD_HANDLE)
        if not (self.r16(CROWD_ON) and not h & 0x80000000 and self.voice_busy(h)):
            self.w16(CROWD_RATE, 0xE0)
            self.w16(CROWD_VOL, 0x40)
            h = self.voice_start(0x50, 0xE0, 0x40)
            self.w32(CROWD_HANDLE, h)
            if h & 0x80000000:
                self._api(-1)
                return
            self.w8(CROWD_ON, 0xFF)
        q = (((level & 0xFFFF) * 0x80) // 1000) & 0xFFFF
        self.w16(CROWD_VOL_TARGET, 2 * q + 0x80)
        self.w16(CROWD_RATE_TARGET, q + 0xC0)
        self._api(-1)

    def crowd_restart(self) -> None:
        """``$13EB6``: restart the crowd voice (current rate / volume) when it
        is on but no longer playing."""
        self._api(+1)
        if self.r16(CROWD_ON):
            h = self.r32(CROWD_HANDLE)
            if h & 0x80000000 or not self.voice_busy(h):
                self.w32(CROWD_HANDLE, self.voice_start(0x50, self.r16(CROWD_RATE),
                                                        self.r16(CROWD_VOL)))
        self._api(-1)

    def crowd_fade(self) -> None:
        """``$13EEA``: crowd off by fading (volume -8 per tick, then stopped)."""
        self.w16(CROWD_ON, 0)
        self.w16(CROWD_VOL_TARGET, 0)

    def crowd_off(self) -> None:
        """``$13EFC``: crowd voice stopped at once."""
        self._api(+1)
        h = self.r32(CROWD_HANDLE)
        if not h & 0x80000000:
            self.voice_stop(h)
            self.w32(CROWD_HANDLE, 0xFFFFFFFF)
        self.w16(CROWD_ON, 0)
        self._api(-1)

    def _api(self, d: int) -> None:
        self.w16(API_DEPTH, self.r16(API_DEPTH) + d)

    def _crowd_tick(self) -> None:
        """``$13F1C``: rate +-4 and volume +-8 per tick towards the targets."""
        h = self.r32(CROWD_HANDLE)
        if h & 0x80000000:
            return
        rate, target = _s16(self.r16(CROWD_RATE)), _s16(self.r16(CROWD_RATE_TARGET))
        if rate != target:
            rate = min(rate + 4, target) if rate < target else max(rate - 4, target)
            self.w16(CROWD_RATE, rate)
            self.voice_rate(h, rate)
        vol, target = _s16(self.r16(CROWD_VOL)), _s16(self.r16(CROWD_VOL_TARGET))
        if vol == target:
            return
        vol = min(vol + 8, target) if vol < target else max(vol - 8, target)
        if vol == 0 and not self.r16(CROWD_ON):
            self.voice_stop(h)
            self.w32(CROWD_HANDLE, 0xFFFFFFFF)
            return
        self.w16(CROWD_VOL, vol)
        self.voice_volume(h, vol)

    def vblank(self) -> TickOutput:
        """``$13DE8``, the VBlank task (every vblank: 60 Hz NTSC, 50 Hz PAL)."""
        fade = self.r16(MUSIC_FADE)
        if fade:
            fade -= 1
            self.w16(MUSIC_FADE, fade)
            if fade == 0:
                self.seq_stop(self.r32(MUSIC_HANDLE))
                self.w32(MUSIC_HANDLE, 0xFFFFFFFF)
                self.w32(MUSIC_SEQ, 0)
                self.w16(MUSIC_REPEAT, 0)
        if self.r16(MUSIC_REPEAT) and not self.seq_busy(self.r32(MUSIC_HANDLE)):
            self.w32(MUSIC_HANDLE, self.seq_start(self.r32(MUSIC_SEQ)))
        if self.r16(API_DEPTH) == 0:
            self._crowd_tick()
            age = (self.r16(POSITIONAL_AGE) + 1) & 0xFFFF
            self.w16(POSITIONAL_AGE, age)
            if age >= 60:
                self.sound_stop(self.r32(POSITIONAL))
        return self.driver_tick()

    # ---- the driver's tick ($17B20) -----------------------------------------------
    def driver_tick(self) -> TickOutput:
        """``$17B20``: modulators, sequencer, then the change records to the Z80
        and the finished PCM voices freed."""
        out = TickOutput()
        if self.z80.pending():                 # the Z80 has not taken the last block
            out.skipped = "z80"
            return out
        if self.r8(LOCK):
            out.skipped = "lock"
            return out
        if not self.r8(SEQ_LOCK):
            self.channels_tick()                # $1715E
            self.seq_tick()                     # $18CD0
        copied = False
        if self.r8(DIRTY):
            start = RECORDS & 0xFFFF
            out.block = bytes(self.mem[start:start + RECORDS_LEN])
            copied = True
        for v in range(4):
            rec = RECORDS + 0x54 + 12 * v
            if self.z80.voice_done(v) and self.r8(rec) & 0x80:
                out.voice_clears.append(v)
                self.w8(SFX_CHANNELS + v * CHANNEL_SIZE + CH_STATE, 0xFF)
        if copied:
            self._records_unchanged()
        return out

    # ---- sequencer ($18890 ..) ---------------------------------------------------
    def seq_start(self, seq: int) -> int:
        """``$18890``: start every track of sequence ``seq`` on a free track
        slot (searched from slot 0 for each); returns the new handle."""
        handle = (self.r32(SEQ_HANDLE) + 1) & 0xFFFFFFFF
        self.w32(SEQ_HANDLE, handle)
        saved_lock = self.r8(SEQ_LOCK)
        self.w8(SEQ_LOCK, 0x80)
        n_tracks = self.rom16(seq + 2)
        tempo_table = TEMPO_PAL if self.pal else TEMPO_NTSC
        i = 0
        while True:
            pos = seq + _s16(self.rom16(seq + 4 + 4 * i))
            midi = self.rom16(seq + 6 + 4 * i)
            t = None
            for s in range(N_TRACKS):
                u = TRACKS + s * TRACK_SIZE
                st = self.r8(u + TR_STATE)
                if st != 0 and not st & 0x80:
                    t = u
                    break
            if t is None:
                break
            self.w8(t + TR_STATE, 0)
            self.w8(TRACKS_ACTIVE, self.r8(TRACKS_ACTIVE) + 1)
            self.w32(t + TR_HANDLE, handle)
            self.w8(t + TR_INDEX, i)
            self.w8(t + TR_CHANNEL, midi)
            self.w32(t + TR_TEMPO, self.rom32(tempo_table + 4 * self.rom8(seq + 1)))
            self.w16(t + TR_FRACTION, 0)
            self.w16(t + TR_VOLUME, 0x80)
            self.w16(t + TR_VOLUME_TARGET, 0x80)
            self.w16(t + TR_FADE_STEP, 0)
            wait, pos = self._vlq(pos)
            self.w32(t + TR_START, pos)
            self.w32(t + TR_POS, pos)
            if wait:
                wait -= 1
            self.w32(t + TR_WAIT, wait)
            self.w32(t + TR_FIRST_WAIT, wait)
            i = (i + 1) & 0xFFFF
            if i == n_tracks:
                break
        self.w8(SEQ_LOCK, saved_lock)
        return handle

    def seq_stop(self, handle: int) -> None:
        """``$187B4``: free the playing tracks of ``handle``; their pending
        note-offs get duration 0 (sent at the next tick)."""
        saved = self.r8(SEQ_LOCK)
        self.w8(SEQ_LOCK, 0x80)
        handle &= 0xFFFFFFFF
        for s in range(N_TRACKS):
            t = TRACKS + s * TRACK_SIZE
            if self.r32(t + TR_HANDLE) != handle or self.r8(t + TR_STATE) != 0:
                continue
            self.w8(TRACKS_ACTIVE, self.r8(TRACKS_ACTIVE) - 1)
            self.w8(t + TR_STATE, 1)
            slot = self.r8(t + TR_SLOT)
            e = self.r32(QUEUE_HEAD)
            while e != self.r32(QUEUE_TAIL):
                if self.r8(e + 10) == slot:
                    self.w32(e, 0)
                e += QUEUE_ENTRY
                if e == self.r32(QUEUE_END):
                    e = _ptr(QUEUE)
        self.w8(SEQ_LOCK, saved)

    def seq_busy(self, handle: int) -> bool:
        """``$189BE``: a track of ``handle`` is playing."""
        handle &= 0xFFFFFFFF
        for s in range(N_TRACKS):
            t = TRACKS + s * TRACK_SIZE
            if self.r8(t + TR_STATE) == 0 and self.r32(t + TR_HANDLE) == handle:
                return True
        return False

    def seq_fade(self, handle: int, track: int, target: int, step: int, d5: int) -> None:
        """``$1896C``: fade the tracks of ``handle`` (``track`` < 0: all, else
        only the one with that index) to volume ``target``; ``step``'s low
        byte is the step per clock (0: jump at once). The stored step word is
        d5 with that byte moved into its low byte: its high byte is whatever
        the caller had in d5 (0 after a track that was at the target)."""
        for s in range(N_TRACKS):
            t = TRACKS + s * TRACK_SIZE
            if self.r8(t + TR_STATE) != 0 or self.r32(t + TR_HANDLE) != handle & 0xFFFFFFFF:
                continue
            if track >= 0 and self.r8(t + TR_INDEX) != track:
                continue
            d5 = (d5 & ~0xFF) | (step & 0xFF)
            if step & 0xFF == 0:
                self.w16(t + TR_VOLUME, target)
            self.w16(t + TR_VOLUME_TARGET, target)
            if self.r16(t + TR_VOLUME) == target & 0xFFFF:
                d5 &= ~0xFFFF
            self.w16(t + TR_FADE_STEP, d5)
            if track >= 0:
                return

    def seq_tick(self) -> None:
        """``$18CD0``: pending note-offs (head to tail; an expired entry is
        replaced by the head entry, the head advances), then each playing
        track's whole clocks this tick."""
        if self.r8(QUEUE_COUNT):
            e = self.r32(QUEUE_HEAD)
            while True:
                left = (self.r32(e) - self.r32(e + 4)) & 0xFFFFFFFF
                self.w32(e, left)
                if left == 0 or left & 0x80000000:
                    self.midi(0x80 | self.r8(e + 9))
                    self.midi(self.r8(e + 8))
                    self.midi(0)
                    head = self.r32(QUEUE_HEAD)
                    if head != e:
                        for k in range(0, 12, 4):
                            self.w32(e + k, self.r32(head + k))
                    head += QUEUE_ENTRY
                    if head == self.r32(QUEUE_END):
                        head = _ptr(QUEUE)
                    self.w32(QUEUE_HEAD, head)
                    self.w8(QUEUE_COUNT, self.r8(QUEUE_COUNT) - 1)
                e += QUEUE_ENTRY
                if e == self.r32(QUEUE_END):
                    e = _ptr(QUEUE)
                if e == self.r32(QUEUE_TAIL):
                    break
        if not self.r8(TRACKS_ACTIVE):
            return
        for s in range(N_TRACKS):
            t = TRACKS + s * TRACK_SIZE
            if self.r8(t + TR_STATE) != 0:
                continue
            acc = self.r16(t + TR_FRACTION) + self.r32(t + TR_TEMPO)
            self.w16(t + TR_FRACTION, acc)
            for _ in range((acc >> 16) & 0xFFFF):
                if self.track_clock(t):
                    return          # a sequence ended or looped: no more tracks this tick

    def track_clock(self, t: int) -> bool:
        """``$189E0``: one MIDI clock (1/24 beat) of track ``t``: the volume
        fade, then the events due. True when a sequence stopped / looped.
        (No state test: a track that ended earlier in this tick runs its
        remaining clocks again from its last saved position.)"""
        vol = _s16(self.r16(t + TR_VOLUME))
        target = _s16(self.r16(t + TR_VOLUME_TARGET))
        step = _s16(self.r16(t + TR_FADE_STEP))
        if vol != target:
            if vol < target:
                vol = _s16(vol + step)
                if not vol < target:
                    vol = target
            else:
                vol = _s16(vol - step)
                if not vol > target:
                    vol = target
            self.w16(t + TR_VOLUME, vol)
        wait = self.r32(t + TR_WAIT)
        if wait:
            self.w32(t + TR_WAIT, wait - 1)
            return False
        enable = SFX_ENABLE if self.r8(t + TR_HANDLE) & 0x80 else MUSIC_ENABLE
        if not self.r16(enable):
            self.w16(NOTES_ON, 0)
        pos = self.r32(t + TR_POS)
        ch = self.r8(t + TR_CHANNEL)
        while True:
            op = self.rom8(pos)
            pos += 1
            if op < 0xD9:
                pos = self._note(t, op, pos)
            elif op > 0xEA or op == 0xE6:
                raise RuntimeError(f"illegal sequence opcode {op:#x} at {pos - 1:#x}")
            elif op == 0xE2:                    # loop start: count
                self.w8(t + TR_LOOP_COUNT, self.rom8(pos))
                pos += 1
                self.w32(t + TR_LOOP, pos)
            elif op == 0xE3:                    # loop end
                n = self.r8(t + TR_LOOP_COUNT)
                if n:
                    self.w8(t + TR_LOOP_COUNT, n - 1)
                    pos = self.r32(t + TR_LOOP)
            elif op == 0xD9:                    # end of track (position not saved)
                if self.r8(t + TR_STATE) == 0:
                    self.w8(t + TR_STATE, 1)
                    self.w8(TRACKS_ACTIVE, self.r8(TRACKS_ACTIVE) - 1)
                return False
            elif op == 0xDA:                    # end of sequence: all its tracks
                h = self.r32(t + TR_HANDLE)
                for s in range(N_TRACKS):
                    u = TRACKS + s * TRACK_SIZE
                    if self.r8(u + TR_STATE) == 0 and self.r32(u + TR_HANDLE) == h:
                        self.w8(u + TR_STATE, 1)
                        self.w8(TRACKS_ACTIVE, self.r8(TRACKS_ACTIVE) - 1)
                self.w16(NOTES_ON, 1)
                return True
            elif op == 0xDB:                    # restart all its tracks
                h = self.r32(t + TR_HANDLE)
                for s in range(N_TRACKS):
                    u = TRACKS + s * TRACK_SIZE
                    if self.r8(u + TR_STATE) == 0 and self.r32(u + TR_HANDLE) == h:
                        self.w32(u + TR_POS, self.r32(u + TR_START))
                        self.w32(u + TR_WAIT, self.r32(u + TR_FIRST_WAIT))
                        self.w16(u + TR_FRACTION, 0)
                self.w16(NOTES_ON, 1)
                return True
            elif op == 0xDC:                    # program change
                self.midi(0xC0 | ch)
                prog = self.rom8(pos)
                pos += 1
                self.w8(t + TR_PROGRAM, prog)
                self.w8(TRACK_PROGRAMS + ch, prog)
                self.midi(prog)
            elif op in (0xDD, 0xDE):            # one ignored byte (DD: the tempo in BPM)
                pos += 1
            elif op == 0xDF:                    # control change
                self.midi(0xB0 | ch)
                self.midi(self.rom8(pos))
                self.midi(self.rom8(pos + 1))
                pos += 2
            elif op == 0xE5:                    # pitch bend
                self.midi(0xE0 | ch)
                self.midi(self.rom8(pos))
                self.midi(self.rom8(pos + 1))
                pos += 2
            elif op == 0xE7:                    # skip n bytes
                pos += 1 + self.rom8(pos)
            elif op == 0xEA:                    # skip 1 byte
                pos += 1
            # $E0 $E1 $E4 $E8 $E9: no operand, nothing
            delta, pos = self._vlq(pos)
            if delta:
                self.w32(t + TR_POS, pos)
                self.w32(t + TR_WAIT, delta - 1)
                self.w16(NOTES_ON, 1)
                return False

    def _note(self, t: int, op: int, pos: int) -> int:
        """A note event (``$18BCA``): key (+ velocity byte if bit 7, else $7F),
        VLQ length in clocks; note-off queued, the program re-sent if the
        channel's last one differs, note-on sent. Skipped when the length or
        the track volume is 0 or the queue is full."""
        if op & 0x80:
            key = op & 0x7F
            vel = self.rom8(pos)
            pos += 1
        else:
            key = op
            vel = 0x7F
        length, pos = self._vlq(pos)
        if length == 0:
            return pos
        vol = self.r16(t + TR_VOLUME)
        if vol == 0:
            return pos
        self.w16(TRACK_VOLUME, vol)
        if key >= 0x58:
            raise RuntimeError(f"note {key:#x} out of range")
        key += 0x18
        if self.r8(QUEUE_COUNT) == 0x40:
            return pos
        e = self.r32(QUEUE_TAIL)
        self.w32(e, (((length & 0xFFFF) << 16) - self.r16(t + TR_FRACTION)) & 0xFFFFFFFF)
        self.w32(e + 4, self.r32(t + TR_TEMPO))
        ch = self.r8(t + TR_CHANNEL)
        self.w8(e + 8, key)
        self.w8(e + 9, ch)
        self.w8(e + 10, self.r8(t + TR_SLOT))
        e += QUEUE_ENTRY
        if e == self.r32(QUEUE_END):
            e = _ptr(QUEUE)
        self.w32(QUEUE_TAIL, e)
        n = (self.r8(QUEUE_COUNT) + 1) & 0xFF
        self.w8(QUEUE_COUNT, n)
        if not _s8(n) < _s8(self.r8(QUEUE_PEAK)):
            self.w8(QUEUE_PEAK, n)
        if ch != 9:
            prog = self.r8(t + TR_PROGRAM)
            if prog != self.r8(TRACK_PROGRAMS + ch):
                self.midi(0xC0 | ch)
                self.midi(prog)
        self.midi(0x90 | ch)
        self.midi(key)
        self.midi(vel)
        return pos

    # ---- MIDI messages ($17356) ---------------------------------------------------
    #: status >> 4 & 7 -> (handler address kept at $E77A, name, data bytes): table $173CA
    MESSAGES = ((0x173EA, "note_off", 2), (0x174D2, "note_on", 2), (0x1797C, "nothing", 2),
                (0x178AA, "control", 2), (0x178F0, "program", 1), (0x1797C, "nothing", 2),
                (0x17904, "bend", 2), (0x1797E, "nothing", 2))

    def midi(self, byte: int) -> None:
        """``$17356``: one byte of a MIDI message (running status kept)."""
        count = self.r16(PARSER_COUNT)
        if count == 0:
            if byte & 0x80:
                self.w8(MIDI_CHANNEL, byte & 0x0F)
                address, _, length = self.MESSAGES[(byte >> 4) & 7]
                self.w16(PARSER_LENGTH, length)
                self.w32(PARSER_HANDLER, address)
                self.w16(PARSER_COUNT, 1)
                return
            count = 1
            self.w16(PARSER_COUNT, 1)
        self.w8(MIDI_DATA + count - 1, byte)
        if count != self.r16(PARSER_LENGTH):
            self.w16(PARSER_COUNT, count + 1)
            return
        self.w16(PARSER_COUNT, 0)
        address = self.r32(PARSER_HANDLER)
        name = next(n for a, n, _ in self.MESSAGES if a == address)
        if self.trace:
            self.trace(name, self.r8(MIDI_CHANNEL), self.r8(MIDI_DATA), self.r8(MIDI_DATA + 1))
        getattr(self, "_msg_" + name)()

    def _msg_nothing(self) -> None:
        """``$1797C`` / ``$1797E``: aftertouch, channel pressure, $Fx: ignored."""

    def _msg_program(self) -> None:
        """``$178F0``."""
        self.w8(PROGRAMS + self.r8(MIDI_CHANNEL), self.r8(MIDI_DATA))

    def _msg_control(self) -> None:
        """``$178AA``: only controller 7 (channel volume) does something."""
        if self.r8(MIDI_DATA) == 7:
            self.w8(VOLUMES + self.r8(MIDI_CHANNEL), self.r8(MIDI_DATA + 1))

    def _msg_bend(self) -> None:
        """``$17904``: bend = second data byte - $40, re-applied to the
        channel's music notes (FM, PSG, pitched PCM; plain PCM keeps its rate)."""
        ch = self.r8(MIDI_CHANNEL)
        bend = (self.r8(MIDI_DATA + 1) - 0x40) & 0xFFFF
        self.w16(BENDS + 2 * ch, bend)
        for n in range(N_CHANNELS):
            c = self.channel(n)
            if self.r8(c + CH_STATE) != 0 or self.r8(c + CH_MIDI) != ch:
                continue
            self.w16(c + CH_BEND, bend)
            self.w16(c + CH_BEND_KEY, 0)
            kind = self.rom8(self.r32(c + CH_INSTR))
            if kind == PSG:
                self._psg_pitch(c)
            elif kind == PCM_PITCHED:
                self._pcm_pitch(c)
            elif kind == FM:
                self._fm_pitch(c)

    def _msg_note_off(self) -> None:
        """``$173EA``: the oldest sounding music note with this channel and key."""
        key, ch = self.r8(MIDI_DATA), self.r8(MIDI_CHANNEL)
        found, serial = None, 0
        for n in range(N_CHANNELS):
            c = self.channel(n)
            if (self.r8(c + CH_STATE) == 0 and self.r8(c + CH_MIDI) == ch
                    and self.r8(c + CH_NOTE) == key and self.r8(c + CH_PHASE) == 1):
                if found is None or serial >= self.r16(c + CH_SERIAL):
                    found, serial = c, self.r16(c + CH_SERIAL)
        if found is None:
            return
        c = found
        self.w8(c + CH_PHASE, 0)
        instr = self.r32(c + CH_INSTR)
        kind = self.rom8(instr)
        rec = self.r32(c + CH_RECORD)
        if kind in (PCM, PCM_PITCHED):
            if self.rom8(instr + 0x10) & 2:     # one-shot: plays on
                return
            self.w8(rec + 1, 0)
            self.w8(rec, 0)
            self.w8(DIRTY, 1)
            self.w8(c + CH_STATE, 0xFF)
        elif kind == FM:
            release = self.rom8(instr + 0x41)
            if release:
                self.w8(c + CH_PHASE, 2)
                self.w8(c + CH_RELEASE, release)
            else:
                self.w8(c + CH_STATE, 0xFF)
            self.w8(rec + 1, 0)
            self.w8(rec, 0)
            self.w8(DIRTY, 1)
        else:                                    # PSG, noise
            self.w8(rec + 1, 0)
            self.w8(rec + 2, 0xFF)
            self.w8(rec, 0)
            self.w8(DIRTY, 1)
            self.w8(c + CH_STATE, 0xFF)

    def _msg_note_on(self) -> None:
        """``$174D2``: instrument = the channel's program (channel 9: key + $5C),
        a channel allocated for its class, then the type's note-on."""
        if not self.r16(NOTES_ON):
            return
        if self.r8(MIDI_DATA + 1) == 0:
            self._msg_note_off()
            return
        ch = self.r8(MIDI_CHANNEL)
        cv = self.r8(VOLUMES + ch)
        if cv == 0:
            return
        self.w16(NOTE_VOLUME, ((cv * self.r16(TRACK_VOLUME)) & 0xFFFF) >> 7)
        index = (self.r8(MIDI_DATA) + 0x5C) if ch == 9 else self.r8(PROGRAMS + ch)
        instr = self.instrument(index)
        c = self.allocate(self.rom8(instr), self.rom8(instr + 1), self.rom16(instr + 2))
        if c is None:
            return
        self.w16(NOTE_SERIAL, self.r16(NOTE_SERIAL) + 1)
        self.w8(c + CH_PRIORITY, self.rom8(instr + 1))
        kind = self.rom8(instr)
        if self.trace:
            self.trace("alloc", (c - CHANNELS) // CHANNEL_SIZE, index)
        if kind in (PCM, PCM_PITCHED):
            self._pcm_note_on(c, instr)
        elif kind == FM:
            self._fm_note_on(c, instr)
        elif kind == PSG:
            self._psg_note_on(c, instr)
        elif kind == NOISE:
            self._noise_note_on(c, instr)

    def _fold(self, key: int) -> int:
        """Note + transpose -> note index (e.g. ``$17710``): signed bytes
        $6C..$7F folded down by octaves (table $169D6); then -12 (C0 = 0)."""
        key &= 0xFF
        if _s8(key) >= 0x0C and _s8(key) >= 0x6C:
            key = self.rom8(NOTE_FOLD + key - 0x6C)
        return (key - 0x0C) & 0xFF

    def _pcm_note_on(self, c: int, instr: int) -> None:
        """``$17556``: a sample note (one-shot when flag bit 1 is set)."""
        if (self.r16(TRACK_VOLUME) & 0xFF) < self.rom8(instr + 0x15):
            return
        self.w32(c + CH_INSTR, instr)
        bank = self._pcm_conflicts(c, self.r8(c + CH_PRIORITY), self.rom32(instr + 4))
        if bank < 0:
            return
        self.w32(c + CH_BANKS, self.rom32(instr + 4))
        self.w16(c + CH_SERIAL, self.r16(NOTE_SERIAL))
        self.w32(c + CH_CACHE, 0)
        self.w32(c + CH_BEND_DELTA, 0)
        self.w16(c + CH_BEND_KEY, 0)
        ch = self.r8(MIDI_CHANNEL)
        self.w8(c + CH_MIDI, ch)
        if self.rom8(instr + 0x12):
            self.w16(c + CH_BEND, self.r16(BENDS + 2 * ch))
            k = (self.r8(MIDI_DATA) + self.rom8(instr + 0x13) - 0x24) & 0xFF
            if k & 0x80 or k >= 0x30:
                return
            self.w8(c + CH_KEY, k)
        rec = self.r32(c + CH_RECORD)
        self._pcm_pitch(c)
        self.w8(rec + 4, 0x80)
        self.w8(rec + 1, 1)
        self._pcm_address(rec, instr, bank)
        self.w8(rec, 0)
        self.w8(c + CH_STATE, 0)
        self.w8(c + CH_NOTE, self.r8(MIDI_DATA))
        self.w8(c + CH_PHASE, 1)

    def _pcm_address(self, rec: int, instr: int, bank: int) -> None:
        """Record bytes 5-7 (bank, address | $8000 high, low), 8 (loop flag),
        9-11 (loop bank and address)."""
        a = (self.rom32(instr + 8) + self.r32(SAMPLE_BASE)) & 0xFFFFFFFF
        self.w8(rec + 7, a | 0x8000)
        self.w8(rec + 6, (a | 0x8000) >> 8)
        b = ((a >> 15) + bank) & 0xFF
        self.w8(rec + 5, b)
        self.w8(BANK_SHADOW, b)
        self.w8(DIRTY, 1)
        loop = self.rom8(instr + 0x10) & 1
        self.w8(rec + 8, loop)
        if loop:
            a = (self.rom16(instr + 0xE) + self.rom32(instr + 8) + self.r32(SAMPLE_BASE)) & 0xFFFFFFFF
            self.w8(rec + 0xB, a | 0x8000)
            self.w8(rec + 0xA, (a | 0x8000) >> 8)
            self.w8(rec + 9, (a >> 15) + bank)

    def _fm_note_on(self, c: int, instr: int) -> None:
        """``$17656``."""
        rec = self.r32(c + CH_RECORD)
        self.w16(c + CH_SERIAL, self.r16(NOTE_SERIAL))
        self.w8(c + CH_STATE, 0)
        ch = self.r8(MIDI_CHANNEL)
        self.w8(c + CH_MIDI, ch)
        self.w16(c + CH_BEND, self.r16(BENDS + 2 * ch))
        self.w8(DIRTY, 1)
        self.w8(c + CH_PENV_STATE, 0)
        self.w8(c + CH_ARP_STATE, 0)
        self.w8(c + CH_VIB_STATE, 0)
        self.w32(c + CH_BEND_DELTA, 0)
        self.w16(c + CH_BEND_KEY, 0)
        self.w16(c + CH_ARP, 0)
        self.w16(c + CH_VIB, 0)
        self.w16(c + CH_VIB_TIMER, 0)
        self.w16(c + CH_PENV, self.rom16(instr + 0xE))
        self.w16(c + CH_PENV_TIMER, self.rom16(instr + 0xC))
        self.w16(c + CH_ARP_TIMER, self.rom16(instr + 0x1C))
        if self.r32(c + CH_PATCH) != instr:
            self.w32(c + CH_PATCH, instr)
            self.w8(rec + 2, 0)
            self.w16(rec + 6, self.r16(DRIVER_LENGTH) + self.rom16(instr + 6))
        self.w32(c + CH_INSTR, instr)
        self.w8(rec + 5, self.rom8(instr + 0x40))
        vol = ((self.r8(MIDI_DATA + 1) * self.r16(NOTE_VOLUME)) & 0xFFFF) >> 7
        self.w16(c + CH_VOLUME, vol)
        self.w8(rec + 3, self.rom8(FM_VOLUME + vol))
        self.w8(rec + 4, 0)
        key = self.r8(MIDI_DATA)
        self.w8(c + CH_NOTE, key)
        self.w8(c + CH_KEY, self._fold(key + self.rom8(instr + 9)))
        self.w32(c + CH_CACHE, 0)
        self._fm_pitch(c)
        self.w8(rec + 1, 1)
        self.w8(rec, 0)
        self.w8(c + CH_PHASE, 1)
        self.w8(c + CH_STATE, 0)

    def _psg_note_on(self, c: int, instr: int) -> None:
        """``$17754`` (no PSG instrument exists in this game)."""
        rec = self.r32(c + CH_RECORD)
        self.w16(c + CH_SERIAL, self.r16(NOTE_SERIAL))
        self.w32(c + CH_INSTR, instr)
        self.w32(c + CH_PATCH, instr)
        self.w8(c + CH_STATE, 0)
        ch = self.r8(MIDI_CHANNEL)
        self.w8(c + CH_MIDI, ch)
        self.w16(c + CH_BEND, self.r16(BENDS + 2 * ch))
        self.w8(DIRTY, 1)
        for f in (CH_PENV_STATE, CH_VENV_STATE, CH_ARP_STATE, CH_VIB_STATE):
            self.w8(c + f, 0)
        self.w32(c + CH_BEND_DELTA, 0)
        for f in (CH_BEND_KEY, CH_ARP, CH_VIB, CH_VIB_TIMER):
            self.w16(c + f, 0)
        self.w16(c + CH_PENV, self.rom16(instr + 0xC))
        self.w16(c + CH_PENV_TIMER, self.rom16(instr + 0xA))
        self.w16(c + CH_VENV, self.rom16(instr + 0x40))
        self.w16(c + CH_VENV_TIMER, self.rom16(instr + 0x3E))
        self.w16(c + CH_ARP_TIMER, self.rom16(instr + 0x1A))
        vol = ((self.r8(MIDI_DATA + 1) * self.r16(NOTE_VOLUME)) & 0xFFFF) >> 7
        self.w16(c + CH_VOLUME, vol)
        self._psg_volume(c)
        self.w8(rec + 3, 0)
        key = self.r8(MIDI_DATA)
        self.w8(c + CH_NOTE, key)
        self.w8(c + CH_KEY, self._fold(key + self.rom8(instr + 7)))
        self.w32(c + CH_CACHE, 0)
        self._psg_pitch(c)
        self.w8(rec + 1, 1)
        self.w8(rec, 0)
        self.w8(c + CH_PHASE, 1)
        self.w8(c + CH_STATE, 0)

    def _noise_note_on(self, c: int, instr: int) -> None:
        """``$17840`` (unused in this game)."""
        rec = self.r32(c + CH_RECORD)
        self.w16(c + CH_SERIAL, self.r16(NOTE_SERIAL))
        self.w32(c + CH_INSTR, instr)
        self.w32(c + CH_PATCH, instr)
        self.w8(c + CH_MIDI, self.r8(MIDI_CHANNEL))
        self.w8(DIRTY, 1)
        vol = ((self.r8(MIDI_DATA + 1) * self.r16(NOTE_VOLUME)) & 0xFFFF) >> 7
        self.w16(c + CH_VOLUME, vol)
        self._psg_volume(c)
        self.w8(rec + 3, 0)
        self.w8(c + CH_NOTE, self.r8(MIDI_DATA))
        self.w16(rec + 4, self.rom8(instr + 5))
        self.w8(rec + 1, 1)
        self.w8(rec, 0)
        self.w8(c + CH_PHASE, 1)
        self.w8(c + CH_STATE, 0)

    # ---- channel allocation ($16958, $172A0) -------------------------------------
    def allocate(self, kind: int, priority: int, mask: int) -> int | None:
        """``$16958``: a channel of class ``kind`` allowed by ``mask``: the
        first free one, else the music note with the lowest priority <=
        ``priority`` (the last of equals). Voices (state 1) are never taken.
        FM has 5 channels while any PCM voice is in use, 6 otherwise."""
        e = ALLOC_CLASSES + 8 * kind
        first, bit, count = self.rom16(e), self.rom16(e + 2), self.rom16(e + 4)
        if count & 0x8000:
            count = 4
            if all(self.r8(SFX_CHANNELS + v * CHANNEL_SIZE + CH_STATE) & 0x80 for v in range(4)):
                count = 5
        best = None
        c = CHANNELS + first
        for _ in range(count + 1):
            if mask & bit & 0xFFFF:
                st = self.r8(c + CH_STATE)
                if st & 0x80:
                    return c
                if st == 0:
                    p = self.r8(c + CH_PRIORITY)
                    if priority >= p:
                        priority = p
                        best = c
            bit = (bit << 1) & 0xFFFF
            c += CHANNEL_SIZE
        return best

    def _pcm_conflicts(self, c: int, priority: int, banks: int) -> int:
        """``$172A0``: all PCM voices play from the one 32 KiB ROM bank the Z80
        maps, so a new sample must share a bank with the others. A voice whose
        bank mask (instrument +4) overlaps narrows the choice to the common
        banks; one that doesn't is killed when its priority <= ``priority``,
        else the new sound fails (-1, nothing killed). Returns the bank offset
        (lowest bit of the remaining mask) to add to the sample's own bank."""
        kill = []
        for v in range(4):
            o = SFX_CHANNELS + v * CHANNEL_SIZE
            if o == c or self.r8(o + CH_STATE) & 0x80:
                continue
            common = self.r32(o + CH_BANKS) & banks
            if common:
                banks = common
            elif priority < self.r8(o + CH_PRIORITY):
                return -1
            else:
                kill.append(v)
        for v in kill:                          # (no dirty flag: the caller sets it)
            rec = RECORDS + 0x54 + 12 * v
            self.w8(rec + 1, 0)
            self.w8(rec, 0)
            self.w8(SFX_CHANNELS + v * CHANNEL_SIZE + CH_STATE, 0xFF)
        if banks == 0:
            return 0
        n = 0
        while not banks & 1:
            banks >>= 1
            n += 1
        return n

    # ---- PCM voices ($17CDE ..) -------------------------------------------------
    def voice_start(self, index: int, rate: int, volume: int) -> int:
        """``$17CDE``: sample instrument ``index`` as a voice (state 1, not a
        music note): ``rate`` (8.8, $100 = 1:1) and ``volume`` (/2 into the
        record). Any of the 4 PCM voices when rate = $100 and volume = $100,
        else only the fourth. Returns a handle or -1."""
        volume = (volume & 0xFFFF) >> 1
        instr = self.instrument(index)
        kind = PCM if (rate & 0xFFFF) == 0x100 and volume == 0x80 else PCM_PITCHED
        c = self.allocate(kind, self.rom8(instr + 1), 0xFFFF)
        if c is None:
            return 0xFFFFFFFF
        self.w8(c + CH_PRIORITY, self.rom8(instr + 1))
        self.w32(c + CH_INSTR, instr)
        bank = self._pcm_conflicts(c, self.r8(c + CH_PRIORITY), self.rom32(instr + 4))
        if bank < 0:
            return 0xFFFFFFFF
        self.w32(c + CH_BANKS, self.rom32(instr + 4))
        self.w32(c + CH_CACHE, 0)
        self.w32(c + CH_BEND_DELTA, 0)
        self.w16(c + CH_BEND_KEY, 0)
        self.w8(c + CH_MIDI, self.r8(MIDI_CHANNEL))
        rec = self.r32(c + CH_RECORD)
        self.w16(rec + 2, rate)
        self.w8(rec + 4, volume)
        self.w8(rec + 1, 1)
        self._pcm_address(rec, instr, bank)
        self.w8(rec, 0)
        self.w8(c + CH_STATE, 1)
        self.w8(c + CH_NOTE, self.r8(MIDI_DATA))
        self.w8(c + CH_PHASE, 1)
        handle = (self.r32(VOICE_HANDLE) + 1) & 0xFFFFFFFF
        self.w32(VOICE_HANDLE, handle)
        self.w32(c + CH_CACHE, handle)
        return handle

    def _voice(self, handle: int) -> int | None:
        for v in range(4):
            c = SFX_CHANNELS + v * CHANNEL_SIZE
            if self.r8(c + CH_STATE) == 1 and self.r32(c + CH_CACHE) == handle & 0xFFFFFFFF:
                return c
        return None

    def voice_stop(self, handle: int) -> None:
        """``$17DFA``."""
        c = self._voice(handle)
        if c is None:
            return
        rec = self.r32(c + CH_RECORD)
        self.w8(rec + 1, 0)
        self.w8(rec, 0)
        self.w8(DIRTY, 1)
        self.w8(c + CH_STATE, 0xFF)

    def voice_busy(self, handle: int) -> bool:
        """``$17E3E``: the voice is still allocated (freed by a stop, a steal or
        the Z80's end-of-sample status, seen at a tick)."""
        return self._voice(handle) is not None

    def voice_rate(self, handle: int, rate: int) -> None:
        """``$17E62``."""
        c = self._voice(handle)
        if c is not None:
            rec = self.r32(c + CH_RECORD)
            self.w16(rec + 2, rate)
            self.w8(rec, 0)
            self.w8(DIRTY, 1)

    def voice_volume(self, handle: int, volume: int) -> None:
        """``$17EA2``: volume / 2 into record byte 4."""
        c = self._voice(handle)
        if c is not None:
            rec = self.r32(c + CH_RECORD)
            self.w8(rec + 4, (volume & 0xFFFF) >> 1)
            self.w8(rec, 0)
            self.w8(DIRTY, 1)

    # ---- per-tick channel update ($1715E) -----------------------------------------
    def channels_tick(self) -> None:
        """``$1715E``: for each music note (state 0): priority decay, FM
        release, modulators, pitch / volume output."""
        for n in range(N_CHANNELS):
            c = self.channel(n)
            if self.r8(c + CH_STATE) != 0:
                continue
            instr = self.r32(c + CH_INSTR)
            kind = self.rom8(instr)
            if kind in (PCM, PCM_PITCHED):
                self._decay(c, instr + 0x11)
            elif kind == NOISE:
                self._decay(c, instr + 6)
            elif kind == PSG:
                self._decay(c, instr + 6)
                mods = self.rom8(instr + 9)
                if mods:
                    if mods & 1:
                        self._envelope(c, instr + 0xA, CH_PENV_STATE, CH_PENV, CH_PENV_TIMER)
                    if mods & 2:
                        self._arpeggio(c, instr + 0x1A)
                    if mods & 4:
                        self._vibrato(c, instr + 0x30)
                    if mods & 8:
                        self._envelope(c, instr + 0x3E, CH_VENV_STATE, CH_VENV, CH_VENV_TIMER)
                        self._psg_volume(c)
                    self._psg_pitch(c)
            elif kind == FM:
                self._decay(c, instr + 8)
                if self.r8(c + CH_PHASE) == 2:
                    left = (self.r8(c + CH_RELEASE) - 1) & 0xFF
                    self.w8(c + CH_RELEASE, left)
                    if left == 0:
                        self.w8(c + CH_PHASE, 0)
                        self.w8(c + CH_STATE, 0xFF)
                        continue
                mods = self.rom8(instr + 0xB)
                if mods:
                    if mods & 1:
                        self._envelope(c, instr + 0xC, CH_PENV_STATE, CH_PENV, CH_PENV_TIMER)
                    if mods & 2:
                        self._arpeggio(c, instr + 0x1C)
                    if mods & 4:
                        self._vibrato(c, instr + 0x32)
                    self._fm_pitch(c)

    def _decay(self, c: int, at: int) -> None:
        """Priority -= the instrument's decay while non-zero (no clamp: wraps)."""
        p = self.r8(c + CH_PRIORITY)
        if p:
            self.w8(c + CH_PRIORITY, p - self.rom8(at))

    def _envelope(self, c: int, p: int, f_state: int, f_value: int, f_timer: int) -> None:
        """``$16F28`` (pitch) / ``$16FB4`` (volume): delay, attack to a peak,
        decay to a sustain level, release to 0. Parameters (words): +0 delay,
        +2 start value (copied at note-on), +4 attack step, +6 peak, +8 decay
        step, +$A sustain, +$C release step."""
        state = self.r8(c + f_state)
        if state == 0:
            t = _s16(self.r16(c + f_timer) - 1)
            self.w16(c + f_timer, t)
            if t < 0:
                self.w8(c + f_state, 2)
        elif state == 2:
            v = _s16(self.r16(c + f_value) + self.rom16(p + 4))
            self.w16(c + f_value, v)
            if v > _s16(self.rom16(p + 6)):
                self.w16(c + f_value, self.rom16(p + 6))
                self.w8(c + f_state, 4)
        elif state == 4:
            v = _s16(self.r16(c + f_value) - self.rom16(p + 8))
            self.w16(c + f_value, v)
            if not v > _s16(self.rom16(p + 0xA)):
                self.w16(c + f_value, self.rom16(p + 0xA))
                self.w8(c + f_state, 6)
        elif state == 6:
            v = _s16(self.r16(c + f_value) - self.rom16(p + 0xC))
            self.w16(c + f_value, v)
            if not v > 0:
                self.w16(c + f_value, 0)
                self.w8(c + f_state, 8)

    def _arpeggio(self, c: int, p: int) -> None:
        """``$17040``: after +0 ticks, for +4 ticks cycle through the +2.b note
        offsets at +6.. (words), each held +3.b + 1 ticks; then offset 0."""
        state = self.r8(c + CH_ARP_STATE)
        if state == 0:
            t = _s16(self.r16(c + CH_ARP_TIMER) - 1)
            self.w16(c + CH_ARP_TIMER, t)
            if t >= 0:
                return
            self.w8(c + CH_ARP_STATE, 2)
            self.w16(c + CH_ARP_TIMER, self.rom16(p + 4))
            self.w16(c + CH_ARP_STEP_TIMER, self.rom8(p + 3))
            self.w16(c + CH_ARP_POS, 0xFFFF)
            state = 2
        if state == 2:
            t = _s16(self.r16(c + CH_ARP_TIMER) - 1)
            self.w16(c + CH_ARP_TIMER, t)
            if t < 0:
                self.w8(c + CH_ARP_STATE, 4)
                self.w16(c + CH_ARP, 0)
                return
            t = _s16(self.r16(c + CH_ARP_STEP_TIMER) - 1)
            self.w16(c + CH_ARP_STEP_TIMER, t)
            if t >= 0:
                return
            self.w16(c + CH_ARP_STEP_TIMER, self.rom8(p + 3))
            pos = (self.r16(c + CH_ARP_POS) + 1) & 0xFFFF
            if not _s8(pos) < _s8(self.rom8(p + 2)):
                pos = 0
            self.w16(c + CH_ARP_POS, pos)
            self.w16(c + CH_ARP, self.rom16(p + 6 + 2 * _s16(pos)))

    def _vibrato(self, c: int, p: int) -> None:
        """``$170C6``: from tick +0 to tick +2 (counted from the note-on):
        phase += +4; value = sine(((phase & +$A) + +$C) >> 2) / 2 * +6 >> 14,
        clamped to +-(+8)."""
        state = self.r8(c + CH_VIB_STATE)
        if state == 0:
            timer = _s16(self.r16(c + CH_VIB_TIMER))
            if timer < _s16(self.rom16(p)):
                self.w16(c + CH_VIB_TIMER, timer + 1)
                return
            self.w8(c + CH_VIB_STATE, 2)
            self.w16(c + CH_VIB_PHASE, 0)
            state = 2
        if state == 2:
            timer = _s16(self.r16(c + CH_VIB_TIMER))
            if not timer < _s16(self.rom16(p + 2)):
                self.w8(c + CH_VIB_STATE, 4)
                self.w16(c + CH_VIB, 0)
                return
            phase = (self.r16(c + CH_VIB_PHASE) + self.rom16(p + 4)) & 0xFFFF
            self.w16(c + CH_VIB_PHASE, phase)
            a = _s16((phase & self.rom16(p + 0xA)) + self.rom16(p + 0xC)) >> 2
            s = self.sine(a) >> 1
            v = _s16((s * _s16(self.rom16(p + 6))) >> 14)
            limit = _s16(self.rom16(p + 8))
            if v > limit:
                v = limit
            if v < _s16(-limit):
                v = _s16(-limit)
            self.w16(c + CH_VIB, v)
            self.w16(c + CH_VIB_TIMER, timer + 1)

    def sine(self, angle: int) -> int:
        """``$14214``: 256 steps per turn, -$7FFF..$7FFF."""
        i = angle & 0x3F
        if angle & 0x40:
            i = 0x40 - i
        v = self.rom16(SINE + 2 * i)
        return -v if angle & 0x80 else v

    # ---- pitch / volume output ------------------------------------------------------
    def _fm_pitch(self, c: int) -> None:
        """``$16DAC``: note index + arpeggio -> linear F-number (table $169EA),
        + bend (towards +-(+$A) notes), detune (+4), pitch envelope, vibrato;
        when changed, normalised to block << 11 | F-number in record bytes 8-9."""
        instr = self.r32(c + CH_INSTR)
        k = ((self.r8(c + CH_KEY) + self.r16(c + CH_ARP)) * 4) & 0xFFFF
        f = self.rom32(FM_FREQ + _s16(k))
        bend = _s16(self.r16(c + CH_BEND))
        if bend and self.rom8(instr + 0xA):
            if k != self.r16(c + CH_BEND_KEY):
                self.w16(c + CH_BEND_KEY, k)
                r = self.rom8(instr + 0xA) * 4
                k2 = _s16(k - r if bend < 0 else k + r)
                d = _s16(self.rom32(FM_FREQ + k2) - f)          # muls.w: low words
                self.w32(c + CH_BEND_DELTA, (d * abs(bend)) >> 6)
            f += self.r32(c + CH_BEND_DELTA)
        f += _s8(self.rom8(instr + 4))
        f += self.r16(c + CH_PENV)                              # unsigned word
        f += _s16(self.r16(c + CH_VIB))
        f &= 0xFFFFFFFF
        if f == self.r32(c + CH_CACHE):
            return
        self.w32(c + CH_CACHE, f)
        block = 0
        while _s32(f) >= 0x800:
            block += 0x800
            f >>= 1
        rec = self.r32(c + CH_RECORD)
        self.w16(rec + 8, block + f)
        self.w8(rec + 4, 0)
        self.w8(rec, 0)
        self.w8(DIRTY, 1)

    def _pcm_pitch(self, c: int) -> None:
        """``$16D32``: rate = +$C, or (pitched, +$12 != 0) the note's word at
        +$16, bent towards +-(+$14) notes; record bytes 2-3 when changed."""
        instr = self.r32(c + CH_INSTR)
        rate = self.rom16(instr + 0xC)
        if self.rom8(instr + 0x12):
            k = (self.r8(c + CH_KEY) * 2) & 0xFF
            rate = self.rom16(instr + 0x16 + k)
            bend = _s16(self.r16(c + CH_BEND))
            if bend and self.rom8(instr + 0x14):
                if k != self.r16(c + CH_BEND_KEY):
                    self.w16(c + CH_BEND_KEY, k)
                    r = self.rom8(instr + 0x14) * 2
                    k2 = _s16(k - r if bend < 0 else k + r)
                    d = _s16(self.rom16(instr + 0x16 + k2) - rate)
                    self.w16(c + CH_BEND_DELTA, (d * abs(bend)) >> 6)
                rate = (rate + self.r16(c + CH_BEND_DELTA)) & 0xFFFF
        if rate == self.r16(c + CH_CACHE):
            return
        self.w16(c + CH_CACHE, rate)
        rec = self.r32(c + CH_RECORD)
        self.w16(rec + 2, rate)
        self.w8(rec, 0)
        self.w8(DIRTY, 1)

    def _psg_pitch(self, c: int) -> None:
        """``$16E60`` (unused in this game)."""
        instr = self.r32(c + CH_INSTR)
        k = ((self.r8(c + CH_KEY) + self.r16(c + CH_ARP)) * 2) & 0xFFFF
        f = self.rom16(PSG_PERIOD + _s16(k))
        bend = _s16(self.r16(c + CH_BEND))
        if bend and self.rom8(instr + 8):
            if k != self.r16(c + CH_BEND_KEY):
                self.w16(c + CH_BEND_KEY, k)
                r = self.rom8(instr + 8) * 2
                k2 = _s16(k - r if bend < 0 else k + r)
                d = _s16(self.rom16(PSG_PERIOD + k2) - f)
                self.w16(c + CH_BEND_DELTA, (d * abs(bend)) >> 6)
            f += self.r16(c + CH_BEND_DELTA)
        f = _s16(f + _s8(self.rom8(instr + 4)) + self.r16(c + CH_PENV) + self.r16(c + CH_VIB))
        if f < 0:
            f = 0
        if f == self.r16(c + CH_CACHE):
            return
        self.w16(c + CH_CACHE, f)
        rec = self.r32(c + CH_RECORD)
        self.w16(rec + 4, f)
        self.w8(rec + 3, 0)
        self.w8(rec, 0)
        self.w8(DIRTY, 1)

    def _psg_volume(self, c: int) -> None:
        """``$16EF6`` (unused in this game)."""
        v = (_s16(self.r16(c + CH_VENV)) >> 7) + _s16(self.r16(c + CH_VOLUME))
        v = _s16(v)
        v = max(0, min(v, 0x7F))
        rec = self.r32(c + CH_RECORD)
        self.w8(rec + 2, self.rom8(PSG_VOLUME + v))
        self.w8(rec, 0)
        self.w8(DIRTY, 1)

    # ---- inspection -------------------------------------------------------------
    def track_state(self, slot: int) -> dict:
        """Track ``slot`` (0-31) decoded."""
        t = TRACKS + slot * TRACK_SIZE
        return dict(state=self.r8(t + TR_STATE), channel=self.r8(t + TR_CHANNEL),
                    index=self.r8(t + TR_INDEX), tempo=self.r32(t + TR_TEMPO),
                    fraction=self.r16(t + TR_FRACTION), volume=_s16(self.r16(t + TR_VOLUME)),
                    volume_target=_s16(self.r16(t + TR_VOLUME_TARGET)),
                    fade_step=_s16(self.r16(t + TR_FADE_STEP)), pos=self.r32(t + TR_POS),
                    wait=self.r32(t + TR_WAIT), handle=self.r32(t + TR_HANDLE),
                    program=self.r8(t + TR_PROGRAM))

    def channel_state(self, n: int) -> dict:
        """Channel struct ``n`` (0-13) decoded (the fields every kind uses)."""
        c = self.channel(n)
        return dict(state=self.r8(c + CH_STATE), instrument=self.r32(c + CH_INSTR),
                    midi=self.r8(c + CH_MIDI), note=self.r8(c + CH_NOTE), key=self.r8(c + CH_KEY),
                    phase=self.r8(c + CH_PHASE), priority=self.r8(c + CH_PRIORITY),
                    serial=self.r16(c + CH_SERIAL), cache=self.r32(c + CH_CACHE),
                    volume=self.r16(c + CH_VOLUME))

    def queue(self) -> list[tuple[int, int, int, int, int]]:
        """Pending note-offs, head to tail: (time left 16.16, step, key, channel, slot)."""
        out = []
        e = self.r32(QUEUE_HEAD)
        for _ in range(self.r8(QUEUE_COUNT)):
            out.append((self.r32(e), self.r32(e + 4), self.r8(e + 8), self.r8(e + 9), self.r8(e + 10)))
            e += QUEUE_ENTRY
            if e & 0xFFFF == (QUEUE + QUEUE_SIZE) & 0xFFFF:
                e = _ptr(QUEUE)
        return out


def run(rom: Rom, calls: dict[int, list[tuple]], ticks: int, pal: bool = False,
        z80: Z80Link | None = None) -> tuple[Sound68k, list[TickOutput]]:
    """A scripted run from power-on: ``reset()``, then for each tick the calls
    listed for it (``(method name, *args)``, made before that tick's VBlank,
    i.e. by the game's main code), then ``vblank()``.

    >>> m, outs = run(Rom.load(), {0: [("music_start", MUSIC_TITLE)], 120: [("sound_play", 0x27)]}, 300)
    """
    m = Sound68k(rom, pal=pal, z80=z80)
    m.reset()
    outs = []
    for tick in range(ticks):
        for name, *args in calls.get(tick, []):
            getattr(m, name)(*args)
        outs.append(m.vblank())
    return m, outs


def main() -> None:
    """``tools/bin/py -m mw_harness.sound68k [--music title|game] [--play ID@TICK ...] [--ticks N]``:
    prints each tick's Z80 writes (the record bytes that carry commands)."""
    import argparse
    ap = argparse.ArgumentParser(description=main.__doc__)
    ap.add_argument("--music", choices=["title", "game"])
    ap.add_argument("--play", action="append", default=[], help="sound id @ tick, hex id: 27@60")
    ap.add_argument("--ticks", type=int, default=240)
    a = ap.parse_args()
    calls: dict[int, list[tuple]] = {}
    if a.music:
        calls.setdefault(0, []).append(("music_start", MUSIC_TITLE if a.music == "title" else MUSIC_GAME))
    for p in a.play:
        sid, _, tick = p.partition("@")
        calls.setdefault(int(tick or 0), []).append(("sound_play", int(sid, 16)))
    _, outs = run(Rom.load(), calls, a.ticks)
    layout = [("FM", 6, 10), ("PSG", 4, 6), ("PCM", 4, 12)]
    for tick, out in enumerate(outs):
        if out.block is None:
            continue
        parts, o = [], 0
        for name, n, size in layout:
            for k in range(n):
                rec = out.block[o:o + size]
                if rec[0] == 0:
                    parts.append(f"{name}{k + 1}:{rec.hex()}")
                o += size
        print(f"{tick:5d} " + " ".join(parts) + (f" voices freed {out.voice_clears}" if out.voice_clears else ""))


if __name__ == "__main__":
    main()
