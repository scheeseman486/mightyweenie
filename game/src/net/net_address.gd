class_name MwNetAddress
extends RefCounted
## The addresses of the online pages (plan 35 section 2, "Holes filled"):
## what JOIN GAME's IP ADDRESS takes and what the host's COPY ADDRESS puts
## on the clipboard. Node-free, no network.
##
## The field takes [code]address[/code], [code]address:port[/code] or
## [code][v6]:port[/code] (JOIN GAME has no port field; 42032 by default):
##
## * an IPv4 dotted quad (four numbers 0-255);
## * an IPv6 address ([code]String.is_valid_ip_address[/code]), bare or in
##   brackets - brackets when a port follows; zone IDs ([code]%eth0[/code])
##   are refused: a link-local address only means something on one link;
## * a host name (owner: accepted and resolved): letters, digits, "-" and
##   ".", labels of 1-63 characters that neither start nor end with "-",
##   253 characters at most, not all digits and dots (that is a broken
##   IPv4 address, not a name).
##
## [method shareable] picks the host's addresses worth showing (no loopback,
## no link-local); [method join] writes one with its port the way the field
## reads it back.

enum Kind { IPV4, IPV6, NAME }

## A host name's limit (RFC 1035); with ":65535" the field's.
const MAX_NAME := 253
const MAX_LABEL := 63
const MAX_TEXT := MAX_NAME + 6


## [param text] read as an address: {host (lower case, no brackets), port,
## kind ([enum Kind]), port_given}; {} when it isn't one.
static func parse(text: String, default_port := MwNetProtocol.PORT) -> Dictionary:
	var trimmed := text.strip_edges()
	if trimmed == "" or trimmed.length() > MAX_TEXT or "%" in trimmed:
		return {}
	var host := trimmed
	var port := default_port
	var given := false
	if trimmed.begins_with("["):
		var close := trimmed.find("]")
		if close < 0:
			return {}
		host = trimmed.substr(1, close - 1)
		var rest := trimmed.substr(close + 1)
		if rest != "":
			if not rest.begins_with(":"):
				return {}
			port = port_of(rest.substr(1))
			given = true
		if not is_ipv6(host):
			return {}
		return {"host": host.to_lower(), "port": port, "kind": Kind.IPV6, "port_given": given} if port > 0 else {}
	if trimmed.count(":") > 1:
		# a bare IPv6 address: no port (it would be ambiguous without brackets)
		return {"host": trimmed.to_lower(), "port": port, "kind": Kind.IPV6, "port_given": false} if is_ipv6(trimmed) \
				else {}
	if trimmed.count(":") == 1:
		host = trimmed.get_slice(":", 0)
		port = port_of(trimmed.get_slice(":", 1))
		given = true
		if port <= 0:
			return {}
	if is_ipv4(host):
		return {"host": host, "port": port, "kind": Kind.IPV4, "port_given": given}
	if is_host_name(host):
		return {"host": host.to_lower(), "port": port, "kind": Kind.NAME, "port_given": given}
	return {}


## A port written as 1-5 digits, 1-65535; 0 when [param text] isn't one.
static func port_of(text: String) -> int:
	if text.length() < 1 or text.length() > 5 or not text.is_valid_int() or not _digits(text):
		return 0
	var p := text.to_int()
	return p if p >= 1 and p <= 65535 else 0


## A dotted quad of four numbers 0-255 (up to three digits each).
static func is_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	for text in parts:
		if text.length() < 1 or text.length() > 3 or not _digits(text) or text.to_int() > 255:
			return false
	return true


## An IPv6 address (no zone ID).
static func is_ipv6(text: String) -> bool:
	return ":" in text and not "%" in text and text.length() <= 45 and text.is_valid_ip_address()


## A host name as section 2 takes it.
static func is_host_name(text: String) -> bool:
	var name := text.trim_suffix(".")
	if name == "" or name.length() > MAX_NAME:
		return false
	var all_digits := true
	for label in name.split("."):
		if label.length() < 1 or label.length() > MAX_LABEL or label.begins_with("-") or label.ends_with("-"):
			return false
		for i in label.length():
			var c := label.unicode_at(i)
			var letter := (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)
			var digit := c >= 0x30 and c <= 0x39
			if not (letter or digit or c == 0x2D):
				return false
			if not digit:
				all_digits = false
	return not all_digits


