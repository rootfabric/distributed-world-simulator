extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const INVALIDATION_SCHEMA := "planet_simulator.fabric_bake_mixed_invalidation_ordering.v1"
const RECOVERY_SCHEMA := "planet_simulator.fabric_bake_mixed_recovery_ordering.v1"
const QUALIFICATION := "BRIDGE_2_D_INVALIDATION_REFINEMENT_ORDERING"
const INVALIDATION_PHASES: Array[String] = [
	"REFINEMENT_GUARD_TRIGGERED",
	"LOCAL_FULL_REFINEMENT_READY",
	"CANONICAL_COMMIT_CONFIRMED",
	"SOURCE_INVALIDATION_PUBLISHED",
	"REDUCED_REPRESENTATIONS_MARKED_STALE",
	"STALE_EXECUTION_REJECTED",
	"STRUCTURAL_SPLIT_REBAKE_READY",
]
const RECOVERY_PHASES: Array[String] = [
	"FRESH_REPRESENTATIONS_REBOUND",
	"FRESH_EXECUTION_RESUMED",
]
const TRACE_FIELDS: Array[String] = [
	"schema", "event_id", "previous_source_frontier_hash", "current_source_frontier_hash",
	"route_hash", "commit_hash", "old_subject_hash", "old_ownership_contract_hash",
	"phase_records", "ordering_qualification", "trace_hash", "checksum",
]
const RECOVERY_TRACE_FIELDS: Array[String] = [
	"schema", "event_id", "current_source_frontier_hash", "old_ownership_contract_hash",
	"fresh_ownership_contract_hash", "phase_records", "recovery_records",
	"ordering_qualification", "trace_hash", "checksum",
]
const PHASE_FIELDS: Array[String] = ["phase_index", "phase_kind", "proof_hash"]
const RECOVERY_FIELDS: Array[String] = [
	"representation_id", "representation_kind", "recovery_action",
	"fresh_identity_hashes", "fresh_execution_state", "recovery_hash",
]
const FRESH_STATES: Array[String] = ["ACTIVE", "DEFERRED_REDERIVE", "FRESH_EXECUTABLE", "SPLIT_FRESH_EXECUTABLE"]

static func create_invalidation(
	event_id: String, previous_frontier_hash: String, current_frontier_hash: String,
	route_hash: String, commit_hash: String, old_subject_hash: String,
	old_ownership_contract_hash: String, phase_proof_hashes: Array
) -> Dictionary:
	if phase_proof_hashes.size() != INVALIDATION_PHASES.size():
		return {}
	var value: Dictionary = {
		"schema": INVALIDATION_SCHEMA,
		"event_id": event_id,
		"previous_source_frontier_hash": previous_frontier_hash,
		"current_source_frontier_hash": current_frontier_hash,
		"route_hash": route_hash,
		"commit_hash": commit_hash,
		"old_subject_hash": old_subject_hash,
		"old_ownership_contract_hash": old_ownership_contract_hash,
		"phase_records": _phases(INVALIDATION_PHASES, phase_proof_hashes, 0),
		"ordering_qualification": QUALIFICATION,
		"trace_hash": "",
		"checksum": "",
	}
	value["trace_hash"] = U.canonical_hash(_without(value, ["trace_hash", "checksum"]))
	value["checksum"] = U.compute_checksum(value)
	return value if bool(validate_invalidation(value).get("success", false)) else {}

