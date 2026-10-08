# Reverse-engineering workspace

| Path | What |
|---|---|
| `labels/*.csv` | **Source of truth** for everything we know about the ROM (committed) |
| `ghidra/mlh_import.py` | Rebuilds the Ghidra DB from the ROM + `labels/` (~15 s) |
| `ghidra/sync.py` | `apply` CSV -> DB, `export` DB -> CSV |
| `ghidra/gh.py` | Read-only queries: `decompile`, `disasm`, `xrefs`, `funcs` |
| `ghidra/peek.py` | Disassemble a range Ghidra has not discovered (throwaway transaction) |
| `ghidra/callers.py` | Which screen handlers reach a function |
| `ghidra/strings_used.py` | Strings referenced by a function and its callees |
| `lindis.py` | Linear disassembly of a ROM range with capstone (no Ghidra, fast) |
| `ghidra/annotations_io.py` | CSV format and the apply/export logic |
| `ghidra/project/` | The Ghidra DB (gitignored, rebuildable) |
| `tests/` | `tools/bin/re-test` - CSV -> DB -> CSV round trip must be lossless |

## CSV files

* `hardware.csv`, `ram.csv`, `rom.csv`: data labels -
  `address,size,name,comment,source,verified`. RAM is written as `$FFxxxx`;
  the `$FFFFxxxx` mirror (absolute-short addressing) is labelled
  automatically.
* `functions.csv`: `address,name,comment,source,verified`; the comment
  becomes the plate comment.
* `comments.csv`: `address,kind,text` with kind `pre`/`post`/`eol`.

`source` = where the fact came from (a URL, "own RE (plan NN)", ...).
`verified` = how it was confirmed (e.g. `disasm $13F96`, `harness: ...`);
empty means unverified.

## Naming

* `snake_case` for functions and variables, `UPPER_CASE` for hardware
  registers, `PascalCase` only for the vector handlers the import creates.
* Unverified names from outside sources keep their prefix: `ra_`
  (RetroAchievements), `gg_` (decoded Game Genie / Action Replay), `forum_`
  (nhl94.com). Drop the prefix once confirmed and fill in `verified`.
* Name by role, not by guess at implementation (`tick_counter`, not
  `frame_count`, when it counts 60 Hz ticks).
* Unknowns stay Ghidra's defaults (`FUN_xxxxxx`, `DAT_xxxxxx`); don't commit
  placeholder names like `func1`.

## Workflow (Ghidra DB has a single writer)

* **Headless:** edit the CSVs and run `sync.py apply` (or `mlh_import.py
  --rebuild`), then commit the CSVs.
* **In the Ghidra GUI** (`tools/bin/ghidra`): open
  `re/ghidra/project/MLH.gpr`, annotate freely, close the project, then run
  `tools/bin/py re/ghidra/sync.py export` and commit the CSV diff. Don't run
  headless scripts while the GUI has the project open (the lock).
* After pulling CSV changes, `sync.py apply` (or a rebuild) brings the DB up
  to date.
