"""Command-line entry: ``tools/bin/py -m mw_harness <command>``.

  info                       ROM identification + header checks
  run  -n FRAMES [-i SCRIPT] [--every N] [-o DIR]
                             run headless and dump state/screens to DIR
  watch -n FRAMES ADDR[:SIZE] ...
                             print RAM values whenever they change
  fades -n FRAMES [-i SCRIPT]
                             list palette fades (start/length in frames and ticks)
  trace -n FRAMES -p ADDR:LABEL[:EXPR,...] ... [-i SCRIPT] [--divider N]
                             BlastEm breakpoint trace, one line per hit
                             (EXPR in BlastEm syntax: [0xffca56].l, d0, ...)
  record SCRIPT.mwi [--probes time,input,screen,...] [-o OUT] [--max-ticks N]
                             play an input script on the original (BlastEm,
                             EA 4-Way Play) and write its pass record
                             (docs/compare.md); cached in out/compare/
  diff A.jsonl B.jsonl [--probes ...] [--context N]
                             first difference between two pass records
  assets [SCRIPT.mwi ...] [-o OUT] [--no-cache]
                             trace what the original loads while playing the
                             tour scripts (default compare/scripts/tour_*.mwi)
                             and write the ROM catalogue (default
                             game/data/rom_catalogue.json); traces are cached
                             in out/assets/
  gfx-hashes [-o OUT]        digests of everything the catalogue decodes to
                             (compare/fixtures/gfx_hashes.json; the GDScript
                             decoders must reproduce them)
  menu-cases [NAME ...] [--update]
                             setup bytes after compare/scripts/menu_*.mwi on the
                             original -> compare/fixtures/menu_cases.json
  playoff-vectors [NAME ...] [--update]
                             the original's playoff state, teams, bracket and
                             passwords in a few scenarios (GPGX) ->
                             compare/fixtures/playoffs.json
  td-cases [NAME ...] [--update]
                             team description vscroll/side/cursor/line after
                             compare/scripts/td_*.mwi on the original ->
                             compare/fixtures/team_description.json
  rink-record [NAME ...]     record the standard rink runs on the original
                             (BlastEm, ~90 s each) -> out/rink/NAME.jsonl.gz
  rink-fixtures              compare/fixtures/rink_draw.json and rink_camera.json
                             from those recordings
  rink-dump [NAME ...] [--every N]
                             every pass of a recording as JSON (out/rink/dec/):
                             full local checks, the rink scene's playback
  sim-record [NAME ...] [--passes N] [--budget S] [--out DIR]
                             simulation recordings of the original (BlastEm,
                             ~90-165 s each) -> out/sim/NAME/ (docs/compare.md,
                             Simulation recordings; runs: RUNS, RUNS3)
  title-timeline [--update]  ticks of screen 0's milestones in the original
                             (no input + skips) -> compare/fixtures/title_timeline.json
  gfx-checkpoints [NAME ...] [--update]
                             measure the checkpoints of
                             compare/fixtures/gfx_checkpoints.json on the
                             original (GPGX); --update rewrites their
                             regression thresholds
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from .emulator import InputScript, ReferenceEmulator
from .rom import Rom


def cmd_info(args) -> None:
    rom = Rom.load(args.rom)
    print(f"path      {rom.path}")
    print(f"size      {len(rom.data):#x}")
    print(f"sha1      {rom.sha1}  ({'OK: No-Intro MLH' if rom.is_mlh else 'UNKNOWN DUMP'})")
    print(f"system    {rom.system!r}")
    print(f"product   {rom.product_code!r}")
    print(f"checksum  header {rom.header_checksum:#06x} computed {rom.computed_checksum():#06x}")
    print(f"reset     SP {rom.reset_sp:#010x} PC {rom.reset_pc:#08x}")


def _dump(emu: ReferenceEmulator, out: Path) -> None:
    from PIL import Image

    s = emu.state()
    d = out / f"f{emu.frame:06d}"
    d.mkdir(parents=True, exist_ok=True)
    (d / "work_ram.bin").write_bytes(s.work_ram)
    (d / "vram.bin").write_bytes(s.vram)
    (d / "z80_ram.bin").write_bytes(s.z80_ram)
    (d / "state.gpgx").write_bytes(s.raw)
    (d / "regs.json").write_text(json.dumps({
        "frame": emu.frame,
        "cram": [f"{c:04X}" for c in s.cram],
        "vsram": [f"{v:04X}" for v in s.vsram[:40]],
        "vdp_regs": s.vdp_regs.hex(),
        "m68k": {k: f"{v:08X}" for k, v in s.m68k.items()},
    }, indent=1))
    Image.fromarray(emu.screen()).save(d / "screen.png")


def cmd_run(args) -> None:
    emu = ReferenceEmulator(args.rom)
    script = InputScript.parse(Path(args.input).read_text() if args.input else "")
    out = Path(args.out)
    for _ in range(args.frames):
        emu.step(script.buttons_at(emu.frame))
        if args.every and emu.frame % args.every == 0:
            _dump(emu, out)
    _dump(emu, out)
    print(f"ran {emu.frame} frames -> {out}")


def cmd_watch(args) -> None:
    emu = ReferenceEmulator(args.rom)
    script = InputScript.parse(Path(args.input).read_text() if args.input else "")
    watches = []
    for w in args.addrs:
        a, _, sz = w.partition(":")
        watches.append((int(a, 16), int(sz or 1)))
    last: dict[int, int] = {}
    for _ in range(args.frames):
        emu.step(script.buttons_at(emu.frame))
        s = emu.state(with_cpu=False)
        for addr, size in watches:
            v = int.from_bytes(s.work_ram[addr & 0xFFFF:(addr & 0xFFFF) + size], "big")
            if last.get(addr) != v:
                print(f"frame {emu.frame:6d}  ${addr:06X} = {v:#0{size * 2 + 2}x}")
                last[addr] = v


def cmd_fades(args) -> None:
    from .fades import find_fades

    emu = ReferenceEmulator(args.rom)
    script = InputScript.parse(Path(args.input).read_text() if args.input else "")
    samples = []
    for _ in range(args.frames):
        emu.step(script.buttons_at(emu.frame))
        s = emu.state(with_cpu=False)
        samples.append((emu.frame, s.ram_u32(0xFFCA56), s.ram_u16(0xFFB05E), s.cram))
    print(f"{'dir':4s} {'start':>7s} {'end':>7s} {'frames':>6s} {'ticks':>6s} screen")
    for f in find_fades(samples):
        print(f"{f.direction:4s} {f.start_frame:7d} {f.end_frame:7d} {f.frames:6d} {f.ticks:6d} {f.screen:6d}")


def cmd_trace(args) -> None:
    from .trace import Probe, run_trace

    probes = []
    for spec in args.probe:
        addr, label, *rest = spec.split(":")
        probes.append(Probe(int(addr, 16), label, rest[0].split(",") if rest else []))
    script = InputScript.parse(Path(args.input).read_text() if args.input else "")
    for e in run_trace(probes, args.frames, script, rom=args.rom, m68k_divider=args.divider):
        print(f"{e.frame:6d} {e.cycle:12d} {e.label:12s} " + " ".join(f"{v:#x}" for v in e.values))


DEFAULT_PROBES = "time,input,screen"


def original_record(script_path: Path, probes: str, rom=None, divider: int = 7, max_ticks=None,
                    out: Path | None = None, use_cache: bool = True) -> Path:
    """Path of the original's record for a script, recording it unless cached."""
    import shutil

    from . import probes as P
    from .record import cache_key, record_original
    from .rom import REPO_ROOT, default_rom_path
    from .script import Script

    rom_path = Path(rom) if rom else default_rom_path()
    text = Path(script_path).read_text()
    sets = P.load_many(probes)
    key = cache_key(text, [p.name for p in sets], Rom.load(rom_path).sha1, f"divider={divider} max={max_ticks}")
    cache = REPO_ROOT / "out" / "compare" / "cache" / f"{Path(script_path).stem}-{key}.jsonl"
    if not (use_cache and cache.exists()):
        record_original(Script.parse(text, Path(script_path).stem), sets, out=cache, rom=rom_path,
                        m68k_divider=divider, max_ticks=max_ticks)
    if out is not None and Path(out) != cache:
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(cache, out)
        return Path(out)
    return cache


