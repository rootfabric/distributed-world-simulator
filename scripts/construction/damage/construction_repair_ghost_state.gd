extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RepairPlanScript = preload("res://scripts/construction/damage/construction_repair_plan.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")

const SCHEMA := "planet_simulator.construction_repair_ghost_state.v1"
const FIELDS: Array[String] = ["schema", "repair_id", "repair_plan_checksum", "target_construct_id", "part_states", "ready", "checksum"]

static func compile(repair_plan: Dictionary, available_items: Array) -> Dictionary:
	var plan_validation := RepairPlanScript.validate(repair_plan)
	if not bool(plan_validation.get("success", false)):
		return plan_validation
	var available := {}
	for projection in available_items:
		var checked := ProjectionScript.validate(projection)
		if not bool(checked.get("success", false)):
			return checked
		available[String(projection["item_instance_id"])] = projection
	var states: Array = []
	var ready := true
	for item_id in repair_plan["required_part_item_ids"]:
		var status := "AVAILABLE" if available.has(String(item_id)) else "MISSING"
		states.append({"item_instance_id": String(item_id), "status": status})
		ready = ready and status == "AVAILABLE"
	var value := {
		"schema": SCHEMA,
		"repair_id": String(repair_plan["repair_id"]),
		"repair_plan_checksum": String(repair_plan["checksum"]),
		"target_construct_id": String(repair_plan["target_construct_id"]),
		"part_states": states,
		"ready": ready,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return _success({"ghost": value})

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_REPAIR_GHOST_SCHEMA")
	if not String(value.get("repair_id", "")).begins_with("repair/") or not String(value.get("target_construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_REPAIR_GHOST_IDENTITY")
	if typeof(value.get("repair_plan_checksum")) != TYPE_STRING or String(value["repair_plan_checksum"]).length() != 64: return _failure("INVALID_CONSTRUCTION_REPAIR_GHOST_PLAN_CHECKSUM")
	if typeof(value.get("part_states")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_REPAIR_GHOST_PART_STATES")
	var previous := ""; var computed_ready := true
	for state in value["part_states"]:
		if typeof(state) != TYPE_DICTIONARY or state.keys().size() != 2 or not state.has("item_instance_id") or not state.has("status"): return _failure("INVALID_CONSTRUCTION_REPAIR_GHOST_PART_STATE")
		var item_id := String(state["item_instance_id"]); var status := String(state["status"])
		if not item_id.begins_with("item/") or (not previous.is_empty() and item_id < previous) or status not in ["AVAILABLE", "MISSING"]: return _failure("INVALID_CONSTRUCTION_REPAIR_GHOST_PART_STATE")
		computed_ready = computed_ready and status == "AVAILABLE"; previous = item_id
	if typeof(value.get("ready")) != TYPE_BOOL or bool(value["ready"]) != computed_ready: return _failure("CONSTRUCTION_REPAIR_GHOST_READY_MISMATCH")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value): return _failure("CONSTRUCTION_REPAIR_GHOST_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
