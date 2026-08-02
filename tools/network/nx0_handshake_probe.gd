extends SceneTree

const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const ConditionSimulatorPort = preload("res://scripts/network/conditions/network_condition_simulator_port.gd")
const ConditionProfileStore = preload("res://scripts/network/conditions/network_condition_profile_store.gd")
const RuntimeIdentity = preload("res://scripts/network/observability/network_runtime_identity.gd")
const CompatibilityHandshake = preload("res://scripts/network/observability/network_compatibility_handshake.gd")
const TelemetryCollector = preload("res://scripts/network/observability/network_telemetry_collector.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")

const SERVER_PEER_ID := "peer/enet/nx0-handshake-server"
const TIMEOUT_MS := 15000


func _init() -> void:
	var options: Dictionary = _parse(OS.get_cmdline_user_args())
	var result_file: String = String(options.get("result_file", ""))
	var port_number: int = int(options.get("port", 0))
	var host: String = String(options.get("host", "127.0.0.1"))
	var session_token: String = String(options.get("session_token", ""))
	if result_file.is_empty() or port_number < 1 or port_number > 65535 or session_token.is_empty():
		_finish(result_file, false, "INVALID_PROBE_OPTIONS")
		return

	var identity_result: Dictionary = RuntimeIdentity.validate_config({
		"world_id": String(options.get("world_id", "moon")),
		"network_session_token": session_token,
	})
	if not bool(identity_result.get("success", false)):
		_finish(result_file, false, String(identity_result.get("error_code", "INVALID_PROBE_IDENTITY")), identity_result)
		return
	var fingerprint: Dictionary = identity_result.get("details", {}).get("fingerprint", {})
	var telemetry = TelemetryCollector.new()
	var telemetry_setup: Dictionary = telemetry.configure("test", fingerprint, 64)
	if not bool(telemetry_setup.get("success", false)):
		_finish(result_file, false, String(telemetry_setup.get("error_code", "TELEMETRY_SETUP_FAILED")), telemetry_setup)
		return
	var profile_result: Dictionary = ConditionProfileStore.load_profile(
		String(options.get("network_profile", "LOCAL")),
		String(options.get("network_presets_file", ConditionProfileStore.DEFAULT_PRESETS_PATH))
	)
	if not bool(profile_result.get("success", false)):
		_finish(result_file, false, String(profile_result.get("error_code", "PROFILE_LOAD_FAILED")), profile_result)
		return
	var simulator = ConditionSimulatorPort.new()
	var simulator_setup: Dictionary = simulator.setup(
		Port.new(),
		Dictionary(profile_result.get("details", {}).get("profile", {})),
		telemetry
	)
	if not bool(simulator_setup.get("success", false)):
		_finish(result_file, false, String(simulator_setup.get("error_code", "SIMULATOR_SETUP_FAILED")), simulator_setup)
		return
	var boundary = Boundary.new()
	var configured: Dictionary = boundary.configure(simulator, 524288, 16, 1048576, telemetry)
	if not bool(configured.get("success", false)):
		_finish(result_file, false, String(configured.get("error_code", "BOUNDARY_SETUP_FAILED")), configured)
		return
	var transport_session_id: String = "transport-session/nx0/probe/%d/%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	var connected: Dictionary = boundary.connect_client(
		Support.endpoint(host, port_number, false),
		SERVER_PEER_ID,
		transport_session_id,
		"route/nx0/probe",
		1
	)
	if not bool(connected.get("success", false)):
		_finish(result_file, false, String(connected.get("error_code", "PROBE_CONNECT_FAILED")), connected)
		return

	var started_ms: int = Time.get_ticks_msec()
	var handshake_started_ms: int = 0
	var hello_sent: bool = false
	var handshake_id: String = "handshake/nx0/probe/%d/%d" % [OS.get_process_id(), started_ms]
	var final_status: String = ""
	var final_error_code: String = ""
	var response: Dictionary = {}
	while Time.get_ticks_msec() - started_ms <= TIMEOUT_MS:
		var polled: Dictionary = boundary.poll_events(32)
		if not bool(polled.get("success", false)):
			final_error_code = String(polled.get("error_code", "PROBE_POLL_FAILED"))
			break
		if not hello_sent and String(boundary.get_peer_snapshot(SERVER_PEER_ID).get("state", "")) == "TRANSPORT_CONNECTED":
			var transition: Dictionary = boundary.mark_peer_handshaking(SERVER_PEER_ID)
			if not bool(transition.get("success", false)):
				final_error_code = String(transition.get("error_code", "PROBE_HANDSHAKE_STATE_FAILED"))
				break
			var hello: Dictionary = CompatibilityHandshake.create_hello(handshake_id, fingerprint, Time.get_ticks_msec())
			var frame_result: Dictionary = boundary.create_frame_for_peer(
				SERVER_PEER_ID, "CONTROL", Support.MESSAGE_SCHEMA,
				{"type": "COMPATIBILITY_HELLO", "hello": hello}
			)
			if not bool(frame_result.get("success", false)):
				final_error_code = String(frame_result.get("error_code", "PROBE_FRAME_CREATE_FAILED"))
				break
			var sent: Dictionary = boundary.send_to_peer(
				SERVER_PEER_ID, frame_result.get("details", {}).get("frame", {})
			)
			if not bool(sent.get("success", false)):
				final_error_code = String(sent.get("error_code", "PROBE_HELLO_SEND_FAILED"))
				break
			var flushed: Dictionary = boundary.flush_outbound(8, SERVER_PEER_ID)
			if not bool(flushed.get("success", false)):
				final_error_code = String(flushed.get("error_code", "PROBE_HELLO_FLUSH_FAILED"))
				break
			hello_sent = true
			handshake_started_ms = Time.get_ticks_msec()
		for event_value in polled.get("details", {}).get("events", []):
			if not event_value is Dictionary or String(event_value.get("event_type", "")) != "MESSAGE_RECEIVED":
				continue
			var payload: Dictionary = event_value.get("frame", {}).get("payload", {})
			var message_type: String = String(payload.get("type", ""))
			if message_type == "COMPATIBILITY_ACK":
				var ack: Dictionary = payload.get("ack", {})
				var ack_check: Dictionary = CompatibilityHandshake.validate_ack(ack)
				if not bool(ack_check.get("success", false)):
					final_error_code = "INVALID_COMPATIBILITY_ACK"
					response = ack_check
				else:
					final_status = "ACK"
					response = ack.duplicate(true)
				break
			if message_type == "COMPATIBILITY_REJECTED":
				var rejection: Dictionary = payload.get("rejection", {})
				var rejection_check: Dictionary = CompatibilityHandshake.validate_rejection(rejection)
				if not bool(rejection_check.get("success", false)):
					final_error_code = "INVALID_COMPATIBILITY_REJECTION"
					response = rejection_check
				else:
					final_status = "REJECTED"
					final_error_code = String(rejection.get("error_code", ""))
					response = rejection.duplicate(true)
				break
		if not final_status.is_empty() or not final_error_code.is_empty():
			break
		OS.delay_msec(5)
	if final_status.is_empty() and final_error_code.is_empty():
		final_error_code = "PROBE_TIMEOUT"
	var telemetry_result: Dictionary = telemetry.create_sample(Time.get_ticks_msec())
	var report: Dictionary = {
		"schema": "planet_simulator.nx0_handshake_probe.v1",
		"state": "COMPLETE" if not final_status.is_empty() else "FAILED",
		"passed": not final_status.is_empty(),
		"status": final_status,
		"error_code": final_error_code,
		"handshake_id": handshake_id,
		"hello_sent": hello_sent,
		"fingerprint": fingerprint.duplicate(true),
		"response": response.duplicate(true),
		"telemetry": telemetry_result.get("details", {}).get("sample", {}),
		"network_conditions": simulator.get_runtime_snapshot(),
		"handshake_elapsed_ms": (Time.get_ticks_msec() - handshake_started_ms) if handshake_started_ms > 0 else 0,
		"process_id": OS.get_process_id(),
	}
	Support.write(result_file, report)
	boundary.stop()
	quit(0 if not final_status.is_empty() else 1)


