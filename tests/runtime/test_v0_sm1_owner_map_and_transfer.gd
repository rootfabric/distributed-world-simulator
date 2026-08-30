extends SceneTree

const OwnerPortMap = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_owner_port_map.gd")
const TransferCoordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const ProjectionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const ShadowScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[sm1-l0][FAIL] %s" % message)


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _make_shadow():
	var projection = ProjectionScript.new()
	var configured: Dictionary = projection.configure_from_canonical_sources({
		"gameplay": {"revision": 11, "player": "player/a"},
		"item_graph": {"revision": 23, "items": ["item/ore/1"]},
		"construction": {"revision": 7, "constructs": ["construct/outpost/1"]},
	})
	_assert(_ok(configured), "canonical projection setup failed")
	var shadow = ShadowScript.new()
	var shadow_config: Dictionary = shadow.configure(projection)
	_assert(_ok(shadow_config), "P6 shadow configure failed")
	var rejected: Dictionary = shadow.apply_delta({"op": "forbidden_warm_write"})
	_assert(not _ok(rejected) and _err(rejected) == ShadowScript.ERR_SHADOW_CANNOT_WRITE, "WARM shadow did not reject write")
	return shadow


func _assert_zero_writers_during_transfer(coordinator, source: String, source_epoch: int, target: String, target_epoch: int, label: String) -> void:
	var source_write: Dictionary = coordinator.authorize_write(source, source_epoch)
	var target_write: Dictionary = coordinator.authorize_write(target, target_epoch)
	_assert(not _ok(source_write), "%s source retained write authority" % label)
	_assert(not _ok(target_write), "%s target gained write authority too early" % label)


