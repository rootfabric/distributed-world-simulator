extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.plant_morphology_resource_profile.v1"
const VERSION := "1.0.0"
const DEFAULT_PROFILE_ID := "plant-morphology-resource/ph3-baseline"
const FIELD_NAMES: Array[String] = [
	"schema", "version", "profile_id",
	"reference_height_m", "reference_crown_spread_m", "reference_branch_probability", "reference_total_length_m",
	"height_light_access_gain", "crown_light_capture_gain", "branch_light_capture_gain",
	"structural_cost_scale", "branch_maintenance_cost_scale", "branch_construction_cost_scale", "crown_water_cost_scale",
	"checksum",
]

static func create_default() -> Dictionary:
	return create(DEFAULT_PROFILE_ID, 3.2, 1.8, 0.48, 4.2040149018635, 0.32, 0.34, 0.20, 0.12, 0.09, 0.075, 0.22)

static func create(
	profile_id: String,
	reference_height_m: float,
	reference_crown_spread_m: float,
	reference_branch_probability: float,
	reference_total_length_m: float,
	height_light_access_gain: float,
	crown_light_capture_gain: float,
	branch_light_capture_gain: float,
	structural_cost_scale: float,
	branch_maintenance_cost_scale: float,
	branch_construction_cost_scale: float,
	crown_water_cost_scale: float
) -> Dictionary:
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"profile_id": profile_id,
		"reference_height_m": reference_height_m,
		"reference_crown_spread_m": reference_crown_spread_m,
		"reference_branch_probability": reference_branch_probability,
		"reference_total_length_m": reference_total_length_m,
		"height_light_access_gain": height_light_access_gain,
		"crown_light_capture_gain": crown_light_capture_gain,
		"branch_light_capture_gain": branch_light_capture_gain,
		"structural_cost_scale": structural_cost_scale,
		"branch_maintenance_cost_scale": branch_maintenance_cost_scale,
		"branch_construction_cost_scale": branch_construction_cost_scale,
		"crown_water_cost_scale": crown_water_cost_scale,
	}
	result["checksum"] = compute_checksum(result)
	return result

static func validate(profile: Dictionary) -> Dictionary:
	if profile.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_MORPH_RESOURCE_PROFILE_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not profile.has(field_name):
			return _failure("ECO_MORPH_RESOURCE_PROFILE_MISSING_FIELD", {"field": field_name})
	if String(profile.get("schema", "")) != SCHEMA or String(profile.get("version", "")) != VERSION:
		return _failure("ECO_MORPH_RESOURCE_PROFILE_SCHEMA_VERSION_MISMATCH")
	if String(profile.get("profile_id", "")).is_empty():
		return _failure("ECO_MORPH_RESOURCE_PROFILE_INVALID_ID")
	for field_name in FIELD_NAMES:
		if field_name in ["schema", "version", "profile_id", "checksum"]:
			continue
		var value = profile.get(field_name)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
			return _failure("ECO_MORPH_RESOURCE_PROFILE_INVALID_VALUE", {"field": field_name})
	if String(profile.get("checksum", "")) != compute_checksum(profile):
		return _failure("ECO_MORPH_RESOURCE_PROFILE_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(profile: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, String(profile.get("profile_id", ""))])
	for field_name in FIELD_NAMES:
		if field_name in ["schema", "version", "profile_id", "checksum"]:
			continue
		tokens.append("%.9f" % float(profile.get(field_name, 0.0)))
	return "|".join(tokens).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
