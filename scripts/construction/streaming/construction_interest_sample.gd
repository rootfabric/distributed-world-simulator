extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_interest_sample.v1"
const FIELDS: Array[String] = ["schema", "observer_id", "construct_id", "tick", "distance_m", "visible", "selected", "interacting", "priority_boost", "checksum"]

static func create(observer_id: String, construct_id: String, tick: int, distance_m: float, visible: bool = false, selected: bool = false, interacting: bool = false, priority_boost: int = 0) -> Dictionary:
	var value := {"schema": SCHEMA, "observer_id": observer_id, "construct_id": construct_id, "tick": tick, "distance_m": distance_m, "visible": visible, "selected": selected, "interacting": interacting, "priority_boost": priority_boost, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_INTEREST_SAMPLE_SCHEMA")
	if not String(value.get("observer_id", "")).begins_with("observer/") or not String(value.get("construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_INTEREST_IDENTITY")
	if not Utils.is_json_integer(value.get("tick")) or int(value["tick"]) < 0: return _failure("INVALID_CONSTRUCTION_INTEREST_TICK")
	if typeof(value.get("distance_m")) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(value["distance_m"])) or is_inf(float(value["distance_m"])) or float(value["distance_m"]) < 0.0: return _failure("INVALID_CONSTRUCTION_INTEREST_DISTANCE")
	for field in ["visible", "selected", "interacting"]:
		if typeof(value.get(field)) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_INTEREST_FLAG")
	if not Utils.is_json_integer(value.get("priority_boost")) or int(value["priority_boost"]) < -1000000 or int(value["priority_boost"]) > 1000000: return _failure("INVALID_CONSTRUCTION_INTEREST_PRIORITY")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_INTEREST_SAMPLE_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
