extends SceneTree

const MovementAuthorityProfile = preload(
	"res://scripts/network/authority/movement_authority_profile.gd"
)
const OwnerService = preload(
	"res://scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd"
)
const ServerPredictedService = preload(
	"res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"
)
const PlayableStateCodec = preload(
	"res://scripts/runtime/listen_host/playable_state_codec.gd"
)

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profile_contract()
	_test_owner_state_validation_and_fencing()
	_test_basis_yaw_roundtrip()
	_test_server_predicted_default_stays_closed()
	_test_owner_runtime_source_contract()
	_finish()


func _test_profile_contract() -> void:
	_assert(MovementAuthorityProfile.normalize("") == MovementAuthorityProfile.SERVER_PREDICTED, "empty mode defaults to server predicted")
	_assert(MovementAuthorityProfile.normalize(" owner_authoritative_validated ") == MovementAuthorityProfile.OWNER_AUTHORITATIVE_VALIDATED, "mode normalization is stable")
	_assert(MovementAuthorityProfile.is_supported("SERVER_PREDICTED"), "server-predicted mode supported")
	_assert(MovementAuthorityProfile.is_owner_authoritative("OWNER_AUTHORITATIVE_VALIDATED"), "owner mode classified")
	_assert(not MovementAuthorityProfile.is_supported("CLIENT_OWNS_GAMEPLAY"), "broad client gameplay authority rejected")


func _test_owner_state_validation_and_fencing() -> void:
	var service = _configured_owner_service("authority/test/nx-c1")
	var transport := "transport-session/test/owner-a"
	var join := service.join("a", transport, "operation/test/nx-c1/join/a")
	_assert(bool(join.get("success", false)), "owner fixture joins")
	var player := service.get_player("a")
	var epoch := int(player.get("ownership_epoch", 0))
	_assert(epoch > 0, "owner fixture has ownership epoch")
	var start := _record_position(player)
	var state := _state(start + Vector3(0.1, 0.0, 0.0), 6.0, 0.0, 1)

	var wrong_session := service.submit_player_state(
		"a", "transport-session/stale", epoch, 1, state, 1.0 / 30.0,
		"operation/test/nx-c1/state/wrong-session"
	)
	_assert(not bool(wrong_session.get("success", true)), "stale transport session rejected")
	var wrong_epoch := service.submit_player_state(
		"a", transport, epoch + 1, 1, state, 1.0 / 30.0,
		"operation/test/nx-c1/state/wrong-epoch"
	)
	_assert(not bool(wrong_epoch.get("success", true)), "stale ownership epoch rejected")

	var accepted := service.submit_player_state(
		"a", transport, epoch, 1, state, 1.0 / 30.0,
		"operation/test/nx-c1/state/1"
	)
	_assert(bool(accepted.get("success", false)), "bounded owner state accepted")
	var after := service.get_player("a")
	_assert(_record_position(after).distance_to(start + Vector3(0.1, 0.0, 0.0)) < 0.000001, "accepted transform becomes canonical server record")
	_assert(int(after.get("last_input_sequence", 0)) == 1, "accepted sequence becomes canonical")

	var impossible := _state(start + Vector3(0.2, 0.0, 0.0), 300.0, 0.0, 2)
	var impossible_result := service.submit_player_state(
		"a", transport, epoch, 2, impossible, 1.0 / 30.0,
		"operation/test/nx-c1/state/impossible"
	)
	_assert(not bool(impossible_result.get("success", true)), "impossible owner velocity rejected")
	_assert(String(impossible_result.get("error_code", "")) == "PLAYER_SPEED_LIMIT_EXCEEDED", "existing speed guard preserved")

	var duplicate := service.submit_player_state(
		"a", transport, epoch, 1, state, 1.0 / 30.0,
		"operation/test/nx-c1/state/duplicate"
	)
	_assert(not bool(duplicate.get("success", true)), "duplicate owner sequence rejected")
	_assert(String(duplicate.get("error_code", "")) == "DUPLICATE_INPUT_SEQUENCE", "monotonic sequence guard preserved")
	var report := service.get_report()
	_assert(String(report.get("movement_authority_mode", "")) == MovementAuthorityProfile.OWNER_AUTHORITATIVE_VALIDATED, "service reports bounded owner mode")
	_assert(int(report.get("owner_state_accepts", 0)) == 1, "acceptance counter exact")
	_assert(int(report.get("owner_state_rejections", 0)) >= 4, "rejections observable")
	service.shutdown()


