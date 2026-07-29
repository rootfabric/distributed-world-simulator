extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")

const SCHEMA := "planet_simulator.mutation_proposal_operation.v1"
const OP_UPDATE := "UPDATE"
const OPERATION_KINDS: Array[String] = [OP_UPDATE]
const FIELDS: Array[String] = ["schema", "operation_kind", "aggregate_id", "aggregate_kind", "state_schema", "changed_fields", "removed_fields"]


static func create_update(aggregate_id: String, aggregate_kind: String, state_schema: String, changed_fields: Dictionary, removed_fields: Array = []) -> Dictionary:
	return {"schema": SCHEMA, "operation_kind": OP_UPDATE, "aggregate_id": aggregate_id, "aggregate_kind": aggregate_kind, "state_schema": state_schema, "changed_fields": changed_fields.duplicate(true), "removed_fields": removed_fields.duplicate()}


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not OPERATION_KINDS.has(String(value.get("operation_kind", ""))):
		return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_OPERATION_KIND")
	if not ComputeUtilsScript.is_identifier(String(value.get("aggregate_id", "")), "aggregate/") or not ComputeUtilsScript.is_upper_kind(String(value.get("aggregate_kind", ""))) or not ComputeUtilsScript.is_versioned_schema(String(value.get("state_schema", ""))):
		return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_OPERATION_IDENTITY")
	if typeof(value.get("changed_fields")) != TYPE_DICTIONARY or typeof(value.get("removed_fields")) != TYPE_ARRAY:
		return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_PATCH")
	if value["changed_fields"].is_empty() and value["removed_fields"].is_empty():
		return ComputeUtilsScript.failure("EMPTY_MUTATION_PROPOSAL_OPERATION")
	var paths: Array[String] = []
	for path_value in value["changed_fields"].keys():
		if typeof(path_value) != TYPE_STRING or not ComputeUtilsScript.is_state_path(String(path_value)):
			return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_PATH")
		paths.append(String(path_value))
	for path_value in value["removed_fields"]:
		if typeof(path_value) != TYPE_STRING or not ComputeUtilsScript.is_state_path(String(path_value)):
			return ComputeUtilsScript.failure("INVALID_MUTATION_PROPOSAL_PATH")
		paths.append(String(path_value))
	var sorted_paths := paths.duplicate(); sorted_paths.sort()
	if paths != sorted_paths or _has_duplicates(paths) or _has_overlaps(paths):
		return ComputeUtilsScript.failure("MUTATION_PROPOSAL_PATHS_NOT_CANONICAL")
	var canonical := ComputeUtilsScript.canonical_copy(value)
	if not bool(canonical.get("success", false)):
		return canonical
	return ComputeUtilsScript.success()


static func _has_duplicates(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value): return true
		seen[value] = true
	return false


static func _has_overlaps(values: Array[String]) -> bool:
	for first_index in range(values.size()):
		for second_index in range(first_index + 1, values.size()):
			if ComputeUtilsScript.paths_overlap(values[first_index], values[second_index]): return true
	return false
