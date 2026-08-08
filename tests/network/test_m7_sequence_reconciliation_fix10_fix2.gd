extends SceneTree

const ServerRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_mtu_budget_contract()
	_test_source_composition()
	_finish()


func _test_mtu_budget_contract() -> void:
	var server = ServerRuntime.new()
	_assert(
		ServerRuntime.FIX10_UNRELIABLE_SAFE_PACKET_BYTES >= 1200
		and ServerRuntime.FIX10_UNRELIABLE_SAFE_PACKET_BYTES <= 1350,
		"FIX10 fix2 uses conservative ENet unreliable packet budget"
	)
	_assert(
		server._fix10_unreliable_budget_decision(1200, true)
		== ServerRuntime.FIX10_UNRELIABLE_DECISION_SEND,
		"FIX10 fix2 sends an in-budget snapshot with ack"
	)
	_assert(
		server._fix10_unreliable_budget_decision(
			ServerRuntime.FIX10_UNRELIABLE_SAFE_PACKET_BYTES + 1,
			true
		) == ServerRuntime.FIX10_UNRELIABLE_DECISION_RETRY_WITHOUT_ACK,
		"FIX10 fix2 retries an oversized snapshot without optional ack"
	)
	_assert(
		server._fix10_unreliable_budget_decision(
			ServerRuntime.FIX10_UNRELIABLE_SAFE_PACKET_BYTES + 1,
			false
		) == ServerRuntime.FIX10_UNRELIABLE_DECISION_DROP,
		"FIX10 fix2 drops an oversized no-ack realtime snapshot instead of fragmenting it"
	)


func _test_source_composition() -> void:
	var server_source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"
	)
	_assert(
		server_source.contains("OPTIONAL_ACK_OMISSION_THEN_DROP_OVERSIZE_V1"),
		"FIX10 fix2 MTU policy source missing"
	)
	_assert(
		server_source.contains("NetworkUtilsFix10.canonical_json(frame)"),
		"FIX10 fix2 does not measure the exact canonical frame bytes used by the transport boundary"
	)
	_assert(
		server_source.contains("payload.erase(\"prediction_ack\")"),
		"FIX10 fix2 optional ack omission path missing"
	)
	_assert(
		server_source.contains("FIX10_UNRELIABLE_FRAME_EXCEEDS_SAFE_MTU"),
		"FIX10 fix2 oversized no-ack prevention path missing"
	)
	_assert(
		server_source.contains("_boundary.send_to_peer(peer_id, frame)"),
		"FIX10 fix2 must preflight the exact frame before transport queue commit"
	)
	_assert(
		server_source.find("_fix10_unreliable_budget_decision")
		< server_source.find("_boundary.send_to_peer(peer_id, frame)"),
		"FIX10 fix2 MTU decision must precede physical queue/send"
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("FIX10 fix2 assertion failed: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 sequence-aware reconciliation FIX10 fix2: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("M7 sequence-aware reconciliation FIX10 fix2: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