func _test_basis_yaw_roundtrip() -> void:
	var service = _configured_owner_service("authority/test/nx-c1/yaw")
	var transport := "transport-session/test/yaw"
	_assert(bool(service.join("yaw", transport, "operation/test/nx-c1/join/yaw").get("success", false)), "yaw fixture joins")
	var epoch := int(service.get_player("yaw").get("ownership_epoch", 0))
	var position := _record_position(service.get_player("yaw"))
	var yaws := [0.0, PI * 0.5, -PI * 0.5]
	for index in range(yaws.size()):
		var sequence := index + 1
		var result := service.submit_player_state(
			"yaw", transport, epoch, sequence,
			_state(position, 0.0, float(yaws[index]), sequence),
			1.0 / 30.0,
			"operation/test/nx-c1/yaw/%d" % sequence
		)
		_assert(bool(result.get("success", false)), "yaw state %d accepted" % sequence)
		_assert(_angle_distance(float(service.get_player("yaw").get("orientation_yaw", 99.0)), float(yaws[index])) < 0.000001, "Basis(-Z) yaw %d round-trips" % sequence)
	_assert(String(service.get_report().get("owner_basis_yaw_roundtrip_policy", "")) == "GODOT_FORWARD_MINUS_Z_BASIS_TO_YAW_V1", "roundtrip policy reported")
	service.shutdown()


func _test_server_predicted_default_stays_closed() -> void:
	var service = ServerPredictedService.new()
	var setup := service.setup(
		"authority/test/server-predicted", 1, 0,
		{"profile":"MULTIPLAYER_CORE", "topology_adapter":"TEST", "region_id":"region/test/server-predicted", "playable_sandbox":true, "fixed_tick_authority":true}
	)
	_assert(bool(setup.get("success", false)), "default service configures")
	var transport := "transport-session/test/server-predicted"
	_assert(bool(service.join("a", transport, "operation/test/server-predicted/join").get("success", false)), "default fixture joins")
	var player := service.get_player("a")
	var state := _state(_record_position(player), 0.0, 0.0, 1)
	var rejected := service.submit_player_state(
		"a", transport, int(player.get("ownership_epoch", 0)), 1, state,
		1.0 / 30.0, "operation/test/server-predicted/state"
	)
	_assert(not bool(rejected.get("success", true)), "default server-predicted service rejects client state")
	_assert(String(rejected.get("error_code", "")) == "CLIENT_AUTHORITATIVE_STATE_FORBIDDEN", "default authority boundary unchanged")
	service.shutdown()


func _test_owner_runtime_source_contract() -> void:
	var client_source := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd")
	var server_source := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_owner_movement.gd")
	_assert(client_source.contains("PLAYER_STATE"), "owner client sends PLAYER_STATE")
	_assert(client_source.contains("UNRELIABLE_SEQUENCED"), "owner state uses realtime unreliable stream")
	_assert(client_source.contains("LOCAL_TRANSFORM_SINGLE_WRITER_RECONCILE_ON_REJECTION_V1"), "single-writer correction policy explicit")
	_assert(server_source.contains("OwnerMovementService"), "dedicated owner runtime composes validated service")
	_assert(not server_source.contains("network_protocol_manifest"), "owner runtime does not fork protocol manifest")
	_assert(server_source.contains("set_block_signals(true)"), "READY cannot race owner service installation")
	_assert(server_source.contains("recovery_rebind"), "persistence adapters rebound when enabled")
	var reconcile_start := client_source.find("func _reconcile_prediction_from_snapshot")
	var operation_start := client_source.find("func _is_owner_state_operation", reconcile_start)
	_assert(reconcile_start >= 0 and operation_start > reconcile_start, "owner snapshot override present")
	if reconcile_start >= 0 and operation_start > reconcile_start:
		var body := client_source.substr(reconcile_start, operation_start - reconcile_start)
		_assert(body.contains("if _owner_reconciliation_required"), "routine snapshots remain no-rewind unless rejection armed")
		_assert(body.contains("super._reconcile_prediction_from_snapshot(snapshot)"), "rejected owner state gets authoritative correction")
		_assert(body.contains("_owner_snapshot_reconciliations_skipped"), "routine snapshot suppression observable")


func _configured_owner_service(owner_id: String):
	var service = OwnerService.new()
	var setup := service.setup(
		owner_id, 1, 0,
		{"profile":"MULTIPLAYER_CORE", "topology_adapter":"TEST", "region_id":"region/test/nx-c1", "playable_sandbox":true, "fixed_tick_authority":true}
	)
	_assert(bool(setup.get("success", false)), "owner service configures")
	return service


func _state(position: Vector3, speed_x: float, yaw: float, sequence: int) -> Dictionary:
	return PlayableStateCodec.create_player_state(
		position,
		Basis(Vector3.UP, yaw),
		Vector3(speed_x, 0.0, 0.0),
		position,
		"flat_humanoid",
		"first_person",
		false,
		sequence,
		"scenario/playground/local",
		"main",
		"playground",
		"scenario-playground"
	)


func _record_position(record: Dictionary) -> Vector3:
	var value := Dictionary(record.get("position", {}))
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))


func _angle_distance(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("NX.C1 owner movement: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("NX.C1 owner movement authority: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("NX.C1 owner movement authority: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
