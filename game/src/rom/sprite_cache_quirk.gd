class_name MwSpriteCacheQuirk
extends RefCounted
## The original's sprite tile cache bug, faked (plan 11; docs/re/graphics.md,
## Sprite tile cache). `sprite_cache` (`$150CE`) gives each sprite piece a
## VRAM slot keyed by the piece's first ROM tile only and, on a hit, hands
## back the slot without looking at its size. A piece that starts on the
## same tile as a smaller piece cached before it gets the smaller slot: its
## first tiles are right, the rest show whatever VRAM holds after the slot
## (other sprites' tiles, which vary with what was loaded before).
##
## Of every animation frame in the ROM, four first tiles are shared by
## pieces of different sizes. In three of them the smaller piece always
## comes first, so the bigger one is always broken:
## * the Zamboni rider's whip (screen 14, `$4CEB2`): frame 1's 4x2 piece at
##   `$DF29` after frame 0's 2x2: its right half;
## * a talking portrait (`$3E110`, the penalty scoreboard's walking player):
##   a frame's 4x1 bottom row at `$89AF` after the previous frame's 1x1
##   corner: three of its four tiles;
## * species 0 / 1 skaters falling through the ice (animation 34, `$43D2E`,
##   facing variants 4 and 5): frame 2's 4x3 piece at `$9EDD` after frame
##   0's 1x1: eleven of its twelve tiles.
## (The fourth, the fight's `$55AC`, is harmless: the 4x4 stand pose is
## always cached before the punch's 1x1.)
##
## Faked cheaply: the extra tiles come from a table of ROM tile words, the
## tiles the original showed there in a recorded visit (whip: GPGX, two
## visits out of five; portrait: one visit, its second tile no ROM tile -
## left empty); the fall, never recorded, takes the tiles uploaded after
## the 1x1 in its own frames. The sprites are built from these at run time
## like any other piece ([MwSpriteLayer], [MwSprites3D]).

## Vector2i(first tile, size byte) -> [tiles the slot holds, the ROM tile
## words shown from there on (0: nothing)].
const PIECES := {
	Vector2i(0xDF29, 0xD): [4, [0xDBA3, 0xDBA4, 0xDBA5, 0xDBA6]],
	Vector2i(0x89AF, 0xC): [1, [0, 0x8927, 0x8928]],
	Vector2i(0x9EDD, 0xE): [1, [0x9F0E, 0x9F0F, 0x9EAD, 0x9EAE, 0x9EAF, 0x9EB0, 0x9EB1, 0x9EB2, 0x9EB3, 0x9EB4, 0x9EB5]],
}


## The ROM tile word the [param n]-th tile (column-major) of the piece
## starting at ROM tile [param first] with size byte [param size] shows: its
## own (first + n) unless the cache bug replaces it; 0 for none.
static func tile(first: int, size: int, n: int) -> int:
	var q: Variant = PIECES.get(Vector2i(first, size & 0xF))
	if q == null:
		return first + n
	var cached: int = q[0]
	if n < cached:
		return first + n
	var extra: Array = q[1]
	return int(extra[n - cached]) if n - cached < extra.size() else 0
