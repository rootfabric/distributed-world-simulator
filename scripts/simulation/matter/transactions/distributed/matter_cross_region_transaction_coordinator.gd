extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const Plan = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd")
const Receipt = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_receipt.gd")
const Record = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_record.gd")
const Reservation = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_reservation.gd")
const InvalidationBatch = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_invalidation_batch.gd")
const OutboxRecord = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_invalidation_outbox_record.gd")
const OperationResult = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_operation_result.gd")
const Checkpoint = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_checkpoint.gd")
const Repository = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_repository.gd")

var _repository = Repository.new()
var _authority_gate = null
var _runtime_adapter = null
var _checkpoint: Dictionary = {}


func configure(repository_root: String, authority_gate, runtime_adapter) -> Dictionary:
	if authority_gate == null or not authority_gate.has_method("authorize_plan"):
		return MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_GATE_REQUIRED")
	for method_name in ["prepare_region", "commit_region", "rollback_region", "publish_invalidation"]:
		if runtime_adapter == null or not runtime_adapter.has_method(method_name):
			return MatterUtils.failure("MATTER_CROSS_REGION_RUNTIME_ADAPTER_REQUIRED", {"method": method_name})
	var configured: Dictionary = _repository.configure(repository_root)
	if not bool(configured.get("success", false)):
		return configured
	_authority_gate = authority_gate
	_runtime_adapter = runtime_adapter
	return MatterUtils.success(configured["details"])


func initialize(checkpoint_id: String, server_tick: int) -> Dictionary:
	if not _checkpoint.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_ALREADY_INITIALIZED")
	var checkpoint: Dictionary = Checkpoint.create({
		"checkpoint_id": checkpoint_id,
		"generation": 1,
		"server_tick": server_tick,
		"previous_checkpoint_checksum": "",
		"transaction_records": [],
		"region_reservations": [],
		"operation_results": [],
		"invalidation_outbox": [],
	})
	if checkpoint.is_empty():
		return MatterUtils.failure("INVALID_INITIAL_MATTER_CROSS_REGION_TRANSACTION_CHECKPOINT")
	var saved: Dictionary = _repository.save_atomic(checkpoint)
	if not bool(saved.get("success", false)):
		return saved
	_checkpoint = checkpoint
	return MatterUtils.success({"checkpoint": checkpoint.duplicate(true)})


func restore_latest() -> Dictionary:
	var loaded: Dictionary = _repository.load_committed()
	if not bool(loaded.get("success", false)):
		return loaded
	var checkpoint: Dictionary = loaded["details"]["checkpoint"]
	var checked: Dictionary = Checkpoint.validate(checkpoint)
	if not bool(checked.get("success", false)):
		return checked
	_checkpoint = checkpoint.duplicate(true)
	var source: String = String(loaded["details"].get("source", ""))
	if source == "PREVIOUS_RECOVERY":
		var repaired: Dictionary = _repository.repair_active_from_previous()
		if not bool(repaired.get("success", false)):
			_checkpoint.clear()
			return repaired
	return MatterUtils.success({
		"checkpoint": _checkpoint.duplicate(true),
		"source": source,
		"pending_files": Array(loaded["details"].get("pending_files", [])).duplicate(),
	})


func checkpoint() -> Dictionary:
	return _checkpoint.duplicate(true)


func latest_record(transaction_id: String) -> Dictionary:
	var normalized: String = transaction_id.strip_edges().to_lower()
	var result: Dictionary = {}
	for raw_record in Array(_checkpoint.get("transaction_records", [])):
		var record: Dictionary = raw_record
		if String(record["transaction_id"]) == normalized:
			result = record
	return result.duplicate(true)


func operation_result(operation_id: String) -> Dictionary:
	var normalized: String = operation_id.strip_edges().to_lower()
	for raw_result in Array(_checkpoint.get("operation_results", [])):
		var result: Dictionary = raw_result
		if String(result["operation_id"]) == normalized:
			return result.duplicate(true)
	return {}


