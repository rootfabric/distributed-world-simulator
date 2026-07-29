extends SceneTree

const RegistryScript = preload("res://scripts/simulation/aggregates/aggregate_adapter_registry.gd")
const AdapterScript = preload("res://tests/simulation/fixtures/test_transaction_aggregate_adapter.gd")
const FactoryScript = preload("res://tests/simulation/fixtures/test_transaction_snapshot_factory.gd")
const RepositoryScript = preload("res://scripts/simulation/transactions/aggregate_transaction_repository.gd")
const CoordinatorScript = preload("res://scripts/simulation/transactions/aggregate_transaction_coordinator.gd")
const InvariantRegistryScript = preload("res://scripts/simulation/transactions/transaction_invariant_registry.gd")
const ConservationValidatorScript = preload("res://tests/simulation/fixtures/test_item_location_conservation_validator.gd")
const PreconditionScript = preload("res://scripts/simulation/transactions/aggregate_precondition.gd")
const OperationScript = preload("res://scripts/simulation/transactions/aggregate_mutation_operation.gd")
const IntentScript = preload("res://scripts/simulation/transactions/outbox_intent.gd")
const BatchScript = preload("res://scripts/simulation/transactions/mutation_batch.gd")

var assertions: int = 0
var failures: Array[String] = []
var _root: String


func _init() -> void:
	_root = "user://m0-integration-%d" % Time.get_ticks_usec()
	_test_atomic_move_and_replay()
	_test_cross_aggregate_conservation_rejection()
	_test_rollback_and_fault_recovery()
	_test_materialize_create_and_outbox_independence()
	_finish()


func _new_runtime(suffix: String, snapshots: Array = []) -> Dictionary:
	var registry := RegistryScript.new(); _assert_ok(registry.setup(), "Registry setup failed")
	_assert_ok(registry.register_adapter(AdapterScript.new()), "Adapter registration failed")
	var repository := RepositoryScript.new(); _assert_ok(repository.configure(_root.path_join(suffix)), "Repository configure failed")
	var invariant_registry := InvariantRegistryScript.new(); _assert_ok(invariant_registry.setup(), "Invariant registry setup failed")
	_assert_ok(invariant_registry.register_validator(ConservationValidatorScript.new()), "Conservation validator registration failed")
	var coordinator := CoordinatorScript.new(); _assert_ok(coordinator.configure(registry, repository, invariant_registry), "Coordinator configure failed")
	if not snapshots.is_empty(): _assert_ok(coordinator.bootstrap(snapshots), "Coordinator bootstrap failed")
	return {"registry": registry, "repository": repository, "coordinator": coordinator}


func _base_snapshots() -> Array:
	return [
		FactoryScript.create_snapshot("aggregate/container/a", 0, 1, "CONTAINER", "", {"aggregate/item/b": true}, 0, {"name": "A"}),
		FactoryScript.create_snapshot("aggregate/container/c", 0, 1, "CONTAINER", "", {}, 0, {"name": "C"}),
		FactoryScript.create_snapshot("aggregate/item/b", 0, 1, "ITEM", "aggregate/container/a", {}, 1, {"type": "beacon"}),
	]


func _move_batch(operation_id: String = "operation/move-item-b") -> Dictionary:
	var ids := ["aggregate/container/a", "aggregate/container/c", "aggregate/item/b"]
	var preconditions: Array = []
	for id in ids: preconditions.append(PreconditionScript.create(id, AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, true, "authority/test-main", 3, 0))
	var operations := [
		OperationScript.create(OperationScript.OP_UPDATE, ids[0], AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, FactoryScript.create_snapshot(ids[0], 1, 10, "CONTAINER", "", {}, 0, {"name": "A"})),
		OperationScript.create(OperationScript.OP_UPDATE, ids[1], AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, FactoryScript.create_snapshot(ids[1], 1, 10, "CONTAINER", "", {ids[2]: true}, 0, {"name": "C"})),
		OperationScript.create(OperationScript.OP_UPDATE, ids[2], AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, FactoryScript.create_snapshot(ids[2], 1, 10, "ITEM", ids[1], {}, 1, {"type": "beacon"})),
	]
	return BatchScript.create("batch/move-item-b", operation_id, "authority/test-main", 3, 10, preconditions, operations, [IntentScript.create("outbox-intent/item-b-moved", "stream/domain-events", "planet_simulator.item_moved.v1", {"item_id": ids[2], "from": ids[0], "to": ids[1]})])


