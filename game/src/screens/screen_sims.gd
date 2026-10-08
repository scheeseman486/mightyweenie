class_name MwScreenSims
extends RefCounted
## The node-free screens between plays (plan 11) by screen id - the scenes
## and the checks make them here.


## A new [MwScreenSim] for [param screen], or null when the screen has none.
static func make(screen: int, rom: PackedByteArray) -> MwScreenSim:
	match screen:
		7:
			return MwReplaySim.new(rom)
		8:
			return MwStatsSim.new(rom)
		10:
			return MwSpecialPlaysSim.new(rom)
		12, 13, 14, 15, 16:
			return MwScoreboardSim.new(rom)
		17:
			return MwMessageScoreboardSim.new(rom)
		18:
			return MwFightSim.new(rom)
		19:
			return MwRefereeSim.new(rom)
	return null
