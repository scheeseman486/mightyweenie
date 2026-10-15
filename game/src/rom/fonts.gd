class_name MwFonts
extends RefCounted
## The original's fonts (docs/re/menus.md, Drawing: +0 height, +2 the space's
## width, +4 the character map's offset, +6 the glyph count, +8 the glyphs,
## 6 bytes each). Plan 40 (D8): their addresses have one owner; a screen's
## own name for one (the original's use) is an alias of these.

const LIGHT := 0x447F4     ## the light menu font: menus, texts, clocks, numbers
const DARK := 0x1F958      ## the dark menu font: speeches, a highlighted item, the frame glyphs
const HEADING := 0x22BEC   ## headings, the stats' team names, jersey numbers
const TITLE := 0x22EE0     ## titles, the speeches' names, the character cards
const BIG := 0x246FA       ## sprite letters (24 px a letter, space 8)
