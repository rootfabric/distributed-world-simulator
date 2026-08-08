extends SceneTree

const ServerRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const ReplicaStore = preload("res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd")
const PlayerSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const RemotePresenter = preload("res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd")
const RuntimeFix8 = preload("res://scripts/world/testing/playground_view_relative_runtime_fix8.gd")

var assertions: int = 0
var failures: Array[String] = []
var emitted_remote_snapshots: int = 0
var emitted_conflict_hints: int = 0
var emitted_last_snapshot: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_standalone_ack_wire_decoding()
	_test_validated_wire_presentation_lane_survives_same_revision_conflict()
	_test_remote_presenter_accepts_newer_tick_at_same_outer_revision()
	_test_world_exact_snapshot_context_contract()
	_test_server_ack_fallback_source_contract()
	_finish()


func _test_standalone_ack_wire_decoding() -> void:
	var runtime = ClientRuntime.new()
	var ack: Dictionary = runtime.call(
		"_fix10_extract_prediction_ack",
		{
			"type": "PREDICTION_ACK",
			"snapshot_server_tick": 777,
			"prediction_ack": [
				12, 700, 704,
				1.0, 2.0, 3.0,
				4.0, 5.0, 6.0,
				0.25, 19,
			],
		},
		"PREDICTION_ACK"
	)
	_assert(not ack.is_empty(), "FIX10 fix3 standalone compact ACK decodes")
	_assert(int(ack.get("input_sequence", 0)) == 12, "FIX10 fix3 standalone ACK preserves sequence")
	_assert(int(ack.get("client_tick", 0)) == 700, "FIX10 fix3 standalone ACK preserves client tick")
	_assert(int(ack.get("transport_snapshot_server_tick", 0)) == 777, "FIX10 fix3 standalone ACK carries snapshot clock")
	var report: Dictionary = runtime.get_report()
	var transport: Dictionary = Dictionary(report.get("fix10_prediction_ack_transport", {}))
	_assert(
		String(transport.get("ack_fallback_policy", ""))
		== "SEPARATE_TELEMETRY_CHANNEL_WHEN_SNAPSHOT_ACK_OMITTED_V1",
		"FIX10 fix3 client exposes standalone ACK fallback policy"
	)
	runtime.free()


func _test_validated_wire_presentation_lane_survives_same_revision_conflict() -> void:
	var runtime = ClientRuntime.new()
	runtime._replica = ReplicaStore.new()
	var current: Dictionary = _snapshot(5, 100, 0.0, 2)
	var incoming: Dictionary = _snapshot(5, 103, 0.6, 3)
	_assert(bool(runtime._replica.accept_snapshot(current).get("success", false)), "FIX10 fix3 canonical conflict fixture installs")
	runtime.remote_presentation_snapshot.connect(_on_remote_presentation_snapshot)
	runtime.call("_fix10_fix3_publish_remote_presentation_snapshot", incoming, "FIXTURE")
	_assert(emitted_remote_snapshots == 1, "FIX10 fix3 publishes contract-valid newer wire snapshot before canonical acceptance")
	_assert(emitted_conflict_hints == 1, "FIX10 fix3 surfaces same-revision semantic conflict without hiding it")
	_assert(int(emitted_last_snapshot.get("server_tick", -1)) == 103, "FIX10 fix3 presentation lane preserves exact incoming server tick")
	var transport: Dictionary = Dictionary(runtime.get_report().get("fix10_fix3_remote_presentation_transport", {}))
	_assert(int(transport.get("same_revision_semantic_conflicts", 0)) == 1, "FIX10 fix3 conflict telemetry increments")
	var conflict: Dictionary = Dictionary(transport.get("last_same_revision_conflict", {}))
	_assert(int(conflict.get("current_server_tick", -1)) == 100, "FIX10 fix3 conflict telemetry preserves current tick")
	_assert(int(conflict.get("incoming_server_tick", -1)) == 103, "FIX10 fix3 conflict telemetry preserves incoming tick")

	var stale: Dictionary = _snapshot(5, 99, -1.0, 1)
	runtime.call("_fix10_fix3_publish_remote_presentation_snapshot", stale, "STALE_FIXTURE")
	_assert(emitted_remote_snapshots == 1, "FIX10 fix3 wire lane never walks server clock backwards")
	transport = Dictionary(runtime.get_report().get("fix10_fix3_remote_presentation_transport", {}))
	_assert(int(transport.get("stale_suppressed", 0)) >= 1, "FIX10 fix3 stale presentation suppression is observable")
	runtime.free()


