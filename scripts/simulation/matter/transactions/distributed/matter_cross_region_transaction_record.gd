extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Plan = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd")
const Receipt = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_receipt.gd")
const InvalidationBatch = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_invalidation_batch.gd")

const SCHEMA := "planet_simulator.matter_cross_region_transaction_record.v1"

const PHASE_BEGIN := "BEGIN"
const PHASE_PREPARING := "PREPARING"
const PHASE_PREPARED := "PREPARED"
const PHASE_COMMIT_DECIDED := "COMMIT_DECIDED"
const PHASE_COMMITTING := "COMMITTING"
const PHASE_COMMITTED := "COMMITTED"
const PHASE_ABORT_DECIDED := "ABORT_DECIDED"
const PHASE_ROLLING_BACK := "ROLLING_BACK"
const PHASE_ABORTED := "ABORTED"
const PHASES: Array[String] = [
	PHASE_BEGIN, PHASE_PREPARING, PHASE_PREPARED, PHASE_COMMIT_DECIDED,
	PHASE_COMMITTING, PHASE_COMMITTED, PHASE_ABORT_DECIDED, PHASE_ROLLING_BACK, PHASE_ABORTED,
]
const DECISION_NONE := "NONE"
const DECISION_COMMIT := "COMMIT"
const DECISION_ABORT := "ABORT"
const DECISIONS: Array[String] = [DECISION_NONE, DECISION_COMMIT, DECISION_ABORT]
const TERMINAL_PHASES: Array[String] = [PHASE_COMMITTED, PHASE_ABORTED]
const FIELDS: Array[String] = [
	"schema", "transaction_id", "operation_id", "plan", "phase", "decision",
	"record_sequence", "transition_id", "created_tick", "prepare_receipts",
	"commit_receipts", "rollback_receipts", "global_commit_hash", "invalidation_batch",
	"previous_record_checksum", "checksum",
]


static func create_begin(plan: Dictionary, transition_id: String, created_tick: int) -> Dictionary:
	return _create({
		"plan": plan,
		"phase": PHASE_BEGIN,
		"decision": DECISION_NONE,
		"record_sequence": 1,
		"transition_id": transition_id,
		"created_tick": created_tick,
		"prepare_receipts": [],
		"commit_receipts": [],
		"rollback_receipts": [],
		"global_commit_hash": "",
		"invalidation_batch": {},
		"previous_record_checksum": "",
	})


static func advance(previous: Dictionary, phase: String, transition_id: String, created_tick: int, updates: Dictionary = {}) -> Dictionary:
	if not bool(validate(previous).get("success", false)):
		return {}
	var candidate: Dictionary = _create({
		"plan": previous["plan"],
		"phase": phase,
		"decision": updates.get("decision", _decision_for_phase(phase)),
		"record_sequence": int(previous["record_sequence"]) + 1,
		"transition_id": transition_id,
		"created_tick": created_tick,
		"prepare_receipts": updates.get("prepare_receipts", previous["prepare_receipts"]),
		"commit_receipts": updates.get("commit_receipts", previous["commit_receipts"]),
		"rollback_receipts": updates.get("rollback_receipts", previous["rollback_receipts"]),
		"global_commit_hash": updates.get("global_commit_hash", previous["global_commit_hash"]),
		"invalidation_batch": updates.get("invalidation_batch", previous["invalidation_batch"]),
		"previous_record_checksum": previous["checksum"],
	})
	if candidate.is_empty() or not bool(validate_progression(candidate, previous).get("success", false)):
		return {}
	return candidate


