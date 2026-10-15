class_name MwSoundIds
extends RefCounted
## The menus' and screens' sound ids (`sound_play` `$13CEE`; docs/re/sound.md,
## Sound ids). Plan 40 (D8): one owner; a screen's own name for one (the
## original's use) is an alias of these.

## a five-track piece: the crowd under the password screen, the team description, the fight card
const CROWD := 0x10
const THUD := 0x15       ## a slam's thud, a landing
const CHANT := 0x1B      ## the matchup's chant (a PCM voice; the organ pool's floor hit)
const MOVE := 0x25       ## a row moved, a value changed, a button accepted
const REFUSED := 0x2E    ## refused (the password screen's; the special play's poot)
const KEY := 0x30        ## a key typed, a team saved
