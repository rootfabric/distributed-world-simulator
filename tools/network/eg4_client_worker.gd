extends SceneTree

## EG4 client worker: a real game-client process connected ONLY to the gateway.
## Lifecycle: CONNECT -> AUTHENTICATE -> PLACE_REQUEST -> WORLD_READY ->
## demand(subscribe, worlds) -> wave 1 (operations + movements) while counting
## EVERY received frame per channel -> PARK until the hold-release marker ->
## wave 2 (more movements: gameplay MUST continue even if the projection
## source died in between) -> demand(withdraw) -> DETACH -> report.
##
## The report is the graphical-style assertion surface: per-channel frame
## counts with timestamps (projections seen BEFORE the source died, snapshots
## seen AFTER it), exact operation-receipt accounting (an injected write from
## the projection source must NEVER appear as an extra receipt), and the
## single-connection fact (one transport peer for the whole run).

const Support = preload("res://tools/network/eg4_process_support.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const EnetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")

const OPTION_SPEC := {
	"host": {"kind": "string", "default": "127.0.0.1"},
	"port": {"kind": "int", "default": 0, "required": true},
	"result-file": {"kind": "string", "default": "", "required": true},
	"timeout-ms": {"kind": "int", "default": 90000},
	"user-data-dir": {"kind": "string", "default": ""},
	"auth-ticket": {"kind": "string", "default": "", "required": true},
	"client-session-id": {"kind": "string", "default": "", "required": true},
	"peer-id": {"kind": "string", "default": "peer/enet/eg4-client"},
	"wire-session": {"kind": "string", "default": "transport-session/eg4/l2-client"},
	"ops-per-wave": {"kind": "int", "default": 2},
	"movements-per-wave": {"kind": "int", "default": 2},
	"movement-seq-base": {"kind": "int", "default": 100},
	"demand-worlds": {"kind": "string", "default": ""},
	"hold-release-marker-file": {"kind": "string", "default": ""},
}

var _options: Dictionary = {}
var _boundary
var _started_ms: int = 0
var _finished := false
var _connected := false
var _authenticated := false
var _placed := false
var _world_ready: Dictionary = {}
var _demand_sent := false
var _demand_withdrawn := false
var _withdraw_ack := false
var _detached_ack := false
var _detach_sent := false
var _next_wire_sequence: int = 1
var _op_queue: Array = []
var _movement_seq: int = 0
var _movements_sent_this_wave: int = 0
var _wave: int = 1
var _awaiting_hold := false
var _ops_expected: int = 0
var _receipts: Array = []
var _frames: Array = []
# channel -> count
var _channel_counts: Dictionary = {}
var _first_projection_at_ms: int = -1
var _last_projection_at_ms: int = -1
var _first_snapshot_at_ms: int = -1
var _last_snapshot_at_ms: int = -1
var _heartbeat_at_ms: int = 0


func _initialize() -> void:
	var parsed: Dictionary = Support.parse_options(OS.get_cmdline_user_args(), OPTION_SPEC)
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_movement_seq = int(_options["movement-seq-base"])
	_ops_expected = int(_options["ops-per-wave"])
	_boundary = BoundaryScript.new()
	var configured: Dictionary = _boundary.configure(EnetPortScript.new(), 1048576, 128, 2097152)
	if not bool(configured.get("success", false)):
		_finish_failure(String(configured.get("error_code", "CONFIGURE_FAILED")), {})
		return
	var connected: Dictionary = _boundary.connect_client(
			Support.enet_endpoint(String(_options["host"]), int(_options["port"])),
			String(_options["peer-id"]), String(_options["wire-session"]),
			"route/eg4/l2-client", 1)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")), {})
		return
	_started_ms = int(Time.get_unix_time_from_system() * 1000.0)
	print("EG4_CLIENT_CONNECTING port=%d" % int(_options["port"]))


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(64)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "POLL_FAILED")), {})
		return false
	for event_value in polled.get("details", {}).get("events", []):
		_handle_event(Dictionary(event_value))
	_drive()
	_boundary.flush_outbound(64)
	_heartbeat()
	if int(Time.get_unix_time_from_system() * 1000.0) - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("CLIENT_TIMEOUT", {"receipts": _receipts.size(), "placed": _placed})
	return false