static func compute_global_commit_hash(plan: Dictionary, prepare_receipts: Array) -> String:
	var checksums: Array[String] = []
	for raw_receipt in prepare_receipts:
		if typeof(raw_receipt) != TYPE_DICTIONARY:
			return ""
		checksums.append(String(raw_receipt.get("checksum", "")))
	return MatterUtils.payload_hash({
		"transaction_id": plan.get("transaction_id", ""),
		"plan_checksum": plan.get("checksum", ""),
		"prepare_receipt_checksums": checksums,
	})


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = MatterUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return MatterUtils.failure("UNSUPPORTED_MATTER_CROSS_REGION_TRANSACTION_RECORD_SCHEMA")
	for field in ["transaction_id", "operation_id", "transition_id"]:
		if not MatterUtils.is_canonical_id(value.get(field), 2):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_RECORD_ID", {"field": field})
	if typeof(value.get("plan")) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_RECORD_PLAN")
	checked = Plan.validate(value["plan"])
	if not bool(checked.get("success", false)):
		return checked
	var plan: Dictionary = value["plan"]
	if String(plan["transaction_id"]) != String(value["transaction_id"]) \
		or String(plan["operation_id"]) != String(value["operation_id"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_RECORD_PLAN_BINDING_MISMATCH")
	var phase: String = String(value.get("phase", ""))
	var decision: String = String(value.get("decision", ""))
	if not phase in PHASES or not decision in DECISIONS:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_RECORD_STATE")
	for field in ["record_sequence", "created_tick"]:
		if not MatterUtils.is_json_integer(value.get(field)):
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_RECORD_INTEGER", {"field": field})
	if int(value["record_sequence"]) < 1 or int(value["created_tick"]) < 0:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_RECORD_FRONTIER")
	var previous_checksum: String = String(value.get("previous_record_checksum", ""))
	if int(value["record_sequence"]) == 1:
		if phase != PHASE_BEGIN or not previous_checksum.is_empty():
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_INITIAL_RECORD")
	elif not MatterUtils.is_lower_hex_64(previous_checksum):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PREVIOUS_RECORD_CHECKSUM")
	var participant_count: int = Array(plan["participants"]).size()
	checked = _validate_receipt_array(value.get("prepare_receipts"), Receipt.ACTION_PREPARE, plan)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_receipt_array(value.get("commit_receipts"), Receipt.ACTION_COMMIT, plan)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_receipt_array(value.get("rollback_receipts"), Receipt.ACTION_ROLLBACK, plan)
	if not bool(checked.get("success", false)):
		return checked
	var prepare_count: int = Array(value["prepare_receipts"]).size()
	var commit_count: int = Array(value["commit_receipts"]).size()
	var rollback_count: int = Array(value["rollback_receipts"]).size()
	if prepare_count > participant_count or commit_count > participant_count or rollback_count > participant_count:
		return MatterUtils.failure("MATTER_CROSS_REGION_RECEIPT_COUNT_EXCEEDS_PARTICIPANTS")
	if commit_count > prepare_count or rollback_count > prepare_count:
		return MatterUtils.failure("MATTER_CROSS_REGION_RECEIPT_WITHOUT_PREPARE")
	checked = _validate_receipt_bindings(value, plan)
	if not bool(checked.get("success", false)):
		return checked
	var global_hash: String = String(value.get("global_commit_hash", ""))
	var invalidation_batch = value.get("invalidation_batch")
	if typeof(invalidation_batch) != TYPE_DICTIONARY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_INVALIDATION_BATCH")
	match phase:
		PHASE_BEGIN:
			if decision != DECISION_NONE or prepare_count != 0 or commit_count != 0 or rollback_count != 0 \
				or not global_hash.is_empty() or not invalidation_batch.is_empty():
				return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_BEGIN_STATE")
		PHASE_PREPARING:
			if decision != DECISION_NONE or prepare_count < 1 or prepare_count >= participant_count \
				or commit_count != 0 or rollback_count != 0 or not global_hash.is_empty() or not invalidation_batch.is_empty():
				return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PREPARING_STATE")
		PHASE_PREPARED:
			if decision != DECISION_NONE or prepare_count != participant_count \
				or commit_count != 0 or rollback_count != 0 or not global_hash.is_empty() or not invalidation_batch.is_empty():
				return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_PREPARED_STATE")
		PHASE_COMMIT_DECIDED:
			if decision != DECISION_COMMIT or prepare_count != participant_count \
				or commit_count != 0 or rollback_count != 0 or not MatterUtils.is_lower_hex_64(global_hash) \
				or not invalidation_batch.is_empty():
				return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_COMMIT_DECISION_STATE")
		PHASE_COMMITTING:
			if decision != DECISION_COMMIT or prepare_count != participant_count \
				or commit_count < 1 or commit_count >= participant_count or rollback_count != 0 \
				or not MatterUtils.is_lower_hex_64(global_hash) or not invalidation_batch.is_empty():
				return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_COMMITTING_STATE")
		PHASE_COMMITTED:
			if decision != DECISION_COMMIT or prepare_count != participant_count \
				or commit_count != participant_count or rollback_count != 0 \
				or not MatterUtils.is_lower_hex_64(global_hash) or invalidation_batch.is_empty():
				return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_COMMITTED_STATE")
			checked = InvalidationBatch.validate(invalidation_batch)
			if not bool(checked.get("success", false)):
				return checked
			if String(invalidation_batch["transaction_id"]) != String(value["transaction_id"]) \
				or String(invalidation_batch["global_commit_hash"]) != global_hash:
				return MatterUtils.failure("MATTER_CROSS_REGION_INVALIDATION_BATCH_BINDING_MISMATCH")
			checked = _validate_invalidation_bindings(value, plan)
			if not bool(checked.get("success", false)):
				return checked
		PHASE_ABORT_DECIDED:
			if decision != DECISION_ABORT or commit_count != 0 or rollback_count != 0 \
				or not global_hash.is_empty() or not invalidation_batch.is_empty():
				return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_ABORT_DECISION_STATE")
		PHASE_ROLLING_BACK:
			if decision != DECISION_ABORT or prepare_count < 1 or rollback_count < 1 \
				or rollback_count >= prepare_count or commit_count != 0 \
				or not global_hash.is_empty() or not invalidation_batch.is_empty():
				return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_ROLLBACK_STATE")
		PHASE_ABORTED:
			if decision != DECISION_ABORT or rollback_count != prepare_count or commit_count != 0 \
				or not global_hash.is_empty() or not invalidation_batch.is_empty():
				return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_ABORTED_STATE")
	if not global_hash.is_empty() and global_hash != compute_global_commit_hash(plan, value["prepare_receipts"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_GLOBAL_COMMIT_HASH_MISMATCH")
	return MatterUtils.validate_checksum(value)


static func validate_progression(current: Dictionary, previous: Dictionary) -> Dictionary:
	var checked: Dictionary = validate(previous)
	if not bool(checked.get("success", false)):
		return checked
	checked = validate(current)
	if not bool(checked.get("success", false)):
		return checked
	for field in ["transaction_id", "operation_id"]:
		if current[field] != previous[field]:
			return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_IDENTITY_CHANGED", {"field": field})
	if current["plan"] != previous["plan"]:
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_PLAN_MUTATED")
	if int(current["record_sequence"]) != int(previous["record_sequence"]) + 1 \
		or String(current["previous_record_checksum"]) != String(previous["checksum"]) \
		or int(current["created_tick"]) < int(previous["created_tick"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_RECORD_CHAIN_MISMATCH")
	var allowed: Dictionary = {
		PHASE_BEGIN: [PHASE_PREPARING, PHASE_PREPARED, PHASE_ABORT_DECIDED],
		PHASE_PREPARING: [PHASE_PREPARING, PHASE_PREPARED, PHASE_ABORT_DECIDED],
		PHASE_PREPARED: [PHASE_COMMIT_DECIDED, PHASE_ABORT_DECIDED],
		PHASE_COMMIT_DECIDED: [PHASE_COMMITTING, PHASE_COMMITTED],
		PHASE_COMMITTING: [PHASE_COMMITTING, PHASE_COMMITTED],
		PHASE_ABORT_DECIDED: [PHASE_ROLLING_BACK, PHASE_ABORTED],
		PHASE_ROLLING_BACK: [PHASE_ROLLING_BACK, PHASE_ABORTED],
		PHASE_COMMITTED: [],
		PHASE_ABORTED: [],
	}
	if not String(current["phase"]) in Array(allowed[String(previous["phase"])]):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_TRANSACTION_TRANSITION")
	checked = _validate_array_append_only(previous["prepare_receipts"], current["prepare_receipts"], "PREPARE")
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_array_append_only(previous["commit_receipts"], current["commit_receipts"], "COMMIT")
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_receipt_set_append_only(previous["rollback_receipts"], current["rollback_receipts"], "ROLLBACK")
	if not bool(checked.get("success", false)):
		return checked
	if not String(previous["global_commit_hash"]).is_empty() \
		and String(current["global_commit_hash"]) != String(previous["global_commit_hash"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_GLOBAL_COMMIT_HASH_MUTATED")
	if not Dictionary(previous["invalidation_batch"]).is_empty() \
		and current["invalidation_batch"] != previous["invalidation_batch"]:
		return MatterUtils.failure("MATTER_CROSS_REGION_INVALIDATION_BATCH_MUTATED")
	return MatterUtils.success()


static func is_terminal(value: Dictionary) -> bool:
	return String(value.get("phase", "")) in TERMINAL_PHASES


static func receipt_by_region(receipts: Array, region_id: String) -> Dictionary:
	var normalized: String = region_id.strip_edges().to_lower()
	for raw_receipt in receipts:
		if typeof(raw_receipt) == TYPE_DICTIONARY and String(raw_receipt.get("region_id", "")) == normalized:
			return Dictionary(raw_receipt).duplicate(true)
	return {}


static func _create(data: Dictionary) -> Dictionary:
	var plan: Dictionary = Dictionary(data.get("plan", {})).duplicate(true)
	var value: Dictionary = {
		"schema": SCHEMA,
		"transaction_id": String(plan.get("transaction_id", "")).strip_edges().to_lower(),
		"operation_id": String(plan.get("operation_id", "")).strip_edges().to_lower(),
		"plan": plan,
		"phase": String(data.get("phase", "")).strip_edges().to_upper(),
		"decision": String(data.get("decision", DECISION_NONE)).strip_edges().to_upper(),
		"record_sequence": int(data.get("record_sequence", 0)),
		"transition_id": String(data.get("transition_id", "")).strip_edges().to_lower(),
		"created_tick": int(data.get("created_tick", 0)),
		"prepare_receipts": _sorted_receipts(Array(data.get("prepare_receipts", []))),
		"commit_receipts": _sorted_receipts(Array(data.get("commit_receipts", []))),
		"rollback_receipts": _sorted_receipts(Array(data.get("rollback_receipts", []))),
		"global_commit_hash": String(data.get("global_commit_hash", "")).strip_edges().to_lower(),
		"invalidation_batch": Dictionary(data.get("invalidation_batch", {})).duplicate(true),
		"previous_record_checksum": String(data.get("previous_record_checksum", "")).strip_edges().to_lower(),
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func _sorted_receipts(receipts: Array) -> Array:
	var result: Array = receipts.duplicate(true)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("region_id", "")) < String(b.get("region_id", ""))
	)
	return result


static func _validate_receipt_array(value, expected_action: String, plan: Dictionary) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RECEIPT_ARRAY", {"action": expected_action})
	var previous_region_id := ""
	for index in range(value.size()):
		var raw_receipt = value[index]
		if typeof(raw_receipt) != TYPE_DICTIONARY:
			return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_RECEIPT", {"action": expected_action})
		var checked: Dictionary = Receipt.validate(raw_receipt)
		if not bool(checked.get("success", false)):
			return checked
		var receipt: Dictionary = raw_receipt
		if String(receipt["action"]) != expected_action \
			or String(receipt["transaction_id"]) != String(plan["transaction_id"]):
			return MatterUtils.failure("MATTER_CROSS_REGION_RECEIPT_BINDING_MISMATCH", {"action": expected_action})
		var participant: Dictionary = Plan.participant_by_region(plan, String(receipt["region_id"]))
		if participant.is_empty() or String(receipt["participant_checksum"]) != String(participant["checksum"]):
			return MatterUtils.failure("MATTER_CROSS_REGION_RECEIPT_PARTICIPANT_MISMATCH")
		var region_id: String = String(receipt["region_id"])
		if index > 0 and region_id <= previous_region_id:
			return MatterUtils.failure("MATTER_CROSS_REGION_RECEIPTS_NOT_SORTED_UNIQUE", {"action": expected_action})
		previous_region_id = region_id
	return MatterUtils.success()


static func _validate_receipt_bindings(value: Dictionary, plan: Dictionary) -> Dictionary:
	var participant_ids: Array[String] = []
	for raw_participant in plan["participants"]:
		participant_ids.append(String(raw_participant["region_id"]))
	var prepare_ids: Array[String] = _receipt_region_ids(value["prepare_receipts"])
	var commit_ids: Array[String] = _receipt_region_ids(value["commit_receipts"])
	var rollback_ids: Array[String] = _receipt_region_ids(value["rollback_receipts"])
	if prepare_ids != participant_ids.slice(0, prepare_ids.size()):
		return MatterUtils.failure("MATTER_CROSS_REGION_PREPARE_ORDER_FRONTIER_MISMATCH")
	if commit_ids != participant_ids.slice(0, commit_ids.size()):
		return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_ORDER_FRONTIER_MISMATCH")
	var expected_rollback: Array[String] = []
	if not rollback_ids.is_empty():
		expected_rollback = prepare_ids.slice(prepare_ids.size() - rollback_ids.size(), prepare_ids.size())
		expected_rollback.sort()
	if rollback_ids != expected_rollback:
		return MatterUtils.failure("MATTER_CROSS_REGION_ROLLBACK_ORDER_FRONTIER_MISMATCH")
	for raw_participant in plan["participants"]:
		var participant: Dictionary = raw_participant
		var region_id: String = String(participant["region_id"])
		var previous_source: Dictionary = participant["previous_source_revision"]
		var prepare: Dictionary = receipt_by_region(value["prepare_receipts"], region_id)
		var commit: Dictionary = receipt_by_region(value["commit_receipts"], region_id)
		var rollback: Dictionary = receipt_by_region(value["rollback_receipts"], region_id)
		if not prepare.is_empty():
			var prepared_source: Dictionary = prepare["source_revision"]
			if String(prepared_source["source_id"]) != String(previous_source["source_id"]) \
				or int(prepared_source["authority_epoch"]) != int(previous_source["authority_epoch"]) \
				or int(prepared_source["source_revision"]) <= int(previous_source["source_revision"]):
				return MatterUtils.failure("MATTER_CROSS_REGION_PREPARE_SOURCE_REVISION_INVALID", {"region_id": region_id})
			if int(prepare["created_tick"]) < int(plan["created_tick"]):
				return MatterUtils.failure("MATTER_CROSS_REGION_PREPARE_RECEIPT_BEFORE_PLAN", {"region_id": region_id})
		if not commit.is_empty():
			if prepare.is_empty() \
				or String(commit["prepare_receipt_checksum"]) != String(prepare["checksum"]) \
				or Dictionary(commit["source_revision"]) != Dictionary(prepare["source_revision"]):
				return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_RECEIPT_BINDING_MISMATCH", {"region_id": region_id})
			if int(commit["created_tick"]) < int(prepare["created_tick"]):
				return MatterUtils.failure("MATTER_CROSS_REGION_COMMIT_RECEIPT_BEFORE_PREPARE", {"region_id": region_id})
		if not rollback.is_empty():
			if prepare.is_empty() \
				or String(rollback["prepare_receipt_checksum"]) != String(prepare["checksum"]) \
				or Dictionary(rollback["source_revision"]) != Dictionary(previous_source):
				return MatterUtils.failure("MATTER_CROSS_REGION_ROLLBACK_RECEIPT_BINDING_MISMATCH", {"region_id": region_id})
			if int(rollback["created_tick"]) < int(prepare["created_tick"]):
				return MatterUtils.failure("MATTER_CROSS_REGION_ROLLBACK_RECEIPT_BEFORE_PREPARE", {"region_id": region_id})
	return MatterUtils.success()


static func _validate_invalidation_bindings(value: Dictionary, plan: Dictionary) -> Dictionary:
	var batch: Dictionary = value["invalidation_batch"]
	if int(batch["created_tick"]) != int(value["created_tick"]):
		return MatterUtils.failure("MATTER_CROSS_REGION_INVALIDATION_BATCH_TICK_MISMATCH")
	if Array(batch["invalidations"]).size() != Array(plan["participants"]).size():
		return MatterUtils.failure("MATTER_CROSS_REGION_INVALIDATION_PARTICIPANT_COUNT_MISMATCH")
	var matched: Dictionary = {}
	for raw_participant in plan["participants"]:
		var participant: Dictionary = raw_participant
		var region_id: String = String(participant["region_id"])
		var commit: Dictionary = receipt_by_region(value["commit_receipts"], region_id)
		var found: Dictionary = {}
		for raw_invalidation in batch["invalidations"]:
			var invalidation: Dictionary = raw_invalidation
			if Dictionary(invalidation["previous_source_revision"]) == Dictionary(participant["previous_source_revision"]):
				if not found.is_empty():
					return MatterUtils.failure("MATTER_CROSS_REGION_DUPLICATE_PARTICIPANT_INVALIDATION", {"region_id": region_id})
				found = invalidation
		if found.is_empty() or commit.is_empty():
			return MatterUtils.failure("MATTER_CROSS_REGION_PARTICIPANT_INVALIDATION_MISSING", {"region_id": region_id})
		if Dictionary(found["new_source_revision"]) != Dictionary(commit["source_revision"]) \
			or Array(found["dirty_bounds_m"]) != Array(participant["dirty_bounds_m"]) \
			or Array(found["affected_scope_ids"]) != Array(participant["affected_scope_ids"]) \
			or String(found["reason"]) != "MUTATION" \
			or int(found["created_tick"]) != int(value["created_tick"]):
			return MatterUtils.failure("MATTER_CROSS_REGION_PARTICIPANT_INVALIDATION_BINDING_MISMATCH", {"region_id": region_id})
		matched[String(found["checksum"])] = true
	if matched.size() != Array(batch["invalidations"]).size():
		return MatterUtils.failure("MATTER_CROSS_REGION_INVALIDATION_SET_MISMATCH")
	return MatterUtils.success()


static func _receipt_region_ids(receipts: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_receipt in receipts:
		result.append(String(raw_receipt["region_id"]))
	return result


static func _validate_array_append_only(previous: Array, current: Array, label: String) -> Dictionary:
	if current.size() < previous.size():
		return MatterUtils.failure("MATTER_CROSS_REGION_%s_RECEIPTS_TRUNCATED" % label)
	if current.size() > previous.size() + 1:
		return MatterUtils.failure("MATTER_CROSS_REGION_%s_RECEIPTS_SKIPPED_JOURNAL_STEP" % label)
	for index in range(previous.size()):
		if previous[index] != current[index]:
			return MatterUtils.failure("MATTER_CROSS_REGION_%s_RECEIPT_HISTORY_MUTATED" % label)
	return MatterUtils.success()


static func _validate_receipt_set_append_only(previous: Array, current: Array, label: String) -> Dictionary:
	if current.size() < previous.size():
		return MatterUtils.failure("MATTER_CROSS_REGION_%s_RECEIPTS_TRUNCATED" % label)
	if current.size() > previous.size() + 1:
		return MatterUtils.failure("MATTER_CROSS_REGION_%s_RECEIPTS_SKIPPED_JOURNAL_STEP" % label)
	var current_by_region: Dictionary = {}
	for raw_receipt in current:
		current_by_region[String(raw_receipt["region_id"])] = raw_receipt
	for raw_receipt in previous:
		var region_id: String = String(raw_receipt["region_id"])
		if not current_by_region.has(region_id) or current_by_region[region_id] != raw_receipt:
			return MatterUtils.failure("MATTER_CROSS_REGION_%s_RECEIPT_HISTORY_MUTATED" % label)
	return MatterUtils.success()


static func _decision_for_phase(phase: String) -> String:
	var normalized: String = phase.strip_edges().to_upper()
	if normalized in [PHASE_COMMIT_DECIDED, PHASE_COMMITTING, PHASE_COMMITTED]:
		return DECISION_COMMIT
	if normalized in [PHASE_ABORT_DECIDED, PHASE_ROLLING_BACK, PHASE_ABORTED]:
		return DECISION_ABORT
	return DECISION_NONE
