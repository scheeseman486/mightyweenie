class_name MwNetUpnp
extends RefCounted
## The router's port opened for a host (plan 35 section 2, owner: UPnP,
## tried automatically at START SERVER): Godot's [UPNP] finds the gateway,
## maps the UDP port to this machine and asks for the public address - the
## one other players on the internet join. It never blocks the menus (the
## discovery waits up to 2 s for the gateway's answer): the work runs on a
## thread and [method poll] takes its result. A failure is shown (OPEN PORT
## 42032 ON YOUR ROUTER), never fatal: players on the same network, or a
## port opened by hand, still join.
##
## [method close] (CLOSE LOBBY, the host leaving) removes the mapping, on a
## thread again; a closed object finishes in the background, serviced by
## [method service] (the Router autoload, every tick) until its threads are
## done.

enum State { IDLE, TRYING, OPEN, FAILED }

## How long the discovery waits for gateways (ms).
const DISCOVER_MS := 2000
const DESCRIPTION := "mightyweenie"

## Closed objects whose threads are still running.
static var _closing: Array[MwNetUpnp] = []

## Makes the UPnP object (tests put a stand-in with the same methods:
## discover, get_gateway, add_port_mapping, delete_port_mapping,
## query_external_address).
var factory: Callable = func() -> Object: return UPNP.new()
var state := State.IDLE
var port := 0
## The public address the gateway reports ("" none).
var external := ""
## Why it failed ("" when it didn't).
var error := ""
var _upnp: Object = null
var _thread: Thread = null
var _mapped := false
var _closed := false


## Tries to map [param p] (UDP) on the gateway, on a thread.
func open(p: int) -> void:
	if state == State.TRYING or _closed:
		return
	port = p
	state = State.TRYING
	external = ""
	error = ""
	_upnp = factory.call()
	_thread = Thread.new()
	_thread.start(_work.bind(_upnp, p))


## Takes the thread's result when it is done; true when the state changed.
func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	var r: Dictionary = _thread.wait_to_finish()
	_thread = null
	if _closed:
		_mapped = bool(r.get("mapped", false)) or _mapped
		return false
	_mapped = bool(r.get("mapped", false))
	external = str(r.get("external", ""))
	error = str(r.get("error", ""))
	state = State.OPEN if _mapped else State.FAILED
	return true


## The mapping goes (on a thread; the object finishes in the background).
func close() -> void:
	if _closed:
		return
	_closed = true
	state = State.IDLE
	if not _closing.has(self):
		_closing.append(self)
	_step_closing()


## Services every closed object: joins finished threads, removes a mapping
## once the thread that made it is done.
static func service() -> void:
	for u in _closing.duplicate():
		u._step_closing()


## Waits for every background thread (the game quitting).
static func finish_all() -> void:
	for u in _closing.duplicate():
		if u._thread != null:
			u._thread.wait_to_finish()
			u._thread = null
		_closing.erase(u)


func _step_closing() -> void:
	if _thread != null:
		if _thread.is_alive():
			return
		var r: Variant = _thread.wait_to_finish()
		_thread = null
		if r is Dictionary and bool((r as Dictionary).get("mapped", false)):
			_mapped = true
	if _mapped:
		_mapped = false
		_thread = Thread.new()
		_thread.start(_unmap.bind(_upnp, port))
		return
	_closing.erase(self)


## The thread's work: discover, map, ask the public address.
static func _work(u: Object, p: int) -> Dictionary:
	var r: int = u.call("discover", DISCOVER_MS, 2, "InternetGatewayDevice")
	if r != UPNP.UPNP_RESULT_SUCCESS:
		return {"mapped": false, "error": "NO ROUTER ANSWERED"}
	var gateway: Object = u.call("get_gateway")
	if gateway == null or not bool(gateway.call("is_valid_gateway")):
		return {"mapped": false, "error": "NO ROUTER ANSWERED"}
	r = u.call("add_port_mapping", p, p, DESCRIPTION, "UDP", 0)
	if r != UPNP.UPNP_RESULT_SUCCESS:
		return {"mapped": false, "error": "THE ROUTER SAID NO"}
	var address := str(u.call("query_external_address"))
	return {"mapped": true, "external": address if address.is_valid_ip_address() else "", "error": ""}


static func _unmap(u: Object, p: int) -> Dictionary:
	u.call("delete_port_mapping", p, "UDP")
	return {}
