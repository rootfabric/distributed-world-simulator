extends RefCounted
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SCHEMA := "planet_simulator.construction_fabrication_job.v1"
const FIELDS: Array[String] = ["schema", "job_id", "recipe_id", "recipe_version", "recipe_checksum", "machine_construct_id", "machine_profile_checksum", "status", "priority", "input_bindings", "output_bindings", "work_required", "work_completed", "reservation_operation_id", "completion_operation_id", "cancellation_operation_id", "last_error_code", "checksum"]
const STATUSES := ["QUEUED", "RESERVED", "PROCESSING", "BLOCKED", "COMPLETED", "CANCELLED"]
static func create(job_id: String, recipe: Dictionary, machine_profile: Dictionary, priority: int, input_bindings: Array, output_bindings: Array) -> Dictionary:
	var value := {"schema": SCHEMA, "job_id": job_id, "recipe_id": String(recipe.get("recipe_id", "")), "recipe_version": int(recipe.get("recipe_version", 0)), "recipe_checksum": String(recipe.get("checksum", "")), "machine_construct_id": String(machine_profile.get("construct_id", "")), "machine_profile_checksum": String(machine_profile.get("checksum", "")), "status": "QUEUED", "priority": priority, "input_bindings": _sorted(input_bindings, "item_instance_id"), "output_bindings": _sorted(output_bindings, "product_key"), "work_required": int(recipe.get("work_units", 0)), "work_completed": 0, "reservation_operation_id": "", "completion_operation_id": "", "cancellation_operation_id": "", "last_error_code": "", "checksum": ""}; value["checksum"] = compute_checksum(value); return value
static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_FABRICATION_JOB_SCHEMA")
	if not String(value.get("job_id", "")).begins_with("fabrication-job/") or not String(value.get("recipe_id", "")).begins_with("fabrication-recipe/") or not String(value.get("machine_construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_IDENTITY")
	if not UtilsScript.is_json_integer(value.get("recipe_version")) or int(value["recipe_version"]) < 1: return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_RECIPE_VERSION")
	for field in ["recipe_checksum", "machine_profile_checksum"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).length() != 64: return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_CHECKSUM_REFERENCE")
	if not STATUSES.has(String(value.get("status", ""))): return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_STATUS")
	if not UtilsScript.is_json_integer(value.get("priority")) or int(value["priority"]) < 0 or int(value["priority"]) > 1000: return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_PRIORITY")
	var input_checked := _validate_input_bindings(value.get("input_bindings")); if not bool(input_checked.get("success", false)): return input_checked
	var output_checked := _validate_output_bindings(value.get("output_bindings")); if not bool(output_checked.get("success", false)): return output_checked
	if not UtilsScript.is_json_integer(value.get("work_required")) or not UtilsScript.is_json_integer(value.get("work_completed")) or int(value["work_required"]) < 1 or int(value["work_completed"]) < 0 or int(value["work_completed"]) > int(value["work_required"]): return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_PROGRESS")
	for field in ["reservation_operation_id", "completion_operation_id", "cancellation_operation_id", "last_error_code"]:
		if typeof(value.get(field)) != TYPE_STRING: return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_TEXT_FIELD")
	if String(value["status"]) == "COMPLETED" and String(value["completion_operation_id"]).is_empty(): return _failure("COMPLETED_FABRICATION_JOB_LACKS_OPERATION")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_FABRICATION_JOB_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_FABRICATION_JOB_NOT_JSON_SAFE")
	return _success()

static func _validate_input_bindings(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or Array(value).is_empty(): return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_INPUT_BINDINGS")
	var previous := ""; var seen := {}
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_INPUT_BINDING")
		for field in ["item_instance_id", "definition_id", "quantity", "components", "original_relation", "source_revision", "source_fingerprint"]:
			if not raw.has(field): return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_INPUT_BINDING")
		var item_id := String(raw["item_instance_id"])
		if not item_id.begins_with("item/") or seen.has(item_id) or (not previous.is_empty() and item_id < previous): return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_INPUT_BINDING")
		if typeof(raw["definition_id"]) != TYPE_STRING or String(raw["definition_id"]).is_empty(): return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_INPUT_BINDING")
		if not UtilsScript.is_json_integer(raw["quantity"]) or int(raw["quantity"]) < 1: return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_INPUT_BINDING")
		if typeof(raw["components"]) != TYPE_DICTIONARY or typeof(raw["original_relation"]) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_INPUT_BINDING")
		var relation_checked := ProjectionScript.validate_relation(raw["original_relation"]); if not bool(relation_checked.get("success", false)): return relation_checked
		if not UtilsScript.is_json_integer(raw["source_revision"]) or int(raw["source_revision"]) < 0 or String(raw["source_fingerprint"]).length() != 64: return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_INPUT_BINDING")
		seen[item_id] = true; previous = item_id
	return _success()
static func _validate_output_bindings(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or Array(value).is_empty(): return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_OUTPUT_BINDINGS")
	var previous := ""; var seen := {}; var item_ids := {}
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY or raw.keys().size() != 2: return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_OUTPUT_BINDING")
		var key := String(raw.get("product_key", "")); var item_id := String(raw.get("item_instance_id", ""))
		if key.is_empty() or not item_id.begins_with("item/") or seen.has(key) or item_ids.has(item_id) or (not previous.is_empty() and key < previous): return _failure("INVALID_CONSTRUCTION_FABRICATION_JOB_OUTPUT_BINDING")
		seen[key] = true; item_ids[item_id] = true; previous = key
	return _success()

static func with_updates(value: Dictionary, updates: Dictionary) -> Dictionary:
	var next := value.duplicate(true)
	for key in updates:
		next[key] = updates[key]
	next["checksum"] = compute_checksum(next)
	return next
static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _sorted(values: Array, key: String) -> Array: var result := values.duplicate(true); result.sort_custom(func(a,b): return String(a.get(key,"")) < String(b.get(key,""))); return result
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
