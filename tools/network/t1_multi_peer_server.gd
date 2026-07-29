extends SceneTree

const SupportScript = preload("res://tools/network/t1_multi_peer_process_support.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const PortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")

var _options: Dictionary = {}
var _boundary
var _started_ms: int = 0
var _completed_at_ms: int = 0
var _received_by_client: Dictionary = {}
var _peer_by_client: Dictionary = {}
var _sent: int = 0
var _peak_peer_count: int = 0
var _replies_sent: bool = false
var _finished: bool = false


func _initialize() -> void:
	var parsed: Dictionary = SupportScript.parse_options(OS.get_cmdline_user_args(), "server")
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	_boundary = BoundaryScript.new()
	var configured: Dictionary = _boundary.configure(PortScript.new(), 65536, 32, 1048576)
	if not bool(configured.get("success", false)):
		_finish_failure(String(configured.get("error_code", "CONFIGURE_FAILED")))
		return
	var started: Dictionary = _boundary.start_server(SupportScript.endpoint(_options))
	if not bool(started.get("success", false)):
		_finish_failure(String(started.get("error_code", "START_FAILED")))
		return
	_started_ms = Time.get_ticks_msec()
	SupportScript.write_json(String(_options["result_file"]), {
		"schema": "planet_simulator.t1_multi_peer_process_state.v1",
		"state": "LISTENING", "passed": false, "port": int(_options["port"]),
	})
	print("T1_SERVER_LISTENING port=%d" % int(_options["port"]))


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(64)
	_peak_peer_count = maxi(_peak_peer_count, int(_boundary.get_snapshot().get("peer_count", 0)))
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "POLL_FAILED")), _boundary.get_snapshot())
		return false
	for event in polled.get("details", {}).get("events", []):
		if String(event.get("event_type", "")) != "MESSAGE_RECEIVED":
			continue
		var peer_id: String = String(event["peer_id"])
		var payload: Dictionary = event.get("frame", {}).get("payload", {})
		var client_id: String = String(payload.get("client_id", ""))
		if client_id not in ["a", "b"] or _received_by_client.has(client_id):
			continue
		_received_by_client[client_id] = payload.duplicate(true)
		_peer_by_client[client_id] = peer_id
	if _received_by_client.size() == int(_options["expected_clients"]) and not _replies_sent:
		var active_peer_count: int = int(_boundary.get_snapshot().get("peer_count", 0))
		_peak_peer_count = maxi(_peak_peer_count, active_peer_count)
		if active_peer_count < int(_options["expected_clients"]):
			_finish_failure("PEER_OVERLAP_NOT_OBSERVED", _boundary.get_snapshot())
			return false
		var client_ids: Array = _received_by_client.keys()
		client_ids.sort()
		for client_id_value in client_ids:
			var client_id: String = String(client_id_value)
			var peer_id: String = String(_peer_by_client[client_id])
			var ready: Dictionary = _boundary.mark_peer_ready(peer_id)
			if not bool(ready.get("success", false)):
				_finish_failure(String(ready.get("error_code", "READY_FAILED")))
				return false
			var frame_result: Dictionary = _boundary.create_frame_for_peer(
				peer_id, "STATE", "planet_simulator.t1.targeted_reply.v1",
				{"client_id": client_id, "target_peer_id": peer_id, "ordinal": _sent + 1}
			)
			if not bool(frame_result.get("success", false)):
				_finish_failure(String(frame_result.get("error_code", "FRAME_FAILED")))
				return false
			var sent: Dictionary = _boundary.send_to_peer(peer_id, frame_result.get("details", {}).get("frame", {}))
			if not bool(sent.get("success", false)):
				_finish_failure(String(sent.get("error_code", "SEND_FAILED")))
				return false
			_sent += 1
		_replies_sent = true
		_completed_at_ms = Time.get_ticks_msec()
	if _replies_sent and Time.get_ticks_msec() - _completed_at_ms >= 500:
		_finish_success()
		return false
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout_ms"]):
		_finish_failure("SERVER_TIMEOUT", _boundary.get_snapshot())
	return false


func _finalize() -> void:
	if _boundary != null:
		_boundary.stop()


func _finish_success() -> void:
	var snapshot: Dictionary = _boundary.get_snapshot()
	var report: Dictionary = {
		"schema": "planet_simulator.t1_multi_peer_server_report.v1",
		"checkpoint": SupportScript.CHECKPOINT,
		"build_id": SupportScript.BUILD_ID,
		"state": "COMPLETE",
		"passed": true,
		"listener_state": String(snapshot.get("state", "")),
		"received_clients": _received_by_client.keys(),
		"peer_by_client": _peer_by_client.duplicate(true),
		"messages_received": _received_by_client.size(),
		"messages_sent": _sent,
		"peer_count": int(snapshot.get("peer_count", 0)),
		"peak_peer_count": _peak_peer_count,
		"process_id": OS.get_process_id(),
	}
	SupportScript.write_json(String(_options["result_file"]), report)
	_finished = true
	print("T1_SERVER_RESULT %s" % JSON.stringify(report))
	quit(0)


func _finish_failure(error_code: String, details: Dictionary = {}) -> void:
	var report: Dictionary = {
		"schema": "planet_simulator.t1_multi_peer_server_report.v1",
		"state": "FAILED", "passed": false, "failure_code": error_code,
		"details": details.duplicate(true), "process_id": OS.get_process_id(),
	}
	if not String(_options.get("result_file", "")).is_empty():
		SupportScript.write_json(String(_options["result_file"]), report)
	_finished = true
	push_error("T1 multi-peer server failed: %s" % error_code)
	quit(1)
