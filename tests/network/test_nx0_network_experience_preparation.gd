extends SceneTree

const Fingerprint = preload("res://scripts/network/observability/network_build_fingerprint.gd")
const Sample = preload("res://scripts/network/observability/network_observability_sample.gd")
const Collector = preload("res://scripts/network/observability/network_telemetry_collector.gd")
const ConditionProfile = preload("res://scripts/network/conditions/network_condition_profile.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_fingerprint_contract()
	_test_telemetry_contracts()
	_test_condition_profiles()
	_test_baseline_and_documentation()
	_finish()


func _test_fingerprint_contract() -> void:
	var protocol_hash: String = Fingerprint.compute_protocol_hash(
		{"gameplay": 1, "protocol_frame": 2},
		{"control": "RELIABLE", "input": "UNRELIABLE_ORDERED"}
	)
	_assert(protocol_hash.length() == 64, "Protocol hash is not SHA-256")
	_assert(protocol_hash == Fingerprint.compute_protocol_hash(
		{"protocol_frame": 2, "gameplay": 1},
		{"input": "UNRELIABLE_ORDERED", "control": "RELIABLE"}
	), "Protocol hash depends on Dictionary insertion order")
	_assert(protocol_hash != Fingerprint.compute_protocol_hash(
		{"gameplay": 2, "protocol_frame": 2},
		{"control": "RELIABLE", "input": "UNRELIABLE_ORDERED"}
	), "Protocol hash ignored contract version change")

	var expected: Dictionary = Fingerprint.create(
		"nx0-observability-baseline-preparation",
		"69bd7fc",
		protocol_hash,
		"playground",
		"session-id/nx0/test-1"
	)
	_assert(_ok(Fingerprint.validate(expected)), "Valid build fingerprint was rejected")
	_assert(String(expected.get("checksum", "")).length() == 64, "Build fingerprint checksum is missing")
	_assert(_ok(Fingerprint.compare(expected, expected)), "Identical fingerprints are incompatible")

	var tampered: Dictionary = expected.duplicate(true)
	tampered["world_id"] = "moon"
	_assert(_error(Fingerprint.validate(tampered)) == "CHECKSUM_MISMATCH", "Fingerprint tampering bypassed checksum")
	_assert(_mismatch(expected, "build_id", "other-build") == "BUILD_ID_MISMATCH", "Build mismatch code is unstable")
	_assert(_mismatch(expected, "git_commit", "69bd7fd") == "GIT_COMMIT_MISMATCH", "Git commit mismatch code is unstable")
	_assert(_mismatch(expected, "protocol_hash", "0".repeat(64)) == "PROTOCOL_HASH_MISMATCH", "Protocol mismatch code is unstable")
	_assert(_mismatch(expected, "world_id", "moon") == "WORLD_ID_MISMATCH", "World mismatch code is unstable")
	_assert(_mismatch(expected, "session_token", "session-id/nx0/test-2") == "SESSION_TOKEN_MISMATCH", "Session mismatch code is unstable")

	var invalid_commit: Dictionary = Fingerprint.create(
		"nx0-observability-baseline-preparation", "69BD7FC", protocol_hash,
		"playground", "session-id/nx0/test-1"
	)
	_assert(_error(Fingerprint.validate(invalid_commit)) == "INVALID_GIT_COMMIT", "Uppercase commit was accepted")
	var invalid_protocol: Dictionary = Fingerprint.create(
		"nx0-observability-baseline-preparation", "69bd7fc", "abc",
		"playground", "session-id/nx0/test-1"
	)
	_assert(_error(Fingerprint.validate(invalid_protocol)) == "INVALID_PROTOCOL_HASH", "Short protocol hash was accepted")

	for unsafe_token in [
		"password",
		"bearer/secret-token",
		"session-token/nx0/test-1",
		"session-id/",
		"sha256/abc",
		"sha256/%s" % "A".repeat(64),
	]:
		var invalid_session: Dictionary = Fingerprint.create(
			"nx0-observability-baseline-preparation",
			"69bd7fc",
			protocol_hash,
			"playground",
			unsafe_token
		)
		_assert(
			_error(Fingerprint.validate(invalid_session)) == "INVALID_SESSION_TOKEN",
			"Unsafe session_token format was accepted: %s" % unsafe_token
		)

	var digest_session: Dictionary = Fingerprint.create(
		"nx0-observability-baseline-preparation",
		"69bd7fc",
		protocol_hash,
		"playground",
		"sha256/%s" % "a".repeat(64)
	)
	_assert(_ok(Fingerprint.validate(digest_session)), "Valid SHA-256 session token was rejected")


func _test_telemetry_contracts() -> void:
	var fingerprint: Dictionary = Fingerprint.create(
		"nx0-observability-baseline-preparation",
		"69bd7fc",
		Fingerprint.compute_protocol_hash({"gameplay": 1}, {"control": "RELIABLE"}),
		"playground",
		"session-id/nx0/telemetry"
	)
	var collector = Collector.new()
	_assert(_error(collector.increment("packets_sent")) == "NOT_CONFIGURED", "Collector accepted update before configure")
	_assert(_error(collector.configure("invalid", fingerprint, 3)) == "INVALID_RUNTIME_ROLE", "Collector accepted invalid role")
	_assert(_error(collector.configure("test", fingerprint, 0)) == "INVALID_SAMPLE_LIMIT", "Collector accepted zero sample window")
	_assert(_ok(collector.configure("test", fingerprint, 3)), "Collector configuration failed")
	_assert(_error(collector.configure("test", fingerprint, 3)) == "ALREADY_CONFIGURED", "Collector allowed reconfiguration")
	_assert(_error(collector.increment("Packets Sent")) == "INVALID_COUNTER_UPDATE", "Collector accepted non-canonical counter")
	_assert(_error(collector.increment("packets_sent", -1)) == "INVALID_COUNTER_UPDATE", "Collector accepted negative counter increment")
	_assert(_ok(collector.increment("packets_sent", 2)), "Counter increment failed")
	_assert(_ok(collector.increment("movement_results_suppressed", 7)), "Suppression counter increment failed")
	_assert(_ok(collector.set_gauge("reliable_queue_depth", 4.0)), "Gauge update failed")
	_assert(_error(collector.set_gauge("server_tick_duration_ms", INF)) == "INVALID_GAUGE_UPDATE", "Collector accepted infinite gauge")

	_assert(_ok(collector.observe("first_observation_ms", 12.5)), "First distribution observation failed")
	_assert(int(collector.get_report().get("distribution_count", 0)) == 1, "First observation was not stored immediately")
	var first_sample_result: Dictionary = collector.create_sample(999)
	_assert(_ok(first_sample_result), "Collector could not sample the first observation")
	var first_distribution: Dictionary = first_sample_result.get("details", {}).get("sample", {}).get("distributions", {}).get("first_observation_ms", {})
	_assert(int(first_distribution.get("count", 0)) == 1, "First observation disappeared before the sample window filled")
	_assert(is_equal_approx(float(first_distribution.get("min", 0.0)), 12.5), "First observation value mismatch")
	var collector_source: String = FileAccess.get_file_as_string("res://scripts/network/observability/network_telemetry_collector.gd")
	_assert(
		collector_source.contains("while values.size() > _sample_limit:\n\t\tvalues.pop_front()\n\t_samples.set(distribution_name, values)"),
		"Telemetry storage assignment is not outside the bounding loop"
	)

	for value in [10.0, 20.0, 30.0, 40.0]:
		_assert(_ok(collector.observe("rtt_ms", value)), "RTT observation failed")
	_assert(_error(collector.observe("RTT", 1.0)) == "INVALID_DISTRIBUTION_SAMPLE", "Collector accepted non-canonical distribution")
	_assert(_ok(collector.record_transport("player_input", "sent", 100)), "Sent channel sample failed")
	_assert(_ok(collector.record_transport("player_input", "received", 80)), "Received channel sample failed")
	_assert(_error(collector.record_transport("player_input", "dropped", 1)) == "INVALID_TRANSPORT_SAMPLE", "Collector accepted invalid direction")

	var sample_result: Dictionary = collector.create_sample(1000)
	_assert(_ok(sample_result), "Collector could not create a sample")
	var sample: Dictionary = sample_result.get("details", {}).get("sample", {})
	_assert(_ok(Sample.validate(sample)), "Generated telemetry sample is invalid")
	_assert(int(sample.get("counters", {}).get("packets_sent", 0)) == 2, "Counter value was not retained")
	_assert(int(sample.get("counters", {}).get("movement_results_suppressed", 0)) == 7, "Suppression counter was not retained")
	_assert(is_equal_approx(float(sample.get("gauges", {}).get("reliable_queue_depth", -1.0)), 4.0), "Gauge value was not retained")
	var rtt: Dictionary = sample.get("distributions", {}).get("rtt_ms", {})
	_assert(int(rtt.get("count", 0)) == 3, "Distribution window is not bounded")
	_assert(is_equal_approx(float(rtt.get("min", 0.0)), 20.0), "Bounded distribution retained stale sample")
	_assert(is_equal_approx(float(rtt.get("max", 0.0)), 40.0), "Distribution maximum mismatch")
	_assert(is_equal_approx(float(rtt.get("p50", 0.0)), 30.0), "Distribution p50 mismatch")
	_assert(is_equal_approx(float(rtt.get("p95", 0.0)), 39.0), "Distribution p95 mismatch")
	_assert(is_equal_approx(float(rtt.get("p99", 0.0)), 39.8), "Distribution p99 mismatch")
	var channel: Dictionary = sample.get("channels", {}).get("player_input", {})
	_assert(int(channel.get("packets_sent", 0)) == 1 and int(channel.get("bytes_sent", 0)) == 100, "Sent channel metrics mismatch")
	_assert(int(channel.get("packets_received", 0)) == 1 and int(channel.get("bytes_received", 0)) == 80, "Received channel metrics mismatch")
	_assert(String(sample.get("checksum", "")).length() == 64, "Telemetry sample checksum is missing")
	var mutated: Dictionary = sample.duplicate(true)
	mutated["gauges"]["reliable_queue_depth"] = 99.0
	_assert(_error(Sample.validate(mutated)) == "CHECKSUM_MISMATCH", "Telemetry tampering bypassed checksum")
	_assert(_ok(collector.reset_window()), "Collector window reset failed")
	var reset_sample: Dictionary = collector.create_sample(1001).get("details", {}).get("sample", {})
	_assert(Dictionary(reset_sample.get("distributions", {})).is_empty(), "Distribution window was not reset")
	_assert(int(reset_sample.get("counters", {}).get("packets_sent", 0)) == 2, "Window reset cleared cumulative counters")


func _test_condition_profiles() -> void:
	var document: Dictionary = _load_json("res://config/network/network-condition-presets.v1.json")
	_assert(not document.is_empty(), "Network condition preset document is missing")
	_assert(_ok(ConditionProfile.validate_document(document)), "Network condition preset document is invalid")
	var expected_ids: Array[String] = [
		"ASYMMETRIC", "AVERAGE_BROADBAND", "BAD_MOBILE", "EXTREME",
		"GOOD_BROADBAND", "LAG_SPIKE", "LOCAL", "MOBILE",
	]
	var actual_ids: Array[String] = []
	var local_profile: Dictionary = {}
	for profile_value in document.get("profiles", []):
		var profile: Dictionary = Dictionary(profile_value)
		actual_ids.append(String(profile.get("profile_id", "")))
		_assert(_ok(ConditionProfile.validate(profile)), "Preset is invalid: %s" % profile.get("profile_id", ""))
		_assert(String(profile.get("checksum", "")).length() == 64, "Preset checksum is missing: %s" % profile.get("profile_id", ""))
		if String(profile.get("profile_id", "")) == "LOCAL":
			local_profile = profile
	actual_ids.sort()
	_assert(actual_ids == expected_ids, "Required condition preset set changed")
	_assert(int(local_profile.get("outgoing_latency_max_ms", -1)) == 0, "LOCAL preset has outgoing latency")
	_assert(float(local_profile.get("packet_loss_percent", -1.0)) == 0.0, "LOCAL preset has packet loss")

	var invalid_range: Dictionary = local_profile.duplicate(true)
	invalid_range["outgoing_latency_min_ms"] = 10
	invalid_range["outgoing_latency_max_ms"] = 5
	invalid_range["checksum"] = ConditionProfile.compute_checksum(invalid_range)
	_assert(_error(ConditionProfile.validate(invalid_range)) == "INVALID_OUTGOING_LATENCY_RANGE", "Invalid latency range was accepted")
	var invalid_loss: Dictionary = local_profile.duplicate(true)
	invalid_loss["packet_loss_percent"] = 101.0
	invalid_loss["checksum"] = ConditionProfile.compute_checksum(invalid_loss)
	_assert(_error(ConditionProfile.validate(invalid_loss)) == "INVALID_PERCENTAGE", "Invalid packet loss was accepted")
	var duplicate_document: Dictionary = document.duplicate(true)
	duplicate_document["profiles"].append(local_profile.duplicate(true))
	_assert(_error(ConditionProfile.validate_document(duplicate_document)) == "DUPLICATE_PROFILE_ID", "Duplicate preset ID was accepted")


func _test_baseline_and_documentation() -> void:
	var roadmap: Dictionary = _load_json("res://config/network/network-experience-roadmap.v1.json")
	var preparation: Dictionary = _load_json("res://config/network/nx0-observability-baseline-preparation.v1.json")
	_assert(String(roadmap.get("current_stage", "")) == "NX0_PREPARATION", "Network experience roadmap current stage mismatch")
	_assert(String(roadmap.get("base_commit", "")) == "69bd7fc", "Network experience roadmap base commit mismatch")
	_assert(roadmap.get("phases", []).size() == 10, "NX roadmap does not contain NX0 through NX9")
	_assert(String(preparation.get("checkpoint", "")) == "v16.10.7-network-nx0-observability-preparation", "NX0 preparation checkpoint mismatch")
	_assert(not bool(preparation.get("runtime_behavior_changed", true)), "Preparation claims production behavior changed")
	_assert(not bool(preparation.get("production_transport_wrapped", true)), "Preparation claims simulator is attached to ENet")
	_assert(preparation.get("confirmed_baseline_findings", []).size() >= 6, "Preparation manifest omits baseline findings")

	var server_source: String = FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
	var client_source: String = FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
	var enet_source: String = FileAccess.get_file_as_string("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
	_assert(server_source.contains("var previous_ms := int(_peer_last_input_ms.get(peer_id, now_ms - 50))"), "M7 packet-arrival movement baseline changed without roadmap update")
	_assert(server_source.contains("authority_intent[\"delta_seconds\"] = clampf(float(now_ms - previous_ms) / 1000.0"), "M7 movement delta baseline probe is missing")
	_assert(server_source.contains("_send_result(peer_id, operation_id, \"PLAYER_INPUT\", result)"), "M7 successful movement result baseline changed")
	_assert(server_source.contains("_broadcast_delta(result.get(\"details\", {}).get(\"delta\", {}))"), "M7 movement delta broadcast baseline changed")
	_assert(server_source.contains("_broadcast_snapshot(\"PLAYER_INPUT_SIMULATED\")"), "M7 per-input full snapshot baseline changed")
	_assert(server_source.contains("const M7_MOVEMENT_CHECKPOINT_INTERVAL_MS := 1500"), "M7 movement persistence interval baseline changed")
	_assert(client_source.contains("_async_command_results += 1"), "M7 async result baseline probe is missing")
	_assert(client_source.contains("func submit_movement_intent_nonblocking"), "M7 nonblocking movement path is missing")
	_assert(enet_source.contains("const MAX_CHANNELS: int = 3"), "ENet channel baseline changed without NX2 update")

	var roadmap_doc: String = FileAccess.get_file_as_string("res://docs/network/NETWORK_EXPERIENCE_ROADMAP_NX0_NX9_RU.md")
	var nx0_doc: String = FileAccess.get_file_as_string("res://docs/network/NX0_OBSERVABILITY_BASELINE_PREPARATION_RU.md")
	_assert(roadmap_doc.contains("NX4 + NX5") and roadmap_doc.contains("NX6"), "Roadmap does not define playable and gameplay gates")
	_assert(roadmap_doc.contains("reliable application message") and roadmap_doc.contains("retransmission"), "Roadmap omits reliable fault-injection caveat")
	_assert(nx0_doc.contains("production M3/M7 runtime: unchanged") or nx0_doc.contains("Поведение production runtime"), "NX0 preparation scope is unclear")
	_assert(nx0_doc.contains("network_transport_boundary_v2.gd") and nx0_doc.contains("enet_multi_peer_transport_port.gd"), "NX0 integration map omits transport points")
	_assert(
		nx0_doc.contains("session-id/<public-id>") and nx0_doc.contains("sha256/<64-lowercase-hex>") and nx0_doc.contains("Raw bearer token"),
		"NX0 documentation does not define enforceable safe session_token formats"
	)

	var focused_sh: String = FileAccess.get_file_as_string("res://RUN_NX0_NETWORK_EXPERIENCE_PREPARATION_TESTS.sh")
	var focused_ps1: String = FileAccess.get_file_as_string("res://RUN_NX0_NETWORK_EXPERIENCE_PREPARATION_TESTS.ps1")
	var network_runner: String = FileAccess.get_file_as_string("res://RUN_NETWORK_CONTRACT_TESTS.ps1")
	var world_runner: String = FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	_assert(focused_sh.contains("test_nx0_network_experience_preparation.gd"), "Linux focused runner omits NX0 preparation test")
	_assert(focused_ps1.contains("test_nx0_network_experience_preparation.gd"), "PowerShell focused runner omits NX0 preparation test")
	_assert(not focused_ps1.contains("$env:HOME"), "PowerShell focused runner rewrites HOME")
	_assert(not focused_ps1.contains("@(\"HOME\","), "PowerShell focused runner snapshots HOME for mutation")
	_assert(network_runner.contains("test_nx0_network_experience_preparation.gd"), "Network regression omits NX0 preparation test")
	_assert(world_runner.contains("test_nx0_network_experience_preparation.gd"), "World regression omits NX0 preparation test")


func _mismatch(expected: Dictionary, field: String, replacement: String) -> String:
	var actual: Dictionary = expected.duplicate(true)
	actual[field] = replacement
	actual["checksum"] = Fingerprint.compute_checksum(actual)
	return _error(Fingerprint.compare(expected, actual))


func _load_json(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var value = JSON.parse_string(text)
	return Dictionary(value) if value is Dictionary else {}


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
		print("NX0 network experience preparation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NX0 network experience preparation: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
