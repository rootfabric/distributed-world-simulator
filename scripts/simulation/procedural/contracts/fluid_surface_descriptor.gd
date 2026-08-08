extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureIdScript = preload("res://scripts/simulation/procedural/contracts/feature_id.gd")
const FeatureBoundsScript = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FluidRegionIdScript = preload("res://scripts/simulation/procedural/contracts/fluid_region_id.gd")
const FluidTypeScript = preload("res://scripts/simulation/procedural/contracts/fluid_type.gd")

const SCHEMA: String = "planet_simulator.fluid_surface_descriptor.v1"
const SURFACE_MODE_PREFIX: String = "fluid-surface-mode/"
const CONSTANT_LEVEL: String = "fluid-surface-mode/constant-level"
const PROFILED: String = "fluid-surface-mode/profiled"
const FIELDS: Array[String] = [
	"schema",
	"fluid_region_id",
	"body_id",
	"fluid_type_id",
	"frame_id",
	"source_feature_id",
	"bounds",
	"surface_mode",
	"reference_level_m",
	"attributes",
	"checksum",
]


static func create(
	fluid_region_id: String,
	body_id: String,
	fluid_type_id: String,
	frame_id: String,
	source_feature_id: String,
	bounds: Dictionary,
	surface_mode: String,
	reference_level_m: float,
	attributes: Dictionary = {}
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"fluid_region_id": fluid_region_id,
		"body_id": body_id,
		"fluid_type_id": fluid_type_id,
		"frame_id": frame_id,
		"source_feature_id": source_feature_id,
		"bounds": bounds.duplicate(true),
		"surface_mode": surface_mode,
		"reference_level_m": reference_level_m,
		"attributes": attributes.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_FLUID_SURFACE_DESCRIPTOR_SCHEMA")
	var region_validation: Dictionary = FluidRegionIdScript.validate(value.get("fluid_region_id"))
	if not bool(region_validation.get("success", false)):
		return region_validation
	if not GeoUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_BODY_ID")
	var type_validation: Dictionary = FluidTypeScript.validate(value.get("fluid_type_id"))
	if not bool(type_validation.get("success", false)):
		return type_validation
	if not GeoUtilsScript.is_canonical_id(value.get("frame_id"), 2):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_FRAME_ID")
	if typeof(value.get("source_feature_id")) != TYPE_STRING:
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_SOURCE_FEATURE")
	var source_feature_id: String = String(value["source_feature_id"])
	if not source_feature_id.is_empty() and not bool(FeatureIdScript.validate(source_feature_id).get("success", false)):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_SOURCE_FEATURE")
	var bounds_value = value.get("bounds")
	if typeof(bounds_value) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_BOUNDS")
	var bounds_validation: Dictionary = FeatureBoundsScript.validate(bounds_value)
	if not bool(bounds_validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_BOUNDS", {"cause": bounds_validation.get("error_code", "")})
	if String(bounds_value["frame_id"]) != String(value["frame_id"]):
		return GeoUtilsScript.failure("FLUID_SURFACE_BOUNDS_FRAME_MISMATCH")
	if typeof(value.get("surface_mode")) != TYPE_STRING:
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_MODE")
	var surface_mode: String = String(value["surface_mode"])
	if not GeoUtilsScript.is_canonical_id(surface_mode, 2) or not surface_mode.begins_with(SURFACE_MODE_PREFIX):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_MODE")
	if not GeoUtilsScript.is_finite_number(value.get("reference_level_m")):
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_REFERENCE_LEVEL")
	if typeof(value.get("attributes")) != TYPE_DICTIONARY:
		return GeoUtilsScript.failure("INVALID_FLUID_SURFACE_ATTRIBUTES")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.fluid_surface_descriptor")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)
