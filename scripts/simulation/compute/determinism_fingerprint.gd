extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")

const SCHEMA := "planet_simulator.determinism_fingerprint.v1"
const FIELDS: Array[String] = [
	"schema", "inputs_hash", "job_type", "required_capability_id", "read_set_hash",
	"write_set_hash", "rule_package_hash", "algorithm_version", "deterministic_seed",
	"from_tick", "to_tick", "fingerprint",
]


static func create(
	inputs: Array,
	job_type: String,
	required_capability_id: String,
	read_set: Dictionary,
	write_set: Dictionary,
	rule_package_hash: String,
	algorithm_version: String,
	deterministic_seed: int,
	from_tick: int,
	to_tick: int
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"inputs_hash": NetworkUtilsScript.payload_hash(inputs),
		"job_type": job_type,
		"required_capability_id": required_capability_id,
		"read_set_hash": NetworkUtilsScript.payload_hash(read_set),
		"write_set_hash": NetworkUtilsScript.payload_hash(write_set),
		"rule_package_hash": rule_package_hash,
		"algorithm_version": algorithm_version,
		"deterministic_seed": deterministic_seed,
		"from_tick": from_tick,
		"to_tick": to_tick,
		"fingerprint": "",
	}
	value["fingerprint"] = compute_fingerprint(value)
	return value


static func compute_fingerprint(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("fingerprint")
	return NetworkUtilsScript.payload_hash(payload)


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return ComputeUtilsScript.failure("UNSUPPORTED_DETERMINISM_FINGERPRINT_SCHEMA")
	for field in ["inputs_hash", "read_set_hash", "write_set_hash", "rule_package_hash", "fingerprint"]:
		if not ComputeUtilsScript.is_lower_hex_64(String(value.get(field, ""))):
			return ComputeUtilsScript.failure("INVALID_DETERMINISM_HASH", {"field": field})
	if not ComputeUtilsScript.is_upper_kind(String(value.get("job_type", ""))):
		return ComputeUtilsScript.failure("INVALID_DETERMINISM_JOB_TYPE")
	if not ComputeUtilsScript.is_identifier(String(value.get("required_capability_id", "")), "capability/"):
		return ComputeUtilsScript.failure("INVALID_DETERMINISM_CAPABILITY")
	if not ComputeUtilsScript.is_identifier(String(value.get("algorithm_version", ""))):
		return ComputeUtilsScript.failure("INVALID_ALGORITHM_VERSION")
	for field in ["deterministic_seed", "from_tick", "to_tick"]:
		if not NetworkUtilsScript.is_json_integer(value.get(field)):
			return ComputeUtilsScript.failure("INVALID_DETERMINISM_COUNTER", {"field": field})
	if int(value["deterministic_seed"]) < 0 or int(value["from_tick"]) < 0 or int(value["to_tick"]) < int(value["from_tick"]):
		return ComputeUtilsScript.failure("INVALID_DETERMINISM_RANGE")
	if String(value["fingerprint"]) != compute_fingerprint(value):
		return ComputeUtilsScript.failure("DETERMINISM_FINGERPRINT_MISMATCH")
	return ComputeUtilsScript.success()
