extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const BudgetScript = preload("res://scripts/simulation/compute/execution_budget.gd")

const SCHEMA := "planet_simulator.compute_capability_descriptor.v1"
const FIELDS: Array[String] = ["schema", "capability_id", "job_types", "rule_package_hashes", "maximum_budget"]


static func create(capability_id: String, job_types: Array, rule_package_hashes: Array, maximum_budget: Dictionary) -> Dictionary:
	return {"schema": SCHEMA, "capability_id": capability_id, "job_types": job_types.duplicate(), "rule_package_hashes": rule_package_hashes.duplicate(), "maximum_budget": maximum_budget.duplicate(true)}


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not ComputeUtilsScript.is_identifier(String(value.get("capability_id", "")), "capability/"):
		return ComputeUtilsScript.failure("INVALID_COMPUTE_CAPABILITY_IDENTITY")
	if typeof(value.get("job_types")) != TYPE_ARRAY or value["job_types"].is_empty() or typeof(value.get("rule_package_hashes")) != TYPE_ARRAY or value["rule_package_hashes"].is_empty():
		return ComputeUtilsScript.failure("INVALID_COMPUTE_CAPABILITY_COLLECTION")
	var job_types: Array[String] = []
	for job_type in value["job_types"]:
		if typeof(job_type) != TYPE_STRING or not ComputeUtilsScript.is_upper_kind(String(job_type)):
			return ComputeUtilsScript.failure("INVALID_COMPUTE_CAPABILITY_JOB_TYPE")
		job_types.append(String(job_type))
	var sorted_jobs := job_types.duplicate(); sorted_jobs.sort()
	if job_types != sorted_jobs or _has_duplicates(job_types):
		return ComputeUtilsScript.failure("COMPUTE_CAPABILITY_JOB_TYPES_NOT_CANONICAL")
	var hashes: Array[String] = []
	for hash_value in value["rule_package_hashes"]:
		if typeof(hash_value) != TYPE_STRING or not ComputeUtilsScript.is_lower_hex_64(String(hash_value)):
			return ComputeUtilsScript.failure("INVALID_COMPUTE_CAPABILITY_PACKAGE_HASH")
		hashes.append(String(hash_value))
	var sorted_hashes := hashes.duplicate(); sorted_hashes.sort()
	if hashes != sorted_hashes or _has_duplicates(hashes):
		return ComputeUtilsScript.failure("COMPUTE_CAPABILITY_HASHES_NOT_CANONICAL")
	var budget_check := BudgetScript.validate(value.get("maximum_budget", {}))
	if not bool(budget_check.get("success", false)):
		return budget_check
	return ComputeUtilsScript.success()


static func supports(value: Dictionary, job_type: String, rule_package_hash: String, requested_budget: Dictionary) -> bool:
	return Array(value.get("job_types", [])).has(job_type) and Array(value.get("rule_package_hashes", [])).has(rule_package_hash) and BudgetScript.contains(value.get("maximum_budget", {}), requested_budget)


static func _has_duplicates(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value): return true
		seen[value] = true
	return false
