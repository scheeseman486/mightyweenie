class_name MwNetKnownHosts
extends RefCounted
## Trust on first use (plan 35 section 6, for hosts without a password): a
## client remembers each host's certificate by address and port in the
## player's data folder ([member path]) after its first successful join,
## and its DTLS sessions are pinned to it from then on (MwNetEnet). If a
## host shows another certificate later, [method check] says CHANGED and
## the client asks before going on (THIS HOST'S KEY HAS CHANGED,
## [MwNetClient]). With a password the proofs bind the certificate anyway
## and a changed one is simply remembered once the host proved itself.
##
## The file holds public certificates only (DER in base64) and their
## fingerprints; nothing secret.

enum Check { NEW, SAME, CHANGED }

## Where the known hosts live (tests point it elsewhere).
static var path := "user://net/known_hosts.cfg"


## The section a host is filed under (hex of "address|port": any address
## form is safe as a section name).
static func _section(address: String, port: int) -> String:
	return ("%s|%d" % [address.strip_edges().to_lower(), port]).to_utf8_buffer().hex_encode()


## The known hosts' file (empty: none yet, damaged, or - plan 45 - not plain settings: MwUserFile.read_config).
static func _load() -> ConfigFile:
	var cfg := MwUserFile.read_config(path)
	return cfg if cfg != null else ConfigFile.new()


## The certificate (DER) remembered for a host; empty when none.
static func lookup(address: String, port: int) -> PackedByteArray:
	var v: Variant = _load().get_value(_section(address, port), "cert", "")
	if not v is String:
		return PackedByteArray()
	var der := Marshalls.base64_to_raw(v)
	return der if der.size() >= MwNetProtocol.MIN_CERT and der.size() <= MwNetProtocol.MAX_CERT \
			else PackedByteArray()


## How [param der] compares with what is remembered for the host.
static func check(address: String, port: int, der: PackedByteArray) -> Check:
	var known := lookup(address, port)
	if known.is_empty():
		return Check.NEW
	return Check.SAME if known == der else Check.CHANGED


## Remembers [param der] as the host's certificate.
static func remember(address: String, port: int, der: PackedByteArray) -> void:
	var cfg := _load()
	var text := _section(address, port)
	cfg.set_value(text, "address", "%s|%d" % [address, port])
	cfg.set_value(text, "cert", Marshalls.raw_to_base64(der))
	cfg.set_value(text, "fingerprint", MwNetIdentity.fingerprint_of(der).hex_encode())
	MwUserFile.write_config(cfg, path)


## Forgets the certificate remembered for the host at [param address] and [param port].
static func forget(address: String, port: int) -> void:
	var cfg := _load()
	var text := _section(address, port)
	if cfg.has_section(text):
		cfg.erase_section(text)
		MwUserFile.write_config(cfg, path)
