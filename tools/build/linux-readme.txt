mightyweenie - Mutant League Hockey reimplementation (Godot 4.7.1)
Build @COMMIT@, Linux x86_64.

The game reads its graphics, text and sound data from your own copy of the
Mutant League Hockey (USA, Europe) ROM; none is included. Put the ROM file
(.gen, .md or .bin, unzipped) in this folder, next to mightyweenie.x86_64,
and start ./mightyweenie.x86_64. Elsewhere:
./mightyweenie.x86_64 -- --rom=/path/to/rom.gen

Controls (player 1 by default; Options > Controller Bindings rebinds any
button of any player to any key but F1-F12, gamepad button or stick)
  Move            arrow keys, or a gamepad's D-pad / left stick
  A / B / C       Z / X / C, or the gamepad's west / south / east buttons
  Start           Enter, or the gamepad's Start (in the port's own menus
                  the gamepad's south button selects too)
  Menu Back       Esc, or the gamepad's east button
  2D / 3D rink    V, or the gamepad's north button, any time in a match
  Players 2-4 have no default controls in this build: bind theirs in the
  options. The menus always answer to the arrow keys, Enter and Esc.

Main menu (after the title): START GAME / OPTIONS / CREDITS / QUIT GAME

Options
  Camera          the view every match starts in: 2D (the original's) or 3D
  Enhance audio   off: the original's sound, samples cutting each other off
  Display         windowed or full screen
  Settings are kept in ~/.local/share/mightyweenie/settings.cfg.

Debug views: F1-F8 pick the rink's views in a match (F1 2D, F8 the 3D
camera; the others are unfinished); a gamepad's Back button steps through
them.

Sound: libmw_audio.linux.*.so (the sound chips) must stay next to
mightyweenie.x86_64; without it the game runs silent. THIRD_PARTY_NOTICES.txt
lists the licences of the code inside it.

Alt+Enter is not bound (use Options > Display); the window can be resized
(whole multiples of 320 x 224 stay pixel-exact).