static func validate_invalidation(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, TRACE_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != INVALIDATION_SCHEMA:
		return U.failure("UNSUPPORTED_BRIDGE2_D_INVALIDATION_SCHEMA")
	checked = _validate_common(value, true)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_phases(value.get("phase_records"), INVALIDATION_PHASES, 0)
	if not bool(checked.get("success", false)):
		return checked
	return _validate_trace_hash(value)

static func create_recovery(
	event_id: String, current_frontier_hash: String, old_ownership_contract_hash: String,
	fresh_ownership_contract_hash: String, phase_proof_hashes: Array, recovery_records: Array
) -> Dictionary:
	if phase_proof_hashes.size() != RECOVERY_PHASES.size():
		return {}
	var records := _recovery_records(recovery_records)
	if records.is_empty():
		return {}
	var value: Dictionary = {
		"schema": RECOVERY_SCHEMA,
		"event_id": event_id,
		"current_source_frontier_hash": current_frontier_hash,
		"old_ownership_contract_hash": old_ownership_contract_hash,
		"fresh_ownership_contract_hash": fresh_ownership_contract_hash,
		"phase_records": _phases(RECOVERY_PHASES, phase_proof_hashes, INVALIDATION_PHASES.size()),
		"recovery_records": records,
		"ordering_qualification": QUALIFICATION,
		"trace_hash": "",
		"checksum": "",
	}
	value["trace_hash"] = U.canonical_hash(_without(value, ["trace_hash", "checksum"]))
	value["checksum"] = U.compute_checksum(value)
	return value if bool(validate_recovery(value).get("success", false)) else {}

static func validate_recovery(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, RECOVERY_TRACE_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != RECOVERY_SCHEMA:
		return U.failure("UNSUPPORTED_BRIDGE2_D_RECOVERY_SCHEMA")
	if not U.is_canonical_id(value.get("event_id"), 2):
		return U.failure("BRIDGE2_D_INVALID_EVENT_ID")
	for field in ["current_source_frontier_hash", "old_ownership_contract_hash", "fresh_ownership_contract_hash", "trace_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("BRIDGE2_D_INVALID_HASH", {"field": field})
	if String(value["old_ownership_contract_hash"]) == String(value["fresh_ownership_contract_hash"]):
		return U.failure("BRIDGE2_D_OWNERSHIP_REBIND_REQUIRED")
	if String(value.get("ordering_qualification", "")) != QUALIFICATION:
		return U.failure("BRIDGE2_D_ORDERING_NOT_QUALIFIED")
	checked = _validate_phases(value.get("phase_records"), RECOVERY_PHASES, INVALIDATION_PHASES.size())
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_recovery_records(value.get("recovery_records"))
	if not bool(checked.get("success", false)):
		return checked
	return _validate_trace_hash(value)

static func _validate_common(value: Dictionary, require_advance: bool) -> Dictionary:
	if not U.is_canonical_id(value.get("event_id"), 2):
		return U.failure("BRIDGE2_D_INVALID_EVENT_ID")
	for field in [
		"previous_source_frontier_hash", "current_source_frontier_hash", "route_hash",
		"commit_hash", "old_subject_hash", "old_ownership_contract_hash", "trace_hash",
	]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("BRIDGE2_D_INVALID_HASH", {"field": field})
	if require_advance and String(value["previous_source_frontier_hash"]) == String(value["current_source_frontier_hash"]):
		return U.failure("BRIDGE2_D_FRONTIER_MUST_ADVANCE")
	if String(value.get("ordering_qualification", "")) != QUALIFICATION:
		return U.failure("BRIDGE2_D_ORDERING_NOT_QUALIFIED")
	return U.success()

static func _phases(kinds: Array[String], hashes: Array, index_offset: int) -> Array:
	var phases: Array = []
	for index in range(kinds.size()):
		phases.append({"phase_index": index + index_offset, "phase_kind": kinds[index], "proof_hash": String(hashes[index])})
	return phases

static func _validate_phases(raw_phases, kinds: Array[String], index_offset: int) -> Dictionary:
	if typeof(raw_phases) != TYPE_ARRAY or raw_phases.size() != kinds.size():
		return U.failure("BRIDGE2_D_PHASE_COVERAGE_MISMATCH")
	for index in range(raw_phases.size()):
		var raw = raw_phases[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("BRIDGE2_D_INVALID_PHASE", {"index": index})
		var checked := U.validate_exact_fields(raw, PHASE_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if int(raw.get("phase_index", -1)) != index + index_offset:
			return U.failure("BRIDGE2_D_PHASE_INDEX_OUT_OF_ORDER", {"index": index})
		if String(raw.get("phase_kind", "")) != kinds[index]:
			return U.failure("BRIDGE2_D_PHASE_KIND_OUT_OF_ORDER", {"index": index})
		if not U.is_lower_hex_64(raw.get("proof_hash")):
			return U.failure("BRIDGE2_D_INVALID_PHASE_PROOF", {"index": index})
	return U.success()

static func _recovery_records(raw_records: Array) -> Array:
	var records: Array = []
	for raw in raw_records:
		if typeof(raw) != TYPE_DICTIONARY:
			return []
		var record: Dictionary = raw.duplicate(true)
		record["fresh_identity_hashes"] = Array(record.get("fresh_identity_hashes", [])).duplicate(true)
		record["fresh_identity_hashes"].sort()
		record["recovery_hash"] = ""
		record["recovery_hash"] = U.canonical_hash(_without(record, ["recovery_hash"]))
		records.append(record)
	records.sort_custom(func(a, b): return String(a.get("representation_id", "")) < String(b.get("representation_id", "")))
	return records

static func _validate_recovery_records(raw_records) -> Dictionary:
	if typeof(raw_records) != TYPE_ARRAY or raw_records.size() != 5:
		return U.failure("BRIDGE2_D_RECOVERY_COVERAGE_MISMATCH")
	var seen := {}
	var previous := ""
	for index in range(raw_records.size()):
		var raw = raw_records[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("BRIDGE2_D_INVALID_RECOVERY_RECORD", {"index": index})
		var checked := U.validate_exact_fields(raw, RECOVERY_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var representation_id := String(raw.get("representation_id", ""))
		if not U.is_canonical_id(representation_id, 2) or seen.has(representation_id):
			return U.failure("BRIDGE2_D_INVALID_OR_DUPLICATE_RECOVERY_ID", {"representation_id": representation_id})
		if not previous.is_empty() and representation_id <= previous:
			return U.failure("BRIDGE2_D_RECOVERY_RECORDS_NOT_SORTED")
		previous = representation_id
		seen[representation_id] = true
		if typeof(raw.get("recovery_action")) != TYPE_STRING or String(raw["recovery_action"]).is_empty():
			return U.failure("BRIDGE2_D_RECOVERY_ACTION_REQUIRED", {"representation_id": representation_id})
		checked = U.validate_sorted_unique_strings(raw.get("fresh_identity_hashes"), true)
		if not bool(checked.get("success", false)):
			return U.failure("BRIDGE2_D_INVALID_FRESH_IDENTITIES", {"representation_id": representation_id})
		for fresh_hash in raw["fresh_identity_hashes"]:
			if not U.is_lower_hex_64(fresh_hash):
				return U.failure("BRIDGE2_D_INVALID_FRESH_IDENTITY_HASH", {"representation_id": representation_id})
		if not FRESH_STATES.has(String(raw.get("fresh_execution_state", ""))):
			return U.failure("BRIDGE2_D_INVALID_FRESH_EXECUTION_STATE", {"representation_id": representation_id})
		var kind := String(raw.get("representation_kind", ""))
		var fresh_count: int = raw["fresh_identity_hashes"].size()
		match kind:
			"FULL":
				if fresh_count != 1 or String(raw["fresh_execution_state"]) != "FRESH_EXECUTABLE":
					return U.failure("BRIDGE2_D_FULL_RECOVERY_CONTRACT_MISMATCH")
			"STRUCTURAL_BAKE":
				if fresh_count != 2 or String(raw["fresh_execution_state"]) != "SPLIT_FRESH_EXECUTABLE":
					return U.failure("BRIDGE2_D_STRUCTURAL_RECOVERY_CONTRACT_MISMATCH")
			"CONTACT_BAKE":
				if fresh_count != 0 or String(raw["fresh_execution_state"]) != "DEFERRED_REDERIVE":
					return U.failure("BRIDGE2_D_CONTACT_RECOVERY_CONTRACT_MISMATCH")
			"DYNAMIC_ROM", "HYBRID_BAKE":
				if fresh_count != 1 or String(raw["fresh_execution_state"]) != "ACTIVE":
					return U.failure("BRIDGE2_D_REDUCED_RECOVERY_CONTRACT_MISMATCH", {"representation_kind": kind})
			_:
				return U.failure("BRIDGE2_D_UNSUPPORTED_RECOVERY_KIND", {"representation_kind": kind})
		if not U.is_lower_hex_64(raw.get("recovery_hash")) or String(raw["recovery_hash"]) != U.canonical_hash(_without(raw, ["recovery_hash"])):
			return U.failure("BRIDGE2_D_RECOVERY_HASH_MISMATCH", {"representation_id": representation_id})
	return U.success()

static func _validate_trace_hash(value: Dictionary) -> Dictionary:
	if not U.is_lower_hex_64(value.get("trace_hash")) or String(value["trace_hash"]) != U.canonical_hash(_without(value, ["trace_hash", "checksum"])):
		return U.failure("BRIDGE2_D_TRACE_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _without(value: Dictionary, fields: Array) -> Dictionary:
	var payload := value.duplicate(true)
	for field in fields:
		payload.erase(field)
	return payload
