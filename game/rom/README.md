# game/rom/

The project's copy of the user's ROM: `mlh.gen` (put there by
`tools/bin/setup-rom`). Everything here except this README is gitignored and
the export plugin (`addons/mw_rom`) keeps it out of exported builds.

The editor imports it as a `RomArchive` (metadata only: path, size, SHA-1);
game and tool code read it through `MwRom` (`src/rom/rom.gd`). The `.gen`
extension is used because the project contains Markdown `.md` files.
