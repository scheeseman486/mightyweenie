class_name MwNetIdentity
extends RefCounted
## The host's identity for encryption (plan 35 section 6): an RSA key and
## a self-signed certificate made at the first START SERVER
## ([method load_or_create]: [code]Crypto.generate_rsa(2048)[/code],
## [code]generate_self_signed_certificate[/code]) and kept in the player's
## data folder ([member dir]: host.key, host.crt) - never shipped, never
## committed; only the certificate is ever sent. The key file is made
## readable by its owner only where the system allows.
##
## A certificate's fingerprint is the SHA-256 of its DER bytes: what the
## handshake's proofs bind (MwNetProtocol.proof) and what clients remember
## for trust on first use ([MwNetKnownHosts]).

const KEY_FILE := "host.key"
const CERT_FILE := "host.crt"
const BITS := 2048
## The certificate's subject (and issuer: it signs itself). The common
## name is what pinned clients check (MwNetEnet.COMMON_NAME).
const SUBJECT := "CN=mightyweenie,O=mightyweenie,C=XX"
const NOT_BEFORE := "20200101000000"
const NOT_AFTER := "20991231235959"

## Where the key and certificate live (tests point it elsewhere).
static var dir := "user://net"

var key: CryptoKey
var cert: X509Certificate
var der := PackedByteArray()
var fingerprint := PackedByteArray()


## The host's identity: loaded from [member dir], or made and saved there
## the first time. Null when it can't be made or saved.
static func load_or_create() -> MwNetIdentity:
	var kp := dir.path_join(KEY_FILE)
	var cp := dir.path_join(CERT_FILE)
	if FileAccess.file_exists(kp) and FileAccess.file_exists(cp):
		var id := MwNetIdentity.new()
		id.key = CryptoKey.new()
		id.cert = X509Certificate.new()
		if id.key.load(kp) == OK and id.cert.load(cp) == OK and id._finish():
			return id
	var made := create()
	if made == null:
		return null
	# plan 45 (L3): the key never readable by anyone else, not even while it is written - its folder its
	# owner's alone, the file's permissions set on the fresh ".part" before the key goes in (the same text
	# CryptoKey.save writes; it used to be written with the default permissions and closed to others after)
	MwUserFile.private_folder(dir)
	if not MwUserFile.write_atomic(kp, made.key.save_to_string().to_utf8_buffer(), MwUserFile.PRIVATE) \
			or made.cert.save(cp) != OK:
		return null
	return made


## A new identity, not saved.
static func create() -> MwNetIdentity:
	var c := Crypto.new()
	var id := MwNetIdentity.new()
	id.key = c.generate_rsa(BITS)
	if id.key == null:
		return null
	id.cert = c.generate_self_signed_certificate(id.key, SUBJECT, NOT_BEFORE, NOT_AFTER)
	return id if id.cert != null and id._finish() else null


func _finish() -> bool:
	der = der_of(cert)
	fingerprint = fingerprint_of(der)
	return not der.is_empty()


## A certificate's DER bytes (from its PEM form, written to a scratch file:
## save_to_string's string carries a stray terminator the engine complains
## about).
static func der_of(c: X509Certificate) -> PackedByteArray:
	if c == null:
		return PackedByteArray()
	var tmp := OS.get_user_data_dir().path_join("mw_net_%s.crt" % MwNetProtocol.random_bytes(8).hex_encode())
	if c.save(tmp) != OK:
		return PackedByteArray()
	var pem := FileAccess.get_file_as_string(tmp)
	DirAccess.remove_absolute(tmp)
	return der_of_pem(pem)


## The DER bytes of the first certificate in [param pem] (empty: none).
static func der_of_pem(pem: String) -> PackedByteArray:
	var a := pem.find("-----BEGIN CERTIFICATE-----")
	var b := pem.find("-----END CERTIFICATE-----")
	if a < 0 or b < a:
		return PackedByteArray()
	var body := pem.substr(a + 27, b - a - 27).replace("\n", "").replace("\r", "").strip_edges()
	return Marshalls.base64_to_raw(body)


## A certificate from its DER bytes; null when they aren't one.
static func cert_from_der(bytes: PackedByteArray) -> X509Certificate:
	if bytes.size() < MwNetProtocol.MIN_CERT or bytes.size() > MwNetProtocol.MAX_CERT:
		return null
	var b64 := Marshalls.raw_to_base64(bytes)
	var lines := PackedStringArray()
	for i in range(0, b64.length(), 64):
		lines.append(b64.substr(i, 64))
	var pem := "-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n" % "\n".join(lines)
	var c := X509Certificate.new()
	return c if c.load_from_string(pem) == OK else null


## SHA-256 of [param bytes] (a certificate's DER).
static func fingerprint_of(bytes: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish()


## A fingerprint for people: its first 8 bytes in groups ("AB12 CD34 ...").
static func readable(fp: PackedByteArray) -> String:
	var hex := fp.slice(0, 8).hex_encode().to_upper()
	var parts := PackedStringArray()
	for i in range(0, hex.length(), 4):
		parts.append(hex.substr(i, 4))
	return " ".join(parts)
