extends SceneTree

const SupportScript = preload("res://tools/network/t1_multi_peer_process_support.gd")
const BoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const PortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")

var _options: Dictionary = {}
var _boundary
var _peer_id: String = "peer/enet/server"
var _session_id: String = ""
var _started_ms: int = 0
var _sent: bool = false
var _finished: bool = false


func _initialize() -> void:
	var parsed: Dictionary = SupportScript.parse_options(OS.get_cmdline_user_args(), "client")
	if not bool(parsed.get("success", false)):
		_finish_failure("INVALID_OPTIONS", {"errors": parsed.get("errors", [])})
		return
	_options = parsed["options"]
	var client_id: String = String(_options["client_id"])
	_session_id = "transport-session/client/%s" % client_id
	_boundary = BoundaryScript.new()
	var configured: Dictionary = _boundary.configure(PortScript.new(), 65536, 16, 524288)
	if not bool(configured.get("success", false)):
		_finish_failure(String(configured.get("error_code", "CONFIGURE_FAILED")))
		return
	var connected: Dictionary = _boundary.connect_client(
		SupportScript.endpoint(_options), _peer_id, _session_id, "route/enet/server/1", 1
	)
	if not bool(connected.get("success", false)):
		_finish_failure(String(connected.get("error_code", "CONNECT_FAILED")))
		return
	_started_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if _finished or _boundary == null:
		return false
	var polled: Dictionary = _boundary.poll_events(32)
	if not bool(polled.get("success", false)):
		_finish_failure(String(polled.get("error_code", "POLL_FAILED")), _boundary.get_snapshot())
		return false
	if not _sent and String(_boundary.get_peer_snapshot(_peer_id).get("state", "")) == "TRANSPORT_CONNECTED":
		var ready: Dictionary = _boundary.mark_peer_ready(_peer_id)
		if not bool(ready.get("success", false)):
			_finish_failure(String(ready.get("error_code", "READY_FAILED")))
			return false
		var frame_result: Dictionary = _boundary.create_frame_for_peer(
			_peer_id, "CONTROL", "planet_simulator.t1.client_probe.v1",
			{"client_id": String(_options["client_id"]), "session_id": _session_id}
		)
		var sent: Dictionary = _boundary.send_to_peer(_peer_id, frame_result.get("details", {}).get("frame", {}))
		if not bool(sent.get("success", false)):
			_finish_failure(String(sent.get("error_code", "SEND_FAILED")))
			return false
		_sent = true
	for event in polled.get("details", {}).get("events", []):
		if String(event.get("event_type", "")) != "MESSAGE_RECEIVED":
			continue
		var payload: Dictionary = event.get("frame", {}).get("payload", {})
		if String(payload.get("client_id", "")) != String(_options["client_id"]):
			_finish_failure("TARGET_ISOLATION_FAILED", {"payload": payload})
			return false
		_finish_success(payload)
		return false
	if Time.get_ticks_msec() - _started_ms > int(_options["timeout_ms"]):
		_finish_failure("CLIENT_TIMEOUT", _boundary.get_snapshot())
	return false


func _finalize() -> void:
	if _boundary != null:
		_boundary.stop()


func _finish_success(payload: Dictionary) -> void:
	var report: Dictionary = {
		"schema": "planet_simulator.t1_multi_peer_client_report.v1",
		"checkpoint": SupportScript.CHECKPOINT,
		"build_id": SupportScript.BUILD_ID,
		"state": "COMPLETE", "passed": true,
		"client_id": String(_options["client_id"]),
		"session_id": _session_id,
		"target_peer_id": String(payload.get("target_peer_id", "")),
		"received_client_id": String(payload.get("client_id", "")),
		"messages_sent": 1, "messages_received": 1,
		"process_id": OS.get_process_id(),
	}
	SupportScript.write_json(String(_options["result_file"]), report)
	_finished = true
	print("T1_CLIENT_RESULT %s" % JSON.stringify(report))
	quit(0)


func _finish_failure(error_code: String, details: Dictionary = {}) -> void:
	var report: Dictionary = {
		"schema": "planet_simulator.t1_multi_peer_client_report.v1",
		"state": "FAILED", "passed": false, "failure_code": error_code,
		"client_id": String(_options.get("client_id", "")),
		"details": details.duplicate(true), "process_id": OS.get_process_id(),
	}
	if not String(_options.get("result_file", "")).is_empty():
		SupportScript.write_json(String(_options["result_file"]), report)
	_finished = true
	push_error("T1 multi-peer client failed: %s" % error_code)
	quit(1)
