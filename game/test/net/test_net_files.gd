extends "res://test/net/net_test_base.gd"
## Plan 35 work item 2: what the net code keeps in the player's data folder
## - the host's key and self-signed certificate (MwNetIdentity: made once,
## loaded after), the known hosts for trust on first use
## (MwNetKnownHosts), the rejoin key (MwNetRejoin) - and that damaged files
## are read as nothing rather than trusted.

func test_identity_made_once_then_loaded() -> void:
	var created := MwNetIdentity.load_or_create()
	assert_not_null(created)
	if created == null:
		return
	assert_true(FileAccess.file_exists(MwNetIdentity.dir.path_join(MwNetIdentity.KEY_FILE)))
	assert_true(FileAccess.file_exists(MwNetIdentity.dir.path_join(MwNetIdentity.CERT_FILE)))
	assert_eq(created.fingerprint.size(), 32)
	assert_eq(created.fingerprint, MwNetIdentity.fingerprint_of(created.der))
	assert_true(created.der.size() >= MwNetProtocol.MIN_CERT and created.der.size() <= MwNetProtocol.MAX_CERT,
			"the certificate (%d bytes) fits one CERT message" % created.der.size())
	assert_true(MwNetProtocol.cert(created.der).size() <= MwNetProtocol.MAX_MESSAGE)
	var identity := MwNetIdentity.load_or_create()
	assert_eq(identity.fingerprint, created.fingerprint, "loaded, not made again")
	var round_trip := MwNetIdentity.cert_from_der(created.der)
	assert_not_null(round_trip)
	assert_eq(MwNetIdentity.der_of(round_trip), created.der, "DER <-> certificate")
	assert_null(MwNetIdentity.cert_from_der(fake_cert(1)), "random bytes aren't a certificate")
	for e in get_errors():
		e.handled = true     # the engine reports the bytes it couldn't parse
	assert_eq(MwNetIdentity.readable(created.fingerprint).length(), 19)
	var key_text := FileAccess.get_file_as_string(MwNetIdentity.dir.path_join(MwNetIdentity.KEY_FILE))
	assert_true("PRIVATE KEY" in key_text, "the key file holds the key (never sent)")
	assert_false("PRIVATE" in Marshalls.raw_to_base64(created.der), "the certificate doesn't")
	if OS.get_name() == "Linux":
		var perms := FileAccess.get_unix_permissions(MwNetIdentity.dir.path_join(MwNetIdentity.KEY_FILE))
		assert_eq(perms & 63, 0, "the key file is its owner's alone (no group or other bits)")


func test_damaged_identity_is_made_again() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MwNetIdentity.dir))
	var f := FileAccess.open(MwNetIdentity.dir.path_join(MwNetIdentity.KEY_FILE), FileAccess.WRITE)
	f.store_string("not a key")
	f.close()
	f = FileAccess.open(MwNetIdentity.dir.path_join(MwNetIdentity.CERT_FILE), FileAccess.WRITE)
	f.store_string("not a certificate")
	f.close()
	var id := MwNetIdentity.load_or_create()
	for e in get_errors():
		e.handled = true     # the engine reports the bad files it was given
	assert_not_null(id, "a new identity replaces damaged files")


func test_known_hosts() -> void:
	var a := fake_cert(1)
	var b := fake_cert(2)
	assert_eq(MwNetKnownHosts.check("192.168.1.5", 42032, a), MwNetKnownHosts.Check.NEW)
	MwNetKnownHosts.remember("192.168.1.5", 42032, a)
	assert_eq(MwNetKnownHosts.check("192.168.1.5", 42032, a), MwNetKnownHosts.Check.SAME)
	assert_eq(MwNetKnownHosts.check("192.168.1.5", 42032, b), MwNetKnownHosts.Check.CHANGED)
	assert_eq(MwNetKnownHosts.check("192.168.1.5", 42033, b), MwNetKnownHosts.Check.NEW, "by address and port")
	MwNetKnownHosts.remember("[fe80::1]", 42032, b)
	assert_eq(MwNetKnownHosts.lookup("[FE80::1]", 42032), b, "any address form, any case")
	assert_eq(MwNetKnownHosts.lookup("192.168.1.5", 42032), a)
	MwNetKnownHosts.forget("192.168.1.5", 42032)
	assert_eq(MwNetKnownHosts.lookup("192.168.1.5", 42032), PackedByteArray())
	var f := FileAccess.open(MwNetKnownHosts.path, FileAccess.WRITE)
	f.store_string("[garbage\n= = =\n")
	f.close()
	assert_eq(MwNetKnownHosts.lookup("[fe80::1]", 42032), PackedByteArray(), "a damaged file knows nothing")
	for e in get_errors():
		e.handled = true


func test_rejoin_key_file() -> void:
	assert_eq(MwNetRejoin.read(), {})
	var key := MwNetProtocol.random_bytes(32)
	MwNetRejoin.save("host.example", 42032, 99, key)
	assert_eq(MwNetRejoin.read(), {"address": "host.example", "port": 42032, "match": 99, "key": key})
	assert_eq(MwNetRejoin.key_for("HOST.example", 42032), key)
	assert_eq(MwNetRejoin.key_for("host.example", 42033), PackedByteArray(), "another host's: none")
	if OS.get_name() == "Linux":
		assert_eq(FileAccess.get_unix_permissions(MwNetRejoin.path) & 63, 0, "its owner's alone")
	MwNetRejoin.clear()
	assert_eq(MwNetRejoin.read(), {})
	var cfg := ConfigFile.new()
	cfg.set_value("rejoin", "address", "a")
	cfg.set_value("rejoin", "port", 1)
	cfg.set_value("rejoin", "match", 1)
	cfg.set_value("rejoin", "key", "zz" + "00".repeat(31))
	cfg.save(MwNetRejoin.path)
	assert_eq(MwNetRejoin.read(), {}, "not a key")
	cfg.set_value("rejoin", "key", "00".repeat(16))
	cfg.save(MwNetRejoin.path)
	assert_eq(MwNetRejoin.read(), {}, "too short")