func _parse(arguments) -> Dictionary:
	var result: Dictionary = {
		"host": "127.0.0.1",
		"port": 0,
		"world_id": "moon",
		"session_token": "",
		"result_file": "",
		"network_profile": "LOCAL",
		"network_presets_file": ConditionProfileStore.DEFAULT_PRESETS_PATH,
	}
	for value in arguments:
		var argument: String = String(value).strip_edges()
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator: int = argument.find("=")
		var key: String = argument.substr(2, separator - 2)
		var raw: String = argument.substr(separator + 1)
		match key:
			"host": result["host"] = raw
			"port": result["port"] = raw.to_int()
			"world-id": result["world_id"] = raw.to_lower()
			"session-token": result["session_token"] = raw.to_lower()
			"result-file": result["result_file"] = raw
			"network-profile": result["network_profile"] = raw.to_upper()
			"network-presets-file": result["network_presets_file"] = raw
	return result


func _finish(result_file: String, passed: bool, error_code: String, details: Dictionary = {}) -> void:
	if not result_file.is_empty():
		Support.write(result_file, {
			"schema": "planet_simulator.nx0_handshake_probe.v1",
			"state": "FAILED",
			"passed": passed,
			"status": "",
			"error_code": error_code,
			"details": details.duplicate(true),
			"process_id": OS.get_process_id(),
		})
	quit(0 if passed else 1)
