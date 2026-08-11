extends SceneTree

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
	_test_owner_state_accepts_and_validates()
	_test_server_predicted_mode_still_forbids_authoritative_state()
	_test_owner_client_source_contract()
	_finish()


func _test_owner_state_accepts_and_validates() -> void:
	var service = OwnerService.new()
	var setup: Dictionary = service.setup(
		"simulation/test/owner-movement",
		1,
		0,
		{
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/test/owner-movement",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	_assert(bool(setup.get("success", false)), "owner movement service configures")
	var join: Dictionary = service.join(
		"a",
		"transport-session/test/owner-a",
		"operation/test/owner-join-a"
	)
	_assert(bool(join.get("success", false)), "owner movement fixture joins")
	var player: Dictionary = service.get_player("a")
	var epoch: int = int(player.get("ownership_epoch", 0))
	_assert(epoch > 0, "owner movement fixture has ownership epoch")
	var start: Vector3 = _record_position(player)
	var accepted_state: Dictionary = PlayableStateCodec.create_player_state(
		start + Vector3(0.1, 0.0, 0.0),
		Basis(Vector3.UP, -PI * 0.5),
		Vector3(6.0, 0.0, 0.0),
		start + Vector3(0.1, 0.0, 0.0),
		"flat_humanoid",
		"first_person",
		false,
		1,
		"scenario/playground/local",
		"main",
		"playground",
		"scenario-playground"
	)
	var accepted: Dictionary = service.submit_player_state(
		"a",
		"transport-session/test/owner-a",
		epoch,
		1,
		accepted_state,
		1.0 / 30.0,
		"operation/test/owner-state-1"
	)
	_assert(bool(accepted.get("success", false)), "valid owner state accepted")
	var after: Dictionary = service.get_player("a")
	_assert(_record_position(after).distance_to(start + Vector3(0.1, 0.0, 0.0)) < 0.000001, "accepted owner transform becomes canonical server record")
	_assert(int(after.get("last_input_sequence", 0)) == 1, "accepted owner sequence becomes canonical")

	var impossible_state: Dictionary = PlayableStateCodec.create_player_state(
		start + Vector3(0.2, 0.0, 0.0),
		Basis(Vector3.UP, -PI * 0.5),
		Vector3(300.0, 0.0, 0.0),
		start + Vector3(0.2, 0.0, 0.0),
		"flat_humanoid",
		"first_person",
		false,
		2,
		"scenario/playground/local",
		"main",
		"playground",
		"scenario-playground"
	)
	var impossible: Dictionary = service.submit_player_state(
		"a",
		"transport-session/test/owner-a",
		epoch,
		2,
		impossible_state,
		1.0 / 30.0,
		"operation/test/owner-state-2"
	)
	_assert(not bool(impossible.get("success", true)), "impossible owner velocity rejected")
	_assert(String(impossible.get("error_code", "")) == "PLAYER_SPEED_LIMIT_EXCEEDED", "owner validation preserves movement speed guard")

	var stale: Dictionary = service.submit_player_state(
		"a",
		"transport-session/test/owner-a",
		epoch,
		1,
		accepted_state,
		1.0 / 30.0,
		"operation/test/owner-state-stale"
	)
	_assert(not bool(stale.get("success", true)), "stale owner state rejected")
	_assert(String(stale.get("error_code", "")) == "DUPLICATE_INPUT_SEQUENCE", "owner validation preserves monotonic sequence")
	var report: Dictionary = service.get_report()
	_assert(String(report.get("movement_authority_mode", "")) == "OWNER_AUTHORITATIVE_VALIDATED", "owner service reports authority mode")
	_assert(int(report.get("owner_state_accepts", 0)) == 1, "owner service acceptance counted")
	_assert(int(report.get("owner_state_rejections", 0)) == 2, "owner service rejections counted")


func _test_server_predicted_mode_still_forbids_authoritative_state() -> void:
	var service = ServerPredictedService.new()
	var setup: Dictionary = service.setup(
		"simulation/test/server-predicted",
		1,
		0,
		{
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/test/server-predicted",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	_assert(bool(setup.get("success", false)), "server-predicted service configures")
	var join: Dictionary = service.join(
		"a",
		"transport-session/test/server-a",
		"operation/test/server-join-a"
	)
	_assert(bool(join.get("success", false)), "server-predicted fixture joins")
	var player: Dictionary = service.get_player("a")
	var state: Dictionary = PlayableStateCodec.create_player_state(
		_record_position(player),
		Basis.IDENTITY,
		Vector3.ZERO,
		_record_position(player),
		"flat_humanoid",
		"first_person",
		false,
		1,
		"scenario/playground/local",
		"main",
		"playground",
		"scenario-playground"
	)
	var rejected: Dictionary = service.submit_player_state(
		"a",
		"transport-session/test/server-a",
		int(player.get("ownership_epoch", 0)),
		1,
		state,
		1.0 / 30.0,
		"operation/test/server-state-1"
	)
	_assert(not bool(rejected.get("success", true)), "server-predicted service still rejects client state")
	_assert(String(rejected.get("error_code", "")) == "CLIENT_AUTHORITATIVE_STATE_FORBIDDEN", "legacy server authority boundary preserved")


func _test_owner_client_source_contract() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd"
	)
	_assert(source.contains("PLAYER_STATE"), "owner client sends PLAYER_STATE")
	_assert(source.contains("UNRELIABLE_SEQUENCED"), "owner state uses realtime unreliable stream")
	_assert(source.contains("LOCAL_TRANSFORM_SINGLE_WRITER_STATE_POSTFACTUM_TO_SERVER_V1"), "owner client policy source present")
	var reconcile_start: int = source.find("func _reconcile_prediction_from_snapshot")
	var playable_start: int = source.find("func _owner_playable_state", reconcile_start)
	_assert(reconcile_start >= 0 and playable_start > reconcile_start, "owner snapshot reconcile override present")
	if reconcile_start >= 0 and playable_start > reconcile_start:
		var body: String = source.substr(reconcile_start, playable_start - reconcile_start)
		_assert(not body.contains("super._reconcile_prediction_from_snapshot"), "routine owner snapshot cannot rewind local prediction")
		_assert(body.contains("_owner_snapshot_reconciliations_skipped"), "owner snapshot skip is observable")


func _record_position(record: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(record.get("position", {}))
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0))
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("M7 owner movement assertion failed: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("M7 owner-authoritative movement: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("M7 owner-authoritative movement: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
