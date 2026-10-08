class_name MwReplaySim
extends MwScreenSim
## Screen 7, the instant replay (plan 11; docs/re/replay.md): `$FBFA`
## reloads the rink's planes and palettes (`rink_load $F7F0`, `$215E`, line
## 3 faded in from `$1BD8A`), then `$9DD0` plays the replay ring
## ([MwInstantReplay]) from its oldest frame, frozen on it. One pad
## controls it: the first of pads 1-4 that newly pressed A in the pause
## menu (from the rink, D7 < 12) or C on a scoreboard (D7 >= 12), pad 1
## when none. Its loop `$9E64` runs once per tick: new A / held A rewinds,
## held B plays slowly, C plays at the recorded speed, Start leaves (the
## read offset and byte count put back, the crowd off, the 32-tick fade);
## the screen returns 6 when it came from the rink (D7 <= 6), else D7 (the
## scoreboard, which shows its menu again). No random number is drawn; the
## crowd loop (`$13E52`, level 50) runs from the first frame to the exit.
##
## What a drawn frame leaves in the rink state (the camera point's plane B
## and scroll buffers, the markers and plates) lasts after the screen:
## [MwInstantReplay.draw_frame].
##
## The locals (a6 = `$FFFFF4`): -$14 the controlling pad (2 * pad), -$12
## play (`st.b`), -$10 the pass's elapsed ticks, -$E the end of the frame at
## the read offset, -$C the wait, -$A the cursor, -8 / -6 the byte count /
## read offset saved at the start, -4 the tick of the last pass boundary
## ([member replay], [member last_tick], [member elapsed_ticks]).
##
## Draws: everything is drawn when a frame is drawn (at the set-up, then at
## most one frame per pass); a pass that draws none leaves the screen as it
## is (the sprite list stays uploaded). Per drawn frame, in the original's
## order:
## * [member plane_ops]: ["scroll", x, y] - plane B (the rink map that
##   [code]["rink"][/code], at the set-up, says is loaded: `$4BE6`, map
##   `$24D08` of picture `$24CFC`) shown at the frame's camera point (map
##   pixels; `$14CEE` / `$14CDE`);
## * [member sprite_ops]: the new sprite list (`$1568E` resets it): the
##   in-ice hazards the frame shows (kind != 0, `ice_hazard_draw $81AA`:
##   frame `$1C88E`[kind - 1] at the live slot's position, depth 1, attr 0),
##   then the frame's sprite records in recorded order, each as its
##   `draw_frame` pieces - ["piece", piece, x, y, attr, depth] in screen
##   pixels (as [method MwRinkDraw.phase_sprite] takes them; the list's
##   depth sort and clipping are `add_sprite_piece`'s);
## * [member window_ops]: the widget's texts "A_B_C" at (4, 4) and "{_|_}"
##   at (4, 5) (`$A04A`, font `$447F4`, attr `$E0`; static).
## At the set-up before the first frame: plane_ops ["rink"]; window_ops the
## window cleared (["fill", 0, 0, 40, 28, $8000]: rink_load's `$146D6`) and the
## widget's map (["map", `$49136`, 9, 9, 5, 2, 2], `$1C9EE`'s copy).
## Events: ["crowd", 50] (set-up), ["crowd_off"] and ["fade_out", 32] (exit).

const LOCALS := 0xFFFFF4             ## a6 of `$9DD0`'s frame
const CROWD := 50                    ## `$13E52`'s level
const WIDGET_MAP := 0x49136          ## the A/B/C widget's name-table words (attr in them)
const WIDGET_COPY := 0x1C9EE         ## its map_copy: row bytes, VRAM, dest stride, src stride, rows
const WINDOW_VRAM := 0xF000
## The window plane object's size (+8, +$A: what `$146D6` fills).
const WINDOW_CELLS := Vector2i(40, 28)
const ROW_BYTES := 0x80
const TEXT_FONT := 0x447F4
const TEXTS := [0x5062B, 0x50631]    ## `$A04A`: "A_B_C", "{_|_}"
const TEXT_AT := Vector2i(4, 4)      ## the first text's cell; the second one row lower
const TEXT_ATTR := 0xE0
const HAZARD_FRAMES := 0x1C88E       ## by kind - 1: frame.l, half width.w, half height.w
const HAZARD_DEPTH := 1
const SPRITE_ORIGIN := 0x80

