"""PCM samples of the sound driver: the reference parser for plan 12 (docs/re/sound.md).

The Z80 driver (ROM $15C90) plays 8-bit PCM through the YM2612 DAC (register
$2A). The 68000 tells it what to play; the sample data is read by the Z80
through its 32 KB bank window ($8000-$FFFF, bank register $6000).

Instrument table (`$E6A6` = $1FF010, set at $13C44): 256 big-endian words,
each an offset from $1FF010 to an instrument record. Record +0 is the
instrument kind: 0 = PCM sample, 3 = pitched PCM sample (a 48-entry note ->
pitch table follows at +$16), 1 / 2 / 4 / 5 = FM / PSG / other instruments of
the 68k sequencer (not handled here). Unused indices point at a default FM
record. Sample records (`$17CDE`, `$17556`):

    +$00  byte   kind (0 or 3)
    +$01  byte   priority (voice allocation `$16958` / `$172A0`)
    +$02  word   voices the sequencer may use (bit k = 68k voice 10+k)
    +$04  long   bank mask: bit k = a copy of the sample exists k banks above
                 the bank of (SAMPLE_BASE + offset), at the same offset in the
                 bank. 0 = the sample plays alone (no copy for mixing).
    +$08  long   offset of the sample header from SAMPLE_BASE ($E6AA = $1C0000)
    +$0C  word   pitch the sequencer uses when +$12 = 0 ($0100 in every record)
    +$0E  word   loop start, as an index into the sample data
    +$10  byte   bit 0: loop (other bits not read by the Z80 path)
    +$12  byte   1 = pitched by the sequencer's note (kind 3) - sequencer only
    +$13  byte   note offset - sequencer only
    +$14  2 bytes  sequencer only

The Z80 mixer reads every channel through ONE bank register, so samples
mixed together must sit in the same bank; the 68k picks, among the banks of
the mask, the lowest one shared with every sample still playing (`$172A0`);
a playing sample that shares none is stopped if its priority is not higher,
else the new sample is refused. All copies are identical.

Sample header (in the bank, at the address above):

    +0  byte  codec: 0 = raw unsigned 8-bit, 2 = 4-bit DPCM, other = "type 1"
              (a marker byte follows; RLE / ramp format, used by no sample)
    then data, ended by a 0 byte (0 never occurs as a sample value).

DPCM: each byte gives two 4-bit codes, high nibble first; value += delta[code]
(mod 256, no clamping), value starting at $80; the DAC gets every value. The
end test (a 0 byte) is made before each high nibble. The 16 signed deltas are
part of the driver blob (Z80 $0112).

Rates (NTSC Z80 = 53.693175 MHz / 15 = 3 579 545 Hz): the raw loop takes 321
T-states plus one read of the 68k bus per sample (+3 T as BlastEm models
the bus arbitration; ~3.3 T measured on hardware) = 324 T -> 11 048 Hz. With
2-4 samples mixing: 317 / 314 / 311 T + 2 / 3 / 4 bus reads = 323 T. DPCM
alternates 330 + 3 and 319 + 3 T: 655 T per byte -> 10 930 Hz mean. The
pitched channel advances by an 8.8 fixed-point step per DAC write ($100 =
1 byte per write), so its playback rate is RAW_RATE * step / 256. These are
the rates inside the loop; the 68000's bus requests and the driver's per-tick
work pause the DAC a few percent of the time (durations ~3 % longer in play).

Nothing here is game content: it only reads the user's ROM.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass

from .rom import Rom

INSTRUMENT_TABLE = 0x1FF010     # $E6A6 (lea $1FF010 at $13C44)
INSTRUMENT_COUNT = 256
SAMPLE_BASE = 0x1C0000          # $E6AA (lea $1C0000 at $13C58)
SOUND_ID_TABLE = 0x1F5C6        # sound_play $13CEE: id - $12 -> instrument index (word, < 0 = none)
SOUND_ID_FIRST = 0x12
SOUND_ID_COUNT = 0x29           # ids $12-$3A; the range check at $13D2C admits $12-$4C,
                                # but entries past $3A belong to other data
SAMPLE_KINDS = (0, 3)
CODEC_RAW, CODEC_TYPE1, CODEC_DPCM = 0, 1, 2

DRIVER_BLOB = 0x15C90           # length word, then the code loaded at Z80 $0000
DPCM_DELTA_TABLE = DRIVER_BLOB + 2 + 0x112   # 16 signed bytes (Z80 $0112)

Z80_HZ = 53_693_175 / 15        # NTSC
BUS_WAIT_T = 3                  # extra T-states per Z80 read through the bank window
RAW_PERIOD_T = 321 + BUS_WAIT_T             # one sample playing (raw)
MIX_PERIOD_T = {1: 321 + BUS_WAIT_T, 2: 317 + 2 * BUS_WAIT_T,
                3: 314 + 3 * BUS_WAIT_T, 4: 311 + 4 * BUS_WAIT_T}
DPCM_PAIR_T = 330 + 319 + 2 * BUS_WAIT_T    # two DAC writes per DPCM byte
RAW_RATE = Z80_HZ / RAW_PERIOD_T            # ~11 048 Hz
DPCM_RATE = 2 * Z80_HZ / DPCM_PAIR_T        # ~10 930 Hz


@dataclass(frozen=True)
class SampleDesc:
    index: int                  # instrument index (what $17CDE takes in D0)
    record: int                 # ROM address of the instrument record
    kind: int                   # 0 = sample, 3 = pitched sample (note table at record + $16)
    priority: int
    bank_mask: int
    offset: int                 # record +8
    loop: bool
    loop_start: int             # index into the data where a loop restarts
    flags: int                  # record +$10
    copies: tuple[int, ...]     # ROM address of the header of every copy (lowest bank first)
    codec: int                  # header byte
    data: int                   # ROM address of the first data byte (first copy)
    length: int                 # data bytes before the 0 terminator
    sound_ids: tuple[int, ...]  # sound_play ids that start this sample (pitch $100, volume $80)

    @property
    def address(self) -> int:
        return self.copies[0]

    @property
    def output_samples(self) -> int:
        """DAC writes for one pass at pitch $100 (DPCM: two per byte)."""
        return self.length * 2 if self.codec == CODEC_DPCM else self.length

    @property
    def rate(self) -> float:
        """Playback rate in Hz at pitch $100 with the sample playing alone."""
        return DPCM_RATE if self.codec == CODEC_DPCM else RAW_RATE

    @property
    def duration_ms(self) -> float:
        """One pass, without the 68000's bus stalls and the driver's per-tick work."""
        return 1000.0 * self.output_samples / self.rate


def instrument_offsets(rom: Rom) -> list[int]:
    return list(struct.unpack_from(f">{INSTRUMENT_COUNT}H", rom.data, INSTRUMENT_TABLE))


def sound_id_map(rom: Rom) -> dict[int, int]:
    """sound_play id -> instrument index (ids $12-$3A with an entry >= 0)."""
    out = {}
    for i in range(SOUND_ID_COUNT):
        v = struct.unpack_from(">h", rom.data, SOUND_ID_TABLE + 2 * i)[0]
        if v >= 0:
            out[SOUND_ID_FIRST + i] = v
    return out


def _copies(offset: int, mask: int) -> tuple[int, ...]:
    a = SAMPLE_BASE + offset
    banks = [k for k in range(32) if mask >> k & 1] or [0]
    return tuple((((a >> 15) + k) << 15) | (a & 0x7FFF) for k in banks)


def parse_sample(rom: Rom, index: int, ids: dict[int, int] | None = None) -> SampleDesc | None:
    """The sample record of instrument ``index``, or None if it is not a sample."""
    rec = INSTRUMENT_TABLE + instrument_offsets(rom)[index]
    kind, pri = rom.data[rec], rom.data[rec + 1]
    if kind not in SAMPLE_KINDS:
        return None
    mask, offset = struct.unpack_from(">II", rom.data, rec + 4)
    loop_start = rom.u16(rec + 0xE)
    flags = rom.data[rec + 0x10]
    copies = _copies(offset, mask)
    codec = rom.data[copies[0]]
    data = copies[0] + (2 if codec not in (CODEC_RAW, CODEC_DPCM) else 1)
    length = rom.data.index(b"\0", data) - data
    if ids is None:
        ids = sound_id_map(rom)
    return SampleDesc(index, rec, kind, pri, mask, offset, bool(flags & 1), loop_start, flags,
                      copies, codec, data, length, tuple(s for s, v in ids.items() if v == index))


def samples(rom: Rom) -> list[SampleDesc]:
    """Every sample instrument, in instrument-index order (one per record)."""
    ids = sound_id_map(rom)
    out, seen = [], set()
    for i, off in enumerate(instrument_offsets(rom)):
        if off in seen:
            continue
        seen.add(off)
        d = parse_sample(rom, i, ids)
        if d is not None:
            out.append(d)
    return out


def dpcm_deltas(rom: Rom) -> tuple[int, ...]:
    """DPCM code -> signed delta, as the driver has it."""
    return struct.unpack_from(">16b", rom.data, DPCM_DELTA_TABLE)


def decode(rom: Rom, desc: SampleDesc) -> bytes:
    """The unsigned 8-bit values the DAC receives for one pass at pitch $100 and
    full volume ($80: the driver's volume table is then the identity)."""
    raw = rom.data[desc.data:desc.data + desc.length]
    if desc.codec == CODEC_RAW:
        return bytes(raw)
    if desc.codec == CODEC_DPCM:
        deltas = dpcm_deltas(rom)
        out = bytearray()
        v = 0x80
        for b in raw:
            v = (v + deltas[b >> 4]) & 0xFF
            out.append(v)
            v = (v + deltas[b & 0xF]) & 0xFF
            out.append(v)
        return bytes(out)
    raise ValueError(f"instrument {desc.index}: codec {desc.codec} is not decoded (no sample uses it)")


def volume_table(volume: int) -> bytes:
    """The driver's 256-byte volume table ($0C07 -> Z80 $1B00) for a volume byte
    ($80 = unchanged; values above $80 amplify and wrap around)."""
    acc = ((0x80 - volume) & 0xFF) << 8
    step = (2 * volume) & 0x1FF
    out = bytearray()
    for _ in range(256):
        out.append(acc >> 8 & 0xFF)
        acc = (acc + step) & 0xFFFF
    return bytes(out)


def mix(values: list[int], carry_bug: bool = True) -> int:
    """The DAC value for 1-4 channels' current bytes (the first already through
    the volume table): signed sum around $80, clamped to 0..255 (tables
    $1C00-$1FFF). With 4 channels the original loses the carry of the first
    addition (Z80 $06FC: XOR A clears it before ADC A,A), so about half the
    outputs clip to 0; ``carry_bug=False`` gives the intended sum."""
    if len(values) == 4 and carry_bug:
        total = ((values[0] + values[1]) & 0xFF) + values[2] + values[3]
    else:
        total = sum(values)
    return max(0, min(255, total - 0x80 * (len(values) - 1)))
