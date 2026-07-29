extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const OperationScript = preload("res://scripts/simulation/compute/mutation_proposal_operation.gd")

const SCHEMA := "planet_simulator.mutation_proposal.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "proposal_id", "job_id", "job_attempt", "job_checksum",
	"worker_id", "capability_id", "determinism_fingerprint", "rule_package_hash", "operations",
	"operation_count", "output_bytes", "instruction_units", "proposal_hash", "checksum",
]


static func create(
	proposal_id: String,
	job_id: String,
	job_attempt: int,
	job_checksum: String,
	worker_id: String,
	capability_id: String,
	determinism_fingerprint: String,
	rule_package_hash: String,
	operations: Array,
	instruction_units: int
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"proposal_id": proposal_id,
		"job_id": job_id,
		"job_attempt": job_attempt,
		"job_checksum": job_checksum,
		"worker_id": worker_id,
		"capability_id": capability_id,
		"determinism_fingerprint": determinism_fingerprint,
		"rule_package_hash": rule_package_hash,
		"operations": operations.duplicate(true),
		"operation_count": operations.size(),
		"output_bytes": 0,
		"instruction_units": instruction_units,
		"proposal_hash": "",
		"checksum": "",
	}
	value["output_bytes"] = _measure_output_bytes(value)
	value["proposal_hash"] = compute_proposal_hash(value)
	value["checksum"] = compute_checksum(value)
	return value


static func compute_proposal_hash(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("proposal_hash")
	payload.erase("checksum")
	return NetworkUtilsScript.payload_hash(payload)


static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return NetworkUtilsScript.payload_hash(payload)


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return ComputeUtilsScript.failure("UNSUPPORTED_MUTATION_PROPOSAL_SCHEMA")
	if not ComputeUtilsScript.is_identifier(String(value.get("proposal_id", "")), "proposal/") or not ComputeUtilsScript.is_identifier(String(value.get("job_id", "")), "job/") or not ComputeUtilsScript.is_identifier(String(value.get("worker_id", "")), "worker/") or not ComputeUtilsScript.is_identifier(String(value.get("capability_id", "")), "capability/"):
		return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_IDENTITY")
	if not NetworkUtilsScript.is_json_integer(value.get("job_attempt")) or int(value["job_attempt"]) < 1:
		return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_ATTEMPT")
	for field in ["job_checksum", "determinism_fingerprint", "rule_package_hash", "proposal_hash", "checksum"]:
		if not ComputeUtilsScript.is_lower_hex_64(String(value.get(field, ""))):
			return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_HASH", {"field": field})
	if typeof(value.get("operations")) != TYPE_ARRAY or value["operations"].is_empty():
		return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_OPERATIONS")
	var aggregate_ids: Array[String] = []
	for operation in value["operations"]:
		if typeof(operation) != TYPE_DICTIONARY:
			return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_OPERATION")
		var operation_check := OperationScript.validate(operation)
		if not bool(operation_check.get("success", false)):
			return operation_check
		aggregate_ids.append(String(operation["aggregate_id"]))
	var sorted_ids := aggregate_ids.duplicate()
	sorted_ids.sort()
	if aggregate_ids != sorted_ids or _has_duplicates(aggregate_ids):
		return ComputeUtilsScript.failure("MUTATION_PROPOSAL_OPERATIONS_NOT_CANONICAL")
	for field in ["operation_count", "output_bytes", "instruction_units"]:
		if not NetworkUtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_METRIC", {"field": field})
	if int(value["operation_count"]) != value["operations"].size() or int(value["output_bytes"]) != _measure_output_bytes(value):
		return ComputeUtilsScript.failure("MUTATION_PROPOSAL_METRIC_MISMATCH")
	if String(value["proposal_hash"]) != compute_proposal_hash(value) or String(value["checksum"]) != compute_checksum(value):
		return ComputeUtilsScript.failure("MUTATION_PROPOSAL_CHECKSUM_MISMATCH")
	return ComputeUtilsScript.success()


static func _measure_output_bytes(value: Dictionary) -> int:
	var payload := value.duplicate(true)
	payload.erase("output_bytes")
	payload.erase("proposal_hash")
	payload.erase("checksum")
	return ComputeUtilsScript.serialized_size(payload)


static func _has_duplicates(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value):
			return true
		seen[value] = true
	return false
