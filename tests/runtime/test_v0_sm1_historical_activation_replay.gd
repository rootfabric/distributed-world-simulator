extends SceneTree

const TransferCoordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const ProjectionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const ShadowScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")

const AUTHORITY_A := "authority/a"
const AUTHORITY_B := "authority/b"

var assertions: int = 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[sm1-historical-activation][FAIL] %s" % message)


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _make_shadow_report() -> Dictionary:
	var projection = ProjectionScript.new()
	_assert(_ok(projection.configure_from_canonical_sources({
		"gameplay": {"revision": 1, "player": "player/replay"},
		"item_graph": {"revision": 1, "items": []},
		"construction": {"revision": 1, "constructs": []},
	})), "projection setup failed")
	var shadow = ShadowScript.new()
	_assert(_ok(shadow.configure(projection)), "shadow setup failed")
	return shadow.get_report()


func _complete_transfer(coordinator, warm_report: Dictionary, transfer_id: String, source: String, target: String, source_epoch: int, target_epoch: int) -> String:
	_assert(_ok(coordinator.begin_transfer(transfer_id, source, target, source_epoch)), "%s begin failed" % transfer_id)
	_assert(_ok(coordinator.validate_warm_target(transfer_id, target, warm_report)), "%s WARM validation failed" % transfer_id)
	var committed: Dictionary = coordinator.commit_ownership(transfer_id, source, target, source_epoch, target_epoch)
	_assert(_ok(committed), "%s commit failed" % transfer_id)
	var token := String(committed.get("details", {}).get("commit_token", ""))
	_assert(not token.is_empty(), "%s commit token missing" % transfer_id)
	_assert(_ok(coordinator.retire_source(transfer_id, source, token)), "%s retire failed" % transfer_id)
	_assert(_ok(coordinator.activate_target(transfer_id, target, target_epoch, token)), "%s activation failed" % transfer_id)
	return token


func _init() -> void:
	var coordinator = TransferCoordinator.new()
	_assert(_ok(coordinator.configure(AUTHORITY_A, 1, {
		"logical_player_id": "player/replay",
		"player_entity_id": "entity/replay",
		"last_input_sequence": 1,
		"last_operation_id": "operation/replay/1",
	})), "coordinator configure failed")
	var warm_report := _make_shadow_report()

	var transfer_ab := "transfer/replay/a-b/1"
	var token_ab := _complete_transfer(coordinator, warm_report, transfer_ab, AUTHORITY_A, AUTHORITY_B, 1, 2)
	var immediate_replay: Dictionary = coordinator.activate_target(transfer_ab, AUTHORITY_B, 2, token_ab)
	_assert(_ok(immediate_replay), "immediate activation replay failed")
	_assert(String(immediate_replay.get("details", {}).get("result", "")) == TransferCoordinator.RESULT_ALREADY_ACTIVE, "immediate replay did not report current ACTIVE")
	_assert(bool(immediate_replay.get("details", {}).get("currently_active", false)), "immediate replay lost current-active truth")

	var transfer_ba := "transfer/replay/b-a/2"
	_complete_transfer(coordinator, warm_report, transfer_ba, AUTHORITY_B, AUTHORITY_A, 2, 3)
	_assert(String(coordinator.snapshot().get("active_authority_id", "")) == AUTHORITY_A, "return transfer did not activate A")
	_assert(int(coordinator.snapshot().get("authority_epoch", 0)) == 3, "return transfer did not advance epoch")

	# A late retry of the old A->B activation is a historical idempotency query,
	# not authority to describe B as currently ACTIVE or to reactivate it.
	var historical_replay: Dictionary = coordinator.activate_target(transfer_ab, AUTHORITY_B, 2, token_ab)
	_assert(_ok(historical_replay), "historical activation replay did not converge")
	_assert(String(historical_replay.get("details", {}).get("result", "")) == TransferCoordinator.RESULT_ALREADY_ACTIVATED, "historical replay incorrectly reported ALREADY_ACTIVE")
	_assert(not bool(historical_replay.get("details", {}).get("currently_active", true)), "historical replay claimed old target is currently active")
	_assert(String(historical_replay.get("details", {}).get("current_authority_id", "")) == AUTHORITY_A, "historical replay hid current authority")
	_assert(int(historical_replay.get("details", {}).get("current_authority_epoch", 0)) == 3, "historical replay hid current epoch")
	_assert(_ok(coordinator.authorize_write(AUTHORITY_A, 3)), "historical replay disturbed current writer")
	_assert(not _ok(coordinator.authorize_write(AUTHORITY_B, 2)), "historical replay resurrected stale B writer")

	var report: Dictionary = coordinator.get_report()
	_assert(int(report.get("counters", {}).get("historical_activation_replays", 0)) == 1, "historical replay counter mismatch")

	if failures.is_empty():
		print("[sm1-historical-activation] all %d assertions passed" % assertions)
		print("[sm1-historical-activation][stage] HISTORICAL_ACTIVATION_REPLAY_DOES_NOT_REASSERT_CURRENT_OWNER_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("[sm1-historical-activation] FAIL %d/%d" % [failures.size(), assertions])
	quit(1)
