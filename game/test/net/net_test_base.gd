extends "res://test/rom/rom_test_base.gd"
## Shared by the net tests (plan 35 work item 2): the player-data files the
## net code writes (known hosts, the rejoin key, the host's identity) go to
## a test folder of their own, emptied around every test; and [World], a
## loopback network with a host and clients that runs on a virtual clock.
## Plan 40 (the survey's B4): the ROM tests' base under it - [member rom],
## [method need_rom] -, and [method rom_or_skip] for the scripts whose every
## test plays a game (pending, not failing, without the ROM).
## Short names: c the MwNetClient under test.

var _saved := {}
var _dir := ""


## For a whole script that needs the ROM: its should_skip_script returns
## this (GUT: a string skips the script with that reason).
static func rom_or_skip() -> Variant:
	return false if MwRom.available() else "ROM not installed (tools/bin/setup-rom)"


func before_all() -> void:
	super.before_all()
	_saved = {"known": MwNetKnownHosts.path, "rejoin": MwNetRejoin.path, "identity": MwNetIdentity.dir}
	_dir = "user://test_net"
	MwNetKnownHosts.path = _dir.path_join("known_hosts.cfg")
	MwNetRejoin.path = _dir.path_join("rejoin.cfg")
	MwNetIdentity.dir = _dir.path_join("identity")


func after_all() -> void:
	_clear_files()
	MwNetKnownHosts.path = _saved["known"]
	MwNetRejoin.path = _saved["rejoin"]
	MwNetIdentity.dir = _saved["identity"]


func before_each() -> void:
	_clear_files()


func _clear_files() -> void:
	for p in [MwNetKnownHosts.path, MwNetRejoin.path, MwNetIdentity.dir.path_join(MwNetIdentity.KEY_FILE),
			MwNetIdentity.dir.path_join(MwNetIdentity.CERT_FILE)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## What both sides of a test claim to be.
static func net_info() -> Dictionary:
	return World.net_info()


## Stand-in certificate bytes for the loopback (which only hashes them).
static func fake_cert(seed_value: int) -> PackedByteArray:
	return World.fake_cert(seed_value)


## A loopback network with a host at [constant HOST_ADDRESS] and clients.
class World:
	const HOST_ADDRESS := "10.0.0.1"

	static func net_info() -> Dictionary:
		var rom := PackedByteArray()
		rom.resize(MwNetProtocol.SHA1_BYTES)
		rom.fill(0x11)
		return {"build": "test build", "rom": rom, "schema": MwNetInput.schema()}

	static func fake_cert(seed_value: int) -> PackedByteArray:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var b := PackedByteArray()
		for i in 300:
			b.append(rng.randi_range(0, 255))
		return b
	var net: MwNetLoopback
	var host: MwNetHost
	var der: PackedByteArray
	var clients: Array[MwNetClient] = []

	func _init(seed_value := 1, password := "", conditions := {}, host_der := PackedByteArray()) -> void:
		net = MwNetLoopback.new(seed_value)
		net.set_conditions(conditions)
		der = host_der if not host_der.is_empty() else fake_cert(seed_value)
		host = MwNetHost.new(net.listen(HOST_ADDRESS, MwNetIdentity.fingerprint_of(der)), der, password,
				net_info())
		host.open()

	## A client at [param from] (default "10.0.1.<n>"; not connected yet:
	## [method join]).
	func make_client(info := {}, from := "") -> MwNetClient:
		var c := MwNetClient.new()
		if from == "":
			from = "10.0.1.%d" % (clients.size() + 1)
		var loopback := net
		c.connector = func(a: String, _p: int, pinned: PackedByteArray) -> MwNetTransport:
			return loopback.connect_to(a, from, MwNetIdentity.fingerprint_of(pinned) if not pinned.is_empty()
					else PackedByteArray())
		c.info = info if not info.is_empty() else net_info()
		clients.append(c)
		return c

	## A new client joining with [param password] and [param locals].
	func join(password := "", locals := 1, info := {}, from := "") -> MwNetClient:
		var c := make_client(info, from)
		c.connect_to(HOST_ADDRESS, MwNetProtocol.PORT, password, locals)
		return c

	## Polls everything for [param ms] in steps of [param step_ms].
	func run(ms: int, step_ms := 10) -> void:
		var end := net.now_ms + ms
		while net.now_ms < end:
			net.advance(step_ms)
			poll()

	func poll() -> void:
		host.poll(net.now_ms)
		for c in clients:
			c.poll(net.now_ms)

	## Runs until [param done] is true (or [param limit_ms]); true if it was.
	func run_until(done: Callable, limit_ms := 20000, step_ms := 10) -> bool:
		var end := net.now_ms + limit_ms
		while net.now_ms < end:
			if done.call():
				return true
			net.advance(step_ms)
			poll()
		return done.call()
