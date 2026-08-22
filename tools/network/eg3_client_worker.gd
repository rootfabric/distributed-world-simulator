extends SceneTree

## EG3 client worker: a real game-client process over real ENET against the
## shared-multiplexed gateway. Lifecycle: CONNECT -> AUTHENTICATE (one-time
## ticket) -> PLACE_REQUEST (optionally with a resume token) -> WORLD_READY ->
## wave-1: distinct operations + one movement + optional paced INPUT flood ->
## results; two-wave mode then parks until a trigger file appears, fires
## wave 2, and DETACHes. --no-detach=1 completes WITHOUT detaching so the
## orchestrator can kill the process and the tunnel must survive the abrupt
## transport-level disappearance.

const Support = preload("res://tools/network/eg3_process_support.gd")
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
	"client-session-id": {"kind": "string", "default": "", "required": true},
	"peer-id": {"kind": "string", "default": "peer/enet/eg3-client"},
	"wire-session": {"kind": "string", "default": "transport-session/eg3/l2-client"},
	"flood-count": {"kind": "int", "default": 0},
	"flood-interval-ms": {"kind": "int", "default": Support.FLOOD_INPUT_INTERVAL_MS},
	"waves": {"kind": "int", "default": 1},
	"wave-trigger-file": {"kind": "string", "default": ""},
	"no-detach": {"kind": "string", "default": ""},
	"movement-seq-base": {"kind": "int", "default": 100},
	## Resume clients reuse the tag's operation table under a HIGHER wave
	## number so operation ids never collide across gateway sessions.
	"op-wave-offset": {"kind": "int", "default": 0},
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
# Only RELIABLE WORLD_OPERATION receipts gate progress: the authoritative
# snapshot rides the shared UNRELIABLE SNAPSHOT stream where concurrent
# sessions may legally coalesce older frames away, so it must never be a
# completion condition.
var _reliable_receipts: int = 0
var _snapshots_received: int = 0
var _receipt_at_ms: Array = []
var _sent_at_log: Array = []
var _frames_received: Array[String] = []
var _frames_sent: Array[String] = []
var _op_queue: Array = []
var _flood_remaining: int = 0
var _flood_next_due_ms: int = 0
var _flood_seq: int = Support.FLOOD_INPUT_SEQ_BASE
var _flood_started_at_ms: int = -1
var _last_input_sent_at_ms: int = -1
var _wave_one_completed_at_ms: int = -1
var _wave: int = 1
var _awaiting_trigger := false
var _detach_sent := false
var _auth_sent := false
var _place_sent := false
var _heartbeat_at_ms: int = 0


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
			"route/eg3/l2-client-%s" % _tag(), 1)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")), {})
		return
	_started_ms = int(Time.get_unix_time_from_system() * 1000.0)
	print("EG3_CLIENT_CONNECTING tag=%s port=%d" % [_tag(), int(_options["port"])])


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
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	if not _finished and now - _heartbeat_at_ms >= 500:
		_heartbeat_at_ms = now
		Support.write_json(String(_options["result-file"]) + ".heartbeat.json", {
			"schema": "planet_simulator.eg3_client_heartbeat.v1",
			"connected": _connected, "authenticated": _authenticated, "placed": _placed,
			"wave": _wave, "receipts": _reliable_receipts, "snapshots": _snapshots_received,
			"op_queue": _op_queue.size(), "movement_active": _movement_active,
			"movement_attempts": int(_movement_pending.get("attempts", 0)),
			"flood_remaining": _flood_remaining, "awaiting_trigger": _awaiting_trigger,
			"detach_sent": _detach_sent, "detached_ack": _detached_ack,
		})
	if Time.get_unix_time_from_system() * 1000.0 - _started_ms > int(_options["timeout-ms"]):
		_finish_failure("CLIENT_TIMEOUT", {"results": _reliable_receipts, "placed": _placed})
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
		"WORLD_OPERATION":
			_results.append({
				"channel": "WORLD_OPERATION",
				"payload": Dictionary(inner.get("payload", {})).duplicate(true),
			})
			_reliable_receipts += 1
			_receipt_at_ms.append({
				"at": int(Time.get_unix_time_from_system() * 1000.0),
				"operation_id": String(Dictionary(inner.get("payload", {})).get("operation_id", "")),
			})
		"AUTHORITATIVE_SNAPSHOT":
			_results.append({
				"channel": "AUTHORITATIVE_SNAPSHOT",
				"payload": Dictionary(inner.get("payload", {})).duplicate(true),
			})
			_snapshots_received += 1
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
				_start_wave()
			elif schema == GatewayUtils.EG2_PLACEMENT_DEGRADED_ACK_PAYLOAD_SCHEMA:
				_finish_failure("PLACEMENT_DEGRADED", {"status": String(payload.get("status", ""))})
			elif String(payload.get("state", "")) == "DETACHED":
				_detached_ack = true
		_:
			pass


