extends SceneTree

## EG2 endpoint-disclosure fence (stage exit predicate component:
## WORLD_READY_WITHOUT_SERVER_ENDPOINT_DISCLOSURE).
##
## Layer 1 (STATIC): every gateway runtime source (plus the shared payload
## builders) is scanned for client-bindable endpoint literals — IP literals,
## localhost names, host/port pair shapes. The allowlist is intentionally
## EMPTY: worker config parsing lives in tools/network/*, outside the gateway
## runtime, and no runtime file needs endpoints.
##
## Layer 2 (RUNTIME): a real gateway node is started over loopback ports, a
## full AUTHENTICATE -> PLACE -> WORLD_READY exchange runs, and EVERY captured
## client-leg frame is scanned both for endpoint substrings and for
## endpoint-ish dictionary keys. Identifier projection (authority/server
## instance ids) MUST be present, so the scan cannot pass vacuously.

const AuthService = preload("res://scripts/network/gateway/runtime/eg2_auth_session_service.gd")
const WorldDirectory = preload("res://scripts/network/gateway/runtime/eg2_world_directory.gd")
const PlacementFlow = preload("res://scripts/network/gateway/runtime/eg2_placement_flow.gd")
const GatewayNode = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const FrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const RUNTIME_DIR := "res://scripts/network/gateway/runtime"
# Shared client-payload builders are fenced alongside the runtime even though
# they live one level up: they assemble every gateway-originated ack.
const EXTRA_FENCE_PATHS: Array[String] = [
	"res://scripts/network/gateway/gateway_contract_utils.gd",
	"res://scripts/network/gateway/client_world_frame.gd",
]
# Files allowed to contain endpoint literals INSIDE the fenced set. Empty by
# design: worker config parsing (the only legitimate consumer of bind hosts)
# lives in tools/network/* and is never scanned here.
const ENDPOINT_LITERAL_ALLOWLIST: Array[String] = []

const FORBIDDEN_SUBSTRINGS: Array[String] = [
	"127.0.0.1", "localhost", "0.0.0.0", "::1",
]
const IPV4_PATTERN := "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b"
const HOSTPORT_PATTERN := "\\b\\d{1,3}(\\.\\d{1,3}){3}:\\d{2,5}\\b"
const FORBIDDEN_KEYS: Array[String] = [
	"host", "hostname", "port", "endpoint", "address", "ip", "url", "bind",
]

var assertions := 0
var failures: Array[String] = []
var _captured_client_frames: Array = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg2-fence][FAIL] %s" % message)


## Returns true when the source text is CLEAN.
func _source_is_clean(source: String) -> bool:
	for needle in FORBIDDEN_SUBSTRINGS:
		if source.contains(needle):
			return false
	var ipv4 := RegEx.create_from_string(IPV4_PATTERN)
	if ipv4.search(source) != null:
		return false
	var hostport := RegEx.create_from_string(HOSTPORT_PATTERN)
	if hostport.search(source) != null:
		return false
	return true


## ---- layer 1: static --------------------------------------------------------


func _run_static_fence() -> void:
	# The scanner must catch a dirty sample: a clean-bill fence that cannot
	# fire is worthless.
	_assert(not _source_is_clean('var x := "127.0.0.1"'), "scanner missed a plain IPv4 literal")
	_assert(not _source_is_clean("connect_to(10.0.0.7:9200)"), "scanner missed a host:port pair")
	_assert(_source_is_clean("authority/eg2/main-a"), "scanner flagged a pure identifier")
	_assert(_source_is_clean("server-instance/eg2/main-a-1"), "scanner flagged a server instance id")

	var dir := DirAccess.open(RUNTIME_DIR)
	_assert(dir != null, "cannot open gateway runtime directory")
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		if ENDPOINT_LITERAL_ALLOWLIST.has(file_name):
			continue
		var source := FileAccess.get_file_as_string("%s/%s" % [RUNTIME_DIR, file_name])
		_assert(not source.is_empty(), "fence could not read %s" % file_name)
		_assert(_source_is_clean(source),
				"runtime file %s contains a client-bindable endpoint literal" % file_name)
	for path in EXTRA_FENCE_PATHS:
		var source := FileAccess.get_file_as_string(path)
		_assert(not source.is_empty(), "fence could not read %s" % path)
		_assert(_source_is_clean(source),
				"payload builder %s contains a client-bindable endpoint literal" % path.get_file())


## ---- layer 2: runtime over a started loopback node --------------------------

var _auth
var _directory
var _flow
var _gateway
var _port_client
var _wire_sequence := 0


func _send_session_control(client_session_id: String, ticket_id: String, schema: String, payload: Dictionary) -> void:
	_wire_sequence += 1
	var inner := ClientWorldFrameScript.create(
			"frame/eg2/fence/%d" % _wire_sequence,
			"gateway-session/eg2/fence-probe",
			"CLIENT_TO_WORLD", "SESSION_CONTROL", _wire_sequence, schema, payload)
	var wire: Dictionary = FrameScript.create(
			"frame/eg2/fence-wire/%d" % _wire_sequence,
			"transport-session/eg2/fence-client",
			_wire_sequence, "CONTROL", "RELIABLE_ORDERED",
			schema, inner)
	var injected: Dictionary = _port_client.inject_received_frame("peer/loopback/eg2-fence-client", wire)
	_assert(bool(injected.get("success", false)), "fence client injection failed")


var _consumed_acks := 0


