extends SceneTree

const PressureBuffer = preload("res://scripts/runtime/networked_gameplay/m3/live2_pressure_input_buffer.gd")
const LegacyBuffer = preload("res://scripts/network/simulation/fixed_tick_input_buffer.gd")
const Diagnostics = preload("res://scripts/runtime/networked_gameplay/m3/live2_bounded_diagnostics.gd")
const EarthPresenter = preload("res://scripts/app/earth_m3_remote_spectator_presenter.gd")
const LiveServer = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const MovementService = preload("res://scripts/runtime/networked_gameplay/services/player_movement_service.gd")
const PlayerSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const CompactSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const ProtocolFrame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const V0P4EarthOutpostAuthority = preload("res://scripts/construction/mvp/v0_p4_mvp_earth_outpost_authority.gd")
const ConstructionStagePlanner = preload("res://scripts/construction/build/construction_stage_transaction_planner.gd")

class FakeResultService:
	extends RefCounted
	var received_result: Dictionary = {}
	func create_targeted_command_result(_message: String, _operation: String, result: Dictionary) -> Dictionary:
		received_result = result.duplicate(true)
		return {"status": "REJECTED", "error_code": result.get("error_code", ""), "payload": result.get("details", {}), "checksum": "fixture"}

class ServerProbe:
	extends LiveServer
	var sent: Array[Dictionary] = []
	func _last_processed_input_sequence(_logical_id: String) -> int:
		return 0
	func _send_on_channel(peer_id: String, message_type: String, data: Dictionary, channel: String, delivery_mode: String) -> bool:
		sent.append({"peer": peer_id, "type": message_type, "data": data.duplicate(true), "channel": channel, "delivery": delivery_mode})
		return true

