extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.construction_runtime_part_descriptor.v1"
const FIELDS: Array[String] = [
	"schema", "part_id", "item_instance_id", "part_kind", "role",
	"geometry_kind", "dimensions_m", "path_points_m", "local_position_m",
	"local_rotation_quaternion", "mass_kg", "condition", "visible",
	"collision_enabled", "source_checksum", "checksum",
]
const GEOMETRY_KINDS: Array[String] = ["BOX", "CYLINDER", "PATH_BOXES"]
const CONDITIONS: Array[String] = ["INTACT", "DEGRADED", "DESTROYED"]

static func create(
	part_id: String,
	item_instance_id: String,
	part_kind: String,
	role: String,
	geometry_kind: String,
	dimensions_m: Array,
	path_points_m: Array,
	local_position_m: Array,
	local_rotation_quaternion: Array,
	mass_kg: float,
	condition: String,
	visible: bool,
	collision_enabled: bool,
	source_checksum: String
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"part_id": part_id,
		"item_instance_id": item_instance_id,
		"part_kind": part_kind,
		"role": role,
		"geometry_kind": geometry_kind,
		"dimensions_m": dimensions_m.duplicate(true),
		"path_points_m": path_points_m.duplicate(true),
		"local_position_m": local_position_m.duplicate(true),
		"local_rotation_quaternion": local_rotation_quaternion.duplicate(true),
		"mass_kg": mass_kg,
		"condition": condition,
		"visible": visible,
		"collision_enabled": collision_enabled,
		"source_checksum": source_checksum,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_PART_DESCRIPTOR_SCHEMA")
	if not _path_id(String(value.get("part_id", "")), "part/"): return _failure("INVALID_CONSTRUCTION_RUNTIME_PART_ID")
	if not _path_id(String(value.get("item_instance_id", "")), "item/"): return _failure("INVALID_CONSTRUCTION_RUNTIME_PART_ITEM_ID")
	for field in ["part_kind", "role"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).is_empty(): return _failure("INVALID_CONSTRUCTION_RUNTIME_PART_%s" % field.to_upper())
	if typeof(value.get("geometry_kind")) != TYPE_STRING or not GEOMETRY_KINDS.has(String(value["geometry_kind"])): return _failure("INVALID_CONSTRUCTION_RUNTIME_GEOMETRY_KIND")
	if not _positive_vector3(value.get("dimensions_m")): return _failure("INVALID_CONSTRUCTION_RUNTIME_DIMENSIONS")
	if typeof(value.get("path_points_m")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_RUNTIME_PATH_POINTS")
	var path_points: Array = value["path_points_m"]
	if String(value["geometry_kind"]) == "PATH_BOXES":
		if path_points.size() < 2: return _failure("CONSTRUCTION_RUNTIME_PATH_REQUIRES_TWO_POINTS")
		for point in path_points:
			if not _finite_vector(point, 3): return _failure("INVALID_CONSTRUCTION_RUNTIME_PATH_POINT")
	elif not path_points.is_empty(): return _failure("CONSTRUCTION_RUNTIME_NON_PATH_HAS_CONTROL_POINTS")
	if not _finite_vector(value.get("local_position_m"), 3): return _failure("INVALID_CONSTRUCTION_RUNTIME_LOCAL_POSITION")
	if not _finite_vector(value.get("local_rotation_quaternion"), 4): return _failure("INVALID_CONSTRUCTION_RUNTIME_LOCAL_ROTATION")
	var quaternion: Array = value["local_rotation_quaternion"]
	var norm := sqrt(float(quaternion[0]) ** 2 + float(quaternion[1]) ** 2 + float(quaternion[2]) ** 2 + float(quaternion[3]) ** 2)
	if absf(norm - 1.0) > 0.000001: return _failure("CONSTRUCTION_RUNTIME_ROTATION_NOT_NORMALIZED")
	if typeof(value.get("mass_kg")) not in [TYPE_INT, TYPE_FLOAT] or float(value["mass_kg"]) <= 0.0 or is_nan(float(value["mass_kg"])) or is_inf(float(value["mass_kg"])): return _failure("INVALID_CONSTRUCTION_RUNTIME_PART_MASS")
	if typeof(value.get("condition")) != TYPE_STRING or not CONDITIONS.has(String(value["condition"])): return _failure("INVALID_CONSTRUCTION_RUNTIME_PART_CONDITION")
	for field in ["visible", "collision_enabled"]:
		if typeof(value.get(field)) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_RUNTIME_%s" % field.to_upper())
	if String(value["condition"]) == "DESTROYED" and (bool(value["visible"]) or bool(value["collision_enabled"])): return _failure("DESTROYED_CONSTRUCTION_RUNTIME_PART_ACTIVE")
	if not bool(value["visible"]) and bool(value["collision_enabled"]): return _failure("HIDDEN_CONSTRUCTION_RUNTIME_PART_COLLIDES")
	if not _hex64(String(value.get("source_checksum", ""))): return _failure("INVALID_CONSTRUCTION_RUNTIME_PART_SOURCE_CHECKSUM")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_RUNTIME_PART_DESCRIPTOR_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_RUNTIME_PART_DESCRIPTOR_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)

static func _positive_vector3(value) -> bool:
	if not _finite_vector(value, 3): return false
	for component in value:
		if float(component) <= 0.0: return false
	return true

static func _finite_vector(value, size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or Array(value).size() != size: return false
	for component in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(component)) or is_inf(float(component)): return false
	return true

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
