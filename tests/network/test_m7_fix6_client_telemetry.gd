extends SceneTree

const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_client_runtime_telemetry_is_throttled()
	_test_process_convergence_uses_captured_authority_checksum()
	_finish()


func _test_client_runtime_telemetry_is_throttled() -> void:
	var runtime_script: Script = ClientRuntime
	_assert(runtime_script.can_instantiate(), "FIX6 graphical client runtime no longer instantiates")
	var runtime = runtime_script.new()
	var report: Dictionary = runtime.get_report()
	var foundation: Dictionary = Dictionary(report.get("client_realtime_foundation", {}))
	_assert(
		String(foundation.get("telemetry_hot_path_policy", "")) == "RING_BUFFER_OBSERVE_THROTTLED_PEER_STATS_V1",
		"FIX6 graphical client telemetry policy missing"
	)
	_assert(
		int(foundation.get("peer_telemetry_interval_ms", 0)) >= 250,
		"graphical client still rebuilds transport peer statistics at frame rate"
	)
	_assert(
		float(foundation.get("process_max_duration_ms", -1.0)) >= 0.0,
		"graphical client process peak latency is not observable"
	)
	_assert(
		float(foundation.get("peer_telemetry_max_duration_ms", -1.0)) >= 0.0,
		"graphical client peer telemetry peak latency is not observable"
	)
	runtime.free()

	var source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
	)
	var update_start: int = source.find("func _update_runtime_telemetry()")
	var next_function: int = source.find("func _emit_prediction_health_if_due()", update_start)
	_assert(update_start >= 0 and next_function > update_start, "FIX6 graphical client telemetry override missing")
	if update_start >= 0 and next_function > update_start:
		var update_source := source.substr(update_start, next_function - update_start)
		var guard_pos: int = update_source.find("M7_CLIENT_PEER_TELEMETRY_INTERVAL_MS")
		var snapshot_pos: int = update_source.find("_boundary.get_snapshot()")
		_assert(
			guard_pos >= 0 and snapshot_pos > guard_pos,
			"graphical client transport snapshot is still built before the telemetry throttle"
		)
		_assert(
			update_source.contains("_fix6_peer_telemetry_skips += 1"),
			"graphical client telemetry throttle is not observable"
		)
	_assert(
		source.contains("client_process_max_duration_ms"),
		"PREDICTION_HEALTH does not expose graphical client process peak latency"
	)
	_assert(
		source.contains("peer_telemetry_max_duration_ms"),
		"PREDICTION_HEALTH does not expose graphical client peer telemetry peak latency"
	)


func _test_process_convergence_uses_captured_authority_checksum() -> void:
	var worker_source: String = FileAccess.get_file_as_string(
		"res://tools/runtime/m7_playable_network_client_camera_sync_fix.gd"
	)
	var preferred_start: int = worker_source.find("func _preferred_server_player_checksum")
	_assert(preferred_start >= 0, "FIX6 graphical process convergence checksum selector missing")
	if preferred_start < 0:
		return
	var preferred_source := worker_source.substr(preferred_start)
	var captured_pos: int = preferred_source.find("last_two_connected_checksum")
	var snapshot_pos: int = preferred_source.find("get(\"snapshot\"")
	_assert(
		captured_pos >= 0,
		"FIX6 graphical process does not use the server-captured two-peer authority checksum"
	)
	_assert(
		snapshot_pos > captured_pos,
		"FIX6 graphical process does not keep the stale READY snapshot checksum as a compatibility fallback"
	)
	_assert(
		worker_source.contains("func _wait_server_player_checksum(timeout_ms: int) -> bool"),
		"FIX6 graphical process does not override stale READY convergence waiting"
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("M7 FIX6 graphical client telemetry: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
