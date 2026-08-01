extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_runtime_opening_descriptor.v1"
const FIELDS: Array[String] = ["schema", "opening_id", "closure_part_id", "status", "target_angle_rad", "collision_enabled", "source_checksum", "checksum"]
const STATUSES: Array[String] = ["SEALED", "CLOSED", "OPEN", "BREACHED", "INACTIVE"]

static func create(opening_id: String, closure_part_id: String, status: String, target_angle_rad: float, collision_enabled: bool, source_checksum: String) -> Dictionary:
	var value := {"schema": SCHEMA, "opening_id": opening_id, "closure_part_id": closure_part_id, "status": status, "target_angle_rad": target_angle_rad, "collision_enabled": collision_enabled, "source_checksum": source_checksum, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_OPENING_DESCRIPTOR_SCHEMA")
	if not _path_id(String(value.get("opening_id", "")), "spatial-opening/"): return _failure("INVALID_CONSTRUCTION_RUNTIME_OPENING_ID")
	var closure := String(value.get("closure_part_id", "")); if not closure.is_empty() and not _path_id(closure, "part/"): return _failure("INVALID_CONSTRUCTION_RUNTIME_OPENING_CLOSURE")
	if typeof(value.get("status")) != TYPE_STRING or not STATUSES.has(String(value["status"])): return _failure("INVALID_CONSTRUCTION_RUNTIME_OPENING_STATUS")
	if typeof(value.get("target_angle_rad")) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(value["target_angle_rad"])) or is_inf(float(value["target_angle_rad"])) or absf(float(value["target_angle_rad"])) > PI: return _failure("INVALID_CONSTRUCTION_RUNTIME_OPENING_ANGLE")
	if typeof(value.get("collision_enabled")) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_RUNTIME_OPENING_COLLISION")
	if String(value["status"]) in ["BREACHED", "INACTIVE"] and bool(value["collision_enabled"]): return _failure("INACTIVE_CONSTRUCTION_RUNTIME_OPENING_COLLIDES")
	if not _hex64(String(value.get("source_checksum", ""))): return _failure("INVALID_CONSTRUCTION_RUNTIME_OPENING_SOURCE_CHECKSUM")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_RUNTIME_OPENING_DESCRIPTOR_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"): return false
	for segment in value.split("/", true):
		if segment.is_empty(): return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_": return false
	return true
static func _hex64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower(): return false
	for character in value:
		if not String(character) in "0123456789abcdef": return false
	return true
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details: result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
