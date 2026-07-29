extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const InputScript = preload("res://scripts/simulation/compute/simulation_job_input_reference.gd")
const ReadSetScript = preload("res://scripts/simulation/compute/mutation_read_set.gd")
const WriteSetScript = preload("res://scripts/simulation/compute/mutation_write_set.gd")
const BudgetScript = preload("res://scripts/simulation/compute/execution_budget.gd")
const FingerprintScript = preload("res://scripts/simulation/compute/determinism_fingerprint.gd")

const SCHEMA := "planet_simulator.simulation_job_envelope.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "job_id", "job_type", "job_attempt", "required_capability_id",
	"authority_owner_id", "authority_epoch", "from_tick", "to_tick", "input_references",
	"read_set", "write_set", "rule_package_hash", "algorithm_version", "deterministic_seed",
	"execution_budget", "determinism_fingerprint", "checksum",
]


static func create(
	job_id: String,
	job_type: String,
	job_attempt: int,
	required_capability_id: String,
	authority_owner_id: String,
	authority_epoch: int,
	from_tick: int,
	to_tick: int,
	input_references: Array,
	read_set: Dictionary,
	write_set: Dictionary,
	rule_package_hash: String,
	algorithm_version: String,
	deterministic_seed: int,
	execution_budget: Dictionary
) -> Dictionary:
	var fingerprint := FingerprintScript.create(input_references, rule_package_hash, algorithm_version, deterministic_seed, from_tick, to_tick)
	var value := {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"job_id": job_id,
		"job_type": job_type,
		"job_attempt": job_attempt,
		"required_capability_id": required_capability_id,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"from_tick": from_tick,
		"to_tick": to_tick,
		"input_references": input_references.duplicate(true),
		"read_set": read_set.duplicate(true),
		"write_set": write_set.duplicate(true),
		"rule_package_hash": rule_package_hash,
		"algorithm_version": algorithm_version,
		"deterministic_seed": deterministic_seed,
		"execution_budget": execution_budget.duplicate(true),
		"determinism_fingerprint": fingerprint,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return NetworkUtilsScript.payload_hash(payload)


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return ComputeUtilsScript.failure("UNSUPPORTED_SIMULATION_JOB_SCHEMA")
	if not ComputeUtilsScript.is_identifier(String(value.get("job_id", "")), "job/") or not ComputeUtilsScript.is_upper_kind(String(value.get("job_type", ""))) or not ComputeUtilsScript.is_identifier(String(value.get("required_capability_id", "")), "capability/"):
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_IDENTITY")
	if not ComputeUtilsScript.is_identifier(String(value.get("authority_owner_id", ""))):
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_AUTHORITY_OWNER")
	for field in ["job_attempt", "authority_epoch", "from_tick", "to_tick", "deterministic_seed"]:
		if not NetworkUtilsScript.is_json_integer(value.get(field)):
			return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_COUNTER", {"field": field})
	if int(value["job_attempt"]) < 1 or int(value["authority_epoch"]) < 1 or int(value["from_tick"]) < 0 or int(value["to_tick"]) < int(value["from_tick"]) or int(value["deterministic_seed"]) < 0:
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_COUNTER")
	if typeof(value.get("input_references")) != TYPE_ARRAY or value["input_references"].is_empty():
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_INPUTS")
	var input_ids: Array[String] = []
	for input_reference in value["input_references"]:
		if typeof(input_reference) != TYPE_DICTIONARY:
			return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_INPUT")
		var input_check := InputScript.validate(input_reference)
		if not bool(input_check.get("success", false)):
			return input_check
		if String(input_reference["authority_owner_id"]) != String(value["authority_owner_id"]) or int(input_reference["authority_epoch"]) != int(value["authority_epoch"]):
			return ComputeUtilsScript.failure("SIMULATION_JOB_INPUT_AUTHORITY_MISMATCH")
		if int(input_reference["server_tick"]) > int(value["from_tick"]):
			return ComputeUtilsScript.failure("SIMULATION_JOB_INPUT_TICK_AHEAD")
		input_ids.append(String(input_reference["aggregate_id"]))
	var sorted_ids := input_ids.duplicate(); sorted_ids.sort()
	if input_ids != sorted_ids or _has_duplicates(input_ids):
		return ComputeUtilsScript.failure("SIMULATION_JOB_INPUTS_NOT_CANONICAL")
	var read_check := ReadSetScript.validate(value.get("read_set", {}))
	if not bool(read_check.get("success", false)):
		return read_check
	var write_check := WriteSetScript.validate(value.get("write_set", {}))
	if not bool(write_check.get("success", false)):
		return write_check
	for read_entry in value["read_set"]["entries"]:
		if not input_ids.has(String(read_entry["aggregate_id"])):
			return ComputeUtilsScript.failure("READ_SET_INPUT_MISSING")
		var input_reference := _input_by_id(value["input_references"], String(read_entry["aggregate_id"]))
		if String(input_reference["aggregate_kind"]) != String(read_entry["aggregate_kind"]) or String(input_reference["state_schema"]) != String(read_entry["state_schema"]):
			return ComputeUtilsScript.failure("READ_SET_INPUT_IDENTITY_MISMATCH")
	var budget_check := BudgetScript.validate(value.get("execution_budget", {}))
	if not bool(budget_check.get("success", false)):
		return budget_check
	if not ComputeUtilsScript.is_lower_hex_64(String(value.get("rule_package_hash", ""))) or not ComputeUtilsScript.is_identifier(String(value.get("algorithm_version", ""))):
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_RULE_IDENTITY")
	var fingerprint_check := FingerprintScript.validate(value.get("determinism_fingerprint", {}))
	if not bool(fingerprint_check.get("success", false)):
		return fingerprint_check
	var expected_fingerprint := FingerprintScript.create(value["input_references"], String(value["rule_package_hash"]), String(value["algorithm_version"]), int(value["deterministic_seed"]), int(value["from_tick"]), int(value["to_tick"]))
	if String(expected_fingerprint["fingerprint"]) != String(value["determinism_fingerprint"]["fingerprint"]):
		return ComputeUtilsScript.failure("SIMULATION_JOB_DETERMINISM_FINGERPRINT_MISMATCH")
	if not ComputeUtilsScript.is_lower_hex_64(String(value.get("checksum", ""))) or String(value["checksum"]) != compute_checksum(value):
		return ComputeUtilsScript.failure("SIMULATION_JOB_CHECKSUM_MISMATCH")
	return ComputeUtilsScript.success()


static func _input_by_id(inputs: Array, aggregate_id: String) -> Dictionary:
	for input_reference in inputs:
		if String(input_reference.get("aggregate_id", "")) == aggregate_id:
			return Dictionary(input_reference)
	return {}


static func _has_duplicates(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value): return true
		seen[value] = true
	return false