func _heartbeat() -> void:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	if now - _heartbeat_at_ms < 500:
		return
	_heartbeat_at_ms = now
	Support.write_json(String(_options["result-file"]) + ".heartbeat.json", {
		"schema": "planet_simulator.eg4_client_heartbeat.v1",
		"connected": _connected, "placed": _placed, "wave": _wave,
		"receipts": _receipts.size(), "channel_counts": _channel_counts.duplicate(true),
		"projections": int(_channel_counts.get("WORLD_PROJECTION", 0)),
		"awaiting_hold": _awaiting_hold, "demand_withdrawn": _demand_withdrawn,
	})


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
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	_frames.append({"at": now, "frame": JSON.stringify(frame)})
	var inner: Dictionary = frame.get("payload", {})
	var channel := String(inner.get("channel", ""))
	_channel_counts[channel] = int(_channel_counts.get(channel, 0)) + 1
	match channel:
		"WORLD_OPERATION":
			var payload: Dictionary = Dictionary(inner.get("payload", {}))
			_receipts.append({
				"at": now,
				"operation_id": String(payload.get("operation_id", "")),
			})
		"AUTHORITATIVE_SNAPSHOT":
			if _first_snapshot_at_ms < 0:
				_first_snapshot_at_ms = now
			_last_snapshot_at_ms = now
		"WORLD_PROJECTION":
			if _first_projection_at_ms < 0:
				_first_projection_at_ms = now
			_last_projection_at_ms = now
		"SESSION_CONTROL":
			var payload: Dictionary = inner.get("payload", {})
			var schema := String(inner.get("payload_schema", ""))
			if schema == Support.GatewayUtils.EG2_SESSION_AUTH_ACK_PAYLOAD_SCHEMA:
				if String(payload.get("ticket_status", "")) == "OK":
					_authenticated = true
				else:
					_finish_failure("AUTH_REJECTED", {})
			elif schema == Support.GatewayUtils.EG2_WORLD_READY_ACK_PAYLOAD_SCHEMA:
				_placed = true
				_world_ready = payload.duplicate(true)
			elif schema == Support.DEMAND_ACK_PAYLOAD_SCHEMA:
				if String(payload.get("demand_kind", "")) == Support.DEMAND_KIND_WITHDRAW:
					_withdraw_ack = true
			elif schema == Support.GatewayUtils.EG2_PLACEMENT_DEGRADED_ACK_PAYLOAD_SCHEMA:
				_finish_failure("PLACEMENT_DEGRADED", {"status": String(payload.get("status", ""))})
			elif String(payload.get("state", "")) == "DETACHED":
				_detached_ack = true
		_:
			pass


func _gateway_session_id() -> String:
	return String(_world_ready.get("gateway_session_id", ""))


func _demand_worlds_list() -> Array[String]:
	var worlds: Array[String] = []
	for value in String(_options["demand-worlds"]).split(",", false):
		worlds.append(value.strip_edges())
	return worlds


func _send_inner(inner: Dictionary) -> void:
	var wire: Dictionary = Support.wire_frame_for_inner(
			inner, String(_options["wire-session"]),
			"frame/eg4/l2/client-wire/%06d" % _next_wire_sequence, _next_wire_sequence)
	_next_wire_sequence += 1
	var sent: Dictionary = _boundary.send_to_peer(String(_options["peer-id"]), wire)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "SEND_FAILED")), {"inner_channel": String(inner["channel"])})


