extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")

const SCHEMA := "planet_simulator.mutation_write_set.v1"
const FIELDS: Array[String] = ["schema", "entries"]
const ENTRY_FIELDS: Array[String] = ["aggregate_id", "aggregate_kind", "state_schema", "operation_kinds", "paths"]
const OPERATION_KINDS: Array[String] = ["CREATE", "DELETE", "UPDATE"]


static func create(entries: Array) -> Dictionary:
	return {"schema": SCHEMA, "entries": entries.duplicate(true)}


static func entry(aggregate_id: String, aggregate_kind: String, state_schema: String, operation_kinds: Array, paths: Array) -> Dictionary:
	return {"aggregate_id": aggregate_id, "aggregate_kind": aggregate_kind, "state_schema": state_schema, "operation_kinds": operation_kinds.duplicate(), "paths": paths.duplicate()}


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or typeof(value.get("entries")) != TYPE_ARRAY or value["entries"].is_empty():
		return ComputeUtilsScript.failure("INVALID_MUTATION_WRITE_SET")
	var aggregate_ids: Array[String] = []
	for raw in value["entries"]:
		var check := _validate_entry(raw)
		if not bool(check.get("success", false)):
			return check
		aggregate_ids.append(String(raw["aggregate_id"]))
	var sorted_ids := aggregate_ids.duplicate(); sorted_ids.sort()
	if aggregate_ids != sorted_ids or _has_duplicates(aggregate_ids):
		return ComputeUtilsScript.failure("MUTATION_WRITE_SET_NOT_CANONICAL")
	return ComputeUtilsScript.success()


static func entry_for(value: Dictionary, aggregate_id: String) -> Dictionary:
	for raw in value.get("entries", []):
		if String(raw.get("aggregate_id", "")) == aggregate_id:
			return Dictionary(raw).duplicate(true)
	return {}


static func allows_operation(value: Dictionary, aggregate_id: String, operation_kind: String) -> bool:
	return Array(entry_for(value, aggregate_id).get("operation_kinds", [])).has(operation_kind)


static func allows_path(value: Dictionary, aggregate_id: String, path: String) -> bool:
	for allowed in entry_for(value, aggregate_id).get("paths", []):
		if String(allowed) == path or String(path).begins_with(String(allowed) + "."):
			return true
	return false


static func _validate_entry(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return ComputeUtilsScript.failure("INVALID_MUTATION_WRITE_ENTRY")
	var exact := NetworkUtilsScript.validate_exact_fields(raw, ENTRY_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if not ComputeUtilsScript.is_identifier(String(raw.get("aggregate_id", "")), "aggregate/") or not ComputeUtilsScript.is_upper_kind(String(raw.get("aggregate_kind", ""))) or not ComputeUtilsScript.is_versioned_schema(String(raw.get("state_schema", ""))):
		return ComputeUtilsScript.failure("INVALID_MUTATION_WRITE_ENTRY_IDENTITY")
	if typeof(raw.get("operation_kinds")) != TYPE_ARRAY or raw["operation_kinds"].is_empty() or typeof(raw.get("paths")) != TYPE_ARRAY:
		return ComputeUtilsScript.failure("INVALID_MUTATION_WRITE_ENTRY_COLLECTION")
	var operation_kinds: Array[String] = []
	for operation_kind in raw["operation_kinds"]:
		if typeof(operation_kind) != TYPE_STRING or not OPERATION_KINDS.has(String(operation_kind)):
			return ComputeUtilsScript.failure("INVALID_MUTATION_WRITE_OPERATION_KIND")
		operation_kinds.append(String(operation_kind))
	var sorted_kinds := operation_kinds.duplicate(); sorted_kinds.sort()
	if operation_kinds != sorted_kinds or _has_duplicates(operation_kinds):
		return ComputeUtilsScript.failure("MUTATION_WRITE_OPERATION_KINDS_NOT_CANONICAL")
	var paths: Array[String] = []
	for path_value in raw["paths"]:
		if typeof(path_value) != TYPE_STRING or not ComputeUtilsScript.is_state_path(String(path_value)):
			return ComputeUtilsScript.failure("INVALID_MUTATION_WRITE_PATH")
		paths.append(String(path_value))
	var sorted_paths := paths.duplicate(); sorted_paths.sort()
	if paths != sorted_paths or _has_duplicates(paths) or _has_overlaps(paths):
		return ComputeUtilsScript.failure("MUTATION_WRITE_PATHS_NOT_CANONICAL")
	if raw["operation_kinds"].has("UPDATE") and paths.is_empty():
		return ComputeUtilsScript.failure("UPDATE_WRITE_SET_REQUIRES_PATHS")
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