def cmd_record(args) -> None:
    out = Path(args.out) if args.out else Path("out/compare") / f"{Path(args.script).stem}.original.jsonl"
    path = original_record(Path(args.script), args.probes, args.rom, args.divider, args.max_ticks, out,
                           use_cache=not args.no_cache)
    print(path)


def cmd_diff(args) -> None:
    import sys

    from . import probes as P
    from .diff import diff
    from .record import read

    res = diff(read(args.a), read(args.b), P.load_many(args.probes), context=args.context)
    print(res.report((Path(args.a).name, Path(args.b).name)))
    sys.exit(0 if res.ok else 1)


def cmd_assets(args) -> None:
    import hashlib

    from .assets import ASSETS_VERSION, catalogue, parse_pokes, trace, write_catalogue
    from .script import Script

    rom = Rom.load(args.rom)
    scripts = [Path(p) for p in args.scripts] or sorted(Path("compare/scripts").glob("tour_*.mwi"))
    traces = []
    for path in scripts:
        text = path.read_text()
        key = hashlib.sha1(f"{ASSETS_VERSION}\n{rom.sha1}\n{text}".encode()).hexdigest()[:16]
        cache = Path("out/assets") / f"{path.stem}.{key}.json"
        if cache.exists() and not args.no_cache:
            events = json.loads(cache.read_text())
        else:
            events = trace(Script.parse(text, path.stem), rom.path, pokes=parse_pokes(text))
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps(events))
        print(f"{path.stem}: {len(events)} loader calls", flush=True)
        traces.append(events)
    if args.trace_only:
        return
    cat = catalogue(traces, rom.data)
    out = Path(args.out)
    write_catalogue(cat, rom, out, [p.as_posix() for p in scripts])
    kinds: dict[str, int] = {}
    for e in cat["entries"].values():
        kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
    print(out, kinds, "frames", sum(len(v) for v in cat["frames"].values()),
          "sprite sources unexplained", cat["sprite_sources"]["unexplained"])


