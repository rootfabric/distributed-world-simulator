extends SceneTree

const Fingerprint = preload("res://scripts/network/observability/network_build_fingerprint.gd")
const ProtocolManifest = preload("res://scripts/network/observability/network_protocol_manifest.gd")
const RuntimeIdentity = preload("res://scripts/network/observability/network_runtime_identity.gd")
const CompatibilityHandshake = preload("res://scripts/network/observability/network_compatibility_handshake.gd")
const TelemetryCollector = preload("res://scripts/network/observability/network_telemetry_collector.gd")
const ObservabilitySample = preload("res://scripts/network/observability/network_observability_sample.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const ProtocolFrame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const LaunchOptions = preload("res://scripts/runtime/launch_options.gd")
const RuntimeDescriptor = preload("res://scripts/runtime/runtime_descriptor.gd")

const TEST_SCHEMA := "planet_simulator.nx0.observability_probe.v1"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_protocol_manifest_and_identity()
	_test_compatibility_handshake()
	_test_launch_and_runtime_descriptor()
	_test_transport_telemetry_integration()
	_test_runtime_wiring_and_non_goals()
	_finish()


func _test_protocol_manifest_and_identity() -> void:
	var manifest: Dictionary = ProtocolManifest.create()
	_assert(_ok(ProtocolManifest.validate(manifest)), "Current protocol manifest was rejected")
	_assert(String(manifest.get("schema", "")) == ProtocolManifest.SCHEMA, "Protocol manifest schema mismatch")
	_assert(int(manifest.get("manifest_version", 0)) == ProtocolManifest.MANIFEST_VERSION, "Protocol manifest version mismatch")
	_assert(String(manifest.get("protocol_hash", "")).length() == 64, "Protocol hash is not SHA-256")
	_assert(ProtocolManifest.current_protocol_hash() == String(manifest.get("protocol_hash", "")), "Current protocol hash is unstable")
	var contracts: Dictionary = manifest.get("contract_versions", {})
	for contract_name in [
		"protocol_frame", "transport_event", "peer_session", "transport_boundary",
		"transport_port", "m3_message", "player_input", "player_snapshot",
		"player_delta", "command_result", "item_graph_snapshot", "item_graph_delta",
		"compatibility_hello", "compatibility_ack", "compatibility_rejection",
		"observability_sample",
	]:
		_assert(contracts.has(contract_name), "Protocol manifest omits %s" % contract_name)
	var policy: Dictionary = manifest.get("channel_policy", {})
	var channel_count: int = int(policy.get("enet_channel_count", 0))
	_assert(channel_count in [3, 6], "Protocol manifest channel count is unsupported")
	_assert(Dictionary(policy.get("mapping", {})).has("CONTROL"), "Protocol manifest omits CONTROL channel")
	if channel_count == 3:
		_assert(Dictionary(policy.get("mapping", {})).has("COMMAND"), "Protocol manifest omits COMMAND channel")
		_assert(Dictionary(policy.get("mapping", {})).has("STATE"), "Protocol manifest omits STATE channel")
	else:
		_assert(Dictionary(policy.get("mapping", {})).has("INPUT"), "Protocol manifest omits INPUT channel")
		_assert(Dictionary(policy.get("mapping", {})).has("SNAPSHOT"), "Protocol manifest omits SNAPSHOT channel")

	var drifted_manifest: Dictionary = manifest.duplicate(true)
	drifted_manifest["channel_policy"]["enet_channel_count"] = 4
	_assert(_error(ProtocolManifest.validate(drifted_manifest)) == "CHANNEL_POLICY_DRIFT", "Channel policy drift was accepted")
	var hash_drift: Dictionary = manifest.duplicate(true)
	hash_drift["protocol_hash"] = "0".repeat(64)
	_assert(_error(ProtocolManifest.validate(hash_drift)) == "PROTOCOL_HASH_MISMATCH", "Protocol hash drift was accepted")
	var extra_manifest_field: Dictionary = manifest.duplicate(true)
	extra_manifest_field["unexpected"] = true
	_assert(_error(ProtocolManifest.validate(extra_manifest_field)) == "FIELD_SET_MISMATCH", "Protocol manifest accepted an extra field")

	var identity_result: Dictionary = RuntimeIdentity.validate_config({
		"world_id": "playground",
		"network_session_token": "session-id/nx0/baseline-test",
	})
	_assert(_ok(identity_result), "Default NX0 runtime identity was rejected")
	var fingerprint: Dictionary = identity_result.get("details", {}).get("fingerprint", {})
	_assert(_ok(Fingerprint.validate(fingerprint)), "Generated NX0 fingerprint is invalid")
	_assert(String(fingerprint.get("build_id", "")) == RuntimeIdentity.BUILD_ID, "NX0 build ID was not embedded")
	_assert(String(fingerprint.get("git_commit", "")) == RuntimeIdentity.SOURCE_COMMIT, "NX0 source commit was not embedded")
	_assert(String(fingerprint.get("protocol_hash", "")) == ProtocolManifest.current_protocol_hash(), "NX0 protocol hash was not embedded")
	_assert(String(fingerprint.get("world_id", "")) == "playground", "NX0 world binding was not embedded")
	_assert(String(fingerprint.get("session_token", "")) == "session-id/nx0/baseline-test", "NX0 session binding was not embedded")
	_assert(String(fingerprint.get("checksum", "")).length() == 64, "NX0 fingerprint checksum is missing")
	_assert(
		Dictionary(identity_result.get("details", {}).get("protocol_manifest", {})) == manifest,
		"Runtime identity returned a different protocol manifest"
	)

	var invalid_identity: Dictionary = RuntimeIdentity.validate_config({
		"world_id": "playground",
		"network_session_token": "raw-password",
	})
	_assert(_error(invalid_identity) == "INVALID_NETWORK_RUNTIME_IDENTITY", "Raw credential was accepted as runtime identity")
	_assert(
		String(invalid_identity.get("details", {}).get("cause", {}).get("error_code", "")) == "INVALID_SESSION_TOKEN",
		"Unsafe session token did not retain its contract error"
	)
	var custom_identity: Dictionary = RuntimeIdentity.validate_config({
		"world_id": "moon",
		"network_session_token": "sha256/%s" % "a".repeat(64),
		"network_build_id": "nx0-custom-build",
		"network_git_commit": "abcdef1",
		"network_protocol_hash": ProtocolManifest.current_protocol_hash(),
	})
	_assert(_ok(custom_identity), "Valid injected build identity was rejected")
	_assert(
		String(custom_identity.get("details", {}).get("fingerprint", {}).get("build_id", "")) == "nx0-custom-build",
		"Injected build ID was ignored"
	)


func _test_compatibility_handshake() -> void:
	var server_fingerprint: Dictionary = RuntimeIdentity.create_fingerprint({
		"world_id": "playground",
		"network_session_token": "session-id/nx0/handshake",
	})
	var client_fingerprint: Dictionary = server_fingerprint.duplicate(true)
	var hello: Dictionary = CompatibilityHandshake.create_hello(
		"handshake/nx0/client-a/1", client_fingerprint, 100
	)
	_assert(_ok(CompatibilityHandshake.validate_hello(hello)), "Valid compatibility hello was rejected")
	_assert(CompatibilityHandshake.is_valid_handshake_id("handshake/nx0/client-a/1"), "Valid handshake ID was rejected")
	for invalid_id in ["", "handshake/", "HANDSHAKE/a", "handshake//a", "session/a", "handshake/a$"]:
		_assert(not CompatibilityHandshake.is_valid_handshake_id(invalid_id), "Invalid handshake ID was accepted: %s" % invalid_id)

	var evaluation: Dictionary = CompatibilityHandshake.evaluate_server(server_fingerprint, hello, 125)
	_assert(_ok(evaluation), "Matching fingerprint handshake was rejected")
	var ack: Dictionary = evaluation.get("details", {}).get("ack", {})
	_assert(_ok(CompatibilityHandshake.validate_ack(ack)), "Generated compatibility ACK is invalid")
	_assert(_ok(CompatibilityHandshake.validate_client_ack(client_fingerprint, hello, ack)), "Client rejected matching server ACK")
	_assert(String(ack.get("handshake_id", "")) == String(hello.get("handshake_id", "")), "ACK changed handshake ID")
	_assert(String(ack.get("client_fingerprint_checksum", "")) == String(client_fingerprint.get("checksum", "")), "ACK did not bind client fingerprint")
	_assert(String(ack.get("server_fingerprint", {}).get("checksum", "")) == String(server_fingerprint.get("checksum", "")), "ACK did not bind server fingerprint")

	var hello_tampered: Dictionary = hello.duplicate(true)
	hello_tampered["client_sent_at_ms"] = 101
	_assert(_error(CompatibilityHandshake.validate_hello(hello_tampered)) == "HELLO_CHECKSUM_MISMATCH", "Tampered hello bypassed checksum")
	_assert(_error(CompatibilityHandshake.evaluate_server(server_fingerprint, {}, 125)) == "FINGERPRINT_REQUIRED", "Missing hello did not require fingerprint")
	var malformed_hello: Dictionary = hello.duplicate(true)
	malformed_hello["handshake_id"] = "handshake/"
	malformed_hello["checksum"] = _handshake_checksum(malformed_hello)
	_assert(_error(CompatibilityHandshake.evaluate_server(server_fingerprint, malformed_hello, 125)) == "INVALID_FINGERPRINT_HELLO", "Malformed hello was not rejected")

	for mismatch in [
		["build_id", "other-build", "BUILD_ID_MISMATCH"],
		["git_commit", "abcdef2", "GIT_COMMIT_MISMATCH"],
		["protocol_hash", "0".repeat(64), "PROTOCOL_HASH_MISMATCH"],
		["world_id", "moon", "WORLD_ID_MISMATCH"],
		["session_token", "session-id/nx0/other", "SESSION_TOKEN_MISMATCH"],
	]:
		var mismatched_fingerprint: Dictionary = client_fingerprint.duplicate(true)
		mismatched_fingerprint[String(mismatch[0])] = String(mismatch[1])
		mismatched_fingerprint["checksum"] = Fingerprint.compute_checksum(mismatched_fingerprint)
		var mismatched_hello: Dictionary = CompatibilityHandshake.create_hello(
			"handshake/nx0/mismatch/%s" % String(mismatch[0]).replace("_", "-"),
			mismatched_fingerprint,
			100
		)
		_assert(
			_error(CompatibilityHandshake.evaluate_server(server_fingerprint, mismatched_hello, 125)) == String(mismatch[2]),
			"Handshake mismatch code changed for %s" % String(mismatch[0])
		)

	var wrong_ack_id: Dictionary = ack.duplicate(true)
	wrong_ack_id["handshake_id"] = "handshake/nx0/other/1"
	wrong_ack_id["checksum"] = _handshake_checksum(wrong_ack_id)
	_assert(_error(CompatibilityHandshake.validate_client_ack(client_fingerprint, hello, wrong_ack_id)) == "HANDSHAKE_ID_MISMATCH", "Client accepted ACK for another handshake")
	var wrong_client_checksum: Dictionary = ack.duplicate(true)
	wrong_client_checksum["client_fingerprint_checksum"] = "0".repeat(64)
	wrong_client_checksum["checksum"] = _handshake_checksum(wrong_client_checksum)
	_assert(_error(CompatibilityHandshake.validate_client_ack(client_fingerprint, hello, wrong_client_checksum)) == "CLIENT_FINGERPRINT_ACK_MISMATCH", "Client accepted ACK for another fingerprint")
	var tampered_ack: Dictionary = ack.duplicate(true)
	tampered_ack["server_sent_at_ms"] = 126
	_assert(_error(CompatibilityHandshake.validate_ack(tampered_ack)) == "ACK_CHECKSUM_MISMATCH", "Tampered ACK bypassed checksum")

	var rejection: Dictionary = CompatibilityHandshake.create_rejection(
		"handshake/nx0/client-a/1", "SESSION_TOKEN_MISMATCH", 130
	)
	_assert(_ok(CompatibilityHandshake.validate_rejection(rejection)), "Valid compatibility rejection was rejected")
	_assert(String(rejection.get("error_code", "")) == "SESSION_TOKEN_MISMATCH", "Compatibility rejection lost error code")
	var tampered_rejection: Dictionary = rejection.duplicate(true)
	tampered_rejection["error_code"] = "BUILD_ID_MISMATCH"
	_assert(_error(CompatibilityHandshake.validate_rejection(tampered_rejection)) == "REJECTION_CHECKSUM_MISMATCH", "Tampered rejection bypassed checksum")


func _test_launch_and_runtime_descriptor() -> void:
	var parsed: Dictionary = LaunchOptions.parse(PackedStringArray([
		"--role=game-client",
		"--world=playground",
		"--player-identity=a",
		"--network-session-token=session-id/nx0/launch-test",
		"--network-build-id=%s" % RuntimeIdentity.BUILD_ID,
		"--network-git-commit=%s" % RuntimeIdentity.SOURCE_COMMIT,
		"--network-protocol-hash=%s" % ProtocolManifest.current_protocol_hash(),
	]))
	_assert(bool(parsed.get("success", false)), "Valid NX0 launch options were rejected")
	var options: Dictionary = parsed.get("options", {})
	_assert(String(options.get("network_session_token", "")) == "session-id/nx0/launch-test", "Launch parser lost session token")
	_assert(String(options.get("network_build_id", "")) == RuntimeIdentity.BUILD_ID, "Launch parser lost build ID")
	_assert(String(options.get("network_git_commit", "")) == RuntimeIdentity.SOURCE_COMMIT, "Launch parser lost source commit")
	_assert(String(options.get("network_protocol_hash", "")) == ProtocolManifest.current_protocol_hash(), "Launch parser lost protocol hash")

	var unsafe: Dictionary = LaunchOptions.parse(PackedStringArray([
		"--role=game-client", "--player-identity=a", "--network-session-token=password",
	]))
	_assert(not bool(unsafe.get("success", true)), "Launch parser accepted raw credential")
	_assert("Network runtime identity is invalid: INVALID_SESSION_TOKEN" in Array(unsafe.get("errors", [])), "Launch parser hid session-token rejection")
	var invalid_protocol: Dictionary = LaunchOptions.parse(PackedStringArray([
		"--role=game-client", "--player-identity=a", "--network-protocol-hash=abc",
	]))
	_assert(not bool(invalid_protocol.get("success", true)), "Launch parser accepted invalid protocol hash")

	var descriptor: Dictionary = RuntimeDescriptor.create(options, {
		"checkpoint": RuntimeIdentity.CHECKPOINT,
		"build_id": RuntimeIdentity.BUILD_ID,
	})
	_assert(bool(RuntimeDescriptor.validate(descriptor).get("success", false)), "NX0 runtime descriptor is invalid")
	_assert(Dictionary(descriptor.get("network_fingerprint", {})) == RuntimeIdentity.create_fingerprint({
		"world_id": "playground",
		"network_session_token": "session-id/nx0/launch-test",
	}), "Runtime descriptor fingerprint differs from launch identity")
	_assert(_ok(ProtocolManifest.validate(Dictionary(descriptor.get("network_protocol_manifest", {})))), "Runtime descriptor protocol manifest is invalid")
	var bad_descriptor_fingerprint: Dictionary = descriptor.duplicate(true)
	bad_descriptor_fingerprint["network_fingerprint"]["world_id"] = "moon"
	_assert(String(RuntimeDescriptor.validate(bad_descriptor_fingerprint).get("error_code", "")) == "INVALID_NETWORK_FINGERPRINT", "Runtime descriptor accepted tampered fingerprint")
	var bad_descriptor_manifest: Dictionary = descriptor.duplicate(true)
	bad_descriptor_manifest["network_protocol_manifest"]["protocol_hash"] = "0".repeat(64)
	_assert(String(RuntimeDescriptor.validate(bad_descriptor_manifest).get("error_code", "")) == "INVALID_NETWORK_PROTOCOL_MANIFEST", "Runtime descriptor accepted protocol drift")


func _test_transport_telemetry_integration() -> void:
	var fingerprint: Dictionary = RuntimeIdentity.create_fingerprint({
		"world_id": "playground",
		"network_session_token": "session-id/nx0/transport-test",
	})
	var collector = TelemetryCollector.new()
	_assert(_ok(collector.configure("test", fingerprint, 32)), "Telemetry collector setup failed")
	var port = LoopbackPort.new()
	var boundary = Boundary.new()
	_assert(_ok(boundary.configure(port, 4096, 8, 32768, collector)), "Boundary rejected telemetry collector")
	_assert(bool(boundary.get_snapshot().get("telemetry_attached", false)), "Boundary did not report attached telemetry")
	_assert(_ok(boundary.start_server({"transport": "LOOPBACK", "name": "nx0"})), "Loopback listener start failed")
	_assert(_ok(port.attach_peer("peer/nx0/a", "transport-session/nx0/a", "route/nx0/a", 1)), "Loopback peer attach failed")
	var connect_poll: Dictionary = boundary.poll_events(8)
	_assert(_ok(connect_poll), "Boundary could not poll connect events")
	_assert(String(boundary.get_peer_snapshot("peer/nx0/a").get("state", "")) == "TRANSPORT_CONNECTED", "Peer did not enter transport-connected state")
	_assert(_ok(boundary.mark_peer_handshaking("peer/nx0/a")), "Peer did not enter handshaking state")

	var control_frame_result: Dictionary = boundary.create_frame_for_peer(
		"peer/nx0/a", "CONTROL", TEST_SCHEMA, {"type": "COMPATIBILITY_HELLO"}
	)
	_assert(_ok(control_frame_result), "Pre-ready CONTROL frame creation failed")
	var control_frame: Dictionary = control_frame_result.get("details", {}).get("frame", {})
	_assert(_ok(boundary.send_to_peer("peer/nx0/a", control_frame)), "Pre-ready CONTROL frame was rejected")
	_assert(int(boundary.get_peer_snapshot("peer/nx0/a").get("queued_messages", 0)) == 1, "CONTROL queue depth was not exposed")
	_assert(_ok(boundary.flush_outbound(8, "peer/nx0/a")), "CONTROL frame dispatch failed")
	_assert(port.get_messages_for_peer("peer/nx0/a").size() == 1, "CONTROL frame did not reach transport port")

	var command_before_ready: Dictionary = boundary.create_frame_for_peer(
		"peer/nx0/a", "COMMAND", TEST_SCHEMA, {"type": "JOIN"}
	).get("details", {}).get("frame", {})
	_assert(_error(boundary.send_to_peer("peer/nx0/a", command_before_ready)) == "PEER_NOT_READY", "Pre-handshake JOIN was accepted by boundary")
	_assert(_ok(boundary.mark_peer_synchronizing("peer/nx0/a")), "Peer did not enter synchronizing state")
	_assert(_ok(boundary.mark_peer_ready("peer/nx0/a")), "Peer did not enter ready state")
	_assert(_ok(boundary.send_to_peer("peer/nx0/a", command_before_ready)), "JOIN frame remained blocked after readiness")
	_assert(_ok(boundary.flush_outbound(8, "peer/nx0/a")), "COMMAND frame dispatch failed")
	_assert(port.get_messages_for_peer("peer/nx0/a").size() == 2, "COMMAND frame did not reach transport port")

	var incoming_control: Dictionary = ProtocolFrame.create(
		"frame/nx0/incoming/1", "transport-session/nx0/a", 1,
		"CONTROL", "RELIABLE_ORDERED", TEST_SCHEMA, {"type": "COMPATIBILITY_ACK"}
	)
	_assert(_ok(port.inject_received_frame("peer/nx0/a", incoming_control)), "Incoming CONTROL frame injection failed")
	var receive_poll: Dictionary = boundary.poll_events(8)
	_assert(_ok(receive_poll), "Boundary could not poll incoming CONTROL frame")
	var message_events: int = 0
	for event_value in receive_poll.get("details", {}).get("events", []):
		if event_value is Dictionary and String(event_value.get("event_type", "")) == "MESSAGE_RECEIVED":
			message_events += 1
	_assert(message_events == 1, "Incoming CONTROL frame did not produce one message event")

	var sample_result: Dictionary = collector.create_sample(500)
	_assert(_ok(sample_result), "Transport telemetry sample creation failed")
	var sample: Dictionary = sample_result.get("details", {}).get("sample", {})
	_assert(_ok(ObservabilitySample.validate(sample)), "Transport telemetry sample is invalid")
	var counters: Dictionary = sample.get("counters", {})
	_assert(int(counters.get("transport_server_starts", 0)) == 1, "Server-start counter mismatch")
	_assert(int(counters.get("transport_frames_queued", 0)) == 2, "Queued-frame counter mismatch")
	_assert(int(counters.get("transport_frames_dispatched", 0)) == 2, "Dispatched-frame counter mismatch")
	var gauges: Dictionary = sample.get("gauges", {})
	_assert(is_equal_approx(float(gauges.get("transport_outbound_pending_messages", -1.0)), 0.0), "Pending-message gauge did not recover")
	_assert(is_equal_approx(float(gauges.get("transport_outbound_pending_bytes", -1.0)), 0.0), "Pending-byte gauge did not recover")
	_assert(is_equal_approx(float(gauges.get("reliable_queue_depth_messages", -1.0)), 0.0), "Reliable message queue gauge did not recover")
	_assert(is_equal_approx(float(gauges.get("reliable_queue_depth_bytes", -1.0)), 0.0), "Reliable byte queue gauge did not recover")
	var channels: Dictionary = sample.get("channels", {})
	var control_metrics: Dictionary = channels.get("control", {})
	var command_metrics: Dictionary = channels.get("command", {})
	_assert(int(control_metrics.get("packets_sent", 0)) == 1, "CONTROL sent packet count mismatch")
	_assert(int(control_metrics.get("packets_received", 0)) == 1, "CONTROL received packet count mismatch")
	_assert(int(control_metrics.get("bytes_sent", 0)) > 0, "CONTROL sent bytes were not measured")
	_assert(int(control_metrics.get("bytes_received", 0)) > 0, "CONTROL received bytes were not measured")
	_assert(int(command_metrics.get("packets_sent", 0)) == 1, "COMMAND sent packet count mismatch")
	_assert(int(command_metrics.get("bytes_sent", 0)) > 0, "COMMAND sent bytes were not measured")
	_assert(Dictionary(sample.get("distributions", {})).has("transport_poll_duration_ms"), "Transport poll duration was not measured")
	_assert(_ok(boundary.stop()), "Boundary stop failed")


func _test_runtime_wiring_and_non_goals() -> void:
	var server_source: String = FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
	var client_source: String = _load_script_source_chain(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd", {}
	)
	var boundary_source: String = FileAccess.get_file_as_string("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
	var enet_source: String = FileAccess.get_file_as_string("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
	var app_source: String = FileAccess.get_file_as_string("res://scripts/app/simulator_app.gd")
	_assert(server_source.find("elif not _is_peer_compatible(peer_id, session_id):") < server_source.find("\"JOIN\": _handle_join"), "Server compatibility gate is not before JOIN dispatch")
	_assert(server_source.contains("CompatibilityHandshake.evaluate_server"), "Server does not evaluate client fingerprint")
	_assert(server_source.contains("FINGERPRINT_REQUIRED"), "Server does not reject pre-handshake gameplay messages")
	_assert(server_source.contains("handshake_replays"), "Server handshake replay is not observable")
	_assert(server_source.contains("CompatibilityHandshake.is_valid_handshake_id"), "Server does not canonicalize rejected handshake IDs")
	_assert(client_source.contains("if _handshake_verified and not _join_sent"), "Client JOIN is not gated by verified fingerprint")
	_assert(client_source.contains("COMPATIBILITY_HELLO"), "Client does not send compatibility hello")
	_assert(client_source.contains("COMPATIBILITY_ACK"), "Client does not consume compatibility ACK")
	_assert(client_source.contains("pending_operation_timers"), "Client operation timer bound is not observable")
	_assert(client_source.contains("item_command_latency_ms"), "Client item command latency is not observable")
	_assert(client_source.contains("snapshot_age_ms"), "Client snapshot age is not observable")
	_assert(server_source.contains("server_tick_duration_ms"), "Server process-tick duration is not observable")
	_assert(boundary_source.contains("pre_ready_control"), "Boundary does not permit pre-ready CONTROL handshake")
	_assert(boundary_source.contains("_telemetry_record_transport"), "Boundary does not record transport bytes")
	_assert(enet_source.find("get_packet_channel()") < enet_source.find("get_packet()"), "ENet packet metadata is read after packet consumption")
	_assert(enet_source.contains("get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)"), "ENet RTT statistic is not exposed")
	_assert(enet_source.contains("packet_loss_percent"), "ENet packet loss statistic is not exposed")
	_assert(app_source.contains("network_session_token"), "SimulatorApp does not forward session binding")
	_assert(app_source.contains("network_protocol_hash"), "SimulatorApp does not forward protocol hash")

	var sh_launcher: String = FileAccess.get_file_as_string("res://PLAY_M7_NETWORKED_PLAYGROUND.sh")
	var ps_launcher: String = FileAccess.get_file_as_string("res://PLAY_M7_NETWORKED_PLAYGROUND.ps1")
	var server_launcher: String = FileAccess.get_file_as_string("res://START_M7_NETWORK_SERVER.ps1")
	var client_launcher: String = FileAccess.get_file_as_string("res://START_M7_NETWORK_CLIENT.ps1")
	for launcher_pair in [
		["PLAY_M7_NETWORKED_PLAYGROUND.sh", sh_launcher],
		["PLAY_M7_NETWORKED_PLAYGROUND.ps1", ps_launcher],
		["START_M7_NETWORK_SERVER.ps1", server_launcher],
		["START_M7_NETWORK_CLIENT.ps1", client_launcher],
	]:
		_assert(String(launcher_pair[1]).contains("network-session-token"), "%s does not pass session binding" % String(launcher_pair[0]))
	_assert(sh_launcher.contains("session-id/m7-"), "Linux launcher does not generate per-run public session ID")
	_assert(ps_launcher.contains("session-id/m7-"), "PowerShell launcher does not generate per-run public session ID")

	# NX0 instrumentation must survive later roadmap stages without freezing old traffic behavior.
	_assert(server_source.contains("const M7_MOVEMENT_CHECKPOINT_INTERVAL_MS := 1500"), "Movement persistence cadence changed outside NX9")
	if RuntimeIdentity.CHECKPOINT.contains("nx2") or RuntimeIdentity.CHECKPOINT.contains("nx3") or RuntimeIdentity.CHECKPOINT.contains("nx4"):
		_assert(server_source.contains("_movement_results_suppressed += 1"), "NX2 movement result suppression is missing")
		_assert(server_source.contains("MOVEMENT_NETWORK_TICK"), "NX2 movement snapshot cadence is missing")
		_assert(enet_source.contains("ChannelPolicyScript.ENET_CHANNEL_COUNT"), "NX2 channel policy is not wired")
	else:
		_assert(server_source.contains("_send_result(peer_id, operation_id, \"PLAYER_INPUT\", result)"), "NX0 movement result baseline changed unexpectedly")
		_assert(server_source.contains("_broadcast_snapshot(\"PLAYER_INPUT_SIMULATED\")"), "NX0 per-input snapshot baseline changed unexpectedly")
		_assert(enet_source.contains("const MAX_CHANNELS: int = 3"), "NX0 ENet channel baseline changed unexpectedly")


func _load_script_source_chain(path: String, visited: Dictionary) -> String:
	if path.is_empty() or visited.has(path):
		return ""
	visited[path] = true
	var source: String = FileAccess.get_file_as_string(path)
	if source.is_empty():
		return source
	var line_end: int = source.find("\n")
	var first_line: String = source.substr(
		0, line_end if line_end >= 0 else source.length()
	).strip_edges()
	if first_line.begins_with("extends \"") and first_line.ends_with("\""):
		var base_path: String = first_line.substr(9, first_line.length() - 10)
		return source + "\n" + _load_script_source_chain(base_path, visited)
	return source


func _handshake_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return preload("res://scripts/network/contracts/network_contract_utils.gd").payload_hash(payload)


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _error(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("NX0 observability baseline: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NX0 observability baseline: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
