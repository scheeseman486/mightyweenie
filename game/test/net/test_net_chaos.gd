extends "res://test/net/net_test_base.gd"
## Plan 35 work item 2, section 7: a host and three clients on the loopback
## at 0, 5, 20 and 40 % loss with delay (up to 250 ms), 30 ms jitter,
## duplicates, reordering and 500 ms outages (net_chaos.gd): every client
## rebuilds exactly the host's stream, every scripted press arrives (one a
## tick, none lost) and stalls stay bounded. The longer runs: net_soak.gd.

const Chaos := preload("res://test/net/net_chaos.gd")

## name, conditions, the stall bound (ms). A tick normally arrives within
## the delay plus a few ticks (every packet repeats the last 8); the bounds
## are set by what a 500 ms outage costs - the ticks it swallowed come back
## by a resend on the reliable channel, whose request and answer are each
## sent again a round trip later when lost (net_soak.gd's worst over longer
## runs: 117 ms at 5 %, 2.8 s at 20 %, 5.0 s at 40 %; the first ticks also
## wait for START itself).
const MATRIX := [
	["clean", {}, 100],
	["5 %", {"loss": 0.05, "delay": 40, "jitter": 30, "duplicate": 0.02, "reorder": 0.05}, 1000],
	["20 %", {"loss": 0.2, "delay": 120, "jitter": 30, "duplicate": 0.05, "reorder": 0.1,
			"outages": [Vector2i(2000, 2500)]}, 3500],
	["40 %", {"loss": 0.4, "delay": 250, "jitter": 30, "duplicate": 0.05, "reorder": 0.1,
			"outages": [Vector2i(1500, 2000), Vector2i(4000, 4500)]}, 7000],
]


func test_chaos_matrix() -> void:
	for row in MATRIX:
		var r := Chaos.run(row[1], 35, 360, 300)
		gut.p("%s: %s" % [row[0], str(r)])
		assert_true(r["ok"], "%s: %s" % [row[0], r["why"]])
		if r["ok"]:
			assert_lt(int(r["max_stall_ms"]), int(row[2]), "%s: stalls bounded" % row[0])
			assert_gt(int(r["presses"]), 50, "%s: the pattern pressed" % row[0])
