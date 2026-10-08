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


## The pictures of the pad mode's backdrop (`$23316` at tile 1, `$4A066`
## at tile 246: separate VRAM).
func _banks() -> PackedStringArray:
	var out := PackedStringArray()
	for a in MwSpecialPlaysSim.pictures(rom, state.pad_mode):
		out.append("picture_%06x" % a)
	return out


## The sim's events: its sounds need nothing (the sim called the driver);
## the palette fades are the router's.
func _event(_ev: Array) -> void:
	pass
