extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const BatchScript = preload("res://scripts/simulation/transactions/mutation_batch.gd")
const OperationScript = preload("res://scripts/simulation/transactions/aggregate_mutation_operation.gd")
const AffectedScript = preload("res://scripts/simulation/transactions/affected_aggregate_result.gd")
const ResultScript = preload("res://scripts/simulation/transactions/mutation_batch_result.gd")
const OutboxScript = preload("res://scripts/simulation/transactions/outbox_record.gd")
const StateScript = preload("res://scripts/simulation/transactions/aggregate_transaction_state.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

var _adapter_registry
var _repository
var _invariant_registry
var _configured := false
var _busy := false


func configure(adapter_registry, repository, invariant_registry) -> Dictionary:
	if adapter_registry == null or not adapter_registry.has_method("validate_snapshot"): return TxUtilsScript.failure("TRANSACTION_ADAPTER_REGISTRY_REQUIRED")
	if repository == null or not repository.has_method("load_or_empty") or not repository.has_method("prepare_atomic") or not repository.has_method("commit_prepared"): return TxUtilsScript.failure("TRANSACTION_REPOSITORY_REQUIRED")
	if invariant_registry == null or not invariant_registry.has_method("validate_transaction"): return TxUtilsScript.failure("TRANSACTION_INVARIANT_REGISTRY_REQUIRED")
	_adapter_registry = adapter_registry; _repository = repository; _invariant_registry = invariant_registry; _configured = true
	return TxUtilsScript.success()


func bootstrap(snapshots: Array) -> Dictionary:
	if not _configured: return TxUtilsScript.failure("TRANSACTION_COORDINATOR_NOT_CONFIGURED")
	var loaded: Dictionary = _repository.load_or_empty()
	if not bool(loaded.get("success", false)): return loaded
	var current: Dictionary = loaded["details"]["state"]
	var loaded_validation: Dictionary = _validate_loaded_state(current)
	if not bool(loaded_validation.get("success", false)): return loaded_validation
	if int(current["generation"]) > 0 or not current["aggregates_by_id"].is_empty(): return TxUtilsScript.success({"replay": true, "state": current})
	var aggregates: Dictionary = {}
	for raw in snapshots:
		if typeof(raw) != TYPE_DICTIONARY: return TxUtilsScript.failure("INVALID_BOOTSTRAP_SNAPSHOT")
		var validation: Dictionary = _adapter_registry.validate_snapshot(raw)
		if not bool(validation.get("success", false)): return TxUtilsScript.failure("BOOTSTRAP_SNAPSHOT_REJECTED", {"cause": validation})
		var aggregate_id := SnapshotScript.aggregate_id(raw)
		if aggregates.has(aggregate_id): return TxUtilsScript.failure("DUPLICATE_BOOTSTRAP_AGGREGATE")
		aggregates[aggregate_id] = SnapshotScript.normalize(raw)
	var state := StateScript.create(1, 0, aggregates, {}, {})
	var saved: Dictionary = _repository.save_atomic(state)
	if not bool(saved.get("success", false)): return saved
	return TxUtilsScript.success({"replay": false, "state": state})


func execute_batch(batch: Dictionary, options: Dictionary = {}) -> Dictionary:
	if not _configured: return TxUtilsScript.failure("TRANSACTION_COORDINATOR_NOT_CONFIGURED")
	if _busy: return TxUtilsScript.failure("TRANSACTION_COORDINATOR_BUSY", {"retryable": true})
	var validation: Dictionary = BatchScript.validate(batch)
	if not bool(validation.get("success", false)): return validation
	_busy = true
	var result: Dictionary = _execute_locked(batch, options)
	_busy = false
	return result


func _execute_locked(batch: Dictionary, options: Dictionary) -> Dictionary:
	var loaded: Dictionary = _repository.load_or_empty()
	if not bool(loaded.get("success", false)): return loaded
	var current: Dictionary = loaded["details"]["state"]
	var loaded_validation: Dictionary = _validate_loaded_state(current)
	if not bool(loaded_validation.get("success", false)): return loaded_validation
	var operation_id: String = String(batch["operation_id"])
	if current["operation_records_by_id"].has(operation_id):
		var record: Dictionary = current["operation_records_by_id"][operation_id]
		if String(record["batch_checksum"]) != String(batch["checksum"]): return TxUtilsScript.failure("MUTATION_OPERATION_ID_CONFLICT")
		return TxUtilsScript.success({"replay": true, "result": Dictionary(record["result"]).duplicate(true), "generation": int(current["generation"])})
	var staged_aggregates: Dictionary = current["aggregates_by_id"].duplicate(true)
	var preconditions_by_id: Dictionary = {}
	for precondition in batch["preconditions"]: preconditions_by_id[String(precondition["aggregate_id"])] = precondition
	var affected: Array = []; var created: Array[String] = []; var updated: Array[String] = []; var deleted: Array[String] = []
	for operation in batch["operations"]:
		var aggregate_id: String = String(operation["aggregate_id"])
		var precondition: Dictionary = preconditions_by_id[aggregate_id]
		var check: Dictionary = _check_precondition(staged_aggregates, precondition, batch)
		if not bool(check.get("success", false)): return check
		var kind: String = String(operation["operation_kind"])
		if kind == OperationScript.OP_DELETE:
			var previous: Dictionary = staged_aggregates[aggregate_id]
			var previous_revision := int(previous["descriptor"]["authority"]["state_revision"])
			staged_aggregates.erase(aggregate_id)
			affected.append(AffectedScript.create(aggregate_id, kind, previous_revision, -1, "")); deleted.append(aggregate_id)
			continue
		var snapshot: Dictionary = operation["result_snapshot"]
		var snapshot_validation: Dictionary = _adapter_registry.validate_snapshot(snapshot)
		if not bool(snapshot_validation.get("success", false)): return TxUtilsScript.failure("TRANSACTION_RESULT_SNAPSHOT_REJECTED", {"aggregate_id": aggregate_id, "cause": snapshot_validation})
		var authority: Dictionary = snapshot["descriptor"]["authority"]
		if String(authority["authority_owner_id"]) != String(batch["authority_owner_id"]) or int(authority["authority_epoch"]) != int(batch["authority_epoch"]) or int(authority["server_tick"]) != int(batch["server_tick"]):
			return TxUtilsScript.failure("TRANSACTION_RESULT_AUTHORITY_MISMATCH", {"aggregate_id": aggregate_id})
		var previous_revision := -1
		if kind == OperationScript.OP_CREATE:
			if int(authority["state_revision"]) != 0: return TxUtilsScript.failure("CREATE_RESULT_REVISION_MUST_BE_ZERO")
			created.append(aggregate_id)
		else:
			previous_revision = int(staged_aggregates[aggregate_id]["descriptor"]["authority"]["state_revision"])
			if int(authority["state_revision"]) != previous_revision + 1: return TxUtilsScript.failure("UPDATE_RESULT_REVISION_MUST_INCREMENT")
			var current_identity: Dictionary = staged_aggregates[aggregate_id]["descriptor"]["identity"]
			if snapshot["descriptor"]["identity"] != current_identity: return TxUtilsScript.failure("UPDATE_RESULT_IDENTITY_CHANGED")
			updated.append(aggregate_id)
		staged_aggregates[aggregate_id] = SnapshotScript.normalize(snapshot)
		affected.append(AffectedScript.create(aggregate_id, kind, previous_revision, int(authority["state_revision"]), String(snapshot["checksum"])))
	var generation := int(current["generation"]) + 1
	var staged_outbox: Dictionary = current["outbox_by_id"].duplicate(true)
	var outbox_ids: Array[String] = []
	for intent in batch["outbox_intents"]:
		var record_id := "outbox/%s" % String(intent["intent_id"]).trim_prefix("outbox-intent/")
		if staged_outbox.has(record_id): return TxUtilsScript.failure("OUTBOX_RECORD_ID_CONFLICT")
		var record := OutboxScript.create(record_id, String(batch["batch_id"]), operation_id, String(intent["stream_id"]), String(intent["event_schema"]), intent["payload"], generation, int(batch["server_tick"]))
		staged_outbox[record_id] = record; outbox_ids.append(record_id)
	created.sort(); updated.sort(); deleted.sort(); outbox_ids.sort()
	var invariant_validation: Dictionary = _invariant_registry.validate_transaction(current["aggregates_by_id"], staged_aggregates, batch)
	if not bool(invariant_validation.get("success", false)):
		return invariant_validation
	var result := ResultScript.create(String(batch["batch_id"]), operation_id, generation, int(batch["server_tick"]), affected, created, updated, deleted, outbox_ids)
	var records: Dictionary = current["operation_records_by_id"].duplicate(true)
	records[operation_id] = {"batch_checksum": String(batch["checksum"]), "result": result.duplicate(true)}
	var next_state := StateScript.create(generation, int(current["generation"]), staged_aggregates, records, staged_outbox)
	var prepared: Dictionary = _repository.prepare_atomic(next_state)
	if not bool(prepared.get("success", false)): return prepared
	if String(options.get("fault_point", "")) == "AFTER_PREPARE": return TxUtilsScript.failure("FAULT_INJECTED_AFTER_PREPARE", {"pending_path": prepared["details"]["pending_path"]})
	var committed: Dictionary = _repository.commit_prepared(String(prepared["details"]["pending_path"]))
	if not bool(committed.get("success", false)): return committed
	if String(options.get("fault_point", "")) == "AFTER_COMMIT": return TxUtilsScript.failure("FAULT_INJECTED_AFTER_COMMIT")
	return TxUtilsScript.success({"replay": false, "result": result, "generation": generation})


func _check_precondition(aggregates: Dictionary, precondition: Dictionary, batch: Dictionary) -> Dictionary:
	var aggregate_id: String = String(precondition["aggregate_id"])
	var exists := aggregates.has(aggregate_id)
	if exists != bool(precondition["expected_exists"]): return TxUtilsScript.failure("AGGREGATE_EXISTENCE_PRECONDITION_FAILED", {"aggregate_id": aggregate_id})
	if not exists: return TxUtilsScript.success()
	var snapshot: Dictionary = aggregates[aggregate_id]
	var identity: Dictionary = snapshot["descriptor"]["identity"]
	var authority: Dictionary = snapshot["descriptor"]["authority"]
	if String(identity["aggregate_kind"]) != String(precondition["aggregate_kind"]) or String(identity["state_schema"]) != String(precondition["state_schema"]): return TxUtilsScript.failure("AGGREGATE_IDENTITY_PRECONDITION_FAILED")
	if String(authority["authority_owner_id"]) != String(precondition["expected_authority_owner_id"]) or int(authority["authority_epoch"]) != int(precondition["expected_authority_epoch"]) or int(authority["state_revision"]) != int(precondition["expected_revision"]): return TxUtilsScript.failure("AGGREGATE_REVISION_PRECONDITION_FAILED", {"aggregate_id": aggregate_id})
	if String(authority["authority_owner_id"]) != String(batch["authority_owner_id"]) or int(authority["authority_epoch"]) != int(batch["authority_epoch"]): return TxUtilsScript.failure("BATCH_AUTHORITY_PRECONDITION_FAILED")
	if int(batch["server_tick"]) < int(authority["server_tick"]): return TxUtilsScript.failure("STALE_MUTATION_BATCH_TICK")
	return TxUtilsScript.success()


func get_snapshot(aggregate_id: String) -> Dictionary:
	var loaded: Dictionary = _repository.load_or_empty()
	if not bool(loaded.get("success", false)): return loaded
	var state: Dictionary = loaded["details"]["state"]
	var loaded_validation: Dictionary = _validate_loaded_state(state)
	if not bool(loaded_validation.get("success", false)): return loaded_validation
	var aggregates: Dictionary = state["aggregates_by_id"]
	if not aggregates.has(aggregate_id): return TxUtilsScript.failure("TRANSACTION_AGGREGATE_NOT_FOUND")
	return TxUtilsScript.success({"snapshot": Dictionary(aggregates[aggregate_id]).duplicate(true)})


func list_unpublished_outbox(limit: int = 100) -> Dictionary:
	if limit < 1 or limit > 10000: return TxUtilsScript.failure("INVALID_OUTBOX_LIMIT")
	var loaded: Dictionary = _repository.load_or_empty()
	if not bool(loaded.get("success", false)): return loaded
	var state: Dictionary = loaded["details"]["state"]
	var loaded_validation: Dictionary = _validate_loaded_state(state)
	if not bool(loaded_validation.get("success", false)): return loaded_validation
	var records: Array = []
	var ids: Array = state["outbox_by_id"].keys(); ids.sort()
	for record_id in ids:
		var record: Dictionary = state["outbox_by_id"][record_id]
		if not bool(record["published"]): records.append(record.duplicate(true))
		if records.size() >= limit: break
	return TxUtilsScript.success({"records": records})


func mark_outbox_published(record_id: String, expected_delivery_checksum: String) -> Dictionary:
	if _busy: return TxUtilsScript.failure("TRANSACTION_COORDINATOR_BUSY", {"retryable": true})
	_busy = true
	var result: Dictionary = _mark_outbox_published_locked(record_id, expected_delivery_checksum)
	_busy = false
	return result


func _mark_outbox_published_locked(record_id: String, expected_delivery_checksum: String) -> Dictionary:
	var loaded: Dictionary = _repository.load_or_empty()
	if not bool(loaded.get("success", false)): return loaded
	var current: Dictionary = loaded["details"]["state"]
	var loaded_validation: Dictionary = _validate_loaded_state(current)
	if not bool(loaded_validation.get("success", false)): return loaded_validation
	if not current["outbox_by_id"].has(record_id): return TxUtilsScript.failure("OUTBOX_RECORD_NOT_FOUND")
	var record: Dictionary = current["outbox_by_id"][record_id]
	if String(record["delivery_checksum"]) != expected_delivery_checksum: return TxUtilsScript.failure("OUTBOX_RECORD_CHECKSUM_CONFLICT")
	if bool(record["published"]): return TxUtilsScript.success({"replay": true, "record": record.duplicate(true)})
	var outbox: Dictionary = current["outbox_by_id"].duplicate(true)
	outbox[record_id] = OutboxScript.mark_published(record)
	var next := StateScript.create(int(current["generation"]) + 1, int(current["generation"]), current["aggregates_by_id"], current["operation_records_by_id"], outbox)
	var saved: Dictionary = _repository.save_atomic(next)
	if not bool(saved.get("success", false)): return saved
	return TxUtilsScript.success({"replay": false, "record": outbox[record_id].duplicate(true), "generation": int(next["generation"])})


func get_state_report() -> Dictionary:
	var loaded: Dictionary = _repository.load_or_empty()
	if not bool(loaded.get("success", false)): return loaded
	var state: Dictionary = loaded["details"]["state"]
	var loaded_validation: Dictionary = _validate_loaded_state(state)
	if not bool(loaded_validation.get("success", false)): return loaded_validation
	return TxUtilsScript.success({"generation": int(state["generation"]), "aggregate_count": state["aggregates_by_id"].size(), "operation_count": state["operation_records_by_id"].size(), "outbox_count": state["outbox_by_id"].size(), "state_checksum": String(state["checksum"]), "pending_files": _repository.list_pending_files()})


func _validate_loaded_state(state: Dictionary) -> Dictionary:
	for aggregate_id in state.get("aggregates_by_id", {}):
		var validation = _adapter_registry.validate_snapshot(state["aggregates_by_id"][aggregate_id])
		if typeof(validation) != TYPE_DICTIONARY or not bool(validation.get("success", false)):
			return TxUtilsScript.failure("PERSISTED_AGGREGATE_SNAPSHOT_REJECTED", {"aggregate_id": aggregate_id, "cause": validation})
	return TxUtilsScript.success()
