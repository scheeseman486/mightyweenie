extends SceneTree
## Plan 35 work item 7: the man-in-the-middle check on real sockets for
## tools/bin/net-soak (net_relay.gd's check: a host, a relay with its own key
## at the address the client knows, the client - ENet with DTLS, every
## endpoint in this process), with a password, without one, and with the
## host's own certificate passed on. Prints a line each and RESULT.
##
##   godot --headless -s res://test/net/mitm_check.gd -- [--address 127.0.0.1|::1] [--dir DIR]

const Relay := preload("res://test/net/net_relay.gd")


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var address := "127.0.0.1"
	var dir := OS.get_user_data_dir().path_join("mitm_check")
	for i in a.size() - 1:
		if a[i] == "--address":
			address = a[i + 1]
		elif a[i] == "--dir":
			dir = a[i + 1]
	DirAccess.make_dir_recursive_absolute(dir)
	MwNetKnownHosts.path = dir.path_join("known_hosts.cfg")
	MwNetRejoin.path = dir.path_join("rejoin.cfg")
	var host_id := MwNetIdentity.create()
	var relay_id := MwNetIdentity.create()
	var info := MwNetHost.local_info()
	var ok := true
	for c in [["pw", true], ["", true], ["pw", false]]:
		if FileAccess.file_exists(MwNetKnownHosts.path):
			DirAccess.remove_absolute(MwNetKnownHosts.path)
		var t0 := Time.get_ticks_msec()
		var r := Relay.check(address, c[0], info, host_id, relay_id, c[1])
		print("mitm %s: %s - %s (%d ms)" % [address, "ok" if r["ok"] else "FAILED", r["text"],
				Time.get_ticks_msec() - t0])
		ok = ok and bool(r["ok"])
	print("mitm %s RESULT %s" % [address, "ok" if ok else "failed"])
	quit(0 if ok else 1)
