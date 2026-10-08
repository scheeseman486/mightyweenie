class_name MwPortrait
extends Node2D
## A player's portrait with its border (`$B51E`-`$B6D2`; docs/re/menus.md,
## Portraits): star players have their own (`$1CC2C`), the others one per
## species (`$1CC68`). Portrait data: [talking animation, expression
## animation, voice sound, (frame, sound) list up to $FFFF]. Talking: after a
## pause the mouth alternates between frame 0 and a random frame every 8
## ticks while the voice plays, twice, then pauses 480 ticks. Expression:
## plays once, with a sound on listed frames.

const STARS := 0x1CC2C          ## 6 x (player record, portrait data, word)
const BY_SPECIES := 0x1CC68     ## by species: (portrait data, word), 6 bytes
const DEFAULT := 0x1CC20        ## no player: this portrait data
const BORDERS := 0x1CDEE        ## border frame by size - 1
const COACHES := 0x1CD26        ## 20 x (coach record, portrait data, word)
const COACH_DEFAULT := 0x1CCA2  ## a coach not listed: this portrait data
const START_DELAY := -40
const PAUSE := -480
const MOUTH_TICKS := 8

var rom: PackedByteArray
var data := 0          ## +$C
var size := 0          ## +$16
var which := 0         ## +$12: 0 talking, 1 expression
var timer := 0         ## +$14
var voices := 0        ## +$1C
var voice := 0         ## +$18 sound handle
var attr := 0          ## draw attr (palette line of the panel)
## The main random stream (talking frames, `$4BD6`).
var rng: MlhRng

var face := RomSprite.new()
var border := RomSprite.new()


func _init() -> void:
	face.tick_driven = true
	border.tick_driven = true
	add_child(border)
	add_child(face)
	visible = false


func set_palette(p: RomPalette) -> void:
	face.palette = p
	border.palette = p


## `$B670`: the star portrait entry of a player record, 0 if none.
static func star_entry(rom_: PackedByteArray, record: int) -> int:
	for i in 6:
		var e := STARS + 10 * i
		if MwGfx.u32(rom_, e) == record:
			return e
	return 0


## `$B690`: the portrait data of a player record (0: none).
static func data_for(rom_: PackedByteArray, record: int) -> int:
	if record == 0:
		return DEFAULT
	var e := star_entry(rom_, record)
	if e != 0:
		return MwGfx.u32(rom_, e + 4)
	return MwGfx.u32(rom_, BY_SPECIES + 6 * (rom_[record + 7] & 0x0F))


## `$B6D2`: the portrait data of a coach record (team record +$C).
static func coach_data(rom_: PackedByteArray, coach: int) -> int:
	for i in 20:
		var e := COACHES + 10 * i
		if MwGfx.u32(rom_, e) == coach:
			return MwGfx.u32(rom_, e + 4)
	return COACH_DEFAULT


## `$B51E`: the portrait of [param record] at border size [param size_], stopped.
func set_player(rom_: PackedByteArray, record: int, size_: int) -> void:
	set_data(rom_, data_for(rom_, record), size_)
	voice = 0


## The portrait [param data_] at border size [param size_] (0: none).
func set_data(rom_: PackedByteArray, data_: int, size_: int) -> void:
	rom = rom_
	size = size_
	data = data_
	if size > 0:
		border.frame_addresses = PackedInt32Array([MwGfx.u32(rom, BORDERS + 4 * (size - 1))])
		border.attr_xor = attr | 0x60
	border.visible = size > 0
	face.attr_xor = attr


## `$B542`: start the talking (0) or expression (1, also for 2-3) animation.
func start(variant: int) -> void:
	which = 1 if variant >= 2 else variant
	face.anim = "%x" % MwGfx.u32(rom, data + 4 * which)
	face.rebuild()
	face.restart()
	timer = START_DELAY
	voices = 2


## `$B572`: [param elapsed] ticks. Pulling a face: a frame change plays
## the sound listed for the frame left (`$B5A6`; the list's frames are
## compared with the old frame, sign-extended). Talking: the voice polled
## (`$B5C4`) and restarted (`$B5EE`).
func advance(elapsed: int) -> void:
	var st := face.state
	if st == null:
		return
	if which != 0:
		var old := st.frame
		face.advance(elapsed)
		if st.frame != old:
			var f := old - 0x100 if old >= 0x80 else old   # ext.w
			var a := data + 10
			while true:
				var listed := MwGfx.u16(rom, a)
				if (f & 0xFFFF) < listed:
					break
				if (f & 0xFFFF) == listed:
					MwSound.play(MwGfx.u16(rom, a + 2))
					break
				a += 4
		return
	if not st.playing():
		return
	var d := elapsed + timer
	if d < 0:
		timer = d
		return
	d -= MOUTH_TICKS
	var f := 0
	if not MwSound.busy(voice):
		if voices == 0:
			d = PAUSE
			voices = 2
			_set_frame(0)
			timer = d
			return
		voices -= 1
		voice = MwSound.play(MwGfx.u16(rom, data + 8))
	if st.frame == 0 and rng:
		f = rng.range_value(0, MwGfx.u8(rom, st_record() + 3) - 1)
	_set_frame(f)
	timer = d


## The face animation's record address.
func st_record() -> int:
	return face.anim.hex_to_int()


func _set_frame(f: int) -> void:
	face.state.frame = f
	face.refresh()


## `$B656`: stop (its voice too, `$B660`).
func stop() -> void:
	hide_now()
	MwSound.stop(voice)
	voice = 0


## Stopped and hidden without a sound call (the main menu's panel reset
## `$13072`: the original leaves the portrait object and its voice alone).
func hide_now() -> void:
	if face.state:
		face.state.flags &= ~MwAnimState.PLAYING
	visible = false


## `$B61C`: border at (x + 1, y + 3 - size), face at (x, y) - screen pixels.
func place(at: Vector2) -> void:
	position = at
	border.position = Vector2(1, 3 - size)
	visible = true
