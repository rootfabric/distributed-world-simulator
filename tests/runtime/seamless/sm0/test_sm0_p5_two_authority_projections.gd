extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const ProjectionContract = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_contract.gd")
const ProjectionStore = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_store.gd")
const P5Server = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_server_node.gd")

const CONTROL_A := 25880
const CONTROL_B := 25881

var _assertions := 0
var _failures: Array[String] = []


func _init() -> void:
	_run()


func _run() -> void:
	_test_projection_contract_and_store()

	var server_a = P5Server.new()
	var server_b = P5Server.new()
	root.add_child(server_a)
	root.add_child(server_b)

	var setup_a: Dictionary = server_a.setup({
		"authority_id": Contracts.AUTHORITY_A,
		"zone_id": Contracts.ZONE_A,
		"local_player_id": "a",
		"control_port": CONTROL_A,
		"peer_control_port": CONTROL_B,
	})
	var setup_b: Dictionary = server_b.setup({
		"authority_id": Contracts.AUTHORITY_B,
		"zone_id": Contracts.ZONE_B,
		"local_player_id": "b",
		"control_port": CONTROL_B,
		"peer_control_port": CONTROL_A,
	})
	_assert(bool(setup_a.get("success", false)), "Authority A P5 server starts")
	_assert(bool(setup_b.get("success", false)), "Authority B P5 server starts")
	if not bool(setup_a.get("success", false)) or not bool(setup_b.get("success", false)):
		server_a.shutdown(1, "setup-failed")
		server_b.shutdown(1, "setup-failed")
		_finish()
		return

	server_a.publish_now_for_tests()
	server_b.publish_now_for_tests()
	await _wait_for_projection_pair(server_a, server_b, 2000)

	var status_a: Dictionary = server_a.status_for_tests()
	var status_b: Dictionary = server_b.status_for_tests()
	var canonical_a: Dictionary = Dictionary(status_a.get("canonical_player", {}))
	var canonical_b: Dictionary = Dictionary(status_b.get("canonical_player", {}))
	var projection_b_on_a: Dictionary = Dictionary(status_a.get("peer_projection", {}))
	var projection_a_on_b: Dictionary = Dictionary(status_b.get("peer_projection", {}))

	_assert(String(canonical_a.get("logical_player_id", "")) == "a", "A owns canonical player a")
	_assert(String(canonical_b.get("logical_player_id", "")) == "b", "B owns canonical player b")
	_assert(int(status_a.get("writer_count", 0)) == 1, "A has exactly one canonical writer")
	_assert(int(status_b.get("writer_count", 0)) == 1, "B has exactly one canonical writer")
	_assert(String(projection_b_on_a.get("logical_player_id", "")) == "b", "A receives read-only projection of b")
	_assert(String(projection_a_on_b.get("logical_player_id", "")) == "a", "B receives read-only projection of a")
	_assert(bool(projection_b_on_a.get("read_only", false)), "b projection on A is explicitly read-only")
	_assert(bool(projection_a_on_b.get("read_only", false)), "a projection on B is explicitly read-only")
	_assert(not projection_b_on_a.has("transport_session_id"), "projection omits transport session identity")
	_assert(not projection_a_on_b.has("transport_session_id"), "projection omits transport session identity")

	var b_before_block := canonical_b.duplicate(true)
	var blocked_a_on_b: Dictionary = server_b.apply_move_for_tests({
		"logical_player_id": "a",
		"delta_x": 0.25,
		"delta_z": 0.0,
	})
	_assert(String(blocked_a_on_b.get("error_code", "")) == "SM0_P5_PROJECTION_READ_ONLY", "B cannot mutate projection of a")
	_assert(
		Dictionary(server_b.status_for_tests().get("canonical_player", {})) == b_before_block,
		"rejected projection mutation does not change B canonical player"
	)

	var a_before: Dictionary = Dictionary(server_a.status_for_tests().get("canonical_player", {}))
	var a_move: Dictionary = server_a.apply_move_for_tests({
		"logical_player_id": "a",
		"input_sequence": int(a_before.get("last_input_sequence", 0)) + 1,
		"delta_x": 0.25,
		"delta_z": 0.0,
	})
	_assert(bool(a_move.get("success", false)), "A mutates canonical player a")
	await _wait_for_projection_revision(
		server_b,
		"a",
		int(Dictionary(server_a.status_for_tests().get("canonical_player", {})).get("state_revision", 0)),
		2000
	)
	var a_after: Dictionary = Dictionary(server_a.status_for_tests().get("canonical_player", {}))
	var a_projected: Dictionary = Dictionary(server_b.status_for_tests().get("peer_projection", {}))
	_assert(int(a_projected.get("state_revision", 0)) == int(a_after.get("state_revision", -1)), "B observes newest canonical revision of a")
	_assert(Dictionary(a_projected.get("position", {})) == Dictionary(a_after.get("position", {})), "B projection position matches A canonical position")

	var blocked_b_on_a: Dictionary = server_a.apply_move_for_tests({
		"logical_player_id": "b",
		"delta_x": -0.25,
		"delta_z": 0.0,
	})
	_assert(String(blocked_b_on_a.get("error_code", "")) == "SM0_P5_PROJECTION_READ_ONLY", "A cannot mutate projection of b")

	var b_before: Dictionary = Dictionary(server_b.status_for_tests().get("canonical_player", {}))
	var b_move: Dictionary = server_b.apply_move_for_tests({
		"logical_player_id": "b",
		"input_sequence": int(b_before.get("last_input_sequence", 0)) + 1,
		"delta_x": -0.25,
		"delta_z": 0.0,
	})
	_assert(bool(b_move.get("success", false)), "B mutates canonical player b")
	await _wait_for_projection_revision(
		server_a,
		"b",
		int(Dictionary(server_b.status_for_tests().get("canonical_player", {})).get("state_revision", 0)),
		2000
	)
	var b_after: Dictionary = Dictionary(server_b.status_for_tests().get("canonical_player", {}))
	var b_projected: Dictionary = Dictionary(server_a.status_for_tests().get("peer_projection", {}))
	_assert(int(b_projected.get("state_revision", 0)) == int(b_after.get("state_revision", -1)), "A observes newest canonical revision of b")
	_assert(Dictionary(b_projected.get("position", {})) == Dictionary(b_after.get("position", {})), "A projection position matches B canonical position")

	_assert(int(server_a.status_for_tests().get("writer_count", 0)) == 1, "A remains one-writer after projection updates")
	_assert(int(server_b.status_for_tests().get("writer_count", 0)) == 1, "B remains one-writer after projection updates")

	server_a.shutdown(0, "test-complete")
	server_b.shutdown(0, "test-complete")
	server_a.queue_free()
	server_b.queue_free()
	await process_frame
	_finish()