func _tag() -> String:
	var client_session_id := String(_options["client-session-id"])
	return client_session_id.get_slice("/", client_session_id.get_slice_count("/") - 1)


func _gateway_session_id() -> String:
	return String(_world_ready.get("gateway_session_id", ""))


func _start_wave() -> void:
	_op_queue.clear()
	_movement_pending = {"seq": int(_options["movement-seq-base"]) + 100 * (_wave - 1),
			"sent_at_ms": 0, "attempts": 0}
	_movement_active = true
	var effective_wave := _wave + int(_options["op-wave-offset"])
	for id_value in Support.tag_operations(_tag(), effective_wave):
		_op_queue.append(id_value)
	if _flood_count() > 0 and _wave == 1:
		_flood_remaining = _flood_count()
		_flood_next_due_ms = 0


var _movement_pending: Dictionary = {}
var _movement_active := false


func _flood_count() -> int:
	return int(_options["flood-count"])


func _send_inner(inner: Dictionary) -> void:
	_frames_sent.append(JSON.stringify(inner))
	_sent_at_log.append({
		"at": int(Time.get_unix_time_from_system() * 1000.0),
		"channel": String(inner["channel"]),
		"operation_id": String(Dictionary(inner.get("payload", {})).get("operation_id", "")),
		"input_seq": int(Dictionary(inner.get("payload", {})).get("input_seq", -1)),
	})
	var wire: Dictionary = Support.wire_frame_for_inner(
			inner, String(_options["wire-session"]),
			"frame/eg3/l2/wire/%s/%d" % [_tag(), _next_wire_sequence], _next_wire_sequence)
	_next_wire_sequence += 1
	var sent: Dictionary = _boundary.send_to_peer(String(_options["peer-id"]), wire)
	if not bool(sent.get("success", false)):
		_finish_failure(String(sent.get("error_code", "SEND_FAILED")), {"inner_channel": String(inner["channel"])})