class FakeP4CanonicalGraph:
	extends RefCounted
	func create_snapshot() -> Dictionary:
		return {"items": [], "inventories": {}, "revision": 0, "tick": 0, "checksum": ""}
	func validate_snapshot(_snapshot: Dictionary) -> Dictionary:
		return {"success": true, "error_code": ""}
	func export_durable_state() -> Dictionary:
		return {"schema": "test.fake_p4_durable.v1"}
	func restore_durable_state(_state: Dictionary) -> Dictionary:
		return {"success": true, "error_code": ""}
	func export_replay_state() -> Dictionary:
		return {"schema": "test.fake_p4_replay.v1"}
	func restore_replay_state(_state: Dictionary) -> Dictionary:
		return {"success": true, "error_code": ""}
	func preflight_server_construction_consume(_operation_id, _player_id, _allocations, _revision, _tick, _checksum, _plan_checksum) -> Dictionary:
		return {"success": true, "error_code": ""}
	func apply_server_construction_consume(_operation_id, _player_id, _allocations, _revision, _tick, _checksum, _plan_checksum) -> Dictionary:
		return {"success": true, "error_code": ""}

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pressure_buffer()
	_test_diagnostics()
	_test_production_wiring()
	_test_v0_p4_restart_build_plan_bootstrap()
	_test_cardinal_movement_wire_stability()
	_test_render_sample_isolation()
	for failure in failures:
		push_error(failure)
	print("LIVE2 R3 presentation/pressure/diagnostics: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _input_record(sequence: int, move_x: float = 1.0, jump: bool = false) -> Dictionary:
	return {
		"input_sequence": sequence,
		"operation_id": "operation/r3/input/%d" % sequence,
		"client_tick": sequence,
		"intent": {"move_x": move_x, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0, "sprint": false, "jump_pressed": jump, "delta_seconds": 1.0 / 60.0},
	}


func _test_pressure_buffer() -> void:
	var buffer = PressureBuffer.new()
	_check(bool(buffer.configure().get("success", false)), "pressure buffer configured")
	for sequence in range(1, 1201):
		var queued: Dictionary = buffer.enqueue(_input_record(sequence), 1)
		_check(bool(queued.get("success", false)), "repeated hold accepted under pressure")
		_check(buffer.get_pending_count() <= PressureBuffer.PRESSURE_HIGH_WATER, "identical holds remain bounded")
	_check(int(buffer.get_report().get("pressure_coalesced", 0)) > 0, "pressure path exercised")
	_check(bool(buffer.enqueue(_input_record(1201, 0.0), 1).get("success", false)), "stop transition accepted")
	var last: Dictionary = {}
	for tick in range(2, 40):
		last = buffer.consume_for_tick(tick)
	_check(int(last.get("details", {}).get("input_sequence", 0)) == 1201, "newest stop acknowledged")
	_check(float(last.get("details", {}).get("intent", {}).get("move_x", -1.0)) == 0.0, "stop is not lost")

	# Distinct transitions and jump edges are not silently converted to latest-wins.
	buffer.configure()
	for sequence in range(1, 65):
		_check(bool(buffer.enqueue(_input_record(sequence, 1.0 if sequence % 2 else -1.0, true), 1).get("success", false)), "distinct transition admitted")
	var full: Dictionary = buffer.enqueue(_input_record(65, 0.0, true), 1)
	_check(String(full.get("error_code", "")) == "INPUT_QUEUE_FULL", "genuinely full transition queue still fails closed")
	_check(int(full.get("details", {}).get("capacity", 0)) == 64, "queue limit not increased")
	_check(buffer.get_pending_count() == 64, "failed enqueue preserves bounded queue")
	var edges := 0
	for tick in range(2, 66):
		var consumed: Dictionary = buffer.consume_for_tick(tick)
		if bool(consumed.get("details", {}).get("jump_edge", false)):
			edges += 1
	_check(edges == 64, "every distinct jump edge survives")

	buffer.configure()
	for sequence in range(1, 17):
		buffer.enqueue(_input_record(sequence), 1)
	var before := buffer.get_pending_count()
	var invalid: Dictionary = buffer.enqueue(_input_record(9000), 1)
	_check(not bool(invalid.get("success", false)), "future sequence rejected")
	_check(buffer.get_pending_count() == before, "invalid input cannot trigger compaction")
	var duplicate: Dictionary = buffer.enqueue(_input_record(16), 1)
	_check(bool(duplicate.get("details", {}).get("redundant", false)), "duplicate stays redundant")
	_check(buffer.get_pending_count() == before, "duplicate cannot trigger compaction")

	var legacy = LegacyBuffer.new()
	legacy.configure()
	for sequence in range(1, 65):
		legacy.enqueue(_input_record(sequence), 1)
	_check(String(legacy.enqueue(_input_record(65), 1).get("error_code", "")) == "INPUT_QUEUE_FULL", "legacy NX3 policy is unchanged")


func _test_diagnostics() -> void:
	var diagnostics = Diagnostics.new()
	var admitted := 0
	for index in range(100):
		var result: Dictionary = diagnostics.record_rejection({
			"command_type": "item.place", "error_code": "E%d" % index,
			"operation_id": "operation/r3/%d\nINJECTED" % index,
			"player_id": "a", "payload": {"secret": "DO_NOT_LOG"},
			"queue": {"pending": 64, "secret": "DO_NOT_LOG"},
		}, 100)
		if bool(result.get("should_log", false)):
			admitted += 1
	var report: Dictionary = diagnostics.get_report()
	_check(admitted == Diagnostics.LOGS_PER_WINDOW, "logging rate bounded globally")
	_check(report.get("recent_rejections", []).size() == Diagnostics.MAX_RECORDS, "diagnostic ring bounded")
	_check(report.get("reason_counts", {}).size() <= Diagnostics.MAX_REASON_BUCKETS, "reason cardinality bounded")
	_check(not JSON.stringify(report).contains("DO_NOT_LOG"), "payload and unapproved keys never retained")
	var latest: Dictionary = report.get("recent_rejections", []).back()
	_check(not String(latest.get("operation_id", "")).contains("\n"), "log text is single-line")
	var reopened: Dictionary = diagnostics.record_rejection({"error_code": "NEXT"}, 1200)
	_check(bool(reopened.get("should_log", false)), "logging window reopens")
	_check(int(reopened.get("entry", {}).get("suppressed_since_last_log", 0)) == 92, "suppressed records accounted")
	diagnostics.observe_handler("CONSTRUCTION_COMMAND", 1200.0)
	_check(float(diagnostics.get_report().get("max_handler_ms", 0.0)) == 1200.0, "placement stall duration observable")


func _test_production_wiring() -> void:
	var server = ServerProbe.new()
	server._v0_p4_composition_report = {"enabled": true}
	var buffer = server._ensure_input_buffer("peer/r3/a", "a")
	_check(buffer is PressureBuffer, "live Earth uses pressure buffer")
	_check(server._ensure_input_buffer("peer/r3/a", "a") == buffer, "one buffer per peer, no second authority")
	server._peer_to_player["peer/r3/a"] = "a"
	var service = FakeResultService.new()
	server._service = service
	var rejection := {"success": false, "error_code": "INPUT_QUEUE_FULL", "details": {"pending": 64}}
	var sent: bool = server._send_result("peer/r3/a", "operation/r3/test", "PLAYER_INPUT", rejection)
	_check(sent, "rejection still delivered")
	_check(service.received_result == rejection, "observer does not rewrite canonical result")
	_check(server.sent.size() == 1, "no duplicate result publication")
	_check(int(server._live2_diagnostics.get_report().get("total_rejections_observed", 0)) == 1, "real server result path records cause")
	server.free()


func _test_v0_p4_restart_build_plan_bootstrap() -> void:
	var repository_root := "user://live3-p4-restart-regression/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var canonical_graph = FakeP4CanonicalGraph.new()
	var first: Dictionary = V0P4EarthOutpostAuthority.create_gateway(
		canonical_graph,
		"authority/live3-restart-regression",
		1,
		repository_root
	)
	_check(bool(first.get("success", false)), "P4 initial gateway bootstrap succeeds")
	if not bool(first.get("success", false)):
		return
	var first_details: Dictionary = first.get("details", {})
	var first_adapter = first_details.get("authoritative_adapter")
	var first_registry = first_adapter.get("_items")
	var base_plan: Dictionary = V0P4EarthOutpostAuthority._build_plan(first_registry)
	var planned: Dictionary = ConstructionStagePlanner.build_stage_transaction_plan(
		base_plan,
		0,
		"operation/live3/restart-regression/stage-0"
	)
	_check(bool(planned.get("success", false)), "P4 stage-0 transaction plan builds before restart")
	if not bool(planned.get("success", false)):
		return
	var applied: Dictionary = first_adapter.apply_plan(planned.get("transaction_plan", {}))
	_check(bool(applied.get("success", false)), "P4 stage-0 authoritative commit persists before restart")
	if not bool(applied.get("success", false)):
		return
	var foundation: Dictionary = first_adapter.get_item_projection(V0P4EarthOutpostAuthority.FOUNDATION_ITEM_ID)
	_check(
		String(foundation.get("relation", {}).get("kind", "")) == "ATTACHMENT",
		"P4 recovered fixture contains an attached completed foundation"
	)

	var reopened: Dictionary = V0P4EarthOutpostAuthority.create_gateway(
		canonical_graph,
		"authority/live3-restart-regression",
		1,
		repository_root
	)
	_check(bool(reopened.get("success", false)), "P4 gateway reopens same M0 after a completed stage")
	if not bool(reopened.get("success", false)):
		return
	var reopened_gateway = reopened.get("details", {}).get("gateway")
	var reopened_executor = reopened_gateway.get("_executor")
	var reopened_build = reopened_executor.get("_build_process")
	var ghost: Dictionary = reopened_build.get_ghost_projection(V0P4EarthOutpostAuthority.BUILD_PLAN_ID)
	_check(
		int(ghost.get("completed_stage_count", -1)) == 1,
		"P4 reopened build plan reconciles completed stage instead of rebuilding sources from ATTACHMENT state"
	)
	var next_stage: Dictionary = reopened_build.get_stage_requirements(V0P4EarthOutpostAuthority.BUILD_PLAN_ID, 1)
	_check(
		int(next_stage.get("stage_index", -1)) == 1
		and Array(next_stage.get("part_ids", [])).size() == 4,
		"P4 restart remains ready to continue with stage 1"
	)


func _test_cardinal_movement_wire_stability() -> void:
	var movement = MovementService.new()
	var record := {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"transport_session_id": "transport-session/m3/a/cardinal",
		"ownership_epoch": 1,
		"connected": true,
		"position": {"x": -5.0, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
		"inventory": [],
		"last_input_sequence": 0,
		"state_revision": 1,
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}
	var moved: Dictionary = movement.apply_fixed_tick(record, 1, {
		"move_x": 0.0,
		"move_z": 1.0,
		"look_yaw": -PI / 2.0,
		"look_pitch": 0.0,
		"sprint": false,
		"jump_pressed": false,
	}, 1.0 / 60.0)
	_check(bool(moved.get("success", false)), "cardinal fixed movement accepted")
	if not bool(moved.get("success", false)):
		return
	var player: Dictionary = moved.get("details", {}).get("player", {})
	_check(float(player.get("velocity", {}).get("z", 1.0)) == 0.0,
		"cardinal movement removes sub-epsilon velocity residue")
	_check(float(player.get("position", {}).get("z", 1.0)) == 0.0,
		"cardinal movement keeps orthogonal position exactly canonical zero")

	var snapshot: Dictionary = PlayerSnapshot.create(
		"simulation/earth", 1, 2, 100, "region/earth", [player],
		{"item_id": "item/shared/beacon/1", "available": true,
			"owner_player_entity_id": "", "revision": 0}
	)
	_check(bool(PlayerSnapshot.validate(snapshot).get("success", false)),
		"cardinal movement produces a valid canonical gameplay snapshot")
	var compact_result: Dictionary = CompactSnapshot.encode(snapshot)
	_check(bool(compact_result.get("success", false)),
		"cardinal movement snapshot compact-encodes")
	if not bool(compact_result.get("success", false)):
		return
	var compact: Dictionary = compact_result.get("details", {}).get("snapshot", {})
	var frame: Dictionary = ProtocolFrame.create(
		"frame/live2-r3/cardinal-wire",
		"transport-session/live2-r3/cardinal-wire",
		1,
		"SNAPSHOT",
		"UNRELIABLE_SEQUENCED",
		"planet_simulator.m3_process_message.v1",
		{
			"type": "COMPACT_GAMEPLAY_SNAPSHOT",
			"reason": "CARDINAL_WIRE_REGRESSION",
			"server_sent_at_ms": 1000,
			"snapshot": compact,
		}
	)
	var encoded: Dictionary = ProtocolFrame.encode(frame)
	_check(bool(encoded.get("success", false)), "cardinal compact frame encodes")
	if not bool(encoded.get("success", false)):
		return
	var decoded: Dictionary = ProtocolFrame.decode(encoded.get("details", {}).get("packet", PackedByteArray()))
	_check(bool(decoded.get("success", false)),
		"cardinal compact frame survives JSON wire round-trip without payload checksum drift")


func _test_render_sample_isolation() -> void:
	var wrapper = EarthPresenter.new()
	var record := {
		"logical_player_id": "b", "player_entity_id": "player/b",
		"transport_session_id": "transport-session/r3/b", "ownership_epoch": 1,
		"connected": true, "position": {"x": 10.0, "y": 2.0, "z": 5.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}, "inventory": [],
		"last_input_sequence": 1, "state_revision": 1,
		"orientation_yaw": 0.0, "flashlight_enabled": false,
	}
	var snapshot := {"server_tick": 10, "snapshot_revision": 1, "authority_epoch": 1}
	var result: Dictionary = wrapper.setup(record, snapshot, Callable(self, "_map_position"))
	_check(bool(result.get("success", false)), "Earth presenter accepts real NX5 record")
	if bool(result.get("success", false)):
		var sampled: Vector3 = wrapper._delegate.get_presented_position()
		var projected: Vector3 = wrapper.position
		for _index in range(30):
			# No new delegate sample: reading its visual offset as state used to
			# recenter the logical remote position at the origin here.
			wrapper._process(0.0)
			_check(wrapper._delegate.get_presented_position().is_equal_approx(sampled), "visual offset does not corrupt logical sample")
			_check(wrapper.position.is_equal_approx(projected), "remote projection stable without new packet")
		_check(wrapper.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "no second physics interpolation of render samples")
		wrapper._process(1.2)
		_check(int(wrapper.get_report().get("long_render_frames", 0)) == 1, "render stall measured")
		_check(int(record.get("state_revision", 0)) == 1, "presentation does not mutate source record")
	wrapper.free()


func _map_position(x: float, z: float) -> Vector3:
	return Vector3(x, 100.0, z)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
