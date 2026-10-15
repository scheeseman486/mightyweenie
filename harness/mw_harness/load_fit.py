"""The rink pass load model (plan 36, docs/re/timing.md "Pass load"): what
each rink pass costs the original's 68000, fitted on the load recordings
(:mod:`load_record`) against the port's own features of the same passes,
for the rink's TICK RATE ORIGINAL (``MwPassCost``, ``MwPassPacer``).

Inputs (all local, under ``out/``):

* ``out/load/NAME/``: load recordings (``load-record NAME``): the 68000's
  cycle stamps through every rink pass, the VBlank handler's callbacks, the
  DMA queue's pushes, per player update and AI think;
* ``out/load_sound/NAME/``: the same with ``--sound``: the sound driver's
  work per VBlank (its cost model);
* ``DIR/NAME.jsonl``: the port's features of every pass of those runs
  (``tools/bin/pass-check --load-features DIR --rec-dir out/load NAME``:
  ``MwPassLoad.features`` while the port replays the recording, visits
  identical throughout).

Fits (least squares, 68000 cycles): the player updates per player (the
recordings' `$86A` calls joined to the port's players by team and slot), the
teams' own work, the phase handler, the rink update, the clock, the rest
before / after the DMA queue wait, the five draw parts, the sound driver per
VBlank. Evaluation (``--check``): fitted on even rink visits, the odd ones
predicted - each part's error; the pass lengths open loop (each pass from
its recorded start, the VBlank grid as recorded) and closed loop (chained
through the visit) against the recorded elapsed ticks, for ORIGINAL's
model and APPROXIMATED's integers. ``--write`` puts the weights (fitted on
everything) into ``game/src/sim/pass_cost_weights.gd`` and, in 1/16
cycles, ``pass_approx_weights.gd`` (TICK RATE APPROXIMATED).

    tools/bin/py -m mw_harness load-fit --features out/plan36/feat [--check] [--write]
"""
from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

from .trace import REPO_ROOT

LOAD_DIR = REPO_ROOT / "out" / "load"
SOUND_DIR = REPO_ROOT / "out" / "load_sound"
WEIGHTS = REPO_ROOT / "game" / "src" / "sim" / "pass_cost_weights.gd"
APPROX_WEIGHTS = REPO_ROOT / "game" / "src" / "sim" / "pass_approx_weights.gd"
FRAME = 896040                  # master clocks per NTSC frame
CPU = 7                         # master clocks per 68000 cycle
#: BlastEm rebases its 32-bit cycle counter now and then by 4 775 frames
#: (the logged value drops).
REBASE = 4775 * FRAME
TEAMS = (0xFFB402, 0xFFB8AC)    # the teams' RAM; players at +$6C, $76 bytes each
#: Part costs between two probe tags (:data:`load_record.PASS_PROBES`).
PART_TAGS = {
    "clock": (3, 4), "pads": (4, 5), "control": (5, 6), "team1": (6, 7), "team2": (7, 8), "puck": (8, 9),
    "portrait": (9, 10), "objects": (10, 11), "cam_target": (11, 12), "rink_update": (12, 13),
    "replay_rec": (15, 16), "pen_timers": (16, 17), "puck_rules": (17, 18), "phase_cost": (18, 19),
    "draw_a": (19, 20), "draw_b": (20, 21), "draw_puck": (21, 22), "draw_rink": (22, 23),
    "draw_portrait": (23, 24), "replay_close": (24, 25), "first_pass": (25, 26), "queue": (26, 29),
}
A_REST = ["pads", "control", "puck", "portrait", "objects", "cam_target"]
B_REST = ["replay_rec", "pen_timers", "puck_rules", "replay_close", "first_pass", "queue"]
DRAWS = {"draw_a": "draw_team_a", "draw_b": "draw_team_b", "draw_puck": "draw_puck", "draw_rink": "draw_rink",
         "draw_portrait": "draw_portrait"}