func _test_atomic_move_and_replay() -> void:
	var runtime := _new_runtime("move", _base_snapshots())
	var coordinator = runtime["coordinator"]
	var before: Dictionary = coordinator.get_state_report(); _assert_ok(before, "Initial report failed")
	var committed: Dictionary = coordinator.execute_batch(_move_batch()); _assert_ok(committed, "Atomic move failed")
	_assert(not bool(committed["details"]["replay"]), "First move marked replay")
	var result: Dictionary = committed["details"]["result"]
	_assert(result["updated_aggregate_ids"].size() == 3 and result["outbox_record_ids"] == ["outbox/item-b-moved"], "Move result did not include all effects")
	var a: Dictionary = coordinator.get_snapshot("aggregate/container/a"); var c: Dictionary = coordinator.get_snapshot("aggregate/container/c"); var item: Dictionary = coordinator.get_snapshot("aggregate/item/b")
	_assert_ok(a, "Container A missing"); _assert_ok(c, "Container C missing"); _assert_ok(item, "Item missing")
	_assert(a["details"]["snapshot"]["state"]["members_by_id"].is_empty(), "Container A retained item")
	_assert(bool(c["details"]["snapshot"]["state"]["members_by_id"].get("aggregate/item/b", false)), "Container C did not receive item")
	_assert(String(item["details"]["snapshot"]["state"]["container_id"]) == "aggregate/container/c", "Item relation not updated")
	var after: Dictionary = coordinator.get_state_report(); _assert(int(after["details"]["generation"]) == int(before["details"]["generation"]) + 1, "Transaction did not make one generation")
	var replay: Dictionary = coordinator.execute_batch(_move_batch()); _assert_ok(replay, "Exact replay failed")
	_assert(bool(replay["details"]["replay"]), "Exact replay mutated again")
	_assert(String(replay["details"]["result"]["checksum"]) == String(result["checksum"]), "Replay result changed")
	var replay_report: Dictionary = coordinator.get_state_report(); _assert(int(replay_report["details"]["generation"]) == int(after["details"]["generation"]), "Replay advanced generation")
	var conflict := _move_batch("operation/move-item-b"); conflict["server_tick"] = 11; conflict["checksum"] = BatchScript.compute_checksum(conflict)
	_assert_error(coordinator.execute_batch(conflict), "MUTATION_OPERATION_ID_CONFLICT", "Changed batch reused operation ID")


func _test_cross_aggregate_conservation_rejection() -> void:
	var runtime := _new_runtime("conservation", _base_snapshots())
	var coordinator = runtime["coordinator"]
	var before: Dictionary = coordinator.get_state_report(); _assert_ok(before, "Conservation baseline report failed")
	var invalid := _move_batch("operation/invalid-double-membership")
	invalid["operations"][0] = OperationScript.create(
		OperationScript.OP_UPDATE,
		"aggregate/container/a",
		AdapterScript.AGGREGATE_KIND,
		AdapterScript.STATE_SCHEMA,
		FactoryScript.create_snapshot("aggregate/container/a", 1, 10, "CONTAINER", "", {"aggregate/item/b": true}, 0, {"name": "A"})
	)
	invalid["checksum"] = BatchScript.compute_checksum(invalid)
	var rejected: Dictionary = coordinator.execute_batch(invalid)
	_assert_error(rejected, "TRANSACTION_INVARIANT_REJECTED", "Cross-aggregate double membership accepted")
	var after: Dictionary = coordinator.get_state_report(); _assert_ok(after, "Conservation post-rejection report failed")
	_assert(String(after["details"]["state_checksum"]) == String(before["details"]["state_checksum"]), "Rejected conservation batch changed state")
	var item: Dictionary = coordinator.get_snapshot("aggregate/item/b"); _assert_ok(item, "Item missing after conservation rejection")
	_assert(String(item["details"]["snapshot"]["state"]["container_id"]) == "aggregate/container/a", "Rejected conservation batch changed item relation")