## The playback ([MwInstantReplay]: the locals -$14..-6).
var replay: MwInstantReplay
## -4: the tick at the last pass boundary (`$9E70`).
var last_tick := 0
## -$10: the last pass's elapsed ticks (-1: not written yet - the set-up's
## calls leave whatever they left there).
var elapsed_ticks := -1
## The plate slots the drawn frames wrote (compared tile for tile).
var _plates_drawn := {}


func ported() -> bool:
	return true


## The checks compare [member sprite_ops] and [member window_ops] with the
## recorder's draw logs.
func logged_draws() -> bool:
	return true


## The pad the screen reads (the checks put a recorded press there).
func control_pad() -> int:
	return replay.pad if replay != null else 0


## The comparisons supply the replay ring's data (`$FF0000`, outside the
## RAM images) at the screen's entry.
func uses_ring() -> bool:
	return true


## `$FBFA` up to the loop: rink_load (window cleared, plane B the rink
## map), `$9DD0`'s set-up (the widget's map, read / used saved, the
## controlling pad, the oldest frame drawn, cursor 1, frozen, the crowd
## loop, the tick, the next frame's wait).
func enter(state: MwRinkState, screen_id: int, from_screen: int) -> void:
	super.enter(state, screen_id, from_screen)
	begin_pass()
	plane_ops.append(["rink"])
	window_ops.append(["fill", 0, 0, WINDOW_CELLS.x, WINDOW_CELLS.y, 0x8000])     # `$146D6`
	window_ops.append(widget_map(rom))
	_plates_drawn.clear()
	elapsed_ticks = -1
	replay = MwInstantReplay.new(s, rom)
	replay.start(MwInstantReplay.control_pad(from, s.pads_new))
	_frame_drawn()
	last_tick = MwScoreboardSim.setup_tick(self)
	crowd_level(CROWD)                                # `$9E5A`


## The widget's map as a window operation (`$1449C` with `$1C9EE`):
## ["map", map, stride (words), w, h, x, y].
static func widget_map(rom_: PackedByteArray) -> Array:
	var row_bytes := MwGfx.u16(rom_, WIDGET_COPY)
	var at := MwGfx.u16(rom_, WIDGET_COPY + 2) - WINDOW_VRAM
	return ["map", WIDGET_MAP, MwGfx.u16(rom_, WIDGET_COPY + 6) / 2, row_bytes / 2, MwGfx.u16(rom_, WIDGET_COPY + 8),
			(at % ROW_BYTES) / 2, at / ROW_BYTES]


## One pass of `$9E64` (one tick): the tick stored, the pads read, the
## controlling pad's word tested ([method MwInstantReplay.step]). Start:
## `$9F5E` (read / used restored, the crowd off), the fade out; returns 6
## from the rink (D7 <= 6) or D7.
func step(elapsed: int, held: Array, new: Array) -> int:
	var e := elapsed & 0xFFFF
	last_tick = MwScoreboardSim.tick_early(self)
	elapsed_ticks = e
	MwScoreboardSim.read_pads(s, held, new)
	var before := replay.drawn
	var left := replay.step(e, int(held[replay.pad]) & 0xFF, int(new[replay.pad]) & 0xFF)
	if replay.drawn != before:
		_frame_drawn()
	if not left:
		return -1
	crowd_off()                                       # `$9F72`
	fade_out(FADE_OUT)
	return 6 if (from & 0xFFFF) <= 6 else from


## The draws of the frame [member replay] just drew (see the class
## description): plane B's scroll, the sprite list, the widget's texts.
func _frame_drawn() -> void:
	var f: Dictionary = replay.shown
	var cam: Vector2i = f["camera"]
	plane_ops.append(["scroll", cam.x, cam.y])
	sprite_ops.clear()
	var hz: Array = f["hazards"]
	for i in hz.size():
		var kind: int = hz[i][0]
		if kind == 0:
			continue
		var h := s.hazards[i]
		var p := MwScoreboardSim.project(s, h.x, h.y, 0)
		_pieces(p.x - cam.x + SPRITE_ORIGIN, p.y - cam.y + SPRITE_ORIGIN, HAZARD_DEPTH, 0,
				MwGfx.u32(rom, HAZARD_FRAMES + 8 * (kind - 1)))
	for r in f["sprites"]:
		_pieces(int(r[0]), int(r[1]), int(r[2]), int(r[3]), int(r[4]))
	for i in TEXTS.size():
		window_ops.append(["text", TEXT_FONT, TEXT_AT.x, TEXT_AT.y + i, TEXT_ATTR, TEXTS[i]])
	for t in s.teams:
		_plates_drawn[t.markers[0].plate & 3] = true
		if t.flags4 & 4:
			_plates_drawn[t.markers[1].plate & 3] = true