def gfx_hashes(rom: Rom, cat: dict) -> dict:
    import struct

    from . import palettes
    from .gfx import catalogue_hashes, digest

    builders = {}
    for name, args in palettes.builder_cases():
        words = palettes.run_case(rom.data, name, args)
        builders["/".join([name, *map(str, args)])] = digest(struct.pack(f">{len(words)}H", *words))
    return {"format": "mw-gfx-hashes/1", "rom_sha1": rom.sha1,
            "comment": "SHA-1 of decoded catalogue entries and palette builder results "
                       "(harness/mw_harness/gfx.py catalogue_hashes); hashes only, no ROM content",
            "entries": catalogue_hashes(rom.data, cat), "palette_builders": builders}


def cmd_gfx_hashes(args) -> None:
    rom = Rom.load(args.rom)
    cat = json.loads(Path(args.catalogue).read_text())
    Path(args.out).write_text(json.dumps(gfx_hashes(rom, cat), indent=1) + "\n")
    print(args.out)


def cmd_gfx_checkpoints(args) -> None:
    from . import gfxcheck

    rom = Rom.load(args.rom)
    cat = json.loads(Path(args.catalogue).read_text())
    path = Path(args.fixture)
    cps = json.loads(path.read_text())
    for cp in cps:
        if args.names and cp["name"] not in args.names:
            continue
        m = gfxcheck.measure(rom.data, cat, cp, (Path("compare/scripts") / f"{cp['script']}.mwi").read_text())
        print(f"{cp['name']:18s} shown {m['shown']:.3f} tiles {m['tiles']:.3f} placed {m['placed'][0]}/{m['placed'][1]}"
              f" sprites {m['sprites'][0]}/{m['sprites'][1]} cram mismatches {m['cram_mismatches']}", flush=True)
        if args.update:
            for k in gfxcheck.THRESHOLD_KEYS:
                cp.pop(k, None)
            cp.update(gfxcheck.thresholds(m))
    if args.update:
        path.write_text("[\n" + ",\n".join(" " + json.dumps(c) for c in cps) + "\n]\n")
        print(path)


