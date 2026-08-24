extends SceneTree

## EG1 client worker: a real game-client process. Connects to the gateway's
## client-facing ENET listener, performs the SESSION_CONTROL handshake
## (HELLO -> ATTACHED ack), streams the fixed scenario (3 canonical item
## commands + 1 movement intent), collects the world->client results,
## then DETACHes and reports what it observed.

const Support = preload("res://tools/network/eg1_process_support.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const OPTION_SPEC := {
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 60000},
	"user-data-dir": {"kind": "string", "default": ""},
}

const CLIENT_PEER_ID := "peer/enet/eg1-client-a"
const CLIENT_WIRE_SESSION := "transport-session/eg1/l2-client"
const EXPECTED_RESULTS := 4  # 3 item results + 1 movement snapshot reply

var _options: Dictionary = {}
var _boundary
var _started_ms: int = 0
var _finished := false
var _connected := false
var _hello_sent := false
var _attached := false
var _gateway_session_id := ""
var _detached_ack := false
var _next_wire_sequence: int = 1
var _results: Array = []
var _scenario_sent_up_to: int = 0
var _movement_sent := false
var _detach_sent := false


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_boundary = BoundaryScript.new()
	var configured: Dictionary = _boundary.configure(EnetPortScript.new(), 1048576, 128, 2097152)
	if not bool(configured.get("success", false)):
		_finish_failure(String(configured.get("error_code", "CONFIGURE_FAILED")), {})
		return
	var connected: Dictionary = _boundary.connect_client(
			Support.enet_endpoint(String(_options["host"]), int(_options["port"])),
			CLIENT_PEER_ID, CLIENT_WIRE_SESSION, "route/eg1/client-a", 1)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")), {})
		return
	_started_ms = Time.get_ticks_msec()
	Support.write_state(String(_options["result-file"]), "CONNECTING", {"port": int(_options["port"])})
	print("EG1_CLIENT_CONNECTING port=%d" % int(_options["port"]))


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(64)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "POLL_FAILED")), {})
		return false
	for event_value in polled.get("details", {}).get("events", []):
		_handle_event(Dictionary(event_value))
	_boundary.flush_outbound(64)
	if _drive():
		return false
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("CLIENT_TIMEOUT", {"results": _results.size(), "attached": _attached})
	return false


func _handle_event(event: Dictionary) -> void:
	match String(event.get("event_type", "")):
		"PEER_CONNECTED":
			_connected = true
			_boundary.mark_peer_handshaking(CLIENT_PEER_ID)
			_boundary.mark_peer_synchronizing(CLIENT_PEER_ID)
			_boundary.mark_peer_ready(CLIENT_PEER_ID)
		"MESSAGE_RECEIVED":
			_on_message(Dictionary(event.get("frame", {})))
		_:
			pass


func _on_message(frame: Dictionary) -> void:
	var inner: Dictionary = frame.get("payload", {})
	match String(inner.get("channel", "")):
		"SESSION_CONTROL":
			var payload: Dictionary = inner.get("payload", {})
			var state := String(payload.get("state", ""))
			if state == "ATTACHED":
				_attached = true
				_gateway_session_id = String(payload.get("gateway_session_id", ""))
			elif state == "DETACHED":
				_detached_ack = true
		"WORLD_OPERATION", "AUTHORITATIVE_SNAPSHOT":
			_results.append({
				"channel": String(inner.get("channel", "")),
				"payload": Dictionary(inner.get("payload", {})).duplicate(true),
			})
		_:
			pass