func _drive() -> void:
	if not _connected or _finished:
		return
	if not _placed:
		if not _authenticated:
			if not _auth_sent:
				_auth_sent = true
				_send_inner(Support.authenticate_inner_eg3(
						String(_options["client-session-id"]), String(_options["auth-ticket"])))
			return
		if not _place_sent:
			_place_sent = true
			_send_inner(Support.place_request_inner_eg3(
					String(_options["client-session-id"]), String(_options["auth-ticket"]),
					String(_options["resume-token"])))
		return
	# Wave order: tracked movement FIRST (per-player input sequences must be
	# strictly increasing, so it precedes the flood's 1000+ seqs), then the
	# reliable operations, then the paced flood pressure. The unreliable
	# movement may be coalesced away under concurrency, so it is retried on a
	# timer until its reliable receipt lands (idempotent at the sim).
	var expected_results := Support.OPS_PER_WAVE + 1
	if _movement_active and int(_movement_pending["sent_at_ms"]) == 0:
		_movement_pending["attempts"] = 1
		_movement_pending["sent_at_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
		_last_input_sent_at_ms = int(_movement_pending["sent_at_ms"])
		_send_inner(Support.movement_inner(_gateway_session_id(), int(_movement_pending["seq"])))
	if not _op_queue.is_empty():
		_send_inner(Support.select_hotbar_inner(_gateway_session_id(), String(_op_queue.pop_front())))
		return
	if _flood_remaining > 0:
		var flood_now := int(Time.get_unix_time_from_system() * 1000.0)
		if flood_now >= _flood_next_due_ms:
			if _flood_started_at_ms < 0:
				_flood_started_at_ms = flood_now
			_send_inner(Support.movement_inner(_gateway_session_id(), _flood_seq))
			_last_input_sent_at_ms = flood_now
			_flood_seq += 1
			_flood_remaining -= 1
			_flood_next_due_ms = flood_now + int(_options["flood-interval-ms"])
		return
	if _reliable_receipts < expected_results:
		if _movement_active:
			var now := int(Time.get_unix_time_from_system() * 1000.0)
			if now - int(_movement_pending["sent_at_ms"]) >= Support.MOVEMENT_RECEIPT_RETRY_MS:
				if int(_movement_pending["attempts"]) >= Support.MOVEMENT_RECEIPT_MAX_ATTEMPTS:
					_finish_failure("MOVEMENT_RECEIPT_LOST", {"seq": int(_movement_pending["seq"])})
					return
				_movement_pending["attempts"] = int(_movement_pending["attempts"]) + 1
				_movement_pending["sent_at_ms"] = now
				_last_input_sent_at_ms = now
				_send_inner(Support.movement_inner(_gateway_session_id(), int(_movement_pending["seq"])))
		return
	_movement_active = false
	if _wave == 1:
		# FIRST-completion timestamp: this branch re-runs every frame while
		# the trigger is pending, so only the first observation counts.
		if _wave_one_completed_at_ms < 0:
			_wave_one_completed_at_ms = int(Time.get_unix_time_from_system() * 1000.0)
		if int(_options["waves"]) >= 2:
			var trigger_path := String(_options["wave-trigger-file"])
			if not FileAccess.file_exists(trigger_path):
				_awaiting_trigger = true
				return
			_awaiting_trigger = false
			_wave = 2
			_results.clear()
			_reliable_receipts = 0
			_start_wave()
			return
		if String(_options["no-detach"]) == "1":
			_finish_success()
			return
	if not _detach_sent:
		_detach_sent = true
		_send_inner(Support.detach_inner_eg3(_gateway_session_id()))
		return
	if _detached_ack:
		_finish_success()


func _finish_success() -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg3_client_report.v1",
		"state": "COMPLETE",
		"passed": true,
		"client_session_id": String(_options["client-session-id"]),
		"tag": _tag(),
		"world_ready": _world_ready,
		"logical_player_id": String(_world_ready.get("logical_player_id", "")),
		"player_entity_id": String(_world_ready.get("player_entity_id", "")),
		"resume_token_out": String(_world_ready.get("resume_token", "")),
		"gateway_session_id": _gateway_session_id(),
		"results_received": _reliable_receipts,
		"snapshots_received": _snapshots_received,
		"receipt_times": _receipt_at_ms,
		"sent_log": _sent_at_log,
		"flood_inputs_sent": _flood_count() - _flood_remaining,
		"flood_started_at_ms": _flood_started_at_ms,
		"last_input_sent_at_ms": _last_input_sent_at_ms,
		"wave_one_completed_at_ms": _wave_one_completed_at_ms,
		"completed_at_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"detached_ack": _detached_ack,
		"frames_received": _frames_received,
		"frames_sent": _frames_sent,
		"user_data_dir": String(_options["user-data-dir"]),
		"process_id": OS.get_process_id(),
	}
	Support.write_json(String(_options["result-file"]), report)
	_boundary.stop()
	print("EG3_CLIENT_COMPLETE tag=%s wave=%d receipts=%d snapshots=%d detached=%s" % [
		_tag(), _wave, _reliable_receipts, _snapshots_received, str(_detached_ack)])
	quit(0)


func _finish_failure(error_code: String, details: Dictionary) -> void:
	_finished = true
	var report: Dictionary = {
		"schema": "planet_simulator.eg3_client_report.v1",
		"state": "FAILED",
		"passed": false,
		"failure_code": error_code,
		"details": details,
		"client_session_id": String(_options["client-session-id"]),
		"tag": _tag(),
		"results_received": _reliable_receipts,
		"snapshots_received": _snapshots_received,
		"world_ready": _world_ready,
		"flood_inputs_sent": _flood_count() - _flood_remaining,
		"last_input_sent_at_ms": _last_input_sent_at_ms,
		"frames_received": _frames_received,
		"frames_sent": _frames_sent,
		"process_id": OS.get_process_id(),
	}
	if not String(_options.get("result-file", "")).is_empty():
		Support.write_json(String(_options["result-file"]), report)
	push_error("EG3 client worker failed: %s" % error_code)
	if _boundary != null:
		_boundary.stop()
	quit(1)
