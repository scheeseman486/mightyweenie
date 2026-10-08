# mightyweenie

A from-scratch reimplementation of **Mutant League Hockey** (Sega Genesis,
Electronic Arts / Abalone, 1994) in Godot 4.7.1, built by reverse engineering the
original in Ghidra using Opus 5.5

This is a spite project I did partially to prove a point. In total, it took about
three days to go from nothing but Ghidra, BlastEm/GPGX and the ROM to the state of
this project as initially published to Github.

Mightyweenie isn't a recompilation, but built with GDScript that matches the original
game's behaviour. Audio is handled through emulating FM synth using ymfm, PCM playback
and mixing is handled natively by Godot.

# New Features

* `3D rink view` - switchable at any moment during play, with exactly the same gameplay as
2D. The rink is a 3D model textured live from the supplied ROM. Alternate views are
available via F row keys, though they can cause some visual issues for the moment.
* `3D nets` - The standard net and the Battle Net pull colour data and some texture
information from the ROM too.
* `3D crowd` - Fans are cut from the ROM's crowd art and seated on 3D stands. Missing front
and back views, as well as mising pixel information, were drawn by hand and are merged on
top of the ROM's graphical assets.
* `Unlocked frame rate` - The 3D view renders at any frame rate and blends smoothly between
simulation steps. The game logic still runs at the original's rate.
* `True translucency` - In place of the Genesis shadow and highlight effects.
* `Keyboard and gamepad support` - Accessible using the new Options menu.

No ROM data shipped. All art, maps and data are read from your own ROM at runtime. Exported
builds look for it next to the executable or take a --rom= path.

For developers: you can browse the ROM's graphics in the Godot editor, and the simulation
is checked step by step against recordings of the original.

Targets Linux and Windows. Further ports are welcome.

Bring your own ROM (see `rom/README.md`).


## Building

```bash
tools/setup/fetch_tools.sh && tools/setup/setup_python.sh
tools/bin/setup-rom         # your ROM into the Godot project (game/rom/mlh.gen)
tools/bin/build-audio       # the audio extension (needs g++ and make)
tools/bin/godot-test        # Godot unit tests (GUT, headless)
tools/bin/harness-test      # reference-emulator tests (pytest)
tools/bin/godot-editor      # open the editor (desktop)
tools/bin/compare compare/scripts/coop_start.mwi   # original vs ours, first difference
tools/bin/export-linux      # packages in out/builds/ (also tools/bin/export-windows)
```

## Licences

The project's code is under the BSD 3-Clause License ([`LICENSE`](LICENSE)). It covers
this project's own code only; the game's data is not included. Vendored: GUT (MIT). The
audio extension's third-party code (ymfm, godot-cpp) is listed in
`game/addons/mw_audio/THIRD_PARTY_NOTICES.txt`. Tools fetched at setup keep their own
licences; emulators are used for observation only and are not linked into the game.

Mutant League Hockey is a trademark of its owners. This is an unofficial fan project, not
affiliated with or endorsed by Electronic Arts or Sega.