func begin_transaction(plan: Dictionary, transition_id: String, server_tick: int) -> Dictionary:
	if _checkpoint.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_INITIALIZED")
	var checked: Dictionary = Plan.validate(plan)
	if not bool(checked.get("success", false)):
		return checked
	var replay_result: Dictionary = operation_result(String(plan["operation_id"]))
	if not replay_result.is_empty():
		if String(replay_result["plan_checksum"]) != String(plan["checksum"]):
			return MatterUtils.failure("MATTER_CROSS_REGION_OPERATION_ID_CONFLICT")
		return MatterUtils.success({"replay": true, "result": replay_result})
	var existing: Dictionary = latest_record(String(plan["transaction_id"]))
	if not existing.is_empty():
		if String(existing["plan"]["checksum"]) != String(plan["checksum"]):
			return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_ID_CONFLICT")
		return MatterUtils.success({"replay": true, "record": existing})
	checked = _authority_gate.authorize_plan(plan, server_tick)
	if typeof(checked) != TYPE_DICTIONARY or not bool(checked.get("success", false)):
		return checked if typeof(checked) == TYPE_DICTIONARY else MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_GATE_INVALID_RESULT")
	var reserved_by_region: Dictionary = _reservations_by_region(_checkpoint["region_reservations"])
	for raw_participant in plan["participants"]:
		var participant: Dictionary = raw_participant
		var region_id: String = String(participant["region_id"])
		if reserved_by_region.has(region_id):
			return MatterUtils.failure("MATTER_CROSS_REGION_REGION_ALREADY_RESERVED", {
				"region_id": region_id,
				"transaction_id": reserved_by_region[region_id]["transaction_id"],
			})
	var begin: Dictionary = Record.create_begin(plan, transition_id, server_tick)
	if begin.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_BEGIN_RECORD_CREATION_FAILED")
	var reservations: Array = Array(_checkpoint["region_reservations"]).duplicate(true)
	for raw_participant in plan["participants"]:
		var participant: Dictionary = raw_participant
		var reservation: Dictionary = Reservation.create(
			String(participant["region_id"]), String(plan["transaction_id"]),
			String(participant["checksum"]), server_tick
		)
		if reservation.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_RESERVATION_CREATION_FAILED")
		reservations.append(reservation)
	var records: Array = Array(_checkpoint["transaction_records"]).duplicate(true)
	records.append(begin)
	var committed: Dictionary = _commit_state(
		records, reservations, _checkpoint["operation_results"], _checkpoint["invalidation_outbox"], server_tick
	)
	if not bool(committed.get("success", false)):
		return committed
	var reauthorized = _authority_gate.authorize_plan(plan, server_tick)
	if typeof(reauthorized) != TYPE_DICTIONARY or not bool(reauthorized.get("success", false)):
		var cause: Dictionary = reauthorized if typeof(reauthorized) == TYPE_DICTIONARY \
			else MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_GATE_INVALID_RESULT")
		var aborted: Dictionary = decide_abort(
			String(plan["transaction_id"]), "%s-authority-abort" % transition_id, server_tick
		)
		if bool(aborted.get("success", false)):
			aborted = rollback_all(
				String(plan["transaction_id"]), "%s-authority-rollback" % transition_id, server_tick
			)
		if not bool(aborted.get("success", false)):
			return MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_CHANGED_RESERVATION_RECOVERY_FAILED", {
				"cause": cause,
				"recovery_error": aborted,
			})
		return MatterUtils.failure("MATTER_CROSS_REGION_AUTHORITY_CHANGED_DURING_RESERVATION", {
			"cause": cause,
			"terminal_result": operation_result(String(plan["operation_id"])),
		})
	return MatterUtils.success({"replay": false, "record": begin})