func _test_remote_presenter_accepts_newer_tick_at_same_outer_revision() -> void:
	var presenter = RemotePresenter.new()
	get_root().add_child(presenter)
	var first: Dictionary = _player("b", 0.0, 2)
	var second: Dictionary = _player("b", 0.6, 3)
	var setup_result: Dictionary = presenter.setup(first, {
		"server_tick": 100,
		"snapshot_revision": 5,
		"authority_epoch": 1,
	})
	_assert(bool(setup_result.get("success", false)), "FIX10 fix3 remote presenter fixture sets up")
	var applied: Dictionary = presenter.apply_replica(second, false, {
		"server_tick": 103,
		"snapshot_revision": 5,
		"authority_epoch": 1,
	})
	_assert(bool(applied.get("success", false)), "FIX10 fix3 remote presenter accepts newer server tick at same outer revision")
	var report: Dictionary = presenter.get_report()
	var interpolation: Dictionary = Dictionary(report.get("interpolation", {}))
	_assert(int(interpolation.get("latest_server_tick", -1)) == 103, "FIX10 fix3 presenter advances exact source clock")
	_assert(int(report.get("interpolation_failures", 0)) == 0, "FIX10 fix3 presentation continuity introduces no interpolator failure")
	presenter.free()


func _test_world_exact_snapshot_context_contract() -> void:
	var world = RuntimeFix8.new()
	var report: Dictionary = world.get_fix10_fix3_remote_continuity_report()
	_assert(
		String(report.get("policy", ""))
		== "EXACT_SNAPSHOT_CONTEXT_PRESENTATION_CONTINUITY_V1",
		"FIX10 fix3 world exposes remote continuity policy"
	)
	world.free()
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/world/testing/playground_view_relative_runtime_fix8.gd"
	)
	_assert(source.contains("remote_presentation_snapshot"), "FIX10 fix3 world subscribes to presentation-only wire lane")
	_assert(source.contains("presenter.setup(record, snapshot_context)"), "FIX10 fix3 presenter setup receives exact snapshot context")
	_assert(source.contains("presenter.apply_replica(record, false, snapshot_context)"), "FIX10 fix3 presenter update receives exact snapshot context")
	_assert(source.contains("[fix10_fix3_remote]"), "FIX10 fix3 manual stress emits remote interpolation health")


func _test_server_ack_fallback_source_contract() -> void:
	var server = ServerRuntime.new()
	_assert(
		String(ServerRuntime.FIX10_FIX3_ACK_FALLBACK_POLICY)
		== "SEPARATE_TELEMETRY_CHANNEL_WHEN_SNAPSHOT_ACK_OMITTED_V1",
		"FIX10 fix3 server exposes ACK fallback policy"
	)
	_assert(
		server._fix10_unreliable_budget_decision(
			ServerRuntime.FIX10_UNRELIABLE_SAFE_PACKET_BYTES + 1,
			true
		) == ServerRuntime.FIX10_UNRELIABLE_DECISION_RETRY_WITHOUT_ACK,
		"FIX10 fix3 preserves fix2 snapshot MTU decision"
	)
	server.free()
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"
	)
	_assert(source.contains("RealtimeChannelPolicy.TELEMETRY"), "FIX10 fix3 standalone ACK uses independent ENet channel")
	_assert(source.contains("\"PREDICTION_ACK\""), "FIX10 fix3 server emits standalone prediction ACK message")
	_assert(source.contains("_fix10_fix3_send_standalone_prediction_ack"), "FIX10 fix3 MTU omission routes to standalone ACK sender")
	_assert(source.contains("packet_bytes > FIX10_UNRELIABLE_SAFE_PACKET_BYTES"), "FIX10 fix3 standalone unreliable ACK is preflight bounded")


func _on_remote_presentation_snapshot(
	snapshot: Dictionary,
	_source: String,
	canonical_conflict_hint: bool
) -> void:
	emitted_remote_snapshots += 1
	if canonical_conflict_hint:
		emitted_conflict_hints += 1
	emitted_last_snapshot = snapshot.duplicate(true)


func _snapshot(revision: int, server_tick: int, remote_x: float, remote_state_revision: int) -> Dictionary:
	return PlayerSnapshot.create(
		"simulation/m3/dedicated",
		1,
		revision,
		server_tick,
		"region/m1/playable",
		[
			_player("a", -2.0, 2),
			_player("b", remote_x, remote_state_revision),
		],
		{
			"item_id": "item/shared/beacon/1",
			"available": true,
			"owner_player_entity_id": "",
			"revision": 0,
		}
	)


func _player(logical_id: String, x: float, state_revision: int) -> Dictionary:
	return {
		"logical_player_id": logical_id,
		"player_entity_id": "player/%s" % logical_id,
		"transport_session_id": "transport-session/m3/%s/fix10-fix3" % logical_id,
		"ownership_epoch": 1,
		"connected": true,
		"position": {"x": x, "y": 0.0, "z": 0.0},
		"velocity": {"x": 6.0 if logical_id == "b" else 0.0, "y": 0.0, "z": 0.0},
		"inventory": [],
		"last_input_sequence": state_revision,
		"state_revision": state_revision,
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("FIX10 fix3 assertion failed: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 sequence-aware reconciliation FIX10 fix3: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("M7 sequence-aware reconciliation FIX10 fix3: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
