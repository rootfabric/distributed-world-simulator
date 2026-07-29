extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")
const CapabilityScript = preload("res://scripts/simulation/compute/compute_capability_descriptor.gd")

const SCHEMA := "planet_simulator.compute_worker_descriptor.v1"
const FIELDS: Array[String] = ["schema", "worker_id", "worker_revision", "max_parallel_jobs", "capabilities"]


static func create(worker_id: String, worker_revision: int, max_parallel_jobs: int, capabilities: Array) -> Dictionary:
	return {"schema": SCHEMA, "worker_id": worker_id, "worker_revision": worker_revision, "max_parallel_jobs": max_parallel_jobs, "capabilities": capabilities.duplicate(true)}


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not ComputeUtilsScript.is_identifier(String(value.get("worker_id", "")), "worker/"):
		return ComputeUtilsScript.failure("INVALID_COMPUTE_WORKER_IDENTITY")
	if not NetworkUtilsScript.is_json_integer(value.get("worker_revision")) or int(value["worker_revision"]) < 0 or not NetworkUtilsScript.is_json_integer(value.get("max_parallel_jobs")) or int(value["max_parallel_jobs"]) < 1:
		return ComputeUtilsScript.failure("INVALID_COMPUTE_WORKER_CAPACITY")
	if typeof(value.get("capabilities")) != TYPE_ARRAY or value["capabilities"].is_empty():
		return ComputeUtilsScript.failure("INVALID_COMPUTE_WORKER_CAPABILITIES")
	var ids: Array[String] = []
	for capability in value["capabilities"]:
		if typeof(capability) != TYPE_DICTIONARY:
			return ComputeUtilsScript.failure("INVALID_COMPUTE_WORKER_CAPABILITY")
		var check := CapabilityScript.validate(capability)
		if not bool(check.get("success", false)):
			return check
		ids.append(String(capability["capability_id"]))
	var sorted_ids := ids.duplicate(); sorted_ids.sort()
	if ids != sorted_ids or _has_duplicates(ids):
		return ComputeUtilsScript.failure("COMPUTE_WORKER_CAPABILITIES_NOT_CANONICAL")
	return ComputeUtilsScript.success()


static func find_capability(value: Dictionary, capability_id: String) -> Dictionary:
	for capability in value.get("capabilities", []):
		if String(capability.get("capability_id", "")) == capability_id:
			return Dictionary(capability).duplicate(true)
	return {}


static func _has_duplicates(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value): return true
		seen[value] = true
	return false
