extends SceneTree

## EG2 client worker: a real game-client process over real ENET. Full EG2
## lifecycle against the gateway worker: CONNECT -> AUTHENTICATE (one-time
## ticket) -> PLACE_REQUEST (optionally with a resume token from a previous
## client process) -> WORLD_READY -> fixed scenario operations -> DETACH.
## Every received wire frame is recorded verbatim so the test orchestrator can
## run the endpoint-disclosure scan across the whole client leg.

const Support = preload("res://tools/network/eg2_process_support.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const GatewayUtils = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const OPTION_SPEC := {
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 60000},
	"user-data-dir": {"kind": "string", "default": ""},
	"auth-ticket": {"kind": "string", "default": "", "required": true},
	"resume-token": {"kind": "string", "default": ""},
	"phase": {"kind": "string", "default": "A"},
	"peer-id": {"kind": "string", "default": "peer/enet/eg2-client-a"},
	"wire-session": {"kind": "string", "default": "transport-session/eg2/l2-client-a"},
}

var _options: Dictionary = {}
var _boundary
var _started_ms: int = 0
var _finished := false
var _connected := false
var _authenticated := false
var _placed := false
var _world_ready: Dictionary = {}
var _detached_ack := false
var _next_wire_sequence: int = 1
var _results: Array = []
var _auth_sent := false
var _place_sent := false
var _scenario_sent_up_to: int = 0
var _movement_sent := false
var _detach_sent := false
var _frames_received: Array[String] = []
var _frames_sent: Array[String] = []


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
			String(_options["peer-id"]), String(_options["wire-session"]),
			"route/eg2/client-%s" % String(_options["phase"]).to_lower(), 1)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")), {})
		return
	_started_ms = Time.get_ticks_msec()
	print("EG2_CLIENT_CONNECTING port=%d phase=%s" % [int(_options["port"]), String(_options["phase"])])


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
		_finish_failure("CLIENT_TIMEOUT", {"results": _results.size(), "placed": _placed})
	return false


func _handle_event(event: Dictionary) -> void:
	match String(event.get("event_type", "")):
		"PEER_CONNECTED":
			_connected = true
			_boundary.mark_peer_handshaking(String(_options["peer-id"]))
			_boundary.mark_peer_synchronizing(String(_options["peer-id"]))
			_boundary.mark_peer_ready(String(_options["peer-id"]))
		"MESSAGE_RECEIVED":
			_on_message(Dictionary(event.get("frame", {})))
		_:
			pass


func _on_message(frame: Dictionary) -> void:
	_frames_received.append(JSON.stringify(frame))
	var inner: Dictionary = frame.get("payload", {})
	match String(inner.get("channel", "")):
		"SESSION_CONTROL":
			var payload: Dictionary = inner.get("payload", {})
			var schema := String(inner.get("payload_schema", ""))
			if schema == GatewayUtils.EG2_SESSION_AUTH_ACK_PAYLOAD_SCHEMA:
				if String(payload.get("ticket_status", "")) == "OK":
					_authenticated = true
				else:
					_finish_failure("AUTH_REJECTED", {"ticket_status": String(payload.get("ticket_status", ""))})
			elif schema == GatewayUtils.EG2_WORLD_READY_ACK_PAYLOAD_SCHEMA:
				_placed = true
				_world_ready = payload.duplicate(true)
			elif schema == GatewayUtils.EG2_PLACEMENT_DEGRADED_ACK_PAYLOAD_SCHEMA:
				_finish_failure("PLACEMENT_DEGRADED", {"status": String(payload.get("status", ""))})
			elif String(payload.get("state", "")) == "DETACHED":
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
	if not _authenticated:
		if not _auth_sent:
			_auth_sent = true
			_send_authenticate()
		return false
	if not _placed:
		if not _place_sent:
			_place_sent = true
			_send_place_request()
		return false
	var expected_results := Support.SCENARIO_A_ITEM_COMMANDS.size() + 1 \
			if String(_options["phase"]) == "A" \
			else Support.SCENARIO_B_ITEM_COMMANDS.size() + 1
	if _scenario_sent_up_to < _phase_item_commands().size():
		_send_scenario_step(_scenario_sent_up_to)
		_scenario_sent_up_to += 1
		return false
	if _scenario_sent_up_to == _phase_item_commands().size() and not _movement_sent:
		_movement_sent = true
		_send_movement()
		return false
	if _results.size() >= expected_results and not _detach_sent:
		_detach_sent = true
		_send_detach()
		return false
	if _detach_sent and _detached_ack:
		_finish_success()
		return true
	return false