DRAW_SECTIONS = ["draw_phase", "draw_team_a", "draw_team_b", "draw_puck", "draw_rink", "draw_portrait"]
#: The VBlank handler (68000 cycles; measured, see docs/re/timing.md):
#: entry / exit and `$14AD4`, the DMA queue `$14752` per word, the fade
#: engine `$149F6` idle / running, the fade-in's VBlanks after a visit's
#: first pass, plane B's rows queued this far into the rink update.
H_BASE, H_QUEUE, H_QUEUE_WORD = 415.0, 523.0, 5.806
H_FADE = (3240.0, 49630.0)
FADE_VBLANKS = 31
RU_PRE = 4110.0
A_GLUE, B_GLUE = 114.0, 174.0
SOUND_TAGS = list(range(70, 91))     # :data:`load_record.SOUND_PROBES`
SOUND_RUNS = ["cpu_s0", "p4_s22", "p1_s9", "coop_s14", "match_p1_s6"]


# --- the recordings ---------------------------------------------------------------------------

def load(name: str, root: Path = LOAD_DIR) -> dict:
    return json.loads((root / name / "meta.json").read_text())


def stream(meta: dict) -> list[list[int]]:
    """Every ``ld`` entry in order, cycles unwrapped: [tag, cycle, value, recorder pass]."""
    per = meta["log_data"]["ld"]
    out, base, last = [], 0, None
    for p in sorted(per, key=int):
        for part in per[p]:
            for t, c, v in part:
                if last is not None and c < last:
                    base += REBASE
                last = c
                out.append([t, base + c, v, int(p)])
    return out


def _pass(seg: list) -> dict:
    vbs, v, pushes, stamps = [], None, [], {}
    for t, c, val, _ in seg[:-1]:
        if t == 40:
            v = {"in": c, "cb": []}
        elif t == 41 and v is not None:
            v["cb"].append([val & 0xFFFFFF, c, None])
        elif t == 42 and v is not None and v["cb"]:
            v["cb"][-1][2] = c
        elif t == 43 and v is not None:
            v["out"] = c
            vbs.append(v)
            v = None
        elif t == 50:
            pushes.append([c, val & 0xFFFF])
        elif t not in stamps:
            stamps[t] = c
    return {"start": seg[0][1], "end": seg[-1][1], "e": seg[0][2], "e_next": seg[-1][2], "stamps": stamps,
            "vblanks": vbs, "pushes": pushes}


def _htime(p: dict, a: int, b: int) -> int:
    return sum(v["out"] - v["in"] for v in p["vblanks"] if a <= v["in"] < b)


def pass_rows(name: str, root: Path = LOAD_DIR) -> list[dict]:
    """The rink visits of a load recording, each {"ents": VBlank handler
    entries, "hs": their lengths, "passes": [...]}: per pass (the recorder's
    pass n: tag 1 to the next) its part costs in 68000 cycles (handlers
    out), A (to the DMA wait) and B (after it), the words queued."""
    meta = load(name, root)
    ent = stream(meta)
    starts = [i for i, e in enumerate(ent) if e[0] == 1]
    rows = []
    for a, b in zip(starts, starts[1:]):
        seg = ent[a:b + 1]
        tags = [e[0] for e in seg]
        if not {5, 13, 14, 29} <= set(tags):
            rows.append(None)
            continue
        n = seg[tags.index(5)][3]                  # the recorder pass whose segment this is
        p = _pass(seg)
        s = p["stamps"]
        r = {"run": name, "n": n, "e": p["e"], "e_next": p["e_next"], "start": p["start"], "end": p["end"]}
        for k, (t1, t2) in PART_TAGS.items():
            r[k] = (s[t2] - s[t1] - _htime(p, s[t1], s[t2])) / CPU if t1 in s and t2 in s else 0.0
        r["A"] = (s[13] - p["start"] - _htime(p, p["start"], s[13])) / CPU
        r["B"] = (p["end"] - s[14] - _htime(p, s[14], p["end"])) / CPU
        r["handlers"] = [(v["out"] - v["in"]) / CPU for v in p["vblanks"]]
        r["ru_words"] = sum(w for c, w in p["pushes"] if s[12] <= c < s[13])
        r["words"] = sum(w for c, w in p["pushes"])
        r["_vblanks"] = p["vblanks"]
        rows.append(r)
    visits, cur = [], []
    for r in rows + [None]:
        if r is not None:
            cur.append(r)
            continue
        ents = [v["in"] for q in cur for v in q["_vblanks"]]
        if len(ents) >= 4 and all(abs((y - x) - FRAME) <= 20000 for x, y in zip(ents, ents[1:])):
            visits.append({"ents": ents, "hs": [(v["out"] - v["in"]) / CPU for q in cur for v in q["_vblanks"]],
                           "passes": cur})
        cur = []
    for v in visits:
        for r in v["passes"]:
            r.pop("_vblanks", None)
    return visits


