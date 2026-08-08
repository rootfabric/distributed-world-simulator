extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")

const SCHEMA: String = "planet_simulator.geo_generation_context.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"query_scope_id",
	"target_resolution_m",
	"max_geometric_error_m",
	"feature_budget",
	"volume_budget",
	"detail_budget",
	"collision_required",
	"interior_required",
	"generator_manifest_version",
	"checksum",
]


static func create(
	body_id: String,
	query_scope_id: String,
	target_resolution_m: float,
	max_geometric_error_m: float,
	feature_budget: float,
	volume_budget: float,
	detail_budget: float,
	collision_required: bool,
	interior_required: bool,
	generator_manifest_version: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": body_id,
		"query_scope_id": query_scope_id,
		"target_resolution_m": target_resolution_m,
		"max_geometric_error_m": max_geometric_error_m,
		"feature_budget": feature_budget,
		"volume_budget": volume_budget,
		"detail_budget": detail_budget,
		"collision_required": collision_required,
		"interior_required": interior_required,
		"generator_manifest_version": generator_manifest_version,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_GEO_GENERATION_CONTEXT_SCHEMA")
	for field in ["body_id", "query_scope_id"]:
		if not GeoUtilsScript.is_canonical_id(value.get(field), 2):
			return GeoUtilsScript.failure("INVALID_GEO_GENERATION_CONTEXT_ID", {"field": field})
	if not GeoUtilsScript.is_positive_number(value.get("target_resolution_m")):
		return GeoUtilsScript.failure("INVALID_TARGET_RESOLUTION")
	if not GeoUtilsScript.is_non_negative_number(value.get("max_geometric_error_m")):
		return GeoUtilsScript.failure("INVALID_MAX_GEOMETRIC_ERROR")
	for field in ["feature_budget", "volume_budget", "detail_budget"]:
		if not GeoUtilsScript.is_ratio(value.get(field)):
			return GeoUtilsScript.failure("INVALID_GEO_GENERATION_BUDGET", {"field": field})
	for field in ["collision_required", "interior_required"]:
		if typeof(value.get(field)) != TYPE_BOOL:
			return GeoUtilsScript.failure("INVALID_GEO_GENERATION_FLAG", {"field": field})
	if not GeoUtilsScript.is_semantic_version(value.get("generator_manifest_version")):
		return GeoUtilsScript.failure("INVALID_GENERATOR_MANIFEST_VERSION")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.geo_generation_context")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)
