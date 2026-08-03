extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Fixture = preload("res://tests/matter/transactions/mw10_test_fixture.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Lease = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_authority_lease.gd")
const Participant = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_participant.gd")
const MassLedger = preload("res://scripts/simulation/matter/transactions/distributed/matter_distributed_mass_ledger.gd")
const Plan = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd")
const Receipt = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_receipt.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const InvalidationBatch = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_invalidation_batch.gd")
const Reservation = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_reservation.gd")
const Record = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_record.gd")
const Checkpoint = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_checkpoint.gd")
const AuthorityGate = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_authority_gate.gd")
const Coordinator = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_coordinator.gd")
const HandoffInterlock = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_handoff_interlock.gd")

var assertions := 0
var failures: Array[String] = []
var roots: Array[String] = []


class FakeRuntime extends RefCounted:
	var calls: Array[String] = []
	var prepared_by_key: Dictionary = {}
	var committed_by_key: Dictionary = {}
	var rolled_back_by_key: Dictionary = {}
	var published_by_id: Dictionary = {}
	var reject_prepare_region := ""
	var reject_commit_region := ""
	var reject_rollback_region := ""
	var reject_publish := false

	func prepare_region(participant: Dictionary, context: Dictionary) -> Dictionary:
		var region_id: String = String(participant["region_id"])
		calls.append("prepare:%s" % region_id)
		if region_id == reject_prepare_region:
			return MatterUtils.failure("FAKE_PREPARE_REJECTED")
		var key: String = "%s|%s" % [context["transaction_id"], region_id]
		if not prepared_by_key.has(key):
			var previous: Dictionary = participant["previous_source_revision"]
			prepared_by_key[key] = SourceRevision.create(
				"MATTER", String(previous["source_id"]), int(previous["authority_epoch"]),
				int(previous["source_revision"]) + 1,
				MatterUtils.payload_hash([key, "prepared-source"]),
				MatterUtils.payload_hash([key, "prepared-dependency"])
			)
		return MatterUtils.success({
			"source_revision": prepared_by_key[key],
			"runtime_state_hash": MatterUtils.payload_hash([key, "prepared-state"]),
		})

	func commit_region(participant: Dictionary, prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
		var region_id: String = String(participant["region_id"])
		calls.append("commit:%s" % region_id)
		if region_id == reject_commit_region:
			return MatterUtils.failure("FAKE_COMMIT_REJECTED")
		var key: String = "%s|%s" % [context["transaction_id"], region_id]
		if not prepared_by_key.has(key):
			return MatterUtils.failure("FAKE_PREPARE_MISSING")
		committed_by_key[key] = prepare_receipt["source_revision"].duplicate(true)
		return MatterUtils.success({
			"source_revision": committed_by_key[key],
			"runtime_state_hash": MatterUtils.payload_hash([key, "committed-state", context["global_commit_hash"]]),
		})

	func rollback_region(participant: Dictionary, prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
		var region_id: String = String(participant["region_id"])
		calls.append("rollback:%s" % region_id)
		if region_id == reject_rollback_region:
			return MatterUtils.failure("FAKE_ROLLBACK_REJECTED")
		var key: String = "%s|%s" % [context["transaction_id"], region_id]
		rolled_back_by_key[key] = true
		prepared_by_key.erase(key)
		committed_by_key.erase(key)
		return MatterUtils.success({
			"source_revision": participant["previous_source_revision"],
			"runtime_state_hash": MatterUtils.payload_hash([key, "rolled-back-state"]),
		})

	func publish_invalidation(outbox_record: Dictionary) -> Dictionary:
		var outbox_id: String = String(outbox_record["outbox_id"])
		calls.append("publish:%s" % outbox_id)
		if reject_publish:
			return MatterUtils.failure("FAKE_PUBLISH_REJECTED")
		published_by_id[outbox_id] = outbox_record["invalidation_batch"].duplicate(true)
		return MatterUtils.success({"outbox_id": outbox_id})


class FlappingAuthorityGate extends RefCounted:
	var calls := 0

	func authorize_plan(_plan: Dictionary, _server_tick: int) -> Dictionary:
		calls += 1
		if calls == 1:
			return MatterUtils.success()
		return MatterUtils.failure("FAKE_AUTHORITY_CHANGED")


func _init() -> void:
	_test_config_and_contracts()
	_test_successful_commit_and_replay()
	_test_abort_and_predecision_recovery()
	_test_commit_and_outbox_recovery()
	_test_authority_and_reservation_fences()
	_test_durable_binding_hardening()
	_test_handoff_interlock_and_authority_race()
	_test_repository_fallback()
	_cleanup()
	if failures.is_empty():
		print("MW10 cross-region Matter transactions: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("MW10 cross-region Matter transactions: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)


func _test_config_and_contracts() -> void:
	var file := FileAccess.open("res://config/matter/mw10-cross-region-transactions.v1.json", FileAccess.READ)
	_assert(file != null, "MW10 config missing")
	if file != null:
		var config = JSON.parse_string(file.get_as_text())
		file.close()
		_assert(typeof(config) == TYPE_DICTIONARY, "MW10 config invalid JSON")
		if typeof(config) == TYPE_DICTIONARY:
			_assert(String(config.get("checkpoint", "")) == "v17.12.0-simulation-mw10-cross-region-matter-transactions", "MW10 checkpoint changed")
			_assert(String(config.get("accepted_base", "")) == "v17.11.0-simulation-mw9-durable-handoff-recovery", "MW10 base changed")
			_assert(bool(config.get("ordering", {}).get("lexicographic_region_order", false)), "Deterministic region ordering disabled")
			_assert(bool(config.get("recovery", {}).get("commit_decision_irreversible", false)), "Commit decision is reversible")
			_assert(bool(config.get("representation", {}).get("invalidation_after_global_commit_only", false)), "Invalidation timing changed")
	var plan: Dictionary = Fixture.plan_ab()
	_assert_ok(Plan.validate(plan), "Valid MW10 plan rejected")
	_assert(String(plan["participants"][0]["region_id"]) == Fixture.REGION_A, "Plan did not sort region A first")
	_assert(String(plan["participants"][1]["region_id"]) == Fixture.REGION_B, "Plan did not sort region B second")
	_assert_ok(MassLedger.validate(plan["mass_ledger"]), "Distributed mass ledger rejected")
	_assert(absf(float(plan["mass_ledger"]["material_balances"][0]["residual_kg"])) <= 0.000000001, "Mass residual is not zero")
	var same: Dictionary = Plan.create({
		"transaction_id": plan["transaction_id"],
		"operation_id": plan["operation_id"],
		"body_id": plan["body_id"],
		"created_tick": plan["created_tick"],
		"participants": [plan["participants"][1], plan["participants"][0]],
		"mass_ledger": plan["mass_ledger"],
	})
	_assert(String(same.get("checksum", "")) == String(plan["checksum"]), "Plan checksum depends on participant arrival order")
	_assert(MassLedger.create(String(plan["transaction_id"]), [
		{"region_id": Fixture.REGION_A, "removed": [{"material_id": "matter/basalt", "mass_kg": 7.0}], "added": []},
		{"region_id": Fixture.REGION_B, "removed": [{"material_id": "matter/basalt", "mass_kg": 3.0}], "added": []},
	], [], [{"material_id": "matter/basalt", "mass_kg": 9.0}]).is_empty(), "Unbalanced distributed ledger accepted")
	var extra: Dictionary = plan.duplicate(true)
	extra["runtime_node"] = "forbidden"
	_assert_fail(Plan.validate(extra), "Plan accepted extra runtime field")
	var tampered: Dictionary = plan.duplicate(true)
	tampered["participant_order_hash"] = MatterUtils.payload_hash("wrong")
	tampered["checksum"] = MatterUtils.compute_checksum(tampered)
	_assert_fail(Plan.validate(tampered), "Plan accepted forged participant order hash")
	var begin: Dictionary = Record.create_begin(plan, "transition/mw10-contract-begin", 30)
	_assert_ok(Record.validate(begin), "BEGIN record rejected")
	_assert(String(begin["decision"]) == Record.DECISION_NONE, "BEGIN decision changed")
	var bad_advance: Dictionary = Record.advance(begin, Record.PHASE_COMMITTED, "transition/mw10-bad", 31)
	_assert(bad_advance.is_empty(), "BEGIN advanced directly to COMMITTED")


func _test_successful_commit_and_replay() -> void:
	var root: String = _root("success")
	var runtime := FakeRuntime.new()
	var coordinator = _new_coordinator(root, runtime)
	_assert_ok(coordinator.initialize(Fixture.CHECKPOINT_ID, 20), "MW10 initialize failed")
	var plan: Dictionary = Fixture.plan_ab()
	_assert_ok(coordinator.begin_transaction(plan, "transition/mw10-success-begin", 30), "MW10 begin failed")
	_assert(Array(coordinator.checkpoint()["region_reservations"]).size() == 2, "Begin did not reserve both regions")
	_assert_ok(coordinator.prepare_next(String(plan["transaction_id"]), "transition/mw10-success-prepare-a", 31), "Prepare A failed")
	_assert(String(coordinator.latest_record(String(plan["transaction_id"]))["phase"]) == Record.PHASE_PREPARING, "First prepare did not enter PREPARING")
	_assert(runtime.calls[0] == "prepare:%s" % Fixture.REGION_A, "Prepare order is not deterministic")
	_assert(runtime.published_by_id.is_empty(), "Invalidation published during prepare")
	_assert_ok(coordinator.prepare_next(String(plan["transaction_id"]), "transition/mw10-success-prepare-b", 32), "Prepare B failed")
	_assert(String(coordinator.latest_record(String(plan["transaction_id"]))["phase"]) == Record.PHASE_PREPARED, "Second prepare did not enter PREPARED")
	_assert_ok(coordinator.decide_commit(String(plan["transaction_id"]), "transition/mw10-success-decision", 33), "Commit decision failed")
	_assert_fail(coordinator.decide_abort(String(plan["transaction_id"]), "transition/mw10-illegal-abort", 34), "Abort replaced durable commit decision")
	_assert_ok(coordinator.commit_next(String(plan["transaction_id"]), "transition/mw10-success-commit-a", 35), "Commit A failed")
	var progress: Dictionary = coordinator.latest_record(String(plan["transaction_id"]))
	_assert(String(progress["phase"]) == Record.PHASE_COMMITTING, "First commit did not enter COMMITTING")
	_assert(String(progress["commit_receipts"][0]["region_id"]) == Fixture.REGION_A, "Commit order is not deterministic")
	_assert(Array(coordinator.checkpoint()["invalidation_outbox"]).is_empty(), "Outbox created before global commit")
	_assert(runtime.published_by_id.is_empty(), "Invalidation published before global commit")
	_assert_ok(coordinator.commit_next(String(plan["transaction_id"]), "transition/mw10-success-commit-b", 36), "Commit B failed")
	var terminal: Dictionary = coordinator.latest_record(String(plan["transaction_id"]))
	_assert(String(terminal["phase"]) == Record.PHASE_COMMITTED, "Transaction did not reach COMMITTED")
	_assert(Array(coordinator.checkpoint()["region_reservations"]).is_empty(), "Committed transaction retained reservations")
	_assert(Array(coordinator.checkpoint()["invalidation_outbox"]).size() == 1, "Committed transaction did not create outbox")
	_assert(not bool(coordinator.checkpoint()["invalidation_outbox"][0]["published"]), "Outbox published inside global commit")
	_assert(Array(terminal["invalidation_batch"]["invalidations"]).size() == 2, "Global invalidation batch does not cover both regions")
	_assert(runtime.published_by_id.is_empty(), "Runtime saw invalidation before outbox publication")
	_assert_ok(coordinator.publish_pending_invalidations(37), "Invalidation publication failed")
	_assert(runtime.published_by_id.size() == 1, "Invalidation batch was not published exactly once")
	_assert(bool(coordinator.checkpoint()["invalidation_outbox"][0]["published"]), "Published outbox state not persisted")
	var call_count: int = runtime.calls.size()
	var replay: Dictionary = coordinator.execute_transaction(plan, "transition/mw10-success-replay", 50)
	_assert_ok(replay, "Exact transaction replay failed")
	_assert(bool(replay["details"].get("replay", false)), "Exact operation replay was not reported")
	_assert(runtime.calls.size() == call_count, "Exact replay invoked runtime twice")
	_assert(String(coordinator.operation_result(String(plan["operation_id"]))["outcome"]) == "COMMITTED", "Committed operation result missing")
	_assert_ok(Checkpoint.validate(coordinator.checkpoint()), "Committed checkpoint rejected")


func _test_abort_and_predecision_recovery() -> void:
	var root: String = _root("abort")
	var runtime := FakeRuntime.new()
	runtime.reject_prepare_region = Fixture.REGION_B
	var coordinator = _new_coordinator(root, runtime)
	_assert_ok(coordinator.initialize(Fixture.CHECKPOINT_ID, 20), "Abort initialize failed")
	var plan: Dictionary = Fixture.plan_ab("matter-transaction/mw10-abort", "matter-operation/mw10-abort")
	_assert_ok(coordinator.begin_transaction(plan, "transition/mw10-abort-begin", 30), "Abort begin failed")
	_assert_ok(coordinator.prepare_next(String(plan["transaction_id"]), "transition/mw10-abort-prepare-a", 31), "Abort prepare A failed")
	_assert_fail(coordinator.prepare_next(String(plan["transaction_id"]), "transition/mw10-abort-prepare-b", 32), "Rejected prepare B succeeded")
	_assert_ok(coordinator.decide_abort(String(plan["transaction_id"]), "transition/mw10-abort-decision", 33), "Abort decision failed")
	_assert_ok(coordinator.rollback_all(String(plan["transaction_id"]), "transition/mw10-abort-rollback", 34), "Rollback failed")
	var terminal: Dictionary = coordinator.latest_record(String(plan["transaction_id"]))
	_assert(String(terminal["phase"]) == Record.PHASE_ABORTED, "Abort did not reach ABORTED")
	_assert(Array(terminal["rollback_receipts"]).size() == 1, "Abort rolled back wrong participant count")
	_assert(String(terminal["rollback_receipts"][0]["region_id"]) == Fixture.REGION_A, "Abort rolled back unprepared region")
	_assert(Array(coordinator.checkpoint()["region_reservations"]).is_empty(), "Abort retained reservations")
	_assert(Array(coordinator.checkpoint()["invalidation_outbox"]).is_empty(), "Abort emitted invalidation outbox")
	_assert(String(coordinator.operation_result(String(plan["operation_id"]))["outcome"]) == "ABORTED", "Abort operation result missing")

	var full_root: String = _root("full-rollback")
	var full_runtime := FakeRuntime.new()
	var full = _new_coordinator(full_root, full_runtime)
	_assert_ok(full.initialize(Fixture.CHECKPOINT_ID, 20), "Full rollback initialize failed")
	var full_plan: Dictionary = Fixture.plan_ab("matter-transaction/mw10-full-rollback", "matter-operation/mw10-full-rollback")
	_assert_ok(full.begin_transaction(full_plan, "transition/mw10-full-rollback-begin", 30), "Full rollback begin failed")
	_assert_ok(full.prepare_all(String(full_plan["transaction_id"]), "transition/mw10-full-rollback-prepare", 31), "Full rollback prepare failed")
	_assert_ok(full.decide_abort(String(full_plan["transaction_id"]), "transition/mw10-full-rollback-decision", 35), "Full rollback decision failed")
	_assert_ok(full.rollback_all(String(full_plan["transaction_id"]), "transition/mw10-full-rollback-run", 36), "Full rollback failed")
	var full_terminal: Dictionary = full.latest_record(String(full_plan["transaction_id"]))
	_assert(String(full_terminal["phase"]) == Record.PHASE_ABORTED, "Full rollback did not reach ABORTED")
	_assert(Array(full_terminal["rollback_receipts"]).size() == 2, "Full rollback receipt count changed")
	_assert(full_runtime.calls.find("rollback:%s" % Fixture.REGION_B) < full_runtime.calls.find("rollback:%s" % Fixture.REGION_A), "Full rollback order is not descending")

	var recovery_root: String = _root("predecision-recovery")
	var recovery_runtime := FakeRuntime.new()
	var seed = _new_coordinator(recovery_root, recovery_runtime)
	_assert_ok(seed.initialize(Fixture.CHECKPOINT_ID, 20), "Predecision seed initialize failed")
	var recovery_plan: Dictionary = Fixture.plan_ab("matter-transaction/mw10-recover-abort", "matter-operation/mw10-recover-abort")
	_assert_ok(seed.begin_transaction(recovery_plan, "transition/mw10-recover-abort-begin", 30), "Predecision seed begin failed")
	_assert_ok(seed.prepare_next(String(recovery_plan["transaction_id"]), "transition/mw10-recover-abort-prepare", 31), "Predecision seed prepare failed")
	var restored = _new_coordinator(recovery_root, recovery_runtime)
	_assert_ok(restored.restore_latest(), "Predecision restore failed")
	var recovered: Dictionary = restored.recover_incomplete("recovery/mw10-predecision", 40)
	_assert_ok(recovered, "Predecision recovery failed")
	_assert(String(restored.latest_record(String(recovery_plan["transaction_id"]))["phase"]) == Record.PHASE_ABORTED, "Undecided transaction did not abort after recovery")
	_assert(String(recovered["details"]["actions"][0]["action"]) == "ABORT_UNDECIDED", "Predecision recovery action changed")
	_assert(recovery_runtime.published_by_id.is_empty(), "Aborted recovery published invalidation")


func _test_commit_and_outbox_recovery() -> void:
	var root: String = _root("commit-recovery")
	var runtime := FakeRuntime.new()
	var seed = _new_coordinator(root, runtime)
	_assert_ok(seed.initialize(Fixture.CHECKPOINT_ID, 20), "Commit recovery initialize failed")
	var plan: Dictionary = Fixture.plan_ab("matter-transaction/mw10-recover-commit", "matter-operation/mw10-recover-commit")
	_assert_ok(seed.begin_transaction(plan, "transition/mw10-recover-commit-begin", 30), "Commit recovery begin failed")
	_assert_ok(seed.prepare_all(String(plan["transaction_id"]), "transition/mw10-recover-prepare", 31), "Commit recovery prepare failed")
	_assert_ok(seed.decide_commit(String(plan["transaction_id"]), "transition/mw10-recover-decision", 35), "Commit recovery decision failed")
	_assert_ok(seed.commit_next(String(plan["transaction_id"]), "transition/mw10-recover-commit-a", 36), "Commit recovery first commit failed")
	var restored = _new_coordinator(root, runtime)
	_assert_ok(restored.restore_latest(), "Commit recovery restore failed")
	var recovered: Dictionary = restored.recover_incomplete("recovery/mw10-commit", 50)
	_assert_ok(recovered, "Commit recovery failed")
	_assert(String(recovered["details"]["actions"][0]["action"]) == "COMPLETE_COMMIT", "Commit recovery action changed")
	_assert(String(restored.latest_record(String(plan["transaction_id"]))["phase"]) == Record.PHASE_COMMITTED, "Commit recovery did not finish global commit")
	_assert(runtime.published_by_id.size() == 1, "Commit recovery did not publish invalidation")
	_assert(_count_prefix(runtime.calls, "commit:%s" % Fixture.REGION_A) == 1, "Recovery recommitted durable participant A")
	_assert(_count_prefix(runtime.calls, "commit:%s" % Fixture.REGION_B) == 1, "Recovery did not commit participant B exactly once")

	var outbox_root: String = _root("outbox-recovery")
	var outbox_runtime := FakeRuntime.new()
	outbox_runtime.reject_publish = true
	var outbox_seed = _new_coordinator(outbox_root, outbox_runtime)
	_assert_ok(outbox_seed.initialize(Fixture.CHECKPOINT_ID, 20), "Outbox initialize failed")
	var outbox_plan: Dictionary = Fixture.plan_ab("matter-transaction/mw10-outbox", "matter-operation/mw10-outbox")
	_assert_ok(outbox_seed.begin_transaction(outbox_plan, "transition/mw10-outbox-begin", 30), "Outbox begin failed")
	_assert_ok(outbox_seed.prepare_all(String(outbox_plan["transaction_id"]), "transition/mw10-outbox-prepare", 31), "Outbox prepare failed")
	_assert_ok(outbox_seed.decide_commit(String(outbox_plan["transaction_id"]), "transition/mw10-outbox-decision", 35), "Outbox decision failed")
	_assert_fail(outbox_seed.commit_all(String(outbox_plan["transaction_id"]), "transition/mw10-outbox-commit", 36, true), "Rejected outbox publication succeeded")
	_assert(String(outbox_seed.latest_record(String(outbox_plan["transaction_id"]))["phase"]) == Record.PHASE_COMMITTED, "Publish failure rolled back global commit")
	_assert(not bool(outbox_seed.checkpoint()["invalidation_outbox"][0]["published"]), "Failed publication marked outbox published")
	outbox_runtime.reject_publish = false
	var outbox_restored = _new_coordinator(outbox_root, outbox_runtime)
	_assert_ok(outbox_restored.restore_latest(), "Outbox restore failed")
	_assert_ok(outbox_restored.recover_incomplete("recovery/mw10-outbox", 60), "Outbox recovery failed")
	_assert(bool(outbox_restored.checkpoint()["invalidation_outbox"][0]["published"]), "Outbox recovery did not persist publication")
	_assert(outbox_runtime.published_by_id.size() == 1, "Outbox recovery did not deduplicate publication by ID")


func _test_authority_and_reservation_fences() -> void:
	var root: String = _root("fences")
	var runtime := FakeRuntime.new()
	var coordinator = _new_coordinator(root, runtime)
	_assert_ok(coordinator.initialize(Fixture.CHECKPOINT_ID, 20), "Fence initialize failed")
	var plan_ab: Dictionary = Fixture.plan_ab("matter-transaction/mw10-fence-ab", "matter-operation/mw10-fence-ab")
	_assert_ok(coordinator.begin_transaction(plan_ab, "transition/mw10-fence-ab", 30), "Fence AB begin failed")
	var plan_bc: Dictionary = Fixture.plan_bc("matter-transaction/mw10-fence-bc", "matter-operation/mw10-fence-bc")
	var overlap: Dictionary = coordinator.begin_transaction(plan_bc, "transition/mw10-fence-bc", 31)
	_assert_fail(overlap, "Overlapping transaction reserved region B twice")
	_assert(String(overlap.get("error_code", "")) == "MATTER_CROSS_REGION_REGION_ALREADY_RESERVED", "Overlap returned wrong error")

	var stale_root: String = _root("stale-fence")
	var stale_runtime := FakeRuntime.new()
	var stale = _new_coordinator(stale_root, stale_runtime)
	_assert_ok(stale.initialize(Fixture.CHECKPOINT_ID, 20), "Stale fence initialize failed")
	var a: Dictionary = Fixture.participant(Fixture.REGION_A, Fixture.OWNER_A, 0, 3)
	var renewed_lease: Dictionary = Lease.renew(
		Fixture.lease(Fixture.REGION_B, Fixture.OWNER_B, 1, 4),
		"transition/mw10-stale-renew", 20, 100, 1000
	)
	var previous_b: Dictionary = Fixture.participant(Fixture.REGION_B, Fixture.OWNER_B, 1, 4)["previous_source_revision"]
	var stale_b: Dictionary = Participant.create({
		"region_id": Fixture.REGION_B,
		"body_id": Fixture.BODY_ID,
		"region_root_address": Fixture.root_address(1),
		"owner_id": Fixture.OWNER_B,
		"authority_epoch": 4,
		"lease_revision": renewed_lease["lease_revision"],
		"fencing_token": renewed_lease["fencing_token"],
		"previous_source_revision": previous_b,
		"mutation_payload": {"shape": "swept-sphere", "segment_id": "mutation-segment/stale", "sample_radius_m": 1.0},
		"dirty_bounds_m": [10.0, -1.0, -1.0, 18.0, 1.0, 1.0],
		"affected_scope_ids": ["matter-scope/mw10-b", "matter-scope/mw10-b-root"],
	})
	var stale_tx := "matter-transaction/mw10-stale"
	var ledger: Dictionary = MassLedger.create(stale_tx, [
		{"region_id": Fixture.REGION_A, "removed": [{"material_id": "matter/basalt", "mass_kg": 5.0}], "added": []},
		{"region_id": Fixture.REGION_B, "removed": [{"material_id": "matter/basalt", "mass_kg": 5.0}], "added": []},
	], [], [{"material_id": "matter/basalt", "mass_kg": 10.0}])
	var stale_plan: Dictionary = Plan.create({
		"transaction_id": stale_tx,
		"operation_id": "matter-operation/mw10-stale",
		"body_id": Fixture.BODY_ID,
		"created_tick": 30,
		"participants": [a, stale_b],
		"mass_ledger": ledger,
	})
	_assert_ok(Plan.validate(stale_plan), "Stale fence plan contract invalid")
	var stale_result: Dictionary = stale.begin_transaction(stale_plan, "transition/mw10-stale", 30)
	_assert_fail(stale_result, "Stale lease revision passed authority gate")
	_assert(String(stale_result.get("error_code", "")) == "MATTER_CROSS_REGION_AUTHORITY_FENCE_MISMATCH", "Stale fence returned wrong error")


func _test_durable_binding_hardening() -> void:
	var root: String = _root("durable-binding")
	var runtime := FakeRuntime.new()
	var coordinator = _new_coordinator(root, runtime)
	_assert_ok(coordinator.initialize(Fixture.CHECKPOINT_ID, 20), "Binding initialize failed")
	var plan: Dictionary = Fixture.plan_ab("matter-transaction/mw10-binding", "matter-operation/mw10-binding")
	_assert_ok(coordinator.begin_transaction(plan, "transition/mw10-binding-begin", 30), "Binding begin failed")
	var begin_checkpoint: Dictionary = coordinator.checkpoint()
	_assert_ok(coordinator.prepare_next(String(plan["transaction_id"]), "transition/mw10-binding-prepare-a", 31), "Binding prepare A failed")
	var preparing_checkpoint: Dictionary = coordinator.checkpoint()
	_assert_ok(coordinator.prepare_next(String(plan["transaction_id"]), "transition/mw10-binding-prepare-b", 32), "Binding prepare B failed")
	var prepared: Dictionary = coordinator.latest_record(String(plan["transaction_id"]))
	var participant_a: Dictionary = plan["participants"][0]
	var previous_a: Dictionary = participant_a["previous_source_revision"]
	var forged_prepare_source: Dictionary = SourceRevision.create(
		"MATTER", String(previous_a["source_id"]), int(previous_a["authority_epoch"]),
		int(previous_a["source_revision"]), MatterUtils.payload_hash("forged-source"),
		MatterUtils.payload_hash("forged-dependency")
	)
	var forged_prepare: Dictionary = Receipt.create({
		"transaction_id": plan["transaction_id"],
		"region_id": participant_a["region_id"],
		"action": Receipt.ACTION_PREPARE,
		"participant_checksum": participant_a["checksum"],
		"prepare_receipt_checksum": "",
		"source_revision": forged_prepare_source,
		"runtime_state_hash": MatterUtils.payload_hash("forged-prepare-state"),
		"created_tick": 31,
	})
	_assert_ok(Receipt.validate(forged_prepare), "Forged prepare fixture is not structurally valid")
	var forged_prepared_record: Dictionary = prepared.duplicate(true)
	forged_prepared_record["prepare_receipts"][0] = forged_prepare
	forged_prepared_record["checksum"] = MatterUtils.compute_checksum(forged_prepared_record)
	_assert_fail(Record.validate(forged_prepared_record), "Persisted record accepted non-advancing prepare source")

	_assert_ok(coordinator.decide_commit(String(plan["transaction_id"]), "transition/mw10-binding-decision", 33), "Binding decision failed")
	var decided: Dictionary = coordinator.latest_record(String(plan["transaction_id"]))
	var forged_hash_record: Dictionary = decided.duplicate(true)
	forged_hash_record["global_commit_hash"] = MatterUtils.payload_hash("forged-global-commit")
	forged_hash_record["checksum"] = MatterUtils.compute_checksum(forged_hash_record)
	_assert_fail(Record.validate(forged_hash_record), "Persisted record accepted forged global commit hash")
	_assert_ok(coordinator.commit_next(String(plan["transaction_id"]), "transition/mw10-binding-commit-a", 34), "Binding commit A failed")
	var committing: Dictionary = coordinator.latest_record(String(plan["transaction_id"]))
	var original_commit: Dictionary = committing["commit_receipts"][0]
	var forged_commit: Dictionary = Receipt.create({
		"transaction_id": original_commit["transaction_id"],
		"region_id": original_commit["region_id"],
		"action": Receipt.ACTION_COMMIT,
		"participant_checksum": original_commit["participant_checksum"],
		"prepare_receipt_checksum": MatterUtils.payload_hash("wrong-prepare-parent"),
		"source_revision": original_commit["source_revision"],
		"runtime_state_hash": original_commit["runtime_state_hash"],
		"created_tick": original_commit["created_tick"],
	})
	_assert_ok(Receipt.validate(forged_commit), "Forged commit fixture is not structurally valid")
	var forged_committing_record: Dictionary = committing.duplicate(true)
	forged_committing_record["commit_receipts"][0] = forged_commit
	forged_committing_record["checksum"] = MatterUtils.compute_checksum(forged_committing_record)
	_assert_fail(Record.validate(forged_committing_record), "Persisted record accepted wrong prepare parent")
	_assert_ok(coordinator.commit_next(String(plan["transaction_id"]), "transition/mw10-binding-commit-b", 35), "Binding commit B failed")
	var terminal: Dictionary = coordinator.latest_record(String(plan["transaction_id"]))
	var original_invalidation: Dictionary = terminal["invalidation_batch"]["invalidations"][0]
	var forged_invalidation: Dictionary = Invalidation.create(
		String(original_invalidation["invalidation_id"]), original_invalidation["previous_source_revision"],
		original_invalidation["new_source_revision"], [-99.0, -99.0, -99.0, -98.0, -98.0, -98.0],
		String(original_invalidation["reason"]), original_invalidation["affected_scope_ids"],
		int(original_invalidation["created_tick"])
	)
	_assert_ok(Invalidation.validate(forged_invalidation), "Forged invalidation fixture is not structurally valid")
	var invalidations: Array = Array(terminal["invalidation_batch"]["invalidations"]).duplicate(true)
	invalidations[0] = forged_invalidation
	var forged_batch: Dictionary = InvalidationBatch.create(
		String(terminal["invalidation_batch"]["batch_id"]), String(terminal["transaction_id"]),
		String(terminal["global_commit_hash"]), invalidations, int(terminal["created_tick"])
	)
	_assert_ok(InvalidationBatch.validate(forged_batch), "Forged batch fixture is not structurally valid")
	var forged_terminal: Dictionary = terminal.duplicate(true)
	forged_terminal["invalidation_batch"] = forged_batch
	forged_terminal["checksum"] = MatterUtils.compute_checksum(forged_terminal)
	_assert_fail(Record.validate(forged_terminal), "Committed record accepted invalidation bound to wrong dirty bounds")

	var mutated_reservations: Array = Array(preparing_checkpoint["region_reservations"]).duplicate(true)
	var old_reservation: Dictionary = mutated_reservations[0]
	mutated_reservations[0] = Reservation.create(
		String(old_reservation["region_id"]), String(old_reservation["transaction_id"]),
		String(old_reservation["participant_checksum"]), int(old_reservation["acquired_tick"]) + 1
	)
	var forged_checkpoint: Dictionary = Checkpoint.create({
		"checkpoint_id": preparing_checkpoint["checkpoint_id"],
		"generation": preparing_checkpoint["generation"],
		"server_tick": preparing_checkpoint["server_tick"],
		"previous_checkpoint_checksum": begin_checkpoint["checksum"],
		"transaction_records": preparing_checkpoint["transaction_records"],
		"region_reservations": mutated_reservations,
		"operation_results": preparing_checkpoint["operation_results"],
		"invalidation_outbox": preparing_checkpoint["invalidation_outbox"],
	})
	_assert_ok(Checkpoint.validate(forged_checkpoint), "Mutated reservation checkpoint fixture is not standalone-valid")
	_assert_fail(Checkpoint.validate_progression(forged_checkpoint, begin_checkpoint), "Checkpoint progression accepted mutated reservation history")


func _test_handoff_interlock_and_authority_race() -> void:
	var root: String = _root("handoff-interlock")
	var runtime := FakeRuntime.new()
	var coordinator = _new_coordinator(root, runtime)
	_assert_ok(coordinator.initialize(Fixture.CHECKPOINT_ID, 20), "Interlock initialize failed")
	var plan: Dictionary = Fixture.plan_ab("matter-transaction/mw10-interlock", "matter-operation/mw10-interlock")
	_assert_ok(coordinator.begin_transaction(plan, "transition/mw10-interlock-begin", 30), "Interlock begin failed")
	var interlock := HandoffInterlock.new()
	_assert_ok(interlock.configure(coordinator), "Interlock configure failed")
	var blocked: Dictionary = interlock.validate_handoff(Fixture.REGION_A)
	_assert_fail(blocked, "Handoff interlock allowed reserved region A")
	_assert(String(blocked.get("error_code", "")) == "MATTER_CROSS_REGION_TRANSACTION_RESERVES_HANDOFF_REGION", "Handoff interlock returned wrong error")
	_assert(String(interlock.reserved_transaction(Fixture.REGION_B).get("transaction_id", "")) == String(plan["transaction_id"]), "Interlock lost transaction reservation binding")
	_assert_ok(interlock.validate_handoff(Fixture.REGION_C), "Interlock blocked unrelated region C")
	_assert_ok(coordinator.decide_abort(String(plan["transaction_id"]), "transition/mw10-interlock-abort", 31), "Interlock abort decision failed")
	_assert_ok(coordinator.rollback_all(String(plan["transaction_id"]), "transition/mw10-interlock-rollback", 32), "Interlock abort finalization failed")
	_assert_ok(interlock.validate_handoff(Fixture.REGION_A), "Interlock did not release region after terminal abort")

	var race_root: String = _root("authority-race")
	var race_runtime := FakeRuntime.new()
	var flapping_gate := FlappingAuthorityGate.new()
	var race := Coordinator.new()
	_assert_ok(race.configure(race_root, flapping_gate, race_runtime), "Authority race coordinator configure failed")
	_assert_ok(race.initialize(Fixture.CHECKPOINT_ID, 20), "Authority race initialize failed")
	var race_plan: Dictionary = Fixture.plan_ab("matter-transaction/mw10-authority-race", "matter-operation/mw10-authority-race")
	var race_result: Dictionary = race.begin_transaction(race_plan, "transition/mw10-authority-race", 30)
	_assert_fail(race_result, "Authority change between validation and reservation was accepted")
	_assert(String(race_result.get("error_code", "")) == "MATTER_CROSS_REGION_AUTHORITY_CHANGED_DURING_RESERVATION", "Authority race returned wrong error")
	_assert(Array(race.checkpoint()["region_reservations"]).is_empty(), "Authority race left durable reservations")
	_assert(String(race.latest_record(String(race_plan["transaction_id"]))["phase"]) == Record.PHASE_ABORTED, "Authority race did not persist terminal abort")
	_assert(String(race.operation_result(String(race_plan["operation_id"]))["outcome"]) == "ABORTED", "Authority race terminal result missing")
	_assert(race_runtime.calls.is_empty(), "Authority race invoked Matter runtime before stable reservation")


func _test_repository_fallback() -> void:
	var root: String = _root("fallback")
	var runtime := FakeRuntime.new()
	var coordinator = _new_coordinator(root, runtime)
	_assert_ok(coordinator.initialize(Fixture.CHECKPOINT_ID, 20), "Fallback initialize failed")
	var plan: Dictionary = Fixture.plan_ab("matter-transaction/mw10-fallback", "matter-operation/mw10-fallback")
	_assert_ok(coordinator.begin_transaction(plan, "transition/mw10-fallback-begin", 30), "Fallback begin failed")
	var active_path: String = coordinator.repository().active_path()
	var previous_path: String = coordinator.repository().previous_path()
	_assert(FileAccess.file_exists(active_path), "Fallback active checkpoint missing")
	_assert(FileAccess.file_exists(previous_path), "Fallback previous checkpoint missing")
	var file := FileAccess.open(active_path, FileAccess.WRITE)
	_assert(file != null, "Fallback could not corrupt active checkpoint")
	if file != null:
		file.store_string("{corrupt")
		file.close()
	var restored = _new_coordinator(root, runtime)
	var loaded: Dictionary = restored.restore_latest()
	_assert_ok(loaded, "Fallback restore failed")
	_assert(String(loaded["details"].get("source", "")) == "PREVIOUS_RECOVERY", "Fallback did not select previous checkpoint")
	_assert(int(restored.checkpoint()["generation"]) == 1, "Fallback selected wrong checkpoint generation")
	_assert(FileAccess.file_exists(active_path), "Fallback did not repair active checkpoint")
	_assert_ok(Checkpoint.validate(restored.checkpoint()), "Fallback repaired checkpoint invalid")


func _new_coordinator(root: String, runtime: FakeRuntime):
	var gate := AuthorityGate.new()
	_assert_ok(gate.configure(Fixture.lease_provider()), "Authority gate configure failed")
	var coordinator := Coordinator.new()
	_assert_ok(coordinator.configure(root, gate, runtime), "Coordinator configure failed")
	return coordinator


func _root(label: String) -> String:
	var path: String = ProjectSettings.globalize_path("user://mw10-focused-%s-%d" % [label, Time.get_ticks_usec()])
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	roots.append(path)
	return path


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, String(result.get("error_code", ""))])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _count_prefix(values: Array[String], expected: String) -> int:
	var count := 0
	for value in values:
		if value == expected:
			count += 1
	return count


func _cleanup() -> void:
	for root in roots:
		_remove_tree(root)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)
