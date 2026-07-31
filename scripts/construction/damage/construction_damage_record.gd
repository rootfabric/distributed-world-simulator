extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RepairPlanScript = preload("res://scripts/construction/damage/construction_repair_plan.gd")

const SCHEMA := "planet_simulator.construction_damage_record.v1"
const FIELDS: Array[String] = [
	"schema", "damage_id", "status", "request_checksum", "damage_plan_checksum", "repair_plan",
	"component_checksums", "applied_generation", "repaired_generation", "checksum",
]
const STATUSES: Array[String] = ["APPLIED", "REPAIRED"]

static func create(damage_id: String, request_checksum: String, damage_plan_checksum: String, repair_plan: Dictionary, component_checksums: Array, applied_generation: int) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"damage_id": damage_id,
		"status": "APPLIED",
		"request_checksum": request_checksum,
		"damage_plan_checksum": damage_plan_checksum,
		"repair_plan": repair_plan.duplicate(true),
		"component_checksums": _sorted(component_checksums),
		"applied_generation": applied_generation,
		"repaired_generation": -1,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func mark_repaired(value: Dictionary, generation: int) -> Dictionary:
	var next := value.duplicate(true)
	next["status"] = "REPAIRED"
	next["repaired_generation"] = generation
	next["checksum"] = compute_checksum(next)
	return next

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_DAMAGE_RECORD_SCHEMA")
	if not String(value.get("damage_id", "")).begins_with("damage/"): return _failure("INVALID_CONSTRUCTION_DAMAGE_RECORD_ID")
	if not STATUSES.has(String(value.get("status", ""))): return _failure("INVALID_CONSTRUCTION_DAMAGE_RECORD_STATUS")
	for field in ["request_checksum", "damage_plan_checksum"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).length() != 64: return _failure("INVALID_CONSTRUCTION_DAMAGE_RECORD_CHECKSUM")
	if typeof(value.get("repair_plan")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_DAMAGE_RECORD_REPAIR_PLAN")
	var repair_validation := RepairPlanScript.validate(value["repair_plan"])
	if not bool(repair_validation.get("success", false)): return repair_validation
	if typeof(value.get("component_checksums")) != TYPE_ARRAY or value["component_checksums"] != _sorted(value["component_checksums"]): return _failure("NON_CANONICAL_CONSTRUCTION_DAMAGE_RECORD_COMPONENTS")
	var seen := {}
	for checksum in value["component_checksums"]:
		if typeof(checksum) != TYPE_STRING or String(checksum).length() != 64 or seen.has(checksum): return _failure("INVALID_CONSTRUCTION_DAMAGE_RECORD_COMPONENT")
		seen[checksum] = true
	if not UtilsScript.is_json_integer(value.get("applied_generation")) or int(value["applied_generation"]) < 0: return _failure("INVALID_CONSTRUCTION_DAMAGE_APPLIED_GENERATION")
	if not UtilsScript.is_json_integer(value.get("repaired_generation")) or int(value["repaired_generation"]) < -1: return _failure("INVALID_CONSTRUCTION_DAMAGE_REPAIRED_GENERATION")
	if String(value["status"]) == "APPLIED" and int(value["repaired_generation"]) != -1: return _failure("APPLIED_CONSTRUCTION_DAMAGE_HAS_REPAIR_GENERATION")
	if String(value["status"]) == "REPAIRED" and int(value["repaired_generation"]) < int(value["applied_generation"]): return _failure("INVALID_CONSTRUCTION_DAMAGE_REPAIR_GENERATION_ORDER")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value): return _failure("CONSTRUCTION_DAMAGE_RECORD_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

static func _sorted(values: Array) -> Array:
	var output := values.duplicate()
	output.sort()
	return output

static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
