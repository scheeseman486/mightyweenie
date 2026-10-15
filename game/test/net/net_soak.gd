extends SceneTree
## The longer chaos runs (plan 35 section 7; not part of the GUT batches):
## the matrix of test_net_chaos with more seeds and longer matches (a 500
## ms outage every 6 s in the conditions that have outages), printing each
## run's report. Run from game/:
##   godot --headless -s res://test/net/net_soak.gd [-- --seeds N --ticks N]
## (out/plan35-wi2/gt.sh run -s res://test/net/net_soak.gd on the VM).

const Chaos := preload("res://test/net/net_chaos.gd")
const Matrix := preload("res://test/net/test_net_chaos.gd")


func _initialize() -> void:
	var seeds := 4
	var ticks := 1800
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		if args[i] == "--seeds":
			seeds = int(args[i + 1])
		elif args[i] == "--ticks":
			ticks = int(args[i + 1])
	var failed := 0
	for row in Matrix.MATRIX:
		var worst := 0
		var worst_steady := 0
		for seed_index in seeds:
			var cond: Dictionary = (row[1] as Dictionary).duplicate()
			if cond.has("outages"):
				var more: Array[Vector2i] = []
				for k in range(0, ticks * 16 - 2000, 6000):    # during the presses, not the drain
					more.append(Vector2i(k + 1500, k + 2000))
				cond["outages"] = more
			var r := Chaos.run(cond, 1000 + seed_index, ticks, 400)
			print("%-6s seed %d: %s" % [row[0], 1000 + seed_index, str(r)])
			if not r["ok"]:
				failed += 1
			else:
				worst = maxi(worst, int(r["max_stall_ms"]))
				worst_steady = maxi(worst_steady, int(r["max_steady_stall_ms"]))
		print("%-6s worst stall %d ms, after START %d ms (bound %d)" % [row[0], worst, worst_steady, row[2]])
	print("soak: %s" % ("all ok" if failed == 0 else "%d runs FAILED" % failed))
	quit(1 if failed else 0)
