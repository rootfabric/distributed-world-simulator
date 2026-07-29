extends SceneTree

const PreconditionScript = preload("res://scripts/simulation/transactions/aggregate_precondition.gd")
const OperationScript = preload("res://scripts/simulation/transactions/aggregate_mutation_operation.gd")
const IntentScript = preload("res://scripts/simulation/transactions/outbox_intent.gd")
const BatchScript = preload("res://scripts/simulation/transactions/mutation_batch.gd")
const AffectedScript = preload("res://scripts/simulation/transactions/affected_aggregate_result.gd")
const ResultScript = preload("res://scripts/simulation/transactions/mutation_batch_result.gd")
const OutboxScript = preload("res://scripts/simulation/transactions/outbox_record.gd")
const StateScript = preload("res://scripts/simulation/transactions/aggregate_transaction_state.gd")
const RepositoryScript = preload("res://scripts/simulation/transactions/aggregate_transaction_repository.gd")
const CoordinatorScript = preload("res://scripts/simulation/transactions/aggregate_transaction_coordinator.gd")
const InvariantPortScript = preload("res://scripts/simulation/transactions/transaction_invariant_validator_port.gd")
const InvariantRegistryScript = preload("res://scripts/simulation/transactions/transaction_invariant_registry.gd")
const ConservationValidatorScript = preload("res://tests/simulation/fixtures/test_item_location_conservation_validator.gd")
const FactoryScript = preload("res://tests/simulation/fixtures/test_transaction_snapshot_factory.gd")
const AdapterScript = preload("res://tests/simulation/fixtures/test_transaction_aggregate_adapter.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_preconditions()
	_test_operations()
	_test_batch_canonicalization()
	_test_results_and_outbox()
	_test_state_and_repository_contracts()
	_test_invariant_registry_contracts()
	_test_runner_contracts()
	_finish()


func _test_preconditions() -> void:
	var existing := PreconditionScript.create("aggregate/item/a", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, true, "authority/test-main", 3, 4)
	_assert_ok(PreconditionScript.validate(existing), "Existing precondition rejected")
	var absent := PreconditionScript.create("aggregate/item/new", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, false, "", 0, -1)
	_assert_ok(PreconditionScript.validate(absent), "Absent precondition rejected")
	var invalid := absent.duplicate(true); invalid["expected_revision"] = 0
	_assert_error(PreconditionScript.validate(invalid), "INVALID_ABSENT_AGGREGATE_PRECONDITION", "Absent aggregate accepted with revision")
	invalid = existing.duplicate(true); invalid["expected_authority_epoch"] = 0
	_assert_error(PreconditionScript.validate(invalid), "INVALID_EXISTING_AGGREGATE_PRECONDITION", "Existing aggregate accepted without epoch")


func _test_operations() -> void:
	var snapshot := FactoryScript.create_snapshot("aggregate/item/a", 5, 20, "ITEM", "aggregate/container/c", {}, 1)
	var update := OperationScript.create(OperationScript.OP_UPDATE, "aggregate/item/a", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, snapshot)
	_assert_ok(OperationScript.validate(update), "Update operation rejected")
	var create := OperationScript.create(OperationScript.OP_CREATE, "aggregate/item/a", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, snapshot)
	_assert_ok(OperationScript.validate(create), "Create operation rejected structurally")
	var delete := OperationScript.create(OperationScript.OP_DELETE, "aggregate/item/a", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {})
	_assert_ok(OperationScript.validate(delete), "Delete operation rejected")
	var delete_with_state := delete.duplicate(true); delete_with_state["result_snapshot"] = snapshot
	_assert_error(OperationScript.validate(delete_with_state), "DELETE_OPERATION_MUST_NOT_HAVE_RESULT_SNAPSHOT", "Delete accepted result snapshot")
	var mismatch := update.duplicate(true); mismatch["aggregate_id"] = "aggregate/item/b"
	_assert_error(OperationScript.validate(mismatch), "AGGREGATE_OPERATION_RESULT_IDENTITY_MISMATCH", "Operation accepted mismatched snapshot identity")


func _test_batch_canonicalization() -> void:
	var ids := ["aggregate/container/a", "aggregate/item/b"]
	var preconditions := [
		PreconditionScript.create(ids[0], AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, true, "authority/test-main", 3, 0),
		PreconditionScript.create(ids[1], AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, true, "authority/test-main", 3, 0),
	]
	var operations := [
		OperationScript.create(OperationScript.OP_UPDATE, ids[0], AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, FactoryScript.create_snapshot(ids[0], 1, 5, "CONTAINER", "", {}, 0)),
		OperationScript.create(OperationScript.OP_UPDATE, ids[1], AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, FactoryScript.create_snapshot(ids[1], 1, 5, "ITEM", "aggregate/container/c", {}, 1)),
	]
	var intents := [IntentScript.create("outbox-intent/item-moved", "stream/domain-events", "planet_simulator.item_moved.v1", {"item_id": ids[1]})]
	var batch := BatchScript.create("batch/test/1", "operation/test/1", "authority/test-main", 3, 5, preconditions, operations, intents)
	_assert_ok(BatchScript.validate(batch), "Valid mutation batch rejected")
	var bad_checksum := batch.duplicate(true); bad_checksum["server_tick"] = 6
	_assert_error(BatchScript.validate(bad_checksum), "MUTATION_BATCH_CHECKSUM_MISMATCH", "Mutated batch accepted stale checksum")
	var reversed := BatchScript.create("batch/test/2", "operation/test/2", "authority/test-main", 3, 5, [preconditions[1], preconditions[0]], [operations[1], operations[0]], intents)
	_assert_error(BatchScript.validate(reversed), "MUTATION_BATCH_AGGREGATES_NOT_SORTED", "Unsorted aggregate operations accepted")
	var duplicate := BatchScript.create("batch/test/3", "operation/test/3", "authority/test-main", 3, 5, [preconditions[0], preconditions[0]], [operations[0], operations[0]], intents)
	_assert_error(BatchScript.validate(duplicate), "MUTATION_BATCH_AGGREGATE_SET_CONFLICT", "Duplicate aggregate operations accepted")
	var adapter_payload: Dictionary = intents[0].duplicate(true); adapter_payload["payload"] = {"nats_subject": "ps.events"}
	_assert_fail(IntentScript.validate(adapter_payload), "Adapter metadata accepted in outbox intent")


func _test_results_and_outbox() -> void:
	var affected := AffectedScript.create("aggregate/item/a", OperationScript.OP_UPDATE, 0, 1, "a".repeat(64))
	_assert_ok(AffectedScript.validate(affected), "Affected aggregate result rejected")
	var result := ResultScript.create("batch/test/1", "operation/test/1", 2, 10, [affected], [], ["aggregate/item/a"], [], ["outbox/item-moved"])
	_assert_ok(ResultScript.validate(result), "Mutation result rejected")
	var record := OutboxScript.create("outbox/item-moved", "batch/test/1", "operation/test/1", "stream/domain-events", "planet_simulator.item_moved.v1", {"item_id": "aggregate/item/a"}, 2, 10)
	_assert_ok(OutboxScript.validate(record), "Outbox record rejected")
	var published := OutboxScript.mark_published(record)
	_assert_ok(OutboxScript.validate(published), "Published outbox record rejected")
	_assert(bool(published["published"]) and int(published["publish_attempts"]) == 1, "Outbox publish state not advanced")
	var bad := published.duplicate(true); bad["publish_attempts"] = 2
	_assert_error(OutboxScript.validate(bad), "OUTBOX_RECORD_CHECKSUM_MISMATCH", "Outbox mutation accepted stale checksum")
	var mismatched_effects := result.duplicate(true)
	mismatched_effects["created_aggregate_ids"] = ["aggregate/item/a"]
	mismatched_effects["updated_aggregate_ids"] = []
	mismatched_effects["checksum"] = ResultScript.compute_checksum(mismatched_effects)
	_assert_error(ResultScript.validate(mismatched_effects), "MUTATION_BATCH_RESULT_EFFECT_SET_MISMATCH", "Result accepted effect lists that disagree with affected aggregates")
	var duplicate_affected := result.duplicate(true)
	duplicate_affected["affected_aggregates"] = [affected, affected]
	duplicate_affected["checksum"] = ResultScript.compute_checksum(duplicate_affected)
	_assert_error(ResultScript.validate(duplicate_affected), "NON_CANONICAL_AFFECTED_AGGREGATE_RESULTS", "Result accepted duplicate affected aggregate")


func _test_state_and_repository_contracts() -> void:
	var empty := StateScript.empty()
	_assert_ok(StateScript.validate(empty), "Empty transaction state rejected")
	var bad := empty.duplicate(true); bad["generation"] = 1
	_assert_error(StateScript.validate(bad), "INVALID_TRANSACTION_STATE_GENERATION_CHAIN", "Broken generation chain accepted")
	var repository := RepositoryScript.new()
	_assert_fail(repository.configure(""), "Repository accepted empty root")
	var root := "user://m0-contract-repository"
	_assert_ok(repository.configure(root), "Repository configuration failed")
	var loaded := repository.load_or_empty()
	_assert_ok(loaded, "Empty repository load failed")
	_assert(int(loaded["details"]["state"]["generation"]) == 0, "Empty repository generation mismatch")


func _test_invariant_registry_contracts() -> void:
	_assert_fail(InvariantPortScript.validate_validator(null), "Null transaction invariant validator accepted")
	_assert_fail(InvariantPortScript.validate_validator(RefCounted.new()), "Incomplete transaction invariant validator accepted")
	var validator := ConservationValidatorScript.new()
	_assert_ok(InvariantPortScript.validate_validator(validator), "Conservation validator rejected by port")
	var registry := InvariantRegistryScript.new()
	_assert_fail(registry.register_validator(validator), "Unconfigured invariant registry accepted registration")
	_assert_ok(registry.setup(), "Invariant registry setup failed")
	_assert_ok(registry.register_validator(validator), "Invariant validator registration failed")
	var replay := registry.register_validator(validator)
	_assert_ok(replay, "Exact invariant validator replay failed")
	_assert(bool(replay.get("details", {}).get("replay", false)), "Invariant validator replay not marked")
	_assert(registry.get_registered_validator_ids() == [ConservationValidatorScript.VALIDATOR_ID], "Invariant registry returned wrong validator IDs")
	var coordinator := CoordinatorScript.new()
	_assert_error(coordinator.configure(null, null, null), "TRANSACTION_ADAPTER_REGISTRY_REQUIRED", "Coordinator accepted missing dependencies")


func _test_runner_contracts() -> void:
	var runner := FileAccess.get_file_as_string("res://RUN_M0_AGGREGATE_TRANSACTION_TESTS.ps1")
	var network_runner := FileAccess.get_file_as_string("res://RUN_NETWORK_CONTRACT_TESTS.ps1")
	var world_runner := FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	_assert(not runner.is_empty(), "M0 PowerShell runner is missing")
	_assert(runner.contains("function Write-JsonFileAtomically"), "M0 runner lacks atomic JSON writer")
	_assert(runner.contains("$Stream.Flush($true)"), "M0 runner does not durably flush summary")
	_assert(runner.contains("[IO.File]::Replace") and runner.contains("[IO.File]::Move"), "M0 runner lacks atomic replace/move publication")
	_assert(runner.contains("PSNativeCommandUseErrorActionPreference"), "M0 runner is not native-stderr safe")
	_assert(runner.contains("finally") and runner.contains("$ErrorActionPreference = $PreviousErrorActionPreference"), "M0 runner does not restore PowerShell preferences")
	_assert(runner.contains("test_m0_aggregate_transaction_contracts.gd"), "M0 runner omits contract tests")
	_assert(runner.contains("test_m0_aggregate_transaction_integration.gd"), "M0 runner omits integration tests")
	_assert(network_runner.contains("test_m0_aggregate_transaction_contracts.gd") and network_runner.contains("test_m0_aggregate_transaction_integration.gd"), "Network profile omits M0 suites")
	_assert(world_runner.contains("test_m0_aggregate_transaction_contracts.gd") and world_runner.contains("test_m0_aggregate_transaction_integration.gd"), "World regression omits M0 suites")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)

func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("M0 aggregate transaction contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("M0 aggregate transaction contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
