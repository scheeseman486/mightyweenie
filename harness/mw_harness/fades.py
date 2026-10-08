"""Find palette fades in the original (start, length, direction) from CRAM.

The original fades by stepping CRAM colours towards/away from black. We
measure overall palette brightness per frame and report monotonic runs that
end (fade out) or start (fade in) at black. Our reimplementation uses a
traditional fader with the same timing (docs/architecture.md).
"""
from __future__ import annotations

from dataclasses import dataclass


def brightness(cram) -> int:
    """Sum of the 3-bit R, G, B levels of all 64 CRAM entries."""
    return sum(((c >> 1) & 7) + ((c >> 5) & 7) + ((c >> 9) & 7) for c in cram)


@dataclass
class Fade:
    direction: str      # "in" or "out"
    start_frame: int    # first frame whose palette differs from the start level
    end_frame: int      # frame on which the target level is reached
    start_tick: int
    end_tick: int
    screen: int

    @property
    def frames(self) -> int:
        return self.end_frame - self.start_frame + 1

    @property
    def ticks(self) -> int:
        return self.end_tick - self.start_tick + 1


def find_fades(samples, min_frames: int = 6) -> list[Fade]:
    """samples: iterable of (frame, tick, screen, cram). Returns fades in order.

    A fade is a run of frames where brightness changes monotonically (allowing
    hold frames between steps) that starts or ends at full black.
    """
    fades: list[Fade] = []
    run = None  # (direction, start_index)
    rows = list(samples)
    b = [brightness(r[3]) for r in rows]
    i = 1
    while i < len(rows):
        if b[i] == b[i - 1]:
            i += 1
            continue
        direction = "in" if b[i] > b[i - 1] else "out"
        start = i
        j = i
        last_change = i
        while j + 1 < len(rows):
            d = b[j + 1] - b[j]
            if d == 0:
                if j + 1 - last_change > 4:  # more than 4 static frames ends the run
                    break
            elif (d > 0) != (direction == "in"):
                break
            else:
                last_change = j + 1
            j += 1
        end = last_change
        starts_black = b[start - 1] == 0
        ends_black = b[end] == 0
        if end - start + 1 >= min_frames and ((direction == "in" and starts_black) or
                                              (direction == "out" and ends_black)):
            fs, ts, sc, _ = rows[start]
            fe, te, _, _ = rows[end]
            fades.append(Fade(direction, fs, fe, ts, te, sc))
        i = end + 1
    return fades
