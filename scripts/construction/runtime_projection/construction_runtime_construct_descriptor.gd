extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const PartDescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_part_descriptor.gd")
const OpeningDescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_opening_descriptor.gd")

const SCHEMA := "planet_simulator.construction_runtime_construct_descriptor.v1"
const FIELDS: Array[String] = ["schema", "construct_id", "construct_checksum", "construct_revision", "build_state", "body_kind", "frozen", "world_origin_m", "world_rotation_quaternion", "collision_layer", "collision_mask", "total_mass_kg", "mobility_state", "part_descriptors", "opening_descriptors", "diagnostics", "checksum"]
const BODY_KINDS: Array[String] = ["STATIC", "RIGID"]
const MOBILITY_STATES: Array[String] = ["", "MOBILE", "DEGRADED", "IMMOBILE"]

static func create(snapshot: Dictionary, body_kind: String, frozen: bool, world_origin_m: Array, world_rotation_quaternion: Array, collision_layer: int, collision_mask: int, total_mass_kg: float, mobility_state: String, parts: Array, openings: Array, diagnostics: Dictionary = {}) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"construct_id": String(snapshot.get("construct_id", "")),
		"construct_checksum": String(snapshot.get("checksum", "")),
		"construct_revision": int(snapshot.get("state_revision", 0)),
		"build_state": String(snapshot.get("build_state", "")),
		"body_kind": body_kind,
		"frozen": frozen,
		"world_origin_m": world_origin_m.duplicate(true),
		"world_rotation_quaternion": world_rotation_quaternion.duplicate(true),
		"collision_layer": collision_layer,
		"collision_mask": collision_mask,
		"total_mass_kg": total_mass_kg,
		"mobility_state": mobility_state,
		"part_descriptors": _sorted(parts, "part_id"),
		"opening_descriptors": _sorted(openings, "opening_id"),
		"diagnostics": diagnostics.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_CONSTRUCT_DESCRIPTOR_SCHEMA")
	if not _path_id(String(value.get("construct_id", "")), "construct/"): return _failure("INVALID_CONSTRUCTION_RUNTIME_CONSTRUCT_ID")
	if not _hex64(String(value.get("construct_checksum", ""))): return _failure("INVALID_CONSTRUCTION_RUNTIME_CONSTRUCT_CHECKSUM")
	if not UtilsScript.is_json_integer(value.get("construct_revision")) or int(value["construct_revision"]) < 0: return _failure("INVALID_CONSTRUCTION_RUNTIME_CONSTRUCT_REVISION")
	if typeof(value.get("build_state")) != TYPE_STRING or not SnapshotScript.VALID_BUILD_STATES.has(String(value["build_state"])): return _failure("INVALID_CONSTRUCTION_RUNTIME_BUILD_STATE")
	if typeof(value.get("body_kind")) != TYPE_STRING or not BODY_KINDS.has(String(value["body_kind"])): return _failure("INVALID_CONSTRUCTION_RUNTIME_BODY_KIND")
	if typeof(value.get("frozen")) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_RUNTIME_FROZEN")
	if String(value["body_kind"]) == "STATIC" and not bool(value["frozen"]): return _failure("STATIC_CONSTRUCTION_RUNTIME_BODY_NOT_FROZEN")
	if not _finite_vector(value.get("world_origin_m"), 3) or not _finite_vector(value.get("world_rotation_quaternion"), 4): return _failure("INVALID_CONSTRUCTION_RUNTIME_WORLD_TRANSFORM")
	var q: Array = value["world_rotation_quaternion"]; var norm := sqrt(float(q[0]) ** 2 + float(q[1]) ** 2 + float(q[2]) ** 2 + float(q[3]) ** 2)
	if absf(norm - 1.0) > 0.000001: return _failure("CONSTRUCTION_RUNTIME_WORLD_ROTATION_NOT_NORMALIZED")
	for field in ["collision_layer", "collision_mask"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0 or int(value[field]) > 4294967295: return _failure("INVALID_CONSTRUCTION_RUNTIME_%s" % field.to_upper())
	if typeof(value.get("total_mass_kg")) not in [TYPE_INT, TYPE_FLOAT] or float(value["total_mass_kg"]) <= 0.0: return _failure("INVALID_CONSTRUCTION_RUNTIME_TOTAL_MASS")
	if typeof(value.get("mobility_state")) != TYPE_STRING or not MOBILITY_STATES.has(String(value["mobility_state"])): return _failure("INVALID_CONSTRUCTION_RUNTIME_MOBILITY_STATE")
	if String(value["body_kind"]) == "STATIC" and not String(value["mobility_state"]).is_empty(): return _failure("STATIC_CONSTRUCTION_RUNTIME_HAS_MOBILITY_STATE")
	if String(value["body_kind"]) == "RIGID" and String(value["mobility_state"]).is_empty(): return _failure("RIGID_CONSTRUCTION_RUNTIME_MISSING_MOBILITY_STATE")
	var part_ids := {}; var item_ids := {}; var previous := ""; var mass_sum := 0.0
	if typeof(value.get("part_descriptors")) != TYPE_ARRAY or Array(value["part_descriptors"]).is_empty(): return _failure("CONSTRUCTION_RUNTIME_PART_DESCRIPTORS_REQUIRED")
	for raw in value["part_descriptors"]:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_RUNTIME_PART_DESCRIPTOR")
		var checked := PartDescriptorScript.validate(raw); if not bool(checked.get("success", false)): return checked
		var part_id := String(raw["part_id"]); var item_id := String(raw["item_instance_id"])
		if part_ids.has(part_id): return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_PART_ID")
		if item_ids.has(item_id): return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_ITEM_ID")
		if not previous.is_empty() and part_id < previous: return _failure("CONSTRUCTION_RUNTIME_PARTS_NOT_SORTED")
		part_ids[part_id] = true; item_ids[item_id] = true; previous = part_id
		if String(raw["condition"]) != "DESTROYED": mass_sum += float(raw["mass_kg"])
	if absf(mass_sum - float(value["total_mass_kg"])) > 0.000001: return _failure("CONSTRUCTION_RUNTIME_TOTAL_MASS_MISMATCH")
	var opening_ids := {}; previous = ""
	if typeof(value.get("opening_descriptors")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_RUNTIME_OPENING_DESCRIPTORS")
	for raw in value["opening_descriptors"]:
		if typeof(raw) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_RUNTIME_OPENING_DESCRIPTOR")
		var checked := OpeningDescriptorScript.validate(raw); if not bool(checked.get("success", false)): return checked
		var opening_id := String(raw["opening_id"])
		if opening_ids.has(opening_id): return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_OPENING_ID")
		if not previous.is_empty() and opening_id < previous: return _failure("CONSTRUCTION_RUNTIME_OPENINGS_NOT_SORTED")
		var closure := String(raw["closure_part_id"]); if not closure.is_empty() and not part_ids.has(closure): return _failure("CONSTRUCTION_RUNTIME_OPENING_CLOSURE_PART_MISSING")
		opening_ids[opening_id] = true; previous = opening_id
	if typeof(value.get("diagnostics")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["diagnostics"]).get("success", false)): return _failure("INVALID_CONSTRUCTION_RUNTIME_DIAGNOSTICS")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_RUNTIME_CONSTRUCT_DESCRIPTOR_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)): return _failure("CONSTRUCTION_RUNTIME_CONSTRUCT_DESCRIPTOR_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _sorted(records: Array, id_field: String) -> Array:
	var result := records.duplicate(true); result.sort_custom(func(a, b): return String(a.get(id_field, "")) < String(b.get(id_field, ""))); return result
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