## Returns true when this worker finished its whole flow.
func _drive() -> bool:
	if not _connected or _finished:
		return false
	if not _attached:
		if not _hello_sent:
			_hello_sent = true
			_send_hello()
		return false
	# Stream the scenario once the session is attached.
	if _scenario_sent_up_to < Support.SCENARIO_ITEM_COMMANDS.size():
		_send_scenario_step(_scenario_sent_up_to)
		_scenario_sent_up_to += 1
		return false
	if _scenario_sent_up_to == Support.SCENARIO_ITEM_COMMANDS.size() and not _movement_sent:
		_movement_sent = true
		_send_movement()
		return false
	if _results.size() >= EXPECTED_RESULTS and not _detach_sent:
		_detach_sent = true
		_send_detach()
		return false
	if _detach_sent and _detached_ack:
		_finish_success()
		return true
	return false


func _send_hello() -> void:
	var inner: Dictionary = Support.ClientWorldFrameScript.create(
			"frame/eg1/p2p/hello/1",
			"gateway-session/eg1/probe/p2p",
			"CLIENT_TO_WORLD",
			"SESSION_CONTROL",
			1,
			GatewayUtils.EG1_SESSION_HELLO_PAYLOAD_SCHEMA,
			{
				"client_session_id": "client-session/eg1/l2-alpha",
				"logical_player_id": "player/eg1-l2",
				"player_entity_id": "entity/eg1-player-l2",
				"world_id": "world/main",
			})
	_send_inner(inner)


func _send_scenario_step(index: int) -> void:
	var step: Dictionary = Support.SCENARIO_ITEM_COMMANDS[index]
	var inner: Dictionary = Support.scenario_inner_frame(_gateway_session_id, step, index + 1)
	_send_inner(inner)


func _send_movement() -> void:
	var inner: Dictionary = Support.movement_inner_frame(_gateway_session_id, Support.MOVEMENT_INPUT_SEQ)
	_send_inner(inner)


func _send_detach() -> void:
	var inner: Dictionary = Support.ClientWorldFrameScript.create(
			"frame/eg1/p2p/detach/1",
			_gateway_session_id,
			"CLIENT_TO_WORLD",
			"SESSION_CONTROL",
			1,
			GatewayUtils.EG1_SESSION_DETACH_PAYLOAD_SCHEMA,
			{})
	_send_inner(inner)


func _send_inner(inner: Dictionary) -> void:
	var wire: Dictionary = Support.wire_frame_for_inner(
			inner, CLIENT_WIRE_SESSION,
			"frame/eg1/p2p/wire/%d" % _next_wire_sequence, _next_wire_sequence)
	_next_wire_sequence += 1
	var sent: Dictionary = _boundary.send_to_peer(CLIENT_PEER_ID, wire)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "SEND_FAILED")), {"inner_channel": String(inner["channel"])})


func _finish_success() -> void:
	_finished = true
	var received_ops: Array[String] = []
	for entry_value in _results:
		var payload: Dictionary = entry_value["payload"]
		if entry_value["channel"] == "WORLD_OPERATION":
			received_ops.append(String(payload.get("operation_id", "")))
	received_ops.sort()
	var expected_results_known := _results.size() == EXPECTED_RESULTS
	Support.write_json(String(_options["result-file"]), {
		"schema": "planet_simulator.eg1_client_report.v1",
		"state": "COMPLETE",
		"passed": expected_results_known and _detached_ack and not _gateway_session_id.is_empty(),
		"gateway_session_id": _gateway_session_id,
		"results_received": _results.size(),
		"received_operation_ids": received_ops,
		"detached_ack": _detached_ack,
		"user_data_dir": String(_options["user-data-dir"]),
		"process_id": OS.get_process_id(),
	})
	_boundary.stop()
	print("EG1_CLIENT_COMPLETE results=%d detached=%s" % [_results.size(), str(_detached_ack)])
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg1_client_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details,
		"results_received": _results.size(),
		"process_id": OS.get_process_id(),
	}
	if not String(_options.get("result-file", "")).is_empty():
		Support.write_json(String(_options["result-file"]), report)
	push_error("EG1 client worker failed: %s" % error_code)
	if _boundary != null:
		_boundary.stop()
	quit(1)