## `draw_frame`'s piece loop (`$A0DC`) for [param frame] at the sprite
## point ([param x], [param y]): one "piece" operation per piece. (A frame
## in RAM - bank $FF - would be drawn from RAM; the rink records none.)
func _pieces(x: int, y: int, depth: int, attr: int, frame: int) -> void:
	if frame >= 0xFF0000 or frame + 2 > rom.size():
		push_warning("MwReplaySim: a sprite record's frame outside the ROM ($%06X)" % frame)
		return
	for i in MwGfx.u16(rom, frame):
		sprite_ops.append(["piece", frame + 2 + 6 * i, MwRinkSim.s16(x - SPRITE_ORIGIN), MwRinkSim.s16(y - SPRITE_ORIGIN),
				attr & 0xFF, depth & 0xFFFF])


# --- comparisons -------------------------------------------------------------------------------

## The locals, the ring object (`$FFC2BE`-`$FFC2D7`), plane B and its
## scroll buffers, both teams' markers, the plates (the slots the frames
## drew tile for tile), the live hazards.
func compare(ram: PackedByteArray, stack: PackedByteArray) -> Array:
	var d := MwScoreboardSim.Diff.new(MwScoreboardSim.Mem.new(ram, stack))
	var a6 := LOCALS
	d.word("pad -$14", a6 - 0x14, 2 * replay.pad)
	d.word("play -$12", a6 - 0x12, 0xFF00 if replay.play else 0)
	if elapsed_ticks >= 0:
		d.word("elapsed -$10", a6 - 0x10, elapsed_ticks)
	d.word("end -$E", a6 - 0xE, replay.frame_end)
	d.word("wait -$C", a6 - 0xC, replay.wait)
	d.word("cursor -$A", a6 - 0xA, replay.cursor)
	d.word("used -8", a6 - 8, replay.saved_used)
	d.word("read -6", a6 - 6, replay.saved_read)
	d.long("tick -4", a6 - 4, last_tick)
	compare_state(d, ram)
	return d.out


## What the screen leaves in the rink state (also after its exit): the
## ring object, plane B (+4 / +6 / +$10 / +$12) and the scroll buffers,
## the markers, the plates, the hazards.
func compare_state(d: MwScoreboardSim.Diff, ram: PackedByteArray) -> void:
	var ours := MwRinkRam.encode(s, ram)
	d.ram_range(ours, MwRinkRam.REPLAY, MwRinkRam.REPLAY + 0x1A)
	d.ram_range(ours, MwRinkRam.PLANE_B + 4, MwRinkRam.PLANE_B + 8)
	d.ram_range(ours, MwRinkRam.PLANE_B + 0x10, MwRinkRam.PLANE_B + 0x14)
	d.ram_range(ours, MwRinkRam.SCROLL_B, MwRinkRam.SCROLL_B + 2)
	d.ram_range(ours, MwRinkRam.SCROLL_B + 4, MwRinkRam.SCROLL_B + 6)
	for t in 2:
		var b: int = MwRinkRam.TEAMS[t]
		d.ram_range(ours, b + 0x346, b + 0x34E)
		d.ram_range(ours, b + 0x35A, b + 0x362)
	d.ram_range(ours, MwRinkRam.HAZARDS, MwRinkRam.HAZARDS + 40)
	for k in 4:
		var a := MwRinkRam.PLATES + 256 * k
		if not _plates_drawn.has(k):
			d.ram_range(ours, a, a + 256)
			continue
		var v: Array = s.plates[k]
		var tiles := MwPlate.tiles(rom, v[0], v[1], v[2])
		for i in 256:
			if tiles[i] != ram[a - MwRinkRam.BASE + i]:
				d.out.append(["plate %d +$%02X" % [k, i], "%02X" % tiles[i], "%02X" % ram[a - MwRinkRam.BASE + i]])
				break


## After the exit, against [param ram]: the next screen's entry record (a
## scoreboard) - everything [method compare_state] covers - or, with
## [param rink_next], the rink's first segment start after entry 6 (whose
## rink_load and first pass redo plane B, the scroll and the markers): the
## ring object, as it was at the screen's entry.
func compare_exit(ram: PackedByteArray, rink_next: bool) -> Array:
	var d := MwScoreboardSim.Diff.new(MwScoreboardSim.Mem.new(ram, PackedByteArray()))
	if rink_next:
		d.ram_range(MwRinkRam.encode(s, ram), MwRinkRam.REPLAY, MwRinkRam.REPLAY + 0x1A)
	else:
		compare_state(d, ram)
	return d.out