def player_rows(name: str, root: Path = LOAD_DIR) -> dict:
    """(recorder pass, team, slot) -> the player's update cost (`$86A`,
    handlers out), 68000 cycles."""
    vb, vin, out, cur = [], None, {}, None
    ent = stream(load(name, root))
    for t, c, v, n in ent:
        if t == 40:
            vin = c
        elif t == 43 and vin is not None:
            vb.append((vin, c))
            vin = None
    import bisect
    vin_list = [a for a, _ in vb]

    def htime(a, b):
        j = bisect.bisect_left(vin_list, a)
        s = 0
        while j < len(vb) and vb[j][0] < b:
            s += vb[j][1] - vb[j][0]
            j += 1
        return s
    for t, c, v, n in ent:
        if t == 61:
            cur = (v & 0xFFFFFF, c, n)
        elif t == 62 and cur is not None:
            a = 0xFF0000 | cur[0]
            team = 0 if a < TEAMS[1] else 1
            out[(cur[2], team, (a - TEAMS[team] - 0x6C) // 0x76)] = (c - cur[1] - htime(cur[1], c)) / CPU
            cur = None
    return out


def sound_rows(name: str, root: Path = SOUND_DIR) -> list[tuple[list[int], float]]:
    """Per `$13DE8` call: the sound probes' counts and its cycles."""
    out, cnt, c0 = [], None, None
    for t, c, v, _ in stream(load(name, root)):
        if t == 41:
            cnt = dict.fromkeys(SOUND_TAGS, 0) if (v & 0xFFFFFF) == 0x13DE8 else None
            c0 = c
        elif t == 42 and cnt is not None:
            out.append(([cnt[k] for k in SOUND_TAGS], (c - c0) / CPU))
            cnt = None
        elif cnt is not None and t in cnt:
            cnt[t] += 1
    return out


# --- the features (MwPassCost's vectors) ----------------------------------------------------

PSTATES = [0, 1, 2, 3, 4, 5, 8, 10, 14, 15, 20]
PPHASES = [0, 1, 3, 4, 5, 8, 9, 10, 14]
PHASES = [0, 1, 3, 5, 8, 9]
KINDS = list(range(1, 24))
PLAYER_FEATURES = 14 + len(PSTATES) + len(PPHASES) + 13


def player_x(a: list, f: dict) -> np.ndarray:
    t, on, own, oth, goalie, carrier, state, human, think, ai, _orig, weapon, _anim = a
    h = [sum(1 for k in f["hazards"] if k == j) for j in (1, 2, 3, 4)]
    v = np.array([1, human, ai > 0, ai, carrier, goalie, t == 0, f["e"], think, weapon >= 0] + h
                 + [state == s for s in PSTATES] + [f["phase"] == q for q in PPHASES]
                 + [own + oth == j for j in range(13)], float)
    return np.concatenate([v * on, v * (1 - on)])


def players_x(f: dict) -> np.ndarray:
    acc = np.zeros(2 * PLAYER_FEATURES)
    for a in f["players"]:
        acc += player_x(a, f)
    return acc


def _kinds(f):
    return [sum(1 for k in f["kinds"] if k == j) for j in KINDS]


def _draw(sec):
    return np.array(list(sec[:6]) + [1.0], float)


def _clock(w):
    if w is None:
        return np.array([0, 0, 0, 0, 0, 1, 1.0])
    return np.array(list(w[:5]) + [w[0] == 0, 1.0], float)


def _ru(f):
    r = f["rows"]
    full = r > 4
    return np.array([0 if full else r, full, f["objects"], f["objects"] * (f["phase"] in (0, 1)),
                     f["nets"][0] == 0, f["nets"][0] == 2] + _kinds(f) + [1.0], float)


def _a_rest(f):
    fl, sp, z, vz = f["puck0"]
    return np.array([f["objects"], fl & 1, (fl >> 1) & 1, sp > 0, z > 0, vz > 0, f["e"]] + _kinds(f)
                    + [f["phase"] == q for q in PPHASES] + [1.0], float)


def _b_rest(f):
    return np.array([f["replay"] != 0] + [f["phase"] == q for q in PPHASES]
                    + [f["phase_end"] != f["phase"], 1.0], float)


def _phase(f):
    return np.array(list(f["window"][:5]) + list(f["draw_phase"][:6]) + [f["phase"] == q for q in PHASES]
                    + [f["phase_end"] != f["phase"], 1.0], float)


#: model -> (features of (pass features, clock counts), the recorded cost of a row)
MODELS = {
    "teams": (lambda f, c: np.array([f["phase"] == q for q in PPHASES] + [len(f["players"]), 1.0], float),
              lambda r: r["team1"] + r["team2"]),
    "phase_cost": (lambda f, c: _phase(f), lambda r: r["phase_cost"]),
    "rink_update": (lambda f, c: _ru(f), lambda r: r["rink_update"]),
    "clock": (lambda f, c: _clock(c), lambda r: r["clock"]),
    "A_rest": (lambda f, c: _a_rest(f), lambda r: sum(r[k] for k in A_REST)),
    "B_rest": (lambda f, c: _b_rest(f), lambda r: sum(r[k] for k in B_REST)),
}
for _k, _sec in DRAWS.items():
    MODELS[_k] = ((lambda s: (lambda f, c: _draw(f[s])))(_sec), (lambda kk: (lambda r: r[kk]))(_k))


def words(f: dict) -> tuple[int, int]:
    """Words queued by the rink update; after the wait (uploads, the list)."""
    r = f["rows"]
    tiles = sum(f[s][4] for s in DRAW_SECTIONS)
    adds = sum(f[s][0] for s in DRAW_SECTIONS)
    return (2048 if r > 4 else 64 * r), 16 * tiles + 4 * adds


# --- fitting ---------------------------------------------------------------------------------

def dataset(names: list[str], features: Path, root: Path = LOAD_DIR) -> list:
    """[(name, visit, [(row, features, clock counts)])] - a pass's clock is
    the previous features' "clock_next" (the replay's order)."""
    out = []
    for n in names:
        F = {}
        for line in open(features / f"{n}.jsonl"):
            f = json.loads(line)
            F[f["n"]] = f
        for v in pass_rows(n, root):
            vv = []
            for r in v["passes"]:
                f = F.get(r["n"])
                prev = F.get(r["n"] - 1)
                vv.append((r, f, prev["clock_next"] if prev else None))
            out.append((n, v, vv))
    return out


def fit(data: list, players: dict) -> dict:
    W = {}
    X, Y = [], []
    for n, v, vv in data:
        for r, f, c in vv:
            if f is None:
                continue
            ps = sorted(((k[1], k[2]), cost) for k, cost in players[n].get(r["n"], {}).items())
            if len(ps) != len(f["players"]):
                continue
            for a, (_, cost) in zip(f["players"], ps):
                X.append(player_x(a, f))
                Y.append(cost)
    W["players"] = np.linalg.lstsq(np.array(X), np.array(Y), rcond=None)[0]
    for k, (fx, fy) in MODELS.items():
        X, Y = [], []
        for n, v, vv in data:
            for r, f, c in vv:
                if f is None:
                    continue
                X.append(fx(f, c))
                Y.append(fy(r) - (float(players_x(f) @ W["players"]) if k == "teams" else 0.0))
        W[k] = np.linalg.lstsq(np.array(X, float), np.array(Y, float), rcond=None)[0]
    return W


def predict(W: dict, f: dict, c) -> dict:
    q = {k: float(fx(f, c) @ W[k]) for k, (fx, _) in MODELS.items()}
    q["teams"] += float(players_x(f) @ W["players"])
    return q


def parts(W: dict, f: dict, c) -> tuple:
    """(before the wait, the rink update, after the wait, (rows' words, words))."""
    q = predict(W, f, c)
    a1 = q["teams"] + q["clock"] + q["A_rest"] + A_GLUE
    b = q["phase_cost"] + sum(q[k] for k in DRAWS) + q["B_rest"] + B_GLUE
    return max(a1, 0.0), max(q["rink_update"], 0.0), max(b, 0.0), words(f)


def handler(words_: int, fade: bool, sound: float) -> float:
    return H_BASE + H_QUEUE + H_QUEUE_WORD * words_ + H_FADE[1 if fade else 0] + sound


def handler_mclk(words_: int, fade: bool, sound: int) -> int:
    """MwPassCost.handler_mclk: master clocks, integers."""
    return 6566 + words_ * 40642 // 1000 + (347410 if fade else 22680) + sound


def run_pass(t: int, base: int, p: tuple, st: list, hfun=None, first=False, mclk=False) -> tuple[int, int]:
    """One pass from master clock [t] on the VBlank grid base + k FRAME, as
    MwPassPacer (integers, master clocks); p = (before, rink update, after,
    (rows' words, words)) in 68000 cycles (rounded to master clocks here) or,
    with [mclk], already in master clocks. st = [words queued since the last
    VBlank, fade VBlanks left], updated; hfun(words) -> a handler's master
    clocks (default: the model with the sound driver at its mean). Returns
    (its end, the VBlanks in it)."""
    a1, ru, b, (wru, wb) = p
    if not mclk:
        a1, ru, b = (int(round(x * CPU)) for x in (a1, ru, b))
    pre = min(ru, int(RU_PRE) * CPU) if wru > 0 else ru
    t = int(t)
    k = (t - base) // FRAME + 1
    n = 0

    def vblank(k):
        h = handler_mclk(st[0], st[1] > 0, SOUND_MEAN_MCLK) if hfun is None else int(hfun(st[0]))
        st[0] = 0
        st[1] = max(st[1] - 1, 0)
        return base + k * FRAME + h, k + 1

    def work(t, amt, k, n):
        while t + amt > base + k * FRAME:
            amt -= base + k * FRAME - t
            t, k = vblank(k)
            n += 1
        return t + amt, k, n
    t, k, n = work(t, a1, k, n)
    t, k, n = work(t, pre, k, n)
    st[0] += wru
    t, k, n = work(t, ru - pre, k, n)
    if st[0] > 0 and wru > 0:
        t, k = vblank(k)
        n += 1
    t, k, n = work(t, b, k, n)
    st[0] += wb
    if first:
        st[1] = FADE_VBLANKS
    if n == 0:
        t, k = vblank(k)
        n += 1
    return t, n


SOUND_MEAN = 3684.0
SOUND_MEAN_MCLK = 25788


#: APPROXIMATED's fixed point: weights in 1/16 cycles (MwPassApprox.SCALE).
APPROX_SCALE = 16


def round_weights(W: dict, scale: int = APPROX_SCALE) -> dict:
    """APPROXIMATED's weights: integers in 1/[scale] cycles (MwPassApproxWeights)."""
    return {k: np.round(w * scale).astype(np.int64) for k, w in W.items()}


def fit_sound(root: Path = SOUND_DIR) -> tuple[np.ndarray, float, float]:
    rows = [r for n in SOUND_RUNS if (root / n / "meta.json").exists() for r in sound_rows(n, root)]
    if not rows:
        raise SystemExit(f"no sound recordings in {root} (load-record {' '.join(SOUND_RUNS)} --sound)")
    X = np.array([r[0] + [1] for r in rows], float)
    Y = np.array([r[1] for r in rows])
    w = np.linalg.lstsq(X, Y, rcond=None)[0]
    return w, float(Y.mean()), float((Y - X @ w).std())


# --- evaluation and the weights ----------------------------------------------------------------

def check(names: list[str], features: Path, root: Path = LOAD_DIR) -> None:
    data = dataset(names, features, root)
    players = {n: _players_by_pass(n, root) for n in names}
    train = [d for i, d in enumerate(data) if i % 2 == 0]
    test = [d for i, d in enumerate(data) if i % 2 == 1]
    W = fit(train, players)
    for label, w, scale in (("ORIGINAL's model (the sound driver at its mean)", W, 0),
                            ("APPROXIMATED (integers, 1/16 cycles)", round_weights(W), APPROX_SCALE)):
        print(label)
        _check_timeline(data, test, w, scale)


def _check_timeline(data, test, W, scale: int = 0) -> None:
    err = defaultdict(list)
    for n, v, vv in test:
        for r, f, c in vv:
            if f is None:
                continue
            q = predict(W, f, c)
            for k, (_, fy) in MODELS.items():
                err[k].append(fy(r) - q[k])
    print("held-out visits, each part's error (68000 cycles): mean / sd")
    for k, e in err.items():
        print(f"  {k:14s} {np.mean(e):8.0f} {np.std(e):8.0f}")
    first = {}                               # the port visit's first pass (the fade-in after it)
    for n, v, vv in data:
        for r, f, c in vv:
            if f is not None:
                first[(n, f["visit"])] = min(first.get((n, f["visit"]), r["n"]), r["n"])
    first_n = {}
    for n, v, vv in test:
        res, per = Counter(), [0, 0, 0]
        for closed in (False, True):
            base, st, t = v["ents"][0], [0, 0], vv[0][0]["start"]
            for i, (r, f, c) in enumerate(vv):
                if f is None:
                    break
                t, e = run_pass(t if closed else r["start"], base, _parts_mclk(W, f, c, scale), st,
                                first=first[(n, f["visit"])] == r["n"], mclk=True)
                if closed:
                    per[0] += 1
                    per[1] += e
                    per[2] += r["e_next"]
                else:
                    res[e - r["e_next"]] += 1
        first_n.setdefault(n, [Counter(), [0, 0, 0]])
        first_n[n][0].update(res)
        first_n[n][1] = [x + y for x, y in zip(first_n[n][1], per)]
    tot, ticks = Counter(), [0, 0, 0]
    for n, (res, per) in first_n.items():
        tot.update(res)
        ticks = [x + y for x, y in zip(ticks, per)]
        print(f"  {n:16s} closed loop {100 * (per[1] - per[2]) / max(per[2], 1):+.2f} % ticks over {per[0]} passes")
    s = sum(tot.values())
    print("open loop: exact %.3f, within one %.3f; closed loop %+.2f %% ticks (mean %.3f against %.3f)" % (
        tot[0] / s, (tot[0] + tot[1] + tot[-1]) / s, 100 * (ticks[1] - ticks[2]) / ticks[2], ticks[1] / ticks[0],
        ticks[2] / ticks[0]))


def _parts_mclk(W: dict, f: dict, c, scale: int = 0) -> tuple:
    """parts() in master clocks: rounded as MwPassCost.work_mclk, or with
    [scale] (APPROXIMATED's integer weights in 1/scale cycles) as
    MwPassApprox.work."""
    if not scale:
        a1, ru, b, w = parts(W, f, c)
        return int(round(a1 * CPU)), int(round(ru * CPU)), int(round(b * CPU)), w
    q = {k: int(round(float(fx(f, c) @ W[k]))) for k, (fx, _) in MODELS.items()}
    q["teams"] += int(round(float(players_x(f) @ W["players"])))
    a1 = q["teams"] + q["clock"] + q["A_rest"] + int(A_GLUE) * scale
    b = q["phase_cost"] + sum(q[k] for k in DRAWS) + q["B_rest"] + int(B_GLUE) * scale
    return (max(a1, 0) * CPU // scale, max(q["rink_update"], 0) * CPU // scale, max(b, 0) * CPU // scale,
            words(f))


def _players_by_pass(name: str, root: Path) -> dict:
    out = defaultdict(dict)
    for (n, team, slot), cost in player_rows(name, root).items():
        out[n][(n, team, slot)] = cost
    return out


def write_weights(names: list[str], features: Path, root: Path = LOAD_DIR, path: Path = WEIGHTS) -> None:
    data = dataset(names, features, root)
    W = fit(data, {n: _players_by_pass(n, root) for n in names})
    ws, mean, sd = fit_sound()
    passes = sum(len(v["passes"]) for _, v, _ in data)

    def arr(w):
        return "[" + ", ".join("%.4f" % x for x in w) + "]"

    def iarr(w):
        return "[" + ", ".join("%d" % x for x in w) + "]"
    lines = ["class_name MwPassCostWeights", "extends RefCounted",
             "## Generated by `mw_harness load-fit --write` (plan 36, docs/re/timing.md",
             "## \"Pass load\"): the weights of [MwPassCost]'s linear models, 68000 cycles",
             "## per feature (see [MwPassCost] for each vector's layout). Fitted on %d rink" % passes,
             "## passes of %d BlastEm load recordings (EA 4-Way Play, six-button pads);" % len(names),
             "## the sound driver's per VBlank (mean %.0f cycles, residual sd %.0f). Do not" % (mean, sd),
             "## edit by hand.", ""]
    for k in ["players"] + list(MODELS):
        lines.append("const %s := %s" % (k.upper(), arr(W[k])))
    lines.append("const SOUND := %s" % arr(ws))
    path.write_text("\n".join(lines) + "\n")
    print(f"weights from {passes} passes -> {path}")
    R = round_weights(W)
    lines = ["class_name MwPassApproxWeights", "extends RefCounted",
             "## Generated by `mw_harness load-fit --write` (plan 36, docs/re/timing.md",
             "## \"Pass load\"): [MwPassCostWeights] in 1/16 cycles, rounded, for TICK RATE",
             "## APPROXIMATED ([MwPassApprox]: integers only, the same on every machine).",
             "## The same vectors' layouts as [MwPassCost]'s. Do not edit by hand.", ""]
    for k in ["players"] + list(MODELS):
        lines.append("const %s := %s" % (k.upper(), iarr(R[k])))
    APPROX_WEIGHTS.write_text("\n".join(lines) + "\n")
    print(f"APPROXIMATED's integer weights -> {APPROX_WEIGHTS}")


def main(args) -> None:
    features = Path(args.features)
    names = sorted(p.stem for p in features.glob("*.jsonl") if (LOAD_DIR / p.stem / "meta.json").exists())
    if args.check:
        check(names, features)
    if args.write:
        write_weights(names, features)
