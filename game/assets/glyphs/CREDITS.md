# Input glyphs (third-party art)

The port's own art for showing the inputs a player has bound (the original
prints the Genesis pad's letters from the ROM). Not ROM data. Where both
sheets have a glyph, the virtual key codes tileset is used (owner,
2026-10-08): keyboard and mouse come from it, the gamepad from Pixel Button
Prompt.

Colours: neither sheet's own colours are shown. Each sheet colour is a role
(label, body, edge) that the game maps at load time to palette indices of
the screen it is drawn on, like the menu fonts' (owner), so the glyphs take
the screen's colours and fade with it:
keys a black keycap (white label, grey edge), gamepad buttons a dark grey
body with a white label (plan 23).

## Virtual key codes tileset - YellowAfterlife

* Source: https://opengameart.org/content/virtual-key-codes-tileset
  (retrieved 2026-10-08; the author's files `vk.png`, `vk-glyphs-only.png`)
* Licence: CC0 1.0 (public domain dedication).
* `vk.png`: 385 x 145, 16 x 16 tiles of 23 x 8 at offset 1, spacing 1, in
  the order of the Windows virtual key codes; keys narrower than a tile are
  centred in it. Colours: label white, body dark, edge black, plus
  half-transparent corner and shadow pixels. `vk-glyphs-only.png`: the
  labels alone (croppable to 21 x 5).
* The first codes (the mouse buttons, Cancel, Backspace, Tab) sit one or
  two tiles early in the author's sheet (a comment on the page posts a
  corrected one); the lookup (MwGlyphs.VK_EARLY) corrects it.

## Pixel Button Prompt - FrankTheApe

* Source: https://franktheape.itch.io/pixel-button-prompt
  (retrieved 2026-10-08; `PixelButtonPrompt.png`,
  `PixelButtonPromptAnimation.png`)
* Terms, as the author states them on the page (no separate licence file):
  "These assets can be used in commercial projects, and edited. Credit is
  appreciated."
* 208 x 64, 8 x 8 tiles: keyboard letters, digits, F1-F9, arrows and
  special keys; mouse buttons; gamepad A B X Y, the PlayStation symbols,
  L1 L2 R1 R2, START, D-pad and stick directions. The animation sheet is the
  same layout pressed (one pixel lower). Colours: label white, body dark
  grey.
