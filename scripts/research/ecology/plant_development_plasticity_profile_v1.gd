extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.plant_development_plasticity_profile.v1"
const VERSION := "1.0.0"
const DEFAULT_PROFILE_ID := "plant-plasticity/ph2-baseline"
const TRAIT_NAMES: Array[String] = [
	"shade_elongation_strength",
	"shade_branch_suppression",
	"light_branching_strength",
	"drought_size_suppression",
	"nutrient_growth_strength",
	"flood_growth_suppression",
]
const FIELD_NAMES: Array[String] = [
	"schema", "version", "profile_id",
	"shade_elongation_strength", "shade_branch_suppression", "light_branching_strength",
	"drought_size_suppression", "nutrient_growth_strength", "flood_growth_suppression",
	"checksum",
]

static func create_default() -> Dictionary:
	return create(DEFAULT_PROFILE_ID, 0.45, 0.55, 0.40, 0.55, 0.25, 0.45)

static func create(
	profile_id: String,
	shade_elongation_strength: float,
	shade_branch_suppression: float,
	light_branching_strength: float,
	drought_size_suppression: float,
	nutrient_growth_strength: float,
	flood_growth_suppression: float
) -> Dictionary:
	var profile := {
		"schema": SCHEMA,
		"version": VERSION,
		"profile_id": profile_id,
		"shade_elongation_strength": shade_elongation_strength,
		"shade_branch_suppression": shade_branch_suppression,
		"light_branching_strength": light_branching_strength,
		"drought_size_suppression": drought_size_suppression,
		"nutrient_growth_strength": nutrient_growth_strength,
		"flood_growth_suppression": flood_growth_suppression,
	}
	profile["checksum"] = compute_checksum(profile)
	return profile

static func validate(profile: Dictionary) -> Dictionary:
	if profile.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_PLASTICITY_PROFILE_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not profile.has(field_name):
			return _failure("ECO_PLASTICITY_PROFILE_MISSING_FIELD", {"field": field_name})
	for field_name in profile.keys():
		if not String(field_name) in FIELD_NAMES:
			return _failure("ECO_PLASTICITY_PROFILE_UNEXPECTED_FIELD", {"field": String(field_name)})
	if String(profile.get("schema", "")) != SCHEMA or String(profile.get("version", "")) != VERSION:
		return _failure("ECO_PLASTICITY_PROFILE_SCHEMA_VERSION_MISMATCH")
	var profile_id := String(profile.get("profile_id", ""))
	if profile_id.is_empty() or profile_id != profile_id.strip_edges():
		return _failure("ECO_PLASTICITY_PROFILE_INVALID_ID")
	for name in TRAIT_NAMES:
		var value = profile.get(name)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1.0:
			return _failure("ECO_PLASTICITY_PROFILE_OUT_OF_RANGE", {"field": name})
	if String(profile.get("checksum", "")) != compute_checksum(profile):
		return _failure("ECO_PLASTICITY_PROFILE_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(profile: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, String(profile.get("profile_id", ""))])
	for name in TRAIT_NAMES:
		tokens.append("%.9f" % float(profile.get(name, 0.0)))
	return "|".join(tokens).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