func _init() -> void:
	# SM1.1: donor semantics are mapped onto current canonical owners only.
	var map_result: Dictionary = OwnerPortMap.validate()
	_assert(_ok(map_result), "SM1.1 owner-port map failed validation")
	_assert(String(map_result.get("details", {}).get("result", "")) == "SM0_DONOR_TO_P6_OWNER_MAP_PASS", "SM1.1 stage marker missing")
	_assert(String(OwnerPortMap.find_port("item_graph").get("expected_owner", "")) == "item/m4-canonical-item-graph", "Item Graph owner changed")
	_assert(String(OwnerPortMap.find_port("construction").get("expected_owner", "")) == "construction/p4-authority", "Construction owner changed")
	_assert(String(OwnerPortMap.find_port("persistence").get("expected_owner", "")) == "persistence/authoritative-recovery", "persistence owner changed")
	for raw_port in OwnerPortMap.PORTS:
		var port := Dictionary(raw_port)
		_assert(not bool(port.get("canonical_truth_created", true)), "SM1 port created private canonical truth: %s" % String(port.get("concern", "")))
		_assert(String(port.get("mapping_action", "")) != OwnerPortMap.FORBIDDEN_ACTION, "SM1 copied an SM0 canonical owner")

	# SM1.2: A -> B with a zero-writer transfer gap and a single linearization point.
	var player_snapshot := {
		"logical_player_id": "player/a",
		"player_entity_id": "entity/player/a",
		"last_input_sequence": 41,
		"last_operation_id": "operation/p6/a/0041",
	}
	var coordinator = TransferCoordinator.new()
	var configured: Dictionary = coordinator.configure("authority/a", 1, player_snapshot)
	_assert(_ok(configured), "transfer coordinator configure failed")
	_assert(_ok(coordinator.authorize_write("authority/a", 1)), "initial A writer not authorized")
	_assert(not _ok(coordinator.authorize_write("authority/b", 1)), "B wrote before handoff")

	var begin: Dictionary = coordinator.begin_transfer("transfer/a-b/1", "authority/a", "authority/b", 1)
	_assert(_ok(begin), "A->B begin failed")
	_assert_zero_writers_during_transfer(coordinator, "authority/a", 1, "authority/b", 2, "SOURCE_FROZEN")
	var competing: Dictionary = coordinator.begin_transfer("transfer/a-b/competing", "authority/a", "authority/b", 1)
	_assert(not _ok(competing) and _err(competing) == "SM1_TRANSFER_IN_PROGRESS", "competing transfer was admitted")
	var early_commit: Dictionary = coordinator.commit_ownership("transfer/a-b/1", "authority/a", "authority/b", 1, 2)
	_assert(not _ok(early_commit) and _err(early_commit) == "SM1_COMMIT_BEFORE_WARM_VALIDATION", "ownership committed before WARM validation")

	var shadow = _make_shadow()
	var warm_report: Dictionary = shadow.get_report()
	var warm: Dictionary = coordinator.validate_warm_target("transfer/a-b/1", "authority/b", warm_report)
	_assert(_ok(warm), "WARM target validation failed")
	_assert_zero_writers_during_transfer(coordinator, "authority/a", 1, "authority/b", 2, "TARGET_WARM_VALIDATED")
	var warm_replay: Dictionary = coordinator.validate_warm_target("transfer/a-b/1", "authority/b", warm_report)
	_assert(_ok(warm_replay) and String(warm_replay.get("details", {}).get("result", "")) == "WARM_ALREADY_VALIDATED", "WARM validation replay not idempotent")

	var committed: Dictionary = coordinator.commit_ownership("transfer/a-b/1", "authority/a", "authority/b", 1, 2)
	_assert(_ok(committed), "A->B ownership commit failed")
	var commit_token := String(committed.get("details", {}).get("commit_token", ""))
	_assert(not commit_token.is_empty(), "commit token missing")
	_assert(bool(committed.get("details", {}).get("linearized_now", false)), "first commit did not mark linearization")
	_assert_zero_writers_during_transfer(coordinator, "authority/a", 1, "authority/b", 2, "OWNERSHIP_COMMITTED")
	var commit_replay: Dictionary = coordinator.commit_ownership("transfer/a-b/1", "authority/a", "authority/b", 1, 2)
	_assert(_ok(commit_replay) and String(commit_replay.get("details", {}).get("result", "")) == TransferCoordinator.RESULT_ALREADY_COMMITTED, "ambiguous commit retry did not converge")
	_assert(String(commit_replay.get("details", {}).get("commit_token", "")) == commit_token, "commit retry changed commit token")
	var late_abort: Dictionary = coordinator.abort_before_commit("transfer/a-b/1", "authority/a")
	_assert(not _ok(late_abort) and _err(late_abort) == "SM1_ABORT_AFTER_COMMIT_FORBIDDEN", "post-commit abort was accepted")

	var bad_retire: Dictionary = coordinator.retire_source("transfer/a-b/1", "authority/a", "bad-token")
	_assert(not _ok(bad_retire), "source retired with invalid commit proof")
	var retired: Dictionary = coordinator.retire_source("transfer/a-b/1", "authority/a", commit_token)
	_assert(_ok(retired), "source retirement failed")
	_assert_zero_writers_during_transfer(coordinator, "authority/a", 1, "authority/b", 2, "SOURCE_RETIRED")
	var activated: Dictionary = coordinator.activate_target("transfer/a-b/1", "authority/b", 2, commit_token)
	_assert(_ok(activated), "target B activation failed")
	_assert(_ok(coordinator.authorize_write("authority/b", 2)), "B writer not authorized after activation")
	var stale_a: Dictionary = coordinator.authorize_write("authority/a", 1)
	_assert(not _ok(stale_a) and _err(stale_a) == "SM1_STALE_AUTHORITY_EPOCH", "stale A was not epoch-fenced")
	var activation_replay: Dictionary = coordinator.activate_target("transfer/a-b/1", "authority/b", 2, commit_token)
	_assert(_ok(activation_replay) and String(activation_replay.get("details", {}).get("result", "")) == TransferCoordinator.RESULT_ALREADY_ACTIVE, "target activation replay not idempotent")
	var after_ab: Dictionary = coordinator.snapshot()
	_assert(String(after_ab.get("player_snapshot", {}).get("logical_player_id", "")) == "player/a", "logical player identity changed on A->B")
	_assert(String(after_ab.get("player_snapshot", {}).get("player_entity_id", "")) == "entity/player/a", "player entity identity changed on A->B")
	_assert(int(after_ab.get("player_snapshot", {}).get("last_input_sequence", -1)) == 41, "input watermark changed on A->B")
	_assert(String(after_ab.get("player_snapshot", {}).get("last_operation_id", "")) == "operation/p6/a/0041", "OperationId watermark changed on A->B")

	# Return B -> A proves the state machine is reusable and epochs are monotonic.
	var begin_return: Dictionary = coordinator.begin_transfer("transfer/b-a/2", "authority/b", "authority/a", 2)
	_assert(_ok(begin_return), "B->A begin failed")
	_assert_zero_writers_during_transfer(coordinator, "authority/b", 2, "authority/a", 3, "RETURN_SOURCE_FROZEN")
	var return_warm: Dictionary = coordinator.validate_warm_target("transfer/b-a/2", "authority/a", warm_report)
	_assert(_ok(return_warm), "return WARM validation failed")
	var return_commit: Dictionary = coordinator.commit_ownership("transfer/b-a/2", "authority/b", "authority/a", 2, 3)
	_assert(_ok(return_commit), "B->A ownership commit failed")
	var return_token := String(return_commit.get("details", {}).get("commit_token", ""))
	_assert(_ok(coordinator.retire_source("transfer/b-a/2", "authority/b", return_token)), "B source retirement failed")
	_assert(_ok(coordinator.activate_target("transfer/b-a/2", "authority/a", 3, return_token)), "A reactivation failed")
	_assert(_ok(coordinator.authorize_write("authority/a", 3)), "A writer not authorized after return")
	var stale_b: Dictionary = coordinator.authorize_write("authority/b", 2)
	_assert(not _ok(stale_b) and _err(stale_b) == "SM1_STALE_AUTHORITY_EPOCH", "stale B was not fenced after return")
	_assert(int(coordinator.snapshot().get("authority_epoch", 0)) == 3, "authority epoch did not increase monotonically A->B->A")
	_assert(int(coordinator.snapshot().get("completed_transfer_count", 0)) == 2, "completed transfer ledger count mismatch")

	# Pre-commit failure can safely abort back to the source because ownership
	# never crossed the linearization boundary.
	var aborting = TransferCoordinator.new()
	_assert(_ok(aborting.configure("authority/a", 10, player_snapshot)), "abort fixture configure failed")
	_assert(_ok(aborting.begin_transfer("transfer/abort/1", "authority/a", "authority/b", 10)), "abort fixture begin failed")
	_assert(_ok(aborting.abort_before_commit("transfer/abort/1", "authority/a")), "pre-commit abort failed")
	_assert(_ok(aborting.authorize_write("authority/a", 10)), "source did not recover authority after pre-commit abort")
	_assert(not _ok(aborting.authorize_write("authority/b", 11)), "target gained authority after aborted transfer")

	var report: Dictionary = coordinator.get_report()
	_assert(not bool(report.get("private_item_graph", true)), "coordinator claims private Item Graph")
	_assert(not bool(report.get("private_construction_truth", true)), "coordinator claims private Construction truth")
	_assert(not bool(report.get("private_persistence_owner", true)), "coordinator claims private persistence owner")
	_assert(not bool(report.get("private_replay_owner", true)), "coordinator claims private replay owner")
	_assert(String(report.get("one_writer_policy", "")) == "ACTIVE_TUPLE_ONLY_ZERO_WRITER_TRANSFER_GAP", "one-writer policy marker mismatch")

	if failures.is_empty():
		print("[sm1-l0] all %d assertions passed" % assertions)
		print("[sm1-l0][stage] SM0_DONOR_TO_P6_OWNER_MAP_PASS")
		print("[sm1-l0][stage] ONE_WRITER_TRANSFER_STATE_MACHINE_PASS")
		print("[sm1-l0][stage] AMBIGUOUS_COMMIT_RETRY_EXACTLY_ONCE_PASS")
		print("[sm1-l0][stage] STALE_SOURCE_FENCED_PASS")
		quit(0)
	else:
		print("[sm1-l0] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