func _test_projection_contract_and_store() -> void:
	var player := {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"ownership_epoch": 1,
		"state_revision": 4,
		"last_input_sequence": 10,
		"connected": true,
		"position": {"x": -0.25, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.25, "y": 0.0, "z": 0.0},
		"orientation_yaw": 0.0,
	}
	var projection := ProjectionContract.create_from_player(player, Contracts.AUTHORITY_A, Contracts.ZONE_A, 1)
	_assert(bool(ProjectionContract.validate(projection).get("success", false)), "projection contract accepts canonical player projection")
	_assert(not projection.has("transport_session_id"), "projection contract does not leak transport session")
	_assert(not projection.has("inventory"), "projection contract does not copy canonical inventory truth")

	var store = ProjectionStore.new()
	_assert(bool(store.setup(Contracts.AUTHORITY_B).get("success", false)), "projection store configures on non-owner authority")
	var accepted := store.accept(projection)
	_assert(bool(accepted.get("success", false)), "projection store accepts foreign owner snapshot")
	var replay := store.accept(projection)
	_assert(bool(replay.get("success", false)) and bool(Dictionary(replay.get("details", {})).get("replay", false)), "exact projection replay is idempotent")

	var mutation := projection.duplicate(true)
	mutation["position"] = {"x": -0.5, "y": 0.0, "z": 0.0}
	mutation["checksum"] = ""
	const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
	mutation = Utils.finalize_json_checksum(mutation)
	_assert(String(store.accept(mutation).get("error_code", "")) == "SM0_P5_PROJECTION_SAME_REVISION_MUTATION", "same-revision projection mutation fails closed")
	_assert(String(store.reject_mutation("a", "move").get("error_code", "")) == "SM0_P5_PROJECTION_READ_ONLY", "projection mutation API fails read-only")
	store = null


func _wait_for_projection_pair(server_a, server_b, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var a_projection: Dictionary = Dictionary(server_a.status_for_tests().get("peer_projection", {}))
		var b_projection: Dictionary = Dictionary(server_b.status_for_tests().get("peer_projection", {}))
		if String(a_projection.get("logical_player_id", "")) == "b" and String(b_projection.get("logical_player_id", "")) == "a":
			return
		await process_frame
	_assert(false, "two-authority projection pair converges before timeout")


func _wait_for_projection_revision(server, logical_player_id: String, revision: int, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var projection: Dictionary = Dictionary(server.status_for_tests().get("peer_projection", {}))
		if String(projection.get("logical_player_id", "")) == logical_player_id and int(projection.get("state_revision", 0)) >= revision:
			return
		await process_frame
	_assert(false, "projection %s reaches canonical revision %d" % [logical_player_id, revision])


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("SM0 P5 two-authority read-only projections: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SM0 P5 two-authority read-only projections: FAIL (%d assertions, %d failures)" % [_assertions, _failures.size()])
	quit(1)