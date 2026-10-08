extends MwBetweenPlays
## Screen 19, the referee cutscene after Waste the Ref (plan 11;
## [MwRefereeSim]): plane B the scoreboard picture with the score panel,
## the window the message panel's picture; as sprites through the side
## view the penalty boxes' occupants, the referee and both teams' players,
## who go on being simulated until the referee is down. No pad is read.


## The scoreboard's picture and the message panel's (VRAM 1-245, 246-273).
func _banks() -> PackedStringArray:
	var out := PackedStringArray()
	for a in MwScoreboardBackdrop.pictures(rom, screen_id):
		out.append("picture_%06x" % a)
	return out


## Run on its own: the demo match lined up for a faceoff in phase 12 with
## the referee on the ice as `$10182` leaves him ((165, 0), 5 hits, attr
## `$A0`), played by team A.
func _demo_state() -> MwRinkState:
	var s := super._demo_state()
	var rink := MwRinkSim.new(rom, s)
	MwRinkPhases.new(MwRinkUpdate.new(rink)).enter(5)
	s.phase = 12
	s.teams[0].flags5 |= 1
	s.ref_flag = 5
	s.ref_attr = 0xA0
	s.referee.motion.init(0xA5, 0, 0)
	s.referee.anim = MwAnimState.from_record(rom, MwRefereeSim.REF_STANDS)
	return s
