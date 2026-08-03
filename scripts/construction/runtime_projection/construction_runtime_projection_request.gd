extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const MobileProfileScript = preload("res://scripts/construction/mobile/construction_mobile_profile.gd")
const SpatialProfileScript = preload("res://scripts/construction/spatial/construction_spatial_profile.gd")

const SCHEMA := "planet_simulator.construction_runtime_projection_request.v1"
const FIELDS: Array[String] = ["schema", "construct_snapshot", "item_projections", "mobile_profile", "spatial_profile", "world_origin_m", "world_rotation_quaternion", "collision_layer", "collision_mask", "checksum"]

static func create(snapshot: Dictionary, item_projections: Array = [], mobile_profile: Dictionary = {}, spatial_profile: Dictionary = {}, world_origin_m: Array = [0.0, 0.0, 0.0], world_rotation_quaternion: Array = [0.0, 0.0, 0.0, 1.0], collision_layer: int = 1, collision_mask: int = 1) -> Dictionary:
	var value := {"schema": SCHEMA, "construct_snapshot": snapshot.duplicate(true), "item_projections": _sorted(item_projections), "mobile_profile": mobile_profile.duplicate(true), "spatial_profile": spatial_profile.duplicate(true), "world_origin_m": world_origin_m.duplicate(true), "world_rotation_quaternion": world_rotation_quaternion.duplicate(true), "collision_layer": collision_layer, "collision_mask": collision_mask, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_PROJECTION_REQUEST_SCHEMA")
	if typeof(value.get("construct_snapshot")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_RUNTIME_REQUEST_SNAPSHOT")
	var checked := SnapshotScript.validate(value["construct_snapshot"]); if not bool(checked.get("success", false)): return checked
	if typeof(value.get("item_projections")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_RUNTIME_REQUEST_ITEMS")
	var seen := {}; var previous := ""
	for raw in value["item_projections"]:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_RUNTIME_REQUEST_ITEM")
		checked = ProjectionScript.validate(raw); if not bool(checked.get("success", false)): return checked
		var item_id := String(raw["item_instance_id"])
		if seen.has(item_id): return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_REQUEST_ITEM")
		if not previous.is_empty() and item_id < previous: return _failure("CONSTRUCTION_RUNTIME_REQUEST_ITEMS_NOT_SORTED")
		seen[item_id] = true; previous = item_id
	for pair in [["mobile_profile", MobileProfileScript], ["spatial_profile", SpatialProfileScript]]:
		var profile = value.get(String(pair[0]))
		if typeof(profile) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_RUNTIME_REQUEST_PROFILE")
		if not Dictionary(profile).is_empty():
			checked = pair[1].validate(profile); if not bool(checked.get("success", false)): return checked
			if String(profile["construct_id"]) != String(value["construct_snapshot"]["construct_id"]) or String(profile["construct_checksum"]) != String(value["construct_snapshot"]["checksum"]): return _failure("CONSTRUCTION_RUNTIME_PROFILE_SNAPSHOT_MISMATCH")
	if not _finite_vector(value.get("world_origin_m"), 3) or not _finite_vector(value.get("world_rotation_quaternion"), 4): return _failure("INVALID_CONSTRUCTION_RUNTIME_REQUEST_TRANSFORM")
	var q: Array = value["world_rotation_quaternion"]; var norm := sqrt(float(q[0]) ** 2 + float(q[1]) ** 2 + float(q[2]) ** 2 + float(q[3]) ** 2)
	if absf(norm - 1.0) > 0.000001: return _failure("CONSTRUCTION_RUNTIME_REQUEST_ROTATION_NOT_NORMALIZED")
	for field in ["collision_layer", "collision_mask"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0 or int(value[field]) > 4294967295: return _failure("INVALID_CONSTRUCTION_RUNTIME_REQUEST_%s" % field.to_upper())
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_RUNTIME_PROJECTION_REQUEST_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_RUNTIME_PROJECTION_REQUEST_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _sorted(values: Array) -> Array:
	var result := values.duplicate(true); result.sort_custom(func(a, b): return String(a.get("item_instance_id", "")) < String(b.get("item_instance_id", ""))); return result
static func _finite_vector(value, size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or Array(value).size() != size: return false
	for component in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(component)) or is_inf(float(component)): return false
	return true
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details: result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