func _drive() -> void:
	if not _connected or _finished:
		return
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	if not _placed:
		if not _authenticated:
			if not _auth_sent:
				_auth_sent = true
				_send_inner(Support.authenticate_inner_eg3(
						String(_options["client-session-id"]), String(_options["auth-ticket"])))
			return
		if not _place_sent:
			_place_sent = true
			_start_wave_ops()
			_send_inner(Support.place_request_inner_eg4(
					String(_options["client-session-id"]), String(_options["auth-ticket"])))
		return
	if _wave == 1:
		if not _demand_sent:
			_demand_sent = true
			_send_inner(Support.projection_demand_inner(
					_gateway_session_id(), Support.DEMAND_KIND_SUBSCRIBE, _demand_worlds_list()))
			return
		if int(_channel_counts.get("WORLD_PROJECTION", 0)) < 5:
			return # wait until the fan-in is visibly flowing
		_run_wave_traffic()
		return
	# wave 2 (post-hold): gameplay continues, then withdraw + detach.
	if not _demand_withdrawn:
		if _movements_sent_this_wave < int(_options["movements-per-wave"]):
			# Wave-2 movements are SENT here: gameplay must continue even if
			# the projection source died while the client was parked on the
			# hold marker (waiting alone would deadlock the run).
			_movements_sent_this_wave += 1
			_send_inner(Support.movement_inner(_gateway_session_id(), _movement_seq))
			_movement_seq += 1
			return
		_demand_withdrawn = true
		_withdraw_sent_at_ms = now
		_send_inner(Support.projection_demand_inner(
				_gateway_session_id(), Support.DEMAND_KIND_WITHDRAW, _demand_worlds_list()))
		return
	if not _withdraw_ack and _withdraw_sent_at_ms > 0 \
			and now - _withdraw_sent_at_ms < 5000:
		return
	if not _detach_sent:
		_detach_sent = true
		_send_inner(Support.detach_inner_eg3(_gateway_session_id()))
		return
	if _detached_ack:
		_finish_success()


var _auth_sent := false
var _place_sent := false
var _withdraw_sent_at_ms: int = 0


func _run_wave_traffic() -> void:
	# wave 1: ops + movements, then park on the hold marker.
	if not _op_queue.is_empty():
		_send_inner(Support.select_hotbar_inner(_gateway_session_id(), String(_op_queue.pop_front())))
		return
	if _movements_sent_this_wave < int(_options["movements-per-wave"]):
		_movements_sent_this_wave += 1
		_send_inner(Support.movement_inner(_gateway_session_id(), _movement_seq))
		_movement_seq += 1
		return
	if _wave == 1:
		if not FileAccess.file_exists(String(_options["hold-release-marker-file"])):
			_awaiting_hold = true
			return
		_awaiting_hold = false
		_wave = 2
		_movements_sent_this_wave = 0
		_withdraw_sent_at_ms = 0


func _start_wave_ops() -> void:
	_op_queue.clear()
	for index in range(_ops_expected):
		_op_queue.append("operation/eg4/l2/%s-w1-%04d" % [
			String(_options["client-session-id"]).replace("client-session/eg4/", ""), index])


func _finish_success() -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg4_client_report.v1",
		"state": "COMPLETE",
		"passed": true,
		"client_session_id": String(_options["client-session-id"]),
		"world_ready": _world_ready,
		"gateway_session_id": _gateway_session_id(),
		"channel_counts": _channel_counts.duplicate(true),
		"receipts": _receipts,
		"receipt_count": _receipts.size(),
		"ops_expected": _ops_expected,
		"first_projection_at_ms": _first_projection_at_ms,
		"last_projection_at_ms": _last_projection_at_ms,
		"first_snapshot_at_ms": _first_snapshot_at_ms,
		"last_snapshot_at_ms": _last_snapshot_at_ms,
		"movements_sent": _movements_sent_this_wave,
		"frames": _frames,
		"detached_ack": _detached_ack,
		"withdraw_ack": _withdraw_ack,
		"user_data_dir": String(_options["user-data-dir"]),
		"process_id": OS.get_process_id(),
	}
	Support.write_json(String(_options["result-file"]), report)
	_boundary.stop()
	print("EG4_CLIENT_COMPLETE receipts=%d projections=%d snapshots=%d detached=%s" % [
		_receipts.size(), int(_channel_counts.get("WORLD_PROJECTION", 0)),
		int(_channel_counts.get("AUTHORITATIVE_SNAPSHOT", 0)), str(_detached_ack)])
	quit(0)


var _receipts_expected := 0


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg4_client_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details,
		"client_session_id": String(_options["client-session-id"]),
		"channel_counts": _channel_counts.duplicate(true),
		"receipt_count": _receipts.size(),
		"world_ready": _world_ready,
		"frames": _frames,
		"process_id": OS.get_process_id(),
	}
	if not String(_options.get("result-file", "")).is_empty():
		Support.write_json(String(_options["result-file"]), report)
	push_error("EG4 client worker failed: %s" % error_code)
	if _boundary != null:
		_boundary.stop()
	quit(1)
