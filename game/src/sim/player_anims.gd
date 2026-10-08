class_name MwPlayerAnims
extends RefCounted
## Which animation a player plays (`$4ABE`): the player record's species
## (byte +7, low nibble) picks a list at `$1C48C`, the animation ID an entry
## in it. One animation is region dependent: `$49DD2` becomes `$49ACE` on
## consoles whose version register has bit 6 set (PAL/European) - we follow
## the NTSC console (docs/architecture.md, stock NTSC first).

const SPECIES := 0x1C48C


static func species(rom: PackedByteArray, player_record: int) -> int:
	return rom[player_record + 7] & 0x0F


## Address of animation [param id] for the player record.
static func anim(rom: PackedByteArray, player_record: int, id: int) -> int:
	var list := MwGfx.u32(rom, SPECIES + 4 * species(rom, player_record))
	return MwGfx.u32(rom, list + 4 * id)