func prepare_next(transaction_id: String, transition_id: String, server_tick: int) -> Dictionary:
	var current: Dictionary = latest_record(transaction_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_FOUND")
	if String(current["phase"]) == Record.PHASE_PREPARED:
		return MatterUtils.success({"replay": true, "record": current})
	if not String(current["phase"]) in [Record.PHASE_BEGIN, Record.PHASE_PREPARING]:
		return MatterUtils.failure("MATTER_CROSS_REGION_PREPARE_PHASE_MISMATCH")
	var participant: Dictionary = _next_participant(current["plan"], current["prepare_receipts"], false)
	if participant.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_PREPARE_PARTICIPANT_MISSING")
	var context: Dictionary = _runtime_context(current, server_tick)
	var runtime_result = _runtime_adapter.prepare_region(participant, context)
	if typeof(runtime_result) != TYPE_DICTIONARY or not bool(runtime_result.get("success", false)):
		return runtime_result if typeof(runtime_result) == TYPE_DICTIONARY else MatterUtils.failure("MATTER_CROSS_REGION_PREPARE_INVALID_RUNTIME_RESULT")
	var details: Dictionary = Dictionary(runtime_result.get("details", {}))
	var receipt: Dictionary = Receipt.create({
		"transaction_id": current["transaction_id"],
		"region_id": participant["region_id"],
		"action": Receipt.ACTION_PREPARE,
		"participant_checksum": participant["checksum"],
		"prepare_receipt_checksum": "",
		"source_revision": details.get("source_revision", {}),
		"runtime_state_hash": details.get("runtime_state_hash", ""),
		"created_tick": server_tick,
	})
	var checked: Dictionary = _validate_prepare_receipt(receipt, participant)
	if not bool(checked.get("success", false)):
		return checked
	var receipts: Array = Array(current["prepare_receipts"]).duplicate(true)
	receipts.append(receipt)
	var next_phase: String = Record.PHASE_PREPARED \
		if receipts.size() == Array(current["plan"]["participants"]).size() else Record.PHASE_PREPARING
	var next: Dictionary = Record.advance(current, next_phase, transition_id, server_tick, {
		"prepare_receipts": receipts,
	})
	return _append_record(next, server_tick, {"receipt": receipt})


func prepare_all(transaction_id: String, transition_prefix: String, server_tick: int) -> Dictionary:
	var tick: int = server_tick
	while true:
		var current: Dictionary = latest_record(transaction_id)
		if current.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_FOUND")
		if String(current["phase"]) == Record.PHASE_PREPARED:
			return MatterUtils.success({"record": current})
		var prepared: Dictionary = prepare_next(
			transaction_id, "%s-%d" % [transition_prefix, int(current["record_sequence"]) + 1], tick
		)
		if not bool(prepared.get("success", false)):
			return prepared
		tick += 1
	return MatterUtils.failure("MATTER_CROSS_REGION_PREPARE_LOOP_TERMINATED")


func decide_commit(transaction_id: String, transition_id: String, server_tick: int) -> Dictionary:
	var current: Dictionary = latest_record(transaction_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_FOUND")
	if String(current["phase"]) in [Record.PHASE_COMMIT_DECIDED, Record.PHASE_COMMITTING, Record.PHASE_COMMITTED]:
		return MatterUtils.success({"replay": true, "record": current})
	if String(current["phase"]) != Record.PHASE_PREPARED:
		return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_DECISION_PHASE_MISMATCH")
	var global_commit_hash: String = Record.compute_global_commit_hash(
		current["plan"], current["prepare_receipts"]
	)
	if not MatterUtils.is_lower_hex_64(global_commit_hash):
		return MatterUtils.failure("MATTER_CROSS_REGION_GLOBAL_COMMIT_HASH_CREATION_FAILED")
	var next: Dictionary = Record.advance(
		current, Record.PHASE_COMMIT_DECIDED, transition_id, server_tick,
		{"decision": Record.DECISION_COMMIT, "global_commit_hash": global_commit_hash}
	)
	return _append_record(next, server_tick, {"global_commit_hash": global_commit_hash})


func commit_next(transaction_id: String, transition_id: String, server_tick: int) -> Dictionary:
	var current: Dictionary = latest_record(transaction_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_FOUND")
	if String(current["phase"]) == Record.PHASE_COMMITTED:
		return MatterUtils.success({"replay": true, "record": current})
	if not String(current["phase"]) in [Record.PHASE_COMMIT_DECIDED, Record.PHASE_COMMITTING]:
		return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_PHASE_MISMATCH")
	var participant: Dictionary = _next_participant(current["plan"], current["commit_receipts"], false)
	if participant.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_PARTICIPANT_MISSING")
	var prepare_receipt: Dictionary = Record.receipt_by_region(current["prepare_receipts"], String(participant["region_id"]))
	if prepare_receipt.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_PREPARE_RECEIPT_MISSING")
	var context: Dictionary = _runtime_context(current, server_tick)
	var runtime_result = _runtime_adapter.commit_region(participant, prepare_receipt, context)
	if typeof(runtime_result) != TYPE_DICTIONARY or not bool(runtime_result.get("success", false)):
		return runtime_result if typeof(runtime_result) == TYPE_DICTIONARY else MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_INVALID_RUNTIME_RESULT")
	var details: Dictionary = Dictionary(runtime_result.get("details", {}))
	var receipt: Dictionary = Receipt.create({
		"transaction_id": current["transaction_id"],
		"region_id": participant["region_id"],
		"action": Receipt.ACTION_COMMIT,
		"participant_checksum": participant["checksum"],
		"prepare_receipt_checksum": prepare_receipt["checksum"],
		"source_revision": details.get("source_revision", {}),
		"runtime_state_hash": details.get("runtime_state_hash", ""),
		"created_tick": server_tick,
	})
	var checked: Dictionary = _validate_commit_receipt(receipt, prepare_receipt, participant)
	if not bool(checked.get("success", false)):
		return checked
	var receipts: Array = Array(current["commit_receipts"]).duplicate(true)
	receipts.append(receipt)
	var participant_count: int = Array(current["plan"]["participants"]).size()
	if receipts.size() < participant_count:
		var progress: Dictionary = Record.advance(
			current, Record.PHASE_COMMITTING, transition_id, server_tick,
			{"decision": Record.DECISION_COMMIT, "commit_receipts": receipts}
		)
		return _append_record(progress, server_tick, {"receipt": receipt})
	var invalidation_batch: Dictionary = _build_invalidation_batch(current, receipts, server_tick)
	if invalidation_batch.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_INVALIDATION_BATCH_CREATION_FAILED")
	var terminal: Dictionary = Record.advance(
		current, Record.PHASE_COMMITTED, transition_id, server_tick, {
			"decision": Record.DECISION_COMMIT,
			"commit_receipts": receipts,
			"invalidation_batch": invalidation_batch,
		}
	)
	if terminal.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_COMMITTED_RECORD_CREATION_FAILED")
	var result: Dictionary = OperationResult.create({
		"operation_id": terminal["operation_id"],
		"transaction_id": terminal["transaction_id"],
		"plan_checksum": terminal["plan"]["checksum"],
		"outcome": OperationResult.OUTCOME_COMMITTED,
		"terminal_record_checksum": terminal["checksum"],
		"global_commit_hash": terminal["global_commit_hash"],
		"invalidation_batch_checksum": invalidation_batch["checksum"],
		"completed_tick": server_tick,
	})
	var outbox: Dictionary = OutboxRecord.create(
		"matter-invalidation-outbox/%s" % _safe_id(String(terminal["transaction_id"])),
		String(terminal["transaction_id"]), String(terminal["checksum"]), invalidation_batch
	)
	if result.is_empty() or outbox.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TERMINAL_OUTPUT_CREATION_FAILED")
	var records: Array = Array(_checkpoint["transaction_records"]).duplicate(true)
	records.append(terminal)
	var results: Array = Array(_checkpoint["operation_results"]).duplicate(true)
	results.append(result)
	var outbox_records: Array = Array(_checkpoint["invalidation_outbox"]).duplicate(true)
	outbox_records.append(outbox)
	var reservations: Array = _without_transaction_reservations(
		_checkpoint["region_reservations"], String(terminal["transaction_id"])
	)
	var committed: Dictionary = _commit_state(records, reservations, results, outbox_records, server_tick)
	if not bool(committed.get("success", false)):
		return committed
	return MatterUtils.success({
		"replay": false,
		"record": terminal,
		"result": result,
		"outbox": outbox,
		"receipt": receipt,
	})


func commit_all(transaction_id: String, transition_prefix: String, server_tick: int, publish: bool = true) -> Dictionary:
	var tick: int = server_tick
	while true:
		var current: Dictionary = latest_record(transaction_id)
		if current.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_FOUND")
		if String(current["phase"]) == Record.PHASE_COMMITTED:
			if publish:
				var published: Dictionary = publish_pending_invalidations(tick)
				if not bool(published.get("success", false)):
					return published
			return MatterUtils.success({"record": current, "result": operation_result(String(current["operation_id"]))})
		var committed: Dictionary = commit_next(
			transaction_id, "%s-%d" % [transition_prefix, int(current["record_sequence"]) + 1], tick
		)
		if not bool(committed.get("success", false)):
			return committed
		tick += 1
	return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_LOOP_TERMINATED")


func decide_abort(transaction_id: String, transition_id: String, server_tick: int) -> Dictionary:
	var current: Dictionary = latest_record(transaction_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_FOUND")
	if String(current["phase"]) in [Record.PHASE_ABORT_DECIDED, Record.PHASE_ROLLING_BACK, Record.PHASE_ABORTED]:
		return MatterUtils.success({"replay": true, "record": current})
	if String(current["phase"]) in [Record.PHASE_COMMIT_DECIDED, Record.PHASE_COMMITTING, Record.PHASE_COMMITTED]:
		return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_DECISION_IS_IRREVERSIBLE")
	if not String(current["phase"]) in [Record.PHASE_BEGIN, Record.PHASE_PREPARING, Record.PHASE_PREPARED]:
		return MatterUtils.failure("MATTER_CROSS_REGION_ABORT_DECISION_PHASE_MISMATCH")
	var next: Dictionary = Record.advance(
		current, Record.PHASE_ABORT_DECIDED, transition_id, server_tick,
		{"decision": Record.DECISION_ABORT}
	)
	return _append_record(next, server_tick)


func rollback_next(transaction_id: String, transition_id: String, server_tick: int) -> Dictionary:
	var current: Dictionary = latest_record(transaction_id)
	if current.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_FOUND")
	if String(current["phase"]) == Record.PHASE_ABORTED:
		return MatterUtils.success({"replay": true, "record": current})
	if not String(current["phase"]) in [Record.PHASE_ABORT_DECIDED, Record.PHASE_ROLLING_BACK]:
		return MatterUtils.failure("MATTER_CROSS_REGION_ROLLBACK_PHASE_MISMATCH")
	var prepare_receipts: Array = current["prepare_receipts"]
	if prepare_receipts.is_empty():
		return _finish_abort(current, transition_id, server_tick)
	var participant: Dictionary = _next_participant(current["plan"], current["rollback_receipts"], true, prepare_receipts)
	if participant.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_ROLLBACK_PARTICIPANT_MISSING")
	var prepare_receipt: Dictionary = Record.receipt_by_region(prepare_receipts, String(participant["region_id"]))
	var context: Dictionary = _runtime_context(current, server_tick)
	var runtime_result = _runtime_adapter.rollback_region(participant, prepare_receipt, context)
	if typeof(runtime_result) != TYPE_DICTIONARY or not bool(runtime_result.get("success", false)):
		return runtime_result if typeof(runtime_result) == TYPE_DICTIONARY else MatterUtils.failure("MATTER_CROSS_REGION_ROLLBACK_INVALID_RUNTIME_RESULT")
	var details: Dictionary = Dictionary(runtime_result.get("details", {}))
	var receipt: Dictionary = Receipt.create({
		"transaction_id": current["transaction_id"],
		"region_id": participant["region_id"],
		"action": Receipt.ACTION_ROLLBACK,
		"participant_checksum": participant["checksum"],
		"prepare_receipt_checksum": prepare_receipt["checksum"],
		"source_revision": details.get("source_revision", {}),
		"runtime_state_hash": details.get("runtime_state_hash", ""),
		"created_tick": server_tick,
	})
	var checked: Dictionary = _validate_rollback_receipt(receipt, prepare_receipt, participant)
	if not bool(checked.get("success", false)):
		return checked
	var receipts: Array = Array(current["rollback_receipts"]).duplicate(true)
	receipts.append(receipt)
	if receipts.size() < prepare_receipts.size():
		var progress: Dictionary = Record.advance(
			current, Record.PHASE_ROLLING_BACK, transition_id, server_tick,
			{"decision": Record.DECISION_ABORT, "rollback_receipts": receipts}
		)
		return _append_record(progress, server_tick, {"receipt": receipt})
	return _finish_abort(current, transition_id, server_tick, receipts, receipt)


func rollback_all(transaction_id: String, transition_prefix: String, server_tick: int) -> Dictionary:
	var tick: int = server_tick
	while true:
		var current: Dictionary = latest_record(transaction_id)
		if current.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_FOUND")
		if String(current["phase"]) == Record.PHASE_ABORTED:
			return MatterUtils.success({"record": current, "result": operation_result(String(current["operation_id"]))})
		var rolled_back: Dictionary = rollback_next(
			transaction_id, "%s-%d" % [transition_prefix, int(current["record_sequence"]) + 1], tick
		)
		if not bool(rolled_back.get("success", false)):
			return rolled_back
		tick += 1
	return MatterUtils.failure("MATTER_CROSS_REGION_ROLLBACK_LOOP_TERMINATED")


func recover_incomplete(recovery_id: String, server_tick: int) -> Dictionary:
	if _checkpoint.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_RESTORED")
	var transaction_ids: Array = Checkpoint.latest_records(_checkpoint["transaction_records"]).keys()
	transaction_ids.sort()
	var actions: Array = []
	var tick: int = server_tick
	for transaction_id in transaction_ids:
		var current: Dictionary = latest_record(String(transaction_id))
		if Record.is_terminal(current):
			continue
		var phase: String = String(current["phase"])
		if phase in [Record.PHASE_COMMIT_DECIDED, Record.PHASE_COMMITTING]:
			var committed: Dictionary = commit_all(
				String(transaction_id), "%s-commit-%s" % [recovery_id, _safe_id(String(transaction_id))], tick, false
			)
			if not bool(committed.get("success", false)):
				return committed
			actions.append({"transaction_id": transaction_id, "action": "COMPLETE_COMMIT"})
			tick += 10
		elif phase in [Record.PHASE_ABORT_DECIDED, Record.PHASE_ROLLING_BACK]:
			var aborted: Dictionary = rollback_all(
				String(transaction_id), "%s-rollback-%s" % [recovery_id, _safe_id(String(transaction_id))], tick
			)
			if not bool(aborted.get("success", false)):
				return aborted
			actions.append({"transaction_id": transaction_id, "action": "COMPLETE_ABORT"})
			tick += 10
		elif phase in [Record.PHASE_BEGIN, Record.PHASE_PREPARING, Record.PHASE_PREPARED]:
			var decided: Dictionary = decide_abort(
				String(transaction_id), "%s-decide-abort-%s" % [recovery_id, _safe_id(String(transaction_id))], tick
			)
			if not bool(decided.get("success", false)):
				return decided
			tick += 1
			var finalized: Dictionary = rollback_all(
				String(transaction_id), "%s-abort-%s" % [recovery_id, _safe_id(String(transaction_id))], tick
			)
			if not bool(finalized.get("success", false)):
				return finalized
			actions.append({"transaction_id": transaction_id, "action": "ABORT_UNDECIDED"})
			tick += 10
		else:
			return MatterUtils.failure("MATTER_CROSS_REGION_RECOVERY_PHASE_INVALID", {"phase": phase})
	var published: Dictionary = publish_pending_invalidations(tick)
	if not bool(published.get("success", false)):
		return published
	return MatterUtils.success({
		"actions": actions,
		"published_outbox_ids": published["details"].get("published_outbox_ids", []),
		"checkpoint": _checkpoint.duplicate(true),
	})


func publish_pending_invalidations(server_tick: int) -> Dictionary:
	var published_ids: Array[String] = []
	var tick: int = server_tick
	while true:
		var pending: Dictionary = {}
		for raw_outbox in Array(_checkpoint.get("invalidation_outbox", [])):
			var outbox: Dictionary = raw_outbox
			if not bool(outbox["published"]):
				pending = outbox
				break
		if pending.is_empty():
			return MatterUtils.success({"published_outbox_ids": published_ids})
		var runtime_result = _runtime_adapter.publish_invalidation(pending)
		if typeof(runtime_result) != TYPE_DICTIONARY or not bool(runtime_result.get("success", false)):
			return runtime_result if typeof(runtime_result) == TYPE_DICTIONARY else MatterUtils.failure("MATTER_CROSS_REGION_INVALIDATION_PUBLISH_INVALID_RESULT")
		var updated: Dictionary = OutboxRecord.mark_published(pending, tick)
		if updated.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_OUTBOX_PUBLISH_STATE_CREATION_FAILED")
		var outbox_records: Array = []
		for raw_outbox in _checkpoint["invalidation_outbox"]:
			var outbox: Dictionary = raw_outbox
			outbox_records.append(updated if String(outbox["outbox_id"]) == String(pending["outbox_id"]) else outbox)
		var committed: Dictionary = _commit_state(
			_checkpoint["transaction_records"], _checkpoint["region_reservations"],
			_checkpoint["operation_results"], outbox_records, tick
		)
		if not bool(committed.get("success", false)):
			return committed
		published_ids.append(String(updated["outbox_id"]))
		tick += 1
	return MatterUtils.failure("MATTER_CROSS_REGION_PUBLISH_LOOP_TERMINATED")


func execute_transaction(plan: Dictionary, transition_prefix: String, server_tick: int) -> Dictionary:
	var begun: Dictionary = begin_transaction(plan, "%s-begin" % transition_prefix, server_tick)
	if not bool(begun.get("success", false)):
		return begun
	if bool(begun["details"].get("replay", false)) and begun["details"].has("result"):
		return begun
	var prepared: Dictionary = prepare_all(String(plan["transaction_id"]), "%s-prepare" % transition_prefix, server_tick + 1)
	if not bool(prepared.get("success", false)):
		return prepared
	var decided: Dictionary = decide_commit(
		String(plan["transaction_id"]), "%s-decide" % transition_prefix, server_tick + 20
	)
	if not bool(decided.get("success", false)):
		return decided
	return commit_all(String(plan["transaction_id"]), "%s-commit" % transition_prefix, server_tick + 21, true)


func cleanup_pending_files() -> Dictionary:
	return _repository.cleanup_pending_files()


func repository():
	return _repository


func _append_record(next: Dictionary, server_tick: int, details: Dictionary = {}) -> Dictionary:
	if next.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_RECORD_CREATION_FAILED")
	var records: Array = Array(_checkpoint["transaction_records"]).duplicate(true)
	records.append(next)
	var committed: Dictionary = _commit_state(
		records, _checkpoint["region_reservations"], _checkpoint["operation_results"],
		_checkpoint["invalidation_outbox"], server_tick
	)
	if not bool(committed.get("success", false)):
		return committed
	var result_details: Dictionary = details.duplicate(true)
	result_details["replay"] = false
	result_details["record"] = next
	return MatterUtils.success(result_details)


func _finish_abort(
	current: Dictionary,
	transition_id: String,
	server_tick: int,
	rollback_receipts: Array = [],
	last_receipt: Dictionary = {}
) -> Dictionary:
	var terminal: Dictionary = Record.advance(
		current, Record.PHASE_ABORTED, transition_id, server_tick, {
			"decision": Record.DECISION_ABORT,
			"rollback_receipts": rollback_receipts,
		}
	)
	if terminal.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_ABORTED_RECORD_CREATION_FAILED")
	var result: Dictionary = OperationResult.create({
		"operation_id": terminal["operation_id"],
		"transaction_id": terminal["transaction_id"],
		"plan_checksum": terminal["plan"]["checksum"],
		"outcome": OperationResult.OUTCOME_ABORTED,
		"terminal_record_checksum": terminal["checksum"],
		"global_commit_hash": "",
		"invalidation_batch_checksum": "",
		"completed_tick": server_tick,
	})
	if result.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_ABORT_RESULT_CREATION_FAILED")
	var records: Array = Array(_checkpoint["transaction_records"]).duplicate(true)
	records.append(terminal)
	var results: Array = Array(_checkpoint["operation_results"]).duplicate(true)
	results.append(result)
	var reservations: Array = _without_transaction_reservations(
		_checkpoint["region_reservations"], String(terminal["transaction_id"])
	)
	var committed: Dictionary = _commit_state(
		records, reservations, results, _checkpoint["invalidation_outbox"], server_tick
	)
	if not bool(committed.get("success", false)):
		return committed
	return MatterUtils.success({
		"replay": false,
		"record": terminal,
		"result": result,
		"receipt": last_receipt,
	})


func _commit_state(records: Array, reservations: Array, results: Array, outbox: Array, server_tick: int) -> Dictionary:
	if _checkpoint.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_NOT_INITIALIZED")
	var next: Dictionary = Checkpoint.create({
		"checkpoint_id": _checkpoint["checkpoint_id"],
		"generation": int(_checkpoint["generation"]) + 1,
		"server_tick": server_tick,
		"previous_checkpoint_checksum": _checkpoint["checksum"],
		"transaction_records": records,
		"region_reservations": reservations,
		"operation_results": results,
		"invalidation_outbox": outbox,
	})
	if next.is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_CHECKPOINT_CREATION_FAILED")
	var saved: Dictionary = _repository.save_atomic(next)
	if not bool(saved.get("success", false)):
		return saved
	_checkpoint = next
	return MatterUtils.success({"checkpoint": next.duplicate(true)})


func _build_invalidation_batch(current: Dictionary, commit_receipts: Array, server_tick: int) -> Dictionary:
	var invalidations: Array = []
	for raw_participant in current["plan"]["participants"]:
		var participant: Dictionary = raw_participant
		var commit_receipt: Dictionary = Record.receipt_by_region(commit_receipts, String(participant["region_id"]))
		if commit_receipt.is_empty():
			return {}
		var invalidation: Dictionary = Invalidation.create(
			"representation-invalidation/%s-%s" % [
				_safe_id(String(current["transaction_id"])), _safe_id(String(participant["region_id"]))
			],
			participant["previous_source_revision"], commit_receipt["source_revision"],
			participant["dirty_bounds_m"], "MUTATION", participant["affected_scope_ids"], server_tick
		)
		if invalidation.is_empty():
			return {}
		invalidations.append(invalidation)
	return InvalidationBatch.create(
		"matter-invalidation-batch/%s" % _safe_id(String(current["transaction_id"])),
		String(current["transaction_id"]), String(current["global_commit_hash"]), invalidations, server_tick
	)


func _validate_prepare_receipt(receipt: Dictionary, participant: Dictionary) -> Dictionary:
	var checked: Dictionary = Receipt.validate(receipt)
	if not bool(checked.get("success", false)):
		return checked
	var previous: Dictionary = participant["previous_source_revision"]
	var current: Dictionary = receipt["source_revision"]
	if String(current["source_id"]) != String(previous["source_id"]) \
		or int(current["authority_epoch"]) != int(previous["authority_epoch"]) \
		or int(current["source_revision"]) <= int(previous["source_revision"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_PREPARE_SOURCE_REVISION_INVALID")
	return MatterUtils.success()


func _validate_commit_receipt(receipt: Dictionary, prepare_receipt: Dictionary, participant: Dictionary) -> Dictionary:
	var checked: Dictionary = Receipt.validate(receipt)
	if not bool(checked.get("success", false)):
		return checked
	if String(receipt["prepare_receipt_checksum"]) != String(prepare_receipt["checksum"]) \
		or Dictionary(receipt["source_revision"]) != Dictionary(prepare_receipt["source_revision"]) \
		or String(receipt["participant_checksum"]) != String(participant["checksum"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_RECEIPT_BINDING_MISMATCH")
	return MatterUtils.success()


func _validate_rollback_receipt(receipt: Dictionary, prepare_receipt: Dictionary, participant: Dictionary) -> Dictionary:
	var checked: Dictionary = Receipt.validate(receipt)
	if not bool(checked.get("success", false)):
		return checked
	if String(receipt["prepare_receipt_checksum"]) != String(prepare_receipt["checksum"]) \
		or Dictionary(receipt["source_revision"]) != Dictionary(participant["previous_source_revision"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_ROLLBACK_RECEIPT_BINDING_MISMATCH")
	return MatterUtils.success()


func _runtime_context(current: Dictionary, server_tick: int) -> Dictionary:
	return {
		"transaction_id": current["transaction_id"],
		"operation_id": current["operation_id"],
		"plan_checksum": current["plan"]["checksum"],
		"phase": current["phase"],
		"record_sequence": current["record_sequence"],
		"global_commit_hash": current["global_commit_hash"],
		"server_tick": server_tick,
	}


func _next_participant(
	plan: Dictionary,
	receipts: Array,
	reverse: bool,
	eligible_prepare_receipts: Array = []
) -> Dictionary:
	var completed: Dictionary = {}
	for raw_receipt in receipts:
		completed[String(raw_receipt["region_id"])] = true
	var eligible: Dictionary = {}
	if not eligible_prepare_receipts.is_empty():
		for raw_receipt in eligible_prepare_receipts:
			eligible[String(raw_receipt["region_id"])] = true
	var participants: Array = Array(plan["participants"]).duplicate(true)
	if reverse:
		participants.reverse()
	for raw_participant in participants:
		var participant: Dictionary = raw_participant
		var region_id: String = String(participant["region_id"])
		if completed.has(region_id):
			continue
		if not eligible.is_empty() and not eligible.has(region_id):
			continue
		return participant.duplicate(true)
	return {}


func _reservations_by_region(reservations: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_reservation in reservations:
		var reservation: Dictionary = raw_reservation
		result[String(reservation["region_id"])] = reservation
	return result


func _without_transaction_reservations(reservations: Array, transaction_id: String) -> Array:
	var result: Array = []
	for raw_reservation in reservations:
		var reservation: Dictionary = raw_reservation
		if String(reservation["transaction_id"]) != transaction_id:
			result.append(reservation.duplicate(true))
	return result


func _safe_id(value: String) -> String:
	return value.strip_edges().to_lower().replace("/", "-").replace("_", "-")