func _test_rollback_and_fault_recovery() -> void:
	var runtime := _new_runtime("fault", _base_snapshots())
	var coordinator = runtime["coordinator"]; var repository = runtime["repository"]
	var bad := _move_batch("operation/stale-move"); bad["preconditions"][0]["expected_revision"] = 99; bad["checksum"] = BatchScript.compute_checksum(bad)
	var before: Dictionary = coordinator.get_state_report()
	_assert_error(coordinator.execute_batch(bad), "AGGREGATE_REVISION_PRECONDITION_FAILED", "Stale batch accepted")
	var after: Dictionary = coordinator.get_state_report(); _assert(String(after["details"]["state_checksum"]) == String(before["details"]["state_checksum"]), "Rejected batch changed state")
	var prepared_failure: Dictionary = coordinator.execute_batch(_move_batch("operation/fault-before-commit"), {"fault_point": "AFTER_PREPARE"})
	_assert_error(prepared_failure, "FAULT_INJECTED_AFTER_PREPARE", "Prepare fault did not stop commit")
	_assert(repository.list_pending_files().size() == 1, "Prepare fault did not leave one pending file")
	var restart := _new_runtime("fault")
	var restarted = restart["coordinator"]
	var unchanged: Dictionary = restarted.get_snapshot("aggregate/item/b"); _assert(String(unchanged["details"]["snapshot"]["state"]["container_id"]) == "aggregate/container/a", "Pending state became authoritative")
	_assert_ok(restart["repository"].cleanup_pending_files(), "Pending cleanup failed")
	_assert(restart["repository"].list_pending_files().is_empty(), "Pending cleanup incomplete")
	var after_commit_fault: Dictionary = restarted.execute_batch(_move_batch("operation/fault-after-commit"), {"fault_point": "AFTER_COMMIT"})
	_assert_error(after_commit_fault, "FAULT_INJECTED_AFTER_COMMIT", "After-commit fault not surfaced")
	var recovered = _new_runtime("fault")["coordinator"]
	var replay: Dictionary = recovered.execute_batch(_move_batch("operation/fault-after-commit")); _assert_ok(replay, "Committed operation not replayable after crash")
	_assert(bool(replay["details"]["replay"]), "Recovered operation mutated twice")


func _test_materialize_create_and_outbox_independence() -> void:
	var field := FactoryScript.create_snapshot("aggregate/field/grass", 0, 1, "FIELD", "", {}, 100, {"generation": 1})
	var runtime := _new_runtime("materialize", [field]); var coordinator = runtime["coordinator"]
	var field_next := FactoryScript.create_snapshot("aggregate/field/grass", 1, 20, "FIELD", "", {"aggregate/item/grass-1": true}, 99, {"generation": 1})
	var item_new := FactoryScript.create_snapshot("aggregate/item/grass-1", 0, 20, "ITEM", "", {}, 1, {"origin": "aggregate/field/grass"})
	var preconditions := [
		PreconditionScript.create("aggregate/field/grass", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, true, "authority/test-main", 3, 0),
		PreconditionScript.create("aggregate/item/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, false, "", 0, -1),
	]
	var operations := [
		OperationScript.create(OperationScript.OP_UPDATE, "aggregate/field/grass", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, field_next),
		OperationScript.create(OperationScript.OP_CREATE, "aggregate/item/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, item_new),
	]
	var batch := BatchScript.create("batch/materialize-grass", "operation/materialize-grass", "authority/test-main", 3, 20, preconditions, operations, [IntentScript.create("outbox-intent/grass-materialized", "stream/domain-events", "planet_simulator.aggregate_materialized.v1", {"field_id": "aggregate/field/grass", "item_id": "aggregate/item/grass-1"})])
	var committed: Dictionary = coordinator.execute_batch(batch); _assert_ok(committed, "Materialization transaction failed")
	_assert(committed["details"]["result"]["created_aggregate_ids"] == ["aggregate/item/grass-1"], "Created aggregate missing from result")
	var unpublished: Dictionary = coordinator.list_unpublished_outbox(); _assert_ok(unpublished, "Outbox listing failed")
	_assert(unpublished["details"]["records"].size() == 1, "Committed outbox record missing")
	var record: Dictionary = unpublished["details"]["records"][0]
	var before_field: Dictionary = coordinator.get_snapshot("aggregate/field/grass")
	var before_item: Dictionary = coordinator.get_snapshot("aggregate/item/grass-1")
	var marked: Dictionary = coordinator.mark_outbox_published(String(record["record_id"]), String(record["delivery_checksum"])); _assert_ok(marked, "Outbox publish mark failed")
	var after_field: Dictionary = coordinator.get_snapshot("aggregate/field/grass"); var after_item: Dictionary = coordinator.get_snapshot("aggregate/item/grass-1")
	_assert(String(before_field["details"]["snapshot"]["checksum"]) == String(after_field["details"]["snapshot"]["checksum"]), "Outbox state changed field aggregate")
	_assert(String(before_item["details"]["snapshot"]["checksum"]) == String(after_item["details"]["snapshot"]["checksum"]), "Outbox state changed item aggregate")
	var empty: Dictionary = coordinator.list_unpublished_outbox(); _assert(empty["details"]["records"].is_empty(), "Published record remained pending")
	var replay_mark: Dictionary = coordinator.mark_outbox_published(String(record["record_id"]), String(marked["details"]["record"]["delivery_checksum"])); _assert_ok(replay_mark, "Published record replay failed")
	_assert(bool(replay_mark["details"]["replay"]), "Published record replay not identified")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty():
		print("M0 aggregate transaction integration: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("M0 aggregate transaction integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
