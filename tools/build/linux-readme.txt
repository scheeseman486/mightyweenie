mightyweenie - Mutant League Hockey reimplementation (Godot 4.7.1)
Build @COMMIT@, Linux x86_64.

The game reads its graphics, text and sound data from your own copy of the
Mutant League Hockey (USA, Europe) ROM; none is included. Start
./mightyweenie.x86_64: the first time, a file dialog asks for your ROM file
(.gen, .md or .bin, unzipped) and the game keeps a copy of it in
~/.local/share/mightyweenie/. Or put the ROM file in this folder, next to
mightyweenie.x86_64, or start ./mightyweenie.x86_64 -- --rom=/path/to/rom.gen

The AppImage (mightyweenie-*-x86_64.AppImage) is this same build in one
file: make it executable (chmod +x) and start it; a ROM file goes next to
the AppImage, or pick it in the dialog as above.

Players: up to 12, each on a controller of their own - player n's is the
n-th gamepad, and the keyboard is player 1's. The controller selection
before a match picks who plays, on which team. Options > Controls >
Controller Bindings: a layout per player (STANDARD or GENESIS), then any
action rebound to any key but F1-F12, gamepad button or stick; an input two
actions of one screen share shows red.

Controls
  Move            arrow keys, or a gamepad's D-pad / left stick (with
                  Analog control the stick steers freely and sets the pace;
                  the bindings' STICK rows pick another stick)
  Play            Z / X / C, or the gamepad's west / south / east buttons:
                  the original's A (punch / dive / special play), B (pass /
                  let go / change player), C (shoot / slap shot / check)
  Pause           Enter, or the gamepad's Start
  Menus           arrow keys; Enter selects, Esc goes back. Gamepad
                  (STANDARD layout): A or Start selects, B goes back, a
                  screen's other choices on X, Y and RB in the order it
                  prints them (its A, B, C). GENESIS layout: the original's
                  buttons everywhere, Back on the gamepad's Back / Select
  Pause menu      (STANDARD) up / down to choose, Enter or A to pick, Esc,
                  B or Start to resume; FORFEIT asks first
  2D / 3D rink    V, or player 1's gamepad Y (north) button, any time in a
                  match (2D EXTENDED / 3D EXTENDED in an EXTENDED match)
  Replays         C plays, B held plays slowly, A held rewinds (FULL GAME:
                  hold A or C longer to go faster), Start leaves
  The menus always answer to the arrow keys, Enter and Esc.

Main menu (after the title): START GAME (exhibition, playoffs, online) /
CREATE-A-TEAM (teams of your own) / the teams' descriptions / OPTIONS /
REPLAYS (saved matches and the attract demos) / CREDITS / QUIT GAME

Options
  Visuals
    Camera        the view every match starts in: 2D (the original's), 3D,
                  2D EXTENDED or 3D EXTENDED (zoomed out to keep every
                  player's character and the puck in the picture); a match
                  keeps to its pair of views
    Display       windowed or full screen (Alt+Enter switches it any time)
    Aspect ratio  ORIGINAL (320 x 224) or WIDE
    ABACABB mode  the blood and oil painted on the 3D arena
    Detailed ice  the 3D ice's own marks and the skates' scratches
    Reflections   the 3D ice as a mirror
  Gameplay modifiers
    Enhance audio off: the original's sound, samples cutting each other off
    Replay length the instant replay: FULL GAME rewinds over the whole match;
                  ORIGINAL keeps the last play
    Replay blood  the arena's paint in the 3D replays (off by default)
    Tick rate     OVERCLOCKED (default): the rink runs 30 passes a second;
                  ORIGINAL: each pass as long as the Genesis took for it,
                  slowdowns included; APPROXIMATED: the same, worked out
                  alike on every machine (online, ORIGINAL plays as this)
    Character select  when the players pick characters: 5+ players, or 3+
                  on a team too
    Captain mode  when a playoff game is a captains' game: 5+ or 2+ players
    Line-up select    the line-ups before a match
    Extended penalties  EXTENDED matches: the referee sees offences anywhere
    Extended CPU  EXTENDED matches: the CPU's players collide everywhere, as
                  yours do
  Controls
    Analog control    on: a stick steers at any angle, sets the pace and
                  aims passes and shots; off: the original's 8 directions
    Shot height buttons  STANDARD layout: HIGH SHOT and LOW SHOT (the
                  triggers; A and Left Shift on the keyboard) pick a shot's
                  height instead of the D-pad
    Controller bindings  see Players above
  Settings are kept in ~/.local/share/mightyweenie/settings.cfg.

Online: START GAME, ONLINE MULTIPLAYER - one player hosts (UDP port 42032 by
default, a password if you like), the others join with the host's address.
Everyone needs this same build and the same ROM. The project's README
explains ports, firewalls and rejoining.

Debug views: F1-F8 pick the rink's views in a match (F1 2D, F8 the 3D
camera; the others are unfinished); a gamepad's Back button steps through
them. Not in online matches.

Sound: libmw_audio.linux.*.so (the sound chips) must stay next to
mightyweenie.x86_64; without it the game runs silent. THIRD_PARTY_NOTICES.txt
lists the licences of the code inside it.

Input glyphs: "Virtual key codes tileset" by YellowAfterlife (CC0) and
"Pixel Button Prompt" by FrankTheApe (free for commercial use; thanks!).

The window can be resized (whole multiples of 320 x 224 stay pixel-exact).
