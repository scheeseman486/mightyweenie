class_name MwScoreboardScreen
extends MwBetweenPlays
## Screens 12-17, the scoreboards (plan 11; [MwScoreboardSim],
## [MwMessageScoreboardSim]): plane B the scoreboard picture with the score
## panel, the window the menu or message panel's picture, the panel and the
## texts, the players / Zamboni / portrait / referee as sprites.


## The scoreboard's picture and the screen's panel picture (`$9034`: they
## share VRAM from tile 246 on, so the panel is the screen's).
func _banks() -> PackedStringArray:
	var out := PackedStringArray()
	for a in MwScoreboardBackdrop.pictures(rom, screen_id):
		out.append("picture_%06x" % a)
	return out