def main() -> None:
    ap = argparse.ArgumentParser(prog="mw_harness")
    ap.add_argument("--rom", help="ROM path (default: rom/Mutant League Hockey (USA, Europe).md)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("info").set_defaults(fn=cmd_info)
    r = sub.add_parser("run")
    r.add_argument("-n", "--frames", type=int, required=True)
    r.add_argument("-i", "--input", help="input script file (see InputScript)")
    r.add_argument("--every", type=int, default=0, help="also dump every N frames")
    r.add_argument("-o", "--out", default="out/run")
    r.set_defaults(fn=cmd_run)
    w = sub.add_parser("watch")
    w.add_argument("-n", "--frames", type=int, required=True)
    w.add_argument("-i", "--input")
    w.add_argument("addrs", nargs="+", help="hex address[:size], e.g. FFB05E:1")
    w.set_defaults(fn=cmd_watch)
    fd = sub.add_parser("fades")
    fd.add_argument("-n", "--frames", type=int, required=True)
    fd.add_argument("-i", "--input")
    fd.set_defaults(fn=cmd_fades)
    t = sub.add_parser("trace")
    t.add_argument("-n", "--frames", type=int, required=True)
    t.add_argument("-p", "--probe", action="append", required=True, help="ADDR:LABEL[:EXPR,EXPR]")
    t.add_argument("-i", "--input")
    t.add_argument("--divider", type=int, default=7, help="68000 clock divider (7 = stock, lower = overclocked)")
    t.set_defaults(fn=cmd_trace)
    rc = sub.add_parser("record")
    rc.add_argument("script")
    rc.add_argument("--probes", default=DEFAULT_PROBES)
    rc.add_argument("-o", "--out")
    rc.add_argument("--max-ticks", type=int)
    rc.add_argument("--divider", type=int, default=7)
    rc.add_argument("--no-cache", action="store_true")
    rc.set_defaults(fn=cmd_record)
    df = sub.add_parser("diff")
    df.add_argument("a")
    df.add_argument("b")
    df.add_argument("--probes", default=DEFAULT_PROBES)
    df.add_argument("--context", type=int, default=3)
    df.set_defaults(fn=cmd_diff)
    a = sub.add_parser("assets")
    a.add_argument("scripts", nargs="*")
    a.add_argument("-o", "--out", default="game/data/rom_catalogue.json")
    a.add_argument("--no-cache", action="store_true")
    a.add_argument("--trace-only", action="store_true", help="only fill the trace cache")
    a.set_defaults(fn=cmd_assets)
    gh = sub.add_parser("gfx-hashes")
    gh.add_argument("--catalogue", default="game/data/rom_catalogue.json")
    gh.add_argument("-o", "--out", default="compare/fixtures/gfx_hashes.json")
    gh.set_defaults(fn=cmd_gfx_hashes)
    gc = sub.add_parser("gfx-checkpoints")
    gc.add_argument("names", nargs="*")
    gc.add_argument("--catalogue", default="game/data/rom_catalogue.json")
    gc.add_argument("--fixture", default="compare/fixtures/gfx_checkpoints.json")
    gc.add_argument("--update", action="store_true")
    gc.set_defaults(fn=cmd_gfx_checkpoints)
    mc = sub.add_parser("menu-cases")
    mc.add_argument("names", nargs="*")
    mc.add_argument("--update", action="store_true")
    mc.set_defaults(fn=lambda a: __import__("mw_harness.menu_cases", fromlist=["main"]).main(a.update, a.names))
    pv = sub.add_parser("playoff-vectors")
    pv.add_argument("names", nargs="*")
    pv.add_argument("--update", action="store_true")
    pv.set_defaults(fn=lambda a: __import__("mw_harness.playoff_vectors", fromlist=["main"]).main(a.update, a.names))
    tc = sub.add_parser("td-cases")
    tc.add_argument("names", nargs="*")
    tc.add_argument("--update", action="store_true")
    tc.set_defaults(fn=lambda a: __import__("mw_harness.td_cases", fromlist=["main"]).main(a.update, a.names))
    for cmd in ("rink-record", "rink-fixtures", "rink-dump"):
        rr = sub.add_parser(cmd)
        rr.add_argument("names", nargs="*")
        rr.add_argument("--every", type=int, default=1)
        rr.set_defaults(fn=lambda a, c=cmd: (setattr(a, "cmd", c),
                                             __import__("mw_harness.rink_fixtures", fromlist=["main"]).main(a)))
    sr = sub.add_parser("sim-record")
    sr.add_argument("names", nargs="*")
    sr.add_argument("--passes", type=int, default=None)
    sr.add_argument("--budget", type=float, default=None, help="seconds (default 165)")
    sr.add_argument("--out", default=None, help="folder (default out/sim)")
    sr.add_argument("--soak", type=int, default=None, help="record soak run SEED (plan 10)")
    sr.add_argument("--from-visit", type=int, default=1, help="--soak: the first rink visit recorded")
    sr.set_defaults(fn=lambda a: __import__("mw_harness.sim_record", fromlist=["main"]).main(a))
    sk = sub.add_parser("soak", help="seeded soak runs with code coverage (plan 10)")
    __import__("mw_harness.soak", fromlist=["add_arguments"]).add_arguments(sk)
    sk.set_defaults(fn=lambda a: __import__("mw_harness.soak", fromlist=["main"]).main(a))
    tt = sub.add_parser("title-timeline")
    tt.add_argument("--update", action="store_true")
    tt.set_defaults(fn=lambda a: __import__("mw_harness.title_timeline", fromlist=["main"]).main(a.update))
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