## [param host] and [param port] written the way [method parse] reads them
## back: [code]1.2.3.4:42032[/code], [code][2001:db8::5]:42032[/code].
static func join(host: String, port: int) -> String:
	return ("[%s]:%d" if ":" in host else "%s:%d") % [host, port]


## The addresses worth giving to other players, from [param all] (the
## machine's, IP.get_local_addresses): no loopback, no link-local (they
## only reach this machine or this cable), no zone IDs; IPv4 first, then
## IPv6 written short ([method compact]); each once.
static func shareable(all: PackedStringArray) -> PackedStringArray:
	var v4 := PackedStringArray()
	var v6 := PackedStringArray()
	for a in all:
		var text := a.strip_edges().to_lower()
		if is_ipv4(text):
			if not (text.begins_with("127.") or text.begins_with("169.254.") or text == "0.0.0.0") and not text in v4:
				v4.append(text)
		elif is_ipv6(text):
			var c := compact(text)
			if c != "::1" and c != "::" and not _link_local(c) and not c.begins_with("::ffff:") and not c in v6:
				v6.append(c)
	v4.append_array(v6)
	return v4


## An IPv6 address in its short form (RFC 5952: lower case, no leading
## zeros, the longest run of two or more zero groups as "::").
static func compact(v6: String) -> String:
	var groups := expand(v6)
	if groups.is_empty():
		return v6.to_lower()
	var best := -1
	var best_len := 0
	var i := 0
	while i < 8:
		if groups[i] == 0:
			var j := i
			while j < 8 and groups[j] == 0:
				j += 1
			if j - i > best_len and j - i >= 2:
				best = i
				best_len = j - i
			i = j
		else:
			i += 1
	var parts := PackedStringArray()
	for k in 8:
		parts.append("%x" % groups[k])
	if best < 0:
		return ":".join(parts)
	var head := ":".join(parts.slice(0, best))
	var tail := ":".join(parts.slice(best + best_len))
	return head + "::" + tail


## An IPv6 address's eight groups (empty when it isn't one; an embedded
## IPv4 tail is read as its two groups).
static func expand(v6: String) -> PackedInt32Array:
	var text := v6.strip_edges().to_lower()
	if not is_ipv6(text):
		return PackedInt32Array()
	var tail_v4 := PackedInt32Array()
	var last := text.rfind(":")
	if "." in text.substr(last + 1):
		var quad := text.substr(last + 1).split(".")
		tail_v4 = PackedInt32Array([quad[0].to_int() * 256 + quad[1].to_int(),
				quad[2].to_int() * 256 + quad[3].to_int()])
		text = text.substr(0, last + 1) + "0"
	var halves := text.split("::")
	var head := halves[0].split(":", false) if halves[0] != "" else PackedStringArray()
	var tail := PackedStringArray()
	if halves.size() > 1 and halves[1] != "":
		tail = halves[1].split(":", false)
	var out := PackedInt32Array()
	for g in head:
		out.append(g.hex_to_int())
	var fill := 8 - head.size() - tail.size() - (0 if tail_v4.is_empty() else 1)
	for _i in maxi(0, fill):
		out.append(0)
	for g in tail:
		out.append(g.hex_to_int())
	if not tail_v4.is_empty():
		out.resize(out.size() - 1)
		out.append_array(tail_v4)
	return out if out.size() == 8 else PackedInt32Array()


## [param address] in at most [param cells] characters for a lobby row: an
## IPv6 address keeps its start and end around "..".
static func shorten(address: String, cells: int) -> String:
	if address.length() <= cells:
		return address
	var keep := cells - 2
	var head := (keep + 1) / 2
	return address.left(head) + ".." + address.right(keep - head)


static func _link_local(v6: String) -> bool:
	var g := expand(v6)
	return not g.is_empty() and (g[0] & 0xFFC0) == 0xFE80


static func _digits(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 0x30 or c > 0x39:
			return false
	return true
