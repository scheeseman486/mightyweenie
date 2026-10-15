extends "res://test/net/net_test_base.gd"
## Plan 35 work item 7: a man in the middle on real sockets (ENet with DTLS
## on 127.0.0.1 and ::1, net_relay.gd): a relay at the address a client
## knows the host by, ending DTLS with its own key and passing the messages
## on, is flagged (THIS HOST'S KEY HAS CHANGED: trust on first use - plan
## 45: with a password too) and, with a password, refused once trusted
## anyway (WRONG PASSWORD: the client's proof names the relay's
## certificate); passing the host's own certificate on, it
## gets no answer at all (DTLS pinned to the host's key).

const Relay := preload("res://test/net/net_relay.gd")
const C := preload("res://src/net/net_client.gd")

var _host_id: MwNetIdentity
var _relay_id: MwNetIdentity


func before_all() -> void:
	super.before_all()
	_host_id = MwNetIdentity.create()
	_relay_id = MwNetIdentity.create()


## The engine logs the DTLS handshakes it refused (the client pinned to the
## host's key meeting the relay) and straggling packets after a close
## (MwNetEnet): expected.
func _handle_dtls_errors() -> void:
	for e in get_errors():
		if e.contains_text("TLS handshake") or e.contains_text("mbedtls"):
			e.handled = true


func after_each() -> void:
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end and not MwNetEnet._lingering.is_empty():
		MwNetEnet.service_lingering()
		OS.delay_msec(2)
	_handle_dtls_errors()


func _has_ipv6() -> bool:
	for a in IP.get_local_addresses():
		if a == "0:0:0:0:0:0:0:1" or a == "::1":
			return true
	return false


func _check(address: String, password: String, replace := true) -> Dictionary:
	_clear_files()
	var r := Relay.check(address, password, net_info(), _host_id, _relay_id, replace)
	_handle_dtls_errors()
	gut.p(r["text"])
	assert_true(r["joined"], "the first join, straight to the host")
	return r


func _with_password(address: String) -> void:
	var r := _check(address, "pw")
	assert_true(r["ok"], r["text"])
	assert_eq([r["state"], r["fail"], r["refusal"]], [C.State.DONE, C.Fail.REFUSED,
			MwNetProtocol.Refusal.WRONG_PASSWORD], "refused: the proof binds the relay's certificate")
	assert_has(r["host_refused"], MwNetProtocol.Refusal.WRONG_PASSWORD, "the host refused it")
	assert_gt(int(r["certs"]), 0, "the relay showed its own certificate")
	assert_eq(r["changed"], [_host_id.fingerprint, _relay_id.fingerprint],
			"plan 45 (M3): THIS HOST'S KEY HAS CHANGED asked with a password too")


func _without_password(address: String) -> void:
	var r := _check(address, "")
	assert_true(r["ok"], r["text"])
	assert_eq(r["state"], C.State.TRUST, "stopped to ask: THIS HOST'S KEY HAS CHANGED")
	assert_eq(r["changed"], [_host_id.fingerprint, _relay_id.fingerprint], "the old key and the relay's")


func test_relay_with_a_password_ipv4() -> void:
	_with_password("127.0.0.1")


func test_relay_without_a_password_ipv4() -> void:
	_without_password("127.0.0.1")


func test_relay_with_a_password_ipv6() -> void:
	if not _has_ipv6():
		pending("this machine has no IPv6 loopback")
		return
	_with_password("::1")


func test_relay_without_a_password_ipv6() -> void:
	if not _has_ipv6():
		pending("this machine has no IPv6 loopback")
		return
	_without_password("::1")


func test_relay_passing_the_host_certificate_on() -> void:
	for password in ["pw", ""]:
		var r := _check("127.0.0.1", password, false)
		assert_true(r["ok"], r["text"])
		assert_eq([r["state"], r["fail"]], [C.State.DONE, C.Fail.NO_ANSWER],
				"pinned to the host's key, DTLS with the relay never completes (password %s)" % str(password != ""))
