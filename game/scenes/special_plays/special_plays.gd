extends MwBetweenPlays
## Screen 10, the special plays with the manual's Reserves page (plan 11;
## [MwSpecialPlaysSim], docs/re/special-plays.md). What renders
## where:
## * plane B: the backdrop from the sim's "map" operations - the screen's
##   picture `$23316` in 28 rows, or (pad modes 0 / 2, team B without a
##   pad) in rows 0-14 with the line-up display `$4A066` in rows 15-23;
## * the window: every text (fonts `$447F4` and `$1F958`, the highlighted
##   item and the comment), the page areas' fills, the coach portrait's
##   frame (map `$23BE6`) and the speech frame - page A from row 0, page B
##   (a second pad) from row 13;
## * sprites ([MwScreenDraw]): the A / B / C buttons, the idle page's six
##   players, the substitution list's health bar, player figure (or a dead
##   one's, the Demon Net's, the box's bars), jersey number, coach portrait
##   and bubble tail;
## * palette: screen 10's (`screen_palette`, `$1BE16` on line 3 - the
##   target of the set-up's `fade_in_start`: the router's fade-in is it).
## The sim calls the sound driver itself ([MwSound]): the menus' tune
## (`$13C6E`), its fade at the exit, the sound effects and the coach's
## voices.


## Port only (plan 38): a custom coach with colours of his own wears them:
## page A's portrait (line 1, attr $20) on line 12, page B's (line 2, $40)
## on line 13, the screen's palette with those lines (RomPalette
## "coach_line"; plan 34's port lines).
func _coach_colours() -> void:
	palette.steps = MwCustomTeams.coach_lines(rom, palette.steps, palette.team_a, palette.team_b, [1, 2])
	var lines := {}
	for k in 2:
		if MwCustomTeams.has_coach_colours(rom, [palette.team_a, palette.team_b][k]):
			lines[1 + k] = MwRinkDraw.COACH_LINE + k
	drawer.portrait_lines = lines


## The pictures of the pad mode's backdrop (`$23316` at tile 1, `$4A066`
## at tile 246: separate VRAM).
func _banks() -> PackedStringArray:
	var out := PackedStringArray()
	for a in MwSpecialPlaysSim.pictures(rom, MwSpecialPlaysSim.layout_mode(state)):
		out.append("picture_%06x" % a)
	return out


## The A / B / C buttons under the plays (sprite pieces `$1F0AC`) as the
## glyphs of the verbs they stand for, in the STANDARD layout (plan 23).
func _sprite_ops(ops: Array) -> Array:
	if not MwPrompts.active():
		return ops
	var out := []
	for op in ops:
		var o: Array = op
		var k := -1
		if str(o[0]) == "piece":
			k = [0, 6, 12].find(int(o[1]) - MwSpecialPlaysSim.BUTTONS)
		if k < 0:
			out.append(o)
			continue
		var verbs := MwVerbs.verbs_of(MwVerbs.Context.SPECIAL_PLAYS, ["A", "B", "C"][k])
		var cells := MwGlyphs.live_cells(verbs[0]) if not verbs.is_empty() else PackedInt32Array()
		out.append(["glyph", o[1], o[2], o[3], o[4], o[5], cells] if not cells.is_empty() else o)
	return out


## The sim's events: its sounds need nothing (the sim called the driver);
## the palette fades are the router's.
func _event(_ev: Array) -> void:
	pass
