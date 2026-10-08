# Known labels (text source of truth)

CSV files here are applied to a fresh Ghidra database by
`re/ghidra/mlh_import.py`. They hold facts gathered from outside sources and
from our own analysis. Columns: `address,size,name,comment,source`.

Naming convention: a provenance prefix marks unverified labels -
`ra_` RetroAchievements code notes, `gg_` decoded Game Genie / Action Replay
codes, `forum_` nhl94.com ROM-hacking threads. Drop the prefix once a label is
confirmed in the disassembly or with the reference harness, and note how in
`comment`.

* `hardware.csv` - Genesis memory-mapped I/O (fixed by the console).
* `ram.csv`      - 68k work RAM ($FF0000-$FFFFFF).
* `rom.csv`      - code/data locations in the cartridge.