func _phase_item_commands() -> Array:
	return Support.SCENARIO_A_ITEM_COMMANDS if String(_options["phase"]) == "A" \
			else Support.SCENARIO_B_ITEM_COMMANDS


func _send_inner(inner: Dictionary) -> void:
	_frames_sent.append(JSON.stringify(inner))
	var wire: Dictionary = Support.wire_frame_for_inner(
			inner, String(_options["wire-session"]),
			"frame/eg2/l2/wire/%d" % _next_wire_sequence, _next_wire_sequence)
	_next_wire_sequence += 1
	var sent: Dictionary = _boundary.send_to_peer(String(_options["peer-id"]), wire)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "SEND_FAILED")), {"inner_channel": String(inner["channel"])})


func _send_authenticate() -> void:
	_send_inner(Support.authenticate_inner(
			Support.CLIENT_SESSION_ID,
			String(_options["auth-ticket"])))


func _send_place_request() -> void:
	_send_inner(Support.place_request_inner(
			String(_options["auth-ticket"]),
			String(_options["resume-token"])))


func _send_scenario_step(index: int) -> void:
	var step: Dictionary = _phase_item_commands()[index]
	var inner: Dictionary = Support.scenario_inner_frame(
			String(_world_ready["gateway_session_id"]), step, index + 1)
	_send_inner(inner)


func _send_movement() -> void:
	var input_seq := Support.MOVEMENT_A_INPUT_SEQ if String(_options["phase"]) == "A" \
			else Support.MOVEMENT_B_INPUT_SEQ
	var inner: Dictionary = Support.ClientWorldFrameScript.create(
			"frame/eg2/l2/move/%d" % input_seq,
			String(_world_ready["gateway_session_id"]),
			"CLIENT_TO_WORLD",
			"INPUT_MOVEMENT",
			input_seq,
			"planet_simulator.test_input.v1",
			{"input_seq": input_seq, "axis_x": 0.0})
	_send_inner(inner)


func _send_detach() -> void:
	_send_inner(Support.detach_inner(String(_world_ready["gateway_session_id"])))


func _finish_success() -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg2_client_report.v1",
		"state": "COMPLETE",
		"passed": true,
		"phase": String(_options["phase"]),
		"world_ready": _world_ready,
		"logical_player_id": String(_world_ready.get("logical_player_id", "")),
		"player_entity_id": String(_world_ready.get("player_entity_id", "")),
		"resume_token_out": String(_world_ready.get("resume_token", "")),
		"gateway_session_id": String(_world_ready.get("gateway_session_id", "")),
		"results_received": _results.size(),
		"detached_ack": _detached_ack,
		"frames_received": _frames_received,
		"frames_sent": _frames_sent,
		"user_data_dir": String(_options["user-data-dir"]),
		"process_id": OS.get_process_id(),
	}
	Support.write_json(String(_options["result-file"]), report)
	_boundary.stop()
	print("EG2_CLIENT_COMPLETE phase=%s results=%d detached=%s" % [
		String(_options["phase"]), _results.size(), str(_detached_ack)])
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg2_client_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details,
		"results_received": _results.size(),
		"frames_received": _frames_received,
		"process_id": OS.get_process_id(),
	}
	if not String(_options.get("result-file", "")).is_empty():
		Support.write_json(String(_options["result-file"]), report)
	push_error("EG2 client worker failed: %s" % error_code)
	if _boundary != null:
		_boundary.stop()
	quit(1)