func _take_ack(stage: String) -> Dictionary:
	var inbox: Array = _port_client.get_messages_for_peer("peer/loopback/eg2-fence-client")
	for index in range(_consumed_acks, inbox.size()):
		var inner: Dictionary = inbox[index].get("payload", {})
		if String(inner.get("channel", "")) == "SESSION_CONTROL":
			_captured_client_frames.append(inbox[index])
			_consumed_acks = index + 1
			return inner
	_assert(false, "no SESSION_CONTROL ack reached the fence client during %s" % stage)
	return {}


func _run_runtime_redaction() -> void:
	_auth = AuthService.new()
	_directory = WorldDirectory.new()
	_flow = PlacementFlow.new()
	_auth.configure({})
	_flow.configure(_auth, _directory)
	_directory.register_world("world/eg2/fence", "authority/eg2/fence-a", "server-instance/eg2/fence-a-1", 1)

	_port_client = LoopbackPort.new()
	var port_backend := LoopbackPort.new()
	_port_client.setup()
	port_backend.setup()
	_gateway = GatewayNode.new()
	var started: Dictionary = _gateway.start(
			{"transport": "LOOPBACK", "name": "eg2-fence-client"},
			{"transport": "LOOPBACK", "name": "eg2-fence-backend"},
			"gateway/eg2/fence",
			{"client_port": _port_client, "backend_port": port_backend, "backend_peer_id": "peer/loopback/eg2-fence-backend"})
	_assert(bool(started.get("success", false)), "fence gateway start failed: %s" % String(started.get("error_code", "")))
	if not bool(started.get("success", false)):
		return
	_gateway.set_placement_handler(_flow)
	var attached: Dictionary = _port_client.attach_peer(
			"peer/loopback/eg2-fence-client", "transport-session/eg2/fence-client", "route/eg2/fence-client", 1)
	_assert(bool(attached.get("success", false)), "fence client attach failed")

	var minted: Dictionary = _auth.mint_auth_ticket("client-session/eg2/fence-alpha")
	_assert(bool(minted.get("success", false)), "fence ticket mint failed")
	var ticket_id := String(minted["details"]["ticket_id"])
	_send_session_control("client-session/eg2/fence-alpha", ticket_id,
			GatewayUtils.EG2_SESSION_AUTHENTICATE_PAYLOAD_SCHEMA,
			{"client_session_id": "client-session/eg2/fence-alpha", "ticket_id": ticket_id})
	_pump("authenticate")
	var auth_ack := _take_ack("authenticate")
	_assert(String(auth_ack.get("payload", {}).get("ticket_status", "")) == "OK", "fence authenticate failed")

	_send_session_control("client-session/eg2/fence-alpha", ticket_id,
			GatewayUtils.EG2_SESSION_PLACE_REQUEST_PAYLOAD_SCHEMA,
			{"client_session_id": "client-session/eg2/fence-alpha", "ticket_id": ticket_id,
				"resume_token": "", "world_id": "world/eg2/fence"})
	_pump("place")
	var ready_ack := _take_ack("place")
	if not ready_ack.is_empty():
		_assert(String(ready_ack["payload"].get("route_role", "")) == "ACTIVE",
				"fence placement did not reach ACTIVE")
		_assert(String(ready_ack["payload"].get("authority_id", "")) == "authority/eg2/fence-a",
				"fence WORLD_READY lost the authority identifier")
		_assert(String(ready_ack["payload"].get("server_instance_id", "")) != "",
				"fence WORLD_READY lost the server instance identifier")

	# THE FENCE: every captured client-leg frame, substring- AND key-scanned.
	_assert(_captured_client_frames.size() >= 2,
			"fence capture suspiciously small: %d" % _captured_client_frames.size())
	var corpus := ""
	for frame_value in _captured_client_frames:
		var frame: Dictionary = frame_value
		corpus += JSON.stringify(frame)
		_scan_keys_recursive(frame.get("payload", {}))
	_assert(corpus.contains("server-instance/") and corpus.contains("authority/"),
			"fence corpus lacks the identifier projection it guards")
	for needle in FORBIDDEN_SUBSTRINGS:
		_assert(not corpus.contains(needle), "client leg leaked endpoint substring '%s'" % needle)
	# A hypothetical sim bind coordinate must appear NOWHERE on the client leg.
	_assert(not corpus.contains("9310"), "client leg leaked a port-shaped token")

	var stopped: Dictionary = _gateway.stop()
	_assert(bool(stopped.get("success", false)), "fence gateway stop failed")
	_captured_client_frames.clear()


func _pump(stage: String) -> void:
	var pumped: Dictionary = _gateway.pump()
	_assert(bool(pumped.get("success", false)), "gateway pump failed during %s" % stage)


func _scan_keys_recursive(value) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for raw_key in value.keys():
				var key := String(raw_key)
				_assert(not FORBIDDEN_KEYS.has(key), "forbidden endpoint-ish key '%s' on the client leg" % key)
				_scan_keys_recursive(value[raw_key])
		TYPE_ARRAY:
			for index in range(value.size()):
				_scan_keys_recursive(value[index])


## ---- main -------------------------------------------------------------------


func _init() -> void:
	_run_static_fence()
	_run_runtime_redaction()
	_finish()


func _finish() -> void:
	var ok := failures.is_empty()
	var summary := {
		"test": "eg2_endpoint_disclosure_fence_l1",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicate": "WORLD_READY_WITHOUT_SERVER_ENDPOINT_DISCLOSURE" if ok else "PREDICATE_NOT_DEMONSTRATED",
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if ok:
		print("[eg2-fence] FENCE PASS — WORLD_READY_WITHOUT_SERVER_ENDPOINT_DISCLOSURE (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg2-fence] FENCE FAIL")
		quit(1)
